#ifndef LKPI_DRM_CORE_H
#define LKPI_DRM_CORE_H

#include <linux/kernel.h>
#include <linux/pci.h>

#define DRIVER_GEM 0x1U
#define DRIVER_MODESET 0x2000U
#define DRIVER_ATOMIC 0x10000U

#define DRM_MODE_TYPE_PREFERRED 0x8U
#define DRM_MODE_TYPE_DRIVER 0x40U
#define DRM_MODE_CONNECTOR_VIRTUAL 15
#define DRM_MODE_MAX_MODES 24
#define DRM_MAX_PIPES 4
#define EDID_LENGTH 128

#define fourcc_code(a, b, c, d) \
	((u32)(a) | ((u32)(b) << 8) | ((u32)(c) << 16) | ((u32)(d) << 24))
#define DRM_FORMAT_XRGB8888 fourcc_code('X', 'R', '2', '4')
#define DRM_FORMAT_BGRX8888 fourcc_code('B', 'X', '2', '4')

enum drm_mode_status {
	MODE_OK = 0,
	MODE_MEM = 1,
	MODE_BAD = 2,
};

struct drm_device;
struct drm_file;
struct drm_connector;
struct drm_edid;
struct drm_simple_display_pipe;

struct file_operations {
	struct module *owner;
};

struct drm_display_mode {
	char name[16];
	u32 type;
	u16 hdisplay;
	u16 vdisplay;
	int clock;
};

struct drm_format_info {
	u32 format;
	u8 depth;
	u8 num_planes;
	u8 cpp[4];
};

struct drm_mode_fb_cmd2 {
	u32 width;
	u32 height;
	u32 pixel_format;
	u32 flags;
	u32 handles[4];
	u32 pitches[4];
	u32 offsets[4];
};

struct drm_mode_create_dumb {
	u32 height;
	u32 width;
	u32 bpp;
	u32 flags;
	u32 handle;
	u32 pitch;
	u64 size;
};

struct drm_gem_object {
	struct drm_device *dev;
	size_t size;
};

struct drm_gem_vram_object {
	struct drm_gem_object gem;
	s64 offset;
	unsigned int pin_count;
	bool used;
};

struct drm_framebuffer {
	struct drm_device *dev;
	const struct drm_format_info *format;
	unsigned int pitches[4];
	unsigned int offsets[4];
	unsigned int width;
	unsigned int height;
	struct drm_gem_object *obj[4];
};

struct drm_plane_state {
	struct drm_framebuffer *fb;
	int crtc_x;
	int crtc_y;
	unsigned int crtc_w;
	unsigned int crtc_h;
};

struct drm_crtc_state {
	struct drm_display_mode mode;
	bool enable;
	bool active;
};

struct drm_plane {
	struct drm_device *dev;
	struct drm_plane_state *state;
};

struct drm_crtc {
	struct drm_device *dev;
	struct drm_crtc_state *state;
};

struct drm_connector_state {
	struct drm_connector *connector;
};

struct drm_connector_funcs {
	int (*fill_modes)(struct drm_connector *connector, u32 max_x, u32 max_y);
	void (*destroy)(struct drm_connector *connector);
	void (*reset)(struct drm_connector *connector);
	struct drm_connector_state *(*atomic_duplicate_state)(struct drm_connector *connector);
	void (*atomic_destroy_state)(struct drm_connector *connector,
				     struct drm_connector_state *state);
};

struct drm_connector_helper_funcs {
	int (*get_modes)(struct drm_connector *connector);
};

struct drm_connector {
	struct drm_device *dev;
	const struct drm_connector_funcs *funcs;
	const struct drm_connector_helper_funcs *helper_private;
	struct drm_connector_state *state;
	int connector_type;
	struct drm_display_mode modes[DRM_MODE_MAX_MODES];
	int num_modes;
};

