/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_COMPLETION_H
#define LKPI_LINUX_COMPLETION_H
#include <linux/wait.h>
struct completion { unsigned int done; wait_queue_head_t wait; };
#define DECLARE_COMPLETION(n) struct completion n = { 0 }
#define init_completion(c) do { (c)->done = 0; init_waitqueue_head(&(c)->wait); } while (0)
#define reinit_completion(c) do { (c)->done = 0; } while (0)
void complete(struct completion *c);
void complete_all(struct completion *c);
void wait_for_completion(struct completion *c);
unsigned long wait_for_completion_timeout(struct completion *c, unsigned long timeout);
bool completion_done(struct completion *c);
#endif
