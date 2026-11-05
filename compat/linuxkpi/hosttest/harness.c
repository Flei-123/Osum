// SPDX-License-Identifier: GPL-2.0-only
#include <osum/osum_if.h>

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef long long s64;

int shim_module_init(u64 state);
void shim_module_exit(u64 state);
int driver_module_init(u64 state);
void driver_module_exit(u64 state);

#define PAGE 4096ULL
#define VRAM_BYTES (16ULL << 20)
#define GUARD_BYTES (64ULL << 10)
#define REG_BYTES 4096ULL
#define STATE_BYTES (OSUM_CTX_OFFSET + 256)
#define POOL_FRAMES 8192ULL
#define MAX_RUNS 8
#define MAX_RUN_FRAMES 1024ULL
#define LOG_BYTES 65536
#define GUARD_BYTE 0xA5
#define DISPI_BASE 0x500
#define REG_ID 0
#define REG_XRES 1
#define REG_YRES 2
#define REG_BPP 3
#define REG_ENABLE 4
#define REG_BANK 5
#define REG_VIRT_WIDTH 6
#define REG_VIRT_HEIGHT 7
#define REG_X_OFFSET 8
#define REG_Y_OFFSET 9
#define REG_VIDEO_MEMORY_64K 10
#define QEXT_SIZE 0x600
#define QEXT_ENDIAN 0x604
#define ENDIAN_LITTLE 0x1e1e1e1eU
#define COLOR_TL 0x00FF0000U
#define COLOR_TR 0x0000FF00U
#define COLOR_BL 0x000000FFU
#define COLOR_BR 0x00FFFFFFU
#define COLOR_BORDER 0x00FFFF00U
#define BORDER 8U
#define HW_OK 0ULL
#define HW_RANGE 3ULL
#define CMD_MASK 0x407ULL

struct variant {
	const char *name;
	u64 abi;
	u64 vendor;
	u64 revision;
	u16 dispi_id;
	u64 bar0_reported;
};

static const struct variant variants[] = {
	{ "ok", 1, 0x1234, 2, 0xB0C5, VRAM_BYTES },
	{ "rev1", 1, 0x1234, 1, 0xB0C5, VRAM_BYTES },
	{ "badid", 1, 0x1234, 2, 0x1234, VRAM_BYTES },
	{ "bar0small", 1, 0x1234, 2, 0xB0C5, 2ULL << 20 },
	{ "bar0min", 1, 0x1234, 2, 0xB0C5, 4ULL << 20 },
	{ "badvendor", 1, 0x1AF4, 2, 0xB0C5, VRAM_BYTES },
	{ "abi2", 2, 0x1234, 2, 0xB0C5, VRAM_BYTES },
};

struct run {
	u64 addr;
	u64 frames;
};

static u8 state_area[STATE_BYTES] __attribute__((aligned(4096)));
static u8 vram_area[VRAM_BYTES + GUARD_BYTES] __attribute__((aligned(4096)));
static u8 reg_area[REG_BYTES] __attribute__((aligned(4096)));
static u8 frame_pool[POOL_FRAMES * PAGE] __attribute__((aligned(4096)));
static char log_buf[LOG_BYTES];
static u64 log_len;
static const struct variant *cur;
static struct run runs[MAX_RUNS];
static u64 pool_next;
static u64 command_reg;
static u64 ioremap_denied;
static u64 frames_denied;

static long sys_write(int fd, const void *buf, u64 count)
{
	long ret;

	__asm__ volatile("syscall" : "=a"(ret) : "0"(1L), "D"((long)fd), "S"(buf), "d"(count)
			 : "rcx", "r11", "memory");
	return ret;
}

static void sys_exit(int code)
{
	for (;;)
		__asm__ volatile("syscall" : : "a"(231L), "D"((long)code) : "rcx", "r11", "memory");
}

static u64 str_len(const char *s)
{
	u64 n = 0;

	while (s[n])
		n++;
	return n;
}

static int str_eq(const char *a, const char *b)
{
	while (*a && *a == *b) {
		a++;
		b++;
	}
	return *a == *b;
}

static void out(const char *s)
{
	sys_write(1, s, str_len(s));
}

static void out_dec(s64 v)
{
	char tmp[24];
	int n = 0;
	u64 u = v < 0 ? (u64)(-v) : (u64)v;

	if (v < 0)
		out("-");
	if (u == 0)
		tmp[n++] = '0';
	while (u) {
		tmp[n++] = (char)('0' + u % 10);
		u /= 10;
	}
	while (n)
		sys_write(1, &tmp[--n], 1);
}

static void kv(const char *key, s64 value)
{
	out(" ");
	out(key);
	out("=");
	out_dec(value);
}

