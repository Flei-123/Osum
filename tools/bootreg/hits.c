#include "hits.h"
#include "util.h"

#define MAX_VOLUMES 64

static u16 node_len(const u8 *p)
{
    return (u16)(p[2] | (p[3] << 8));
}

static int volume_has(handle_t h, const u16 *path)
{
    sfs_t *fs;
    file_t *root;
    file_t *f;
    if (g_st->bs->handle_protocol(h, &G_SIMPLE_FS, (void **)&fs)) return 0;
    if (fs->open_volume(fs, &root)) return 0;
    u64 st = root->open(root, &f, path, FILE_MODE_READ, 0);
    root->close(root);
    if (st) return 0;
    f->close(f);
    return 1;
}

static u64 build_dp(handle_t h, const u16 *path, hit_t *hit)
{
    const u8 *dp;
    u64 plen = u16_len(path);
    u64 total = 0;
    u16 fnode;
    if (g_st->bs->handle_protocol(h, &G_DEVICE_PATH, (void **)&dp)) return EFI_NOT_FOUND;
    for (;;) {
        u16 len = node_len(dp + total);
        if (len < 4 || total + len > DP_MAX) return EFI_INVALID_PARAMETER;
        if (dp[total] == 0x7f && dp[total + 1] == 0xff) break;
        total += len;
    }
    fnode = (u16)(4 + (plen + 1) * 2);
    if (total + fnode + 4 > DP_MAX) return EFI_OUT_OF_RESOURCES;
    memcpy(hit->dp, dp, total);
    hit->dp[total] = 4;
    hit->dp[total + 1] = 4;
    hit->dp[total + 2] = (u8)fnode;
    hit->dp[total + 3] = (u8)(fnode >> 8);
    memcpy(hit->dp + total + 4, path, (plen + 1) * 2);
    total += fnode;
    hit->dp[total] = 0x7f;
    hit->dp[total + 1] = 0xff;
    hit->dp[total + 2] = 4;
    hit->dp[total + 3] = 0;
    hit->dp_len = (u16)(total + 4);
    return EFI_SUCCESS;
}

static void make_path(u16 *out, const char *slug, const char *file)
{
    u64 n = 0;
    out[n++] = '\\';
    out[n++] = 'E';
    out[n++] = 'F';
    out[n++] = 'I';
    out[n++] = '\\';
    n += ascii_to_u16(out + n, slug, 60);
    out[n++] = '\\';
    ascii_to_u16(out + n, file, 60);
}

static int try_slug(handle_t h, const char *slug, const config_t *cfg, hit_t *hits, int n, int max)
{
    u16 path[128];
    make_path(path, slug, cfg->file);
    if (n >= max || !volume_has(h, path)) return n;
    memset(&hits[n], 0, sizeof(hit_t));
    if (build_dp(h, path, &hits[n])) return n;
    return n + 1;
}

int hits_find(const config_t *cfg, handle_t own_volume, hit_t *hits, int max)
{
    static handle_t handles[MAX_VOLUMES];
    uintn size = sizeof(handles);
    int n = 0;
    uintn count;
    uintn i;
    int s;
    if (g_st->bs->locate_handle(LOCATE_BY_PROTOCOL, &G_SIMPLE_FS, 0, &size, handles)) return 0;
    count = size / sizeof(handle_t);
    for (i = 0; i < count; i++) {
        if (handles[i] == own_volume) continue;
        n = try_slug(handles[i], cfg->slug, cfg, hits, n, max);
        for (s = 0; s < cfg->n_alt; s++) n = try_slug(handles[i], cfg->alt[s], cfg, hits, n, max);
    }
    return n;
}
