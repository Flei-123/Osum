#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/nvmeq/run.sh -- DER BEWEIS, DASS EIN AUFTRAG IN DER
# WARTESCHLANGE DES GERAETS LANDET UND NICHT IN EINEM WARTENDEN FADEN.
#
# WAS DIESE RUNDE BEHAUPTET, UND WAS NICHT.
#
# Sie behauptet zwei Dinge, und beide werden hier gemessen und nicht
# erzaehlt:
#
#   1. NIEMAND WARTET MEHR. Ein Lesevorgang ueber den Ring geht in die
#      Submission-Queue des NVMe-Controllers, das Geraet holt ihn sich
#      selbst, und der Interrupt bringt die Meldung zurueck. Die Zahl
#      dafuer ist `nvme.waits + nvme.spins` -- die `hlt` und die
#      Drehungen mit vollem Prozessor in `nvme.await`. Ueber die
#      Warteschlange MUSS sie sich um NULL bewegen.
#   2. DAS GERAET SIEHT NIE EINE ADRESSE DES PROGRAMMS. Was in einen
#      NVMe-Eintrag geschrieben wird, kommt aus dem DMA-Vorrat des
#      Kerns. Die Gegenprobe `nqnopool` nimmt stattdessen den Wert aus
#      dem geteilten Ring, und die Zusage `a-prp-aus-vorrat` MUSS damit
#      fallen.
#
# Sie behauptet NICHT, dass alles schneller ist. Abschnitt 6 sagt, ab
# welcher Tiefe der synchrone Weg geschlagen wird -- und bei Tiefe 1
# sagt er auch, dass er es nicht wird.
#
# Verwendung:  bash tools/nvmeq/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
. tools/nvmeq/bau.sh         # nq_bau, nq_stufe, nq_platten, nq_start

# NICHT `mktemp -d`: das gibt /tmp/tmp.XXXX, und auf einer Maschine, auf
# der mehrere Runden gleichzeitig laufen, raeumt frueher oder spaeter
# jemand genau dieses Muster weg -- mitten in diesem Lauf. Der Name hier
# gehoert dieser Runde allein.
TMPD=$(mktemp -d -t osum-nvmeq-XXXXXX)
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

# Eine Zahl aus einer Zeile "nvmeq: NAME=WERT" bzw. "qbench: NAME=WERT".
zahl()  { sed -n "s/^nvmeq: $2=\([0-9]*\).*/\1/p" "$1" | head -1; }
bzahl() { sed -n "s/^qbench: $2=\([0-9]*\).*/\1/p" "$1" | head -1; }

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
    echo "NVMEQ: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

# Die Kommandozeile jedes Laufs. `osum` mountet die Wurzel und ruft
# `k14_setup` (ohne das gibt es kein /dev und damit kein /dev/nvme0),
# `vfs` schaltet die Einhaengeschicht an, `nvme` den Controller,
# `nvmeq` den Selbsttest.
BASIS="osum nopwr vfs nvme nvmeq"

# =====================================================================
echo "== 1. die Nummern, die Speicherkarte und die Bereiche =="
# =====================================================================

# 1a. Kein Aufruf zweimal vergeben. Sockelnamen (*_BASE, *_MAXNR) sind
#     ABSICHTLICH doppelt: sie benennen dieselbe Nummer zweimal.
dup=$(grep -a '^const \(SYS_\|CAP_\|WM_\|HND_\|AIO_\|RING_\|NVMEQ_\)[A-Z0-9_]*: u64 = [0-9]*' kernel/sys.fi \
    | sed 's/.*= *\([0-9]*\).*/\1/' | sort -n | uniq -d | tr '\n' ' ')
