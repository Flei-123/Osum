#define TNAME "fsspeed"
#include "t.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <time.h>

#define DIR_PATH "/tmp/fsb"
#define FILE_COUNT 400
#define SAMPLE_COUNT 40
#define APPEND_COUNT 400
#define APPEND_BYTES 328
#define LOOKUP_LIMIT_US 2500
#define CREATE_LIMIT_US 30000
#define APPEND_LIMIT_US 3500
#define RENAME_LIMIT_US 22000
#define UNLINK_LIMIT_US 13000

static long now_us(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000000L + t.tv_nsec / 1000;
}

static void path_of(char *buf, int i)
{
    snprintf(buf, 64, DIR_PATH "/f%04d", i);
}

static void churn(void)
{
    rename(DIR_PATH "/m0", DIR_PATH "/m1");
    rename(DIR_PATH "/m1", DIR_PATH "/m0");
}

static long create_range(int from, int to)
{
    char p[64];
    long t0 = now_us();
    for (int i = from; i < to; i++) {
        path_of(p, i);
        int fd = open(p, O_CREAT | O_EXCL | O_WRONLY, 0644);
        if (fd >= 0)
            close(fd);
    }
    return (now_us() - t0) / (to - from);
}

static long sample_calls(int kind)
{
    char p[64];
    struct stat st;
    long total = 0;
    for (int k = 0; k < SAMPLE_COUNT; k++) {
        path_of(p, FILE_COUNT - 1 - k * 2);
        churn();
        long t0 = now_us();
        if (kind == 0) {
            int fd = open(p, O_RDONLY);
            long t1 = now_us();
            if (fd >= 0)
                close(fd);
            total += t1 - t0;
            continue;
        }
        if (kind == 1)
            stat(p, &st);
        else
            access(p, R_OK);
        total += now_us() - t0;
    }
    return total / SAMPLE_COUNT;
}

static long append_calls(int bytes, int count)
{
    char *buf = calloc(1, bytes);
    struct iovec iov = { buf, (size_t)bytes };
    int fd = open(DIR_PATH "/log", O_CREAT | O_WRONLY | O_APPEND, 0644);
    long total = 0;
    for (int i = 0; i < count; i++) {
        long t0 = now_us();
        writev(fd, &iov, 1);
        total += now_us() - t0;
    }
    close(fd);
    free(buf);
    return total / count;
}

static long rename_calls(void)
{
    char a[64], b[64];
    long total = 0;
    for (int i = 0; i < SAMPLE_COUNT; i++) {
        path_of(a, 5 + i);
        snprintf(b, sizeof b, DIR_PATH "/t%04d", i);
        int fd = open(b, O_CREAT | O_WRONLY, 0644);
        if (fd >= 0)
            close(fd);
        long t0 = now_us();
        rename(b, a);
        total += now_us() - t0;
    }
    return total / SAMPLE_COUNT;
}

static long unlink_calls(void)
{
    char p[64];
    long t0 = now_us();
    for (int i = 0; i < SAMPLE_COUNT; i++) {
        path_of(p, 100 + i);
        unlink(p);
    }
    return (now_us() - t0) / SAMPLE_COUNT;
}

static int exists(const char *p)
{
    struct stat st;
    return stat(p, &st) == 0;
}

static void touch(const char *p)
{
    int fd = open(p, O_CREAT | O_WRONLY, 0644);
    if (fd >= 0)
        close(fd);
}

static int coherence_basic(void)
{
    touch(DIR_PATH "/c_a");
    int ok = exists(DIR_PATH "/c_a") && !exists(DIR_PATH "/c_b");
    touch(DIR_PATH "/c_b");
    ok = ok && exists(DIR_PATH "/c_b");
    rename(DIR_PATH "/c_a", DIR_PATH "/c_c");
    ok = ok && !exists(DIR_PATH "/c_a") && exists(DIR_PATH "/c_c");
    unlink(DIR_PATH "/c_b");
    ok = ok && !exists(DIR_PATH "/c_b");
    unlink(DIR_PATH "/c_c");
    return ok && !exists(DIR_PATH "/c_c");
}

static int coherence_link(void)
{
    touch(DIR_PATH "/l_a");
    link(DIR_PATH "/l_a", DIR_PATH "/l_b");
    int ok = exists(DIR_PATH "/l_a") && exists(DIR_PATH "/l_b");
    unlink(DIR_PATH "/l_a");
    ok = ok && !exists(DIR_PATH "/l_a") && exists(DIR_PATH "/l_b");
    unlink(DIR_PATH "/l_b");
    return ok && !exists(DIR_PATH "/l_b");
}

