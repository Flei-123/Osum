/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_KCONFIG_H
#define LKPI_LINUX_KCONFIG_H
#define __ARG_PLACEHOLDER_1 0,
#define __take_second_arg(__ignored, val, ...) val
#define ____is_defined(arg1_or_junk) __take_second_arg(arg1_or_junk 1, 0)
#define ___is_defined(val) ____is_defined(__ARG_PLACEHOLDER_##val)
#define __is_defined(x) ___is_defined(x)
#define IS_BUILTIN(option) __is_defined(option)
#define IS_MODULE(option) __is_defined(option##_MODULE)
#define IS_ENABLED(option) (__is_defined(option) || __is_defined(option##_MODULE))
#define IS_REACHABLE(option) IS_ENABLED(option)
#endif
