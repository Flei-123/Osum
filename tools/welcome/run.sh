#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/welcome/run.sh -- E3: THE WELCOME WINDOW (/bin/welcome), MEASURED.
#
#   /root/jarvis/bin/heavy bash tools/welcome/run.sh
#
# Part A, guest shell (no display): the switch /etc/welcome.conf
#   - no file          -> `welcome status` says show=nein (a missing file means NO)
#   - `welcome show on`  -> the file holds show=ja, status says ja
#   - `welcome show off` -> the file holds show=nein, status says nein
#   - `welcome -a` with show=nein exits silently (rc 0, no window line)
#   - COUNTER-PROBE: `welcome -a` with show=ja TRIES to open the window
#     (no display in this guest -> "welcome: no surface"); so the silent exit above
#     is the switch and not a broken program
#   - bad arguments -> usage, rc 2
# Part B, audit machine with a display: /etc/welcome.conf (show=ja) in the image,
# the desktop starts `/bin/welcome -a` by itself: wizard page 0 (language) with its rects.
# Part C: every page opened by the conf key p= (0 language, 1 Wi-Fi with f=1 fake networks, 2 done) reports its
# page number and its controls; small window sizes keep the navigation inside the window.
# Part D: clicks walk the wizard (next, next, row opens Settings, finish).
# Static: the string keys exist in de + en, the bundle is in the stick list.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
# ---- static
for l in de en; do
    miss=0
    for k in title show sett back next done lang.head lang.note lang.search lang.open net.head net.note net.noadapter net.empty net.open net.secured net.saved net.pw net.connect net.fail net.short net.retry done.head done.note step.upd step.disp; do
        n=$(grep -c "^welcome\.$k = " locale/$l/messages)
        [ "$n" = 1 ] || { miss=$((miss+1)); echo "    key welcome.$k: $n entries in $l"; }
    done
    [ "$miss" = 0 ] && ok "locale $l: 27 wizard keys, each exactly once" || bad "locale $l: $miss wizard keys missing or duplicated"
