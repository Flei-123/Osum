#include "../src/lkpi.h"

int lkpi_wifi_fake_init(void);
void lkpi_wifi_fake_exit(void);
int lkpi_wifi_module_init(u64 state) __asm__("module_init");
void lkpi_wifi_module_exit(u64 state) __asm__("module_exit");

int lkpi_wifi_module_init(u64 state)
{
	(void)state;
	return lkpi_wifi_fake_init();
}

void lkpi_wifi_module_exit(u64 state)
{
	(void)state;
	lkpi_wifi_fake_exit();
}
