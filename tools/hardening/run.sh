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
    echo "  der Nachweis liess sich nicht uebersetzen:" >&2
    sed 's/^/    /' "$TMPD/bau.log" >&2
    exit 1
fi
ok "der Nachweis uebersetzt"

feld() { sed -n "s/.*  $2=\([0-9]*\).*/\1/p" <<<"$1"; }

echo "  -- satt (Gegenprobe: heap_alloc gelingt)"
for f in 1 2 3 4; do
    zeile=$("$TMPD/nachweis" "$f" 2>&1)
    echo "     $zeile"
    kan=$(feld "$zeile" kanarie)
    cn=$(feld "$zeile" capnach)
    if [[ $kan == 1 ]]; then
        ok "satt, Fall $f: Kanarienvogel heil"
    else
        nok "satt, Fall $f: Kanarienvogel ueberschrieben (kanarie=$kan)"
    fi
    if [[ $cn == 256 ]]; then
        ok "satt, Fall $f: der Puffer ist gewachsen (cap 128 -> 256)"
    else
        nok "satt, Fall $f: der Puffer waere gewachsen, capnach=$cn"
    fi
done

echo "  -- hungrig (die Arena ist wirklich erschoepft)"
for f in 1 2 3; do
    zeile=$(ulimit -v 32768; timeout 120 "$TMPD/nachweis" "$f" hunger 2>&1)
    echo "     $zeile"
    kan=$(feld "$zeile" kanarie)
    cn=$(feld "$zeile" capnach)
    ln=$(feld "$zeile" len)
    if [[ $cn == 128 ]]; then
        ok "hungrig, Fall $f: buf_grow ist gescheitert (cap bleibt 128)"
    else
        nok "hungrig, Fall $f: die Arena war nicht leer (capnach=$cn)"
    fi
    if [[ $kan == 1 ]]; then
        ok "hungrig, Fall $f: Kanarienvogel heil"
    else
        nok "hungrig, Fall $f: STILLER UEBERLAUF (kanarie=$kan, len=$ln)"
    fi
    if [[ $ln == 128 ]]; then
        ok "hungrig, Fall $f: nichts wurde geschrieben (len bleibt 128)"
    else
        nok "hungrig, Fall $f: es wurde ueber das Ende geschrieben (len=$ln)"
    fi
done

echo "  -- die Gegenprobe (Fall 4: der ungepruefte Aufrufer)"
zeile=$(ulimit -v 32768; timeout 120 "$TMPD/nachweis" 4 hunger 2>&1)
echo "     $zeile"
kan=$(feld "$zeile" kanarie)
ln=$(feld "$zeile" len)
if [[ $kan == 0 && $ln == 192 ]]; then
    ok "die Gegenprobe FAELLT (kanarie=0, len=192) -- der Nachweis misst wirklich"
else
    nok "die Gegenprobe faellt NICHT (kanarie=$kan, len=$ln) -- dieser Laeufer misst nichts"
fi

echo
echo "HAERTUNG: $pass gehalten, $fail gefallen"
[[ $fail -eq 0 ]]
