#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh

TMPD=$(mktemp -d)
. tools/lib/summary.sh; summary_begin XTSTAFEL
trap 'summary_guard; rm -rf "$TMPD"; cp -f "$TMPD.xts" lib/crypto/xts.fi 2>/dev/null || true; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== 1. the board: switching without refilling =="
if $FIRNC tools/xtstafel/board.fi -o "$TMPD/tafel" 2>"$TMPD/t.err"; then
    ok "tools/xtstafel/board.fi uebersetzt"
else
    bad "board.fi cannot be compiled"
    sed 's/^/        /' "$TMPD/t.err" | head -20
    summary_emit "$pass" "$fail" 0; exit 1
fi
"$TMPD/tafel" > "$TMPD/tafel.txt" 2>&1
rc=$?
sed 's/^/        /' "$TMPD/tafel.txt"
if [ "$rc" = 0 ]; then
    ok "the board acceptance is green (errors=0)"
else
    bad "the board acceptance failed"
fi
W=$(grep -oE '200 sectors alternating, fills: [0-9]+' "$TMPD/tafel.txt" | grep -oE '[0-9]+$')
if [ "${W:-x}" = 0 ]; then
    ok "NO refilling when switching between two carriers (fills=0)"
else
    bad "refilling happens when switching (fills=${W:-?})"
fi

echo "== 2. the delete test: after forget() nothing is left =="
if $FIRNC tools/xtstafel/delete.fi -o "$TMPD/loeschen" 2>"$TMPD/l.err"; then
    "$TMPD/loeschen" > "$TMPD/loeschen.txt" 2>&1
    rc=$?
    sed 's/^/        /' "$TMPD/loeschen.txt"
    if [ "$rc" = 0 ]; then
        ok "after forget() the whole board is zeroed"
    else
        bad "after forget() something is still on the board"
    fi
else
    bad "delete.fi cannot be compiled"
    sed 's/^/        /' "$TMPD/l.err" | head -20
fi

GLIB="$TMPD/lib-gegen"
XTS_SHA0=$(sha256sum lib/crypto/xts.fi | cut -d' ' -f1)
rm -rf "$GLIB"; cp -a lib "$GLIB"

echo "== 3. CONTROL RUN: one slot (the state BEFORE this round) =="
sed -i 's/^const SLOTS: usize = 4$/const SLOTS: usize = 1/' "$GLIB/crypto/xts.fi"
if grep -q '^const SLOTS: usize = 1$' "$GLIB/crypto/xts.fi" && \
   FIRNLIB="$GLIB" $FIRNC tools/xtstafel/board.fi -o "$TMPD/g1" 2>/dev/null; then
    "$TMPD/g1" > "$TMPD/g1.txt" 2>&1
    G=$(grep -oE '200 sectors alternating, fills: [0-9]+' "$TMPD/g1.txt" | grep -oE '[0-9]+$')
    if [ "${G:-0}" -gt 0 ]; then
        ok "with ONE slot it refills at every switch (fills=$G) -- the measurement bites"
    else
        bad "even with one slot no fill is seen -- then the acceptance measures nothing"
    fi
else
    bad "the control run cannot be compiled"
fi
cp -f lib/crypto/xts.fi "$GLIB/crypto/xts.fi"

echo "== 4. CONTROL RUN: forget() clears only ONE slot =="
GLIB="$GLIB" python3 - <<'PYEOF'
import os
p=os.environ["GLIB"] + "/crypto/xts.fi"
s=open(p,encoding="utf-8").read()
s=s.replace("""fn forget() {
    var s: usize = 0
    while s < SLOTS {""","""fn forget() {
    var s: usize = 0
    while s < 1 {""",1)
s=s.replace("    octets.zero(table_start(), table_length())\n","",1)
open(p,"w",encoding="utf-8").write(s)
PYEOF
if FIRNLIB="$GLIB" $FIRNC tools/xtstafel/delete.fi -o "$TMPD/g2" 2>/dev/null; then
    "$TMPD/g2" > "$TMPD/g2.txt" 2>&1
    if [ $? != 0 ]; then
        R=$(grep -oE 'non-zero octets after forget\(\): [0-9]+' "$TMPD/g2.txt" | grep -oE '[0-9]+$')
        ok "a half forget() is CAUGHT (remainder: ${R:-?} octets) -- the delete test bites"
    else
        bad "a half forget() gets through -- the delete test is no good"
    fi
else
    bad "the control run cannot be compiled"
fi
rm -rf "$GLIB"
if [ "$(sha256sum lib/crypto/xts.fi | cut -d' ' -f1)" = "$XTS_SHA0" ]; then
    ok "lib/crypto/xts.fi in the tree is untouched after both control runs"
else
    bad "lib/crypto/xts.fi in the tree was changed"
fi

summary_emit "$pass" "$fail" 6 || exit 1
[ "$fail" = 0 ] || exit 1
