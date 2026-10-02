#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/time/run.sh -- DAILY-DRIVER: THE CLOCK, MEASURED.
#
#   bash tools/time/run.sh
#
# What a machine you use every day needs from its clock, and what this
# round built:
#
#   1. /bin/sntp builds, and the image carries it
#   2. the good way: ask a time server, see the offset, set the clock
#      (clock_settime, root only) -- against tools/time/fakentp.py, which
#      answers with any time the test wants, through QEMU's user network
#      (10.0.2.2 is the host)
#   3. SUMMER TIME BY RULE (`tz=60 tzrule=eu`): the local time at six
#      instants around the two European changeovers. The boot line used to
#      carry a fixed `tz=120`, which is an hour wrong all winter.
#   4. the faulty answers are refused and the clock stays where it was:
#      spoofed originate field, stratum 0, leap indicator 3, a short
#      packet, the wrong mode -- and a time outside 2024..2100 is refused
#      by the KERNEL even when the packet is fine
#   5. GEGENPROBE: without `tzrule=eu` the same instants show the fixed
#      offset all year
#
# What is not measured here, and cannot be in QEMU: whether a real board's
# CMOS accepts what rtc_write puts into it (the call is made, its result
# is not checked), and a real NTP server on the real network.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh
OUT=${OUT:-/tmp/time-run}
mkdir -p "$OUT"
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"
export OUT
PORT=${TIME_PORT:-$(( 12000 + ($$ % 900) ))}
export OSUM_CPU=${OSUM_CPU:-Haswell}
NETBASIS="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
SERVER="10.0.2.2:$PORT"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

NTPPID=""
ntp_aus() { [ -n "$NTPPID" ] && { kill "$NTPPID" 2>/dev/null; wait "$NTPPID" 2>/dev/null; }; NTPPID=""; }
trap ntp_aus EXIT
ntp() { # [--mode m] --time t1 t2 ...
    ntp_aus
    : > "$OUT/ntp.log"
    python3 tools/time/fakentp.py --port "$PORT" --log "$OUT/ntp.log" "$@" \
        > "$OUT/ntp.out" 2>&1 &
    NTPPID=$!
    local i
    for i in $(seq 1 30); do
        grep -qa "^START" "$OUT/ntp.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
lauf() { # name zone-words script [limit]
    cp -f "$OUT/ziel0.img" "$OUT/ziel.img"
    OTA_NETZ="$NETBASIS $2" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" iso "$3" "${4:-240}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "TIME: uebersprungen, $t fehlt"; exit 0; }
done

# =====================================================================
echo "== 1. the build: kernel, /bin/sntp, an image that carries it =="
# =====================================================================
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 \
    && ok "the pinned compiler ($(cut -c1-8 vendor/firn/COMMIT))" \
    || { bad "fetch-firnc.sh"; tail -5 "$OUT/firnc.log"; }
bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "image built ($(grep -a 'programme' "$OUT/build.log" | tr -s ' '))" \
    || { bad "tools/install/build.sh"; tail -20 "$OUT/build.log"; }
[ -s "$OUT/bin/sntp" ] && ok "/bin/sntp is in the image ($(stat -c%s "$OUT/bin/sntp") octets)" \
    || bad "/bin/sntp missing"
head -c $((64 * 1024 * 1024)) /dev/zero > "$OUT/ziel0.img"

# =====================================================================
echo
echo "== 2. the good way: ask, see the offset, set the clock =="
# =====================================================================
ntp --time 2026-10-02T12:00:00Z 2026-10-02T12:00:00Z 2026-10-02T12:00:00Z || bad "fake NTP server"
rc=$(lauf t1 "tz=60 tzrule=eu" "date;sntp -n $SERVER;date;sntp $SERVER;date;exit")
gleich "t1: the machine comes up" "$rc" "21"
hat "$OUT/t1.txt" "sntp: from 10.0.2.2 offset=" "the offset to the server is reported"
hat "$OUT/t1.txt" "sntp: clock left alone" "-n looks and does not touch"
hat "$OUT/t1.txt" "sntp: clock set" "without -n the clock is set (root)"
# after the set the local time is 14:00:xx (12:00 UTC + 2 h, summer time)
hat "$OUT/t1.txt" "2026-10-02 14:00:" "the clock now says 14:00 local (12:00 UTC, EU summer time)"
# the first `date` is before the set: it must NOT already say 2026-10-02 14:00
first=$(grep -a '^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] ' "$OUT/t1.txt" | head -1)
case "$first" in "2026-10-02 14:00:"*) bad "the first date is already the server's -- -n changed the clock" ;;
    *) ok "the first date ($first) was NOT the server's: -n did not set" ;; esac
