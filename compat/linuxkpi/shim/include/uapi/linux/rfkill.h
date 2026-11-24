/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_UAPI_LINUX_RFKILL_H
#define LKPI_UAPI_LINUX_RFKILL_H
#include <linux/types.h>
enum rfkill_hard_block_reasons {
	RFKILL_HARD_BLOCK_SIGNAL = 1 << 0,
	RFKILL_HARD_BLOCK_NOT_OWNER = 1 << 1,
};
#endif