struct drm_simple_display_pipe_funcs {
	enum drm_mode_status (*mode_valid)(struct drm_simple_display_pipe *pipe,
					   const struct drm_display_mode *mode);
	void (*enable)(struct drm_simple_display_pipe *pipe,
		       struct drm_crtc_state *crtc_state,
		       struct drm_plane_state *plane_state);
	void (*disable)(struct drm_simple_display_pipe *pipe);
	void (*update)(struct drm_simple_display_pipe *pipe,
		       struct drm_plane_state *old_state);
	int (*prepare_fb)(struct drm_simple_display_pipe *pipe,
			  struct drm_plane_state *new_state);
	void (*cleanup_fb)(struct drm_simple_display_pipe *pipe,
			   struct drm_plane_state *old_state);
};

struct drm_simple_display_pipe {
	struct drm_crtc crtc;
	struct drm_plane plane;
	struct drm_connector *connector;
	const struct drm_simple_display_pipe_funcs *funcs;
	const u32 *formats;
	unsigned int format_count;
};

struct drm_atomic_state {
	struct drm_device *dev;
	struct drm_simple_display_pipe *pipe;
	struct drm_crtc_state new_crtc;
	struct drm_plane_state new_plane;
};

struct drm_mode_config_funcs {
	struct drm_framebuffer *(*fb_create)(struct drm_device *dev, struct drm_file *file,
					     const struct drm_mode_fb_cmd2 *cmd);
	enum drm_mode_status (*mode_valid)(struct drm_device *dev,
					   const struct drm_display_mode *mode);
	int (*atomic_check)(struct drm_device *dev, struct drm_atomic_state *state);
	int (*atomic_commit)(struct drm_device *dev, struct drm_atomic_state *state,
			     bool nonblock);
};

struct drm_mode_config {
	int min_width;
	int min_height;
	int max_width;
	int max_height;
	unsigned int preferred_depth;
	bool prefer_shadow;
	bool quirk_addfb_prefer_host_byte_order;
	const struct drm_mode_config_funcs *funcs;
	struct drm_connector *connectors[DRM_MAX_PIPES];
	unsigned int connector_count;
	struct drm_simple_display_pipe *pipes[DRM_MAX_PIPES];
	unsigned int pipe_count;
};

struct drm_driver {
	u32 driver_features;
	const struct file_operations *fops;
	const char *name;
	const char *desc;
	const char *date;
	int major;
	int minor;
	int (*dumb_create)(struct drm_file *file, struct drm_device *dev,
			   struct drm_mode_create_dumb *args);
};

struct drm_managed_entry;

struct drm_device {
	struct device *dev;
	const struct drm_driver *driver;
	void *dev_private;
	struct drm_mode_config mode_config;
	struct drm_managed_entry *managed;
	int refcount;
	bool registered;
	bool unplugged;
};

#define DEFINE_DRM_GEM_FOPS(name) \
	static const struct file_operations name = { .owner = THIS_MODULE }
#define DRM_GEM_VRAM_DRIVER .dumb_create = drm_gem_vram_driver_dumb_create

#define DRM_INFO(fmt, ...) _printk("[drm] " fmt, ##__VA_ARGS__)
#define DRM_WARN(fmt, ...) _printk("[drm] WARNING " fmt, ##__VA_ARGS__)
#define DRM_ERROR(fmt, ...) _printk("[drm:%s] *ERROR* " fmt, __func__, ##__VA_ARGS__)
#define DRM_DEBUG(fmt, ...) no_printk(fmt, ##__VA_ARGS__)
#define DRM_DEBUG_DRIVER(fmt, ...) no_printk(fmt, ##__VA_ARGS__)

static inline bool drm_firmware_drivers_only(void)
{
	return false;
}

static inline void drm_connector_helper_add(struct drm_connector *connector,
					    const struct drm_connector_helper_funcs *funcs)
{
	connector->helper_private = funcs;
}

