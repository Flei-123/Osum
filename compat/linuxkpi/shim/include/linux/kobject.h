/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_KOBJECT_H
#define LKPI_LINUX_KOBJECT_H
#include <linux/types.h>
struct kobject { const char *name; };
enum kobject_action { KOBJ_ADD, KOBJ_REMOVE, KOBJ_CHANGE };
int kobject_uevent_env(struct kobject *kobj, enum kobject_action action, char *envp[]);
#endif
