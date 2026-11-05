#ifndef OSUM_OSUM_IF_H
#define OSUM_OSUM_IF_H

#define OSUM_ABI 1ULL
#define OSUM_CTX_OFFSET 0xAA800ULL
#define OSUM_CTX_VENDOR 16
#define OSUM_CTX_DEVICE 24
#define OSUM_CTX_SUBSYSTEM 32
#define OSUM_CTX_CLASS 40
#define OSUM_CTX_PROGIF 48
#define OSUM_CTX_BDF 56
#define OSUM_CTX_BAR0_MAPPED 64
#define OSUM_CTX_IRQ 72
#define OSUM_CTX_PCI_INDEX 80
#define OSUM_CTX_BAR0_PHYS 88

#define OSUM_BAR_COUNT 6
#define OSUM_BAR_IO 1ULL
#define OSUM_BAR_PREFETCH 2ULL
#define OSUM_BAR_64BIT 4ULL

#define OSUM_KERNEL_SYMBOLS \
	k_abi k_puts \
	k_pcicfg_read k_pcicfg_write k_pcibar \
	k_ioremap k_frames k_frames_free

unsigned long long k_abi(void);
void k_puts(const char *text);
unsigned long long k_pcicfg_read(unsigned long long offset);
void k_pcicfg_write(unsigned long long offset, unsigned long long value);
unsigned long long k_pcibar(unsigned long long index, unsigned long long *out);
unsigned long long k_ioremap(unsigned long long phys, unsigned long long size);
unsigned long long k_frames(unsigned long long count);
void k_frames_free(unsigned long long addr, unsigned long long count);

static inline unsigned long long osum_ctx_read(unsigned long long state,
					       unsigned long long offset)
{
	return *(volatile unsigned long long *)(state + OSUM_CTX_OFFSET + offset);
}

#endif