echt=""
for n in $dup; do
    namen=$(grep -a "^const \(SYS_\|CAP_\|WM_\|HND_\|AIO_\|RING_\|NVMEQ_\)[A-Z0-9_]*: u64 = $n\$" kernel/sys.fi \
        | sed 's/^const \([A-Z0-9_]*\).*/\1/')
    rest=$(printf '%s\n' "$namen" | grep -vc '_BASE$\|_MAXNR$\|^SYS_MARK$\|^SYS_LEAVE$')
    [ "$rest" -gt 1 ] && echt="$echt $n"
done
[ -z "$echt" ] && ok "kernel/sys.fi: keine Aufrufnummer doppelt vergeben" \
               || bad "doppelte Aufrufnummern:$echt"

# 1b. Der Block liegt direkt hinter dem der Runde RING (1986..1991).
nb=$(sed -n 's/^const NVMEQ_BASE: u64 = \([0-9]*\).*/\1/p' kernel/sys.fi | head -1)
rm_=$(sed -n 's/^const RING_MAXNR: u64 = \([0-9]*\).*/\1/p' kernel/sys.fi | head -1)
if [ "$nb" = "1992" ] && [ "$rm_" = "1991" ]; then
    ok "NVMEQ_BASE=1992 liegt direkt hinter RING_MAXNR=1991"
else bad "NVMEQ_BASE='$nb', RING_MAXNR='$rm_'"; fi

# 1c. NVMEQ_INFO gibt Innenzahlen des Kerns heraus und darf deshalb
#     NICHT in der libc stehen -- ein Testfenster im Regelbetrieb ist
#     eine Hintertuer. Dieselbe Regel wie bei RING_INFO.
if grep -qa '^const NVMEQ_INFO' lib/libc/kcall.fi 2>/dev/null; then
    bad "NVMEQ_INFO steht in der libc -- ein Testfenster im Regelbetrieb"
else
    ok "NVMEQ_INFO (1993) steht NICHT in der libc"
fi

