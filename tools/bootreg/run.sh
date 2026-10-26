#!/bin/bash
# bootreg gate: UEFI registrar app registers an NVRAM boot entry for a loader on another disk's ESP.
# QEMU + OVMF (persistent pflash vars): run A registers, run B boots ONLY the disk via the NVRAM entry,
# run C is idempotent, list mode shows the entry, counter-proofs: fresh vars, no loader dir, legacy slug (alt=).
# Env: KEEP=1 keeps the work dir.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
for f in "$OVMF_CODE" "$OVMF_VARS"; do [ -f "$f" ] || { echo "BOOTREG: $f missing"; exit 1; }; done
D=$(mktemp -d /root/abbilder/bootreg.XXXXXX)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"' EXIT
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
SLUG=$MARKE_KURZ
NAME=$MARKE_PRODUKT
OLD=oldslug
MARK_WIN="PROOF-WINDOWS-$$"
MARK_SLUG="PROOF-SLUG-$$"
MARK_OLD="PROOF-OLD-$$"
ESP_OFF=$((2048*512))
REG_RE="bootreg: (registered|already|NOT FOUND|FAILED)"

mkdir -p "$D/efi"
bash tools/bootreg/build.sh "$D/efi" || { echo "BOOTREG: build failed"; exit 1; }
bash tools/bootreg/build.sh "$D/efi" proof win "$MARK_WIN" fail || exit 1
bash tools/bootreg/build.sh "$D/efi" proof slug "$MARK_SLUG" fail || exit 1
bash tools/bootreg/build.sh "$D/efi" proof old "$MARK_OLD" fail || exit 1

blank() { dd if=/dev/null of="$1" bs=1M seek="$2" 2> /dev/null; }

mkdisk() {
    local out=$1; shift
    local esp="$D/esp.$$.img"
    blank "$out" 1024
    sgdisk -o -n 1:2048:+200M -t 1:ef00 -c 1:EFI -n 2:0:+16M -t 2:0c01 -c 2:MSR -n 3:0:+300M -t 3:0700 -c 3:Basic \
        -n 4:0:+100M -t 4:2700 -c 4:Recovery "$out" > /dev/null || return 1
    blank "$esp" 200
    mkfs.fat -F 32 -s 1 "$esp" > /dev/null || return 1
    mmd -i "$esp" ::EFI ::EFI/Microsoft ::EFI/Microsoft/Boot || return 1
    mcopy -i "$esp" "$D/efi/win.efi" ::EFI/Microsoft/Boot/bootmgfw.efi || return 1
    local d proof
    for d in "$@"; do
        proof=slug; [ "$d" = "$OLD" ] && proof=old
        mmd -i "$esp" "::EFI/$d" || return 1
        mcopy -i "$esp" "$D/efi/$proof.efi" "::EFI/$d/BOOTX64.EFI" || return 1
    done
    dd if="$esp" of="$out" bs=512 seek=2048 conv=notrunc 2> /dev/null || return 1
    rm -f "$esp"
}

mkstick() {
    local out=$1
    blank "$out" 16
    mkfs.fat -F 16 "$out" > /dev/null || return 1
    mmd -i "$out" ::EFI ::EFI/BOOT || return 1
    mcopy -i "$out" "$D/efi/bootreg.efi" ::EFI/BOOT/BOOTX64.EFI || return 1
    printf '%b' "$2" > "$D/cfg.tmp"
    mcopy -i "$out" "$D/cfg.tmp" ::EFI/BOOT/bootreg.cfg
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
        grep -aqE "$pat" "$D/$tag.txt" 2>/dev/null && { sleep 4; break; }
        sleep 0.5; n=$((n+1))
    done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return 0
}
fresh_vars() { cp "$OVMF_VARS" "$1"; }
lines() { grep -a "$1" "$D/$2.txt" 2>/dev/null | tr -d '\r' | sed 's/\x1b\[[0-9;=?]*[A-Za-z]//g' | sort -u; }
count() { lines "$1" "$2" | grep -c . ; }
tail_of() { tail -c 250 "$D/$1.txt" | tr '\r\n' '  '; }

