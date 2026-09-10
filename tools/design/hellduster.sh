#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/hellduster.sh -- ZIEHT DER DUNKLE MODUS UEBERALL MIT?
#
#   bash tools/design/hellduster.sh [kern.mb] [wurzel.img] [ausgabe]
#
# Justins Frage: "aendert der dunkle Modus auch die Farbe des
# Suchfensters?" Die Antwort darf keine Meinung sein. Dieser Laeufer
# faehrt DIESELBE Ansichtsfolge zweimal -- einmal mode=light, einmal
# mode=dark -- und legt beide Abzuege nebeneinander. Gemessen wird
# danach mit tools/design/dunkelmess.py: mittlere Helligkeit je
# Flaeche. Bleibt eine Flaeche in beiden Laeufen gleich hell, ist sie
# NICHT umgestellt.
#
# Aufgenommen werden: Schreibtisch, Suchfenster (zu und getippt),
# Kontrollzentrum, Einstellungsfenster, Taskleiste.
# Alles in 3440x1440.
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/final-img/osum.mb}
WURZEL=${2:-/tmp/final-img/root.img}
AUS=${3:-/tmp/hellduster}
rm -rf "$AUS"; mkdir -p "$AUS"

lauf() {
    local modus=$1
    local W="$AUS/$modus"
    mkdir -p "$W"
    cp "$WURZEL" "$W/disk.img"
    # /etc/theme.conf im Abbild auf den gewuenschten Modus stellen
    python3 tools/osum/mkfs.py cat "$W/disk.img" /etc/theme.conf \
        > "$W/theme.conf" 2>/dev/null || true
    sed -i "s/^mode=.*/mode=$modus/" "$W/theme.conf"
    python3 tools/osum/mkfs.py put "$W/disk.img" /etc/theme.conf \
        "$W/theme.conf" >/dev/null 2>&1 || echo "   (theme.conf nicht ersetzt)"

    cat > "$W/drehbuch.txt" <<'DREH'
warteauf launcher: ready || 120
warte 6
foto 10-schreibtisch
taste meta_l
warte 3
foto 11-suchfenster
taste s
taste e
taste t
warte 3
foto 12-suchfenster-getippt
taste esc
warte 2
klickauf netz
warte 4
foto 13-kontrollzentrum
taste esc
warte 2
foto 14-taskleiste
DREH

    qemu-system-x86_64 -kernel "$KERN" -m 2048 \
      -append "osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer herz absturzhalt nopuls tz=120 lang=en usb hidgen modfs nosched noproc nofs" \
      -serial "file:$W/serial.txt" -display none -no-reboot \
      -device "VGA,edid=on,xres=3440,yres=1440,vgamem_mb=128" \
      -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
      -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
    local QP=$!
    sleep 3
    python3 tools/design/fahren.py "$W/mon" "$W/serial.txt" "$W" \
        "$W/drehbuch.txt" > "$W/fahren.log" 2>&1 || true
    kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null
    echo "== $modus =="
    grep -a 'theme\|scheme\|mode' "$W/serial.txt" | head -4 | sed 's/^/   /'
    ls "$W"/*.ppm 2>/dev/null | wc -l | sed 's/^/   Abzuege: /'
}

lauf light
lauf dark
echo
echo "Abzuege in $AUS/{light,dark}/"
