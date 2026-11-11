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

PW1="correct-horse-battery"; PIN1="482915"; PINBAD="590813"
ORIGIN="https://example.com"; USER1="alice"; LPW="s3cr3t-pw-7"
hx() { python3 -I -c 'import sys; sys.stdout.write(sys.argv[1].encode().hex())' "$1"; }
H_LPW=$(hx "$LPW")

: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

command -v swtpm >/dev/null 2>&1 || { echo "VAULTD-TPM: swtpm missing"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "VAULTD-TPM: qemu missing"; exit 1; }


echo "== 1. build + static =="
. tools/lib/firnenv.sh
PROGS="sh ls cat echo sleep mkdir grep su chmod vaultd vaultctl pinctl vaultui"
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "programs build"; else bad "programs do not build"; tail -15 "$TMPD/b.txt"; echo "VAULTUI: $pass passed, $fail failed"; exit 1; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "kernel builds"; else bad "kernel does not build"; tail -8 "$TMPD/k.txt"; echo "VAULTUI: $pass passed, $fail failed"; exit 1; fi
for l in de en; do
    miss=0
    for k in title head note pin unlock cancel ready bad short wait_a wait_b off noslot notpm nosvc open none fail; do
        n=$(grep -c "^vaultui\.$k = " locale/$l/messages)
        [ "$n" = 1 ] || { miss=$((miss+1)); echo "    key vaultui.$k: $n entries in $l"; }
    done
    [ "$miss" = 0 ] && ok "locale $l: 18 keys, each exactly once" || bad "locale $l: $miss keys missing or duplicated"
done
grep -q 'vaultprompt vaultui' tools/usbimg/build.sh && ok "usbimg PROGS has vaultui" || bad "usbimg PROGS"
grep -q '/bin/vaultprompt /bin/vaultui' tools/usbimg/build.sh && ok "usbimg PFLICHT has vaultui" || bad "usbimg PFLICHT"
[ "$(grep -hE '^[[:space:]]*//' kernel/user/vaultui.fi kernel/user/vaultcall.fi kernel/user/expvault.fi kernel/user/vuihost.fi tools/vaultui/run.sh | grep -vc SPDX)" = 0 ] && ok "no comments in the new modules" || bad "comments in the new modules"
python3 -I -c "
import re,sys
s=open('kernel/user/vaultui.fi',encoding='utf-8').read()
sys.exit(1 if re.search(r'\b(Falsch|Tresor|Fehler)\b',s) else 0)" && ok "vaultui source is English" || bad "German text in vaultui.fi"

for f in start.txt INFO symbol.osym symbol.svg symbol44.osym symbol64.osym; do
    [ -s assets/apps/vault.osp/$f ] || bad "bundle file missing: $f"
done
[ "$(grep -v '^#' assets/apps/vault.osp/start.txt | head -1)" = /bin/vaultui ] && ok "start menu bundle vault.osp starts /bin/vaultui" || bad "vault.osp start.txt"
grep -q '^name=Vault$' assets/apps/vault.osp/INFO && ! grep -q '^menu=hidden' assets/apps/vault.osp/INFO && ok "bundle is listed in the start menu (not hidden)" || bad "vault.osp INFO"
grep -q '/apps/vault.osp/start /apps/vault.osp/INFO /apps/vault.osp/symbol' tools/usbimg/build.sh && ok "usbimg PFLICHT has the vault bundle" || bad "usbimg PFLICHT bundle"
grep -q 'import expvault' kernel/user/explorer/expnav.fi && grep -q 'expvault.is_vault_dir(full)' kernel/user/explorer/expnav.fi && grep -q '/bin/vaultui' kernel/user/expvault.fi && ok "explorer opens the vault window for the /secrets folder" || bad "explorer vault hook"
sed 's/expvault.is_vault_dir(full)/false/' kernel/user/explorer/expnav.fi | grep -q 'expvault.is_vault_dir(full)' && bad "COUNTER-PROOF: hook removal not detected" || ok "COUNTER-PROOF: without the call the hook check turns red"
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
    bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
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
echo ==A-NOPIN==
vaultctl status
vaultui
echo ui-rc=\$?
echo ==A-SETUP==
pinctl set root $PIN1
vaultctl create pw=$PW1
vaultctl tpmenroll pin=$PIN1
vaultctl lock
echo ==A-STATUS==
vaultctl status
echo ==A-UI==
vaultui
echo ui-rc=\$?
echo ==A-BAD1==
vaultctl unlock pin=$PINBAD
echo ==A-BAD2==
vaultctl unlock pin=$PINBAD
echo ==A-BAD3==
vaultctl unlock pin=$PINBAD
echo ==A-BAD4==
vaultctl unlock pin=$PINBAD
echo ==A-BAD5==
vaultctl unlock pin=$PINBAD
echo ==A-DELAYED==
vaultctl unlock pin=$PIN1
vaultctl status
echo ==A-PW==
vaultctl unlock pw=$PW1
vaultctl status
echo ==FERTIG==
EOS

