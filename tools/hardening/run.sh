#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."

FIRNC=${FIRNC:-vendor/firn/bin/firnc}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()   { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
nok()  { fail=$((fail+1)); printf '  FEHL  %s\n' "$1"; }

echo "HAERTUNG-2 Befund 1: buf_grow bei erschoepfter Arena"

if [[ ! -x $FIRNC ]]; then
    echo "  firnc fehlt -- ./vendor/firn/fetch-firnc.sh laufen lassen" >&2
    exit 1
fi

cp tools/hardening/canary.fi "$TMPD/canary.fi"
cp tools/hardening/proof.fi "$TMPD/nachweis.fi"

export FIRNLIB="$(pwd)/vendor/firn/lib"
if ! "$FIRNC" "$TMPD/nachweis.fi" -o "$TMPD/nachweis" 2>"$TMPD/bau.log"; then
    echo "  the proof could not be compiled:" >&2
    sed 's/^/    /' "$TMPD/bau.log" >&2
    exit 1
fi
ok "der Nachweis uebersetzt"

feld() { sed -n "s/.*  $2=\([0-9]*\).*/\1/p" <<<"$1"; }

echo "  -- satt (Gegenprobe: heap_alloc gelingt)"
for f in 1 2 3 4; do
    zeile=$("$TMPD/nachweis" "$f" 2>&1)
    echo "     $zeile"
    kan=$(feld "$zeile" canary)
    cn=$(feld "$zeile" capnach)
    if [[ $kan == 1 ]]; then
        ok "satt, Fall $f: Kanarienvogel heil"
    else
        nok "satt, Fall $f: Kanarienvogel ueberschrieben (canary=$kan)"
    fi
    if [[ $cn == 256 ]]; then
        ok "full, case $f: the buffer has grown (cap 128 -> 256)"
    else
        nok "full, case $f: the buffer would have grown, capafter=$cn"
    fi
done

echo "  -- hungry (the arena is really exhausted)"
for f in 1 2 3; do
    zeile=$(ulimit -v 32768; timeout 120 "$TMPD/nachweis" "$f" hunger 2>&1)
    echo "     $zeile"
    kan=$(feld "$zeile" canary)
    cn=$(feld "$zeile" capnach)
    ln=$(feld "$zeile" len)
    if [[ $cn == 128 ]]; then
        ok "hungry, case $f: buf_grow failed (cap stays 128)"
    else
        nok "hungry, case $f: the arena was not empty (capafter=$cn)"
    fi
    if [[ $kan == 1 ]]; then
        ok "hungrig, Fall $f: Kanarienvogel heil"
    else
        nok "hungrig, Fall $f: STILLER UEBERLAUF (canary=$kan, len=$ln)"
    fi
    if [[ $ln == 128 ]]; then
        ok "hungry, case $f: nothing was written (len stays 128)"
    else
        nok "hungry, case $f: it was written past the end (len=$ln)"
    fi
done

echo "  -- the control run (case 4: the unchecked caller)"
zeile=$(ulimit -v 32768; timeout 120 "$TMPD/nachweis" 4 hunger 2>&1)
echo "     $zeile"
kan=$(feld "$zeile" canary)
ln=$(feld "$zeile" len)
if [[ $kan == 0 && $ln == 192 ]]; then
    ok "the control run FAILS (canary=0, len=192) -- the proof really measures"
else
    nok "the control run does NOT fail (canary=$kan, len=$ln) -- this runner measures nothing"
fi

echo
echo "HAERTUNG: $pass gehalten, $fail gefallen"
[[ $fail -eq 0 ]]
