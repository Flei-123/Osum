#include "bootvars.h"
#include "util.h"

#define VAR_BUF 2048
#define MAX_ORDER 512

static u16 g_name[512];

static int is_boot_name(const u16 *n, u16 *number)
{
    u16 v = 0;
    int i;
    if (n[0] != 'B' || n[1] != 'o' || n[2] != 'o' || n[3] != 't') return 0;
    for (i = 4; i < 8; i++) {
        u16 c = n[i];
        v <<= 4;
        if (c >= '0' && c <= '9') v |= c - '0';
        else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
        else return 0;
    }
    if (n[8]) return 0;
    *number = v;
    return 1;
}

static u64 get_var(const u16 *name, void *buf, uintn *size)
{
    *size = VAR_BUF;
    return g_st->rt->get_variable(name, &G_GLOBAL_VARIABLE, 0, size, buf);
}

static const u8 *option_path(const u8 *opt, uintn size, u16 *len)
{
    const u16 *desc;
    u64 dl;
    if (size < 8) return 0;
    *len = (u16)(opt[4] | (opt[5] << 8));
    desc = (const u16 *)(opt + 6);
    dl = u16_len(desc);
    if (6 + (dl + 1) * 2 + *len > size) return 0;
    return opt + 6 + (dl + 1) * 2;
}

static u64 load_order(u16 *order, int *n)
{
    uintn size = MAX_ORDER * 2;
    u64 st = g_st->rt->get_variable((const u16 *)L"BootOrder", &G_GLOBAL_VARIABLE, 0, &size, order);
    if (st == EFI_NOT_FOUND) {
        *n = 0;
        return EFI_SUCCESS;
    }
    if (st) return st;
    *n = (int)(size / 2);
    return EFI_SUCCESS;
}

static int order_has(const u16 *order, int n, u16 number)
{
    int i;
    for (i = 0; i < n; i++)
        if (order[i] == number) return 1;
    return 0;
}

static u64 scan(const hit_t *hits, int n_hits, u8 *used, int *found, int verbose)
{
    static u8 buf[VAR_BUF];
    guid_t guid;
    uintn size;
    int h;
    memset(g_name, 0, sizeof(g_name));
    for (;;) {
        u16 number;
        u64 st;
        size = sizeof(g_name);
        st = g_st->rt->get_next_name(&size, g_name, &guid);
        if (st == EFI_NOT_FOUND) break;
        if (st) return st;
        if (!guid_equal(&guid, &G_GLOBAL_VARIABLE) || !is_boot_name(g_name, &number)) continue;
        used[number >> 3] |= (u8)(1 << (number & 7));
        if (get_var(g_name, buf, &size)) continue;
        if (verbose) {
            log_str("bootreg: list ");
            log_u16(g_name);
            log_str(" ");
            log_u16((const u16 *)(buf + 6));
            log_str("\n");
        }
        u16 len;
        const u8 *path = option_path(buf, size, &len);
        if (!path) continue;
        for (h = 0; h < n_hits; h++)
            if (len == hits[h].dp_len && memcmp(path, hits[h].dp, len) == 0 && found[h] < 0) found[h] = number;
    }
    return EFI_SUCCESS;
}

static u64 build_option(u8 *buf, uintn *size, const config_t *cfg, const hit_t *hit)
{
    u64 dl = u16_len(cfg->name16);
    u64 off = 0;
    u32 attr = LOAD_OPTION_ACTIVE;
    memcpy(buf, &attr, 4);
    buf[4] = (u8)hit->dp_len;
    buf[5] = (u8)(hit->dp_len >> 8);
    off = 6;
    memcpy(buf + off, cfg->name16, (dl + 1) * 2);
    off += (dl + 1) * 2;
    memcpy(buf + off, hit->dp, hit->dp_len);
    off += hit->dp_len;
    *size = off;
    return EFI_SUCCESS;
}

static u64 pick_free(const u8 *used, u16 *number)
{
    u32 i;
    for (i = 0; i < 0x10000; i++) {
        if (!(used[i >> 3] & (1 << (i & 7)))) {
            *number = (u16)i;
            return EFI_SUCCESS;
        }
    }
    return EFI_OUT_OF_RESOURCES;
}

