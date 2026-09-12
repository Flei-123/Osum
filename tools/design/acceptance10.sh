#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/acceptance10.sh -- DIE ABNAHME DER RUNDE MERGE-10.
#
#   bash tools/design/acceptance10.sh <ausgabeverzeichnis>
#
# ACHT ANSICHTEN, ZWEI AUFLOESUNGEN, ZWEI MODI. Und jede Ansicht wird
# WIRKLICH aufgemacht.
#
# WARUM DIESES SKRIPT UEBERHAUPT EXISTIERT, obwohl es
# `tools/design/capture.sh` schon gibt: der PROGRAMM-AUDIT vom
# 09.09.2026 hat gezaehlt, dass bei 1280x800 zuletzt SECHS von acht
# Bildern eines Laufs Oktett-gleich waren -- Explorer, Dialog,
# Kontrollzentrum und Einstellungen gingen nie auf, und 15 von 22
# Programmen sind in keinem einzigen Beleg je zu sehen gewesen. Ein
# Bild, das denselben Schreibtisch zeigt wie das davor, ist kein Beleg
# fuer ein Programm; es ist ein Beleg dafuer, dass der Klick daneben
# ging.
#
# DIE ANTWORT DARAUF IST NICHT "besser klicken", SONDERN JE PROGRAMM
# EINE EIGENE MASCHINE: `wigapp=/bin/<prog>` startet genau dieses
# Programm im Fensterserver. Damit haengt das Bild nicht mehr an einer
# Klickfolge, die bei jeder Aufloesung andere Koordinaten hat --
# entweder das Programm kommt hoch (dann ist es im Bild) oder es kommt
# nicht hoch (dann steht das in der Tafel und ist ein BEFUND, kein
# stilles gleiches Bild).
#
# Je Bild wird geschrieben:
#   * die PPM-Aufnahme
#   * die serielle Leitung des Laufs
#   * der gemessene Blaustich (B-R, flaechengewichtet)
#   * ob das Fenster des Programms wirklich da war
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

OUT=${1:?usage: acceptance10.sh <outdir>}
mkdir -p "$OUT"

# Die acht Ansichten. Vier davon sind eigene Programme und bekommen je
# eine eigene Maschine; "schreibtisch", "startmenue" und
# "taskleiste-nah" kommen aus dem Drehbuch-Lauf, weil sie NUR im
# Zusammenspiel entstehen (eine Leiste ohne Schreibtisch ist keine).
# Die Programme, die je eine eigene Maschine bekommen. `explorer` ist
# zweimal da: einmal fuer sein Fenster und einmal (mit `dlg`) fuer den
# Strg+N-Dialog -- in einer Maschine, in der KEIN Startmenue offen ist
# und ihm die Taste wegnimmt.
EIGEN="settings explorer sh dispctl"

blau() { python3 "$ROOT/tools/design/blaustich.py" "$1" 2>/dev/null; }

# `uiscale=2` GEHOERT ZU 2560x1440 UND IST KEIN SCHMUCK.
#
# Justins Schirm meldet ueber EDID die Vervielfachung 2; QEMU liefert
# kein EDID, also stand im Emulator immer 1 -- und genau deshalb war
# KEINER der Fehler, die nur bei Vervielfachung 2 auftreten
# (uebereinanderstehende Spaltenkoepfe, abgeschnittene Beschriftungen),
# je im Emulator zu sehen, obwohl sie seit Wochen im Baum lagen.
# `uiscale=<n>` auf der Kommandozeile schlaegt das EDID (kgui.fi).
lauf() {
    # lauf <name> <res> <mode> <extra...>
    local name=$1 res=$2 mode=$3; shift 3
    local d="$OUT/$mode-$res-$name"
    rm -rf "$d"; mkdir -p "$d"
    local ds="" sc=""
    [ "$mode" = dark ] && ds="dark_scheme=midnight"
    [ "$res" = 2560x1440 ] && sc="uiscale=2"
    # `extra=` kann schon von aussen kommen (wigapp=...); beides muss in
    # EIN `extra=` gehen, sonst gewinnt das letzte.
    local ex="$sc"
    local rest=()
    local a
    for a in "$@"; do
        case "$a" in
            extra=*) ex="$ex ${a#extra=}" ;;
            *) rest+=("$a") ;;
        esac
    done
    bash tools/design/capture.sh "$d" \
        scheme=day $ds mode="$mode" res="$res" lang=en \
        extra="$ex" ${rest[@]+"${rest[@]}"} \
        > "$d/bau.log" 2>&1
    echo $? > "$d/rc"
}

echo "== MERGE-10, Abnahme: 2 Aufloesungen x 2 Modi =="
for res in 1280x800 2560x1440; do
  for mode in light dark; do
    echo "-- $res $mode --"
    # 1. der Durchklick-Lauf: Schreibtisch, Startmenue, Explorer,
    #    Dialog, Kontrollzentrum, Einstellungen
    lauf durchklick "$res" "$mode"
    # 2. je Programm eine eigene Maschine
    for p in $EIGEN; do
        lauf "$p" "$res" "$mode" extra="wigapp=/bin/$p" \
            drehbuch=tools/design/einzeln.txt
    done
    # 3. DER DATEIDIALOG, und warum er eine eigene Maschine braucht.
    #
    # Im Durchklick-Lauf startet der Dateimanager AUS DEM STARTMENUE,
    # und der Starter holt sich danach den Eingabefokus zurueck (er
    # liegt auf L_TOP und laeuft nach dem Start noch seine Bewegung
    # zu Ende -- `wlib: anim ... dur=12`). Strg+N landet dann bei IHM
    # und nicht beim Dateimanager; gemessen als `wm: fokus id=11
    # vor=14` unmittelbar vor der Taste, und das ist der Grund, warum
    # `04-dialog` seit Runden Oktett fuer Oktett `03-explorer` war
    # (OFFEN.md G-003).
    #
    # `wigapp=/bin/explorer` startet den Dateimanager als EINZIGES
    # Fenster -- kein Startmenue, kein Fokusdieb. Was hier gemessen
    # wird, ist damit wirklich der Dialog und nicht die Klickfolge.
    lauf dialog "$res" "$mode" extra="wigapp=/bin/explorer" \
        drehbuch=tools/design/dlg.txt
  done
done
echo "== fertig, Bilder unter $OUT =="
