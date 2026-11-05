#include "lkpi.h"

#define PCI_COMMAND 4
#define PCI_COMMAND_IO 0x1U
#define PCI_COMMAND_MEMORY 0x2U
#define PCI_COMMAND_MASK 0x407U
#define PCI_REVISION 8

static struct pci_dev device;
static struct pci_driver *bound_driver;
static bool attached;
static bool probed;
static int probe_status = -ENODEV;

static bool id_matches(const struct pci_device_id *id, const struct pci_dev *dev)
{
	if (id->vendor != PCI_ANY_ID && id->vendor != dev->vendor)
		return false;
	if (id->device != PCI_ANY_ID && id->device != dev->device)
		return false;
	if (id->subvendor != PCI_ANY_ID && id->subvendor != dev->subsystem_vendor)
		return false;
	if (id->subdevice != PCI_ANY_ID && id->subdevice != dev->subsystem_device)
		return false;
	return !((id->class ^ dev->class) & id->class_mask);
}

static const struct pci_device_id *find_id(const struct pci_driver *driver,
					   const struct pci_dev *dev)
{
	const struct pci_device_id *id = driver->id_table;

	for (; id && (id->vendor || id->subvendor || id->class_mask); id++) {
		if (id_matches(id, dev))
			return id;
	}
	return NULL;
}

int lkpi_pci_attach(u64 state)
{
	u64 bar[3];
	u64 subsystem;
	u64 class_code;
	unsigned int i;

	if (k_abi() != OSUM_ABI) {
		_printk("lkpi: kernel ABI %llu, shim expects %llu\n", k_abi(), OSUM_ABI);
		return -ENOSYS;
	}
	memset(&device, 0, sizeof(device));
	subsystem = osum_ctx_read(state, OSUM_CTX_SUBSYSTEM);
	class_code = (osum_ctx_read(state, OSUM_CTX_CLASS) << 8) |
		     (osum_ctx_read(state, OSUM_CTX_PROGIF) & 0xff);
	device.vendor = (u16)osum_ctx_read(state, OSUM_CTX_VENDOR);
	device.device = (u16)osum_ctx_read(state, OSUM_CTX_DEVICE);
	device.subsystem_vendor = (u16)(subsystem >> 16);
	device.subsystem_device = (u16)subsystem;
	device.class = (u32)class_code;
	device.devfn = (u32)osum_ctx_read(state, OSUM_CTX_BDF) & 0xff;
	device.irq = (u8)osum_ctx_read(state, OSUM_CTX_IRQ);
	device.revision = (u8)k_pcicfg_read(PCI_REVISION);
	for (i = 0; i < OSUM_BAR_COUNT; i++) {
		struct resource *res = &device.resource[i];

		if (k_pcibar(i, bar) != 0 || bar[1] == 0)
			continue;
		res->start = bar[0];
		res->end = bar[0] + bar[1] - 1;
		res->flags = (bar[2] & OSUM_BAR_IO) ? IORESOURCE_IO : IORESOURCE_MEM;
		if (bar[2] & OSUM_BAR_PREFETCH)
			res->flags |= IORESOURCE_PREFETCH;
	}
	attached = true;
	probed = false;
	probe_status = -ENODEV;
	return 0;
}

int lkpi_pci_probe_status(void)
{
	return probe_status;
}

int __pci_register_driver(struct pci_driver *driver, struct module *owner, const char *name)
{
	const struct pci_device_id *id;

	(void)owner;
	(void)name;
	if (!attached || bound_driver)
		return 0;
	id = find_id(driver, &device);
	if (!id) {
		_printk("lkpi: %s: no matching device %04x:%04x\n", driver->name, device.vendor,
			device.device);
		return 0;
	}
	bound_driver = driver;
	probe_status = driver->probe(&device, id);
	probed = probe_status == 0;
	if (!probed)
		_printk("lkpi: %s: probe failed %d\n", driver->name, probe_status);
	return 0;
}

void pci_unregister_driver(struct pci_driver *driver)
{
	if (bound_driver != driver)
		return;
	if (probed && driver->remove)
		driver->remove(&device);
	probed = false;
	bound_driver = NULL;
	probe_status = -ENODEV;
}

int pcim_enable_device(struct pci_dev *dev)
{
	u64 command;

	(void)dev;
	command = k_pcicfg_read(PCI_COMMAND) & PCI_COMMAND_MASK;
	k_pcicfg_write(PCI_COMMAND, command | PCI_COMMAND_IO | PCI_COMMAND_MEMORY);
	return 0;
}

int pci_request_region(struct pci_dev *dev, int bar, const char *name)
{
	(void)name;
	if (bar < 0 || bar >= PCI_NUM_RESOURCES || !dev->resource[bar].flags)
		return -EINVAL;
	if (dev->requested & (1U << bar))
		return -EBUSY;
	dev->requested |= 1U << bar;
	return 0;
}

void pci_release_regions(struct pci_dev *dev)
{
	dev->requested = 0;
}
