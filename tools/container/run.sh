#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/container/run.sh -- RUNDE O-CONTAINER: DIE ZUSAGEN, NACHGEMESSEN.
#
#   bash tools/container/run.sh
#
#     cat /etc/wirt-geheim      -> zeigt nichts
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
BLOCKS=8192
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

echo 'WIRT-GEHEIM-7731' > "$TMPD/wirt-geheim"
echo 'CONTAINER-EIGEN-4242' > "$TMPD/eigen"
echo 'WIRT-ZWEITER-9002' > "$TMPD/wirt2"

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

echo
echo "== 2. GEGENPROBE VORAB: im WIRT ist alles sichtbar =="

lauf wirt "$BASE script=cat /etc/wirt-geheim;cat /etc/wirt2;ctr list"
S="$TMPD/wirt.txt"
num "der Kern beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "WIRT-GEHEIM-7731" "DER WIRT liest /etc/wirt-geheim -- die Datei gibt es"
hat "$S" "WIRT-ZWEITER-9002" "und /etc/wirt2 ebenso"
hat_nicht "$S" "panic" "kein Absturz"
hat_nicht "$S" "EXCEPTION" "keine Ausnahme"

echo
echo "== 3. STUFE 1: EIGENE WURZEL -- die vier Ausbruchswege =="

CMD='ctr create eins /c/eins'
CMD="$CMD;ctr list"
CMD="$CMD;ctr exec 1 /bin/cat /etc/eigen"
CMD="$CMD;ctr exec 1 /bin/cat /etc/wirt-geheim"
CMD="$CMD;ctr exec 1 /bin/cat ../../etc/wirt-geheim"
CMD="$CMD;ctr exec 1 /bin/cat /../../../etc/wirt-geheim"
CMD="$CMD;ctr exec 1 /bin/ls /"
CMD="$CMD;echo ctr-wirt-lebt"

lauf wurzel "$BASE script=$CMD"
S="$TMPD/wurzel.txt"
num "der Lauf beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "ctr: angelegt" "der Container wird angelegt"

hat "$S" "CONTAINER-EIGEN-4242" \
    "IM CONTAINER: /etc/eigen ist lesbar -- der Pfad wird UMGEBOGEN, nicht verworfen"

hat_nicht "$S" "WIRT-GEHEIM-7731" \
    "AUSBRUCH GESCHEITERT: /etc/wirt-geheim bleibt unsichtbar (absolut, .., gemischt)"
hat_nicht "$S" "WIRT-ZWEITER-9002" "auch die zweite Datei des Wirts bleibt unsichtbar"

hat "$S" "ctr-wirt-lebt" "der WIRT laeuft nach allen Versuchen weiter"
hat_nicht "$S" "panic" "kein Absturz durch die Ausbruchsversuche"
hat_nicht "$S" "EXCEPTION" "keine Ausnahme"

echo
echo "== 4. STUFE 2: DIE SPEICHERGRENZE -- sie greift, und der Wirt lebt =="
#

CMD='ctr create eins /c/eins'
CMD="$CMD;ctr set 1 mem 64"
CMD="$CMD;ctr show 1"
CMD="$CMD;ctr exec 1 /bin/stress 2"
CMD="$CMD;ctr exec 1 /bin/stress 6"
CMD="$CMD;ctr show 1"
CMD="$CMD;echo ctr-wirt-lebt"
CMD="$CMD;stress 6"
CMD="$CMD;echo ctr-wirt-hat-speicher"

lauf mem "$BASE script=$CMD"
S="$TMPD/mem.txt"
num "der Lauf beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "ctr: mem_limit 64" "die Grenze steht auf 64 Rahmen"

hat "$S" "stress: ok 2" \
    "UNTER der Grenze: 32 Rahmen werden vergeben (die Grenze sperrt nicht alles)"
hat "$S" "stress: knapp" \
    "UEBER der Grenze: die Anforderung SCHEITERT sauber (kein Einfrieren)"
