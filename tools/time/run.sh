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

NTPPIDS=()
ntp_aus() {
    local p
    for p in "${NTPPIDS[@]:-}"; do
        [ -n "$p" ] && { kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; }
    done
    NTPPIDS=()
}
trap ntp_aus EXIT
ntp_more() { # port logname [--mode m] --time t1 t2 ...
    local port=$1 name=$2
    shift 2
    : > "$OUT/$name.log"
    python3 tools/time/fakentp.py --port "$port" --log "$OUT/$name.log" "$@" \
        > "$OUT/$name.out" 2>&1 &
    NTPPIDS+=($!)
    local i
    for i in $(seq 1 30); do
        grep -qa "^START" "$OUT/$name.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}
ntp() { # [--mode m] --time t1 t2 ...
    ntp_aus
    ntp_more "$PORT" ntp "$@"
}
offset_ms_of() { # file nth -> offset_ms of the nth "sntp: from" line
    grep -a -o 'offset_ms=-\?[0-9]*' "$1" | sed -n "${2}p" | sed 's/offset_ms=//'
}
between() { # description value low high
    if [ -n "$2" ] && [ "$2" -ge "$3" ] && [ "$2" -le "$4" ]; then ok "$1: $2 (expected $3..$4)"; else bad "$1: '$2' not in $3..$4"; fi
}
lauf() { # name zone-words script [limit]
    cp -f "$OUT/ziel0.img" "$OUT/ziel.img"
    OTA_NETZ="$NETBASIS $2" OUT="$OUT" bash tools/install/oneshot.sh \
        "$1" iso "$3" "${4:-240}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

sect() { case " ${TIME_SECTIONS:-2 3 4 5 6 7 8} " in *" $1 "*) return 0 ;; esac; return 1; }

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "TIME: uebersprungen, $t fehlt"; exit 0; }
done

# =====================================================================
echo "== 1. the build: kernel, /bin/sntp, an image that carries it =="
# =====================================================================
if [ -z "${TIME_REUSE:-}" ] || [ ! -s "$OUT/ziel0.img" ]; then
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 \
    && ok "the pinned compiler ($(cut -c1-8 vendor/firn/COMMIT))" \
    || { bad "fetch-firnc.sh"; tail -5 "$OUT/firnc.log"; }
bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "image built ($(grep -a 'programme' "$OUT/build.log" | tr -s ' '))" \
    || { bad "tools/install/build.sh"; tail -20 "$OUT/build.log"; }
[ -s "$OUT/bin/sntp" ] && ok "/bin/sntp is in the image ($(stat -c%s "$OUT/bin/sntp") octets)" \
    || bad "/bin/sntp missing"
head -c $((64 * 1024 * 1024)) /dev/zero > "$OUT/ziel0.img"
fi

# =====================================================================
if sect 2; then
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

fi
# =====================================================================
if sect 3; then
echo
echo "== 3. summer time by rule: six instants around the two changeovers =="
# =====================================================================
# 2027: last Sunday of March = 28th, of October = 31st, both 01:00 UTC.
# (the clock floor is 2026-10-01: a server time before it is not plausible.)
ntp --time 2027-03-28T00:59:30Z 2027-03-28T01:00:30Z \
         2027-10-31T00:59:30Z 2027-10-31T01:00:30Z \
         2027-07-01T12:00:00Z 2027-12-01T12:00:00Z
rc=$(lauf t3 "tz=60 tzrule=eu" "sntp -f $SERVER;date;sntp -f $SERVER;date;sntp -f $SERVER;date;sntp -f $SERVER;date;sntp -f $SERVER;date;sntp -f $SERVER;date;exit")
gleich "t3: the machine comes up" "$rc" "21"
hat "$OUT/t3.txt" "2027-03-28 01:59:" "28.03. 00:59:30 UTC -> 01:59 (CET, +1 h): before the changeover"
hat "$OUT/t3.txt" "2027-03-28 03:00:" "28.03. 01:00:30 UTC -> 03:00 (CEST, +2 h): the clock jumped over 02:00"
hat "$OUT/t3.txt" "2027-10-31 02:59:" "31.10. 00:59:30 UTC -> 02:59 (CEST, +2 h): before the changeover"
hat "$OUT/t3.txt" "2027-10-31 02:00:" "31.10. 01:00:30 UTC -> 02:00 (CET, +1 h): the hour 02:00 comes a second time"
hat "$OUT/t3.txt" "2027-07-01 14:00:" "1 July 12:00 UTC -> 14:00 (summer)"
hat "$OUT/t3.txt" "2027-12-01 13:00:" "1 December 12:00 UTC -> 13:00 (winter)"

