#ifndef LKPI_LINUX_MODULE_H
#define LKPI_LINUX_MODULE_H

#include <linux/kernel.h>

struct module;
#define THIS_MODULE ((struct module *)0)

#define LKPI_NOOP_DECL _Static_assert(1, "module metadata")
#define module_param(name, type, perm) LKPI_NOOP_DECL
#define module_param_named(name, var, type, perm) LKPI_NOOP_DECL
#define MODULE_PARM_DESC(name, desc) LKPI_NOOP_DECL
#define MODULE_DEVICE_TABLE(bus, table) LKPI_NOOP_DECL
#define MODULE_AUTHOR(text) LKPI_NOOP_DECL
#define MODULE_DESCRIPTION(text) LKPI_NOOP_DECL
#define MODULE_LICENSE(text) LKPI_NOOP_DECL

#define module_init(fn) extern int lkpi_driver_init(void) __attribute__((alias(#fn)))
#define module_exit(fn) extern void lkpi_driver_exit(void) __attribute__((alias(#fn)))

#endif
