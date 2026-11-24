/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_CPUMASK_H
#define LKPI_LINUX_CPUMASK_H
#include <linux/bitops.h>
#define NR_CPUS 64
typedef struct { DECLARE_BITMAP(bits, NR_CPUS); } cpumask_t;
typedef cpumask_t cpumask_var_t[1];
static inline void cpumask_clear(cpumask_t *m) { m->bits[0] = 0; }
static inline void cpumask_set_cpu(unsigned int cpu, cpumask_t *m) { __set_bit(cpu, m->bits); }
static inline int cpumask_empty(const cpumask_t *m) { return !m->bits[0]; }
#endif
