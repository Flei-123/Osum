#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wmplug/regel.sh -- DIE FENSTERREGEL-ENGINE, GEMESSEN.
#
# Modul `regel` der Runde WMPLUGIN. Zwei Laeufe desselben Kernels und
# desselben Abbilds, ein einziges Wort Unterschied auf der
# Kommandozeile:
#
#   MIT : wigapp=/bin/plugregel,recht,demo   (das Plugin bekommt R_ACT_WIN)
#   OHNE: wigapp=/bin/plugregel,demo         (es bekommt nur R_DEFAULT)
#
# In beiden Laeufen geht dasselbe Fenster auf (/bin/calc, Buendelname
# `rechner`), in beiden greift dieselbe Regel aus /etc/wmregeln.conf --
# nur darf das Plugin einmal handeln und einmal nicht.
#
# GEMESSEN WIRD NICHT DER RUECKGABEWERT, SONDERN DER ZUSTAND:
#   * die Zeile `plugregel: nachgemessen id= x= y= w= h= flaeche= sichtbar=`
#     -- das Plugin liest ZURUECK, was wirklich dasteht,
#   * die Fenstertafel des Servers beim Herunterfahren
#     (`wm: win ... t=[Rechner]`), die dasselbe noch einmal sagt,
#   * und zwei Fotos, an EINER benannten Koordinate nachgerechnet:
#     die Stelle, an der das Fenster nur nach der Regel steht.
#
# Die Mitte ist ausgerechnet und nicht abgeschrieben: Arbeitsflaeche
# 800x570 (Taskleiste 30), Fenster 340x430 -> x=230, y=70.
#
# Die Bilder landen in docs/shots/wmplug/.
#
# Gebrauch: bash tools/wmplug/regel.sh
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
punkt() { python3 tools/gfx/checkshot.py punkt "$1" "$2" "$3" 2>/dev/null; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "REGEL: uebersprungen, qemu-system-x86_64 ist nicht da"; exit 0
fi
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "firnc fehlt"; exit 1; }

echo "== 1. bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/k.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k.mb") Oktette)" \
    || { bad "der Kernel baut nicht"; tail -12 "$TMPD/k.log" | sed 's/^/        /'; }
