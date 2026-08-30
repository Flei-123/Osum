#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ring/run.sh -- DER BEWEIS, DASS DER COMPLETION-RING IM GETEILTEN
# SPEICHER TRAEGT.
#
# WAS DIESE RUNDE BEHAUPTET, UND WAS NICHT. Sie behauptet NICHT in erster
# Linie "schneller" -- das ist Abschnitt 7, und dort steht auch, wo es
# nicht schneller ist. Sie behauptet:
#
#   EIN PROGRAMM DARF IN DIESEN SPEICHER SCHREIBEN, WAS ES WILL,
#   UND DER KERN BLEIBT HEIL UND EHRLICH.
#
# Der Abgabering liegt im Adressraum des PROGRAMMS. Es kann jeden
# Eintrag jederzeit aendern -- auch waehrend der Kern ihn liest. Daraus
# folgen die beiden Regeln, um die es geht, und jede hat hier eine
# GEGENPROBE, die sie absichtlich kaputtmacht:
#
#   REGEL 1  GENAU EINE KOPIE. Ein Abgabesatz wird beim Einlesen einmal
#            in kerneigenen Speicher kopiert; danach arbeitet der Kern
#            nur noch mit der Kopie. Gegenprobe `noringcopy`: er liest
#            die Felder bei der Ausfuehrung noch einmal aus dem
#            geteilten Speicher -- also "time of check to time of use".
#            Die Zusage `a-kopie-haelt` MUSS damit fallen.
#   REGEL 2  KEIN ZEIGER AUS DEM GETEILTEN SPEICHER IST EIN INDEX. Jeder
#            Index wird maskiert, und die Zahl der anliegenden Saetze
#            wird gegen die Ringlaenge geprueft. Gegenprobe `noringsq`:
#            die Pruefung entfaellt. `b-riesiger-schwanz` MUSS fallen.
#
# Google hat 2023 berichtet, dass rund 60 % der eingereichten
# Linux-Kernel-Exploits aus io_uring stammten. Der geteilte Speicher war
# nicht die Ursache -- die Ursache war, dass irgendwo zweimal gelesen
# oder einmal nicht maskiert wurde. Deshalb misst dieser Laeufer genau
# das, und die Leistungszahlen stehen ganz am Schluss.
#
# Verwendung:  bash tools/ring/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo ringt"
BLOCKS=4096

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()   { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note() { printf '        %s\n' "$1"; }

num() { # name wert op erwartet
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}

# Eine Zahl aus einer Zeile "ring: NAME=WERT".
zahl()  { sed -n "s/^ring: $2=\([0-9]*\).*/\1/p" "$1" | head -1; }
# ... und aus "rbench: NAME=WERT" bzw. "abench: NAME=WERT".
bzahl() { sed -n "s/^rbench: $2=\([0-9]*\).*/\1/p" "$1" | head -1; }
azahl() { sed -n "s/^abench: $2=\([0-9]*\).*/\1/p" "$1" | head -1; }
# ... und aus "ringt: NAME = WERT" (mit Vorzeichen).
rzahl() { sed -n "s/^ringt: $2 = \(-\{0,1\}[0-9]*\).*/\1/p" "$1" | head -1; }

zusage() { # datei name
    if grep -qa "^  \[ ok \] $2\$" "$1"; then ok "Zusage $2"
    else
        local z
        z=$(grep -a "\] $2" "$1" | head -1 | sed 's/^ *//')
        bad "Zusage $2 -- ${z:-fehlt ganz}"
    fi
}
gefallen() { # datei name gegenprobe -- sie MUSS fallen
    if grep -qa "^  \[FAIL\] $2" "$1"; then ok "GEGENPROBE $3: '$2' faellt, wie sie soll"
    else bad "GEGENPROBE $3: '$2' steht trotzdem -- die Zusage misst nichts"; fi
}

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "RING: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

# =====================================================================
echo "== 1. die Nummern, die Speicherkarte und der Ringkopf =="
# =====================================================================

# 1a. Kein Aufruf zweimal vergeben. Sockelnamen (*_BASE, *_MAXNR) sind
#     ABSICHTLICH doppelt: sie benennen dieselbe Nummer zweimal.
for f in kernel/sys.fi lib/libc/kcall.fi; do
    dup=$(grep -a '^const \(SYS_\|CAP_\|WM_\|HND_\|AIO_\|RING_\)[A-Z0-9_]*: u64 = [0-9]*' "$f" \
        | sed 's/.*= *\([0-9]*\).*/\1/' | sort -n | uniq -d | tr '\n' ' ')
    echt=""
    for n in $dup; do
        namen=$(grep -a "^const \(SYS_\|CAP_\|WM_\|HND_\|AIO_\|RING_\)[A-Z0-9_]*: u64 = $n\$" "$f" \
            | sed 's/^const \([A-Z0-9_]*\).*/\1/')
        rest=$(printf '%s\n' "$namen" | grep -vc '_BASE$\|_MAXNR$\|^SYS_MARK$\|^SYS_LEAVE$')
        [ "$rest" -gt 1 ] && echt="$echt $n"
    done
    [ -z "$echt" ] && ok "$f: keine Aufrufnummer doppelt vergeben" \
                   || bad "$f: doppelte Aufrufnummern:$echt"
done

# 1b. Kernel und libc sagen dasselbe. Der Block 1986..1991 liegt direkt
#     hinter dem der Runde ASYNC (1980..1985).
for n in RING_VERSION:1986 RING_SETUP:1987 RING_MAP:1988 \
         RING_ENTER:1989 RING_CLOSE:1990; do
    name=${n%%:*}; want=${n##*:}
    k=$(sed -n "s/^const $name: u64 = \([0-9]*\).*/\1/p" kernel/sys.fi | head -1)
    l=$(sed -n "s/^const $name: u64 = \([0-9]*\).*/\1/p" lib/libc/kcall.fi | head -1)
    if [ "$k" = "$want" ] && [ "$l" = "$want" ]; then ok "$name = $want in Kernel und libc"
    else bad "$name: Kernel='$k' libc='$l', erwartet $want"; fi
done
# RING_INFO gibt Innenzahlen des Kerns heraus und ist nur im
# Selbsttestmodus erreichbar -- es gehoert deshalb NICHT in die libc.
if grep -qa '^const RING_INFO' lib/libc/kcall.fi; then
    bad "RING_INFO steht in der libc -- ein Testfenster im Regelbetrieb"
else
    ok "RING_INFO (1991) steht NICHT in der libc: kein Testfenster fuer Programme"
fi

# 1c. Die Grenze von `kdata` steht ZWEIMAL im Baum und muss gleich sein.
kk=$(sed -n 's/^const KDATA_SIZE: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/kstate.fi | head -1)
kb=$(sed -n 's/.*\.set KDATA_SIZE, \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/arch/x86_64/boot.s | head -1)
if [ "$kk" = "$kb" ] && [ -n "$kk" ]; then ok "KDATA_SIZE: kstate.fi und boot.s sagen beide $kk"
else bad "KDATA_SIZE: kstate.fi='$kk', boot.s='$kb'"; fi

# 1d. Kein Bereich ueberschneidet einen anderen.
if python3 tools/kernel/memmap.py > "$TMPD/memmap.txt" 2>&1; then
    ok "memmap.py: $(tail -1 "$TMPD/memmap.txt")"
else
    bad "memmap.py meldet Kollisionen"; sed 's/^/        /' "$TMPD/memmap.txt" | head -10
fi

# 1e. DER RINGKOPF STEHT AN DREI STELLEN, und alle drei muessen
#     dasselbe sagen: der Kern schreibt ihn, `uprog.fi` liest ihn im
#     Selbsttest, die libc liest ihn fuer jedes Programm.
felder="RH_MAGIC RH_VERSION RH_SQE RH_CQE RH_SQMASK RH_CQMASK RH_SQOFF \
RH_CQOFF RH_SQHEAD RH_SQTAIL RH_CQHEAD RH_CQTAIL RH_FLAGS RH_DROPPED \
RH_OVER RH_BYTES RH_ID"
schief=""
for f in $felder; do
    a=$(sed -n "s/^const $f: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p" kernel/ring.fi | head -1)
    b=$(sed -n "s/^const $f: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p" kernel/uprog.fi | head -1)
    c=$(sed -n "s/^const $f: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p" lib/libc/io.fi | head -1)
    if [ -z "$a" ] || [ "$a" != "$b" ] || [ "$a" != "$c" ]; then
        schief="$schief $f($a/$b/$c)"
    fi
done
[ -z "$schief" ] && ok "der Ringkopf: 17 Felder, dreimal derselbe Versatz (ring.fi, uprog.fi, io.fi)" \
                 || bad "Ringkopf uneinheitlich:$schief"
# Und der Fertigsatz ist DERSELBE wie in Runde ASYNC -- diese Runde
# ersetzt den WEG der Eintraege, nicht ihre Form.
ac=$(sed -n 's/^const C_BYTES: u64 = \([0-9]*\).*/\1/p' kernel/async.fi | head -1)
rc=$(sed -n 's/^const CQE_BYTES: u64 = \([0-9]*\).*/\1/p' kernel/ring.fi | head -1)
lc=$(sed -n 's/^const CQE_BYTES: u64 = \([0-9]*\).*/\1/p' lib/libc/io.fi | head -1)
if [ "$ac" = "$rc" ] && [ "$ac" = "$lc" ]; then
    ok "der Fertigsatz ist unveraendert $ac Oktett (async.fi, ring.fi, io.fi)"
else bad "Fertigsatz: async=$ac ring=$rc libc=$lc"; fi

# 1f. DIE RINGKACHEL LIEGT AUSSERHALB BEIDER MMAP-FENSTER. Das ist der
#     Grund, warum ein Programm seinem eigenen Kern die Seiten nicht
#     wegziehen kann -- ohne eine einzige Sonderregel in `munmap`.
rb=$(sed -n 's/^const RING_BASE: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/proc.fi | head -1)
bt=$(sed -n 's/^const BIG_TOP: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/proc.fi | head -1)
if [ "$rb" = "$bt" ]; then
    ok "RING_BASE ($rb) faengt genau da an, wo BIG_TOP aufhoert -- kein Fenster ueberlappt"
else bad "RING_BASE=$rb, BIG_TOP=$bt -- die Ringkachel koennte im mmap-Bereich liegen"; fi

# =====================================================================
echo "== 2. bauen: Kernel und /bin/ringt, mit beiden Uebersetzern =="
# =====================================================================
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" \
        || bad "$f.s laesst sich nicht assemblieren"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"

build_stage() { # 0 = firnc0, 1 = firnc1
    local s=$1 cc p
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    [ -x "$cc" ] || return 1
    "$cc" kernel/kmain.fi -o "$TMPD/k$s.o" >"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt den Kernel nicht"; sed 's/^/        /' "$TMPD/e$s" | head -8; return 1; }
    # DER NAME DIESER OBJEKTDATEI IST NICHT BELIEBIG. `kernel/kernel.ld`
    # sammelt den Ring-3-Code mit dem Muster `*uprog*.o(.text .text.*)`.
    # Heisst die Datei anders, landet `uprog.fi` im Kerneltext, und jedes
    # Programm in Ring 3 faellt beim ersten Befehl -- der Lauf ist dann
    # trotzdem "sauber" zu Ende, der Kernel sagt nur nichts mehr. Die
    # Runden HANDLE und ASYNC hatten diesen Fehler je einmal.
    "$cc" kernel/uprog.fi -o "$TMPD/uprog$s.o" >>"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s uebersetzt uprog.fi nicht"; sed 's/^/        /' "$TMPD/e$s" | head -8; return 1; }
    ld -n -T "$LDSCRIPT" \
        --defsym=KERNEL_MAIN="_F$s.kernel_main" \
        --defsym=KERNEL_TRAP="_F$s.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F$s.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F$s.tasks__main" \
        --defsym=KERNEL_USER_START="_F$s.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F$s.smp__ap_main" \
        --defsym=USER_MAIN="_F$s.u_enter" \
        -o "$TMPD/k$s.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
        "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k$s.o" "$TMPD/uprog$s.o" 2>"$TMPD/ld$s.err" \
        || { bad "firnc$s: ld ist am Kernel gescheitert"; return 1; }
    objcopy -O elf32-i386 "$TMPD/k$s.elf" "$TMPD/k$s.mb" 2>/dev/null
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" >"$TMPD/e$p$s" 2>&1 \
            || { bad "firnc$s uebersetzt $p.fi nicht"; sed 's/^/        /' "$TMPD/e$p$s" | head -6; return 1; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>/dev/null \
            || { bad "firnc$s: ld ist an $p gescheitert"; return 1; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return 0
}
build_stage 0 || { echo "RING: $pass bestanden, $fail durchgefallen"; exit 1; }
ok "firnc0: Kernel + $(echo $PROGS | wc -w) Programme"
ZWEI=0
if build_stage 1; then
    ok "firnc1: dasselbe, aus dem in Firn geschriebenen Uebersetzer"
    ZWEI=1
else
    note "firnc1 hat nicht gebaut -- die Messungen unten laufen mit firnc0"
fi

undef=$(nm -u "$TMPD/ringt0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "/bin/ringt hat keinen undefinierten Namen -- die libc-Anbindung ist vollstaendig" \
                || bad "undefinierte Namen in ringt: $undef"

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py hat ein OFS-Abbild mit /bin/ringt gebaut" \
    || { bad "mkfs.py fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt"; }

run_kernel() { # abbild anhang ausgabe [weitere qemu-argumente]
    local image=$1 append=$2 out=$3
    shift 3
    timeout 300 $QEMU_X86 -kernel "$image" -m 128 -append "$append" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}
run_disk() { # abbild anhang ausgabe
    local copy="$TMPD/live.img"
    cp "$TMPD/disk.img" "$copy"
    run_kernel "$1" "$2" "$3" -drive "file=$copy,format=raw,if=ide,index=0"
}
saubere() { tr -d '\000' < "$1" > "$2"; }

# =====================================================================
echo "== 3. die sieben Fehlerklassen, aus Ring 3 ($OSUM_QEMU_ACCEL) =="
# =====================================================================
T0=$(date +%s%N)
run_kernel "$TMPD/k0.mb" "uring" "$TMPD/r0.txt"
rc=$?
T1=$(date +%s%N)
saubere "$TMPD/r0.txt" "$TMPD/r0.clean"
F="$TMPD/r0.clean"
[ "$rc" -eq 21 ] && ok "der Kernel hat selbst Schluss gemacht (Beendigungscode 21)" \
                 || { bad "QEMU-Beendigungscode $rc, erwartet 21"; tail -8 "$F" | sed 's/^/        /'; }
note "Laufzeit dieses Abschnitts: $(( (T1-T0)/1000000 )) ms mit $OSUM_QEMU_ACCEL"

echo "   -- das Grundgeruest: aufsetzen, abbilden, ein Auftrag hin und zurueck"
for z in ring-fassung-da ring-aufgesetzt grund-kennung grund-fassung \
         grund-laenge grund-maske grund-ein-auftrag grund-kennzahl \
         grund-kein-munmap grund-speicher; do
    zusage "$F" "$z"
done

echo "   -- (a) DER ABGABESATZ WIRD NACH DER ABGABE GEAENDERT (die Kopierregel)"
for z in a-abgegeben a-kopie-haelt a-kopie-puffer a-fremder-puffer-leer; do
    zusage "$F" "$z"
done

echo "   -- (b) KOPF UND SCHWANZ SIND GELOGEN"
for z in b-riesiger-schwanz b-rueckwaerts-schwanz b-kopf-steht \
         b-badsq-gezaehlt b-danach-heil b-fertigkopf-verbogen; do
    zusage "$F" "$z"
done

echo "   -- (c) der Ring ist voll: Rueckstau statt Verwerfen"
for z in c-acht-in-flug c-rueckstau c-satz-bleibt-da c-kein-verlust \
         c-kein-leck; do
    zusage "$F" "$z"
done

echo "   -- (e) das Handle wird geschlossen, der Platz neu vergeben"
for z in e-selber-platz e-veraltet e-nicht-das-neue-ding; do
    zusage "$F" "$z"
done

echo "   -- (f) ein fremder Ring, und (d) der Prozesstod"
for z in f-fremdes-handle-map f-fremdes-handle-enter f-fremdes-handle-close \
         d-ring-abgeraeumt d-rahmen-zurueck d-kein-auftrag; do
    zusage "$F" "$z"
done

echo "   -- (g) die Weckregel, und der Auftrag OHNE Systemaufruf"
for z in g-flagge-gesetzt g-nach-anstoss-da g-kicks-gezaehlt \
         o-ohne-syscall o-kein-ring-enter o-ernte-gestiegen ring-kein-leck; do
    zusage "$F" "$z"
done

exitcode=$(sed -n 's/^ring: ring 3 exit=\([0-9]*\).*/\1/p' "$F" | head -1)
num "gefallene Zusagen in Ring 3" "$exitcode" eq 0
gesamt=$(sed -n 's/^ring: \([0-9]*\)\/\([0-9]*\) Zusagen.*/\1/p' "$F" | head -1)
num "bestandene Zusagen" "$gesamt" eq 41

# =====================================================================
echo "== 4. die drei Gegenproben: was faellt, wenn die Regel fehlt =="
# =====================================================================
#
# EINE ZUSAGE, DIE AUCH OHNE IHREN CODE STEHT, MISST NICHTS.

run_kernel "$TMPD/k0.mb" "uring noringcopy" "$TMPD/nc.txt"
saubere "$TMPD/nc.txt" "$TMPD/nc.clean"
G="$TMPD/nc.clean"
gefallen "$G" "a-kopie-haelt" "noringcopy"
gefallen "$G" "a-kopie-puffer" "noringcopy"
gefallen "$G" "a-fremder-puffer-leer" "noringcopy"
# UND ZWAR MIT DEM WERT DES ANGREIFERS. Das Testprogramm schreibt nach
# der Abgabe die Kennzahl 0xBAD (2989) in seinen Abgabesatz; ohne die
# Kopierregel steht genau die in der Fertigmeldung. Das ist der Beweis,
# dass hier wirklich ein zweites Mal aus dem Speicher des Programms
# gelesen wurde -- und nicht irgendetwas anderes schiefging.
if grep -qa 'a-kopie-haelt   got=2989' "$G"; then
    ok "noringcopy: der Kern nimmt die Kennzahl des ANGREIFERS (0xBAD) -- genau der io_uring-Fehler"
else
    bad "noringcopy: 'a-kopie-haelt' faellt, aber nicht mit 2989 -- $(grep -a 'a-kopie-haelt' "$G" | head -1 | sed 's/^ *//')"
fi
# Die uebrigen Zusagen stehen auch ohne die Kopierregel: sie messen
# etwas anderes, und das gehoert dazugesagt.
ncrest=$(sed -n 's/^ring: \([0-9]*\)\/.*/\1/p' "$G" | head -1)
num "noringcopy: der Rest steht trotzdem" "$ncrest" eq 38

run_kernel "$TMPD/k0.mb" "uring noringsq" "$TMPD/ns.txt"
saubere "$TMPD/ns.txt" "$TMPD/ns.clean"
H="$TMPD/ns.clean"
gefallen "$H" "b-riesiger-schwanz" "noringsq"
gefallen "$H" "b-rueckwaerts-schwanz" "noringsq"
gefallen "$H" "b-badsq-gezaehlt" "noringsq"
# EHRLICH DAZU: ohne die Pruefung faellt nicht nur die eine Zusage. Der
# Kern arbeitet dann eine Million behauptete Abgabesaetze ab, und der
# Ring ist danach unbrauchbar -- fuenfzehn der einundvierzig Zusagen
# fallen. Das ist keine schlechte Gegenprobe, sondern eine sehr
# deutliche: die Pruefung traegt alles, was danach kommt.
nsrest=$(sed -n 's/^ring: \([0-9]*\)\/.*/\1/p' "$H" | head -1)
if [ -n "$nsrest" ] && [ "$nsrest" -le 30 ]; then
    ok "noringsq: der Ring ist danach unbrauchbar ($nsrest/41 stehen noch) -- die Pruefung traegt alles Weitere"
else
    bad "noringsq: $nsrest/41 stehen noch -- die Pruefung scheint nichts zu tragen"
fi

run_kernel "$TMPD/k0.mb" "uring noawork" "$TMPD/nw.txt"
saubere "$TMPD/nw.txt" "$TMPD/nw.clean"
I="$TMPD/nw.clean"
# OHNE ARBEITSFAEDEN GIBT ES KEINE RINGABFRAGE. Das ist der Nachweis,
# dass die Abgabe ohne Systemaufruf wirklich von einem anderen Faden
# abgeholt wird und nicht heimlich vom Abgebenden selbst.
gefallen "$I" "o-ohne-syscall" "noawork"
gefallen "$I" "o-ernte-gestiegen" "noawork"
gefallen "$I" "g-flagge-gesetzt" "noawork"

# =====================================================================
echo "== 5. die libc-Anbindung: /bin/ringt von der Platte =="
# =====================================================================
run_disk "$TMPD/k0.mb" "osum nokbd nosched noproc noring3 script=ringt;exit" "$TMPD/rt.txt"
saubere "$TMPD/rt.txt" "$TMPD/rt.clean"
R="$TMPD/rt.clean"
if grep -qa '^ringt: ' "$R"; then
    ok "/bin/ringt ist gelaufen ($(grep -ca '^ringt: ' "$R") Zeilen)"
else
    bad "/bin/ringt hat nichts gesagt"; tail -12 "$R" | sed 's/^/        /'
fi
num "ringt: der Speicher IST ein Ring" "$(rzahl "$R" istring)" eq 1
num "ringt: Abgabering 16 Saetze" "$(rzahl "$R" sqe)" eq 16
num "ringt: Fertigring DOPPELT so lang" "$(rzahl "$R" cqe)" eq 32
num "ringt: ein Satz gelegt" "$(rzahl "$R" one_gelegt)" eq 1
num "ringt: vier Oktett gelesen" "$(rzahl "$R" one_res)" eq 4
num "ringt: die Kennzahl kommt zurueck" "$(rzahl "$R" one_ud)" eq 4711
num "ringt: die Art kommt zurueck" "$(rzahl "$R" one_op)" eq 1
num "ringt: acht Saetze gelegt" "$(rzahl "$R" acht_gelegt)" eq 8
num "ringt: acht Meldungen geholt" "$(rzahl "$R" acht_holen)" eq 8
num "ringt: acht Oktett zusammen" "$(rzahl "$R" acht_summe)" eq 8
num "ringt: die Weckregel traegt" "$(rzahl "$R" weck_res)" eq 4
num "ringt: sechzehn passen hinein" "$(rzahl "$R" voll_passt)" eq 16
num "ringt: der siebzehnte nicht" "$(rzahl "$R" voll_nein)" eq 0
num "ringt: ein unsinniger Satz gibt -EINVAL" "$(rzahl "$R" quatsch_res)" eq 22
num "ringt: ... und zwar MIT der Kennzahl des Programms" "$(rzahl "$R" quatsch_ud)" eq 7777
num "ringt: genau eine Abgabe verworfen" "$(rzahl "$R" dropped)" eq 1
num "ringt: KEINE Fertigmeldung verloren" "$(rzahl "$R" overflow)" eq 0
num "ringt: die Fassung der Schnittstelle" "$(rzahl "$R" version)" eq 1

# =====================================================================
echo "== 6. die Leckzahlen =="
# =====================================================================
num "ring: aufgesetzt"        "$(zahl "$F" setups)"   ge 3
num "ring: ebenso viele abgebaut" "$(zahl "$F" closes)" eq "$(zahl "$F" setups)"
num "ring: Saetze geerntet"   "$(zahl "$F" harvest)"  ge 10
num "ring: Fertigmeldungen gestellt" "$(zahl "$F" posted)" ge 10
num "ring: unglaubwuerdige Schwaenze erkannt" "$(zahl "$F" badsq)" eq 2
num "ring: unglaubwuerdige Fertigkoepfe erkannt" "$(zahl "$F" badcq)" ge 1
# DIE ZAHLEN, DIE NULL SEIN MUESSEN.
num "ring: keine Ringtafel belegt"    "$(zahl "$F" used)"     eq 0
num "ring: kein Auftrag mehr an einem Ring" "$(zahl "$F" inflight)" eq 0
num "ring: die Auftragstafel ist leer" "$(zahl "$F" aioused)" eq 0
num "ring: keine Fertigmeldung uebergelaufen" "$(zahl "$F" overflow)" eq 0
num "ring: kein Zugriff auf einen fremden Ring gelungen" "$(zahl "$F" denied)" eq 0
num "ring: kein Arbeitsfaden mehr wach"  "$(zahl "$F" awake)" eq 0
# DIE RAHMEN. Ein Ring ist der erste Speicher dieses Systems, den ein
# unprivilegierter Prozess vom Rahmenverwalter bekommt. Die Differenz
# ist NICHT null, und zwar mit gutem Grund: die vier Arbeitsfaeden der
# Runde ASYNC entstehen bei der ersten Abgabe und behalten ihre
# Kernstapel (WORKERS * KSTACK_FRAMES Rahmen). Alles darueber hinaus
# waere ein Leck.
vor=$(zahl "$F" frames); nach=$(zahl "$F" "frames-after")
ks=$(sed -n 's/^const KSTACK_FRAMES: u64 = \([0-9]*\).*/\1/p' kernel/sched.fi | head -1)
wk=$(sed -n 's/^const WORKERS: u64 = \([0-9]*\).*/\1/p' kernel/async.fi | head -1)
if [ -n "$vor" ] && [ -n "$nach" ] && [ -n "$ks" ] && [ -n "$wk" ]; then
    erwartet=$(( vor - ks * wk ))
    if [ "$nach" = "$erwartet" ]; then
        ok "ring: die Rahmen stimmen auf den Rahmen genau ($vor -> $nach, davon $((ks*wk)) Kernstapel der $wk Arbeitsfaeden)"
    else
        bad "ring: Rahmen $vor -> $nach, erwartet $erwartet ($((ks*wk)) fuer die Arbeitsfaeden) -- Differenz $(( erwartet - nach ))"
    fi
else
    bad "ring: die Rahmenzahlen fehlen"
fi
note "die genaue Rahmenprobe steht in Ring 3: 'd-rahmen-zurueck' vergleicht"
note "vor und nach dem Tod eines Kindes mit eigenem Ring, auf den Rahmen genau."

# =====================================================================
echo "== 7. die Messung: ein Boot, drei Wege, dieselbe Roehre =="
# =====================================================================
#
# ABENCH UND RBENCH IN EINEM LAUF. Das ist keine Kosmetik: der synchrone
# Weg misst sich zwischen zwei Boots um bis zu 20 % anders (Zeitgeber,
# Cache, Zufall der Rahmenvergabe). Nur wenn "sync" in DEMSELBEN Boot
# steht wie "async" und "ring", sagen die Verhaeltnisse etwas.
#
# GEMESSEN WIRD AUF EINEM KERN. Die Messung laeuft in `kmain` VOR
# `smp.stage`, genau wie die der Runde ASYNC -- der zweite Prozessor ist
# zu diesem Zeitpunkt noch gar nicht gestartet. Das ist die harte
# Bedingung, unter der der synchrone Weg am besten dasteht, und es ist
# die ehrliche Vergleichsbedingung.
run_kernel "$TMPD/k0.mb" "abench rbench" "$TMPD/m.txt"
saubere "$TMPD/m.txt" "$TMPD/m.clean"
M="$TMPD/m.clean"
khz=$(sed -n 's/^ring: rbench-khz=\([0-9]*\).*/\1/p' "$M" | head -1)
[ -z "$khz" ] && khz=1
us() { echo "$(( $1 * 1000000 / khz )),$(( ($1 * 100000000 / khz) % 100 ))"; }
ops() { [ "$1" -gt 0 ] 2>/dev/null && echo $(( khz * 1000 / $1 )) || echo 0; }

s16=$(bzahl "$M" sync);   a1=$(azahl "$M" async1)
a4=$(azahl "$M" async4);  a16=$(azahl "$M" async16)
asub=$(azahl "$M" submit)
r1=$(bzahl "$M" ring1);   r4=$(bzahl "$M" ring4)
r16=$(bzahl "$M" ring16); rput=$(bzahl "$M" put)
s8=$(bzahl "$M" sync8);   r64=$(bzahl "$M" ring64)
f1=$(bzahl "$M" frei1);   f8=$(bzahl "$M" frei8); f32=$(bzahl "$M" frei32)
kicks=$(bzahl "$M" kicks); harv=$(bzahl "$M" harvest)
rby=$(bzahl "$M" bytes)

fehlt=0
for v in "$s16" "$a1" "$r1" "$rput" "$f8" "$kicks"; do
    [ -z "$v" ] && fehlt=1
done
[ "$fehlt" = 1 ] && bad "die Messung hat nicht alle Zahlen geliefert" \
                 || ok "die Messung hat alle Zahlen geliefert (TSC $khz kHz)"

printf '        %-26s %10s %10s %14s\n' "Weg (16 x 32 Oktett)" "Zyklen" "us" "Auftraege/s"
for z in "synchron:$s16" "async Tiefe 1:$a1" "async Tiefe 4:$a4" \
         "async Tiefe 16:$a16" "ring Tiefe 1:$r1" "ring Tiefe 4:$r4" \
         "ring Tiefe 16:$r16" "async nur Abgabe:$asub" \
         "ring nur Abgabe:$rput"; do
    n=${z%%:*}; v=${z##*:}
    [ -n "$v" ] && printf '        %-26s %10s %10s %14s\n' "$n" "$v" "$(us "$v")" "$(ops "$v")"
done
printf '        %-26s %10s %10s %14s\n' "Weg (64 x 8 Oktett)" "Zyklen" "us" "Auftraege/s"
for z in "synchron:$s8" "ring Tiefe 64:$r64" "ring frei, Buendel 1:$f1" \
         "ring frei, Buendel 8:$f8" "ring frei, Buendel 32:$f32"; do
    n=${z%%:*}; v=${z##*:}
    [ -n "$v" ] && printf '        %-26s %10s %10s %14s\n' "$n" "$v" "$(us "$v")" "$(ops "$v")"
done

# 7a. DIE ZAHL DIESER RUNDE. In den drei "frei"-Laeufen wurden 3 * 2112
#     Auftraege abgegeben und abgeholt -- und dabei KEIN EINZIGES MAL
#     `ring_enter` gerufen.
num "die Ernte lief ohne Anstoss: Auftraege durch den Ring" "$harv" ge 6000
# DIE ZAHL, UM DIE ES GEHT -- und sie ist ABSICHTLICH keine harte Null.
# Meistens ist sie null; wenn die Abgabewache in einer Pause aufgibt
# (RING_SPIN Runden ohne Arbeit), setzt der Kern die Weckflagge, das
# Programm sieht sie und stoesst EINMAL an. Genau dafuer ist die
# Weckregel da, und ein Test, der null verlangt, wuerde die Regel
# bestrafen, statt sie zu pruefen. Verlangt wird deshalb: hoechstens
# 32 Aufrufe fuer 6336 Auftraege -- also unter 5 je 1000, gegen 1063
# je 1000 in Runde ASYNC.
if [ -n "$kicks" ] && [ -n "$harv" ] && [ "$harv" -gt 0 ]; then
    je1000=$(( kicks * 1000 / harv ))
    if [ "$kicks" -le 32 ]; then
        ok "SYSTEMAUFRUFE FUER $harv AUFTRAEGE (ring_enter): $kicks -- das sind $je1000 je 1000"
    else
        bad "ring_enter wurde $kicks mal gerufen fuer $harv Auftraege ($je1000 je 1000)"
    fi
else
    bad "die Aufrufzahlen fehlen"
fi
note "Systemaufrufe je 1000 abgeschlossene Auftraege:"
note "  synchron     1000 (ein read ist ein Aufruf)"
note "  Runde ASYNC  1000 Abgaben + mindestens 63 Abholungen (min_complete 16)"
note "  Runde RING      0, solange die Abgabewache wach ist; gemessen"
note "                  wurden $kicks Aufrufe fuer $harv Auftraege."
note "                  Gibt die Wache auf, kostet es EINEN Anstoss je"
note "                  Pause -- nicht einen je Auftrag."
note "EHRLICH: SYS_YIELD in der Warteschleife ist auf EINEM Kern"
note "unvermeidlich und in dieser Null NICHT enthalten -- gezaehlt sind"
note "die Aufrufe FUER ABGABE UND ABHOLUNG, und die sind wirklich null."

# 7b. Die Abgabe selbst. Das ist die Zahl, die sich am staerksten
#     bewegt hat, und sie ist der Kern der Sache: eine Abgabe ist kein
#     Systemaufruf mehr, sondern sechs Schreibzugriffe.
if [ -n "$rput" ] && [ -n "$asub" ] && [ "$rput" -gt 0 ]; then
    ok "nur die Abgabe: $asub Zyklen (ASYNC) -> $rput Zyklen (RING), Faktor $(( asub / rput ))"
else
    bad "die Abgabezahlen fehlen"
fi
num "eine Abgabe kostet keinen Systemaufruf mehr (< 400 Zyklen)" "$rput" lt 400

# 7c. UND DIE EHRLICHE ZEILE. Auf EINEM Kern schlaegt der Ring den
#     synchronen Weg nicht -- der Grund ist derselbe wie in Runde ASYNC
#     und steht in docs/RING-STATUS.md: die Arbeitsfaeden gehen intern
#     weiter SYNCHRON auf die Platte.
if [ -n "$s16" ] && [ -n "$r16" ]; then
    if [ "$r16" -lt "$s16" ]; then
        ok "ring Tiefe 16 ist schneller als synchron ($r16 gegen $s16 Zyklen)"
    else
        note "EHRLICH: ring Tiefe 16 ist $r16 Zyklen gegen synchron $s16 --"
        note "der synchrone Weg bleibt auf EINEM Kern vorn. Grund: die"
        note "Arbeitsfaeden arbeiten intern weiter synchron. Echte"
        note "Geraete-Warteschlangen (NVMe/AHCI) sind die naechste Runde."
        ok "die Zahl steht im Protokoll und wird nicht schoengerechnet"
    fi
fi
# Gegen Runde ASYNC gemessen -- DAS ist der Vergleich, den diese Runde
# gewinnen muss, denn sie ersetzt genau deren Abholweg.
#
# TIEFE 1 HAT EINE ANDERE SCHRANKE ALS 4 UND 16, UND DAS IST KEINE
# NACHSICHT. Bei Tiefe 1 besteht die Zeit fast vollstaendig aus dem
# Weg zum Arbeitsfaden und zurueck -- Zeitscheibe, Wecken, Umschalten.
# Der Systemaufruf, den diese Runde einspart, ist dort ein kleiner
# Posten. Vier saubere Laeufe hintereinander (ohne Last daneben) geben
# ring1 = 32630..32707 gegen async1 = 34663..34754, also rund -6 %;
# UNTER LAST kippt dieses Verhaeltnis, weil beide Zahlen von der
# Zeitscheibe abhaengen. Eine harte Schranke waere hier ein Test, der
# von der Auslastung des Wirts abhaengt, und das ist kein Test.
# Verlangt wird deshalb: nicht schlechter als 10 % ueber ASYNC.
for z in "1:$a1:$r1:110" "4:$a4:$r4:100" "16:$a16:$r16:100"; do
    t=$(echo "$z" | cut -d: -f1); av=$(echo "$z" | cut -d: -f2)
    rv=$(echo "$z" | cut -d: -f3); gr=$(echo "$z" | cut -d: -f4)
    if [ -n "$av" ] && [ -n "$rv" ]; then
        if [ "$rv" -lt "$av" ]; then
            ok "Tiefe $t: der Ring schlaegt die Auftragsschicht ($rv gegen $av Zyklen, -$(( (av - rv) * 100 / av )) %)"
        else
            if [ $(( rv * 100 )) -le $(( av * gr )) ]; then
                ok "Tiefe $t: gleichauf mit der Auftragsschicht ($rv gegen $av Zyklen, Schranke $gr %)"
                note "Tiefe 1 ist der Weg zum Arbeitsfaden und zurueck, nicht der Systemaufruf."
            else
                bad "Tiefe $t: der Ring ist NICHT besser als ASYNC ($rv gegen $av)"
            fi
        fi
    fi
done
num "Speicherkosten je Ring (32 Saetze, in Oktett)" "$(zahl "$F" bytes)" eq 8192
num "Speicherkosten je Ring (64 Saetze, in Oktett)" "$rby" eq 12288

# =====================================================================
echo "== 8. beide Uebersetzer sagen dasselbe =="
# =====================================================================
if [ "$ZWEI" = 1 ]; then
    run_kernel "$TMPD/k1.mb" "uring" "$TMPD/r1.txt"
    rc1=$?
    saubere "$TMPD/r1.txt" "$TMPD/r1.clean"
    [ "$rc1" -eq 21 ] && ok "firnc1: der Kernel hat selbst Schluss gemacht" \
                      || bad "firnc1: Beendigungscode $rc1"
    e1=$(sed -n 's/^ring: ring 3 exit=\([0-9]*\).*/\1/p' "$TMPD/r1.clean" | head -1)
    num "firnc1: keine gefallene Zusage" "$e1" eq 0
    g1=$(sed -n 's/^ring: \([0-9]*\)\/.*/\1/p' "$TMPD/r1.clean" | head -1)
    num "firnc1: dieselben 41 Zusagen" "$g1" eq 41
    num "firnc1: Ringtafel leer" "$(zahl "$TMPD/r1.clean" used)" eq 0
else
    note "firnc1 nicht vorhanden -- Abschnitt uebersprungen"
fi

echo
echo "RING: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
