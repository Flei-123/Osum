#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh
export OSUM_CPU=${OSUM_CPU:-Haswell}
OUT=${OUT:-/tmp/ota-plattform}
export OUT
mkdir -p "$OUT"
OPK=${OPK:-$(python3 "$(dirname "${BASH_SOURCE[0]}")/../lib/opkpfad.py")}   # A-025: der alte Ordner war ein Arbeitsbaum
export OPK
PORT=${OTA_PORT:-$(( 19000 + ($$ % 900) ))}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

for t in qemu-system-x86_64 python3 curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "PLATTFORM: uebersprungen, $t fehlt"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "PLATTFORM: uebersprungen, python3-cryptography fehlt"; exit 0; }

SRVPID=""
dienst_aus() { [ -n "$SRVPID" ] && { kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; }; SRVPID=""; }
trap dienst_aus EXIT
dienst() {
    dienst_aus
    python3 tools/ota/server.py --wurzel "$1" --port "$PORT" \
        --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" \
        --log "$OUT/srv.log" > "$OUT/srv.out" 2>&1 &
    SRVPID=$!
    for _ in $(seq 1 40); do
        grep -qa "^START" "$OUT/srv.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
lauf() { # name skript [limit]
    : > "$OUT/srv.log"
    OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" iso "$2" "${3:-300}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
}

echo "== 1. the three packages: x86-64, AArch64 and pure data =="
bash tools/install/pakete.sh "$OUT" > "$OUT/pak1.log" 2>&1 \
    && ok "the two versions of hallo (host, signed)" \
    || { cat "$OUT/pak1.log"; bad "install/pakete.sh"; exit 1; }

python3 - "$OUT" <<'PY' || exit 1
import struct, sys
o = sys.argv[1]
b = bytearray(open(o + "/h2.elf", "rb").read())
struct.pack_into("<H", b, 18, 183)
open(o + "/harm.elf", "wb").write(bytes(b))
PY
cat > "$OUT/hallo-arm.rezept" <<EOF
name=hallo-arm
version=1.0.0
titel=Hallo (AArch64)
info=Dasselbe Programm, uebersetzt fuer eine andere Maschine
keys=hallo,arm
handle=konsole
datei=nutzlast $OUT/harm.elf
EOF
printf 'nur text, kein programm\n' > "$OUT/daten.txt"
cat > "$OUT/daten.rezept" <<EOF
name=daten
version=1.0.0
titel=Daten
info=Kein ELF -- passt auf jede Maschine
keys=daten
handle=konsole
datei=nutzlast $OUT/daten.txt
EOF
rm -rf "$OUT/netzmix"; mkdir -p "$OUT/netzmix"
cp "$OUT/quelle2/hallo-2.opk" "$OUT/quelle2/hallo-2.opk.sig" "$OUT/netzmix/"
python3 "$OPK" bauen "$OUT/hallo-arm.rezept" -o "$OUT/netzmix/hallo-arm-1.opk" \
    > "$OUT/arm.log" 2>&1 || { cat "$OUT/arm.log"; bad "hallo-arm bauen"; exit 1; }
python3 "$OPK" bauen "$OUT/daten.rezept" -o "$OUT/netzmix/daten-1.opk" \
    > "$OUT/daten.log" 2>&1 || { cat "$OUT/daten.log"; bad "daten bauen"; exit 1; }
python3 "$OPK" quelle "$OUT/netzmix" --schluessel "$OUT/geheim.key" \
    > "$OUT/mixq.log" 2>&1 || { cat "$OUT/mixq.log"; bad "opk quelle"; exit 1; }
python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT/netzmix"/*.opk \
    > "$OUT/mixsig.log" 2>&1 || { cat "$OUT/mixsig.log"; bad "signpak"; exit 1; }

echo "== 2. the DIRECTORY and its sixth column =="
python3 tools/ota/listing.py "$OUT/netzmix" --revision 2 \
    --key "$OUT/geheim.key" > "$OUT/vz.log" 2>&1 \
    && ok "$(grep -a VERZEICHNIS "$OUT/vz.log" | tr -s ' ')" \
    || { cat "$OUT/vz.log"; bad "listing.py"; exit 1; }
V="$OUT/netzmix/VERZEICHNIS"
grep -qa "^paket	hallo	.*	osum-x86_64$"    "$V" && ok "hallo carries osum-x86_64 (from the ELF header)"    || bad "hallo: falsche Spalte -- $(grep -a '^paket	hallo	' "$V")"
grep -qa "^paket	hallo-arm	.*	osum-aarch64$" "$V" && ok "hallo-arm traegt osum-aarch64"                  || bad "hallo-arm: falsche Spalte"
grep -qa "^paket	daten	.*	osum-any$"        "$V" && ok "daten carries osum-any (no ELF)"                 || bad "daten: falsche Spalte"
[ "$(head -1 "$V")" = OTA2 ] && ok "the tag stays OTA2 -- an old device keeps reading" || bad "Kennung nicht OTA2"

rm -rf "$OUT/netzalt"; cp -a "$OUT/netzmix" "$OUT/netzalt"
python3 - "$OUT" "$OPK" <<'PY' || exit 1
import importlib.util, sys
o, opk = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("opkpy", opk)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
p = o + "/netzalt/VERZEICHNIS"
z = open(p, "rb").read().decode("ascii").split("\n")
for i, s in enumerate(z):
    if s.startswith("paket\tdaten\t"):
        z[i] = "\t".join(s.split("\t")[:6])
roh = "\n".join(z).encode("ascii")
sk = open(o + "/geheim.key", "rb").read()
sig = m.ed25519_sign(sk, roh)
assert m.ed25519_verify(m.ed25519_public(sk), roh, sig)
open(p, "wb").write(roh)
open(p + ".sig", "wb").write(sig)
PY
ok "a second source: at 'daten' fehlt die Spalte, die Signatur stimmt"

echo "== 3. the image (with /bin/ota, /bin/fetch and the root) =="
cat > "$OUT/ota.conf" <<EOF
quelle=https://10.0.2.2:$PORT
name=ota.test
abstand=3600
auto=nein
frist=15
EOF
python3 tools/ota/mkcerts.py "$OUT/certs" ota.test 10.0.2.2 > "$OUT/certs.log" 2>&1 \
    && ok "certificates (Python's cryptography, not this repo)" \
    || { cat "$OUT/certs.log"; bad "mkcerts"; exit 1; }
[ -s "$OUT/ziel.img" ] || head -c $((64 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OTA_ROOTS="$OUT/certs/ca.pem" OTA_CONF="$OUT/ota.conf" ZIEL_MIB=64 \
    bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "das Abbild ($(grep -a 'apps ' "$OUT/build.log" | tr -s ' '))" \
    || { tail -20 "$OUT/build.log"; bad "build.sh"; exit 1; }

echo "== 4. the run: the mixed source =="
dienst "$OUT/netzmix" && ok "die Gegenstelle laeuft (127.0.0.1:$PORT)" || bad "Gegenstelle"
lauf mix "ota search;exit"
cat "$OUT/mix.txt" | sed -n '/ota:/p' | head -20
hat    "$OUT/mix.txt" "ota: platform osum-x86_64" "das Geraet nennt seine Plattform"
hat    "$OUT/mix.txt" "hallo"     "hallo wird angeboten"
hat    "$OUT/mix.txt" "daten"     "daten (osum-any) wird angeboten"
hatnicht "$OUT/mix.txt" "hallo-arm" "hallo-arm wird NICHT angeboten"
hat    "$OUT/mix.txt" "ota: hidden, for other platforms: 1" \
       "das Ausgeblendete wird gezaehlt und genannt"

echo "== 5. the run: a DIRECTORY without the column =="
dienst "$OUT/netzalt" && ok "the peer now points to netzalt" || bad "Gegenstelle"
lauf alt "ota search;exit"
cat "$OUT/alt.txt" | sed -n '/ota:/p' | head -20
hat "$OUT/alt.txt" "ota: hidden, no platform given: 1" \
    "eine Zeile ohne Auskunft wird ausgeblendet und gezaehlt"
hatnicht "$OUT/alt.txt" "daten " "und 'daten' steht nicht in der Liste"
dienst_aus

echo
echo "PLATTFORMPROBE: $pass gruen, $fail rot"
[ "$fail" = 0 ]
