#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/anbfleitec/interop.sh -- OrientOS `konto` (anb_fleitec) against the REAL
# broker fleitec-id (fake backend, local), MEASURED.
#
# run.sh uses a MOCK IdP to force cases a real server never produces. This
# run is the other half: the guest talks to the real code of fleitec-id
# (node, --fake: justin / test-password-1, nothing real), through a TLS 1.3
# terminator (tools/anbfleitec/proxy.py), because the guest only speaks HTTPS.
# The "person at the other device" is tools/anbfleitec/approve.py (login +
# CSRF + confirm/deny, like a browser).
#
# WHAT THIS CHECKS
#  1. Broker up: discovery + JWKS over TLS, client orientos-device / aud orientos.
#  2. Device flow in two manual steps: code + URL shown, pending, approve,
#     tokens; the subject/audience in the guest equal the broker's own token.
#  3. `--warten` (the guest polls itself) while the "person" approves.
#  4. Errors from the real broker: denied (access_denied), expired
#     (expired_token), slow_down (host pre-poll makes the guest poll too fast),
#     wrong --aud, unknown --client, device code used twice.
#  5. Refresh: rotation, replay of the old refresh token kills the family
#     (checked on the broker), the next renew ends the session cleanly.
#  6. Sign-out: POST /oidc/revoke reaches the broker, refresh token dead.
#  7. No token in clear on the disk image.
#  8. socfleitec: a broker token is NOT an fkt1 token (documented gap, r106).
#
# Usage: bash tools/anbfleitec/interop.sh    (heavy: ~20 guest boots)
# Env: FLEITEC_ID=<dir of fleitec-id> (default: the JARVIS project folder)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "${2:-}" = "$3" ]; then ok "$1: $2"; else bad "$1: '${2:-}', expected '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
num() { local n=$1 v=${2:-} o=$3 w=$4
    if [ -z "$v" ]; then bad "$n: no number (expected $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, expected $o $w"; fi
}
kv() { grep -aoE "^konto: $2 = .*" "$1" 2>/dev/null | tail -1 | sed 's/^konto: [a-z_]* = //' | tr -d '\r'; }
msg() { grep -a "^$1 = " locale/de/messages | head -1 | sed 's/^[^=]*= //'; }

FID=${FLEITEC_ID:-/root/jarvis/projects/u_DiS4in7esMF1/fleitec-id}
for t in qemu-system-x86_64 python3 openssl ip curl node; do
    command -v "$t" >/dev/null 2>&1 || { echo "ANBINTEROP: skipped, $t missing"; exit 0; }
done
[ -f "$FID/bin/fleitec-id.js" ] || { echo "ANBINTEROP: skipped, no fleitec-id at $FID"; exit 0; }
grep -q -- '--device-client' "$FID/bin/fleitec-id.js" || { echo "ANBINTEROP: skipped, fleitec-id too old (no --device-client)"; exit 0; }
python3 -c 'import cryptography' 2>/dev/null || { echo "ANBINTEROP: skipped, python3-cryptography missing"; exit 0; }

TMPD=$(mktemp -d)
NS=anbi-$$
V0=ai0-$$
V1=ai1
BPORT=$(( 16600 + ($$ % 300) * 2 ))
QPORT=$(( BPORT + 1 ))
IDPORT=$(( 20000 + ($$ % 20000) ))       # broker, loopback inside the namespace
SRVPID=""; PXPID=""; BRPID=""; GPID=""
Z="https://10.9.0.1:8443"
broker_zu() {
    if [ -n "$SRVPID" ]; then kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; fi
    SRVPID=""
}
cleanup() {
    [ -n "$GPID" ] && kill "$GPID" 2>/dev/null
    broker_zu
    [ -n "$PXPID" ] && kill "$PXPID" 2>/dev/null
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    [ -z "${KEEP_TMPD:-}" ] && rm -rf "$TMPD"
    [ -n "${KEEP_TMPD:-}" ] && echo "TMPD=$TMPD"
}
trap cleanup EXIT

ip netns del "$NS" 2>/dev/null
ip netns add "$NS" 2>/dev/null || { echo "ANBINTEROP: skipped, no network namespaces"; exit 0; }
ip netns del "$NS" 2>/dev/null

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
mkdir -p "$TMPD/w" "$TMPD/fid"

