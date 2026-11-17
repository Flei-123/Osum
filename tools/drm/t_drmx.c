/* SPDX-License-Identifier: GPL-2.0-only */
#define TNAME "t_drmx"
#include "../unterbau/t.h"
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>

#define IOWR(nr, sz) ((3u << 30) | ((unsigned)(sz) << 16) | (0x64u << 8) | (nr))
#define CRTC 0x32
#define NS 1000000000ull

struct card_res { uint64_t fb, crtc, conn, enc; uint32_t nfb, ncrtc, nconn, nenc, minw, maxw, minh, maxh; };
struct modeinfo { uint32_t clock; uint16_t hd, hss, hse, ht, hskew, vd, vss, vse, vt, vscan; uint32_t vrefresh, flags, type; char name[32]; };
struct get_conn { uint64_t enc_ptr, modes_ptr, props_ptr, vals_ptr; uint32_t nmodes, nprops, nenc, enc_id, conn_id, type, type_id, connection, mmw, mmh, subpixel, pad; };
struct mode_crtc { uint64_t conn_ptr; uint32_t nconn, crtc_id, fb_id, x, y, gamma, mode_valid; struct modeinfo mode; };
struct create_dumb { uint32_t height, width, bpp, flags, handle, pitch; uint64_t size; };
struct map_dumb { uint32_t handle, pad; uint64_t offset; };
struct fb_cmd2 { uint32_t fb_id, width, height, format, flags, handles[4], pitches[4], offsets[4]; uint64_t modifier[4]; };
struct flip { uint32_t crtc_id, fb_id, flags, sequence; uint64_t user_data; };
struct event { uint32_t type, length; uint64_t user_data; uint32_t sec, usec, seq, crtc; };
struct vblank { uint32_t type, sequence; uint64_t a, b, c; };
struct seq_get { uint32_t crtc_id, active; uint64_t sequence; int64_t ns; };
struct seq_queue { uint32_t crtc_id, flags; uint64_t sequence, user_data; };
struct so_create { uint32_t handle, flags; };
struct so_fd { uint32_t handle, flags; int32_t fd; uint32_t pad; uint64_t point; };
struct so_wait { uint64_t handles; int64_t timeout; uint32_t count, flags, first, pad; uint64_t deadline; };
struct so_twait { uint64_t handles, points; int64_t timeout; uint32_t count, flags, first, pad; uint64_t deadline; };
struct so_array { uint64_t handles; uint32_t count, pad; };
struct so_tsignal { uint64_t handles, points; uint32_t count, flags; };
struct so_transfer { uint32_t src, dst; uint64_t src_point, dst_point; uint32_t flags, pad; };
struct prime { uint32_t handle, flags; int32_t fd; };
struct gem_close { uint32_t handle, pad; };

static int card, render;
static uint32_t fbs[2];

static uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * NS + t.tv_nsec; }

static int dio(int fd, unsigned nr, void *p, size_t sz) { return ioctl(fd, IOWR(nr, sz), p); }
#define DIO(fd, nr, p) dio(fd, nr, p, sizeof *(p))

static int make_fb(uint32_t w, uint32_t h, uint32_t *fb)
{
    struct create_dumb cd = { .height = h, .width = w, .bpp = 32 };
    if (DIO(card, 0xB2, &cd)) return -1;
    struct fb_cmd2 f = { .width = w, .height = h, .format = 0x34325258 };
    f.handles[0] = cd.handle; f.pitches[0] = cd.pitch;
    if (DIO(card, 0xB8, &f)) return -1;
    *fb = f.fb_id;
    return 0;
}

