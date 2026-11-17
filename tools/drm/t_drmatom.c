/* SPDX-License-Identifier: GPL-2.0-only */
#define TNAME "t_drmatom"
#include "../unterbau/t.h"
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>

#define IOWR(nr, sz) ((3u << 30) | ((unsigned)(sz) << 16) | (0x64u << 8) | (nr))
#define CRTC 0x32
#define CONN 0x30
#define PRIMARY 0x33
#define CURSOR 0x34
#define PROP(i) (0x200u + (i))
#define P_TYPE 0
#define P_FB_ID 1
#define P_PLANE_CRTC 2
#define P_SRC_W 5
#define P_SRC_H 6
#define P_CRTC_X 7
#define P_CRTC_Y 8
#define P_CRTC_W 9
#define P_CRTC_H 10
#define P_ACTIVE 11
#define P_MODE_ID 12
#define P_CONN_CRTC 14
#define MODE_BLOB 0x300
#define FLAG_EVENT 1u
#define FLAG_TEST 0x100u
#define FLAG_MODESET 0x400u

struct card_res { uint64_t fb, crtc, conn, enc; uint32_t nfb, ncrtc, nconn, nenc, minw, maxw, minh, maxh; };
struct modeinfo { uint32_t clock; uint16_t hd, hss, hse, ht, hskew, vd, vss, vse, vt, vscan; uint32_t vrefresh, flags, type; char name[32]; };
struct get_conn { uint64_t enc_ptr, modes_ptr, props_ptr, vals_ptr; uint32_t nmodes, nprops, nenc, enc_id, conn_id, type, type_id, connection, mmw, mmh, subpixel, pad; };
struct mode_crtc { uint64_t conn_ptr; uint32_t nconn, crtc_id, fb_id, x, y, gamma, mode_valid; struct modeinfo mode; };
struct create_dumb { uint32_t height, width, bpp, flags, handle, pitch; uint64_t size; };
struct fb_cmd2 { uint32_t fb_id, width, height, format, flags, handles[4], pitches[4], offsets[4]; uint64_t modifier[4]; };
struct event { uint32_t type, length; uint64_t user_data; uint32_t sec, usec, seq, crtc; };
struct plane_res { uint64_t ids; uint32_t count; uint32_t pad; };
struct get_plane { uint32_t id, crtc, fb, possible, gamma, nformats; uint64_t formats; };
struct set_plane { uint32_t id, crtc, fb, flags; int32_t cx, cy; uint32_t cw, ch, sx, sy, sh, sw; };
struct obj_props { uint64_t props, values; uint32_t count, obj, type, pad; };
struct get_prop { uint64_t values, enums; uint32_t id, flags; char name[32]; uint32_t nvalues, nenums; };
struct prop_enum { uint64_t value; char name[32]; };
struct blob_create { uint64_t data; uint32_t length, id; };
struct blob_get { uint32_t id, length; uint64_t data; };
struct blob_destroy { uint32_t id; };
struct atomic { uint32_t flags, nobjs; uint64_t objs, nprops, props, values, reserved, user; };
struct client_cap { uint64_t cap, value; };
struct get_cap { uint64_t cap, value; };
struct so_create { uint32_t handle, flags; };
struct so_array { uint64_t handles; uint32_t count, pad; };
struct so_eventfd { uint32_t handle, flags; uint64_t point; int32_t fd; uint32_t pad; };

static int card;
static uint32_t fbs[2];
static struct modeinfo mode;

static int dio(int fd, unsigned nr, void *p, size_t sz) { return ioctl(fd, IOWR(nr, sz), p); }
#define DIO(fd, nr, p) dio(fd, nr, p, sizeof *(p))

static int make_fb(uint32_t w, uint32_t h, uint32_t format, uint32_t *fb)
{
    struct create_dumb cd = { .height = h, .width = w, .bpp = 32 };
    if (DIO(card, 0xB2, &cd)) return -1;
    struct fb_cmd2 f = { .width = w, .height = h, .format = format };
    f.handles[0] = cd.handle; f.pitches[0] = cd.pitch;
    if (DIO(card, 0xB8, &f)) return -1;
    *fb = f.fb_id;
    return 0;
}

