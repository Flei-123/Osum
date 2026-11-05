#include "lkpi.h"

static const u16 mode_sizes[][2] = {
	{ 640, 480 }, { 800, 600 }, { 1024, 768 }, { 1152, 864 }, { 1280, 720 },
	{ 1280, 768 }, { 1280, 800 }, { 1280, 960 }, { 1280, 1024 }, { 1360, 768 },
	{ 1366, 768 }, { 1400, 1050 }, { 1440, 900 }, { 1600, 900 }, { 1600, 1200 },
	{ 1680, 1050 }, { 1792, 1344 }, { 1856, 1392 }, { 1920, 1080 }, { 1920, 1200 },
	{ 2560, 1440 },
};

static void mode_set(struct drm_display_mode *mode, u16 h, u16 v)
{
	snprintf(mode->name, sizeof(mode->name), "%ux%u", (unsigned int)h, (unsigned int)v);
	mode->type = DRM_MODE_TYPE_DRIVER;
	mode->hdisplay = h;
	mode->vdisplay = v;
	mode->clock = (int)((u32)h * v * 60 / 1000);
}

int drm_add_modes_noedid(struct drm_connector *connector, int hdisplay, int vdisplay)
{
	unsigned int i;
	int added = 0;

	for (i = 0; i < ARRAY_SIZE(mode_sizes) && connector->num_modes < DRM_MODE_MAX_MODES; i++) {
		if (hdisplay && vdisplay &&
		    (mode_sizes[i][0] > hdisplay || mode_sizes[i][1] > vdisplay))
			continue;
		mode_set(&connector->modes[connector->num_modes++], mode_sizes[i][0],
			 mode_sizes[i][1]);
		added++;
	}
	return added;
}

void drm_set_preferred_mode(struct drm_connector *connector, int hpref, int vpref)
{
	int i;

	for (i = 0; i < connector->num_modes; i++) {
		if (connector->modes[i].hdisplay == hpref && connector->modes[i].vdisplay == vpref)
			connector->modes[i].type |= DRM_MODE_TYPE_PREFERRED;
	}
}

static bool mode_better(const struct drm_display_mode *a, const struct drm_display_mode *b)
{
	bool pref_a = a->type & DRM_MODE_TYPE_PREFERRED;
	bool pref_b = b->type & DRM_MODE_TYPE_PREFERRED;

	if (pref_a != pref_b)
		return pref_a;
	return (u32)a->hdisplay * a->vdisplay > (u32)b->hdisplay * b->vdisplay;
}

int drm_helper_probe_single_connector_modes(struct drm_connector *connector, u32 max_x,
					    u32 max_y)
{
	const struct drm_mode_config_funcs *funcs = connector->dev->mode_config.funcs;
	int kept = 0;
	int i;
	int j;

	connector->num_modes = 0;
	if (connector->helper_private && connector->helper_private->get_modes)
		connector->helper_private->get_modes(connector);
	for (i = 0; i < connector->num_modes; i++) {
		const struct drm_display_mode *mode = &connector->modes[i];

		if ((max_x && mode->hdisplay > max_x) || (max_y && mode->vdisplay > max_y))
			continue;
		if (funcs && funcs->mode_valid && funcs->mode_valid(connector->dev, mode) != MODE_OK)
			continue;
		if (kept != i)
			connector->modes[kept] = *mode;
		kept++;
	}
	connector->num_modes = kept;
	for (i = 1; i < kept; i++) {
		struct drm_display_mode key = connector->modes[i];

		for (j = i - 1; j >= 0 && mode_better(&key, &connector->modes[j]); j--)
			connector->modes[j + 1] = connector->modes[j];
		connector->modes[j + 1] = key;
	}
	return kept;
}

int drm_connector_init(struct drm_device *dev, struct drm_connector *connector,
		       const struct drm_connector_funcs *funcs, int connector_type)
{
	struct drm_mode_config *config = &dev->mode_config;

	if (config->connector_count >= DRM_MAX_PIPES)
		return -ENOSPC;
	connector->dev = dev;
	connector->funcs = funcs;
	connector->connector_type = connector_type;
	connector->num_modes = 0;
	config->connectors[config->connector_count++] = connector;
	return 0;
}

void drm_connector_cleanup(struct drm_connector *connector)
{
	struct drm_mode_config *config = &connector->dev->mode_config;
	unsigned int i;
	unsigned int kept = 0;

	if (connector->state && connector->funcs->atomic_destroy_state)
		connector->funcs->atomic_destroy_state(connector, connector->state);
	connector->state = NULL;
	for (i = 0; i < config->connector_count; i++) {
		if (config->connectors[i] != connector)
			config->connectors[kept++] = config->connectors[i];
	}
	for (i = kept; i < config->connector_count; i++)
		config->connectors[i] = NULL;
	config->connector_count = kept;
}

void drm_connector_attach_edid_property(struct drm_connector *connector)
{
	(void)connector;
}

void drm_atomic_helper_connector_reset(struct drm_connector *connector)
{
	struct drm_connector_state *state = kzalloc(sizeof(*state), GFP_KERNEL);

	kfree(connector->state);
	connector->state = state;
	if (state)
		state->connector = connector;
}

struct drm_connector_state *
drm_atomic_helper_connector_duplicate_state(struct drm_connector *connector)
{
	struct drm_connector_state *state = kzalloc(sizeof(*state), GFP_KERNEL);

	if (state && connector->state)
		*state = *connector->state;
	return state;
}

void drm_atomic_helper_connector_destroy_state(struct drm_connector *connector,
					       struct drm_connector_state *state)
{
	(void)connector;
	kfree(state);
}

