/* mmap / mprotect / madvise / mremap / munmap mix, with SIGSEGV as the witness for page rights. */
#define TNAME "mem"
#include "t.h"
#include <fcntl.h>
#include <setjmp.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>

#define PG 4096
static sigjmp_buf jb;
static volatile int segv_seen;
static struct sigaction g_sa;
/* the handler re-arms itself: this kernel resets a fault handler after one delivery (documented gap, docs/RUNDE-UNTERBAU-FIREFOX.md) */
static void on_segv(int s, siginfo_t *si, void *u) { (void)si; (void)u; segv_seen++; sigaction(s, &g_sa, 0); siglongjmp(jb, 1); }

/* returns 1 when the access faulted */
static int faults_write(volatile char *p)
{
    segv_seen = 0;
    if (sigsetjmp(jb, 1) == 0) { *p = 1; return 0; }
    return 1;
}
static int faults_read(volatile char *p)
{
    segv_seen = 0;
    if (sigsetjmp(jb, 1) == 0) { (void)*p; return 0; }
    return 1;
}

static int try_call(int (*f)(void), int *out)
{
    segv_seen = 0;
    if (sigsetjmp(jb, 1) == 0) { *out = f(); return 1; }
    return 0;
}

int main(void)
{
    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_segv; sa.sa_flags = SA_SIGINFO | SA_NODEFER; sigemptyset(&sa.sa_mask);
    g_sa = sa;
    int have_segv = sigaction(SIGSEGV, &sa, 0) == 0;
    CHECK("sigsegv_handler_installed", have_segv, "sigaction(SIGSEGV) failed");
    sigaction(SIGBUS, &sa, 0);

    char *a = mmap(0, 4 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECKC("anon_rw", a != MAP_FAILED);
    if (a == MAP_FAILED) return 1;
    memset(a, 0xAB, 4 * PG);
    CHECK("anon_write_read", a[PG] == (char)0xAB, "wrong byte");

    /* ---- mprotect read-only: a write must fault */
    int r = mprotect(a + PG, PG, PROT_READ);
    CHECKC("mprotect_ro_call", r == 0);
    CHECK("mprotect_ro_read_ok", !faults_read(a + PG), "read of a PROT_READ page faulted");
    CHECK("mprotect_ro_write_faults", faults_write(a + PG), "write to a PROT_READ page went through (mprotect has no effect)");
    CHECK("mprotect_neighbours_unchanged", !faults_write(a) && !faults_write(a + 2 * PG), "neighbour pages lost write");
    /* ---- back to read-write, data must survive */
    r = mprotect(a + PG, PG, PROT_READ | PROT_WRITE);
    CHECK("mprotect_rw_again", r == 0 && !faults_write(a + PG) && a[PG] == 1, "page not writable again or data lost (%d)", a[PG]);
    /* ---- PROT_NONE */
    r = mprotect(a + 2 * PG, PG, PROT_NONE);
    CHECKC("mprotect_none_call", r == 0);
    CHECK("mprotect_none_read_faults", faults_read(a + 2 * PG), "read of a PROT_NONE page went through");
    CHECK("mprotect_none_write_faults", faults_write(a + 2 * PG), "write to a PROT_NONE page went through");
    r = mprotect(a + 2 * PG, PG, PROT_READ | PROT_WRITE);
    CHECK("mprotect_none_to_rw_keeps_data", r == 0 && !faults_read(a + 2 * PG), "page not back");
    /* ---- a syscall into a PROT_NONE buffer must fail with EFAULT, not scribble */
    mprotect(a + 3 * PG, PG, PROT_NONE);
    int p[2]; (void)!pipe(p); (void)!write(p[1], "x", 1);
    errno = 0;
    ssize_t rd = read(p[0], a + 3 * PG, 1);
    CHECK("read_into_none_is_efault", rd == -1 && errno == EFAULT, "read returned %zd errno %d", rd, errno);
    close(p[0]); close(p[1]);
    mprotect(a + 3 * PG, PG, PROT_READ | PROT_WRITE);

    /* ---- the PROT_NONE reservation pattern (thread stacks, jemalloc, JS engines) */
    char *res = mmap(0, 16 * PG, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECKC("reserve_none", res != MAP_FAILED);
    if (res != MAP_FAILED) {
        CHECK("reserve_none_really_none", faults_read(res), "PROT_NONE reservation is readable");
        r = mprotect(res + 4 * PG, 4 * PG, PROT_READ | PROT_WRITE);
        CHECK("reserve_commit", r == 0 && !faults_write(res + 4 * PG) && !faults_write(res + 7 * PG), "commit failed");
        CHECK("reserve_guard_holds", faults_write(res) && faults_write(res + 8 * PG), "guard/uncommitted pages writable");
        munmap(res, 16 * PG);
    }

    /* ---- exec rights: write code into an RW page, mprotect to RX, call it; then NX */
    unsigned char *code = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (code != MAP_FAILED) {
        code[0] = 0xB8; code[1] = 42; code[2] = 0; code[3] = 0; code[4] = 0; code[5] = 0xC3;  /* mov eax,42; ret */
        r = mprotect(code, PG, PROT_READ | PROT_EXEC);
        CHECKC("jit_rx_call", r == 0);
        if (r == 0) {
            int (*f)(void) = (int (*)(void))code; int rv = 0;
            int ran = try_call(f, &rv);
            CHECK("jit_rx_runs", ran && rv == 42, "code did not run (%s)", ran ? "wrong value" : "fault: page not executable");
            CHECK("jit_rx_write_faults", faults_write((char *)code), "RX page is writable (W^X not enforced)");
        }
        /* NX: an RW page must not execute */
        unsigned char *nx = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        nx[0] = 0xC3;
        segv_seen = 0;
        if (sigsetjmp(jb, 1) == 0) { ((void (*)(void))nx)(); }
        CHECK("nx_rw_page_faults", segv_seen == 1, "RW page executed");
    }

    /* ---- munmap hole */
    char *b = mmap(0, 3 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    b[0] = 1; b[PG] = 2; b[2 * PG] = 3;
    CHECKC("munmap_mid", munmap(b + PG, PG) == 0);
    CHECK("munmap_hole_faults", faults_read(b + PG) , "unmapped page still readable");
    CHECK("munmap_edges_ok", b[0] == 1 && b[2 * PG] == 3, "edges lost");

    /* ---- MAP_FIXED over an existing mapping */
    char *c = mmap(0, 4 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    memset(c, 7, 4 * PG);
    char *f2 = mmap(c + PG, 2 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    CHECK("fixed_address", f2 == c + PG, "got %p want %p", (void *)f2, (void *)(c + PG));
    if (f2 == c + PG) CHECK("fixed_replaces_zeroed", c[PG] == 0 && c[2 * PG + 5] == 0 && c[0] == 7 && c[3 * PG] == 7, "old contents survived or neighbours hurt");

    /* ---- file mappings */
    int fd = open("/tmp/ub_map.dat", O_RDWR | O_CREAT | O_TRUNC, 0600);
    char pat[PG * 2 + 100]; for (size_t i = 0; i < sizeof pat; i++) pat[i] = (char)(i * 7 + 3);
    ssize_t wn = 0;
    if (fd >= 0) { wn = write(fd, pat, sizeof pat); fsync(fd); }
    CHECKC("tmpfile_create", fd >= 0);
    if (fd >= 0) {
        CHECK("tmpfile_write_full", wn == (ssize_t)sizeof pat, "write of %zu bytes returned %zd (errno %d)", sizeof pat, wn, errno);
        char rb[sizeof pat]; ssize_t rn = pread(fd, rb, sizeof rb, 0);
        CHECK("tmpfile_pread_full", rn == (ssize_t)sizeof pat && memcmp(rb, pat, sizeof pat) == 0, "pread returned %zd, content %s", rn, rn > 0 && memcmp(rb, pat, rn) == 0 ? "matches as far as it goes" : "differs");
    }
    if (fd >= 0) {
        char *m = mmap(0, sizeof pat, PROT_READ, MAP_PRIVATE, fd, 0);
        CHECKC("mmap_file_private", m != MAP_FAILED);
        if (m != MAP_FAILED) {
            CHECK("mmap_file_contents", memcmp(m, pat, sizeof pat) == 0, "file bytes differ");
            CHECK("mmap_file_tail_zero", m[sizeof pat] == 0 || (sizeof pat % PG) == 0, "tail of last page not zero");
            CHECK("mmap_file_ro_write_faults", faults_write(m), "write into PROT_READ file mapping went through");
        }
        char *m2 = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, PG);
        CHECKC("mmap_file_offset", m2 != MAP_FAILED);
        if (m2 != MAP_FAILED) {
            CHECK("mmap_file_offset_contents", memcmp(m2, pat + PG, PG) == 0, "offset mapping shows wrong bytes");
            m2[0] = 99;
            char chk; (void)!pread(fd, &chk, 1, PG);
            CHECK("mmap_private_cow", chk == pat[PG], "MAP_PRIVATE write reached the file");
        }
        char *m3 = mmap(0, PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        CHECKC("mmap_file_shared", m3 != MAP_FAILED);
        if (m3 != MAP_FAILED) {
            m3[10] = 55; msync(m3, PG, MS_SYNC);
            char chk; (void)!pread(fd, &chk, 1, 10);
            CHECK("mmap_shared_writeback", chk == 55, "MAP_SHARED write not visible in the file (got %d)", chk);
        }
        close(fd);
    }
    /* ---- madvise / mremap / mlock */
    char *d = mmap(0, 4 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    memset(d, 5, 4 * PG);
    errno = 0;
    r = madvise(d, 4 * PG, MADV_DONTNEED);
    CHECKC("madvise_dontneed_call", r == 0);
    if (r == 0) CHECK("madvise_dontneed_zeroes", d[0] == 0 && d[3 * PG] == 0, "pages not zero after MADV_DONTNEED (%d)", d[0]);
    errno = 0; r = madvise(d, 4 * PG, MADV_FREE);
    CHECKC("madvise_free_call", r == 0 || errno == EINVAL);
    errno = 0; r = madvise(d, 4 * PG, MADV_NOHUGEPAGE);
    CHECKC("madvise_nohuge_call", r == 0);
    errno = 0;
    void *g = mremap(d, 4 * PG, 8 * PG, MREMAP_MAYMOVE);
    CHECKC("mremap_grow", g != MAP_FAILED);
    if (g != MAP_FAILED) { ((char *)g)[7 * PG] = 1; CHECK("mremap_grown_usable", ((char *)g)[7 * PG] == 1, "grown area not usable"); }
    errno = 0; r = mlock(a, PG);
    CHECKC("mlock_call", r == 0);

    /* ---- big reservations: how much address space can a process reserve (Firefox reserves GBs) */
    size_t sizes[] = { 64u << 20, 256u << 20, 1024u << 20 };
    const char *names[] = { "reserve_64M", "reserve_256M", "reserve_1G" };
    for (int i = 0; i < 3; i++) {
        errno = 0;
        void *big = mmap(0, sizes[i], PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (big == MAP_FAILED) GAP(names[i], "mmap failed errno=%d", errno); else { PASS(names[i]); munmap(big, sizes[i]); }
    }
    /* a committed 8 MiB buffer (a real frame, memory must exist) */
    errno = 0;
    char *bb = mmap(0, 8 << 20, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (bb == MAP_FAILED) GAP("commit_8M", "errno=%d", errno);
    else { memset(bb, 1, 8 << 20); PASS("commit_8M"); munmap(bb, 8 << 20); }
    return 0;
}
