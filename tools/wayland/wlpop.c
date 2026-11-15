// SPDX-License-Identifier: GPL-2.0-only
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <poll.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

#define PARENT_W 300
#define PARENT_H 200
#define POPUP_W 120
#define POPUP_H 80
#define ANCHOR_X 40
#define ANCHOR_Y 50
#define CHURN_ROUNDS 300
#define CHURN_SYNC_EVERY 10
#define PARENT_COLOUR 0xFFF2F2F2u
#define POPUP_COLOUR 0xFFE00000u

static const char *name = "?";
static struct wl_compositor *comp;
static struct wl_shm *shm;
static struct xdg_wm_base *wmbase;
static struct wl_seat *seat;
static struct wl_display *dpy;
static struct wl_surface *parent_surface;
static struct wl_surface *popup_surface;
static int parent_configured;
static int popup_configured;
static int popup_gone;
static struct xdg_popup *popup_obj;
static struct xdg_surface *popup_xdg;

static void say(const char *fmt, ...)
{
    char line[300];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    printf("wlpop[%s]: %s\n", name, line);
    fflush(stdout);
}

static long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static void pump_ms(long ms)
{
    long end = now_ms() + ms;
    while (now_ms() < end) {
        struct pollfd pfd;
        while (wl_display_prepare_read(dpy) != 0)
            wl_display_dispatch_pending(dpy);
        wl_display_flush(dpy);
        pfd.fd = wl_display_get_fd(dpy);
        pfd.events = POLLIN;
        if (poll(&pfd, 1, 20) > 0)
            wl_display_read_events(dpy);
        else
            wl_display_cancel_read(dpy);
        wl_display_dispatch_pending(dpy);
    }
}

static const char *surface_name(struct wl_surface *s)
{
    if (s == popup_surface)
        return "popup";
    if (s == parent_surface)
        return "parent";
    return "other";
}

static void p_enter(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *sf, wl_fixed_t x, wl_fixed_t y)
{
    say("ptr enter on=%s x=%d y=%d", surface_name(sf), wl_fixed_to_int(x), wl_fixed_to_int(y));
}
static void p_leave(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *sf)
{
    say("ptr leave on=%s", surface_name(sf));
}
static void p_motion(void *d, struct wl_pointer *p, uint32_t t, wl_fixed_t x, wl_fixed_t y) {}
static void p_button(void *d, struct wl_pointer *p, uint32_t s, uint32_t t, uint32_t b, uint32_t st)
{
    say("ptr button button=%u state=%u", b, st);
}
static void p_axis(void *d, struct wl_pointer *p, uint32_t t, uint32_t a, wl_fixed_t v) {}
static void p_frame(void *d, struct wl_pointer *p) {}
static void p_axis_source(void *d, struct wl_pointer *p, uint32_t s) {}
static void p_axis_stop(void *d, struct wl_pointer *p, uint32_t t, uint32_t a) {}
static void p_axis_discrete(void *d, struct wl_pointer *p, uint32_t a, int32_t v) {}
static const struct wl_pointer_listener p_l = { p_enter, p_leave, p_motion, p_button, p_axis, p_frame, p_axis_source, p_axis_stop, p_axis_discrete };

static void seat_caps(void *d, struct wl_seat *s, uint32_t caps)
{
    if (caps & WL_SEAT_CAPABILITY_POINTER)
        wl_pointer_add_listener(wl_seat_get_pointer(s), &p_l, NULL);
}
static void seat_name(void *d, struct wl_seat *s, const char *n) {}
static const struct wl_seat_listener seat_l = { seat_caps, seat_name };

