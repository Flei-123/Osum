#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/anbfleitec/run.sh -- Fleitec-ID backend (device flow), MEASURED.
#
# WHAT THIS CHECKS
#  0. The copies kernel/app/{kbig,ksha512,ked25519}.fi are current
#     (tools/anbfleitec/mkcopies.sh --check).
#  1. Programs build (--profile=app, no undefined symbol).
#  2. JWT: all cases of docs/fleitec-id/vectors_v2.json (group jwt_eddsa)
#     run through kernel/app/kjwt.fi IN THE GUEST; every reason must equal
#     the `expect` column. Counter-probe: the comparator fails on a
#     doctored output.
#  3. Device flow against a mock IdP over TLS 1.3 (tools/anbfleitec/idp.py):
#     start (code/url) -> pending -> approved; slow_down (+5 s, measured on
#     the HOST clock); denied; expired code; and nine defective tokens
#     (wrong iss, wrong aud, HS256 key confusion, alg none, expired,
#     flipped signature, unknown kid, id_token naming another subject,
#     rotation without a new refresh token). Each refused case leaves NO
#     account and NO session on the disk.
#  4. Tokens never in clear on the disk (access + refresh searched in the
#     whole image). Counter-probe --kaputt=klartext: the access token MUST
#     be found.
#  5. Refresh rotation: the new refresh token differs; replaying the old
#     one is refused and kills the family (the server side of it is the
#     mock; the device side is: a dead refresh token ends the session
#     cleanly, the account entry stays).
#  6. Sign-out: /oidc/revoke is called, the refresh token is dead after it,
#     the session file is gone.
#  7. NO NETWORK: a signed-in device stays signed in and usable.
#  8. Counter-probe on the verifier settings: a valid token with another
#     --aud is refused (so the audience check is live).
#  9. (r34) ziel= with a DNS NAME (https://konto.test:8443): resolved in the
#     guest through /etc/resolv.conf (dnsdienst.py in the namespace); full
#     device flow, ONE query per run (cache), Host header = the name, the
#     certificate is checked against the NAME (other.test -> same server ->
#     refused), NXDOMAIN / DNS server down -> keinnetz in bounded time with no
#     request at the broker, a broken number (10.9.0) is refused without DNS.
#
# Usage: bash tools/anbfleitec/run.sh      (heavy: ~25 guest boots)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hin() { printf '  --    %s\n' "$1"; }
is()  { if [ "${2:-}" = "$3" ]; then ok "$1: $2"; else bad "$1: '${2:-}', expected '$3'"; fi; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
num() { local n=$1 v=${2:-} o=$3 w=$4
    if [ -z "$v" ]; then bad "$n: no number (expected $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, expected $o $w"; fi
}
kv() { grep -aoE "^konto: $2 = .*" "$1" 2>/dev/null | tail -1 | sed 's/^konto: [a-z_]* = //' | tr -d '\r'; }
kv1() { grep -aoE "^konto: $2 = .*" "$1" 2>/dev/null | head -1 | sed 's/^konto: [a-z_]* = //' | tr -d '\r'; }
msg() { grep -a "^$1 = " locale/de/messages | head -1 | sed 's/^[^=]*= //'; }

for t in qemu-system-x86_64 python3 openssl ip curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "ANBFLEITEC: skipped, $t missing"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "ANBFLEITEC: skipped, python3-cryptography missing"; exit 0; }

TMPD=$(mktemp -d)
NS=anbf-$$
V0=af0-$$
V1=af1
BPORT=$(( 16000 + ($$ % 300) * 2 ))
QPORT=$(( BPORT + 1 ))
SRVPID=""
BRPID=""
DNSPID=""
cleanup() {
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    [ -n "$DNSPID" ] && kill "$DNSPID" 2>/dev/null
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    [ -z "${KEEP_TMPD:-}" ] && rm -rf "$TMPD"
    [ -n "${KEEP_TMPD:-}" ] && echo "TMPD=$TMPD"
}
trap cleanup EXIT

ip netns del "$NS" 2>/dev/null
ip netns add "$NS" 2>/dev/null || { echo "ANBFLEITEC: skipped, no network namespaces"; exit 0; }
ip netns del "$NS" 2>/dev/null

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

