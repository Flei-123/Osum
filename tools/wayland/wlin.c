/* SPDX-License-Identifier: GPL-2.0-only
 * tools/wayland/wlin.c -- A LINUX WAYLAND PROGRAM THAT LOGS WHAT THE SEAT SENDS AND TALKS CLIPBOARD.
 *
 * Plain C against libwayland-client and xdg-shell, static musl, the way weston-simple-shm is built (tools/wayland/input.sh). It
 * opens one 200x120 window and writes every keyboard, pointer and data device event it gets to standard output:
 *
 *   wlin[A]: keymap fmt=1 size=64434 crc=0x1234abcd head=xkb_keymap
 *   wlin[A]: kb enter serial=102 surface=ours
 *   wlin[A]: key serial=105 key=30 state=1
 *   wlin[A]: mods depressed=1
 *   wlin[A]: ptr enter serial=120 x=40 y=30
 *   wlin[A]: ptr motion x=41 y=30
 *   wlin[A]: ptr button serial=121 button=272 state=1
 *   wlin[A]: paste=hello      selection=none     source send mime=... wrote=5     source cancelled
 *
 *   wlin <socket> <seconds> <name> [copy=TEXT] [paste] [badserial] [noseat]
 *
 *   copy=TEXT   at the FIRST key press: make a wl_data_source, offer text, set_selection(source, the serial of that key)
 *   badserial   at the first key press: set_selection with a serial that was never given (must be refused: `source cancelled`)
 *   paste       when a selection arrives: receive it through a pipe and print paste=...  (the pipe is read without blocking, 3 s)
 *   noseat      do not bind the seat (counter-proof: such a client gets no input at all)
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <poll.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

#define W 200
#define H 120
#define SYS_OSUM_BUS 1960
#define SYS_OSUM_SPERRE 1870
static time_t lock_until, idle_until;
static long idle_a;

static const char *name = "?";
static struct wl_compositor *comp;
static struct wl_shm *shm;
static struct xdg_wm_base *wmbase;
static struct wl_seat *seat;
static struct wl_data_device_manager *ddm;
static struct wl_data_device *ddev;
static struct wl_display *g_dpy;
static struct wl_surface *surf;
static struct wl_buffer *buf;
static struct wl_data_source *src;
static struct wl_data_offer *cur_offer;
static int configured, done;
static int do_copy, do_paste, do_bad, no_seat;
static const char *copy_text = "";
static char offered[8][64];
static int n_offered;
static int did_set;
static uint32_t seat_ver;
static void sysclip(const char *tag);

static void say(const char *fmt, ...)
{
    char line[300];
    char out[340];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    snprintf(out, sizeof out, "wlin[%s]: %s\n", name, line);
    fputs(out, stdout);
    fflush(stdout);
}

static uint32_t crc32(const unsigned char *p, size_t n)
{
    uint32_t c = 0xFFFFFFFFu;
    size_t i;
    int k;
    for (i = 0; i < n; i++) {
        c ^= p[i];
        for (k = 0; k < 8; k++)
            c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1)));
    }
    return ~c;
}

/* ------------------------------------------------------------ clipboard */
static void src_target(void *d, struct wl_data_source *s, const char *m) {}
static void src_send(void *d, struct wl_data_source *s, const char *mime, int32_t fd)
{
    ssize_t w = write(fd, copy_text, strlen(copy_text));
    close(fd);
    say("source send mime=%s wrote=%ld", mime, (long)w);
}
static void src_cancelled(void *d, struct wl_data_source *s)
{
    say("source cancelled");
    wl_data_source_destroy(s);
    if (s == src)
        src = NULL;
}
static void src_dnd_drop(void *d, struct wl_data_source *s) {}
static void src_dnd_fin(void *d, struct wl_data_source *s) {}
static void src_action(void *d, struct wl_data_source *s, uint32_t a) {}
static const struct wl_data_source_listener src_l = { src_target, src_send, src_cancelled, src_dnd_drop, src_dnd_fin, src_action };

