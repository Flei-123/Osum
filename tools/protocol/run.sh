#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/protocol/run.sh -- RUNDE PROTOKOLL: DIE FUENF MESSUNGEN.
#
# Die Roadmap nennt Block B1 "hoechsten Nutzen pro Aufwand der ganzen
# Liste", und der Grund steht in einem Satz: die Fehlersuche auf echter
# Hardware war bis zu dieser Runde BLIND. Ein Treiber sagte, was er tat,
# genau einmal, auf eine serielle Leitung, die Justins Brett nicht hat
# (LSR 0xFF) -- und eine Panik sagte "*** EXCEPTION 14" und fuenf nackte
# Zahlen.
#
# Gemessen wird hier, was diese Runde daraus gemacht hat:
#
#   (a) VIER KERNE, VIERZIGTAUSEND ZEILEN, EIN RING. Keine Zeile
#       verschraenkt, keine verloren. Der Kern zaehlt selbst mit und
#       prueft selbst nach (`klog.verify`) -- die Kernnummer steht
#       einmal im Kopf des Eintrags und einmal, vom rufenden Kern
#       geschrieben, im Text; gehen sie auseinander, haben sich zwei
#       Kerne denselben Platz genommen.
#   (b) EINE ERZWUNGENE KERNEL-PANIK, und der Panik-Bildschirm wird
#       WIRKLICH GELESEN: `tools/protocol/schirmtext.py` macht aus dem
#       Bildschirmfoto wieder Text, indem es die Glyphen von
#       `kernel/font.fi` zurueckrechnet. Verlangt sind mindestens fuenf
#       aufgeloeste Symbole MIT Datei:Zeile.
#   (c) DER BERICHT UEBERLEBT DEN NEUSTART. Zwei Laeufe auf DERSELBEN
#       Plattendatei (nicht auf einer Kopie): im ersten knallt es, im
#       zweiten liest `/bin/absturz` den Bericht.
#   (d) EIN NULLZEIGER IN RING 3 ist KEINE Kernel-Panik: das Programm
#       stirbt, ein Bericht mit seinem NAMEN entsteht, und die Shell
#       laeuft danach weiter -- gemessen daran, dass der Befehl DANACH
#       noch etwas ausgibt.
#   (e) WAS EIN WEGGEFILTERTER AUFRUF KOSTET. Eine Million Aufrufe der
#       Stufe debug bei einer Schwelle darueber, im Kern gemessen.
#
# ZU (e) UND DER SCHWELLE VON 100 ms, ehrlich und vorweg: unter TCG
# (reiner Emulation) sind es rund 130 ms, unter KVM rund 26. Die
# Abnahmeschwelle gilt fuer den Lauf auf echter Prozessorgeschwindigkeit;
# dieses Skript nimmt KVM, WENN es da ist, und misst sonst TCG und sagt
# beide Zahlen. Eine Emulation, die jeden Befehl uebersetzt, ist keine
# Aussage ueber den Preis eines Befehls.
set -uo pipefail
cd "$(dirname "$0")/../.."

