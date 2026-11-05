#include "lkpi.h"

struct drm_managed_entry {
	struct drm_managed_entry *next;
	size_t size;
};

struct drm_device *drm_dev_alloc(const struct drm_driver *driver, struct device *parent)
{
	struct drm_device *dev = kzalloc(sizeof(*dev), GFP_KERNEL);

	if (!dev)
		return ERR_PTR(-ENOMEM);
	dev->driver = driver;
	dev->dev = parent;
	dev->refcount = 1;
	return dev;
}

int drm_dev_register(struct drm_device *dev, unsigned long flags)
{
	(void)flags;
	if (dev->registered)
		return -EINVAL;
	dev->registered = true;
	return 0;
}

void drm_dev_unplug(struct drm_device *dev)
{
	dev->unplugged = true;
}

bool drm_dev_enter(struct drm_device *dev, int *idx)
{
	*idx = 0;
	return !dev->unplugged;
}

void drm_dev_exit(int idx)
{
	(void)idx;
}

void *drmm_kzalloc(struct drm_device *dev, size_t size, gfp_t flags)
{
	struct drm_managed_entry *entry = kzalloc(sizeof(*entry) + size, flags);

	if (!entry)
		return NULL;
	entry->size = size;
	entry->next = dev->managed;
	dev->managed = entry;
	return entry + 1;
}

int drmm_mode_config_init(struct drm_device *dev)
{
	memset(&dev->mode_config, 0, sizeof(dev->mode_config));
	return 0;
}

int drm_aperture_remove_conflicting_pci_framebuffers(struct pci_dev *pdev,
						     const struct drm_driver *driver)
{
	(void)pdev;
	(void)driver;
	return 0;
}

void drm_dev_put(struct drm_device *dev)
{
	struct drm_managed_entry *entry;

	if (!dev || --dev->refcount > 0)
		return;
	lkpi_fbdev_release(dev);
	lkpi_kms_release(dev);
	lkpi_vram_release(dev);
	entry = dev->managed;
	while (entry) {
		struct drm_managed_entry *next = entry->next;

		kfree(entry);
		entry = next;
	}
	kfree(dev);
}
