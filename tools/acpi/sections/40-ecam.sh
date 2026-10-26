# SPDX-License-Identifier: GPL-2.0-only
AER_ID=0001
AER_OFFSET=100
AER_VERSION=2
ROOT_PORT_BDF=00:03.0
REAL_MCFG=tools/acpi/real/surface-laptop-4/MCFG
[ -f "$REAL_MCFG" ] || REAL_MCFG=/tmp/acpi-work/surf/MCFG01.dat

clean() {
    tr -d '\000\r' < "$D/$1.txt" > "$D/$1.c"
}

mon_text() {
    (printf '%s\n' "$2"; sleep "${3:-3}") | timeout 15 socat - "unix-connect:$D/$1.mon" 2> /dev/null | tr -d '\r'
}

devs_kernel() {
    grep -a '^ecamcmp: dev=' "$D/$1.c" | sed 's/^ecamcmp: dev=//; s/ same=.*//' | sort
}

devs_listed() {
    grep -aE '^pci: [0-9a-f]{2}:[0-9a-f]{2}\.[0-7] ' "$D/$1.c" | awk '{print $2}' | sort
}

pci_lines() {
    grep -a '^pci: ' "$D/$1.c"
}

pcie_lines() {
    grep -a '^pcie ' "$D/$1.c" | sort -u
}

QARGS=(-machine q35
    -device pcie-root-port,id=rp1,chassis=1 -device pcie-root-port,id=rp2,chassis=2
    -device virtio-net-pci,bus=rp1
    -drive "file=$D/nvme.img,if=none,id=n0,format=raw" -device nvme,drive=n0,serial=ecam,bus=rp2)
head -c 8388608 /dev/zero > "$D/nvme.img"

qstart "$K" q35 "osum ecamcmp ecamcaps ecamhold noring3 nofs" "${QARGS[@]}"
for _ in $(seq 1 600); do
    [ "$(grep -ac 'ecamcmp: windows used=' "$D/q35.txt" 2> /dev/null)" -ge 2 ] 2> /dev/null && break
    sleep 0.2
done
sleep 1
clean q35
mon_text q35 'info mtree -f' 4 > "$D/q35.mtree"
python3 -I tools/acpi/ecamref.py "$D/q35.mon" 0xb0000000 > "$D/q35.ref" 2> "$D/q35.referr"
qfinish q35

mm=$(grep -aE 'pcie-mmcfg-mmio' "$D/q35.mtree" | head -1)
want_base=$(echo "$mm" | sed -E 's/^ *0*([0-9a-f]+)-.*/0x\1/')
want_end=$(echo "$mm" | sed -E 's/^ *[0-9a-f]+-0*([0-9a-f]+) .*/\1/')
want_buses=$(( ((0x$want_end - ${want_base}) >> 20) + 1 ))
got=$(line q35 '^ecam entry=0 ')
chk "q35: ecam reported present" 1 "$(val "$(line q35 '^ecam present=')" present)"
chk "q35: one allocation entry" 1 "$(val "$(line q35 '^ecam present=')" entries)"
chk "q35: base equals QEMU mmcfg region" "$want_base" "$(val "$got" base)"
chk "q35: segment 0" 0 "$(val "$got" segment)"
chk "q35: bus range equals QEMU region size" "0-$((want_buses - 1))" "$(val "$got" bus)"
chk "q35: monitor reference has devices" 1 "$([ "$(grep -c '^dev=' "$D/q35.ref")" -ge 8 ] && echo 1 || echo 0)"
chk "q35: devices behind root ports found by the reference" 2 "$(grep -cE '^dev=0[12]:' "$D/q35.ref")"
chk "q35: ecam read of 256 bytes equals port read, every device" 0 "$(grep -ac 'ecamcmp: dev=.* same=0' "$D/q35.c")"
cmp_line=$(line q35 '^ecamcmp: devices=')
chk "q35: compared == equal" "$(val "$cmp_line" devices)" "$(val "$cmp_line" equal)"
chk "q35: compared set == listed set" "$(devs_listed q35)" "$(devs_kernel q35)"
chk "q35: compared set == monitor reference set" "$(grep '^dev=' "$D/q35.ref" | sed 's/^dev=//' | sort)" "$(devs_kernel q35)"
chk "q35: extended capabilities == independent walk of the raw bytes" "$(grep '^pcie ' "$D/q35.ref" | sort -u)" "$(pcie_lines q35)"
chk "q35: root port has AER at 0x100" 1 "$(pcie_lines q35 | grep -c "^pcie $ROOT_PORT_BDF ext=${AER_ID}@${AER_OFFSET}v${AER_VERSION}")"
chk "q35: capabilities seen on more than one function" 1 "$([ "$(pcie_lines q35 | wc -l)" -ge 2 ] && echo 1 || echo 0)"
chk "q35: window hop keeps the data" 1 "$(val "$(line q35 '^ecamcmp: hop')" ok)"
chk_ge "q35: window was retargeted" 2 "$(val "$(line q35 '^ecamcmp: hop')" retargets)"
chk "q35: config write through ecam seen by port read, restored" 1 "$(val "$(line q35 '^ecamcmp: write')" ok)"
win_before=$(val "$(line q35 '^apic: id=')" window)
win_used=$(grep -a '^ecamcmp: windows used=' "$D/q35.c" | sed 's/.*used=//')
chk "q35: ecam takes exactly one shared window" "$((win_before + 1))" "$(echo "$win_used" | head -1)"
chk "q35: caps scan takes no further window" "$(echo "$win_used" | head -1)" "$(echo "$win_used" | tail -1)"

