#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$ROOT/lib"
D=$(mktemp -d); chmod 755 "$D"
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

RFC_MSG='\x6b\xc1\xbe\xe2\x2e\x40\x9f\x96\xe9\x3e\x7d\x11\x73\x93\x17\x2a\xae\x2d\x8a\x57\x1e\x03\xac\x9c\x9e\xb7\x6f\xac\x45\xaf\x8e\x51\x30\xc8\x1c\x46\xa3\x5c\xe4\x11\xe5\xfb\xc1\x19\x1a\x0a\x52\xef\xf6\x9f\x24\x45\xdf\x4f\x9b\x17\xad\x2b\x41\x7b\xe6\x6c\x37\x10'
CMAC_KEY=2b7e151628aed2a6abf7158809cf4f3c
cmac_ref() { openssl mac -cipher AES-128-CBC -macopt hexkey:$CMAC_KEY CMAC | tr 'A-F' 'a-f'; }
for n in 0 16 40 64; do
    printf "$RFC_MSG" | head -c $n > "$D/rfc.msg"
    got=$("$D/ct" c "$(cat "$D/rfc.msg")" x); want=$(cmac_ref < "$D/rfc.msg")
    [ "$got" = "$want" ] && ok "aes-128-cmac equals openssl on the RFC 4493 message ($n octets)" || bad "cmac $n: $got != $want"
done
for n in 1 15 17 31 32 33 63 100 255; do
    m=$(head -c $n /dev/zero | tr '\0' 'q')
    got=$("$D/ct" c "$m" x); want=$(printf %s "$m" | cmac_ref)
    [ "$got" = "$want" ] || { bad "cmac len $n: $got != $want"; continue; }
done
ok "aes-128-cmac equals openssl for lengths 1,15,17,31,32,33,63,100,255"
got=$("$D/ct" c a x); [ "$got" != "$("$D/ct" c b x)" ] && ok "counter-proof: cmac differs for different messages" || bad "cmac counter-proof"
. tools/smb/samba.sh
samba_setup "$D"
PORT=$SMB_PORT
SHARE="$D/share"
samba_conf auto
samba_user && ok "samba test user" || bad "smbpasswd"
start_smbd() { samba_start "$1"; }
stop_smbd() { samba_stop; }
export SMB_PASSWORD=gatepass
C() { timeout 60 "$D/smbctl" -p "$PORT" -u gateuser "$@"; }

