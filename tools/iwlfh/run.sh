#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/iwlfh/run.sh -- gate for the kernel glue of the family-8000 firmware loader (HP-9b).
#
#   bash tools/iwlfh/run.sh        (heavy: kernel build + 8 QEMU boots)
#
# MEASURES (QEMU, no Intel WLAN device; kernel word `iwlfhtest` fakes an 8265 identity and runs the REAL
# lib/wlan/iwl_fh8000.fi against a fake CSR window in RAM, kernel/drv/net/iwl_fake.fi):
#   * the candidate file /lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode is read through the VFS
#   * the five summary lines (RC, STAT, LOADSTAT, CHICK, VIOL/LOST/NONZERO/DIGEST) equal the independent Python
#     reference (tools/iwlfh/ref.py -> tools/wlan/fh8000_ref.py): chunk plan, extended range, load status, SRAM bytes
# CONTROL RUNS:
#   * `iwlfhlost`  -- the fake never raises end-of-TFD: loader times out (RC -45), == Python mode 1
#   * `iwlfhbad`   -- the fake expects the bounce window elsewhere: every DMA refused, LOST == all bytes, NONZERO 0
#   * empty section (library guard) -> RC -43 before any SRAM write; edges blob -> extended-range chunks
#   * file missing -> `iwl: fw no file`, no `iwl: fh`; corrupt blob -> negative parse rc, no `iwl: fh`; no word -> nothing
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "IWLFH: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
python3 -I tools/wlan/iwlfw_ref.py gen "$T/blobs" >/dev/null 2>&1
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode

bash tools/sync/build.sh "$T/bin" 0 sh echo > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "IWLFH: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "IWLFH: $pass ok, $fail fail"; exit 1; }
printf 'echo ==START==\necho ==END==\n' > "$T/s.sh"