# --- build (same as run.sh) ----------------------------------------------
echo "== 0. build =="
bash tools/anbfleitec/mkcopies.sh --check > "$TMPD/copies.txt" 2>&1 \
    && ok "crypto module copies are current" || bad "stale copy: $(cat "$TMPD/copies.txt")"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if ! "$FIRNC" -c --profile=app -o "$TMPD/konto.o" kernel/app/account.fi > "$TMPD/cc.log" 2>&1; then
    bad "account.fi does not compile"; head -12 "$TMPD/cc.log" | sed 's/^/        /'
    echo "ANBINTEROP: $pass passed, $fail failed"; exit 1
fi
ld -T kernel/user/user.ld -o "$TMPD/konto.elf" "$TMPD/konto.o" && strip --strip-all "$TMPD/konto.elf" 2>/dev/null
ok "konto builds"
SOC_PROG=""
if "$FIRNC" -c --profile=app -o "$TMPD/soc.o" kernel/app/socfleitec.fi > "$TMPD/cc_soc.log" 2>&1 \
   && ld -T kernel/user/user.ld -o "$TMPD/soc.elf" "$TMPD/soc.o" 2>/dev/null; then
    strip --strip-all "$TMPD/soc.elf" 2>/dev/null; SOC_PROG="/bin/socfleitec=$TMPD/soc.elf"
    ok "socfleitec builds"
else bad "socfleitec does not build"; fi
HWNET_PROGS="sh ls cat echo" bash tools/hwnet/build.sh "$TMPD/s0" 0 > "$TMPD/b0.txt" 2>&1 \
    || { bad "kernel does not build"; tail -8 "$TMPD/b0.txt" | sed 's/^/        /'
         echo "ANBINTEROP: $pass passed, $fail failed"; exit 1; }
ok "kernel and userland built"
K="$TMPD/s0/k.mb"
python3 tools/hwnet/mkcerts.py "$TMPD/certs" konto.test > "$TMPD/certs.txt" 2>&1 \
    && ok "test certificates" || bad "mkcerts.py failed"
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'lang=de\n' > "$TMPD/locale.conf"
printf 'fleitec ziel=%s name=konto.test\n' "$Z" > "$TMPD/konten.conf"

abbild() { # <target>
    python3 tools/osum/mkfs.py build "$1" 24576 \
        /bin/ /etc/ /etc/ssl/ /etc/social/ /usr/ /usr/share/ /usr/share/locale/ \
        /usr/share/locale/en/ /usr/share/locale/de/ \
        /users/ /users/justin/ /users/justin/config/ \
        "/bin/sh=$TMPD/s0/sh.elf" "/bin/ls=$TMPD/s0/ls.elf" \
        "/bin/cat=$TMPD/s0/cat.elf" "/bin/echo=$TMPD/s0/echo.elf" \
        "/bin/konto=$TMPD/konto.elf" ${SOC_PROG:+"$SOC_PROG"} \
        "/etc/ssl/roots.pem=$TMPD/certs/ca.pem" \
        "/etc/passwd=$TMPD/passwd" "/etc/locale.conf=$TMPD/locale.conf" \
        "/etc/konten.conf=$TMPD/konten.conf" \
        "/usr/share/locale/en/messages=$ROOT/locale/en/messages" \
        "/usr/share/locale/de/messages=$ROOT/locale/de/messages" \
        > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs: $(tail -2 "$TMPD/mkfs.txt")"; return 1; }
}

# --- network: namespace 10.9.0.1 (broker + TLS proxy), bridge to the guest ---
ip netns add "$NS"
ip link add "$V0" type veth peer name "$V1"
ip link set "$V1" netns "$NS"
ip netns exec "$NS" ip addr add 10.9.0.1/24 dev "$V1"
ip netns exec "$NS" ip link set "$V1" up
ip netns exec "$NS" ip link set lo up
ip link set "$V0" up
ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
"$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!
ip netns exec "$NS" python3 tools/anbfleitec/proxy.py --listen 10.9.0.1:8443 --to "127.0.0.1:$IDPORT" \
    --cert "$TMPD/certs/good.pem" --key "$TMPD/certs/good.key" --log "$TMPD/w" > "$TMPD/px.log" 2>&1 & PXPID=$!

