// SPDX-License-Identifier: GPL-2.0-only
// tools/wayland/wlclient.c -- STUFE 1: ein Client gegen libwayland-client.
//
// Das ist KEIN Nachbau des Protokolls. Dieses Programm ruft
// wl_display_connect, wl_registry, wl_shm, xdg_surface und
// wl_surface_commit -- die echten Funktionen der echten Bibliothek
// (libwayland-client 1.21.0, unveraendert, statisch gegen musl). Was
// hier gemessen wird, ist deshalb der SERVER und nicht ein Selbstgespraech.
//
// Gemalt wird ein BEKANNTES MUSTER, damit das Bildschirmfoto nachpruefbar
// ist und nicht nur "irgendwas Buntes" zeigt:
//
//   ein 200x150 grosses Fenster
//   Hintergrund      0xFF202060  (dunkelblau)
//   ein Balken oben  0xFFE00000  (rot)    y in [10,40)
//   ein Balken mitte 0xFF00C000  (gruen)  y in [50,80)
//   ein Balken unten 0xFF0060FF  (blau)   y in [90,120)
//
// Die Farben sind mit Absicht weit auseinander: ein Foto, auf dem sie
// nicht zu unterscheiden waeren, hat nichts bewiesen.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static int configured;

#define W 200
#define H 150

static void reg_global(void *d, struct wl_registry *r, uint32_t name,
                       const char *iface, uint32_t ver)
{
    (void)d; (void)ver;
    if (strcmp(iface, "wl_compositor") == 0)
        compositor = wl_registry_bind(r, name, &wl_compositor_interface, 1);
    else if (strcmp(iface, "wl_shm") == 0)
        shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
    else if (strcmp(iface, "xdg_wm_base") == 0)
        wm_base = wl_registry_bind(r, name, &xdg_wm_base_interface, 1);
}

static void reg_remove(void *d, struct wl_registry *r, uint32_t name)
{ (void)d; (void)r; (void)name; }

static const struct wl_registry_listener reg_l = { reg_global, reg_remove };

static void xs_configure(void *d, struct xdg_surface *s, uint32_t serial)
{
    (void)d;
    xdg_surface_ack_configure(s, serial);
    configured = 1;
}
static const struct xdg_surface_listener xs_l = { xs_configure };

static void wmb_ping(void *d, struct xdg_wm_base *b, uint32_t serial)
{ (void)d; xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wmb_l = { wmb_ping };

int main(int argc, char **argv)
{
    // libwayland nimmt einen ABSOLUTEN Pfad als Anzeigenamen und geht
    // dann an XDG_RUNTIME_DIR vorbei (src/wayland-client.c,
    // connect_to_socket: `path_is_absolute`). Das ist der Weg, der auf
    // OrientOS gangbar ist -- eine Umgebungsvariable setzt dort keine
    // Shell.
    const char *path = (argc > 1) ? argv[1] : "/tmp/wayland-0";
    struct wl_display *dpy = wl_display_connect(path);
    if (!dpy) {
        fprintf(stderr, "wlclient: KEIN SERVER (%s)\n", path);
        return 2;
    }
    printf("wlclient: verbunden\n");

    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &reg_l, NULL);
    printf("wlclient: vor roundtrip, fd=%d\n", wl_display_get_fd(dpy));
    fflush(stdout);
    int rt = wl_display_roundtrip(dpy);
    printf("wlclient: roundtrip=%d err=%d\n", rt,
           wl_display_get_error(dpy));
    fflush(stdout);

    if (!compositor || !shm || !wm_base) {
        fprintf(stderr, "wlclient: fehlend comp=%p shm=%p wm=%p\n",
                (void *)compositor, (void *)shm, (void *)wm_base);
        return 3;
    }
    printf("wlclient: registry ok\n");
    xdg_wm_base_add_listener(wm_base, &wmb_l, NULL);

    int stride = W * 4;
    int size = stride * H;

    // memfd_create statt einer Datei: das ist der Weg, den auch
    // weston-simple-shm nimmt (shared/os-compatibility.c,
    // os_create_anonymous_file), und der einzige, der auf OrientOS
    // funktioniert -- dieses System hat kein ftruncate auf Dateien.
    int fd = (int)syscall(319, "wlclient", 0);
    if (fd < 0) { perror("memfd_create"); return 4; }
    if (ftruncate(fd, size) < 0) { perror("ftruncate"); return 5; }
    unsigned int *px = mmap(NULL, size, PROT_READ | PROT_WRITE,
                            MAP_SHARED, fd, 0);
    if (px == MAP_FAILED) { perror("mmap"); return 6; }

    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            unsigned int c = 0xFF202060u;
            if (y >= 10 && y < 40)  c = 0xFFE00000u;
            if (y >= 50 && y < 80)  c = 0xFF00C000u;
            if (y >= 90 && y < 120) c = 0xFF0060FFu;
            px[y * W + x] = c;
        }
    printf("wlclient: muster gemalt\n");

    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *buf = wl_shm_pool_create_buffer(pool, 0, W, H,
                                                      stride, 0);
    struct wl_surface *surf = wl_compositor_create_surface(compositor);
    struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(wm_base, surf);
    xdg_surface_add_listener(xs, &xs_l, NULL);
    struct xdg_toplevel *tl = xdg_surface_get_toplevel(xs);
    xdg_toplevel_set_title(tl, "wlclient");
    wl_surface_commit(surf);
    wl_display_roundtrip(dpy);
    printf("wlclient: configured=%d\n", configured);

    wl_surface_attach(surf, buf, 0, 0);
    wl_surface_damage(surf, 0, 0, W, H);
    wl_surface_commit(surf);
    wl_display_roundtrip(dpy);
    printf("wlclient: FERTIG -- %dx%d angehaengt und festgeschrieben\n",
           W, H);
    wl_display_flush(dpy);
    // Stehenbleiben, damit das Fenster beim Bildschirmfoto noch da ist.
    // Ohne das raeumt der Server es ab, bevor QEMU screendump macht.
    // Wie lange das Fenster stehenbleibt, bevor sich der Client
    // beendet. Fuer das Bildschirmfoto lang, fuer die Abnahme des
    // Bedarfsstarts kurz -- deshalb ein Argument und keine feste Zahl.
    int halten = (argc > 2) ? atoi(argv[2]) : 400;
    for (int i = 0; i < halten; i++) {
        wl_display_dispatch_pending(dpy);
        wl_display_flush(dpy);
        usleep(50000);
    }
    printf("wlclient: beende mich\n");
    return 0;
}