static int scanout(void)
{
    uint32_t conn = 0, crtc = 0, enc = 0;
    struct card_res r = { .crtc = (uintptr_t)&crtc, .conn = (uintptr_t)&conn, .enc = (uintptr_t)&enc, .ncrtc = 1, .nconn = 1, .nenc = 1 };
    struct get_conn gc = { .modes_ptr = (uintptr_t)&mode, .nmodes = 1 };
    if (DIO(card, 0xA0, &r)) return -1;
    gc.conn_id = conn;
    if (DIO(card, 0xA7, &gc) || make_fb(mode.hd, mode.vd, 0x34325258, &fbs[0]) || make_fb(mode.hd, mode.vd, 0x34325258, &fbs[1])) return -1;
    struct mode_crtc sc = { .conn_ptr = (uintptr_t)&conn, .nconn = 1, .crtc_id = crtc, .fb_id = fbs[0], .mode_valid = 1, .mode = mode };
    return DIO(card, 0xA2, &sc);
}

static uint64_t prop_value(uint32_t obj, uint32_t prop)
{
    uint32_t ids[16];
    uint64_t vals[16];
    struct obj_props op = { .props = (uintptr_t)ids, .values = (uintptr_t)vals, .count = 16, .obj = obj };
    if (DIO(card, 0xB9, &op)) return ~0ull;
    for (uint32_t i = 0; i < op.count; i++)
        if (ids[i] == prop) return vals[i];
    return ~0ull - 1;
}

static uint32_t plane_fb(uint32_t plane)
{
    struct get_plane gp = { .id = plane };
    return DIO(card, 0xB6, &gp) ? ~0u : gp.fb;
}

static int atomic_set(uint32_t flags, uint32_t nobjs, uint32_t *objs, uint32_t *counts, uint32_t *props, uint64_t *values, uint64_t user)
{
    struct atomic a = { .flags = flags, .nobjs = nobjs, .objs = (uintptr_t)objs, .nprops = (uintptr_t)counts,
        .props = (uintptr_t)props, .values = (uintptr_t)values, .user = user };
    return DIO(card, 0xBC, &a);
}

static int plane_fb_commit(uint32_t flags, uint32_t fb, uint64_t user)
{
    uint32_t objs[1] = { PRIMARY }, counts[1] = { 1 }, props[1] = { PROP(P_FB_ID) };
    uint64_t values[1] = { fb };
    return atomic_set(flags, 1, objs, counts, props, values, user);
}

