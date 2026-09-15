#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# tools/theme/shots.sh -- DIE SIEBEN BILDSCHIRME, UND SIE BLEIBEN LIEGEN.
#
# `tests/theme/run.sh` baut dieselben Bilder, wirft sie aber am Ende weg
# (`trap 'rm -rf "$TMPD"' EXIT`). Fuer A-023 musste man sie ANSEHEN und
# nicht nur die Prozentzahlen lesen -- also dasselbe noch einmal, mit
# einem Verzeichnis, das stehen bleibt.
#
#   bash tools/theme/shots.sh AUSGABEVERZEICHNIS
#
# Erzeugt je Schema ein .ppm, ein .png daneben und eine Zeile mit den
# fuenf haeufigsten Farben.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

OUT=${1:?Ausgabeverzeichnis fehlt}
mkdir -p "$OUT"
TMPD="$OUT/bau"
mkdir -p "$TMPD"

if [ ! -f "$TMPD/k.mb" ]; then
    echo "== bauen (einmalig, dauert)"
    bash tests/theme/build.sh "$TMPD" > "$TMPD/build.log" 2>&1 || {
        echo "build.sh fehlgeschlagen"; tail -20 "$TMPD/build.log"; exit 1; }
fi

foto() { # name abbild kommandozeile [marke]
    local name=$1 img=$2 zeile=$3 marke=${4:-"wm: hold"}
    local sock="$TMPD/s-$name.sock"
    rm -f "$sock" "$OUT/$name.ppm" "$TMPD/$name.txt"
    cp -f "$img" "$TMPD/l-$name.img"
    timeout 400 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$zeile" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/l-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 2000 ]; do
        grep -qaF "$marke" "$TMPD/$name.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    python3 tools/gfx/screenshot.py "$sock" "$OUT/$name.ppm" 25 >/dev/null 2>&1
    wait "$pid"
    rm -f "$sock"
}

shot() { # name schema modus akzent
    local name=$1 sch=$2 mod=$3 akz=$4
    bash tests/theme/image.sh "$TMPD" "$sch" "$mod" "$akz" \
        "$TMPD/img-$name.img" > /dev/null 2>&1 || {
        echo "$name: Abbild fehlgeschlagen"; return; }
    foto "shot-$name" "$TMPD/img-$name.img" \
        "gfx wm wmhold desk einst themeshot nokbd nosched noproc nofs" \
        "themetest: gui ready"
    local surf
    surf=$(python3 tools/theme/model.py semantic "assets/schemes/$sch.scheme" \
        "$mod" ${akz:+"$akz"} | awk '$2 == "surface" {print $3}')
    printf '%-9s surface=#%s  top5: %s\n' "$name" "$surf" \
        "$(python3 tests/theme/pixel.py "$OUT/shot-$name.ppm" --top 5 2>/dev/null)"
}

shot light    day      light ""
shot dark     day      dark  ""
shot green    day      light 22c55e
shot violet   day      light 7c3aed
shot gold     paper    light a16207
shot contrast contrast light ""
shot midnight midnight dark  ""
