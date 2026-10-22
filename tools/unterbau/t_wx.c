/* W^X audit: no mapping is writable and executable at once, and data pages (stack, heap, .data, big and small anonymous maps) do not execute. */
#define TNAME "wx"
#include "t.h"
#include <fcntl.h>
#include <unistd.h>
#include <setjmp.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <stdint.h>

#define PG 4096
static sigjmp_buf jb;
static volatile int segv_seen;
static struct sigaction g_sa;
static void on_segv(int s, siginfo_t *si, void *u) { (void)si; (void)u; segv_seen++; sigaction(s, &g_sa, 0); siglongjmp(jb, 1); }

static int faults_write(volatile char *p)
{
    segv_seen = 0;
    if (sigsetjmp(jb, 1) == 0) { *p = 1; return 0; }
    return 1;
}
static int faults_exec(void *p)
{
    segv_seen = 0;
    if (sigsetjmp(jb, 1) == 0) { ((void (*)(void))p)(); return 0; }
    return 1;
}
static int runs_exec(void *p, int *out)
{
    segv_seen = 0;
    if (sigsetjmp(jb, 1) == 0) { *out = ((int (*)(void))p)(); return 1; }
    return 0;
}

static const unsigned char CODE[] = { 0xB8, 42, 0, 0, 0, 0xC3 };
static unsigned char g_data[PG] __attribute__((aligned(PG))) = { 0xC3 };

static void maps_scan(void)
{
    char buf[16384];
    int fd = open("/proc/self/maps", O_RDONLY);
    if (fd < 0) { GAP("maps_readable", "open /proc/self/maps failed errno=%d", errno); return; }
    int n = 0, m;
    while (n < (int)sizeof buf - 1 && (m = read(fd, buf + n, sizeof buf - 1 - n)) > 0) n += m;
    close(fd);
    buf[n] = 0;
    int rwx = 0, lines = 0;
    char first[200]; first[0] = 0;
    char *p = buf;
    while (*p) {
        char *e = strchr(p, '\n');
        int len = e ? (int)(e - p) : (int)strlen(p);
        char *sp = memchr(p, ' ', len);
        lines++;
        if (sp && sp + 4 <= p + len && sp[1] == 'r' && sp[2] == 'w' && sp[3] == 'x') {
            if (!rwx) { int c = len < 199 ? len : 199; memcpy(first, p, c); first[c] = 0; }
            rwx++;
        }
        if (!e) break;
        p = e + 1;
    }
    CHECK("maps_readable", lines > 0, "no lines");
    CHECK("maps_no_rwx", rwx == 0, "%d of %d mappings are rwx, first: %s", rwx, lines, first);
}

int main(void)
{
    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_segv; sa.sa_flags = SA_SIGINFO | SA_NODEFER; sigemptyset(&sa.sa_mask);
    g_sa = sa;
    sigaction(SIGSEGV, &sa, 0);
    sigaction(SIGBUS, &sa, 0);

    maps_scan();

    char stackbuf[64] __attribute__((aligned(16)));
    stackbuf[0] = (char)0xC3;
    CHECK("stack_nx", faults_exec(stackbuf), "code on the stack executed");

    CHECK("data_nx", faults_exec(g_data), ".data page executed");

    unsigned char *heap = malloc(256);
    heap[0] = 0xC3;
    CHECK("heap_nx", faults_exec(heap), "malloc memory executed");

    unsigned char *rw = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECKC("small_rw_map", rw != MAP_FAILED);
    if (rw != MAP_FAILED) { rw[0] = 0xC3; CHECK("small_rw_nx", faults_exec(rw), "small RW map executed"); }

    unsigned char *rx = mmap(0, PG, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECKC("small_rx_map", rx != MAP_FAILED);
    if (rx != MAP_FAILED) CHECK("small_rx_write_faults", faults_write((char *)rx), "PROT_READ|PROT_EXEC small map is writable");

    unsigned char *ro = mmap(0, PG, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECKC("small_ro_map", ro != MAP_FAILED);
    if (ro != MAP_FAILED) CHECK("small_ro_write_faults", faults_write((char *)ro), "PROT_READ small map is writable");

    size_t big = 4u << 20;
    unsigned char *bro = mmap(0, big, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECKC("big_ro_map", bro != MAP_FAILED);
    if (bro != MAP_FAILED) CHECK("big_ro_write_faults", faults_write((char *)bro + 2 * PG), "PROT_READ big map is writable");

    unsigned char *brx = mmap(0, big, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECKC("big_rx_map", brx != MAP_FAILED);
    if (brx != MAP_FAILED) CHECK("big_rx_write_faults", faults_write((char *)brx + 2 * PG), "PROT_READ|PROT_EXEC big map is writable");

    unsigned char *brw = mmap(0, big, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECKC("big_rw_map", brw != MAP_FAILED);
    if (brw != MAP_FAILED) { brw[2 * PG] = 0xC3; CHECK("big_rw_nx", faults_exec(brw + 2 * PG), "big RW map executed"); }

    unsigned char *jit = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (jit != MAP_FAILED) {
        memcpy(jit, CODE, sizeof CODE);
        int rc = mprotect(jit, PG, PROT_READ | PROT_EXEC);
        int v = 0;
        CHECK("jit_flip_runs", rc == 0 && runs_exec(jit, &v) && v == 42, "rc=%d v=%d", rc, v);
        CHECK("jit_flip_write_faults", faults_write((char *)jit), "RX page is writable after flip");
        rc = mprotect(jit, PG, PROT_READ | PROT_WRITE);
        CHECKC("jit_back_to_rw", rc == 0);
        CHECK("jit_back_nx", faults_exec(jit), "RW page executes after flip back");
    }

    int fd = open("/bin/sh", O_RDONLY);
    if (fd >= 0) {
        unsigned char *fx = mmap(0, PG, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
        if (fx != MAP_FAILED) CHECK("file_rx_write_faults", faults_write((char *)fx), "file RX map is writable");
        else GAP("file_rx_map", "errno=%d", errno);
        close(fd);
    } else GAP("file_rx_map", "no file to map");
    return 0;
}
