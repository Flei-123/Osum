#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#
#
#
#
# Die Abschnitte:
#
#
# Verwendung:  bash tools/tiling/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
TMPD=${TILING_TMPD:-$(mktemp -d)}
[ -n "${TILING_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name wert op erwartet
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}

has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }

schau() { local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "$name ($aus)"; else bad "$name -- $aus"; fi
}
schau_nicht() { local name=$1; shift
    local aus rc
    aus=$(python3 tools/gfx/checkshot.py "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- passed: $aus"; fi
}
zahl() { grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+' | tail -1; }
feld() { grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+$'; }

. tools/lib/firnenv.sh
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "TILING: skipped, qemu-system-x86_64 is missing"
    exit 0
fi

GRUND="nokbd nosched noproc nofs"

#
VGA_STD=${VGA_STD:-"-vga std -global VGA.edid=off"}

lauf() { # abbild kommandozeile ausgabe abbilddatei
    local abbild=$1 zeile=$2 aus=$3 disk=$4
    cp -f "$disk" "$TMPD/live.img"
    timeout 300 $QEMU_X86 -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot $VGA_STD \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

RC=0
foto() { # abbild kommandozeile ausgabe ppm abbilddatei
    local abbild=$1 zeile=$2 aus=$3 ppm=$4 disk=$5
    local sock="$TMPD/mon-$$.sock"
    local live="$TMPD/live-$(basename "$aus").img"
    rm -f "$aus" "$ppm" "$sock"
    cp -f "$disk" "$live"
    timeout 300 $QEMU_X86 -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot $VGA_STD \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$live,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 1500 ]; do
        grep -qa '^wm: hold' "$aus" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 25 > "$TMPD/schuss.txt" 2>&1
    wait "$pid"
    RC=$?
    rm -f "$sock"
    return 0
}

echo "== 1. build: the same kernel from both compilers =="
for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: Kernel gebaut ($(stat -c%s "$TMPD/k$s.mb") Oktette)"
    else
        bad "firnc$s: the kernel cannot be built"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
K0="$TMPD/k0.mb"
[ -f "$K0" ] || { echo "TILING: $pass passed, $((fail + 1)) failed"; exit 1; }

echo "== 2. the memory map: four pages for the window tree =="
kart=$(python3 tools/kernel/memmap.py kernel 2>&1)
if [ $? -eq 0 ]; then ok "the memory map of kdata: $kart"
else bad "the memory map of kdata collides"; echo "$kart" | sed 's/^/        /'; fi
kartv=$(python3 tools/kernel/memmap.py kernel -v 2>/dev/null)
if grep -q " TILE  *kstate.fi:" <<< "$kartv"; then
    ok "the region TILE is in the map"
else
    bad "the region TILE is NOT in the map"
fi
GG="$TMPD/kernel-gg"; mkdir -p "$GG"
( cd kernel && find . -name '*.fi' -exec cp --parents {} "$GG/" \; )
sed -i -E 's/^const TILE_OFF: u64 = 0x[0-9A-Fa-f]+/const TILE_OFF: u64 = 0x58000/' "$GG/lib/kstate.fi"
grep -q '^const TILE_OFF: u64 = 0x58000' "$GG/lib/kstate.fi" \
    || bad "the control could not move TILE_OFF at all"
gg=$(python3 tools/kernel/memmap.py "$GG" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$gg" | grep -q 'COLLISION'; then
    ok "with TILE_OFF at 0x58000 the checker finds the collision with K18"
else
    bad "the collision checker does NOT find the new collision: $gg"
fi

echo "== the images: with and without key bindings =="
gebaut=1
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || gebaut=0
for p in sh echo uname tiling; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/$p.log" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>>"$TMPD/$p.log" \
        || { gebaut=0; sed 's/^/        /' "$TMPD/$p.log" | head -4; }
done
[ "$gebaut" = 1 ] && ok "the programs for the terminal window are built" \
    || bad "the programs for the terminal window cannot be built"
CONF=assets/tiling.conf
[ -f "$CONF" ] && ok "$CONF is in the tree ($(grep -c '^bind' $CONF) Zeilen mit bind)" \
    || bad "$CONF fehlt"
DISK="$TMPD/disk.img"
bash tools/mkfsfi/mkfs.sh build "$DISK" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    /bin/ /bin/sh="$TMPD/sh.elf" /bin/echo="$TMPD/echo.elf" \
    /bin/uname="$TMPD/uname.elf" /bin/tiling="$TMPD/tiling.elf" \
    /users/ /users/osum/ /users/osum/config/ \
    /users/osum/config/tiling.conf="$CONF" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py builds an image with the fonts and the key bindings" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt"; }
DISK2="$TMPD/disk-ohne.img"
bash tools/mkfsfi/mkfs.sh build "$DISK2" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    /bin/ /bin/sh="$TMPD/sh.elf" > "$TMPD/mkfs2.txt" 2>&1 \
    && ok "and a second one WITHOUT the file, for the control" \
    || bad "the second image cannot be built"

echo "== 3. the tree: twenty-four promises about itself =="
lauf "$K0" "gfx wm tile tilefuzz $GRUND" "$TMPD/t.txt" "$DISK"
num "der Kern beendet sich sauber" "$?" eq 21
st=$(zahl "$TMPD/t.txt" 'tile: selftest [0-9]+')
tsoll=$(grep -aoE 'return [0-9]+' <<< "$(sed -n '/fn selftest_max/,/^}/p' kernel/ui/tile.fi)" \
    | head -1 | grep -oE '[0-9]+')
num "die Zusagen des Fensterbaums ueber sich selbst" "$st" eq "${tsoll:-24}"
fbits=$(grep -aoE 'failed=0x[0-9A-Fa-f]+' "$TMPD/t.txt" | head -1 | sed 's/.*=//')
if [ "$fbits" = "0x0" ]; then ok "and NONE of them failed ($fbits)"
else bad "failed promises: $fbits (one bit per number)"; fi
has "$TMPD/t.txt" "nodes=96  maxleaf=48" \
    "die Obergrenze ist benannt: 96 Knoten tragen 48 Fenster"

echo "== 4. the timings: a recomputation for 2, 8 and 32 windows =="
r2=$(feld "$TMPD/t.txt" 'relay2=[0-9]+')
r8=$(feld "$TMPD/t.txt" 'relay8=[0-9]+')
r32=$(feld "$TMPD/t.txt" 'relay32=[0-9]+')
c32=$(feld "$TMPD/t.txt" 'check32=[0-9]+')
num "Neuberechnung fuer 2 Fenster (ns)" "$r2" gt 0
num "Neuberechnung fuer 8 Fenster (ns)" "$r8" gt 0
num "Neuberechnung fuer 32 Fenster (ns)" "$r32" gt 0
num "und die Pruefung der Invariante fuer 32 Fenster (ns)" "$c32" gt 0
if [ -n "$r2" ] && [ -n "$r32" ] && [ "$r2" -gt 0 ]; then
    v=$((r32 * 100 / r2))
    if [ "$v" -lt 4000 ]; then
        ok "the effort grows linearly: 32 windows cost $((v / 100)),$((v % 100 / 10)) times two"
    else
        bad "the effort grows too fast: factor $((v / 100))"
    fi
fi

echo "== 5. der Zufallstest: zehntausend Operationen, null Verletzungen =="
fz=$(feld "$TMPD/t.txt" 'fuzz ops=[0-9]+')
num "zufaellige Operationen auf dem Baum" "$fz" eq 10000
vi=$(feld "$TMPD/t.txt" 'violations=[0-9]+')
num "Verletzungen der Invariante" "$vi" eq 0
ck=$(feld "$TMPD/t.txt" 'checks=[0-9]+')
num "und nach JEDER Operation wurde nachgerechnet" "$ck" eq 10000
pk=$(feld "$TMPD/t.txt" 'peak=[0-9]+')
num "die meisten Knoten, die dabei gleichzeitig belegt waren" "$pk" le 96

echo "== 6. the region tracking: only the affected subtree =="
lauf "$K0" "gfx wm tile tileshot $GRUND" "$TMPD/s.txt" "$DISK"
num "der Kern beendet sich sauber" "$?" eq 21
sp=$(feld "$TMPD/s.txt" 'dirty split=[0-9]+')
sc=$(feld "$TMPD/s.txt" 'screen=[0-9]+')
num "der ganze Schirm sind" "$sc" eq 480000
num "ein Teilen faerbt weniger als den ganzen Schirm" "$sp" lt 480000
lauf "$K0" "gfx wm tile tileshot notiledirty $GRUND" "$TMPD/nd.txt" "$DISK"
sp2=$(feld "$TMPD/nd.txt" 'dirty split=[0-9]+')
num "GEGENPROBE notiledirty: dasselbe Teilen faerbt den ganzen Schirm" "$sp2" eq 480000
if [ -n "$sp" ] && [ -n "$sp2" ] && [ "$sp" -gt 0 ]; then
    num "und das spart die Teilbaumverfolgung (in Prozent der Flaeche)" \
        "$((sp2 * 100 / sp))" ge 150
fi

echo "== 7. the photos: split, tab, rotation =="
foto "$K0" "gfx wm tile tileshot wmhold $GRUND" "$TMPD/g.txt" "$TMPD/g.ppm" "$DISK"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/g.txt" "wm: hold" "der Kern haelt fuer das Foto still"
schau "das Foto ist 800x600" size "$TMPD/g.ppm" 800 600
has "$TMPD/g.txt" "tile: win=1 0,0 400x300" "Fenster 1 liegt oben links (400x300)"
has "$TMPD/g.txt" "tile: win=2 400,0 400x300" "Fenster 2 oben rechts"
has "$TMPD/g.txt" "tile: win=3 400,300 400x300" "Fenster 3 unten rechts"
has "$TMPD/g.txt" "tile: win=4 0,300 400x300" "Fenster 4 unten links"
schau "und im Bild ist Fenster 1 wirklich rot" \
    area "$TMPD/g.ppm" 2 22 396 264 192 48 48
schau "Fenster 2 gruen" area "$TMPD/g.ppm" 402 22 396 264 48 176 80
schau "Fenster 3 blau" area "$TMPD/g.ppm" 402 322 396 276 48 96 224
schau "Fenster 4 gelb" area "$TMPD/g.ppm" 2 322 396 276 224 192 48
schau_nicht "an der Naht der vier Kacheln liegt keine Luecke" \
    pixel "$TMPD/g.ppm" 399 299 30 42 56
foto "$K0" "gfx wm tile tileshot tiletabs wmhold $GRUND" "$TMPD/tb.txt" \
    "$TMPD/tb.ppm" "$DISK"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/tb.txt" "tile: tabs=1  hidden=3" \
    "vier Reiter, drei davon verdeckt -- genau EINER ist zu sehen"
has "$TMPD/tb.txt" "tile: win=1 0,22 800x578" \
    "und alle vier haben dasselbe Rechteck unter der Reiterzeile"
schau "der sichtbare Reiter fuellt die Flaeche unter der Zeile" \
    area "$TMPD/tb.ppm" 2 44 796 200 224 192 48
schau "der vierte Reiter ist der aktive (helle Leiste rechts oben)" \
    area "$TMPD/tb.ppm" 700 5 60 12 28 78 126
DKT=$(sed -n '/fn deco_fallback/,/^}/p' kernel/ui/wm/wmbase.fi \
    | grep -A2 'i == DK_TITLE {' | grep -oE '0x00[0-9A-Fa-f]{6}' | head -1)
DKT=${DKT:-0x002C3848}
dkr=$(( (DKT >> 16) & 255 )); dkg=$(( (DKT >> 8) & 255 )); dkb=$(( DKT & 255 ))
schau "der erste ist es nicht (dunkle Leiste links oben, DK_TITLE)" \
    area "$TMPD/tb.ppm" 100 5 60 12 $dkr $dkg $dkb
schau_nicht "und in der Reiterzeile steht Text, nicht nur Farbe" \
    area "$TMPD/tb.ppm" 606 4 40 16 28 78 126
foto "$K0" "gfx wm tile tileshot tilerot wmhold $GRUND" "$TMPD/rt.txt" \
    "$TMPD/rt.ppm" "$DISK"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/rt.txt" "tile: win=4 0,0 400x300" "nach der Drehung liegt Fenster 4 oben links"
has "$TMPD/rt.txt" "tile: win=1 400,0 400x300" "und Fenster 1 oben rechts"
schau "im Bild ist oben links jetzt gelb" \
    area "$TMPD/rt.ppm" 2 22 396 264 224 192 48
schau "und oben rechts rot" \
    area "$TMPD/rt.ppm" 402 22 396 264 192 48 48
schau_nicht "die Farben sind also WIRKLICH gewandert" \
    area "$TMPD/rt.ppm" 2 22 396 276 192 48 48

echo "== 8. the key bindings: one file, no source code =="
bd=$(feld "$TMPD/t.txt" 'tile: binds=[0-9]+')
soll=$(grep -c '^bind' "$CONF")
num "Eintraege, die aus /users/osum/config/tiling.conf gelesen wurden" "$bd" eq "$soll"
lauf "$K0" "gfx wm tile $GRUND" "$TMPD/nb.txt" "$DISK2"
has "$TMPD/nb.txt" "tile: binds=0" \
    "GEGENPROBE: ohne die Datei hat der Kernel KEINE Tastenbelegung"

echo "== 9. /bin/tiling: the operation lives in ring 3 =="
lauf "$K0" "gfx wm tile wmshell $GRUND script=tiling;tiling load;tiling keys" \
    "$TMPD/u.txt" "$DISK"
num "der Lauf mit /bin/tiling endet sauber" "$?" eq 21
U="$TMPD/u.txt"
has "$U" "tiling: tiling mode is running" "das Programm sieht den Kachelbetrieb"
has "$U" "Fenster: 2 von 48" "es nennt die Zahl der Fenster und die Obergrenze"
has "$U" "Aufbau:  split" "es nennt den Modus des Containers"
has "$U" "invariant: holds" "und es laesst den Kern die Invariante NACHRECHNEN"
has "$U" "$soll tiling: Einträge gelesen" \
    "es liest /users/osum/config/tiling.conf und schiebt sie in den Kern"
has "$U" "mod+h  focus-left" "es liest die Belegung wieder heraus"
has "$U" "mod+shift+l  move-right" "mit Modifikatoren"
has "$U" "mod+left  snap-left" "und mit Tasten, die kein Zeichen sind"
ub=$(grep -aoE '^[0-9]+ tiling: Einträge' "$U" | head -1 | grep -oE '^[0-9]+')
if [ -n "$ub" ] && [ "$ub" = "$soll" ]; then
    ok "kernel and ring 3 count the same entries ($ub)"
else
    bad "Kern sagt $soll, /bin/tiling sagt '$ub'"
fi

echo "== 10. the control for the whole round: without 'tile' wie vorher =="
lauf "$K0" "gfx wm wmhold $GRUND" "$TMPD/o.txt" "$DISK"
ws=$(zahl "$TMPD/o.txt" 'wm: .*selftest [0-9]+')
wsoll=$(grep -aoE 'return [0-9]+' <<< "$(sed -n '/fn selftest_max/,/^}/p' kernel/ui/wm/vtest.fi)" \
    | head -1 | grep -oE '[0-9]+')
num "die Zusagen des Fensterservers ueber sich selbst, unveraendert" "$ws" eq "${wsoll:-17}"
has "$TMPD/o.txt" "wm: 800x600" "der Server kennt die Flaeche wie vorher"
has "$TMPD/o.txt" "wm: term win=0" "das Terminalfenster entsteht wie vorher"
hasnot "$TMPD/o.txt" "tile: win=" "und KEIN Fenster geht in den Baum"

echo "TILING: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
