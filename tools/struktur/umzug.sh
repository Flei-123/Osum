#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/umzug.sh -- DER UMZUG, MECHANISCH.
#
# Diese Datei ist der Umzug der Runde STRUKTUR, als Skript und nicht als
# Erzaehlung. Sie steht im Repo, weil ein Umzug von siebzehn Dateien von
# Hand nicht nachpruefbar ist: wer wissen will, WAS verschoben wurde und
# WELCHE Zeile deshalb anders lautet, liest hier drei Tabellen statt
# einen Commit-Diff von tausend Zeilen.
#
# Sie ist EINMAL gelaufen. Ein zweiter Lauf findet die Dateien nicht mehr
# und sagt das (`git mv` scheitert), er richtet keinen Schaden an.
#
# ---------------------------------------------------------- WARUM ES GEHT
#
# Nachgelesen im Uebersetzer (`compiler/src/modules.rs` im Firn-Repo,
# Commit a751b3db), nicht geraten -- an zwei Stellen, und beide
# entscheiden diesen Umzug:
#
#   1. SUCHREIHENFOLGE eines `import` (modules.rs, Zeilen 100-110):
#        (1) neben der IMPORTIERENDEN Datei
#        (2) neben der WURZELDATEI  (hier: kernel/kmain.fi -> kernel/)
#        (3) Paketquellen, (4) needs, (5) $FIRNLIB, (6) <firnc>/../lib
#      Daraus folgt beides, was diesen Umzug billig macht:
#      * Eine verschobene Datei erreicht den KERN weiter mit `import
#        kstate` -- Regel (2) findet kernel/kstate.fi, egal wie tief sie
#        selbst liegt. KEINE Zeile in den Treibern aendert sich dafuer.
#      * Treiber DERSELBEN Klasse erreichen einander weiter mit `import
#        virtio` -- Regel (1), gleiches Verzeichnis.
#      Zu aendern ist genau eine Sorte Zeile: ein `import` von AUSSERHALB
#      der Klasse auf eine verschobene Datei.
#
#   2. MODULNAME = DATEINAME OHNE SUFFIX (modules.rs `module_name`,
#      package.rs `module_name`, dort mit Test:
#      `module_name("/a/b/geo.fi") == "geo"`). Der Pfad steht NICHT
#      darin. Daraus folgt zweierlei:
#      * Das Linkersymbol `_F0.virtio__tx_frame` bleibt Zeichen fuer
#        Zeichen dasselbe. Der Umzug ist im fertigen Abbild NICHT zu
#        sehen -- und genau das misst die Abnahme.
#      * Ein Modul wird unter dem LETZTEN Pfadteil angesprochen. Nach
#        `import drivers.blk.blk` heisst der Aufruf weiter `blk.read(..)`.
#        Die paar tausend AUFRUFSTELLEN bleiben unberuehrt; nur die
#        Importzeile aendert sich. Das ist der Grund, warum dieser Umzug
#        ueberhaupt in einer Runde machbar ist.
#
# EIN FALSCHER IMPORTPFAD IST EIN UEBERSETZUNGSFEHLER, kein stiller
# Fehler -- der Uebersetzer nennt die Datei, die er nicht findet. Das
# Risiko dieses Umzugs liegt deshalb NICHT im Quelltext, sondern in den
# Testlaeufern, die mit `grep` in Kerndateien lesen (Abschnitt 3 unten):
# ein `grep` auf einen Pfad, den es nicht mehr gibt, liefert die leere
# Zeichenkette und faellt nicht auf, sondern misst ab da etwas anderes.
set -euo pipefail
cd "$(dirname "$0")/../.."

# ============================================================ 1. DIE TAFEL
#
# Was Treiber ist und was Kern, in einer Tabelle. Die Regel dahinter ist
# eng und absichtlich eng: TREIBER IST, WAS MIT DEM GERAET REDET --
# Register, Portadressen, Ringe, Unterbrechungen. Alles andere bleibt
# liegen, auch wenn es "irgendwie zur Grafik gehoert".
#
# Deshalb geht `fb.fi` (der Rahmenpuffer, MMIO) nach drivers/gfx/, aber
# `wm.fi` (der Fensterserver) NICHT -- der kennt keine einzige
# Hardwareadresse, der kennt Fenster. Dasselbe fuer `ttf.fi` (ein
# Schriftrasterer), `tile.fi` (ein Fensterbaum) und `ansi.fi` (eine
# Terminalemulation). Waeren die mitgezogen, hiesse "drivers" nur noch
# "alles, was mit Bildschirm zu tun hat", und die Trennung, um die es
# geht, waere im ersten Schritt schon verwaessert.
KLASSEN="bus net blk usb input gfx"

bus_DATEIEN="pci acpi"        # der Bus selbst: hier entsteht jede Treiberwahl
net_DATEIEN="netdev virtio e1000"
blk_DATEIEN="blk nvme ahci"
usb_DATEIEN="usb xhci"
input_DATEIEN="kbd ps2m"
gfx_DATEIEN="gfx gfx-aus fb vmode font"

