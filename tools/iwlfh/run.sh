#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/iwlfh/run.sh -- gate for the kernel glue of the family-8000 firmware loader (HP-9b).
#
#   bash tools/iwlfh/run.sh        (heavy: kernel build + 10 QEMU boots)
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

bash tools/sync/build.sh "$T/bin" 0 sh echo cat > "$T/b.txt" 2>&1 \
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
image two "$T/blobs/two.bin" || { bad "image two"; exit 1; }
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
hasnot "$A" 'iwl: boot rc=' "no boot line without iwlboot"
has "$A" 'iwl: boot2 no init fw rc=-43' "HP-9c.2: image without an INIT section is refused before any phase"
hasnot "$A" 'iwl: boot2 rt' "HP-9c.2: no RT phase when INIT is missing"

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

echo "-- I2: HP-9c.2 two-phase boot INIT -> ALIVE -> stop -> RT -> ALIVE against the fake (image with INIT 3000 octets + RT 151461)"
run i2 two iwlfhtest
I2="$T/i2.klar"
has "$I2" 'iwl: boot2 init load rc=0 bytes=3000' "INIT image loaded first (3000 octets)"
has "$I2" 'iwl: boot2 init alive rc=0' "ALIVE after the INIT image"
has "$I2" 'iwl: boot2 init stop rc=0' "device stopped between the images"
has "$I2" 'iwl: boot2 rt load rc=0 bytes=151461' "RT image loaded after the stop (151461 octets)"
has "$I2" 'iwl: boot2 rt alive rc=0' "ALIVE after the RT image"
grep -aE 'iwl: boot2 SUMMARY phase 2 init 3000 rt 151461 viol 0 stops [1-9]' "$I2" >/dev/null && ok "model: 2 ALIVEs, bytes per phase exact, no violation, stop seen" || { bad "model summary"; grep -a 'boot2 SUMMARY' "$I2"; }
echo "-- K: command queue 0 + RX ring (fake firmware answers through the RX ring)"
[ "$(grep -ac 'iwl: cq init rc=0' "$I2")" = 2 ] && ok "RX ring + command ring programmed before both images" || bad "cq init lines"
grep -aqE 'iwl: cq alive scd=0x0*800000 rc=0' "$I2" && ok "ALIVE notification read from the RX ring, scd_base_ptr 0x800000 at packet offset 44" || bad "cq alive"
has "$I2" 'iwl: cq sched rc=0' "scheduler + queue 0 enabled from the ALIVE scd base"
has "$I2" 'iwl: cq binding rc=0 v=' "BINDING_CONTEXT sent, response status 0 read back"
has "$I2" 'iwl: cq phycfg rc=0 v=' "PHY_CONFIG sent, response status 0"
has "$I2" 'iwl: cq scan rc=0 v=1372' "SCAN_REQ_UMAC (1372 octets, two TBs) accepted by the fake"
has "$I2" 'iwl: cq scan-complete rc=20 v=1' "SCAN_COMPLETE_UMAC notification (status 1) via the RX ring"
has "$I2" 'iwl: cq scan-uid rc=20 v=4660' "scan uid in the notification == uid of the request (0x1234)"
has "$I2" 'iwl: cq stress rc=300 v=300' "300 commands: TFD ring wraps, RX ring wraps and is restocked"
has "$I2" 'iwl: cq ctl-big rc=-71' "control: command larger than the slot refused (-71)"
has "$I2" 'iwl: cq ctl-fakenorx rc=-70' "control: firmware never answers -> bounded timeout (-70)"
has "$I2" 'iwl: cq ctl-norx rc=-72' "control: RX ring not programmed -> -72"
has "$I2" 'iwl: cq ctl-notx rc=-73' "control: scheduler/queue not enabled -> -73"
has "$I2" 'iwl: cq SUMMARY cmds=318 pkts=325 drops=1 viol=0 last=152' "model: 318 commands (14 boot + 304 selftest), 325 RX packets, 1 intended drop, no protocol violation"
echo "-- I3: lost end-of-TFD interrupt in the INIT phase: bounded failure, RT never loaded"
run i3 two "iwlfhtest iwlfhlost"
I3="$T/i3.klar"
has "$I3" 'iwl: boot2 init load rc=-45' "INIT load times out (RC -45)"
hasnot "$I3" 'iwl: cq SUMMARY' "no command-queue self test after a failed INIT"
hasnot "$I3" 'iwl: boot2 rt' "no RT phase after a failed INIT"
echo "-- I4: misdirected DMA must be seen in both phases"
run i4 two "iwlfhtest iwlfhbad"
grep -aE 'iwl: boot2 SUMMARY phase [0-9] init 0 rt 0 ' "$T/i4.klar" >/dev/null && ok "bad window: nothing lands in either phase (init 0, rt 0)" || { bad "bad-window summary"; grep -a 'boot2' "$T/i4.klar" | head -5; }

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
    has "$T/i.klar" 'iwl: boot2 init alive rc=0' "HP-9c.2 REAL blob: INIT image loads and ALIVE comes (fake)"
    has "$T/i.klar" 'iwl: boot2 rt alive rc=0' "HP-9c.2 REAL blob: RT image after the stop, ALIVE (fake)"
    grep -aE 'iwl: boot2 SUMMARY phase 2 init [1-9][0-9]* rt 636520 viol 0 stops [1-9]' "$T/i.klar" >/dev/null && ok "HP-9c.2 REAL blob: RT = 636520 octets, no violation" || { bad "real boot2 summary"; grep -a 'boot2' "$T/i.klar" | head -6; }
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