image() { # name [blob]
    local n=$1 blob=${2:-}
    local extra=()
    [ -n "$blob" ] && extra=("$FWPATH=$blob")
    python3 tools/osum/mkfs.py build "$T/$n.img" 20000 --v3 /bin/ /t/ /etc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" "/t/s.sh=$T/s.sh" "${extra[@]}" > "$T/$n.mkfs" 2>&1 \
        || { tail -3 "$T/$n.mkfs"; return 1; }
}
run() { # name image words
    local n=$1 img=$2 words=$3
    timeout 200 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -drive "file=$T/$img.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
# the five `iwl: fh ...` summary lines of a run, prefix stripped
fhlines() { grep -a '^iwl: fh ' "$1" | sed 's/^iwl: fh //' | grep -aE '^(RC|STAT|LOADSTAT|CHICK|VIOL) '; }
same() { # run-log expected-file description
    fhlines "$1" > "$T/got.txt"
    if cmp -s "$T/got.txt" "$2"; then ok "$3 == Python reference ($(wc -l < "$2") lines)"
    else bad "$3 differs from the reference"; diff "$T/got.txt" "$2" | head -8; fi
}

for c in big edges empty; do image "$c" "$T/blobs/$c.bin" || { bad "image $c"; exit 1; }; done
image none || { bad "image none"; exit 1; }
image badm "$T/blobs/bad_magic.bin" || { bad "image badm (iwlfw_ref gen)"; exit 1; }
SIZE=$(stat -c %s "$T/blobs/big.bin")

echo "-- A: 8265 identity, fake CSR window, image with 6 chunks / 2 extended-range chunks"
run a big iwlfhtest
A="$T/a.klar"
has "$A" "iwl: fw file=$FWPATH size=$SIZE" "file read through the VFS (family 8000 file name), size == $SIZE"
same "$A" "$T/blobs/big.exp" "kernel loader summary"
BIGSHA=$(sha256sum "$T/blobs/big.bin" | cut -d' ' -f1)
has "$A" "iwl: fw sha256=$BIGSHA pin=none" "file digest logged, synthetic blob is NOT a pinned firmware file"
has "$A" 'iwl: fh STAT chunks=6 bytes=151461 ext=2 cpu1=3 cpu2=2' "anchor: 6 chunks, 2 extended-range chunks, paging section not loaded"
has "$A" 'iwl: fh VIOL 0 LOST 0 NONZERO 151461' "anchor: no protocol violation, nothing misdirected, every byte in SRAM"
hasnot "$A" 'iwl: boot' "no boot line without iwlboot"

echo "-- B: extended-range edge sections"
run b edges iwlfhtest
same "$T/b.klar" "$T/blobs/edges.exp" "edge blob"
has "$T/b.klar" 'iwl: fh STAT chunks=5 bytes=22 ext=3' "anchor: extended range 0x40000..0x57FFF inclusive"

echo "-- C: empty section (library guard)"
run c empty iwlfhtest
same "$T/c.klar" "$T/blobs/empty.exp" "empty-section blob"
has "$T/c.klar" 'iwl: fh RC -43 FAILSEC 2' "anchor: refused with the section index, before any SRAM write"

echo "-- D: lost end-of-TFD interrupt (fake never raises it)"
run d big "iwlfhtest iwlfhlost"
same "$T/d.klar" "$T/blobs/lost.exp" "lost-interrupt run"
has "$T/d.klar" 'iwl: fh RC -45 FAILSEC 0' "anchor: loader times out, section reported"

echo "-- E: fake expects the bounce window elsewhere (misdirected DMA must be seen)"
run e big "iwlfhtest iwlfhbad"
E="$T/e.klar"
has "$E" 'iwl: fh RC 0 FAILSEC 0' "loader itself still completes"
has "$E" 'iwl: fh VIOL 0 LOST 151461 NONZERO 0 DIGEST 0x0' "gate sees it: LOST == all bytes, SRAM empty"
grep -a '^iwl: fh VIOL ' "$T/e.klar" | grep -qa 'LOST 0 ' && bad "control not detected" || ok "control run differs from run A"

echo "-- F: file missing"
run f none iwlfhtest
has "$T/f.klar" 'iwl: fw no file' "missing file reported"
hasnot "$T/f.klar" 'iwl: fh' "no loader line without a file"

echo "-- G: corrupt blob"
run g badm iwlfhtest
has "$T/g.klar" 'iwl: fw file=' "corrupt file is still found"
grep -aqE 'iwl: fw rc=-[0-9]+' "$T/g.klar" && ok "parse refuses it (negative rc)" || bad "no negative rc"
hasnot "$T/g.klar" 'iwl: fh' "no loader line for a refused blob"

echo "-- H: no word"
run h big ""
hasnot "$T/h.klar" 'iwl: fh' "nothing happens without the word and without a device"
hasnot "$T/h.klar" 'iwl: fw' "no firmware stage either"

echo "-- I: the REAL Intel iwlwifi-8265-36.ucode (optional: WLAN_8265_FW=<file>; never committed, SHA-256 pinned)"
PIN36=1336afcd028ed094d1fe33893c84c273bb5711be52970040344a75a12f276d56
if [ -n "${WLAN_8265_FW:-}" ] && [ -f "$WLAN_8265_FW" ] && [ "$(sha256sum "$WLAN_8265_FW" | cut -d' ' -f1)" = "$PIN36" ]; then
    mkdir -p "$T/real"
    python3 -I tools/wlan/fh8000_ref.py real "$WLAN_8265_FW" "$T/real" || bad "real reference"
    tail -5 "$T/real/real_128k.exp" > "$T/real/kern.exp"
    image real "$WLAN_8265_FW" || { bad "image real"; echo "IWLFH: $pass ok, $fail fail"; exit 1; }
    run i real iwlfhtest
    has "$T/i.klar" "iwl: fw sha256=$PIN36 pin=8265/36" "kernel hashes the real file and recognises the pin (family 8265, API 36)"
    has "$T/i.klar" 'iwl: fw rc=0 ver=36 lmac=4 umac=4 paging=2' "kernel TLV parser reads the real file: ver 36, 4 + 4 sections, 2 paging sections"
    same "$T/i.klar" "$T/real/kern.exp" "REAL blob through the kernel loader"
    has "$T/i.klar" 'iwl: fh STAT chunks=10 bytes=636520 ext=1 cpu1=4 cpu2=4' "anchor: 10 chunks, 636520 octets, one extended-range chunk"
    echo "-- J: same file with ONE flipped octet inside a data section (pin must not match)"
    python3 -I - "$WLAN_8265_FW" "$T/tamper.bin" <<'PYEOF'
import sys
b = bytearray(open(sys.argv[1], 'rb').read())
b[300000] ^= 1
open(sys.argv[2], 'wb').write(b)
PYEOF
    image tam "$T/tamper.bin" || { bad "image tam"; exit 1; }
    run j tam iwlfhtest
    hasnot "$T/j.klar" "pin=8265/36" "tampered file is not recognised as pinned"
    has "$T/j.klar" 'iwl: fw rc=0 ver=36' "... but still parses (the ROM, not the pin, verifies the Intel signature)"
    grep -a '^iwl: fh VIOL ' "$T/j.klar" > "$T/j.v"; grep -a 'VIOL' "$T/real/kern.exp" | sed 's/^/iwl: fh /' > "$T/i.v"
    cmp -s "$T/j.v" "$T/i.v" && bad "tampered file gives the same SRAM digest" || ok "tampered file gives a different SRAM digest (the gate sees one flipped octet)"
else
    echo "  (no pinned WLAN_8265_FW: real-blob runs skipped)"
fi

echo "IWLFH: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