broker_auf() { # <device interval> <device ttl>
    broker_zu
    (cd "$FID" && exec ip netns exec "$NS" node bin/fleitec-id.js --fake --init-key --port "$IDPORT" \
        --issuer "$Z" --device-client orientos-device:orientos \
        --device-interval "$1" --device-ttl "$2" --data "$TMPD/fid") > "$TMPD/fid.log" 2>&1 &
    SRVPID=$!
    local i
    for i in $(seq 1 50); do
        ip netns exec "$NS" curl -sf "http://127.0.0.1:$IDPORT/healthz" >/dev/null 2>&1 && return 0
        sleep 0.2
    done
    bad "broker did not start: $(tail -3 "$TMPD/fid.log")"; return 1
}
hcurl() { ip netns exec "$NS" curl -s --cacert "$TMPD/certs/ca.pem" --resolve konto.test:8443:10.9.0.1 "$@"; }
approve() { ip netns exec "$NS" python3 -I tools/anbfleitec/approve.py "$Z" "$TMPD/certs/ca.pem" "$1" "$2"; }
jf() { python3 -c 'import sys,json;print(json.load(sys.stdin).get(sys.argv[1],""))' "$1" 2>/dev/null; }
jwtc() { # <token> <claim>
    python3 - "$1" "$2" <<'PY'
import base64, json, sys
p = sys.argv[1].split(".")[1]
c = json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
v = c.get(sys.argv[2], "")
print(",".join(v) if isinstance(v, list) else v)
PY
}
wire_tokens() { # <field> -> every value of that field the broker sent, in order
    python3 - "$TMPD/w/s2c.log" "$1" <<'PY'
import re, sys
d = open(sys.argv[1], "rb").read().decode("latin-1")
for m in re.finditer(r'"%s":"([^"]+)"' % sys.argv[2], d):
    print(m.group(1))
PY
}