static u64 verify_option(const config_t *cfg, const hit_t *hit, u16 number, int wrote)
{
    static u8 expect[VAR_BUF];
    static u8 got[VAR_BUF];
    u16 name[9];
    uintn es;
    uintn gs;
    u16 len;
    const u8 *path;
    boot_name(name, number);
    u64 st = get_var(name, got, &gs);
    if (st) return st;
    if (wrote) {
        build_option(expect, &es, cfg, hit);
        if (es != gs || memcmp(expect, got, es) != 0) return EFI_COMPROMISED_DATA;
    }
    path = option_path(got, gs, &len);
    if (!path || len != hit->dp_len || memcmp(path, hit->dp, len) != 0) return EFI_COMPROMISED_DATA;
    return EFI_SUCCESS;
}

static void print_order(const char *prefix, const u16 *order, int n)
{
    int i;
    log_str(prefix);
    for (i = 0; i < n; i++) {
        log_str(" ");
        log_hex(order[i], 4);
    }
    log_str("\n");
}

static void print_entry(const char *state, u16 number, const config_t *cfg, const hit_t *hit)
{
    u16 name[9];
    boot_name(name, number);
    log_str("bootreg: ");
    log_str(state);
    log_str(" ");
    log_u16(name);
    log_str(" ");
    log_str(cfg->name);
    log_str(" -> ");
    log_dp(hit->dp);
    log_str(" ");
}

u64 bootvars_register(const config_t *cfg, hit_t *hits, int n_hits)
{
    static u8 used[0x10000 / 8];
    static u16 order[MAX_ORDER];
    static u16 new_order[MAX_ORDER];
    static u8 opt[VAR_BUF];
    int found[MAX_HITS];
    int n_order = 0;
    int n_new = 0;
    int h;
    int wrote_order = 0;
    u64 st;
    uintn osz;
    for (h = 0; h < n_hits; h++) found[h] = -1;
    st = scan(hits, n_hits, used, found, 0);
    if (st) return st;
    st = load_order(order, &n_order);
    if (st) return st;
    for (h = 0; h < n_hits; h++) {
        u16 name[9];
        hits[h].existing = found[h] >= 0;
        if (hits[h].existing) {
            hits[h].number = (u16)found[h];
            continue;
        }
        st = pick_free(used, &hits[h].number);
        if (st) return st;
        used[hits[h].number >> 3] |= (u8)(1 << (hits[h].number & 7));
        build_option(opt, &osz, cfg, &hits[h]);
        boot_name(name, hits[h].number);
        st = g_st->rt->set_variable(name, &G_GLOBAL_VARIABLE, VAR_ALL, osz, opt);
        if (st) return st;
    }
    for (h = 0; h < n_hits; h++) {
        if (order_has(order, n_order, hits[h].number) || order_has(new_order, n_new, hits[h].number)) continue;
        if (n_new + n_order + 1 > MAX_ORDER) return EFI_OUT_OF_RESOURCES;
        new_order[n_new++] = hits[h].number;
    }
    if (n_new) {
        memcpy(new_order + n_new, order, (u64)n_order * 2);
        st = g_st->rt->set_variable((const u16 *)L"BootOrder", &G_GLOBAL_VARIABLE, VAR_ALL, (uintn)(n_new + n_order) * 2, new_order);
        if (st) return st;
        wrote_order = 1;
    }
    {
        static u16 check[MAX_ORDER];
        int n_check = 0;
        st = load_order(check, &n_check);
        if (st) return st;
        if (wrote_order && (n_check != n_new + n_order || memcmp(check, new_order, (u64)n_check * 2) != 0)) return EFI_COMPROMISED_DATA;
        for (h = 0; h < n_hits; h++)
            if (!order_has(check, n_check, hits[h].number)) return EFI_COMPROMISED_DATA;
    }
    for (h = 0; h < n_hits; h++) {
        st = verify_option(cfg, &hits[h], hits[h].number, !hits[h].existing);
        if (st) return st;
        print_entry(hits[h].existing ? "already registered" : "registered", hits[h].number, cfg, &hits[h]);
        log_str("verified\n");
    }
    {
        static u16 final_order[MAX_ORDER];
        int n_final = 0;
        if (load_order(final_order, &n_final) == EFI_SUCCESS) print_order("bootreg: order", final_order, n_final);
    }
    return EFI_SUCCESS;
}

u64 bootvars_list(void)
{
    static u8 used[0x10000 / 8];
    static u16 order[MAX_ORDER];
    int n = 0;
    int found[1];
    u64 st = scan(0, 0, used, found, 1);
    if (st) return st;
    st = load_order(order, &n);
    if (st) return st;
    print_order("bootreg: list order", order, n);
    return EFI_SUCCESS;
}