static int scanout(void)
{
    uint32_t conn = 0, crtc = 0, enc = 0;
    struct card_res r = { .crtc = (uintptr_t)&crtc, .conn = (uintptr_t)&conn, .enc = (uintptr_t)&enc, .ncrtc = 1, .nconn = 1, .nenc = 1 };
    struct modeinfo m = {0};
    struct get_conn gc = { .modes_ptr = (uintptr_t)&m, .nmodes = 1 };
    if (DIO(card, 0xA0, &r)) return -1;
    gc.conn_id = conn;
    if (DIO(card, 0xA7, &gc) || make_fb(m.hd, m.vd, &fbs[0]) || make_fb(m.hd, m.vd, &fbs[1])) return -1;
    struct mode_crtc sc = { .conn_ptr = (uintptr_t)&conn, .nconn = 1, .crtc_id = crtc, .fb_id = fbs[0], .mode_valid = 1, .mode = m };
    return DIO(card, 0xA2, &sc);
}

static int next_event(int fd, struct event *e, int timeout_ms)
{
    struct pollfd p = { .fd = fd, .events = POLLIN };
    if (poll(&p, 1, timeout_ms) != 1 || !(p.revents & POLLIN)) return -1;
    return read(fd, e, sizeof *e) == (ssize_t)sizeof *e ? 0 : -1;
}

static void drain(int fd)
{
    struct event e;
    while (next_event(fd, &e, 60) == 0) {}
}

static void check_flip_events(void)
{
    struct event e = {0};
    struct flip f = { .crtc_id = CRTC, .fb_id = fbs[1], .flags = 1, .user_data = 0xABCD1234ull };
    CHECKC("flip_event_queued", DIO(card, 0xB0, &f) == 0, "x");
    int got = next_event(card, &e, 500);
    CHECK("flip_event_read", got == 0 && e.type == 2 && e.length == 32 && e.user_data == 0xABCD1234ull && e.crtc == CRTC && e.seq > 0, "got=%d type=%u len=%u ud=%llx", got, e.type, e.length, (unsigned long long)e.user_data);
    uint64_t t0 = now_ns();
    uint32_t last = 0, ordered = 1;
    for (int i = 0; i < 10; i++) {
        f.fb_id = fbs[i & 1];
        if (DIO(card, 0xB0, &f) || next_event(card, &e, 500)) { ordered = 0; break; }
        if (e.seq <= last) ordered = 0;
        last = e.seq;
    }
    uint64_t dt = now_ns() - t0;
    CHECK("flip_loop_ordered", ordered, "last=%u", last);
    CHECK("flip_loop_paced", dt >= 100000000ull && dt < 2000000000ull, "ms=%llu", (unsigned long long)(dt / 1000000));
    int nb = open("/dev/dri/card0", O_RDWR | O_NONBLOCK);
    char buf[64];
    CHECK("read_nonblock_empty", nb >= 0 && read(nb, buf, sizeof buf) < 0 && errno == EAGAIN, "errno=%d", errno);
    close(nb);
    CHECK("read_small_buffer_refused", read(card, buf, 8) < 0 && errno == EINVAL, "errno=%d", errno);
    f.fb_id = fbs[0]; f.flags = 0x80;
    CHECK("flip_bad_flags_refused", DIO(card, 0xB0, &f) < 0 && errno == EINVAL, "errno=%d", errno);
    f.flags = 1;
    int full = 0;
    for (int i = 0; i < 9; i++)
        if (DIO(card, 0xB0, &f) < 0 && errno == EBUSY) full++;
    CHECK("flip_queue_full_busy", full == 1, "full=%d", full);
    drain(card);
}

