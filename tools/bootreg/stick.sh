#!/bin/bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
STICK_IMG=${STICK_IMG:?usage: STICK_IMG=<stick.img> bash tools/bootreg/stick.sh}
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
D=$(mktemp -d /root/abbilder/bootregstick.XXXXXX)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"' EXIT
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
SLUG=$MARKE_KURZ
NAME=$MARKE_PRODUKT
LEGACY=$(grep -v '^#' tools/marke/legacy-slugs.txt | head -1)
MARK_WIN="PROOF-WINDOWS-$$"
OFF=$((2048*512))
REG_RE="bootreg: (registered|already|NOT FOUND|FAILED)"
KERNEL_RE="Osum|osum"

mkdir -p "$D/efi"
bash tools/bootreg/build.sh "$D/efi" proof win "$MARK_WIN" fail || exit 1
mcopy -i "$STICK_IMG@@$OFF" ::EFI/BOOT/BOOTX64.EFI "$D/limine.efi" || exit 1
mcopy -i "$STICK_IMG@@$OFF" ::osum.mb "$D/osum.mb" || exit 1
mcopy -i "$STICK_IMG@@$OFF" ::limine.conf "$D/stick.conf" || exit 1

blank() { dd if=/dev/null of="$1" bs=1M seek="$2" 2> /dev/null; }

mkdisk() {
    local out=$1 dir=$2 esp="$D/esp.img"
    blank "$out" 1024
    sgdisk -o -n 1:2048:+200M -t 1:ef00 -c 1:EFI -n 2:0:+16M -t 2:0c01 -c 2:MSR -n 3:0:+300M -t 3:0700 -c 3:Basic \
        -n 4:0:+100M -t 4:2700 -c 4:Recovery "$out" > /dev/null || return 1
    blank "$esp" 200
    mkfs.fat -F 32 -s 1 "$esp" > /dev/null || return 1
    mmd -i "$esp" ::EFI ::EFI/Microsoft ::EFI/Microsoft/Boot "::EFI/$dir" || return 1
    mcopy -i "$esp" "$D/efi/win.efi" ::EFI/Microsoft/Boot/bootmgfw.efi || return 1
    mcopy -i "$esp" "$D/limine.efi" "::EFI/$dir/BOOTX64.EFI" || return 1
    mcopy -i "$esp" "$D/osum.mb" "::EFI/$dir/osum.mb" || return 1
    printf 'timeout: 1\ndefault_entry: 1\n\n/%s\n    protocol: multiboot1\n    path: boot():/EFI/%s/osum.mb\n    cmdline: osum vfs nosched noproc nofs\n' \
        "$NAME" "$dir" > "$D/disk.conf"
    mcopy -i "$esp" "$D/disk.conf" ::limine.conf || return 1
    dd if="$esp" of="$out" bs=512 seek=2048 conv=notrunc 2> /dev/null || return 1
    rm -f "$esp"
}

mkstick() {
    local out=$1
    cp "$STICK_IMG" "$out"
    awk -v want="/Register" 'BEGIN{p=0} /^\/[^\/]/{p=(index($0,want)==1)} p{print}' "$D/stick.conf" > "$D/reg_entry.txt"
    [ -s "$D/reg_entry.txt" ] || return 1
    { printf 'timeout: 1\ndefault_entry: 1\n\n'; cat "$D/reg_entry.txt"; } > "$D/stick_test.conf"
    mcopy -i "$out@@$OFF" -o "$D/stick_test.conf" ::limine.conf
}

qrun() {
    local tag=$1 vars=$2 pat=$3 secs=$4; shift 4
    local drives=() i=0 img total=$#
    for img in "$@"; do
        drives+=(-drive "file=$img,format=raw,if=none,id=d$i" -device "virtio-blk-pci,drive=d$i,bootindex=$((total-1-i))")
        i=$((i+1))
    done
    : > "$D/$tag.txt"
    timeout $((secs+20)) qemu-system-x86_64 "${KVM[@]}" -machine q35 -m 2048 -smp 2 \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$vars" \
        "${drives[@]}" -serial "file:$D/$tag.txt" -display none -no-reboot > /dev/null 2>&1 &
    local pid=$! n=0
    while [ $n -lt $((secs*2)) ]; do
        grep -aqE "$pat" "$D/$tag.txt" 2>/dev/null && { sleep 6; break; }
        sleep 0.5; n=$((n+1))
    done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return 0
}
clean() { tr -d '\r' < "$D/$1.txt" | sed 's/\x1b\[[0-9;=?]*[A-Za-z]//g'; }

mkstick "$D/stick.img" || { echo "BOOTREGSTICK: stick has no Register entry"; exit 1; }
ok "stick limine.conf carries the Register entry"

for DIR in "$SLUG" "$LEGACY"; do
    echo "== loader dir \\EFI\\$DIR"
    mkdisk "$D/disk.img" "$DIR" || { echo "BOOTREGSTICK: disk build failed"; exit 1; }
    SHA_WIN=$(mcopy -i "$D/disk.img@@$OFF" ::EFI/Microsoft/Boot/bootmgfw.efi - | sha256sum)
    cp "$OVMF_VARS" "$D/v.fd"
    qrun X "$D/v.fd" "$KERNEL_RE" 40 "$D/disk.img"
    grep -aqE "$KERNEL_RE" "$D/X.txt" && bad "$DIR: fresh firmware already boots the loader (no counter-proof)" || ok "$DIR: counter-proof: fresh NVRAM + disk only does not reach the kernel"
    qrun R "$D/v.fd" "$REG_RE" 120 "$D/disk.img" "$D/stick.img"
    clean R | grep -a "bootreg: " | head -3
    clean R | grep -aq "bootreg: registered Boot[0-9A-F]\{4\} $NAME -> .*\\\\EFI\\\\$DIR\\\\BOOTX64.EFI verified" \
        && ok "$DIR: Limine menu entry chainloaded bootreg, registered and verified" || bad "$DIR: not registered: $(clean R | tail -c 300 | tr '\n' ' ')"
    qrun B "$D/v.fd" "$KERNEL_RE" 120 "$D/disk.img"
    grep -aqE "$KERNEL_RE" "$D/B.txt" && ok "$DIR: stick removed, firmware boots Limine+kernel from the NVRAM entry" || bad "$DIR: nothing booted without stick: $(clean B | tail -c 200 | tr '\n' ' ')"
    grep -aq "$MARK_WIN" "$D/B.txt" && bad "$DIR: Windows proof started instead" || ok "$DIR: Windows proof not started"
    [ "$(mcopy -i "$D/disk.img@@$OFF" ::EFI/Microsoft/Boot/bootmgfw.efi - | sha256sum)" = "$SHA_WIN" ] && ok "$DIR: Windows boot manager file unchanged" || bad "$DIR: Windows file changed"
done

echo "BOOTREGSTICK: $pass ok, $fail fail"
[ "$fail" = 0 ]
