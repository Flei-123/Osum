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
	k_ioremap k_frames k_frames_free \
	k_kms_register k_kms_unregister k_shm_frame \
	k_wifi_register k_wifi_unregister k_wifi_hw

unsigned long long k_abi(void);
void k_puts(const char *text);
unsigned long long k_pcicfg_read(unsigned long long offset);
void k_pcicfg_write(unsigned long long offset, unsigned long long value);
unsigned long long k_pcibar(unsigned long long index, unsigned long long *out);
unsigned long long k_ioremap(unsigned long long phys, unsigned long long size);
unsigned long long k_frames(unsigned long long count);
void k_frames_free(unsigned long long addr, unsigned long long count);

struct osum_kms_ops {
	unsigned long long ready;
	unsigned long long width;
	unsigned long long height;
	unsigned long long refresh;
	unsigned long long scanout;
	unsigned long long release;
	unsigned long long tag;
};

unsigned long long k_kms_register(const struct osum_kms_ops *ops);
void k_kms_unregister(unsigned long long tag);
unsigned long long k_shm_frame(unsigned long long state, unsigned long long shm,
			       unsigned long long index);

#define OSUM_WIFI_HW_RESET 1ULL
#define OSUM_WIFI_HW_TX 2ULL
#define OSUM_WIFI_HW_RESP 3ULL
#define OSUM_WIFI_HW_NETS 4ULL
#define OSUM_WIFI_HW_BEACON 5ULL

struct osum_wifi_ops {
	unsigned long long ready;
	unsigned long long tx;
	unsigned long long rx_take;
	unsigned long long set_channel;
	unsigned long long op;
	unsigned long long bssid_set;
	unsigned long long addr_set;
	unsigned long long aid_set;
	unsigned long long scan_state;
	unsigned long long rssi;
	unsigned long long tag;
};

unsigned long long k_wifi_register(const struct osum_wifi_ops *ops);
void k_wifi_unregister(unsigned long long tag);
unsigned long long k_wifi_hw(unsigned long long op, unsigned long long a, unsigned long long b,
			     unsigned long long c);

static inline unsigned long long osum_ctx_read(unsigned long long state,
					       unsigned long long offset)
{
	return *(volatile unsigned long long *)(state + OSUM_CTX_OFFSET + offset);
}

#endif
