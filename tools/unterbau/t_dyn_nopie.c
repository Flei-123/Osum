/* SPDX-License-Identifier: GPL-2.0-only
 * dynamic non-PIE (ET_EXEC + PT_INTERP, gcc -no-pie): the executable at 0x400000, the interpreter and libc.so above the low window. */
#define TNAME "dyn_nopie"
#include "t.h"
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>

static int initial_data = 41;
static int zero_bss[2048];
static const char ro_text[] = "read-only text";
static char *argv0;

static void *thread_body(void *arg)
{
    *(int *)arg = initial_data + 1;
    return arg;
}

int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "child") == 0) return 6;
    argv0 = argv[0];
    uintptr_t data = (uintptr_t)&initial_data;
    uintptr_t code = (uintptr_t)&main;
    CHECK("exe_in_low_window", data >= 0x400000 && data < 0x1000000 && code >= 0x400000 && code < 0x1000000, "data %#lx code %#lx", (unsigned long)data, (unsigned long)code);
    CHECK("libc_above_low_window", (uintptr_t)&strlen >= 0x1000000, "strlen at %p", (void *)&strlen);
    CHECK("data_initial_and_write", initial_data == 41 && (initial_data = 42) == 42, "got %d", initial_data);
    zero_bss[2047] = 3;
    int sum = 0;
    for (int i = 0; i < 2047; i++) sum |= zero_bss[i];
    CHECK("bss_zero_and_write", sum == 0 && zero_bss[2047] == 3, "sum %d", sum);
    CHECK("rodata", strcmp(ro_text, "read-only text") == 0, "bad rodata");

    char *m = malloc(2 * 1024 * 1024);
    CHECK("malloc_large", m != NULL && (memset(m, 0x5a, 2 * 1024 * 1024), (unsigned char)m[2 * 1024 * 1024 - 1] == 0x5a), "malloc");
    int fd = open("/dev/null", O_WRONLY);
    ssize_t w = write(fd, ro_text, sizeof ro_text);
    CHECK("syscall_buffer_from_low", w == (ssize_t)sizeof ro_text, "wrote %ld", (long)w);

    int slot = 0;
    pthread_t th;
    int prc = pthread_create(&th, NULL, thread_body, &slot);
    if (prc == 0) pthread_join(th, NULL);
    CHECK("thread_writes_low_data", prc == 0 && slot == 43, "rc %d slot %d", prc, slot);

    void *h = dlopen("libc.so", RTLD_NOW);
    if (!h) h = dlopen("/lib/ld-musl-x86_64.so.1", RTLD_NOW);
    CHECK("dlopen_with_nopie_exe", h != NULL, "dlopen failed");

    void *fixed = mmap((void *)0x600000, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    CHECK("map_fixed_low_rejected", fixed == MAP_FAILED, "mapped at %p", fixed);
    void *hint = mmap((void *)0x600000, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK("map_hint_low_not_forced", hint == MAP_FAILED || ((uintptr_t)hint != 0x600000), "hint honoured at %p", hint);

    pid_t c = fork();
    if (c == 0) { initial_data = 99; _exit(initial_data == 99 ? 3 : 4); }
    int st = 0;
    pid_t wp = c > 0 ? waitpid(c, &st, 0) : -1;
    CHECK("fork_child_ran", wp == c && WIFEXITED(st) && WEXITSTATUS(st) == 3, "st %#x", st);
    CHECK("fork_copy_private", initial_data == 42, "data %d", initial_data);

    c = fork();
    if (c == 0) {
        char *args[] = { argv0, "child", NULL };
        execv(argv0, args);
        _exit(77);
    }
    wp = c > 0 ? waitpid(c, &st, 0) : -1;
    CHECK("exec_self", wp == c && WIFEXITED(st) && WEXITSTATUS(st) == 6, "st %#x", st);

    FILE *f = fopen("/proc/self/maps", "r");
    int saw_low = 0;
    if (f) {
        char line[256];
        while (fgets(line, sizeof line, f)) {
            if (strncmp(line, "000000000040", 12) == 0 || strncmp(line, "000000000050", 12) == 0) saw_low = 1;
        }
        fclose(f);
    }
    CHECK("proc_maps_low_image", saw_low, "no 0x4xxxxx line");
    return 0;
}
