#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/time/boot.sh -- r544: THE CLOCK RIGHT AFTER THE BOOT, BEFORE ANY SNTP.
#
#   bash tools/time/boot.sh
#
# The real Dell (Vienna, summer time) showed `sntp: ... offset=-7199s` on
# its first sync: the clock had been 2 h wrong since the boot. This test
# boots the install image with a chosen hardware clock (QEMU -rtc base=..,
# fixed, so the value the guest finds is exact) and asks the kernel what it
# made of it -- BEFORE the network clock may touch it: `date` is the first
# thing the script does, then `sntp -n` only measures the offset to a fake
# server that says the TRUE time (2026-10-11 09:00:00 UTC = 11:00 CEST).
#
# Cases (all with the stick's boot words `tz=60 tzrule=eu`):
#   A  RTC holds LOCAL time 11:00  (the Windows habit, our default)
#   B  RTC holds UTC 09:00 + `rtcutc`
#   C  RTC holds UTC 09:00, no `rtcutc` (a board whose firmware / Linux
#      keeps the chip on UTC, and nobody told the kernel)
#   D  C near the changeover: RTC UTC 2026-10-25 00:30 (still summer time)
#   E  RTC holds local 11:00 but the boot line has NO zone (tz= missing):
#      the zone only arrives later, from /etc/time.conf via `sntp boot`
#      (SETTZ) -- the kernel converts the hardware clock then, once
# The expected local time after the boot is 11:00 in A, B, C, E and
# 02:30 on 25.10. in D; the offset to the true time is then ~0 s.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh
OUT=${OUT:-$(mktemp -d /tmp/time-boot.XXXXXX)}
trap '[ -n "${NTPPID:-}" ] && kill "$NTPPID" 2>/dev/null; [ "${KEEP:-0}" = 1 ] || rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
. "$ROOT/tools/lib/sperre.sh" && osum_sperre "$OUT"
export OUT
PORT=${TIME_PORT:-$(( 13000 + ($$ % 900) ))}
export OSUM_CPU=${OSUM_CPU:-Haswell}
NETBASIS="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
SERVER="10.0.2.2:$PORT"
MODE=${1:-check}   # check = pass/fail, measure = only print numbers

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "TIME-BOOT: skipped, $t missing"; exit 0; }
done

bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 || { echo "build failed"; tail -20 "$OUT/build.log"; exit 1; }
head -c $((64 * 1024 * 1024)) /dev/zero > "$OUT/ziel0.img"

ntp() { # TRUE-UTC-TIME
    [ -n "${NTPPID:-}" ] && { kill "$NTPPID" 2>/dev/null; wait "$NTPPID" 2>/dev/null; }
    : > "$OUT/ntp.log"
    python3 tools/time/fakentp.py --port "$PORT" --log "$OUT/ntp.log" --time "$1" "$1" \
        > "$OUT/ntp.out" 2>&1 &
    NTPPID=$!
    local i
    for i in $(seq 1 30); do
        grep -qa "^START" "$OUT/ntp.log" 2>/dev/null && return 0
        sleep 0.2
    done
}

# run NAME RTC-BASE BOOT-WORDS [TRUE-UTC] -> sets $LOCAL (first `date`) and $OFF (sntp offset)
run() {
    ntp "${4:-$2Z}"
    cp -f "$OUT/ziel0.img" "$OUT/ziel.img"
    OSUM_RTC="base=$2,clock=vm" OTA_NETZ="$NETBASIS $3" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" iso "${SCRIPT:-date;sntp -n $SERVER;date;exit}" 240 > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
    LOCAL=$(grep -a '^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] ' "$OUT/$1.txt" | ${WHICH:-head -1})
    OFF=$(grep -a -o 'offset=-\?[0-9]*s' "$OUT/$1.txt" | head -1 | sed 's/offset=//; s/s$//')
    printf '  [%s] first date: "%s"  offset to true time: %ss\n' "$1" "${LOCAL:-?}" "${OFF:-?}"
}

