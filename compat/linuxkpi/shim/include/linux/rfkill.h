/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_RFKILL_H
#define LKPI_LINUX_RFKILL_H
#include <linux/types.h>
#include <uapi/linux/rfkill.h>
struct rfkill;
bool rfkill_set_hw_state_reason(struct rfkill *rfkill, bool blocked, enum rfkill_hard_block_reasons reason);
static inline bool rfkill_set_hw_state(struct rfkill *rfkill, bool blocked)
{
	return rfkill_set_hw_state_reason(rfkill, blocked, RFKILL_HARD_BLOCK_SIGNAL);
}
#endif
