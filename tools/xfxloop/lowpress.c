/* SPDX-License-Identifier: GPL-2.0-only
 * Empties the low frame window (first GiB) with private file pages and holds them until killed. Usage: lowpress <leave-free-MiB> */
#include "lowpress.h"

int main(int argc, char **argv)
{
    long leave = (argc > 1 ? atol(argv[1]) : 64) << 8;
    long held = lowpress_eat(leave);
    printf("lowpress: held %ld MiB, free low %ld MiB\n", held >> 8, lp_free_low() >> 8);
    fflush(stdout);
    for (;;) pause();
}