static void reg_global(void *d, struct wl_registry *r, uint32_t n, const char *iface, uint32_t v)
{
    if (!strcmp(iface, "wl_compositor"))
        comp = wl_registry_bind(r, n, &wl_compositor_interface, 1);
    else if (!strcmp(iface, "wl_shm"))
        shm = wl_registry_bind(r, n, &wl_shm_interface, 1);
    else if (!strcmp(iface, "xdg_wm_base"))
        wmbase = wl_registry_bind(r, n, &xdg_wm_base_interface, 3);
    else if (!strcmp(iface, "wl_seat")) {
        seat = wl_registry_bind(r, n, &wl_seat_interface, v < 5 ? v : 5);
        wl_seat_add_listener(seat, &seat_l, NULL);
    }
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener reg_l = { reg_global, reg_remove };

static void ping(void *d, struct xdg_wm_base *b, uint32_t serial) { xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wm_l = { ping };

static void parent_conf(void *d, struct xdg_surface *xs, uint32_t serial)
{
    xdg_surface_ack_configure(xs, serial);
    parent_configured = 1;
}
static const struct xdg_surface_listener parent_xs_l = { parent_conf };

static void popup_conf(void *d, struct xdg_surface *xs, uint32_t serial)
{
    xdg_surface_ack_configure(xs, serial);
    popup_configured = 1;
}
static const struct xdg_surface_listener popup_xs_l = { popup_conf };

static void tl_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *s) {}
static void tl_close(void *d, struct xdg_toplevel *t) {}
static const struct xdg_toplevel_listener tl_l = { tl_configure, tl_close };

static void pp_configure(void *d, struct xdg_popup *p, int32_t x, int32_t y, int32_t w, int32_t h)
{
    say("popup configure x=%d y=%d w=%d h=%d", x, y, w, h);
}
static void pp_done(void *d, struct xdg_popup *p)
{
    say("popup done");
    popup_gone = 1;
}
static void pp_repositioned(void *d, struct xdg_popup *p, uint32_t token) {}
static const struct xdg_popup_listener pp_l = { pp_configure, pp_done, pp_repositioned };

static struct wl_buffer *make_solid(int w, int h, uint32_t colour)
{
    int stride = w * 4, size = stride * h, i;
    int fd = syscall(SYS_memfd_create, "wlpop", 0);
    uint32_t *px;
    struct wl_shm_pool *pool;
    struct wl_buffer *b;
    if (fd < 0 || ftruncate(fd, size) < 0)
        return NULL;
    px = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (px == MAP_FAILED)
        return NULL;
    for (i = 0; i < w * h; i++)
        px[i] = colour;
    pool = wl_shm_create_pool(shm, fd, size);
    b = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return b;
}

static struct xdg_surface *parent_xdg;

static int open_parent(void)
{
    struct xdg_toplevel *tl;
    struct wl_buffer *b;
    parent_surface = wl_compositor_create_surface(comp);
    parent_xdg = xdg_wm_base_get_xdg_surface(wmbase, parent_surface);
    xdg_surface_add_listener(parent_xdg, &parent_xs_l, NULL);
    tl = xdg_surface_get_toplevel(parent_xdg);
    xdg_toplevel_add_listener(tl, &tl_l, NULL);
    xdg_toplevel_set_title(tl, name);
    wl_surface_commit(parent_surface);
    while (!parent_configured && wl_display_dispatch(dpy) != -1)
        ;
    b = make_solid(PARENT_W, PARENT_H, PARENT_COLOUR);
    if (!b)
        return 0;
    wl_surface_attach(parent_surface, b, 0, 0);
    wl_surface_damage(parent_surface, 0, 0, PARENT_W, PARENT_H);
    wl_surface_commit(parent_surface);
    wl_display_roundtrip(dpy);
    return 1;
}

static struct xdg_positioner *make_positioner(void)
{
    struct xdg_positioner *pos = xdg_wm_base_create_positioner(wmbase);
    xdg_positioner_set_size(pos, POPUP_W, POPUP_H);
    xdg_positioner_set_anchor_rect(pos, ANCHOR_X, ANCHOR_Y, 1, 1);
    xdg_positioner_set_anchor(pos, XDG_POSITIONER_ANCHOR_TOP_LEFT);
    xdg_positioner_set_gravity(pos, XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT);
    return pos;
}

static void open_popup(void)
{
    struct xdg_positioner *pos = make_positioner();
    struct xdg_surface *xs;
    struct xdg_popup *pp;
    struct wl_buffer *b;
    popup_surface = wl_compositor_create_surface(comp);
    xs = xdg_wm_base_get_xdg_surface(wmbase, popup_surface);
    xdg_surface_add_listener(xs, &popup_xs_l, NULL);
    pp = xdg_surface_get_popup(xs, parent_xdg, pos);
    popup_obj = pp;
    popup_xdg = xs;
    xdg_popup_add_listener(pp, &pp_l, NULL);
    xdg_popup_grab(pp, seat, 1);
    xdg_positioner_destroy(pos);
    wl_surface_commit(popup_surface);
    while (!popup_configured && wl_display_dispatch(dpy) != -1)
        ;
    b = make_solid(POPUP_W, POPUP_H, POPUP_COLOUR);
    wl_surface_attach(popup_surface, b, 0, 0);
    wl_surface_damage(popup_surface, 0, 0, POPUP_W, POPUP_H);
    wl_surface_commit(popup_surface);
    wl_display_roundtrip(dpy);
    say("popup up");
}

static void churn_round(void)
{
    struct wl_region *rg = wl_compositor_create_region(comp);
    struct xdg_positioner *pos = make_positioner();
    struct wl_surface *s = wl_compositor_create_surface(comp);
    struct wl_surface *ps = wl_compositor_create_surface(comp);
    struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(wmbase, ps);
    struct xdg_popup *pp = xdg_surface_get_popup(xs, parent_xdg, pos);
    struct wl_touch *touch = wl_seat_get_touch(seat);
    struct wl_pointer *ptr = wl_seat_get_pointer(seat);
    struct wl_keyboard *kb = wl_seat_get_keyboard(seat);
    int fd = syscall(SYS_memfd_create, "wlchurn", 0);
    struct wl_shm_pool *pool;
    struct wl_buffer *b;
    wl_region_add(rg, 0, 0, 10, 10);
    wl_region_destroy(rg);
    wl_surface_destroy(s);
    xdg_popup_destroy(pp);
    xdg_surface_destroy(xs);
    wl_surface_destroy(ps);
    xdg_positioner_destroy(pos);
    wl_touch_release(touch);
    wl_pointer_release(ptr);
    wl_keyboard_release(kb);
    if (fd >= 0 && ftruncate(fd, 4096) == 0) {
        pool = wl_shm_create_pool(shm, fd, 4096);
        b = wl_shm_pool_create_buffer(pool, 0, 8, 8, 32, WL_SHM_FORMAT_XRGB8888);
        wl_buffer_destroy(b);
        wl_shm_pool_destroy(pool);
    }
    if (fd >= 0)
        close(fd);
}

static void run_churn(void)
{
    int i;
    for (i = 0; i < CHURN_ROUNDS; i++) {
        churn_round();
        if (i % CHURN_SYNC_EVERY == CHURN_SYNC_EVERY - 1 && wl_display_roundtrip(dpy) < 0) {
            say("churn FAIL round=%d err=%d", i, wl_display_get_error(dpy));
            return;
        }
    }
    if (wl_display_roundtrip(dpy) < 0)
        say("churn FAIL end err=%d", wl_display_get_error(dpy));
    else
        say("churn ok rounds=%d err=%d", CHURN_ROUNDS, wl_display_get_error(dpy));
}

int main(int argc, char **argv)
{
    const char *sock = argc > 1 ? argv[1] : "/tmp/wayland-0";
    int secs = argc > 2 ? atoi(argv[2]) : 60;
    int do_churn = 0, do_popup = 0, i;
    long end;

    if (argc > 3)
        name = argv[3];
    for (i = 4; i < argc; i++) {
        if (!strcmp(argv[i], "churn"))
            do_churn = 1;
        else if (!strcmp(argv[i], "popup"))
            do_popup = 1;
    }
    dpy = wl_display_connect(sock);
    if (!dpy) {
        say("no display");
        return 1;
    }
    wl_registry_add_listener(wl_display_get_registry(dpy), &reg_l, NULL);
    wl_display_roundtrip(dpy);
    if (!comp || !shm || !wmbase || !seat) {
        say("globals missing");
        return 1;
    }
    xdg_wm_base_add_listener(wmbase, &wm_l, NULL);
    wl_display_roundtrip(dpy);
    if (!open_parent()) {
        say("no buffer");
        return 1;
    }
    say("window up %dx%d", PARENT_W, PARENT_H);
    if (do_churn)
        run_churn();
    if (do_popup)
        open_popup();
    end = now_ms() + secs * 1000L;
    while (now_ms() < end) {
        pump_ms(100);
        if (popup_gone && popup_surface) {
            xdg_popup_destroy(popup_obj);
            xdg_surface_destroy(popup_xdg);
            wl_surface_destroy(popup_surface);
            popup_surface = NULL;
            say("popup surface destroyed");
        }
    }
    say("end");
    wl_display_disconnect(dpy);
    return 0;
}
