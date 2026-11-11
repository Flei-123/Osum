#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
CC=$FIRNC
OUT=${1:-/tmp/upd}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
OPK=${OPK:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum

[ -f "$OUT/geheim.key" ] || { echo "== $OUT/geheim.key fehlt -- erst tools/install/pakete.sh"; exit 1; }

mkdir -p "$OUT/quelle3" "$OUT/boese"
as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1

# ---------------------------------------------------------- Fassung 3
"$CC" kernel/user/hallo3.fi -o "$OUT/h3.o" > "$OUT/h3.err" 2>&1 || {
    echo "== h3: der Uebersetzer sagt nein"; head -10 "$OUT/h3.err"; exit 1; }
ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
   -o "$OUT/h3.elf" "$OUT/crt.o" "$OUT/h3.o" || exit 1
strip --strip-all "$OUT/h3.elf"
sed "s#H3ELF#$OUT/h3.elf#" tools/update/hallo3.rezept > "$OUT/hallo3.rezept"
rm -f "$OUT/quelle3"/*
python3 "$OPK" bauen "$OUT/hallo3.rezept" -o "$OUT/quelle3/hallo-3.opk" || exit 1
python3 "$OPK" quelle "$OUT/quelle3" --schluessel "$OUT/geheim.key" \
    > "$OUT/quelle3.log" 2>&1 || { cat "$OUT/quelle3.log"; exit 1; }
python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT/quelle3"/*.opk || exit 1

# ---------------------------------------------------------- die boesen
rm -f "$OUT/boese"/*
# 1. ohne Signatur
cp "$OUT/quelle1/hallo-1.opk" "$OUT/boese/ohnesig.opk"
cp "$OUT/quelle1/hallo-1.opk" "$OUT/boese/verdreht.opk"
cp "$OUT/quelle1/hallo-1.opk.sig" "$OUT/boese/verdreht.opk.sig"
python3 - "$OUT/boese/verdreht.opk" <<'EOF'
import sys
f = open(sys.argv[1], "r+b")
f.seek(20000)
b = f.read(1)
f.seek(20000)
f.write(bytes([b[0] ^ 0x40]))
f.close()
EOF
cp "$OUT/quelle1/hallo-1.opk" "$OUT/boese/hallo-1.opk"
cp "$OUT/quelle1/hallo-1.opk.sig" "$OUT/boese/hallo-1.opk.sig"
cp "$OUT/quelle1/INDEX.sig" "$OUT/boese/INDEX.sig"
python3 - "$OUT/quelle1/INDEX" "$OUT/boese/INDEX" <<'EOF'
import sys
z = open(sys.argv[1]).read()
f = z.split("\t")
f[2] = "0" * 64
open(sys.argv[2], "w").write("\t".join(f))
EOF

# ---------------------------------------------------------- fremder Schluessel
mkdir -p "$OUT/fremd"
python3 "$OPK" schluessel "$OUT/fremd" > "$OUT/fremd.log" 2>&1 || {
    cat "$OUT/fremd.log"; exit 1; }
cp "$OUT/fremd/oeffentlich.key" "$OUT/fremd.pub"

echo "   quelle3   $(ls "$OUT/quelle3" | wc -l) Dateien (Fassung 3, signiert, scheitert beim Start)"
echo "   boese     $(ls "$OUT/boese" | wc -l) Dateien"
echo "   fremd.pub $(stat -c%s "$OUT/fremd.pub") Oktette"
exit 0
