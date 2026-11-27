// SPDX-License-Identifier: GPL-2.0-only
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <poll.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

#define WIDTH 400
#define HEIGHT 300
#define NOISE_FRAMES 100
#define RED 0xFFC81414u
#define BLUE 0xFF1414C8u
#define GREEN 0xFF14C814u
#define BLUE_X 40
#define BLUE_Y 30
#define BLUE_W 60
#define BLUE_H 40
#define GREEN_X 200
#define GREEN_Y 150
#define GREEN_W 60
#define GREEN_H 50

static struct wl_compositor *comp;
static struct wl_shm *shm;
static struct xdg_wm_base *wmbase;
static struct wl_display *dpy;
static struct wl_surface *surf;
static int configured;
static uint32_t *px;
static struct wl_buffer *buf;

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

static void say(const char *what, long v)
{
    printf("wldamage: %s=%ld\n", what, v);
    fflush(stdout);
}

static void reg_global(void *d, struct wl_registry *r, uint32_t n, const char *iface, uint32_t v)
{
    if (!strcmp(iface, "wl_compositor"))
        comp = wl_registry_bind(r, n, &wl_compositor_interface, 1);
    else if (!strcmp(iface, "wl_shm"))
        shm = wl_registry_bind(r, n, &wl_shm_interface, 1);
    else if (!strcmp(iface, "xdg_wm_base"))
        wmbase = wl_registry_bind(r, n, &xdg_wm_base_interface, 3);
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener reg_l = { reg_global, reg_remove };

static void ping(void *d, struct xdg_wm_base *b, uint32_t serial) { xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wm_l = { ping };

static void xs_conf(void *d, struct xdg_surface *xs, uint32_t serial)
{
    xdg_surface_ack_configure(xs, serial);
    configured = 1;
}
static const struct xdg_surface_listener xs_l = { xs_conf };

static void tl_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *s) {}
static void tl_close(void *d, struct xdg_toplevel *t) {}
static const struct xdg_toplevel_listener tl_l = { tl_configure, tl_close };

static int make_buffer(void)
{
    int stride = WIDTH * 4, size = stride * HEIGHT;
    int fd = syscall(SYS_memfd_create, "wldamage", 0);
    struct wl_shm_pool *pool;
    if (fd < 0 || ftruncate(fd, size) < 0)
        return 0;
    px = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (px == MAP_FAILED)
        return 0;
    pool = wl_shm_create_pool(shm, fd, size);
    buf = wl_shm_pool_create_buffer(pool, 0, WIDTH, HEIGHT, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return buf != NULL;
}

static void fill_rect(int x0, int y0, int w, int h, uint32_t colour)
{
    int x, y;
    for (y = y0; y < y0 + h; y++)
        for (x = x0; x < x0 + w; x++)
            px[y * WIDTH + x] = colour;
}

static void commit_damage(int x, int y, int w, int h)
{
    wl_surface_attach(surf, buf, 0, 0);
    wl_surface_damage_buffer(surf, x, y, w, h);
    wl_surface_commit(surf);
}

static void fill_noise(uint32_t *seed)
{
    int i;
    for (i = 0; i < WIDTH * HEIGHT; i++) {
        *seed ^= *seed << 13;
        *seed ^= *seed >> 17;
        *seed ^= *seed << 5;
        px[i] = 0xFF000000u | (*seed & 0xFFFFFF);
    }
}

int main(int argc, char **argv)
{
    struct wl_registry *reg;
    struct xdg_surface *xs;
    struct xdg_toplevel *tl;
    uint32_t seed = 2463534242u;
    long t0;
    int i;
    dpy = wl_display_connect(argc > 1 ? argv[1] : NULL);
    if (!dpy)
        return 1;
    reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &reg_l, NULL);
    wl_display_roundtrip(dpy);
    if (!comp || !shm || !wmbase || !make_buffer())
        return 2;
    xdg_wm_base_add_listener(wmbase, &wm_l, NULL);
    surf = wl_compositor_create_surface(comp);
    xs = xdg_wm_base_get_xdg_surface(wmbase, surf);
    xdg_surface_add_listener(xs, &xs_l, NULL);
    tl = xdg_surface_get_toplevel(xs);
    xdg_toplevel_add_listener(tl, &tl_l, NULL);
    xdg_toplevel_set_title(tl, "wldamage");
    wl_surface_commit(surf);
    while (!configured && wl_display_dispatch(dpy) != -1)
        ;
    fill_rect(0, 0, WIDTH, HEIGHT, RED);
    commit_damage(0, 0, WIDTH, HEIGHT);
    wl_display_roundtrip(dpy);
    pump_ms(2000);
    say("phase_red", 1);
    t0 = now_ms();
    for (i = 0; i < NOISE_FRAMES; i++) {
        fill_noise(&seed);
        commit_damage(0, 0, WIDTH, HEIGHT);
        wl_display_roundtrip(dpy);
    }
    say("noise_ms", now_ms() - t0);
    fill_rect(0, 0, WIDTH, HEIGHT, RED);
    commit_damage(0, 0, WIDTH, HEIGHT);
    wl_display_roundtrip(dpy);
    pump_ms(2000);
    fill_rect(BLUE_X, BLUE_Y, BLUE_W, BLUE_H, BLUE);
    fill_rect(GREEN_X, GREEN_Y, GREEN_W, GREEN_H, GREEN);
    commit_damage(BLUE_X, BLUE_Y, BLUE_W, BLUE_H);
    wl_display_roundtrip(dpy);
    say("partial_committed", 1);
    pump_ms(600000);
    return 0;
}