# ====================================================== 2. VERSCHIEBEN
echo "== 1. git mv =="
for k in $KLASSEN; do
    mkdir -p "kernel/drivers/$k"
    eval "dateien=\$${k}_DATEIEN"
    for d in $dateien; do
        [ -f "kernel/$d.fi" ] || { echo "  FEHLT: kernel/$d.fi" >&2; exit 1; }
        git mv "kernel/$d.fi" "kernel/drivers/$k/$d.fi"
        echo "  kernel/$d.fi -> kernel/drivers/$k/$d.fi"
    done
done

# ================================================== 3. DIE IMPORTZEILEN
#
# Fuer jede verschobene Datei D der Klasse K: `^import D$` wird
# `import drivers.K.D` -- AUSSER in Dateien, die selbst in
# kernel/drivers/K/ liegen (die finden D ueber Regel (1)).
#
# LC_ALL=C, weil `kernel/procfs.fi` Oktette enthaelt, die kein gueltiges
# UTF-8 sind (`file` sagt "data"). Ohne das bricht sed mit
# "invalid byte sequence" ab -- gefunden, nicht vermutet.
echo "== 2. Importzeilen =="
ALLE_FI=$(find kernel -name '*.fi' | sort)
for k in $KLASSEN; do
    eval "dateien=\$${k}_DATEIEN"
    for d in $dateien; do
        n=0
        for f in $ALLE_FI; do
            # Dateien der eigenen Klasse ueberspringen: Regel (1) traegt.
            [ "$(dirname "$f")" = "kernel/drivers/$k" ] && continue
            if LC_ALL=C grep -q "^import $d\$" "$f" 2>/dev/null; then
                LC_ALL=C sed -i "s|^import $d\$|import drivers.$k.$d|" "$f"
                n=$((n + 1))
            fi
        done
        if [ "$n" -gt 0 ]; then
            printf '  %-10s -> drivers.%s.%-8s in %2d Dateien\n' "$d" "$k" "$d" "$n"
        fi
    done
done

# ============================================== 4. DIE PFADE IN DEN LAEUFERN
#
# Der gefaehrliche Teil. `tools/gfx/run.sh` liest Konstanten mit `grep`
# aus `kernel/drivers/gfx/fb.fi`; zeigt der Pfad ins Leere, ist das Ergebnis leer und
# der Vergleich still falsch. Deshalb wird hier NICHT nur ersetzt,
# sondern hinterher gezaehlt (`tools/struktur/pruefe.sh`).
#
# Auch die Kommentarkoepfe der Quelldateien werden nachgezogen: ein
# Kommentar, der auf einen Pfad zeigt, den es nicht gibt, ist eine Luege
# mit langer Haltbarkeit.
#
# NICHT nachgezogen werden die RUNDENBERICHTE unter docs/ (ROUND*.md,
# RUNDE-*.md, *STATUS*.md, OSUM-K*.md und die Themenberichte einzelner
# Runden). Zwei Gruende, beide ernst gemeint:
#   * Ein Bericht der Runde K7 beschreibt, was DAMALS geschah, und damals
#     lag die Datei unter kernel/drivers/gfx/fb.fi. Einen abgeschlossenen Messbericht
#     nachtraeglich auf den heutigen Baum umzuschreiben ist keine Pflege,
#     das ist Geschichtsfaelschung -- und beim naechsten Widerspruch
#     glaubt niemand mehr, dass die Zahlen daneben echt sind.
#   * `docs/REALHW.md` wird GERADE von der Runde BLECH geaendert. Jede
#     Zeile, die diese Runde dort anfasst, ist ein Merge-Konflikt ohne
#     Gegenwert.
# Nachgezogen wird deshalb nur, was den HEUTIGEN Baum beschreibt:
# README.md und docs/ARCH.md.
ZIELE="tools/ test.sh kernel/ README.md docs/ARCH.md"
echo "== 3. Pfade in Laeufern, Kommentaren, README.md, docs/ARCH.md =="
for k in $KLASSEN; do
    eval "dateien=\$${k}_DATEIEN"
    for d in $dateien; do
        liste=$(LC_ALL=C grep -rl "kernel/$d\.fi" $ZIELE 2>/dev/null || true)
        n=$(printf '%s\n' "$liste" | grep -c . || true)
        if [ "$n" -gt 0 ]; then
            printf '%s\n' "$liste" | while read -r f; do
                [ -n "$f" ] || continue
                LC_ALL=C sed -i "s|kernel/$d\.fi|kernel/drivers/$k/$d.fi|g" "$f"
            done
            printf '  kernel/%-9s -> kernel/drivers/%s/%-9s in %2d Dateien\n' "$d.fi" "$k" "$d.fi" "$n"
        fi
    done
done

echo "== fertig =="
