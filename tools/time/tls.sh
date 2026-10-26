#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/time/tls.sh -- THE CLOCK AND TLS: a wrong clock is refused, the network clock fixes it.
#
#   bash tools/time/tls.sh
#
# A real HTTPS server (Python ssl) with a certificate chain made by Python's `cryptography`
# (tools/ota/mkcerts.py: valid from yesterday to a year from now) and a fake NTP server that
# answers with the host's real time. Guest runs with three wrong hardware clocks:
#
#   A  2001-01-01   below the clock floor: the kernel says "clock state=unset" and TLS refuses
#                   with clock_not_set (it does not check dates against a clock it knows is void)
#   B  2026-10-10   plausible but too early: certificate not yet valid
#   C  2028-01-01   plausible but too late: certificate expired
#
# Each guest then asks the NTP server (sntp) and fetches again: the same page now works.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh
OUT=${OUT:-/tmp/time-tls}
mkdir -p "$OUT"
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"
export OUT
export OSUM_CPU=${OSUM_CPU:-Haswell}
NTP_PORT=${TIME_PORT:-$(( 12900 + ($$ % 90) ))}
TLS_PORT=$(( NTP_PORT + 1 ))
NETBASIS="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 tz=60 tzrule=eu"
SERVER="10.0.2.2:$NTP_PORT"
URL="https://10.0.2.2:$TLS_PORT/hello"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }

PIDS=()
cleanup() {
    local p
    for p in "${PIDS[@]:-}"; do
        [ -n "$p" ] && { kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; }
    done
}
trap cleanup EXIT

for t in qemu-system-x86_64 python3 curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "TIME-TLS: skipped, $t missing"; exit 0; }
done
python3 -c "import cryptography" 2>/dev/null || { echo "TIME-TLS: skipped, python cryptography missing"; exit 0; }

echo "== 1. the build: certificates, image with the CA in its trust store =="
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 && ok "the pinned compiler" || bad "fetch-firnc.sh"
python3 tools/ota/mkcerts.py "$OUT/certs" ota.test 10.0.2.2 > "$OUT/certs.log" 2>&1 \
    && ok "certificates made by Python's cryptography" || { bad "mkcerts.py"; cat "$OUT/certs.log"; }
OTA_ROOTS="$OUT/certs/ca.pem" bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "image built ($(grep -a 'programme' "$OUT/build.log" | tr -s ' '))" \
    || { bad "tools/install/build.sh"; tail -20 "$OUT/build.log"; }
[ -s "$OUT/bin/fetch" ] && ok "/bin/fetch is in the image" || bad "/bin/fetch missing"
head -c $((96 * 1024 * 1024)) /dev/zero > "$OUT/ziel0.img"

mkdir -p "$OUT/www"
printf 'hello from the host\n' > "$OUT/www/hello"
python3 - "$OUT" "$TLS_PORT" > "$OUT/tls-server.log" 2>&1 <<'PY' &
import http.server, ssl, sys
out, port = sys.argv[1], int(sys.argv[2])
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=out + "/www", **k)
    def log_message(self, *a):
        pass
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(out + "/certs/srv.pem", out + "/certs/srv.key")
srv = http.server.HTTPServer(("127.0.0.1", port), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print("START", flush=True)
srv.serve_forever()
PY
PIDS+=($!)
python3 tools/time/fakentp.py --port "$NTP_PORT" --log "$OUT/ntp.log" --now-offset-ms 0 > "$OUT/ntp.out" 2>&1 &
PIDS+=($!)
for i in $(seq 1 40); do
    grep -qa "^START" "$OUT/ntp.log" 2>/dev/null && grep -qa START "$OUT/tls-server.log" 2>/dev/null && break
    sleep 0.2
done
CV=$(curl -s --cacert "$OUT/certs/ca.pem" --resolve "ota.test:$TLS_PORT:127.0.0.1" -o /dev/null \
     -w '%{http_code} %{ssl_verify_result}' "https://ota.test:$TLS_PORT/hello" 2>/dev/null)
[ "$CV" = "200 0" ] && ok "the server answers curl with a verified chain ($CV)" || bad "curl against the server: '$CV'"

lauf() { # name rtc-base script
    cp -f "$OUT/ziel0.img" "$OUT/ziel.img"
    OSUM_RTC="base=$2,clock=vm" OTA_NETZ="$NETBASIS" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" iso "$3" 300 > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}
FETCH="fetch -n ota.test $URL"
SCRIPT="cat /proc/clock;$FETCH;sntp $SERVER;cat /proc/clock;$FETCH;exit"

echo
echo "== 2. A: hardware clock 2001 (below the floor) =="
rc=$(lauf tlsA 2001-01-01T00:00:00 "$SCRIPT")
[ "$rc" = 21 ] && ok "tlsA: the machine comes up" || bad "tlsA: exit code '$rc'"
hat "$OUT/tlsA.txt" "clock state=unset" "the kernel knows the clock is void"
hat "$OUT/tlsA.txt" "verify REFUSED clock_not_set" "TLS refuses with clock_not_set (not with a date verdict)"
hat "$OUT/tlsA.txt" "the clock is not set" "and says why"
hat "$OUT/tlsA.txt" "sntp: clock set" "the network clock sets it"
hat "$OUT/tlsA.txt" "clock state=set" "the kernel now says the clock is set"
hat "$OUT/tlsA.txt" "fetch: verify OK" "after the sync the same page verifies"

echo
echo "== 3. B: hardware clock 2026-10-10 (plausible, before the certificate starts) =="
rc=$(lauf tlsB 2026-10-10T12:00:00 "$SCRIPT")
[ "$rc" = 21 ] && ok "tlsB: the machine comes up" || bad "tlsB: exit code '$rc'"
hat "$OUT/tlsB.txt" "clock state=rtc" "a plausible RTC value is state=rtc"
hat "$OUT/tlsB.txt" "verify REFUSED not_yet_valid" "the certificate is refused: not yet valid"
hat "$OUT/tlsB.txt" "fetch: verify OK" "after the sync the page verifies"

echo
echo "== 4. C: hardware clock 2028-01-01 (plausible, after the certificate ends) =="
rc=$(lauf tlsC 2028-01-01T12:00:00 "$SCRIPT")
[ "$rc" = 21 ] && ok "tlsC: the machine comes up" || bad "tlsC: exit code '$rc'"
hat "$OUT/tlsC.txt" "verify REFUSED expired" "the certificate is refused: expired"
hat "$OUT/tlsC.txt" "fetch: verify OK" "after the sync the page verifies"

echo
echo "== 5. GEGENPROBE: a right clock needs no sync =="
rc=$(lauf tlsD "$(date -u +%Y-%m-%dT%H:%M:%S)" "cat /proc/clock;$FETCH;exit")
hat "$OUT/tlsD.txt" "clock state=rtc" "state=rtc with a plausible hardware clock"
hat "$OUT/tlsD.txt" "fetch: verify OK" "the page verifies at once"
hatnicht "$OUT/tlsD.txt" "REFUSED" "nothing is refused"

echo
echo "=================================================================="
echo "  TIME-TLS: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
