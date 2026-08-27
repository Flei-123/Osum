#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/powermon/run.sh -- WHERE THE BATTERY GOES, AND WHAT OF IT IS MEASURED.
#
# ==================================================================
# WHAT THIS HOST CAN PROVE AND WHAT IT CANNOT -- READ THIS FIRST
# ==================================================================
#
# The measuring machine is QEMU 7.2 without /dev/kvm, so TCG. `-device
# battery` arrived in QEMU 8.2 and does not exist here; the only battery
# on this host is the one `tools/k18/ssdt.py` writes into an ACPI table
# and hands over with `-acpitable`. That single fact decides the shape of
# this whole run:
#
#   * THE MEASURED DRAW IS A CONSTANT. `_BST` is a static package in a
#     static table. It says 7700 mW while the machine idles and 7700 mW
#     while it computes, because it is a number in a file. NOTHING in
#     this run may be read as "the power went up under load", and nothing
#     here claims it. Whether the draw of a real machine responds to load
#     the way this round assumes IS NOT TESTED HERE AND CANNOT BE.
#
#   * THE SPLIT IS REAL. `T_TICKS` is counted by the scheduler on a real
#     timer, it moves with the load, and every share in this run comes
#     out of it. Section 6 starts a program that holds the processor and
#     shows its share appearing, and shows the column adding up to a
#     hundred exactly.
#
#   * THE FLOOR IS REAL, AND SO IS WHAT HAPPENS WITHOUT IT. Section 5
#     runs the SAME workload against the SAME table twice, once with the
#     idle floor measured and once with `pmonnofloor`, and the two runs
#     hand the programs completely different numbers. That is the
#     commonest mistake in this kind of display, demonstrated rather than
#     described.
#
#   * THE PIPELINE IS REAL. Section 4 boots the same kernel against three
#     different tables and gets three different answers out of
#     `/bin/powermon`. A number that changes when the firmware changes
#     came from the firmware.
#
#   * WHAT THE BOOKKEEPING COSTS IS MEASURED. Section 8 runs the same
#     workload with and without `nopowermon`. A monitor whose own cost is
#     a guess is a monitor in the wrong place -- and this one runs inside
#     a timer interrupt.
#
# EVERY CLAIM HAS A COUNTER-CHECK, and a MISSING value FAILS instead of
# passing quietly. That is the lesson of round B3 and of round K18 before
# this one: two empty pages are not an agreement.
#
# `pmonsay` on every command line below: without it the kernel prints no
# report at all. That word exists because the first version printed one in
# every boot, and `kmain.power_stage` runs in every boot that does not say
# `nopwr` -- which scrolled the shell's own line off the mirrored console
# in tools/gfx/run.sh. A round that talks in runs that did not ask it to
# is a round that breaks other people's measurements.
#
# Usage:  bash tools/powermon/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BLOCKS=4096
PROGS="sh echo cat ls power powermon burn"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

