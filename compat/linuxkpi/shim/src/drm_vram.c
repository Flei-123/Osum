#include "lkpi.h"

#define VRAM_OBJECTS 8

static struct {
	void *map;
	u64 base;
	size_t size;
	struct drm_gem_vram_object objects[VRAM_OBJECTS];
} vram;

static const struct drm_format_info xrgb8888_info = {
	DRM_FORMAT_XRGB8888, 24, 1, { 4, 0, 0, 0 }
};
static const struct drm_format_info bgrx8888_info = {
	DRM_FORMAT_BGRX8888, 24, 1, { 4, 0, 0, 0 }
};

void *lkpi_vram_map(void)
{
	return vram.map;
}

int drmm_vram_helper_init(struct drm_device *dev, unsigned long long vram_base, size_t vram_size)
{
	(void)dev;
	memset(&vram, 0, sizeof(vram));
	vram.map = ioremap(vram_base, vram_size);
	if (!vram.map)
		return -ENOMEM;
	vram.base = vram_base;
	vram.size = vram_size;
	return 0;
}

enum drm_mode_status drm_vram_helper_mode_valid(struct drm_device *dev,
						const struct drm_display_mode *mode)
{
	u64 pages;

	(void)dev;
	if (!vram.map)
		return MODE_BAD;
	pages = ((u64)mode->hdisplay * mode->vdisplay * 4 + PAGE_SIZE - 1) >> PAGE_SHIFT;
	return pages > ((vram.size / 2) >> PAGE_SHIFT) ? MODE_MEM : MODE_OK;
}

static bool range_free(u64 start, u64 size)
{
	unsigned int i;

	for (i = 0; i < VRAM_OBJECTS; i++) {
		const struct drm_gem_vram_object *o = &vram.objects[i];

		if (o->used && start < (u64)o->offset + o->gem.size && (u64)o->offset < start + size)
			return false;
	}
	return true;
}

int lkpi_vram_create_object(struct drm_device *dev, size_t size,
			    struct drm_gem_vram_object **out, u32 *handle)
{
	struct drm_gem_vram_object *gbo;
	u64 best = ~0ULL;
	unsigned int slot;
	unsigned int i;

	for (slot = 0; slot < VRAM_OBJECTS && vram.objects[slot].used; slot++)
		;
	if (slot == VRAM_OBJECTS)
		return -ENOSPC;
	size = PAGE_ALIGN(size);
	if (size == 0 || size > vram.size)
		return -EINVAL;
	for (i = 0; i <= VRAM_OBJECTS; i++) {
		u64 cand = 0;

		if (i < VRAM_OBJECTS) {
			if (!vram.objects[i].used)
				continue;
			cand = (u64)vram.objects[i].offset + vram.objects[i].gem.size;
		}
		if (cand < best && cand + size <= vram.size && range_free(cand, size))
			best = cand;
	}
	if (best == ~0ULL)
		return -ENOSPC;
	gbo = &vram.objects[slot];
	memset(gbo, 0, sizeof(*gbo));
	gbo->gem.dev = dev;
	gbo->gem.size = size;
	gbo->offset = (s64)best;
	gbo->used = true;
	*out = gbo;
	*handle = slot + 1;
	return 0;
}

void lkpi_vram_destroy_object(struct drm_gem_vram_object *gbo)
{
	gbo->used = false;
	gbo->pin_count = 0;
}

int drm_gem_vram_driver_dumb_create(struct drm_file *file, struct drm_device *dev,
				    struct drm_mode_create_dumb *args)
{
	struct drm_gem_vram_object *gbo;
	u32 pitch;
	int ret;

	(void)file;
	if (!args->width || !args->height || args->bpp < 8 || args->bpp > 32)
		return -EINVAL;
	pitch = args->width * ((args->bpp + 7) / 8);
	ret = lkpi_vram_create_object(dev, (size_t)pitch * args->height, &gbo, &args->handle);
	if (ret)
		return ret;
	args->pitch = pitch;
	args->size = gbo->gem.size;
	return 0;
}

int drm_gem_vram_simple_display_pipe_prepare_fb(struct drm_simple_display_pipe *pipe,
						struct drm_plane_state *new_state)
{
	(void)pipe;
	if (new_state->fb)
		drm_gem_vram_of_gem(new_state->fb->obj[0])->pin_count++;
	return 0;
}

void drm_gem_vram_simple_display_pipe_cleanup_fb(struct drm_simple_display_pipe *pipe,
						 struct drm_plane_state *old_state)
{
	struct drm_gem_vram_object *gbo;

	(void)pipe;
	if (!old_state->fb)
		return;
	gbo = drm_gem_vram_of_gem(old_state->fb->obj[0]);
	if (gbo->pin_count)
		gbo->pin_count--;
}

s64 drm_gem_vram_offset(struct drm_gem_vram_object *gbo)
{
	return gbo->pin_count ? gbo->offset : -ENODEV;
}

struct drm_framebuffer *drm_gem_fb_create(struct drm_device *dev, struct drm_file *file,
					  const struct drm_mode_fb_cmd2 *cmd)
{
	const struct drm_format_info *info;
	struct drm_gem_vram_object *gbo;
	struct drm_framebuffer *fb;

	(void)file;
	if (cmd->pixel_format == DRM_FORMAT_XRGB8888)
		info = &xrgb8888_info;
	else if (cmd->pixel_format == DRM_FORMAT_BGRX8888)
		info = &bgrx8888_info;
	else
		return ERR_PTR(-EINVAL);
	if (cmd->handles[0] == 0 || cmd->handles[0] > VRAM_OBJECTS ||
	    !vram.objects[cmd->handles[0] - 1].used)
		return ERR_PTR(-ENOENT);
	gbo = &vram.objects[cmd->handles[0] - 1];
	if (!cmd->width || !cmd->height || cmd->pitches[0] < cmd->width * 4 ||
	    (u64)cmd->pitches[0] * cmd->height + cmd->offsets[0] > gbo->gem.size)
		return ERR_PTR(-EINVAL);
	fb = kzalloc(sizeof(*fb), GFP_KERNEL);
	if (!fb)
		return ERR_PTR(-ENOMEM);
	fb->dev = dev;
	fb->format = info;
	fb->width = cmd->width;
	fb->height = cmd->height;
	fb->pitches[0] = cmd->pitches[0];
	fb->offsets[0] = cmd->offsets[0];
	fb->obj[0] = &gbo->gem;
	return fb;
}

void lkpi_vram_release(struct drm_device *dev)
{
	(void)dev;
	if (vram.map)
		iounmap(vram.map);
	memset(&vram, 0, sizeof(vram));
}