static void check_vblank(void)
{
    struct seq_get g = { .crtc_id = CRTC };
    CHECKC("get_sequence", DIO(card, 0x3B, &g) == 0 && g.active == 1 && g.sequence > 0, "seq=%llu", (unsigned long long)g.sequence);
    struct vblank v = { .type = 1, .sequence = 3 };
    uint64_t t0 = now_ns();
    int r = DIO(card, 0x3A, &v);
    uint64_t dt = now_ns() - t0;
    CHECKC("wait_vblank_relative", r == 0 && v.sequence > g.sequence && dt >= 30000000ull && dt < 1000000000ull, "ms=%llu seq=%u", (unsigned long long)(dt / 1000000), v.sequence);
    struct vblank imm = { .type = 1, .sequence = 0 };
    CHECK("wait_vblank_zero_immediate", DIO(card, 0x3A, &imm) == 0, "errno=%d", errno);
    struct vblank ev = { .type = 1 | 0x04000000, .sequence = 2, .a = 0x77 };
    struct event e = {0};
    int q = DIO(card, 0x3A, &ev);
    int got = next_event(card, &e, 500);
    CHECK("vblank_event", q == 0 && got == 0 && e.type == 1 && e.user_data == 0x77 && e.seq == ev.sequence, "q=%d got=%d type=%u seq=%u want=%u", q, got, e.type, e.seq, ev.sequence);
    struct vblank bad = { .type = 0x40000000 };
    CHECK("wait_vblank_signal_refused", DIO(card, 0x3A, &bad) < 0 && errno == EINVAL, "errno=%d", errno);
    struct seq_queue sq = { .crtc_id = CRTC, .flags = 1, .sequence = 2, .user_data = 0x99 };
    int sr = DIO(card, 0x3C, &sq);
    got = next_event(card, &e, 500);
    CHECK("queue_sequence_event", sr == 0 && got == 0 && e.type == 3 && e.user_data == 0x99, "sr=%d got=%d type=%u", sr, got, e.type);
    struct seq_queue past = { .crtc_id = CRTC, .flags = 0, .sequence = 1 };
    CHECK("queue_sequence_past_refused", DIO(card, 0x3C, &past) < 0 && errno == EINVAL, "errno=%d", errno);
    struct vblank rv = { .type = 1 };
    CHECK("render_vblank_refused", dio(render, 0x3A, &rv, sizeof rv) < 0 && errno == EACCES, "errno=%d", errno);
}

static uint32_t so_new(int fd, uint32_t flags)
{
    struct so_create c = { .flags = flags };
    return DIO(fd, 0xBF, &c) == 0 ? c.handle : 0;
}

static int so_wait(int fd, uint32_t h, int64_t abs_to, uint32_t flags, uint32_t *first)
{
    struct so_wait w = { .handles = (uintptr_t)&h, .timeout = abs_to, .count = 1, .flags = flags };
    int r = DIO(fd, 0xC3, &w);
    if (first) *first = w.first;
    return r;
}

static int so_signal(int fd, uint32_t h)
{
    struct so_array a = { .handles = (uintptr_t)&h, .count = 1 };
    return DIO(fd, 0xC5, &a);
}

static int so_point(int fd, uint32_t h, uint64_t p)
{
    struct so_tsignal s = { .handles = (uintptr_t)&h, .points = (uintptr_t)&p, .count = 1 };
    return DIO(fd, 0xCD, &s);
}

static int so_twait(int fd, uint32_t h, uint64_t p, int64_t abs_to, uint32_t flags)
{
    struct so_twait w = { .handles = (uintptr_t)&h, .points = (uintptr_t)&p, .timeout = abs_to, .count = 1, .flags = flags };
    return DIO(fd, 0xCA, &w);
}

static uint64_t so_query(int fd, uint32_t h)
{
    uint64_t p = 0;
    struct so_tsignal q = { .handles = (uintptr_t)&h, .points = (uintptr_t)&p, .count = 1 };
    return DIO(fd, 0xCB, &q) == 0 ? p : ~0ull;
}

