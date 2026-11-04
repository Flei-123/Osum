#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
num() {
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "${value:-}" ]; then bad "$name: no number (want $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"; else bad "$name: $value, want $op $want"; fi
}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
finish() { echo "CLASSES-DEVICES: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
calls() { grep -aoE "^# class-calls $2=[0-9]+" "$1" | tail -1 | cut -d= -f2; }
found() { grep -aoE "^$2 [a-z]+ [^ ]+ found=[0-9?]+" "$1" | head -1 | sed 's/.*found=//'; }

echo "== 1. build =="
PROGS="sh cat echo"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; finish; }
printf 'echo ==DRIVERS==\ncat /proc/drivers\necho ==END==\n' > "$D/s.sh"
bash tools/mkfsfi/mkfs.sh build "$D/d.img" 8192 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"

echo "== 2. static: every device class reaches its driver through a table =="
for f in audio:kernel/drv/snd/audioclass.fi input:kernel/drv/hid/inputclass.fi display:kernel/gfx/displayclass.fi; do
    n=${f%%:*}; p=${f#*:}
    has "$p" "fn null_ops()" "$n class has a null table"
done
for drv in hda ac97; do
    num "audio.fi reaches $drv only through ${drv}.ops()" "$(grep -cE "${drv}\.ops\(\)" kernel/drv/snd/audio.fi)" eq 1
done
for drv in ps2m i2chid; do
    num "gfx.fi reaches $drv only through ${drv}.ops()" "$(grep -cE "${drv}\.ops\(\)" kernel/gfx/gfx.fi)" eq 1
done
for drv in vgpu vmsvga; do
    num "gfx.fi reaches $drv only through ${drv}.ops()" "$(grep -cE "${drv}\.ops\(\)" kernel/gfx/gfx.fi)" eq 1
done
for w in noaudclass noinclass nodisclass nomatch; do
    has kernel/lib/kstate.fi "M_$(echo "$w" | tr a-z A-Z)" "kernel word $w exists"
done
for drv in ahci nvme; do
    num "$drv binds through drvreg.find" "$(grep -c "drvreg.find" kernel/drv/blk/$drv.fi)" ge 1
done
for drv in hda ac97 ehci ohci vmsvga; do
    f=$(grep -rlE "drvreg\.find(_either)?\(" kernel/drv | grep "/$drv\.fi" | head -1)
    [ -n "$f" ] && ok "$drv binds through drvreg.find" || bad "$drv binds through drvreg.find"
done

runq() {
    local name=$1 words=$2; shift 2
    cp "$D/d.img" "$D/d-$name.img"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum nokbd vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=none,id=d0" -device ahci,id=a0 -device ide-hd,drive=d0,bus=a0.0 "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
runide() {
    local name=$1 words=$2; shift 2
    cp "$D/d.img" "$D/d-$name.img"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum nokbd vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}

echo "== 3. runs =="
HDA="-device intel-hda -device hda-duplex"
runq hda "audio nosounds" $HDA -vga vmware
runq hdano "audio nosounds noaudclass" $HDA -vga vmware
runq ac97 "audio nosounds" -device AC97 -vga vmware
runq ac97no "audio nosounds noaudclass" -device AC97 -vga vmware
runq none "audio nosounds" -vga vmware
runide hdanm "audio nosounds nomatch" $HDA -vga vmware
runq ahcinm "nomatch" -vga vmware
[ -n "${CLASSES_DUMP:-}" ] && cp "$D"/*.klar "$CLASSES_DUMP"/

echo "== 4. audio through the table and counter-proofs =="
has "$D/hda.klar" "hda: ready" "hda: backend ready through the table"
num "hda: class-calls audio counted" "$(calls "$D/hda.klar" audio)" ge 5
has "$D/hdano.klar" "# class-calls net-eth" "hda noaudclass: run still completes"
hasnot "$D/hdano.klar" "# class-calls audio" "hda noaudclass: no dispatch counted"
hasnot "$D/hdano.klar" "hda: ready" "hda noaudclass: null table, backend never ready"
num "ac97: class-calls audio counted" "$(calls "$D/ac97.klar" audio)" ge 3
hasnot "$D/ac97no.klar" "# class-calls audio" "ac97 noaudclass: no dispatch counted"
hasnot "$D/none.klar" "hda: ready" "no codec: no hda backend"

echo "== 5. table-driven binding =="
num "hda row found with HDA device" "$(found "$D/hda.klar" hda)" eq 1
num "ac97 row found with AC97 device" "$(found "$D/ac97.klar" ac97)" eq 1
num "ac97 row not found with HDA device" "$(found "$D/hda.klar" ac97)" eq 0
num "hda row not found with AC97 device" "$(found "$D/ac97.klar" hda)" eq 0
num "ahci row found" "$(found "$D/hda.klar" ahci)" eq 1
num "vmsvga row found with -vga vmware" "$(found "$D/hda.klar" vmsvga)" eq 1
has "$D/hda.klar" "osum: mount=1" "ahci root mounts through drvreg.find"
hasnot "$D/hdanm.klar" "hda: ready" "nomatch: find returns nothing, hda never initialised"
has "$D/hdanm.klar" "osum: ata0 sectors=8192" "nomatch: legacy ide root unaffected"
hasnot "$D/ahcinm.klar" "osum: mount=1" "nomatch: ahci root not found, no mount"
finish
