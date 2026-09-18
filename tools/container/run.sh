#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/container/run.sh -- RUNDE O-CONTAINER: DIE ZUSAGEN, NACHGEMESSEN.
#
#   bash tools/container/run.sh
#
# ==================================================================
# WAS HIER GEMESSEN WIRD, UND WARUM JEDE ZUSAGE EINE GEGENPROBE HAT
# ==================================================================
#
# Ein Test, der nichts findet und trotzdem gruen meldet, ist in diesem
# Baum ein Fehler. Die Gefahr ist bei einer Einsperrung besonders gross,
# denn die Zeile
#
#     cat /etc/wirt-geheim      -> zeigt nichts
#
# ist AUCH dann gruen, wenn es die Datei gar nicht gibt, wenn `cat`
# fehlt oder wenn der Kern beim Start stehengeblieben ist. Deshalb steht
# neben jeder Zusage ihre Umkehrung:
#
#   * DIE DATEI GIBT ES WIRKLICH. Derselbe Befehl, aus dem WIRT
#     ausgefuehrt, MUSS ihren Inhalt zeigen. Erst wenn der Wirt
#     `WIRT-GEHEIM-7731` liest und der Container nicht, ist die Schranke
#     gemessen und nicht nur die Abwesenheit einer Datei.
#   * DER CONTAINER LEBT. Er liest im selben Lauf seine EIGENE Datei
#     (`CONTAINER-EIGEN-4242`) unter dem Pfad `/etc/eigen`. Damit ist
#     bewiesen, dass `cat` laeuft, dass das Dateisystem antwortet und
#     dass der Pfad UMGEBOGEN und nicht einfach verworfen wurde.
#   * DIE GRENZE GREIFT WIRKLICH. Der Container fordert mehr Speicher
#     an, als er darf, und MUSS scheitern -- und im selben Lauf fordert
#     er WENIGER an, als er darf, und MUSS Erfolg haben. Eine Grenze,
#     die alles ablehnt, waere sonst ebenso gruen. Dazu die dritte
#     Probe: DERSELBE Aufruf OHNE Grenze muss durchlaufen.
#   * DER WIRT LEBT WEITER. Nach dem gescheiterten Versuch laeuft der
#     Wirt weiter, sagt es, und holt sich SELBST denselben Speicher.
#     Ein Kern, der an der Grenze stehenbleibt oder den Wirt mitsperrt,
#     faellt genau hier auf.
#
# DIE AUSBRUCHSWEGE, die einzeln geprueft werden:
#
#   1. absoluter Pfad          cat /etc/wirt-geheim
#   2. mit zwei Punkten        cat ../../etc/wirt-geheim
#   3. Punkte UEBER die Wurzel hinaus, gemischt
#                              cat /../../../etc/wirt-geheim
#   4. ueber das Arbeitsverzeichnis   cd ..; cat etc/wirt-geheim
#
# Gemessen wie in den Runden 59 bis K17: QEMU je Fall, mit Zeitlimit,
# serielle Ausgabe gegen Erwartungen, Beendigungscode aus
# `isa-debug-exit` (21 = der Kernel hat sich selbst beendet).
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BLOCKS=8192
# `ctr` ist das Werkzeug der Runde, `stress` die Messsonde fuer die
# Speichergrenze. Der Rest ist, was die Drehbuecher unten brauchen.
PROGS="sh cat echo ls cp rm mkdir wc grep head true false ps ctr stress ctrkill"

TMPD=${CT_TMPD:-$(mktemp -d)}
mkdir -p "$TMPD"
[ -n "${CT_TMPD:-}" ] || trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() {
    grep -qaF "$2" "$1" 2>/dev/null \
        && bad "$3 -- '$2' steht da und sollte NICHT" || ok "$3"
}
num() {
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}
# Eine Zahl aus der seriellen Ausgabe, letztes Vorkommen.
zahl() { grep -oaE "$2[0-9]+" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "CONTAINER: uebersprungen, qemu fehlt"; exit 0; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    [ -x "$FIRNC" ] || { echo "CONTAINER: kein firnc"; exit 1; }; }

