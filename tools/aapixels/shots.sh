#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -u
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT=${1:?usage: shots.sh <outdir>}
mkdir -p "$OUT"
export DESIGNBUILD="$OUT/build"
export OSUM_RTC="base=2026-10-11T11:00:00,clock=vm"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit term sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
HEAVY=/root/jarvis/bin/heavy
$HEAVY bash tools/design/eh6.sh "$OUT/o0" res=1920x1080 accel=kvm nurbau=ja progs="$PROGS" > "$OUT/build.log" 2>&1 || { echo "build failed"; exit 1; }
run() { $HEAVY bash tools/design/eh6.sh "$OUT/$1" res=1920x1080 accel=kvm uiscale=$2 mode=$3 tafel=nein progs="$PROGS" drehbuch="$ROOT/tools/aapixels/scene.txt" > "$OUT/$1.log" 2>&1; }
run s1l 1 light & run s1d 1 dark & run s2l 2 light & run s2d 2 dark &
wait
for r in s1l s1d s2l s2d; do bash tools/aapixels/check.sh "$OUT/$r"; done
