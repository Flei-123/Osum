#include "lkpi.h"

#define BORDER 8U
#define COLOR_TL 0x00FF0000U
#define COLOR_TR 0x0000FF00U
#define COLOR_BL 0x000000FFU
#define COLOR_BR 0x00FFFFFFU
#define COLOR_BORDER 0x00FFFF00U

static struct drm_framebuffer *client_fb;
static struct drm_gem_vram_object *client_gbo;

static const struct drm_display_mode *pick_mode(const struct drm_connector *connector)
{
	int i;

	for (i = 0; i < connector->num_modes; i++) {
		if (connector->modes[i].type & DRM_MODE_TYPE_PREFERRED)
			return &connector->modes[i];
	}
	return connector->num_modes ? &connector->modes[0] : NULL;
}

static void paint(const struct drm_framebuffer *fb, const struct drm_gem_vram_object *gbo)
{
	volatile u32 *base = (volatile u32 *)((u8 *)lkpi_vram_map() + gbo->offset);
	u32 pitch = fb->pitches[0] / 4;
	u32 x;
	u32 y;

	for (y = 0; y < fb->height; y++) {
		for (x = 0; x < fb->width; x++) {
			u32 color;

			if (x < BORDER || y < BORDER || x >= fb->width - BORDER ||
			    y >= fb->height - BORDER)
				color = COLOR_BORDER;
			else if (y < fb->height / 2)
				color = x < fb->width / 2 ? COLOR_TL : COLOR_TR;
			else
				color = x < fb->width / 2 ? COLOR_BL : COLOR_BR;
			base[y * pitch + x] = color;
		}
	}
}

void drm_fbdev_ttm_setup(struct drm_device *dev, unsigned int preferred_bpp)
{
	struct drm_connector *connector = dev->mode_config.connectors[0];
	struct drm_simple_display_pipe *pipe = dev->mode_config.pipes[0];
	const struct drm_display_mode *mode;
	struct drm_mode_create_dumb dumb;
	struct drm_mode_fb_cmd2 cmd;
	struct drm_atomic_state state;
	struct drm_framebuffer *fb;

	(void)preferred_bpp;
	if (!connector || !pipe || client_fb)
		return;
	connector->funcs->fill_modes(connector, dev->mode_config.max_width,
				     dev->mode_config.max_height);
	mode = pick_mode(connector);
	if (!mode) {
		_printk("lkpi: modeset failed: no mode\n");
		return;
	}
	memset(&dumb, 0, sizeof(dumb));
	dumb.width = mode->hdisplay;
	dumb.height = mode->vdisplay;
	dumb.bpp = 32;
	if (dev->driver->dumb_create(NULL, dev, &dumb)) {
		_printk("lkpi: modeset failed: dumb buffer\n");
		return;
	}
	memset(&cmd, 0, sizeof(cmd));
	cmd.width = dumb.width;
	cmd.height = dumb.height;
	cmd.pixel_format = DRM_FORMAT_XRGB8888;
	cmd.handles[0] = dumb.handle;
	cmd.pitches[0] = dumb.pitch;
	fb = dev->mode_config.funcs->fb_create(dev, NULL, &cmd);
	if (IS_ERR(fb)) {
		_printk("lkpi: modeset failed: framebuffer\n");
		return;
	}
	client_fb = fb;
	client_gbo = drm_gem_vram_of_gem(fb->obj[0]);
	memset(&state, 0, sizeof(state));
	state.dev = dev;
	state.pipe = pipe;
	state.new_crtc.mode = *mode;
	state.new_crtc.enable = true;
	state.new_crtc.active = true;
	state.new_plane.fb = fb;
	state.new_plane.crtc_w = mode->hdisplay;
	state.new_plane.crtc_h = mode->vdisplay;
	if (dev->mode_config.funcs->atomic_check(dev, &state) ||
	    dev->mode_config.funcs->atomic_commit(dev, &state, false)) {
		_printk("lkpi: modeset failed: commit\n");
		return;
	}
	paint(fb, client_gbo);
	_printk("lkpi: modeset %ux%u ok\n", (unsigned int)mode->hdisplay,
		(unsigned int)mode->vdisplay);
}

void lkpi_fbdev_release(struct drm_device *dev)
{
	(void)dev;
	if (!client_fb)
		return;
	kfree(client_fb);
	lkpi_vram_destroy_object(client_gbo);
	client_fb = NULL;
	client_gbo = NULL;
}
