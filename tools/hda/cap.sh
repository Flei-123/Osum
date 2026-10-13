#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hda/cap.sh -- MICROPHONE GATE (W-TRAY6 follow-up, 13.10.2026).
#
# QEMU: `-device intel-hda -device hda-micro` with `-audiodev none` (no sound needed, the codec still
# runs the input DMA). The kernel word `audcap` runs kernel/drv/snd/captest.fi and prints `aud: <name>=<n>`.
#
# CLAIMS (and how each is measured):
#   (a) DMA really writes   the ring is 0x5A-filled before the start (pre5a = all words, proves the checker
#                           sees 0x5A) and holds NO 0x5A word after the capture (post5a = 0); reader 1 never
#                           receives a 0x5A frame while draining (a_5a = 0)
#   (b) position monotonic  back = 0 and the frame counter advances (rate is printed, NOT asserted tightly:
#                           QEMU's `none` backend does not pace the input at 48 kHz, measured 56k..113k)
#   (c) mute = silence      stream stopped, ring = pattern 0x11112222: an unmuted reader gets the pattern
#                           (b_pat = b_n); a muted reader gets zeros in a buffer pre-filled with junk
#                           (c_zero = c_n, c_pat = 0, c_junk = 0); unmuted again -> pattern (d_pat = d_n)
#   (d) fifth reader refused   fifth = 1 while four readers are live (users = 4); who0/who3 name the live readers
#                           (what AUDGET A_CAPWHO0..3 hands to the tray)
#   (e) idle stop           after 2.2 s without a read the stream is stopped (idle_run = 0, idle_users = 0)
#   (f) overruns            only printed (reader 1 may fall behind in the emulator), not claimed
#
# COUNTER-SAMPLES (each must say "no microphone", never fake data):
#   nodev     no sound card at all        -> no capture lines, kernel ends normally (rc 21)
#   outonly   hda-output (no input codec)  -> ready=0, why=3 (no ADC)
#   nohda     HDA skipped (AC97 only)      -> ready=0, why=1 (no HDA)
#
# Usage: bash tools/hda/cap.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name value op expected
    local name=$1 v=$2 op=$3 want=$4
    if [ -z "$v" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$v" -"$op" "$want" ] 2>/dev/null; then ok "$name: $v"
    else bad "$name: $v, expected $op $want"; fi
}
same() { if [ "$2" = "$3" ]; then ok "$1: $3"; else bad "$1: $3, expected $2"; fi; }
has()    { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' should not be there" || ok "$3"; }
val() { grep -oaE "aud: $2=[0-9]+" "$1" | tail -1 | grep -oE '[0-9]+$'; }

echo "== 0. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/build.txt" 2>&1 \
    && ok "kernel builds ($(stat -c%s "$TMPD/k.mb") octets)" \
    || { bad "kernel does not build"; sed 's/^/        /' "$TMPD/build.txt" | tail -20; \
         echo "CAP: $pass passed, $fail failed"; exit 1; }

AUD="-audiodev none,id=snd0"
run() { # name  cmdline  devices  [timeout]
    local n=$1 cmd=$2 dev=$3 t=${4:-90}
    timeout "$t" $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -append "$cmd" \
        -serial "file:$TMPD/$n.txt" -display none -no-reboot $AUD $dev \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $?
}
MIC="-device intel-hda -device hda-micro,audiodev=snd0"

echo "== 1. microphone: path, DMA, position =="
rc=$(run cap "osum nokbd nosched noproc nofs audio audcap" "$MIC")
same "the kernel ends itself (21)" 21 "$rc"
has "$TMPD/cap.txt" "hda: capture path" "the input path was found (log line)"
num "ready" "$(val "$TMPD/cap.txt" ready)" eq 1
num "why (0 = ok)" "$(val "$TMPD/cap.txt" why)" eq 0
num "pin kind (10 = mic)" "$(val "$TMPD/cap.txt" kind)" eq 10
rw=$(val "$TMPD/cap.txt" ringwords)
num "ring words" "$rw" eq 4096
num "(a) before the start every ring word is 0x5A (the checker sees it)" "$(val "$TMPD/cap.txt" pre5a)" eq "${rw:-0}"
num "(a) after capture no 0x5A word is left: the DMA wrote" "$(val "$TMPD/cap.txt" post5a)" eq 0
num "(a) the ring holds the DMA's data (zeros from the none backend)" "$(val "$TMPD/cap.txt" postzero)" eq "${rw:-0}"
num "(a) frames reader 1 drained" "$(val "$TMPD/cap.txt" a_total)" ge 20000
num "(a) 0x5A frames reader 1 received" "$(val "$TMPD/cap.txt" a_5a)" eq 0
num "(b) position steps back" "$(val "$TMPD/cap.txt" back)" eq 0
ff=$(val "$TMPD/cap.txt" frames_first); fl=$(val "$TMPD/cap.txt" frames_last)
tf=$(val "$TMPD/cap.txt" t_first); tl=$(val "$TMPD/cap.txt" t_last)
if [ -n "$ff" ] && [ -n "$fl" ] && [ -n "$tf" ] && [ -n "$tl" ] && [ "$tl" -gt "$tf" ]; then
    hz=$(( (fl - ff) * 1000000000 / (tl - tf) ))
    echo "    rate over the last second: $((fl - ff)) frames in $((tl - tf)) ns -> $hz Hz (emulator, information only)"
    num "(b) the counter advances (frames in the last second)" "$((fl - ff))" ge 20000
    num "(b) and not absurdly fast (< 4 x 48000 per second)" "$hz" le 192000
else
    bad "(b) measurement values missing"
fi
num "(d) readers counted while four are live" "$(val "$TMPD/cap.txt" users)" eq 4
num "(d) the first live reader is named (task index)" "$(val "$TMPD/cap.txt" who0)" eq 1
num "(d) the fourth live reader is named (task index)" "$(val "$TMPD/cap.txt" who3)" eq 4
num "(d) the fifth reader is refused (1 = refused)" "$(val "$TMPD/cap.txt" fifth)" eq 1
num "(e) 2.2 s without a read: users" "$(val "$TMPD/cap.txt" idle_users)" eq 0
num "(e) 2.2 s without a read: stream running (0 = stopped)" "$(val "$TMPD/cap.txt" idle_run)" eq 0
echo "    overruns (information): $(val "$TMPD/cap.txt" overruns)"

echo "== 2. mute = silence =="
n=$(val "$TMPD/cap.txt" b_n)
num "unmuted reader: frames" "$n" ge 1024
same "(c) unmuted: every frame is the ring's pattern" "${n:-x}" "$(val "$TMPD/cap.txt" b_pat)"
n=$(val "$TMPD/cap.txt" c_n)
num "muted reader: frames" "$n" ge 1024
same "(c) muted: every frame is zero" "${n:-x}" "$(val "$TMPD/cap.txt" c_zero)"
num "(c) muted: frames with the ring's pattern" "$(val "$TMPD/cap.txt" c_pat)" eq 0
num "(c) muted: junk left in the buffer" "$(val "$TMPD/cap.txt" c_junk)" eq 0
n=$(val "$TMPD/cap.txt" d_n)
num "unmuted again: frames" "$n" ge 1024
same "(c) unmuted again: the pattern is back" "${n:-x}" "$(val "$TMPD/cap.txt" d_pat)"
has "$TMPD/cap.txt" "aud: done=1" "the self test ran to the end"
has "$TMPD/cap.txt" "kernel: done" "the kernel runs on normally"

echo "== 3. COUNTER-SAMPLES: no microphone must say so =="
rc=$(run nodev "osum nokbd nosched noproc nofs audio audcap" "")
same "nodev: the kernel ends normally (21)" 21 "$rc"
hasnot "$TMPD/nodev.txt" "aud: done=1" "nodev: no capture test ran"
has "$TMPD/nodev.txt" "aud: kein Geraet" "nodev: the audio layer says there is no device"
has "$TMPD/nodev.txt" "kernel: done" "nodev: the system runs on"

rc=$(run outonly "osum nokbd nosched noproc nofs audio audcap" "-device intel-hda -device hda-output,audiodev=snd0")
same "outonly: the kernel ends normally (21)" 21 "$rc"
num "outonly: ready" "$(val "$TMPD/outonly.txt" ready)" eq 0
num "outonly: why (3 = no input converter)" "$(val "$TMPD/outonly.txt" why)" eq 3
hasnot "$TMPD/outonly.txt" "aud: done=1" "outonly: no capture test ran"
has "$TMPD/outonly.txt" "kernel: done" "outonly: the system runs on"

rc=$(run nohda "osum nokbd nosched noproc nofs audio nohda audcap" "-device AC97,audiodev=snd0")
same "nohda: the kernel ends normally (21)" 21 "$rc"
num "nohda: ready" "$(val "$TMPD/nohda.txt" ready)" eq 0
num "nohda: why (1 = no HDA)" "$(val "$TMPD/nohda.txt" why)" eq 1
hasnot "$TMPD/nohda.txt" "aud: done=1" "nohda: no capture test ran"
has "$TMPD/nohda.txt" "kernel: done" "nohda: the system runs on"

echo "CAP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