static void do_set_selection(uint32_t serial)
{
    if (!ddm || !ddev)
        return;
    src = wl_data_device_manager_create_data_source(ddm);
    wl_data_source_add_listener(src, &src_l, NULL);
    wl_data_source_offer(src, "text/plain;charset=utf-8");
    wl_data_source_offer(src, "text/plain");
    wl_data_device_set_selection(ddev, src, serial);
    say("set_selection serial=%u", serial);
    did_set = 1;
}

static void off_offer(void *d, struct wl_data_offer *o, const char *mime)
{
    if (n_offered < 8) {
        snprintf(offered[n_offered], 64, "%s", mime);
        n_offered++;
    }
    say("offer mime=%s", mime);
}
static void off_src_actions(void *d, struct wl_data_offer *o, uint32_t a) {}
static void off_action(void *d, struct wl_data_offer *o, uint32_t a) {}
static const struct wl_data_offer_listener off_l = { off_offer, off_src_actions, off_action };

static void dd_data_offer(void *d, struct wl_data_device *dev, struct wl_data_offer *o)
{
    n_offered = 0;
    cur_offer = o;
    wl_data_offer_add_listener(o, &off_l, NULL);
    say("data_offer");
}
static void dd_enter(void *d, struct wl_data_device *dev, uint32_t s, struct wl_surface *sf, wl_fixed_t x, wl_fixed_t y, struct wl_data_offer *o) {}
static void dd_leave(void *d, struct wl_data_device *dev) {}
static void dd_motion(void *d, struct wl_data_device *dev, uint32_t t, wl_fixed_t x, wl_fixed_t y) {}
static void dd_drop(void *d, struct wl_data_device *dev) {}
static void dd_selection(void *d, struct wl_data_device *dev, struct wl_data_offer *o)
{
    int fds[2], i, have = 0, got = 0;
    char text[256];
    time_t t0;
    if (!o) {
        say("selection=none");
        return;
    }
    say("selection offers=%d", n_offered);
    if (!do_paste)
        return;
    for (i = 0; i < n_offered; i++)
        if (!strcmp(offered[i], "text/plain;charset=utf-8"))
            have = 1;
    if (!have) {
        say("paste=no text type");
        return;
    }
    if (pipe(fds) < 0) {
        say("paste=no pipe");
        return;
    }
    wl_data_offer_receive(o, "text/plain;charset=utf-8", fds[1]);
    close(fds[1]);
    wl_display_flush(g_dpy);
    /* the display is flushed by the main loop; read without blocking, 3 s */
    t0 = time(NULL);
    fcntl(fds[0], F_SETFL, O_NONBLOCK);
    for (;;) {
        ssize_t n = read(fds[0], text + got, sizeof text - 1 - got);
        if (n > 0) {
            got += n;
        } else if (n == 0) {
            break;
        } else if (errno != EAGAIN) {
            break;
        }
        if (time(NULL) - t0 >= 3)
            break;
        /* pump the connection so our own request really goes out */
        wl_display_flush(g_dpy);
        usleep(20000);
    }
    close(fds[0]);
    text[got] = 0;
    say("paste=%s", text);
    sysclip("sysclip");
}
static const struct wl_data_device_listener dd_l = { dd_data_offer, dd_enter, dd_leave, dd_motion, dd_drop, dd_selection };