CFG="slug=$SLUG\nname=$NAME\n"
mkdisk "$D/disk.img" "$SLUG" || { echo "BOOTREG: disk build failed"; exit 1; }
mkdisk "$D/disk_none.img" || exit 1
mkdisk "$D/disk_old.img" "$OLD" || exit 1
mkdisk "$D/disk_both.img" "$SLUG" "$OLD" || exit 1
mkstick "$D/stick.img" "$CFG" || exit 1
mkstick "$D/stick_list.img" "${CFG}mode=list\n" || exit 1
mkstick "$D/stick_alt.img" "${CFG}alt=$OLD\n" || exit 1
mkstick "$D/stick_crlf.img" "# comment\r\nslug=$SLUG\r\nname=$NAME\r\nfile=BOOTX64.EFI\r\n" || exit 1
SHA_DISK=$(sha256sum < "$D/disk.img")
SHA_WIN=$(mcopy -i "$D/disk.img@@$ESP_OFF" ::EFI/Microsoft/Boot/bootmgfw.efi - | sha256sum)

echo "== A: stick + disk, fresh vars: register"
fresh_vars "$D/v1.fd"
qrun A "$D/v1.fd" "$REG_RE" 120 "$D/disk.img" "$D/stick.img"
LINE=$(lines "bootreg: registered" A | head -1)
echo "$LINE" | grep -aq "bootreg: registered Boot[0-9A-F]\{4\} $NAME -> .*\\\\EFI\\\\$SLUG\\\\BOOTX64.EFI verified" \
    && ok "A: registered + verified line on serial" || bad "A: no registered line: $(tail_of A)"
NUM_A=$(echo "$LINE" | sed -n 's/.*registered \(Boot[0-9A-F]*\) .*/\1/p')
[ "$(count 'bootreg: registered' A)" = 1 ] && ok "A: exactly one entry registered" || bad "A: registered count $(count 'bootreg: registered' A)"

echo "== L1: list mode after A"
qrun L1 "$D/v1.fd" "bootreg: list order" 120 "$D/disk.img" "$D/stick_list.img"
grep -aq "bootreg: list $NUM_A $NAME" "$D/L1.txt" && ok "L1: firmware lists $NUM_A $NAME" || bad "L1: entry $NUM_A not listed"
ORDER1=$(lines "bootreg: list order" L1 | head -1)
echo "$ORDER1" | grep -q "${NUM_A#Boot}" && ok "L1: BootOrder contains ${NUM_A#Boot} after reboot" || bad "L1: BootOrder lacks ${NUM_A#Boot}: $ORDER1"
lines "bootreg: order " A | grep -q "bootreg: order ${NUM_A#Boot} " && ok "A: new entry prepended to BootOrder" || bad "A: order line: $(lines 'bootreg: order ' A)"
[ "$(lines "bootreg: order " A | wc -w)" -ge 5 ] && ok "A: existing BootOrder entries kept" || bad "A: BootOrder entries lost"
ENT1=$(count "bootreg: list Boot" L1)
[ "$(echo "$ORDER1" | wc -w)" -ge 4 ] && ok "L1: foreign entries still in BootOrder" || bad "L1: foreign entries gone: $ORDER1"

echo "== B: disk only, same vars: firmware boots the NVRAM entry"
qrun B "$D/v1.fd" "PROOF: $MARK_SLUG" 120 "$D/disk.img"
grep -aq "PROOF: $MARK_SLUG" "$D/B.txt" && ok "B: loader started from NVRAM entry without stick" || bad "B: marker not reached"
grep -aq "PROOF: $MARK_WIN" "$D/B.txt" && bad "B: windows proof started" || ok "B: windows proof not started"

echo "== C: stick + disk again: idempotent"
qrun C "$D/v1.fd" "$REG_RE" 120 "$D/disk.img" "$D/stick.img"
grep -aq "bootreg: already registered $NUM_A $NAME -> .* verified" "$D/C.txt" && ok "C: already registered $NUM_A" || bad "C: $(tail_of C)"
grep -aq "bootreg: registered " "$D/C.txt" && bad "C: registered again" || ok "C: no second registration"
qrun L2 "$D/v1.fd" "bootreg: list order" 120 "$D/disk.img" "$D/stick_list.img"
[ "$(count 'bootreg: list Boot' L2)" = "$ENT1" ] && ok "L2: Boot#### count unchanged ($ENT1)" || bad "L2: count $(count 'bootreg: list Boot' L2) vs $ENT1"
[ "$(lines "bootreg: list order" L2 | head -1)" = "$ORDER1" ] && ok "L2: BootOrder unchanged" || bad "L2: BootOrder changed"
[ "$(lines "bootreg: list Boot" L2 | grep -c " $NAME")" = 1 ] && ok "L2: exactly one $NAME entry" || bad "L2: $NAME entry count"

