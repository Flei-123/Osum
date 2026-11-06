#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#
#
#
#
#
# Die Bilder landen in docs/shots/wmplug/.
#
# Gebrauch: bash tools/wmplug/rule.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/userprog.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d /tmp/wmplug-regel-XXXXXX)
[ "${REGEL_KEEP:-0}" = 1 ] || trap 'rm -rf "$TMPD"' EXIT
SHOTS="docs/shots/wmplug"
mkdir -p "$SHOTS"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }
punkt() { python3 tools/gfx/checkshot.py pixel "$1" "$2" "$3" 2>/dev/null; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "RULE: skipped, qemu-system-x86_64 is missing"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "the kernel does not build"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; }
[ -f "$TMPD/k.mb" ] || { echo "RULE: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s assembliert nicht"
PROGS="desktop taskbar launcher calc plugregel sh"
gebaut=1
for p in $PROGS; do
    up_build vendor/firn/bin/firnc "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
        "$TMPD/crt.o" kernel/user/user.ld 0 "$TMPD/$p.err" || {
        bad "firnc0 uebersetzt $p.fi nicht"
        sed 's/^/        /' "$TMPD/$p.err" | head -6; gebaut=0; }
done
[ "$gebaut" = 1 ] && ok "$(echo $PROGS | wc -w) Programme gebaut, /bin/plugregel ist $(stat -c%s "$TMPD/plugregel.elf") Oktette" \
    || { echo "RULE: $pass bestanden, $fail gescheitert"; exit 1; }

for sym in plugregel__anwenden plugregel__u_start plugregel__conf_lesen; do
    if nm -a "$TMPD/k.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "the kernel carries $sym -- a plugin belongs in ring 3"
    else
        ok "the kernel does NOT carry $sym (the rule engine is ring 3)"
    fi
done

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "the directory tree is ready" || bad "tools/k15/tree.py fehlgeschlagen"

echo "== 2. das Abbild =="
[ -f etc/wmregeln.conf ] && ok "etc/wmregeln.conf is in the tree ($(grep -c '^[a-z]' etc/wmregeln.conf) Regelzeilen)" \
    || bad "etc/wmregeln.conf fehlt"
ARGS=(build "$TMPD/disk.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/wmregeln.conf=etc/wmregeln.conf")
[ -f etc/wmplug.conf ] && ARGS+=("/etc/wmplug.conf=etc/wmplug.conf")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
bash tools/mkfsfi/mkfs.sh "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the image is built" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

BASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs nostart wmplug"
RC=0
lauf() { # name wigapp-argumente [zusatzwoerter]
    local name=$1 wa=$2 extra=${3:-}
    local sock="$TMPD/mon-$name.sock" out="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$out" "$ppm" "$sock"
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$BASE $extra wigapp=/bin/plugregel,$wa" \
        -serial "file:$out" -display none -no-reboot \
        -vga std -global VGA.edid=off -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$! i=0
    while [ $i -lt 1400 ]; do
        grep -qa '^wm: hold' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    i=0
    while [ $i -lt 200 ]; do
        grep -qa 'plugregel: nachgemessen' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i+1))
    done
    sleep 2
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/$name.shot" 2>&1
    wait "$pid"; RC=$?
    rm -f "$sock"
    tr -cd '\11\12\15\40-\176' < "$out" > "$TMPD/$name.klar"
}

echo "== 3. the run WITH the right R_ACT_WIN =="
lauf mit "recht,demo"
[ "$RC" = 21 ] && ok "the kernel exits cleanly (21)" || bad "Exitcode $RC statt 21"
has "$TMPD/mit.klar" "wm: hold" "der Schreibtisch steht"
has "$TMPD/mit.klar" "plugregel: regeln aus /etc/wmregeln.conf: 2" \
    "das Plugin hat zwei Regeln gelesen"
has "$TMPD/mit.klar" "wmplug: reg regel" "es hat einen Tafelplatz bekommen"
has "$TMPD/mit.klar" "rechte=0x103" "mit R_ACT_WIN (0x103 = EV_WIN|EV_FOCUS|ACT_WIN)"
has "$TMPD/mit.klar" "app=rechner" "die Regel hat auf den Buendelnamen getroffen"
has "$TMPD/mit.klar" "x=212 y=70 w=376 h=430 flaeche=2 sichtbar=1" \
    "nachgemessen: zentriert (212,70) auf Flaeche 2 und sichtbar"
hasnot "$TMPD/mit.klar" "plugregel: rejected" "keine Handlung wurde abgewiesen"
hasnot "$TMPD/mit.klar" "wmplug: unreg regel" "das Plugin wurde nicht hinausgeworfen"
has "$TMPD/mit.klar" "plugregel: pulse" "und es lebte nach der Regel weiter"
if grep -a 'wm: win ' "$TMPD/mit.klar" | grep -qE 'x=212 y=70 .*t=\[(Rechner|calc.title)\]'; then
    ok "the window table of the server shows the calculator at (212,70)"