/* ------------------------------------------------------------- keyboard */
static void kb_keymap(void *d, struct wl_keyboard *k, uint32_t fmt, int32_t fd, uint32_t size)
{
    char head[16] = "";
    uint32_t crc = 0;
    if (fmt == 1 && size > 0) {
        void *p = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (p != MAP_FAILED) {
            memcpy(head, p, 10);
            head[10] = 0;
            /* the protocol counts the closing zero in the size */
            crc = crc32(p, size - 1);
            munmap(p, size);
        } else {
            strcpy(head, "MMAP-FAILED");
        }
    }
    say("keymap fmt=%u size=%u crc=0x%08x head=%s", fmt, size, crc, head);
    close(fd);
}
static void kb_enter(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *sf, struct wl_array *keys)
{
    say("kb enter serial=%u surface=%s keys=%u", s, sf == surf ? "ours" : "other", (unsigned)keys->size);
}
static void kb_leave(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *sf)
{
    say("kb leave serial=%u surface=%s", s, sf == surf ? "ours" : "other");
}
static void sysclip(const char *tag)
{
    char buf[256];
    uint64_t meta[6];
    long n;
    memset(buf, 0, sizeof buf);
    n = syscall(SYS_OSUM_BUS, 11, 0, buf, 192, meta, 0);
    if (n > 0)
        say("%s=%s", tag, buf);
    else
        say("%s=<none>", tag);
}

static void kb_key(void *d, struct wl_keyboard *k, uint32_t s, uint32_t t, uint32_t key, uint32_t st)
{
    say("key serial=%u key=%u state=%u", s, key, st);
    if (st == 1 && key == 67) { /* F9: a NATIVE copy: the OrientOS clipboard is set by this process through the bus system call */
        const char *txt = "native-says-hi";
        long r = syscall(SYS_OSUM_BUS, 10, 1, txt, (long)strlen(txt), 0, 0);
        say("native clip_set r=%ld", r);
    }
    if (st == 1 && key == 68) { /* F10: lock the screen for 12 s (op 1 locks, op 4 makes this program the locker so that it can unlock) */
        long r = syscall(SYS_OSUM_SPERRE, 1, 0, 0);
        long r4 = syscall(SYS_OSUM_SPERRE, 4, 0, 0);
        lock_until = time(NULL) + 12;
        say("lock on r=%ld locker=%ld", r, r4);
    }
    if (st == 1 && key == 66 && ddm && ddev) /* F8: copy again */
        do_set_selection(s);
    if (st == 1 && key == 64) { /* F6: die at once, without a word to the compositor: no destroy, no disconnect */
        say("exit now");
        _exit(3);
    }
    if (st == 1 && key == 62) { /* F4: die by a fault (the process is killed by SIGSEGV) */
        say("crash now");
        *(volatile int *)0 = 1;
    }
    if (st == 1 && key == 63) { /* F5: count the system calls of the whole system over the next 5 s (nobody touching anything) */
        idle_a = syscall(1002, 10, 0, 0);
        idle_until = time(NULL) + 5;
    }
    if (st == 1 && key == 65)   /* F7: show what the system clipboard holds */
        sysclip("sysclip");
    if (st == 1 && !did_set && key < 60) {
        if (do_bad)
            do_set_selection(s + 5000); /* a serial this client was never given */
        else if (do_copy)
            do_set_selection(s);
    }
}
static void kb_mods(void *d, struct wl_keyboard *k, uint32_t s, uint32_t a, uint32_t b, uint32_t c, uint32_t g)
{
    say("mods serial=%u depressed=%u latched=%u locked=%u group=%u", s, a, b, c, g);
}
static void kb_repeat(void *d, struct wl_keyboard *k, int32_t rate, int32_t delay)
{
    say("repeat rate=%d delay=%d", rate, delay);
}
static const struct wl_keyboard_listener kb_l = { kb_keymap, kb_enter, kb_leave, kb_key, kb_mods, kb_repeat };

