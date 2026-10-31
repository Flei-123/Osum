#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
TMPD=$(mktemp -d)
SWPIDS=()
cleanup() { for p in "${SWPIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; [ -d "${VAULTD_KEEP:-}" ] && cp "$TMPD"/*.klar "$VAULTD_KEEP"/ 2>/dev/null; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

PW1="correct-horse-battery"; PIN1="482915"; PIN2="735190"; PINBAD="590813"
ORIGIN="https://example.com"; USER1="alice"; LPW="s3cr3t-pw-7"
hx() { python3 -I -c 'import sys; sys.stdout.write(sys.argv[1].encode().hex())' "$1"; }
H_LPW=$(hx "$LPW")

: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

command -v swtpm >/dev/null 2>&1 || { echo "VAULTD-TPM: swtpm missing"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "VAULTD-TPM: qemu missing"; exit 1; }

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh ls cat echo sleep mkdir grep su chmod vaultd vaultctl pinctl"
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "programs build"; else bad "programs do not build"; tail -15 "$TMPD/b.txt"; echo "VAULTD-TPM: $pass passed, $fail failed"; exit 1; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "kernel builds"; else bad "kernel does not build"; tail -8 "$TMPD/k.txt"; echo "VAULTD-TPM: $pass passed, $fail failed"; exit 1; fi

printf 'root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/:/bin/sh\n' > "$TMPD/passwd"
printf 'root:x:0:\njustin:x:1000:\n' > "$TMPD/group"
printf 'kib=64\npasses=1\nlanes=1\n' > "$TMPD/kdf"

image() {
    local img=$1 script=$2
    local -a A=(build "$img" 20000 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/vault/ /secrets/ /device/ /var/ /var/log/ /run/)
    local p
    for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    A+=("/etc/passwd=$TMPD/passwd" "/etc/group=$TMPD/group" "/etc/vault/kdf=$TMPD/kdf" "/t/s.sh=$script")
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
}

run() {
    local img=$1 nm=$2 secs=$3 tpm=$4
    local -a X=()
    rm -f "$TMPD/$nm.txt"
    if [ "$tpm" = tis ]; then
        mkdir -p "$TMPD/st-$nm"
        swtpm socket --tpmstate "dir=$TMPD/st-$nm" --ctrl "type=unixio,path=$TMPD/sock-$nm" --tpm2 --log "file=$TMPD/sw-$nm.log" &
        SWPIDS+=($!)
        for _ in $(seq 50); do [ -S "$TMPD/sock-$nm" ] && break; sleep 0.1; done
        X=(-chardev "socket,id=chrtpm,path=$TMPD/sock-$nm" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0)
    fi
    timeout "$secs" qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -cpu max \
        -kernel "$TMPD/k0.img" -m 512 "${X[@]}" \
        -append "osum vfs nokbd bus nosched noproc nofs script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! i=0
    while [ $i -lt $((secs * 2)) ] && kill -0 "$pid" 2>/dev/null; do
        grep -qa "^==FERTIG==" "$TMPD/$nm.txt" 2>/dev/null && { sleep 1; break; }
        sleep 0.5; i=$((i+1))
    done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$TMPD/$nm.txt" > "$TMPD/$nm.klar" 2>/dev/null || true
}

cat > "$TMPD/sa.sh" <<EOS
vaultd /secrets 30000 &
sleep -m 500
echo ==A-STATUS0==
vaultctl status
echo ==A-DEVPERM==
su justin /bin/cat /dev/tpm0
echo rc=\$?
echo ==A-CREATE==
pinctl set root $PIN1
vaultctl create pw=$PW1
echo rc=\$?
vaultctl put title=Example origins=$ORIGIN username=$USER1 password=$LPW
echo ==A-ENROLL==
vaultctl tpmenroll pin=$PIN1
echo rc=\$?
vaultctl status
echo ==A-LOCK==
vaultctl lock
vaultctl status
echo ==A-PINUNLOCK==
vaultctl unlock pin=$PIN1
echo rc=\$?
vaultctl find origin=$ORIGIN
echo ==A-LOCK2==
vaultctl lock
echo ==A-BADPIN==
vaultctl unlock pin=$PINBAD
echo rc=\$?
vaultctl status
echo ==A-STALE==
pinctl set root $PIN2
vaultctl unlock pin=$PIN2
echo rc=\$?
vaultctl status
echo ==A-OLDPIN==
vaultctl unlock pin=$PIN1
echo rc=\$?
echo ==A-PW==
vaultctl unlock pw=$PW1
echo rc=\$?
echo ==A-DROP==
vaultctl tpmdrop
echo rc=\$?
vaultctl status
echo ==FERTIG==
EOS

cat > "$TMPD/sc.sh" <<EOS
vaultd /secrets 30000 &
sleep -m 500
echo ==C-CREATE==
pinctl set root $PIN1
vaultctl create pw=$PW1
vaultctl lock
echo ==C-NOSLOT==
vaultctl unlock pin=$PIN1
echo rc=\$?
echo ==FERTIG==
EOS

cat > "$TMPD/sb.sh" <<EOS
vaultd /secrets 30000 &
sleep -m 500
echo ==B-STATUS0==
vaultctl status
echo ==B-CREATE==
pinctl set root $PIN1
vaultctl create pw=$PW1
echo ==B-ENROLL==
vaultctl tpmenroll pin=$PIN1
echo rc=\$?
vaultctl status
echo ==B-UNLOCK==
vaultctl lock
vaultctl unlock pin=$PIN1
echo rc=\$?
vaultctl unlock pw=$PW1
echo rc=\$?
echo ==FERTIG==
EOS

echo "== 2. boot A: swtpm tpm-tis =="
image "$TMPD/A.img" "$TMPD/sa.sh"
run "$TMPD/A.img" a 400 tis
A="$TMPD/a.klar"
grep -qa "==FERTIG==" "$A" || { bad "boot A did not reach the end"; tail -15 "$A" | sed 's/^/        /'; }
part "$A" A-STATUS0 A-DEVPERM > "$TMPD/p.txt"
has "$TMPD/p.txt" "tpm=1" "vaultd sees /dev/tpm0 (tpm=1)"
part "$A" A-DEVPERM A-CREATE > "$TMPD/p.txt"
hasnot "$TMPD/p.txt" "rc=0" "a non-root user cannot open /dev/tpm0"
part "$A" A-CREATE A-ENROLL > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "vault created"
part "$A" A-ENROLL A-LOCK > "$TMPD/p.txt"
has "$TMPD/p.txt" "rc=0" "tpmenroll succeeds through the kernel device"
has "$TMPD/p.txt" "tpmslot=1" "status: tpm slot present"
has "$TMPD/p.txt" "pinunlock=1" "status: PIN unlock available"
part "$A" A-LOCK A-PINUNLOCK > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=locked" "locked after lock"
part "$A" A-PINUNLOCK A-LOCK2 > "$TMPD/p.txt"
has "$TMPD/p.txt" "rc=0" "PIN unlock succeeds"
has "$TMPD/p.txt" "$H_LPW" "the stored login is readable after the PIN unlock"
part "$A" A-BADPIN A-STALE > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=0" "a wrong PIN does not unlock"
has "$TMPD/p.txt" "state=locked" "... and the vault stays locked"
part "$A" A-STALE A-OLDPIN > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=bad" "a PIN that the TPM did not seal is refused by the TPM (err=bad)"
has "$TMPD/p.txt" "state=locked" "... and the vault stays locked"
part "$A" A-OLDPIN A-PW > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=0" "the old PIN is refused by pin.fi after the change"
part "$A" A-PW A-DROP > "$TMPD/p.txt"
has "$TMPD/p.txt" "rc=0" "the main password still unlocks"
part "$A" A-DROP FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "tpmslot=0" "tpmdrop removes the slot"

echo "== 3. boot C: swtpm, vault without a slot =="
image "$TMPD/C.img" "$TMPD/sc.sh"
run "$TMPD/C.img" c 400 tis
C="$TMPD/c.klar"
grep -qa "==FERTIG==" "$C" || { bad "boot C did not reach the end"; tail -15 "$C" | sed 's/^/        /'; }
part "$C" C-NOSLOT FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=noslot" "PIN unlock without a slot: noslot"

echo "== 4. boot B: no TPM (counter-proof) =="
image "$TMPD/B.img" "$TMPD/sb.sh"
run "$TMPD/B.img" b 400 none
B="$TMPD/b.klar"
grep -qa "==FERTIG==" "$B" || { bad "boot B did not reach the end"; tail -15 "$B" | sed 's/^/        /'; }
part "$B" B-STATUS0 B-CREATE > "$TMPD/p.txt"
has "$TMPD/p.txt" "tpm=0" "without a TPM: tpm=0"
part "$B" B-ENROLL B-UNLOCK > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=tpm" "without a TPM: tpmenroll is refused (err=tpm)"
hasnot "$TMPD/p.txt" "tpmslot=1" "... no slot appears"
part "$B" B-UNLOCK FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "rc=1" "without a TPM: PIN unlock fails"
has "$TMPD/p.txt" "ok=1" "... the main password still unlocks"

echo "VAULTD-TPM: $pass passed, $fail failed"
[ "$fail" = 0 ]