dn=$(zahl "$S" 'ctr: mem_denied ')
num "der Kern hat Abweisungen gezaehlt" "${dn:-0}" ge 1
pk=$(zahl "$S" 'ctr: mem_peak ')
num "der hoechste Stand bleibt unter der Grenze" "${pk:-999}" le 64

hat "$S" "ctr-wirt-lebt" "der WIRT laeuft nach dem Scheitern weiter"
hat "$S" "stress: ok 6" \
    "DER WIRT bekommt 96 Rahmen -- mehr als der Container durfte"
hat "$S" "ctr-wirt-hat-speicher" \
    "und laeuft danach weiter -- die Grenze traf NUR den Container"
hat_nicht "$S" "panic" "kein Absturz an der Speichergrenze"
hat_nicht "$S" "EXCEPTION" "keine Ausnahme an der Speichergrenze"

CMD='ctr create zwei /c/zwei'
CMD="$CMD;ctr exec 1 /bin/stress 6"
CMD="$CMD;echo ctr-ohne-grenze-fertig"
lauf memfrei "$BASE script=$CMD"
S="$TMPD/memfrei.txt"
num "der Lauf ohne Grenze beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "stress: ok 6" \
    "GEGENPROBE: OHNE Grenze laufen dieselben 96 Rahmen durch -- es lag an der GRENZE"
hat "$S" "ctr-ohne-grenze-fertig" "und der Lauf kommt zu Ende"

echo
echo "== 5. STUFE 3: EIGENE PROZESSSICHT =="

CMD='ctr create eins /c/eins'
CMD="$CMD;ctrkill -n"
CMD="$CMD;echo ctr-wirt-gezaehlt"
CMD="$CMD;ctr exec 1 /bin/ctrkill -n"
CMD="$CMD;echo ctr-drin-gezaehlt"
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

sieht_wirt=$(grep -oaE 'ctrkill: sieht [0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
sieht_drin=$(grep -oaE 'ctrkill: sieht [0-9]+' "$S" | tail -1 | grep -oE '[0-9]+$')
num "DER WIRT sieht mehrere Prozesse" "${sieht_wirt:-0}" ge 3
num "DER CONTAINER sieht WENIGER als der Wirt" \
    "${sieht_drin:-99}" lt "${sieht_wirt:-0}"
num "DER CONTAINER sieht aber SICH SELBST (nicht 0 -- pstat lebt)" \
    "${sieht_drin:-0}" ge 1

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

CMD='ctr create eins /c/eins'
CMD="$CMD;ctr set 1 mem 64"
CMD="$CMD;ctr set 1 mem 32"
CMD="$CMD;echo ctr-kleiner-ok"
# GROESSER: muss SCHEITERN.
CMD="$CMD;ctr set 1 mem 4096"
CMD="$CMD;echo ctr-groesser-versucht"
CMD="$CMD;ctr set 1 mem 0"
CMD="$CMD;ctr show 1"
CMD="$CMD;ctr set 1 wurzel /"
CMD="$CMD;ctr set 1 wurzel /c"
CMD="$CMD;ctr list"
CMD="$CMD;echo ctr-wirt-lebt"

lauf einbahn "$BASE script=$CMD"
S="$TMPD/einbahn.txt"
num "der Lauf beendet sich selbst (21)" "${RC:-99}" eq 21
hat "$S" "ctr-kleiner-ok" "KLEINER: 64 -> 32 wird angenommen"
hat "$S" "ctr-groesser-versucht" "der Lauf kommt bis zum Versuch, sie zu oeffnen"
lim=$(zahl "$S" 'ctr: mem_limit ')
num "GROESSER wurde ABGELEHNT: die Grenze steht immer noch auf 32" \
    "${lim:-0}" eq 32
hat "$S" "/c/eins" "die Wurzel steht weiter auf /c/eins"
hat_nicht "$S" "panic" "kein Absturz"

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
