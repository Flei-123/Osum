#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vaultprompt/run.sh -- r2480: the consent window for "reveal a saved password" (/bin/vaultprompt) and the vaultd side.
#
#   /root/jarvis/bin/heavy bash tools/vaultprompt/run.sh
#
# Part A (headless guest, vaultd with /bin/vpstub as the prompt): allow shows the login, deny / timeout / no-UI / hang
#   (killed after the deadline) show an error and NEVER the password; the daemon keeps serving afterwards; the stub gets
#   origin, user, requester and seconds as arguments.
# Part B (headless guest, shipped default path): without a session there is nobody to ask -> noprompt, no password;
#   `vaultprompt` itself exits 3 without a surface and 4 on bad arguments.
# Part C (display guest): the window matches the HTML mockup (SSIM >= 0.95), Allow / Deny / timeout are reported.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
TMPD=$(mktemp -d)
[ -n "${VAULTPROMPT_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
hx() { python3 -I -c 'import sys; sys.stdout.write(sys.argv[1].encode().hex())' "$1"; }

PW1="correct-horse-battery"; LPW="s3cr3t-pw-7"; USER1="alice"
H_PW1=$(hx "$PW1"); H_LPW=$(hx "$LPW"); H_USR=$(hx "$USER1")
ID_ALLOW=00000000000000000000000000000a01
ID_DENY=00000000000000000000000000000a02
ID_TIMEOUT=00000000000000000000000000000a03
ID_UI=00000000000000000000000000000a04
ID_HANG=00000000000000000000000000000a05
SECS=3
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh ls cat echo sleep mkdir vaultd vaultctl vaultprompt vpstub"
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20
    echo "VAULTPROMPT: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "VAULTPROMPT: $pass passed, $fail failed"; exit 1
fi
for l in de en; do
    miss=0
    for k in title head note site user from self hint allow deny; do
        n=$(grep -c "^vaultprompt\.$k = " locale/$l/messages)
        [ "$n" = 1 ] || { miss=$((miss+1)); echo "    key vaultprompt.$k: $n entries in $l"; }
    done
    [ "$miss" = 0 ] && ok "locale $l: 10 keys, each exactly once" || bad "locale $l: $miss keys missing or duplicated"
done
grep -q 'vaultd vaultctl vaultprompt' tools/usbimg/build.sh && ok "usbimg PROGS has vaultprompt" || bad "usbimg PROGS"
grep -q '/bin/vaultctl /bin/vaultprompt' tools/usbimg/build.sh && ok "usbimg PFLICHT has vaultprompt" || bad "usbimg PFLICHT"

printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'root:x:0:\n' > "$TMPD/group"
printf 'kib=64\npasses=1\nlanes=1\n' > "$TMPD/kdf"

image() {
    local img=$1 script=$2
    local -a A=(build "$img" 20000 /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /etc/vault/ /secrets/ /var/ /var/log/ /run/)
    local p
    for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    A+=("/etc/passwd=$TMPD/passwd" "/etc/group=$TMPD/group" "/etc/vault/kdf=$TMPD/kdf" "/t/s.sh=$script")
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
}
run() {
    local img=$1 nm=$2 secs=${3:-240}
    rm -f "$TMPD/$nm.txt"
    timeout "$secs" qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
        -kernel "$TMPD/k0.img" -m 512 \
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

seed() {
    cat <<EOS
sleep -m 500
vaultctl create pw=$PW1
vaultctl put id=$ID_ALLOW title=A origins=allow.test username=$USER1 password=$LPW
vaultctl put id=$ID_DENY title=D origins=deny.test username=$USER1 password=$LPW
vaultctl put id=$ID_TIMEOUT title=T origins=timeout.test username=$USER1 password=$LPW
vaultctl put id=$ID_UI title=U origins=ui.test username=$USER1 password=$LPW
vaultctl put id=$ID_HANG title=H origins=hang.test username=$USER1 password=$LPW
EOS
}

echo "== 2. part A: stub prompt =="
{
    echo "vaultd /secrets 30000 /bin/vpstub $SECS &"
    seed
    for t in ALLOW DENY TIMEOUT UI HANG ALLOW2; do
        id=ID_${t%2}
        [ "$t" = HANG ] && echo "sleep -m 20000"
        echo "echo ==R-$t=="
        echo "vaultctl reveal id=${!id}"
        echo "echo rc=\$?"
    done
    echo "echo ==R-NOID=="
    echo "vaultctl reveal id=00000000000000000000000000000fff"
    echo "echo ==FERTIG=="
} > "$TMPD/sa.sh"
image "$TMPD/A.img" "$TMPD/sa.sh"
run "$TMPD/A.img" a 300
A="$TMPD/a.klar"
grep -qa "==FERTIG==" "$A" || { bad "part A did not reach the end"; tail -15 "$A" | sed 's/^/        /'; }
part "$A" R-ALLOW R-DENY > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "allow: the reveal succeeds"
has "$TMPD/p.txt" "$H_LPW" "allow: the password comes back"
has "$TMPD/p.txt" "$H_USR" "allow: the user name comes back"
has "$TMPD/p.txt" "vpstub: args 6 allow.test alice" "the prompt gets origin and user as arguments"
has "$TMPD/p.txt" " $SECS" "the prompt gets the wait time as an argument"
part "$A" R-DENY R-TIMEOUT > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=declined" "deny: err=declined"
hasnot "$TMPD/p.txt" "$H_LPW" "COUNTER-PROOF: deny leaks no password"
hasnot "$TMPD/p.txt" "password=" "COUNTER-PROOF: deny has no password field"
part "$A" R-TIMEOUT R-UI > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=timeout" "prompt exit 2: err=timeout"
hasnot "$TMPD/p.txt" "$H_LPW" "timeout leaks no password"
part "$A" R-UI R-HANG > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=noprompt" "prompt exit 3: err=noprompt"
hasnot "$TMPD/p.txt" "$H_LPW" "no UI leaks no password"
part "$A" R-HANG R-ALLOW2 > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=timeout" "a hanging prompt is killed after the deadline: err=timeout"
hasnot "$TMPD/p.txt" "$H_LPW" "hang leaks no password"
part "$A" R-ALLOW2 R-NOID > "$TMPD/p.txt"
has "$TMPD/p.txt" "$H_LPW" "the daemon serves again after a killed prompt"
part "$A" R-NOID FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=notfound" "unknown id: notfound, no prompt"
hasnot "$TMPD/p.txt" "vpstub: args" "... and the prompt was not started"

echo "== 3. part B: shipped default, no session =="
{
    echo "vaultd /secrets 30000 &"
    seed
    cat <<EOS
echo ==B-REVEAL==
vaultctl reveal id=$ID_ALLOW
echo rc=\$?
echo ==B-PROMPT==
vaultprompt reveal github.com alice - 5
echo rc=\$?
echo ==B-USAGE==
vaultprompt frob
echo rc=\$?
echo ==FERTIG==
EOS
} > "$TMPD/sb2.sh"
image "$TMPD/B.img" "$TMPD/sb2.sh"
run "$TMPD/B.img" b 240
B="$TMPD/b.klar"
grep -qa "==FERTIG==" "$B" || { bad "part B did not reach the end"; tail -15 "$B" | sed 's/^/        /'; }
part "$B" B-REVEAL B-PROMPT > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=noprompt" "no session: err=noprompt"
hasnot "$TMPD/p.txt" "$H_LPW" "no session: no password"
part "$B" B-PROMPT B-USAGE > "$TMPD/p.txt"
has "$TMPD/p.txt" "vaultprompt: no surface" "vaultprompt without a display says so"
has "$TMPD/p.txt" "rc=3" "... and exits 3"
part "$B" B-USAGE FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "usage: vaultprompt" "bad arguments: usage text"
has "$TMPD/p.txt" "rc=4" "... and exit 4"

echo "== 4. part C: the window =="
B2=tools/alltag/build.sh
CPROGS="vaultprompt theme sh echo ls cat"
cwin() { # name secs keys...
    local nm=$1 secs=$2; shift 2
    local m="" c
    for c in "$@"; do m="$m mon=sendkey\ $c mon=warte\ 1"; done
    eval bash "$B2" "$TMPD/$nm" kbd=yes uitrace=yes lang=en warten=10 \
        extra=\"wigapp=/bin/vaultprompt,reveal,github.com,alice,-,$secs\" progs=\"$CPROGS\" \
        xfile=/etc/wallpaper=assets/wallpaper-sea.osym $m > "$TMPD/$nm.log" 2>&1
}
cwin c1 60
S=$TMPD/c1/serial.txt
has "$S" "vaultprompt: ready" "the window opens"
N=$(grep -ac 'vaultprompt: rect ' "$S")
[ "$N" -ge 3 ] && ok "the host reports $N controls" || bad "controls: $N, expected >= 3"
if [ -s "$TMPD/c1/desktop.png" ]; then
    sc=$(python3 -I tools/mockup/ssim.py /root/jarvis/data/projects_kb/orientos/reports/mockups/vaultprompt.png "$TMPD/c1/desktop.png" auto "$TMPD/crop.png" 2>&1 | tail -1)
    v=$(echo "$sc" | sed -n 's/.*"ssim": *\([0-9.]*\).*/\1/p')
    python3 -I -c "import sys; sys.exit(0 if float('${v:-0}') >= 0.95 else 1)" && ok "mockup match: $sc" || bad "mockup match: $sc"
    [ -n "${VAULTPROMPT_SHOT:-}" ] && cp "$TMPD/crop.png" "$VAULTPROMPT_SHOT"
else
    bad "no screenshot"
fi
cwin c2 60 tab tab ret
has "$TMPD/c2/serial.txt" "vaultprompt: allow" "Tab (details), Tab (Allow), Enter: allow"
hasnot "$TMPD/c2/serial.txt" "vaultprompt: deny" "... and not deny"
cwin c3 60 tab tab tab ret
has "$TMPD/c3/serial.txt" "vaultprompt: deny" "Tab x3, Enter: deny"
hasnot "$TMPD/c3/serial.txt" "vaultprompt: allow" "COUNTER-PROOF: deny never says allow"
cwin c4 4
has "$TMPD/c4/serial.txt" "vaultprompt: timeout" "no answer: timeout"
hasnot "$TMPD/c4/serial.txt" "vaultprompt: allow" "COUNTER-PROOF: a timeout never says allow"
for d in c1 c2 c3 c4; do
    c=$(grep -acE 'ABSTURZ|EXCEPTION' "$TMPD/$d/serial.txt" 2>/dev/null; true)
    [ "$c" = 0 ] || bad "crash lines in $d: $c"
done
echo "VAULTPROMPT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
