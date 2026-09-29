/* SPDX-License-Identifier: GPL-2.0-only
 * tools/actionbus/fakeplayer.c -- A LINUX PROGRAM THAT KNOWS NOTHING OF
 * ORIENTOS, for the compat adapters of the action bus (AB-008).
 *
 * Plain POSIX C, built with musl as a static Linux binary (the same way
 * tools/foreign builds Lua and SQLite). It behaves like the remote-control
 * command line of a media player (playerctl, mpc): it keeps its state in
 * /var/player/state and prints key=value lines. The wrapper manifest in
 * tools/actionbus/run.sh makes actions out of it; the program itself is
 * never changed.
 *
 *   fakeplayer status | play | pause | volume <0..100> | title <text>
 *   fakeplayer argv <...>   print what it received, one line per argument
 *   fakeplayer hang         never returns (the broker must kill it)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define STATE "/var/player/state"

static char state[16] = "stopped";
static char title[128] = "nothing";
static int volume = 50;

static void load(void)
{
    FILE *f = fopen(STATE, "r");
    char line[256];
    if (!f)
        return;
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\n")] = 0;
        if (!strncmp(line, "state=", 6))
            snprintf(state, sizeof state, "%s", line + 6);
        else if (!strncmp(line, "title=", 6))
            snprintf(title, sizeof title, "%s", line + 6);
        else if (!strncmp(line, "volume=", 7))
            volume = atoi(line + 7);
    }
    fclose(f);
}

static int save(void)
{
    FILE *f = fopen(STATE, "w");
    if (!f) {
        printf("cannot write %s\n", STATE);
        return 1;
    }
    fprintf(f, "state=%s\ntitle=%s\nvolume=%d\n", state, title, volume);
    fclose(f);
    return 0;
}

/* the kernel's word on who we are: /proc/self/status, "Origin:" */
static void origin(void)
{
    FILE *f = fopen("/proc/self/status", "r");
    char line[128];
    if (!f)
        return;
    while (fgets(line, sizeof line, f)) {
        if (!strncmp(line, "Origin: ", 8)) {
            line[strcspn(line, "\n")] = 0;
            printf("origin=%s\n", line + 8);
        }
    }
    fclose(f);
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        printf("usage: fakeplayer status|play|pause|volume N|title T|argv ...|hang\n");
        return 2;
    }
    load();
    if (!strcmp(argv[1], "status")) {
        printf("state=%s\ntitle=%s\nvolume=%d\nuid=%d\n", state, title,
               volume, (int)getuid());
        origin();
        return 0;
    }
    if (!strcmp(argv[1], "play") || !strcmp(argv[1], "pause")) {
        snprintf(state, sizeof state, "%s",
                 argv[1][1] == 'l' ? "playing" : "paused");
        if (save())
            return 1;
        printf("state=%s\n", state);
        return 0;
    }
    if (!strcmp(argv[1], "volume") && argc == 3) {
        int v = atoi(argv[2]);
        if (v < 0 || v > 100) {
            printf("volume out of range\n");
            return 3;
        }
        printf("old=%d\n", volume);
        volume = v;
        return save();
    }
    if (!strcmp(argv[1], "title") && argc == 3) {
        snprintf(title, sizeof title, "%s", argv[2]);
        return save();
    }
    if (!strcmp(argv[1], "argv")) {
        printf("argc=%d\n", argc);
        for (int i = 2; i < argc; i++)
            printf("arg%d=%s\n", i - 1, argv[i]);
        return 0;
    }
    if (!strcmp(argv[1], "hang")) {
        for (;;)
            sleep(1);
    }
    printf("unknown command %s\n", argv[1]);
    return 2;
}
