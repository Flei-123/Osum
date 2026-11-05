#ifndef LKPI_INTERNAL_H
#define LKPI_INTERNAL_H

#include <linux/kernel.h>
#include <linux/pci.h>
#include <drm/drm_core.h>
#include <osum/osum_if.h>

void lkpi_heap_release(void);
size_t lkpi_heap_used(void);

int lkpi_pci_attach(u64 state);
int lkpi_pci_probe_status(void);

void *lkpi_vram_map(void);
int lkpi_vram_create_object(struct drm_device *dev, size_t size,
			    struct drm_gem_vram_object **out, u32 *handle);
void lkpi_vram_destroy_object(struct drm_gem_vram_object *gbo);
void lkpi_vram_release(struct drm_device *dev);
void lkpi_kms_release(struct drm_device *dev);
void lkpi_fbdev_release(struct drm_device *dev);

#endif
