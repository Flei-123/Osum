#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/deps/run.sh -- r105: PACKAGE DEPENDENCIES (`deps=` in the signed package metadata),
# measured on a real guest (QEMU/KVM, /bin/opk from this tree, signed sources from the host).
#
#   bash tools/deps/run.sh [--keep]
#
# PACKAGES (all signed, all carry the hallo-1 binary; only names and `deps=` differ):
#   libx  (no deps)   appy (deps=libx)   appz (deps=libx,nolib; `nolib` exists nowhere)
#   loopa (deps=loopb)  loopb (deps=loopa)  -- a cycle
#
# SECTIONS
#   1. build: packages, signed source /dsrc, image, install onto an empty disk
#   2. strict install: appy without libx is REFUSED and nothing is written; libx first, then appy
#   3. remove: libx is refused while appy needs it; appy first, then libx works (counter-proof
#      without deps: hallo installs/removes as before)
#   4. resolving update: `opk update appy --source /dsrc` pulls libx first, from the same signed source
#   5. unresolvable: appz (dependency missing in the source) is not installed; a cycle ends in an error
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
KEEP=${1:-}
OUT=${OUT:-$(mktemp -d /tmp/deps-run.XXXXXX)}
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
mkrez libx "" && mkrez appy libx && mkrez appz "libx,nolib" \
    && mkrez loopa loopb && mkrez loopb loopa \
    && ok "five dependency packages built" || bad "mkrez"
python3 "$OPK" quelle "$OUT/dsrc" --schluessel "$OUT/geheim.key" > "$OUT/dsrc.log" 2>&1 \
    && python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT/dsrc"/*.opk > /dev/null \
    && ok "source /dsrc signed" || { cat "$OUT/dsrc.log"; bad "source signing"; }
grep -qa "deps=libx" "$OUT/dsrc/appy-1.opk" && ok "deps= is inside the package metadata (hashed + signed)" \
    || bad "deps= not in package"

EX="/dsrc/"
for f in "$OUT/dsrc"/*; do EX="$EX /dsrc/$(basename "$f")=$f"; done
EXTRA="$EX" bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "image built" || { tail -20 "$OUT/build.log"; bad "build.sh"; }
rm -f "$OUT/ziel.img"
head -c $((256 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --ja;exit" 900 > /dev/null 2>&1
gleich "install onto empty disk" "$(cat "$OUT/inst.rc" 2>/dev/null)" "21"
cp -f "$OUT/ziel.img" "$OUT/leer.img"

echo
echo "== 2. strict install =="
rc=$(lauf s1 "opk install /dsrc/appy-1.opk;opk list;exit")
hat "$OUT/s1.txt" "opk: missing dependency: libx" "appy without libx is refused, naming libx"
hatnicht "$OUT/s1.txt" "opk: installed appy" "and nothing is installed"
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf s2 "opk install /dsrc/libx-1.opk;opk install /dsrc/appy-1.opk;opk list;exit")
hat "$OUT/s2.txt" "opk: installed libx" "libx installs"
hat "$OUT/s2.txt" "opk: installed appy" "appy installs once libx is there"
hatnicht "$OUT/s2.txt" "missing dependency" "no complaint when the dependency is present"

echo
echo "== 3. remove protection =="
rc=$(lauf r1 "opk remove libx;opk list;exit")
hat "$OUT/r1.txt" "opk: still needed by: appy" "libx cannot go while appy needs it"
hatnicht "$OUT/r1.txt" "opk: removed libx" "and it stays"
rc=$(lauf r2 "opk remove appy;opk remove libx;opk list;exit")
hat "$OUT/r2.txt" "opk: removed appy" "appy goes first"
hat "$OUT/r2.txt" "opk: removed libx" "then libx goes"
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf r3 "opk install /quelle1/hallo-1.opk;opk remove hallo;exit")
hat "$OUT/r3.txt" "opk: removed hallo" "COUNTER-PROOF: a package without deps installs and removes as before"

echo
echo "== 4. resolving update =="
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf u1 "opk update appy --source /dsrc;opk list;exit")
hat "$OUT/u1.txt" "opk: installing dependency: libx" "the missing dependency is pulled first"
hat "$OUT/u1.txt" "opk: installed libx" "libx is installed"
hat "$OUT/u1.txt" "opk: installed appy" "then appy"

echo
echo "== 5. unresolvable =="
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf x1 "opk update appz --source /dsrc;opk list;exit")
hat "$OUT/x1.txt" "opk: installing dependency: nolib" "appz: the unknown dependency is looked up"
hatnicht "$OUT/x1.txt" "opk: installed appz" "and appz is NOT installed"
cp -f "$OUT/leer.img" "$OUT/ziel.img"
rc=$(lauf x2 "opk update loopa --source /dsrc;opk list;exit")
hat "$OUT/x2.txt" "too deep or circular" "a dependency cycle ends in an error"
hatnicht "$OUT/x2.txt" "opk: installed loopa" "loopa not installed"
hatnicht "$OUT/x2.txt" "opk: installed loopb" "loopb not installed"

echo
echo "=================================================================="
echo "  $pass green, $fail red"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