/* -------------------------------------------------------------- pointer */
static void p_enter(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *sf, wl_fixed_t x, wl_fixed_t y)
{
    say("ptr enter serial=%u surface=%s x=%d y=%d", s, sf == surf ? "ours" : "other", wl_fixed_to_int(x), wl_fixed_to_int(y));
}
static void p_leave(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *sf)
{
    say("ptr leave serial=%u", s);
}
static void p_motion(void *d, struct wl_pointer *p, uint32_t t, wl_fixed_t x, wl_fixed_t y)
{
    say("ptr motion x=%d y=%d", wl_fixed_to_int(x), wl_fixed_to_int(y));
}
static void p_button(void *d, struct wl_pointer *p, uint32_t s, uint32_t t, uint32_t b, uint32_t st)
{
    say("ptr button serial=%u button=%u state=%u", s, b, st);
}
static void p_axis(void *d, struct wl_pointer *p, uint32_t t, uint32_t a, wl_fixed_t v)
{
    say("ptr axis axis=%u value=%d", a, wl_fixed_to_int(v));
}
static void p_frame(void *d, struct wl_pointer *p) { say("ptr frame"); }
static void p_axis_source(void *d, struct wl_pointer *p, uint32_t s) {}
static void p_axis_stop(void *d, struct wl_pointer *p, uint32_t t, uint32_t a) {}
static void p_axis_discrete(void *d, struct wl_pointer *p, uint32_t a, int32_t v) {}
static const struct wl_pointer_listener p_l = { p_enter, p_leave, p_motion, p_button, p_axis, p_frame, p_axis_source, p_axis_stop, p_axis_discrete };

/* ----------------------------------------------------------------- seat */
static void seat_caps(void *d, struct wl_seat *s, uint32_t caps)
{
    if (caps & WL_SEAT_CAPABILITY_KEYBOARD)
        wl_keyboard_add_listener(wl_seat_get_keyboard(s), &kb_l, NULL);
    if (caps & WL_SEAT_CAPABILITY_POINTER)
        wl_pointer_add_listener(wl_seat_get_pointer(s), &p_l, NULL);
    if (ddm && !ddev) {
        ddev = wl_data_device_manager_get_data_device(ddm, s);
        wl_data_device_add_listener(ddev, &dd_l, NULL);
    }
    say("seat caps=%u version=%u", caps, seat_ver);
}
static void seat_name(void *d, struct wl_seat *s, const char *n) { say("seat name=%s", n); }
static const struct wl_seat_listener seat_l = { seat_caps, seat_name };

