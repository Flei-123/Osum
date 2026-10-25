#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$ROOT/lib"
D=$(mktemp -d); chmod 755 "$D"
SMBPID=""
stop_smbd() { [ -n "$SMBPID" ] && kill "$SMBPID" 2>/dev/null && wait "$SMBPID" 2>/dev/null; SMBPID=""; }
trap 'stop_smbd; rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for t in smbd smbpasswd openssl sha256sum; do
    command -v "$t" >/dev/null 2>&1 || command -v "/usr/sbin/$t" >/dev/null 2>&1 || { echo "SMB: skipped, $t is missing"; exit 0; }
done
export PATH="$PATH:/usr/sbin"
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

$FIRNC tools/smb/cryptotest.fi -o "$D/ct" 2> "$D/ct.err" && ok "crypto vectors program builds" || { bad "cryptotest build"; head -5 "$D/ct.err"; }
$FIRNC kernel/app/smbctl.fi -o "$D/smbctl" 2> "$D/cc.err" && ok "smbctl builds (host profile)" || { bad "smbctl build"; head -10 "$D/cc.err"; echo "SMB: $pass ok, $fail FAIL"; exit 1; }
FIRNLIB="$ROOT/lib" $FIRNC -c --profile=app -o "$D/smbctl.o" kernel/app/smbctl.fi 2> "$D/app.err" && ok "smbctl builds (--profile=app, ring 3)" || { bad "smbctl app-profile build"; head -10 "$D/app.err"; }

for s in "" a abc "message digest" "$(printf 'x%.0s' $(seq 1 55))" "$(printf 'x%.0s' $(seq 1 56))" "$(printf 'x%.0s' $(seq 1 64))" "$(printf 'y%.0s' $(seq 1 200))"; do
    got=$("$D/ct" 4 "$s" x); want=$(printf %s "$s" | openssl dgst -md4 -provider legacy -provider default 2>/dev/null | awk '{print $NF}')
    [ -n "$want" ] && [ "$got" = "$want" ] || { bad "md4 len ${#s}: $got != $want"; continue; }
done
ok "md4 equals openssl for lengths 0,1,3,14,55,56,64,200"
for k in key "$(printf 'k%.0s' $(seq 1 100))"; do
    got=$("$D/ct" h "$k" "The quick brown fox"); want=$(printf %s "The quick brown fox" | openssl dgst -md5 -hmac "$k" | awk '{print $NF}')
    [ "$got" = "$want" ] && ok "hmac-md5 equals openssl (key ${#k} octets)" || bad "hmac-md5 key ${#k}: $got != $want"
done

PORT=$(( 20000 + RANDOM % 20000 ))
SHARE="$D/share"; mkdir -p "$SHARE/sub" "$D/priv" "$D/lock" "$D/state" "$D/cache"
chmod 777 "$SHARE" "$SHARE/sub"
echo "hello world" > "$SHARE/hello.txt"
head -c 300000 /dev/urandom > "$SHARE/big.bin"
echo 'nobody = gateuser' > "$D/usermap"
write_conf() {
cat > "$D/smb.conf" <<CONF
[global]
workgroup = TESTGRP
interfaces = 127.0.0.1
bind interfaces only = yes
smb ports = $PORT
disable netbios = yes
load printers = no
printing = bsd
printcap name = /dev/null
disable spoolss = yes
log file = $D/log.%m
private dir = $D/priv
lock directory = $D/lock
state directory = $D/state
cache directory = $D/cache
pid directory = $D/lock
passdb backend = tdbsam:$D/priv/passdb.tdb
username map = $D/usermap
server min protocol = SMB2_02
map to guest = never
server signing = $1
[data]
path = $SHARE
read only = no
force user = root
CONF
}
write_conf auto
printf 'gatepass\ngatepass\n' | smbpasswd -c "$D/smb.conf" -a -s nobody >/dev/null 2>&1 && ok "samba test user" || bad "smbpasswd"
start_smbd() {
    write_conf "$1"
    setsid smbd -s "$D/smb.conf" -F --no-process-group > "$D/smbd.out" 2>&1 < /dev/null &
    SMBPID=$!
    for _ in $(seq 1 50); do ss -ltn 2>/dev/null | grep -q ":$PORT " && return 0; sleep 0.2; done
    return 1
}
C() { timeout 60 "$D/smbctl" -p "$PORT" -u gateuser "$@"; }

