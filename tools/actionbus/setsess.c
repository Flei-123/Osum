/* SPDX-License-Identifier: GPL-2.0-only
 * tools/actionbus/setsess.c -- TEST AID: say whose session this is.
 *
 * On a real device /bin/glogin enters the uid of the person who signed
 * in into the kernel (SYS_SPERRE 1870, op 7, root only, once) and then
 * drops to it. The action-bus test has no sign-in screen, so this does
 * the one kernel call glogin does -- nothing else -- and the test then
 * runs `act` as that uid with /bin/su.
 *
 *   setsess <uid>        prints "setsess: rc=<n>"
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/syscall.h>

int main(int argc, char **argv)
{
    long r;
    if (argc < 2) {
        fprintf(stderr, "usage: setsess <uid>\n");
        return 2;
    }
    r = syscall(1870, 7L, atol(argv[1]), 0L);
    printf("setsess: rc=%ld who=%ld\n", r, syscall(1870, 8L, 0L, 0L));
    return r < 0 ? 1 : 0;
}
