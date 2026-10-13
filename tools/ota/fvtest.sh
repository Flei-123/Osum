#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/fvtest.sh -- FreeViewer viewer package: install + update + signature
# negative test in the OrientOS VM. Everything is LOCAL: own test key, own test CA,
# own feed server on the host. It never touches /srv/store or any live system.
#
#   bash tools/ota/fvtest.sh [out-dir]      (run it through /root/jarvis/bin/heavy)
#
#   1. build fvviewer 1.0.0 and 1.0.1 (pakete/bauen.sh), osdk check --strict
#   2. LIVE image (RAM root, oneshot mode iso; the disk installer is not used),
#      `opk install /fv/fvviewer-1.0.0.opk`,
#      the app is in /apps/fvviewer.osp and starts (headless usage line)
#   3. signed feed (netz2: fvviewer 1.0.1): `ota apply` updates 1.0.0 -> 1.0.1
#   4. negatives: package with wrong signature, tampered package (hash mismatch),
#      VERZEICHNIS signed with a foreign key -> nothing is installed
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh
export OSUM_CPU=${OSUM_CPU:-Haswell}
OUT=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
export OUT
PORT=${OTA_PORT:-$(( 18000 + ($$ % 900) ))}
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
OPK=${OPK:-$(python3 tools/lib/opkpfad.py)}
export OPK
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

