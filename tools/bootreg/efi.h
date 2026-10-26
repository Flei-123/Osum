#ifndef BOOTREG_EFI_H
#define BOOTREG_EFI_H

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef u64 uintn;
typedef void *handle_t;

#define EFIAPI __attribute__((ms_abi))
#define ERR(n) (0x8000000000000000ULL | (n))
#define EFI_SUCCESS 0ULL
#define EFI_INVALID_PARAMETER ERR(2)
#define EFI_BUFFER_TOO_SMALL ERR(5)
#define EFI_DEVICE_ERROR ERR(7)
#define EFI_OUT_OF_RESOURCES ERR(9)
#define EFI_NOT_FOUND ERR(14)
#define EFI_ABORTED ERR(21)
#define EFI_COMPROMISED_DATA ERR(33)

#define VAR_NV 1u
#define VAR_BS 2u
#define VAR_RT 4u
#define VAR_ALL (VAR_NV | VAR_BS | VAR_RT)
#define LOAD_OPTION_ACTIVE 1u
#define FILE_MODE_READ 1ULL
#define LOCATE_BY_PROTOCOL 2u

typedef struct {
    u32 a;
    u16 b;
    u16 c;
    u8 d[8];
} guid_t;

typedef struct text_out {
    void *reset;
    u64 (EFIAPI *output_string)(struct text_out *, u16 *);
} text_out_t;

typedef struct {
    u8 hdr[24];
    void *fill[13];
    void *install_protocol;
    void *reinstall_protocol;
    void *uninstall_protocol;
    u64 (EFIAPI *handle_protocol)(handle_t, const guid_t *, void **);
    void *reserved;
    void *register_notify;
    u64 (EFIAPI *locate_handle)(u32, const guid_t *, void *, uintn *, handle_t *);
    void *locate_device_path;
    void *install_config;
    void *load_image;
    void *start_image;
    void *exit;
    void *unload_image;
    void *exit_boot_services;
    void *next_monotonic;
    u64 (EFIAPI *stall)(uintn);
} boot_services_t;

typedef struct {
    u8 hdr[24];
    void *fill[6];
    u64 (EFIAPI *get_variable)(const u16 *, const guid_t *, u32 *, uintn *, void *);
    u64 (EFIAPI *get_next_name)(uintn *, u16 *, guid_t *);
    u64 (EFIAPI *set_variable)(const u16 *, const guid_t *, u32, uintn, const void *);
} runtime_services_t;

typedef struct {
    u8 hdr[24];
    u16 *fw_vendor;
    u32 fw_revision;
    handle_t con_in_handle;
    void *con_in;
    handle_t con_out_handle;
    text_out_t *con_out;
    handle_t err_handle;
    text_out_t *err;
    runtime_services_t *rt;
    boot_services_t *bs;
} system_table_t;

typedef struct {
    u32 revision;
    handle_t parent;
    system_table_t *st;
    handle_t device;
    void *file_path;
    void *reserved;
    u32 options_size;
    void *options;
} loaded_image_t;

typedef struct file file_t;
struct file {
    u64 revision;
    u64 (EFIAPI *open)(file_t *, file_t **, const u16 *, u64, u64);
    u64 (EFIAPI *close)(file_t *);
    void *delete_file;
    u64 (EFIAPI *read)(file_t *, uintn *, void *);
};

typedef struct sfs sfs_t;
struct sfs {
    u64 revision;
    u64 (EFIAPI *open_volume)(sfs_t *, file_t **);
};

typedef struct {
    u8 type;
    u8 subtype;
    u8 length[2];
} dp_node_t;

#define _Check(n, f) _Static_assert(__builtin_offsetof(boot_services_t, f) == (n), #f)
_Check(152, handle_protocol);
_Check(176, locate_handle);
_Check(248, stall);
_Static_assert(__builtin_offsetof(runtime_services_t, get_variable) == 72, "get_variable");
_Static_assert(__builtin_offsetof(runtime_services_t, set_variable) == 88, "set_variable");
_Static_assert(__builtin_offsetof(system_table_t, rt) == 88, "rt");
_Static_assert(__builtin_offsetof(system_table_t, bs) == 96, "bs");
_Static_assert(__builtin_offsetof(loaded_image_t, device) == 24, "device");
_Static_assert(__builtin_offsetof(loaded_image_t, options) == 56, "options");
_Static_assert(__builtin_offsetof(file_t, read) == 32, "read");

extern const guid_t G_GLOBAL_VARIABLE;
extern const guid_t G_LOADED_IMAGE;
extern const guid_t G_SIMPLE_FS;
extern const guid_t G_DEVICE_PATH;

extern system_table_t *g_st;

#endif
