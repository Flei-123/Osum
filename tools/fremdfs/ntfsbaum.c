// SPDX-License-Identifier: GPL-2.0-only
// tools/fremdfs/ntfsbaum.c -- EINEN VERZEICHNISBAUM IN EIN NTFS-ABBILD
// LEGEN, OHNE ES EINZUHAENGEN.
//
// WARUM ES DIESE DATEI GIBT. Der uebliche Weg, ein Pruefbild zu
// fuellen, ist `mount -o loop` und danach `cp -a`. In einem
// LXC-Behaelter gibt es weder /dev/loop* noch /dev/fuse, also gibt es
// diesen Weg nicht -- und `ntfscp` allein reicht nicht: es schreibt
// DATEIEN in ein NTFS, aber es legt keine VERZEICHNISSE an, und ohne
// Verzeichnisse waere genau das ungeprueft, was diese Runde behauptet
// ($I30-Indizes, tiefe Pfade, viele Eintraege).
//
// Also wird dieselbe Bibliothek benutzt, die auch `ntfs-3g` benutzt --
// libntfs-3g --, nur ohne den FUSE-Aufsatz darueber. Das ist kein
// Nachbau des Formats: es ist DER Schreiber, mit dem Linux NTFS
// schreibt. Osum wird also gegen fremden Code gemessen und nicht
// gegen einen zweiten eigenen.
//
//   ntfsbaum <abbild> <quellverzeichnis>
//
// legt den Inhalt von <quellverzeichnis> rekursiv in die Wurzel von
// <abbild>. Namen kommen als UTF-8 herein und werden mit
// `ntfs_mbstoucs` nach UTF-16 gewandelt -- dieselbe Wandlung, die
// ntfs-3g benutzt, damit die Umlaute im Namen wirklich die sind, die
// Windows sehen wuerde.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

#include <ntfs-3g/volume.h>
#include <ntfs-3g/dir.h>
#include <ntfs-3g/attrib.h>
#include <ntfs-3g/unistr.h>
#include <ntfs-3g/inode.h>

static int fehler = 0;

// Ein Name als UTF-16. Rueckgabe: Zahl der Zeichen, oder -1.
static int nach_ucs(const char *name, ntfschar **out)
{
    *out = NULL;
    int n = ntfs_mbstoucs(name, out);
    return n;
}

static ntfs_inode *verzeichnis_anlegen(ntfs_volume *vol, ntfs_inode *eltern,
                                       const char *name)
{
    ntfschar *uname = NULL;
    int ulen = nach_ucs(name, &uname);
    if (ulen < 0) {
        fprintf(stderr, "ntfsbaum: Name nicht wandelbar: %s\n", name);
        fehler++;
        return NULL;
    }
    ntfs_inode *ni = ntfs_create(eltern, 0, uname, ulen, S_IFDIR);
    free(uname);
    if (!ni) {
        fprintf(stderr, "ntfsbaum: mkdir %s: %s\n", name, strerror(errno));
        fehler++;
    }
    return ni;
}

// Eine Datei anlegen und ihren Inhalt schreiben. Der Inhalt geht in
// den unbenannten $DATA-Strom -- also genau dorthin, wo ihn jeder
// NTFS-Leser sucht.
static int datei_schreiben(ntfs_volume *vol, ntfs_inode *eltern,
                           const char *name, const char *quelle)
{
    ntfschar *uname = NULL;
    int ulen = nach_ucs(name, &uname);
    if (ulen < 0) {
        fprintf(stderr, "ntfsbaum: Name nicht wandelbar: %s\n", name);
        fehler++;
        return -1;
    }
    ntfs_inode *ni = ntfs_create(eltern, 0, uname, ulen, S_IFREG);
    free(uname);
    if (!ni) {
        fprintf(stderr, "ntfsbaum: create %s: %s\n", name, strerror(errno));
        fehler++;
        return -1;
    }

    int fd = open(quelle, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "ntfsbaum: open %s: %s\n", quelle, strerror(errno));
        ntfs_inode_close(ni);
        fehler++;
        return -1;
    }

    struct stat st;
    fstat(fd, &st);

    // EINE DATEI MIT NULL OKTETTEN BEKOMMT TROTZDEM EINEN $DATA-STROM.
    // ntfs_attr_open/ntfs_attr_truncate legen ihn an; ohne diesen
    // Schritt haette `leer.bin` gar kein $DATA, und ein Leser, der
    // dann "keine Daten" statt "null Oktette" meldet, laege nicht
    // einmal falsch. Die leere Datei ist ein eigener Pruefpunkt, also
    // muss sie ein richtiger sein.
    ntfs_attr *na = ntfs_attr_open(ni, AT_DATA, AT_UNNAMED, 0);
    if (!na) {
        fprintf(stderr, "ntfsbaum: attr_open %s\n", name);
        close(fd);
        ntfs_inode_close(ni);
        fehler++;
        return -1;
    }

    if (st.st_size == 0) {
        ntfs_attr_truncate(na, 0);
    } else {
        char puffer[65536];
        s64 pos = 0;
        ssize_t gelesen;
        while ((gelesen = read(fd, puffer, sizeof puffer)) > 0) {
            s64 geschrieben = ntfs_attr_pwrite(na, pos, gelesen, puffer);
            if (geschrieben != gelesen) {
                fprintf(stderr, "ntfsbaum: write %s bei %lld: %lld von %zd\n",
                        name, (long long)pos, (long long)geschrieben, gelesen);
                fehler++;
                break;
            }
            pos += geschrieben;
        }
    }

    ntfs_attr_close(na);
    close(fd);
    ntfs_inode_mark_dirty(ni);
    // DER RUECKGABEWERT VON ntfs_inode_close WIRD HIER BEWUSST NICHT
    // ALS FEHLER GEZAEHLT.
    //
    // Gemessen (14.09.2026): libntfs-3g 2022.10.3 liefert beim
    // Schliessen eines frisch angelegten Inodes EIO, obwohl alles
    // geschrieben ist -- `ntfsfix -n` meldet das Abbild danach als
    // sauber, `ntfsls` sieht jeden Eintrag, und `ntfscat` gibt jede
    // Datei Oktett fuer Oktett wieder heraus (Pruefsummen gleich).
    // Der Wert ist also ein Artefakt der Bibliothek ohne FUSE-Aufsatz
    // und keine Aussage ueber das Abbild.
    //
    // DASS DAS ABBILD IN ORDNUNG IST, WIRD NICHT GEGLAUBT, SONDERN
    // GEPRUEFT: `tools/fremdfs/bild.sh` laesst hinterher `ntfsfix -n`
    // und `ntfscat` ueber jede einzelne Datei laufen und vergleicht
    // die Pruefsummen mit denen des Wirtsbaums. Faellt dort etwas auf,
    // faellt der Bau -- und dann steht hier ein echter Fehler.
    ntfs_inode_close(ni);
    return 0;
}