static int coherence_dir(void)
{
    mkdir(DIR_PATH "/d_a", 0755);
    touch(DIR_PATH "/d_a/f");
    int ok = exists(DIR_PATH "/d_a/f");
    rename(DIR_PATH "/d_a", DIR_PATH "/d_b");
    ok = ok && !exists(DIR_PATH "/d_a/f") && exists(DIR_PATH "/d_b/f");
    unlink(DIR_PATH "/d_b/f");
    ok = ok && !exists(DIR_PATH "/d_b/f");
    rmdir(DIR_PATH "/d_b");
    return ok && !exists(DIR_PATH "/d_b");
}

static int coherence_slot_reuse(void)
{
    char p[64];
    int seen = 0;
    int expect = 0;
    for (int i = 0; i < 3; i++) {
        snprintf(p, sizeof p, DIR_PATH "/f%04d", 200 + i * 7);
        unlink(p);
        snprintf(p, sizeof p, DIR_PATH "/r%04d", i);
        touch(p);
    }
    DIR *d = opendir(DIR_PATH);
    struct dirent *e;
    while (d && (e = readdir(d)) != NULL) {
        if (e->d_name[0] == 'r')
            seen++;
    }
    if (d)
        closedir(d);
    for (int i = 0; i < 3; i++) {
        snprintf(p, sizeof p, DIR_PATH "/r%04d", i);
        expect += exists(p);
        unlink(p);
    }
    return seen == 3 && expect == 3;
}

static int listing_complete(void)
{
    int count = 0;
    DIR *d = opendir(DIR_PATH);
    struct dirent *e;
    while (d && (e = readdir(d)) != NULL) {
        if (e->d_name[0] == 'f')
            count++;
    }
    if (d)
        closedir(d);
    return count;
}

int main(void)
{
    mkdir(DIR_PATH, 0755);
    int fd = open(DIR_PATH "/m0", O_CREAT | O_WRONLY, 0644);
    if (fd >= 0)
        close(fd);
    long create_first = create_range(0, SAMPLE_COUNT);
    create_range(SAMPLE_COUNT, FILE_COUNT - SAMPLE_COUNT);
    long create_last = create_range(FILE_COUNT - SAMPLE_COUNT, FILE_COUNT);
    long open_us = sample_calls(0);
    long stat_us = sample_calls(1);
    long access_us = sample_calls(2);
    long append_small = append_calls(APPEND_BYTES, APPEND_COUNT);
    long append_page = append_calls(4096, 100);
    long rename_us = rename_calls();
    long unlink_us = unlink_calls();
    int listed = listing_complete();
    PASS("metrics", "create_first=%ld create_last=%ld open=%ld stat=%ld access=%ld writev_small=%ld writev_page=%ld rename=%ld unlink=%ld",
        create_first, create_last, open_us, stat_us, access_us, append_small, append_page, rename_us, unlink_us);
    CHECK("coherence_basic", coherence_basic(), "stale lookup after create/rename/unlink");
    CHECK("coherence_link", coherence_link(), "stale lookup after unlinking one hard link");
    CHECK("coherence_dir", coherence_dir(), "stale lookup below a renamed directory");
    CHECK("coherence_slot_reuse", coherence_slot_reuse(), "freed directory slots not reused or entries lost");
    CHECK("listing_complete", listed == FILE_COUNT - SAMPLE_COUNT, "listed=%d expected=%d", listed, FILE_COUNT - SAMPLE_COUNT);
    CHECK("create_first", create_first < CREATE_LIMIT_US, "us=%ld limit=%d", create_first, CREATE_LIMIT_US);
    CHECK("create_last", create_last < CREATE_LIMIT_US, "us=%ld limit=%d", create_last, CREATE_LIMIT_US);
    CHECK("open_cold", open_us < LOOKUP_LIMIT_US, "us=%ld limit=%d", open_us, LOOKUP_LIMIT_US);
    CHECK("stat_cold", stat_us < LOOKUP_LIMIT_US, "us=%ld limit=%d", stat_us, LOOKUP_LIMIT_US);
    CHECK("access_cold", access_us < LOOKUP_LIMIT_US, "us=%ld limit=%d", access_us, LOOKUP_LIMIT_US);
    CHECK("writev_small", append_small < APPEND_LIMIT_US, "us=%ld limit=%d", append_small, APPEND_LIMIT_US);
    CHECK("writev_page", append_page < APPEND_LIMIT_US, "us=%ld limit=%d", append_page, APPEND_LIMIT_US);
    CHECK("rename_over", rename_us < RENAME_LIMIT_US, "us=%ld limit=%d", rename_us, RENAME_LIMIT_US);
    CHECK("unlink", unlink_us < UNLINK_LIMIT_US, "us=%ld limit=%d", unlink_us, UNLINK_LIMIT_US);
    return 0;
}
