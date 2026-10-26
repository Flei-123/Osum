/* SPDX-License-Identifier: GPL-2.0-only */
/* gtk4_hello.c -- GTK4 probe stone: one window with a button on the Wayland backend (cairo renderer), quits after a delay. */
#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>

static gboolean quit_cb(gpointer d) { puts("GTK4-QUIT"); g_application_quit(G_APPLICATION(d)); return G_SOURCE_REMOVE; }
static void activate(GtkApplication *app, gpointer u) {
    (void)u;
    puts("GTK4-ACTIVATE");
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), "Osum GTK4");
    gtk_window_set_default_size(GTK_WINDOW(win), 420, 220);
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_box_append(GTK_BOX(box), gtk_label_new("Hello from GTK4 on Osum"));
    gtk_box_append(GTK_BOX(box), gtk_button_new_with_label("Button"));
    gtk_window_set_child(GTK_WINDOW(win), box);
    gtk_window_present(GTK_WINDOW(win));
    puts("GTK4-PRESENT");
    g_timeout_add_seconds(getenv("GTK_HELLO_SECS") ? atoi(getenv("GTK_HELLO_SECS")) : 20, quit_cb, app);
}
int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("org.osum.hello", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int st = g_application_run(G_APPLICATION(app), argc, argv);
    printf("GTK4-EXIT %d\n", st);
    return st;
}
