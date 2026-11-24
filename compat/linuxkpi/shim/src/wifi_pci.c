#include "wifi.h"
#include <linux/pci.h>
#include <osum/osum_if.h>

#define PCI_CFG_COMMAND 4
#define PCI_COMMAND_BUS_MASTER 0x4U
#define PCI_COMMAND_KEEP_MASK 0x407U
#define PCI_CAP_POINTER 0x34
#define PCI_CAP_LIST_MAX 48
#define PCI_CAP_ID_EXP 0x10
#define PCI_EXT_CAP_START 0x100
#define PCI_EXT_CAP_LIST_MAX 48
#define PCI_NAME_MAX 16
#define PCI_DWORD_MASK 3U
#define PCI_FUNCTIONS_PER_SLOT 8

static void __iomem *iomap_table[PCI_NUM_RESOURCES];
static char name_buffer[PCI_NAME_MAX];

static u32 cfg_dword(unsigned int offset)
{
	return (u32)k_pcicfg_read(offset & ~PCI_DWORD_MASK);
}

static void cfg_write_bits(unsigned int offset, unsigned int shift, u32 mask, u32 value)
{
	u32 word = cfg_dword(offset);

	word = (word & ~(mask << shift)) | ((value & mask) << shift);
	k_pcicfg_write(offset & ~PCI_DWORD_MASK, word);
}

int pci_read_config_dword(struct pci_dev *dev, int where, u32 *val)
{
	(void)dev;
	*val = cfg_dword(where);
	return 0;
}

int pci_read_config_word(struct pci_dev *dev, int where, u16 *val)
{
	(void)dev;
	*val = (u16)(cfg_dword(where) >> ((where & 2) * 8));
	return 0;
}

int pci_write_config_word(struct pci_dev *dev, int where, u16 val)
{
	(void)dev;
	cfg_write_bits(where, (where & 2) * 8, 0xffffU, val);
	return 0;
}

int pci_write_config_byte(struct pci_dev *dev, int where, u8 val)
{
	(void)dev;
	cfg_write_bits(where, (where & PCI_DWORD_MASK) * 8, 0xffU, val);
	return 0;
}

void pci_set_master(struct pci_dev *dev)
{
	(void)dev;
	k_pcicfg_write(PCI_CFG_COMMAND, (cfg_dword(PCI_CFG_COMMAND) & PCI_COMMAND_KEEP_MASK) | PCI_COMMAND_BUS_MASTER);
}

static int find_capability(int cap_id)
{
	unsigned int hops;
	unsigned int pos = cfg_dword(PCI_CAP_POINTER) & 0xfcU;

	for (hops = 0; pos && hops < PCI_CAP_LIST_MAX; hops++) {
		u32 header = cfg_dword(pos);

		if ((int)(header & 0xffU) == cap_id)
			return pos;
		pos = (header >> 8) & 0xfcU;
	}
	return 0;
}

u16 pci_find_ext_capability(struct pci_dev *dev, int cap_id)
{
	unsigned int hops;
	unsigned int pos = PCI_EXT_CAP_START;

	(void)dev;
	for (hops = 0; pos >= PCI_EXT_CAP_START && hops < PCI_EXT_CAP_LIST_MAX; hops++) {
		u32 header = cfg_dword(pos);

		if (!header || header == 0xffffffffU)
			return 0;
		if ((int)(header & 0xffffU) == cap_id)
			return pos;
		pos = (header >> 20) & 0xffcU;
	}
	return 0;
}

int pcie_capability_read_word(struct pci_dev *dev, int pos, u16 *val)
{
	int cap = find_capability(PCI_CAP_ID_EXP);

	*val = 0;
	if (!cap)
		return -EINVAL;
	return pci_read_config_word(dev, cap + pos, val);
}

struct pci_dev *pcie_find_root_port(struct pci_dev *dev)
{
	(void)dev;
	return NULL;
}

int pci_disable_link_state(struct pci_dev *pdev, int state)
{
	(void)pdev;
	(void)state;
	return 0;
}

struct pci_dev *pci_dev_get(struct pci_dev *dev)
{
	return dev;
}

void pci_dev_put(struct pci_dev *dev)
{
	(void)dev;
}

const char *pci_name(const struct pci_dev *dev)
{
	unsigned int bus = dev->bus ? dev->bus->number : 0;

	snprintf(name_buffer, sizeof(name_buffer), "0000:%02x:%02x.%u", bus, dev->devfn / PCI_FUNCTIONS_PER_SLOT,
		 dev->devfn % PCI_FUNCTIONS_PER_SLOT);
	return name_buffer;
}

bool pci_pme_capable(struct pci_dev *dev, pci_power_t state)
{
	(void)dev;
	(void)state;
	return false;
}

int pci_enable_msi(struct pci_dev *dev)
{
	(void)dev;
	return -ENOSYS;
}

int pci_enable_msix_range(struct pci_dev *dev, struct msix_entry *entries, int minvec, int maxvec)
{
	(void)dev;
	(void)entries;
	(void)minvec;
	(void)maxvec;
	return -ENOSYS;
}

int pci_assign_resource(struct pci_dev *dev, int resno)
{
	(void)dev;
	(void)resno;
	return -ENOSYS;
}

void pci_lock_rescan_remove(void)
{
}

void pci_unlock_rescan_remove(void)
{
}

int pci_rescan_bus(struct pci_bus *bus)
{
	(void)bus;
	return 0;
}

void pci_stop_and_remove_bus_device(struct pci_dev *dev)
{
	(void)dev;
}

int pcim_iomap_regions_request_all(struct pci_dev *dev, int mask, const char *name)
{
	int bar;

	for (bar = 0; bar < PCI_NUM_RESOURCES; bar++) {
		u64 start;
		u64 length;

		if (!(mask & (1 << bar)) || !dev->resource[bar].flags)
			continue;
		if (pci_request_region(dev, bar, name))
			return -EBUSY;
		start = pci_resource_start(dev, bar);
		length = pci_resource_len(dev, bar);
		iomap_table[bar] = (void __iomem *)k_ioremap(start, length);
		if (!iomap_table[bar])
			return -ENOMEM;
		lkpi_mmio_note_mapping((u64)(unsigned long)iomap_table[bar]);
	}
	return 0;
}

void __iomem *const *pcim_iomap_table(struct pci_dev *dev)
{
	(void)dev;
	return iomap_table;
}