static void check_syncobj_binary(void)
{
    uint32_t a = so_new(card, 1), b = so_new(card, 0);
    CHECKC("syncobj_create", a && b && a != b, "a=%u b=%u", a, b);
    uint32_t first = 9;
    CHECK("syncobj_wait_signaled", so_wait(card, a, now_ns() + NS, 0, &first) == 0 && first == 0, "errno=%d first=%u", errno, first);
    CHECK("syncobj_wait_no_fence_einval", so_wait(card, b, now_ns() + NS, 0, 0) < 0 && errno == EINVAL, "errno=%d", errno);
    uint64_t t0 = now_ns();
    int r = so_wait(card, b, now_ns() + 30000000ll, 2, 0);
    uint64_t dt = now_ns() - t0;
    CHECK("syncobj_wait_timeout_etime", r < 0 && errno == ETIME && dt >= 25000000ull && dt < 500000000ull, "errno=%d ms=%llu", errno, (unsigned long long)(dt / 1000000));
    CHECK("syncobj_wait_past_deadline_etime", so_wait(card, b, 1, 2, 0) < 0 && errno == ETIME, "errno=%d", errno);
    pid_t pid = fork();
    if (pid == 0) { usleep(40000); so_signal(card, b); _exit(0); }
    t0 = now_ns();
    r = so_wait(card, b, INT64_MAX, 2, 0);
    dt = now_ns() - t0;
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK("syncobj_wait_blocks_until_signal", r == 0 && dt >= 30000000ull && dt < 2000000000ull, "r=%d errno=%d ms=%llu", r, errno, (unsigned long long)(dt / 1000000));
    struct so_array rs = { .handles = (uintptr_t)&b, .count = 1 };
    int rr = DIO(card, 0xC4, &rs);
    CHECK("syncobj_reset", rr == 0 && so_wait(card, b, now_ns() + NS, 0, 0) < 0, "rr=%d", rr);
    uint32_t hs[2] = { a, b };
    struct so_wait all = { .handles = (uintptr_t)hs, .timeout = now_ns() + 20000000ll, .count = 2, .flags = 3 };
    CHECK("syncobj_wait_all_needs_both", DIO(card, 0xC3, &all) < 0 && errno == ETIME, "errno=%d", errno);
    struct so_wait any = { .handles = (uintptr_t)hs, .timeout = now_ns() + NS, .count = 2, .flags = 0 };
    CHECK("syncobj_wait_any_first_index", DIO(card, 0xC3, &any) == 0 && any.first == 0, "first=%u", any.first);
    so_signal(card, b);
    all.timeout = now_ns() + NS;
    CHECK("syncobj_wait_all_both_signaled", DIO(card, 0xC3, &all) == 0, "errno=%d", errno);
    struct so_create bad = { .flags = 0x10 };
    CHECK("syncobj_create_bad_flags", DIO(card, 0xBF, &bad) < 0 && errno == EINVAL, "errno=%d", errno);
    struct so_create d = { .handle = a };
    int dr = DIO(card, 0xC0, &d);
    CHECK("syncobj_destroy", dr == 0 && so_wait(card, a, now_ns() + NS, 0, 0) < 0 && errno == ENOENT, "dr=%d errno=%d", dr, errno);
    CHECK("syncobj_destroy_twice_enoent", DIO(card, 0xC0, &d) < 0 && errno == ENOENT, "errno=%d", errno);
}