SRVPID=""
dienst_aus() { [ -n "$SRVPID" ] && { kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; }; SRVPID=""; }
dienst() {
    dienst_aus; local w=$1; shift
    : > "$OUT/srv.log"
    python3 tools/ota/server.py --wurzel "$w" --port "$PORT" --cert "$OUT/certs/srv.pem" \
        --key "$OUT/certs/srv.key" --log "$OUT/srv.log" "$@" > "$OUT/srv.out" 2>&1 &
    SRVPID=$!
    local i; for i in $(seq 1 40); do
        grep -qa "^START port=$PORT " "$OUT/srv.log" 2>/dev/null && return 0; sleep 0.2; done
    return 1
}
trap 'dienst_aus; [ -n "${1:-}" ] || rm -rf "$OUT"' EXIT
lauf() { # name script [limit]
    : > "$OUT/srv.log"
    OTA_NETZ="$NETZ" OUT="$OUT" bash tools/install/oneshot.sh "$1" iso "$2" "${3:-600}" >/dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

echo "== 1. build the packages =="
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 || { bad "fetch-firnc"; tail -3 "$OUT/firnc.log"; }
bash pakete/bauen.sh "$OUT/pk" > "$OUT/bauen.log" 2>&1
[ -f "$OUT/pk/fvviewer-1.0.0.opk" ] && ok "fvviewer-1.0.0.opk built ($(stat -c%s "$OUT/pk/fvviewer-1.0.0.opk") octets)" \
    || { bad "fvviewer-1.0.0.opk not built"; tail -5 "$OUT/bauen.log"; exit 1; }
python3 tools/sdk/osdk.py check pakete/fvviewer/INFO --strict > "$OUT/osdk.log" 2>&1 \
    && ok "osdk check --strict: $(tail -1 "$OUT/osdk.log")" || { bad "osdk check --strict"; cat "$OUT/osdk.log"; }
# 1.0.1 = same ELF, new recipe version (and INFO version, so the manifest differs)
mkdir -p "$OUT/r101" && cp -r pakete/fvviewer/. "$OUT/r101/"
sed -i 's/^fassung=.*/fassung=1.0.1/' "$OUT/r101/rezept"
sed -i 's/1\.0\.0/1.0.1/' "$OUT/r101/INFO"
python3 tools/sdk/osdk.py check "$OUT/r101/INFO" --strict > /dev/null 2>&1 && ok "1.0.1 INFO passes osdk --strict" || bad "1.0.1 INFO"
( cd "$OUT/r101" && python3 "$OPK" bauen rezept -o "$OUT/pk/fvviewer-1.0.1.opk" > "$OUT/b101.log" 2>&1 ) \
    && ok "fvviewer-1.0.1.opk built" || { bad "1.0.1 build"; cat "$OUT/b101.log"; exit 1; }

echo "== 2. image with fvviewer-1.0.0 (+ .sig) in /fv, test key, certs =="
bash tools/install/pakete.sh "$OUT" > "$OUT/pak1.log" 2>&1 || { cat "$OUT/pak1.log"; bad "install/pakete.sh"; exit 1; }
bash tools/update/pakete.sh "$OUT" > "$OUT/pak2.log" 2>&1 || { cat "$OUT/pak2.log"; bad "update/pakete.sh"; exit 1; }
python3 tools/ota/mkcerts.py "$OUT/certs" ota.test 10.0.2.2 > "$OUT/certs.log" 2>&1 || { bad mkcerts; exit 1; }
python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT/pk/fvviewer-1.0.0.opk" "$OUT/pk/fvviewer-1.0.1.opk" > /dev/null || { bad signpak; exit 1; }
cat > "$OUT/ota.conf" <<EOF
quelle=https://10.0.2.2:$PORT
name=ota.test
abstand=3600
auto=nein
frist=15
EOF
printf 'opk rebuild\n/apps/fvviewer.osp/start\nota confirm\nopk trial\n' > "$OUT/start.sh"
OTA_ROOTS="$OUT/certs/ca.pem" OTA_CONF="$OUT/ota.conf" ZIEL_MIB=96 \
    EXTRA="/start.sh=$OUT/start.sh /fv/ /fv/fvviewer-1.0.0.opk=$OUT/pk/fvviewer-1.0.0.opk /fv/fvviewer-1.0.0.opk.sig=$OUT/pk/fvviewer-1.0.0.opk.sig" \
    bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 && ok "image built" || { bad "build.sh"; tail -8 "$OUT/build.log"; exit 1; }
# feeds (build.sh re-made quelle1/2 with hallo; add fvviewer 1.0.1 to the update source)
cp "$OUT/pk/fvviewer-1.0.1.opk" "$OUT/pk/fvviewer-1.0.1.opk.sig" "$OUT/quelle2/"
python3 "$OPK" quelle "$OUT/quelle2" --schluessel "$OUT/geheim.key" > "$OUT/q2.log" 2>&1 || { cat "$OUT/q2.log"; bad "opk quelle"; exit 1; }
python3 tools/update/signpak.py "$OUT/geheim.key" "$OUT/quelle2"/*.opk > /dev/null || bad signpak2
bash tools/ota/pakete.sh "$OUT" > "$OUT/pak3.log" 2>&1 || { cat "$OUT/pak3.log"; bad "ota/pakete.sh"; exit 1; }
mkfeed() { # dir fassung extra-listing-args...
    local d=$1 f=$2; shift 2
    rm -rf "$OUT/$d"; mkdir -p "$OUT/$d"; cp "$OUT/quelle2"/* "$OUT/$d/"
    rm -f "$OUT/$d/VERZEICHNIS" "$OUT/$d/VERZEICHNIS.sig"
}
mkfeed netzfvman 2
python3 tools/ota/listing.py "$OUT/netzfvman" --fassung 2 --schluessel "$OUT/geheim.key" --kaputt fvviewer-1.0.1.opk > /dev/null || bad netzfvman
mkfeed netzfvsig 2
cp "$OUT/pk/fvviewer-1.0.0.opk.sig" "$OUT/netzfvsig/fvviewer-1.0.1.opk.sig"
python3 tools/ota/listing.py "$OUT/netzfvsig" --fassung 2 --schluessel "$OUT/geheim.key" > /dev/null || bad netzfvsig
mkfeed netzfv 2
python3 tools/ota/listing.py "$OUT/netzfv" --fassung 2 --schluessel "$OUT/geheim.key" > /dev/null || bad netzfv
ok "feeds: netzfv (1.0.1), netzfvman (tampered), netzfvsig (wrong .sig), netzfremd (foreign key)"

echo "== 3. install fvviewer 1.0.0 from the .opk, app starts =="
lauf b0 "opk install /fv/fvviewer-1.0.0.opk;opk list;sh /start.sh;exit" 400 > /dev/null
hat "$OUT/b0.txt" "signature checked" "opk checked the package signature"
hat "$OUT/b0.txt" "opk: installed fvviewer" "opk installed fvviewer"
hat "$OUT/b0.txt" "usage: fvviewer -t" "the app started (headless usage line)"

echo "== 4. update 1.0.0 -> 1.0.1 over the signed feed =="
dienst "$OUT/netzfv" || bad "server"
lauf u1 "opk install /fv/fvviewer-1.0.0.opk;ota show;ota search;ota apply;opk list;exit" 900 > /dev/null
hat "$OUT/u1.txt" "NEW VERSION" "feed offers a new version"
hat "$OUT/u1.txt" "fvviewer 1.0.1" "ota lists fvviewer 1.0.1"
hat "$OUT/u1.txt" "opk: signature checked /tmp/ota/fvviewer-1.0.1.opk" "update package signature verified"
hat "$OUT/u1.txt" "opk: installed fvviewer -> 1" "fvviewer 1.0.1 installed as generation 1"
hat "$OUT/u1.txt" "READY FOR RESTART" "ota: ready for restart"
dienst_aus

echo "== 5. negatives: nothing may be installed =="
neg() { # name feed expected-text
    dienst "$OUT/$2" || bad "server $2"
    lauf "$1" "opk install /fv/fvviewer-1.0.0.opk;ota apply;opk list;exit" 900 > /dev/null
    hat "$OUT/$1.txt" "$3" "$1: rejected ($3)"
    hatnicht "$OUT/$1.txt" "fvviewer 1.0.1" "$1: 1.0.1 not installed"
    dienst_aus
}
neg n1 netzfvsig "SIGNATURE WRONG"
neg n2 netzfvman "HASH MISMATCH"
neg n3 netzfremd "SIGNATURE OF THE VERZEICHNIS WRONG"
echo "FVTEST: $pass ok, $fail failed (device output in $OUT/*.txt)"
[ "$fail" = 0 ]
