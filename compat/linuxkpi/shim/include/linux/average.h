/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_AVERAGE_H
#define LKPI_LINUX_AVERAGE_H
#include <linux/kernel.h>
#define DECLARE_EWMA(name, _precision, _weight_rcp) \
	struct ewma_##name { unsigned long internal; }; \
	static inline void ewma_##name##_init(struct ewma_##name *e) { e->internal = 0; } \
	static inline unsigned long ewma_##name##_read(struct ewma_##name *e) { return e->internal >> (_precision); } \
	static inline void ewma_##name##_add(struct ewma_##name *e, unsigned long val) \
	{ \
		unsigned long internal = e->internal; \
		e->internal = internal ? (((internal << (_weight_rcp)) - internal) + (val << (_precision))) >> (_weight_rcp) : (val << (_precision)); \
	}
#endif
