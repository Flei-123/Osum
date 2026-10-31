#!/usr/bin/env bash
#
#   bash tools/netzui/run.sh
#
set -uo pipefail
cd "$(dirname "$0")/../.."

FIRNC=${FIRNC:-vendor/firn/bin/firnc}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export FIRNLIB="$PWD/lib"
FIRNLIB_TEST="$PWD/lib:$PWD/vendor/firn/lib"

pass=0
fail=0
ok()  { echo "  ok   $*"; pass=$((pass+1)); }
bad() { echo "  FAIL $*"; fail=$((fail+1)); }

echo "== 1. ist die geprueft Kopie noch dieselbe wie das Programm? =="

rumpf() { # datei funktion
    awk -v f="fn $2(" '
        index($0, f) == 1 { in_f = 1 }
        in_f { print }
        in_f && $0 == "}" { exit }
    ' "$1" | grep -v '^\s*//' | grep -v '^\s*$' | sed 's/[[:space:]]\+/ /g'
}

for fn in rate_aus rate_an append_amount zehntel_an; do
    a=$(rumpf kernel/user/settings.fi "$fn")
    b=$(rumpf tools/netzui/logik.fi "$fn")
    if [ -z "$a" ]; then
        bad "$fn: in kernel/user/settings.fi nicht gefunden"
    elif [ "$a" = "$b" ]; then
        ok "$fn ist in beiden Dateien Zeichen fuer Zeichen dieselbe"
    else
        bad "$fn ist AUSEINANDERGELAUFEN -- die Kopie prueft etwas anderes"
        diff <(echo "$a") <(echo "$b") | head -10 | sed 's/^/        /'
    fi
done

for fn in glatt_ein glatt_tx glatt_rx; do
    a=$(rumpf kernel/user/settings.fi "$fn")
    b=$(rumpf tools/netzui/logik.fi "$fn")
    if [ "$a" = "$b" ] && [ -n "$a" ]; then
        ok "$fn ist in beiden Dateien dieselbe"
    else
        bad "$fn ist auseinandergelaufen"
    fi
done

echo "== 2. die Gegenprobe der Gegenprobe =="
cp tools/netzui/logik.fi "$TMPD/kaputt.fi"
sed -i 's|return (fresh - alt) \* 100 / dt|return (fresh - alt) * 99 / dt|' "$TMPD/kaputt.fi"
a=$(rumpf kernel/user/settings.fi rate_aus)
b=$(rumpf "$TMPD/kaputt.fi" rate_aus)
if [ "$a" != "$b" ]; then
    ok "ein veraenderter Rumpf wird erkannt (100 -> 99)"
else
    bad "der Vergleich schlaegt NICHT an -- er prueft nichts"
fi

echo "== 3. die Rechnungen selbst =="
if ! FIRNLIB="$FIRNLIB_TEST" "$FIRNC" --profile=app tools/netzui/logik.fi \
        -o "$TMPD/logik" > "$TMPD/build.log" 2>&1; then
    bad "tools/netzui/logik.fi laesst sich nicht uebersetzen"
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
        bad "das Pruefprogramm endete mit $rc, meldet aber keinen Fehlschlag"
    fi
fi

echo "== 4. uebersetzt das Programm, in das die Rechnung gehoert? =="
if "$FIRNC" -c --profile=app kernel/user/settings.fi -o "$TMPD/settings.o" \
        > "$TMPD/set.log" 2>&1; then
    ok "kernel/user/settings.fi uebersetzt"
else
    bad "kernel/user/settings.fi uebersetzt NICHT"
    sed 's/^/        /' "$TMPD/set.log" | head -15
fi

echo "== 5. stehen die neuen Texte in BEIDEN Katalogen? =="
kn=0
for k in $(grep -o 'settings\.net\.[a-z.]*' kernel/user/settings.fi | sort -u); do
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
    ok "$kn Schluessel, alle in locale/de und locale/en"
else
    bad "keine Schluessel gefunden -- der Test misst nichts"
fi

echo "== 6. passen die Texte in ihre Spalte? =="
if python3 tools/netzui/breiten.py > "$TMPD/breiten.txt" 2>&1; then
    ok "alle Zeilen der Netzseite passen in ihre Spalte"
    sed 's/^/  /' "$TMPD/breiten.txt" | grep -a 'ok  ' | tail -3
else
    bad "Zeilen der Netzseite laufen aus ihrer Spalte"
    sed 's/^/        /' "$TMPD/breiten.txt" | grep -a 'ZU BREIT'
fi

echo "== 7. passen die Tafelspalten zu ihrer Tafel? =="
for tafel in c_nprog c_nconn; do
    summe=$(grep -a "static mut $tafel" kernel/user/settings.fi \
            | sed 's/.*= "//; s/".*//' \
            | grep -aoE '[0-9]+' \
            | awk '{s += $1} END {print s+0}')
    if [ -n "$summe" ] && [ "$summe" -le 428 ]; then
        ok "$tafel: Spalten zusammen $summe von 428 Bildpunkten"
    else
        bad "$tafel: Spalten zusammen $summe -- die Tafel hat 428"
    fi
done

echo
echo "NETZUI: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
