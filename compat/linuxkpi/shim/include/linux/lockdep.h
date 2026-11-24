/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_LOCKDEP_H
#define LKPI_LINUX_LOCKDEP_H
#include <linux/spinlock.h>
#include <linux/mutex.h>
struct lock_class_key { int unused; };
#define lockdep_assert_held(l) ((void)(l))
#define lockdep_assert_held_once(l) ((void)(l))
#define lockdep_assert_not_held(l) ((void)(l))
#define lockdep_assert_held_write(l) ((void)(l))
#define lockdep_assert_irqs_disabled() do { } while (0)
#define lockdep_is_held(l) 1
#define lockdep_set_class(l, k) do { } while (0)
#define lockdep_register_key(k) do { } while (0)
#define lockdep_unregister_key(k) do { } while (0)
#define lockdep_init_map(m, n, k, s) do { } while (0)
#define might_sleep() do { } while (0)
#define might_sleep_if(c) do { } while (0)
struct lockdep_map { int unused; };
#define STATIC_LOCKDEP_MAP_INIT(n, k) { 0 }
#define lock_map_acquire(m) do { } while (0)
#define lock_map_release(m) do { } while (0)
#define lock_map_acquire_read(m) do { } while (0)
#define lock_map_acquire_try(m) do { } while (0)
#endif
