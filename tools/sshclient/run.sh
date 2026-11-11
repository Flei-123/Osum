#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/pidkill.sh
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo sleep true false init shasum ssh scp sftp"
BLOCKS=4096
OSUM_IP=10.0.2.15
OSUM_GW=10.0.2.2
HOSTPORT=${HOSTPORT:-$(( 47000 + ($$ % 900) ))}
DONE_MARK=SSHCLIENT-GUEST-DONE

TMPD=$(mktemp -d)
cleanup() {
    [ -n "${QPID:-}" ] && osum_kill_tree "$QPID"
    [ -n "${SPID:-}" ] && kill "$SPID" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1: '$2', expected '$3'"; fi; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc missing: $FIRNC"; exit 1; }
for t in qemu-system-x86_64 ssh scp ssh-keygen sha256sum; do
    command -v "$t" >/dev/null 2>&1 || { echo "SSHCLIENT: skipped, $t missing"; exit 0; }
done
SSHD_BIN=$(command -v sshd || echo /usr/sbin/sshd)
[ -x "$SSHD_BIN" ] || { echo "SSHCLIENT: skipped, sshd missing"; exit 0; }

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm"; else ACCEL="-accel tcg"; fi

echo "== 1. build: kernel and $(echo $PROGS | wc -w) programs =="
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>/dev/null || bad "$f.s cannot be assembled"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"

"$FIRNC" kernel/kmain.fi -o "$TMPD/k.o" >"$TMPD/ek" 2>&1 \
    && "$FIRNC" kernel/uprog.fi -o "$TMPD/u.o" >>"$TMPD/ek" 2>&1 \
    || { bad "kernel does not compile"; head -8 "$TMPD/ek" | sed 's/^/        /'; echo "SSHCLIENT: $pass passed, $fail failed"; exit 1; }
ld -n -T "$LDSCRIPT" --defsym=KERNEL_MAIN=_F0.kernel_main --defsym=KERNEL_TRAP=_F0.trap__entry \
    --defsym=KERNEL_SYSCALL=_F0.sys__entry --defsym=KERNEL_TASK_MAIN=_F0.tasks__main \
    --defsym=KERNEL_USER_START=_F0.proccopy__user_start --defsym=KERNEL_AP_MAIN=_F0.smp__ap_main \
    --defsym=USER_MAIN=_F0.u_enter -o "$TMPD/k.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
    "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k.o" "$TMPD/u.o" 2>"$TMPD/ldk" || bad "kernel link failed"
objcopy -O elf32-i386 "$TMPD/k.elf" "$TMPD/k.mb" 2>/dev/null

build_prog() { # srcdir name outelf
    "$FIRNC" "$1/$2.fi" -o "$TMPD/$2.o" >"$TMPD/e$2" 2>&1 \
        && ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$3" "$TMPD/crt.o" "$TMPD/$2.o" 2>/dev/null \
        && strip --strip-all "$3"
}
for p in $PROGS; do
    build_prog kernel/user "$p" "$TMPD/$p.elf" || { bad "$p does not build"; head -6 "$TMPD/e$p" | sed 's/^/        /'; }
done
[ -s "$TMPD/ssh.elf" ] && [ -s "$TMPD/scp.elf" ] && ok "ssh and scp build ($(stat -c%s "$TMPD/ssh.elf") / $(stat -c%s "$TMPD/scp.elf") octets)"
for p in ssh scp; do
    undef=$(nm -u "$TMPD/$p.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$undef" ] && ok "/bin/$p has no undefined name" || bad "undefined names in $p: $undef"
done