grep -qa "^REQ 2 " "$OUT/ntp.log" && ok "the server saw two requests (one for -n, one for the set)" \
    || bad "server log: $(tr '\n' '|' < "$OUT/ntp.log")"

# =====================================================================
echo
echo "== 3. summer time by rule: six instants around the two changeovers =="
# =====================================================================
# 2026: last Sunday of March = 29th, of October = 25th, both 01:00 UTC.
ntp --time 2026-03-29T00:59:30Z 2026-03-29T01:00:30Z \
         2026-10-25T00:59:30Z 2026-10-25T01:00:30Z \
         2026-07-01T12:00:00Z 2026-12-01T12:00:00Z
rc=$(lauf t3 "tz=60 tzrule=eu" "sntp $SERVER;date;sntp $SERVER;date;sntp $SERVER;date;sntp $SERVER;date;sntp $SERVER;date;sntp $SERVER;date;exit")
gleich "t3: the machine comes up" "$rc" "21"
hat "$OUT/t3.txt" "2026-03-29 01:59:" "29.03. 00:59:30 UTC -> 01:59 (CET, +1 h): before the changeover"
hat "$OUT/t3.txt" "2026-03-29 03:00:" "29.03. 01:00:30 UTC -> 03:00 (CEST, +2 h): the clock jumped over 02:00"
hat "$OUT/t3.txt" "2026-10-25 02:59:" "25.10. 00:59:30 UTC -> 02:59 (CEST, +2 h): before the changeover"
hat "$OUT/t3.txt" "2026-10-25 02:00:" "25.10. 01:00:30 UTC -> 02:00 (CET, +1 h): the hour 02:00 comes a second time"
hat "$OUT/t3.txt" "2026-07-01 14:00:" "1 July 12:00 UTC -> 14:00 (summer)"
hat "$OUT/t3.txt" "2026-12-01 13:00:" "1 December 12:00 UTC -> 13:00 (winter)"

# =====================================================================
echo
echo "== 4. faulty answers are refused, the clock stays =="
# =====================================================================
for m in spoof kod li3 short wrongmode; do
    ntp --mode "$m" --time 2026-10-02T12:00:00Z
    rc=$(lauf "t4$m" "tz=60 tzrule=eu" "date;sntp $SERVER;date;exit" 300)
    hat "$OUT/t4$m.txt" "sntp: no valid answer" "$m: the answer is refused"
    hatnicht "$OUT/t4$m.txt" "sntp: clock set" "$m: and the clock is not set"
    hatnicht "$OUT/t4$m.txt" "2026-10-02 14:00:" "$m: nor does the time say what the forger wanted"
done
# a good packet with a time the kernel will not take
ntp --time 2001-01-01T00:00:00Z
rc=$(lauf t4old "tz=60 tzrule=eu" "sntp $SERVER;date;exit")
hat "$OUT/t4old.txt" "clock_settime refused" "a time before 2024 is refused by the KERNEL (-EINVAL)"
hatnicht "$OUT/t4old.txt" "2001-01-01" "... and the clock did not go there"
# 2150 does not fit the 32 bits of NTP: it wraps to a time before 2024 and is refused as such
ntp --time 2150-01-01T00:00:00Z
rc=$(lauf t4new "tz=60 tzrule=eu" "sntp $SERVER;date;exit")
hat "$OUT/t4new.txt" "clock_settime refused" "a time that wraps out of the 32 bits is refused too"
# NTP era 1 (after 7 February 2036) is read correctly: the machine does not
# stop updating its clock in 2036
ntp --time 2040-06-01T10:00:00Z
rc=$(lauf t4era "tz=60 tzrule=eu" "sntp $SERVER;date;exit")
hat "$OUT/t4era.txt" "sntp: clock set" "a server time in NTP era 1 (2040) is accepted"
hat "$OUT/t4era.txt" "2040-06-01 12:00:" "... and the local time is 12:00 (summer time)"

# =====================================================================
echo
echo "== 5. GEGENPROBE: without tzrule=eu the offset is fixed all year =="
# =====================================================================
ntp --time 2026-07-01T12:00:00Z 2026-12-01T12:00:00Z
rc=$(lauf t5 "tz=120" "sntp $SERVER;date;sntp $SERVER;date;exit")
hat "$OUT/t5.txt" "2026-07-01 14:00:" "tz=120 alone: July is 14:00"
hat "$OUT/t5.txt" "2026-12-01 14:00:" "tz=120 alone: December is STILL 14:00 -- the old wrong winter clock"
ntp_aus

echo
echo "=================================================================="
echo "  TIME: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