qstart "$K" noe "osum noecam ecamcmp ecamcaps ecamhold noring3 nofs" "${QARGS[@]}"
for _ in $(seq 1 300); do
    grep -aq '^pci: devices=' "$D/noe.txt" 2> /dev/null && grep -aq '^ecam present=0' "$D/noe.txt" 2> /dev/null && break
    sleep 0.2
done
sleep 1
clean noe
qfinish noe
chk "noecam: reported off" 1 "$(has noe '^ecam present=0 disabled=noecam')"
chk "noecam: no extended capability lines" 0 "$(grep -ac '^pcie ' "$D/noe.c")"
chk "noecam: no ecam comparison lines" 0 "$(grep -ac '^ecamcmp' "$D/noe.c")"
chk "noecam: port path lists the same devices, byte for byte" "$(pci_lines q35)" "$(pci_lines noe)"

qrun "$K" pc "osum ecamcmp ecamcaps noring3 nofs" -machine pc
clean pc
chk "pc (no MCFG): kernel finished" 21 "$(cat "$D/pc.rc")"
chk "pc (no MCFG): ecam absent" 0 "$(val "$(line pc '^ecam present=')" present)"
chk "pc (no MCFG): no entries" 0 "$(val "$(line pc '^ecam present=')" entries)"
chk "pc (no MCFG): no extended capability lines" 0 "$(grep -ac '^pcie ' "$D/pc.c")"
chk "pc (no MCFG): no comparison lines" 0 "$(grep -ac '^ecamcmp' "$D/pc.c")"
chk_ge "pc (no MCFG): devices still listed" 4 "$(grep -aoE '^pci: devices=[0-9]+' "$D/pc.c" | sed 's/.*=//')"

if [ -n "${KB:-}" ]; then
    qstart "$KB" base "osum noring3 nofs" "${QARGS[@]}"
    for _ in $(seq 1 300); do
        grep -aq '^pci: devices=' "$D/base.txt" 2> /dev/null && break
        sleep 0.2
    done
    sleep 1
    clean base
    qfinish base
    chk "q35: device list identical to the image without ecam (BARs sized through ports)" "$(pci_lines base)" "$(pci_lines q35)"
    qrun "$KB" pcbase "osum noring3 nofs" -machine pc
    clean pcbase
    chk "pc: device list identical to the image without ecam" "$(pci_lines pcbase)" "$(pci_lines pc)"
fi

python3 -I tools/acpi/mcfgsynth.py "$D/synth"
python3 -I tools/acpi/retag.py "$REAL_MCFG" "$D/synth/real-surface" XMCF
for tbl in real-surface synth-multi synth-invalid synth-empty synth-partial; do
    qrun "$K" "self-$tbl" "osum ecamself noring3 nofs" -machine q35 -acpitable "sig=XMCF,file=$D/synth/$tbl"
    clean "self-$tbl"
    chk "ecamself $tbl: kernel finished" 21 "$(cat "$D/self-$tbl.rc")"
    chk "ecamself $tbl: parser == independent parser" "$(python3 -I tools/acpi/mcfgref.py "$D/synth/$tbl" XMCF)" "$(grep -a '^ecamself: ' "$D/self-$tbl.c")"
done
chk "ecamself real table: one entry" 1 "$(grep -ac '^ecamself: entry=' "$D/self-real-surface.c")"
chk "ecamself real table: base 0xe0000000" 1 "$(grep -ac '^ecamself: entry=0 base=0xe0000000 segment=0 bus=0-255 usable=1' "$D/self-real-surface.c")"
chk "ecamself synthetic: invalid entries rejected" 4 "$(grep -ac 'usable=0' "$D/self-synth-invalid.c")"
chk "ecamself synthetic: second segment parsed" 1 "$(grep -ac 'entry=2 base=0x8000000000 segment=1' "$D/self-synth-multi.c")"
chk "q35 with extra table: real allocation still the one in use" "$want_base" "$(val "$(line self-synth-multi '^ecam entry=0 ')" base)"

if asl_build tools/acpi/asl/ecam-aml.asl "$D/ecamaml"; then
    qrun "$K" aml "osum ecamaml noring3 nofs" "${QARGS[@]}" -acpitable "file=$D/ecamaml.aml"
    clean aml
    aml_line=$(line aml '^ecamaml: aml=')
    want_hdr=$(grep -a "^hdr $ROOT_PORT_BDF " "$D/q35.ref" | awk '{print $3}')
    chk "aml: PCI_Config region at 0x100 read through ecam == independent monitor read" "$want_hdr" "$(val "$aml_line" aml)"
    chk "aml: interpreter result == direct ecam read" "$(val "$aml_line" direct)" "$(val "$aml_line" aml)"
    qrun "$K" amlno "osum ecamaml noring3 nofs" "${QARGS[@]}"
    clean amlno
    chk "aml: counter-proof without the table there is no method" 1 "$(has amlno '^ecamaml: no method')"
    qrun "$K" amloff "osum ecamaml noecam noring3 nofs" "${QARGS[@]}" -acpitable "file=$D/ecamaml.aml"
    clean amloff
    chk "aml: counter-proof with noecam the region reads all ones" "0xffffffff" "$(val "$(line amloff '^ecamaml: aml=')" aml)"
else
    echo "  FAIL  aml: iasl could not build tools/acpi/asl/ecam-aml.asl"
    echo fail >> "$RESULTS"
fi