echo "== 2. boot A: swtpm, vaultd, the calls the window makes =="
image "$TMPD/A.img" "$TMPD/sa.sh"
run "$TMPD/A.img" a 500 tis
A="$TMPD/a.klar"
grep -qa "==FERTIG==" "$A" || { bad "boot A did not reach the end"; tail -15 "$A" | sed 's/^/        /'; }
part "$A" A-NOPIN A-SETUP > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=none" "no vault yet: status says none"
has "$TMPD/p.txt" "vaultui: no surface" "vaultui without a display says so"
has "$TMPD/p.txt" "ui-rc=3" "... and exits 3"
part "$A" A-STATUS A-UI > "$TMPD/p.txt"
has "$TMPD/p.txt" "state=locked" "locked vault"
has "$TMPD/p.txt" "pinunlock=1" "status offers the PIN unlock (the window enables the field)"
part "$A" A-UI A-BAD1 > "$TMPD/p.txt"
has "$TMPD/p.txt" "vaultui: no surface" "vaultui with a PIN-ready vault but no display: no surface"
for n in 1 2 3 4; do
    nx=$((n+1))
    part "$A" A-BAD$n A-BAD$nx > "$TMPD/p.txt"
    has "$TMPD/p.txt" "err=bad" "wrong PIN $n: err=bad (window: Wrong PIN)"
    hasnot "$TMPD/p.txt" "wait=" "wrong PIN $n: no delay yet"
done
part "$A" A-BAD5 A-DELAYED > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=bad" "wrong PIN 5: err=bad, the delay starts after it"
part "$A" A-DELAYED A-PW > "$TMPD/p.txt"
has "$TMPD/p.txt" "err=wait" "COUNTER-PROOF: the right PIN during the delay is refused (window: countdown)"
has "$TMPD/p.txt" "wait=60" "... with the delay in seconds"
has "$TMPD/p.txt" "state=locked" "... and the vault stays locked"
part "$A" A-PW FERTIG > "$TMPD/p.txt"
has "$TMPD/p.txt" "ok=1" "the password still opens the vault during the PIN delay"
has "$TMPD/p.txt" "state=open" "... and the status is open"

echo "== 3. part B: the window =="
B2=tools/alltag/build.sh
cwin() {
    local nm=$1; shift
    local m="" c
    for c in "$@"; do m="$m mon=sendkey\ $c mon=warte\ 1"; done
    eval bash "$B2" "$TMPD/$nm" kbd=yes uitrace=yes lang=en warten=10 \
        extra=\"bus wigapp=/bin/vaultui\" progs=\"vaultui theme sh echo ls cat\" \
        xfile=/etc/wallpaper=assets/wallpaper-sea.osym $m > "$TMPD/$nm.log" 2>&1
}
cwin w1
S=$TMPD/w1/serial.txt
has "$S" "vaultui: ready" "the window opens"
has "$S" "vaultui: state 7" "without vaultd the window reports 'service not running' (state 7)"
if [ -s "$TMPD/w1/desktop.png" ]; then
    sc=$(python3 -I tools/mockup/ssim.py /root/jarvis/data/projects_kb/orientos/reports/mockups/vaultui-nosvc.png "$TMPD/w1/desktop.png" auto "$TMPD/crop.png" 2>&1 | tail -1)
    v=$(echo "$sc" | sed -n 's/.*"ssim": *\([0-9.]*\).*/\1/p')
    python3 -I -c "import sys; sys.exit(0 if float('${v:-0}') >= 0.95 else 1)" && ok "mockup match: $sc" || bad "mockup match: $sc"
else
    bad "no screenshot"
fi
N=$(grep -ac 'vaultui: rect ' "$S")
[ "$N" -ge 3 ] && ok "the host reports $N controls" || bad "controls: $N, expected >= 3"
cwin w2 tab tab ret
has "$TMPD/w2/serial.txt" "vaultui: cancel" "Tab to Cancel, Enter: cancel"
hasnot "$TMPD/w2/serial.txt" "vaultui: unlock ok" "COUNTER-PROOF: cancel never unlocks"
for d in w1 w2; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$TMPD/$d/serial.txt" 2>/dev/null; true)
    [ "$c" = 0 ] || bad "crash lines in $d: $c"
done
if command -v swtpm >/dev/null 2>&1; then
    echo "== live guest (tools/vaultui/live.sh) =="
    LV=$(bash tools/vaultui/live.sh 2>&1)
    printf '%s\n' "$LV" | grep -a '^  \(OK\|FAIL\)\|^=='
    lp=$(printf '%s\n' "$LV" | sed -n 's/^VAULTUI-LIVE: \([0-9]*\) passed, \([0-9]*\) failed.*/\1/p')
    lf=$(printf '%s\n' "$LV" | sed -n 's/^VAULTUI-LIVE: \([0-9]*\) passed, \([0-9]*\) failed.*/\2/p')
    if [ -z "$lp" ]; then bad "live gate gave no result"; else pass=$((pass + lp)); fail=$((fail + lf)); fi
fi
echo "VAULTUI: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
