/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_CPU_H
#define LKPI_LINUX_CPU_H
#include <linux/kernel.h>
#include <linux/cpumask.h>
int num_online_cpus(void);
int smp_processor_id(void);
#define get_cpu() smp_processor_id()
#define put_cpu() do { } while (0)
#define nr_cpu_ids 1
#define for_each_possible_cpu(cpu) for ((cpu) = 0; (cpu) < 1; (cpu)++)
#define for_each_online_cpu(cpu) for_each_possible_cpu(cpu)
#endif
