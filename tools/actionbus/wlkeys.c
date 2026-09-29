/* SPDX-License-Identifier: GPL-2.0-only
 * tools/actionbus/wlkeys.c -- A LINUX WAYLAND PROGRAM THAT KNOWS NOTHING
 * OF ORIENTOS, for the foreign-window adapters of the action bus (AB-008b).
 *
 * Plain C against libwayland-client and xdg-shell, built with musl as a
 * static Linux binary -- the same way tools/wayland builds weston's
 * simple-shm. It opens one window titled "Fake Viewer" (app id
 * "fakeviewer"), paints it, and writes every key, button and close it
 * receives to standard output and to /tmp/wlkeys.log:
 *
 *   wlkeys: key=30 state=1        (Linux evdev code, 1 pressed / 0 released)
 *   wlkeys: button=272 state=1 x=40 y=30
 *   wlkeys: close
 *
 * It reads raw evdev codes and needs no keymap -- which is what wayd
 * offers today (no wl_keyboard.keymap, see kernel/user/wayd.fi).
 *
 *   wlkeys [socket] [seconds]     default /tmp/wayland-0, 60 s
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
#include <sys/mman.h>
#include <sys/syscall.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

#define W 200
#define H 120

static struct wl_compositor *comp;
static struct wl_shm *shm;
static struct xdg_wm_base *wmbase;
static struct wl_seat *seat;
static struct wl_surface *surf;
static struct wl_buffer *buf;
static int configured, done;
static FILE *logfp;
static int px, py;

static void say(const char *fmt, long a, long b, long c, long d)
{
    char line[160];
    snprintf(line, sizeof line, fmt, a, b, c, d);
    fputs(line, stdout);
    fflush(stdout);
    if (logfp) {
        fputs(line, logfp);
        fflush(logfp);
    }
}

/* ---------------------------------------------------------- keyboard */
static void kb_keymap(void *d, struct wl_keyboard *k, uint32_t f, int32_t fd, uint32_t n)
{
    close(fd);
}
static void kb_enter(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *sf, struct wl_array *keys)
{
    say("wlkeys: keyboard enter\n", 0, 0, 0, 0);
}
static void kb_leave(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *sf) {}
static void kb_key(void *d, struct wl_keyboard *k, uint32_t s, uint32_t t, uint32_t key, uint32_t st)
{
    say("wlkeys: key=%ld state=%ld\n", key, st, 0, 0);
}
static void kb_mods(void *d, struct wl_keyboard *k, uint32_t s, uint32_t a, uint32_t b, uint32_t c, uint32_t g) {}
static const struct wl_keyboard_listener kb_l = { kb_keymap, kb_enter, kb_leave, kb_key, kb_mods };

/* ----------------------------------------------------------- pointer */
static void p_enter(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *sf, wl_fixed_t x, wl_fixed_t y)
{
    px = wl_fixed_to_int(x);
    py = wl_fixed_to_int(y);
}
static void p_leave(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *sf) {}
static void p_motion(void *d, struct wl_pointer *p, uint32_t t, wl_fixed_t x, wl_fixed_t y)
{
    px = wl_fixed_to_int(x);
    py = wl_fixed_to_int(y);
}
static void p_button(void *d, struct wl_pointer *p, uint32_t s, uint32_t t, uint32_t b, uint32_t st)
{
    say("wlkeys: button=%ld state=%ld x=%ld y=%ld\n", b, st, px, py);
}
static void p_axis(void *d, struct wl_pointer *p, uint32_t t, uint32_t a, wl_fixed_t v) {}
static const struct wl_pointer_listener p_l = { p_enter, p_leave, p_motion, p_button, p_axis };

/* -------------------------------------------------------------- seat */
static void seat_caps(void *d, struct wl_seat *s, uint32_t caps)
{
    if (caps & WL_SEAT_CAPABILITY_KEYBOARD)
        wl_keyboard_add_listener(wl_seat_get_keyboard(s), &kb_l, NULL);
    if (caps & WL_SEAT_CAPABILITY_POINTER)
        wl_pointer_add_listener(wl_seat_get_pointer(s), &p_l, NULL);
    say("wlkeys: seat caps=%ld\n", caps, 0, 0, 0);
}
static void seat_name(void *d, struct wl_seat *s, const char *n) {}
static const struct wl_seat_listener seat_l = { seat_caps, seat_name };

/* --------------------------------------------------------- xdg-shell */
static void ping(void *d, struct xdg_wm_base *b, uint32_t serial)
{
    xdg_wm_base_pong(b, serial);
}
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
    say("wlkeys: close\n", 0, 0, 0, 0);
    done = 1;
}
static const struct xdg_toplevel_listener tl_l = { tl_conf, tl_close };

