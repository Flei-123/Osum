#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/srguest/run.sh -- screen reader guest gate (P-016): QEMU with intel-hda + -audiodev wav.
#   bash tools/srguest/run.sh [workdir]
# Boots window server + a11ydemo + /bin/screenreader, moves the focus with sendkey tab, then checks the `sr: say:` lines,
# the password rule (name + protected, canary never spoken) and that the WAV the guest played is not silent.
# Counter-proofs: `serve silent` (same lines, WAV must stay silent) and no sound device (reader says `sr: audio none`).
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }

TMPD=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
PROGS="sh ls cat echo sleep a11ydemo screenreader"

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "programs build ($PROGS)"
else
    bad "programs do not build"; tail -12 "$TMPD/b.txt" | sed 's/^/        /'
    echo "SRGUEST: $pass passed, $fail failed"; exit 1
fi
if bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "kernel builds"
else
    bad "kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "SRGUEST: $pass passed, $fail failed"; exit 1
fi

mkscript() { # name serve-args say-word
    cat > "$TMPD/$1.sh" <<EOS
sleep -m 300
/apps/a11ydemo.prog/start &
sleep 3
screenreader serve 6000 $2 &
sleep 3
echo ==SR-READY==
sleep 25
echo ==SR-TYPED==
$3
sleep 4
echo ==SR-DONE==
sleep 2
echo ==FERTIG==
EOS
}
mkscript loud "" "screenreader say probe"
mkscript mute "silent" "echo no-say"
cp "$TMPD/loud.sh" "$TMPD/nodev.sh"

