#ifdef LKPI_IWL_DEBUG
#include <linux/kernel.h>
#include "iwl-modparams.h"
#endif
#include "../src/lkpi.h"
#include "../src/wifi.h"
#include "iwl_fwinfo.h"

#define IWL_PUMP_ROUNDS 3000

int lkpi_init_iwl_drv_init(void);
void lkpi_exit_iwl_drv_exit(void);
int lkpi_init_iwl_mvm_init(void);
void lkpi_exit_iwl_mvm_exit(void);
int lkpi_module_init(u64 state) __asm__("module_init");
void lkpi_module_exit(u64 state) __asm__("module_exit");

int lkpi_module_init(u64 state)
{
	int rc = lkpi_pci_attach(state);

#ifdef LKPI_IWL_DEBUG
	iwlwifi_mod_params.debug_level = 0xFFFFFFFF;
#endif

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
	rc = lkpi_pci_probe_status();
	if (rc)
		return rc;
#ifdef LKPI_IWL_PUMP
	if (lkpi_wifi_glue_attach_when_ready(IWL_PUMP_ROUNDS))
		_printk("lkpi: iwl radio not registered after %d rounds\n", IWL_PUMP_ROUNDS);
#endif
	return 0;
}

void lkpi_module_exit(u64 state)
{
	(void)state;
	lkpi_exit_iwl_mvm_exit();
	lkpi_exit_iwl_drv_exit();
	lkpi_firmware_clear();
}
