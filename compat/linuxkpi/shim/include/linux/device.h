/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LKPI_LINUX_DEVICE_H
#define LKPI_LINUX_DEVICE_H
#include <linux/kobject.h>
#include <linux/kernel.h>
#include <linux/lockdep.h>
#include <linux/atomic.h>
#include <linux/dma-direction.h>
#include <linux/refcount.h>
struct dev_pm_ops { int unused; };
#define SET_SYSTEM_SLEEP_PM_OPS(suspend_fn, resume_fn)
#define SIMPLE_DEV_PM_OPS(name, suspend_fn, resume_fn) const struct dev_pm_ops name = { 0 }
#define DEFINE_SIMPLE_DEV_PM_OPS(name, suspend_fn, resume_fn) const struct dev_pm_ops name = { 0 }
#define pm_sleep_ptr(p) (p)
struct device_driver {
	const char *name;
	const struct dev_pm_ops *pm;
};
struct bus_type { const char *name; };
struct device {
	struct kobject kobj;
	const struct bus_type *bus;
	void *driver_data;
	struct device *parent;
	const char *init_name;
};
const char *dev_name(const struct device *dev);
void *dev_get_drvdata(const struct device *dev);
void dev_set_drvdata(struct device *dev, void *data);
#define dev_err(dev, fmt, ...) _printk("lkpi: " fmt, ##__VA_ARGS__)
#define dev_crit(dev, fmt, ...) _printk("lkpi: " fmt, ##__VA_ARGS__)
#define dev_warn(dev, fmt, ...) _printk("lkpi: " fmt, ##__VA_ARGS__)
#define dev_info(dev, fmt, ...) _printk("lkpi: " fmt, ##__VA_ARGS__)
#define dev_dbg(dev, fmt, ...) no_printk(fmt, ##__VA_ARGS__)
#define dev_err_ratelimited(dev, fmt, ...) dev_err(dev, fmt, ##__VA_ARGS__)
#endif
