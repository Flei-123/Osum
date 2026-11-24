#include "wifi.h"
#include <linux/firmware.h>
#include <linux/dmi.h>
#include <linux/kobject.h>
#include <linux/devcoredump.h>
#include <osum/osum_if.h>
#define LKPI_FRAME_BYTES 4096

#define LKPI_FW_REGISTRY_MAX 8
#define LKPI_FORMAT_MAX 256

struct devres {
	struct devres *next;
	struct device *dev;
	void (*release)(void *payload);
} __attribute__((aligned(16)));

struct fw_entry {
	const char *name;
	const void *data;
	size_t size;
	unsigned long long frames;
};

struct fw_request {
	struct work_struct work;
	const char *name;
	struct device *dev;
	void *context;
	void (*cont)(const struct firmware *fw, void *context);
};

static struct devres *devres_head;
static struct fw_entry fw_registry[LKPI_FW_REGISTRY_MAX];
static unsigned int fw_count;

const char *dev_name(const struct device *dev)
{
	if (dev->init_name)
		return dev->init_name;
	return dev->kobj.name ? dev->kobj.name : "";
}

void *dev_get_drvdata(const struct device *dev)
{
	return dev->driver_data;
}

void dev_set_drvdata(struct device *dev, void *data)
{
	dev->driver_data = data;
}

struct device *get_device(struct device *dev)
{
	return dev;
}

void put_device(struct device *dev)
{
	(void)dev;
}

void device_release_driver(struct device *dev)
{
	(void)dev;
}

int device_reprobe(struct device *dev)
{
	(void)dev;
	return 0;
}

void *lkpi_devres_alloc(struct device *dev, size_t size, void (*release)(void *payload))
{
	struct devres *res = kzalloc(sizeof(*res) + size, GFP_KERNEL);

	if (!res)
		return NULL;
	res->dev = dev;
	res->release = release;
	res->next = devres_head;
	devres_head = res;
	return res + 1;
}

void lkpi_devres_release(struct device *dev)
{
	struct devres **link = &devres_head;
	struct devres *res;

	while ((res = *link)) {
		if (dev && res->dev != dev) {
			link = &res->next;
			continue;
		}
		*link = res->next;
		if (res->release)
			res->release(res + 1);
		kfree(res);
	}
}

void *devm_kzalloc(struct device *dev, size_t size, gfp_t gfp)
{
	(void)gfp;
	return lkpi_devres_alloc(dev, size, NULL);
}

char *devm_kasprintf(struct device *dev, gfp_t gfp, const char *fmt, ...)
{
	char text[LKPI_FORMAT_MAX];
	va_list args;
	char *copy;
	int len;

	va_start(args, fmt);
	len = vsnprintf(text, sizeof(text), fmt, args);
	va_end(args);
	if (len < 0 || (size_t)len >= sizeof(text))
		return NULL;
	copy = devm_kzalloc(dev, len + 1, gfp);
	if (copy)
		memcpy(copy, text, len + 1);
	return copy;
}

int lkpi_firmware_register(const char *name, const void *data, size_t size)
{
	if (fw_count >= LKPI_FW_REGISTRY_MAX)
		return -ENOSPC;
	fw_registry[fw_count].name = name;
	fw_registry[fw_count].data = data;
	fw_registry[fw_count].size = size;
	fw_registry[fw_count].frames = 0;
	fw_count++;
	return 0;
}

int lkpi_firmware_load(const char *name, const unsigned char *hash, size_t cap)
{
	unsigned long long frames = (cap + LKPI_FRAME_BYTES - 1) / LKPI_FRAME_BYTES;
	unsigned long long base = k_frames(frames);
	unsigned long long size;
	int rc;

	if (!base)
		return -ENOMEM;
	size = k_fwreq(name, hash, base, frames * LKPI_FRAME_BYTES);
	if (!size) {
		k_frames_free(base, frames);
		return -ENOENT;
	}
	rc = lkpi_firmware_register(name, (const void *)base, size);
	if (rc) {
		k_frames_free(base, frames);
		return rc;
	}
	fw_registry[fw_count - 1].frames = frames;
	return 0;
}

void lkpi_firmware_clear(void)
{
	unsigned int i;

	for (i = 0; i < fw_count; i++)
		if (fw_registry[i].frames)
			k_frames_free((unsigned long long)fw_registry[i].data, fw_registry[i].frames);
	fw_count = 0;
}

int firmware_request_nowarn(const struct firmware **fw, const char *name, struct device *dev)
{
	struct firmware *found;
	unsigned int i;

	(void)dev;
	*fw = NULL;
	for (i = 0; i < fw_count; i++) {
		if (strcmp(fw_registry[i].name, name))
			continue;
		found = kzalloc(sizeof(*found), GFP_KERNEL);
		if (!found)
			return -ENOMEM;
		found->data = fw_registry[i].data;
		found->size = fw_registry[i].size;
		*fw = found;
		return 0;
	}
	return -ENOENT;
}

int request_firmware(const struct firmware **fw, const char *name, struct device *dev)
{
	int rc = firmware_request_nowarn(fw, name, dev);

	if (rc)
		_printk("lkpi: firmware %s not available (%d)\n", name, rc);
	return rc;
}

void release_firmware(const struct firmware *fw)
{
	kfree(fw);
}

static void fw_request_run(struct work_struct *work)
{
	struct fw_request *req = container_of(work, struct fw_request, work);
	const struct firmware *fw = NULL;

	request_firmware(&fw, req->name, req->dev);
	req->cont(fw, req->context);
	kfree(req);
}

int request_firmware_nowait(struct module *module, bool uevent, const char *name, struct device *dev, gfp_t gfp,
			    void *context, void (*cont)(const struct firmware *fw, void *context))
{
	struct fw_request *req = kzalloc(sizeof(*req), gfp);

	(void)module;
	(void)uevent;
	if (!req)
		return -ENOMEM;
	INIT_WORK(&req->work, fw_request_run);
	req->name = name;
	req->dev = dev;
	req->context = context;
	req->cont = cont;
	schedule_work(&req->work);
	return 0;
}

int kobject_uevent_env(struct kobject *kobj, enum kobject_action action, char *envp[])
{
	(void)kobj;
	(void)action;
	(void)envp;
	return 0;
}

const char *dmi_get_system_info(int field)
{
	(void)field;
	return NULL;
}

int dmi_check_system(const struct dmi_system_id *list)
{
	(void)list;
	return 0;
}

#define DEV_PRINTK_LINE 256

void dev_printk(const char *level, const struct device *dev, const char *fmt, ...)
{
	char line[DEV_PRINTK_LINE];
	va_list args;

	(void)level;
	(void)dev;
	va_start(args, fmt);
	vsnprintf(line, sizeof(line), fmt, args);
	va_end(args);
	_printk("lkpi: %s", line);
}
