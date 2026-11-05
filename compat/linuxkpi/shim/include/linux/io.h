#ifndef LKPI_LINUX_IO_H
#define LKPI_LINUX_IO_H

#include <linux/kernel.h>

static inline u8 readb(const volatile void __iomem *addr) { return *(const volatile u8 *)addr; }
static inline u16 readw(const volatile void __iomem *addr) { return *(const volatile u16 *)addr; }
static inline u32 readl(const volatile void __iomem *addr) { return *(const volatile u32 *)addr; }
static inline u64 readq(const volatile void __iomem *addr) { return *(const volatile u64 *)addr; }
static inline void writeb(u8 value, volatile void __iomem *addr) { *(volatile u8 *)addr = value; }
static inline void writew(u16 value, volatile void __iomem *addr) { *(volatile u16 *)addr = value; }
static inline void writel(u32 value, volatile void __iomem *addr) { *(volatile u32 *)addr = value; }
static inline void writeq(u64 value, volatile void __iomem *addr) { *(volatile u64 *)addr = value; }

static inline void outb(u8 value, u16 port)
{
	__asm__ volatile("outb %0, %1" : : "a"(value), "Nd"(port));
}

static inline void outw(u16 value, u16 port)
{
	__asm__ volatile("outw %0, %1" : : "a"(value), "Nd"(port));
}

static inline void outl(u32 value, u16 port)
{
	__asm__ volatile("outl %0, %1" : : "a"(value), "Nd"(port));
}

static inline u8 inb(u16 port)
{
	u8 value;
	__asm__ volatile("inb %1, %0" : "=a"(value) : "Nd"(port));
	return value;
}

static inline u16 inw(u16 port)
{
	u16 value;
	__asm__ volatile("inw %1, %0" : "=a"(value) : "Nd"(port));
	return value;
}

static inline u32 inl(u16 port)
{
	u32 value;
	__asm__ volatile("inl %1, %0" : "=a"(value) : "Nd"(port));
	return value;
}

struct resource {
	resource_size_t start;
	resource_size_t end;
	const char *name;
	unsigned long flags;
};

#define IORESOURCE_IO 0x00000100UL
#define IORESOURCE_MEM 0x00000200UL
#define IORESOURCE_PREFETCH 0x00002000UL

extern struct resource ioport_resource;
extern struct resource iomem_resource;

void __iomem *ioremap(resource_size_t phys, unsigned long size);
void iounmap(volatile void __iomem *addr);
struct resource *__request_region(struct resource *parent, resource_size_t start,
				  resource_size_t count, const char *name, int flags);
void __release_region(struct resource *parent, resource_size_t start,
		      resource_size_t count);

#define request_region(start, count, name) \
	__request_region(&ioport_resource, (start), (count), (name), 0)
#define release_region(start, count) \
	__release_region(&ioport_resource, (start), (count))

#endif
