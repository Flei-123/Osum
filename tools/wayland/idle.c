/* SPDX-License-Identifier: GPL-2.0-only
 * tools/wayland/idle.c -- WHAT THE WHOLE SYSTEM DOES WHILE NOTHING IS GOING ON.
 *
 *   idle <milliseconds> <label>      prints   idle[<label>]: syscalls=<n> in <ms> ms  (<per second> per second)
 *
 * The kernel counts every system call (SYS_OSUM_SYSINFO, I_SYSCALLS). A server that loops with yield() for ever makes tens of
 * thousands per second; one that sleeps in poll() makes a few per second. The count is of the whole system, so the run keeps
 * everything else quiet: a shell sleeping in nanosleep, wayd, and this program.
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>

#define SYS_OSUM_SYSINFO 1002
#define I_SYSCALLS 10

int main(int argc, char **argv)
{
    long ms = argc > 1 ? atol(argv[1]) : 5000;
    const char *label = argc > 2 ? argv[2] : "?";
    long a = syscall(SYS_OSUM_SYSINFO, I_SYSCALLS, 0, 0);
    struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
    long b = syscall(SYS_OSUM_SYSINFO, I_SYSCALLS, 0, 0);
    printf("idle[%s]: syscalls=%ld in %ld ms (%ld per second)\n", label, b - a, ms, (b - a) * 1000 / ms);
    return 0;
}