static inline struct drm_gem_vram_object *drm_gem_vram_of_gem(struct drm_gem_object *gem)
{
	return container_of(gem, struct drm_gem_vram_object, gem);
}

struct drm_device *drm_dev_alloc(const struct drm_driver *driver, struct device *parent);
int drm_dev_register(struct drm_device *dev, unsigned long flags);
void drm_dev_unplug(struct drm_device *dev);
void drm_dev_put(struct drm_device *dev);
bool drm_dev_enter(struct drm_device *dev, int *idx);
void drm_dev_exit(int idx);
void *drmm_kzalloc(struct drm_device *dev, size_t size, gfp_t flags);
int drmm_mode_config_init(struct drm_device *dev);
int drm_aperture_remove_conflicting_pci_framebuffers(struct pci_dev *pdev,
						     const struct drm_driver *driver);

void drm_mode_config_reset(struct drm_device *dev);
int drm_connector_init(struct drm_device *dev, struct drm_connector *connector,
		       const struct drm_connector_funcs *funcs, int connector_type);
void drm_connector_cleanup(struct drm_connector *connector);
void drm_connector_attach_edid_property(struct drm_connector *connector);
int drm_helper_probe_single_connector_modes(struct drm_connector *connector, u32 max_x,
					    u32 max_y);
int drm_simple_display_pipe_init(struct drm_device *dev, struct drm_simple_display_pipe *pipe,
				 const struct drm_simple_display_pipe_funcs *funcs,
				 const u32 *formats, unsigned int format_count,
				 const u64 *format_modifiers, struct drm_connector *connector);

void drm_atomic_helper_connector_reset(struct drm_connector *connector);
struct drm_connector_state *
drm_atomic_helper_connector_duplicate_state(struct drm_connector *connector);
void drm_atomic_helper_connector_destroy_state(struct drm_connector *connector,
					       struct drm_connector_state *state);
int drm_atomic_helper_check(struct drm_device *dev, struct drm_atomic_state *state);
int drm_atomic_helper_commit(struct drm_device *dev, struct drm_atomic_state *state,
			     bool nonblock);
void drm_atomic_helper_shutdown(struct drm_device *dev);

int drm_edid_header_is_valid(const void *raw_edid);
const struct drm_edid *drm_edid_read_custom(struct drm_connector *connector,
					    int (*read_block)(void *context, u8 *buf,
							      unsigned int block, size_t len),
					    void *context);
void drm_edid_free(const struct drm_edid *edid);
int drm_edid_connector_update(struct drm_connector *connector, const struct drm_edid *edid);
int drm_edid_connector_add_modes(struct drm_connector *connector);
int drm_add_modes_noedid(struct drm_connector *connector, int hdisplay, int vdisplay);
void drm_set_preferred_mode(struct drm_connector *connector, int hpref, int vpref);

int drmm_vram_helper_init(struct drm_device *dev, unsigned long long vram_base,
			  size_t vram_size);
enum drm_mode_status drm_vram_helper_mode_valid(struct drm_device *dev,
						const struct drm_display_mode *mode);
int drm_gem_vram_driver_dumb_create(struct drm_file *file, struct drm_device *dev,
				    struct drm_mode_create_dumb *args);
int drm_gem_vram_simple_display_pipe_prepare_fb(struct drm_simple_display_pipe *pipe,
						struct drm_plane_state *new_state);
void drm_gem_vram_simple_display_pipe_cleanup_fb(struct drm_simple_display_pipe *pipe,
						 struct drm_plane_state *old_state);
s64 drm_gem_vram_offset(struct drm_gem_vram_object *gbo);
struct drm_framebuffer *drm_gem_fb_create(struct drm_device *dev, struct drm_file *file,
					  const struct drm_mode_fb_cmd2 *cmd);

void drm_fbdev_ttm_setup(struct drm_device *dev, unsigned int preferred_bpp);

#endif
