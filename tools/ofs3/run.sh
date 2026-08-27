#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ofs3/run.sh -- RUNDE OFS3: DER DECKEL, DEN NIEMAND AUFGESCHRIEBEN HAT.
#
# Was diese Runde behebt, stand seit Runde 62 im Quelltext und in keiner
# Roadmap: `kernel/fs.fi` hatte EINEN Block Blockkarte. Ein Block sind
# 512 Oktette, also 4096 Bits, also 4096 Bloecke -- ZWEI MEGAOKTETT je
# Platte. Und dahinter sass ein zweiter Deckel, der noch weniger
# aufgefallen ist: `kmain.fi` meldete die Wurzelplatte mit der KONSTANTEN
# `OSUM_BLOCKS = 4096` an, ganz gleich, wie gross sie wirklich war.
# Selbst eine mehrblockige Karte haette daran nichts geaendert.
#
# Die Regel dieses Projekts ist, dass eine Eigenschaft ohne Gegenprobe
# eine Behauptung ist. Jeder Punkt hier hat deshalb eine zweite Messung,
# die FALLEN muss:
#
#   1. DIE PLATTE. Ein Abbild von vier Gibioktett wird gebaut, gebootet
#      und von `df` gezaehlt. Gegenprobe: dieselben Programme auf einer
#      Platte der Fassung 2 -- dort bleibt alles beim Alten.
#   2. DIE DATEI. `/bin/ofs3` schreibt in Ring 3 ueber die alte Grenze
#      von 2.134.016 Oktetten hinaus und liest an drei Stellen zurueck.
#      Der Sollwert an jeder Stelle ist AUS DER STELLE AUSGERECHNET --
#      ein falscher Block faellt damit auf, statt eine Null zu liefern,
#      die wie eine Null aussieht.
#   3. DER WEITE BLOCK. Ein Abbild, dessen erste 200.000 Datenbloecke von
#      Hand belegt sind; die Datei darin liegt an einer Blocknummer, fuer
#      die es in Fassung 2 kein Bit gab. Der Kern liest sie, schreibt sie
#      neu, und der WIRT prueft nach, was wirklich auf der Platte steht.
#   4. DER NAME. 255 Zeichen, angelegt, wiedergefunden, ueber `getdents`
#      in voller Laenge zurueck. Gegenprobe: dieselbe Datei auf einer
#      Platte in Fassung 2 -- dort passt der Name nicht.
#   5. DIE ZEIT. Eine frische Datei traegt eine Zeit ungleich null, ein
#      Schreiben hebt sie, und sie steht NACH EINEM NEUSTART noch da.
#      Gegenprobe: dieselbe Zeile auf einer Platte der Fassung 2 zeigt
#      die Null von 1970.
#   6. UMBENENNEN OHNE KOPIEREN. Die Inodenummer vor und nach `rename`
#      ist dieselbe.
#   7. DER SYMBOLISCHE VERWEIS. Anlegen, `readlink`, hindurchlesen,
#      `lstat` sieht `l` und `stat` sieht die Datei. Gegenprobe: mit dem
#      Wort `nolinks` folgt der Kern keinem Verweis mehr.
#   8. DIE ALTEN ABBILDER. Fassung 1 und Fassung 2 booten weiter, und
#      ihre Vorgabe hat sich nicht um ein Oktett verschoben.
#
# Gemessen wie in jeder Runde davor: QEMU je Fall, mit Zeitlimit,
# serielle Ausgabe gegen die Erwartung, Rueckgabewert aus
# `isa-debug-exit` (21 = der Kern hat selbst abgeschaltet).
#
# Benutzung:  bash tools/ofs3/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo rm ofs3 ln touch df find tar mv sleep"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name value op expected
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }
# eine `ofs3: <name> = <zahl>`-Zeile
val3() { tr -d '\000' < "$1" | grep -a "^ofs3: $2 = " | head -1 | sed 's/.* = //'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "OFS3: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

# --------------------------------------------------------------- laufen
run_disk() { # kernel append out disk
    local image=$1 append=$2 out=$3 disk=$4
    cp --sparse=always "$disk" "$TMPD/live.img"
    timeout 600 qemu-system-x86_64 -kernel "$image" -m 512 -append "$append" \
        -serial "file:$out" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    local rc=$?
    # der Zustand der Platte NACH dem Lauf -- der Wirt sieht ihn sich an
    cp --sparse=always "$TMPD/live.img" "$TMPD/after.img"
    return $rc
}
# ZWEI LAEUFE AUF DERSELBEN PLATTE. Das ist der einzige Weg, "es steht
# nach einem Neustart noch da" zu messen: der zweite Lauf bekommt genau
# die Oktette, die der erste hinterlassen hat.
run_again() { # kernel append out
    timeout 600 qemu-system-x86_64 -kernel "$1" -m 512 -append "$2" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

echo "== 1. bauen =="
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/$f.s" 2>"$TMPD/as.err" \
        || { bad "$f.s laesst sich nicht assemblieren"; sed 's/^/        /' "$TMPD/as.err" | head -5; }
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
"$FIRNC" kernel/kmain.fi -o "$TMPD/k.o" >"$TMPD/e" 2>&1 \
    || { bad "der Kern uebersetzt nicht"; sed 's/^/        /' "$TMPD/e" | head -10; \
         echo "OFS3: $pass bestanden, $fail gescheitert"; exit 1; }
"$FIRNC" kernel/uprog.fi -o "$TMPD/u.o" >>"$TMPD/e" 2>&1 || bad "uprog.fi"
ld -n -T "$LDSCRIPT" \
    --defsym=KERNEL_MAIN="_F0.kernel_main" \
    --defsym=KERNEL_TRAP="_F0.trap__entry" \
    --defsym=KERNEL_SYSCALL="_F0.sys__entry" \
    --defsym=KERNEL_TASK_MAIN="_F0.tasks__main" \
    --defsym=KERNEL_USER_START="_F0.proc__user_start" \
    --defsym=KERNEL_AP_MAIN="_F0.smp__ap_main" \
    --defsym=USER_MAIN="_F0.u_enter" \
    -o "$TMPD/k.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
    "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k.o" "$TMPD/u.o" 2>"$TMPD/ld.err" \
    || { bad "ld"; grep -v 'GNU-stack\|RWX\|deprecated' "$TMPD/ld.err" | head -5; }
objcopy -O elf32-i386 "$TMPD/k.elf" "$TMPD/k.mb" 2>/dev/null
ok "Kern gebaut und zu einem Multiboot-Abbild gemacht ($(stat -c%s "$TMPD/k.mb") Oktette)"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$p.fi uebersetzt nicht"; sed 's/^/        /' "$TMPD/e$p" | head -6; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
done
ok "$(echo $PROGS | wc -w) Programme gebaut, darunter das neue /bin/ofs3 und /bin/ln"

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
QUIET="nokbd nosched noproc nofs noring3"

echo
echo "== 2. was der Wirt ueber das Format sagt =="
python3 tools/osum/mkfs.py build "$TMPD/v2.img" 4096 $SPEC /tmp/ > "$TMPD/m2.txt" 2>&1 \
    || bad "mkfs Fassung 2"
python3 tools/osum/mkfs.py build "$TMPD/v1.img" 4096 --v1 /bin/ /bin/sh="$TMPD/sh.elf" \
    /bin/ls="$TMPD/ls.elf" > "$TMPD/m1.txt" 2>&1 || bad "mkfs Fassung 1"
python3 tools/osum/mkfs.py build "$TMPD/v3.img" 131072 --v3 --inodes=1024 \
    --time=1780000000 $SPEC /tmp/ > "$TMPD/m3.txt" 2>&1 || bad "mkfs Fassung 3"
cat "$TMPD/m1.txt" "$TMPD/m2.txt" "$TMPD/m3.txt" | sed 's/^/        /'
# DIE VORGABE HAT SICH NICHT VERSCHOBEN. Ohne `--v3` ist alles wie vorher
# -- Karte ein Block, Inode 128, Eintrag 32, Name 24, Daten ab Block 34.
has "$TMPD/m2.txt" "version=2 bmblocks=1 isize=128 dirent=32 namelen=24" \
    "ohne --v3 baut mkfs weiter GENAU die Fassung 2"
has "$TMPD/m2.txt" "data=34" "und der Datenbereich faengt weiter bei Block 34 an"
has "$TMPD/m1.txt" "version=1 bmblocks=1 isize=128 dirent=32 namelen=24" \
    "und --v1 weiter genau die Fassung 1"
has "$TMPD/m3.txt" "version=3 bmblocks=32 isize=256 dirent=264 namelen=256" \
    "--v3: 32 Kartenbloecke, Inode 256, Eintrag 264, Name 256"
mf2=$(grep -oa 'maxfile=[0-9]*' "$TMPD/m2.txt" | cut -d= -f2)
mf3=$(grep -oa 'maxfile=[0-9]*' "$TMPD/m3.txt" | cut -d= -f2)
num "groesste Datei in Fassung 2 (Oktette)" "$mf2" eq 2134016
num "groesste Datei in Fassung 3 (Oktette)" "$mf3" eq 136351744
# Zwei gleiche Laeufe geben dasselbe Abbild -- die Zusage aus K15, und
# sie gilt fuer die neue Fassung genauso.
python3 tools/osum/mkfs.py build "$TMPD/v3b.img" 131072 --v3 --inodes=1024 \
    --time=1780000000 $SPEC /tmp/ >/dev/null 2>&1
cmp -s "$TMPD/v3.img" "$TMPD/v3b.img" \
    && ok "zweimal gebaut gibt Oktett fuer Oktett dasselbe Abbild" \
    || bad "zwei Laeufe von mkfs --v3 geben verschiedene Abbilder"
rm -f "$TMPD/v3b.img"

echo
echo "== 3. die Zusagen der Runde, in Ring 3 gemessen =="
run_disk "$TMPD/k.mb" "osum vfs $QUIET script=ofs3;exit" "$TMPD/o3.txt" "$TMPD/v3.img"
rc=$?
O="$TMPD/o3.txt"
[ "$rc" -eq 21 ] && ok "der Kern hat selbst abgeschaltet (exit 21)" \
                 || { bad "QEMU exit $rc, erwartet 21"; tail -8 "$O" | tr -d '\000' | sed 's/^/        /'; }
has "$O" "osum: mount=1" "der Kern haengt ein Abbild der Fassung 3 ein"
has "$O" "k13: ofsver=3" "und er sagt selbst, dass es Fassung 3 ist"

# --- die grosse Datei
g=$(val3 "$O" grossdatei)
num "geschriebene Oktette in EINE Datei" "$g" gt 2134016
num "und es sind die vollen 2,5 MiB" "$g" eq 2396160
num "richtige Oktette am Anfang der Datei (von 512)" "$(val3 "$O" lesen1)" eq 512
num "richtige Oktette HINTER der alten Grenze (von 512)" "$(val3 "$O" lesen2)" eq 512
num "richtige Oktette ganz am Ende (von 512)" "$(val3 "$O" lesen3)" eq 512

# --- der lange Name
num "Laenge des angelegten Namens" "$(val3 "$O" namelen)" eq 255
num "der Name liess sich anlegen und wiederfinden" "$(val3 "$O" nameok)" eq 1
num "und er kam ueber getdents in voller Laenge zurueck" "$(val3 "$O" dentlen)" eq 255

# --- die Zeit
c=$(val3 "$O" ctime); m0=$(val3 "$O" mtime0); m1=$(val3 "$O" mtime1)
num "Erzeugungszeit einer frischen Datei" "$c" gt 1700000000
num "Aenderungszeit einer frischen Datei" "$m0" gt 1700000000
num "und nach dem zweiten Schreiben ist sie hoeher" "$m1" gt "${m0:-0}"

# --- der Verweis
num "symlink() hat einen Verweis angelegt" "$(val3 "$O" linkok)" eq 1
num "readlink() gibt die Laenge des Ziels (/tmp/zeit)" "$(val3 "$O" linklen)" eq 9
num "lstat sieht den VERWEIS" "$(val3 "$O" linklstat)" eq 1
num "stat sieht die DATEI dahinter" "$(val3 "$O" linkstat)" eq 1
num "und durch den Verweis hindurch lesen geht" "$(val3 "$O" linkread)" eq 1

# --- umbenennen
num "rename() kam ohne Fehler zurueck" "$(val3 "$O" rename)" eq 0
i1=$(val3 "$O" ino1); i2=$(val3 "$O" ino2)
if [ -n "$i1" ] && [ "$i1" = "$i2" ] && [ "$i1" != 0 ]; then
    ok "UMBENANNT UND NICHT KOPIERT: dieselbe Inode vor und nach rename ($i1)"
else
    bad "rename: Inode vorher $i1, nachher $i2"
fi

# --- viele Dateien
num "Dateien in einem Verzeichnis mit 255-Zeichen-Eintraegen" "$(val3 "$O" viele)" eq 120
num "das Pruefprogramm ist bis zum Ende gekommen" "$(val3 "$O" ende)" eq 1
has "$O" "kernel: done" "und der Kern auch"

echo
echo "== 4. GEGENPROBE: dasselbe Programm auf einer Platte der Fassung 2 =="
run_disk "$TMPD/k.mb" "osum vfs $QUIET script=ofs3;exit" "$TMPD/o2.txt" "$TMPD/v2.img"
rc=$?
Z="$TMPD/o2.txt"
[ "$rc" -eq 21 ] && ok "auch der alte Datentraeger laeuft bis zum Ende (exit 21)" \
                 || bad "Fassung-2-Lauf: exit $rc"
has "$Z" "k13: ofsver=2" "der Kern erkennt die Fassung 2"
num "der lange Name geht dort NICHT" "$(val3 "$Z" nameok)" eq 0
num "und die Zeitstempel sind dort null" "$(val3 "$Z" ctime)" eq 0
num "auch die Aenderungszeit ist null" "$(val3 "$Z" mtime0)" eq 0

echo
echo "== 5. DIE PLATTE: vier Gibioktett =="
# Der Wirt baut sie als Loch -- 4 GiB Adressraum, ein Megaoktett auf der
# Platte des Wirts. Was zaehlt, ist was der KERN daraus macht.
python3 tools/osum/mkfs.py build "$TMPD/4g.img" 8388608 --v3 --inodes=256 \
    --time=1780000000 $SPEC /tmp/ > "$TMPD/m4g.txt" 2>&1 || bad "mkfs 4 GiB"
sed 's/^/        /' "$TMPD/m4g.txt"
has "$TMPD/m4g.txt" "blocks=8388608" "der Wirt baut ein Abbild von 8.388.608 Bloecken (4 GiB)"
has "$TMPD/m4g.txt" "bmblocks=2048" "seine Blockkarte ist 2048 Bloecke gross (1 MiB, 0,02 % der Platte)"
echo "        auf dem Wirt: $(du -h --apparent-size "$TMPD/4g.img" | cut -f1) angemeldet, $(du -h "$TMPD/4g.img" | cut -f1) belegt"
run_disk "$TMPD/k.mb" "osum vfs $QUIET script=df;exit" "$TMPD/o4g.txt" "$TMPD/4g.img"
rc=$?
V="$TMPD/o4g.txt"
[ "$rc" -eq 21 ] && ok "der Lauf auf der 4-GiB-Platte endet von selbst (exit 21)" \
                 || bad "4-GiB-Lauf: exit $rc"
tot=$(tr -d '\000' < "$V" | grep -a '^blocks total=' | head -1 | grep -oa 'total=[0-9]*' | cut -d= -f2)
frei=$(tr -d '\000' < "$V" | grep -a '^blocks total=' | head -1 | grep -oa 'free=[0-9]*' | cut -d= -f2)
num "BLOECKE, DIE DER KERN VERWALTET (vorher: 4096, immer)" "$tot" eq 8388608
num "davon frei" "$frei" gt 8300000
[ -n "$tot" ] && echo "        das sind $((tot / 2048)) MiB Platte gegen 2 MiB vor dieser Runde"
rm -f "$TMPD/4g.img"

echo
echo "== 6. DER WEITE BLOCK: eine Datei, die es in Fassung 2 nicht geben konnte =="
printf 'weit hinten auf der platte\n' > "$TMPD/weit.txt"
python3 tools/osum/mkfs.py build "$TMPD/weit.img" 262144 --v3 --inodes=64 \
    --time=1780000000 --reserve=200000 $SPEC /weit.txt="$TMPD/weit.txt" \
    > "$TMPD/mweit.txt" 2>&1 || bad "mkfs --reserve"
python3 tools/osum/mkfs.py where "$TMPD/weit.img" /weit.txt > "$TMPD/wo.txt" 2>&1
sed 's/^/        /' "$TMPD/wo.txt"
wb=$(grep -oa 'first=[0-9]*' "$TMPD/wo.txt" | cut -d= -f2)
num "die Datei liegt an einem Block, fuer den Fassung 2 kein Bit hatte" "$wb" gt 4096
num "und er ist wirklich weit hinten" "$wb" gt 200000
run_disk "$TMPD/k.mb" "osum vfs $QUIET script=cat /weit.txt;echo NEUERINHALT>/weit.txt;cat /weit.txt;exit" \
    "$TMPD/oweit.txt" "$TMPD/weit.img"
rc=$?
W="$TMPD/oweit.txt"
[ "$rc" -eq 21 ] && ok "der Lauf auf der reservierten Platte endet von selbst (exit 21)" \
                 || bad "weit-Lauf: exit $rc"
has "$W" "weit hinten auf der platte" "DER KERN LIEST einen Block jenseits der alten Grenze"
python3 tools/osum/mkfs.py cat "$TMPD/after.img" /weit.txt > "$TMPD/wcat.txt" 2>&1
has "$TMPD/wcat.txt" "NEUERINHALT" "UND ER SCHREIBT DORT: der Wirt liest zurueck, was der Kern hingelegt hat"
python3 tools/osum/mkfs.py where "$TMPD/after.img" /weit.txt > "$TMPD/wo2.txt" 2>&1
wb2=$(grep -oa 'first=[0-9]*' "$TMPD/wo2.txt" | cut -d= -f2)
num "und die Datei liegt danach immer noch weit hinten" "$wb2" gt 200000
rm -f "$TMPD/weit.img"

echo
echo "== 7. DIE ZEIT UEBERLEBT DEN NEUSTART =="
# Erster Lauf: eine Datei anlegen und ihre Zeit aufschreiben.
run_disk "$TMPD/k.mb" "osum vfs $QUIET script=touch /tmp/marke;ls -l /tmp;exit" \
    "$TMPD/t1.txt" "$TMPD/v3.img"
rc=$?
[ "$rc" -eq 21 ] && ok "erster Lauf: Datei angelegt (exit 21)" || bad "erster Zeit-Lauf: exit $rc"
z1=$(tr -d '\000' < "$TMPD/t1.txt" | grep -a ' marke$' | head -1)
echo "        ls -l nach dem Anlegen:  $z1"
# Zweiter Lauf auf DERSELBEN Platte -- nichts wird neu gebaut.
run_again "$TMPD/k.mb" "osum vfs $QUIET script=ls -l /tmp;exit" "$TMPD/t2.txt"
rc=$?
[ "$rc" -eq 21 ] && ok "zweiter Lauf auf derselben Platte (exit 21)" || bad "zweiter Zeit-Lauf: exit $rc"
z2=$(tr -d '\000' < "$TMPD/t2.txt" | grep -a ' marke$' | head -1)
echo "        ls -l nach dem Neustart: $z2"
if [ -n "$z1" ] && [ "$z1" = "$z2" ]; then
    ok "DIE ZEIT STEHT NACH DEM NEUSTART NOCH DA, Zeichen fuer Zeichen"
else
    bad "die Zeit hat den Neustart nicht ueberlebt: '$z1' vs '$z2'"
fi
echo "$z2" | grep -qE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]' \
    && ok "und sie steht als Datum da, nicht als Leerraum" \
    || bad "ls -l zeigt kein Datum: '$z2'"
# Gegenprobe: dieselbe Zeile auf der Platte der Fassung 2.
run_disk "$TMPD/k.mb" "osum vfs $QUIET script=touch /tmp/marke;ls -l /tmp;exit" \
    "$TMPD/t3.txt" "$TMPD/v2.img"
z3=$(tr -d '\000' < "$TMPD/t3.txt" | grep -a ' marke$' | head -1)
echo "        dieselbe Zeile in Fassung 2: $z3"
echo "$z3" | grep -q '1970-01-01' \
    && ok "GEGENPROBE: in Fassung 2 steht dort die Null von 1970" \
    || bad "Fassung 2 zeigt kein 1970: '$z3'"

echo
echo "== 8. was die Programme aus der Zeit machen =="
run_disk "$TMPD/k.mb" "osum vfs $QUIET script=touch /tmp/alt;sleep 2;touch /tmp/neu;find /tmp -newer /tmp/alt;tar -cf /tmp/t.tar /tmp/neu;exit" \
    "$TMPD/p.txt" "$TMPD/v3.img"
rc=$?
P="$TMPD/p.txt"
[ "$rc" -eq 21 ] && ok "der Lauf mit find und tar endet von selbst (exit 21)" \
                 || { bad "find/tar-Lauf: exit $rc"; tail -6 "$P" | tr -d '\000' | sed 's/^/        /'; }
has "$P" "/tmp/neu" "'find -newer' findet die JUENGERE Datei"
tr -d '\000' < "$P" | grep -qa '^/tmp/alt$' \
    && bad "'find -newer' hat auch die aeltere gefunden" \
    || ok "und die aeltere NICHT -- das ist der Unterschied, den es vorher nicht geben konnte"
# tar: das mtime-Feld steht bei Versatz 136, zwoelf Oktette oktal.
python3 tools/osum/mkfs.py cat "$TMPD/after.img" /tmp/t.tar > "$TMPD/t.tar" 2>/dev/null
if [ -s "$TMPD/t.tar" ]; then
    mt=$(python3 -c "
d = open('$TMPD/t.tar','rb').read(512)
s = d[136:148].decode('ascii','replace').strip('\0 ')
print(int(s, 8) if s.strip() else 0)
" 2>/dev/null)
    num "die Aenderungszeit im tar-Kopf" "$mt" gt 1700000000
else
    bad "tar hat kein Archiv geschrieben"
fi

echo
echo "== 9. der symbolische Verweis, und die Gegenprobe dazu =="
# DER VERWEIS KOMMT VOM WIRT und nicht aus einem `echo` in der Shell.
# Der erste Versuch hat ihn im Lauf angelegt -- und die Shell schreibt
# jeden Befehl, den sie ausfuehrt, auf dieselbe serielle Leitung. Das
# Wort, auf das die Gegenprobe wartet, stand damit schon in der
# Befehlszeile, und die Messung haette immer bestanden. So etwas ist
# schlimmer als kein Test.
printf 'ZIELINHALT\n' > "$TMPD/ziel.txt"
python3 tools/osum/mkfs.py build "$TMPD/link.img" 131072 --v3 --inodes=256 \
    --time=1780000000 $SPEC /ziel.txt="$TMPD/ziel.txt" "/zeiger->/ziel.txt" \
    > "$TMPD/mlink.txt" 2>&1 || bad "mkfs mit einem Verweis"
python3 tools/osum/mkfs.py list "$TMPD/link.img" > "$TMPD/llist.txt" 2>&1
has "$TMPD/llist.txt" "/zeiger" "der WIRT legt einen symbolischen Verweis ins Abbild"
run_disk "$TMPD/k.mb" "osum vfs $QUIET script=cat /zeiger;ls -l /;exit" \
    "$TMPD/l1.txt" "$TMPD/link.img"
rc=$?
L="$TMPD/l1.txt"
[ "$rc" -eq 21 ] && ok "der Verweis-Lauf endet von selbst (exit 21)" || bad "Verweis-Lauf: exit $rc"
has "$L" "ZIELINHALT" "'cat /zeiger' liest durch den Verweis hindurch die Zieldatei"
tr -d '\000' < "$L" | grep -qa 'zeiger -> /ziel.txt' \
    && ok "'ls -l' zeigt ihn als 'zeiger -> /ziel.txt'" \
    || { bad "ls -l zeigt den Verweis nicht"; tr -d '\000' < "$L" | grep -a 'zeiger' | sed 's/^/        /'; }
tr -d '\000' < "$L" | grep -qaE '^l +[0-9]+ ' \
    && ok "und mit dem Buchstaben 'l' in der ersten Spalte" \
    || bad "ls -l kennzeichnet den Verweis nicht mit 'l'"
# GEGENPROBE: mit `nolinks` folgt der Kern keinem Verweis mehr. Dieselbe
# Platte, derselbe Befehl, ein Wort auf der Kommandozeile anders.
run_disk "$TMPD/k.mb" "osum vfs nolinks $QUIET script=cat /zeiger;exit" \
    "$TMPD/l2.txt" "$TMPD/link.img"
N="$TMPD/l2.txt"
hasnot "$N" "ZIELINHALT" "GEGENPROBE 'nolinks': durch denselben Verweis kommt nichts mehr"
rm -f "$TMPD/link.img"

echo
echo "== 10. die alten Abbilder booten weiter =="
run_disk "$TMPD/k.mb" "osum $QUIET script=ls;ls /bin;exit" "$TMPD/a1.txt" "$TMPD/v1.img"
rc=$?
A="$TMPD/a1.txt"
[ "$rc" -eq 21 ] && ok "eine Platte der FASSUNG 1 bootet und endet von selbst (exit 21)" \
                 || bad "Fassung-1-Lauf: exit $rc"
has "$A" "osum: mount=1" "sie wird eingehaengt"
has "$A" "sh: ready, osum" "und ihre Shell startet"
has "$A" "k13: ofsver=1" "der Kern sagt: Fassung 1"
run_disk "$TMPD/k.mb" "osum $QUIET script=ls;ls /bin;exit" "$TMPD/a2.txt" "$TMPD/v2.img"
rc=$?
A2="$TMPD/a2.txt"
[ "$rc" -eq 21 ] && ok "eine Platte der FASSUNG 2 bootet und endet von selbst (exit 21)" \
                 || bad "Fassung-2-Lauf: exit $rc"
has "$A2" "k13: ofsver=2" "der Kern sagt: Fassung 2"
has "$A2" "sh: ready, osum" "und ihre Shell startet"

echo
echo "== 11. nichts geht verloren =="
for f in "$TMPD/o3.txt" "$TMPD/o4g.txt" "$TMPD/l1.txt"; do
    line=$(tr -d '\000' < "$f" | grep -a -m1 '^osum: frames_free=')
    now=$(echo "$line" | grep -oa 'frames_free=[0-9]*' | cut -d= -f2)
    was=$(echo "$line" | grep -oa 'of [0-9]*' | awk '{print $2}')
    if [ -n "$now" ] && [ "$now" = "$was" ]; then
        ok "$(basename "$f"): jeder Rahmen kam zurueck ($now frei)"
    else
        bad "$(basename "$f"): Rahmen nachher $now, vorher $was"
    fi
done
exc=0
for f in "$TMPD/o3.txt" "$TMPD/o4g.txt" "$TMPD/oweit.txt" "$TMPD/l1.txt"; do
    grep -qa '\*\*\* EXCEPTION' "$f" && { bad "$(basename "$f"): eine Ausnahme im Lauf"; exc=1; }
done
[ "$exc" -eq 0 ] && ok "in keinem Lauf dieser Runde eine Ausnahme"

echo
echo "OFS3: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ] || exit 1
exit 0
