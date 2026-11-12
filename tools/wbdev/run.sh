#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=${KEEP:-$(mktemp -d)}; mkdir -p "$D"
trap '[ -n "${KEEP:-}" ] || rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
. tools/lib/firnenv.sh
finish() { echo "WBDEV: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
BIG_BYTES=${BIG_BYTES:-524288}
NVME_WRITE_RATIO=${NVME_WRITE_RATIO:-4}
NVME_FLUSH_RATIO=${NVME_FLUSH_RATIO:-10}
AHCI_RATIO=${AHCI_RATIO:-3}
APPENDS=${APPENDS:-40}
KERNEL_IN=${KERNEL:-}

echo "== 1. build =="
PROGS="sh cat shasum echo wbcopy"
mkdir -p "$D/bin" "$D/usrc"
cp -r kernel/user/. "$D/usrc/"
cp tools/wbdev/wbcopy.fi "$D/usrc/wbcopy.fi"
USRC="$D/usrc" bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
if [ -n "$KERNEL_IN" ]; then
    cp "$KERNEL_IN" "$D/k.img"
else
    ./tools/build-kernel.sh "$D/k.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; finish; }
fi
head -c "$BIG_BYTES" /dev/urandom > "$D/big.bin"
WANT=$(sha256sum "$D/big.bin" | cut -d' ' -f1)
: > "$D/log.txt"
{
    echo 'wbcopy /t/big /tmp/copy'
    for i in $(seq 1 "$APPENDS"); do echo "echo append-line-$i-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx >> /tmp/log"; printf 'append-line-%s-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$i" >> "$D/log.txt"; done
    echo 'shasum /tmp/copy'
    echo 'shasum /tmp/log'
    echo 'echo ==END=='
} > "$D/s1.sh"
printf 'shasum /tmp/copy\nshasum /tmp/log\necho ==END==\n' > "$D/s2.sh"
LOGWANT=$(sha256sum "$D/log.txt" | cut -d' ' -f1)
SPEC="/bin/ /t/ /tmp/ /proc/ /dev/ /var/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$D/bin/$p.elf"; done
bash tools/mkfsfi/mkfs.sh build "$D/d.img" 16384 $SPEC "/t/s1.sh=$D/s1.sh" "/t/s2.sh=$D/s2.sh" "/t/big=$D/big.bin" > "$D/mkfs.txt" 2>&1 \
    && ok "image built" || { bad "mkfs"; tail -3 "$D/mkfs.txt"; finish; }

declare -A cmds
boot() {
    local name=$1 drive=$2 words=$3 script=$4 img=$5
    local dev tr
    if [ "$drive" = nvme ]; then
        dev=(-device nvme,drive=d0,serial=wbdev)
        tr=(-trace "pci_nvme_write" -trace "pci_nvme_flush_ns,file=$D/$name.t")
    else
        dev=(-device ahci,id=ahci -device ide-hd,drive=d0,bus=ahci.0)
        tr=(-trace "ahci_populate_sglist,file=$D/$name.t")
    fi
    timeout 300 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k.img" -m 512 \
        -append "osum nokbd vfs $words script=sh $script;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$img,format=raw,if=none,id=d0" "${dev[@]}" "${tr[@]}" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    touch "$D/$name.t"
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
count() { local c; c=$(grep -c "$2" "$D/$1" 2>/dev/null); echo "${c:-0}"; }

echo "== 2. runs =="
for drive in nvme ahci; do
    for mode in off on; do
        words=""
        [ "$mode" = off ] && words="nowbdev"
        cp "$D/d.img" "$D/d-$drive-$mode.img"
        boot "$drive-$mode-1" "$drive" "$words" /t/s1.sh "$D/d-$drive-$mode.img"
        boot "$drive-$mode-2" "$drive" "$words" /t/s2.sh "$D/d-$drive-$mode.img"
    done
done

echo "== 3. checks =="
for drive in nvme ahci; do
    for mode in off on; do
        for r in 1 2; do
            n="$drive-$mode-$r"
            grep -aq "rootsel: $drive" "$D/$n.klar" && ok "$n: root on $drive" || bad "$n: root not on $drive"
            [ "$(grep -ac "^$WANT  /tmp/copy" "$D/$n.klar")" -ge 1 ] && ok "$n: copy hash matches" || bad "$n: copy hash differs"
            [ "$(grep -ac "^$LOGWANT  /tmp/log" "$D/$n.klar")" -ge 1 ] && ok "$n: appended log hash matches" || bad "$n: log hash differs"
            grep -aq "==END==" "$D/$n.klar" && ok "$n: script finished" || bad "$n: script did not finish"
        done
    done
done
nw_off=$(count nvme-off-1.t pci_nvme_write); nw_on=$(count nvme-on-1.t pci_nvme_write)
nf_off=$(count nvme-off-1.t pci_nvme_flush_ns); nf_on=$(count nvme-on-1.t pci_nvme_flush_ns)
aw_off=$(( $(count ahci-off-1.t ahci_populate_sglist) - $(count ahci-off-2.t ahci_populate_sglist) ))
aw_on=$(( $(count ahci-on-1.t ahci_populate_sglist) - $(count ahci-on-2.t ahci_populate_sglist) ))
echo "  nvme writes: off=$nw_off on=$nw_on; flushes: off=$nf_off on=$nf_on; ahci commands (minus read-only run): off=$aw_off on=$aw_on"
[ "$nw_on" -gt 0 ] && [ $(( nw_on * NVME_WRITE_RATIO )) -le "$nw_off" ] \
    && ok "nvme: at least ${NVME_WRITE_RATIO}x fewer write commands ($nw_off -> $nw_on)" || bad "nvme write ratio too small ($nw_off -> $nw_on)"
[ "$nf_on" -gt 0 ] && [ $(( nf_on * NVME_FLUSH_RATIO )) -le "$nf_off" ] \
    && ok "nvme: at least ${NVME_FLUSH_RATIO}x fewer flush commands ($nf_off -> $nf_on)" || bad "nvme flush ratio too small ($nf_off -> $nf_on)"
[ "$aw_on" -gt 0 ] && [ $(( aw_on * AHCI_RATIO )) -le "$aw_off" ] \
    && ok "ahci: at least ${AHCI_RATIO}x fewer commands ($aw_off -> $aw_on)" || bad "ahci command ratio too small ($aw_off -> $aw_on)"
[ "$nw_off" -ge $(( BIG_BYTES / 512 )) ] && ok "off: one nvme write per sector ($nw_off)" || bad "off: fewer nvme writes than sectors ($nw_off)"
finish
