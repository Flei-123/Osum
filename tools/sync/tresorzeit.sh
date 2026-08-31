#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sync/tresorzeit.sh -- WIE LANGE DAUERT ES, DEN TRESOR ZU OEFFNEN?
#
# Der Auftrag fragt danach, und die Antwort aus der scrypt-Tabelle des
# Wirtes ist nur die halbe: sie sagt, was das VERFAHREN kostet, nicht
# was das SYSTEM braucht. Also wird hier IM System gemessen, mit der Uhr
# des Systems (`date -u` gibt die Betriebsdauer in Millisekunden) und mit
# dem voreingestellten Preis N=16384, r=8 -- nicht mit dem billigen
# N=256 der uebrigen Testlaeufe.
#
#   bash tools/sync/tresorzeit.sh [N] [r]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
BLOCKS=8192
PROGS="sh ls cat echo date sync tresor"
PASS=eine-lange-passphrase
NP=${1:-16384}
RP=${2:-8}
TMPD=${TZ_TMP:-/tmp/synctresorzeit}
rm -rf "$TMPD"; mkdir -p "$TMPD/bin"

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 || {
    tail -5 "$TMPD/b0.txt"; exit 1; }
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS || exit 1

cat > "$TMPD/s.sh" <<EOS
echo ==NEU==
date -u
sync neu /konto $PASS eigen /store $NP $RP
date -u
echo ==TRESORNEU==
tresor neu /konto /tresor $PASS
date -u
echo ==AUF==
tresor auf /konto /tresor $PASS 60
date -u
echo ==LEGEN==
tresor legen /tresor bank geheim-4711
date -u
echo ==GIB==
tresor gib /tresor bank
date -u
echo ==ZU==
tresor zu /tresor
date -u
echo ==AUF2==
tresor auf /konto /tresor $PASS 60
date -u
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/d.img" $BLOCKS \
    /bin/ /t/ /proc/ /dev/ /konto/ /store/ /daten/ /tresor/ /system/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    /t/s.sh="$TMPD/s.sh" > "$TMPD/mkfs.txt" 2>&1 || cat "$TMPD/mkfs.txt"
SYNC_TIMEOUT=1800 bash tools/sync/lauf.sh "$TMPD/k0.img" "$TMPD/d.img" \
    "$TMPD/d.txt" /t/s.sh > /dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/d.txt" > "$TMPD/d.log"

echo "===== scrypt N=$NP r=$RP, gemessen IM System ====="
sed -n '/^==NEU==/,/^==END==/p' "$TMPD/d.log" | grep -aE '^(==|up )'
echo
python3 - "$TMPD/d.log" <<'PY'
import re, sys
zeilen = open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()
marke = None
letzte = None
for z in zeilen:
    z = z.strip()
    if z.startswith('==') and z.endswith('=='):
        marke = z.strip('=')
        continue
    m = re.match(r'^up (\d+) ms$', z)
    if m:
        t = int(m.group(1))
        if letzte is not None and marke:
            print("%-12s %7d ms" % (marke, t - letzte))
        letzte = t
PY
echo "Arbeitsordner bleibt: $TMPD"
