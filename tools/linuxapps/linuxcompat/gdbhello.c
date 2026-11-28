#include <stdio.h>
#include <stdlib.h>

static int add(int left, int right)
{
    int sum = left + right;
    return sum;
}

int main(int argc, char **argv)
{
    int total = add(argc, 41);
    printf("total=%d\n", total);
    if (argc > 1 && argv[1][0] == 'c') {
        volatile int *bad = 0;
        *bad = total;
    }
    return 0;
}
