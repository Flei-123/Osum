#include "util.h"

const guid_t G_GLOBAL_VARIABLE = {0x8be4df61, 0x93ca, 0x11d2, {0xaa, 0x0d, 0x00, 0xe0, 0x98, 0x03, 0x2b, 0x8c}};
const guid_t G_LOADED_IMAGE = {0x5b1b31a1, 0x9562, 0x11d2, {0x8e, 0x3f, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b}};
const guid_t G_SIMPLE_FS = {0x964e5b22, 0x6459, 0x11d2, {0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b}};
const guid_t G_DEVICE_PATH = {0x09576e91, 0x6d3f, 0x11d2, {0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b}};

system_table_t *g_st;

void *memcpy(void *dst, const void *src, u64 n)
{
    u8 *d = dst;
    const u8 *s = src;
    while (n--) *d++ = *s++;
    return dst;
}

void *memset(void *dst, int c, u64 n)
{
    u8 *d = dst;
    while (n--) *d++ = (u8)c;
    return dst;
}

int memcmp(const void *a, const void *b, u64 n)
{
    const u8 *x = a;
    const u8 *y = b;
    while (n--) {
        if (*x != *y) return *x < *y ? -1 : 1;
        x++;
        y++;
    }
    return 0;
}

int guid_equal(const guid_t *a, const guid_t *b)
{
    return memcmp(a, b, sizeof(guid_t)) == 0;
}

u64 str_len(const char *s)
{
    u64 n = 0;
    while (s[n]) n++;
    return n;
}

u64 u16_len(const u16 *s)
{
    u64 n = 0;
    while (s[n]) n++;
    return n;
}

int u16_equal_ascii(const u16 *s, const char *ascii)
{
    while (*s && *ascii) {
        if (*s != (u16)(u8)*ascii) return 0;
        s++;
        ascii++;
    }
    return *s == 0 && *ascii == 0;
}

u64 ascii_to_u16(u16 *dst, const char *src, u64 max)
{
    u64 n = 0;
    while (src[n] && n + 1 < max) {
        dst[n] = (u8)src[n];
        n++;
    }
    dst[n] = 0;
    return n;
}

u64 u16_to_ascii(char *dst, const u16 *src, u64 max)
{
    u64 n = 0;
    while (src[n] && n + 1 < max) {
        dst[n] = src[n] < 0x80 ? (char)src[n] : '?';
        n++;
    }
    dst[n] = 0;
    return n;
}

static void outb(u16 port, u8 v)
{
    __asm__ __volatile__("outb %0, %1" : : "a"(v), "Nd"(port));
}

static u8 inb(u16 port)
{
    u8 v;
    __asm__ __volatile__("inb %1, %0" : "=a"(v) : "Nd"(port));
    return v;
}

void log_init(system_table_t *st)
{
    g_st = st;
    outb(0x3F8 + 1, 0x00);
    outb(0x3F8 + 3, 0x80);
    outb(0x3F8 + 0, 0x03);
    outb(0x3F8 + 1, 0x00);
    outb(0x3F8 + 3, 0x03);
    outb(0x3F8 + 2, 0xC7);
    outb(0x3F8 + 4, 0x0B);
}

static void ser_putc(char c)
{
    int guard = 0;
    while (!(inb(0x3F8 + 5) & 0x20) && guard < 100000) guard++;
    outb(0x3F8, (u8)c);
}

static void con_puts(const char *s)
{
    u16 buf[256];
    u64 n = 0;
    if (!g_st || !g_st->con_out || !g_st->con_out->output_string) return;
    while (*s) {
        if (n + 3 >= 256) {
            buf[n] = 0;
            g_st->con_out->output_string(g_st->con_out, buf);
            n = 0;
        }
        if (*s == '\n') buf[n++] = '\r';
        buf[n++] = (u8)*s++;
    }
    buf[n] = 0;
    g_st->con_out->output_string(g_st->con_out, buf);
}

static char g_line[320];
static u64 g_line_len;

static void flush_line(void)
{
    u64 i;
    if (!g_line_len) return;
    g_line[g_line_len] = 0;
    for (i = 0; i < g_line_len; i++) {
        if (g_line[i] == '\n') ser_putc('\r');
        ser_putc(g_line[i]);
    }
    con_puts(g_line);
    g_line_len = 0;
}

void log_flush(void)
{
    flush_line();
}

void log_str(const char *s)
{
    while (*s) {
        if (g_line_len + 2 >= sizeof(g_line)) flush_line();
        g_line[g_line_len++] = *s;
        if (*s == '\n') flush_line();
        s++;
    }
}

void log_u16(const u16 *s)
{
    char buf[128];
    u16_to_ascii(buf, s, sizeof(buf));
    log_str(buf);
}

void log_hex(u64 v, int digits)
{
    char buf[17];
    int i;
    for (i = 0; i < digits; i++) buf[i] = "0123456789ABCDEF"[(v >> (4 * (digits - 1 - i))) & 15];
    buf[digits] = 0;
    log_str(buf);
}

void log_status(u64 status)
{
    log_str("0x");
    log_hex(status, 16);
}

void log_dp(const u8 *dp)
{
    for (;;) {
        const dp_node_t *n = (const dp_node_t *)dp;
        u16 len = (u16)(n->length[0] | (n->length[1] << 8));
        if (n->type == 0x7f || len < 4) break;
        if (n->type == 4 && n->subtype == 1 && len >= 8) {
            log_str("HD(");
            log_hex(*(const u32 *)(dp + 4), 1);
            log_str(")");
        } else if (n->type == 4 && n->subtype == 4) {
            log_u16((const u16 *)(dp + 4));
        } else {
            log_str("(");
            log_hex(n->type, 2);
            log_str(",");
            log_hex(n->subtype, 2);
            log_str(")");
        }
        dp += len;
    }
}

void boot_name(u16 *out, u16 number)
{
    int i;
    out[0] = 'B';
    out[1] = 'o';
    out[2] = 'o';
    out[3] = 't';
    for (i = 0; i < 4; i++) out[4 + i] = (u16)"0123456789ABCDEF"[(number >> (4 * (3 - i))) & 15];
    out[8] = 0;
}
