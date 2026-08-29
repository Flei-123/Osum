#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/handle/run.sh -- DER BEWEIS, DASS DIE LEBENSDAUER STIMMT,
# BEVOR ES DIE ERSTE ASYNCHRONE OPERATION GIBT.
#
# WARUM DIESE RUNDE ZUERST KOMMT. Google hat 2023 berichtet, dass rund
# 60 % der eingereichten Linux-Kernel-Exploits aus io_uring stammten, und
# hat den Ring auf Android und ChromeOS abgeschaltet. Die Ursache war
# nicht der geteilte Speicher und nicht die Ringform -- es war die
# ASYNCHRONE LEBENSDAUER: ein Auftrag lebt laenger als der Aufruf, der
# ihn eingereicht hat, das Programm schliesst inzwischen sein Handle, der
# Platz wird neu vergeben, und der alte Auftrag greift auf das neue
# Objekt zu. Das ist Use-after-free mit Zwischenschritten, und es ist
# nachtraeglich nicht zu reparieren.
#
# Also wird es hier VORHER gebaut und VORHER gemessen. Der Ring (Runde
# RING) ist NICHT Teil dieser Runde.
#
# WAS GEMESSEN WIRD, UND WARUM JEDE ZUSAGE EINE GEGENPROBE HAT:
#
#   1. FUENFUNDDREISSIG ZUSAGEN AUS RING 3 (`uprog.u_handle`). Nicht der
#      Kernel behauptet, seine Rechnung stimme -- ein unprivilegiertes
#      Programm jenseits des Schutzwalls sagt Zeile fuer Zeile, was es
#      geschafft hat und was ihm verwehrt wurde. Jede Zeile wird hier
#      EINZELN nachgelesen; eine Sammelzahl allein waere zu leicht.
#   2. ZWEI DINGE, DIE EIN PROGRAMM NICHT ZEIGEN KANN, misst der Kernel
#      selbst: dass zwei Prozesse fuer DASSELBE Objekt am DEMSELBEN Platz
#      verschiedene Handle-Werte bekommen (und der fremde Wert nichts
#      trifft), und dass eine ausdrueckliche Uebergabe die Rechte
#      schneidet statt sie zu uebernehmen.
#   3. DIE LECKZAHLEN. Nach einem Lauf, in dem jeder Prozess ordentlich
#      geendet hat, muss die Objekttafel wieder auf den drei
#      Konsoleneintraegen stehen und kein Auftrag mehr laufen. Eine
#      Refcount-Schicht, die niemand nachzaehlt, ist eine Behauptung.
#   4. VIER GEGENPROBEN, und jede schaltet GENAU EINE Zusage aus:
#        nogen     -- die Generation wird nicht verglichen. "veraltet"
#                     MUSS fallen, und der alte Auftrag MUSS das neue
#                     Objekt treffen. Das ist der io_uring-Fehler,
#                     absichtlich wieder eingebaut.
#        noflight  -- ein laufender Auftrag haelt keinen Verweis.
#                     "kein-free-in-flug" MUSS fallen.
#        norights  -- die Rechte des Handles werden im Deskriptorpfad
#                     nicht geprueft. "kopie-darf-nicht" MUSS fallen.
#        (ohne)    -- ohne das Wort `handle` passiert nichts von alledem.
#   5. DER SCHALTER `hstrict` AUF DEM PLATTENWEG: nichts wird geerbt.
#      Die Shell von der Platte bekommt dann keine Deskriptoren mehr und
#      sagt kein Wort -- das ist die Messung, WAS am alten Verhalten
#      haengt, und nicht bloss die Behauptung, dass etwas daran haengt.
#   6. DER PREIS. `file.fd_of` in Zyklen, Median aus 33 Bloecken zu 512
#      Aufrufen. Die Zahl steht im Protokoll; der Vergleich mit dem Stand
#      vor der Runde steht in docs/HANDLE-STATUS.md.
#   7. BEIDE UEBERSETZER. firnc0 und firnc1 bauen denselben Kernel, und
#      er sagt beide Male dasselbe.
#
# Verwendung:  bash tools/handle/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls"
BLOCKS=4096

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

