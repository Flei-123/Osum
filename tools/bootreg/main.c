#include "bootvars.h"
#include "util.h"

#define STALL_US 3000000

static int options_say_list(const loaded_image_t *li)
{
    const u16 *o = li->options;
    u32 n = li->options_size / 2;
    u32 i = 0;
    while (i < n && o[i] == ' ') i++;
    if (i >= n) return 0;
    return o[i] == 'l' && i + 3 < n && o[i + 1] == 'i' && o[i + 2] == 's' && o[i + 3] == 't';
}

static void report_failure(u64 st)
{
    log_str("bootreg: FAILED: ");
    log_status(st);
    log_str("\n");
}

static u64 run(handle_t image)
{
    static config_t cfg;
    static hit_t hits[MAX_HITS];
    loaded_image_t *li;
    int list = 0;
    int n;
    u64 st = g_st->bs->handle_protocol(image, &G_LOADED_IMAGE, (void **)&li);
    if (st) return st;
    list = options_say_list(li);
    st = config_load(li->device, &cfg);
    if (st && !list) return st;
    if (cfg.list_mode) list = 1;
    if (list) return bootvars_list();
    n = hits_find(&cfg, li->device, hits, MAX_HITS);
    if (n == 0) {
        log_str("bootreg: NOT FOUND: no ");
        log_str(cfg.slug);
        log_str(" on any disk\n");
        return EFI_NOT_FOUND;
    }
    return bootvars_register(&cfg, hits, n);
}

u64 EFIAPI efi_main(handle_t image, system_table_t *st)
{
    u64 status;
    log_init(st);
    status = run(image);
    if (status && status != EFI_NOT_FOUND) report_failure(status);
    log_flush();
    st->bs->stall(STALL_US);
    return status;
}