# ======================================================================
echo "== 0. copies of the crypto modules are current =="
# ======================================================================
if bash tools/anbfleitec/mkcopies.sh --check > "$TMPD/copies.txt" 2>&1; then
    ok "kbig/ksha512/ked25519 equal lib/crypto/{big,sha512,ed25519} (modulo names)"
else
    bad "stale copy: $(cat "$TMPD/copies.txt")"
fi

# ======================================================================
echo "== 1. programs build =="
# ======================================================================
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
build() { # <src> <name>
    if ! "$FIRNC" -c --profile=app -o "$TMPD/$2.o" "$1" > "$TMPD/cc_$2.log" 2>&1; then
        bad "$1 does not compile"; head -12 "$TMPD/cc_$2.log" | sed 's/^/        /'
        return 1
    fi
    local undef
    undef=$(nm -u "$TMPD/$2.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$undef" ] && ok "$1: compiles, no undefined symbol" || { bad "$1 undefined: $undef"; return 1; }
    ld -T kernel/user/user.ld -o "$TMPD/$2.elf" "$TMPD/$2.o" 2>"$TMPD/ld_$2.err" \
        && ok "$1: ld with kernel/user/user.ld" \
        || { bad "$1: ld fails"; head -3 "$TMPD/ld_$2.err"; return 1; }
    strip --strip-all "$TMPD/$2.elf" 2>/dev/null
    return 0
}
# jwtvec.fi imports the app modules by bare name: compile it next to them.
mkdir -p "$TMPD/stage"
cp kernel/app/*.fi "$TMPD/stage/"
cp tools/anbfleitec/jwtvec.fi "$TMPD/stage/jwtvec.fi"
build kernel/app/account.fi konto || { echo "ANBFLEITEC: $pass passed, $fail failed"; exit 1; }
build "$TMPD/stage/jwtvec.fi" jwtvec || { echo "ANBFLEITEC: $pass passed, $fail failed"; exit 1; }
num "konto program size (octets)" "$(stat -c%s "$TMPD/konto.elf")" le 2500000

HWNET_PROGS="sh ls cat echo" bash tools/hwnet/build.sh "$TMPD/s0" 0 \
    > "$TMPD/b0.txt" 2>&1 \
    || { bad "kernel does not build"; tail -8 "$TMPD/b0.txt" | sed 's/^/        /'
         echo "ANBFLEITEC: $pass passed, $fail failed"; exit 1; }
ok "kernel and userland built"
K="$TMPD/s0/k.mb"
python3 tools/hwnet/mkcerts.py "$TMPD/certs" konto.test > "$TMPD/certs.txt" 2>&1 \
    && ok "test certificates from python cryptography" || bad "mkcerts.py failed"
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c"

printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'lang=de\n' > "$TMPD/locale.conf"
Z="https://10.9.0.1:8443"
printf 'fleitec ziel=%s name=konto.test\n' "$Z" > "$TMPD/konten.conf"

# vectors -> TSV + JWKS for the guest
python3 - "$TMPD" <<'PY'
import json, sys
d = sys.argv[1]
v = json.load(open("/root/jarvis/docs/fleitec-id/vectors_v2.json", encoding="utf-8"))
g = v["jwt_eddsa"]
open(d + "/jwks.json", "w").write(json.dumps(g["verifier"]["jwks"]))
with open(d + "/vec.tsv", "w") as f:
    for c in g["cases"]:
        f.write("%s\t%d\t%s\n" % (c["id"], c["now"], c["token"]))
json.dump({c["id"]: c["expect"] for c in g["cases"]}, open(d + "/expect.json", "w"))
print(len(g["cases"]))
PY

abbild() { # <target> [extra mkfs args...]
    local t=$1; shift
    python3 tools/osum/mkfs.py build "$t" 24576 \
        /bin/ /etc/ /etc/ssl/ /usr/ /usr/share/ /usr/share/locale/ \
        /usr/share/locale/en/ /usr/share/locale/de/ \
        /users/ /users/justin/ /users/justin/config/ \
        "/bin/sh=$TMPD/s0/sh.elf" "/bin/ls=$TMPD/s0/ls.elf" \
        "/bin/cat=$TMPD/s0/cat.elf" "/bin/echo=$TMPD/s0/echo.elf" \
        "/bin/konto=$TMPD/konto.elf" "/bin/jwtvec=$TMPD/jwtvec.elf" \
        "/etc/ssl/roots.pem=$TMPD/certs/ca.pem" \
        "/etc/passwd=$TMPD/passwd" "/etc/locale.conf=$TMPD/locale.conf" \
        "/etc/konten.conf=$TMPD/konten.conf" \
        "/vec.tsv=$TMPD/vec.tsv" "/jwks.json=$TMPD/jwks.json" \
        "/usr/share/locale/en/messages=$ROOT/locale/en/messages" \
        "/usr/share/locale/de/messages=$ROOT/locale/de/messages" "$@" \
        > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs: $(tail -2 "$TMPD/mkfs.txt")"; return 1; }
    return 0
}

netz_auf() {
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
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
    sleep 0.4
}
netz_zu() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; BRPID=""
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
}
mkdir -p "$TMPD/idp"
server_auf() {
    ip netns exec "$NS" python3 tools/anbfleitec/idp.py --port 8443 \
        --zertifikat "$TMPD/certs/good.pem" --schluessel "$TMPD/certs/good.key" \
        --verzeichnis "$TMPD/idp" --issuer "$Z" "$@" > "$TMPD/srv.log" 2>&1 & SRVPID=$!
    sleep 1.0
}
server_zu() { [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; SRVPID=""; }

lauf() { # <image> <script> <out>
    timeout 200 qemu-system-x86_64 -kernel "$K" -m 512 \
        -append "osum nokbd nosched noproc nofs noring3 nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0 script=$2;exit" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$1,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
lauf_ohne_netz() { # <image> <script> <out>
    timeout 200 qemu-system-x86_64 -kernel "$K" -m 512 \
        -append "osum nokbd nosched noproc nofs noring3 script=$2;exit" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$1,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

# ======================================================================
echo "== 2. JWT: every case of vectors_v2.json, in the guest =="
# ======================================================================
abbild "$TMPD/dj.img" || true
lauf_ohne_netz "$TMPD/dj.img" "jwtvec" "$TMPD/o_jwt.txt"
cmp_jwt() { # <out file> -> prints "cases=N bad=M" and the mismatches
    python3 - "$1" "$TMPD/expect.json" <<'PY'
import json, re, sys
exp = json.load(open(sys.argv[2]))
got = {}
for z in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = re.match(r"^jwt: (\S+) = (\S+)\s*$", z)
    if m and m.group(1) != "done":
        got[m.group(1)] = m.group(2)
bad = [(k, exp[k], got.get(k)) for k in exp if got.get(k) != exp[k]]
for k, e, g in bad:
    print("MISMATCH %s expected=%s got=%s" % (k, e, g))
print("cases=%d got=%d bad=%d" % (len(exp), len(got), len(bad)))
PY
}
cmp_jwt "$TMPD/o_jwt.txt" > "$TMPD/jwt_cmp.txt"
grep MISMATCH "$TMPD/jwt_cmp.txt" | sed 's/^/        /'
is "vector cases run" "$(grep -oE 'got=[0-9]+' "$TMPD/jwt_cmp.txt" | cut -d= -f2)" "34"
is "vector cases with a wrong reason" "$(grep -oE 'bad=[0-9]+' "$TMPD/jwt_cmp.txt" | cut -d= -f2)" "0"
has "$TMPD/o_jwt.txt" "jwt: done" "the guest program ran to the end"
# counter-probe: a doctored output must be caught
sed 's/^jwt: good_key_a = ok/jwt: good_key_a = sig/' "$TMPD/o_jwt.txt" > "$TMPD/o_jwt_x.txt"
cmp_jwt "$TMPD/o_jwt_x.txt" > "$TMPD/jwt_cmp2.txt"
num "counter-probe: doctored output is caught" "$(grep -oE 'bad=[0-9]+' "$TMPD/jwt_cmp2.txt" | cut -d= -f2)" ge 1

# ======================================================================
echo "== 3. device flow against the mock IdP (TLS 1.3) =="
# ======================================================================
netz_auf
server_auf
abbild "$TMPD/base.img" || true
CMD="konto anmelden --anbieter=fleitec --device --wait"
scen() { printf '%s\n' "$1" > "$TMPD/idp/szenario"; }

# 3a: the two manual steps (what the settings dialog does)
scen approve
lauf "$TMPD/base.img" "konto anmelden --anbieter=fleitec --device" "$TMPD/o_s1.txt"
is "step 1: state" "$(kv "$TMPD/o_s1.txt" stand)" "device"
is "step 1: user code" "$(kv "$TMPD/o_s1.txt" code)" "ABCD-EFGH"
has "$TMPD/o_s1.txt" "konto: url = https://10.9.0.1:8443/device" "step 1: the URL is shown"
has "$TMPD/o_s1.txt" "konto: url_complete = " "step 1: the complete URL is shown"
DC=$(kv "$TMPD/o_s1.txt" zwischen)
case "$DC" in dc-approve-*) ok "step 1: device code kept for step 2 ($DC)";; *) bad "step 1: no device code ('$DC')";; esac
is "step 1: interval" "$(kv "$TMPD/o_s1.txt" interval)" "1"
lauf "$TMPD/base.img" "konto anmelden --anbieter=fleitec --geraet --zwischen=$DC" "$TMPD/o_s2.txt"
is "step 2 (first poll, OLD flags --geraet --zwischen): still waiting" "$(kv "$TMPD/o_s2.txt" stand)" "device"
lauf "$TMPD/base.img" "konto liste" "$TMPD/o_s3.txt"
is "nothing signed in after a pending answer" "$(kv "$TMPD/o_s3.txt" konten)" "0"

# 3b: approve (pending twice, then tokens), the wait loop in the guest
scen approve
cp "$TMPD/base.img" "$TMPD/d_login.img"
lauf "$TMPD/d_login.img" "$CMD" "$TMPD/o_ok.txt"
is "approve: state" "$(kv "$TMPD/o_ok.txt" stand)" "ok"
is "approve: polls" "$(kv "$TMPD/o_ok.txt" polls)" "3"
is "approve: sealed" "$(kv "$TMPD/o_ok.txt" gesiegelt)" "1"
is "approve: subject" "$(kv "$TMPD/o_ok.txt" subjekt)" "0b6f1c1e-5a7e-4d2c-9a4b-2f1d3c4b5a69"
is "approve: display name" "$(kv "$TMPD/o_ok.txt" anzeige)" "Justin"
KEN=$(kv "$TMPD/o_ok.txt" kennung)
[ -n "$KEN" ] && ok "approve: account id $KEN" || bad "approve: no account id"
num "approve: expiry (unix, from the token)" "$(kv "$TMPD/o_ok.txt" ablauf)" gt 1700000000

# the wire: form bodies, no cookies, no Authorization on the token calls
python3 - "$TMPD/idp/protokoll.jsonl" > "$TMPD/wire.txt" <<'PY'
import json, sys
n_dev = n_tok = bad_ct = cookie = auth_tok = 0
for z in open(sys.argv[1], encoding="utf-8"):
    e = json.loads(z)
    k = e["kopfzeilen"]
    if "cookie" in k:
        cookie += 1
    if e["pfad"] == "/oidc/device_authorization":
        n_dev += 1
    if e["pfad"] == "/oidc/token":
        n_tok += 1
        if "authorization" in k:
            auth_tok += 1
    if e["metode"] == "POST" and not k.get("content-type", "").startswith("application/x-www-form-urlencoded"):
        bad_ct += 1
print("dev=%d tok=%d badct=%d cookie=%d authtok=%d" % (n_dev, n_tok, bad_ct, cookie, auth_tok))
PY
cat "$TMPD/wire.txt" | sed 's/^/        /'
is "wire: POSTs that are not form-encoded" "$(grep -oE 'badct=[0-9]+' "$TMPD/wire.txt" | cut -d= -f2)" "0"
is "wire: requests with a cookie" "$(grep -oE 'cookie=[0-9]+' "$TMPD/wire.txt" | cut -d= -f2)" "0"
is "wire: token calls with Authorization" "$(grep -oE 'authtok=[0-9]+' "$TMPD/wire.txt" | cut -d= -f2)" "0"

# 3c: slow_down: +5 s, measured on the host clock
scen slowdown
cp "$TMPD/base.img" "$TMPD/d_slow.img"
: > "$TMPD/idp/protokoll.jsonl"
lauf "$TMPD/d_slow.img" "$CMD" "$TMPD/o_slow.txt"
is "slow_down: state" "$(kv "$TMPD/o_slow.txt" stand)" "ok"
is "slow_down: final interval (1 + 5)" "$(kv "$TMPD/o_slow.txt" interval)" "6"
python3 - "$TMPD/idp/protokoll.jsonl" > "$TMPD/gap.txt" <<'PY'
import json, sys
ts = []
for z in open(sys.argv[1], encoding="utf-8"):
    e = json.loads(z)
    if e["pfad"] == "/oidc/token":
        ts.append(e["t"])
gaps = [round(b - a, 1) for a, b in zip(ts, ts[1:])]
print("polls=%d gap_after_slowdown=%s" % (len(ts), gaps[0] if gaps else -1))
PY
cat "$TMPD/gap.txt" | sed 's/^/        /'
GAP=$(grep -oE 'gap_after_slowdown=[0-9.]+' "$TMPD/gap.txt" | cut -d= -f2)
python3 -c "import sys; sys.exit(0 if float('${GAP:-0}') >= 5.5 else 1)" \
    && ok "slow_down: the next poll came >= 5.5 s later ($GAP s)" \
    || bad "slow_down: the next poll came after $GAP s"

# 3d: denied, expired code
check_refused() { # <scenario> <state> <hint key> <label>
    scen "$1"
    cp "$TMPD/base.img" "$TMPD/d_$1.img"
    lauf "$TMPD/d_$1.img" "$CMD" "$TMPD/o_$1.txt"
    is "$4: state" "$(kv "$TMPD/o_$1.txt" stand)" "$2"
    local want; want=$(msg "$3")
    is "$4: hint text ($3)" "$(kv "$TMPD/o_$1.txt" hinweis)" "$want"
    lauf "$TMPD/d_$1.img" "konto liste" "$TMPD/o_$1_l.txt"
    is "$4: accounts on the device" "$(kv "$TMPD/o_$1_l.txt" konten)" "0"
    python3 tools/osum/mkfs.py where "$TMPD/d_$1.img" "/state/session/konto" > "$TMPD/wo_$1.txt" 2>&1
    if grep -qa "no such path" "$TMPD/wo_$1.txt"; then ok "$4: no session directory on the disk"
    else
        # the directory may exist but must hold no file
        N=$(python3 tools/osum/mkfs.py ls "$TMPD/d_$1.img" "/state/session/konto" 2>/dev/null | grep -vc '^$' || true)
        is "$4: session files on the disk" "${N:-0}" "0"
    fi
}
check_refused deny abgelehnt konto.hint.dev_denied "denied on the other device"
check_refused expired abgelaufen konto.hint.dev_expired "expired device code"

# 3e: defective tokens
check_refused bad_iss abgelehnt konto.hint.jwt_iss "wrong issuer"
check_refused bad_aud abgelehnt konto.hint.jwt_aud "wrong audience"
check_refused hs256 abgelehnt konto.hint.jwt_alg "HS256 with the public key (key confusion)"
check_refused algnone abgelehnt konto.hint.jwt_alg "alg none"
check_refused exp_old abgelehnt konto.hint.jwt_expired "expired token"
check_refused bad_sig abgelehnt konto.hint.jwt_sig "flipped signature bit"
check_refused bad_kid abgelehnt konto.hint.jwt_kid "unknown kid"
check_refused id_other abgelehnt konto.hint.jwt_subject "id_token names another subject"

# 3f: counter-probe: the SAME valid token with another audience on the device
scen approve
cp "$TMPD/base.img" "$TMPD/d_aud.img"
lauf "$TMPD/d_aud.img" "$CMD --aud=another-product" "$TMPD/o_aud.txt"
is "counter-probe: valid token, other --aud: state" "$(kv "$TMPD/o_aud.txt" stand)" "abgelehnt"
is "counter-probe: hint" "$(kv "$TMPD/o_aud.txt" hinweis)" "$(msg konto.hint.jwt_aud)"

# ======================================================================
echo "== 4. tokens never in clear on the disk =="
# ======================================================================
# d_login.img is the approved sign-in of 3b. access.txt/refresh.txt hold
# every token the mock ever issued (also those of refused cases).
: > "$TMPD/hits.txt"
HITS=0; NTOK=0
for f in access.txt refresh.txt; do
    while IFS= read -r t; do
        [ -z "$t" ] && continue
        NTOK=$((NTOK+1))
        c=$(grep -c -aF -- "$t" "$TMPD/d_login.img" 2>/dev/null || true)
        HITS=$((HITS+${c:-0}))
    done < "$TMPD/idp/$f"
done
num "tokens issued by the mock (searched)" "$NTOK" ge 10
is "hits of any issued token in the disk image" "$HITS" "0"
python3 tools/osum/mkfs.py where "$TMPD/d_login.img" "/state/session/konto/$KEN" > "$TMPD/wo.txt" 2>&1
grep -qa "^where " "$TMPD/wo.txt" && ok "the session file exists: $(cat "$TMPD/wo.txt")" \
    || bad "no session file: $(cat "$TMPD/wo.txt")"
python3 tools/osum/mkfs.py cat "$TMPD/d_login.img" "/state/session/konto/$KEN" > "$TMPD/seal.bin" 2>/dev/null
head -c4 "$TMPD/seal.bin" | grep -qa "OKS1" && ok "and it is SEALED (head OKS1)" || bad "the session file carries no seal"

# counter-probe: clear text variant
scen approve
cp "$TMPD/base.img" "$TMPD/d_kl.img"
: > "$TMPD/idp/access.txt"
lauf "$TMPD/d_kl.img" "konto --kaputt=klartext anmelden --anbieter=fleitec --device --wait" "$TMPD/o_kl.txt"
is "counter-probe klartext: signed in" "$(kv "$TMPD/o_kl.txt" stand)" "ok"
KT=$(tail -1 "$TMPD/idp/access.txt")
KH=$(grep -c -aF -- "$KT" "$TMPD/d_kl.img" 2>/dev/null || true)
num "counter-probe klartext: the access token IS found in the image" "${KH:-0}" ge 1
ok "  (so section 4 measures the seal and not the void)"

# ======================================================================
echo "== 5. refresh rotation =="
# ======================================================================
: > "$TMPD/idp/refresh.txt"
# a fresh login on the copy so refresh.txt starts with the family
scen approve
cp "$TMPD/base.img" "$TMPD/d_ref.img"
lauf "$TMPD/d_ref.img" "$CMD" "$TMPD/o_r0.txt"
RKEN=$(kv "$TMPD/o_r0.txt" kennung)
R1=$(sed -n 1p "$TMPD/idp/refresh.txt")
lauf "$TMPD/d_ref.img" "konto erneuern --kennung=$RKEN" "$TMPD/o_r1.txt"
is "renew: renewed" "$(kv "$TMPD/o_r1.txt" erneuert)" "1"
is "renew: state" "$(kv "$TMPD/o_r1.txt" stand)" "ok"
R2=$(sed -n 2p "$TMPD/idp/refresh.txt")
if [ -n "$R1" ] && [ -n "$R2" ] && [ "$R1" != "$R2" ]; then ok "the refresh token rotated (new one differs)"
else bad "refresh token did not rotate ('$R1' / '$R2')"; fi
replay() { # <refresh token> -> HTTP status
    ip netns exec "$NS" curl -s -o /dev/null -w '%{http_code}' \
        --cacert "$TMPD/certs/ca.pem" --resolve konto.test:8443:10.9.0.1 \
        -d grant_type=refresh_token -d "refresh_token=$1" -d client_id=orientos-device \
        https://konto.test:8443/oidc/token
}
is "replay of the OLD refresh token" "$(replay "$R1")" "400"
is "after the replay the whole family is dead (new token too)" "$(replay "$R2")" "400"
# the device holds the (now dead) new token: the next renew ends the SESSION, not the account
lauf "$TMPD/d_ref.img" "konto erneuern --kennung=$RKEN" "$TMPD/o_r2.txt"
is "dead refresh token: renewed" "$(kv "$TMPD/o_r2.txt" erneuert)" "0"
is "dead refresh token: session ended cleanly" "$(kv "$TMPD/o_r2.txt" abgemeldet)" "1"
lauf "$TMPD/d_ref.img" "konto liste" "$TMPD/o_r3.txt"
is "dead refresh token: the account entry stays" "$(kv "$TMPD/o_r3.txt" konten)" "1"
# rotation without a new refresh token is refused
scen norefresh
cp "$TMPD/base.img" "$TMPD/d_nr.img"
lauf "$TMPD/d_nr.img" "$CMD" "$TMPD/o_nr0.txt"
NRK=$(kv "$TMPD/o_nr0.txt" kennung)
is "norefresh: first sign-in works" "$(kv "$TMPD/o_nr0.txt" stand)" "ok"
lauf "$TMPD/d_nr.img" "konto erneuern --kennung=$NRK" "$TMPD/o_nr1.txt"
is "norefresh: a rotation without a new refresh token is not accepted" "$(kv "$TMPD/o_nr1.txt" erneuert)" "0"
lauf "$TMPD/d_nr.img" "konto liste" "$TMPD/o_nr2.txt"
is "norefresh: the account entry stays" "$(kv "$TMPD/o_nr2.txt" konten)" "1"

# ======================================================================
echo "== 6. sign-out =="
# ======================================================================
scen approve
cp "$TMPD/base.img" "$TMPD/d_out.img"
: > "$TMPD/idp/refresh.txt"
lauf "$TMPD/d_out.img" "$CMD" "$TMPD/o_o0.txt"
OKEN=$(kv "$TMPD/o_o0.txt" kennung)
O1=$(sed -n 1p "$TMPD/idp/refresh.txt")
: > "$TMPD/idp/protokoll.jsonl"
lauf "$TMPD/d_out.img" "konto abmelden --kennung=$OKEN" "$TMPD/o_o1.txt"
is "sign-out: done" "$(kv "$TMPD/o_o1.txt" abgemeldet)" "1"
grep -q '"/oidc/revoke"' "$TMPD/idp/protokoll.jsonl" \
    && ok "sign-out: POST /oidc/revoke reached the service" || bad "sign-out: no revoke call"
is "sign-out: the refresh token is dead afterwards" "$(replay "$O1")" "400"
python3 tools/osum/mkfs.py where "$TMPD/d_out.img" "/state/session/konto/$OKEN" > "$TMPD/wo_o.txt" 2>&1
grep -qa "no such path" "$TMPD/wo_o.txt" && ok "sign-out: the session file is gone" \
    || bad "sign-out: the session file is still there"

# ======================================================================
echo "== 9. a NAME instead of a number in ziel= (r34: DNS in the guest) =="
# ======================================================================
# The issuer is now https://konto.test:8443. The guest gets the number only
# from a tiny DNS server in the namespace (tools/operation/dnsdienst.py,
# /etc/resolv.conf). The name stays the certificate name and the Host header.
server_zu
Z9="https://konto.test:8443"
server_auf --issuer "$Z9"
ip netns exec "$NS" python3 tools/operation/dnsdienst.py --port 53 --adresse 10.9.0.1 \
    --eintrag konto.test=10.9.0.1 --eintrag other.test=10.9.0.1 \
    --log "$TMPD/dns.log" > /dev/null 2>&1 & DNSPID=$!
sleep 0.8
printf 'nameserver 10.9.0.1\noptions timeout:1 attempts:1\n' > "$TMPD/resolv.conf"
cp "$TMPD/konten.conf" "$TMPD/konten.orig"
printf 'fleitec ziel=%s\n' "$Z9" > "$TMPD/konten.conf"
abbild "$TMPD/d_dns.img" "/etc/resolv.conf=$TMPD/resolv.conf" || true
dns_asked() { grep -c "^FRAGE $1 " "$TMPD/dns.log" 2>/dev/null || true; }

scen approve
: > "$TMPD/dns.log"; : > "$TMPD/idp/protokoll.jsonl"
lauf "$TMPD/d_dns.img" "$CMD" "$TMPD/o_d1.txt"
is "name target: full device flow signs in" "$(kv "$TMPD/o_d1.txt" stand)" "ok"
is "name target: the DNS was asked ONCE for the whole run (cache)" "$(dns_asked konto.test)" "1"
grep -q '"host": "konto.test"' "$TMPD/idp/protokoll.jsonl" \
    && ok "name target: the Host header carries the NAME" || bad "name target: Host header is not konto.test"
grep -q '"host": "10\.9\.0\.1' "$TMPD/idp/protokoll.jsonl" \
    && bad "name target: a request went out with the number as Host" || ok "name target: no request names the number"

# a name that resolves to the SAME server, but the certificate is for konto.test
printf 'fleitec ziel=https://other.test:8443\n' > "$TMPD/konten.conf"
abbild "$TMPD/d_dns2.img" "/etc/resolv.conf=$TMPD/resolv.conf" || true
: > "$TMPD/dns.log"
lauf "$TMPD/d_dns2.img" "$CMD" "$TMPD/o_d2.txt"
is "other name -> same number: certificate is checked against the NAME (refused)" "$(kv "$TMPD/o_d2.txt" stand)" "tls"
is "other name: the DNS was asked for other.test" "$(dns_asked other.test)" "1"

# a name the DNS does not know
printf 'fleitec ziel=https://gibtsnicht.test:8443\n' > "$TMPD/konten.conf"
abbild "$TMPD/d_dns3.img" "/etc/resolv.conf=$TMPD/resolv.conf" || true
: > "$TMPD/dns.log"; : > "$TMPD/idp/protokoll.jsonl"
lauf "$TMPD/d_dns3.img" "$CMD" "$TMPD/o_d3.txt"
is "unknown name (NXDOMAIN): state keinnetz" "$(kv "$TMPD/o_d3.txt" stand)" "keinnetz"
is "unknown name: the DNS was asked" "$(dns_asked gibtsnicht.test)" "1"
is "unknown name: no request reached the server" "$(grep -c . "$TMPD/idp/protokoll.jsonl")" "0"

# broken numbers are NOT names: refused before any DNS query
printf 'fleitec ziel=https://10.9.0:8443\n' > "$TMPD/konten.conf"
abbild "$TMPD/d_dns4.img" "/etc/resolv.conf=$TMPD/resolv.conf" || true
: > "$TMPD/dns.log"
lauf "$TMPD/d_dns4.img" "$CMD" "$TMPD/o_d4.txt"
is "broken number 10.9.0: not keinnetz (refused as a target)" "$(kv "$TMPD/o_d4.txt" stand)" "fehler"
is "broken number: no DNS query at all" "$(grep -c '^FRAGE' "$TMPD/dns.log" 2>/dev/null || true)" "0"

# DNS server gone: bounded wait, clear state, nothing reaches the broker
kill "$DNSPID" 2>/dev/null; wait "$DNSPID" 2>/dev/null; DNSPID=""
printf 'fleitec ziel=%s\n' "$Z9" > "$TMPD/konten.conf"
abbild "$TMPD/d_dns5.img" "/etc/resolv.conf=$TMPD/resolv.conf" || true
: > "$TMPD/idp/protokoll.jsonl"
T0=$(date +%s)
lauf "$TMPD/d_dns5.img" "$CMD" "$TMPD/o_d5.txt"
T1=$(date +%s)
is "DNS server down: state keinnetz" "$(kv "$TMPD/o_d5.txt" stand)" "keinnetz"
num "DNS server down: the guest gave up in bounded time (s, boot included)" "$((T1 - T0))" le 60
is "DNS server down: no request reached the broker" "$(grep -c . "$TMPD/idp/protokoll.jsonl")" "0"
cp "$TMPD/konten.orig" "$TMPD/konten.conf"

# ======================================================================
echo "== 7. NO NETWORK: signed in stays signed in =="
# ======================================================================
server_zu
netz_zu
lauf_ohne_netz "$TMPD/d_login.img" "konto status --ohne-netz --kennung=$KEN" "$TMPD/o_n1.txt"
is "offline (--ohne-netz): session still there" "$(kv "$TMPD/o_n1.txt" sitzung)" "1"
lauf_ohne_netz "$TMPD/d_login.img" "konto status --kennung=$KEN" "$TMPD/o_n2.txt"
is "offline: renewal due but no network: state" "$(kv "$TMPD/o_n2.txt" stand)" "ok"
is "offline: not renewed, and not signed out" "$(kv "$TMPD/o_n2.txt" abgemeldet)" ""
lauf_ohne_netz "$TMPD/d_login.img" "konto liste" "$TMPD/o_n3.txt"
is "offline: the account is still listed" "$(kv "$TMPD/o_n3.txt" konten)" "1"
lauf_ohne_netz "$TMPD/base.img" "konto anmelden --anbieter=fleitec --device" "$TMPD/o_n4.txt"
S4=$(kv "$TMPD/o_n4.txt" stand)
case "$S4" in keinnetz|fehler) ok "sign-in without network fails clearly ($S4)";; *) bad "sign-in without network: '$S4'";; esac
lauf_ohne_netz "$TMPD/base.img" "echo hallo > /probe.txt;cat /probe.txt;konto status" "$TMPD/o_n5.txt"
has "$TMPD/o_n5.txt" "hallo" "a device with no account works as before"

echo "ANBFLEITEC: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
