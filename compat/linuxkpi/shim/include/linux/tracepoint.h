/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_TRACEPOINT_H
#define LKPI_LINUX_TRACEPOINT_H
#include <linux/kernel.h>
#define PARAMS(args...) args
#define TP_PROTO(args...) args
#define TP_ARGS(args...) args
#define TP_STRUCT__entry(args...) args
#define TP_fast_assign(args...) args
#define TP_printk(fmt, args...) fmt, args
#define TP_CONDITION(args...) args
#define DECLARE_TRACE(name, proto, args) \
	static inline void trace_##name(proto) { } \
	static inline bool trace_##name##_enabled(void) { return false; }
#define TRACE_EVENT(name, proto, args, tstruct, assign, print) DECLARE_TRACE(name, PARAMS(proto), PARAMS(args))
#define DECLARE_EVENT_CLASS(name, proto, args, tstruct, assign, print)
#define DEFINE_EVENT(tmpl, name, proto, args) DECLARE_TRACE(name, PARAMS(proto), PARAMS(args))
#define DEFINE_EVENT_PRINT(tmpl, name, proto, args, print) DECLARE_TRACE(name, PARAMS(proto), PARAMS(args))
#define TRACE_EVENT_CONDITION(name, proto, args, cond, tstruct, assign, print) DECLARE_TRACE(name, PARAMS(proto), PARAMS(args))
#endif
