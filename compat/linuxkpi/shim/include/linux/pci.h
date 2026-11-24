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
#define PCI_BASE_ADDRESS_0 0x10
#define PCIE_LINK_STATE_L0S 1
#define PCIE_LINK_STATE_L1 2
#define PCIE_LINK_STATE_CLKPM 4
struct pci_dev;
int pci_disable_link_state(struct pci_dev *pdev, int state);
#define PCI_BASE_ADDRESS_MEM_TYPE_MASK 0x06
#define PCI_BASE_ADDRESS_MEM_TYPE_64 0x04
#define PCI_BASE_ADDRESS_MEM_MASK (~0x0fUL)
typedef int pci_power_t;
#define PCI_D0 0
#define PCI_D1 1
#define PCI_D2 2
#define PCI_D3hot 3
#define PCI_D3cold 4
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

struct pci_bus { struct pci_bus *parent; unsigned char number; struct pci_dev *self; };
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

int pci_read_config_dword(struct pci_dev *dev, int where, u32 *val);
int pci_read_config_word(struct pci_dev *dev, int where, u16 *val);
int pci_write_config_word(struct pci_dev *dev, int where, u16 val);
int pci_write_config_byte(struct pci_dev *dev, int where, u8 val);
void pci_set_master(struct pci_dev *dev);
u16 pci_find_ext_capability(struct pci_dev *dev, int cap_id);
int pcie_capability_read_word(struct pci_dev *dev, int pos, u16 *val);
struct pci_dev *pcie_find_root_port(struct pci_dev *dev);
struct pci_dev *pci_dev_get(struct pci_dev *dev);
void pci_dev_put(struct pci_dev *dev);
const char *pci_name(const struct pci_dev *dev);
bool pci_pme_capable(struct pci_dev *dev, pci_power_t state);
int pci_enable_msi(struct pci_dev *dev);
int pci_enable_msix_range(struct pci_dev *dev, struct msix_entry *entries, int minvec, int maxvec);
int pci_assign_resource(struct pci_dev *dev, int resno);
void pci_lock_rescan_remove(void);
void pci_unlock_rescan_remove(void);
int pci_rescan_bus(struct pci_bus *bus);
void pci_stop_and_remove_bus_device(struct pci_dev *dev);
int pcim_iomap_regions_request_all(struct pci_dev *dev, int mask, const char *name);
void __iomem *const *pcim_iomap_table(struct pci_dev *dev);
static inline void pci_set_drvdata(struct pci_dev *dev, void *data)
{
	dev->dev.driver_data = data;
}

static inline void *pci_get_drvdata(struct pci_dev *dev)
{
	return dev->dev.driver_data;
}

#endif
