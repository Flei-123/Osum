#!/usr/bin/env bash
#
#   bash tools/design/acceptance10.sh <ausgabeverzeichnis>
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

OUT=${1:?usage: acceptance10.sh <outdir>}
mkdir -p "$OUT"

EIGEN="settings explorer sh dispctl"

blau() { python3 "$ROOT/tools/design/blaustich.py" "$1" 2>/dev/null; }

lauf() {
    # lauf <name> <res> <mode> <extra...>
    local name=$1 res=$2 mode=$3; shift 3
    local d="$OUT/$mode-$res-$name"
    rm -rf "$d"; mkdir -p "$d"
    local ds="" sc=""
    [ "$mode" = dark ] && ds="dark_scheme=midnight"
    [ "$res" = 2560x1440 ] && sc="uiscale=2"
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
    #
    lauf dialog "$res" "$mode" extra="wigapp=/bin/explorer" \
        drehbuch=tools/design/dlg.txt
  done
done
echo "== fertig, Bilder unter $OUT =="
