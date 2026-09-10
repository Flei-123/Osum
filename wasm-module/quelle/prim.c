/* DERSELBE ALGORITHMUS wie kernel/app/prim.fi -- Probedivision.
   Wird nach wasm32-wasi uebersetzt und im Deuter ausgefuehrt. */
#include <stdio.h>
#include <stdlib.h>

static int ist_prim(unsigned long long n) {
    if (n < 2) return 0;
    if (n % 2 == 0) return n == 2;
    for (unsigned long long d = 3; d * d <= n; d += 2)
        if (n % d == 0) return 0;
    return 1;
}

int main(int argc, char **argv) {
    unsigned long long grenze = 200000;
    if (argc > 1) grenze = strtoull(argv[1], 0, 10);
    unsigned long long zahl = 0;
    for (unsigned long long k = 2; k < grenze; k++)
        if (ist_prim(k)) zahl++;
    printf("primzahlen unter %llu: %llu\n", grenze, zahl);
    return 0;
}