done
grep -q 'privacy welcome[ "]' tools/usbimg/build.sh && ok "usbimg PROGS has welcome" || bad "usbimg PROGS"
grep -q '/apps/welcome.osp/start' tools/usbimg/build.sh && ok "usbimg PFLICHT has the bundle" || bad "usbimg PFLICHT"
grep -q 'welcome_start()' kernel/user/desktop.fi && ok "desktop starts the welcome window" || bad "desktop hook"
grep -q 'welcome.conf' kernel/user/instaccount.fi && ok "installer writes /etc/welcome.conf" || bad "installer hook"
# ---- part A
mkdir -p "$TMPD/bin"
PROGS="sh cat echo welcome"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "welcome builds"; else bad "build"; head -20 "$TMPD/b.txt"; echo "WELCOME: $pass passed, $fail failed"; exit 1; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "kernel builds"; else bad "kernel"; tail -5 "$TMPD/k.txt"; echo "WELCOME: $pass passed, $fail failed"; exit 1; fi
cat > "$TMPD/s.sh" <<'EOS'
echo ==ST0==
welcome status
echo ==ON==
welcome show on
cat /etc/welcome.conf
welcome status
echo ==OFF==
welcome show off
cat /etc/welcome.conf
welcome status
echo ==AOFF==
welcome -a
echo rc=$?
echo ==AON==
welcome show on
welcome -a
echo ==USE==
welcome frob
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    "/t/s.sh=$TMPD/s.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/o.txt" -display none -no-reboot \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/o.txt" > "$TMPD/o.klar"
for s in "ST0 ON" "ON OFF" "OFF AOFF" "AOFF AON" "AON USE" "USE END"; do set -- $s; part "$TMPD/o.klar" "$1" "$2" > "$TMPD/$1.txt"; done
has "$TMPD/ST0.txt" "welcome: show=nein" "no file -> status nein"
has "$TMPD/ON.txt" "show=ja" "show on: the file holds show=ja"
has "$TMPD/ON.txt" "welcome: show=ja" "show on: status says ja"
has "$TMPD/OFF.txt" "show=nein" "show off: the file holds show=nein"
has "$TMPD/OFF.txt" "welcome: show=nein" "show off: status says nein"
hasnot "$TMPD/AOFF.txt" "welcome: ready" "-a with show=nein opens no window"
hasnot "$TMPD/AOFF.txt" "welcome: no surface" "-a with show=nein does not even try"
has "$TMPD/AOFF.txt" "rc=0" "-a with show=nein exits with 0"
has "$TMPD/AON.txt" "welcome: no surface" "COUNTER-PROBE: -a with show=ja tries to open the window"
has "$TMPD/USE.txt" "usage: welcome" "bad argument: usage text"
# ---- audit machine helper: run_audit <tag> <conf text> <book text> -> $W/<tag>/serial.txt
W=$(mktemp -d); trap 'rm -rf "$TMPD" "$W"' EXIT
run_audit() {
    local V="$W/$1"
    printf "$2" > "$V.conf"
    printf "$3" > "$V.book"
    DESIGNBUILD="$V-build" AUDIT_MKFS_EXTRA="/etc/ /etc/welcome.conf=$V.conf" \
        bash tools/design/audit.sh "$V" accel=kvm uitrace=yes halt=300 \
        progs="desktop taskbar settings launcher explorer edit sh echo ls cat theme welcome" drehbuch="$V.book" > "$V.log" 2>&1
}
rects_of() { grep -a '^welcome: rect ' "$1" | wc -l; }
lay_num() { echo "$1" | sed -n "s/.* $2=\([0-9]*\).*/\1/p"; }
# ---- part B: the desktop starts the wizard by itself (page 0, language)
run_audit auto 'show=ja\n' 'warteauf "welcome: ready" || 240\nwarte 3\nfoto 00-lang\n'
S="$W/auto/serial.txt"
has "$S" "welcome: ready" "audit machine: the desktop started the welcome wizard by itself"
has "$S" "welcome: page 0 of 3" "wizard opens on page 0"
n=$(rects_of "$S")
[ "$n" -ge 4 ] && ok "page 0 reports $n controls (field, chevron, dots, next)" || bad "page 0 controls: $n"
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
# ---- part C: each page opens directly (conf p=) and fits small windows
page_check() { # tag page extra-conf w h expected-min-rects
    run_audit "$1" "show=ja\np=$2\n$3w=$4\nh=$5\n" 'warteauf "welcome: ready" || 240\nwarte 3\nfoto 00\n'
    local SS="$W/$1/serial.txt"
    has "$SS" "welcome: page $2 of 3" "page $2 at $4x$5 opens"
    has "$SS" "welcome: geom x=160 y=120 w=$4 h=$5" "page $2 at $4x$5 has the asked size"
    local r; r=$(rects_of "$SS")
    [ "$r" -ge "$6" ] && ok "page $2 at $4x$5: $r controls (>= $6)" || bad "page $2 at $4x$5: $r controls (< $6)"
    local bottom; bottom=$(grep -a '^welcome: rect ' "$SS" | sed -n 's/.* y=\([0-9]*\) w=[0-9]* h=\([0-9]*\)$/\1 \2/p' | awk '{b=$1+$2; if(b>m)m=b} END{print m+0}')
    [ "$bottom" -le "$5" ] 2>/dev/null && ok "page $2 at $4x$5: all controls end inside the window ($bottom <= $5)" || bad "page $2 at $4x$5: controls end at $bottom > $5"
    local cc; cc=$(grep -acE 'ABSTURZ|EXCEPTION' "$SS" 2>/dev/null; true)
    [ "$cc" = 0 ] && ok "page $2 at $4x$5: no crash" || bad "page $2 at $4x$5: crash lines $cc"
}
page_check pg0 0 '' 520 420 4
page_check pg1 1 'f=1\ns=1\n' 520 420 6
page_check pg2 2 '' 520 420 4
page_check pg1s 1 'f=1\n' 360 360 5
# ---- part D: the clicks walk the wizard
run_audit walk 'show=ja\nf=1\ns=1\n' 'warteauf "welcome: ready" || 240
warte 3
klickauf wlnth7x2
warteauf "welcome: page 1 of 3" || 60
warte 2
fahre 1270,790
warte 1
foto 01-net
klickauf wlnth7x3
warteauf "welcome: page 2 of 3" || 60
warte 2
fahre 1270,790
warte 1
foto 02-done
klickauf wlnth6x0
warteauf "settings: ready" || 120
warte 2
foto 03-settings
'
S="$W/walk/serial.txt"
has "$S" "welcome: page 1 of 3" "click next: Wi-Fi page"
has "$S" "welcome: page 2 of 3" "click next: done page"
has "$S" "settings: ready" "click on a done row opens Settings"
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash after the clicks" || bad "crash lines after the clicks: $c"
mkdir -p /tmp/welcome-last; cp "$W/walk/"0?-*.ppm /tmp/welcome-last/ 2>/dev/null
echo "WELCOME: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