static void check_caps_and_props(void)
{
    struct client_cap uc = { .cap = 2, .value = 1 }, ac = { .cap = 3, .value = 1 };
    CHECKC("client_cap_universal", DIO(card, 0x0D, &uc) == 0, "x");
    CHECKC("client_cap_atomic", DIO(card, 0x0D, &ac) == 0, "x");
    struct client_cap bad = { .cap = 3, .value = 2 };
    CHECK("client_cap_bad_value_refused", DIO(card, 0x0D, &bad) < 0 && errno == EINVAL, "errno=%d", errno);
    struct get_cap cw = { .cap = 8 }, ch = { .cap = 9 };
    CHECK("cap_cursor_size", DIO(card, 0x0C, &cw) == 0 && DIO(card, 0x0C, &ch) == 0 && cw.value == 64 && ch.value == 64, "w=%llu h=%llu", (unsigned long long)cw.value, (unsigned long long)ch.value);
    uint32_t ids[4] = {0};
    struct plane_res pr = { .ids = (uintptr_t)ids, .count = 4 };
    CHECK("plane_resources", DIO(card, 0xB5, &pr) == 0 && pr.count == 2 && ids[0] == PRIMARY && ids[1] == CURSOR, "n=%u ids=%x,%x", pr.count, ids[0], ids[1]);
    uint32_t formats[4] = {0};
    struct get_plane gp = { .id = PRIMARY, .formats = (uintptr_t)formats, .nformats = 4 };
    CHECK("get_plane_primary", DIO(card, 0xB6, &gp) == 0 && gp.fb == fbs[0] && gp.crtc == CRTC && gp.possible == 1 && gp.nformats == 2 && formats[0] == 0x34325258, "fb=%u crtc=%u nf=%u", gp.fb, gp.crtc, gp.nformats);
    struct get_plane gc = { .id = CURSOR };
    CHECK("get_plane_cursor_idle", DIO(card, 0xB6, &gc) == 0 && gc.fb == 0 && gc.crtc == 0, "fb=%u", gc.fb);
    struct get_plane none = { .id = 0x99 };
    CHECK("get_plane_unknown_enoent", DIO(card, 0xB6, &none) < 0 && errno == ENOENT, "errno=%d", errno);
    CHECK("prop_plane_type_primary", prop_value(PRIMARY, PROP(P_TYPE)) == 1, "v=%llu", (unsigned long long)prop_value(PRIMARY, PROP(P_TYPE)));
    CHECK("prop_plane_type_cursor", prop_value(CURSOR, PROP(P_TYPE)) == 2, "v=%llu", (unsigned long long)prop_value(CURSOR, PROP(P_TYPE)));
    CHECK("prop_plane_fb_id_value", prop_value(PRIMARY, PROP(P_FB_ID)) == fbs[0], "v=%llu", (unsigned long long)prop_value(PRIMARY, PROP(P_FB_ID)));
    CHECK("prop_crtc_active", prop_value(CRTC, PROP(P_ACTIVE)) == 1, "v=%llu", (unsigned long long)prop_value(CRTC, PROP(P_ACTIVE)));
    CHECK("prop_crtc_mode_blob", prop_value(CRTC, PROP(P_MODE_ID)) == MODE_BLOB, "v=%llu", (unsigned long long)prop_value(CRTC, PROP(P_MODE_ID)));
    CHECK("prop_connector_crtc", prop_value(CONN, PROP(P_CONN_CRTC)) == CRTC, "v=%llu", (unsigned long long)prop_value(CONN, PROP(P_CONN_CRTC)));
    struct obj_props badobj = { .obj = 0x77 };
    CHECK("obj_props_unknown_enoent", DIO(card, 0xB9, &badobj) < 0 && errno == ENOENT, "errno=%d", errno);
    uint64_t vals[4] = {0};
    struct prop_enum enums[4] = {0};
    struct get_prop gt = { .id = PROP(P_TYPE), .values = (uintptr_t)vals, .enums = (uintptr_t)enums, .nvalues = 4, .nenums = 4 };
    CHECK("get_property_type_enum", DIO(card, 0xAA, &gt) == 0 && !strcmp(gt.name, "type") && (gt.flags & 8) && (gt.flags & 4) && gt.nenums == 3 && !strcmp(enums[1].name, "Primary") && enums[2].value == 2, "name=%s flags=%x ne=%u", gt.name, gt.flags, gt.nenums);
    struct get_prop gf = { .id = PROP(P_FB_ID) };
    CHECK("get_property_fb_id_object_atomic", DIO(card, 0xAA, &gf) == 0 && !strcmp(gf.name, "FB_ID") && (gf.flags & 0x40) && (gf.flags & 0x80000000u), "name=%s flags=%x", gf.name, gf.flags);
    struct get_prop gx = { .id = PROP(P_CRTC_X) };
    CHECK("get_property_signed_range", DIO(card, 0xAA, &gx) == 0 && (gx.flags & 0x80) && gx.nvalues == 2, "flags=%x nv=%u", gx.flags, gx.nvalues);
    struct get_prop gm = { .id = PROP(P_MODE_ID) };
    CHECK("get_property_mode_blob", DIO(card, 0xAA, &gm) == 0 && (gm.flags & 16) && gm.nvalues == 0, "flags=%x", gm.flags);
    struct get_prop gn = { .id = 0x999 };
    CHECK("get_property_unknown_enoent", DIO(card, 0xAA, &gn) < 0 && errno == ENOENT, "errno=%d", errno);
}

static void check_blobs(void)
{
    char data[16] = "blobdata-12345";
    struct blob_create bc = { .data = (uintptr_t)data, .length = sizeof data };
    CHECKC("blob_create", DIO(card, 0xBD, &bc) == 0 && bc.id != 0, "x");
    char back[16] = {0};
    struct blob_get bg = { .id = bc.id, .length = sizeof back, .data = (uintptr_t)back };
    CHECK("blob_get_roundtrip", DIO(card, 0xAC, &bg) == 0 && bg.length == sizeof data && !memcmp(back, data, sizeof data), "errno=%d", errno);
    struct blob_destroy bd = { .id = bc.id };
    CHECK("blob_destroy", DIO(card, 0xBE, &bd) == 0, "errno=%d", errno);
    CHECK("blob_destroy_twice_enoent", DIO(card, 0xBE, &bd) < 0 && errno == ENOENT, "errno=%d", errno);
    struct blob_get gone = { .id = bc.id, .length = sizeof back, .data = (uintptr_t)back };
    CHECK("blob_get_gone_enoent", DIO(card, 0xAC, &gone) < 0 && errno == ENOENT, "errno=%d", errno);
    struct blob_create empty = { .data = (uintptr_t)data, .length = 0 };
    CHECK("blob_create_empty_refused", DIO(card, 0xBD, &empty) < 0 && errno == EINVAL, "errno=%d", errno);
    struct blob_get mb = { .id = MODE_BLOB, .length = 0 };
    CHECK("blob_mode_length", DIO(card, 0xAC, &mb) == 0 && mb.length == 68, "len=%u errno=%d", mb.length, errno);
}

