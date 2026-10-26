#include "config.h"
#include "util.h"

#define CONFIG_PATH L"\\EFI\\BOOT\\bootreg.cfg"
#define CONFIG_MAX 2047

static void copy_value(char *dst, u64 max, const char *src, u64 len)
{
    u64 n = 0;
    while (n < len && n + 1 < max) {
        dst[n] = src[n];
        n++;
    }
    dst[n] = 0;
}

static int key_is(const char *line, u64 klen, const char *key)
{
    return klen == str_len(key) && memcmp(line, key, klen) == 0;
}

static void parse_line(config_t *cfg, const char *line, u64 len)
{
    u64 eq = 0;
    while (eq < len && line[eq] != '=') eq++;
    if (eq == len) return;
    const char *val = line + eq + 1;
    u64 vlen = len - eq - 1;
    if (key_is(line, eq, "slug")) copy_value(cfg->slug, sizeof(cfg->slug), val, vlen);
    else if (key_is(line, eq, "alt")) {
        if (cfg->n_alt < MAX_ALT && vlen) copy_value(cfg->alt[cfg->n_alt++], sizeof(cfg->alt[0]), val, vlen);
    } else if (key_is(line, eq, "file")) copy_value(cfg->file, sizeof(cfg->file), val, vlen);
    else if (key_is(line, eq, "name")) copy_value(cfg->name, sizeof(cfg->name), val, vlen);
    else if (key_is(line, eq, "mode") && vlen == 4 && memcmp(val, "list", 4) == 0) cfg->list_mode = 1;
}

static void parse(config_t *cfg, const char *text, u64 size)
{
    u64 start = 0;
    u64 i;
    for (i = 0; i <= size; i++) {
        if (i == size || text[i] == '\n') {
            u64 end = i;
            while (end > start && (text[end - 1] == '\r' || text[end - 1] == ' ' || text[end - 1] == '\t')) end--;
            if (end > start && text[start] != '#') parse_line(cfg, text + start, end - start);
            start = i + 1;
        }
    }
}

static u64 read_text(handle_t volume, char *buf, u64 *size)
{
    sfs_t *fs;
    file_t *root;
    file_t *f;
    u64 st = g_st->bs->handle_protocol(volume, &G_SIMPLE_FS, (void **)&fs);
    if (st) return st;
    st = fs->open_volume(fs, &root);
    if (st) return st;
    st = root->open(root, &f, CONFIG_PATH, FILE_MODE_READ, 0);
    root->close(root);
    if (st) return st;
    *size = CONFIG_MAX;
    st = f->read(f, size, buf);
    f->close(f);
    return st;
}

u64 config_load(handle_t volume, config_t *cfg)
{
    static char text[CONFIG_MAX + 1];
    u64 size = 0;
    u64 st = read_text(volume, text, &size);
    if (st) return st;
    parse(cfg, text, size);
    if (!cfg->file[0]) copy_value(cfg->file, sizeof(cfg->file), "BOOTX64.EFI", 11);
    if (!cfg->name[0]) copy_value(cfg->name, sizeof(cfg->name), cfg->slug, str_len(cfg->slug));
    ascii_to_u16(cfg->name16, cfg->name, 96);
    return cfg->slug[0] ? EFI_SUCCESS : EFI_NOT_FOUND;
}