fi
# =====================================================================
if sect 4; then
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
hat "$OUT/t4old.txt" "refused: time not plausible" "a time before the clock floor (2026-10-01) is not plausible: refused before any set"
hatnicht "$OUT/t4old.txt" "2001-01-01" "... and the clock did not go there"
# 2150 does not fit the 32 bits of NTP: it wraps to a time before 2024 and is refused as such
ntp --time 2150-01-01T00:00:00Z
rc=$(lauf t4new "tz=60 tzrule=eu" "sntp $SERVER;date;exit")
hat "$OUT/t4new.txt" "refused: time not plausible" "a time that wraps out of the 32 bits reads as 2014 and is refused too"
# NTP era 1 (after 7 February 2036) is read correctly: the machine does not
# stop updating its clock in 2036
ntp --time 2040-06-01T10:00:00Z
rc=$(lauf t4era "tz=60 tzrule=eu" "sntp $SERVER;date;exit")
hat "$OUT/t4era.txt" "sntp: clock set" "a server time in NTP era 1 (2040) is accepted"
hat "$OUT/t4era.txt" "2040-06-01 12:00:" "... and the local time is 12:00 (summer time)"

fi
# =====================================================================
if sect 5; then
echo
echo "== 5. GEGENPROBE: without tzrule=eu the offset is fixed all year =="
# =====================================================================
ntp --time 2027-07-01T12:00:00Z 2027-12-01T12:00:00Z
rc=$(lauf t5 "tz=120" "sntp -f $SERVER;date;sntp -f $SERVER;date;exit")
hat "$OUT/t5.txt" "2027-07-01 14:00:" "tz=120 alone: July is 14:00"
hat "$OUT/t5.txt" "2027-12-01 14:00:" "tz=120 alone: December is STILL 14:00 -- the old wrong winter clock"
ntp_aus

fi
# =====================================================================
if sect 6; then
echo
echo "== 6. step to the nanosecond, slew, panic limit =="
# =====================================================================
PORT2=$((PORT + 1))
PORT3=$((PORT + 2))
SERVER2="10.0.2.2:$PORT2"
SERVER3="10.0.2.2:$PORT3"
ntp --now-offset-ms 700
rc=$(lauf t6step "tz=60 tzrule=eu" "sntp $SERVER;sntp -n $SERVER;exit")
gleich "t6step: the machine comes up" "$rc" "21"
hat "$OUT/t6step.txt" "sntp: clock set" "the first sync steps the clock"
between "t6step: after the step the offset to the server (ms)" "$(offset_ms_of "$OUT/t6step.txt" 2)" -25 25

ntp --now-offset-ms 700
ntp_more "$PORT2" ntp2 --now-offset-ms 712
rc=$(lauf t6slew "tz=60 tzrule=eu" "sntp $SERVER;sntp $SERVER2;sntp -n $SERVER2;sleep 10;sntp -n $SERVER2;cat /proc/clock;exit" 300)
gleich "t6slew: the machine comes up" "$rc" "21"
hat "$OUT/t6slew.txt" "sntp: clock slewed by" "a 12 ms offset is slewed, not stepped"
between "t6slew: offset right after the slew was queued (ms)" "$(offset_ms_of "$OUT/t6slew.txt" 3)" 7 14
left_ns=$(grep -a -o 'slew_ns=-\?[0-9]*' "$OUT/t6slew.txt" | tail -1 | sed 's/slew_ns=//')
between "t6slew: ten seconds later the kernel still has about half to slew (ns, 500 ppm)" "$left_ns" 3000000 8500000
hat "$OUT/t6slew.txt" "clock state=set" "/proc/clock says the clock is set"