void drm_mode_config_reset(struct drm_device *dev)
{
	struct drm_mode_config *config = &dev->mode_config;
	unsigned int i;

	for (i = 0; i < config->pipe_count; i++) {
		struct drm_simple_display_pipe *pipe = config->pipes[i];

		kfree(pipe->plane.state);
		kfree(pipe->crtc.state);
		pipe->plane.state = kzalloc(sizeof(*pipe->plane.state), GFP_KERNEL);
		pipe->crtc.state = kzalloc(sizeof(*pipe->crtc.state), GFP_KERNEL);
	}
	for (i = 0; i < config->connector_count; i++) {
		struct drm_connector *connector = config->connectors[i];

		if (connector->funcs->reset)
			connector->funcs->reset(connector);
	}
}

int drm_simple_display_pipe_init(struct drm_device *dev, struct drm_simple_display_pipe *pipe,
				 const struct drm_simple_display_pipe_funcs *funcs,
				 const u32 *formats, unsigned int format_count,
				 const u64 *format_modifiers, struct drm_connector *connector)
{
	struct drm_mode_config *config = &dev->mode_config;

	(void)format_modifiers;
	if (config->pipe_count >= DRM_MAX_PIPES)
		return -ENOSPC;
	pipe->crtc.dev = dev;
	pipe->plane.dev = dev;
	pipe->connector = connector;
	pipe->funcs = funcs;
	pipe->formats = formats;
	pipe->format_count = format_count;
	config->pipes[config->pipe_count++] = pipe;
	return 0;
}

static bool format_listed(const struct drm_simple_display_pipe *pipe, u32 format)
{
	unsigned int i;

	for (i = 0; i < pipe->format_count; i++) {
		if (pipe->formats[i] == format)
			return true;
	}
	return false;
}

int drm_atomic_helper_check(struct drm_device *dev, struct drm_atomic_state *state)
{
	const struct drm_framebuffer *fb = state->new_plane.fb;
	const struct drm_display_mode *mode = &state->new_crtc.mode;

	(void)dev;
	if (!state->pipe || !state->pipe->funcs)
		return -EINVAL;
	if (!state->new_crtc.enable)
		return 0;
	if (!fb || !format_listed(state->pipe, fb->format->format))
		return -EINVAL;
	if (!mode->hdisplay || !mode->vdisplay || fb->width < mode->hdisplay ||
	    fb->height < mode->vdisplay)
		return -EINVAL;
	return 0;
}

int drm_atomic_helper_commit(struct drm_device *dev, struct drm_atomic_state *state,
			     bool nonblock)
{
	struct drm_simple_display_pipe *pipe = state->pipe;
	struct drm_plane_state old_plane = *pipe->plane.state;
	bool was_active = pipe->crtc.state->active;
	int ret;

	(void)dev;
	(void)nonblock;
	if (pipe->funcs->prepare_fb) {
		ret = pipe->funcs->prepare_fb(pipe, &state->new_plane);
		if (ret)
			return ret;
	}
	*pipe->crtc.state = state->new_crtc;
	*pipe->plane.state = state->new_plane;
	if (state->new_crtc.active && !was_active)
		pipe->funcs->enable(pipe, pipe->crtc.state, pipe->plane.state);
	else if (state->new_crtc.active)
		pipe->funcs->update(pipe, &old_plane);
	else if (was_active)
		pipe->funcs->disable(pipe);
	if (pipe->funcs->cleanup_fb && old_plane.fb)
		pipe->funcs->cleanup_fb(pipe, &old_plane);
	return 0;
}

void drm_atomic_helper_shutdown(struct drm_device *dev)
{
	struct drm_mode_config *config = &dev->mode_config;
	unsigned int i;

	for (i = 0; i < config->pipe_count; i++) {
		struct drm_simple_display_pipe *pipe = config->pipes[i];

		if (!pipe->crtc.state || !pipe->crtc.state->active)
			continue;
		pipe->funcs->disable(pipe);
		if (pipe->funcs->cleanup_fb && pipe->plane.state->fb)
			pipe->funcs->cleanup_fb(pipe, pipe->plane.state);
		pipe->crtc.state->active = false;
		pipe->crtc.state->enable = false;
		pipe->plane.state->fb = NULL;
	}
}

void lkpi_kms_release(struct drm_device *dev)
{
	struct drm_mode_config *config = &dev->mode_config;
	unsigned int count = config->connector_count;
	unsigned int i;

	for (i = 0; i < config->pipe_count; i++) {
		kfree(config->pipes[i]->plane.state);
		kfree(config->pipes[i]->crtc.state);
		config->pipes[i]->plane.state = NULL;
		config->pipes[i]->crtc.state = NULL;
	}
	while (count--) {
		struct drm_connector *connector = config->connectors[count];

		if (connector && connector->funcs->destroy)
			connector->funcs->destroy(connector);
	}
	config->connector_count = 0;
	config->pipe_count = 0;
}

int drm_edid_header_is_valid(const void *raw_edid)
{
	static const u8 header[8] = { 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00 };
	const u8 *raw = raw_edid;
	int score = 0;
	int i;

	for (i = 0; i < 8; i++) {
		if (raw[i] == header[i])
			score++;
	}
	return score;
}

const struct drm_edid *drm_edid_read_custom(struct drm_connector *connector,
					    int (*read_block)(void *context, u8 *buf,
							      unsigned int block, size_t len),
					    void *context)
{
	(void)connector;
	(void)read_block;
	(void)context;
	return NULL;
}

void drm_edid_free(const struct drm_edid *edid)
{
	(void)edid;
}

int drm_edid_connector_update(struct drm_connector *connector, const struct drm_edid *edid)
{
	(void)connector;
	(void)edid;
	return 0;
}

int drm_edid_connector_add_modes(struct drm_connector *connector)
{
	(void)connector;
	return 0;
}
