#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tiling/run.sh -- DER BEWEIS, DASS OSUM EINEN FENSTERBAUM HAT.
#
# Bis zu dieser Runde schwebten die Fenster frei.  Runde K10 gab ihnen
# eine Stapelreihenfolge, einen Eingabefokus und eine Bereichsverfolgung;
# WOHIN ein Fenster gelegt wurde, entschied der, der es anlegte.  Mit acht
# Fenstern ist das kein Arbeitsplatz, sondern ein Kartenstapel.
#
# WAS HIER GEMESSEN WIRD, UND WARUM ES SO GEMESSEN WERDEN MUSS.
#
# Ein Kachelsystem hat genau eine Eigenschaft, an der alles haengt: die
# Fenster muessen die Flaeche EXAKT ausfuellen.  Keine Luecke, keine
# Ueberlappung, und die Summe der Kinder ist der Elternknoten -- nach
# JEDER Operation, nicht nur nach denen, die man von Hand ausprobiert.
# Deshalb wird hier nicht "es sieht richtig aus" geprueft, sondern:
#
#   * ZEHNTAUSEND ZUFAELLIGE OPERATIONEN (oeffnen, schliessen,
#     verschieben, Modus wechseln, Groesse aendern, drehen, spiegeln,
#     schnappen), und nach jeder einzelnen rechnet der Kernel die
#     Invariante nach.  Null Verletzungen, oder die Runde ist nichts
#     wert.  Der Generator ist festgenagelt: derselbe Startwert, dieselbe
#     Folge, ein Fehler ist wiederholbar.
#   * DIE PRUEFUNG SELBST HAT EINE GEGENPROBE.  Zusage 23 des Selbsttests
#     verstellt ein Rechteck um EINEN Bildpunkt und verlangt, dass
#     `check` es findet.  Eine Pruefung, die nicht fallen kann, prueft
#     nichts -- die Lehre aus Runde K7B, eine Ebene hoeher.
#   * DIE BEREICHSVERFOLGUNG DARF NICHT KAPUTTGEHEN.  Beim Teilen eines
#     Blattes wird nur der betroffene TEILBAUM neu gezeichnet.  Gemessen
#     wird der Zaehler des Fensterservers (`compose` addiert die Flaeche,
#     die es wirklich zusammengesetzt hat), und `notiledirty` schaltet die
#     Teilbaumverfolgung ab, damit die Zahl etwas bedeutet.
#   * DREI BILDSCHIRMFOTOS, maschinell nachgerechnet: vier Kacheln im
#     Teilungsmodus, dieselben vier als REITER, und dieselben vier nach
#     einer Vierteldrehung.  Jedes Fenster hat eine eigene Farbe; geprueft
#     wird die Farbe an der Stelle, an der der Baum sie ausgerechnet hat,
#     und einen Bildpunkt daneben nicht.
#
# Die Abschnitte:
#
#   1. BAUEN.  Beide Uebersetzer bauen denselben Kernel.
#   2. DIE SPEICHERKARTE.  TILE (0x4C000..0x50000) steht in der Karte,
#      und der Kollisionspruefer schlaegt an, wenn man ihn woanders
#      hinlegt.
#   3. DER BAUM.  Vierundzwanzig Zusagen ueber sich selbst.
#   4. DIE ZEITEN.  Neuberechnung fuer 2, 8 und 32 Fenster.
#   5. DER ZUFALLSTEST.  Zehntausend Operationen, null Verletzungen.
#   6. DIE BEREICHSVERFOLGUNG und ihre Gegenprobe.
#   7. DIE FOTOS.  Teilung, Reiter, Drehung.
#   8. DIE TASTENBELEGUNG aus /users/<name>/config/tiling.conf, und die
#      Gegenprobe: ohne die Datei gibt es keine Belegung.
#   9. /bin/tiling: die Bedienung liegt in RING 3 und redet ueber vier
#      Systemaufrufe mit dem Kern.
#  10. DIE GEGENPROBE ZUR GANZEN RUNDE.  Ohne das Wort `tile` verhaelt
#      sich der Fensterserver Zeile fuer Zeile wie vor dieser Runde.
#
# Verwendung:  bash tools/tiling/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name wert op erwartet
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
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
    if [ "$rc" -ne 0 ]; then ok "$name ($aus)"; else bad "$name -- ging durch: $aus"; fi
}
zahl() { grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+' | tail -1; }
feld() { grep -aoE "$2" "$1" | head -1 | grep -oE '[0-9]+$'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "TILING: skipped, qemu-system-x86_64 ist nicht da"
    exit 0
fi

GRUND="nokbd nosched noproc nofs"

lauf() { # abbild kommandozeile ausgabe abbilddatei
    local abbild=$1 zeile=$2 aus=$3 disk=$4
    cp -f "$disk" "$TMPD/live.img"
    timeout 300 $QEMU_X86 -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot -vga std \
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
        -serial "file:$aus" -display none -no-reboot -vga std \
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

echo "== 1. bauen: derselbe Kernel aus beiden Uebersetzern =="
for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: Kernel gebaut ($(stat -c%s "$TMPD/k$s.mb") Oktette)"
    else
        bad "firnc$s: der Kernel laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/b$s.log" | head -12
    fi
done
K0="$TMPD/k0.mb"
[ -f "$K0" ] || { echo "TILING: $pass passed, $((fail + 1)) failed"; exit 1; }

echo "== 2. die Speicherkarte: vier Seiten fuer den Fensterbaum =="
kart=$(python3 tools/kernel/memmap.py kernel 2>&1)
if [ $? -eq 0 ]; then ok "die Speicherkarte von kdata: $kart"
else bad "die Speicherkarte von kdata kollidiert"; echo "$kart" | sed 's/^/        /'; fi
if python3 tools/kernel/memmap.py kernel -v 2>/dev/null | grep -q " TILE  *kstate.fi:"; then
    ok "der Bereich TILE steht in der Karte"
else
    bad "der Bereich TILE steht NICHT in der Karte"
fi
# Und die Gegenprobe zum Pruefer: legt man den Baum auf die Seiten der
# Energieschicht, MUSS er anschlagen.  Genau so ist Runde K7 gescheitert.
# RUNDE MERGE, ZWEI SACHEN AN DIESER GEGENPROBE:
#   * Die Kopie braucht `kernel/arch/x86_64/` mit. Seit Runde ARM liegt
#     `hv.fi` dort, und ohne sie stirbt der Kartenpruefer an einem
#     KeyError, statt die Kollision zu melden, die hier gemessen wird --
#     der Lauf meldete dann "findet die neue Kollision NICHT", und der
#     Pruefer hatte recht.
#   * Die Adresse steht nicht mehr fest im `sed`. TILE_OFF war 0x4C000
#     und ist auf dem zusammengefuehrten Baum 0x68000, also traf das
#     Muster nichts, die Kopie blieb unveraendert und war -- richtigerweise
#     -- kollisionsfrei. Gesucht wird jetzt der Name und nicht der Wert.
GG="$TMPD/kernel-gg"; mkdir -p "$GG/arch/x86_64"
cp kernel/*.fi "$GG/"
cp kernel/arch/x86_64/*.fi "$GG/arch/x86_64/"
sed -i -E 's/^const TILE_OFF: u64 = 0x[0-9A-Fa-f]+/const TILE_OFF: u64 = 0x58000/' "$GG/kstate.fi"
grep -q '^const TILE_OFF: u64 = 0x58000' "$GG/kstate.fi" \
    || bad "die Gegenprobe konnte TILE_OFF gar nicht verschieben"
gg=$(python3 tools/kernel/memmap.py "$GG" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$gg" | grep -q 'KOLLISION'; then
    ok "mit TILE_OFF auf 0x58000 findet der Pruefer die Kollision mit K18"
else
    bad "der Kollisionspruefer findet die neue Kollision NICHT: $gg"
fi

echo "== die Abbilder: mit und ohne Tastenbelegung =="
gebaut=1
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || gebaut=0
for p in sh echo uname tiling; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/$p.log" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>>"$TMPD/$p.log" \
        || { gebaut=0; sed 's/^/        /' "$TMPD/$p.log" | head -4; }
done
[ "$gebaut" = 1 ] && ok "die Programme fuer das Terminalfenster gebaut" \
    || bad "die Programme fuer das Terminalfenster lassen sich nicht bauen"
# DIE TASTENBELEGUNG IST EINE DATEI UND KEIN QUELLTEXT.  Sie liegt hier
# im Baum, kommt so auf das Abbild und wird beim Hochlauf gelesen.
CONF=assets/tiling.conf
[ -f "$CONF" ] && ok "$CONF liegt im Baum ($(grep -c '^bind' $CONF) Zeilen mit bind)" \
    || bad "$CONF fehlt"
DISK="$TMPD/disk.img"
python3 tools/osum/mkfs.py build "$DISK" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    /bin/ /bin/sh="$TMPD/sh.elf" /bin/echo="$TMPD/echo.elf" \
    /bin/uname="$TMPD/uname.elf" /bin/tiling="$TMPD/tiling.elf" \
    /users/ /users/osum/ /users/osum/config/ \
    /users/osum/config/tiling.conf="$CONF" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py baut ein Abbild mit den Schriften und der Tastenbelegung" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt"; }
DISK2="$TMPD/disk-ohne.img"
python3 tools/osum/mkfs.py build "$DISK2" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    /bin/ /bin/sh="$TMPD/sh.elf" > "$TMPD/mkfs2.txt" 2>&1 \
    && ok "und ein zweites OHNE die Datei, fuer die Gegenprobe" \
    || bad "das zweite Abbild laesst sich nicht bauen"

echo "== 3. der Baum: vierundzwanzig Zusagen ueber sich selbst =="
lauf "$K0" "gfx wm tile tilefuzz $GRUND" "$TMPD/t.txt" "$DISK"
num "der Kern beendet sich sauber" "$?" eq 21
st=$(zahl "$TMPD/t.txt" 'tile: selftest [0-9]+')
num "die Zusagen des Fensterbaums ueber sich selbst" "$st" eq 24
fbits=$(grep -aoE 'failed=0x[0-9A-Fa-f]+' "$TMPD/t.txt" | head -1 | sed 's/.*=//')
if [ "$fbits" = "0x0" ]; then ok "und KEINE davon ist gefallen ($fbits)"
else bad "gefallene Zusagen: $fbits (ein Bit je Nummer)"; fi
has "$TMPD/t.txt" "nodes=96  maxleaf=48" \
    "die Obergrenze ist benannt: 96 Knoten tragen 48 Fenster"

echo "== 4. die Zeiten: eine Neuberechnung fuer 2, 8 und 32 Fenster =="
# Tausend Laeufe je Zahl.  Die Mikrosekunde des ganzen Laufs ist damit
# die Nanosekunde EINES Laufs -- ohne eine Division, die etwas
# beschoenigen koennte.  Gemessen in QEMU OHNE KVM; auf echtem Blech ist
# es schneller, und diese Zahl steht so auch in docs/TILING.md.
r2=$(feld "$TMPD/t.txt" 'relay2=[0-9]+')
r8=$(feld "$TMPD/t.txt" 'relay8=[0-9]+')
r32=$(feld "$TMPD/t.txt" 'relay32=[0-9]+')
c32=$(feld "$TMPD/t.txt" 'check32=[0-9]+')
num "Neuberechnung fuer 2 Fenster (ns)" "$r2" gt 0
num "Neuberechnung fuer 8 Fenster (ns)" "$r8" gt 0
num "Neuberechnung fuer 32 Fenster (ns)" "$r32" gt 0
num "und die Pruefung der Invariante fuer 32 Fenster (ns)" "$c32" gt 0
# DIE ZUSAGE UEBER DIE ZEIT: sie waechst mit der Zahl der Fenster und
# nicht mit ihrem Quadrat.  32 Fenster sind das Sechzehnfache von zwei;
# der Aufwand darf hoechstens das Vierzigfache sein.
if [ -n "$r2" ] && [ -n "$r32" ] && [ "$r2" -gt 0 ]; then
    v=$((r32 * 100 / r2))
    if [ "$v" -lt 4000 ]; then
        ok "der Aufwand waechst linear: 32 Fenster kosten das $((v / 100)),$((v % 100 / 10))-fache von zwei"
    else
        bad "der Aufwand waechst zu schnell: Faktor $((v / 100))"
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

echo "== 6. die Bereichsverfolgung: nur der betroffene Teilbaum =="
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

echo "== 7. die Fotos: Teilung, Reiter, Drehung =="
foto "$K0" "gfx wm tile tileshot wmhold $GRUND" "$TMPD/g.txt" "$TMPD/g.ppm" "$DISK"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/g.txt" "wm: hold" "der Kern haelt fuer das Foto still"
schau "das Foto ist 800x600" groesse "$TMPD/g.ppm" 800 600
# DIE VIER KACHELN.  Der Baum hat sie ausgerechnet, die serielle Leitung
# meldet dieselben Zahlen, und das Bild zeigt sie an genau der Stelle.
has "$TMPD/g.txt" "tile: win=1 0,0 400x300" "Fenster 1 liegt oben links (400x300)"
has "$TMPD/g.txt" "tile: win=2 400,0 400x300" "Fenster 2 oben rechts"
has "$TMPD/g.txt" "tile: win=3 400,300 400x300" "Fenster 3 unten rechts"
has "$TMPD/g.txt" "tile: win=4 0,300 400x300" "Fenster 4 unten links"
schau "und im Bild ist Fenster 1 wirklich rot" \
    flaeche "$TMPD/g.ppm" 2 22 396 276 192 48 48
schau "Fenster 2 gruen" flaeche "$TMPD/g.ppm" 402 22 396 276 48 176 80
schau "Fenster 3 blau" flaeche "$TMPD/g.ppm" 402 322 396 276 48 96 224
schau "Fenster 4 gelb" flaeche "$TMPD/g.ppm" 2 322 396 276 224 192 48
# KEINE LUECKE.  Die Zusage des ganzen Systems in einem Bildpunkt: an der
# Naht zwischen zwei Kacheln steht Fensterrahmen und NICHT der
# Hintergrund des Servers (0x1E2A38).
schau_nicht "an der Naht der vier Kacheln liegt keine Luecke" \
    punkt "$TMPD/g.ppm" 399 299 30 42 56
foto "$K0" "gfx wm tile tileshot tiletabs wmhold $GRUND" "$TMPD/tb.txt" \
    "$TMPD/tb.ppm" "$DISK"
num "der Kern beendet sich sauber" "$RC" eq 21
has "$TMPD/tb.txt" "tile: tabs=1  hidden=3" \
    "vier Reiter, drei davon verdeckt -- genau EINER ist zu sehen"
has "$TMPD/tb.txt" "tile: win=1 0,22 800x578" \
    "und alle vier haben dasselbe Rechteck unter der Reiterzeile"
# Der Zeiger steht in der Bildmitte und ist zwoelf mal achtzehn
# Bildpunkte gross -- die Probeflaeche bleibt darueber.
schau "der sichtbare Reiter fuellt die Flaeche unter der Zeile" \
    flaeche "$TMPD/tb.ppm" 2 44 796 200 224 192 48
schau "der vierte Reiter ist der aktive (helle Leiste rechts oben)" \
    flaeche "$TMPD/tb.ppm" 700 5 60 12 28 78 126
# RUNDE MERGE: DIE FARBE STEHT NICHT MEHR IM LAEUFER. Der Reiterhinter-
# grund war 0x222C38, weil diese Runde ihn so in `kernel/wm.fi`
# hineingeschrieben hatte -- und genau das hat Runde THEME verboten
# (tests/theme/rawcolour.py). Ein Reiter IST eine Titelleiste, also
# nimmt er seit dem Zusammenfuehren den Deko-Platz DK_TITLE, und der
# steht bei 0x2C3848. Geholt wird er hier aus `deco_fallback`, damit
# ein neues Schema die Zusage nicht wieder umwirft.
DKT=$(sed -n '/fn deco_fallback/,/^}/p' kernel/wm.fi \
    | grep -A2 'i == DK_TITLE {' | grep -oE '0x00[0-9A-Fa-f]{6}' | head -1)
DKT=${DKT:-0x002C3848}
dkr=$(( (DKT >> 16) & 255 )); dkg=$(( (DKT >> 8) & 255 )); dkb=$(( DKT & 255 ))
schau "der erste ist es nicht (dunkle Leiste links oben, DK_TITLE)" \
    flaeche "$TMPD/tb.ppm" 100 5 60 12 $dkr $dkg $dkb
schau_nicht "und in der Reiterzeile steht Text, nicht nur Farbe" \
    flaeche "$TMPD/tb.ppm" 606 4 40 16 28 78 126
foto "$K0" "gfx wm tile tileshot tilerot wmhold $GRUND" "$TMPD/rt.txt" \
    "$TMPD/rt.ppm" "$DISK"
num "der Kern beendet sich sauber" "$RC" eq 21
# EINE VIERTELDREHUNG IM UHRZEIGERSINN: aus links wird oben, aus oben
# wird rechts.  Fenster 4 lag unten links und liegt jetzt oben links,
# Fenster 1 lag oben links und liegt jetzt oben rechts.
has "$TMPD/rt.txt" "tile: win=4 0,0 400x300" "nach der Drehung liegt Fenster 4 oben links"
has "$TMPD/rt.txt" "tile: win=1 400,0 400x300" "und Fenster 1 oben rechts"
schau "im Bild ist oben links jetzt gelb" \
    flaeche "$TMPD/rt.ppm" 2 22 396 276 224 192 48
schau "und oben rechts rot" \
    flaeche "$TMPD/rt.ppm" 402 22 396 276 192 48 48
schau_nicht "die Farben sind also WIRKLICH gewandert" \
    flaeche "$TMPD/rt.ppm" 2 22 396 276 192 48 48

echo "== 8. die Tastenbelegung: eine Datei, kein Quelltext =="
bd=$(feld "$TMPD/t.txt" 'tile: binds=[0-9]+')
soll=$(grep -c '^bind' "$CONF")
num "Eintraege, die aus /users/osum/config/tiling.conf gelesen wurden" "$bd" eq "$soll"
# DIE GEGENPROBE, und sie ist der ganze Punkt: ohne die Datei gibt es
# KEINE Belegung.  Ein eingebauter Satz Tasten im Quelltext waere genau
# das, was die Aufgabe verboten hat -- und er wuerde hier durchgehen.
lauf "$K0" "gfx wm tile $GRUND" "$TMPD/nb.txt" "$DISK2"
has "$TMPD/nb.txt" "tile: binds=0" \
    "GEGENPROBE: ohne die Datei hat der Kernel KEINE Tastenbelegung"

echo "== 9. /bin/tiling: die Bedienung liegt in Ring 3 =="
# DER GANZE PUNKT DIESES ABSCHNITTS: alles, was hier steht, kommt aus
# einem ELF von der Platte, das ueber `syscall` fragt -- nicht aus dem
# Kern und nicht aus dem Testlaeufer.  `wmshell` gibt dem Programm die
# Shell IM Terminalfenster, und `script=` schiebt ihm die Zeilen hinein.
lauf "$K0" "gfx wm tile wmshell $GRUND script=tiling;tiling load;tiling keys" \
    "$TMPD/u.txt" "$DISK"
num "der Lauf mit /bin/tiling endet sauber" "$?" eq 21
U="$TMPD/u.txt"
has "$U" "tiling: der Kachelbetrieb laeuft" "das Programm sieht den Kachelbetrieb"
has "$U" "Fenster: 2 von 48" "es nennt die Zahl der Fenster und die Obergrenze"
has "$U" "Aufbau:  split" "es nennt den Modus des Containers"
has "$U" "Invariante: haelt" "und es laesst den Kern die Invariante NACHRECHNEN"
has "$U" "21 tiling: Eintraege gelesen" \
    "es liest /users/osum/config/tiling.conf und schiebt sie in den Kern"
has "$U" "mod+h  focus-left" "es liest die Belegung wieder heraus"
has "$U" "mod+shift+l  move-right" "mit Modifikatoren"
has "$U" "mod+left  snap-left" "und mit Tasten, die kein Zeichen sind"
# Beide Wege muessen dieselbe Zahl sagen: der Kern beim Hochlauf und das
# Programm ueber den Systemaufruf.
ub=$(grep -aoE '^[0-9]+ tiling: Eintraege' "$U" | head -1 | grep -oE '^[0-9]+')
if [ -n "$ub" ] && [ "$ub" = "$soll" ]; then
    ok "Kern und Ring 3 zaehlen dieselben Eintraege ($ub)"
else
    bad "Kern sagt $soll, /bin/tiling sagt '$ub'"
fi

echo "== 10. die Gegenprobe zur ganzen Runde: ohne 'tile' wie vorher =="
lauf "$K0" "gfx wm wmhold $GRUND" "$TMPD/o.txt" "$DISK"
ws=$(zahl "$TMPD/o.txt" 'wm: .*selftest [0-9]+')
# RUNDE MERGE: die Zahl stand hier als 17 im Quelltext des Laeufers. Der
# Fensterserver hat seitdem zugelegt -- die Runden DESKTOP, TASKBAR,
# DISPLAY und THEME haben eigene Zusagen dazugelegt, `selftest_max()`
# sagt jetzt 30 -- und ein Laeufer, der die alte Zahl festhaelt, meldet
# ab dann jede Runde einen Fehler, den es nicht gibt. Die Frage dieser
# Zeile ist "aendert `tile` etwas am Fensterserver", also wird gegen das
# gemessen, was der Fensterserver ueber sich SELBST sagt.
wsoll=$(grep -aoE 'return [0-9]+' <<< "$(sed -n '/fn selftest_max/,/^}/p' kernel/wm.fi)" \
    | head -1 | grep -oE '[0-9]+')
num "die Zusagen des Fensterservers ueber sich selbst, unveraendert" "$ws" eq "${wsoll:-17}"
has "$TMPD/o.txt" "wm: 800x600" "der Server kennt die Flaeche wie vorher"
has "$TMPD/o.txt" "wm: term win=0" "das Terminalfenster entsteht wie vorher"
hasnot "$TMPD/o.txt" "tile: win=" "und KEIN Fenster geht in den Baum"

echo "TILING: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
