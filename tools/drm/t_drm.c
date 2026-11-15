/* SPDX-License-Identifier: GPL-2.0-only */
#define TNAME "t_drm"
#include "../unterbau/t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

#define IOWR(nr, sz) ((3u << 30) | ((unsigned)(sz) << 16) | (0x64u << 8) | (nr))

struct version { int major, minor, patch; size_t name_len; char *name; size_t date_len; char *date; size_t desc_len; char *desc; };
struct get_cap { uint64_t cap, value; };
struct card_res { uint64_t fb, crtc, conn, enc; uint32_t nfb, ncrtc, nconn, nenc, minw, maxw, minh, maxh; };
struct modeinfo { uint32_t clock; uint16_t hd, hss, hse, ht, hskew, vd, vss, vse, vt, vscan; uint32_t vrefresh, flags, type; char name[32]; };
struct get_conn { uint64_t enc_ptr, modes_ptr, props_ptr, vals_ptr; uint32_t nmodes, nprops, nenc, enc_id, conn_id, type, type_id, connection, mmw, mmh, subpixel, pad; };
struct mode_crtc { uint64_t conn_ptr; uint32_t nconn, crtc_id, fb_id, x, y, gamma, mode_valid; struct modeinfo mode; };
struct create_dumb { uint32_t height, width, bpp, flags, handle, pitch; uint64_t size; };
struct map_dumb { uint32_t handle, pad; uint64_t offset; };
struct fb_cmd2 { uint32_t fb_id, width, height, format, flags, handles[4], pitches[4], offsets[4]; uint64_t modifier[4]; };

static uint32_t colors[4] = { 0x00FF0000, 0x0000FF00, 0x000000FF, 0x00FFFFFF };
static const uint32_t alt_colors[4] = { 0x000000FF, 0x00FFFFFF, 0x00FF0000, 0x0000FF00 };

static void paint(uint32_t *px, uint32_t w, uint32_t h, uint32_t pitch)
{
    for (uint32_t y = 0; y < h; y++)
        for (uint32_t x = 0; x < w; x++)
            px[y * (pitch / 4) + x] = colors[(y >= h / 2) * 2 + (x >= w / 2)];
}

static int open_card(const char *path) { return open(path, O_RDWR | O_CLOEXEC); }

static void check_nodes(void)
{
    struct stat st = {0};
    CHECKC("stat_card0", stat("/dev/dri/card0", &st) == 0 && S_ISCHR(st.st_mode) && major(st.st_rdev) == 226 && minor(st.st_rdev) == 0, "rdev=%lx", (long)st.st_rdev);
    CHECKC("stat_render", stat("/dev/dri/renderD128", &st) == 0 && major(st.st_rdev) == 226 && minor(st.st_rdev) == 128, "rdev=%lx", (long)st.st_rdev);
    DIR *d = opendir("/dev/dri");
    int seen = 0;
    struct dirent *e;
    while (d && (e = readdir(d)))
        seen += !strcmp(e->d_name, "card0") + !strcmp(e->d_name, "renderD128");
    if (d) closedir(d);
    CHECK("readdir_dri", seen == 2, "seen=%d", seen);
}

