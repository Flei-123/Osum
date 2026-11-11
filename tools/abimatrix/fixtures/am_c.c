#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int cmp(const void *a, const void *b) { return *(const int *)a - *(const int *)b; }

static void *worker(void *arg) { *(int *)arg = 41; return NULL; }

int main(void) {
    int v[5] = {5, 3, 9, 1, 7};
    qsort(v, 5, sizeof v[0], cmp);
    char *buf = malloc(4096);
    memset(buf, 'x', 4095);
    buf[4095] = 0;
    FILE *f = fopen("/tmp/am_c.txt", "w");
    if (!f) return 2;
    fprintf(f, "%d%d", v[0], v[4]);
    fclose(f);
    char rd[16] = {0};
    f = fopen("/tmp/am_c.txt", "r");
    if (!f || !fgets(rd, sizeof rd, f)) return 3;
    fclose(f);
    int shared = 0;
    pthread_t t;
    pthread_create(&t, NULL, worker, &shared);
    pthread_join(t, NULL);
    printf("am-c ok %s %zu %d\n", rd, strlen(buf), shared + 1);
    return 0;
}