static void check_timeline(void)
{
    uint32_t t = so_new(card, 0), u = so_new(card, 0);
    CHECK("timeline_signal", so_point(card, t, 5) == 0 && so_query(card, t) == 5, "q=%llu", (unsigned long long)so_query(card, t));
    CHECK("timeline_wait_reached", so_twait(card, t, 3, now_ns() + NS, 0) == 0, "errno=%d", errno);
    CHECK("timeline_wait_exact", so_twait(card, t, 5, now_ns() + NS, 0) == 0, "errno=%d", errno);
    CHECK("timeline_wait_unsubmitted_einval", so_twait(card, t, 7, now_ns() + NS, 0) < 0 && errno == EINVAL, "errno=%d", errno);
    CHECK("timeline_wait_submit_etime", so_twait(card, t, 7, now_ns() + 20000000ll, 2) < 0 && errno == ETIME, "errno=%d", errno);
    CHECK("timeline_signal_backwards_refused", so_point(card, t, 4) < 0 && errno == EINVAL && so_query(card, t) == 5, "errno=%d", errno);
    pid_t pid = fork();
    if (pid == 0) { usleep(40000); so_point(card, t, 9); _exit(0); }
    uint64_t t0 = now_ns();
    int r = so_twait(card, t, 8, INT64_MAX, 2);
    uint64_t dt = now_ns() - t0;
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK("timeline_wait_blocks_until_point", r == 0 && dt >= 30000000ull && so_query(card, t) == 9, "r=%d errno=%d ms=%llu", r, errno, (unsigned long long)(dt / 1000000));
    struct so_transfer tr = { .src = t, .dst = u, .src_point = 6, .dst_point = 3 };
    int rr = DIO(card, 0xCC, &tr);
    CHECK("timeline_transfer", rr == 0 && so_query(card, u) == 3, "rr=%d q=%llu", rr, (unsigned long long)so_query(card, u));
    struct so_transfer miss = { .src = u, .dst = t, .src_point = 50, .dst_point = 60 };
    CHECK("timeline_transfer_unready_refused", DIO(card, 0xCC, &miss) < 0 && errno == EINVAL && so_query(card, t) == 9, "errno=%d", errno);
}

static void check_syncfd(void)
{
    uint32_t a = so_new(card, 0);
    struct so_fd e = { .handle = a };
    CHECK("syncobj_fd_export", DIO(card, 0xC1, &e) == 0 && e.fd >= 0, "errno=%d", errno);
    struct pollfd p = { .fd = e.fd, .events = POLLIN };
    CHECK("syncobj_fd_poll_idle", poll(&p, 1, 0) == 0, "revents=%x", p.revents);
    so_signal(card, a);
    CHECK("syncobj_fd_poll_signaled", poll(&p, 1, 200) == 1 && (p.revents & POLLIN), "revents=%x", p.revents);
    struct so_fd imp = { .fd = e.fd };
    int ir = DIO(render, 0xC2, &imp);
    CHECK("syncobj_fd_import_render", ir == 0 && imp.handle != 0, "ir=%d errno=%d", ir, errno);
    CHECK("syncobj_fd_shared_state", ir == 0 && so_wait(render, imp.handle, now_ns() + NS, 0, 0) == 0, "errno=%d", errno);
    int bad = open("/dev/null", O_RDONLY);
    struct so_fd badfd = { .fd = bad };
    CHECK("syncobj_fd_import_wrong_kind", DIO(card, 0xC2, &badfd) < 0 && errno == EINVAL, "errno=%d", errno);
    close(bad);
    uint32_t c = so_new(card, 0);
    struct so_fd sf = { .handle = c, .flags = 1 };
    CHECK("sync_file_export_unsignaled_refused", DIO(card, 0xC1, &sf) < 0 && errno == EINVAL, "errno=%d", errno);
    so_signal(card, c);
    CHECK("sync_file_export", DIO(card, 0xC1, &sf) == 0 && sf.fd >= 0, "errno=%d", errno);
    struct pollfd sp = { .fd = sf.fd, .events = POLLIN };
    CHECK("sync_file_poll_signaled", poll(&sp, 1, 200) == 1 && (sp.revents & POLLIN), "revents=%x", sp.revents);
    struct so_fd si = { .fd = sf.fd, .flags = 1 };
    int sr = DIO(card, 0xC2, &si);
    CHECK("sync_file_import", sr == 0 && si.handle && so_wait(card, si.handle, now_ns() + NS, 0, 0) == 0, "sr=%d errno=%d", sr, errno);
    close(e.fd);
    CHECK("syncobj_survives_fd_close", so_wait(card, a, now_ns() + NS, 0, 0) == 0, "errno=%d", errno);
    close(sf.fd);
}

