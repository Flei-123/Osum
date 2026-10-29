#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has()  { grep -qaE "$2" "$1" && ok "$3" || bad "$3 -- /$2/ missing"; }
look() { local name=$1; shift; local out rc
    out=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($out)"; else bad "$name -- $out"; fi; }
lookno() { local name=$1; shift; local out rc
    out=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name ($out)"; else bad "$name -- passed: $out"; fi; }

VGA_STD=${VGA_STD:-"-vga std -global VGA.edid=off"}
BASE="gfx fbres=1920x1080 nocursor fbtest fbcanon fbhold nokbd nosched noproc nofs noring3"

echo "== 1. build =="
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/k0.log" 2>&1 || { bad "kernel build"; tail -8 "$TMPD/k0.log"; echo "FBFMT: $pass ok, $fail failed"; exit 1; }
ok "kernel built"

RC=0
shot() {
    local name=$1 line=$2
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$out" "$ppm" "$sock"
    timeout 200 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 -append "$line" \
        -serial "file:$out" -display none -no-reboot $VGA_STD \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1500 ]; do
        grep -qa '^fb: hold' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1; i=$((i + 1))
    done
    sleep 0.4
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"; RC=$?
    rm -f "$sock"
}

fields_ok() {
    look "$1: red field" flaeche "$2" 0 0 100 100 255 0 0
    look "$1: green field" flaeche "$2" 100 0 100 100 0 255 0
    look "$1: blue field" flaeche "$2" 200 0 100 100 0 0 255
    look "$1: white field" flaeche "$2" 300 0 100 100 255 255 255
    look "$1: canonical red literal" flaeche "$2" 500 0 100 100 255 0 0
    look "$1: canonical green literal" flaeche "$2" 600 0 100 100 0 255 0
    look "$1: canonical blue literal" flaeche "$2" 700 0 100 100 0 0 255
    look "$1: canonical mixed literal" flaeche "$2" 800 0 100 100 16 32 48
}

echo "== 2. 1920x1080, pitch == width*4 =="
shot plain "$BASE"
has "$TMPD/plain.txt" "fb: 1920x1080x32 +pitch=7680" "plain: pitch 7680"
has "$TMPD/plain.txt" "fb: order panel=1 +swz=0" "plain: BGRX panel, no conversion"
look "plain: shot is 1920x1080" size "$TMPD/plain.ppm" 1920 1080
fields_ok plain "$TMPD/plain.ppm"

echo "== 3. 1920x1080, pitch 8192 (card stride wider than the picture) =="
shot wide "$BASE fbvirt=2048"
has "$TMPD/wide.txt" "fb: 1920x1080x32 +pitch=8192" "wide: kernel measured pitch 8192"
look "wide: shot is 1920x1080" size "$TMPD/wide.ppm" 1920 1080
fields_ok wide "$TMPD/wide.ppm"

echo "== 4. counter-proof: kernel assumes pitch = width*4 on the wide card =="
shot widebad "$BASE fbvirt=2048 fbnopitch"
has "$TMPD/widebad.txt" "fb: 1920x1080x32 +pitch=7680" "widebad: kernel really used 7680"
lookno "widebad: red field is torn" area "$TMPD/widebad.ppm" 0 0 100 100 255 0 0

echo "== 5. RGBX panel (R at byte 0): canonical colours are converted =="
shot rgbx "$BASE fbrgb"
has "$TMPD/rgbx.txt" "fb: order panel=2 +swz=1" "rgbx: panel order 2, conversion on"
look "rgbx: red literal lands in byte 0 (card reads blue)" area "$TMPD/rgbx.ppm" 500 0 100 100 0 0 255
look "rgbx: blue literal lands in byte 2 (card reads red)" area "$TMPD/rgbx.ppm" 700 0 100 100 255 0 0
look "rgbx: green literal unchanged" area "$TMPD/rgbx.ppm" 600 0 100 100 0 255 0
look "rgbx: mixed literal swapped" area "$TMPD/rgbx.ppm" 800 0 100 100 48 32 16
look "rgbx: console field follows the same order" area "$TMPD/rgbx.ppm" 0 0 100 100 0 0 255

echo "== 6. counter-proof: RGBX panel without conversion =="
shot rgbxraw "$BASE fbrgb fbnoswz"
has "$TMPD/rgbxraw.txt" "fb: order panel=2 +swz=0" "rgbxraw: conversion off"
look "rgbxraw: literal red stays in byte 2 (wrong on a real RGBX panel)" area "$TMPD/rgbxraw.ppm" 500 0 100 100 255 0 0

echo "== 7. RGBX with wide pitch together =="
shot both "$BASE fbrgb fbvirt=2048"
has "$TMPD/both.txt" "fb: 1920x1080x32 +pitch=8192" "both: pitch 8192"
look "both: red literal converted" area "$TMPD/both.ppm" 500 0 100 100 0 0 255
look "both: mixed literal converted" area "$TMPD/both.ppm" 800 0 100 100 48 32 16

echo "FBFMT: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
