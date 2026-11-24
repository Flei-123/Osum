/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_PTP_CLOCK_KERNEL_H
#define LKPI_LINUX_PTP_CLOCK_KERNEL_H
#include <linux/time.h>
struct ptp_clock;
struct ptp_system_timestamp;
struct ptp_clock_info { struct module *owner; char name[32]; s32 max_adj; int n_alarm; int n_ext_ts; int n_per_out; int n_pins; int pps;
	int (*adjfine)(struct ptp_clock_info *, long); int (*adjtime)(struct ptp_clock_info *, s64);
	int (*gettimex64)(struct ptp_clock_info *, struct timespec64 *, struct ptp_system_timestamp *);
	int (*settime64)(struct ptp_clock_info *, const struct timespec64 *); };
struct ptp_clock *ptp_clock_register(struct ptp_clock_info *info, struct device *parent);
void ptp_clock_unregister(struct ptp_clock *ptp);
int ptp_clock_index(struct ptp_clock *ptp);
#endif
