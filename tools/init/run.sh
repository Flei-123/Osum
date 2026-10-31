#!/usr/bin/env bash
#
# Verwendung:  bash tools/init/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
BLOCKS=8192

NEU="init svc shutdown reboot"
BASIS="sh ls cat echo sleep true false k13t id"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
[ -n "${KEEP_TMPD:-}" ] && trap - EXIT && echo "TMPD=$TMPD"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }
val() { grep -aoE "$2" "$1" | tail -1 | grep -oE '\-?[0-9]+$'; }
sp() {
    local f=$1 name=$2 col=$3 which=${4:-tail}
    grep -aoE "^$name (running|stopped|done|waiting|failed) [0-9]+ [0-9]+ [0-9]+ [0-9]+ [a-z,]+" "$f" \
        | $which -1 | awk -v c="$col" '{print $c}'
}

spn() {
    local f=$1 name=$2 col=$3 n=$4
    grep -aoE "^$name (running|stopped|done|waiting|failed) [0-9]+ [0-9]+ [0-9]+ [0-9]+ [a-z,]+" "$f" \
        | sed -n "${n}p" | awk -v c="$col" '{print $c}'
}

spmax() {
    local f=$1 name=$2 col=$3
    grep -aoE "^$name (running|stopped|done|waiting|failed) [0-9]+ [0-9]+ [0-9]+ [0-9]+ [a-z,]+" "$f" \
        | awk -v c="$col" '{print $c}' | sort -n | tail -1
}

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "INIT: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

# ------------------------------------------------------- die Maschine

ACC=tcg
if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    if qemu-system-x86_64 -accel kvm -m 32 -display none -no-reboot \
            -kernel /bin/true 2>&1 | grep -qi 'kvm'; then ACC=tcg; else ACC=kvm; fi
fi
CPU=""
[ "$ACC" = kvm ] && CPU="-cpu host"
echo "== 0. die Maschine =="
if [ "$ACC" = kvm ]; then
    ok "Beschleunigung: kvm (/dev/kvm, die echte CPU)"
else
    ok "Beschleunigung: tcg (kein benutzbares /dev/kvm)"
fi

# ------------------------------------------------------------- 1. bauen

echo "== 1. bauen: der Kern und $(echo $NEU $BASIS | wc -w) Programme in Ring 3 =="

bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "firnc0 baut den Kern mit /bin/init und dem echten Neustart" \
    || { bad "firnc0 baut den Kern nicht"; sed 's/^/        /' "$TMPD/b0.txt" | head -8; }