start_smbd auto && ok "samba (signing auto) listening on 127.0.0.1:$PORT" || { bad "samba did not start"; cat "$D/smbd.out" | head -5; }
out=$(C 127.0.0.1 data ls)
echo "$out" | grep -q '^- 12 hello.txt$' && echo "$out" | grep -q '^d 0 sub$' && echo "$out" | grep -q '^- 300000 big.bin$' && ok "ls lists files and directories with sizes" || bad "ls: $out"
echo x > "$SHARE/sub/in.txt"
C 127.0.0.1 data ls sub | grep -q '^- 2 in.txt$' && ok "ls of a subdirectory" || bad "ls sub"
out=$(C 127.0.0.1 data get big.bin "$D/got.bin")
want=$(sha256sum "$SHARE/big.bin" | awk '{print $1}')
echo "$out" | grep -q "octets 300000 sha256 $want" && cmp -s "$SHARE/big.bin" "$D/got.bin" && ok "get: 300000 octets, 5 chunks, byte-exact" || bad "get: $out"
head -c 200000 /dev/urandom > "$D/up.bin"
C 127.0.0.1 data put "$D/up.bin" sub/up.bin | grep -q 'octets 200000' && cmp -s "$D/up.bin" "$SHARE/sub/up.bin" && ok "put: 200000 octets land byte-exact on the share" || bad "put"
C 127.0.0.1 data put "$D/up.bin" "/ö-ünï.bin" >/dev/null && cmp -s "$D/up.bin" "$SHARE/ö-ünï.bin" && C 127.0.0.1 data ls | grep -q '^- 200000 ö-ünï.bin$' && ok "UTF-8 names round-trip (put, ls)" || bad "utf8 names"
C 127.0.0.1 data put "$D/up.bin" sub/up.bin >/dev/null && ok "put overwrites an existing file" || bad "overwrite"
C 127.0.0.1 data stat hello.txt | grep -q 'stat ok' && C 127.0.0.1 data stat sub | grep -q 'stat ok' && ok "stat: an existing file and a directory are found" || bad "stat existing"
C 127.0.0.1 data stat no-such-file.txt >/dev/null; [ $? -eq 5 ] && ok "stat: a missing path exits 5" || bad "stat missing"
echo gone > "$SHARE/sub/del.txt"
C 127.0.0.1 data rm sub/del.txt | grep -q 'rm ok' && [ ! -e "$SHARE/sub/del.txt" ] && ok "rm: the file is gone from the share" || bad "rm"
C 127.0.0.1 data rm sub/del.txt >/dev/null; [ $? -eq 5 ] && ok "rm: a missing file exits 5" || bad "rm missing"
out=$(printf 'gatepass\n' | SMB_PASSWORD= C 127.0.0.1 data ls); echo "$out" | grep -q 'Password: ' && echo "$out" | grep -q 'ls ok' && ok "password prompt on standard input works when SMB_PASSWORD is unset" || bad "prompt: $out"
out=$(printf '\n' | SMB_PASSWORD= C 127.0.0.1 data ls); echo "$out" | grep -q 'no password' && ok "counter-proof: empty prompt answer -> no password, no connection" || bad "empty prompt: $out"
out=$(C -w gatepass 127.0.0.1 data ls); echo "$out" | grep -q "unknown option" && ! echo "$out" | grep -q "ls ok" && ok "counter-proof: -w is rejected as an unknown option (the password never travels in argv)" || bad "-w accepted: $out"
out=$(SMB_PASSWORD=wrongpass C 127.0.0.1 data ls); echo "$out" | grep -q 'FAILED login auth c000006d' && ! echo "$out" | grep -q 'hello.txt' && ok "counter-proof: wrong password -> login auth c000006d, nothing listed" || bad "wrong password: $out"
out=$(C 127.0.0.1 nosuchshare ls); echo "$out" | grep -q 'FAILED tree share c00000cc' && ok "counter-proof: missing share -> tree share c00000cc" || bad "missing share: $out"
out=$(C 127.0.0.1 data get nothere.txt); echo "$out" | grep -q 'FAILED open notfound c0000034' && ok "counter-proof: missing file -> open notfound c0000034" || bad "missing file: $out"
out=$(timeout 20 "$D/smbctl" -p "$PORT" -u nosuchuser 127.0.0.1 data ls); echo "$out" | grep -q 'FAILED login auth' && ok "counter-proof: unknown user -> login auth" || bad "unknown user: $out"
out=$(timeout 20 "$D/smbctl" -p 1 -u gateuser 127.0.0.1 data ls); echo "$out" | grep -q 'FAILED connect connect' && ok "counter-proof: closed port -> connect" || bad "closed port: $out"
C -m 210 -N 127.0.0.1 data ls | grep -q "ls ok" && ok "SMB 2.1: signing off against a server that does not require it works (-N)" || bad "-N against auto server"
stop_smbd