static void check_atomic(void)
{
    CHECKC("atomic_test_only_ok", plane_fb_commit(FLAG_TEST, fbs[1], 0) == 0, "x");
    CHECK("atomic_test_only_no_effect", plane_fb(PRIMARY) == fbs[0], "fb=%u", plane_fb(PRIMARY));
    CHECK("atomic_commit_switches_fb", plane_fb_commit(0, fbs[1], 0) == 0 && plane_fb(PRIMARY) == fbs[1], "fb=%u errno=%d", plane_fb(PRIMARY), errno);
    CHECK("atomic_prop_reads_back", prop_value(PRIMARY, PROP(P_FB_ID)) == fbs[1], "v=%llu", (unsigned long long)prop_value(PRIMARY, PROP(P_FB_ID)));
    struct event e = {0};
    int rc = plane_fb_commit(FLAG_EVENT, fbs[0], 0xA70C0001ull);
    struct pollfd p = { .fd = card, .events = POLLIN };
    int got = poll(&p, 1, 500) == 1 && read(card, &e, sizeof e) == (ssize_t)sizeof e;
    CHECK("atomic_flip_event", rc == 0 && got && e.type == 2 && e.user_data == 0xA70C0001ull && e.crtc == CRTC, "rc=%d got=%d type=%u ud=%llx", rc, got, e.type, (unsigned long long)e.user_data);
    CHECK("atomic_test_only_event_refused", plane_fb_commit(FLAG_TEST | FLAG_EVENT, fbs[1], 1) < 0 && errno == EINVAL, "errno=%d", errno);
    CHECK("atomic_unknown_fb_enoent", plane_fb_commit(0, 9999, 0) < 0 && errno == ENOENT, "errno=%d", errno);
    CHECK("atomic_failed_commit_keeps_state", plane_fb(PRIMARY) == fbs[0], "fb=%u", plane_fb(PRIMARY));
    CHECK("atomic_bad_flags_refused", plane_fb_commit(0x10000, fbs[1], 0) < 0 && errno == EINVAL, "errno=%d", errno);
    uint32_t objs[1] = { PRIMARY }, counts[1] = { 1 }, crtc_prop[1] = { PROP(P_PLANE_CRTC) };
    uint64_t wrong[1] = { 0x99 };
    CHECK("atomic_wrong_crtc_refused", atomic_set(FLAG_TEST, 1, objs, counts, crtc_prop, wrong, 0) < 0 && errno == EINVAL, "errno=%d", errno);
    uint32_t mism_props[1] = { PROP(P_CRTC_W) };
    uint64_t mism[1] = { 17 };
    CHECK("atomic_size_mismatch_refused", atomic_set(FLAG_TEST, 1, objs, counts, mism_props, mism, 0) < 0 && errno == EINVAL, "errno=%d", errno);
    uint32_t type_props[1] = { PROP(P_TYPE) };
    uint64_t type_val[1] = { 2 };
    CHECK("atomic_immutable_type_refused", atomic_set(FLAG_TEST, 1, objs, counts, type_props, type_val, 0) < 0 && errno == EINVAL, "errno=%d", errno);
    uint32_t foreign[1] = { PROP(P_ACTIVE) };
    uint64_t one[1] = { 1 };
    CHECK("atomic_foreign_prop_refused", atomic_set(FLAG_TEST, 1, objs, counts, foreign, one, 0) < 0 && errno == EINVAL, "errno=%d", errno);
    uint32_t unknown[1] = { 0x999 };
    CHECK("atomic_unknown_prop_enoent", atomic_set(FLAG_TEST, 1, objs, counts, unknown, one, 0) < 0 && errno == ENOENT, "errno=%d", errno);
    uint32_t off_objs[3] = { PRIMARY, CRTC, CONN }, off_counts[3] = { 2, 1, 1 };
    uint32_t off_props[4] = { PROP(P_FB_ID), PROP(P_PLANE_CRTC), PROP(P_ACTIVE), PROP(P_CONN_CRTC) };
    uint64_t off_vals[4] = { 0, 0, 0, 0 };
    CHECK("atomic_modeset_needs_flag", atomic_set(FLAG_TEST, 3, off_objs, off_counts, off_props, off_vals, 0) < 0 && errno == EINVAL, "errno=%d", errno);
    CHECK("atomic_modeset_allowed_test", atomic_set(FLAG_TEST | FLAG_MODESET, 3, off_objs, off_counts, off_props, off_vals, 0) == 0, "errno=%d", errno);
    CHECK("atomic_modeset_test_no_effect", prop_value(CRTC, PROP(P_ACTIVE)) == 1 && plane_fb(PRIMARY) == fbs[0], "active=%llu", (unsigned long long)prop_value(CRTC, PROP(P_ACTIVE)));
    uint32_t mode_objs[1] = { CRTC }, mode_counts[1] = { 1 }, mode_props[1] = { PROP(P_MODE_ID) };
    uint64_t no_blob[1] = { 0x3FF };
    CHECK("atomic_unknown_mode_blob_refused", atomic_set(FLAG_TEST, 1, mode_objs, mode_counts, mode_props, no_blob, 0) < 0, "errno=%d", errno);
    int other = open("/dev/dri/card0", O_RDWR);
    uint32_t o_objs[1] = { PRIMARY }, o_counts[1] = { 1 }, o_props[1] = { PROP(P_FB_ID) };
    uint64_t o_vals[1] = { fbs[1] };
    struct atomic a = { .flags = FLAG_TEST, .nobjs = 1, .objs = (uintptr_t)o_objs, .nprops = (uintptr_t)o_counts, .props = (uintptr_t)o_props, .values = (uintptr_t)o_vals };
    CHECK("atomic_needs_client_cap", other >= 0 && DIO(other, 0xBC, &a) < 0, "errno=%d", errno);
    close(other);
}