mkdisk() { # name
    local A=(build "$TMPD/$1.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
       "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/ /etc/ /apps/ /apps/a11ydemo.prog/
       "/apps/a11ydemo.prog/start=$TMPD/bin/a11ydemo.elf" "/t/g.sh=$TMPD/$1.sh")
    [ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
    [ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
    printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
    A+=("/etc/theme.conf=$TMPD/theme.conf" /etc/schemas/)
    for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
    for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1
}

run_guest() { # name audio(1/0)
    local n=$1 withaud=$2
    mkdisk "$n" || { bad "mkfs $n"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; return 1; }
    local SOCK="$TMPD/$n.sock" SER="$TMPD/$n.txt"
    rm -f "$SOCK" "$SER" "$TMPD/$n.wav"
    local DEV=()
    if [ "$withaud" = 1 ]; then
        DEV=(-audiodev "wav,id=snd0,path=$TMPD/$n.wav,out.frequency=48000,out.channels=2,out.format=s16"
             -device intel-hda -device hda-duplex,audiodev=snd0)
    fi
    timeout 300 $QEMU_X86 -kernel "$TMPD/k0.img" -m 768 \
        -append "gfx disp wm wmdauer wmshell osum vfs audio script=sh /t/g.sh;exit" \
        -serial "file:$SER" -display none -no-reboot -vga std \
        -monitor "unix:$SOCK,server,nowait" "${DEV[@]}" \
        -drive "file=$TMPD/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$n.qemu" 2>&1 &
    local QPID=$!
    waitfor() {
        local i=0
        while [ $i -lt $(( $2 * 5 )) ]; do
            grep -qaF -- "$1" "$SER" 2>/dev/null && return 0
            kill -0 "$QPID" 2>/dev/null || return 1
            sleep 0.2; i=$((i + 1))
        done
        return 1
    }
    klick() {
        python3 tools/themestore/click.py "$1,$2" > "$TMPD/c.txt" 2>/dev/null
        python3 tools/wm/monitor.py "$SOCK" "$TMPD/c.txt" > /dev/null 2>&1
        sleep 1.5
    }
    keys() {
        printf '%s\n' "$@" > "$TMPD/keys.txt"
        python3 tools/wm/monitor.py "$SOCK" "$TMPD/keys.txt" 0.3 > /dev/null 2>&1
        sleep 1.2
    }
    if waitfor "==SR-READY==" 150; then
        sleep 2
        klick 200 70
        keys "sendkey tab"
        keys "sendkey tab"
        keys "sendkey tab"
        keys "sendkey tab"
        keys "sendkey tab"
        keys "sendkey tab"
    else
        bad "$n: the script did not reach the reader start"
    fi
    waitfor "==FERTIG==" 120 || note "$n: no FERTIG before the time limit"
    printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
    wait "$QPID" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$SER" > "$TMPD/$n.klar"
    perl -0pi -e 's/wm: fen i=[^\n]*? tka=\d+\r?\n//g' "$TMPD/$n.klar"
}

wavnum() { grep -oE "$2=[0-9.-]+" "$1" | head -1 | cut -d= -f2; }

echo "== 2. loud run: intel-hda + wav =="
run_guest loud 1
G="$TMPD/loud.klar"
grep -qaE 'sr: serving rights=[0-9]+ audio=1' "$G" && ok "reader started with audio on" || bad "reader start line: $(grep -a 'sr: serving' "$G" | head -1)"
n=$(grep -ac '^sr: say: ' "$G")
[ "$n" -ge 3 ] && ok "$n announcements on the serial line" || bad "only $n announcements"
grep -a '^sr: say: ' "$G" | sed 's/^/        /' | head -12
grep -qaE '^sr: say: .*button' "$G" && ok "a button is announced with its role" || bad "no button announcement"
grep -qaE '^sr: say: .*(Save|Add note)' "$G" && ok "button names are spoken" || bad "no button name spoken"
grep -qaE '^sr: say: .*check box' "$G" && ok "the check box is announced with its role" || bad "no check box announcement"
grep -qaE '^sr: say: A11Y' "$G" && ok "the window title is announced when the focus enters the window" || bad "no window title announced"
grep -qaE '^sr: say: .*Password, password field, protected' "$G" && ok "password field: name + protected" || bad "password announcement: $(grep -a 'sr: say: Password' "$G" | head -1)"
n=$(grep -ac 'GEHEIMNIS7\|HEIMNIS' "$TMPD/loud.txt")
[ "$n" = 0 ] && ok "the canary appears NOWHERE on the serial line" || bad "the canary appears $n times"
grep -qaE '^sr: say: probe' "$G" && ok "'screenreader say' speaks free text" || bad "say command not seen"
grep -qaE '^sr: audio frames=[1-9][0-9]* peak=[1-9][0-9]*' "$G" && ok "the synthesizer rendered frames with a non-zero peak" || bad "no rendered frames: $(grep -a 'sr: audio' "$G" | head -2 | tr '\n' ' ')"
grep -qaE 'sr: audio none' "$G" && bad "reader found no sound device" || ok "the reader opened the mixer"
grep -qaE 'panic|EXCEPTION|#PF|#GP' "$G" && bad "a panic or exception" || ok "no panic, no exception"
if [ -s "$TMPD/loud.wav" ]; then
    python3 tools/hda/wavcheck.py "$TMPD/loud.wav" --hz 125 --rate 48000 > "$TMPD/loud.chk" 2>&1
    sed 's/^/        /' "$TMPD/loud.chk"
    nutz=$(( $(wavnum "$TMPD/loud.chk" nutz) - $(wavnum "$TMPD/loud.chk" still) )); rms=$(wavnum "$TMPD/loud.chk" rms); mx=$(wavnum "$TMPD/loud.chk" max)
    [ "${nutz:-0}" -ge 8000 ] 2>/dev/null && ok "the WAV has sound: ${nutz} non-silent frames" || bad "WAV nearly empty: nutz=${nutz:-?}"
    awk -v r="${rms:-0}" 'BEGIN{exit !(r+0>=150)}' && ok "WAV rms $rms is not silent" || bad "WAV rms ${rms:-?} too low"
    [ "${mx:-0}" -lt 32767 ] 2>/dev/null && ok "WAV not clipped (max $mx)" || bad "WAV clipped (max ${mx:-?})"
else
    bad "no WAV written"
fi

echo "== 3. counter-proof: serve silent =="
run_guest mute 1
G2="$TMPD/mute.klar"
n=$(grep -ac '^sr: say: ' "$G2")
[ "$n" -ge 3 ] && ok "silent mode still announces on serial ($n)" || bad "silent mode: only $n announcements"
if [ -s "$TMPD/mute.wav" ]; then
    python3 tools/hda/wavcheck.py "$TMPD/mute.wav" --hz 125 --rate 48000 > "$TMPD/mute.chk" 2>&1
    nutz=$(( $(wavnum "$TMPD/mute.chk" nutz) - $(wavnum "$TMPD/mute.chk" still) ))
    [ "${nutz:-0}" -le 2000 ] 2>/dev/null && ok "silent mode leaves the WAV nearly silent (${nutz:-0} frames of system sound vs. the loud run)" || bad "silent mode produced sound (nutz=${nutz:-?})"
else
    ok "silent mode wrote no sound"
fi

echo "== 4. counter-proof: no sound device =="
run_guest nodev 0
G3="$TMPD/nodev.klar"
has "$G3" "sr: audio none" "without a sound device the reader says so and keeps running"
n=$(grep -ac '^sr: say: ' "$G3")
[ "$n" -ge 3 ] && ok "announcements continue without a device ($n)" || bad "without device only $n announcements"
grep -qaF "==FERTIG==" "$G3" && ok "the script ran to the end" || bad "no FERTIG without device"

rm -f "$TMPD"/*.img "$TMPD"/*.wav
echo "SRGUEST: $pass passed, $fail failed"
[ "$fail" = 0 ]
