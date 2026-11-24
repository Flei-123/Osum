/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_SPINLOCK_H
#define LKPI_LINUX_SPINLOCK_H
#include <linux/kernel.h>
#include <linux/cleanup.h>
typedef struct { int locked; } spinlock_t;
typedef struct { int locked; } raw_spinlock_t;
typedef struct { int locked; } rwlock_t;
#define __SPIN_LOCK_UNLOCKED(x) { 0 }
#define DEFINE_SPINLOCK(x) spinlock_t x = { 0 }
#define DEFINE_RAW_SPINLOCK(x) raw_spinlock_t x = { 0 }
#define spin_lock_init(l) do { (l)->locked = 0; } while (0)
#define raw_spin_lock_init(l) spin_lock_init(l)
#define rwlock_init(l) spin_lock_init(l)
#define spin_lock(l) do { (l)->locked = 1; } while (0)
#define spin_unlock(l) do { (l)->locked = 0; } while (0)
#define spin_lock_bh(l) spin_lock(l)
#define spin_unlock_bh(l) spin_unlock(l)
#define spin_lock_irq(l) spin_lock(l)
#define spin_unlock_irq(l) spin_unlock(l)
#define spin_lock_irqsave(l, f) do { (f) = 0; spin_lock(l); } while (0)
#define spin_unlock_irqrestore(l, f) do { (void)(f); spin_unlock(l); } while (0)
#define spin_trylock(l) ((l)->locked ? 0 : ((l)->locked = 1))
#define spin_is_locked(l) ((l)->locked)
#define assert_spin_locked(l) ((void)(l))
#define raw_spin_lock_irqsave(l, f) spin_lock_irqsave(l, f)
#define raw_spin_unlock_irqrestore(l, f) spin_unlock_irqrestore(l, f)
#define raw_spin_lock(l) spin_lock(l)
#define raw_spin_unlock(l) spin_unlock(l)
#define read_lock(l) spin_lock(l)
#define read_unlock(l) spin_unlock(l)
#define write_lock_bh(l) spin_lock(l)
#define write_unlock_bh(l) spin_unlock(l)
#define local_bh_disable() do { } while (0)
#define local_bh_enable() do { } while (0)
#define local_irq_save(f) do { (f) = 0; } while (0)
#define local_irq_restore(f) do { (void)(f); } while (0)
#define local_irq_disable() do { } while (0)
#define local_irq_enable() do { } while (0)
DEFINE_LOCK_GUARD_1(spinlock, spinlock_t, spin_lock(_T->lock), spin_unlock(_T->lock))
DEFINE_LOCK_GUARD_1(spinlock_bh, spinlock_t, spin_lock_bh(_T->lock), spin_unlock_bh(_T->lock))
DEFINE_LOCK_GUARD_1(spinlock_irqsave, spinlock_t, spin_lock_irqsave(_T->lock, _T->flags), spin_unlock_irqrestore(_T->lock, _T->flags), unsigned long flags)
#endif
