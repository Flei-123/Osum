#ifndef LKPI_LINUX_PCI_H
#define LKPI_LINUX_PCI_H

#include <linux/kernel.h>
#include <linux/io.h>
#include <linux/module.h>

#define PCI_ANY_ID (~0U)
#define PCI_SUBVENDOR_ID_REDHAT_QUMRANET 0x1af4
#define PCI_SUBDEVICE_ID_QEMU 0x1100
#define PCI_NUM_RESOURCES 6

struct dev_pm_ops {
};

#define SET_SYSTEM_SLEEP_PM_OPS(suspend_fn, resume_fn)

struct device_driver {
	const char *name;
	const struct dev_pm_ops *pm;
};

struct device {
	void *driver_data;
	struct device *parent;
};

struct pci_device_id {
	u32 vendor;
	u32 device;
	u32 subvendor;
	u32 subdevice;
	u32 class;
	u32 class_mask;
	unsigned long driver_data;
};

struct pci_dev {
	struct device dev;
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
