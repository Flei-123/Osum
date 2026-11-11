#!/usr/bin/env bash
#
#   bash tools/netzui/run.sh
#
set -uo pipefail
cd "$(dirname "$0")/../.."

. tools/lib/firnenv.sh
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
FIRNLIB_TEST="$PWD/lib:$FIRN_TOOLCHAIN/lib"

pass=0
fail=0
ok()  { echo "  ok   $*"; pass=$((pass+1)); }
bad() { echo "  FAIL $*"; fail=$((fail+1)); }

echo "== 1. is the checked copy still the same as the program? =="

rumpf() { # datei funktion
    awk -v f="fn $2(" '
        index($0, f) == 1 { in_f = 1 }
        in_f { print }
        in_f && $0 == "}" { exit }
    ' "$1" | grep -v '^\s*//' | grep -v '^\s*$' | sed 's/[[:space:]]\+/ /g'
}

for fn in rate_aus rate_an append_amount zehntel_an; do
    a=$(rumpf <(bash tools/structure/catprog.sh kernel/user/settings.fi) "$fn")
    b=$(rumpf tools/netzui/logik.fi "$fn")
    if [ -z "$a" ]; then
        bad "$fn: in kernel/user/settings.fi nicht gefunden"
    elif [ "$a" = "$b" ]; then
        ok "$fn is the same character for character in both files"
    else
        bad "$fn HAS DIVERGED -- the copy checks something else"
        diff <(echo "$a") <(echo "$b") | head -10 | sed 's/^/        /'
    fi
done

for fn in glatt_ein glatt_tx glatt_rx; do
    a=$(rumpf <(bash tools/structure/catprog.sh kernel/user/settings.fi) "$fn")
    b=$(rumpf tools/netzui/logik.fi "$fn")
    if [ "$a" = "$b" ] && [ -n "$a" ]; then
        ok "$fn ist in beiden Dateien dieselbe"
    else
        bad "$fn ist auseinandergelaufen"
    fi
done

echo "== 2. the control of the control =="
cp tools/netzui/logik.fi "$TMPD/kaputt.fi"
sed -i 's|return (fresh - alt) \* 100 / dt|return (fresh - alt) * 99 / dt|' "$TMPD/kaputt.fi"
a=$(rumpf <(bash tools/structure/catprog.sh kernel/user/settings.fi) rate_aus)
b=$(rumpf "$TMPD/kaputt.fi" rate_aus)
if [ "$a" != "$b" ]; then
    ok "a changed body is detected (100 -> 99)"
else
    bad "the comparison does NOT trigger -- it checks nothing"
fi

echo "== 3. the computations themselves =="
if ! FIRNLIB="$FIRNLIB_TEST" "$FIRNC" --profile=app tools/netzui/logik.fi \
        -o "$TMPD/logik" > "$TMPD/build.log" 2>&1; then
    bad "tools/netzui/logik.fi cannot be compiled"
    sed 's/^/        /' "$TMPD/build.log" | head -15
else
    ok "tools/netzui/logik.fi uebersetzt"
    "$TMPD/logik" > "$TMPD/out.txt" 2>&1
    rc=$?
    sed 's/^/  /' "$TMPD/out.txt"
    n_ok=$(sed -n 's/^NETZUI-LOGIK: \([0-9]*\) passed.*/\1/p' "$TMPD/out.txt")
    n_bad=$(sed -n 's/^NETZUI-LOGIK: [0-9]* passed, \([0-9]*\) failed.*/\1/p' "$TMPD/out.txt")
    pass=$((pass + ${n_ok:-0}))
    fail=$((fail + ${n_bad:-0}))
    if [ "$rc" != 0 ] && [ "${n_bad:-0}" = 0 ]; then
        bad "the test program ended with $rc, but reports no failure"
    fi
fi

echo "== 4. does the program the computation belongs in compile? =="
if "$FIRNC" -c --profile=app kernel/user/settings.fi -o "$TMPD/settings.o" \
        > "$TMPD/set.log" 2>&1; then
    ok "kernel/user/settings.fi uebersetzt"
else
    bad "kernel/user/settings.fi uebersetzt NICHT"
    sed 's/^/        /' "$TMPD/set.log" | head -15
fi

echo "== 5. stehen die neuen Texte in BEIDEN Katalogen? =="
kn=0
for k in $(grep -o 'settings\.net\.[a-z.]*' <(bash tools/structure/catprog.sh kernel/user/settings.fi) | sort -u); do
    kn=$((kn+1))
    d=$(grep -c "^$k = " locale/de/messages)
    e=$(grep -c "^$k = " locale/en/messages)
    if [ "$d" = 1 ] && [ "$e" = 1 ]; then
        :
    else
        bad "$k: de=$d en=$e (je genau 1 erwartet)"
    fi
done
if [ "$kn" -gt 0 ]; then
    ok "$kn keys, all in locale/de and locale/en"
else
    bad "no keys found -- the test measures nothing"
fi

echo "== 6. do the texts fit their column? =="
if python3 tools/netzui/breiten.py > "$TMPD/breiten.txt" 2>&1; then
    ok "all rows of the network page fit their column"
    sed 's/^/  /' "$TMPD/breiten.txt" | grep -a 'ok  ' | tail -3
else
    bad "rows of the network page overflow their column"
    sed 's/^/        /' "$TMPD/breiten.txt" | grep -a 'ZU BREIT'
fi

echo "== 7. do the table columns fit their table? =="
for tafel in c_nprog c_nconn; do
    summe=$(grep -a "static mut $tafel" <(bash tools/structure/catprog.sh kernel/user/settings.fi) \
            | sed 's/.*= "//; s/".*//' \
            | grep -aoE '[0-9]+' \
            | awk '{s += $1} END {print s+0}')
    if [ -n "$summe" ] && [ "$summe" -le 428 ]; then
        ok "$tafel: columns total $summe of 428 pixels"
    else
        bad "$tafel: columns total $summe -- the table has 428"
    fi
done

echo
echo "NETZUI: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
