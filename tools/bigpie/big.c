#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#define N (14u<<20)
static const unsigned char blob[N] = {1,2,3};
static unsigned char dat[300000] = {9};
static unsigned char zer[2000000];
int main(int argc, char **argv) {
    unsigned long s = 0;
    for (unsigned i = 0; i < N; i += 4093) s += blob[i];
    dat[5] = 7; zer[1999999] = 3;
    char *m = malloc(100000); memset(m, 5, 100000);
    printf("BIGPIE sum=%lu dat=%d zer=%d m=%d argc=%d\n", s, dat[0]+dat[5], zer[1999999]+zer[0], m[99999], argc);
    return 0;
}