echo "== 2. host OpenSSH as the server side =="
ssh-keygen -q -t ed25519 -N '' -f "$TMPD/host_key" -C hostkey
ssh-keygen -q -t ed25519 -N '' -f "$TMPD/other_host_key" -C otherhost
ssh-keygen -q -t ed25519 -N '' -f "$TMPD/id_ed25519" -C guestkey
ssh-keygen -q -t ed25519 -N '' -f "$TMPD/wrong_ed25519" -C wrongkey
cp "$TMPD/id_ed25519.pub" "$TMPD/authorized_keys"
mkdir -p "$TMPD/hostdir"
head -c 30000 /dev/urandom > "$TMPD/blob.bin"
BLOBSUM=$(sha256sum "$TMPD/blob.bin" | cut -d' ' -f1)
UPDIR="$TMPD/hostdir"
cat > "$TMPD/sshd_config" <<CFG
Port $HOSTPORT
ListenAddress 127.0.0.1
HostKey $TMPD/host_key
PidFile $TMPD/sshd.pid
AuthorizedKeysFile $TMPD/authorized_keys
PermitRootLogin yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
Subsystem sftp /usr/lib/openssh/sftp-server
LogLevel VERBOSE
CFG
"$SSHD_BIN" -D -e -f "$TMPD/sshd_config" 2>"$TMPD/sshd.log" &
SPID=$!
for i in $(seq 1 50); do grep -q 'Server listening' "$TMPD/sshd.log" 2>/dev/null && break; sleep 0.2; done
grep -q 'Server listening' "$TMPD/sshd.log" && ok "OpenSSH listens on 127.0.0.1:$HOSTPORT" || { bad "host sshd did not start"; head -5 "$TMPD/sshd.log" | sed 's/^/        /'; }

HK=$(awk '{print $1" "$2}' "$TMPD/host_key.pub")
OK_=$(awk '{print $1" "$2}' "$TMPD/other_host_key.pub")
printf '[%s]:%s %s\n' "$OSUM_GW" "$HOSTPORT" "$OK_" > "$TMPD/kh_bad"
: > "$TMPD/kh_empty"
cp "$TMPD/kh_empty" "$TMPD/kh_new"

TARGET="root@$OSUM_GW"
COMMON="-p $HOSTPORT -i /etc/id_ed25519"
SCPC="-P $HOSTPORT -i /etc/id_ed25519"
cat > "$TMPD/t.sh" <<GUEST
/bin/echo T1
/bin/ssh $COMMON -o UserKnownHostsFile=/etc/kh_new $TARGET 'echo SSHOK:\$((6*7))'
/bin/echo RC1:\$?
/bin/echo T2
/bin/ssh $COMMON -o UserKnownHostsFile=/etc/kh_new $TARGET 'echo SECOND:\$((6*7))'
/bin/echo RC2:\$?
/bin/echo T3
/bin/ssh $COMMON -o UserKnownHostsFile=/etc/kh_new $TARGET 'exit 7'
/bin/echo RC3:\$?
/bin/echo T4
/bin/ssh -p $HOSTPORT -i /etc/wrong_ed25519 -w nopass -o UserKnownHostsFile=/etc/kh_new $TARGET 'echo SHOULDNOT'
/bin/echo RC4:\$?
/bin/echo T5
/bin/ssh $COMMON -o UserKnownHostsFile=/etc/kh_bad $TARGET 'echo CHANGEDOK'
/bin/echo RC5:\$?
/bin/echo T6
/bin/ssh $COMMON -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/etc/kh_empty $TARGET 'echo STRICTOK'
/bin/echo RC6:\$?
/bin/echo T7
/bin/scp $SCPC -o UserKnownHostsFile=/etc/kh_new /d/blob.bin $TARGET:$UPDIR/up.bin
/bin/echo RC7:\$?
/bin/echo T8
/bin/scp $SCPC -o UserKnownHostsFile=/etc/kh_new $TARGET:$UPDIR/up.bin /d/down.bin
/bin/echo RC8:\$?
/bin/shasum /d/down.bin
/bin/echo T9
/bin/sftp $SCPC -o UserKnownHostsFile=/etc/kh_new $TARGET pwd
/bin/echo RC9:\$?
/bin/echo T10
/bin/sftp $SCPC -o UserKnownHostsFile=/etc/kh_new $TARGET put /d/blob.bin $UPDIR/sftp_up.bin
/bin/echo RC10:\$?
/bin/echo T11
/bin/sftp $SCPC -o UserKnownHostsFile=/etc/kh_new $TARGET get $UPDIR/sftp_up.bin /d/sftp_down.bin
/bin/echo RC11:\$?
/bin/shasum /d/sftp_down.bin
/bin/echo T12
/bin/sftp $SCPC -o UserKnownHostsFile=/etc/kh_new $TARGET ls $UPDIR
/bin/echo RC12:\$?
/bin/echo $DONE_MARK
GUEST