lauf() { # <image> <script> <out>
    timeout 200 qemu-system-x86_64 -kernel "$K" -m 512 \
        -append "osum nokbd nosched noproc nofs noring3 nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0 script=$2;exit" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$1,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
# the guest waits by itself (--warten); once it shows the user code the
# "person" approves (allow|deny) -- like a user reading the code off the screen
lauf_warten() { # <image> <out> <allow|deny> [extra konto args]
    local img=$1 out=$2 dec=$3; shift 3
    : > "$out"
    lauf "$img" "konto anmelden --anbieter=fleitec --geraet --warten $*" "$out" & GPID=$!
    local i uc=""
    for i in $(seq 1 150); do
        uc=$(kv "$out" code); [ -n "$uc" ] && break
        sleep 0.4
    done
    if [ -z "$uc" ]; then bad "the guest never showed a user code"; else
        approve "$uc" "$dec" > "$out.approve" 2>&1 || bad "approve($dec) failed: $(cat "$out.approve")"
    fi
    wait "$GPID" 2>/dev/null; GPID=""
}

# slow_down made certain: shortly before the guest's first poll the HOST polls
# the same device code (still pending), then the person approves; the guest's
# poll then comes <2 s after the host's -> slow_down, +5 s, and a final ok.
lauf_warten_slow() { # <image> <out> <broker interval>
    local img=$1 out=$2 b=$3
    : > "$out"
    lauf "$img" "konto anmelden --anbieter=fleitec --geraet --warten" "$out" & GPID=$!
    local i uc=""
    for i in $(seq 1 150); do
        uc=$(kv "$out" code); [ -n "$uc" ] && break
        sleep 0.2
    done
    if [ -z "$uc" ]; then bad "the guest never showed a user code"; else
        local dc; dc=$(kv "$out" zwischen)
        sleep "$(python3 -c "print($b - 1.6)")"
        hcurl -d grant_type=urn:ietf:params:oauth:grant-type:device_code -d client_id=orientos-device -d "device_code=$dc" \
            https://konto.test:8443/oidc/token | jf error > "$out.pre"
        approve "$uc" allow > "$out.approve" 2>&1 || bad "approve failed: $(cat "$out.approve")"
    fi
    wait "$GPID" 2>/dev/null; GPID=""
    is "slow_down: the host's pre-poll was pending (not consumed)" "$(cat "$out.pre" 2>/dev/null)" "authorization_pending"
}

CMD="konto anmelden --anbieter=fleitec --geraet"

# ======================================================================
echo "== 1. broker up (real fleitec-id, fake backend) =="
# ======================================================================
broker_auf 1 600 || { echo "ANBINTEROP: $pass passed, $fail failed"; exit 1; }
hcurl https://konto.test:8443/.well-known/openid-configuration > "$TMPD/disc.json"
is "discovery: issuer" "$(jf issuer < "$TMPD/disc.json")" "$Z"
is "discovery: device endpoint" "$(jf device_authorization_endpoint < "$TMPD/disc.json")" "$Z/oidc/device_authorization"
hcurl https://konto.test:8443/oidc/jwks.json > "$TMPD/jwks.json"
python3 - "$TMPD/jwks.json" > "$TMPD/jwks.txt" <<'PY'
import json, sys
k = json.load(open(sys.argv[1]))["keys"]
print("n=%d kty=%s crv=%s kid=%s alg=%s" % (len(k), k[0].get("kty"), k[0].get("crv"), "yes" if k[0].get("kid") else "no", k[0].get("alg", "-")))
PY
is "JWKS" "$(cat "$TMPD/jwks.txt")" "n=1 kty=OKP crv=Ed25519 kid=yes alg=EdDSA"
abbild "$TMPD/base.img" || { echo "ANBINTEROP: $pass passed, $fail failed"; exit 1; }

# ======================================================================
echo "== 2. device flow in two manual steps =="
# ======================================================================
: > "$TMPD/w/s2c.log"; : > "$TMPD/w/c2s.log"
cp "$TMPD/base.img" "$TMPD/d_man.img"
lauf "$TMPD/d_man.img" "$CMD" "$TMPD/o_s1.txt"
is "step 1: state" "$(kv "$TMPD/o_s1.txt" stand)" "geraet"
UC=$(kv "$TMPD/o_s1.txt" code)
echo "$UC" | grep -qE '^[A-Z0-9]{4}-[A-Z0-9]{4}$' && ok "step 1: user code shape ($UC)" || bad "step 1: user code '$UC'"
is "step 1: URL is the broker's" "$(kv "$TMPD/o_s1.txt" url)" "$Z/oidc/device"
has "$TMPD/o_s1.txt" "konto: urlkomplett = $Z/oidc/device?user_code=" "step 1: complete URL carries the code"
DC=$(kv "$TMPD/o_s1.txt" zwischen)
[ -n "$DC" ] && ok "step 1: device code kept for step 2" || bad "step 1: no device code"
is "step 1: interval from the broker" "$(kv "$TMPD/o_s1.txt" intervall)" "1"
sleep 1.2
lauf "$TMPD/d_man.img" "$CMD --zwischen=$DC" "$TMPD/o_s2.txt"
is "step 2 before approval: still waiting" "$(kv "$TMPD/o_s2.txt" stand)" "geraet"
lauf "$TMPD/d_man.img" "konto liste" "$TMPD/o_s2l.txt"
is "nothing signed in after a pending answer" "$(kv "$TMPD/o_s2l.txt" konten)" "0"
approve "$UC" allow > "$TMPD/ap1.txt" 2>&1 && ok "the person approved on the broker ($(cat "$TMPD/ap1.txt"))" || bad "approve: $(cat "$TMPD/ap1.txt")"
sleep 1.2
lauf "$TMPD/d_man.img" "$CMD --zwischen=$DC" "$TMPD/o_s3.txt"
is "step 2 after approval: state" "$(kv "$TMPD/o_s3.txt" stand)" "ok"
is "sealed" "$(kv "$TMPD/o_s3.txt" gesiegelt)" "1"
ACC=$(wire_tokens access_token | head -1)
is "subject in the guest = sub of the broker's token" "$(kv "$TMPD/o_s3.txt" subjekt)" "$(jwtc "$ACC" sub)"
is "broker token: aud" "$(jwtc "$ACC" aud)" "orientos"
is "broker token: iss" "$(jwtc "$ACC" iss)" "$Z"
num "expiry in the guest = exp of the broker's token" "$(kv "$TMPD/o_s3.txt" ablauf)" ge "$(jwtc "$ACC" exp)"
[ -n "$(kv "$TMPD/o_s3.txt" kennung)" ] && ok "account id $(kv "$TMPD/o_s3.txt" kennung)" || bad "no account id"
# the same device code is single use (checked on the broker)
sleep 1.2
hcurl -d grant_type=urn:ietf:params:oauth:grant-type:device_code -d client_id=orientos-device -d "device_code=$DC" \
    https://konto.test:8443/oidc/token | jf error > "$TMPD/reuse.txt"
is "device code used twice (broker)" "$(cat "$TMPD/reuse.txt")" "invalid_grant"
# only the guest's own calls (the human's browser traffic carries cookies on purpose)
python3 - "$TMPD/w/c2s.log" > "$TMPD/wire.txt" <<'PY'
import re, sys
d = open(sys.argv[1], "rb").read().decode("latin-1")
parts = re.split(r"(?=(?:GET|POST) /oidc/)", d)  # bodies have no trailing newline: no ^ anchor
n = cookie = auth = badct = 0
for b in parts:
    m = re.match(r"(GET|POST) (/oidc/(?:device_authorization|token|revoke|jwks\.json|userinfo)) HTTP", b)
    if not m:
        continue
    head = b.split("\r\n\r\n", 1)[0].lower()
    n += 1
    cookie += "\ncookie:" in head
    auth += "\nauthorization:" in head and m.group(2) != "/oidc/userinfo"
    if m.group(1) == "POST" and "content-type: application/x-www-form-urlencoded" not in head:
        badct += 1
print("calls=%d cookie=%d authtok=%d badct=%d" % (n, cookie, auth, badct))
PY
sed 's/^/        /' "$TMPD/wire.txt"
grep -aoE '(GET|POST) /oidc/[a-z_./]+ HTTP' "$TMPD/w/c2s.log" | sort | uniq -c | sed 's/^/        /'
num "wire: guest calls seen" "$(grep -oE 'calls=[0-9]+' "$TMPD/wire.txt" | cut -d= -f2)" ge 5
is "wire: guest calls with a cookie" "$(grep -oE 'cookie=[0-9]+' "$TMPD/wire.txt" | cut -d= -f2)" "0"
is "wire: token/revoke calls with Authorization" "$(grep -oE 'authtok=[0-9]+' "$TMPD/wire.txt" | cut -d= -f2)" "0"
is "wire: POSTs that are not form-encoded" "$(grep -oE 'badct=[0-9]+' "$TMPD/wire.txt" | cut -d= -f2)" "0"

# ======================================================================
echo "== 3. --warten, the guest polls by itself =="
# ======================================================================
cp "$TMPD/base.img" "$TMPD/d_login.img"
lauf_warten "$TMPD/d_login.img" "$TMPD/o_w.txt" allow
is "warten: state" "$(kv "$TMPD/o_w.txt" stand)" "ok"
is "warten: sealed" "$(kv "$TMPD/o_w.txt" gesiegelt)" "1"
num "warten: polls" "$(kv "$TMPD/o_w.txt" abfragen)" ge 1
KEN=$(kv "$TMPD/o_w.txt" kennung)
is "warten: display name" "$(kv "$TMPD/o_w.txt" anzeige)" "justin"

# ======================================================================
echo "== 4. errors from the real broker =="
# ======================================================================
chk() { # <label> <image> <out> <state> <hint key>
    is "$1: state" "$(kv "$3" stand)" "$4"
    [ -n "$5" ] && is "$1: hint ($5)" "$(kv "$3" hinweis)" "$(msg "$5")"
    lauf "$2" "konto liste" "$3.l"
    is "$1: accounts on the device" "$(kv "$3.l" konten)" "0"
}
# denied
cp "$TMPD/base.img" "$TMPD/d_deny.img"
lauf_warten "$TMPD/d_deny.img" "$TMPD/o_deny.txt" deny
chk "denied" "$TMPD/d_deny.img" "$TMPD/o_deny.txt" abgelehnt konto.hint.dev_denied
# wrong audience (counter-probe: the SAME valid token is fine with the right one, see section 3)
cp "$TMPD/base.img" "$TMPD/d_aud.img"
lauf_warten "$TMPD/d_aud.img" "$TMPD/o_aud.txt" allow --aud=another-product
chk "wrong --aud" "$TMPD/d_aud.img" "$TMPD/o_aud.txt" abgelehnt konto.hint.jwt_aud
# unknown client id
cp "$TMPD/base.img" "$TMPD/d_cl.img"
lauf "$TMPD/d_cl.img" "$CMD --client=nobody" "$TMPD/o_cl.txt"
case "$(kv "$TMPD/o_cl.txt" stand)" in fehler|abgelehnt) ok "unknown client: refused ($(kv "$TMPD/o_cl.txt" stand))";; *) bad "unknown client: '$(kv "$TMPD/o_cl.txt" stand)'";; esac
lauf "$TMPD/d_cl.img" "konto liste" "$TMPD/o_cl.l"
is "unknown client: accounts on the device" "$(kv "$TMPD/o_cl.l" konten)" "0"