start_smbd mandatory && ok "samba (signing mandatory) listening" || bad "samba mandatory did not start"
C 127.0.0.1 data ls | grep -q 'ls ok' && ok "HMAC-SHA256 signing: mandatory-signing server accepts every signed request" || bad "signed session against mandatory server"
out=$(C 127.0.0.1 data get big.bin); echo "$out" | grep -q "sha256 $want" && ok "signed get of 300000 octets verifies every response signature" || bad "signed get: $out"
out=$(C -N 127.0.0.1 data ls); echo "$out" | grep -q 'ls ok' && bad "counter-proof: unsigned session was ACCEPTED by a mandatory-signing server" || ok "counter-proof: -N (no signing) against mandatory server is refused"
stop_smbd
SMB_EXTRA=""
for row in "SMB2_10:0210" "SMB3_00:0300" "SMB3_02:0302" "SMB3_11:0311"; do
    name=${row%%:*}; want_d=${row##*:}
    SMB_MIN=$name; SMB_MAX=$name
    start_smbd mandatory || bad "samba $name did not start"
    out=$(C 127.0.0.1 data ls); echo "$out" | grep -q "dialect $want_d" && echo "$out" | grep -q 'ls ok' && ok "$name: negotiated dialect $want_d, signed ls against a mandatory-signing server" || bad "$name ls: $out"
    out=$(C 127.0.0.1 data get big.bin); echo "$out" | grep -q "sha256 $want" && ok "$name: signed get of 300000 octets, every response signature verified" || bad "$name get: $out"
    C 127.0.0.1 data put "$D/up.bin" "sub/up-$want_d.bin" >/dev/null && cmp -s "$D/up.bin" "$SHARE/sub/up-$want_d.bin" && ok "$name: signed put of 200000 octets lands byte-exact" || bad "$name put"
    out=$(C -N 127.0.0.1 data ls); echo "$out" | grep -q 'ls ok' && bad "$name: unsigned session ACCEPTED" || ok "$name: counter-proof: unsigned session refused"
    stop_smbd
done
SMB_MIN=SMB3_00; SMB_MAX=SMB3_11
start_smbd mandatory || bad "samba SMB3 only did not start"
out=$(C -m 210 127.0.0.1 data ls); echo "$out" | grep -q 'FAILED negotiate' && ok "counter-proof: a client limited to SMB 2.1 against an SMB3-only server is refused at negotiate" || bad "-m 210 vs SMB3-only: $out"
out=$(C -m 300 127.0.0.1 data ls); echo "$out" | grep -q 'dialect 0300' && echo "$out" | grep -q 'ls ok' && ok "client limited to 3.0 against a server that offers up to 3.1.1 settles on 3.0" || bad "-m 300: $out"
stop_smbd
SMB_MIN=SMB3_02; SMB_MAX=SMB3_02
start_smbd mandatory || bad "samba 3.0.2 did not start"
mkdir -p "$D/badlib" && cp -r "$ROOT/lib/." "$D/badlib/" && sed -i 's/SMB2AESCMAC/SMB2AESCMAX/' "$D/badlib/smb/client.fi"
FIRNLIB="$D/badlib" $FIRNC kernel/app/smbctl.fi -o "$D/smbctl_badkdf" 2>/dev/null && ok "variant with a wrong signing-key label builds" || bad "badkdf build"
out=$(timeout 60 "$D/smbctl_badkdf" -p "$PORT" -u gateuser 127.0.0.1 data ls); echo "$out" | grep -q 'ls ok' && bad "counter-proof: a wrong CMAC signing key was ACCEPTED" || ok "counter-proof: a wrong CMAC signing-key label is refused by the server"
sed -i 's/SMBSigningKey/SMBSigningKez/' "$D/badlib/smb/client.fi"
stop_smbd
SMB_MIN=SMB3_11; SMB_MAX=SMB3_11
start_smbd mandatory || bad "samba 3.1.1 did not start"
FIRNLIB="$D/badlib" $FIRNC kernel/app/smbctl.fi -o "$D/smbctl_badpre" 2>/dev/null
out=$(timeout 60 "$D/smbctl_badpre" -p "$PORT" -u gateuser 127.0.0.1 data ls); echo "$out" | grep -q 'ls ok' && bad "counter-proof: a wrong 3.1.1 signing-key label was ACCEPTED" || ok "counter-proof: a wrong 3.1.1 signing-key label is refused by the server"
stop_smbd
SMB_MIN=SMB2_02; SMB_MAX=SMB3_11
mkdir -p "$D/s2"
SMB_SHARES="[docs]
path = $D/s2
comment = Documents of the team
read only = yes
[hidden\$]
path = $D/s2
[Ünï]
path = $D/s2
comment = Ünïcode remark"
for n in $(seq 1 120); do SMB_SHARES="$SMB_SHARES
[bulk$n]
path = $D/s2
comment = bulk share number $n with a rather long remark text to force several RPC fragments"; done
start_smbd mandatory && ok "samba (many shares) listening" || bad "samba shares did not start"
out=$(C 127.0.0.1 shares)
echo "$out" | grep -q '^d data	' && echo "$out" | grep -q '^d docs	Documents of the team$' && echo "$out" | grep -q '^d hidden\$	' && echo "$out" | grep -q '^i IPC\$	' && ok "shares: names, kinds, remarks (disk, hidden \$, IPC)" || bad "shares: $(echo "$out" | head -5)"
echo "$out" | grep -q '^d Ünï	Ünïcode remark$' && ok "shares: UTF-8 names and remarks round-trip" || bad "shares utf8"
[ "$(echo "$out" | grep -c '^d bulk')" = 120 ] && echo "$out" | grep -q '^d bulk120	bulk share number 120 ' && echo "$out" | grep -q 'shares ok' && ok "shares: 120 extra shares (multi-fragment RPC response) all listed" || bad "shares fragments: $(echo "$out" | grep -c '^d bulk')"
for m in 210 300 302 311; do
    echo "$(C -m $m 127.0.0.1 shares)" | grep -q 'shares ok' && ok "shares over SMB dialect $m" || bad "shares dialect $m"
done
C -o "$D/list.txt" 127.0.0.1 data ls | grep -q 'ls ok' && grep -q '^- 12 hello.txt$' "$D/list.txt" && ok "-o writes the listing to a file, not to the terminal" || bad "-o ls"
out=$(C -o "$D/shares.txt" 127.0.0.1 shares); ! echo "$out" | grep -q '^d data' && grep -q '^d docs' "$D/shares.txt" && ok "-o also takes the share list" || bad "-o shares"
printf 'gatepass\nignored\n' > "$D/pw.txt"
out=$(SMB_PASSWORD= timeout 60 "$D/smbctl" -p "$PORT" -u gateuser -F "$D/pw.txt" 127.0.0.1 data ls)
echo "$out" | grep -q 'ls ok' && [ ! -e "$D/pw.txt" ] && ok "-F reads the password from a file (first line) and deletes the file" || bad "-F: $out"
printf 'wrongpass\n' > "$D/pw.txt"
SMB_PASSWORD= timeout 60 "$D/smbctl" -p "$PORT" -u gateuser -F "$D/pw.txt" 127.0.0.1 data ls >/dev/null; rc=$?
[ "$rc" = 3 ] && [ ! -e "$D/pw.txt" ] && ok "counter-proof: wrong password from -F exits 3 (auth) and the file is still deleted" || bad "-F wrong: rc=$rc"
SMB_PASSWORD=wrongpass C 127.0.0.1 shares >/dev/null; [ $? = 3 ] && ok "counter-proof: shares with a wrong password exits 3 (auth)" || bad "shares wrong password rc"
C 127.0.0.1 nosuchshare ls >/dev/null; [ $? = 5 ] && ok "exit code 5 for a missing share" || bad "exit 5"
timeout 20 "$D/smbctl" -p 1 -u gateuser 127.0.0.1 shares >/dev/null; [ $? = 4 ] && ok "exit code 4 for a closed port" || bad "exit 4"
C 127.0.0.1 data get nothere.txt >/dev/null; [ $? = 5 ] && ok "exit code 5 for a missing file" || bad "exit 5 file"
mkdir -p "$D/badlib2" && cp -r "$ROOT/lib/." "$D/badlib2/" && sed -i 's/^const OP_NET_SHARE_ENUM_ALL: u64 = 15/const OP_NET_SHARE_ENUM_ALL: u64 = 99/' "$D/badlib2/smb/shares.fi"
FIRNLIB="$D/badlib2" $FIRNC kernel/app/smbctl.fi -o "$D/smbctl_badop" 2>/dev/null
out=$(timeout 60 "$D/smbctl_badop" -p "$PORT" -u gateuser 127.0.0.1 shares); echo "$out" | grep -q 'shares ok' && bad "counter-proof: a wrong RPC opnum was ACCEPTED" || ok "counter-proof: a wrong RPC opnum makes the server fault and the listing fail"
stop_smbd
if [ -z "${SMB_NO_GUEST:-}" ]; then
    echo "== guest (tools/smb/guest.sh) =="
    gout=$(bash tools/smb/guest.sh 2>&1)
    echo "$gout" | sed 's/^/  | /'
    gl=$(echo "$gout" | grep -a '^SMBGUEST: ' | tail -1)
    if echo "$gl" | grep -q 'skipped'; then echo "  guest part skipped"
    elif [ -n "$gl" ]; then
        pass=$((pass + $(echo "$gl" | awk '{print $2}'))); fail=$((fail + $(echo "$gl" | awk '{print $4}')))
    else bad "guest gate gave no summary"; fi
fi
echo "  SMB gate: $pass ok, $fail FAIL"
[ "$fail" = 0 ]