printf 'echo ==START==\ncat /proc/wlan\necho ==END==\n' > "$T/s2.sh"
echo "-- L: INIT stage over the command queue (NVM, PHY_CFG, calibration, INIT_COMPLETE), RT replay, /proc/wlan"
python3 tools/osum/mkfs.py build "$T/twoc.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
    /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" "/t/s.sh=$T/s2.sh" "$FWPATH=$T/blobs/two.bin" > "$T/twoc.mkfs" 2>&1 || bad "image twoc"
runc() {
    cp "$T/${RUNC_BASE:-twoc}.img" "$T/$1.img"
    local n=$1 words=$2
    timeout 200 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
runc l1 iwlfhtest
L1="$T/l1.klar"
has "$L1" 'iwl: boot2 init nvm rc=0' "INIT stage over the command queue succeeds"
has "$L1" 'iwl: boot2 FAKEFW nvm=6 phydb=4 initc=1' "fake saw 6 NVM_ACCESS reads, 4 PHY_DB replays, 1 INIT_COMPLETE"
has "$L1" 'phase=ready' "/proc/wlan: phase=ready after RT"
has "$L1" 'err_text=ok' "/proc/wlan: err_text=ok"
has "$L1" 'nvm=ok bytes=200 secs=3' "/proc/wlan: NVM read (3 sections incl. MAC override, 200 octets)"
has "$L1" 'calib=4 bytes=24 replayed=4' "/proc/wlan: 4 calibration results collected and replayed"
has "$L1" 'last_cmd=0x6a last_notif=0x04' "/proc/wlan: last command PHY_CFG, last notification INIT_COMPLETE"
has "$L1" 'alive=yes init_alive=yes rt_alive=yes' "/proc/wlan: both ALIVEs seen"
runc l2 "iwlfhtest iwlfhnonvm"
L2="$T/l2.klar"
has "$L2" 'iwl: boot2 init nvm rc=-61' "control nonvm: NVM_ACCESS never answered -> bounded failure (-61)"
has "$L2" 'phase=failed' "control nonvm: /proc/wlan phase=failed"
has "$L2" 'failed_at=nvm' "control nonvm: failed_at=nvm"
hasnot "$L2" 'iwl: boot2 rt load' "control nonvm: RT image never loaded"
has "$L2" '==END==' "control nonvm: the rest of the system keeps running"
runc l3 "iwlfhtest iwlfhnoinitc"
L3="$T/l3.klar"
has "$L3" 'iwl: boot2 init nvm rc=-62' "control noinitc: INIT_COMPLETE never comes -> bounded timeout (-62)"
has "$L3" 'failed_at=init_complete' "control noinitc: failed_at=init_complete"
hasnot "$L3" 'iwl: boot2 rt load' "control noinitc: RT image never loaded"
runc l4 "iwlfhtest iwlfhbadnvm"
L4="$T/l4.klar"
has "$L4" 'iwl: boot2 init nvm rc=-63' "control badnvm: invalid HW section refused (-63)"
has "$L4" 'err=-63' "control badnvm: /proc/wlan err=-63"
runc l5 "iwlfhtest iwlfhnoalive"
L5="$T/l5.klar"
has "$L5" 'phase=failed' "control noalive: ALIVE packet missing -> phase=failed"
has "$L5" 'err=-70' "control noalive: bounded timeout (-70)"
hasnot "$L5" 'iwl: boot2 init nvm' "control noalive: no NVM exchange without a command queue"
has "$L5" '==END==' "control noalive: the rest of the system keeps running"
runc l6 "iwlfhtest iwlfhslow"
L6="$T/l6.klar"
has "$L6" 'iwl: boot2 init alive rc=0' "slow ALIVE (60000 reads): the clock-bounded wait still sees it"
has "$L6" 'iwl: boot2 rt alive rc=0' "slow ALIVE: runtime image reaches ALIVE too"
has "$L6" 'phase=ready' "slow ALIVE: /proc/wlan phase=ready"
hasnot "$L6" 'fail_alive=' "slow ALIVE: no failure line"
runc l7 "iwlfhtest iwlfhslow iwloldalive iwlnotrace"
L7="$T/l7.klar"
has "$L7" 'iwl: boot2 init alive rc=-30' "counter-proof iwloldalive: the old 25000-read wait times out on the slow ALIVE (-30)"
has "$L7" 'phase=failed' "counter-proof iwloldalive: phase=failed"
has "$L7" 'err_text=ALIVE timeout' "counter-proof iwloldalive: err_text=ALIVE timeout"
has "$L7" 'fail_alive=int=' "counter-proof iwloldalive: fail_alive line (CSR_INT, FH_INT, GP1/GP2, CPU status) is in /proc/wlan"
has "$L7" 'fail_pm=rev=' "counter-proof iwloldalive: PCI diagnostics line (revision, subsystem, PM state, link control of card and root port, warm CSR state) is in /proc/wlan"
has "$L7" 'fail_alive2=load=' "counter-proof iwloldalive: second diagnostics line (load status, CPU header words, secure-boot config) is in /proc/wlan"
has "$L7" ' img=init sc1=' "counter-proof iwloldalive: the failing image (init) and the sections loaded per CPU are reported"
hasnot "$L7" ' sc1=0 sc2=0' "counter-proof iwloldalive: both CPUs got sections before the wait"
has "$L7" 'fail_regs=hwif=' "counter-proof iwloldalive: first failure snapshot kept (not overwritten after int_disable)"
has "$L7" '==END==' "counter-proof iwloldalive: the rest of the system keeps running"

runc l8 "iwlfhtest iwlfhrxonly"
L8="$T/l8.klar"
has "$L8" 'iwl: boot2 init alive rc=0' "rx-only ALIVE (no CSR_INT bit 0): accepted via the RX ring"
has "$L8" 'iwl: boot2 rt alive rc=0' "rx-only ALIVE: runtime image reaches ALIVE too"
has "$L8" 'phase=ready' "rx-only ALIVE: /proc/wlan phase=ready"
hasnot "$L8" 'fail_alive=' "rx-only ALIVE: no failure line"
runc l9 "iwlfhtest iwlfhrxonly iwloldalive iwlnotrace iwlnoraw"
L9="$T/l9.klar"
has "$L9" 'iwl: boot2 init alive rc=-30' "counter-proof iwloldalive: bit-0-only wait never sees the rx-only ALIVE (-30)"
has "$L9" 'phase=failed' "counter-proof iwloldalive rxonly: phase=failed"
has "$L9" '==END==' "counter-proof iwloldalive rxonly: the rest of the system keeps running"

echo "-- M: secure-boot trace (W-WLAN27): per-section samples, failure series, experiments"
runc m1 "iwlfhtest iwlfhdead"
M1="$T/m1.klar"
has "$M1" 'fail_trace=c1s0 t=' "trace: sample after the first CPU1 section"
has "$M1" 'fail_trace=c1end t=' "trace: sample after CPU1 is complete"
has "$M1" 'fail_trace=c2end t=' "trace: sample after CPU2 is complete"
has "$M1" ' cpu1=00000003 cpu2=000029' "trace: SB_CPU1/SB_CPU2 values read through PRPH"
has "$M1" 'fail_series=7 t=' "series: 8 samples after the timeout"
has "$M1" 'fail_exp=status ' "experiment: LOAD_STATUS written again"
has "$M1" 'fail_exp=release ' "experiment: RELEASE_CPU_RESET written again"
has "$M1" 'fail_exp=wait ' "experiment: long wait"
has "$M1" 'fail_exp=initdelay ' "experiment: reload with delay after INIT_DONE"
has "$M1" 'fail_exp=pci41 ' "experiment: reload with PCI 0x41 = 0"
has "$M1" 'fail_exp=pause ' "experiment: reload with a pause between CPU1 and CPU2"
has "$M1" 'phase=failed' "no ALIVE anywhere: phase=failed"
has "$M1" '==END==' "the rest of the system keeps running"
runc m2 "iwlfhtest iwlfhdead iwlnotrace"
M2="$T/m2.klar"
has "$M2" 'phase=failed' "counter-proof iwlnotrace: still failed"
hasnot "$M2" 'fail_trace=' "counter-proof iwlnotrace: no trace lines"
hasnot "$M2" 'fail_exp=' "counter-proof iwlnotrace: no experiments"
if [ -n "${WLAN_8265_FW:-}" ] && [ -f "$T/real/kern.exp" ]; then
    python3 tools/osum/mkfs.py build "$T/realc.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" "/t/s.sh=$T/s2.sh" "$FWPATH=$WLAN_8265_FW" > "$T/realc.mkfs" 2>&1 || bad "image realc"
    RUNC_BASE=realc runc m4 "iwlfhtest iwlfhdead"
    M4="$T/m4.klar"
    has "$M4" 'fail_trace=c2end t=' "REAL blob failure: trace reaches the end of CPU2"
    has "$M4" 'fail_series=7 t=' "REAL blob failure: series complete in /proc/wlan"
    has "$M4" 'fail_exp=pause ' "REAL blob failure: last experiment line not cut off"
    has "$M4" 'fail_rxs=' "REAL blob failure: RX scan line in /proc/wlan"
    has "$M4" 'fail_rx=stts=' "REAL blob failure: RX scan register line in /proc/wlan"
    has "$M4" 'fail_alive2=load=' "REAL blob failure: second diagnostics line in /proc/wlan"
    has "$M4" 'fail_pm=rev=' "REAL blob failure: PCI diagnostics line in /proc/wlan"
    has "$M4" 'err_text=' "REAL blob failure: generic tail of /proc/wlan not cut off"
    has "$M4" 'fail_exp2=apm ' "REAL blob failure: exp2 table complete in /proc/wlan"
    has "$M4" '==END==' "REAL blob failure: system keeps running"
fi
runc m3 "iwlfhtest iwlfhdead iwlfhwake"
M3="$T/m3.klar"
has "$M3" 'iwl: boot2 exp alive' "an experiment (second RELEASE_CPU_RESET) brings ALIVE: boot continues"
echo "-- N: RX scan after an ALIVE timeout (W-WLAN29)"
has "$M1" 'fail_rxs=rx-empty' "dead ROM: RX scan reports an empty ring"
has "$M1" 'fail_rx=stts=000 rxr=00 rbnz=0 alv=0 first=ffff' "dead ROM: no RX buffer holds data (rbnz=0)"
has "$M1" 'fail_rxr= b0=' "dead ROM: FH/CSR register line present"
runc n1 "iwlfhtest iwlfhrxsilent"
N1="$T/n1.klar"
has "$N1" 'iwl: boot2 init alive rc=-30' "silent RX: the interrupt-based wait times out"
has "$N1" 'iwl: boot2 rx-raw alive' "silent RX: ALIVE found by scanning the RX buffers"
has "$N1" 'iwl: boot2 rt alive rc=0' "silent RX: runtime image reaches ALIVE through the raw ring"
has "$N1" 'phase=ready' "silent RX: /proc/wlan phase=ready after the recovery"
hasnot "$N1" 'fail_rx=' "silent RX: no failure scan line after the recovery"
runc n2 "iwlfhtest iwlfhrxsilent iwlnoraw iwlnotrace"
N2="$T/n2.klar"
has "$N2" 'fail_rxs=alive-in-rx-silent' "counter-proof iwlnoraw: the scan names the state alive-in-rx-silent"
has "$N2" 'phase=failed' "counter-proof iwlnoraw: without the recovery the boot fails"
hasnot "$N2" 'iwl: boot2 rx-raw alive' "counter-proof iwlnoraw: no recovery line"
echo "-- O: RX experiment table after the series (W-WLAN30)"
has "$M1" 'fail_exp2=base i=' "exp2: baseline row measured before any experiment"
has "$M1" 'fail_exp2=mask i=' "exp2: INT_MASK=FFFFFFFF row"
has "$M1" 'fail_exp2=coal i=' "exp2: INT_COALESCING row"
has "$M1" 'fail_exp2=dram i=' "exp2: DRAM_INT_TBL row"
has "$M1" 'fail_exp2=wptr i=' "exp2: RX write pointer row"
has "$M1" 'fail_exp2=nic i=' "exp2: nic_init again row"
has "$M1" 'fail_exp2=apm i=' "exp2: apm_init again row (last row not cut off)"
hasnot "$M1" 'fail_exp2=intx' "exp2: no INTx rows without a PCI device (fake bed)"
has "$M1" ' c1=00000003 c2=000029' "exp2: cpu1/cpu2 read per row"
has "$M1" 'iwl: boot2 rxexp rows=7 alive=0' "exp2: 7 rows, no ALIVE"
runc o1 "iwlfhtest iwlfhdead iwlfhexpwake"
O1="$T/o1.klar"
has "$O1" 'iwl: boot2 rxexp rows=4 alive=1' "exp2: ALIVE after the dram row stops the table (no wptr/nic/apm)"
has "$O1" 'iwl: boot2 exp alive' "exp2: boot continues after the experiment ALIVE"
hasnot "$O1" 'fail_exp2=wptr' "exp2: no row after the one that brought ALIVE in the first phase"
runc o2 "iwlfhtest iwlfhdead iwlfhexpwake iwlnorxexp"
O2="$T/o2.klar"
has "$O2" 'phase=failed' "counter-proof iwlnorxexp: without the table the boot fails"
hasnot "$O2" 'fail_exp2=' "counter-proof iwlnorxexp: no exp2 lines"
hasnot "$O2" 'iwl: boot2 rxexp' "counter-proof iwlnorxexp: no rxexp summary"
hasnot "$L1" 'fail_trace=' "normal boot: no trace lines"
hasnot "$L6" 'fail_trace=' "slow ALIVE: no trace lines"
hasnot "$L1" 'fail_exp2=' "normal boot: no exp2 lines"
hasnot "$L1" 'iwl: boot2 rxexp' "normal boot: no experiments run"

echo "IWLFH: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