else
    bad "the window table does NOT show the calculator at (212,70)"
    grep -aE 'wm: win .*(Rechner|calc.title)' "$TMPD/mit.klar" | sed 's/^/        /'
fi

echo "== 4. the run WITHOUT the right (rights control) =="
lauf ohne "demo"
[ "$RC" = 21 ] && ok "the kernel exits cleanly (21)" || bad "Exitcode $RC statt 21"
has "$TMPD/ohne.klar" "rechte=0x1f" "ohne Eintrag bekommt das Plugin nur R_DEFAULT"
has "$TMPD/ohne.klar" "plugregel: WITHOUT R_ACT_WIN -- watching only" \
    "und sagt selbst, dass es nichts anfassen darf"
has "$TMPD/ohne.klar" "app=rechner" "dieselbe Regel trifft dasselbe Fenster"
has "$TMPD/ohne.klar" "rejected action=6 id=" "PA_DESK wird abgewiesen"
has "$TMPD/ohne.klar" "errors=2" "mit -E_RIGHTS (cap.E_RIGHTS = 2)"
has "$TMPD/ohne.klar" "plugregel: pulse" "das Plugin lebt weiter, statt zu sterben"
hasnot "$TMPD/ohne.klar" "wmplug: unreg regel" "und bleibt angemeldet"
if grep -a 'wm: win ' "$TMPD/ohne.klar" | grep -qE 'x=80 y=60 .*t=\[(Rechner|calc.title)\]'; then
    ok "THE WINDOW STAYS UNCHANGED at (80,60) -- measured by state"
else
    bad "the window is no longer at (80,60), although the right was missing"
    grep -aE 'wm: win .*(Rechner|calc.title)' "$TMPD/ohne.klar" | sed 's/^/        /'
fi

echo "== 5. the short deadline: does the plugin sleep too long? =="
lauf kurz "recht,demo" "plugfrist"
[ "$RC" = 21 ] && ok "the kernel exits cleanly (21)" || bad "Exitcode $RC statt 21"
has "$TMPD/kurz.klar" "frist=3" "die Frist steht auf 3 Ticks (30 ms)"
hasnot "$TMPD/kurz.klar" "wmplug: unreg regel"     "und das Plugin wird trotzdem nicht wegen Frist hinausgeworfen"
has "$TMPD/kurz.klar" "x=212 y=70 w=376 h=430 flaeche=2 sichtbar=1"     "die Regel greift auch unter der kurzen Frist"

echo "== 6. the two photos, told apart by machine =="
for f in mit ohne; do
    [ -s "$TMPD/$f.ppm" ] && ok "Foto $f.ppm ($(python3 tools/gfx/checkshot.py size "$TMPD/$f.ppm"))" \
        || bad "no photo for run $f"
done
if [ -s "$TMPD/mit.ppm" ] && [ -s "$TMPD/ohne.ppm" ]; then
    a=$(punkt "$TMPD/mit.ppm" 500 300)
    b=$(punkt "$TMPD/ohne.ppm" 500 300)
    c=$(punkt "$TMPD/ohne.ppm" 120 300)
    d=$(punkt "$TMPD/mit.ppm" 120 300)
    [ "$a" != "$b" ] && ok "(500,300) ist in beiden Bildern verschieden: '$a' gegen '$b'" \
        || bad "(500,300) is the same in both images ('$a') -- kein sichtbarer Unterschied"
    e=$(punkt "$TMPD/mit.ppm" 252 310)
    [ "$e" = "$c" ] && ok "and in the WITH image the window colour of the WITHOUT image from (120,300) sits at the shifted point (252,310): '$e'" \
        || bad "the window colour did not move along: '$e' gegen '$c'"
    [ "$d" != "$c" ] && ok "(120,300) has left the window: '$d' gegen '$c'" \
        || bad "(120,300) zeigt in beiden Bildern dasselbe"
fi
cp -f "$TMPD/mit.ppm" "$SHOTS/regel-mit-recht.ppm" 2>/dev/null
cp -f "$TMPD/ohne.ppm" "$SHOTS/regel-ohne-recht.ppm" 2>/dev/null
for f in regel-mit-recht regel-ohne-recht; do
    [ -s "$SHOTS/$f.ppm" ] || continue
    python3 -c "from PIL import Image; Image.open('$SHOTS/$f.ppm').save('$SHOTS/$f.png')" \
        2>/dev/null && rm -f "$SHOTS/$f.ppm"
done
ls "$SHOTS" | grep -q regel- && ok "die Bilder liegen in $SHOTS" \
    || bad "the images were not stored"

echo
echo "RULE: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
exit 0