[ -f "$TMPD/k.mb" ] || { echo "REGEL: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }

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
    || { echo "REGEL: $pass bestanden, $fail gescheitert"; exit 1; }

# DER KERN TRAEGT KEINE ZEILE DIESES PLUGINS. Das ist die Zusage der
# ganzen Runde, und sie wird am Abbild geprueft und nicht behauptet.
for sym in plugregel__anwenden plugregel__u_start plugregel__conf_lesen; do
    if nm -a "$TMPD/k.mb.elf" 2>/dev/null | grep -q "$sym"; then
        bad "der Kernel traegt $sym -- ein Plugin gehoert nach Ring 3"
    else
        ok "der Kernel traegt $sym NICHT (die Regel-Engine ist Ring 3)"
    fi
done

python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    && ok "der Verzeichnisbaum steht" || bad "tools/k15/tree.py fehlgeschlagen"

echo "== 2. das Abbild =="
[ -f etc/wmregeln.conf ] && ok "etc/wmregeln.conf liegt im Baum ($(grep -c '^[a-z]' etc/wmregeln.conf) Regelzeilen)" \
    || bad "etc/wmregeln.conf fehlt"
ARGS=(build "$TMPD/disk.img" 32768 /lib/
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in $PROGS; do ARGS+=("/bin/$p=$TMPD/$p.elf"); done
ARGS+=(/etc/ "/etc/theme=$TMPD/baum/theme" "/etc/wmregeln.conf=etc/wmregeln.conf")
# /etc/wmplug.conf gehoert dem Modul `verwaltung`. Ist es da, kommt es
# mit aufs Abbild; fehlt es, laeuft dieser Lauf trotzdem -- dieses Modul
# wartet auf keines.
[ -f etc/wmplug.conf ] && ARGS+=("/etc/wmplug.conf=etc/wmplug.conf")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "das Abbild ist gebaut" \
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
    # Der Starter wartet zwei Sekunden, bevor er /bin/calc startet, und
    # /bin/calc braucht selbst eine Weile, bis sein Fenster steht. Erst
    # danach hat die Regel etwas getan, das man fotografieren kann.
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

echo "== 3. der Lauf MIT dem Recht R_ACT_WIN =="
lauf mit "recht,demo"
[ "$RC" = 21 ] && ok "der Kern beendet sich sauber (21)" || bad "Exitcode $RC statt 21"
has "$TMPD/mit.klar" "wm: hold" "der Schreibtisch steht"
has "$TMPD/mit.klar" "plugregel: regeln aus /etc/wmregeln.conf: 2" \
    "das Plugin hat zwei Regeln gelesen"
has "$TMPD/mit.klar" "wmplug: reg regel" "es hat einen Tafelplatz bekommen"
has "$TMPD/mit.klar" "rechte=0x103" "mit R_ACT_WIN (0x103 = EV_WIN|EV_FOCUS|ACT_WIN)"
has "$TMPD/mit.klar" "app=rechner" "die Regel hat auf den Buendelnamen getroffen"
has "$TMPD/mit.klar" "x=230 y=70 w=340 h=430 flaeche=2 sichtbar=1" \
    "nachgemessen: zentriert (230,70) auf Flaeche 2 und sichtbar"
hasnot "$TMPD/mit.klar" "plugregel: abgewiesen" "keine Handlung wurde abgewiesen"
hasnot "$TMPD/mit.klar" "wmplug: unreg regel" "das Plugin wurde nicht hinausgeworfen"
has "$TMPD/mit.klar" "plugregel: puls" "und es lebte nach der Regel weiter"
# DIE FENSTERTAFEL DES SERVERS SAGT DASSELBE. Zwei Quellen, eine Zahl.
if grep -a 'wm: win ' "$TMPD/mit.klar" | grep -q 'x=230 y=70 .*t=\[Rechner\]'; then
    ok "die Fenstertafel des Servers zeigt den Rechner auf (230,70)"
else
    bad "die Fenstertafel zeigt den Rechner NICHT auf (230,70)"
    grep -a 'wm: win .*Rechner' "$TMPD/mit.klar" | sed 's/^/        /'
fi

echo "== 4. der Lauf OHNE das Recht (Rechte-Gegenprobe) =="
lauf ohne "demo"
[ "$RC" = 21 ] && ok "der Kern beendet sich sauber (21)" || bad "Exitcode $RC statt 21"
has "$TMPD/ohne.klar" "rechte=0x1f" "ohne Eintrag bekommt das Plugin nur R_DEFAULT"
has "$TMPD/ohne.klar" "plugregel: OHNE R_ACT_WIN -- nur zusehen" \
    "und sagt selbst, dass es nichts anfassen darf"
has "$TMPD/ohne.klar" "app=rechner" "dieselbe Regel trifft dasselbe Fenster"
has "$TMPD/ohne.klar" "abgewiesen handlung=6 id=" "PA_DESK wird abgewiesen"
has "$TMPD/ohne.klar" "fehler=2" "mit -E_RIGHTS (cap.E_RIGHTS = 2)"
has "$TMPD/ohne.klar" "plugregel: puls" "das Plugin lebt weiter, statt zu sterben"
hasnot "$TMPD/ohne.klar" "wmplug: unreg regel" "und bleibt angemeldet"
if grep -a 'wm: win ' "$TMPD/ohne.klar" | grep -q 'x=80 y=60 .*t=\[Rechner\]'; then
    ok "DAS FENSTER STEHT UNVERAENDERT auf (80,60) -- am Zustand gemessen"
else
    bad "das Fenster steht nicht mehr auf (80,60), obwohl das Recht fehlte"
    grep -a 'wm: win .*Rechner' "$TMPD/ohne.klar" | sed 's/^/        /'
fi

echo "== 5. die kurze Frist: schlaeft das Plugin zu lange? =="
# `plugfrist` setzt die Frist des Kerns von 50 auf 3 Ticks -- 30
# Millisekunden. Die Hauptschleife holt alle 10 ms ab; sie muss das also
# auch dann ueberstehen, wenn der Kehrbesen dreimal so scharf gestellt
# ist wie im Betrieb. Faellt diese Zusage, schlaeft die Schleife zu lang.
lauf kurz "recht,demo" "plugfrist"
[ "$RC" = 21 ] && ok "der Kern beendet sich sauber (21)" || bad "Exitcode $RC statt 21"
has "$TMPD/kurz.klar" "frist=3" "die Frist steht auf 3 Ticks (30 ms)"
hasnot "$TMPD/kurz.klar" "wmplug: unreg regel"     "und das Plugin wird trotzdem nicht wegen Frist hinausgeworfen"
has "$TMPD/kurz.klar" "x=230 y=70 w=340 h=430 flaeche=2 sichtbar=1"     "die Regel greift auch unter der kurzen Frist"

echo "== 6. die zwei Fotos, maschinell auseinandergehalten =="
for f in mit ohne; do
    [ -s "$TMPD/$f.ppm" ] && ok "Foto $f.ppm ($(python3 tools/gfx/checkshot.py groesse "$TMPD/$f.ppm"))" \
        || bad "kein Foto fuer den Lauf $f"
done
if [ -s "$TMPD/mit.ppm" ] && [ -s "$TMPD/ohne.ppm" ]; then
    # (500,300) liegt im ZENTRIERTEN Fenster (230..570) und ausserhalb
    # des unveraenderten (80..420); (120,300) genau andersherum.
    a=$(punkt "$TMPD/mit.ppm" 500 300)
    b=$(punkt "$TMPD/ohne.ppm" 500 300)
    c=$(punkt "$TMPD/ohne.ppm" 120 300)
    d=$(punkt "$TMPD/mit.ppm" 120 300)
    [ "$a" != "$b" ] && ok "(500,300) ist in beiden Bildern verschieden: '$a' gegen '$b'" \
        || bad "(500,300) ist in beiden Bildern gleich ('$a') -- kein sichtbarer Unterschied"
    [ "$a" = "$c" ] && ok "und im MIT-Bild steht dort die Fensterfarbe des OHNE-Bildes von (120,300): '$a'" \
        || bad "die Fensterfarbe wanderte nicht mit: '$a' gegen '$c'"
    [ "$d" != "$c" ] && ok "(120,300) hat das Fenster verlassen: '$d' gegen '$c'" \
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
    || bad "die Bilder wurden nicht abgelegt"

echo
echo "REGEL: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
exit 0