has()    { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }

num() { # name wert op erwartet
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}

# Eine Zahl aus einer Zeile "handle: NAME=WERT".
zahl() { sed -n "s/^handle: $2=\([0-9]*\).*/\1/p" "$1" | head -1; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "HANDLE: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

run_kernel() { # abbild anhang ausgabe [weitere qemu-argumente]
    local image=$1 append=$2 out=$3
    shift 3
    timeout 120 $QEMU_X86 -kernel "$image" -m 128 -append "$append" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

run_disk() { # abbild anhang ausgabe plattenabbild
    local copy="$TMPD/live.img"
    cp "$4" "$copy"
    run_kernel "$1" "$2" "$3" -drive "file=$copy,format=raw,if=ide,index=0"
}

echo "== 1. bauen =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" \
        || { bad "$f.s laesst sich nicht assemblieren"; }
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null

build_stage() { # 0 = firnc0, 1 = firnc1
    local s=$1 cc
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    [ -x "$cc" ] || { bad "Uebersetzer fehlt: $cc"; return 1; }
    "$cc" kernel/kmain.fi -o "$TMPD/k$s.o" >"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt kernel/kmain.fi nicht"; sed 's/^/        /' "$TMPD/e$s" | head -8; return 1; }
    "$cc" kernel/uprog.fi -o "$TMPD/u$s.o" >>"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt kernel/uprog.fi nicht"; sed 's/^/        /' "$TMPD/e$s" | head -8; return 1; }
    ld -n -T "$LDSCRIPT" \
        --defsym=KERNEL_MAIN="_F$s.kernel_main" \
        --defsym=KERNEL_TRAP="_F$s.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F$s.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F$s.tasks__main" \
        --defsym=KERNEL_USER_START="_F$s.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F$s.smp__ap_main" \
        --defsym=USER_MAIN="_F$s.u_enter" \
        -o "$TMPD/k$s.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
        "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k$s.o" "$TMPD/u$s.o" 2>"$TMPD/ld$s.err" \
        || { bad "firnc$s: ld am Kernel gescheitert"; return 1; }
    objcopy -O elf32-i386 "$TMPD/k$s.elf" "$TMPD/k$s.mb" 2>/dev/null
    ok "firnc$s: Kernel gebunden und zu einem Multiboot-Abbild gemacht"
    local p
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" >"$TMPD/ep$s" 2>&1 || { bad "firnc$s: $p.fi"; return 1; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>/dev/null || { bad "firnc$s: ld an $p"; return 1; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return 0
}

build_stage 0 || { echo "HANDLE: $pass bestanden, $fail gefallen"; exit 1; }

# Die Speicherkarte von kdata: die fuenf Bereiche dieser Runde duerfen
# sich mit nichts ueberschneiden. Das ist die Stelle, an der dieses
# Projekt viermal denselben Fehler gemacht hat.
if python3 tools/kernel/memmap.py > "$TMPD/map.txt" 2>&1; then
    ok "die Speicherkarte von kdata geht auf: $(sed -n 's/.*, \([0-9]*\) Kollisionen/\1/p' "$TMPD/map.txt") Kollisionen"
else
    bad "tools/kernel/memmap.py meldet eine Kollision"; sed 's/^/        /' "$TMPD/map.txt" | head -6
fi

echo "== 2. der Hauptlauf: fuenfunddreissig Zusagen aus Ring 3 =="
run_kernel "$TMPD/k0.mb" "handle hbench" "$TMPD/main.txt"
rc=$?
M="$TMPD/main.txt"
[ "$rc" -eq 21 ] && ok "der Kernel hat sich selbst beendet (exit 21)" \
                 || { bad "QEMU-Rueckgabe $rc, erwartet 21"; tail -8 "$M" | sed 's/^/        /'; }

