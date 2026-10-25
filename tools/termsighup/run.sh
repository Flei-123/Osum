#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
CYC=${CYC:-6}
TARGET=${TARGET:-10.0.2.99}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" 2>/dev/null' EXIT
export DESIGNBUILD="$TMPD/build"
{
    echo "warteauf 'launcher: ready' || 120"
    echo "warte 8"
    echo "klick 300,600"
    echo "warte 1"
    echo "tippe ps"
    echo "taste ret"
    echo "warte 4"
    for i in $(seq 1 "$CYC"); do
        echo "marke tt: new win="
        echo "taste ctrl-shift-t"
        echo "warteneu tt: new win= || 40"
        echo "warte 2"
        echo "tippe ping $TARGET"
        echo "taste ret"
        echo "warte 4"
        echo "marke tt: close win="
        echo "taste ctrl-shift-w"
        echo "warteneu tt: close win= || 20"
        echo "warte 2"
    done
    echo "klick 300,600"
    echo "warte 1"
    echo "tippe ps"
    echo "taste ret"
    echo "warte 6"
    echo "foto z-end"
} > "$TMPD/dreh.txt"
run() {
    (cd "$2" && DESIGNBUILD="$TMPD/build-$1" bash tools/design/eh6.sh "$TMPD/$1" accel=kvm netz=ja moreprogs=term drehbuch="$TMPD/dreh.txt" > "$TMPD/$1.log" 2>&1)
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$1.log" | head -3
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP/$1"; cp "$TMPD/$1/serial.txt" "$KEEP/$1"/; }
}
run new "$ROOT"
python3 tools/termsighup/check.py "$TMPD/new/serial.txt" "$CYC" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt")
OLDREF=${OLDREF:-}
if [ -n "$OLDREF" ]; then
    echo "== counter-proof: the same script on $OLDREF =="
    OLDWT="$TMPD/oldtree"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    run old "$OLDWT"
    python3 tools/termsighup/check.py "$TMPD/old/serial.txt" "$CYC" | tee "$TMPD/old.txt"
    f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
    [ "$f2" -ge 1 ] && echo "  OK    the old tree fails $f2 checks: they measure something" || echo "  FAIL  the old tree passes"
fi
echo "== result =="
[ "$f1" -eq 0 ] && echo "  OK    all checks pass" || echo "  FAIL  $f1 failed"
[ "$f1" -eq 0 ] && { [ -z "$OLDREF" ] || [ "${f2:-0}" -ge 1 ]; }
