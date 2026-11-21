#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
WD=${1:?prepared firefox workdir}
OUT=${2:?output dir}
ROUNDS=${XL_ROUNDS:-10}
UP_SECONDS=${XL_UP:-25}
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

SRC=$OUT/src
mkdir -p "$SRC"
cp -r kernel/user/. "$SRC/"; cp tools/xfx/xfxt.fi "$SRC/"
as --64 -o "$OUT/crt.o" kernel/user/crt.s
"$FIRNC" "$SRC/xfxt.fi" -o "$OUT/xfxt.o" > "$OUT/xfxt.build" 2>&1 \
    && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$OUT/xfxt.elf" "$OUT/crt.o" "$OUT/xfxt.o" \
    && strip --strip-all "$OUT/xfxt.elf" || { echo "XFXLOOP: xfxt build failed"; exit 1; }

if [ -n "${XL_PRESSURE:-}" ]; then
    musl-gcc -O1 -static -o "$OUT/shmpress" tools/xfxloop/shmpress.c || { echo "XFXLOOP: shmpress build failed"; exit 1; }
fi

printf 'root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/home/justin:/bin/sh\n' > "$OUT/passwd"
printf 'root:x:0:\njustin:x:1000:\n' > "$OUT/group"
head -c 128 /dev/zero | tr '\0' 'x' > "$OUT/installed"
cp "${XL_USERJS:-assets/xfx/user.js}" "$OUT/user.js"
grep -v -E '^/etc/(passwd|group|shadow)=' "$WD/fxrun/spec.txt" > "$OUT/spec.in"
cp "$OUT/spec.in" "$OUT/spec.base"

{
    echo "echo XLBEGIN"
    echo "/bin/xfxt sess 1000"
    [ -n "${XL_PRESSURE:-}" ] && echo "/bin/shmpress $XL_PRESSURE"
    echo "grep -a -E 'FramesFreeLow|ShmFail' /proc/meminfo"
    echo "grep -a ShmObjects: /proc/meminfo"
    r=1
    while [ "$r" -le "$ROUNDS" ]; do
        echo "echo XLROUND $r"
        echo "/bin/xfx start"
        echo "grep -a wayd /var/log/xfx.log"
        echo "sleep $UP_SECONDS"
        echo "echo XLUP $r"
        echo "cat /proc/loadavg"
        echo "/bin/xfx status"
        echo "grep -a ShmObjects: /proc/meminfo"
        echo "grep -a -E 'FramesFreeLow|ShmFail' /proc/meminfo"
        echo "/bin/xfxt procs"
        echo "echo XLCHUNK"
        echo "grep -a -c failed.to.allocate /var/log/xfx.log"
        [ -n "${XL_DIAG:-}" ] && echo "grep -a -v ShmSegmentsWriter /var/log/xfx.log"
        [ -n "${XL_DIAG:-}" ] && echo "echo XLLOGEND"
        [ -n "${XL_DIAG:-}" ] && echo "grep -a ShmSegmentsWriter /var/log/xfx.log"
        [ -n "${XL_DIAG:-}" ] && echo "echo XLSHMEND"
        echo "/bin/xfx stop"
        echo "sleep 1"
        echo "echo XLT1"
        echo "grep -a ShmObjects: /proc/meminfo"
        echo "sleep 2"
        echo "echo XLT3"
        echo "grep -a ShmObjects: /proc/meminfo"
        echo "sleep 40"
        echo "echo XLDOWN $r"
        [ -n "${XL_DIAG:-}" ] && echo "grep -a -v ShmSegmentsWriter /var/log/xfx.log"
        [ -n "${XL_DIAG:-}" ] && echo "echo XLLOGEND"
        echo "/bin/xfx status"
        echo "grep -a ShmObjects: /proc/meminfo"
        echo "/bin/xfxt procs"
        r=$((r + 1))
    done
    echo "echo XLEND"
    echo "echo FX-END"
} > "$OUT/guest.sh"

