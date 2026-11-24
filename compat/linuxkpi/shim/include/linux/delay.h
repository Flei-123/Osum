/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_DELAY_H
#define LKPI_LINUX_DELAY_H
#include <linux/types.h>
void udelay(unsigned long usecs);
void mdelay(unsigned long msecs);
void msleep(unsigned int msecs);
void usleep_range(unsigned long min, unsigned long max);
#define ndelay(n) udelay(((n) + 999) / 1000)
#endif