# Die fuenfunddreissig stehen hier im Klartext, damit eine GELOESCHTE
# oder umbenannte Zusage auffaellt -- und nicht nur eine kleinere Summe.
ZUSAGEN=(
 "fassung"                "die Schnittstelle meldet ihre Fassung"
 "roehre"                 "eine Roehre als Testobjekt"
 "plaetze-belegt"         "drei Konsolen- und zwei Roehrenplaetze"
 "rechte-lesen"           "(a) das Leseende darf lesen"
 "rechte-nicht-schreiben" "(a) das Leseende darf NICHT schreiben"
 "rechte-schreiben"       "(a) das Schreibende darf schreiben"
 "rechte-nicht-lesen"     "(a) das Schreibende darf NICHT lesen"
 "seek-eigenrecht"        "(a) die Position verstellen ist ein eigenes Recht"
 "dup-weniger"            "(a) vervielfaeltigen gelingt"
 "keine-eskalation"       "(a) ALLE Rechte verlangt -- und keines dazubekommen"
 "kopie-darf-nicht"       "(a) die beschnittene Kopie kann weniger als das Original"
 "auftrag-an"             "(b) der Auftrag laeuft"
 "lebt-vor-dem-close"     "(b) das Objekt lebt vor dem Schliessen"
 "kein-free-in-flug"      "(b) SCHLIESSEN WAEHREND DES AUFTRAGS GIBT NICHT FREI"
 "platz-neu-vergeben"     "(b) derselbe Deskriptorplatz, ein anderes Objekt"
 "veraltet"               "(b) DER ALTE AUFTRAG BEKOMMT -E_STALE"
 "nicht-das-neue-ding"    "(b) UND NICHT DAS NEUE OBJEKT"
 "ende-raeumt-ab"         "(b) das Ende des Auftrags raeumt nach"
 "danach-weg"             "(b) danach ist der Eintrag wirklich weg"
 "close1"                 "(c) das erste Schliessen gelingt"
 "close-zweimal"          "(c) DAS ZWEITE SCHLIESSEN GIBT -EBADF"
 "handle-weg"             "(c) hinter dem Deskriptor steht kein Handle mehr"
 "gefaelschte-gen"        "(d) eine erfundene Generation trifft nichts"
 "platz-ausserhalb"       "(d) ein Platz ausserhalb der Tafel trifft nichts"
 "handle-null"            "(d) das Handle 0 ist kein stdin"
 "erfundenes-token"       "(d) ein erfundenes Abbruch-Token trifft nichts"
 "nummer-gibt-es-nicht"   "(d) eine Aufrufnummer, die es nicht gibt"
 "auftrag-laeuft"         "(e) der Auftrag steht auf laufend"
 "abgebrochen"            "(e) abbrechen gelingt"
 "zustand-ab"             "(e) danach steht er auf abgebrochen"
 "zweimal-abbrechen"      "(e) ein zweites Abbrechen trifft nichts"
 "zugriff-abgebrochen"    "(e) der Zugriff gibt -E_CANCELLED"
 "abbruch-raeumt-nicht"   "(e) ABBRECHEN GIBT DAS OBJEKT NICHT FREI"
 "ende-raeumt-noch-nicht" "(e) solange ein Deskriptor darauf zeigt"
 "close-raeumt-ab"        "(e) erst das Schliessen raeumt ab"
)
i=0
while [ $i -lt ${#ZUSAGEN[@]} ]; do
    has "$M" "[ ok ] ${ZUSAGEN[$i]}" "${ZUSAGEN[$((i+1))]}"
    i=$((i+2))
done
hasnot "$M" "[FAIL]" "keine einzige gefallene Zusage im Hauptlauf"
has "$M" "handle: 35/35 Zusagen" "das Programm zaehlt selbst 35 von 35"
has "$M" "handle: ring 3 exit=0" "sein Beendigungscode ist die Zahl der gefallenen: 0"

echo "== 3. was ein Programm nicht zeigen kann: der Kernel misst selbst =="
grep -qa 'handle: ha=.* differ=1  cross=1  nonce-differ=1' "$M" \
    && ok "(d) zwei Prozesse, DERSELBE Platz: verschiedene Handles, und der fremde trifft nichts" \
    || { bad "(d) der Vergleich zweier Tafeln stimmt nicht"; grep -a 'handle: ha=' "$M" | sed 's/^/        /'; }
grep -qa 'handle: pass=1  shrink=1  notransfer=1  refs=2' "$M" \
    && ok "die ausdrueckliche Uebergabe: sie gelingt, sie SCHNEIDET die Rechte, ohne R_TRANSFER geht sie nicht, und das Objekt haelt danach zwei Verweise" \
    || { bad "die Uebergabe an ein Kind stimmt nicht"; grep -a 'handle: pass=' "$M" | sed 's/^/        /'; }

echo "== 4. die Zaehler: hat ueberhaupt jemand gefragt? =="
num "Aufloesungen eines Handles im ganzen Lauf" "$(zahl "$M" checks)" ge 100
num "abgelehnt, weil ein Recht fehlte"          "$(zahl "$M" denied)" ge 1
num "abgelehnt, weil etwas veraltet war"        "$(zahl "$M" stale)" ge 3
num "abgebrochene Auftraege"                    "$(zahl "$M" cancels)" ge 1
num "Freigaben, die ein Auftrag aufgehalten hat" "$(zahl "$M" deferred)" ge 1
num "versuchte Rechteerweiterungen (gezaehlt, nicht gewaehrt)" "$(zahl "$M" escalate)" ge 1
num "angelegte Objekte"                         "$(zahl "$M" opened)" ge 10
# DIE BEIDEN LECKZAHLEN. Am Ende dieses Abschnitts hat jeder Prozess
# ordentlich geendet: es darf kein Auftrag mehr laufen, und die
# Objekttafel darf nur noch die DREI Konsoleneintraege halten. Eine
# Verweiszaehlung, die niemand nachzaehlt, ist eine Behauptung.
num "Objekte am Ende (nur die drei Konsoleneintraege)" "$(zahl "$M" objects)" eq 3
num "Auftraege am Ende (keiner)"                       "$(zahl "$M" inflight)" eq 0
# Und der Waechter des Benchmarks: misst er ueberhaupt eine Aufloesung?
num "bench-fdok (der Eintrag hinter Deskriptor 1 -- 64 hiesse: die Messung misst nichts)" \
    "$(zahl "$M" bench-fdok)" eq 1
FDOF=$(zahl "$M" bench-fd-of); LEER=$(zahl "$M" bench-leer); KHZ=$(zahl "$M" bench-khz)
printf '  ZAHL  file.fd_of: %s Zyklen (Median), Leerschleife %s, TSC %s kHz\n' "$FDOF" "$LEER" "$KHZ"
num "file.fd_of kostet weniger als 200 Zyklen" "$FDOF" lt 200

echo "== 5. Gegenprobe 'nogen': der io_uring-Fehler, absichtlich wieder eingebaut =="
run_kernel "$TMPD/k0.mb" "handle nogen" "$TMPD/nogen.txt"
N="$TMPD/nogen.txt"
has "$N" "[FAIL] veraltet" "ohne Generationsvergleich faellt 'veraltet'"
has "$N" "[FAIL] nicht-das-neue-ding" "und der alte Auftrag trifft WIRKLICH das neue Objekt"
has "$N" "[FAIL] gefaelschte-gen" "und eine erfundene Generation trifft dann auch"
hasnot "$N" "handle: 35/35 Zusagen" "der Lauf ist nicht mehr vollstaendig gruen"

echo "== 6. Gegenprobe 'noflight': Freigeben waehrend ein Auftrag laeuft =="
run_kernel "$TMPD/k0.mb" "handle noflight" "$TMPD/nofl.txt"
F2="$TMPD/nofl.txt"
has "$F2" "[FAIL] kein-free-in-flug" "ohne den Mitzaehler wird waehrend des Auftrags freigegeben"
hasnot "$F2" "handle: 35/35 Zusagen" "der Lauf ist nicht mehr vollstaendig gruen"

echo "== 7. Gegenprobe 'norights': die zweite Haelfte der Tiefenstaffelung faellt weg =="
run_kernel "$TMPD/k0.mb" "handle norights" "$TMPD/norg.txt"
R="$TMPD/norg.txt"
has "$R" "[FAIL] kopie-darf-nicht" "ohne Rechtepruefung darf die beschnittene Kopie doch lesen"
has "$R" "[ ok ] keine-eskalation" "die Rechte STEHEN dabei trotzdem richtig in der Tafel -- nur gefragt wird nicht mehr"
hasnot "$R" "handle: 35/35 Zusagen" "der Lauf ist nicht mehr vollstaendig gruen"

echo "== 8. Gegenprobe: ohne das Wort passiert nichts davon =="
run_kernel "$TMPD/k0.mb" "nokbd" "$TMPD/off.txt"
O="$TMPD/off.txt"
has "$O" "handle: skipped" "ohne 'handle' meldet der Abschnitt sich ab"
hasnot "$O" "handle: ring 3 beginnt" "und startet kein Programm"
hasnot "$O" "[ ok ] veraltet" "und misst nichts"

echo "== 9. der Schalter 'hstrict': nichts wird geerbt =="
# Was am alten Verhalten haengt, wird hier GEMESSEN und nicht behauptet:
# /bin/sh von der Platte liest von 0 und schreibt nach 1, ohne je danach
# gefragt zu haben. Mit `hstrict` bekommt ein Kind von `elf.spawn` gar
# keine Deskriptoren mehr -- und dann sagt die Shell kein Wort.
printf 'runde handle\n' > "$TMPD/readme.txt"
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf"; done
if python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
       /readme.txt="$TMPD/readme.txt" >"$TMPD/mkfs.txt" 2>&1; then
    ok "mkfs.py hat ein OFS-Abbild mit /bin/sh gebaut"
    QUIET="nokbd nosched noproc nofs noring3"
    run_disk "$TMPD/k0.mb" "osum $QUIET script=ls;exit" "$TMPD/erbt.txt" "$TMPD/disk.img"
    run_disk "$TMPD/k0.mb" "osum hstrict $QUIET script=ls;exit" "$TMPD/streng.txt" "$TMPD/disk.img"
    has    "$TMPD/erbt.txt"   "sh: ready, osum" "ohne den Schalter erbt die Shell 0, 1 und 2 wie bisher"
    hasnot "$TMPD/streng.txt" "sh: ready, osum" "MIT 'hstrict' bekommt sie NICHTS und sagt kein Wort"
    has    "$TMPD/streng.txt" "osum: mount=1" "der Kernel selbst laeuft dabei weiter -- es ist die Shell, der etwas fehlt"
else
    bad "mkfs.py ist gescheitert"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5
fi

echo "== 10. der zweite Uebersetzer =="
if build_stage 1; then
    run_kernel "$TMPD/k1.mb" "handle" "$TMPD/s1.txt"
    rc1=$?
    [ "$rc1" -eq 21 ] && ok "firnc1: der Kernel beendet sich selbst" \
                      || bad "firnc1: QEMU-Rueckgabe $rc1, erwartet 21"
    has "$TMPD/s1.txt" "handle: 35/35 Zusagen" "firnc1 sagt dasselbe wie firnc0"
    hasnot "$TMPD/s1.txt" "[FAIL]" "firnc1: keine gefallene Zusage"
else
    echo "  (firnc1 nicht verfuegbar -- uebersprungen)"
fi

echo "HANDLE: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ] || exit 1
exit 0