static int log_has(const char *needle)
{
	u64 n = str_len(needle);
	u64 i;
	u64 j;

	for (i = 0; i + n <= log_len; i++) {
		for (j = 0; j < n && log_buf[i + j] == needle[j]; j++)
			;
		if (j == n)
			return 1;
	}
	return 0;
}

static u16 reg_read(u32 reg)
{
	return *(volatile u16 *)(reg_area + DISPI_BASE + 2 * reg);
}

static void reg_write(u32 reg, u16 value)
{
	*(volatile u16 *)(reg_area + DISPI_BASE + 2 * reg) = value;
}

static u64 open_frames(void)
{
	u64 total = 0;
	int i;

	for (i = 0; i < MAX_RUNS; i++)
		total += runs[i].frames;
	return total;
}

u64 k_abi(void)
{
	return cur->abi;
}

void k_puts(const char *text)
{
	u64 n = str_len(text);
	u64 i;

	for (i = 0; i < n && log_len + 1 < LOG_BYTES; i++)
		log_buf[log_len++] = text[i];
	out("  | ");
	out(text);
}

u64 k_pcicfg_read(u64 offset)
{
	if (offset >= 256 || (offset & 3))
		return 0xFFFFFFFFULL;
	if (offset == 0)
		return cur->vendor | (0x1111ULL << 16);
	if (offset == 4)
		return command_reg;
	if (offset == 8)
		return 0x03800000ULL | cur->revision;
	return 0;
}

void k_pcicfg_write(u64 offset, u64 value)
{
	if (offset == 4)
		command_reg = (command_reg & ~CMD_MASK) | (value & CMD_MASK);
}

u64 k_pcibar(u64 index, u64 *info)
{
	if (index >= OSUM_BAR_COUNT)
		return HW_RANGE;
	info[0] = 0;
	info[1] = 0;
	info[2] = 0;
	if (index == 0) {
		info[0] = (u64)vram_area;
		info[1] = cur->bar0_reported;
		info[2] = OSUM_BAR_PREFETCH;
	} else if (index == 2) {
		info[0] = (u64)reg_area;
		info[1] = REG_BYTES;
	}
	return HW_OK;
}

u64 k_ioremap(u64 phys, u64 size)
{
	u64 vram_end = (u64)vram_area + cur->bar0_reported;
	u64 reg_end = (u64)reg_area + REG_BYTES;

	if (size && phys + size >= phys &&
	    ((phys >= (u64)vram_area && phys + size <= vram_end) ||
	     (phys >= (u64)reg_area && phys + size <= reg_end)))
		return phys;
	ioremap_denied++;
	return 0;
}

u64 k_frames(u64 count)
{
	u64 base;
	u64 i;
	int slot;

	if (count == 0 || count > MAX_RUN_FRAMES || pool_next + count > POOL_FRAMES)
		return 0;
	for (slot = 0; slot < MAX_RUNS && runs[slot].frames; slot++)
		;
	if (slot == MAX_RUNS)
		return 0;
	base = (u64)frame_pool + pool_next * PAGE;
	for (i = 0; i < count * PAGE; i++)
		((volatile u8 *)base)[i] = 0;
	runs[slot].addr = base;
	runs[slot].frames = count;
	pool_next += count;
	return base;
}

void k_frames_free(u64 addr, u64 count)
{
	int i;

	for (i = 0; i < MAX_RUNS; i++) {
		if (runs[i].frames == count && runs[i].addr == addr && count) {
			runs[i].frames = 0;
			runs[i].addr = 0;
			return;
		}
	}
	frames_denied++;
}

static void ctx_set(u64 offset, u64 value)
{
	*(volatile u64 *)(state_area + OSUM_CTX_OFFSET + offset) = value;
}

static u32 expected_pixel(u32 x, u32 y, u32 w, u32 h)
{
	if (x < BORDER || y < BORDER || x >= w - BORDER || y >= h - BORDER)
		return COLOR_BORDER;
	if (y < h / 2)
		return x < w / 2 ? COLOR_TL : COLOR_TR;
	return x < w / 2 ? COLOR_BL : COLOR_BR;
}

static s64 pixel_mismatches(void)
{
	u32 w = reg_read(REG_XRES);
	u32 h = reg_read(REG_YRES);
	u32 vw = reg_read(REG_VIRT_WIDTH);
	u32 xo = reg_read(REG_X_OFFSET);
	u32 yo = reg_read(REG_Y_OFFSET);
	u64 first;
	u64 bad = 0;
	u32 x;
	u32 y;

	if (reg_read(REG_ENABLE) != 0x41 || reg_read(REG_BPP) != 32 || !w || !h || vw < w)
		return -1;
	first = ((u64)yo * vw + xo) * 4;
	if (first + ((u64)(h - 1) * vw + w) * 4 > cur->bar0_reported)
		return -2;
	for (y = 0; y < h; y++) {
		for (x = 0; x < w; x++) {
			u32 got = *(volatile u32 *)(vram_area + first + ((u64)y * vw + x) * 4);

			if (got != expected_pixel(x, y, w, h))
				bad++;
		}
	}
	return (s64)bad;
}

