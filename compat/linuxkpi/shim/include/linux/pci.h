#ifndef LKPI_LINUX_PCI_H
#define LKPI_LINUX_PCI_H

#include <linux/kernel.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/device.h>
#include <linux/dma-mapping.h>
#include <linux/mod_devicetable.h>

#define PCI_SUBVENDOR_ID_REDHAT_QUMRANET 0x1af4
#define PCI_SUBDEVICE_ID_QEMU 0x1100
#define PCI_NUM_RESOURCES 6
#define PCI_EXP_LNKCTL 16
#define PCI_EXP_LNKCTL_ASPM_L0S 0x0001
#define PCI_EXP_LNKCTL_ASPM_L1 0x0002
#define PCI_EXP_LNKCTL_ASPMC 0x0003
#define PCI_EXP_LNKSTA 18
#define PCI_EXP_LNKSTA_CLS 0x000f
#define PCI_EXP_LNKSTA_CLS_2_5GB 0x0001
#define PCI_EXP_LNKSTA_CLS_5_0GB 0x0002
#define PCI_EXP_LNKSTA_CLS_8_0GB 0x0003
#define PCI_EXP_DEVCTL2 40
#define PCI_EXP_DEVCTL2_LTR_EN 0x0400
#define PCI_VENDOR_ID_INTEL 0x8086
#define PCI_ERR_ROOT_COMMAND 0x2c
#define PCI_ERR_ROOT_STATUS 0x30
#define PCI_ERR_ROOT_ERR_SRC 0x34
#define PCI_EXT_CAP_ID_ERR 0x01
#define PCI_COMMAND 4
#define PCI_COMMAND_INTX_DISABLE 0x400
#define PCI_STATUS 6
#define PCI_STATUS_INTERRUPT 0x08
struct msix_entry { u32 vector; u16 entry; };

struct pci_bus { unsigned char number; struct pci_dev *self; };
struct pci_dev {
	struct device dev;
	struct pci_bus *bus;
	u16 vendor;
	u16 device;
	u16 subsystem_vendor;
	u16 subsystem_device;
	u32 class;
	u8 revision;
	u8 irq;
	u32 devfn;
	u32 requested;
	struct resource resource[PCI_NUM_RESOURCES];
};

struct pci_driver {
	const char *name;
	const struct pci_device_id *id_table;
	int (*probe)(struct pci_dev *dev, const struct pci_device_id *id);
	void (*remove)(struct pci_dev *dev);
	void (*shutdown)(struct pci_dev *dev);
	struct device_driver driver;
};

#define to_pci_dev(d) container_of(d, struct pci_dev, dev)
#define pci_resource_start(dev, bar) ((dev)->resource[(bar)].start)
#define pci_resource_flags(dev, bar) ((dev)->resource[(bar)].flags)
#define pci_resource_len(dev, bar) \
	((dev)->resource[(bar)].flags ? \
	 (dev)->resource[(bar)].end - (dev)->resource[(bar)].start + 1 : 0)
#define pci_register_driver(driver) __pci_register_driver((driver), THIS_MODULE, #driver)

int __pci_register_driver(struct pci_driver *driver, struct module *owner, const char *name);
void pci_unregister_driver(struct pci_driver *driver);
int pcim_enable_device(struct pci_dev *dev);
int pci_request_region(struct pci_dev *dev, int bar, const char *name);
void pci_release_regions(struct pci_dev *dev);

static inline void pci_set_drvdata(struct pci_dev *dev, void *data)
{
	dev->dev.driver_data = data;
}

static inline void *pci_get_drvdata(struct pci_dev *dev)
{
	return dev->dev.driver_data;
}

#endif
