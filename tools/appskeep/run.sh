#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/appskeep/run.sh -- an opk install/remove must not wipe the bundles the image ships (SYSTEM marker).
# Image without a generation: install libx, then /apps must still list settings, explorer and libx.
# COUNTER-PROOF: run with the pre-fix kernel/user/opk.fi (git stash); the "image bundles survive" checks must be red.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
KEEP=${1:-}
OUT=${OUT:-$(mktemp -d /tmp/appskeep-run.XXXXXX)}
export OUT
[ "$KEEP" = "--keep" ] || trap 'rm -rf "$OUT"' EXIT
OPK=${OPK:-$(python3 tools/lib/opkpfad.py)}
export OPK

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
hat() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hatnicht() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present but must not be" || ok "$3"; }

lauf() { # name script [limit]
    OUT="$OUT" bash tools/install/oneshot.sh "$1" platte "$2" "${3:-600}" \
        > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

echo "== 1. build =="
bash tools/install/pakete.sh "$OUT" > "$OUT/pak.log" 2>&1 \
    && ok "base packages + key built" || { cat "$OUT/pak.log"; bad "install/pakete.sh"; }
mkdir -p "$OUT/dsrc" "$OUT/rez"
rm -f "$OUT/dsrc"/*
mkrez() { # name deps
    {
        echo "name=$1"
        echo "fassung=1.0.0"
        echo "titel=$1"
        echo "info=dependency probe"
        echo "keys=$1,probe"
        echo "handle=konsole"
        [ -n "$2" ] && echo "deps=$2"
        echo "datei=start $OUT/h1.elf"
    } > "$OUT/rez/$1.rezept"
    python3 "$OPK" bauen "$OUT/rez/$1.rezept" -o "$OUT/dsrc/$1-1.opk"
}
mkrez libx "" && ok "package built" || bad "mkrez"
python3 "$OPK" quelle "$OUT/dsrc" --schluessel "$OUT/geheim.key" > "$OUT/dsrc.log" 2>&1 \
    && python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT/dsrc"/*.opk > /dev/null \
    && ok "source /dsrc signed" || { cat "$OUT/dsrc.log"; bad "source signing"; }

printf 'name=keep\ninfo=image bundle probe\nkeys=keep\n' > "$OUT/keepinfo"
printf 'system\n' > "$OUT/sysmark"
EX="/dsrc/ /apps/keep.osp/ /apps/keep.osp/start=$OUT/h1.elf /apps/keep.osp/SYSTEM=$OUT/sysmark /apps/keep.osp/INFO=$OUT/keepinfo"
for f in "$OUT/dsrc"/*; do EX="$EX /dsrc/$(basename "$f")=$f"; done
EXTRA="$EX" bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "image built" || { tail -20 "$OUT/build.log"; bad "build.sh"; }
rm -f "$OUT/ziel.img"
head -c $((256 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --ja;exit" 900 > /dev/null 2>&1
gleich "install onto empty disk" "$(cat "$OUT/inst.rc" 2>/dev/null)" "21"
cp -f "$OUT/ziel.img" "$OUT/leer.img"

echo
echo "== 2. install keeps image bundles =="
rc=$(lauf k1 "opk install /dsrc/libx-1.opk;ls /apps;exit")
hat "$OUT/k1.txt" "opk: installed libx" "libx installs"
hat "$OUT/k1.txt" "libx.osp" "the installed bundle is in /apps"
hat "$OUT/k1.txt" "keep.osp" "image bundle keep survives the install"
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf k2 "opk install /dsrc/libx-1.opk;opk remove libx;ls /apps;exit")
hat "$OUT/k2.txt" "opk: removed libx" "libx is removed"
hat "$OUT/k2.txt" "keep.osp" "image bundle keep survives the remove"
hatnicht "$OUT/k2.txt" "libx.osp" "the removed bundle is gone from /apps"

echo
echo "=================================================================="
echo "  $pass green, $fail red"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