/* ------------------------------------------------------------ xdg-shell */
static void ping(void *d, struct xdg_wm_base *b, uint32_t serial) { xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wm_l = { ping };
static void xs_conf(void *d, struct xdg_surface *xs, uint32_t serial)
{
    xdg_surface_ack_configure(xs, serial);
    configured = 1;
}
static const struct xdg_surface_listener xs_l = { xs_conf };
static void tl_conf(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *st) {}
static void tl_close(void *d, struct xdg_toplevel *t)
{
    say("close");
    done = 1;
}
static const struct xdg_toplevel_listener tl_l = { tl_conf, tl_close };

static void reg_global(void *d, struct wl_registry *r, uint32_t n, const char *iface, uint32_t v)
{
    if (!strcmp(iface, "wl_compositor"))
        comp = wl_registry_bind(r, n, &wl_compositor_interface, 1);
    else if (!strcmp(iface, "wl_shm"))
        shm = wl_registry_bind(r, n, &wl_shm_interface, 1);
    else if (!strcmp(iface, "xdg_wm_base"))
        wmbase = wl_registry_bind(r, n, &xdg_wm_base_interface, 1);
    else if (!strcmp(iface, "wl_data_device_manager"))
        ddm = wl_registry_bind(r, n, &wl_data_device_manager_interface, v < 3 ? v : 3);
    else if (!strcmp(iface, "wl_seat") && !no_seat) {
        seat_ver = v < 5 ? v : 5;
        seat = wl_registry_bind(r, n, &wl_seat_interface, seat_ver);
        wl_seat_add_listener(seat, &seat_l, NULL);
    }
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener reg_l = { reg_global, reg_remove };

static struct wl_buffer *make_buffer(void)
{
    int stride = W * 4, size = stride * H, i;
    int fd = syscall(SYS_memfd_create, "wlin", 0);
    uint32_t *px;
    struct wl_shm_pool *pool;
    struct wl_buffer *b;
    if (fd < 0 || ftruncate(fd, size) < 0)
        return NULL;
    px = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (px == MAP_FAILED)
        return NULL;
    for (i = 0; i < W * H; i++)
        px[i] = (i / W) < 24 ? 0xFF2D6CDF : 0xFFF2F2F2;
    pool = wl_shm_create_pool(shm, fd, size);
    b = wl_shm_pool_create_buffer(pool, 0, W, H, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return b;
}

int main(int argc, char **argv)
{
    const char *sock = argc > 1 ? argv[1] : "/tmp/wayland-0";
    int secs = argc > 2 ? atoi(argv[2]) : 60;
    struct wl_display *dpy;
    struct xdg_surface *xs;
    struct xdg_toplevel *tl;
    time_t t0 = time(NULL);
    int i;

    if (argc > 3)
        name = argv[3];
    for (i = 4; i < argc; i++) {
        if (!strncmp(argv[i], "copy=", 5)) {
            do_copy = 1;
            copy_text = argv[i] + 5;
        } else if (!strcmp(argv[i], "paste")) {
            do_paste = 1;
        } else if (!strcmp(argv[i], "badserial")) {
            do_bad = 1;
        } else if (!strcmp(argv[i], "noseat")) {
            no_seat = 1;
        }
    }
    say("start");
    dpy = wl_display_connect(sock);
    g_dpy = dpy;
    if (!dpy) {
        say("no display");
        return 1;
    }
    wl_registry_add_listener(wl_display_get_registry(dpy), &reg_l, NULL);
    wl_display_roundtrip(dpy);
    if (!comp || !shm || !wmbase || (!seat && !no_seat)) {
        say("globals missing");
        return 1;
    }
    xdg_wm_base_add_listener(wmbase, &wm_l, NULL);
    surf = wl_compositor_create_surface(comp);
    xs = xdg_wm_base_get_xdg_surface(wmbase, surf);
    xdg_surface_add_listener(xs, &xs_l, NULL);
    tl = xdg_surface_get_toplevel(xs);
    xdg_toplevel_add_listener(tl, &tl_l, NULL);
    xdg_toplevel_set_title(tl, name);
    xdg_toplevel_set_app_id(tl, "wlin");
    wl_surface_commit(surf);
    while (!configured && wl_display_dispatch(dpy) != -1)
        ;
    buf = make_buffer();
    if (!buf) {
        say("no buffer");
        return 1;
    }
    wl_surface_attach(surf, buf, 0, 0);
    wl_surface_damage(surf, 0, 0, W, H);
    wl_surface_commit(surf);
    wl_display_roundtrip(dpy);
    say("window up %dx%d", W, H);
    while (!done && time(NULL) - t0 < secs) {
        struct pollfd pfd;
        while (wl_display_prepare_read(dpy) != 0)
            wl_display_dispatch_pending(dpy);
        wl_display_flush(dpy);
        pfd.fd = wl_display_get_fd(dpy);
        pfd.events = POLLIN;
        if (poll(&pfd, 1, 50) > 0)
            wl_display_read_events(dpy);
        else
            wl_display_cancel_read(dpy);
        if (wl_display_dispatch_pending(dpy) < 0)
            break;
        if (idle_until && time(NULL) >= idle_until) {
            long b = syscall(1002, 10, 0, 0);
            say("idle syscalls=%ld in 5 s", b - idle_a);
            idle_until = 0;
        }
        if (lock_until && time(NULL) >= lock_until) {
            long r = syscall(SYS_OSUM_SPERRE, 2, 0, 0);
            lock_until = 0;
            say("lock off r=%ld", r);
        }
    }
    say("end");
    wl_display_disconnect(dpy);
    return 0;
}
