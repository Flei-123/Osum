#define TNAME "shmclose"
#include "t.h"
#include <pthread.h>
#include <stdint.h>
#include <sys/mman.h>

#define ROUNDS 3000
#define WINDOW 48
#define JITTER_MASK 31
#define PAGE_BYTES 4096

static volatile int armed;
static volatile int finished;
static volatile int stop;
static volatile int shared_fd;
static void *volatile mapped;
static unsigned char *held[WINDOW];
static unsigned char held_pattern[WINDOW];
static int corrupted;
static int mapped_rounds;

static inline void relax(void)
{
    __builtin_ia32_pause();
}

static uint32_t next_random(uint32_t *s)
{
    uint32_t x = *s;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return *s = x;
}

static void *mapper(void *arg)
{
    (void)arg;
    while (!stop) {
        while (armed != 1 && !stop)
            relax();
        if (stop)
            break;
        int fd = shared_fd;
        armed = 2;
        void *p = mmap(NULL, PAGE_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        mapped = p == MAP_FAILED ? NULL : p;
        finished = 1;
    }
    return NULL;
}

static int fill_object(int fd, unsigned char value)
{
    unsigned char page[PAGE_BYTES];
    memset(page, value, sizeof page);
    return pwrite(fd, page, sizeof page, 0) == (ssize_t)sizeof page ? 0 : -1;
}

static int page_intact(const unsigned char *p, unsigned char value)
{
    for (int i = 0; i < PAGE_BYTES; i++)
        if (p[i] != value)
            return 0;
    return 1;
}

static void close_after_map(void)
{
    int fd = memfd_create("shmclose-seq", 0);
    if (fd < 0 || ftruncate(fd, PAGE_BYTES) != 0 || fill_object(fd, 0x5a) != 0) {
        FAIL("map_survives_close", "setup failed errno %d", errno);
        return;
    }
    unsigned char *p = mmap(NULL, PAGE_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (p == MAP_FAILED) {
        FAIL("map_survives_close", "mmap failed errno %d", errno);
        return;
    }
    close(fd);
    CHECK("map_survives_close", page_intact(p, 0x5a), "content changed after close");
    munmap(p, PAGE_BYTES);
}

static void retire(int slot)
{
    if (!held[slot])
        return;
    if (!page_intact(held[slot], held_pattern[slot]))
        corrupted++;
    munmap(held[slot], PAGE_BYTES);
    held[slot] = NULL;
}

static void close_race(void)
{
    uint32_t seed = 0x9e3779b9;
    pthread_t th;
    if (pthread_create(&th, NULL, mapper, NULL) != 0) {
        FAIL("close_race_survived", "pthread_create failed");
        return;
    }
    for (int i = 0; i < ROUNDS; i++) {
        int fd = memfd_create("shmclose", 0);
        if (fd < 0 || ftruncate(fd, PAGE_BYTES) != 0) {
            FAIL("close_race_survived", "memfd setup failed round %d errno %d", i, errno);
            break;
        }
        unsigned char value = (unsigned char)(i % 250 + 1);
        (void)fill_object(fd, value);
        shared_fd = fd;
        mapped = NULL;
        finished = 0;
        armed = 1;
        while (armed != 2)
            relax();
        for (uint32_t j = next_random(&seed) & JITTER_MASK; j > 0; j--)
            relax();
        close(fd);
        while (!finished)
            relax();
        armed = 0;
        retire(i % WINDOW);
        held[i % WINDOW] = mapped;
        held_pattern[i % WINDOW] = value;
        if (mapped)
            mapped_rounds++;
    }
    stop = 1;
    armed = 1;
    pthread_join(th, NULL);
    for (int i = 0; i < WINDOW; i++)
        retire(i);
    CHECK("close_race_mappings_intact", corrupted == 0, "%d of %d surviving mappings changed", corrupted, mapped_rounds);
    PASS("close_race_survived");
}

int main(void)
{
    close_after_map();
    close_race();
    return 0;
}