static void check_cursor(void)
{
    uint32_t cur = 0, big = 0;
    CHECKC("cursor_fb_create", make_fb(64, 64, 0x34325241, &cur) == 0 && make_fb(128, 128, 0x34325241, &big) == 0, "x");
    uint32_t objs[1] = { CURSOR }, counts[1] = { 8 };
    uint32_t props[8] = { PROP(P_FB_ID), PROP(P_PLANE_CRTC), PROP(P_SRC_W), PROP(P_SRC_H), PROP(P_CRTC_X), PROP(P_CRTC_Y), PROP(P_CRTC_W), PROP(P_CRTC_H) };
    uint64_t values[8] = { cur, CRTC, 64u << 16, 64u << 16, 10, 20, 64, 64 };
    CHECK("cursor_atomic_commit", atomic_set(0, 1, objs, counts, props, values, 0) == 0, "errno=%d", errno);
    CHECK("cursor_plane_fb_set", plane_fb(CURSOR) == cur, "fb=%u", plane_fb(CURSOR));
    CHECK("cursor_position_reads_back", prop_value(CURSOR, PROP(P_CRTC_X)) == 10 && prop_value(CURSOR, PROP(P_CRTC_Y)) == 20, "x=%llu y=%llu", (unsigned long long)prop_value(CURSOR, PROP(P_CRTC_X)), (unsigned long long)prop_value(CURSOR, PROP(P_CRTC_Y)));
    CHECK("cursor_primary_unaffected", plane_fb(PRIMARY) == fbs[0], "fb=%u", plane_fb(PRIMARY));
    values[0] = big; values[2] = 128u << 16; values[3] = 128u << 16; values[6] = 128; values[7] = 128;
    CHECK("cursor_too_big_refused", atomic_set(FLAG_TEST, 1, objs, counts, props, values, 0) < 0 && errno == EINVAL, "errno=%d", errno);
    struct set_plane sp = { .id = CURSOR, .crtc = CRTC, .fb = cur, .cx = 40, .cy = 50, .cw = 64, .ch = 64, .sw = 64u << 16, .sh = 64u << 16 };
    CHECK("setplane_legacy_cursor_move", DIO(card, 0xB7, &sp) == 0 && prop_value(CURSOR, PROP(P_CRTC_X)) == 40, "errno=%d x=%llu", errno, (unsigned long long)prop_value(CURSOR, PROP(P_CRTC_X)));
    struct set_plane off = { .id = CURSOR };
    CHECK("setplane_disable_cursor", DIO(card, 0xB7, &off) == 0 && plane_fb(CURSOR) == 0, "errno=%d fb=%u", errno, plane_fb(CURSOR));
    struct set_plane unknown = { .id = 0x99 };
    CHECK("setplane_unknown_enoent", DIO(card, 0xB7, &unknown) < 0 && errno == ENOENT, "errno=%d", errno);
}