# ============================================== 1. bauen

echo "== 1. bauen: Kern, Programme, Wurzelplatte =="

KERN="$TMPD/k.mb"
./tools/build-kernel.sh "$KERN" > "$TMPD/build.log" 2>&1 \
    && ok "der Kern steht ($(stat -c%s "$KERN") Oktette)" \
    || { bad "der Kern laesst sich nicht bauen"; tail -20 "$TMPD/build.log"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null
MK=""
gebaut=0
for p in $PROGS; do
    src=kernel/user/$p.fi
    [ -f "$src" ] || continue
    if "$FIRNC" "$src" -o "$TMPD/$p.o" > "$TMPD/$p.log" 2>&1 \
       && ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
              -o "$TMPD/$p" "$TMPD/crt.o" "$TMPD/$p.o" 2>>"$TMPD/$p.log"; then
        MK="$MK /bin/$p=$TMPD/$p"
        gebaut=$((gebaut+1))
    else
        bad "$p laesst sich nicht bauen"
        grep -E '^error' "$TMPD/$p.log" | head -3 | sed 's/^/        /'
    fi
done
num "Programme gebaut" "$gebaut" ge 13
[ -f "$TMPD/ctr" ] && ok "das Werkzeug /bin/ctr ist dabei" \
    || bad "/bin/ctr fehlt -- ohne das Werkzeug misst diese Runde nichts"
[ -f "$TMPD/stress" ] && ok "die Messsonde /bin/stress ist dabei" \
    || bad "/bin/stress fehlt -- ohne sie ist die Speichergrenze nicht messbar"

# ================= DIE BEIDEN DATEIEN, AUF DENEN ALLES BERUHT
#
# `/etc/wirt-geheim` liegt im WIRT und darf aus dem Container NIE
# sichtbar sein. `/c/eins/etc/eigen` liegt IM Container und muss dort
# unter dem Pfad `/etc/eigen` sichtbar sein -- derselbe Pfad, andere
# Datei. Genau dieses Paar unterscheidet "eingesperrt" von "kaputt".
echo 'WIRT-GEHEIM-7731' > "$TMPD/wirt-geheim"
echo 'CONTAINER-EIGEN-4242' > "$TMPD/eigen"
echo 'WIRT-ZWEITER-9002' > "$TMPD/wirt2"

# Die Programme liegen AUCH im Container, unter seinem eigenen /bin --
# sonst faende `ctr exec 1 /bin/cat` nichts, denn /bin des Containers
# ist /c/eins/bin des Wirts. Das ist kein Kunstgriff des Tests, das ist
# genau das, was ein Abbild ausmacht: ein Verzeichnisbaum, der die
# Programme enthaelt, die darin laufen sollen.
CMK=""
for p in cat echo ls ps stress sh ctrkill; do
    [ -f "$TMPD/$p" ] && CMK="$CMK /c/eins/bin/$p=$TMPD/$p"
done
for p in cat echo stress; do
    [ -f "$TMPD/$p" ] && CMK="$CMK /c/zwei/bin/$p=$TMPD/$p"
done

python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ /mnt/ /etc/ /c/ /c/eins/ /c/eins/etc/ /c/eins/bin/ \
    /c/zwei/ /c/zwei/etc/ /c/zwei/bin/ \
    /etc/wirt-geheim="$TMPD/wirt-geheim" \
    /etc/wirt2="$TMPD/wirt2" \
    /c/eins/etc/eigen="$TMPD/eigen" \
    $MK $CMK > "$TMPD/mkfs.log" 2>&1 \
    && ok "die Wurzelplatte steht: $(tail -1 "$TMPD/mkfs.log")" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$TMPD/mkfs.log" | head -8; }

# ============================================== der Laeufer

lauf() { # <name> <kommandozeile>
    local name=$1 app=$2
    shift 2
    cp "$TMPD/root.img" "$TMPD/live-$name.img"
    timeout "${CT_TIMEOUT:-240}" $QEMU_X86 -kernel "$KERN" -m 256 \
        -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot -vga std \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        "$@" -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > /dev/null 2>&1
    RC=$?
}

BASE="osum vfs gfx nosched noproc"

# ============================================== 2. die Gegenprobe zuerst
#
# BEVOR irgendetwas eingesperrt wird: DER WIRT MUSS DIE DATEI LESEN
# KOENNEN. Ohne diesen Abschnitt waere jede Zusage weiter unten wertlos
# -- eine Datei, die es nicht gibt, kann auch niemand lesen.

echo
echo "== 2. GEGENPROBE VORAB: im WIRT ist alles sichtbar =="

lauf wirt "$BASE script=cat /etc/wirt-geheim;cat /etc/wirt2;ctr list"
S="$TMPD/wirt.txt"
num "der Kern beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "WIRT-GEHEIM-7731" "DER WIRT liest /etc/wirt-geheim -- die Datei gibt es"
hat "$S" "WIRT-ZWEITER-9002" "und /etc/wirt2 ebenso"
hat_nicht "$S" "panic" "kein Absturz"
hat_nicht "$S" "EXCEPTION" "keine Ausnahme"

# ============================================== 3. STUFE 1: die Wurzel

echo
echo "== 3. STUFE 1: EIGENE WURZEL -- die vier Ausbruchswege =="

CMD='ctr create eins /c/eins'
CMD="$CMD;ctr list"
# A. DIE EIGENE DATEI -- der Beweis, dass drinnen etwas funktioniert.
CMD="$CMD;ctr exec 1 /bin/cat /etc/eigen"
# B. ABSOLUTER PFAD auf die Datei des Wirts.
CMD="$CMD;ctr exec 1 /bin/cat /etc/wirt-geheim"
# C. MIT ZWEI PUNKTEN.
CMD="$CMD;ctr exec 1 /bin/cat ../../etc/wirt-geheim"
# D. MIT PUNKTEN UEBER DIE WURZEL HINAUS, absolut gemischt.
CMD="$CMD;ctr exec 1 /bin/cat /../../../etc/wirt-geheim"
# E. UEBER DAS ARBEITSVERZEICHNIS: was sieht die Wurzel von innen?
CMD="$CMD;ctr exec 1 /bin/ls /"
CMD="$CMD;echo ctr-wirt-lebt"

lauf wurzel "$BASE script=$CMD"
S="$TMPD/wurzel.txt"
num "der Lauf beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "ctr: angelegt" "der Container wird angelegt"

# DIE ZUSAGE, POSITIV: drinnen ist die EIGENE Datei unter /etc/eigen da.
hat "$S" "CONTAINER-EIGEN-4242" \
    "IM CONTAINER: /etc/eigen ist lesbar -- der Pfad wird UMGEBOGEN, nicht verworfen"

# DIE ZUSAGE, NEGATIV: die Dateien des Wirts sind es NICHT -- auf keinem
# der drei Wege. Das ist die eigentliche Messung der Stufe.
hat_nicht "$S" "WIRT-GEHEIM-7731" \
    "AUSBRUCH GESCHEITERT: /etc/wirt-geheim bleibt unsichtbar (absolut, .., gemischt)"
hat_nicht "$S" "WIRT-ZWEITER-9002" "auch die zweite Datei des Wirts bleibt unsichtbar"

# UND DER WIRT LEBT.
hat "$S" "ctr-wirt-lebt" "der WIRT laeuft nach allen Versuchen weiter"
hat_nicht "$S" "panic" "kein Absturz durch die Ausbruchsversuche"
hat_nicht "$S" "EXCEPTION" "keine Ausnahme"

# ============================================== 4. STUFE 2: der Speicher

echo
echo "== 4. STUFE 2: DIE SPEICHERGRENZE -- sie greift, und der Wirt lebt =="
#
# `stress` fordert Speicher in Bloecken zu je 64 KiB (16 Rahmen) an und
# BERUEHRT jede Seite -- erst das holt die Rahmen wirklich. Die Grenze
# steht auf 64 Rahmen = 256 KiB.
#
# ZWEI MESSUNGEN IN EINEM LAUF: erst UNTER der Grenze (muss GEHEN),
# dann UEBER die Grenze (muss SCHEITERN). Nur beides zusammen misst.

CMD='ctr create eins /c/eins'
CMD="$CMD;ctr set 1 mem 64"
CMD="$CMD;ctr show 1"
# UNTER der Grenze: 2 Bloecke = 32 Rahmen von 64 erlaubten.
CMD="$CMD;ctr exec 1 /bin/stress 2"
# UEBER der Grenze: 6 Bloecke = 96 Rahmen von 64 erlaubten. Muss
# scheitern -- und zwar an der CONTAINERGRENZE: 96 Rahmen liegen unter
# der Architekturgrenze von 112, die `brk` ohnehin setzt.
CMD="$CMD;ctr exec 1 /bin/stress 6"
CMD="$CMD;ctr show 1"
CMD="$CMD;echo ctr-wirt-lebt"
# Und der WIRT holt sich danach selbst denselben Speicher -- haette die
# Grenze den Wirt mitgetroffen, faellt das genau hier auf.
CMD="$CMD;stress 6"
CMD="$CMD;echo ctr-wirt-hat-speicher"

lauf mem "$BASE script=$CMD"
S="$TMPD/mem.txt"
num "der Lauf beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "ctr: mem_limit 64" "die Grenze steht auf 64 Rahmen"

# UNTER der Grenze MUSS es gehen.
hat "$S" "stress: ok 2" \
    "UNTER der Grenze: 32 Rahmen werden vergeben (die Grenze sperrt nicht alles)"
# UEBER der Grenze MUSS es scheitern.
hat "$S" "stress: knapp" \
    "UEBER der Grenze: die Anforderung SCHEITERT sauber (kein Einfrieren)"
# UND DIE ZAHL DES KERNS: der Container hat Abweisungen gezaehlt.
dn=$(zahl "$S" 'ctr: mem_denied ')
num "der Kern hat Abweisungen gezaehlt" "${dn:-0}" ge 1
# Der hoechste Stand darf die Grenze NIE ueberschritten haben.
pk=$(zahl "$S" 'ctr: mem_peak ')
num "der hoechste Stand bleibt unter der Grenze" "${pk:-999}" le 64

# DER WIRT LEBT -- und bekommt selbst noch Speicher.
hat "$S" "ctr-wirt-lebt" "der WIRT laeuft nach dem Scheitern weiter"
# DER WIRT NIMMT SICH 96 RAHMEN -- MEHR, ALS DER CONTAINER DURFTE.
# Die Zahl ist mit Bedacht 6 Bloecke und nicht 40: der `brk`-Bereich
# eines Prozesses ist in diesem Kern 0x40080000..0x400F0000, also
# 448 KiB = 112 Rahmen = 7 Bloecke (`sys.BRK_BASE`, `sys.MMAP_TOP`).
# Ein `stress 40` scheitert deshalb AUCH IM WIRT, und zwar an der
# Adressraumgrenze und nicht an einer Containergrenze -- als Gegenprobe
# waere es wertlos gewesen. 6 Bloecke = 96 Rahmen liegen unter der
# Architekturgrenze und UEBER den 64 Rahmen des Containers: geht das
# durch, hat die Grenze wirklich nur den Container getroffen.
hat "$S" "stress: ok 6" \
    "DER WIRT bekommt 96 Rahmen -- mehr als der Container durfte"
hat "$S" "ctr-wirt-hat-speicher" \
    "und laeuft danach weiter -- die Grenze traf NUR den Container"
hat_nicht "$S" "panic" "kein Absturz an der Speichergrenze"
hat_nicht "$S" "EXCEPTION" "keine Ausnahme an der Speichergrenze"

# ================= DIE DRITTE PROBE: OHNE GRENZE GEHT DASSELBE
#
# Dieselben 6 Bloecke in einem Container OHNE Speichergrenze MUESSEN
# durchlaufen. Ohne diesen Lauf waere "stress: knapp" auch dann gruen,
# wenn die Anforderung auf dieser Maschine grundsaetzlich scheitert --
# es waere dann die MASCHINE gemessen und nicht die GRENZE. Genau das
# ist beim ersten Lauf dieser Runde passiert: die Gegenprobe stand auf
# `stress 40`, und 40 Bloecke scheitern auch im Wirt an der
# Adressraumgrenze von 112 Rahmen. Die Zusage war gruen und mass nichts.
CMD='ctr create zwei /c/zwei'
CMD="$CMD;ctr exec 1 /bin/stress 6"
CMD="$CMD;echo ctr-ohne-grenze-fertig"
lauf memfrei "$BASE script=$CMD"
S="$TMPD/memfrei.txt"
num "der Lauf ohne Grenze beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "stress: ok 6" \
    "GEGENPROBE: OHNE Grenze laufen dieselben 96 Rahmen durch -- es lag an der GRENZE"
hat "$S" "ctr-ohne-grenze-fertig" "und der Lauf kommt zu Ende"

# ============================================== 5. STUFE 3: die Sicht

echo
echo "== 5. STUFE 3: EIGENE PROZESSSICHT =="

#
# ZWEI ZUSAGEN, und beide werden mit ZAHLEN gemessen:
#
#   a) DER WIRT SIEHT MEHR ALS DER CONTAINER. `ctrkill -n` zaehlt die
#      Prozesse, die der Aufrufer ueberhaupt sehen kann. Im Wirt sind
#      das alle, im Container nur die eigenen. Gemessen wird die
#      DIFFERENZ -- eine Zahl, die in beiden Faellen gleich waere,
#      hiesse, dass die Sicht nicht wirkt.
#   b) `kill` UEBER DIE GRENZE SCHEITERT. Der Container schiesst auf
#      pid 1 (den Bootprozess des Wirts, den es immer gibt) und muss
#      abgewehrt werden -- und es muss AUSDRUECKLICH "abgewehrt"
#      dastehen, nicht bloss nichts.

CMD='ctr create eins /c/eins'
# ZUERST DER WIRT: wie viele Prozesse sieht er?
CMD="$CMD;ctrkill -n"
CMD="$CMD;echo ctr-wirt-gezaehlt"
# UND DER CONTAINER: wie viele sieht er?
CMD="$CMD;ctr exec 1 /bin/ctrkill -n"
CMD="$CMD;echo ctr-drin-gezaehlt"
# DER SCHUSS UEBER DIE GRENZE: pid 1 ist der Bootprozess des Wirts.
CMD="$CMD;ctr exec 1 /bin/ctrkill 1"
CMD="$CMD;echo ctr-schuss-fertig"
CMD="$CMD;ctr exec 1 /bin/ps"
CMD="$CMD;echo ctr-ps-fertig"
CMD="$CMD;ps"
CMD="$CMD;ctr show"
CMD="$CMD;echo ctr-wirt-lebt"

lauf sicht "$BASE script=$CMD"
S="$TMPD/sicht.txt"
num "der Lauf beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "ctr-ps-fertig" "ps laeuft im Container durch"
hat "$S" "ctr-wirt-lebt" "und der Wirt lebt danach"
hat "$S" "ctr: escapes " "der Kern fuehrt einen Zaehler abgewehrter Versuche"

# ================= DIE ZAHLEN DER SICHT
#
# `ctrkill: sieht <n>` steht zweimal in der Ausgabe: das erste Mal aus
# dem WIRT, das zweite Mal aus dem CONTAINER.
sieht_wirt=$(grep -oaE 'ctrkill: sieht [0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
sieht_drin=$(grep -oaE 'ctrkill: sieht [0-9]+' "$S" | tail -1 | grep -oE '[0-9]+$')
num "DER WIRT sieht mehrere Prozesse" "${sieht_wirt:-0}" ge 3
num "DER CONTAINER sieht WENIGER als der Wirt" \
    "${sieht_drin:-99}" lt "${sieht_wirt:-0}"
# Und er sieht ueberhaupt etwas -- sich selbst. Eine 0 hiesse, dass
# `pstat` schlicht kaputt ist, und das waere ebenso gruen wie eine
# wirksame Sicht.
num "DER CONTAINER sieht aber SICH SELBST (nicht 0 -- pstat lebt)" \
    "${sieht_drin:-0}" ge 1

# ================= DER SCHUSS UEBER DIE GRENZE
hat "$S" "ctrkill: abgewehrt 1" \
    "KILL UEBER DIE GRENZE: der Container trifft pid 1 des Wirts NICHT"
hat_nicht "$S" "ctrkill: getroffen 1" \
    "und es steht ausdruecklich NICHT 'getroffen' da"
hat "$S" "ctr-schuss-fertig" "der Lauf kommt hinter dem Schuss weiter"
hat "$S" "ctr-wirt-gezaehlt" "die Zaehlung im Wirt lief"
hat "$S" "ctr-drin-gezaehlt" "die Zaehlung im Container lief"

# ============================================== 6. die Einbahnstrassen

echo
echo "== 6. DIE EINBAHNSTRASSEN: Grenzen werden nur kleiner =="
#
# Die Zusage, die diese Runde von `cap.fi` erbt (`rights_restrict` ist
# eine Schnittmenge): eine gesetzte Grenze laesst sich nicht wieder
# oeffnen, und eine Wurzel nicht wieder anheben. AUCH NICHT VOM WIRT --
# sonst waere sie nur so fest wie der naechste Aufruf.

CMD='ctr create eins /c/eins'
CMD="$CMD;ctr set 1 mem 64"
# KLEINER: muss GEHEN.
CMD="$CMD;ctr set 1 mem 32"
CMD="$CMD;echo ctr-kleiner-ok"
# GROESSER: muss SCHEITERN.
CMD="$CMD;ctr set 1 mem 4096"
CMD="$CMD;echo ctr-groesser-versucht"
# UNBEGRENZT: muss ebenfalls SCHEITERN (0 waere die groesste Grenze).
CMD="$CMD;ctr set 1 mem 0"
CMD="$CMD;ctr show 1"
# DIE WURZEL ANHEBEN: muss SCHEITERN, beide Male.
CMD="$CMD;ctr set 1 wurzel /"
CMD="$CMD;ctr set 1 wurzel /c"
CMD="$CMD;ctr list"
CMD="$CMD;echo ctr-wirt-lebt"

lauf einbahn "$BASE script=$CMD"
S="$TMPD/einbahn.txt"
num "der Lauf beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "ctr-kleiner-ok" "KLEINER: 64 -> 32 wird angenommen"
hat "$S" "ctr-groesser-versucht" "der Lauf kommt bis zum Versuch, sie zu oeffnen"
# DIE MESSUNG: die Grenze steht am Ende auf 32 und NICHT auf 4096 oder 0.
lim=$(zahl "$S" 'ctr: mem_limit ')
num "GROESSER wurde ABGELEHNT: die Grenze steht immer noch auf 32" \
    "${lim:-0}" eq 32
hat "$S" "/c/eins" "die Wurzel steht weiter auf /c/eins"
hat_nicht "$S" "panic" "kein Absturz"

# ============================================== 7. der Bericht des Kerns

echo
echo "== 7. die Zahlen, die der KERN selbst meldet =="

cr=$(zahl "$TMPD/einbahn.txt" 'ctr: count ')
num "der Kern zaehlt die angelegten Container" "${cr:-0}" ge 1
esc=$(zahl "$TMPD/einbahn.txt" 'ctr: escapes ')
num "und die abgewehrten Versuche (Grenze oeffnen, Wurzel anheben)" \
    "${esc:-0}" ge 1

# ============================================== Schluss

echo
echo "CONTAINER: $pass passed, $fail failed"
[ -n "${CT_TMPD:-}" ] && echo "  (Arbeitsverzeichnis: $TMPD)"
[ "$fail" -eq 0 ] || exit 1
exit 0
