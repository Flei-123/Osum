/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_FIRMWARE_H
#define LKPI_LINUX_FIRMWARE_H
#include <linux/device.h>
struct module;
struct firmware { size_t size; const u8 *data; void *priv; };
#define FW_ACTION_NOUEVENT 0
#define FW_ACTION_UEVENT 1
int request_firmware(const struct firmware **fw, const char *name, struct device *dev);
int firmware_request_nowarn(const struct firmware **fw, const char *name, struct device *dev);
int request_firmware_nowait(struct module *module, bool uevent, const char *name, struct device *dev, gfp_t gfp, void *context,
			    void (*cont)(const struct firmware *fw, void *context));
void release_firmware(const struct firmware *fw);
#endif
