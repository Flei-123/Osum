#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# pruef/zieh-ab.sh -- RUNDE ZIEH, DIE GEGENPROBE IN BILDERN UND ZAHLEN.
#
#   bash pruef/zieh-ab.sh <arbeitsbaum> <ausgabe> [lift] [tilt] [swing]
#
# Faehrt einen Schreibtisch hoch (tools/look/shot.sh, also mit Platte,
# Schriften und Sprachdateien -- ohne die faellt der Kern vor der
# Oberflaeche wieder heraus), laesst den Kern den Zug SELBST fuehren
# (`wmzieh`, kgui.fi `zieh_vorfuehrung`) und schiesst WAEHREND des
# Zuges vier Bilder statt eines am Ende.
#
# WARUM MEHRERE BILDER. Ein Foto vom Ende eines Zuges sieht aus wie
# eines ohne Zug. Die Wirkung, um die es geht, liegt mitten in der
# Bewegung: das Fenster ist groesser, es steht versetzt, und der
# angefasste Punkt liegt still.
#
# WARUM DER KERN DEN ZUG FAEHRT UND NICHT DIE MAUS. `pruef/
# ziehprobe.py` hat in vier Fassungen gemessen, dass der Kern die
# gedrueckte Taste waehrend einer Zeigerbewegung gar nicht sieht
# (`kl=0`) -- auf dem alten Abbild genauso wie auf dem neuen. Ein
# echter Zug ueber QEMU misst deshalb nichts. Die Vorfuehrung ruft
# genau die drei Stellen, die ein Zeiger riefe: `drag_begin`,
# `move_win`, `drag_end`.
#
# DIE ZAHLEN stehen am Ende in der Zeile `wm: vsync=...`:
#   lift= tilt= swing=   die drei Marken, wie sie im SERVER stehen
#   ziehpx=              Bildpunkte, die skaliert uebertragen wurden
#   swings=              Ticks, in denen sich der Nachzug geaendert hat
set -uo pipefail
BAUM=${1:?usage: zieh-ab.sh <arbeitsbaum> <ausgabe> [lift] [tilt] [swing]}
OUT=${2:?usage: zieh-ab.sh <arbeitsbaum> <ausgabe> [lift] [tilt] [swing]}
LIFT=${3:-}
TILT=${4:-}
SWING=${5:-}
cd "$BAUM"
mkdir -p "$OUT"

# DIE DREI MARKEN AUF DER BEFEHLSZEILE. Im Betrieb kommen sie aus der
# Formdatei ueber die Taskleiste (wlibc.form_push -> WM_FORM); dieser
# Lauf setzt sie direkt, damit die Messung eine Marke misst und nicht
# den Weg dorthin. Fehlt eine, bleibt sie, was der Server von sich aus
# tut -- also 0, der Weg vor dieser Runde.
MARKEN="wmzieh"
[ -n "$LIFT" ] && MARKEN="$MARKEN wmlift=$LIFT"
[ -n "$TILT" ] && MARKEN="$MARKEN wmtilt=$TILT"
[ -n "$SWING" ] && MARKEN="$MARKEN wmswing=$SWING"

# DER ABLAUF DER VORFUEHRUNG, in Ticks nach `wm: hold` (TICK_HZ=100):
#    50  anfassen (an der Stelle 40|20, also weit aus der Mitte)
#  60..100  ziehen, je Tick 9 nach rechts und 4 nach hoch
# 100..180  HAENGT NOCH, steht aber still  <- hier wird gemessen
#   180  loslassen, ab hier pendelt der Nachzug aus
#
# Die Schuesse liegen bei rund 0,45 / 0,80 / 1,15 / 1,60 / 2,10 s:
# einer vor dem Anfassen, einer im Zug, ZWEI am stehenden aber
# aufgehobenen Fenster (dort ist die Skalierung eindeutig messbar)
# und einer nach dem Absetzen.
export LOOKBUILD=${LOOKBUILD:-$OUT/build}
bash tools/look/shot.sh "$OUT/lauf" lang=de user=de accel=kvm \
    shape=osum scheme=day mode=light \
    extra="$MARKEN" shots="0.45 0.30 0.25 0.25 0.25" \
    > "$OUT/lauf.log" 2>&1

echo "== $BAUM  lift=${LIFT:-0} tilt=${TILT:-0} swing=${SWING:-0} =="
grep -ao 'wm: vsync=.*' "$OUT/lauf.log" | tail -1
# Die zwei Marken des Zuges. Steht "losgelassen" VOR dem letzten
# Schuss, lag der Schuss nicht mehr am Haken -- dann misst er die Ruhe
# und nicht das Aufheben.
grep -ao "ziehbild: .*" "$OUT/lauf/serial.txt" 2>/dev/null | tail -1 | tr "\\n" " "; echo
grep -ao 'bildzeit: .*' "$OUT/lauf/serial.txt" 2>/dev/null | tail -1
ls "$OUT/lauf"/schuss-*.png 2>/dev/null
rm -f "$OUT/lauf/disk.img"
