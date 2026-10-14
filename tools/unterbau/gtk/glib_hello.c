/* SPDX-License-Identifier: GPL-2.0-only */
/* glib_hello.c -- GLib/GIO probe stone: main loop, timeouts, threads, pipe watch, UNIX signal source, file monitor, spawn. */
#include <glib.h>
#include <glib-unix.h>
#include <gio/gio.h>
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <sys/socket.h>

static GMainLoop *loop;
static int ticks, got_pipe, got_sig, got_thread, got_mon;
static gboolean on_tick(gpointer d) { (void)d; ticks++; if (ticks == 3) { raise(SIGUSR1); } return ticks < 6; }
static gboolean on_done(gpointer d) { (void)d; g_main_loop_quit(loop); return G_SOURCE_REMOVE; }
static gboolean on_sig(gpointer d) { (void)d; got_sig = 1; puts("GLIB-SIGNAL"); return G_SOURCE_REMOVE; }
static gboolean on_pipe(GIOChannel *c, GIOCondition cond, gpointer d) {
    gchar buf[16]; gsize n = 0; (void)cond; (void)d;
    if (g_io_channel_read_chars(c, buf, sizeof buf, &n, NULL) == G_IO_STATUS_NORMAL && n) { got_pipe = 1; puts("GLIB-PIPE"); }
    return G_SOURCE_REMOVE;
}
static gpointer worker(gpointer d) { int fd = GPOINTER_TO_INT(d); g_usleep(100000); got_thread = 1; if (write(fd, "x", 1) != 1) {} return NULL; }
static void on_mon(GFileMonitor *m, GFile *f, GFile *o, GFileMonitorEvent e, gpointer d) { (void)m; (void)f; (void)o; (void)e; (void)d; got_mon = 1; puts("GLIB-MONITOR"); }

int main(void) {
    int pfd[2], sp[2];
    loop = g_main_loop_new(NULL, FALSE);
    puts("GLIB-START");
    if (!g_unix_open_pipe(pfd, FD_CLOEXEC, NULL)) { puts("GLIB-FAIL pipe"); return 1; }
    GIOChannel *ch = g_io_channel_unix_new(pfd[0]);
    g_io_add_watch(ch, G_IO_IN, on_pipe, NULL);
    g_unix_signal_add(SIGUSR1, on_sig, NULL);
    g_timeout_add(100, on_tick, NULL);
    GThread *t = g_thread_new("w", worker, GINT_TO_POINTER(pfd[1]));
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, sp) == 0) { puts("GLIB-DGRAMPAIR"); close(sp[0]); close(sp[1]); } else { puts("GLIB-NODGRAMPAIR"); }
    GFile *tmp = g_file_new_for_path("/tmp");
    GError *err = NULL;
    GFileMonitor *mon = g_file_monitor_directory(tmp, G_FILE_MONITOR_NONE, NULL, &err);
    if (mon) { g_signal_connect(mon, "changed", G_CALLBACK(on_mon), NULL); puts("GLIB-MONITOR-ON"); } else { printf("GLIB-NOMONITOR %s\n", err ? err->message : "?"); g_clear_error(&err); }
    FILE *f = fopen("/tmp/glib-mon.txt", "w"); if (f) { fputs("x\n", f); fclose(f); }
    gchar *out = NULL; gint st = 0;
    if (g_spawn_command_line_sync("/bin/busybox echo spawnok", &out, NULL, &st, &err) && out) { printf("GLIB-SPAWN %s", out); } else { printf("GLIB-NOSPAWN %s\n", err ? err->message : "?"); g_clear_error(&err); }
    g_free(out);
    gchar *data = NULL; gsize len = 0;
    if (g_file_get_contents("/etc/hosts", &data, &len, NULL)) printf("GLIB-FILE %zu\n", len);
    g_free(data);
    g_timeout_add(1500, on_done, NULL);
    g_main_loop_run(loop);
    g_thread_join(t);
    printf("GLIB-RESULT ticks=%d pipe=%d sig=%d thread=%d mon=%d\n", ticks, got_pipe, got_sig, got_thread, got_mon);
    puts("GLIB-DONE");
    return 0;
}