printf '# name:art:befehl\nt:once:/bin/sh /etc/t.sh\nende:ctrl:/bin/sleep 600\n' > "$TMPD/inittab"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
DIRS="/bin/ /sbin/ /etc/ /d/ /tmp/"
SPEC=""
for p in $PROGS; do
    case $p in init) SPEC="$SPEC /sbin/init=$TMPD/$p.elf@755:0:0" ;; *) SPEC="$SPEC /bin/$p=$TMPD/$p.elf" ;; esac
done
ETC="/etc/passwd=$TMPD/passwd@644:0:0 /etc/inittab=$TMPD/inittab@644:0:0 /etc/t.sh=$TMPD/t.sh@644:0:0
     /etc/id_ed25519=$TMPD/id_ed25519@600:0:0 /etc/wrong_ed25519=$TMPD/wrong_ed25519@600:0:0
     /etc/kh_new=$TMPD/kh_new@644:0:0 /etc/kh_bad=$TMPD/kh_bad@644:0:0 /etc/kh_empty=$TMPD/kh_empty@644:0:0"
DATA="/d/blob.bin=$TMPD/blob.bin@644:0:0"

make_image() { # out
    bash tools/mkfsfi/mkfs.sh build "$1" $BLOCKS $DIRS $SPEC $ETC $DATA >"$TMPD/mkfs.txt" 2>&1 \
        || { bad "mkfs failed"; sed 's/^/        /' "$TMPD/mkfs.txt"; return 1; }
}

QPID=""
run_guest() { # image serial
    local img=$1 ser=$2
    rm -f "$ser"
    timeout 600 qemu-system-x86_64 $ACCEL -kernel "$TMPD/k.mb" -m 512 \
        -append "osum nokbd nic nip=$OSUM_IP/24 ngw=$OSUM_GW" \
        -serial "file:$ser" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -netdev "user,id=n0" -device "virtio-net-pci,netdev=n0,mac=52:54:00:5b:1d:02" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    QPID=$!
    local i=0
    while [ $i -lt 2800 ]; do
        grep -qa "$DONE_MARK" "$ser" 2>/dev/null && break
        kill -0 "$QPID" 2>/dev/null || break
        sleep 0.2; i=$((i+1))
    done
    osum_kill_tree "$QPID"
    wait "$QPID" 2>/dev/null
    QPID=""
}
field() { tr -d '\000\r' < "$1" | grep -a "^$2" | head -1 | sed "s/^$2//"; }

make_image "$TMPD/disk.img" && ok "image with keys, known_hosts files and a 30000 octet blob"
cp "$TMPD/disk.img" "$TMPD/live.img"