static void check_prime(void)
{
    struct create_dumb cd = { .height = 16, .width = 16, .bpp = 32 };
    struct map_dumb md;
    CHECKC("prime_create", DIO(card, 0xB2, &cd) == 0, "x");
    md = (struct map_dumb){ .handle = cd.handle };
    DIO(card, 0xB3, &md);
    uint32_t *px = mmap(0, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, card, md.offset);
    if (px == MAP_FAILED) { FAIL("prime_map", "errno=%d", errno); return; }
    px[0] = 0xC0FFEE11u;
    struct prime ex = { .handle = cd.handle, .flags = 0x80002 };
    CHECK("prime_export", DIO(card, 0x2D, &ex) == 0 && ex.fd >= 0, "errno=%d", errno);
    uint32_t *dm = mmap(0, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, ex.fd, 0);
    CHECK("prime_dmabuf_mmap_sees_data", dm != MAP_FAILED && dm[0] == 0xC0FFEE11u, "errno=%d v=%x", errno, dm == MAP_FAILED ? 0 : dm[0]);
    if (dm != MAP_FAILED) { dm[1] = 0x1234ABCDu; CHECK("prime_shared_writes", px[1] == 0x1234ABCDu, "v=%x", px[1]); }
    struct prime same = { .fd = ex.fd };
    CHECK("prime_import_same_client_dedup", DIO(card, 0x2E, &same) == 0 && same.handle == cd.handle, "h=%u want=%u", same.handle, cd.handle);
    struct prime other = { .fd = ex.fd };
    int rr = DIO(render, 0x2E, &other);
    CHECK("prime_import_other_client", rr == 0 && other.handle != 0, "rr=%d errno=%d", rr, errno);
    struct gem_close gc = { .handle = cd.handle };
    CHECK("prime_gem_close_keeps_buffer", DIO(card, 0x09, &gc) == 0 && dm != MAP_FAILED && dm[0] == 0xC0FFEE11u, "errno=%d", errno);
    struct prime back = { .fd = ex.fd };
    int br = DIO(card, 0x2E, &back);
    CHECK("prime_reimport_after_close", br == 0 && back.handle != 0, "br=%d errno=%d", br, errno);
    struct prime gone = { .handle = 4000 };
    CHECK("prime_export_bad_handle", DIO(card, 0x2D, &gone) < 0 && errno == ENOENT, "errno=%d", errno);
    int nul = open("/dev/null", O_RDONLY);
    struct prime wrong = { .fd = nul };
    CHECK("prime_import_wrong_kind", DIO(card, 0x2E, &wrong) < 0 && errno == EINVAL, "errno=%d", errno);
    close(nul);
    struct get_cap { uint64_t cap, value; } cap = { .cap = 5 };
    CHECK("cap_prime", DIO(card, 0x0C, &cap) == 0 && cap.value == 3, "v=%llu", (unsigned long long)cap.value);
    cap = (struct get_cap){ .cap = 0x13 };
    uint64_t a = DIO(card, 0x0C, &cap) == 0 ? cap.value : 0;
    cap = (struct get_cap){ .cap = 0x14 };
    uint64_t b = DIO(card, 0x0C, &cap) == 0 ? cap.value : 0;
    cap = (struct get_cap){ .cap = 0x12 };
    uint64_t c = DIO(card, 0x0C, &cap) == 0 ? cap.value : 0;
    CHECK("cap_syncobj_timeline_vblank_event", a == 1 && b == 1 && c == 1, "a=%llu b=%llu c=%llu", (unsigned long long)a, (unsigned long long)b, (unsigned long long)c);
}

int main(void)
{
    card = open("/dev/dri/card0", O_RDWR);
    render = open("/dev/dri/renderD128", O_RDWR);
    CHECKC("open_nodes", card >= 0 && render >= 0, "card=%d render=%d", card, render);
    if (card < 0 || render < 0) return 1;
    CHECKC("scanout_ready", scanout() == 0, "x");
    check_flip_events();
    check_vblank();
    check_syncobj_binary();
    check_timeline();
    check_syncfd();
    check_prime();
    printf("\nDRMX_DONE\n");
    fflush(stdout);
    return 0;
}