# check NAME RTC-BASE WORDS EXPECTED-PREFIX
check() {
    run "$1" "$2" "$3" "${5:-}"
    if [ "$MODE" = measure ]; then return; fi
    case "$LOCAL" in
        "$4"*) ok "$1: the clock right after the boot says $4.." ;;
        *) bad "$1: after the boot '$LOCAL', expected '$4..'" ;;
    esac
    case "${OFF:-x}" in
        x) bad "$1: no offset line" ;;
        *) local a=${OFF#-}
           if [ "$a" -le 300 ]; then ok "$1: offset to the true time is ${OFF}s (boot time only)"
           else bad "$1: offset to the true time is ${OFF}s (> 300)"; fi ;;
    esac
}

want() { case " ${CASES:-A B C D E F G H I J K L M} " in *" $1 "*) return 0 ;; esac; return 1; }

# the convention (tools/time docs, ECHTHARDWARE-1): without `rtcutc` the
# hardware clock holds LOCAL time, as Windows keeps it. A and E-G are the
# normal boards; B is the Linux habit with the word; C documents what a
# UTC chip without the word gives (the mirror image of the old bug).
if want A; then echo "== A  RTC local 11:00 (summer), zone on the boot line =="
check A  2026-10-11T11:00:00 "tz=60 tzrule=eu"        "2026-10-11 11:0" 2026-10-11T09:00:00Z; fi
if want B; then echo "== B  RTC UTC 09:00 + rtcutc =="
check B  2026-10-11T09:00:00 "tz=60 tzrule=eu rtcutc" "2026-10-11 11:0"; fi
if want C; then echo "== C  RTC UTC 09:00 WITHOUT rtcutc: read as local, shows 09:00 (the convention) =="
check C  2026-10-11T09:00:00 "tz=60 tzrule=eu"        "2026-10-11 09:0" 2026-10-11T07:00:00Z; fi
if want D; then echo "== D  RTC UTC 00:30 on 25.10. + rtcutc (summer time still on) =="
check D  2026-10-25T00:30:00 "tz=60 tzrule=eu rtcutc" "2026-10-25 02:3"; fi
if want E; then echo "== E  RTC local 11:00, NO zone on the boot line: SETTZ from /etc/time.conf converts it once =="
# the script writes the zone file, runs `sntp boot` (applies it; no ntp.conf = it ends
# at once) and only then reads the date: the last `date` line must be 11:0x local
SCRIPT="date;echo offset=120 > /etc/time.conf;sntp boot;date;sntp -n $SERVER;exit" WHICH="tail -1" \
check E  2026-10-11T11:00:00 ""                       "2026-10-11 11:0" 2026-10-11T09:00:00Z; fi
if want F; then echo "== F  RTC local 03:30 on 25.10. (already winter time, 02:30 UTC) =="
check F  2026-10-25T03:30:00 "tz=60 tzrule=eu"        "2026-10-25 03:3" 2026-10-25T02:30:00Z; fi
if want G; then echo "== G  RTC local 11:00 in winter (1.12., 10:00 UTC) =="
check G  2026-12-01T11:00:00 "tz=60 tzrule=eu"        "2026-12-01 11:0" 2026-12-01T10:00:00Z; fi