QEMU_X86=${QEMU_X86:-qemu-system-x86_64}
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh ls cat echo log absturz krach"
# Seit ENGLISCH ETAPPE 9 heissen die QUELLEN anders als die Programme:
# /bin/absturz kommt aus crash.fi, /bin/krach aus noise.fi. Die Zusagen
# unten pruefen die /bin/-Namen, darum wird hier nur die Quelle abgebildet.
quelle() { case $1 in absturz) echo crash ;; krach) echo noise ;; *) echo "$1" ;; esac; }
BLOCKS=4096

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
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
same() { [ "$2" = "$3" ] && ok "$1: $3" || bad "$1: '$3' statt '$2'"; }
value() { grep -oaE "$2" "$1" | head -1 | grep -oE '[0-9]+$'; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
command -v "$QEMU_X86" >/dev/null 2>&1 || {
    echo "PROTOKOLL: uebersprungen, $QEMU_X86 fehlt"; exit 0; }

# ----------------------------------------------------------- Beschleunigung
#
# Siehe den Kopf: (e) misst einen Preis in Nanosekunden, und den kann nur
# eine Maschine messen, die Befehle wirklich ausfuehrt.
ACCEL=""
ACCELNAME="tcg"
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL="-accel kvm -cpu host"
    ACCELNAME="kvm"
fi
echo "PROTOKOLL: Beschleunigung = $ACCELNAME"

# ------------------------------------------------------------------ laufen

lauf() { # abbild kommandozeile ausgabe [weitere qemu-argumente]
    local abbild=$1 zeile=$2 aus=$3
    shift 3
    timeout 240 $QEMU_X86 $ACCEL -kernel "$abbild" -m 256 -append "$zeile" \
        -serial "file:$aus" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

# DIESELBE PLATTE, NICHT EINE KOPIE. `tools/osum/run.sh` kopiert das
# Abbild vor jedem Lauf, damit ein Fall den naechsten nicht beeinflusst.
# Punkt (c) misst GENAU DAS GEGENTEIL: dass ein Bericht den Neustart
# ueberlebt. Also wird hier auf der Datei selbst gearbeitet.
lauf_platte() { # abbild kommandozeile ausgabe platte
    lauf "$1" "$2" "$3" -drive "file=$4,format=raw,if=ide,index=0"
}

echo "== 1. bauen: Kernel mit Symboltabelle, und die drei neuen Programme =="
bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/build.log" 2>&1 \
    && ok "Kernel gebaut ($(stat -c%s "$TMPD/k0.mb") Oktette)" \
    || { bad "der Kernel laesst sich nicht bauen"
         sed 's/^/        /' "$TMPD/build.log" | head -15
         echo "PROTOKOLL: $pass passed, $fail failed"; exit 1; }
K0="$TMPD/k0.mb"

# DIE ZWEI DURCHGAENGE HABEN DIESELBEN ADRESSEN -- sonst waere die
# Symboltabelle falsch, und `build-kernel.sh` haette abgebrochen. Dass
# es sie ueberhaupt gibt, steht in der Bauausgabe.
n=$(grep -oaE 'symtab: [0-9]+ Symbole' "$TMPD/build.log" | grep -oE '[0-9]+')
num "Symbole im Abbild" "$n" gt 3000
n=$(grep -oaE '[0-9]+ Zeilen' "$TMPD/build.log" | head -1 | grep -oE '[0-9]+')
num "Quellzeilen-Eintraege im Abbild" "$n" gt 20000

# Und die Gegenprobe zur Behauptung "das kostet Platz, und wir sagen wie
# viel": derselbe Kern ohne Tabellen.
bash tools/build-kernel.sh "$TMPD/knosym.mb" --ohne-symbole \
    > "$TMPD/build2.log" 2>&1 \
    && ok "--ohne-symbole baut ebenfalls" || bad "--ohne-symbole baut nicht"
if [ -f "$TMPD/knosym.mb" ]; then
    a=$(stat -c%s "$K0"); b=$(stat -c%s "$TMPD/knosym.mb")
    echo "        Preis der Tabellen: $((a - b)) Oktette ($a gegen $b)"
    num "die Tabellen kosten wirklich Platz" "$((a - b))" gt 100000
fi

for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" \
        || bad "$f.s laesst sich nicht assemblieren"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
for p in $PROGS; do
    q=$(quelle "$p")
    "$FIRNC" "kernel/user/$q.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$q.fi uebersetzt nicht"; sed 's/^/        /' "$TMPD/e$p" | head -6; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null \
        || bad "$p laesst sich nicht binden"
done
[ -f "$TMPD/log.elf" ] && ok "/bin/log, /bin/absturz und /bin/krach gebaut" \
                       || bad "die neuen Programme fehlen"

# DIE AUFRUFNUMMERN STEHEN AN ZWEI STELLEN. Wenn sie auseinanderlaufen,
# ruft das Werkzeug etwas anderes an, als der Kern anbietet -- und das
# faellt zur Laufzeit als -EINVAL auf, an einer Stelle, die nichts damit
# zu tun hat.
kn=$(grep -aoE 'const SYS_OSUM_KLOG: u64 = [0-9]+' kernel/sys/sys.fi | grep -oE '[0-9]+$')
un=$(grep -aoE 'const SYS_KLOG: u64 = [0-9]+' kernel/user/ulib.fi | grep -oE '[0-9]+$')
[ "$kn" = "$un" ] && [ -n "$kn" ] \
    && ok "SYS_KLOG ist im Kern und in ulib dieselbe Nummer ($kn)" \
    || bad "SYS_KLOG: Kern=$kn ulib=$un"
kn=$(grep -aoE 'const SYS_OSUM_KRACH: u64 = [0-9]+' kernel/sys/sys.fi | grep -oE '[0-9]+$')
un=$(grep -aoE 'const SYS_KRACH: u64 = [0-9]+' kernel/user/ulib.fi | grep -oE '[0-9]+$')
[ "$kn" = "$un" ] && [ -n "$kn" ] \
    && ok "SYS_KRACH ist im Kern und in ulib dieselbe Nummer ($kn)" \
    || bad "SYS_KRACH: Kern=$kn ulib=$un"

# Die Speicherkarte: der Ring hat sich eine Seite genommen, und sie darf
# sich mit nichts ueberschneiden.
python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1
has "$TMPD/map.txt" "0 Kollisionen" "die Speicherkarte von kdata bleibt kollisionsfrei"
# RUNDE MERGE-7: hier stand die Zahl 0xC0000. Die Runde PROTOKOLL hat
# kdata auf genau diesen Wert wachsen lassen, und der Pruefstand hat ihn
# abgeschrieben. Beim Zusammenfuehren mit SYSTEMBUS und TON -- die
# dasselbe Loch fuer sich beansprucht hatten -- ist kdata auf 0x100000
# gewachsen, und diese Zusage wurde rot, OHNE dass am Protokoll etwas
# faul war. Eine Zusage, die eine Zahl abschreibt statt sie zu lesen,
# misst den Abschreibfehler mit. Jetzt wird die geltende Groesse aus
# kstate.fi gelesen, und geprueft wird, was hier wirklich zaehlt: der
# Ring liegt drin und die Karte bleibt kollisionsfrei.
KDS=$(sed -n 's/^const KDATA_SIZE: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/lib/kstate.fi | head -1)
grep -q "$KDS" "$TMPD/map.txt" \
    && ok "kdata ist $KDS gross (der Ring braucht 64 KiB am Stueck)" \
    || bad "kdata hat nicht die erwartete Groesse ($KDS)"
a=$(grep -aoE 'KDATA_SIZE, 0x[0-9A-F]+' kernel/arch/x86_64/boot.s | head -1 | grep -oE '0x[0-9A-F]+')
b=$(grep -aoE 'const KDATA_SIZE: u64 = 0x[0-9A-F]+' kernel/lib/kstate.fi | grep -oE '0x[0-9A-F]+')
[ "$a" = "$b" ] && ok "KDATA_SIZE steht in boot.s und kstate.fi gleich ($a)" \
                || bad "KDATA_SIZE: boot.s=$a kstate.fi=$b"

echo "== 2. (a) vier Kerne, zehntausend Zeilen jeder, ein Ring =="
lauf "$K0" "nokbd nosched noproc nofs noring3 logall lograce" \
    "$TMPD/race.txt" -smp 4
if grep -qa 'smp: lograce' "$TMPD/race.txt"; then
    z=$(value "$TMPD/race.txt" 'zeilen=[0-9]+')
    g=$(value "$TMPD/race.txt" 'gesamt=[0-9]+')
    r=$(value "$TMPD/race.txt" 'ring=[0-9]+')
    ro=$(value "$TMPD/race.txt" 'rotiert=[0-9]+')
    kp=$(value "$TMPD/race.txt" 'kaputt=[0-9]+')
    ke=$(value "$TMPD/race.txt" 'kerne=[0-9]+')
    num "Kerne, die geschrieben haben" "$ke" eq 4
    num "Zeilen, die die Kerne geschrieben haben" "$z" eq 40000
    num "Zeilen, die der Ring gezaehlt hat (keine darf verloren gehen)" "$g" eq 40000
    num "Zeilen, die noch im Ring stehen" "$r" eq 510
    num "Zeilen, die der Ring ueberschrieben hat (40000 - 510)" "$ro" eq 39490
    num "verschraenkte Eintraege (Kopf und Text von verschiedenen Kernen)" "$kp" eq 0
else
    bad "der Lauf mit vier Kernen hat keine lograce-Zeile geliefert"
    tail -5 "$TMPD/race.txt" | sed 's/^/        /'
fi

echo "== 3. (e) was ein weggefilterter Aufruf kostet =="
ms=$(value "$TMPD/race.txt" 'logbank aufrufe=1000000  ns=[0-9]+  ms=[0-9]+')
je=$(value "$TMPD/race.txt" 'ns_je_10=[0-9]+')
if [ -n "$ms" ]; then
    echo "        1 Mio. Aufrufe Stufe debug (ausgefiltert): $ms ms, $je ns je 10 Aufrufe, $ACCELNAME"
    if [ "$ACCELNAME" = kvm ]; then
        num "eine Million ausgefilterte Aufrufe in Millisekunden" "$ms" lt 100
    else
        # Siehe den Kopf: unter reiner Emulation ist die Schwelle keine
        # Aussage ueber den Kern. Gemessen und gesagt wird sie trotzdem.
        num "eine Million ausgefilterte Aufrufe in Millisekunden (TCG, nur Schranke gegen Ausreisser)" \
            "$ms" lt 1000
        echo "        (die Abnahmeschwelle 100 ms gilt fuer KVM; hier lief TCG)"
    fi
else
    bad "keine Messung des schnellen Weges gefunden"
fi

echo "== 4. das Protokoll im Betrieb: Quellen, Stufen, /proc und /dev =="
# MIT DATEISYSTEM UND TREIBERN -- ohne sie hat kein einziger Treiber
# etwas zu melden, und die Messung waere eine Messung des Nichts. Der
# erste Anlauf lief mit `nofs` und zaehlte deshalb null Zeilen.
lauf "$K0" "nokbd nosched noproc noring3 logdebug" "$TMPD/dbg.txt"
n=$(grep -ac ' [DIWE] ' "$TMPD/dbg.txt")
num "Protokollzeilen auf der seriellen Leitung mit logdebug" "$n" ge 1
grep -qaE '\[ *[0-9]+\] [0-9]+/[0-9]+ [DIWE] [a-z]+ *: ' "$TMPD/dbg.txt" \
    && ok "das Format stimmt: [zeit] kern/pid stufe quelle: text" \
    || bad "keine Zeile im vereinbarten Format"
# UND DIE GEGENPROBE: mit `logquiet` sind dieselben Zeilen NICHT da.
lauf "$K0" "nokbd nosched noproc nofs noring3 logquiet" "$TMPD/quiet.txt"
n2=$(grep -ac ' [DI] ' "$TMPD/quiet.txt")
num "debug/info-Zeilen mit logquiet (die Schwelle muss wirken)" "${n2:-0}" eq 0

echo "== 5. die Platte, die Programme darauf und der Neustart =="
printf 'protokoll\n' > "$TMPD/readme.txt"
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
# /proc, /dev und /mnt sind VERZEICHNISSE auf der Wurzelplatte, in die
# der Kern die anderen Dateisysteme haengt (Runde K14). Ohne sie gibt es
# kein `cat /proc/klog` und kein `cat /dev/klog`.
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
    /proc/ /dev/ /mnt/ /var/ /var/crash/ \
    /readme.txt="$TMPD/readme.txt" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "OFS-Abbild mit $BLOCKS Bloecken gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head; }

# `vfs` haengt /proc und /dev als ECHTE Dateisysteme ein (Runde K14).
# Ohne dieses Wort gibt es die beiden Verzeichnisse auf der Platte, aber
# nichts darin -- der erste Anlauf bekam "cat: cannot open /proc/klog".
QUIET="nokbd vfs"
# ---- (d) EIN NULLZEIGER IN RING 3.
#
# Danach kommt `echo weiter` -- und genau das ist die Messung: eine
# Kernel-Panik haette die Zeile nie erreicht.
lauf_platte "$K0" "osum $QUIET logall krach script=krach prog;echo WEITERLAEUFT;log -n 3;exit" \
    "$TMPD/r3.txt" "$TMPD/disk.img"
rc=$?
has "$TMPD/r3.txt" "user fault" "(d) der Nullzeiger in Ring 3 wurde als Benutzerfehler behandelt"
has "$TMPD/r3.txt" "process killed" "(d) das Programm ist gestorben"
has "$TMPD/r3.txt" "WEITERLAEUFT" "(d) das System laeuft danach weiter"
hasber=$(grep -aoE '/var/crash/[0-9]+\.txt' "$TMPD/r3.txt" | head -1)
[ -n "$hasber" ] && ok "(d) ein Bericht wurde abgelegt: $hasber" \
                 || bad "(d) es wurde kein Bericht abgelegt"
grep -qa 'absturz: bericht' "$TMPD/r3.txt" \
    && ok "(d) der Kern sagt, was aus dem Bericht geworden ist" \
    || bad "(d) der Kern schweigt ueber den Bericht"

# ---- (c) EINE KERNEL-PANIK AUS DER SHELL, dann DERSELBE DATENTRAEGER
#      NOCH EINMAL. Warum eine Kernel-Panik und nicht der Ring-3-Absturz
#      von eben: nur ihre Rueckverfolgung laeuft durch KERNCODE, und nur
#      dafuer gibt es eine Symboltabelle. Ein Ring-3-Bericht traegt die
#      Adressen des Programms, und das Programm hat seine eigenen
#      Symbole -- die stehen nicht im Kernabbild und sollen es auch
#      nicht.
lauf_platte "$K0" "osum $QUIET logall krach script=krach kern;exit" \
    "$TMPD/panikdisk.txt" "$TMPD/disk.img"
has "$TMPD/panikdisk.txt" "*** EXCEPTION" "(c) die erzwungene Kernel-Panik hat stattgefunden"
hasber=$(grep -aoE '/var/crash/[0-9]+\.txt' "$TMPD/panikdisk.txt" | tail -1)
[ -n "$hasber" ] && ok "(c) der Kern hat trotz Panik einen Bericht abgelegt: $hasber" \
                 || bad "(c) bei der Panik wurde kein Bericht abgelegt"

lauf_platte "$K0" "osum $QUIET script=absturz;exit" \
    "$TMPD/nachher.txt" "$TMPD/disk.img"
has "$TMPD/nachher.txt" "absturz: ein Bericht vom letzten Start liegt vor" \
    "(c) der Kern findet die Marke des letzten Laufs wieder"
has "$TMPD/nachher.txt" "EIN BERICHT VOM LETZTEN START" \
    "(c) /bin/absturz meldet ihn dem Benutzer"
has "$TMPD/nachher.txt" "ABSTURZBERICHT" "(c) der Bericht selbst wird angezeigt"
has "$TMPD/nachher.txt" "-- rueckspur" "(c) der Bericht enthaelt die Rueckverfolgung"
has "$TMPD/nachher.txt" "-- protokoll" "(c) der Bericht enthaelt die letzten Protokollzeilen"
has "$TMPD/nachher.txt" "ABSTURZBERICHT (KERN)" "(c) es ist der Bericht der Kernel-Panik"
n=$(grep -acE '^  #[0-9]+ [a-z]+\.[a-z_0-9]+\+0x' "$TMPD/nachher.txt")
num "(c) aufgeloeste Symbole im Bericht" "${n:-0}" ge 1

# ---- /bin/log
lauf_platte "$K0" "osum $QUIET logall script=log -z;log -p HALLOWELT;log -n 4;exit" \
    "$TMPD/werkzeug.txt" "$TMPD/disk.img"
has "$TMPD/werkzeug.txt" "zeilen:" "/bin/log -z zeigt die Zahlen des Rings"
has "$TMPD/werkzeug.txt" "HALLOWELT" "/bin/log -p schreibt eine Zeile in den Ring"
grep -qa 'prog *: HALLOWELT' "$TMPD/werkzeug.txt" \
    && ok "die geschriebene Zeile steht als Quelle 'prog' im Ring" \
    || bad "die geschriebene Zeile taucht nicht als Protokollzeile auf"
lauf_platte "$K0" "osum $QUIET logall script=cat /proc/klog;exit" \
    "$TMPD/proc.txt" "$TMPD/disk.img"
has "$TMPD/proc.txt" "# klog" "/proc/klog liefert einen Kopf mit den Zahlen"
lauf_platte "$K0" "osum $QUIET logall script=cat /dev/klog;exit" \
    "$TMPD/dev.txt" "$TMPD/disk.img"
grep -qaE '\[ *[0-9]+\] [0-9]+/[0-9]+ [DIWE] ' "$TMPD/dev.txt" \
    && ok "/dev/klog liefert dieselben Zeilen im selben Format" \
    || bad "/dev/klog liefert nichts Lesbares"

# ---- der Riegel vor dem Testausloeser
lauf_platte "$K0" "osum $QUIET script=krach kern;echo LEBTNOCH;exit" \
    "$TMPD/riegel.txt" "$TMPD/disk.img"
has "$TMPD/riegel.txt" "LEBTNOCH" \
    "ohne 'krach' auf der Kernel-Befehlszeile lehnt der Aufruf 1861 ab"

echo "== 6. (b) der Panik-Bildschirm, wirklich gelesen =="
sock="$TMPD/mon.sock"
rm -f "$sock" "$TMPD/panik.ppm" "$TMPD/panik.txt"
timeout 240 $QEMU_X86 $ACCEL -kernel "$K0" -m 256 \
    -append "nokbd nosched noproc noring3 gfx logall absturzhalt krach krachjetzt" \
    -serial "file:$TMPD/panik.txt" -display none -no-reboot \
    -vga std -global VGA.edid=off \
    -monitor "unix:$sock,server,nowait" >/dev/null 2>&1 &
qpid=$!
i=0
while [ $i -lt 900 ]; do
    grep -qa 'kernel halted' "$TMPD/panik.txt" 2>/dev/null && break
    kill -0 "$qpid" 2>/dev/null || break
    sleep 0.2
    i=$((i + 1))
done
sleep 1
python3 tools/gfx/screenshot.py "$sock" "$TMPD/panik.ppm" 25 \
    > "$TMPD/schuss.txt" 2>&1
kill "$qpid" 2>/dev/null
wait "$qpid" 2>/dev/null
rm -f "$sock"

if [ -s "$TMPD/panik.ppm" ]; then
    ok "ein Bildschirmfoto der Panik liegt vor ($(stat -c%s "$TMPD/panik.ppm") Oktette)"
    python3 tools/protocol/schirmtext.py "$TMPD/panik.ppm" kernel/gfx/font.fi \
        > "$TMPD/schirm.txt" 2>"$TMPD/schirm.err"
    if [ -s "$TMPD/schirm.txt" ]; then
        echo "        --- was auf dem Schirm steht:"
        sed 's/^/        | /' "$TMPD/schirm.txt" | head -32
        has "$TMPD/schirm.txt" "KERNEL-PANIK" "(b) der Schirm sagt, was los ist"
        has "$TMPD/schirm.txt" "#PF" "(b) der Schirm nennt die Ausnahme beim Namen"
        has "$TMPD/schirm.txt" "RUECKSPUR" "(b) der Schirm hat einen Abschnitt Rueckverfolgung"
        has "$TMPD/schirm.txt" "PROTOKOLL" "(b) der Schirm zeigt die letzten Protokollzeilen"
        has "$TMPD/schirm.txt" "KERN 0" "(b) der Schirm nennt die Kernnummer"
        # ALLE SECHZEHN REGISTER.
        n=$(grep -oaE '\b(rax|rbx|rcx|rdx|rsi|rdi|rbp|rsp|r8 |r9 |r1[0-5])=0x' \
            "$TMPD/schirm.txt" | sort -u | wc -l)
        num "(b) verschiedene Register auf dem Schirm" "$n" eq 16
        # DIE ZAHL, UM DIE ES GEHT: aufgeloeste Symbole MIT Datei:Zeile.
        #
        # K-009: BIS HIER STAND "MINDESTENS FUENF", und die Zahl mass den
        # Stapelscan: drei echte Rahmen und dahinter Altlast. Die
        # Rahmenkette liefert genau die Aufrufe, die es gab -- und DIE
        # werden jetzt verlangt, in ihrer Reihenfolge.
        kette=$(grep -oaE '[a-z_0-9]+\.[a-z_0-9]+\+0x[0-9a-f]+ \([a-z_0-9]+\.fi:[0-9]+\)' \
            "$TMPD/schirm.txt" | sed 's/+.*//' | head -3 | tr '\n' ' ')
        same "(b) die Rueckverfolgung auf dem Schirm ist die echte Aufrufkette" \
            "crash.knall_b crash.knall_a crash.knall " "$kette"
        n=$(grep -ac '?' "$TMPD/schirm.txt")
        num "(b) Zeilen mit unlesbaren Zellen (die Glyphen muessen exakt passen)" \
            "${n:-0}" le 1
    else
        bad "(b) aus dem Bildschirmfoto liess sich kein Text lesen"
        sed 's/^/        /' "$TMPD/schirm.err" | head -5
    fi
else
    bad "(b) es kam kein Bildschirmfoto zustande"
    sed 's/^/        /' "$TMPD/schuss.txt" | head -5
fi
# UND DIE SERIELLE SEITE DERSELBEN PANIK.
has "$TMPD/panik.txt" "*** EXCEPTION" "(b) dieselbe Panik steht auch auf der Leitung"
# K-009: DIE RAHMENKETTE, Eintrag fuer Eintrag. `knall_c` ist die
# Absturzstelle selbst (sie steht als rip da), darunter muessen ihre
# drei Rufer kommen, dann `kernel_main` -- und dann ENDET die Kette,
# weil boot.s `rbp` vor dem Sprung loescht. Nichts dahinter.
spur() { # datei -> die Namen der kspur-Zeilen, eine je Zeile
    awk '/^  kspur:/ { an = 1; next } an && /^      / { print $1; next } an { exit }' "$1" \
        | sed 's/+0x.*//'
}
has "$TMPD/panik.txt" "kspur: rahmenkette" "(b) die Rueckverfolgung geht die Rahmenzeiger ab, nicht den Stapel"
kette=$(spur "$TMPD/panik.txt" | tr '\n' ' ')
same "(b) die serielle Rueckverfolgung ist genau die Aufrufkette bis zum Start" \
    "crash.knall_b crash.knall_a crash.knall KERNEL_MAIN long_mode " "$kette"
n=$(grep -acE '^ +[a-z_0-9]+\.[a-z_0-9]+\+0x[0-9a-f]+ \([a-z_0-9]+\.fi:[0-9]+\)$' \
    "$TMPD/panik.txt")
num "(b) aufgeloeste Symbole mit Datei:Zeile in der seriellen Rueckverfolgung" "${n:-0}" ge 3
# GEGENPROBE: DIESELBE Panik mit `stapelscan`, also dem alten Weg. Er
# muss Eintraege liefern, die in keiner Aufrufkette dieser Panik stehen
# -- sonst waere nicht gezeigt, dass die Kette etwas weglaesst, das
# vorher falsch dastand.
timeout 120 $QEMU_X86 $ACCEL -kernel "$K0" -m 256 \
    -append "nokbd nosched noproc noring3 logall krach krachjetzt stapelscan" \
    -serial "file:$TMPD/scan.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
has "$TMPD/scan.txt" "kspur: stapelscan" "GEGENPROBE: mit 'stapelscan' wird wieder gescannt"
alt=$(spur "$TMPD/scan.txt" | grep -cvE '^(crash\.knall(_a|_b)?|KERNEL_MAIN|long_mode)$')
num "GEGENPROBE: der Scan meldet Eintraege, die keine Rufer sind (Altlast)" "${alt:-0}" ge 1
has "$TMPD/panik.txt" "die letzten Protokollzeilen" \
    "(b) die letzten Protokollzeilen stehen auch auf der Leitung"

echo "== 7. dass die Umstellung der Treiber wirklich stattgefunden hat =="
n=0
# RUNDE GRUNDLINIE-2 (A-021): die sechs Treiber liegen laengst in
# Unterordnern (kernel/drv/blk/nvme.fi, kernel/drv/usb/xhci.fi,
# kernel/usb/usb.fi, kernel/drv/blk/ahci.fi, kernel/drv/net/e1000.fi,
# kernel/fs/fs.fi). `kernel/$f.fi` traf keine einzige Datei, `grep` gab 0
# zurueck -- und die Zusage meldete "0 von 6", obwohl ALLE SECHS die
# Log-Schnittstelle benutzen. Der Pfad wird jetzt gesucht, nicht getippt.
for f in nvme xhci usb ahci e1000 fs; do
    q=$(find kernel -name "$f.fi" -print -quit)
    k=$(grep -ac 'klog\.' "$q" 2>/dev/null || echo 0)
    [ "$k" -gt 0 ] && n=$((n + 1))
    printf '        %-6s %s Aufrufe der Log-Schnittstelle\n' "$f" "$k"
done
num "Treiber, die ueber die Log-Schnittstelle sprechen" "$n" eq 6

echo "PROTOKOLL: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
