#include "lkpi.h"

#define REFRESH_HZ 60ULL
#define CALL_ALIGN 16UL
#define BYTES_PER_PIXEL 4ULL

static struct drm_device *bound;
static bool alignment_logged;

static void log_alignment(void)
{
	if (alignment_logged)
		return;
	alignment_logged = true;
	_printk("lkpi: kms op stack aligned=%d\n",
		((unsigned long)__builtin_frame_address(0) % CALL_ALIGN) == 0);
}

static u64 op_ready(u64 state)
{
	u8 *base;
	u32 w;
	u32 h;
	u32 pitch;

	(void)state;
	return bound && lkpi_fbdev_target(&base, &w, &h, &pitch);
}

static u64 op_width(u64 state)
{
	u8 *base;
	u32 w;
	u32 h;
	u32 pitch;

	(void)state;
	return lkpi_fbdev_target(&base, &w, &h, &pitch) ? w : 0;
}

static u64 op_height(u64 state)
{
	u8 *base;
	u32 w;
	u32 h;
	u32 pitch;

	(void)state;
	return lkpi_fbdev_target(&base, &w, &h, &pitch) ? h : 0;
}

static u64 op_refresh(u64 state)
{
	(void)state;
	return REFRESH_HZ;
}

static bool copy_row(u64 state, u64 shm, u64 src_off, u8 *dst, u64 count)
{
	u64 done = 0;

	while (done < count) {
		u64 off = src_off + done;
		u64 in_page = off % PAGE_SIZE;
		u64 chunk = PAGE_SIZE - in_page;
		u64 frame = k_shm_frame(state, shm, off / PAGE_SIZE);

		if (!frame)
			return false;
		if (chunk > count - done)
			chunk = count - done;
		memcpy(dst + done, (const void *)(frame + in_page), chunk);
		done += chunk;
	}
	return true;
}

static u64 op_scanout(u64 state, u64 shm, u64 w, u64 h, u64 pitch)
{
	u8 *base;
	u32 fb_w;
	u32 fb_h;
	u32 fb_pitch;
	u64 cols;
	u64 rows;
	u64 y;

	log_alignment();
	if (!lkpi_fbdev_target(&base, &fb_w, &fb_h, &fb_pitch))
		return 0;
	cols = w < fb_w ? w : fb_w;
	rows = h < fb_h ? h : fb_h;
	for (y = 0; y < rows; y++) {
		if (!copy_row(state, shm, y * pitch, base + y * fb_pitch, cols * BYTES_PER_PIXEL))
			return 0;
	}
	return 1;
}

static void op_release(u64 state)
{
	(void)state;
}

void lkpi_backend_register(struct drm_device *dev)
{
	struct osum_kms_ops ops;

	ops.ready = (unsigned long long)(unsigned long)op_ready;
	ops.width = (unsigned long long)(unsigned long)op_width;
	ops.height = (unsigned long long)(unsigned long)op_height;
	ops.refresh = (unsigned long long)(unsigned long)op_refresh;
	ops.scanout = (unsigned long long)(unsigned long)op_scanout;
	ops.release = (unsigned long long)(unsigned long)op_release;
	ops.tag = (unsigned long long)(unsigned long)dev;
	if (!k_kms_register(&ops)) {
		_printk("lkpi: kms backend refused\n");
		return;
	}
	bound = dev;
	_printk("lkpi: kms backend registered\n");
}

void lkpi_backend_unregister(struct drm_device *dev)
{
	if (bound != dev)
		return;
	k_kms_unregister((unsigned long long)(unsigned long)dev);
	bound = NULL;
}