EXTRA_SPEC="/bin/xfxt=$OUT/xfxt.elf@755 ${XL_PRESSURE:+/bin/shmpress=$OUT/shmpress@755} /usr/share/xfx/@755 /usr/share/xfx/installed=$OUT/installed@644 /usr/share/xfx/user.js=$OUT/user.js@644 /etc/passwd=$OUT/passwd@644 /etc/group=$OUT/group@644 /home/@755:0:0 /home/justin/@700:1000:1000 /run/@755 /var/log/@755 /tmp/@1777"
grep -v -E '^(/usr/share/xfx/|/home/|/run/|/var/log/|/tmp/)' "$OUT/spec.base" > "$OUT/spec.in"
SPEC=$OUT/spec.in GUI=1 GUI_EXTRA="xfx" DONE=FX-END BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-1500} MEM=${MEM:-4096} SMP=${SMP:-4} \
    EXTRA="$EXTRA_SPEC" \
    KARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace smpfrueh script=sh /etc/fx.sh;exit" \
    bash tools/linuxapps/run.sh "$WD" "$OUT/guest.sh" "$OUT/run" > "$OUT/run.log" 2>&1

S=$OUT/run/ser.clean
[ -s "$S" ] || { echo "XFXLOOP: no serial output"; tail -5 "$OUT/run.log"; exit 1; }
base=$(awk '/ShmObjects:/{print $2; exit}' "$S")
echo "base ShmObjects: $base"
r=1
while [ "$r" -le "$ROUNDS" ]; do
    started=$(awk -v r="$r" '$1=="XLROUND"&&$2==r{f=1;next} f&&/^xfx:/{print; exit}' "$S")
    case "$started" in "xfx: started uid=1000") ok "round $r: xfx start succeeded" ;; *) bad "round $r: xfx start said '$started'" ;; esac
    up_fx=$(awk -v r="$r" '$1=="XLUP"&&$2==r{f=1;next} f&&/^xfxt: proc firefox/{n++} f&&/^XLDOWN/{exit} END{print n+0}' "$S")
    [ "${up_fx:-0}" -ge 1 ] && ok "round $r: firefox alive after ${UP_SECONDS}s ($up_fx tasks)" || bad "round $r: firefox not alive after ${UP_SECONDS}s"
    chunk=$(awk -v r="$r" '$1=="XLUP"&&$2==r{f=1;next} f&&$1=="XLCHUNK"{g=1;next} g&&/^[0-9]+$/{print; exit}' "$S")
    [ "${chunk:-1}" = 0 ] && ok "round $r: no chunk allocation failure logged" || bad "round $r: chunk allocation failures logged: ${chunk:-?}"
    tasks_up=$(awk -v r="$r" '$1=="XLUP"&&$2==r{f=1;next} f&&/^[0-9.]+ [0-9.]+ [0-9.]+ [0-9]+\/[0-9]+/{split($4,a,"/"); print a[2]; exit}' "$S")
    echo "  INFO  round $r: ${tasks_up:-?} live tasks"
    shm_down=$(awk -v r="$r" '$1=="XLDOWN"&&$2==r{f=1;next} f&&/ShmObjects:/{print $2; exit}' "$S")
    procs_down=$(awk -v r="$r" '$1=="XLDOWN"&&$2==r{f=1;next} f&&/^xfxt: proc /{if($3=="firefox"||$3=="wayd")n++} f&&/^(XLROUND|XLEND)/{exit} END{print n+0}' "$S")
    [ "${procs_down:-1}" = 0 ] && ok "round $r: no firefox/wayd process after stop" || bad "round $r: $procs_down firefox/wayd processes left after stop"
    [ -n "$shm_down" ] && [ "$shm_down" -le $((base + 2)) ] && ok "round $r: ShmObjects $shm_down back to base $base" || bad "round $r: ShmObjects $shm_down after stop (base $base)"
    r=$((r + 1))
done
echo "XFXLOOP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