static void check_syncobj_eventfd(void)
{
    struct so_create sc = {0};
    CHECKC("eventfd_syncobj_create", DIO(card, 0xBF, &sc) == 0 && sc.handle != 0, "x");
    int efd = eventfd(0, EFD_NONBLOCK);
    struct so_eventfd ev = { .handle = sc.handle, .fd = efd };
    CHECK("syncobj_eventfd_register", efd >= 0 && DIO(card, 0xCF, &ev) == 0, "errno=%d", errno);
    uint64_t n = 0;
    CHECK("syncobj_eventfd_idle", read(efd, &n, 8) < 0 && errno == EAGAIN, "errno=%d", errno);
    struct so_array sig = { .handles = (uintptr_t)&sc.handle, .count = 1 };
    CHECK("syncobj_eventfd_signal_fires", DIO(card, 0xC5, &sig) == 0 && read(efd, &n, 8) == 8 && n == 1, "n=%llu errno=%d", (unsigned long long)n, errno);
    int again = eventfd(0, EFD_NONBLOCK);
    struct so_eventfd ready = { .handle = sc.handle, .fd = again };
    CHECK("syncobj_eventfd_already_signaled", DIO(card, 0xCF, &ready) == 0 && read(again, &n, 8) == 8 && n == 1, "n=%llu errno=%d", (unsigned long long)n, errno);
    struct so_eventfd badh = { .handle = 9999, .fd = efd };
    CHECK("syncobj_eventfd_bad_handle_enoent", DIO(card, 0xCF, &badh) < 0 && errno == ENOENT, "errno=%d", errno);
    int nul = open("/dev/null", O_RDONLY);
    struct so_eventfd wrong = { .handle = sc.handle, .fd = nul };
    CHECK("syncobj_eventfd_wrong_fd_einval", DIO(card, 0xCF, &wrong) < 0 && errno == EINVAL, "errno=%d", errno);
    struct so_eventfd flags = { .handle = sc.handle, .flags = 0x80, .fd = efd };
    CHECK("syncobj_eventfd_bad_flags_einval", DIO(card, 0xCF, &flags) < 0 && errno == EINVAL, "errno=%d", errno);
    close(nul); close(efd); close(again);
}

struct crtc_seq { uint32_t crtc_id, active; uint64_t sequence; int64_t sequence_ns; };

static uint64_t crtc_sequence(void)
{
    struct crtc_seq cs = { .crtc_id = CRTC };
    return DIO(card, 0x3B, &cs) == 0 ? cs.sequence : 0;
}

static void check_vblank_rate(void)
{
    uint64_t a = crtc_sequence();
    struct timespec ts = { 1, 0 };
    nanosleep(&ts, NULL);
    uint64_t b = crtc_sequence();
    printf("VBLRATE %llu\n", (unsigned long long)(b - a));
    CHECK("vblank_rate_measured", b > a, "a=%llu b=%llu", (unsigned long long)a, (unsigned long long)b);
}

int main(void)
{
    card = open("/dev/dri/card0", O_RDWR);
    CHECKC("open_card", card >= 0, "card=%d", card);
    if (card < 0) return 1;
    CHECKC("scanout_ready", scanout() == 0, "x");
    check_caps_and_props();
    check_blobs();
    check_atomic();
    check_cursor();
    check_syncobj_eventfd();
    check_vblank_rate();
    printf("\nDRMA_DONE\n");
    fflush(stdout);
    return 0;
}