[ -f "$TMPD/k0.img" ] || { echo "INIT: $pass passed, $((fail+1)) failed"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s uebersetzt nicht"

build_progs() { # stufe
    local s=$1 cc p rc=0
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    for p in $NEU $BASIS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" >"$TMPD/e$p$s" 2>&1 || {
            bad "firnc$s uebersetzt $p.fi nicht"
            sed 's/^/        /' "$TMPD/e$p$s" | head -6; rc=1; continue; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>/dev/null || {
            bad "firnc$s: ld scheitert an $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return $rc
}
build_progs 0 && ok "firnc0 baut alle $(echo $NEU $BASIS | wc -w) Programme" \
             || bad "firnc0 baut nicht alle Programme"

undef=""
for p in $NEU; do
    u=$(nm -u "$TMPD/${p}0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "kein neues Programm hat ein undefiniertes Symbol" \
               || bad "undefinierte Symbole:$undef"

if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "$(tail -1 "$TMPD/karte.txt")"
else
    bad "der Kartenpruefer schlaegt an"; sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi

# ---------------------------------------------------------- 2. die Faelle

echo "== 2. die Abbilder: /etc/inittab, /etc/ziel, /var/log =="

cat > "$TMPD/inittab" <<'TAB'
# name:ziele:art:befehl:optionen
blink:*:respawn:/bin/sleep 1
kaputt:*:respawn:/bin/false
sauber:*:respawn:/bin/true
proto:*:once:/bin/echo protokoll-zeile:log=/var/log/proto.log
fenster:grafik:respawn:/bin/sleep 60
kons:konsole:respawn:/bin/sleep 60
spaet:*:once:/bin/echo netz-ist-da:netz
alt:respawn:/bin/sleep 60
sh:*:ctrl:/bin/sh
TAB
cat > "$TMPD/inittab2" <<'TAB2'
sh:*:ctrl:/bin/sh
sauber:*:respawn:/bin/true
TAB2
printf 'konsole\n' > "$TMPD/ziel"
printf 'grafik\n'  > "$TMPD/ziel-g"

cat > "$TMPD/dienste.sh" <<'SCRIPT'
echo ==BEGIN==
svc status
echo --SPAETER--
sleep 5
svc status
echo --TAFEL--
svc list
echo --ZIEL--
svc ziel
echo --PROTOKOLL--
cat /var/log/proto.log
echo --STEUER--
svc stop blink
svc start kaputt
sleep 2
svc status
echo --WAISE--
k13t waise
sleep 1
echo ==END==
SCRIPT

cat > "$TMPD/kurz.sh" <<'SCRIPT'
echo ==BEGIN==
sleep 4
svc status
echo ==END==
SCRIPT

SPEC=""
for p in $NEU $BASIS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf@755:0:0"; done
DIRS="/bin/ /etc/ /run/ /var/ /var/log/@755:0:0 /t/"
DATA="/t/dienste.sh=$TMPD/dienste.sh@644:0:0 /t/kurz.sh=$TMPD/kurz.sh@644:0:0"

bau() { # abbild ziel-datei
    python3 tools/osum/mkfs.py build "$1" $BLOCKS $DIRS $SPEC $DATA \
        "/etc/inittab=$TMPD/inittab@644:0:0" \
        "/etc/ziel=$2@644:0:0" > "$TMPD/mkfs.txt" 2>&1
}

bau "$TMPD/d0.img" "$TMPD/ziel" \
    && ok "mkfs.py baut ein Abbild mit /bin/init, /etc/inittab (9 Dienste) und /etc/ziel" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }
bau "$TMPD/dg.img" "$TMPD/ziel-g" \
    && ok "und ein zweites, das sich NUR in /etc/ziel unterscheidet (grafik)" \
    || bad "mkfs.py fehlgeschlagen (grafik)"
python3 tools/osum/mkfs.py build "$TMPD/dn.img" $BLOCKS $DIRS $SPEC $DATA \
    >/dev/null 2>&1 \
    && ok "und ein drittes GANZ OHNE /etc/inittab" \
    || bad "mkfs.py fehlgeschlagen (ohne inittab)"
python3 tools/osum/mkfs.py build "$TMPD/d2.img" $BLOCKS $DIRS $SPEC $DATA \
    "/etc/inittab=$TMPD/inittab2@644:0:0" "/etc/ziel=$TMPD/ziel@644:0:0" \
    >/dev/null 2>&1 \
    && ok "und ein viertes mit genau ZWEI Zeilen -- fuer die Gegenprobe zum Kernfehler" \
    || bad "mkfs.py fehlgeschlagen (zwei Zeilen)"

m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /bin/init)
is "die Rechte von /bin/init im Abbild" "$m" "/bin/init 755 0 0"
m=$(python3 tools/osum/mkfs.py meta "$TMPD/d0.img" /etc/inittab)
is "und die von /etc/inittab" "$m" "/etc/inittab 644 0 0"

# ---------------------------------------------------------- 3. die Laeufe

run_case() { # name abbild anhang zeitlimit [weitere qemu-argumente]
    local name=$1 img=$2 app=$3 limit=$4
    shift 4
    cp "$img" "$TMPD/live-$name.img"
    timeout "$limit" qemu-system-x86_64 -accel "$ACC" $CPU -kernel "$TMPD/k0.img" \
        -m 256 -append "$app" -serial "file:$TMPD/$name.txt" -display none \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    echo $?
}

BASE="nokbd nosched noproc nofs noring3"

echo "== 3. der Lauf: acht Dienste, ein Absturz, ein Ziel =="
rc=$(run_case dienste "$TMPD/d0.img" "osum $BASE script=sh /t/dienste.sh" 300 -no-reboot)
F="$TMPD/dienste.txt"
is "die Maschine faehrt ueber ACPI herunter (QEMU beendet sich mit 0)" "$rc" "0"
has "$F" "osum: pid1 init" "der Kern startet init und nicht die Shell"
is "und der Kern sagt es auch" "$(val "$F" 'init=[0-9]+')" "1"
has "$F" "init: wurzel=1" "init hat die Wurzel nachgeprueft und sie steht"
has "$F" "init: ziel=konsole" "das Ziel kommt aus /etc/ziel"
has "$F" "init: dienste=9" "init liest /etc/inittab und findet neun Dienste"
hasnot "$F" "init: ich bin nicht der Prozess 1" "init IST der Prozess 1"

echo "-- 3a. respawn: der Dienst, der wiederkommt"
first=$(sp "$F" blink 4 head)
later=$(spmax "$F" blink 4)
if [ -n "${later:-}" ] && [ "$later" -gt "${first:-0}" ]; then
    ok "ein Dienst mit respawn wird neu gestartet: $first -> $later Starts"
else bad "der Dienst wurde nicht neu gestartet (${first:-?} -> ${later:-?})"; fi
is "und er hat dabei KEINEN Rueckfall (er endet mit 0)" "$(sp "$F" blink 5 head)" "0"

echo "-- 3b. der Rueckfall-Zaehler: fuenfmal, dann Schluss"
has "$F" "init: abgeschaltet kaputt nach 5 Fehlstarts, 5 Starts" \
    "init schaltet den abstuerzenden Dienst nach genau fuenf Versuchen ab"
is "sein Zustand ist danach 'failed' und nicht 'running'" \
   "$(spn "$F" kaputt 2 2)" "failed"
is "er wurde GENAU fuenfmal gestartet" "$(spn "$F" kaputt 4 2)" "5"
is "und fuenf Rueckfaelle gezaehlt" "$(spn "$F" kaputt 5 2)" "5"
has "$F" "kaputt failed 0 5 5 0" \
    "und die ganze Zeile steht so im Mitschnitt: failed, pid 0, 5 Starts, 5 Fehler"

echo "-- 3c. DIE GEGENPROBE: wer mit 0 endet, wird NIE abgeschaltet"
sauber_n=$(spmax "$F" sauber 4)
if [ -n "${sauber_n:-}" ] && [ "$sauber_n" -gt 5 ]; then
    ok "der Dienst 'sauber' (/bin/true) hat $sauber_n Starts -- mehr als die Grenze"
else bad "'sauber' hat nur ${sauber_n:-?} Starts, die Gegenprobe traegt nicht"; fi
is "und trotzdem null Rueckfaelle" "$(spmax "$F" sauber 5)" "0"
if grep -qa "^sauber failed" "$F"; then
    bad "'sauber' wurde abgeschaltet -- die Grenze trifft das Falsche"
else ok "'sauber' wurde NICHT abgeschaltet: $(spn "$F" sauber 2 2)"; fi

echo "-- 3d. das Ziel: was nicht dazugehoert, laeuft nicht"
is "der grafische Dienst steht still" "$(sp "$F" fenster 2 tail)" "stopped"
is "und wurde NULL mal gestartet -- in KEINER Ausgabe" "$(spmax "$F" fenster 4)" "0"
is "sein Ziel steht in der Zeile" "$(sp "$F" fenster 7 head)" "grafik"
is "und der konsolen-eigene Dienst laeuft" "$(sp "$F" kons 2 tail)" "running"

echo "-- 3e. erst nach dem Netz"
is "der Dienst mit 'netz' wartet, weil dieser Lauf keine Karte hat" \
   "$(sp "$F" spaet 2 tail)" "waiting"
is "und wurde NULL mal gestartet -- in KEINER Ausgabe" "$(spmax "$F" spaet 4)" "0"
hasnot "$F" "netz-ist-da" "seine Zeile steht folglich nirgends"

echo "-- 3f. das alte Format von K13"
is "eine Zeile 'name:art:befehl' laeuft weiter" "$(sp "$F" alt 2 tail)" "running"
is "und sie gilt fuer JEDES Ziel" "$(sp "$F" alt 7 head)" "konsole,grafik"

echo "-- 3g. die Protokolldatei"
has "$F" "protokoll-zeile" "die Zeile des Dienstes 'proto' steht in /var/log/proto.log"
n=$(grep -ac 'protokoll-zeile' "$F")
is "und zwar GENAU EINMAL -- sie ging nicht auch auf die Konsole" "$n" "1"

echo "-- 3h. svc: die Tafel und der Handgriff"
has "$F" "DIENST           ZUSTAND   PID  STARTS  FEHLER  LAUFZEIT  ZIEL" \
    "svc list zeigt eine Tafel mit Laufzeit und Neustarts"
has "$F" "Dienste laufen" "und darunter, wieviele von wievielen laufen"
is "svc stop haelt einen Dienst an" "$(sp "$F" blink 2 tail)" "done"
kn=$(sp "$F" kaputt 4 tail)
if [ -n "${kn:-}" ] && [ "$kn" -gt 5 ]; then
    ok "svc start hebt die Abschaltung auf: $kn Starts statt der fuenf, bei denen es stand"
else bad "svc start hat den abgeschalteten Dienst nicht wieder angefasst (${kn:-?})"; fi
if grep -qa "init: abgeschaltet kaputt nach 5 Fehlstarts, 10 Starts" "$F"; then
    ok "und die Grenze greift danach ein ZWEITES Mal -- fuenf neue Versuche, dann wieder aus"
else
    bad "nach dem Handgriff greift die Grenze nicht noch einmal"
fi

echo "-- 3i. Waisen und Leichen"
is "DIE WAISE FAELLT AN DEN PROZESS 1 und wird eingesammelt" \
   "$(val "$F" 'init: orphans=[0-9]+')" "1"
is "und am Ende steht keine Leiche mehr" "$(val "$F" 'zombies=[0-9]+')" "0"
has "$F" "power: acpi pm1a=" "die Abschaltung liest FADT und _S5_ aus der ACPI-Tafel"

echo "-- 3j. DER KERNFEHLER, DEN DIESE RUNDE GEFUNDEN HAT"
rc=$(run_case zweizeilen "$TMPD/d2.img" "osum $BASE script=sh /t/kurz.sh" 200 -no-reboot)
Z="$TMPD/zweizeilen.txt"
zn=$(spmax "$Z" sauber 4)
is "behoben: die Maschine kommt sauber herunter" "$rc" "0"
if [ -n "${zn:-}" ] && [ "$zn" -gt 5 ]; then
    ok "behoben: der Dienst wurde $zn mal gestartet und jedes Mal eingesammelt"
else bad "behoben: nur ${zn:-?} Starts -- die Messung taugt so nicht"; fi
is "und am Ende steht keine Leiche" "$(val "$Z" 'zombies=[0-9]+')" "0"

rc=$(run_case waitfirst "$TMPD/d2.img" "osum waitfirst $BASE script=sh /t/kurz.sh" 200 -no-reboot)
WF="$TMPD/waitfirst.txt"
wn=$(spmax "$WF" sauber 4)
if [ -n "${wn:-}" ] && [ "$wn" -le 2 ]; then
    ok "GEGENPROBE waitfirst: derselbe Dienst bleibt bei $wn Starts stehen (behoben: $zn)"
else bad "GEGENPROBE waitfirst traegt nicht: ${wn:-?} Starts gegen $zn"; fi
is "und er meldet sich weiter als 'running', obwohl er tot ist" \
   "$(sp "$WF" sauber 2 tail)" "running"
wr=$(val "$WF" 'init: reaped=[0-9]+')
zr=$(val "$Z" 'init: reaped=[0-9]+')
if [ -n "${wr:-}" ] && [ -n "${zr:-}" ] && [ "$wr" -le 2 ] && [ "$zr" -gt "$wr" ]; then
    ok "und init hat im GANZEN Lauf nur $wr Kinder eingesammelt -- behoben waren es $zr"
else bad "die Zahl der eingesammelten Kinder trennt die beiden Laeufe nicht (${wr:-?} gegen ${zr:-?})"; fi

echo "== 4. DIE GEGENPROBE ZUM ZIEL: derselbe Baum mit /etc/ziel=grafik =="
rc=$(run_case grafik "$TMPD/dg.img" "osum $BASE script=sh /t/kurz.sh" 300 -no-reboot)
G="$TMPD/grafik.txt"
has "$G" "init: ziel=grafik" "das Ziel ist ein anderes"
is "JETZT laeuft der grafische Dienst" "$(sp "$G" fenster 2 head)" "running"
gs=$(spmax "$G" fenster 4)
if [ -n "${gs:-}" ] && [ "$gs" -ge 1 ]; then
    ok "und wurde $gs mal gestartet -- im Lauf davor war es null"
else bad "'fenster' wurde auch mit ziel=grafik nicht gestartet"; fi
is "und JETZT steht der konsolen-eigene still" "$(sp "$G" kons 2 head)" "stopped"
is "mit null Starts -- im Lauf davor lief er" "$(spmax "$G" kons 4)" "0"

echo "== 5. herunterfahren und neu starten =="
rc=$(run_case runter "$TMPD/d0.img" "osum $BASE script=shutdown" 300 -no-reboot)
R="$TMPD/runter.txt"
is "/bin/shutdown: QEMU beendet sich mit 0, also ueber ACPI" "$rc" "0"
has "$R" "init: herunterfahren" "init hat es getan und nicht das Programm selbst"
has "$R" "power: acpi pm1a=" "und zwar ueber die ACPI-Tafel"
hasnot "$R" "shutdown: init antwortet nicht" "init hat rechtzeitig geantwortet"

rc=$(run_case neu "$TMPD/d0.img" "osum $BASE script=reboot" 300 -no-reboot)
N="$TMPD/neu.txt"
is "/bin/reboot: QEMU beendet sich mit 0" "$rc" "0"
has "$N" "init: neustart" "init unterscheidet den Neustart vom Ausschalten"
if grep -qaE 'power: reset (fadt|0xCF9|8042)' "$N"; then
    ok "und der Kern hat wirklich ein RESET ausgeloest: $(grep -aoE 'power: reset [^ ]*' "$N" | tail -1)"
else
    bad "kein 'power: reset ...' im Mitschnitt -- es war kein Neustart"
fi
hasnot "$N" "power: acpi pm1a=" "und KEINE Abschaltung -- die beiden Wege sind getrennt"

echo "-- 5a. DER EHRLICHSTE BEWEIS: die Maschine kommt wirklich zurueck"
cp "$TMPD/d0.img" "$TMPD/live-wieder.img"
W="$TMPD/wieder.txt"
: > "$W"
timeout 240 qemu-system-x86_64 -accel "$ACC" $CPU -kernel "$TMPD/k0.img" \
    -m 256 -append "osum $BASE script=reboot" -serial "file:$W" -display none \
    -drive "file=$TMPD/live-wieder.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
qpid=$!
for _ in $(seq 1 240); do
    b=$(grep -ac 'osum: pid1 init' "$W" 2>/dev/null || true)
    [ "${b:-0}" -ge 2 ] && break
    kill -0 "$qpid" 2>/dev/null || break
    sleep 1
done
pkill -f "live-wieder.img" >/dev/null 2>&1
kill "$qpid" >/dev/null 2>&1
wait "$qpid" 2>/dev/null
b=$(grep -ac 'osum: pid1 init' "$W" 2>/dev/null || true)
if [ "${b:-0}" -ge 2 ]; then
    ok "der Kernel kam $b mal hoch -- der Neustart war ein echter Neustart"
else bad "der Kernel kam nur ${b:-0} mal hoch; ein 'halt' saehe genauso aus"; fi

echo "== 6. die Gegenproben =="
rc=$(run_case noacpi "$TMPD/d0.img" "osum noacpi $BASE script=shutdown" 300 -no-reboot)
is "GEGENPROBE noacpi: derselbe Lauf endet ueber den Pruefstand (21) statt ueber ACPI (0)" \
   "$rc" "21"

rc=$(run_case keintab "$TMPD/dn.img" "osum $BASE script=id" 300 -no-reboot)
K="$TMPD/keintab.txt"
has "$K" "osum: pid1 init" "GEGENPROBE ohne /etc/inittab: der Kern startet init trotzdem"
has "$K" "init: /etc/inittab fehlt" "und init sagt, was fehlt, statt still zu enden"
is "und gibt 1 zurueck" "$(val "$K" 'osum: sh exit=[0-9]+')" "1"

rc=$(run_case initsh "$TMPD/d0.img" "osum initsh $BASE script=id" 300 -no-reboot)
I="$TMPD/initsh.txt"
is "DER NOTWEG: mit initsh endet der Lauf wie vor dieser Runde" "$rc" "21"
hasnot "$I" "osum: pid1 init" "und zwar mit /bin/sh statt init"
has "$I" "uid=0 gid=0 euid=0 egid=0" "das System ist damit vollstaendig benutzbar"

# ------------------------------------------------------ 7. firnc1

echo "== 7. der zweite Uebersetzer =="
if build_progs 1; then
    ok "firnc1 baut dieselben $(echo $NEU $BASIS | wc -w) Programme"
    SPEC1=""
    for p in $NEU $BASIS; do SPEC1="$SPEC1 /bin/$p=$TMPD/${p}1.elf@755:0:0"; done
    python3 tools/osum/mkfs.py build "$TMPD/d1.img" $BLOCKS $DIRS $SPEC1 $DATA \
        "/etc/inittab=$TMPD/inittab@644:0:0" \
        "/etc/ziel=$TMPD/ziel@644:0:0" >/dev/null 2>&1
    rc=$(run_case stufe1 "$TMPD/d1.img" "osum $BASE script=sh /t/kurz.sh" 300 -no-reboot)
    S="$TMPD/stufe1.txt"
    is "die Programme von firnc1 fahren dieselbe Maschine herunter" "$rc" "0"
    has "$S" "init: dienste=9" "und ihr init liest dieselbe Tafel"
    is "und schaltet denselben Dienst ab" "$(sp "$S" kaputt 2 tail)" "failed"
else
    bad "firnc1 baut die Programme nicht"
fi

echo
echo "INIT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
