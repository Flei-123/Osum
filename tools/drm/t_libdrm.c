/* SPDX-License-Identifier: GPL-2.0-only */
#define TNAME "t_libdrm"
#include "../unterbau/t.h"
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <sys/mman.h>
#include <time.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_fourcc.h>

#define NS 1000000000ull

static int flips_done;
static uint64_t flip_user;
static unsigned flip_seq;

static void on_flip(int fd, unsigned seq, unsigned sec, unsigned usec, void *user)
{
    (void)fd; (void)sec; (void)usec;
    flips_done++;
    flip_seq = seq;
    flip_user = (uintptr_t)user;
}

static uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * NS + t.tv_nsec; }

static int make_fb(int fd, uint32_t w, uint32_t h, uint32_t *fb)
{
    struct drm_mode_create_dumb cd = { .height = h, .width = w, .bpp = 32 };
    if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd)) return -1;
    return drmModeAddFB2(fd, w, h, DRM_FORMAT_XRGB8888, (uint32_t[4]){ cd.handle }, (uint32_t[4]){ cd.pitch }, (uint32_t[4]){ 0 }, fb, 0);
}

static void check_modes(int fd, uint32_t *crtc, uint32_t *conn, drmModeModeInfo *mode)
{
    drmModeRes *r = drmModeGetResources(fd);
    CHECKC("lib_getresources", r && r->count_crtcs == 1 && r->count_connectors == 1, "r=%p", (void *)r);
    if (!r) return;
    *crtc = r->crtcs[0];
    *conn = r->connectors[0];
    drmModeConnector *c = drmModeGetConnector(fd, *conn);
    CHECKC("lib_getconnector", c && c->count_modes >= 1 && c->connection == DRM_MODE_CONNECTED, "c=%p", (void *)c);
    if (c) { *mode = c->modes[0]; drmModeFreeConnector(c); }
    drmModeFreeResources(r);
}

static void check_flip(int fd, uint32_t crtc, uint32_t conn, drmModeModeInfo *m)
{
    uint32_t fb[2];
    CHECKC("lib_addfb2", make_fb(fd, m->hdisplay, m->vdisplay, &fb[0]) == 0 && make_fb(fd, m->hdisplay, m->vdisplay, &fb[1]) == 0, "x");
    CHECKC("lib_setcrtc", drmModeSetCrtc(fd, crtc, fb[0], 0, 0, &conn, 1, m) == 0, "x");
    drmEventContext ev = { .version = 2, .page_flip_handler = on_flip };
    int ok = 1;
    unsigned last = 0, ordered = 1;
    uint64_t t0 = now_ns();
    for (int i = 0; i < 6; i++) {
        int before = flips_done;
        if (drmModePageFlip(fd, crtc, fb[i & 1], DRM_MODE_PAGE_FLIP_EVENT, (void *)(uintptr_t)(0x100 + i))) { ok = 0; break; }
        struct pollfd p = { .fd = fd, .events = POLLIN };
        if (poll(&p, 1, 500) != 1 || drmHandleEvent(fd, &ev) != 0 || flips_done != before + 1 || flip_user != 0x100u + i) { ok = 0; break; }
        if (flip_seq <= last) ordered = 0;
        last = flip_seq;
    }
    uint64_t dt = now_ns() - t0;
    CHECK("lib_pageflip_event_handler", ok && ordered, "ok=%d ordered=%u done=%d", ok, ordered, flips_done);
    CHECK("lib_pageflip_paced", dt >= 60000000ull, "ms=%llu", (unsigned long long)(dt / 1000000));
}

static void check_vblank_sequence(int fd, uint32_t crtc)
{
    uint64_t seq0 = 0, ns0 = 0, seq1 = 0, ns1 = 0;
    CHECKC("lib_crtc_get_sequence", drmCrtcGetSequence(fd, crtc, &seq0, &ns0) == 0 && seq0 > 0, "seq=%llu", (unsigned long long)seq0);
    drmVBlank vbl = { .request = { .type = DRM_VBLANK_RELATIVE, .sequence = 2 } };
    CHECKC("lib_wait_vblank", drmWaitVBlank(fd, &vbl) == 0 && vbl.reply.sequence >= seq0 + 2, "seq=%u", vbl.reply.sequence);
    CHECK("lib_sequence_advances", drmCrtcGetSequence(fd, crtc, &seq1, &ns1) == 0 && seq1 > seq0 && ns1 > ns0, "seq1=%llu", (unsigned long long)seq1);
}