echo "== D: cfg with CRLF, comment and file= on fresh vars"
fresh_vars "$D/v4.fd"
qrun D "$D/v4.fd" "$REG_RE" 120 "$D/disk.img" "$D/stick_crlf.img"
grep -aq "bootreg: registered Boot[0-9A-F]\{4\} $NAME -> .* verified" "$D/D.txt" && ok "D: CRLF cfg parsed" || bad "D: $(tail_of D)"

echo "== X1: fresh vars + disk only: nothing registered, loader not reached"
fresh_vars "$D/v2.fd"
qrun X1 "$D/v2.fd" "PROOF: " 40 "$D/disk.img"
grep -aq "PROOF: " "$D/X1.txt" && bad "X1: something booted: $(tail_of X1)" || ok "X1: no loader and no windows proof reached"

echo "== X2: disk without \\EFI\\$SLUG: NOT FOUND, nothing written"
fresh_vars "$D/v3.fd"
qrun X2 "$D/v3.fd" "$REG_RE" 120 "$D/disk_none.img" "$D/stick.img"
grep -aq "bootreg: NOT FOUND: no $SLUG on any disk" "$D/X2.txt" && ok "X2: NOT FOUND line" || bad "X2: $(tail_of X2)"
qrun X2L "$D/v3.fd" "bootreg: list order" 120 "$D/disk_none.img" "$D/stick_list.img"
if grep -aq "bootreg: list order" "$D/X2L.txt"; then
    lines "bootreg: list Boot" X2L | grep -q " $NAME" && bad "X2: entry written" || ok "X2: no $NAME variable written"
else bad "X2: list run did not report"; fi

echo "== E: legacy slug via alt= (only \\EFI\\$OLD on disk)"
fresh_vars "$D/v5.fd"
qrun E "$D/v5.fd" "$REG_RE" 120 "$D/disk_old.img" "$D/stick_alt.img"
grep -aq "bootreg: registered Boot[0-9A-F]\{4\} $NAME -> .*\\\\EFI\\\\$OLD\\\\BOOTX64.EFI verified" "$D/E.txt" && ok "E: registered legacy path" || bad "E: $(tail_of E)"
qrun E2 "$D/v5.fd" "PROOF: $MARK_OLD" 120 "$D/disk_old.img"
grep -aq "PROOF: $MARK_OLD" "$D/E2.txt" && ok "E: disk-only boot runs the legacy loader" || bad "E: legacy marker not reached"
fresh_vars "$D/v6.fd"
qrun E3 "$D/v6.fd" "$REG_RE" 120 "$D/disk_old.img" "$D/stick.img"
grep -aq "bootreg: NOT FOUND" "$D/E3.txt" && ok "E: without alt= the legacy dir is ignored" || bad "E: legacy dir found without alt"

echo "== F: slug and legacy dir both present"
fresh_vars "$D/v7.fd"
qrun F "$D/v7.fd" "$REG_RE" 120 "$D/disk_both.img" "$D/stick_alt.img"
[ "$(count 'bootreg: registered Boot' F)" = 2 ] && ok "F: both candidates registered" || bad "F: registered count $(count 'bootreg: registered Boot' F)"

echo "== G: nothing was written to disks"
[ "$(sha256sum < "$D/disk.img")" = "$SHA_DISK" ] && ok "G: disk image sha256 unchanged after all runs" || bad "G: disk image changed"
[ "$(mcopy -i "$D/disk.img@@$ESP_OFF" ::EFI/Microsoft/Boot/bootmgfw.efi - | sha256sum)" = "$SHA_WIN" ] && ok "G: bootmgfw.efi bytes unchanged" || bad "G: bootmgfw.efi changed"

echo "BOOTREG: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
