/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_LEDS_H
#define LKPI_LINUX_LEDS_H
#include <linux/kernel.h>
struct led_classdev { const char *name; const char *default_trigger; int (*blink_set)(struct led_classdev *, unsigned long *, unsigned long *);
	void (*brightness_set)(struct led_classdev *, int); int brightness; unsigned int flags; };
int led_classdev_register(struct device *parent, struct led_classdev *led);
void led_classdev_unregister(struct led_classdev *led);
#endif