echo "== 3. guest ssh/scp against OpenSSH =="
run_guest "$TMPD/live.img" "$TMPD/run.txt"
S="$TMPD/run.txt"
grep -qa "$DONE_MARK" "$S" && ok "guest script ran to the end" || { bad "guest script did not finish"; tr -d '\000' < "$S" | tail -15 | sed 's/^/        /'; }
is "key login runs a remote command (6*7 evaluated by the host shell)" "$(field "$S" SSHOK:)" "42"
is "exit status 0" "$(field "$S" RC1:)" "0"
grep -qa 'host key added' "$S" && ok "unknown host key was added to known_hosts" || bad "no 'host key added' line"
is "second login with known host key" "$(field "$S" SECOND:)" "42"
is "second login exit status" "$(field "$S" RC2:)" "0"
is "remote exit 7 reaches the guest" "$(field "$S" RC3:)" "7"
is "wrong key and wrong password is refused" "$(field "$S" RC4:)" "255"
if tr -d '\000' < "$S" | grep -qa 'SHOULDNOT'; then bad "wrong key got a command through"; else ok "no output from the refused login"; fi
is "changed host key is refused" "$(field "$S" RC5:)" "255"
if tr -d '\000' < "$S" | grep -qa 'CHANGEDOK'; then bad "changed host key let the command run"; else ok "no command ran against the changed key"; fi
grep -qa 'HOST KEY CHANGED' "$S" && ok "warning about the changed host key" || bad "no changed-key warning"
is "StrictHostKeyChecking=yes refuses an unknown host" "$(field "$S" RC6:)" "255"
if tr -d '\000' < "$S" | grep -qa 'STRICTOK'; then bad "strict mode let the command run"; else ok "no command ran in strict mode"; fi
is "scp upload exit status" "$(field "$S" RC7:)" "0"
HOSTSUM=$(sha256sum "$UPDIR/up.bin" 2>/dev/null | cut -d' ' -f1)
is "uploaded file: SHA-256 on the host equals the original" "$HOSTSUM" "$BLOBSUM"
is "scp download exit status" "$(field "$S" RC8:)" "0"
GUESTSUM=$(tr -d '\000\r' < "$S" | grep -a ' /d/down.bin' | head -1 | cut -d' ' -f1)
is "downloaded file: SHA-256 in the guest equals the original" "$GUESTSUM" "$BLOBSUM"
is "sftp pwd exit status" "$(field "$S" RC9:)" "0"
tr -d '\000\r' < "$S" | sed -n '/^T9$/,/^RC9:/p' | grep -aq '^/' && ok "sftp pwd prints an absolute path" || bad "sftp pwd printed no path"
is "sftp put exit status" "$(field "$S" RC10:)" "0"
is "sftp put: SHA-256 on the host equals the original" "$(sha256sum "$UPDIR/sftp_up.bin" 2>/dev/null | cut -d' ' -f1)" "$BLOBSUM"
is "sftp get exit status" "$(field "$S" RC11:)" "0"
is "sftp get: SHA-256 in the guest equals the original" "$(tr -d '\000\r' < "$S" | grep -a ' /d/sftp_down.bin' | head -1 | cut -d' ' -f1)" "$BLOBSUM"
is "sftp ls exit status" "$(field "$S" RC12:)" "0"
lsout=$(tr -d '\000\r' < "$S" | sed -n '/^T12$/,/^RC12:/p')
echo "$lsout" | grep -aq 'sftp_up.bin' && echo "$lsout" | grep -aq 'up.bin' && ok "sftp ls lists both uploaded files" || bad "sftp ls misses the files"
accepted=$(grep -c 'Accepted publickey' "$TMPD/sshd.log")
[ "$accepted" -ge 5 ] && ok "OpenSSH booked $accepted publickey logins" || bad "only $accepted accepted logins in the host log"

[ "$fail" -gt 0 ] && { note "guest output:"; tr -d '\000\r' < "$S" | sed -n '/^T7$/,/^T9$/p' | sed 's/^/        | /'; }

echo "== 4. counter-probes: weakened clients must fail the same script =="
rm -rf "$TMPD/umut"
cp -r kernel/user "$TMPD/umut"
sed -i 's/if state == hosts.HOST_CHANGED {/if state == 99 {/; s/if opt_strict == STRICT_YES {/if opt_strict == 99 {/' "$TMPD/umut/sshconn.fi"
if build_prog "$TMPD/umut" ssh "$TMPD/ssh_mut.elf"; then
    cp "$TMPD/ssh.elf" "$TMPD/ssh_good.elf"
    cp "$TMPD/ssh_mut.elf" "$TMPD/ssh.elf"
    SPEC=${SPEC/$TMPD\/ssh_good.elf/}
    make_image "$TMPD/mut.img" || true
    cp "$TMPD/ssh_good.elf" "$TMPD/ssh.elf"
    run_guest "$TMPD/mut.img" "$TMPD/mut.txt"
    M="$TMPD/mut.txt"
    is "mutant (changed-key check off): the changed key is accepted" "$(field "$M" RC5:)" "0"
    is "mutant (strict check off): an unknown host is accepted" "$(field "$M" RC6:)" "0"
else
    bad "the mutant does not build"; head -5 "$TMPD/essh" | sed 's/^/        /'
fi

echo "SSHCLIENT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
