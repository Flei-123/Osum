/* malloc across threads (musl mallocng): stress, cross-thread free, realloc, large blocks, pattern integrity. */
#define TNAME "malloc"
#include "t.h"
#include <pthread.h>
#include <stdlib.h>
#include <stdint.h>
#include <sched.h>

#define NT 4
static volatile int bad[NT];
static uint32_t rnd(uint32_t *s) { *s = *s * 1664525u + 1013904223u; return *s >> 8; }
static void *stress(void *a)
{
    long id = (long)a; uint32_t seed = 1234 + id * 77;
    void *slot[64] = { 0 }; size_t sz[64] = { 0 };
    for (int it = 0; it < 6000; it++) {
        int i = rnd(&seed) % 64;
        if (slot[i]) {
            unsigned char *p = slot[i];
            for (size_t k = 0; k < sz[i]; k += 97) if (p[k] != (unsigned char)(i + sz[i])) { bad[id]++; break; }
            if (rnd(&seed) & 1) { size_t n = rnd(&seed) % 20000 + 1; void *q = realloc(slot[i], n); if (!q) { bad[id]++; continue; } size_t keep = n < sz[i] ? n : sz[i]; for (size_t k = 0; k < keep; k += 97) if (((unsigned char *)q)[k] != (unsigned char)(i + sz[i])) { bad[id]++; break; } slot[i] = q; sz[i] = n; memset(q, (unsigned char)(i + n), n); }
            else { free(slot[i]); slot[i] = 0; }
        } else {
            size_t n = (rnd(&seed) % 4 == 0) ? rnd(&seed) % 100000 + 1 : rnd(&seed) % 300 + 1;
            void *q = malloc(n); if (!q) { bad[id]++; continue; }
            memset(q, (unsigned char)(i + n), n); slot[i] = q; sz[i] = n;
        }
    }
    for (int i = 0; i < 64; i++) free(slot[i]);
    return 0;
}
/* producer allocates, consumer (another thread) frees */
static void *box[200]; static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER; static int head, tail, prod_done;
static void *producer(void *a) { (void)a; for (int i = 0; i < 4000; i++) { void *p = malloc(40 + (i % 7) * 100); if (!p) continue; memset(p, 0x5A, 40); for (;;) { pthread_mutex_lock(&mu); if (head - tail < 200) { box[head++ % 200] = p; pthread_mutex_unlock(&mu); break; } pthread_mutex_unlock(&mu); sched_yield(); } } pthread_mutex_lock(&mu); prod_done = 1; pthread_mutex_unlock(&mu); return 0; }
static int freed, corrupt;
static void *consumer(void *a) { (void)a; for (;;) { pthread_mutex_lock(&mu); if (tail < head) { void *p = box[tail++ % 200]; pthread_mutex_unlock(&mu); if (((unsigned char *)p)[0] != 0x5A) corrupt++; free(p); freed++; } else { int d = prod_done; pthread_mutex_unlock(&mu); if (d) break; sched_yield(); } } return 0; }

static void *run_stress_once(void *a) { return stress(a); }

int main(void)
{
    pthread_t t[NT];
    /* diagnosis first: where does malloc run dry, with one thread? */
    { size_t n = 0; void *head = 0; errno = 0; for (;;) { void **q = malloc(64); if (!q) break; *q = head; head = q; if (++n >= 200000) break; } int e = errno;
      while (head) { void *nx = *(void **)head; free(head); head = nx; }
      t_emit("diag_small_blocks_until_null", n >= 100000 ? "PASS" : "FAIL", "%zu x 64-byte blocks before NULL (errno %d)", n, e); }
    { size_t n = 0; void *head = 0; errno = 0; for (;;) { void **q = malloc(65536); if (!q) break; *q = head; head = q; if (++n >= 4000) break; } int e = errno;
      while (head) { void *nx = *(void **)head; free(head); head = nx; }
      t_emit("diag_64k_blocks_until_null", n >= 1500 ? "PASS" : "FAIL", "%zu x 64 KiB before NULL = %zu MiB (errno %d)", n, n >> 4, e); }
    { void *v[32]; int bad1 = 0; for (int r = 0; r < 300 && !bad1; r++) { for (int i = 0; i < 32; i++) { v[i] = malloc(30000 + r * 7 + i); if (!v[i]) bad1 = r + 1; } for (int i = 0; i < 32; i++) free(v[i]); }
      t_emit("diag_alloc_free_cycles", !bad1 ? "PASS" : "FAIL", "300 rounds of 32 x ~30 KB alloc/free, first NULL in round %d (memory is not given back or addresses are not reused)", bad1); }
    { bad[0] = 0; run_stress_once((void *)0L); t_emit("st_stress_integrity", !bad[0] ? "PASS" : "FAIL", "single thread, %d corruptions/NULLs", bad[0]); }
    for (long i = 0; i < NT; i++) if (pthread_create(&t[i], 0, stress, (void *)i)) { FAIL("threads_create", "pthread_create failed"); return 1; }
    for (int i = 0; i < NT; i++) pthread_join(t[i], 0);
    CHECK("mt_stress_integrity", !bad[0] && !bad[1] && !bad[2] && !bad[3], "corruption/NULL per thread: %d %d %d %d", bad[0], bad[1], bad[2], bad[3]);
    pthread_t p, c; pthread_create(&p, 0, producer, 0); pthread_create(&c, 0, consumer, 0);
    pthread_join(p, 0); pthread_join(c, 0);
    CHECK("cross_thread_free", freed == 4000 && corrupt == 0, "freed %d corrupt %d", freed, corrupt);
    /* large blocks (mmap threshold), realloc growth, calloc zero */
    char *big = malloc(5 << 20); CHECK("malloc_5M", big != 0, "malloc(5 MiB) failed"); if (big) { memset(big, 3, 5 << 20); big = realloc(big, 9 << 20); CHECK("realloc_grow_9M", big && big[(5 << 20) - 1] == 3, "realloc lost data or failed"); free(big); }
    char *z = calloc(1 << 20, 1); int zero = z != 0; for (int i = 0; z && i < (1 << 20); i += 4093) if (z[i]) zero = 0;
    CHECK("calloc_zero_1M", zero, "calloc block not zero"); free(z);
    void *al = 0; int e = posix_memalign(&al, 65536, 1000);
    CHECK("posix_memalign_64k", e == 0 && ((uintptr_t)al & 65535) == 0, "e=%d p=%p", e, al); free(al);
    /* many small allocations: fragmentation + return of memory */
    void **v = malloc(sizeof(void *) * 50000); int okn = 1;
    for (int i = 0; i < 50000; i++) { v[i] = malloc(24 + (i & 63)); if (!v[i]) { okn = 0; break; } }
    for (int i = 0; i < 50000; i++) free(v[i]); free(v);
    CHECK("50000_small_blocks", okn, "malloc returned NULL early");
    return 0;
}