/* ---------------------------------------------------------- registry */
static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t v)
{
    if (!strcmp(iface, "wl_compositor"))
        comp = wl_registry_bind(r, name, &wl_compositor_interface, 1);
    else if (!strcmp(iface, "wl_shm"))
        shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
    else if (!strcmp(iface, "xdg_wm_base"))
        wmbase = wl_registry_bind(r, name, &xdg_wm_base_interface, 1);
    else if (!strcmp(iface, "wl_seat")) {
        /* the listener at once: the seat says what it has right after
         * the bind, in the same roundtrip */
        seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
        wl_seat_add_listener(seat, &seat_l, NULL);
    }
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener reg_l = { reg_global, reg_remove };

static struct wl_buffer *make_buffer(void)
{
    int stride = W * 4, size = stride * H;
    int fd = syscall(SYS_memfd_create, "wlkeys", 0);
    uint32_t *px0;
    struct wl_shm_pool *pool;
    struct wl_buffer *b;
    int i;
    if (fd < 0 || ftruncate(fd, size) < 0)
        return NULL;
    px0 = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (px0 == MAP_FAILED)
        return NULL;
    for (i = 0; i < W * H; i++)
        px0[i] = (i / W) < 24 ? 0xFF2D6CDF : 0xFFF2F2F2;
    pool = wl_shm_create_pool(shm, fd, size);
    b = wl_shm_pool_create_buffer(pool, 0, W, H, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return b;
}

static void wl_log_cb(const char *fmt, va_list ap)
{
    char line[200];
    vsnprintf(line, sizeof line, fmt, ap);
    printf("wlkeys: libwayland: %s", line);
    fflush(stdout);
}

int main(int argc, char **argv)
{
    const char *sock = argc > 1 ? argv[1] : "/tmp/wayland-0";
    int secs = argc > 2 ? atoi(argv[2]) : 60;
    struct wl_display *dpy;
    struct xdg_surface *xs;
    struct xdg_toplevel *tl;
    time_t t0 = time(NULL);

    logfp = fopen("/tmp/wlkeys.log", "w");
    say("wlkeys: start\n", 0, 0, 0, 0);
    wl_log_set_handler_client(wl_log_cb);
    dpy = wl_display_connect(sock);
    if (!dpy) {
        say("wlkeys: no display\n", 0, 0, 0, 0);
        return 1;
    }
    say("wlkeys: connected fd=%ld\n", wl_display_get_fd(dpy), 0, 0, 0);
    wl_registry_add_listener(wl_display_get_registry(dpy), &reg_l, NULL);
    {
        int f = wl_display_flush(dpy);
        say("wlkeys: flush=%ld\n", f, 0, 0, 0);
    }
    say("wlkeys: roundtrip=%ld\n", wl_display_roundtrip(dpy), 0, 0, 0);
    if (!comp || !shm || !wmbase || !seat) {
        say("wlkeys: globals missing comp=%ld shm=%ld wm=%ld seat=%ld\n",
            comp != 0, shm != 0, wmbase != 0, seat != 0);
        return 1;
    }
    xdg_wm_base_add_listener(wmbase, &wm_l, NULL);
    surf = wl_compositor_create_surface(comp);
    xs = xdg_wm_base_get_xdg_surface(wmbase, surf);
    xdg_surface_add_listener(xs, &xs_l, NULL);
    tl = xdg_surface_get_toplevel(xs);
    xdg_toplevel_add_listener(tl, &tl_l, NULL);
    xdg_toplevel_set_title(tl, "Fake Viewer");
    xdg_toplevel_set_app_id(tl, "fakeviewer");
    wl_surface_commit(surf);
    while (!configured && wl_display_dispatch(dpy) != -1)
        ;
    buf = make_buffer();
    if (!buf) {
        say("wlkeys: no buffer\n", 0, 0, 0, 0);
        return 1;
    }
    wl_surface_attach(surf, buf, 0, 0);
    wl_surface_damage(surf, 0, 0, W, H);
    wl_surface_commit(surf);
    wl_display_roundtrip(dpy);
    say("wlkeys: window up %ldx%ld\n", W, H, 0, 0);
    while (!done && time(NULL) - t0 < secs) {
        if (wl_display_dispatch_pending(dpy) < 0)
            break;
        wl_display_flush(dpy);
        if (wl_display_prepare_read(dpy) == 0) {
            wl_display_read_events(dpy);
        }
        usleep(20000);
    }
    say("wlkeys: end\n", 0, 0, 0, 0);
    wl_display_disconnect(dpy);
    return 0;
}