ntp --time 2027-01-01T12:00:00Z
ntp_more "$PORT2" ntp2 --time 2027-01-02T12:00:00Z
rc=$(lauf t6panic "tz=60 tzrule=eu" "sntp $SERVER;sntp $SERVER2;date;sntp -f $SERVER2;date;exit" 300)
hat "$OUT/t6panic.txt" "beyond the panic limit, refused" "a synchronised clock is not dragged a day away"
hat "$OUT/t6panic.txt" "2027-01-01 13:00:" "the clock stayed at the first server's time"
hat "$OUT/t6panic.txt" "2027-01-02 13:00:" "-f takes the step on request"
ntp_aus

fi
# =====================================================================
if sect 7; then
echo
echo "== 7. several sources: majority, no quorum, rate limit =="
# =====================================================================
ntp --time 2027-01-01T12:00:00Z
ntp_more "$PORT2" ntp2 --time 2027-01-01T12:00:00Z
ntp_more "$PORT3" ntp3 --time 2027-06-01T12:00:00Z
rc=$(lauf t7maj "tz=60 tzrule=eu" "sntp $SERVER $SERVER2 $SERVER3;date;exit" 300)
hat "$OUT/t7maj.txt" "sntp: 2 of 3 sources agree" "one liar among three is outvoted"
hat "$OUT/t7maj.txt" "2027-01-01 13:00:" "the clock took the majority's time"
hatnicht "$OUT/t7maj.txt" "2027-06-01" "and not the liar's"
ntp --time 2027-01-01T12:00:00Z
ntp_more "$PORT3" ntp3 --time 2027-06-01T12:00:00Z
rc=$(lauf t7split "tz=60 tzrule=eu" "sntp $SERVER $SERVER3;date;exit" 300)
hat "$OUT/t7split.txt" "sntp: sources disagree" "two sources that disagree move nothing"
hatnicht "$OUT/t7split.txt" "sntp: clock set" "no set without agreement"
ntp --mode rate --time 2027-01-01T12:00:00Z
rc=$(lauf t7rate "tz=60 tzrule=eu" "sntp $SERVER;date;exit" 300)
hat "$OUT/t7rate.txt" "refused: kiss-o'-death RATE" "a RATE answer is recognised as such"
hatnicht "$OUT/t7rate.txt" "sntp: clock set" "and sets nothing"
ntp_aus
fi

if sect 8; then
echo
echo "== 8. the real pool, through QEMU's user network =="
POOL_IPS=$(python3 - <<'PY'
import socket, struct, time
ips = []
for n in range(4):
    try:
        ip = socket.gethostbyname("%d.pool.ntp.org" % n)
    except OSError:
        continue
    if ip in ips:
        continue
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(2)
    try:
        s.sendto(b"\x23" + b"\0" * 47, (ip, 123))
        s.recvfrom(100)
        ips.append(ip)
    except OSError:
        pass
print(" ".join(ips))
PY
)
set -- $POOL_IPS
if [ "$#" -lt 2 ]; then
    echo "  SKIP  no route to the public NTP pool from this host ($# usable servers)"
else
    rc=$(lauf t8pool "tz=60 tzrule=eu" "sntp -n $POOL_IPS;exit" 300)
    gleich "t8pool: the machine comes up" "$rc" "21"
    hat "$OUT/t8pool.txt" "sntp: from $1 offset=" "the first real pool server answers"
    hat "$OUT/t8pool.txt" " sources agree" "the real servers agree with each other"
    off=$(grep -a -o 'sources agree, offset_ms=-\?[0-9]*' "$OUT/t8pool.txt" | sed 's/.*offset_ms=//' | head -1)
    case "$off" in
        ""|*[!0-9-]*) bad "t8pool: no agreed offset in the output" ;;
        *) off_abs=${off#-}
           if [ "$off_abs" -le 7300000 ]; then ok "t8pool: offset to the real time is ${off} ms (the guest RTC is UTC read as local, so up to two hours are expected)"
           else bad "t8pool: offset ${off} ms is implausible"; fi ;;
    esac
fi
fi

echo
echo "=================================================================="
echo "  TIME: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
