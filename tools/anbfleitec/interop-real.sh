#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/anbfleitec/interop-real.sh -- OrientOS `socfleitec login broker` against
# the REAL FirnChat (firnchat-web + fleikontakte binaries) and the REAL broker
# fleitec-id (fake backend, local), MEASURED. Nothing is mocked here.
#
# interop.sh (section 8) is the FAST run: a python mock of the address book
# (book.py) with a Ed25519 check of its own. This run is the other half: the
# guest meets the real code on both sides.
#
#   guest (qemu, OrientOS)  --https-->  proxy.py (TLS 1.3 terminator, path routing)
#                                          /api/kontakte  ->  firnchat-web  -> fleikontakte
#                                          everything else -> fleitec-id
#   firnchat-web reaches the broker as its OIDC issuer over https
#   (https://10.9.0.1:8443 through the same proxy, ca-file = the test CA).
#
# WHAT THIS CHECKS
#  1. Services: broker with 2 device clients (orientos-device -> aud orientos,
#     other-device -> aud other-product), firnchat-web with broker-exchange = ja,
#     broker-audience = orientos, --contacts-port/--contacts-key, fleikontakte
#     with --proxy-key; the web login of "the person" creates the account.
#  2. Before the account exists: a valid token is refused (the swap never
#     creates an account).
#  3. After the web login (account jarvis:u_FAKEjustin01): the guest signs in by
#     itself (konto, device flow), `login broker -f` -> a real fkt1, `contacts`
#     ok; the fkt1 opens the book on the host too and is read-only (profile
#     change = 403); the JWT is neither printed, stored in the configuration,
#     nor copied onto the disk image.
#  4. Refused by the REAL check, each from a clean configuration: foreign
#     signature, id_token, wrong audience (real token of another client),
#     expired (real token of a broker with --access-ttl 1, used >60 s later:
#     the library allows 60 s of leeway), garbage, missing file.
#     A refused token leaves a stored fkt1 alone.
#  5. One token, one swap (jti replay): the second swap of the SAME token is
#     refused; a fresh token swaps fine again (control).
#  6. Guard (r121), host side through the same TLS path: block list (jti, konto;
#     read on every request, a block does not consume the token), brake (429 +
#     Retry-After, also for a valid token, which stays usable afterwards), audit file.
#
# Usage: bash tools/anbfleitec/interop-real.sh     (heavy: ~12 guest boots)
# Env: FLEITEC_ID=<dir of fleitec-id>   (default: the JARVIS project folder)
#      FIRNCHAT=<firnchat checkout>     (default: the JARVIS project folder; HEAD is built)
#      FIRNCHAT_BIN=<dir with firnchat, firnchat-web, fleikontakte>  (skips the build)
#      FC_FIRNC / FC_FIRNLIB            (compiler + library for FirnChat, default: the Firn project)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "${2:-}" = "$3" ]; then ok "$1: $2"; else bad "$1: '${2:-}', expected '$3'"; fi; }
num() { local n=$1 v=${2:-} o=$3 w=$4
    if [ -z "$v" ]; then bad "$n: no number (expected $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, expected $o $w"; fi
}
info() { printf '  INFO  %s\n' "$1"; }
kv() { grep -aoE "^konto: $2 = .*" "$1" 2>/dev/null | tail -1 | sed 's/^konto: [a-z_]* = //' | tr -d '\r'; }

FID=${FLEITEC_ID:-/root/jarvis/projects/u_DiS4in7esMF1/fleitec-id}
FC=${FIRNCHAT:-/root/jarvis/projects/u_DiS4in7esMF1/firnchat}
FC_FIRNC=${FC_FIRNC:-/root/jarvis/projects/u_DiS4in7esMF1/firn/compiler/target/release/firnc}
FC_FIRNLIB=${FC_FIRNLIB:-/root/jarvis/projects/u_DiS4in7esMF1/firn/lib}
for t in qemu-system-x86_64 python3 openssl ip curl node git tar; do
    command -v "$t" >/dev/null 2>&1 || { echo "ANBREAL: skipped, $t missing"; exit 0; }