static void check_syncobj(int fd)
{
    uint32_t h = 0, t = 0, first = 9;
    CHECKC("lib_syncobj_create", drmSyncobjCreate(fd, 0, &h) == 0 && drmSyncobjCreate(fd, DRM_SYNCOBJ_CREATE_SIGNALED, &t) == 0 && h && t, "h=%u t=%u", h, t);
    CHECK("lib_syncobj_wait_signaled", drmSyncobjWait(fd, &t, 1, now_ns() + NS, 0, &first) == 0 && first == 0, "errno=%d", errno);
    CHECK("lib_syncobj_wait_timeout", drmSyncobjWait(fd, &h, 1, now_ns() + 20000000ll, DRM_SYNCOBJ_WAIT_FLAGS_WAIT_FOR_SUBMIT, &first) < 0 && errno == ETIME, "errno=%d", errno);
    CHECK("lib_syncobj_signal_wait", drmSyncobjSignal(fd, &h, 1) == 0 && drmSyncobjWait(fd, &h, 1, now_ns() + NS, 0, &first) == 0, "errno=%d", errno);
    CHECK("lib_syncobj_reset", drmSyncobjReset(fd, &h, 1) == 0 && drmSyncobjWait(fd, &h, 1, now_ns() + NS, 0, &first) < 0, "errno=%d", errno);
    uint64_t p = 7, q = 0;
    CHECK("lib_timeline_signal_query", drmSyncobjTimelineSignal(fd, &h, &p, 1) == 0 && drmSyncobjQuery(fd, &h, &q, 1) == 0 && q == 7, "q=%llu", (unsigned long long)q);
    p = 5;
    CHECK("lib_timeline_wait", drmSyncobjTimelineWait(fd, &h, &p, 1, now_ns() + NS, 0, &first) == 0, "errno=%d", errno);
    int obj_fd = -1, sync_fd = -1;
    uint32_t back = 0, imp = 0;
    drmSyncobjSignal(fd, &h, 1);
    CHECK("lib_syncobj_fd_roundtrip", drmSyncobjHandleToFD(fd, h, &obj_fd) == 0 && drmSyncobjFDToHandle(fd, obj_fd, &back) == 0 && back && back != h, "errno=%d", errno);
    CHECK("lib_sync_file_roundtrip", drmSyncobjExportSyncFile(fd, h, &sync_fd) == 0 && drmSyncobjCreate(fd, 0, &imp) == 0 && drmSyncobjImportSyncFile(fd, imp, sync_fd) == 0
          && drmSyncobjWait(fd, &imp, 1, now_ns() + NS, 0, &first) == 0, "errno=%d", errno);
    CHECK("lib_syncobj_destroy", drmSyncobjDestroy(fd, h) == 0 && drmSyncobjDestroy(fd, h) < 0, "errno=%d", errno);
}

static void check_prime(int fd)
{
    struct drm_mode_create_dumb cd = { .height = 8, .width = 8, .bpp = 32 };
    struct drm_mode_map_dumb md;
    int prime = -1;
    uint32_t back = 0;
    CHECKC("lib_prime_create", drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd) == 0, "x");
    md = (struct drm_mode_map_dumb){ .handle = cd.handle };
    drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md);
    uint32_t *gem = mmap(0, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, md.offset);
    if (gem == MAP_FAILED) { FAIL("lib_prime_map", "errno=%d", errno); return; }
    gem[3] = 0x5A5AA5A5u;
    CHECK("lib_prime_handle_to_fd", drmPrimeHandleToFD(fd, cd.handle, DRM_CLOEXEC | DRM_RDWR, &prime) == 0 && prime >= 0, "errno=%d", errno);
    uint32_t *dm = mmap(0, cd.size, PROT_READ, MAP_SHARED, prime, 0);
    CHECK("lib_prime_content_shared", dm != MAP_FAILED && dm[3] == 0x5A5AA5A5u, "errno=%d", errno);
    CHECK("lib_prime_fd_to_handle", drmPrimeFDToHandle(fd, prime, &back) == 0 && back == cd.handle, "back=%u want=%u", back, cd.handle);
}

int main(void)
{
    int fd = drmOpen("osum", NULL);
    if (fd < 0) fd = open("/dev/dri/card0", O_RDWR);
    CHECKC("lib_open", fd >= 0, "fd=%d", fd);
    if (fd < 0) return 1;
    uint32_t crtc = 0, conn = 0;
    drmModeModeInfo mode = {0};
    check_modes(fd, &crtc, &conn, &mode);
    if (!crtc || !mode.hdisplay) return 1;
    check_flip(fd, crtc, conn, &mode);
    check_vblank_sequence(fd, crtc);
    check_syncobj(fd);
    check_prime(fd);
    printf("\nLIBDRM_DONE\n");
    fflush(stdout);
    return 0;
}
