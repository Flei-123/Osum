#include "../src/lkpi.h"
#include "../src/wifi.h"
#include "iwl_fwinfo.h"

int lkpi_init_iwl_drv_init(void);
void lkpi_exit_iwl_drv_exit(void);
int lkpi_init_iwl_mvm_init(void);
void lkpi_exit_iwl_mvm_exit(void);
int lkpi_module_init(u64 state) __asm__("module_init");
void lkpi_module_exit(u64 state) __asm__("module_exit");

int lkpi_module_init(u64 state)
{
	int rc = lkpi_pci_attach(state);

	if (rc)
		return rc;
	rc = lkpi_firmware_load(IWL_FW_NAME, iwl_fw_hash, IWL_FW_CAP);
	if (rc)
		return rc;
	rc = lkpi_init_iwl_drv_init();
	if (rc)
		return rc;
	rc = lkpi_init_iwl_mvm_init();
	if (rc) {
		lkpi_exit_iwl_drv_exit();
		lkpi_firmware_clear();
		return rc;
	}
	return lkpi_pci_probe_status();
}

void lkpi_module_exit(u64 state)
{
	(void)state;
	lkpi_exit_iwl_mvm_exit();
	lkpi_exit_iwl_drv_exit();
	lkpi_firmware_clear();
}
