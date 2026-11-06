#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
TMPD=$(mktemp -d)
SRVPID=""
cleanup() { [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; [ -n "${BROWSERDEF_KEEP:-}" ] && cp -r "$TMPD" "$BROWSERDEF_KEEP" 2>/dev/null; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }

REAL=${BROWSERDEF_REAL:-0}
CB=0; BLOCKS=32768; [ "$REAL" = 1 ] && { CB=1; BLOCKS=163840; }
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "BROWSERDEF: qemu missing"; exit 1; }

mkdir -p "$TMPD/www"
cat > "$TMPD/www/i.htm" <<'HTML'
<!doctype html><html><head><title>Default browser</title></head><body>
<h1>Opened through the handler registry</h1>
<p>This page comes over TCP from the host.</p>
<div style="background:#0033aa;width:300px;height:80px"></div>
<div style="background:#cc0000;width:200px;height:40px"></div>
</body></html>
HTML
PORT=$(python3 -I -c "import socket;s=socket.socket();s.bind(('0.0.0.0',0));print(s.getsockname()[1]);s.close()")
( cd "$TMPD/www" && exec python3 -I -m http.server "$PORT" --bind 0.0.0.0 >/dev/null 2> "$TMPD/http.log" ) &
SRVPID=$!
sleep 1

URL="http://10.0.2.2:$PORT/i.htm"
cat > "$TMPD/vuihost.script" <<EOS
/bin/open /data/archive.xyz
/bin/open noextension
/bin/open $URL
EOS

: > "$TMPD/handlers.empty"

live() {
    local nm=$1 wait_re=$2; shift 2
    local -a ENVV=("$@")
    env "${ENVV[@]}" bash tools/alltag/build.sh "$TMPD/$nm" kbd=yes uitrace=yes lang=en \
        "accel=${OSUM_QEMU_ACCEL}" "waitfor=$wait_re" "bloecke=$BLOCKS" \
        "extra=osum vfs bus nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 wighalt=120 wigapp=/bin/vuihost" \
        "progs=open certus vuihost sh echo theme" \
        xdir=/proc xdir=/dev xdir=/etc \
        "xfile=/etc/vuihost.script=$TMPD/vuihost.script" \
        "xfile=/etc/wallpaper=assets/wallpaper-sea.osym" \
        "xfile=/etc/handlers.conf=${HC:-etc/handlers.conf}" \
        "qemu=-netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c" \
        warten=25 > "$TMPD/$nm.log" 2>&1
}

colour_count() {
    python3 -I - "$1" "$2" <<'PY'
import sys
from PIL import Image
img = Image.open(sys.argv[1]).convert("RGB")
r, g, b = (int(sys.argv[2][i:i+2], 16) for i in (0, 2, 4))
n = 0
for pr, pg, pb in img.getdata():
    if abs(pr - r) <= 12 and abs(pg - g) <= 12 and abs(pb - b) <= 12:
        n += 1
print(n)
PY
}

echo "== 1. registry present: http target opens the real browser =="
live r1 "vuihost: run /bin/open rc=0" CERTUS_BUILD=$CB
S=$TMPD/r1/serial.txt
has "$S" "vuihost: run /bin/open rc=3" "unknown extension: open exits 3"
has "$S" "open: no handler for /data/archive.xyz" "unknown extension: named in the message"
has "$S" "open: no handler for noextension" "target without scheme or extension: no handler"
hasnot "$S" "open: no handler for $URL" "the http target has a handler"
has "$S" "vuihost: run /bin/open rc=0" "the http open call exits 0"
if [ "$REAL" != 1 ]; then
    has "$S" "certus: open $URL" "the handler started Certus with the http target as argument"
fi
if [ "$REAL" = 1 ]; then
    hasnot "$S" "outside the user region" "the kernel accepted the real Certus image"
    if grep -q "GET /i.htm" "$TMPD/http.log"; then ok "the guest browser fetched /i.htm from the host server"; else bad "no GET /i.htm reached the server"; fi
    if [ -s "$TMPD/r1/desktop.png" ]; then
        B=$(colour_count "$TMPD/r1/desktop.png" 0033aa); R=$(colour_count "$TMPD/r1/desktop.png" cc0000)
        [ "${B:-0}" -ge 4000 ] && ok "screen shows the blue block of the page ($B px)" || bad "blue block missing ($B px)"
        [ "${R:-0}" -ge 1500 ] && ok "screen shows the red block of the page ($R px)" || bad "red block missing ($R px)"
    else
        bad "no screenshot (r1)"
    fi
fi

echo "== 2. COUNTER-PROOF: no /etc/handlers.conf content =="
before=$(grep -c "GET /i.htm" "$TMPD/http.log")
HC="$TMPD/handlers.empty" live r2 "open: no handler for http" CERTUS_BUILD=$CB
S=$TMPD/r2/serial.txt
has "$S" "open: no handler for $URL" "empty registry: open refuses the http target"
hasnot "$S" "vuihost: run /bin/open rc=0" "empty registry: no successful open"
[ "$REAL" = 1 ] || hasnot "$S" "certus: open" "empty registry: Certus was not started"
if [ "$REAL" = 1 ]; then
    after=$(grep -c "GET /i.htm" "$TMPD/http.log")
    [ "$after" -eq "$before" ] && ok "empty registry: the server saw no new request" || bad "the server saw $((after-before)) new requests"
    if [ -s "$TMPD/r2/desktop.png" ]; then
        B=$(colour_count "$TMPD/r2/desktop.png" 0033aa)
        [ "${B:-0}" -lt 200 ] && ok "empty registry: no page on screen ($B blue px)" || bad "page painted without a handler ($B blue px)"
    else
        bad "no screenshot (r2)"
    fi
fi

echo "== 3. guests did not crash =="
for d in r1 r2; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$TMPD/$d/serial.txt" 2>/dev/null; true)
    [ "$c" = 0 ] || bad "crash lines in $d: $c"
done
echo "BROWSERDEF: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
