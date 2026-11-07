#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/qemu.sh

LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
TMPD=$(mktemp -d)
trap '[ -n "${S3RTC_KEEP:-}" ] && { rm -rf "$S3RTC_KEEP"; mkdir -p "$S3RTC_KEEP"; cp "$TMPD"/l-*.txt "$S3RTC_KEEP"/ 2>/dev/null; }; rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasline() { tr -d '\r' < "$1" | grep -qax "$2" && ok "$3" || bad "$3 -- line '$2' missing"; }
hasnotline() { tr -d '\r' < "$1" | grep -qax "$2" && bad "$3 -- line '$2' present" || ok "$3"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
num() { local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, expected $op $want"; fi
}
for w in qemu-system-x86_64 sgdisk mkfs.vfat mcopy socat; do
    command -v "$w" >/dev/null 2>&1 || { echo "S3RTC: skipped, $w missing"; exit 0; }
done
[ -x "$LIMINE/limine" ] || { echo "S3RTC: skipped, Limine missing"; exit 0; }

WAKE_SECS=4
RTC_STATUS_BIT=1024
IDLE_WAIT_S=25

field() { tr -d '\r' < "$1" | grep -a "^$2 " | sed -n "$3p" | awk '{print $2}'; }
hexval() { local v=${1#0x}; [ -n "$v" ] && echo $((16#$v)); }

mkdisk() { # img cmdline
    local img=$1 cmd=$2 t="$TMPD/esp.img"
    printf 'timeout: 0\ndefault_entry: 1\n/s3\n    protocol: multiboot1\n    path: boot():/osum.mb\n    module_path: boot():/quelle.img\n    cmdline: osum vfs modfs modcrc=%s nokbd nosched noproc nofs noring3 script=%s\n' "$CRC" "$cmd" > "$TMPD/limine.conf"
    rm -f "$img" "$t"
    dd if=/dev/zero of="$img" bs=1M count=0 seek=64 status=none
    sgdisk --clear --new=1:2048:+56M --typecode=1:EF00 "$img" >/dev/null 2>&1 || return 1
    dd if=/dev/zero of="$t" bs=1M count=56 status=none
    mkfs.vfat -F 32 "$t" >/dev/null 2>&1 || return 1
    mcopy -i "$t" "$LIMINE/limine-bios.sys" ::/limine-bios.sys || return 1
    mcopy -i "$t" "$TMPD/limine.conf" ::/limine.conf || return 1
    mcopy -i "$t" "$INST/k.mb" ::/osum.mb || return 1
    mcopy -i "$t" "$INST/quelle.img" ::/quelle.img || return 1
    dd if="$t" of="$img" bs=512 seek=2048 conv=notrunc status=none
    rm -f "$t"
    "$LIMINE/limine" bios-install "$img" >/dev/null 2>&1
}

# run name img wait_mode(done|idle)
run() {
    local name=$1 img=$2 mode=$3 sock="$TMPD/mon.$1" L="$TMPD/l-$1.txt" i
    rm -f "$L"
    timeout 200 $QEMU_X86 -m 512 -drive "file=$img,format=raw,if=ide,index=0" \
        -drive "file=$INST/ziel.img,format=raw,if=ide,index=1" \
        -serial "file:$L" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    if [ "$mode" = idle ]; then
        for i in $(seq 1 450); do
            grep -qa 's3: sleep cycle' "$L" 2>/dev/null && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        sleep "$IDLE_WAIT_S"
        STATE=$(echo 'info status' | socat - "UNIX-CONNECT:$sock" 2>/dev/null | tr -d '\r' | grep -ao 'VM status: .*' | head -1)
        echo quit | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
    fi
    wait "$pid"; RC=$?
}

echo "== 1. build image with /bin/standby and /bin/cat =="
INST="$TMPD/inst"
mkdir -p "$INST"
if OUT="$INST" PROGS="sh echo sync standby cat" APPS="" bash tools/install/build.sh "$INST" > "$TMPD/inst.txt" 2>&1; then
    ok "root image built"
else
    bad "root image build"; tail -8 "$TMPD/inst.txt" | sed 's/^/        /'
    echo "S3RTC: $pass passed, $fail failed"; exit 1
fi
CRC=$(cat "$INST/quelle.crc")

echo "== 2. standby --rtc $WAKE_SECS: wakes by itself, no monitor wake =="
mkdisk "$TMPD/a.img" "cat /proc/s3;standby --rtc $WAKE_SECS;cat /proc/s3;echo after-rtc;exit" && ok "disk image" || bad "disk image"
run rtc "$TMPD/a.img" done
L="$TMPD/l-rtc.txt"
has "$L" "standby: rtc wake in sec=$WAKE_SECS" "the program announces the alarm"
has "$L" "s3: sleep cycle=" "the kernel went to sleep"
has "$L" "s3: wake cycle=" "the kernel woke up without a monitor wake"
has "$L" "standby: zurueck, rc=0" "the system call returns 0"
hasline "$L" "after-rtc" "the shell runs the next command"
num "return code of the machine (isa-debug-exit)" "$RC" eq 21
num "/proc/s3 dumps" "$(grep -ac '^version 1' "$L")" eq 2
num "s3 capable (first dump)" "$(field "$L" s3 1)" eq 1
num "cycles before" "$(field "$L" cycles 1)" eq 0
num "cycles after" "$(field "$L" cycles 2)" eq 1
num "result code (1 = back from S3)" "$(field "$L" result 2)" eq 1
num "rtc_secs recorded" "$(field "$L" rtc_secs 2)" eq "$WAKE_SECS"
num "rtc armed" "$(field "$L" rtc_armed 2)" eq 1
ws=$(hexval "$(field "$L" wake_sts 2)")
num "PM1 status carries the RTC wake bit" "$(( ${ws:-0} & RTC_STATUS_BIT ))" eq "$RTC_STATUS_BIT"
num "clock caught up (slept_s)" "$(field "$L" slept_s 2)" ge $((WAKE_SECS - 1))
num "cores online after = before" "$(field "$L" cores_after 2)" eq "$(field "$L" cores_before 2)"

echo "== 3. counter-proof: standby without --rtc stays asleep =="
mkdisk "$TMPD/b.img" "standby;cat /proc/s3;echo after-rtc;exit" && ok "disk image" || bad "disk image"
run plain "$TMPD/b.img" idle
L="$TMPD/l-plain.txt"
has "$L" "s3: sleep cycle=" "the kernel went to sleep"
case $STATE in *suspended*) ok "still suspended after ${IDLE_WAIT_S} s ($STATE)";; *) bad "state: '$STATE'";; esac
hasnot "$L" "s3: wake cycle=" "no wake without the alarm"
hasnotline "$L" "after-rtc" "the shell did not continue"

echo "== 4. bad argument: refused, no sleep =="
mkdisk "$TMPD/c.img" "standby --rtc 0;echo after-rtc;exit" && ok "disk image" || bad "disk image"
run bad "$TMPD/c.img" done
L="$TMPD/l-bad.txt"
has "$L" "standby: --rtc needs 1..3600 sec" "usage message"
hasnot "$L" "s3: sleep cycle=" "no sleep"
hasline "$L" "after-rtc" "the shell continues"

echo
echo "S3RTC: $pass passed, $fail failed"
[ "$fail" = 0 ]
