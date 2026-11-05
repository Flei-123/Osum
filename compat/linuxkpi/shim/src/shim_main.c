#include "lkpi.h"

int lkpi_shim_init(u64 state) __asm__("module_init");
void lkpi_shim_exit(u64 state) __asm__("module_exit");

int lkpi_shim_init(u64 state)
{
	(void)state;
	if (k_abi() != OSUM_ABI) {
		_printk("lkpi: kernel ABI %llu, shim expects %llu\n", k_abi(), OSUM_ABI);
		return -ENOSYS;
	}
	_printk("lkpi: shim ready\n");
	return 0;
}

void lkpi_shim_exit(u64 state)
{
	(void)state;
	lkpi_heap_release();
}
