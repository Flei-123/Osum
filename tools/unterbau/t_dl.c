/* dlopen of foreign shared objects from files (needs mmap with a file descriptor, MAP_FIXED, real mprotect). */
#define TNAME "dl"
#include "t.h"
#include <dlfcn.h>
#include <link.h>
#include <pthread.h>

static int count_phdr(struct dl_phdr_info *i, size_t s, void *d) { (void)i; (void)s; (*(int *)d)++; return 0; }
static int g_tls_seen;
static void *thr(void *a) { int (*get)(void) = a; g_tls_seen = get(); return 0; }

int main(void)
{
    void *h1 = dlopen("/lib/libub1.so", RTLD_NOW);
    CHECK("open1", h1 != 0, "dlerror=%s", dlerror());
    if (!h1) goto next;
    int (*add)(int, int) = dlsym(h1, "ub1_add");
    CHECK("sym_add", add != 0, "dlsym failed");
    if (add) CHECK("call_add", add(2, 3) == 5, "got %d", add(2, 3));
    int (*ctor)(void) = dlsym(h1, "ub1_ctor");
    if (ctor) CHECK("ctor", ctor() == 1, "constructor did not run: %d", ctor());
    const char *(*msg)(void) = dlsym(h1, "ub1_msg");
    if (msg) CHECK("reloc_ptr", strcmp(msg(), "libub1 string") == 0, "got '%s'", msg());
    int (*bss)(void) = dlsym(h1, "ub1_bss_sum");
    int *bssv = dlsym(h1, "ub1_bss");
    if (bss && bssv) { bssv[500] = 9; CHECK("bss_zero_and_rw", bss() == 9, "bss sum %d", bss()); }
    int *dv = dlsym(h1, "ub1_data");
    if (dv) { *dv = 42; CHECK("data_rw", add(1, 1) == 3, "data write not seen: %d", add(1, 1)); *dv = 41; }
    int (*fmt)(char *, int) = dlsym(h1, "ub1_fmt");
    if (fmt) { char b[64]; fmt(b, sizeof b); CHECK("libc_in_lib", strcmp(b, "libub1 string/13") == 0, "got '%s'", b); }
    Dl_info di;
    CHECK("dladdr", add && dladdr((void *)add, &di) && di.dli_fname && strstr(di.dli_fname, "libub1"), "dladdr failed");
    int n = 0; dl_iterate_phdr(count_phdr, &n);
    CHECK("iterate_phdr", n >= 3, "only %d objects", n);

next:;
    void *h2 = dlopen("/lib/libub2.so", RTLD_NOW | RTLD_GLOBAL);
    CHECK("open2_needed", h2 != 0, "dlerror=%s", dlerror());
    if (h2) { int (*c2)(int) = dlsym(h2, "ub2_call"); if (c2) CHECK("call_across", c2(1) == 101, "got %d", c2(1)); }

    void *h3 = dlopen("/lib/libub3.so", RTLD_NOW);
    CHECK("open3_tls", h3 != 0, "dlerror=%s", dlerror());
    if (h3) {
        int (*get)(void) = dlsym(h3, "ub3_get");
        void (*set)(int) = dlsym(h3, "ub3_set");
        if (get && set) {
            CHECK("tls_main", get() == 7, "got %d", get());
            set(11);
            pthread_t t; pthread_create(&t, 0, thr, get); pthread_join(t, 0);
            CHECK("tls_per_thread", g_tls_seen == 7 && get() == 11, "thread saw %d, main %d", g_tls_seen, get());
        }
    }
    void *hx = dlopen("/lib/gibtesnicht.so", RTLD_NOW);
    CHECK("missing_is_null", hx == 0 && dlerror() != 0, "dlopen of a missing file did not fail cleanly");
    if (h1) CHECK("close", dlclose(h1) == 0, "dlclose failed");
    void *h1b = dlopen("/lib/libub1.so", RTLD_NOW);
    CHECK("reopen", h1b != 0, "second dlopen failed: %s", dlerror());
    return 0;
}