static void show(int fd, int skip_set)
{
    char name[16] = {0};
    struct version v = { .name_len = sizeof name - 1, .name = name };
    CHECKC("version", ioctl(fd, IOWR(0x00, sizeof v), &v) == 0 && !strcmp(name, "osum"), "name=%s", name);
    struct get_cap c = { .cap = 1 };
    CHECKC("cap_dumb", ioctl(fd, IOWR(0x0C, sizeof c), &c) == 0 && c.value == 1, "value=%llu", (unsigned long long)c.value);
    uint32_t crtc = 0, conn = 0, enc = 0;
    struct card_res r = { .crtc = (uintptr_t)&crtc, .conn = (uintptr_t)&conn, .enc = (uintptr_t)&enc, .ncrtc = 1, .nconn = 1, .nenc = 1 };
    CHECKC("getresources", ioctl(fd, IOWR(0xA0, sizeof r), &r) == 0 && r.ncrtc == 1 && crtc && conn, "crtc=%u conn=%u", crtc, conn);
    struct modeinfo m = {0};
    struct get_conn gc = { .modes_ptr = (uintptr_t)&m, .nmodes = 1, .conn_id = conn };
    CHECKC("getconnector", ioctl(fd, IOWR(0xA7, sizeof gc), &gc) == 0 && gc.nmodes == 1 && gc.connection == 1 && m.hd > 0, "modes=%u hd=%u", gc.nmodes, m.hd);
    printf("\nDRM_MODE %ux%u %s\n", m.hd, m.vd, m.name);
    struct create_dumb cd = { .height = m.vd, .width = m.hd, .bpp = 32 };
    CHECKC("create_dumb", ioctl(fd, IOWR(0xB2, sizeof cd), &cd) == 0 && cd.handle && cd.pitch >= m.hd * 4u && cd.size >= (uint64_t)cd.pitch * m.vd, "pitch=%u", cd.pitch);
    struct map_dumb md = { .handle = cd.handle };
    CHECKC("map_dumb", ioctl(fd, IOWR(0xB3, sizeof md), &md) == 0, "x");
    uint32_t *px = mmap(0, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, md.offset);
    CHECKC("mmap", px != MAP_FAILED, "x");
    if (px == MAP_FAILED) return;
    void *bad = mmap(0, cd.size, PROT_READ, MAP_SHARED, fd, md.offset + (40ull << 32));
    CHECK("mmap_bad_offset_refused", bad == MAP_FAILED && errno == EINVAL, "errno=%d", errno);
    paint(px, cd.width, cd.height, cd.pitch);
    struct fb_cmd2 f = { .width = cd.width, .height = cd.height, .format = 0x34325258 };
    f.handles[0] = cd.handle; f.pitches[0] = cd.pitch;
    CHECKC("addfb2", ioctl(fd, IOWR(0xB8, sizeof f), &f) == 0 && f.fb_id, "x");
    struct mode_crtc sc = { .conn_ptr = (uintptr_t)&conn, .nconn = 1, .crtc_id = crtc, .fb_id = f.fb_id, .mode_valid = 1, .mode = m };
    if (!skip_set)
        CHECKC("setcrtc", ioctl(fd, IOWR(0xA2, sizeof sc), &sc) == 0, "x");
    struct mode_crtc gcr = { .crtc_id = crtc };
    CHECKC("getcrtc", ioctl(fd, IOWR(0xA1, sizeof gcr), &gcr) == 0 && gcr.fb_id == (skip_set ? 0 : f.fb_id), "fb=%u", gcr.fb_id);
}

static void check_render_and_reap(void)
{
    int rfd = open_card("/dev/dri/renderD128");
    struct mode_crtc sc = { .crtc_id = 0x32 };
    CHECK("render_setcrtc_refused", rfd >= 0 && ioctl(rfd, IOWR(0xA2, sizeof sc), &sc) < 0 && errno == EACCES, "errno=%d", errno);
    close(rfd);
    int fd = open_card("/dev/dri/card0");
    struct create_dumb a = { .height = 16, .width = 16, .bpp = 32 };
    int made = ioctl(fd, IOWR(0xB2, sizeof a), &a) == 0;
    close(fd);
    fd = open_card("/dev/dri/card0");
    struct create_dumb b = { .height = 16, .width = 16, .bpp = 32 };
    int again = ioctl(fd, IOWR(0xB2, sizeof b), &b) == 0;
    CHECK("closed_fd_reaps_handles", made && again && a.handle == b.handle, "a=%u b=%u", a.handle, b.handle);
    close(fd);
}

int main(int argc, char **argv)
{
    int skip_set = argc > 1 && !strcmp(argv[1], "noset");
    if (argc > 1 && !strcmp(argv[1], "alt"))
        memcpy(colors, alt_colors, sizeof colors);
    check_nodes();
    int fd = open_card("/dev/dri/card0");
    CHECKC("open_card0", fd >= 0, "x");
    if (fd < 0) return 1;
    show(fd, skip_set);
    check_render_and_reap();
    printf("\nDRM_HOLD\n");
    fflush(stdout);
    sleep(8);
    printf("\nDRM_DONE\n");
    return 0;
}