# slow_down: broker interval 15; the host polls once, the guest polls right after
broker_auf 15 600 || true
R=$(hcurl -d client_id=orientos-device -d 'scope=openid profile offline_access' https://konto.test:8443/oidc/device_authorization)
SDC=$(echo "$R" | jf device_code)
hcurl -d grant_type=urn:ietf:params:oauth:grant-type:device_code -d client_id=orientos-device -d "device_code=$SDC" \
    https://konto.test:8443/oidc/token | jf error > "$TMPD/sd0.txt"
is "slow_down: first (host) poll" "$(cat "$TMPD/sd0.txt")" "authorization_pending"
cp "$TMPD/base.img" "$TMPD/d_sd.img"
lauf "$TMPD/d_sd.img" "$CMD --zwischen=$SDC" "$TMPD/o_sd.txt"
is "slow_down: the guest is told to slow down" "$(kv "$TMPD/o_sd.txt" stand)" "gebremst"
# (a single --zwischen poll prints no new interval; the +5 lives in the --warten loop, measured below)
cp "$TMPD/base.img" "$TMPD/d_sdw.img"
broker_auf 6 600 || true
lauf_warten_slow "$TMPD/d_sdw.img" "$TMPD/o_sdw.txt" 6
is "slow_down in the --warten loop: ends signed in" "$(kv "$TMPD/o_sdw.txt" stand)" "ok"
num "slow_down in the --warten loop: polls (slow_down + final)" "$(kv "$TMPD/o_sdw.txt" abfragen)" ge 2
num "slow_down in the --warten loop: interval grew by >= 5 (6 -> 11)" "$(kv "$TMPD/o_sdw.txt" intervall)" ge 11

# expired code: broker device ttl 4 s
broker_auf 1 4 || true
cp "$TMPD/base.img" "$TMPD/d_exp.img"
lauf "$TMPD/d_exp.img" "$CMD" "$TMPD/o_e1.txt"
EDC=$(kv "$TMPD/o_e1.txt" zwischen)
sleep 5
lauf "$TMPD/d_exp.img" "$CMD --zwischen=$EDC" "$TMPD/o_e2.txt"
chk "expired" "$TMPD/d_exp.img" "$TMPD/o_e2.txt" abgelaufen konto.hint.dev_expired

# ======================================================================
echo "== 5. refresh rotation against the real broker =="
# ======================================================================
broker_auf 1 600 || true
cp "$TMPD/base.img" "$TMPD/d_ref.img"
: > "$TMPD/w/s2c.log"
lauf_warten "$TMPD/d_ref.img" "$TMPD/o_r0.txt" allow
RKEN=$(kv "$TMPD/o_r0.txt" kennung)
is "refresh: sign-in" "$(kv "$TMPD/o_r0.txt" stand)" "ok"
lauf "$TMPD/d_ref.img" "konto erneuern --kennung=$RKEN" "$TMPD/o_r1.txt"
is "renew: renewed" "$(kv "$TMPD/o_r1.txt" erneuert)" "1"
is "renew: state" "$(kv "$TMPD/o_r1.txt" stand)" "ok"
R1=$(wire_tokens refresh_token | sed -n 1p); R2=$(wire_tokens refresh_token | sed -n 2p)
if [ -n "$R1" ] && [ -n "$R2" ] && [ "$R1" != "$R2" ]; then ok "the broker rotated the refresh token"; else bad "no rotation on the wire ('$R1' / '$R2')"; fi
A2=$(wire_tokens access_token | sed -n 2p)
is "renewed access token: aud" "$(jwtc "$A2" aud)" "orientos"
replay() { hcurl -o /dev/null -w '%{http_code}' -d grant_type=refresh_token -d "refresh_token=$1" -d client_id=orientos-device https://konto.test:8443/oidc/token; }
is "replay of the OLD refresh token (broker)" "$(replay "$R1")" "400"
is "after the replay the whole family is dead (new token too)" "$(replay "$R2")" "400"
lauf "$TMPD/d_ref.img" "konto erneuern --kennung=$RKEN" "$TMPD/o_r2.txt"
is "dead refresh token: renewed" "$(kv "$TMPD/o_r2.txt" erneuert)" "0"
is "dead refresh token: session ended cleanly" "$(kv "$TMPD/o_r2.txt" abgemeldet)" "1"
lauf "$TMPD/d_ref.img" "konto liste" "$TMPD/o_r3.txt"
is "dead refresh token: the account entry stays" "$(kv "$TMPD/o_r3.txt" konten)" "1"

# ======================================================================
echo "== 6. sign-out =="
# ======================================================================
cp "$TMPD/base.img" "$TMPD/d_out.img"
: > "$TMPD/w/s2c.log"; : > "$TMPD/w/c2s.log"
lauf_warten "$TMPD/d_out.img" "$TMPD/o_o0.txt" allow
OKEN=$(kv "$TMPD/o_o0.txt" kennung)
O1=$(wire_tokens refresh_token | sed -n 1p)
lauf "$TMPD/d_out.img" "konto abmelden --kennung=$OKEN" "$TMPD/o_o1.txt"
is "sign-out: done" "$(kv "$TMPD/o_o1.txt" abgemeldet)" "1"
grep -aq 'POST /oidc/revoke' "$TMPD/w/c2s.log" && ok "POST /oidc/revoke reached the broker" || bad "no revoke call"
is "the refresh token is dead after sign-out (broker)" "$(replay "$O1")" "400"
python3 tools/osum/mkfs.py where "$TMPD/d_out.img" "/state/session/konto/$OKEN" > "$TMPD/wo_o.txt" 2>&1
grep -qa "no such path" "$TMPD/wo_o.txt" && ok "the session file is gone" || bad "the session file is still there"

# ======================================================================
echo "== 7. tokens never in clear on the disk =="
# ======================================================================
HITS=0; NTOK=0
for f in access_token refresh_token id_token; do
    while IFS= read -r t; do
        [ -z "$t" ] && continue
        NTOK=$((NTOK+1))
        c=$(cat "$TMPD"/d_*.img | grep -c -aF -- "$t" || true)
        HITS=$((HITS+${c:-0}))
    done < <(wire_tokens "$f")
done
num "tokens the broker issued (searched; last wire window)" "$NTOK" ge 2
is "hits in any disk image" "$HITS" "0"

# ======================================================================
echo "== 8. socfleitec and a broker token =="
# ======================================================================
# A broker access token is an EdDSA JWT, NOT "<fkt1>.<account>.<64 hex>".
# socfleitec only takes the latter (fleikontakte issues it). The bridge
# OIDC session -> fkt1 does not exist yet (fleikontakte knows no fc_sess, r106).
if [ -n "$SOC_PROG" ]; then
    : > "$TMPD/w/s2c.log"
    cp "$TMPD/base.img" "$TMPD/d_soc.img"
    lauf_warten "$TMPD/d_soc.img" "$TMPD/o_soc0.txt" allow
    ST=$(wire_tokens access_token | head -1)
    printf 'name=konto.test\nport=8443\n' > "$TMPD/fl.conf"
    lauf "$TMPD/d_soc.img" "socfleitec v1 login token $ST" "$TMPD/o_soc.txt"
    grep -aq '^err.bad' "$TMPD/o_soc.txt" && ok "socfleitec refuses a broker JWT as login token (known gap: no OIDC -> fkt1 bridge yet)" \
        || bad "socfleitec did not refuse a broker JWT: $(grep -a 'err\|ok' "$TMPD/o_soc.txt" | head -2)"
    FKT="fkt1.u_TEST.$(printf '0%.0s' $(seq 1 64))"
    lauf "$TMPD/d_soc.img" "socfleitec v1 login token $FKT" "$TMPD/o_soc2.txt"
    grep -aq '^ok' "$TMPD/o_soc2.txt" && ok "control: a token shaped fkt1.<account>.<64 hex> is accepted" \
        || bad "control: fkt1-shaped token refused: $(grep -a 'err\|ok' "$TMPD/o_soc2.txt" | head -2)"
fi

echo "ANBINTEROP: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
