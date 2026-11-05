#ifndef LKPI_DRM_MODULE_H
#define LKPI_DRM_MODULE_H

#include <drm/drm_core.h>

#define drm_module_pci_driver_if_modeset(pci_drv, modeset) \
	static int __init pci_drv##_init(void) \
	{ \
		if (drm_firmware_drivers_only() && (modeset) == -1) \
			return -ENODEV; \
		if ((modeset) == 0) \
			return -ENODEV; \
		return pci_register_driver(&(pci_drv)); \
	} \
	module_init(pci_drv##_init); \
	static void __exit pci_drv##_exit(void) \
	{ \
		pci_unregister_driver(&(pci_drv)); \
	} \
	module_exit(pci_drv##_exit)

#endif
