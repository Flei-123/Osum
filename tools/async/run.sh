#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/async/run.sh -- DER BEWEIS, DASS DIE ASYNCHRONE AUFTRAGSSCHICHT
# TRAEGT, BEVOR DER RING DARAUF GEBAUT WIRD.
#
# WARUM DIESE RUNDE NACH HANDLE UND VOR RING KOMMT. Runde HANDLE hat die
# Lebensdauer eines Kernobjekts geordnet -- Verweiszaehler, Generation,
# Abbruch-Token -- aber sie hatte keinen Kunden: `req_begin` und
# `req_end` standen im selben Systemaufruf nebeneinander, und dazwischen
# konnte nichts geschehen. Erst diese Runde legt zwischen die beiden
# einen Zustandswechsel, einen Arbeitsfaden und beliebig viele
# Zeitscheiben eines anderen Prozesses. Damit wird die Zusage von Runde
# HANDLE ueberhaupt erst PRUEFBAR.
#
# Google hat 2023 berichtet, dass rund 60 % der eingereichten
# Linux-Kernel-Exploits aus io_uring stammten. Die Ursache war nicht der
# geteilte Speicher und nicht die Ringform, sondern GENAU DIESE SCHICHT:
# ein Auftrag, der ein Objekt meint, das inzwischen ein anderes ist.
# Deshalb hat hier jede Zusage eine GEGENPROBE, die sie absichtlich
# kaputtmacht -- eine Zusage, die auch ohne ihren Code steht, misst
# nichts.
#
# WAS GEMESSEN WIRD:
#
#   1. DIE NUMMERNTAFEL. Sechs neue Aufrufe im Kernel und in der libc,
#      und keine Nummer doppelt. Das ist die Lehre aus der Runde mit der
#      zweimal vergebenen 1320.
#   2. DIE SPEICHERKARTE. Diese Runde laesst `kdata` von 0x80000 auf
#      0x90000 wachsen -- dieselbe Zahl steht in `kstate.fi` UND in
#      `kernel/arch/x86_64/boot.s`, und beide werden hier verglichen.
#      Dazu `memmap.py`: kein Bereich ueberschneidet einen anderen.
#   3. ZWEIUNDDREISSIG ZUSAGEN AUS RING 3 (`uprog.u_async`) ueber die
#      sechs Fehlerklassen (a) bis (f), jede einzeln nachgelesen.
#   4. SIEBEN WEITERE auf einem echten Dateisystem (`uprog.u_asyncfs`):
#      asynchron oeffnen, lesen, auf den Traeger druecken, schliessen.
#   5. DREI GEGENPROBEN, und jede schaltet Zusagen aus:
#        noagen   -- der Arbeitsfaden fragt die Generation NICHT.
#                    "b-veraltet" und "b-nicht-das-neue-ding" MUESSEN
#                    fallen: der alte Auftrag trifft das neue Objekt.
#                    Das ist der io_uring-Fehler, absichtlich wieder
#                    eingebaut.
#        noareap  -- ein sterbender Prozess raeumt seine Auftraege NICHT
#                    ab. "d-drei-abgeraeumt" MUSS fallen.
#        noawork  -- es laufen KEINE Arbeitsfaeden. Mehrere Zusagen
#                    MUESSEN fallen -- das ist der Nachweis, dass die
#                    Arbeit wirklich woanders geschieht.
#   6. DIE LIBC-ANBINDUNG, von der Platte: `/bin/aiot` ist ein
#      gewoehnliches Programm, gebunden gegen `lib/libc/io.fi`, geladen
#      vom ELF-Lader, gestartet von der Shell. Eine libc-Anbindung, die
#      niemand uebersetzt, ist eine Behauptung.
#   7. DIE LECKZAHLEN. Nach einem Lauf, in dem jeder Prozess ordentlich
#      geendet hat, MUSS die Auftragstafel leer sein, kein Handle-Auftrag
#      mehr in Flug und kein Ring eine Meldung verloren haben.
#   8. DIE MESSUNG. Latenz und Durchsatz bei 1, 4 und 16 gleichzeitig
#      offenen Auftraegen, gegen den synchronen Weg. Die Zahlen stehen
#      im Protokoll; die Auswertung in docs/ASYNC-STATUS.md.
#   9. BEIDE UEBERSETZER. firnc0 und firnc1 bauen denselben Kernel.
#
# Verwendung:  bash tools/async/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo aiot"
BLOCKS=4096

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()   { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note() { printf '        %s\n' "$1"; }

has()    { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht da sein" || ok "$3"; }

num() { # name wert op erwartet
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}

# Eine Zahl aus einer Zeile "async: NAME=WERT".
zahl()  { sed -n "s/^async: $2=\([0-9]*\).*/\1/p" "$1" | head -1; }
# ... und aus "abench: NAME=WERT".
bzahl() { sed -n "s/^abench: $2=\([0-9]*\).*/\1/p" "$1" | head -1; }
# ... und aus "aiot: NAME = WERT" (mit Vorzeichen).
azahl() { sed -n "s/^aiot: $2 = \(-\{0,1\}[0-9]*\).*/\1/p" "$1" | head -1; }

# Eine einzelne Zusage aus Ring 3 nachlesen: "  [ ok ] NAME".
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
    echo "ASYNC: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

# =====================================================================
echo "== 1. die Nummern und die Speicherkarte, ohne den Kernel zu starten =="
# =====================================================================

# 1a. Kein Aufruf zweimal vergeben -- ueber die GANZE Tafel beider Dateien.
#     Sockelnamen (AIO_BASE = AIO_VERSION, HND_BASE = HND_VERSION,
#     CAP_BASE = CAP_VERSION, HND_MAXNR = HND_OBJINFO) sind ABSICHTLICH
#     doppelt: sie benennen dieselbe Nummer zweimal. Herausgerechnet wird
#     deshalb nur, was auch als *_BASE oder *_MAXNR dasteht.
#     SYS_MARK (1) und SYS_LEAVE (2) sind der ZWEITE Fall: sie gehoeren
#     zur Ausflug-ABI der Runde 59 und werden in `dispatch` VOR allem
#     anderen verteilt, und zwar nur, solange `kstate.EXCURSION` steht.
#     Sie bedeuten also nie gleichzeitig dasselbe wie SYS_WRITE und
#     SYS_OPEN. Sie stehen namentlich hier, damit diese Ausnahme
#     benannt ist statt uebersehen.
for f in kernel/sys/sys.fi lib/libc/kcall.fi; do
    dup=$(grep -a '^const \(SYS_\|CAP_\|WM_\|HND_\|AIO_\)[A-Z0-9_]*: u64 = [0-9]*' "$f" \
        | sed 's/.*= *\([0-9]*\).*/\1/' | sort -n | uniq -d | tr '\n' ' ')
    echt=""
    for n in $dup; do
        namen=$(grep -a "^const \(SYS_\|CAP_\|WM_\|HND_\|AIO_\)[A-Z0-9_]*: u64 = $n\$" "$f" \
            | sed 's/^const \([A-Z0-9_]*\).*/\1/')
        rest=$(printf '%s\n' "$namen" | grep -vc '_BASE$\|_MAXNR$\|^SYS_MARK$\|^SYS_LEAVE$')
        [ "$rest" -gt 1 ] && echt="$echt $n"
    done
    [ -z "$echt" ] && ok "$f: keine Aufrufnummer doppelt vergeben" \
                   || bad "$f: doppelte Aufrufnummern:$echt"
done

# 1b. Kernel und libc sagen dasselbe.
for n in AIO_VERSION:1980 AIO_SUBMIT:1981 AIO_WAIT:1982 AIO_CANCEL:1983 \
         AIO_STATE:1984 SYS_FSYNC:74; do
    name=${n%%:*}; want=${n##*:}
    k=$(sed -n "s/^const $name: u64 = \([0-9]*\).*/\1/p" kernel/sys/sys.fi | head -1)
    l=$(sed -n "s/^const $name: u64 = \([0-9]*\).*/\1/p" lib/libc/kcall.fi | head -1)
    if [ "$k" = "$want" ] && [ "$l" = "$want" ]; then ok "$name = $want in Kernel und libc"
    else bad "$name: Kernel='$k' libc='$l', erwartet $want"; fi
done

# 1c. Die Grenze von `kdata` steht ZWEIMAL im Baum und muss gleich sein.
kk=$(sed -n 's/^const KDATA_SIZE: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/lib/kstate.fi | head -1)
kb=$(sed -n 's/.*\.set KDATA_SIZE, \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/arch/x86_64/boot.s | head -1)
if [ "$kk" = "$kb" ] && [ -n "$kk" ]; then ok "KDATA_SIZE: kstate.fi und boot.s sagen beide $kk"
else bad "KDATA_SIZE: kstate.fi='$kk', boot.s='$kb'"; fi

# 1d. Und kein Bereich ueberschneidet einen anderen.
if python3 tools/kernel/memmap.py > "$TMPD/memmap.txt" 2>&1; then
    ok "memmap.py: $(tail -1 "$TMPD/memmap.txt")"
else
    bad "memmap.py meldet Kollisionen"; sed 's/^/        /' "$TMPD/memmap.txt" | head -10
fi

# =====================================================================
echo "== 2. bauen: Kernel und /bin/aiot, mit beiden Uebersetzern =="
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
    # sammelt den Ring-3-Code mit dem Muster `*uprog*.o(.text .text.*)`
    # in den Abschnitt `.utext` und schliesst ihn aus dem Kerneltext aus.
    # Heisst die Datei anders -- `u0.o` zum Beispiel --, landet `uprog.fi`
    # im Kerneltext, und jedes Programm in Ring 3 faellt beim ersten
    # Befehl. Der Lauf ist dann trotzdem "sauber" zu Ende: der Kernel
    # sagt nur nichts mehr. Runde HANDLE hat diesen Fehler schon einmal
    # gehabt; diese Runde hat ihn beim Abschreiben des Laeufers von POLL
    # ein zweites Mal geerbt.
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
build_stage 0 || { echo "ASYNC: $pass bestanden, $fail durchgefallen"; exit 1; }
ok "firnc0: Kernel + $(echo $PROGS | wc -w) Programme"
if build_stage 1; then
    ok "firnc1: dasselbe, aus dem in Firn geschriebenen Uebersetzer"
else
    note "firnc1 hat nicht gebaut -- die Messungen unten laufen mit firnc0"
fi

undef=$(nm -u "$TMPD/aiot0.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "/bin/aiot hat keinen undefinierten Namen -- die libc-Anbindung ist vollstaendig" \
                || bad "undefinierte Namen in aiot: $undef"

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py hat ein OFS-Abbild mit /bin/aiot gebaut" \
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

# =====================================================================
echo "== 3. die sechs Fehlerklassen, aus Ring 3 ($OSUM_QEMU_ACCEL) =="
# =====================================================================
T0=$(date +%s%N)
run_kernel "$TMPD/k0.mb" "async" "$TMPD/a0.txt"
rc=$?
T1=$(date +%s%N)
tr -d '\000' < "$TMPD/a0.txt" > "$TMPD/a0.clean"
F="$TMPD/a0.clean"
[ "$rc" -eq 21 ] && ok "der Kernel hat selbst Schluss gemacht (Beendigungscode 21)" \
                 || { bad "QEMU-Beendigungscode $rc, erwartet 21"; tail -8 "$F" | sed 's/^/        /'; }
note "Laufzeit dieses Abschnitts: $(( (T1-T0)/1000000 )) ms mit $OSUM_QEMU_ACCEL"

echo "   -- (a) das Handle wird geschlossen, waehrend der Auftrag laeuft"
zusage "$F" "a-auftrag-laeuft"
zusage "$F" "a-kein-free-in-flug"
zusage "$F" "a-ergebnis-vier"
zusage "$F" "a-danach-frei"
zusage "$F" "a-kein-leck"

echo "   -- (b) der Platz wird neu vergeben (die io_uring-Fehlerklasse)"
zusage "$F" "b-selber-platz"
zusage "$F" "b-veraltet"
zusage "$F" "b-nicht-das-neue-ding"
zusage "$F" "b-kein-leck"

echo "   -- (c) Abbruch, und GENAU EINE Fertigmeldung"
zusage "$F" "c-angelegt"
zusage "$F" "c-abgebrochen"
zusage "$F" "c-nach-abbruch-weg"
zusage "$F" "c-zweimal-abbrechen"
zusage "$F" "c-genau-eine-meldung"
zusage "$F" "c-laufender-abbruch"
zusage "$F" "c-kein-leck"

echo "   -- (e) Warteschlange voll, Zeitgrenze abgelaufen"
zusage "$F" "e-sechzehn-offen"
zusage "$F" "e-warteschlange-voll"
zusage "$F" "e-nichtblockierend"
zusage "$F" "e-zeitgrenze"
zusage "$F" "e-kein-leck"

echo "   -- (f) ein fremder Auftrag, und (d) der Prozesstod"
zusage "$F" "f-es-gibt-ihn-wirklich"
zusage "$F" "f-fremder-zustand"
zusage "$F" "f-fremder-abbruch"
zusage "$F" "d-tod-raeumt-ab"
zusage "$F" "d-drei-abgeraeumt"

echo "   -- die Arten: schreiben, schliessen"
zusage "$F" "arten-fassung"
zusage "$F" "arten-schreiben"
zusage "$F" "arten-schliessen"
zusage "$F" "arten-danach-zu"
zusage "$F" "arten-kein-leck"

echo "   -- und dieselben Arten auf einem Dateisystem"
zusage "$F" "fs-open-geht"
zusage "$F" "fs-read-vierzehn"
zusage "$F" "fs-fsync-ok"
zusage "$F" "fs-close-ok"
zusage "$F" "fs-danach-zu"
zusage "$F" "fs-open-fehlt"
zusage "$F" "fs-kein-leck"

has "$F" "async: 32/32 Zusagen" "das Programm zaehlt selbst 32 von 32"
has "$F" "asyncfs: 7/7 Zusagen" "und 7 von 7 auf dem Dateisystem"
has "$F" "async: ring 3 exit=0" "Beendigungscode 0: keine Zusage gefallen"

echo "   -- die Leckzahlen (sie sind der eigentliche Beweis)"
num "belegte Auftragsplaetze nach dem Lauf" "$(zahl "$F" used)" eq 0
num "laufende Auftraege nach dem Lauf"      "$(zahl "$F" live)" eq 0
num "verlorene Fertigmeldungen"             "$(zahl "$F" lost)" eq 0
num "Handle-Auftraege noch in Flug"         "$(zahl "$F" inflight)" eq 0
num "Objekte in der Objekttafel"            "$(zahl "$F" objects)" eq 0
num "Arbeitsfaeden"                         "$(zahl "$F" workers)" eq 4
num "Speicher je Auftrag in Oktett"         "$(zahl "$F" bytes)" eq 112
num "abgegebene Auftraege"                  "$(zahl "$F" submitted)" ge 20
num "abgebrochene Auftraege"                "$(zahl "$F" cancelled)" ge 17
num "an der Generation gescheiterte"        "$(zahl "$F" stale)" ge 1
num "Abgaben an voller Warteschlange"       "$(zahl "$F" full)" ge 1
num "Wartevorgaenge an der Zeitgrenze"      "$(zahl "$F" timeouts)" ge 1
num "beim Prozesstod abgeraeumte"           "$(zahl "$F" abandoned)" ge 3
num "Zugriffe auf fremde Auftraege"         "$(zahl "$F" denied)" ge 2
# DIE ZAHL, DIE DIE WARTESCHLEIFE ENTLARVT HAETTE. Ein `poll`-Auftrag,
# der auf sein Ereignis WARTET statt zu drehen, laesst die Arbeitsfaeden
# nur ein paar Dutzend Mal laufen. Die erste Fassung dieser Runde kam
# fuer dieselben Auftraege auf 525241.
num "Durchlaeufe der Arbeitsfaeden mit Arbeit" "$(zahl "$F" workruns)" lt 2000

# =====================================================================
echo "== 4. die drei Gegenproben: ohne sie beweist Abschnitt 3 nichts =="
# =====================================================================
run_kernel "$TMPD/k0.mb" "async noagen" "$TMPD/g1.txt"
tr -d '\000' < "$TMPD/g1.txt" > "$TMPD/g1.clean"
gefallen "$TMPD/g1.clean" "b-veraltet" "noagen"
gefallen "$TMPD/g1.clean" "b-nicht-das-neue-ding" "noagen"
note "noagen ist der io_uring-Fehler, absichtlich wieder eingebaut: der alte"
note "Auftrag trifft das neue Objekt. Mit der Generationspruefung: -ESTALE."

run_kernel "$TMPD/k0.mb" "async noareap" "$TMPD/g2.txt"
tr -d '\000' < "$TMPD/g2.txt" > "$TMPD/g2.clean"
gefallen "$TMPD/g2.clean" "d-drei-abgeraeumt" "noareap"
num "ohne Aufraeumen beim Prozesstod: abgeraeumte Auftraege" \
    "$(zahl "$TMPD/g2.clean" abandoned)" eq 0

run_kernel "$TMPD/k0.mb" "async noawork" "$TMPD/g3.txt"
tr -d '\000' < "$TMPD/g3.txt" > "$TMPD/g3.clean"
num "ohne Arbeitsfaeden: laufende Faeden" "$(zahl "$TMPD/g3.clean" workers)" eq 0
gf=$(grep -ca '\[FAIL\]' "$TMPD/g3.clean")
num "ohne Arbeitsfaeden gefallene Zusagen" "${gf:-0}" ge 5
note "noawork fuehrt jeden Auftrag im ABGEBENDEN Prozess aus. Dass dabei"
note "mehrere Zusagen fallen, ist der Nachweis, dass die Arbeit im"
note "Regelbetrieb wirklich woanders geschieht -- und nicht nur so heisst."

# =====================================================================
echo "== 5. die libc-Anbindung: /bin/aiot von der Platte =="
# =====================================================================
run_disk "$TMPD/k0.mb" "osum nokbd nosched noproc noring3 async script=aiot;exit" \
         "$TMPD/d0.txt"
rc=$?
tr -d '\000' < "$TMPD/d0.txt" > "$TMPD/d0.clean"
D="$TMPD/d0.clean"
[ "$rc" -eq 21 ] && ok "der Lauf von der Platte ist sauber zu Ende gekommen" \
                 || { bad "QEMU-Beendigungscode $rc, erwartet 21"; tail -8 "$D" | sed 's/^/        /'; }

num "aio_version"                        "$(azahl "$D" version)"     eq 1
num "eine Fertigmeldung fuer ein read"   "$(azahl "$D" read_got)"    eq 1
num "und ihr Ergebnis: vier Oktette"     "$(azahl "$D" read_res)"    eq 4
num "die Kennzahl kommt unveraendert zurueck" "$(azahl "$D" read_ud)" eq 4711
num "und die Art des Auftrags"           "$(azahl "$D" read_op)"     eq 1
num "asynchron geschrieben: acht Oktette" "$(azahl "$D" write_res)"  eq 8
num "und sie stehen wirklich im Rohr"    "$(azahl "$D" write_da)"    eq 8
num "acht Auftraege, EIN Aufruf von aio_wait" "$(azahl "$D" batch_n)" eq 8
num "Summe der Ergebnisse (8 x 4)"       "$(azahl "$D" batch_summe)" eq 32
num "Summe der Kennzahlen (1..8) -- acht VERSCHIEDENE Auftraege" \
    "$(azahl "$D" batch_uzsm)" eq 36
num "asynchron geoeffneter Deskriptor"   "$(azahl "$D" file_fd)"     ge 3
num "asynchron gelesen, obwohl der Pfadpuffer inzwischen Muell ist" \
    "$(azahl "$D" file_len)" eq 12
num "asynchrones fsync"                  "$(azahl "$D" file_fsync)"  eq 0
num "asynchrones close"                  "$(azahl "$D" file_close)"  eq 0
num "ein Pfad, den es nicht gibt: -ENOENT in der MELDUNG" \
    "$(azahl "$D" file_fehlt)" eq 2
num "aio_poll vor dem Ereignis: noch nichts fertig" "$(azahl "$D" poll_vorher)" eq 0
num "und danach POLLIN -- readiness als completion" "$(azahl "$D" poll_revent)" eq 1
num "die Art des Auftrags ist poll"      "$(azahl "$D" poll_op)"     eq 6
num "abbrechen gibt 0"                   "$(azahl "$D" cancel_call)" eq 0
num "und die Meldung -ECANCELED"         "$(azahl "$D" cancel_res)"  eq 125
num "genau eine Meldung, keine zweite"   "$(azahl "$D" cancel_zwei)" eq 0
num "sechzehn Auftraege gehen"           "$(azahl "$D" voll_wieg)"   eq 16
num "der siebzehnte gibt -EAGAIN"        "$(azahl "$D" voll_fehler)" eq 11
num "und alle sechzehn kommen zurueck"   "$(azahl "$D" voll_weg)"    eq 16

# =====================================================================
echo "== 6. die Messung: Latenz und Durchsatz gegen den synchronen Weg =="
# =====================================================================
run_kernel "$TMPD/k0.mb" "abench unix" "$TMPD/b0.txt"
tr -d '\000' < "$TMPD/b0.txt" > "$TMPD/b0.clean"
B="$TMPD/b0.clean"
sy=$(bzahl "$B" sync); a1=$(bzahl "$B" async1); a4=$(bzahl "$B" async4)
a16=$(bzahl "$B" async16); su=$(bzahl "$B" submit); by=$(bzahl "$B" bytes)
khz=$(zahl "$B" abench-khz)
if [ -n "$khz" ] && [ "$khz" -gt 0 ] 2>/dev/null && [ -n "$a16" ]; then
    us()  { python3 -c "print('%.2f' % ($1*1000.0/$khz))"; }
    ops() { python3 -c "print(int($khz*1000.0/$1))"; }
    note "TSC $khz kHz. Ein read von 32 Oktett aus einer Roehre, Median aus"
    note "33 Bloecken zu 16 Lesevorgaengen:"
    note "  synchron             $sy Zyklen = $(us "$sy") us    $(ops "$sy") Auftraege/s"
    note "  asynchron, Tiefe 1   $a1 Zyklen = $(us "$a1") us    $(ops "$a1") Auftraege/s"
    note "  asynchron, Tiefe 4   $a4 Zyklen = $(us "$a4") us    $(ops "$a4") Auftraege/s"
    note "  asynchron, Tiefe 16  $a16 Zyklen = $(us "$a16") us    $(ops "$a16") Auftraege/s"
    note "  nur die Abgabe       $su Zyklen = $(us "$su") us    (was der ABGEBER zahlt)"
    note "  Speicher je Auftrag  $by Oktett"
else
    bad "die Messung hat keine Zahlen geliefert"
fi
# DIE ZUSAGE, DIE DIESE RUNDE UEBERHAUPT RECHTFERTIGT: mehr gleichzeitig
# offene Auftraege muessen den Preis JE AUFTRAG senken. Tut das die Zahl
# nicht, hat die Schicht ihren Zweck verfehlt -- und das steht dann hier
# und nicht in einer Ausrede.
if [ -n "$a1" ] && [ -n "$a16" ]; then
    if [ "$a16" -lt "$a1" ]; then
        ok "die Tiefe zahlt sich aus: 16 offene Auftraege kosten je $a16 Zyklen, einer $a1"
    else
        bad "die Tiefe zahlt sich NICHT aus: 16 offene kosten je $a16, einer $a1"
    fi
fi
# UND DIE ZWEITE, DIE EHRLICHERE: die Abgabe allein muss deutlich
# billiger sein als der ganze synchrone Aufruf. Das ist die Zeit, die der
# abgebende Prozess wirklich spart -- und das ist der Gewinn, den diese
# Runde auf EINEM Kern nachweisen kann.
if [ -n "$su" ] && [ -n "$sy" ]; then
    if [ "$su" -lt "$sy" ]; then
        ok "der Abgeber zahlt $su statt $sy Zyklen je Lesevorgang"
    else
        bad "die Abgabe ($su) ist nicht billiger als der synchrone Aufruf ($sy)"
    fi
fi
num "Speicher je Auftrag in Oktett (Satz + Fertigmeldung)" "${by:-0}" eq 112

# =====================================================================
echo "== 7. derselbe Kernel aus dem zweiten Uebersetzer =="
# =====================================================================
if [ -f "$TMPD/k1.mb" ]; then
    run_kernel "$TMPD/k1.mb" "async" "$TMPD/a1.txt"
    tr -d '\000' < "$TMPD/a1.txt" > "$TMPD/a1.clean"
    has "$TMPD/a1.clean" "async: 32/32 Zusagen" "firnc1: dieselben 32 Zusagen"
    has "$TMPD/a1.clean" "asyncfs: 7/7 Zusagen" "firnc1: dieselben 7 auf dem Dateisystem"
    num "firnc1: belegte Auftragsplaetze" "$(zahl "$TMPD/a1.clean" used)" eq 0
else
    note "firnc1 fehlt -- Abschnitt 7 uebersprungen"
fi

echo
echo "ASYNC: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
exit 0