# 1d. Die Grenze von `kdata` steht ZWEIMAL im Baum und muss gleich sein.
kk=$(sed -n 's/^const KDATA_SIZE: u64 = \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/kstate.fi | head -1)
kb=$(sed -n 's/.*\.set KDATA_SIZE, \(0x[0-9A-Fa-f]*\).*/\1/p' kernel/arch/x86_64/boot.s | head -1)
if [ "$kk" = "$kb" ] && [ -n "$kk" ]; then ok "KDATA_SIZE: kstate.fi und boot.s sagen beide $kk"
else bad "KDATA_SIZE: kstate.fi='$kk', boot.s='$kb'"; fi

# 1e. Kein Bereich ueberschneidet einen anderen.
if python3 tools/kernel/memmap.py > "$TMPD/memmap.txt" 2>&1; then
    ok "memmap.py: $(tail -1 "$TMPD/memmap.txt")"
else
    bad "memmap.py meldet Kollisionen"; sed 's/^/        /' "$TMPD/memmap.txt" | head -10
fi

# 1f. DER NACHLAUFRING IST DOPPELT SO LANG WIE DIE FLUGTAFEL. Daraus --
#     und nur daraus -- folgt, dass er nicht ueberlaufen kann.
sl=$(sed -n 's/^const NQ_SLOTS: u64 = \([0-9]*\).*/\1/p' kernel/nvmeq.fi | head -1)
dn=$(sed -n 's/^const DONE_SLOTS: u64 = \([0-9]*\).*/\1/p' kernel/nvmeq.fi | head -1)
if [ -n "$sl" ] && [ "$dn" = "$((sl * 2))" ]; then
    ok "der Nachlaufring ist doppelt so lang wie die Flugtafel ($dn zu $sl)"
else bad "NQ_SLOTS=$sl, DONE_SLOTS=$dn -- das Verhaeltnis 1:2 stimmt nicht"; fi

# 1g. DIE WACHE STEHT VOR DER TUERKLINGEL. Das ist die Sicherheitszusage
#     der Runde, und sie laesst sich am Quelltext ablesen: `pool_holds`
#     muss in `push` VOR `nvme.doorbell` vorkommen.
pw=$(grep -n 'pool_holds(state, prp' kernel/nvmeq.fi | head -1 | cut -d: -f1)
pd=$(grep -n 'nvme.doorbell(state, q_get(state, q, QD_QID), 0, tail)' kernel/nvmeq.fi | head -1 | cut -d: -f1)
if [ -n "$pw" ] && [ -n "$pd" ] && [ "$pw" -lt "$pd" ]; then
    ok "die DMA-Wache (Zeile $pw) steht vor der Tuerklingel (Zeile $pd)"
else bad "pool_holds=$pw, doorbell=$pd -- die Wache steht nicht davor"; fi

# =====================================================================
echo "== 2. bauen, mit beiden Uebersetzern =="
# =====================================================================
nq_bau "$TMPD" || { bad "Assembler"; echo "NVMEQ: $pass bestanden, $fail durchgefallen"; exit 1; }
if nq_stufe 0; then ok "firnc0: Kernel und Programme"
else bad "firnc0 baut den Kernel nicht"; sed 's/^/        /' "$TMPD/e0" | head -10
     echo "NVMEQ: $pass bestanden, $fail durchgefallen"; exit 1; fi
ZWEI=0
if nq_stufe 1; then ok "firnc1: dasselbe, aus dem in Firn geschriebenen Uebersetzer"; ZWEI=1
else note "firnc1 hat nicht gebaut -- die Laeufe unten benutzen firnc0"; fi
nq_platten && ok "Wurzelplatte (OFS, mit /dev) und eine leere 8-MiB-NVMe-Platte" \
           || { bad "mkfs.py/dd fehlgeschlagen"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

# =====================================================================
echo "== 3. der Regellauf: die Warteschlange traegt ($OSUM_QEMU_ACCEL) =="
# =====================================================================
T0=$(date +%s%N)
nq_start k0 "$BASIS" "$TMPD/a.txt"
rc=$?
T1=$(date +%s%N)
A="$TMPD/a.txt.clean"
[ "$rc" -eq 21 ] && ok "der Kernel hat selbst Schluss gemacht (Beendigungscode 21)" \
                 || { bad "QEMU-Beendigungscode $rc, erwartet 21"; tail -8 "$A" | sed 's/^/        /'; }
note "Laufzeit dieses Abschnitts: $(( (T1-T0)/1000000 )) ms"
note "$(grep -a '^nvmeq: queues=' "$A" | head -1)"

echo "   -- das Grundgeruest: ein Auftrag geht durch das GERAET"
for z in q-fassung-da q-bereit q-warteschlangen q-tiefe q-geraet-da \
         q-muster-steht q-ein-auftrag q-daten-stimmen q-schnellweg \
         q-abgegeben q-niemand-wartet; do
    zusage "$A" "$z"
done

echo "   -- (a) EIN MANIPULIERTER PUFFER-ZEIGER ERREICHT DAS GERAET NICHT"
for z in a-wilder-zeiger a-wild-nicht-abgegeben a-prp-aus-vorrat \
         a-prp-nicht-die-programmadresse a-badprp-null; do
    zusage "$A" "$z"
done

echo "   -- (b) das Handle geht zu, waehrend Auftraege im Geraet stehen"
for z in b-alle-gemeldet b-veraltet b-kein-flug b-verweise-null \
         b-kein-auftrag; do
    zusage "$A" "$z"
done

echo "   -- (c) der Prozess stirbt mit Auftraegen im Geraet"
for z in c-kein-flug c-kein-auftrag c-kein-ring c-rahmen-zurueck; do
    zusage "$A" "$z"
done

echo "   -- (e) Rueckstau und (f) der Interrupt, und der Rueckfallweg"
for z in e-alle-gemeldet e-kein-verlust e-voll-gezaehlt \
         f-alle-gemeldet f-kein-doppel f-kein-verlorener-satz \
         r-roehre-geht r-roehre-kein-schnell q-kein-leck; do
    zusage "$A" "$z"
done

gef=$(grep -ac '^  \[FAIL\]' "$A")
num "gefallene Zusagen in Ring 3" "$gef" eq 0
num "bestandene Zusagen" "$(sed -n 's/^nvmeq: \([0-9]*\)\/\([0-9]*\) Zusagen.*/\1/p' "$A" | head -1)" eq 34

echo "   -- die Leckzahlen"
num "nvmeq: inflight (Eintraege beim Geraet)" "$(zahl "$A" inflight)" eq 0
num "nvmeq: done (Saetze im Nachlaufring)"    "$(zahl "$A" done)"     eq 0
num "nvmeq: lost (Nachlaufsaetze ohne Platz)" "$(zahl "$A" lost)"     eq 0
num "nvmeq: badprp (abgewiesene Adressen)"    "$(zahl "$A" badprp)"   eq 0
num "nvmeq: timeouts"                          "$(zahl "$A" timeouts)" eq 0
num "nvmeq: submits == completed" "$(zahl "$A" submits)" eq "$(zahl "$A" completed)"
num "nvmeq: fast (Auftraege ueber die Warteschlange)" "$(zahl "$A" fast)" ge 40
num "nvmeq: staled (Generationspruefung hat gegriffen)" "$(zahl "$A" staled)" eq 4
num "nvmeq: cancelled (Auftraege eines toten Prozesses)" "$(zahl "$A" cancelled)" ge 1
num "nvmeq: queues (Warteschlangenpaare)" "$(zahl "$A" queues)" ge 1
num "nvmeq: depth" "$(zahl "$A" depth)" eq 64
note "DMA-Vorrat: $(zahl "$A" poolbytes) Oktett, einmal beim Aufsetzen geholt"

# DIE RAHMENPROBE. Was hinterher fehlt, sind GENAU die Kernstapel der
# vier Arbeitsfaeden aus Runde ASYNC (4 * KSTACK_FRAMES), die bei der
# ersten Abgabe entstehen. Die Zahl wird aus dem Quelltext gerechnet und
# nicht hingeschrieben.
ks=$(sed -n 's/^const KSTACK_FRAMES: u64 = \([0-9]*\).*/\1/p' kernel/sched.fi | head -1)
wk=$(sed -n 's/^const WORKERS: u64 = \([0-9]*\).*/\1/p' kernel/async.fi | head -1)
v=$(zahl "$A" frames); n2=$(zahl "$A" frames-after)
if [ -n "$v" ] && [ -n "$n2" ] && [ -n "$ks" ] && [ -n "$wk" ]; then
    num "Rahmen nach dem Lauf (nur die $wk Kernstapel fehlen)" "$((v - n2))" eq "$((ks * wk))"
else bad "Rahmenprobe: frames='$v' after='$n2' kstack='$ks' workers='$wk'"; fi

# =====================================================================
echo "== 4. die sechs Gegenproben: was faellt, wenn die Regel fehlt =="
# =====================================================================

# ---- 4a. nqnopool: DIE WICHTIGSTE. Die Adresse fuer den NVMe-Eintrag
#          kommt aus dem geteilten Ring statt aus dem DMA-Vorrat.
nq_start k0 "$BASIS nqnopool" "$TMPD/nopool.txt"
P="$TMPD/nopool.txt.clean"
gefallen "$P" "a-prp-aus-vorrat" nqnopool
gefallen "$P" "a-prp-nicht-die-programmadresse" nqnopool
gefallen "$P" "a-badprp-null" nqnopool
num "nqnopool: badprp (die Wache hat angeschlagen)" "$(zahl "$P" badprp)" ge 1
# UND DIE ZAHL, AUF DIE ES ANKOMMT: das Geraet hat davon NICHTS gesehen.
num "nqnopool: submits (Eintraege, die beim Geraet lagen)" "$(zahl "$P" submits)" eq 0
num "nqnopool: der Kernel steht trotzdem" "$(grep -ac 'nvmeq: fertig' "$P")" ge 1

# ---- 4b. nqerr: DAS GERAET SAGT NEIN.
nq_start k0 "$BASIS nqerr" "$TMPD/err.txt"
E="$TMPD/err.txt.clean"
for z in d-alle-gemeldet d-fehler-kommt-an d-deverr-gezaehlt; do
    zusage "$E" "$z"
done
num "nqerr: deverr (Fertigmeldungen mit Status != 0)" "$(zahl "$E" deverr)" ge 4
num "nqerr: timeouts (kein Haenger)" "$(zahl "$E" timeouts)" eq 0
num "nqerr: inflight" "$(zahl "$E" inflight)" eq 0

# ---- 4c. nqtiny: DIE WARTESCHLANGE IST KURZ -> RUECKSTAU.
nq_start k0 "$BASIS nqtiny" "$TMPD/tiny.txt"
Y="$TMPD/tiny.txt.clean"
num "nqtiny: depth" "$(zahl "$Y" depth)" eq 4
for z in e-alle-gemeldet e-kein-verlust e-voll-gezaehlt; do
    zusage "$Y" "$z"
done
num "nqtiny: qfull (die Warteschlange war voll)" "$(zahl "$Y" qfull)" ge 1
num "nqtiny: fallback (der Rest ging ueber den Fadenweg)" "$(zahl "$Y" fallback)" ge 1
num "nqtiny: lost" "$(zahl "$Y" lost)" eq 0
num "nqtiny: gefallene Zusagen" "$(grep -ac '^  \[FAIL\]' "$Y")" eq 0

# ---- 4d. nqweg: DER INTERRUPT GEHT VERLOREN.
nq_start k0 "$BASIS nqweg" "$TMPD/weg.txt"
W="$TMPD/weg.txt.clean"
num "nqweg: irqs (die Oberhaelfte hat nichts abgeraeumt)" "$(zahl "$W" irqs)" eq 0
num "nqweg: polled (gefunden hat es das Nachsehen)" "$(zahl "$W" polled)" ge 1
num "nqweg: submits == completed -- trotzdem alles fertig" \
    "$(zahl "$W" submits)" eq "$(zahl "$W" completed)"
num "nqweg: inflight" "$(zahl "$W" inflight)" eq 0
num "nqweg: gefallene Zusagen (kein Haenger, nur langsamer)" \
    "$(grep -ac '^  \[FAIL\]' "$W")" eq 0

# ---- 4e. nqdouble: DER INTERRUPT KOMMT DOPPELT.
nq_start k0 "$BASIS nqdouble" "$TMPD/dbl.txt"
D="$TMPD/dbl.txt.clean"
num "nqdouble: lost (der erste Durchgang hat nichts liegen lassen)" \
    "$(zahl "$D" lost)" eq 0
num "nqdouble: submits == completed -- genau eine Meldung je Auftrag" \
    "$(zahl "$D" submits)" eq "$(zahl "$D" completed)"
num "nqdouble: spurious (der zweite Durchgang findet nichts)" \
    "$(zahl "$D" spurious)" ge 1
num "nqdouble: gefallene Zusagen" "$(grep -ac '^  \[FAIL\]' "$D")" eq 0

# ---- 4f. nqoff: DIE WEICHE IST AUS. Alles geht wieder den Fadenweg
#          der Runde RING -- und funktioniert.
nq_start k0 "$BASIS nqoff" "$TMPD/off.txt"
O="$TMPD/off.txt.clean"
num "nqoff: fast (Auftraege ueber die Warteschlange)" "$(zahl "$O" fast)" eq 0
num "nqoff: submits" "$(zahl "$O" submits)" eq 0
for z in r-roehre-geht r-roehre-kein-schnell q-kein-leck; do
    zusage "$O" "$z"
done
num "nqoff: gefallene Zusagen" "$(grep -ac '^  \[FAIL\]' "$O")" eq 0

# =====================================================================
echo "== 5. die Regression der Vorrunden =="
# =====================================================================
for t in ring async handle poll; do
    if [ -x "tools/$t/run.sh" ] || [ -f "tools/$t/run.sh" ]; then
        out=$(bash "tools/$t/run.sh" 2>&1 | tail -3)
        line=$(printf '%s\n' "$out" | grep -aiE '[0-9]+ (bestanden|passed)' | tail -1)
        # Die Laeufer schreiben ihr Ergebnis nicht alle gleich:
        # "0 durchgefallen", "0 gefallen", "0 failed" -- alle drei
        # kommen im Baum vor.
        case "$line" in
            *" 0 durchgefallen"*|*" 0 gefallen"*|*" 0 failed"*)
                ok "tools/$t/run.sh: $line" ;;
            "") bad "tools/$t/run.sh: keine Ergebniszeile" ;;
            *) bad "tools/$t/run.sh: $line" ;;
        esac
    fi