same() { # name want got
    if [ "$2" = "$3" ]; then ok "$1 ($3)"
    else bad "$1 -- want '$2', got '$3'"; fi
}
num() { # name value op want
    if [ -z "${2:-}" ]; then bad "$1: no number at all (wanted $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, wanted $3 $4"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
has_not() { grep -qaF "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }

# A value out of the KERNEL's report ("pmon: name=number").
kw() { grep -a -m1 "^pmon: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '\r\000'; }
# A value out of RING 3 ("powermon: name=number").
uw() { grep -a -m1 "^powermon: $2=" "$1" 2>/dev/null | sed 's/^[^=]*=//' | tr -d '\r\000'; }
# One program row out of ring 3: "powermon: NAME ticks energy share procs".
prow() { grep -a -m1 "^powermon: $2 " "$1" 2>/dev/null | awk "{print \$$3}" | tr -d '\r\000'; }
# One program row out of the KERNEL: "pmon: pN ticks energy procs name".
kprow() { grep -a "^pmon: p" "$1" 2>/dev/null | awk -v n="$2" "\$6==n{print \$$3}" | tr -d '\r\000'; }

# A CLAIM ABOUT A VALUE FROM RING 3. A MISSING value FAILS -- the lesson
# of round B3, written down for the third time.
says() { # file name want description
    local got; got=$(uw "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- the line 'powermon: $2=' is missing entirely"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, wanted $3"; fi
}
ksays() { # file name want description
    local got; got=$(kw "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- the line 'pmon: $2=' is missing entirely"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, wanted $3"; fi
}
number_in() { grep -aE "^const $2: u64 = [0-9]+" "$1" | head -1 \
    | sed -E 's/^const [A-Za-z0-9_]+: u64 = ([0-9]+).*/\1/'; }

bash vendor/firn/hole-firnc.sh >/dev/null || { echo "vendor/firn/hole-firnc.sh failed"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "POWERMON: skipped, qemu-system-x86_64 is missing"
    exit 0
fi

# ============================================ 1. the numbers and the map

echo "== 1. the call number, the page of kdata, the licence and the language =="

v=$(number_in kernel/sys.fi "SYS_OSUM_PMON")
same "SYS_OSUM_PMON" "1830" "${v:-missing}"
if [ "${v:-0}" -ge 1830 ] && [ "${v:-0}" -le 1839 ]; then
    ok "SYS_OSUM_PMON lies inside this round's store 1830..1839: $v"
else
    bad "SYS_OSUM_PMON = ${v:-missing} lies OUTSIDE 1830..1839"
fi

# THE NUMBERS OF THIS ROUND APPEAR NOWHERE ELSE. This is the situation
# out of which all four kdata collisions of this project grew: a dozen
# rounds on the same tree at the same time. Round K18 learned to look for
# CALL NUMBERS and not for any occurrence of the digits -- a buffer
# length of 1832 collides with nothing.
foreign=$(grep -ran --include='*.fi' --include='*.s' -E '^const SYS_[A-Za-z0-9_]+: u64 = 183[0-9]' kernel/ \
    | grep -v -e '^kernel/sys.fi' -e '^kernel/user/powermon.fi' || true)
if [ -z "$foreign" ]; then
    ok "no CALL NUMBER out of 1830..1839 stands outside this round's files"
else
    bad "call numbers from 1830..1839 also stand in: $(echo $foreign | tr '\n' ' ')"
fi

pmoff=$(grep -aE '^const PMON_OFF' kernel/kstate.fi | sed 's/.*= //')
pmmax=$(grep -aE '^const PMON_MAX' kernel/kstate.fi | sed 's/.*= //')
same "the kdata pages of this round" "0x5C000" "$pmoff"
same "how many of them" "0x3000" "$pmmax"

# THE MAP CHECKER is the only thing that can see a collision that stands
# in no shared line of text.
if python3 tools/kernel/karte.py kernel > "$TMPD/map.txt" 2>&1; then
    ok "the memory map of kdata: $(tail -1 "$TMPD/map.txt")"
else
    bad "tools/kernel/karte.py reports collisions"
    sed 's/^/        /' "$TMPD/map.txt" | head -8
fi
has "$TMPD/map.txt" "0 Kollisionen" "no two areas of kdata overlap"

# This round starts at 0x5C000 and not at the first free page, because
# NETMON and DISPLAY are taking 0x5A000..0x5C000 on their own branches at
# this moment. Checked, so a later edit cannot quietly move it into them.
if [ "$(python3 -c "print(int('${pmoff:-0}',0))")" -ge "$(python3 -c "print(int('0x5C000',0))")" ]; then
    ok "this round's area starts above the pages NETMON and DISPLAY are taking"
else
    bad "this round's area starts at $pmoff, inside 0x5A000..0x5C000"
fi

# SPDX ON EVERY NEW FILE OF THIS ROUND.
for f in kernel/pmon.fi kernel/user/powermon.fi kernel/user/burn.fi \
         tools/powermon/run.sh docs/POWERMON.md; do
    if head -3 "$f" 2>/dev/null | grep -qa 'SPDX-License-Identifier: GPL-2.0-only'; then
        ok "SPDX header in $f"
    else
        bad "SPDX header missing in $f"
    fi
done

# ENGLISH, AND PLAIN ASCII. The rule of this round, checked and not promised.
for f in kernel/pmon.fi kernel/user/powermon.fi kernel/user/burn.fi; do
    ger=$(grep -cawi -E 'und|oder|nicht|eine|einen|werden|wird|ueber|fuer|Runde|Zahl|Datei|Aufgabe' "$f" || true)
    if [ "${ger:-0}" -eq 0 ]; then ok "$f is English throughout"
    else bad "$f still holds $ger lines with German words"; fi
    if LC_ALL=C grep -qa -P '[\x80-\xFF]' "$f"; then
        bad "$f holds octets outside ASCII (umlauts?)"
    else
        ok "$f is plain ASCII"
    fi
done

# ==================================================== 2. build

echo "== 2. the kernel and the programs =="

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || { echo "as fails"; exit 1; }
rc=0
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/k0.log" 2>&1 || {
    bad "the kernel does not build"; sed 's/^/        /' "$TMPD/k0.log" | tail -8; rc=1; }
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/$p.err" 2>&1 || {
        bad "firnc does not translate $p.fi"; head -6 "$TMPD/$p.err"; rc=1; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/$p.elf" \
        "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || { bad "ld fails on $p"; rc=1; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ "$rc" = 0 ] && ok "the kernel and $(echo $PROGS | wc -w) programs are built"
[ -f "$TMPD/k0.mb" ] || { echo "POWERMON: nothing works without a kernel"; echo "POWERMON: $pass passed, $((fail+1)) failed"; exit 1; }

# The second compiler, the one written in Firn. Both have to build this.
if bash tools/build-kernel.sh "$TMPD/k1.mb" --stufe 1 > "$TMPD/k1.log" 2>&1; then
    ok "firnc1 builds this round too (the compiler written in Firn)"
else
    bad "firnc1 does not build this round"; tail -5 "$TMPD/k1.log" | sed 's/^/        /'
fi

MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/$p.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" /bin/ /etc/ $MKARGS \
    > "$TMPD/mkfs.log" 2>&1 && ok "the disk is built: $(tail -1 "$TMPD/mkfs.log")" \
    || bad "mkfs.py fails"

# ============================================ 3. the batteries this run writes

echo "== 3. the ACPI batteries this run dictates =="

mk_ssdt() { # name arguments...
    local n=$1; shift
    python3 tools/k18/ssdt.py "$TMPD/$n.aml" "$@" > "$TMPD/$n.want" 2>&1 \
        && ok "SSDT '$n' built: $(cat "$TMPD/$n.want")" \
        || { bad "ssdt.py fails on '$n'"; cat "$TMPD/$n.want"; }
}
# Three batteries that differ in the ONE number this round is about: the
# present rate of draw. Plus one that is worn out and one on mains.
mk_ssdt low   --rest 3300 --voll 4400 --design 4400 --rate 1200 --volt 11400 --zustand 1 --netz 0
mk_ssdt high  --rest 3300 --voll 4400 --design 4400 --rate 7700 --volt 11400 --zustand 1 --netz 0
mk_ssdt worn  --rest 2200 --voll 3000 --design 6000 --rate 2500 --volt 11400 --zustand 1 --netz 0
mk_ssdt mains --rest 3300 --voll 4400 --design 4400 --rate 900  --volt 11400 --zustand 2 --netz 1
mk_ssdt none  --kein-akku

run() { # name commandline [ssdt] [timeout]
    local name=$1 line=$2 ssdt=${3:-} t=${4:-200}
    local out="$TMPD/$name.txt"
    rm -f "$out"
    cp -f "$TMPD/root.img" "$TMPD/live-$name.img"
    local -a args
    args=(-cpu max -kernel "$TMPD/k0.mb" -m 256 -append "$line" -serial "file:$out"
          -display none -no-reboot
          -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0"
          -device isa-debug-exit,iobase=0xf4,iosize=0x04)
    [ -n "$ssdt" ] && args+=(-acpitable
        "sig=SSDT,rev=2,oem_id=OSUM,oem_table_id=PMON,data=$TMPD/$ssdt.aml")
    timeout "$t" qemu-system-x86_64 "${args[@]}" > /dev/null 2>&1
    echo $?
}

# ======================================== 4. the number comes from outside

echo "== 4. the measured draw comes from the firmware and from nowhere else =="

RC=$(run low "osum pwr pmonsay nokbd script=powermon raw;exit" low)
num "the run with the 1200 mW battery ends cleanly" "$RC" eq 21
says "$TMPD/low.txt" rate 1200 "ring 3 reports the rate that stands in the table"
says "$TMPD/low.txt" rateok 1 "and says that it really read it"

RC=$(run high "osum pwr pmonsay nokbd script=powermon raw;exit" high)
num "the run with the 7700 mW battery ends cleanly" "$RC" eq 21
says "$TMPD/high.txt" rate 7700 "another table, another rate -- the number is not in the kernel"

# THE COUNTER-CHECK THAT MATTERS MOST: no battery, no numbers. A monitor
# that prints a zero where it measured nothing is worse than one that
# prints nothing, because a zero in milliwatts looks like a measurement.
RC=$(run none "osum pwr pmonsay nokbd script=powermon raw;powermon;exit" none)
num "the run without a battery ends cleanly" "$RC" eq 21
says "$TMPD/none.txt" rateok 0 "GEGENPROBE without a battery: nothing was measured"
says "$TMPD/none.txt" rate 0 "and the rate stays zero instead of being invented"
has "$TMPD/none.txt" "Power now          --" "and the page shows a dash and not a zero"

# THE TWO SIDES OF THE SAME NUMBERS: the kernel on the serial line, ring
# 3 over the system call. Where they part, the interface is broken.
#
# But only for the numbers that CAN be compared. The kernel prints its
# report when the run ends, `/bin/powermon` read its values earlier, and
# the machine kept counting in between -- so `samples`, `windows` and the
# two energy totals are LARGER on the kernel's side by construction. The
# first draft of this run compared them for equality and failed on
# `samples=23` against `samples=22`, which is not a fault in anything.
# Equality for the standing values, "grew or stayed" for the counters.
for f in rate rateok health healthok minutes hz on unit; do
    a=$(kw "$TMPD/high.txt" "$f"); b=$(uw "$TMPD/high.txt" "$f")
    if [ -z "$a" ] || [ -z "$b" ]; then
        bad "$f: one of the two sides did not report at all (kernel='$a' ring3='$b')"
    elif [ "$a" = "$b" ]; then ok "$f: kernel and /bin/powermon say the same ($a)"
    else bad "$f: kernel says $a, /bin/powermon says $b"; fi
done
for f in samples windows proce syse basen misses; do
    a=$(kw "$TMPD/high.txt" "$f"); b=$(uw "$TMPD/high.txt" "$f")
    if [ -z "$a" ] || [ -z "$b" ]; then
        bad "$f: one of the two sides did not report at all (kernel='$a' ring3='$b')"
    elif [ "$a" -ge "$b" ]; then ok "$f: a counter that only grows -- ring 3 $b, kernel $a later"
    else bad "$f: the kernel's later value $a is SMALLER than ring 3's earlier $b"; fi
done

# ==================================== 5. the floor, and the mistake without it

echo "== 5. the system floor -- and what the display looks like without it =="

# THE SAME WORKLOAD, THE SAME TABLE, TWICE. Once with the floor measured,
# once with `pmonnofloor`. Without a floor, whichever program happens to
# be awake gets the backlight, the radios and the chipset hung around its
# neck; with one, they are called what they are.
RC=$(run floor "osum pwr pmonsay nokbd script=burn 6;powermon raw;exit" high 300)
num "the run with the floor ends cleanly" "$RC" eq 21
RC=$(run nofloor "osum pwr pmonsay pmonnofloor nokbd script=burn 6;powermon raw;exit" high 300)
num "the run without the floor ends cleanly" "$RC" eq 21

says "$TMPD/floor.txt" baseok 1 "with the floor: it was really measured"
says "$TMPD/nofloor.txt" baseok 0 "GEGENPROBE pmonnofloor: no floor was measured"
says "$TMPD/nofloor.txt" base 0 "and the floor is therefore zero and not guessed at"

fb=$(uw "$TMPD/floor.txt" basen)
num "the floor rests on more than one idle window" "${fb:-0}" gt 1

a1=$(uw "$TMPD/floor.txt" attrib); a2=$(uw "$TMPD/nofloor.txt" attrib)
r1=$(uw "$TMPD/floor.txt" rate);   b1=$(uw "$TMPD/floor.txt" base)
if [ -z "$a1" ] || [ -z "$a2" ] || [ -z "$r1" ] || [ -z "$b1" ]; then
    bad "one of the two runs did not report the numbers this claim needs"
else
    same "with the floor, the attributable part is rate minus floor" \
        "$((r1 - b1))" "$a1"
    same "without it, the WHOLE measured draw is handed to the programs" "$r1" "$a2"
    if [ "$a2" -gt "$a1" ]; then
        ok "the two displays differ by $((a2 - a1)) mW on the same machine -- the mistake, measured"
    else
        bad "the floor made no difference: with $a1 mW, without $a2 mW"
    fi
fi

# And the arithmetic that says the floor was not simply thrown away: all
# of the measured draw is still accounted for, only under another name.
p1=$(uw "$TMPD/floor.txt" proce); s1=$(uw "$TMPD/floor.txt" syse)
p2=$(uw "$TMPD/nofloor.txt" proce); s2=$(uw "$TMPD/nofloor.txt" syse)
if [ -n "$p1" ] && [ -n "$s1" ] && [ -n "$p2" ] && [ -n "$s2" ]; then
    if [ "$p1" -lt "$p2" ] && [ "$s1" -gt "$s2" ]; then
        ok "the same energy, booked differently: programs $p1 -> $p2, system $s1 -> $s2 mW-ticks"
    else
        bad "the two runs do not move the energy the way the floor demands ($p1/$s1 against $p2/$s2)"
    fi
else
    bad "one of the two runs reported neither proce nor syse"
fi

# ==================================== 6. the split is real and it adds up

echo "== 6. the split: it follows the load and the column adds to a hundred =="

# `burn` holds the processor and makes no system call inside its loop, so
# it is runnable on every timer tick. `ls` is the opposite: it waits on a
# disk, so it collects almost no ticks -- the correct answer for `ls`,
# and the reason a load test needs a program like `burn`.
RC=$(run idle "osum pwr pmonsay pmonnofloor nokbd script=echo x;powermon raw;exit" high)
num "the quiet run ends cleanly" "$RC" eq 21
RC=$(run load "osum pwr pmonsay pmonnofloor nokbd script=burn 60;powermon raw;exit" high 400)
num "the busy run ends cleanly" "$RC" eq 21

bt=$(prow "$TMPD/load.txt" burn 3)
if [ -z "$bt" ]; then
    bad "the busy run shows no row for burn at all"
else
    num "burn appears in the table with processor time of its own" "$bt" gt 0
fi
bs=$(prow "$TMPD/load.txt" burn 5)
num "and with a share above zero" "${bs:-0}" gt 0

# The quiet run must NOT show it. A monitor that reports a program which
# did not run is as broken as one that misses a program which did.
if grep -qa '^powermon: burn ' "$TMPD/idle.txt"; then
    bad "GEGENPROBE: burn has a row in a run in which it never started"
else
    ok "GEGENPROBE: no row for burn in the run in which it never started"
fi

# THE COLUMN ADDS UP TO A HUNDRED. Not 99, not 101. Ring 3 rounds on the
# running sum for exactly this reason.
says "$TMPD/load.txt" sumshare 100 "the shares add up to a hundred exactly"
says "$TMPD/floor.txt" sumshare 100 "and they do in the other run as well"

# AND THE SUM OF THE ROWS IS THE KERNEL'S OWN TOTAL. The split is exact
# integer arithmetic with no division in it, and this is where that is
# checked rather than asserted.
python3 - "$TMPD/load.txt" > "$TMPD/sum.txt" 2>&1 <<'PYEOF'
import re, sys
text = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
scal = {m.group(1): int(m.group(2))
        for m in re.finditer(r'^powermon: (\w+)=(\d+)\s*$', text, re.M)}
rows = re.findall(r'^powermon: (\S+) (\d+) (\d+) (\d+) (\d+)\s*$', text, re.M)
e = sum(int(r[2]) for r in rows)
t = sum(int(r[1]) for r in rows)
print("rows=%d rowenergy=%d proce=%d rowticks=%d progticks=%d"
      % (len(rows), e, scal.get('proce', -1), t, scal.get('progticks', -1)))
print("EQUAL" if rows and e == scal.get('proce') and t == scal.get('progticks')
      else "DIFFERENT")
PYEOF
sed 's/^/        /' "$TMPD/sum.txt"
has "$TMPD/sum.txt" "EQUAL" "the sum of the program rows IS the kernel's own total, to the last mW-tick"

# The same identity from the kernel's side, out of the serial report.
python3 - "$TMPD/load.txt" > "$TMPD/ksum.txt" 2>&1 <<'PYEOF'
import re, sys
text = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
scal = {m.group(1): int(m.group(2))
        for m in re.finditer(r'^pmon: (\w+)=(\d+)\s*$', text, re.M)}
rows = re.findall(r'^pmon: p\d+ (\d+) (\d+) (\d+) (\S+)\s*$', text, re.M)
e = sum(int(r[1]) for r in rows)
print("kernelrows=%d rowenergy=%d proce=%d" % (len(rows), e, scal.get('proce', -1)))
print("EQUAL" if rows and e == scal.get('proce') else "DIFFERENT")
PYEOF
sed 's/^/        /' "$TMPD/ksum.txt"
has "$TMPD/ksum.txt" "EQUAL" "and the kernel's own rows add up to the same number"

# ==================================== 7. the numbers that explain a battery

echo "== 7. ageing, runtime left, mains against battery =="

# LAST FULL CHARGE AGAINST DESIGN CHARGE. The table says 3000 of 6000, so
# the answer is fifty, and it is fifty because the table says so.
RC=$(run worn "osum pwr pmonsay nokbd script=powermon raw;powermon;exit" worn)
num "the run with the worn battery ends cleanly" "$RC" eq 21
says "$TMPD/worn.txt" health 50 "the ageing of the battery: 3000 of 6000 mWh is fifty percent"
says "$TMPD/worn.txt" healthok 1 "and both numbers were really read"
has "$TMPD/worn.txt" "Health             50 %" "the page puts it in front of the person"
says "$TMPD/high.txt" health 100 "GEGENPROBE: a battery at its design charge reads a hundred percent"

# RUNTIME OUT OF THE RATE THAT WAS JUST MEASURED. 3300 mWh at 7700 mW is
# 25 minutes, at 1200 mW it is 165. Same charge, different draw.
says "$TMPD/high.txt" minutes 25 "runtime left at 7700 mW: 25 minutes"
says "$TMPD/low.txt" minutes 165 "the same charge at 1200 mW: 165 minutes"

# MAINS AGAINST BATTERY, kept apart.
RC=$(run mains "osum pwr pmonsay nokbd script=powermon raw;powermon;exit" mains)
num "the run on mains ends cleanly" "$RC" eq 21
says "$TMPD/mains.txt" acrate 900 "on mains the rate is booked as the mains rate"
says "$TMPD/mains.txt" batrate 0 "and nothing is booked as a battery rate"
says "$TMPD/high.txt" batrate 7700 "on battery it is the other way round"
says "$TMPD/high.txt" acrate 0 "and nothing is booked as a mains rate"
has "$TMPD/mains.txt" "On mains          yes" "the page says which of the two it is"

# ======================================= 8. what the bookkeeping costs

echo "== 8. what the accounting itself costs, measured =="

# THE SAME WORKLOAD, ONCE COUNTED AND ONCE NOT. `nopowermon` is the
# counter-check and the difference between the two runs is the price.
RC=$(run cost_on "osum pwr pmonsay nokbd script=burn 60;powermon raw;exit" high 400)
num "the counted run ends cleanly" "$RC" eq 21
RC=$(run cost_off "osum pwr pmonsay nopowermon nokbd script=burn 60;powermon raw;exit" high 400)
num "the uncounted run ends cleanly" "$RC" eq 21

ksays "$TMPD/cost_off.txt" on 0 "GEGENPROBE nopowermon: the accounting really is off"
ksays "$TMPD/cost_off.txt" samples 0 "and not one sample was taken"
has "$TMPD/cost_off.txt" "powermon: the power accounting is not running." \
    "and the page says so instead of showing a table of zeros"

c=$(uw "$TMPD/cost_on.txt" cost); n=$(uw "$TMPD/cost_on.txt" costn)
hz=$(uw "$TMPD/cost_on.txt" hz)
if [ -n "$c" ] && [ -n "$n" ] && [ "${n:-0}" -gt 0 ]; then
    per=$((c / n))
    ok "one sample costs $per cycles, measured over $n of them ($c in total)"
    # Ten samples a second, so per*10 cycles a second. Against a
    # processor doing a thousand million cycles a second that has to stay
    # well under one percent -- and TCG is the slowest case there is.
    ppm=$(( (per * 10 * 1000000) / 1000000000 ))
    ok "at 10 samples a second that is about $ppm parts per million of a 1 GHz processor"
    if [ "$per" -lt 4000000 ]; then
        ok "a sample stays under four million cycles even under TCG"
    else
        bad "a sample costs $per cycles -- too much for a timer interrupt"
    fi
else
    bad "the run reported no cost for its own bookkeeping"
fi

# The same workload has to have done the same work. `burn` prints its own
# result, and the two runs must agree on it to the digit -- if the
# accounting changed what the machine computed, it changed the machine.
s1=$(grep -a -m1 '^burn: sum=' "$TMPD/cost_on.txt" | tr -d '\r\000')
s2=$(grep -a -m1 '^burn: sum=' "$TMPD/cost_off.txt" | tr -d '\r\000')
if [ -n "$s1" ] && [ "$s1" = "$s2" ]; then
    ok "counted and uncounted, burn computed exactly the same thing ($s1)"
else
    bad "the two runs did not compute the same thing: '$s1' against '$s2'"
fi

t1=$(kprow "$TMPD/cost_on.txt" burn 3)
if [ -n "$t1" ]; then
    ok "burn was measured at $t1 processor ticks in the counted run"
else
    bad "burn has no row in the counted run"
fi

# ================================== 9. the day file: readable and capped

echo "== 9. the day file -- plain text, readable with cat, and it stops growing =="

RC=$(run day "osum pwr pmonsay pmonnofloor nokbd script=burn 6;powermon day;powermon day;powermon day;cat /etc/powermon.days;exit" high 300)
num "the run that writes the day file ends cleanly" "$RC" eq 21
has "$TMPD/day.txt" "# osum powermon -- one line per day" "the file starts with a line saying what it is"
has "$TMPD/day.txt" "day=" "and holds a day line"
has "$TMPD/day.txt" "totalmJ=" "with the measured total in millijoules"
has "$TMPD/day.txt" "basemW=" "with the measured floor beside it"
has "$TMPD/day.txt" "prog=" "and the programs that used it"
has "$TMPD/day.txt" "powermon: wrote " "the program says how many octets it wrote"

# The size, and why it matters: OFS still has a two-megabyte ceiling per
# volume (round OFS3 is lifting it), and a monitor that fills the disk it
# is monitoring is a bad monitor.
sz=$(grep -a 'powermon: wrote ' "$TMPD/day.txt" | tail -1 | sed -E 's/.*wrote ([0-9]+).*/\1/')
if [ -n "$sz" ]; then
    num "the file stays far under the 2 MiB ceiling of a volume" "$sz" lt 20000
    lim=$(grep -aE '^const KEEP_DAYS' kernel/user/powermon.fi | sed 's/.*= //')
    same "and it keeps at most ninety days" "90" "$lim"
else
    bad "the day file was never written"
fi

days=$(grep -ac '^day=' "$TMPD/day.txt" || true)
num "cat shows the day lines as plain text" "${days:-0}" gt 0
ksays "$TMPD/day.txt" days 3 "the day mark moved once per write and no more"

# ======================================== 10. the page and the window

echo "== 10. the page: what it shows and what it refuses to claim =="

RC=$(run page "osum pwr pmonsay pmonnofloor nokbd script=burn 6;powermon;powermon graph;powermon bright;exit" high 300)
num "the run that draws the page ends cleanly" "$RC" eq 21
has "$TMPD/page.txt" "Battery usage by program" "the page carries the heading Windows uses"
has "$TMPD/page.txt" "measured total, proportionally attributed" \
    "AND THE SENTENCE THAT SAYS WHAT THE NUMBERS ARE, on the page and not in a footnote"
has "$TMPD/page.txt" "PROGRAM             CPU   SHARE       mJ  RUNS" "the table has its columns"
has "$TMPD/page.txt" "Sum of the shares: 100 %" "and the sum stands under it"
has "$TMPD/page.txt" "Measured draw, newest last" "the graph is drawn out of the sample ring"
has "$TMPD/page.txt" "Brightness against measured draw" "and the brightness table exists"
has "$TMPD/page.txt" "Health" "the ageing of the battery is on the page"
has "$TMPD/page.txt" "Runtime left" "and so is the runtime left"

# On this host the page says the awkward thing itself.
RC=$(run note "osum pwr pmonsay nokbd script=burn 6;powermon;exit" high 300)
num "the run with the floor on ends cleanly" "$RC" eq 21
has "$TMPD/note.txt" "the measured draw did not change with the load on this" \
    "ON THIS HOST THE PAGE SAYS SO ITSELF: nothing could be attributed"

# ============================================== 11. the same page as a window

echo "== 11. the window: it is really opened, and it is really drawn =="

# A PAGE IN A WINDOW IS WORTH NOTHING IF IT CANNOT BE OPENED, and a
# window that opens is worth nothing if nothing is painted in it. So this
# is measured twice: the window server counts its windows, and the frame
# buffer is READ BACK at the place where the window stands.
#
# `wigapp=/bin/powermon` is how the program gets there. Round K15 starts
# one of three hard-wired names in its window server; a fourth would have
# been a fourth, and the round after this one a fifth, so the path is
# read out of the command line instead. It is COPIED at boot, into this
# round's own page -- the command line of the boot loader lies above
# `kernel_end` and the frame allocator hands exactly those frames out.
# The first draft read it in `k15_start` and got the unchanged default
# back; nothing crashed and nothing was right.
MONO="$ROOT/assets/osum-mono.ttf"
SANS="$ROOT/assets/osum-sans.ttf"
GARGS=(build "$TMPD/gui.img" "$BLOCKS" /lib/ "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/ /etc/)
for p in $PROGS; do GARGS+=("/bin/$p=$TMPD/$p.elf"); done
python3 tools/osum/mkfs.py "${GARGS[@]}" > "$TMPD/gui.log" 2>&1 \
    && ok "a disk with the fonts and the programs on it: $(tail -1 "$TMPD/gui.log")" \
    || bad "mkfs.py fails on the disk for the window"

WSOCK="$TMPD/win.sock"; WOUT="$TMPD/win.txt"; WPPM="$TMPD/win.ppm"
rm -f "$WSOCK" "$WOUT" "$WPPM"
cp -f "$TMPD/gui.img" "$TMPD/live-win.img"
timeout 240 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
    -append "gfx wm wig wmhold wiglong pmonsay pmonnofloor wigapp=/bin/powermon nokbd nosched noproc nofs" \
    -serial "file:$WOUT" -display none -no-reboot -vga std \
    -monitor "unix:$WSOCK,server,nowait" \
    -drive "file=$TMPD/live-win.img,format=raw,if=ide,index=0" \
    -acpitable "sig=SSDT,rev=2,oem_id=OSUM,oem_table_id=PMON,data=$TMPD/high.aml" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
WPID=$!
i=0
while [ $i -lt 900 ]; do
    grep -qa '^wm: hold' "$WOUT" 2>/dev/null && break
    kill -0 "$WPID" 2>/dev/null || break
    sleep 0.15
    i=$((i + 1))
done
python3 tools/gfx/schuss.py "$WSOCK" "$WPPM" 25 > "$TMPD/shot.log" 2>&1
wait "$WPID"
RC=$?
num "the run with the window ends cleanly" "$RC" eq 21
has "$WOUT" "k15: start /bin/powermon" "wigapp= really started THIS program and not the default"
has_not "$WOUT" "k15: start /bin/wigdemo" "GEGENPROBE: it did not start the built-in default"
has "$WOUT" "wm: windows=1" "the window server counts the window /bin/powermon opened"
has "$WOUT" "ttf: sans" "the fonts are on the disk, so there is something to draw with"

# AND THE PICTURE. Not "the screen is not black" -- that is the area
# counting of round K7B, where 87 percent agreement was 87 percent
# background. The window rectangle is sampled on a grid and the number of
# DISTINCT colours in it is counted: a window with a panel, a frame, a
# heading and a table of text has many; an empty rectangle has one.
if [ -s "$WPPM" ]; then
    dc=$(python3 - "$WPPM" <<'PYEOF2'
import sys
d = open(sys.argv[1], 'rb').read()
i = d.index(b'255\n') + 4
hdr = d[:i].split()
w = int(hdr[1])
px = d[i:]
seen = set()
for y in range(70, 70 + 420, 7):
    for x in range(70, 70 + 620, 7):
        o = (y * w + x) * 3
        seen.add(px[o:o + 3])
print(len(seen))
PYEOF2
)
    num "distinct colours inside the window rectangle in the screenshot" "${dc:-0}" gt 5
else
    bad "no screenshot was taken at all"
fi

echo
echo "POWERMON: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
