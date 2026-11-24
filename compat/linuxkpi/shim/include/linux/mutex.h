/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_MUTEX_H
#define LKPI_LINUX_MUTEX_H
#include <linux/kernel.h>
#include <linux/cleanup.h>
struct mutex { int locked; };
struct rw_semaphore { int count; };
#define DEFINE_MUTEX(x) struct mutex x = { 0 }
#define mutex_init(m) do { (m)->locked = 0; } while (0)
#define mutex_lock(m) do { (m)->locked = 1; } while (0)
#define mutex_unlock(m) do { (m)->locked = 0; } while (0)
#define mutex_trylock(m) ((m)->locked ? 0 : ((m)->locked = 1))
#define mutex_is_locked(m) ((m)->locked)
#define mutex_lock_interruptible(m) ({ (m)->locked = 1; 0; })
#define mutex_destroy(m) do { } while (0)
#define init_rwsem(s) do { (s)->count = 0; } while (0)
#define down_read(s) do { (s)->count++; } while (0)
#define up_read(s) do { (s)->count--; } while (0)
#define down_write(s) do { (s)->count = -1; } while (0)
#define up_write(s) do { (s)->count = 0; } while (0)
DEFINE_GUARD(mutex, struct mutex *, mutex_lock(_T), mutex_unlock(_T))
#endif