static u64 guard_damage(void)
{
	u64 bad = 0;
	u64 i;

	for (i = cur->bar0_reported; i < sizeof(vram_area); i++) {
		if (vram_area[i] != GUARD_BYTE)
			bad++;
	}
	return bad;
}

static void setup(void)
{
	u64 i;

	for (i = cur->bar0_reported; i < sizeof(vram_area); i++)
		vram_area[i] = GUARD_BYTE;
	reg_write(REG_ID, cur->dispi_id);
	reg_write(REG_VIDEO_MEMORY_64K, (u16)(VRAM_BYTES >> 16));
	*(volatile u32 *)(reg_area + QEXT_SIZE) = 8;
	*(volatile u32 *)(reg_area + QEXT_ENDIAN) = 0;
	ctx_set(OSUM_CTX_VENDOR, cur->vendor);
	ctx_set(OSUM_CTX_DEVICE, 0x1111);
	ctx_set(OSUM_CTX_SUBSYSTEM, 0x11001af4ULL);
	ctx_set(OSUM_CTX_CLASS, 0x0380);
	ctx_set(OSUM_CTX_PROGIF, 0);
	ctx_set(OSUM_CTX_BDF, 0x18);
	ctx_set(OSUM_CTX_IRQ, 11);
	ctx_set(OSUM_CTX_PCI_INDEX, 0);
}

static void run_variant(const struct variant *v)
{
	u64 state = (u64)state_area;
	int shim_rc;
	int drv_rc;
	s64 pix;
	u64 guard;

	cur = v;
	setup();
	out("harness: variant ");
	out(v->name);
	out("\n");
	shim_rc = shim_module_init(state);
	drv_rc = driver_module_init(state);
	pix = pixel_mismatches();
	guard = guard_damage();
	out("harness: result ");
	out(v->name);
	kv("shim_rc", shim_rc);
	kv("drv_rc", drv_rc);
	kv("xres", reg_read(REG_XRES));
	kv("yres", reg_read(REG_YRES));
	kv("bpp", reg_read(REG_BPP));
	kv("enable", reg_read(REG_ENABLE));
	kv("vwidth", reg_read(REG_VIRT_WIDTH));
	kv("vheight", reg_read(REG_VIRT_HEIGHT));
	kv("xoff", reg_read(REG_X_OFFSET));
	kv("yoff", reg_read(REG_Y_OFFSET));
	kv("endian", *(volatile u32 *)(reg_area + QEXT_ENDIAN) == ENDIAN_LITTLE);
	kv("cmd", (s64)(command_reg & 3));
	kv("pixbad", pix);
	kv("guard", (s64)guard);
	kv("found", log_has("[drm] Found bochs VGA, ID 0xb0c5"));
	kv("modeset", log_has("lkpi: modeset 1024x768 ok"));
	kv("denied", (s64)ioremap_denied);
	out("\n");
	driver_module_exit(state);
	shim_module_exit(state);
	out("harness: exit ");
	out(v->name);
	kv("open", (s64)open_frames());
	kv("freedenied", (s64)frames_denied);
	out("\n");
}

static void reset_state(void)
{
	u64 i;

	for (i = 0; i < sizeof(state_area); i++)
		state_area[i] = 0;
	for (i = 0; i < REG_BYTES; i++)
		reg_area[i] = 0;
	for (i = 0; i < MAX_RUNS; i++) {
		runs[i].addr = 0;
		runs[i].frames = 0;
	}
	pool_next = 0;
	command_reg = 0;
	ioremap_denied = 0;
	frames_denied = 0;
	log_len = 0;
}

void harness_main(u64 *sp)
{
	u64 argc = sp[0];
	char **argv = (char **)(sp + 1);
	u64 i;

	if (argc < 2) {
		out("harness: usage: harness <variant>\n");
		sys_exit(2);
	}
	for (i = 0; i < sizeof(variants) / sizeof(variants[0]); i++) {
		if (str_eq(argv[1], variants[i].name)) {
			reset_state();
			run_variant(&variants[i]);
			sys_exit(0);
		}
	}
	out("harness: unknown variant\n");
	sys_exit(2);
}

__asm__(".globl _start\n"
	"_start:\n"
	"\txor %ebp, %ebp\n"
	"\tmov %rsp, %rdi\n"
	"\tand $-16, %rsp\n"
	"\tcall harness_main\n");