CLOCKSCRIPT="date;cat /proc/clock;sntp -n $SERVER;exit"
proc_has() { # CASE PATTERN DESCRIPTION
    if grep -aq -- "$2" "$OUT/$1.txt"; then ok "$1: /proc/clock $3"; else bad "$1: /proc/clock lacks $3 ('$2')"; fi
}
if want H; then echo "== H  25.10. 12:10 CET, RTC local in the winter frame (after the changeover) =="
SCRIPT="$CLOCKSCRIPT" check H 2026-10-25T12:10:00 "tz=60 tzrule=eu" "2026-10-25 12:1" 2026-10-25T11:10:00Z
proc_has H '^rtc 2026-10-25 12:10:.. mode=local frame=std rule=eu(1) base=+60 dst=0' "reports raw RTC, local mode, std frame, rule eu"
proc_has H '^sync none' "reports no sync yet"
if grep -aq '^alt-summer-frame' "$OUT/H.txt"; then ok "H: alt line present (recent changeover)"; else bad "H: alt line missing"; fi; fi
if want I; then echo "== I  25.10. 12:10 CET but the RTC still runs in the summer frame (reads 13:10): unavoidable without a time source =="
SCRIPT="$CLOCKSCRIPT" run I 2026-10-25T13:10:00 "tz=60 tzrule=eu" 2026-10-25T11:10:00Z
case "$LOCAL" in
    "2026-10-25 13:1"*) ok "I: the clock shows the RTC value 13:1.. (the frame cannot be known without a source)" ;;
    *) bad "I: after the boot '$LOCAL', expected 13:1.." ;;
esac
proc_has I '^rtc 2026-10-25 13:10:.. mode=local frame=std' "names the RTC raw value and the std frame"
proc_has I '^alt-summer-frame local 2026-10-25 12:10:' "offers the corrected reading 12:10 for a stale summer-frame RTC"
case "${OFF:-x}" in
    -3[56]??|3[56]??) ok "I: sntp measures the 1 h error (${OFF}s) and would fix it" ;;
    *) bad "I: offset '${OFF:-?}' not about 3600" ;;
esac; fi
if want J; then echo "== J  25.10. RTC UTC 11:10 + rtcutc (Linux habit, after the changeover) =="
SCRIPT="$CLOCKSCRIPT" check J 2026-10-25T11:10:00 "tz=60 tzrule=eu rtcutc" "2026-10-25 12:1" 2026-10-25T11:10:00Z
proc_has J '^rtc 2026-10-25 11:10:.. mode=utc frame=utc' "reports mode=utc"; fi
if want K; then echo "== K  RTC local 02:30 on 25.10., true instant 00:30 UTC (first 02:30, still CEST) =="
SCRIPT="$CLOCKSCRIPT" check K 2026-10-25T02:30:00 "tz=60 tzrule=eu" "2026-10-25 02:3" 2026-10-25T00:30:00Z
proc_has K '^rtc 2026-10-25 02:30:.. mode=local frame=summer' "reports the summer frame"; fi
if want L; then echo "== L  RTC local 02:30 on 25.10., true instant 01:30 UTC (second 02:30, already CET): the doubled hour is ambiguous =="
SCRIPT="$CLOCKSCRIPT" run L 2026-10-25T02:30:00 "tz=60 tzrule=eu" 2026-10-25T01:30:00Z
case "$LOCAL" in
    "2026-10-25 02:3"*) ok "L: shows 02:3.. (first reading wins, documented ambiguity)" ;;
    *) bad "L: after the boot '$LOCAL', expected 02:3.." ;;
esac
proc_has L '^rtc 2026-10-25 02:30:.. mode=local frame=summer' "reports which reading it chose"; fi

if want M; then echo "== M  RTC stale in the summer frame (13:10), the network clock arrives later: sntp corrects display + RTC =="
SCRIPT="date;sntp $SERVER;date;cat /proc/clock;exit" WHICH="tail -1" run M 2026-10-25T13:10:00 "tz=60 tzrule=eu" 2026-10-25T11:10:00Z
case "$LOCAL" in
    "2026-10-25 12:1"*) ok "M: after sntp the clock says 12:1.. (1 h corrected)" ;;
    *) bad "M: after sntp '$LOCAL', expected 12:1.." ;;
esac
proc_has M '^sync n=1 last utc 2026-10-25 11:1.:.. delta=-36[0-9][0-9] rtc_set=1' "records the sync: delta about -3600 s, RTC written back"; fi

echo
echo "=================================================================="
echo "  TIME-BOOT: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
