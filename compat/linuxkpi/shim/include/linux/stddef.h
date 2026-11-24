/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_STDDEF_H
#define LKPI_LINUX_STDDEF_H
#define __struct_group(TAG, NAME, ATTRS, MEMBERS...) \
	union { struct { MEMBERS } ATTRS; struct TAG { MEMBERS } ATTRS NAME; } ATTRS
#define struct_group(NAME, MEMBERS...) __struct_group(, NAME, , MEMBERS)
#define struct_group_attr(NAME, ATTRS, MEMBERS...) __struct_group(, NAME, ATTRS, MEMBERS)
#define struct_group_tagged(TAG, NAME, MEMBERS...) __struct_group(TAG, NAME, , MEMBERS)
#define DECLARE_FLEX_ARRAY(TYPE, NAME) struct { struct { } __empty_##NAME; TYPE NAME[]; }
#define offsetof(T, m) __builtin_offsetof(T, m)
#define offsetofend(T, m) (offsetof(T, m) + sizeof(((T *)0)->m))
#define sizeof_field(T, m) sizeof(((T *)0)->m)
#define typeof_member(T, m) __typeof__(((T *)0)->m)
#define typeof __typeof__
#endif
