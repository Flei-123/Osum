#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/brand-env.sh
. tools/lib/qemu.sh
. tools/lib/summary.sh
. tools/sync/gc.sh
. tools/lib/pidkill.sh

export FIRNLIB="$ROOT/lib"
export BOOT_KERNEL_COPY=1
export OSUM_CPU=${OSUM_CPU:-Haswell}
OLD_CLIENT_REF=${OLD_CLIENT_REF:-a11a0b9e8}
CC="$ROOT/vendor/firn/bin/firnc"
OUT=$(mktemp -d "${TMPDIR:-/tmp}/feedlisting.XXXXXX")
export OUT
PORT=${FEEDLISTING_PORT:-$((19000 + ($$ % 900)))}
NET="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
SRVPID=""
pass=0
fail=0

summary_begin FEEDLISTING
stop_server() {
    [ -n "$SRVPID" ] && osum_kill_tree "$SRVPID" 2>/dev/null
    SRVPID=""
}
cleanup() { stop_server; summary_guard; [ -n "${OSUM_KEEP_TMP:-}" ] || rm -rf "$OUT"; }
trap cleanup EXIT

ok()  { pass=$((pass + 1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
equal() { [ "$2" = "$3" ] && ok "$1: $2" || bad "$1: '$2', expected '$3'"; }

serve() {
    stop_server
    : > "$OUT/srv.log"
    python3 tools/ota/server.py --wurzel "$1" --port "$PORT" \
        --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" \
        --log "$OUT/srv.log" > "$OUT/srv.out" 2>&1 &
    SRVPID=$!
    local i
    for i in $(seq 1 40); do
        grep -qa "^START port=$PORT " "$OUT/srv.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

boot() {
    local name=$1 script=$2
    cp -f "$OUT/base.img" "$OUT/ziel.img"
    : > "$OUT/srv.log"
    OTA_NETZ="$NET" bash tools/install/oneshot.sh "$name" platte "$script" 600 > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$name.txt" 2>/dev/null
    cat "$OUT/$name.rc" 2>/dev/null
}

make_feed() {
    local dir=$1 styles=$2
    rm -rf "$OUT/$dir"
    mkdir -p "$OUT/$dir"
    cp "$OUT"/quelle2/* "$OUT/$dir/"
    rm -f "$OUT/$dir/VERZEICHNIS" "$OUT/$dir/VERZEICHNIS.sig"
    OTA_LISTING_STYLES=$styles python3 tools/ota/listing.py "$OUT/$dir" --revision 2 --key "$OUT/geheim.key" > "$OUT/$dir.log" 2>&1
}

echo "== 1. publisher: both documents, same content, legacy bytes unchanged =="
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 && ok "pinned compiler" || bad "fetch-firnc.sh"
bash tools/install/pakete.sh "$OUT" > "$OUT/pak1.log" 2>&1 && ok "signed sources" || bad "install/pakete.sh"
python3 tools/ota/mkcerts.py "$OUT/certs" ota.test 10.0.2.2 > "$OUT/certs.log" 2>&1 && ok "certificates" || bad "mkcerts.py"

make_feed feed_dual legacy,english
make_feed feed_legacy legacy
make_feed feed_english english
for f in VERZEICHNIS VERZEICHNIS.sig LISTING LISTING.sig; do
    [ -s "$OUT/feed_dual/$f" ] && ok "dual feed has $f" || bad "dual feed lacks $f"
done
[ -e "$OUT/feed_legacy/LISTING" ] && bad "legacy feed has LISTING" || ok "legacy feed has no LISTING"
[ -e "$OUT/feed_english/VERZEICHNIS" ] && bad "english feed has VERZEICHNIS" || ok "english feed has no VERZEICHNIS"
equal "legacy marker" "$(head -1 "$OUT/feed_dual/VERZEICHNIS")" "OTA2"
equal "english marker" "$(head -1 "$OUT/feed_dual/LISTING")" "OTA3"
python3 -I tools/feedlisting/compare.py "$OUT/feed_dual" "$OUT/geheim.key" > "$OUT/compare.log" 2>&1 \
    && ok "same packages, same hashes, both signatures verify" || { bad "documents differ"; tail -5 "$OUT/compare.log"; }

OLD="$OUT/old"
mkdir -p "$OLD"
git archive "$OLD_CLIENT_REF" kernel lib | tar -x -C "$OLD"
(
    cd "$OLD" && FIRNLIB="$OLD/lib" "$CC" $OPTL kernel/user/ota.fi -o ota.o \
        && as --64 -o crt.o kernel/user/crt.s \
        && ld $GCS -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start -o ota-old crt.o ota.o \
        && strip --strip-all ota-old
) > "$OUT/old-build.log" 2>&1 && ok "legacy client built from $OLD_CLIENT_REF" || { bad "legacy client build"; tail -5 "$OUT/old-build.log"; }
hasnot "$OLD/kernel/user/ota/otacmd.fi" "LISTING" "the pinned legacy client really has no LISTING support" 

echo "== 2. image with the new client plus the legacy client as /bin/ota-old =="
cat > "$OUT/ota.conf" <<EOF
source=https://10.0.2.2:$PORT
name=ota.test
abstand=3600
auto=nein
frist=15
EOF
printf 'opk rebuild\nopk trial\n' > "$OUT/start.sh"
OTA_ROOTS="$OUT/certs/ca.pem" OTA_CONF="$OUT/ota.conf" ZIEL_MIB=96 \
    EXTRA="/start.sh=$OUT/start.sh /bin/ota-old=$OLD/ota-old" \
    bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 && ok "image built" || { bad "build.sh"; tail -10 "$OUT/build.log"; }
rm -f "$OUT/ziel.img"
head -c $((96 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
OUT="$OUT" bash tools/install/oneshot.sh inst iso "install /dev/hda --yes;exit" 900 > /dev/null 2>&1
equal "installation" "$(cat "$OUT/inst.rc" 2>/dev/null)" "21"
cp -f "$OUT/ziel.img" "$OUT/base.img"

echo "== 3. new client =="
serve "$OUT/feed_dual"
equal "new client, dual feed: boots" "$(boot n1 'ota search;exit')" "21"
has "$OUT/n1.txt" "ota: version there 2" "new client reads the dual feed"
has "$OUT/srv.log" "200 LISTING" "it took LISTING"
hasnot "$OUT/srv.log" "VERZEICHNIS" "and never asked for VERZEICHNIS"

serve "$OUT/feed_legacy"
equal "new client, legacy-only feed: boots" "$(boot n2 'ota search;exit')" "21"
has "$OUT/n2.txt" "ota: version there 2" "new client falls back to VERZEICHNIS"
has "$OUT/srv.log" "404 /LISTING" "LISTING answered 404"
has "$OUT/srv.log" "200 VERZEICHNIS" "and VERZEICHNIS was read"

serve "$OUT/feed_english"
equal "new client, english-only feed: boots" "$(boot n3 'ota search;exit')" "21"
has "$OUT/n3.txt" "ota: version there 2" "new client reads the english-only feed"
hasnot "$OUT/srv.log" "VERZEICHNIS" "no VERZEICHNIS request"
equal "apply from the english-only feed: boots" "$(boot n4 'ota apply;exit')" "21"
has "$OUT/n4.txt" "opk: installed hallo" "ota apply installs the package"
has "$OUT/n4.txt" "ota: READY FOR RESTART" "and offers the restart"

echo "== 4. legacy client (installed HP builds) =="
serve "$OUT/feed_dual"
equal "legacy client, dual feed: boots" "$(boot o1 'ota-old search;exit')" "21"
has "$OUT/o1.txt" "ota: version there 2" "legacy client reads the dual feed"
has "$OUT/srv.log" "200 VERZEICHNIS" "through VERZEICHNIS"
hasnot "$OUT/srv.log" "LISTING" "without touching LISTING"
equal "legacy client apply: boots" "$(boot o2 'ota-old apply;exit')" "21"
has "$OUT/o2.txt" "opk: installed hallo" "legacy client installs from the dual feed"

serve "$OUT/feed_english"
equal "counter-probe, legacy client on english-only feed: boots" "$(boot o3 'ota-old search;exit')" "21"
hasnot "$OUT/o3.txt" "ota: version there 2" "the legacy client cannot read an english-only feed"

echo "== 5. signature checks stay strict =="
make_feed feed_badsig legacy,english
python3 -I - "$OUT/feed_badsig/LISTING.sig" <<'PY'
import sys
data = bytearray(open(sys.argv[1], "rb").read())
data[0] ^= 1
open(sys.argv[1], "wb").write(bytes(data))
PY
serve "$OUT/feed_badsig"
equal "bad LISTING.sig, good VERZEICHNIS: boots" "$(boot s1 'ota search;exit')" "21"
has "$OUT/s1.txt" "SIGNATURE OF THE VERZEICHNIS WRONG" "no silent fallback to the legacy document"
hasnot "$OUT/srv.log" "200 VERZEICHNIS" "legacy document not read after a bad signature"

stop_server
summary_emit "$pass" "$fail" 40
