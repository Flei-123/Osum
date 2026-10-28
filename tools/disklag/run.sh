#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/disklag/run.sh -- OrientOS on a SLOW rotating disk (AHCI, QEMU throttle).
#
# Symptom (Dell 9020, ST500LM000, installed): `ls /etc` took > 150 s, login
# lost keys, ota/glogin starved. Causes (measured here, see
# reports/20261011-W-DISKLAG.md):
#   1. ahci.write_block flushed the drive cache after EVERY 512-byte block.
#   2. AHCI reads had no read-ahead: one DMA command per 512-byte block.
# The control sample is the kernel word `hddold` (old behaviour); the
# disk is throttled to 100 IOPS (~10 ms per command, like a 5400 rpm disk).
# FLUSH commands are not throttled by QEMU, so they are COUNTED (info
# blockstats), not timed.
#
# usage: bash tools/disklag/run.sh        (run it through /root/jarvis/bin/heavy)
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
IOPS=${IOPS:-100}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

echo "== 1. build: kernel, programs, OFS root (300 files in /etc, journal) =="
bash tools/build-kernel.sh "$TMPD/k.mb" --stufe 0 >"$TMPD/b.txt" 2>&1 \
    && ok "kernel built" || { bad "kernel build"; tail -5 "$TMPD/b.txt"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s
for p in sh ls cat echo; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" && ld -T kernel/user/user.ld \
        --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" \
        || { bad "$p"; exit 1; }
done
mkdir -p "$TMPD/etc"; SPECS=()
for i in $(seq 1 300); do
    head -c 700 /dev/urandom | base64 -w0 > "$TMPD/etc/f$i.conf"
    SPECS+=("/etc/f$i.conf=$TMPD/etc/f$i.conf")
done
python3 tools/osum/mkfs.py build "$TMPD/root.img" 16384 --inodes=1024 --journal /bin/ /etc/ \
    "/bin/sh=$TMPD/sh.elf" "/bin/ls=$TMPD/ls.elf" "/bin/cat=$TMPD/cat.elf" \
    "/bin/echo=$TMPD/echo.elf" "${SPECS[@]}" >"$TMPD/mkfs.txt" 2>&1 \
    && ok "root image built" || { bad "mkfs"; exit 1; }

echo "== 2. both runs at $IOPS IOPS (new / control sample hddold), in parallel =="
python3 tools/disklag/drive.py "$TMPD/k.mb" "$TMPD/root.img" "$IOPS" "$TMPD/new" \
    "osum console=ttyS0" --keys --writes=3 >"$TMPD/new.out" 2>&1 &
P1=$!
python3 tools/disklag/drive.py "$TMPD/k.mb" "$TMPD/root.img" "$IOPS" "$TMPD/old" \
    "osum console=ttyS0 hddold" --keys --writes=3 >"$TMPD/old.out" 2>&1 &
P2=$!
wait $P1 $P2
echo "-- new";  grep '^M' "$TMPD/new.out" | grep -v tail | sed 's/^/     /'
echo "-- hddold (control)"; grep '^M' "$TMPD/old.out" | grep -v tail | sed 's/^/     /'

val() { grep -a "^M $2=" "$TMPD/$1.out" | head -1 | sed 's/^[^=]*=//'; }
part() { echo "$1" | cut -d/ -f"$2"; }   # rd/wr/flush -> field

ER=$(part "$(val new echo_rd_wr_flush)" 1);   OR=$(part "$(val old echo_rd_wr_flush)" 1)
LR=$(part "$(val new ls_etc_rd_wr_flush)" 1); LO=$(part "$(val old ls_etc_rd_wr_flush)" 1)
WF=$(part "$(val new write1_rd_wr_flush)" 3); WFO=$(part "$(val old write1_rd_wr_flush)" 3)
WW=$(part "$(val new write1_rd_wr_flush)" 2)
LT=$(val new ls_etc_s); LTO=$(val old ls_etc_s)

[ "${ER:-999}" -le 40 ]   && ok "new: exec of /bin/echo = $ER disk reads (<= 40)"   || bad "new: echo reads ${ER:-?}"
[ "${LR:-999}" -le 150 ]  && ok "new: ls /etc = $LR disk reads (<= 150)"            || bad "new: ls reads ${LR:-?}"
awk -v t="${LT:-999}" 'BEGIN{exit !(t<=3)}' && ok "new: ls /etc in ${LT} s at $IOPS IOPS (<= 3 s)" || bad "new: ls time ${LT:-?}"
[ "${WF:-999}" -le $(( ${WFO:-0} / 2 )) ] && ok "new: flushes per file create $WF (control $WFO, writes $WW): journal barriers only" || bad "new: flushes $WF vs control $WFO (writes $WW)"
[ "$(val new keys_in_line)" = "15" ] && ok "new: all 15 typed keys arrived during disk load" || bad "new: keys $(val new keys_in_line)/15"
[ "${OR:-0}" -ge 500 ]   && ok "control: exec of echo = $OR disk reads (>= 500)"   || bad "control: echo reads ${OR:-?} (the control sample must show the old path)"
[ "${LO:-0}" -ge 1000 ]  && ok "control: ls /etc = $LO disk reads (>= 1000)"       || bad "control: ls reads ${LO:-?}"
[ "${WFO:-0}" -ge 30 ]   && ok "control: $WFO flushes for one file create (>= 30)" || bad "control: flushes ${WFO:-?}"
awk -v a="${LTO:-0}" -v b="${LT:-1}" 'BEGIN{exit !(a/b>=20)}' && ok "ls /etc: new is >= 20x faster than control (${LTO} s vs ${LT} s)" || bad "ls speed-up < 20x"
echo
echo "DISKLAG: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