start_smbd auto && ok "samba (signing auto) listening on 127.0.0.1:$PORT" || { bad "samba did not start"; cat "$D/smbd.out" | head -5; }
out=$(C -w gatepass 127.0.0.1 data ls)
echo "$out" | grep -q '^- 12 hello.txt$' && echo "$out" | grep -q '^d 0 sub$' && echo "$out" | grep -q '^- 300000 big.bin$' && ok "ls lists files and directories with sizes" || bad "ls: $out"
echo x > "$SHARE/sub/in.txt"
C -w gatepass 127.0.0.1 data ls sub | grep -q '^- 2 in.txt$' && ok "ls of a subdirectory" || bad "ls sub"
out=$(C -w gatepass 127.0.0.1 data get big.bin "$D/got.bin")
want=$(sha256sum "$SHARE/big.bin" | awk '{print $1}')
echo "$out" | grep -q "octets 300000 sha256 $want" && cmp -s "$SHARE/big.bin" "$D/got.bin" && ok "get: 300000 octets, 5 chunks, byte-exact" || bad "get: $out"
head -c 200000 /dev/urandom > "$D/up.bin"
C -w gatepass 127.0.0.1 data put "$D/up.bin" sub/up.bin | grep -q 'octets 200000' && cmp -s "$D/up.bin" "$SHARE/sub/up.bin" && ok "put: 200000 octets land byte-exact on the share" || bad "put"
C -w gatepass 127.0.0.1 data put "$D/up.bin" "/ö-ünï.bin" >/dev/null && cmp -s "$D/up.bin" "$SHARE/ö-ünï.bin" && C -w gatepass 127.0.0.1 data ls | grep -q '^- 200000 ö-ünï.bin$' && ok "UTF-8 names round-trip (put, ls)" || bad "utf8 names"
C -w gatepass 127.0.0.1 data put "$D/up.bin" sub/up.bin >/dev/null && ok "put overwrites an existing file" || bad "overwrite"
out=$(C -w wrongpass 127.0.0.1 data ls); echo "$out" | grep -q 'FAILED login auth c000006d' && ! echo "$out" | grep -q 'hello.txt' && ok "counter-proof: wrong password -> login auth c000006d, nothing listed" || bad "wrong password: $out"
out=$(C -w gatepass 127.0.0.1 nosuchshare ls); echo "$out" | grep -q 'FAILED tree share c00000cc' && ok "counter-proof: missing share -> tree share c00000cc" || bad "missing share: $out"
out=$(C -w gatepass 127.0.0.1 data get nothere.txt); echo "$out" | grep -q 'FAILED open notfound c0000034' && ok "counter-proof: missing file -> open notfound c0000034" || bad "missing file: $out"
out=$(timeout 20 "$D/smbctl" -p "$PORT" -u nosuchuser -w gatepass 127.0.0.1 data ls); echo "$out" | grep -q 'FAILED login auth' && ok "counter-proof: unknown user -> login auth" || bad "unknown user: $out"
out=$(timeout 20 "$D/smbctl" -p 1 -u gateuser -w gatepass 127.0.0.1 data ls); echo "$out" | grep -q 'FAILED connect connect' && ok "counter-proof: closed port -> connect" || bad "closed port: $out"
C -w gatepass -N 127.0.0.1 data ls | grep -q 'ls ok' && ok "signing off against a server that does not require it works (-N)" || bad "-N against auto server"
stop_smbd

start_smbd mandatory && ok "samba (signing mandatory) listening" || bad "samba mandatory did not start"
C -w gatepass 127.0.0.1 data ls | grep -q 'ls ok' && ok "HMAC-SHA256 signing: mandatory-signing server accepts every signed request" || bad "signed session against mandatory server"
out=$(C -w gatepass 127.0.0.1 data get big.bin); echo "$out" | grep -q "sha256 $want" && ok "signed get of 300000 octets verifies every response signature" || bad "signed get: $out"
out=$(C -w gatepass -N 127.0.0.1 data ls); echo "$out" | grep -q 'ls ok' && bad "counter-proof: unsigned session was ACCEPTED by a mandatory-signing server" || ok "counter-proof: -N (no signing) against mandatory server is refused"
stop_smbd
echo "  SMB gate: $pass ok, $fail FAIL"
[ "$fail" = 0 ]
