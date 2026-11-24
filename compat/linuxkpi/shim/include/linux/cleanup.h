/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_CLEANUP_H
#define LKPI_LINUX_CLEANUP_H
#include <linux/types.h>
#define __cleanup(func) __attribute__((__cleanup__(func)))
#define __PASTE2(a, b) a##b
#define __PASTE(a, b) __PASTE2(a, b)
#define __UNIQUE_ID(prefix) __PASTE(__PASTE(__UNIQUE_ID_, prefix), __COUNTER__)
#define DEFINE_FREE(_name, _type, _free) \
	static inline void __free_##_name(void *p) { _type _T = *(_type *)p; _free; }
#define __free(_name) __cleanup(__free_##_name)
#define __get_and_null(p, nullvalue) ({ __auto_type __ptr = &(p); __auto_type __val = *__ptr; *__ptr = nullvalue; __val; })
#define no_free_ptr(p) ((__typeof__(p))__get_and_null(p, NULL))
#define return_ptr(p) return no_free_ptr(p)
#define DEFINE_CLASS(_name, _type, _exit, _init, _init_args...) \
	typedef _type class_##_name##_t; \
	static inline void class_##_name##_destructor(_type *p) { _type _T = *p; _exit; } \
	static inline _type class_##_name##_constructor(_init_args) { _type t = _init; return t; }
#define CLASS(_name, var) class_##_name##_t var __cleanup(class_##_name##_destructor) = class_##_name##_constructor
#define DEFINE_GUARD(_name, _type, _lock, _unlock) \
	DEFINE_CLASS(_name, _type, if (_T) { _unlock; }, ({ _lock; _T; }), _type _T)
#define DEFINE_LOCK_GUARD_1(_name, _type, _lock, _unlock, ...) \
	typedef struct { _type *lock; __VA_ARGS__; } class_##_name##_t; \
	static inline void class_##_name##_destructor(class_##_name##_t *_T) { if (_T->lock) { _unlock; } } \
	static inline class_##_name##_t class_##_name##_constructor(_type *l) { class_##_name##_t _t = { .lock = l }, *_T = &_t; _lock; return _t; }
#define guard(_name) CLASS(_name, __UNIQUE_ID(guard))
#define scoped_guard(_name, args...) \
	for (CLASS(_name, scope)(args), *done = NULL; !done; done = (void *)1)
#endif