done

# =====================================================================
echo "== 6. die Messung: synchron gegen Fadenweg gegen Warteschlange =="
# =====================================================================
#
# EIN BOOT, DREI WEGE, DERSELBE DESKRIPTOR. Die Weiche wird zwischen
# den Reihen umgelegt (`NQ_INFO 36`) -- zwischen zwei Boots misst sich
# der synchrone Weg um bis zu zwanzig Prozent anders, und nur in EINEM
# Boot sagen die Verhaeltnisse etwas. Dieselbe Regel wie in Runde RING.
mess() { # <smp> <datei>
    nq_start k0 "osum nopwr vfs nvme nqmess" "$2" -smp "$1"
    return $?
}
mess 1 "$TMPD/m1.txt"
M1="$TMPD/m1.txt.clean"

zeig() { # datei ueberschrift
    local f=$1
    local khz sy r1 r4 r16 r64 q1 q4 q16 q64
    khz=$(sed -n 's/^nvmeq: qbench-khz=\([0-9]*\).*/\1/p' "$f" | head -1)
    printf '        %-26s %10s %10s %10s\n' "$2 ($(sed -n 's/^nvmeq: qbench-cpus=\([0-9]*\).*/\1/p' "$f" | head -1) Kerne)" "Zyklen" "us" "Auftr/s"
    for r in "synchron:sync" "ring Tiefe 1:ring1" "ring Tiefe 4:ring4" \
             "ring Tiefe 16:ring16" "ring Tiefe 64:ring64" \
             "nvmeq Tiefe 1:nq1" "nvmeq Tiefe 4:nq4" \
             "nvmeq Tiefe 16:nq16" "nvmeq Tiefe 64:nq64" \
             "ring frei B1:ringfrei1" "ring frei B8:ringfrei8" \
             "ring frei B32:ringfrei32" \
             "nvmeq frei B1:nqfrei1" "nvmeq frei B8:nqfrei8" \
             "nvmeq frei B32:nqfrei32"; do
        local name=${r%%:*} key=${r##*:} v
        v=$(bzahl "$f" "$key")
        [ -z "$v" ] && continue
        printf '        %-26s %10s %10s %10s\n' "$name" "$v" \
            "$(awk -v c="$v" -v k="$khz" 'BEGIN{printf "%.2f", c/(k/1000)}')" \
            "$(awk -v c="$v" -v k="$khz" 'BEGIN{printf "%.0f", (k*1000)/c}')"
    done
}
zeig "$M1" "EIN KERN"

# ---- UND DIE MESSUNG MIT MEHREREN KERNEN, DIE ES NICHT GIBT.
#
# Sie steht hier als LAUF und nicht als Behauptung: der Kernel wird mit
# -smp 2 und -smp 4 gestartet, und was dabei herauskommt, wird gedruckt.
# Beide Laeufe enden in einem Doppelfehler, und zwar an einer Stelle,
# die dieser Runde NICHT gehoert -- das wird eine Zeile tiefer
# nachgewiesen, indem derselbe Lauf mit ABGESCHALTETER Weiche
# wiederholt wird. Ist der Warteschlangenweg aus, sieht `nvmeq.fi`
# keinen einzigen Auftrag und weckt aus dem Interrupt niemanden; kracht
# es trotzdem, kann es nicht daran liegen.
for kerne in 2 4; do
    mess "$kerne" "$TMPD/m$kerne.txt"
    rcm=$?
    MK="$TMPD/m$kerne.txt.clean"
    if [ "$rcm" -eq 21 ] && [ -n "$(bzahl "$MK" nq16)" ]; then
        zeig "$MK" "$kerne KERNE"
    else
        note "-smp $kerne: Beendigungscode $rcm, $(grep -ac 'EXCEPTION' "$MK") Ausnahme(n) -- $(grep -a 'EXCEPTION' "$MK" | head -1 | sed 's/^\*\*\* //')"
        note "   letzte Zahl vor dem Abbruch: $(grep -a '^qbench:' "$MK" | tail -1)"
    fi
done
# DIE GEGENPROBE ZUM DOPPELFEHLER -- UND SIE IST EINE NOTIZ UND KEINE
# ZUSAGE, weil das Ergebnis nicht jedes Mal dasselbe ist.
#
# Mit ABGESCHALTETER Weiche sieht `nvmeq.fi` keinen einzigen Auftrag und
# weckt aus dem Interrupt niemanden. Trotzdem endete dieser Lauf am
# 30.08.2026 EINMAL im selben Doppelfehler und EINMAL sauber. Das heisst:
# der Fehler ist ein RENNEN, das es auch ohne diese Runde gibt -- und
# das die Interruptlast dieser Runde sehr viel wahrscheinlicher macht.
# Beides gehoert gesagt, und deshalb steht hier weder ein "gehoert nicht
# dieser Runde" noch ein "liegt an dieser Runde", sondern das, was der
# Lauf getan hat.
nq_start k0 "osum nopwr vfs nvme nqmess nqoff" "$TMPD/moff.txt" -smp 2
rco=$?
MO="$TMPD/moff.txt.clean"
if [ "$rco" -ne 21 ]; then
    note "-smp 2 MIT ABGESCHALTETER WEICHE: kracht auch ($(grep -a 'EXCEPTION' "$MO" | head -1 | sed 's/^\*\*\* //')) -- ohne einen einzigen Auftrag im Warteschlangenweg"
else
    note "-smp 2 MIT ABGESCHALTETER WEICHE: laeuft diesmal durch -- das Rennen trifft nicht jedes Mal"
fi

# DIE ENTSCHEIDENDE FRAGE, und sie wird hier beantwortet und nicht
# umschrieben: AB WELCHER TIEFE WIRD DER SYNCHRONE WEG GESCHLAGEN?
sy=$(bzahl "$M1" sync)
ab=""
for d in 1 4 16 64; do
    v=$(bzahl "$M1" "nq$d")
    [ -z "$v" ] && continue
    if [ -z "$ab" ] && [ "$v" -lt "$sy" ]; then ab=$d; fi
done
if [ -n "$ab" ]; then
    ok "der synchrone Weg wird ab Tiefe $ab geschlagen (synchron $sy, nvmeq $(bzahl "$M1" "nq$ab"))"
else
    bad "der synchrone Weg wird auf einem Kern NICHT geschlagen (synchron $sy)"
fi

# Der Warteschlangenweg gegen den FADENWEG -- der Vergleich innerhalb
# derselben Schicht: gleicher Ring, gleiches Programm, gleiche Bloecke,
# einmal mit und einmal ohne Geraetewarteschlange.
#
# STRENG AB TIEFE 4, UND BEI TIEFE 1 NICHT. Das ist keine Bequemlichkeit,
# sondern die Sache selbst: bei EINEM offenen Auftrag gibt es nichts
# nebeneinander zu tun. Der Fadenweg laesst den Arbeitsfaden den Auftrag
# gleich selbst ausfuehren; der Warteschlangenweg gibt ihn ans Geraet,
# wartet auf den Interrupt und laesst ihn von einem Faden abholen -- ein
# Uebergang mehr. Was diese Runde gewinnt, ist NEBENLAEUFIGKEIT und
# nicht Latenz, und eine Zusage, die bei Tiefe 1 etwas anderes
# verlangte, wuerde vom Wirt und seiner Auslastung abhaengen statt vom
# Kernel.
r1=$(bzahl "$M1" ring1); q1=$(bzahl "$M1" nq1)
if [ -n "$r1" ] && [ -n "$q1" ]; then
    if [ "$q1" -lt "$r1" ]; then
        note "Tiefe 1: Warteschlange $q1 < Fadenweg $r1 -- hier gewinnt sie, muss sie aber nicht"
    else
        note "Tiefe 1: Warteschlange $q1 > Fadenweg $r1 -- der Uebergang mehr, ohne etwas nebeneinander zu tun"
    fi
fi
for d in 4 16 64; do
    r=$(bzahl "$M1" "ring$d"); q=$(bzahl "$M1" "nq$d")
    [ -z "$r" ] && continue
    if [ "$q" -lt "$r" ]; then
        ok "Tiefe $d: Warteschlange $q < Fadenweg $r ($(awk -v a="$r" -v b="$q" 'BEGIN{printf "%.0f", (a-b)*100/a}') % schneller)"
    else
        bad "Tiefe $d: Warteschlange $q ist NICHT schneller als der Fadenweg $r"
    fi
done

echo "   -- die Lastzahl: wer wartet auf das Geraet?"
#
# `spins` sind die Drehungen in `nvme.await` MIT VOLLEM PROZESSOR,
# `waits` die `hlt`. Gemessen wird ueber die Tiefen 1/4/16 -- nicht
# ueber 64, denn dort ist die Geraetewarteschlange voll und ein Teil
# der Auftraege geht ueber den Fadenweg; die drehen dann natuerlich,
# und eine Lastzahl, die den Rueckstau mitmisst, misst nicht mehr, was
# sie behauptet.
num "synchron: Drehungen in nvme.await" "$(bzahl "$M1" spinssync)" ge 1
num "Fadenweg: Drehungen in nvme.await" "$(bzahl "$M1" spinsring)" ge 1
num "WARTESCHLANGE: Drehungen in nvme.await" "$(bzahl "$M1" spinsnq)" eq 0
num "WARTESCHLANGE: hlt in nvme.await"       "$(bzahl "$M1" waitsnq)" eq 0
note "fast=$(bzahl "$M1" fast) fallback=$(bzahl "$M1" fallback) irqs=$(bzahl "$M1" irqs) polled=$(bzahl "$M1" polled) timeouts=$(bzahl "$M1" timeouts)"

# =====================================================================
echo "== 7. derselbe Selbsttest mit firnc1 =="
# =====================================================================
if [ "$ZWEI" = 1 ]; then
    nq_start k1 "$BASIS" "$TMPD/b1.txt"
    B1="$TMPD/b1.txt.clean"
    num "firnc1: bestandene Zusagen" \
        "$(sed -n 's/^nvmeq: \([0-9]*\)\/\([0-9]*\) Zusagen.*/\1/p' "$B1" | head -1)" eq 34
    num "firnc1: gefallene Zusagen" "$(grep -ac '^  \[FAIL\]' "$B1")" eq 0
else
    note "firnc1 uebersprungen"
fi

echo
echo "NVMEQ: $pass bestanden, $fail durchgefallen  ($OSUM_QEMU_ACCEL)"
[ "$fail" -eq 0 ] || exit 1
exit 0