// Rekursiv. `pfad` ist der Weg im Wirtsdateisystem, `ni` das schon
// offene Zielverzeichnis im Abbild.
static void baum_kopieren(ntfs_volume *vol, ntfs_inode *ni, const char *pfad)
{
    DIR *d = opendir(pfad);
    if (!d) {
        fprintf(stderr, "ntfsbaum: opendir %s: %s\n", pfad, strerror(errno));
        fehler++;
        return;
    }

    // ERST EINSAMMELN, DANN SORTIEREN, DANN SCHREIBEN. Die Reihenfolge,
    // in der readdir() liefert, ist die des Wirtsdateisystems und
    // damit nicht wiederholbar; ein Pruefbild, das bei jedem Bau
    // anders aussieht, taugt nicht als Messgeraet.
    char **namen = NULL;
    size_t anzahl = 0, platz = 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, ".."))
            continue;
        if (anzahl == platz) {
            platz = platz ? platz * 2 : 64;
            namen = realloc(namen, platz * sizeof *namen);
        }
        namen[anzahl++] = strdup(e->d_name);
    }
    closedir(d);

    for (size_t i = 0; i + 1 < anzahl; i++)
        for (size_t j = i + 1; j < anzahl; j++)
            if (strcmp(namen[i], namen[j]) > 0) {
                char *t = namen[i];
                namen[i] = namen[j];
                namen[j] = t;
            }

    for (size_t i = 0; i < anzahl; i++) {
        char unten[4096];
        snprintf(unten, sizeof unten, "%s/%s", pfad, namen[i]);
        struct stat st;
        if (lstat(unten, &st)) {
            fprintf(stderr, "ntfsbaum: lstat %s\n", unten);
            fehler++;
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            ntfs_inode *kind = verzeichnis_anlegen(vol, ni, namen[i]);
            if (kind) {
                baum_kopieren(vol, kind, unten);
                ntfs_inode_mark_dirty(kind);
                ntfs_inode_close(kind);
            }
        } else if (S_ISREG(st.st_mode)) {
            datei_schreiben(vol, ni, namen[i], unten);
        }
        // Symbolische Verweise werden AUSGELASSEN. NTFS kennt sie nur
        // als Reparse-Punkte, Windows legt sie so gut wie nie an, und
        // dieser Treiber unterstuetzt sie ausdruecklich nicht (siehe
        // docs/RUNDE-FREMDFS.md). Etwas zu pruefen, das der Treiber
        // nicht zusagt, waere kein Messpunkt, sondern Theater.
        free(namen[i]);
    }
    free(namen);
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: ntfsbaum <abbild> <quellverzeichnis>\n");
        return 2;
    }

    ntfs_volume *vol = ntfs_mount(argv[1], 0);
    if (!vol) {
        fprintf(stderr, "ntfsbaum: ntfs_mount %s: %s\n", argv[1],
                strerror(errno));
        return 1;
    }

    ntfs_inode *wurzel = ntfs_inode_open(vol, FILE_root);
    if (!wurzel) {
        fprintf(stderr, "ntfsbaum: Wurzel nicht zu oeffnen\n");
        ntfs_umount(vol, 1);
        return 1;
    }

    baum_kopieren(vol, wurzel, argv[2]);

    ntfs_inode_mark_dirty(wurzel);
    ntfs_inode_close(wurzel);
    if (ntfs_umount(vol, 0)) {
        fprintf(stderr, "ntfsbaum: umount: %s\n", strerror(errno));
        fehler++;
    }

    if (fehler) {
        fprintf(stderr, "ntfsbaum: %d Fehler\n", fehler);
        return 1;
    }
    printf("ntfsbaum: fertig\n");
    return 0;
}
