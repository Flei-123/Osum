#include "../src/lkpi.h"

int lkpi_driver_init(void);
void lkpi_driver_exit(void);
int lkpi_module_init(u64 state) __asm__("module_init");
void lkpi_module_exit(u64 state) __asm__("module_exit");

int lkpi_module_init(u64 state)
{
	int rc = lkpi_pci_attach(state);

	if (rc)
		return rc;
	rc = lkpi_driver_init();
	if (rc)
		return rc;
	return lkpi_pci_probe_status();
}

void lkpi_module_exit(u64 state)
{
	(void)state;
	lkpi_driver_exit();
}
