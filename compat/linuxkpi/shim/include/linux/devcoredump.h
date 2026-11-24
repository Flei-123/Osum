/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_DEVCOREDUMP_H
#define LKPI_LINUX_DEVCOREDUMP_H
#include <linux/device.h>
#include <linux/scatterlist.h>
void dev_coredumpv(struct device *dev, void *data, size_t datalen, gfp_t gfp);
#endif
