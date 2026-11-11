#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dialog/run.sh -- unified dialog API (kernel/user/dialog.fi, consent.fi, /bin/msgbox) in a real guest, German scale 1 and English scale 2.
#   bash tools/dialog/run.sh [workdir]
# Cases: message, confirm (default = no, y = yes), warning/error/critical severities, consent (system.elevate/store.install text),
# a wrong key keeps the dialog open, nothing answers by itself. Screenshots land in <workdir>/<cfg>-<case>.png (look at them).
# Counter-proofs: two identical dialogs give identical pixels (the pixel method is stable) while info vs error vs critical differ;
# msgbox without a key press must report no answer.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
TMPD=${1:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${1:-}" "$TMPD"
mkdir -p "$TMPD/bin"
PROGS="sh echo sleep msgbox"
echo "== 1. build =="
. tools/lib/firnenv.sh
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 && ok "programs build" \
    || { bad "programs do not build"; tail -8 "$TMPD/b.txt"; echo "DIALOG: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 && ok "kernel builds" \
    || { bad "kernel does not build"; tail -5 "$TMPD/k.txt"; echo "DIALOG: $pass passed, $fail failed"; exit 1; }

cat > "$TMPD/g.sh" <<'EOS'
sleep 3
echo ==M1==
msgbox "Titel eins" "Dies ist eine Beschreibung mit mehreren Woertern, die lang genug ist um umgebrochen zu werden."
echo ==M2==
msgbox -c "Frage" "Wirklich loeschen?"
echo ==M3==
msgbox -c "Frage" "Wirklich loeschen?"
echo ==M4==
msgbox -l warning "Achtung" "Akku fast leer."
echo ==M5==
msgbox -l error "Fehler" "Datei nicht gefunden."
echo ==M6==
msgbox -l critical "Kritisch" "Datenverlust moeglich."
echo ==M7==
msgbox --consent helper store.install name=foo
echo ==M8==
msgbox -c "Frage" "Bleibt offen"
echo ==M9==
msgbox -l error "Fehler" "Datei nicht gefunden."
echo ==FERTIG==
EOS

run_cfg() {
    local tag=$1 lang=$2 scale=$3 W="$TMPD/$1"
    mkdir -p "$W"
    printf 'lang=%s\n' "$lang" > "$W/locale.conf"
    printf 'root:x:0:0:root:/:/bin/sh\n' > "$W/passwd"
    local A=(build "$W/disk.img" 16384 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /var/ /var/log/ /proc/ /etc/ "/etc/passwd=$W/passwd" "/etc/locale.conf=$W/locale.conf"
        /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ /usr/share/locale/en/
        "/usr/share/locale/de/messages=locale/de/messages" "/usr/share/locale/en/messages=locale/en/messages"
        "/t/g.sh=$TMPD/g.sh")
    [ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
    [ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
    A+=(/etc/schemas/)
    for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
    for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$W/mkfs.txt" 2>&1 && ok "[$tag] disk built" || { bad "[$tag] mkfs"; return; }
    local SOCK="$W/mon.sock" ACC=()
    [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
    timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 512 \
        -append "gfx disp wm wmdauer wmshell osum vfs bus uiscale=$scale script=sh /t/g.sh;exit" \
        -serial "file:$W/ser.txt" -display none -no-reboot -vga std -monitor "unix:$SOCK,server,nowait" \
        -drive "file=$W/disk.img,format=raw,if=ide,index=0" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$W/qemu.txt" 2>&1 &
    local QPID=$!
    nup()  { local c; c=$(grep -ac 'wm: trusted dialog up no=' "$W/ser.txt" 2>/dev/null); echo "${c:-0}"; }
    nans() { local c; c=$(grep -ac 'msgbox: answer=' "$W/ser.txt" 2>/dev/null); echo "${c:-0}"; }
    waitn() { local i=0; while [ $i -lt $(( $1 * 5 )) ]; do [ "$($2)" -ge "$3" ] && return 0
            kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.2; i=$((i + 1)); done; return 1; }
    shot() { python3 tools/gfx/screenshot.py "$SOCK" "$W/$1.ppm" 5 > /dev/null 2>&1; }
    key() { echo "sendkey $1" > "$W/kk.txt"; python3 tools/wm/monitor.py "$SOCK" "$W/kk.txt" > /dev/null 2>&1; sleep 0.7; }
    local n=0
    case_step() { # name key expect-answer-line
        n=$((n+1))
        if waitn 90 nup $n; then
            sleep 1.5; shot "$1"
            local a0; a0=$(nans)
            if [ -n "$2" ]; then key "$2"; fi
            if [ -n "$3" ]; then
                waitn 20 nans $((a0+1)) && ok "[$tag] $1: dialog answered" || bad "[$tag] $1: no answer after key $2"
            fi
        else bad "[$tag] $1: dialog did not come up"; fi
    }
    case_step m1-message "" ""
    sleep 3
    [ "$(nans)" = 0 ] && ok "[$tag] message waits for a person (no answer without a key)" || bad "[$tag] answered without a key"
    key ret; waitn 20 nans 1 && ok "[$tag] message closed by Enter" || bad "[$tag] message not closed by Enter"
    case_step m2-confirm-default ret y
    case_step m3-confirm-yes y y
    case_step m4-warning n y
    case_step m5-error n y
    case_step m6-critical n y
    case_step m7-consent n y
    n=$((n+1))
    if waitn 90 nup $n; then
        sleep 1.5; shot m8-wrongkey
        local a0; a0=$(nans); key x; sleep 2
        [ "$(nans)" = "$a0" ] && ok "[$tag] a wrong key keeps the dialog open" || bad "[$tag] wrong key answered the dialog"
        key n; waitn 20 nans $((a0+1)) && ok "[$tag] closed afterwards by N" || bad "[$tag] N did not close"
    else bad "[$tag] m8 did not come up"; fi
    case_step m9-error-again n y
    local i=0; while [ $i -lt 100 ]; do grep -qaF "==FERTIG==" "$W/ser.txt" 2>/dev/null && break; sleep 0.5; i=$((i+1)); done
    printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
    wait "$QPID" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$W/ser.txt" > "$W/ser.klar"
    for q in "$W"/*.ppm; do [ -s "$q" ] && python3 -c "from PIL import Image; Image.open('$q').save('${q%.ppm}.png')" 2>/dev/null; done
    local G="$W/ser.klar"
    [ "$(grep -ac 'msgbox: answer=y' "$G")" -ge 6 ] && ok "[$tag] yes/ack lines: $(grep -ac 'msgbox: answer=y' "$G")" || bad "[$tag] too few 'answer=y' lines"
    [ "$(grep -ac 'msgbox: answer=n' "$G")" -ge 2 ] && ok "[$tag] no lines: $(grep -ac 'msgbox: answer=n' "$G")" || bad "[$tag] too few 'answer=n' lines"
    grep -qaF "==FERTIG==" "$G" && ok "[$tag] script ran to the end" || bad "[$tag] script did not finish"
    python3 tools/dialog/pixels.py "$W" "$scale" > "$W/pix.txt" 2>&1; cat "$W/pix.txt" | sed 's/^/        /'
    grep -q '^PIXELS-OK' "$W/pix.txt" && ok "[$tag] pixels: dialogs drawn, severities differ, identical dialogs identical" || bad "[$tag] pixel checks"
    local NL; NL=$(grep -ac 'wm: trusted dialog layout' "$G")
    local NW; NW=$(grep -a 'wm: trusted dialog layout' "$G" | grep -ac " w=$((512 * scale)) title=")
    [ "$NL" -ge 9 ] && [ "$NW" = "$NL" ] && ok "[$tag] all $NL dialogs are $((512 * scale)) px wide (scale $scale)" || bad "[$tag] dialog width wrong: $NW of $NL are $((512 * scale)) px"
    local NT; NT=$(grep -a 'wm: trusted dialog layout' "$G" | grep -acE " title=[A-Za-z0-9]+ - ")
    [ "$NT" = "$NL" ] && ok "[$tag] every title line starts with the product name" || bad "[$tag] title without product name: $NT of $NL"
    for f in m1-message m2-confirm-default m3-confirm-yes m4-warning m5-error m6-critical m7-consent m8-wrongkey m9-error-again; do
        [ -s "$W/$f.png" ] && ok "[$tag] photo $W/$f.png" || bad "[$tag] no photo $f"; done
}
echo "== 2. german, scale 1 =="; run_cfg de1 de 1
echo "== 3. english, scale 2 =="; run_cfg en2 en 2
echo "DIALOG: $pass passed, $fail failed"
[ "$fail" = 0 ]
