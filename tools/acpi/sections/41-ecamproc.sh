# SPDX-License-Identifier: GPL-2.0-only
PROGS="sh cat"
mkdir -p "$D/bin"
if ! bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/progs.log" 2>&1; then
    echo "  FAIL  proc: user programs did not build"
    echo fail >> "$RESULTS"
    tail -5 "$D/progs.log"
    exit 0
fi
python3 tools/osum/mkfs.py build "$D/proc.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) > "$D/mkfs.log" 2>&1
head -c 8388608 /dev/zero > "$D/pnvme.img"
QARGS_PROC=(-machine q35 -smp 1 -m 512
    -device pcie-root-port,id=rp1,chassis=1 -device pcie-root-port,id=rp2,chassis=2
    -device virtio-net-pci,bus=rp1
    -drive "file=$D/pnvme.img,if=none,id=n0,format=raw" -device nvme,drive=n0,serial=ecam,bus=rp2
    -drive "file=$D/proc.img,format=raw,if=ide,index=0")
proc_capture() {
    ACPI_TIMEOUT=150 qrun "$K" proc "osum vfs usb ecamcaps script=cat /proc/pcie;cat /proc/version;exit" "${QARGS_PROC[@]}"
    tr -d '\000\r' < "$D/proc.txt" > "$D/proc.c"
    sed '/^osum: bin /,$!d; /^osum: kstack/,$d' "$D/proc.c" > "$D/proc.body"
    sed '/^osum: mount=/,$d' "$D/proc.c" | grep -a '^pcie ' | sort -u > "$D/proc.boot"
    [ "$(cat "$D/proc.boot")" = "$(grep -a '^pcie ' "$D/proc.body" | sort -u)" ]
}
for _ in 1 2 3 4 5 6 7 8; do
    proc_capture && break
done
chk "proc: /proc/pcie has the header" 1 "$(grep -ac '^ecam present=1 entries=1' "$D/proc.body")"
chk "proc: /proc/pcie names the allocation" 1 "$(grep -ac '^ecam entry=0 base=0xb0000000 segment=0 bus=0-255' "$D/proc.body")"
chk_ge "proc: boot dump was not empty" 3 "$(wc -l < "$D/proc.boot")"
chk "proc: /proc/pcie function lines == boot dump of the same render" "$(cat "$D/proc.boot")" "$(grep -a '^pcie ' "$D/proc.body" | sort -u)"
chk "proc: root port AER line" 1 "$(grep -ac '^pcie 00:03.0 ext=0001@100v2' "$D/proc.body")"