done
[ -f "$FID/bin/fleitec-id.js" ] || { echo "ANBREAL: skipped, no fleitec-id at $FID"; exit 0; }
grep -q -- '--access-ttl' "$FID/bin/fleitec-id.js" || { echo "ANBREAL: skipped, fleitec-id too old (no --access-ttl)"; exit 0; }
[ -d "$FC/src" ] || { echo "ANBREAL: skipped, no FirnChat at $FC"; exit 0; }
python3 -c 'import cryptography' 2>/dev/null || { echo "ANBREAL: skipped, python3-cryptography missing"; exit 0; }

TMPD=$(mktemp -d)
NS=anbr-$$
V0=ar0-$$
V1=ar1
BPORT=$(( 17600 + ($$ % 300) * 2 ))
QPORT=$(( BPORT + 1 ))
IDPORT=$(( 20000 + ($$ % 20000) ))       # broker, loopback in the namespace
WPORT=$(( IDPORT + 1 ))                  # firnchat-web, loopback in the namespace
ABB_EXTRA=()
SRVPID=""; PXPID=""; BRPID=""; GPID=""; RLPID=""; BKPID=""; WBPID=""
Z="https://10.9.0.1:8443"
stop_pid() { [ -n "${1:-}" ] && { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }; return 0; }
broker_zu() { stop_pid "$SRVPID"; SRVPID=""; }
cleanup() {
    [ -n "$GPID" ] && kill "$GPID" 2>/dev/null
    stop_pid "$WBPID"; stop_pid "$BKPID"; stop_pid "$RLPID"
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
ip netns add "$NS" 2>/dev/null || { echo "ANBREAL: skipped, no network namespaces"; exit 0; }
ip netns del "$NS" 2>/dev/null

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
mkdir -p "$TMPD/w" "$TMPD/fid" "$TMPD/mint" "$TMPD/jw"

# --- build: FirnChat (3 binaries from HEAD, in the temp folder) and the guest ---
echo "== 0. build =="
if [ -n "${FIRNCHAT_BIN:-}" ]; then
    FCB=$FIRNCHAT_BIN
    for b in firnchat firnchat-web fleikontakte; do
        [ -x "$FCB/$b" ] || { echo "ANBREAL: $FCB/$b missing"; exit 1; }
    done
    ok "FirnChat binaries from $FCB"
else
    mkdir -p "$TMPD/fc"
    git -C "$FC" archive HEAD | tar -x -C "$TMPD/fc"
    FCB=$TMPD/fc/bin; mkdir -p "$FCB"
    FCREV=$(git -C "$FC" rev-parse --short HEAD)
    if ( cd "$TMPD/fc" && export FIRNLIB="$FC_FIRNLIB" \
         && "$FC_FIRNC" -o "$FCB/firnchat" src/cli.fi \
         && "$FC_FIRNC" -o "$FCB/firnchat-web" src/web.fi \
         && "$FC_FIRNC" -o "$FCB/fleikontakte" src/kontakte.fi ) > "$TMPD/fcbuild.log" 2>&1; then
        ok "FirnChat $FCREV: firnchat, firnchat-web, fleikontakte built"
    else
        bad "FirnChat does not build"; head -12 "$TMPD/fcbuild.log" | sed 's/^/        /'
        echo "ANBREAL: $pass passed, $fail failed"; exit 1
    fi
fi
WEBDIR=$FC/web
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/anbfleitec/mkcopies.sh --check > "$TMPD/copies.txt" 2>&1 \
    && ok "crypto module copies are current" || bad "stale copy: $(cat "$TMPD/copies.txt")"
if ! "$FIRNC" -c --profile=app -o "$TMPD/konto.o" kernel/app/account.fi > "$TMPD/cc.log" 2>&1; then
    bad "account.fi does not compile"; head -12 "$TMPD/cc.log" | sed 's/^/        /'
    echo "ANBREAL: $pass passed, $fail failed"; exit 1
fi
ld -T kernel/user/user.ld -o "$TMPD/konto.elf" "$TMPD/konto.o" && strip --strip-all "$TMPD/konto.elf" 2>/dev/null
ok "konto builds"
if "$FIRNC" -c --profile=app -o "$TMPD/soc.o" kernel/app/socfleitec.fi > "$TMPD/cc_soc.log" 2>&1 \
   && ld -T kernel/user/user.ld -o "$TMPD/soc.elf" "$TMPD/soc.o" 2>/dev/null; then
    strip --strip-all "$TMPD/soc.elf" 2>/dev/null; ok "socfleitec builds"
else bad "socfleitec does not build"; echo "ANBREAL: $pass passed, $fail failed"; exit 1; fi
HWNET_PROGS="sh ls cat echo" bash tools/hwnet/build.sh "$TMPD/s0" 0 > "$TMPD/b0.txt" 2>&1 \
    || { bad "kernel does not build"; tail -8 "$TMPD/b0.txt" | sed 's/^/        /'
         echo "ANBREAL: $pass passed, $fail failed"; exit 1; }
ok "kernel and userland built"
K="$TMPD/s0/k.mb"
# Own CA + one certificate for the terminator. The name list carries konto.test (what the
# guest checks) and the IP 10.9.0.1 as an iPAddress entry: firnchat-web (Firn
# lib/tls/x509.fi, since r124) compares an IP issuer with iPAddress entries only. The old
# workaround (the IP text as an extra dNSName) is gone; with a Firn without r124 this run
# fails at every call to the issuer (`unreachable`).
mkdir -p "$TMPD/certs"
( cd "$TMPD/certs" \
  && openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -subj "/CN=ANB Real Test Root" -days 30 \
         -addext "basicConstraints=critical,CA:TRUE" \
  && openssl req -newkey rsa:2048 -nodes -keyout good.key -out good.csr -subj "/CN=konto.test" \
  && printf 'subjectAltName=DNS:konto.test,IP:10.9.0.1\nbasicConstraints=critical,CA:FALSE\n' > ext \
  && openssl x509 -req -in good.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out leaf.pem -days 30 -sha256 -extfile ext \
  && cat leaf.pem ca.pem > good.pem ) > "$TMPD/certs.txt" 2>&1 \
    && ok "test certificates (CA + leaf for konto.test and 10.9.0.1)" || bad "certificates: $(tail -2 "$TMPD/certs.txt")"
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'lang=de\n' > "$TMPD/locale.conf"
printf 'fleitec ziel=%s name=konto.test\n' "$Z" > "$TMPD/konten.conf"
printf 'url=%s\nname=konto.test\nroots=/etc/ssl/roots.pem\n' "$Z" > "$TMPD/fl.conf"

abbild() { # <target>
    python3 tools/osum/mkfs.py build "$1" 24576 \
        /bin/ /etc/ /etc/ssl/ /etc/social/ /usr/ /usr/share/ /usr/share/locale/ \
        /usr/share/locale/en/ /usr/share/locale/de/ \
        /users/ /users/justin/ /users/justin/config/ \
        "/bin/sh=$TMPD/s0/sh.elf" "/bin/ls=$TMPD/s0/ls.elf" \
        "/bin/cat=$TMPD/s0/cat.elf" "/bin/echo=$TMPD/s0/echo.elf" \
        "/bin/konto=$TMPD/konto.elf" "/bin/socfleitec=$TMPD/soc.elf" \
        "/etc/ssl/roots.pem=$TMPD/certs/ca.pem" \
        "/etc/passwd=$TMPD/passwd" "/etc/locale.conf=$TMPD/locale.conf" \
        "/etc/konten.conf=$TMPD/konten.conf" "${ABB_EXTRA[@]}" \
        "/usr/share/locale/en/messages=$ROOT/locale/en/messages" \
        "/usr/share/locale/de/messages=$ROOT/locale/de/messages" \
        > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs: $(tail -2 "$TMPD/mkfs.txt")"; return 1; }
}

# --- network: namespace 10.9.0.1 (broker, FirnChat, TLS proxy), bridge to the guest ---
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
    --cert "$TMPD/certs/good.pem" --key "$TMPD/certs/good.key" --log "$TMPD/w" \
    --route "/api/kontakte=127.0.0.1:$WPORT" > "$TMPD/px.log" 2>&1 & PXPID=$!

broker_auf() { # <access ttl>
    broker_zu
    (cd "$FID" && exec ip netns exec "$NS" node bin/fleitec-id.js --fake --init-key --port "$IDPORT" \
        --issuer "$Z" --device-client orientos-device:orientos,other-device:other-product \
        --client-redirect "http://127.0.0.1:$WPORT/api/oidc/callback" \
        --device-interval 1 --device-ttl 600 --access-ttl "$1" --data "$TMPD/fid") > "$TMPD/fid.log" 2>&1 &
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
mint() { # <name> <client> -> $TMPD/mint/<name>.{access,id,refresh}
    ip netns exec "$NS" python3 -I tools/anbfleitec/devtoken.py "$Z" "$TMPD/certs/ca.pem" "$2" \
        "openid profile offline_access fleitec.account" "$TMPD/mint/$1" > "$TMPD/mint/$1.out" 2>&1 \
        || bad "mint $1: $(cat "$TMPD/mint/$1.out")"
}
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
run_wait() { # <image> <out> <allow|deny>
    local img=$1 out=$2 dec=$3
    : > "$out"
    lauf "$img" "konto anmelden --anbieter=fleitec --device --wait" "$out" & GPID=$!
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

# ======================================================================
echo "== 1. broker and FirnChat up =="
# ======================================================================
# phase A: a broker with access tokens of 1 s lifetime hands out the token that
# will be "expired" by the time it is used (the library allows 60 s leeway)
broker_auf 1 || { echo "ANBREAL: $pass passed, $fail failed"; exit 1; }
mint expd orientos-device
T_EXP_AT=$(date +%s)
[ -s "$TMPD/mint/expd.access" ] && ok "a short-lived access token was minted (exp - iat = $(( $(jwtc "$(cat "$TMPD/mint/expd.access")" exp) - $(jwtc "$(cat "$TMPD/mint/expd.access")" iat) )) s)"
broker_auf 900 || { echo "ANBREAL: $pass passed, $fail failed"; exit 1; }
hcurl https://konto.test:8443/.well-known/openid-configuration > "$TMPD/disc.json"
is "discovery over TLS: issuer" "$(python3 -c 'import sys,json;print(json.load(sys.stdin).get("issuer",""))' < "$TMPD/disc.json")" "$Z"

D=$TMPD/fc-run; mkdir -p "$D/konten" "$D/relay" "$D/kontakte"
head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$D/proxy.key"; echo >> "$D/proxy.key"; chmod 600 "$D/proxy.key"
head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$D/jarvis.secret"; echo >> "$D/jarvis.secret"; chmod 600 "$D/jarvis.secret"
printf '[lokal]\ntyp = lokal\n\n[jarvis]\ntyp = oidc\nissuer = %s\nclient-id = fc_localtest\nredirect = http://127.0.0.1:%s/api/oidc/callback\nauto-konto = ja\nactive = ja\nca-file = %s\nbroker-exchange = ja\nbroker-audience = orientos\nbroker-denylist = %s/denylist.txt\nbroker-audit = %s/audit.log\n' \
    "$Z" "$WPORT" "$TMPD/certs/ca.pem" "$D" "$D" > "$D/konten/anbieter.conf"
: > "$D/denylist.txt"
printf '[lokal]\ntyp = lokal\n\n[jarvis]\ntyp = jwt\ncookie = fleitec_session\ngeheimnis = %s/jarvis.secret\nauto-konto = ja\n' "$D" > "$D/kontakte.conf"
svc_wait() { # <log> <marker regex> -> prints the port
    local i p
    for i in $(seq 1 60); do
        p=$(grep -aoE "$2" "$1" 2>/dev/null | head -1 | grep -aoE '[0-9]+$')
        [ -n "$p" ] && { echo "$p"; return 0; }
        sleep 0.2
    done
    return 1
}
(cd "$D/relay" && exec ip netns exec "$NS" "$FCB/firnchat" serve 0 data 0) > "$D/relay.log" 2>&1 & RLPID=$!
RPORT=$(svc_wait "$D/relay.log" 'FIRNCHAT listening [0-9]+') || bad "relay did not start: $(head -3 "$D/relay.log")"
(cd "$D" && exec ip netns exec "$NS" "$FCB/fleikontakte" --port 0 --daten "$D/kontakte" --anbieter-conf "$D/kontakte.conf" \
    --web-dir "$WEBDIR" --proxy-key "$D/proxy.key") > "$D/book.log" 2>&1 & BKPID=$!
KPORT=$(svc_wait "$D/book.log" 'FLEIKONTAKTE listening [0-9]+') || bad "fleikontakte did not start: $(head -3 "$D/book.log")"
(cd "$D" && exec ip netns exec "$NS" "$FCB/firnchat-web" --port "$WPORT" --relay-port "${RPORT:-0}" --konten-dir "$D/konten" \
    --web-dir "$WEBDIR" --id "$D/web.id" --contacts-port "${KPORT:-0}" --contacts-key "$D/proxy.key") > "$D/web.log" 2>&1 & WBPID=$!
svc_wait "$D/web.log" 'FIRNCHAT-WEB listening [0-9]+' >/dev/null && ok "firnchat-web + fleikontakte up (broker-exchange = ja, broker-audience = orientos, https issuer, ca-file)" \
    || { bad "firnchat-web did not start: $(head -3 "$D/web.log")"; echo "ANBREAL: $pass passed, $fail failed"; exit 1; }
wlog_n() { grep -ac 'broker exchange refused' "$D/web.log"; }
wlog_last() { grep -a 'broker exchange refused' "$D/web.log" | tail -1 | sed 's/^firnchat-web: oidc broker exchange refused: //'; }

# tokens for the cases (every swap gets its OWN token: the address book takes a token once)
mint unk orientos-device; mint fgn orientos-device; mint wrg other-device; mint ctl orientos-device; mint rep orientos-device
python3 - "$(cat "$TMPD/mint/fgn.access")" > "$TMPD/jw/foreign" <<'PY'
import base64, sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
h, p, _ = sys.argv[1].split(".")
sig = Ed25519PrivateKey.generate().sign((h + "." + p).encode())
print(h + "." + p + "." + base64.urlsafe_b64encode(sig).rstrip(b"=").decode(), end="")
PY
is "the wrong-audience token is a real token of the other client (aud)" "$(jwtc "$(cat "$TMPD/mint/wrg.access")" aud)" "other-product"
is "the good tokens have aud orientos" "$(jwtc "$(cat "$TMPD/mint/ctl.access")" aud)" "orientos"
UIDC=$(jwtc "$(cat "$TMPD/mint/ctl.access")" uid)
is "the access token carries the account id (uid)" "$UIDC" "u_FAKEjustin01"

# ======================================================================
echo "== 2. no account yet: the swap refuses (it never creates one) =="
# ======================================================================
cp "$TMPD/mint/unk.access" "$TMPD/jw/unk"
ABB_EXTRA=(/tmp/ "/etc/social/fleitec.conf=$TMPD/fl.conf" "/tmp/ju=$TMPD/jw/unk")
abbild "$TMPD/pre.img" || { echo "ANBREAL: $pass passed, $fail failed"; exit 1; }
ABB_EXTRA=()
N0=$(wlog_n)
lauf "$TMPD/pre.img" "socfleitec v1 login broker -f /tmp/ju;cat /etc/social/fleitec.conf" "$TMPD/o_pre.txt"
is "unknown account: the guest sees 'denied'" "$(grep -a '^err' "$TMPD/o_pre.txt" | head -1 | cut -f1,2)" "$(printf 'err\tdenied')"
num "unknown account: firnchat-web logged one refusal" "$(( $(wlog_n) - N0 ))" eq 1
case "$(wlog_last)" in *"[no account]"*) ok "unknown account: reason at firnchat-web is [no account]" ;; *) bad "unknown account: reason '$(wlog_last)'" ;; esac
num "unknown account: no token= in the configuration" "$(grep -ac '^token=' "$TMPD/o_pre.txt")" eq 0

# ======================================================================
echo "== 3. the person signs in at firnchat-web (creates the account) =="
# ======================================================================
WL=$(ip netns exec "$NS" python3 -I tools/anbfleitec/weblogin.py "http://127.0.0.1:$WPORT" "$Z" "$TMPD/certs/ca.pem" 2>&1)
is "browser login through the https broker" "$WL" "ok"

# ======================================================================
echo "== 4. the guest signs in (device flow) and swaps for a fkt1 =="
# ======================================================================
abbild "$TMPD/base.img" || { echo "ANBREAL: $pass passed, $fail failed"; exit 1; }
: > "$TMPD/w/s2c.log"
cp "$TMPD/base.img" "$TMPD/d_in.img"
run_wait "$TMPD/d_in.img" "$TMPD/o_in.txt" allow
is "device sign-in at the broker (konto)" "$(kv "$TMPD/o_in.txt" stand)" "ok"
ST=$(wire_tokens access_token | head -1)
IDT=$(wire_tokens id_token | head -1)
is "the guest's access token carries the same account" "$(jwtc "$ST" uid)" "$UIDC"
printf '%s\n' "$ST" > "$TMPD/jw/good"; printf '%s\n' "$IDT" > "$TMPD/jw/idt"
cp "$TMPD/mint/wrg.access" "$TMPD/jw/wrong"; cp "$TMPD/mint/expd.access" "$TMPD/jw/expired"
printf '%s\n' "$(cat "$TMPD/mint/ctl.access")" > "$TMPD/jw/ctl"; printf '%s\n' "$(cat "$TMPD/mint/rep.access")" > "$TMPD/jw/rep"
printf 'not-a-token' > "$TMPD/jw/junk"
ABB_EXTRA=(/tmp/ "/etc/social/fleitec.conf=$TMPD/fl.conf" "/tmp/jg=$TMPD/jw/good" "/tmp/jf=$TMPD/jw/foreign" \
    "/tmp/ji=$TMPD/jw/idt" "/tmp/jw=$TMPD/jw/wrong" "/tmp/je=$TMPD/jw/expired" "/tmp/jc=$TMPD/jw/ctl" \
    "/tmp/jr=$TMPD/jw/rep" "/tmp/jj=$TMPD/jw/junk")
abbild "$TMPD/soc_base.img" || { echo "ANBREAL: $pass passed, $fail failed"; exit 1; }
ABB_EXTRA=()
cp "$TMPD/soc_base.img" "$TMPD/d_soc.img"
N0=$(wlog_n)
lauf "$TMPD/d_soc.img" "socfleitec v1 hello;socfleitec v1 login broker -f /tmp/jg;socfleitec v1 contacts;socfleitec v1 login broker -f /tmp/jf;socfleitec v1 contacts;socfleitec v1 login broker abc;socfleitec v1 login broker -f /tmp/jj;socfleitec v1 login broker -f /tmp/nothere;cat /etc/social/fleitec.conf" "$TMPD/o_soc1.txt"
grep -aq "^account.$UIDC" "$TMPD/o_soc1.txt" && ok "swap: socfleitec reports account $UIDC" || bad "swap: no 'account $UIDC' line: $(grep -a '^err\|^account' "$TMPD/o_soc1.txt" | head -3)"
FKT=$(grep -aoE "^token=fkt1\.[A-Za-z0-9_]+\.[0-9a-f]{64}" "$TMPD/o_soc1.txt" | tail -1 | sed 's/^token=//' | tr -d '\r')
echo "$FKT" | grep -qE "^fkt1\.$UIDC\.[0-9a-f]{64}$" && ok "the REAL address book issued fkt1.<uid>.<64 hex> (the only token in the configuration)" || bad "no fkt1 in the configuration: '$FKT'"
num "contacts answered ok before and after a refused token" "$(grep -ac '^ok' "$TMPD/o_soc1.txt")" ge 3
num "refused tokens (foreign signature, garbage, missing file) leave the fkt1 in place" "$(grep -ac '^err.\(denied\|bad\)' "$TMPD/o_soc1.txt")" eq 4
num "firnchat-web refused exactly the foreign signature (2 other inputs never left the guest)" "$(( $(wlog_n) - N0 ))" eq 1
num "the JWT never shows in the output" "$(grep -acF "${ST%%.*}" "$TMPD/o_soc1.txt")" eq 0
H0=$(grep -aoF -- "$ST" "$TMPD/soc_base.img" | wc -l); H1=$(grep -aoF -- "$ST" "$TMPD/d_soc.img" | wc -l)
is "the JWT is on the image once (the input file); the run adds no copy" "$H1" "$H0"
# the fkt1 on the host, through the same path as a device (TLS terminator, path routing)
if [ -n "$FKT" ]; then
    S1=$(hcurl -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $FKT" https://konto.test:8443/api/kontakte/profil)
    is "host: the fkt1 opens the book (GET /api/kontakte/profil)" "$S1" "200"
    S2=$(hcurl -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $FKT" -H 'Content-Type: application/json' -d '{"name":"Hacker"}' https://konto.test:8443/api/kontakte/profil)
    is "host: the device fkt1 may not change the profile" "$S2" "403"
fi

# ======================================================================
echo "== 5. refusals by the REAL check (each from a clean configuration) =="
# ======================================================================
refuse() { # <label> <token file in the image> <reason the real check names>
    cp "$TMPD/soc_base.img" "$TMPD/d_socn.img"
    local n0; n0=$(wlog_n)
    lauf "$TMPD/d_socn.img" "socfleitec v1 login broker -f $2;socfleitec v1 contacts;cat /etc/social/fleitec.conf" "$TMPD/o_socn.txt"
    is "$1: refused" "$(grep -a '^err' "$TMPD/o_socn.txt" | head -1 | cut -f1,2)" "$(printf 'err\tdenied')"
    num "$1: firnchat-web logged one refusal" "$(( $(wlog_n) - n0 ))" eq 1
    case "$(wlog_last)" in *"[$3]"*) ok "$1: the real check names the reason [$3]" ;; *) bad "$1: reason is '$(wlog_last)', expected [$3]" ;; esac
    num "$1: no token stored (contacts is 'denied' too)" "$(grep -ac '^err.denied' "$TMPD/o_socn.txt")" eq 2
    num "$1: no token= in the configuration" "$(grep -ac '^token=' "$TMPD/o_socn.txt")" eq 0
}
refuse "foreign signature" /tmp/jf sig
refuse "id_token of the broker" /tmp/ji aud
refuse "wrong audience (token of another client)" /tmp/jw aud
AGE=$(( $(date +%s) - T_EXP_AT ))
if [ "$AGE" -gt 70 ]; then ok "the 1 s token is $AGE s old (leeway is 60 s)"; else info "waiting for the 1 s token to be past the leeway"; sleep $(( 70 - AGE )); fi
refuse "expired" /tmp/je expired

# ======================================================================
echo "== 6. one token, one swap; a fresh one swaps again =="
# ======================================================================
cp "$TMPD/soc_base.img" "$TMPD/d_socc.img"
lauf "$TMPD/d_socc.img" "socfleitec v1 login broker -f /tmp/jc;socfleitec v1 contacts" "$TMPD/o_socc.txt"
grep -aq '^ok' "$TMPD/o_socc.txt" && ok "control: a fresh good token swaps (after all those refusals)" || bad "control: swap failed: $(grep -a '^err' "$TMPD/o_socc.txt" | head -1)"
cp "$TMPD/soc_base.img" "$TMPD/d_socr.img"
lauf "$TMPD/d_socr.img" "socfleitec v1 login broker -f /tmp/jr;socfleitec v1 login broker -f /tmp/jr;socfleitec v1 contacts;cat /etc/social/fleitec.conf" "$TMPD/o_socr.txt"
R1=$(grep -a '^\(ok\|err\)' "$TMPD/o_socr.txt" | sed -n 1p | cut -f1,2); R2=$(grep -a '^\(ok\|err\)' "$TMPD/o_socr.txt" | sed -n 2p | cut -f1,2)
is "first swap of a token works" "$R1" "ok"
is "the SAME token again is refused (one swap per jti)" "$R2" "$(printf 'err\tdenied')"
num "the fkt1 of the first swap is still in place (contacts ok)" "$(grep -ac '^ok' "$TMPD/o_socr.txt")" ge 2
num "exactly one fkt1 in the configuration" "$(grep -ac '^token=fkt1' "$TMPD/o_socr.txt")" eq 1

# ======================================================================
echo "== 7. guard of the swap: block list, brake, audit (host side, the same path as a device) =="
# ======================================================================
HS_CODE=""
hswap() { # <token> -> HS_CODE, body in $TMPD/hs.out, headers in $TMPD/hs.hdr
    HS_CODE=$(hcurl -o "$TMPD/hs.out" -D "$TMPD/hs.hdr" -w '%{http_code}' -X POST -H "Authorization: Bearer $1" \
        -H 'Content-Type: application/json' -d '{}' https://konto.test:8443/api/kontakte/zugang-broker)
}
BL="$D/denylist.txt"
mint blk orientos-device; B1=$(cat "$TMPD/mint/blk.access"); J1=$(jwtc "$B1" jti)
echo "jti $J1" > "$BL"
hswap "$B1"; is "block list: a token whose jti is listed -> 403" "$HS_CODE" "403"
echo "# unblocked" > "$BL"
hswap "$B1"; is "block list: removed from the file -> the SAME token swaps (taking effect without a restart; the block did not consume it)" "$HS_CODE" "200"
hswap "$B1"; is "the same token again -> 401 (token already used)" "$HS_CODE" "401"
mint blk2 orientos-device; B2=$(cat "$TMPD/mint/blk2.access"); J2=$(jwtc "$B2" jti)
echo "account $UIDC" > "$BL"
hswap "$B2"; is "block list: the whole account (konto <uid>) -> 403" "$HS_CODE" "403"
echo "# unblocked" > "$BL"
hswap "$B2"; is "block list: account released -> swaps" "$HS_CODE" "200"
# brake: garbage first (cheap, before the token is even looked at), then a VALID token while braked
mint brk orientos-device; B3=$(cat "$TMPD/mint/brk.access"); J3=$(jwtc "$B3" jti)
CODES=""
for i in $(seq 1 45); do
    CODES="$CODES $(hcurl -o /dev/null -D "$TMPD/hs$i.hdr" -w '%{http_code}' -X POST -H 'Authorization: Bearer junk' -H 'Content-Type: application/json' -d '{}' https://konto.test:8443/api/kontakte/zugang-broker)"
done
N429=$(printf '%s\n' $CODES | grep -c '^429$'); N401=$(printf '%s\n' $CODES | grep -c '^401$')
num "brake: garbage burst of 45 -> the first ones are 401 (refused token)" "$N401" ge 1
num "brake: ... and from the limit on 429" "$N429" ge 1
RA=$(grep -ail '^retry-after' "$TMPD"/hs*.hdr 2>/dev/null | head -1)
[ -n "$RA" ] && ok "brake: 429 carries Retry-After ($(grep -ai '^retry-after' "$RA" | tr -d '\r'))" || bad "brake: no Retry-After header"
hswap "$B3"; is "brake: even a VALID token is braked (429)" "$HS_CODE" "429"
RAV=$(grep -ai '^retry-after' "$TMPD/hs.hdr" | head -1 | tr -dc '0-9'); [ -z "$RAV" ] && RAV=60
sleep $(( RAV + 2 ))
hswap "$B3"; is "brake: after the window the same token swaps (429 consumed nothing)" "$HS_CODE" "200"
# audit file: append-only, no token in it
AU="$D/audit.log"
num "audit: swap lines (guest: 3 tokens, host: 3 tokens)" "$(grep -ac ' swap ' "$AU")" eq 6
num "audit: deny replay (guest 1, host 1)" "$(grep -ac ' deny replay ' "$AU")" eq 2
num "audit: deny blocked (jti, konto)" "$(grep -ac ' deny blocked ' "$AU")" eq 2
num "audit: the jti of a blocked token and its swap are both there" "$(grep -acF "$J1" "$AU")" eq 3
num "audit: no token (no signature segment of any token) in the file" "$(grep -acF "${B1##*.}" "$AU")" eq 0
num "firnchat-web's log holds no token either" "$(grep -acF "${B1##*.}" "$D/web.log")" eq 0

echo "ANBREAL: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
