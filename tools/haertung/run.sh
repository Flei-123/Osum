#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/haertung/run.sh -- RUNDE HAERTUNG: W^X, WACHSEITEN, ASLR, IOMMU.
#
# WAS DIESE RUNDE NICHT GEBRACHT HAT, damit die Zahlen unten richtig
# gelesen werden: SMEP und SMAP standen schon (Runde K10,
# `kernel/arch/x86_64/guard.fi`, nachgemessen von tools/guard/run.sh).
# Das NX-Bit gab es seit Runde K1, die Zeigerpruefung `proc.user_ok`
# seit Runde 62. Der urspruengliche Auftrag hielt SMEP fuer fehlend,
# weil er DATEIEN gezaehlt hatte und nicht Vorkommen.
#
# WAS SIE GEBRACHT HAT, und was hier nachgemessen wird:
#
#   1. W^X FUER DEN KERN SELBST. Die Identitaetsabbildung bestand aus
#      2-MiB-Kacheln mit den Bits 0x83: vorhanden, schreibbar, und ohne
#      NX also auch ausfuehrbar. JEDE Seite des Kerns war damit
#      schreibbar UND ausfuehrbar -- sein Code liess sich ueberschreiben,
#      sein Stapel liess sich anspringen. SMEP half dagegen nicht: SMEP
#      verbietet Ring 0 nur Seiten mit BENUTZERBIT, und keine dieser
#      Seiten hatte eins.
#   2. WACHSEITEN unter jedem Kernstapel -- den acht Rahmen je Aufgabe
#      und den vier festen aus `boot.s`.
#   3. ASLR fuer die Stapel, mit gemessener Entropie.
#   4. Die IOMMU wird GELESEN und gemeldet, nicht gebaut.
#
# JEDE ZUSAGE HAT EINE GEGENPROBE. Das ist der Punkt: ein Kernel, der
# die Bits setzt und trotzdem durchlaesst, saehe von aussen genauso aus
# wie einer, der schuetzt. Die Gegenproben bauen den Angriff wirklich:
#
#   `wxwrite`  der Kern schreibt in seinen EIGENEN Code
#   `wxexec`   der Kern springt in seinen eigenen Datenbereich
#   `kblow`    der Kern laeuft seinen Stapel hinunter
#
# und daneben stehen `nowx`, `nonx`, `noguard`, die den Schutz
# abschalten. Erst der UNTERSCHIED zwischen beiden Laeufen ist ein
# Nachweis.

set -u
cd "$(dirname "$0")/../.." || exit 1

BESTANDEN=0
GEFALLEN=0

ok() { printf '  OK    %s\n' "$1"; BESTANDEN=$((BESTANDEN + 1)); }
nein() { printf '  FEHLER %s\n' "$1"; GEFALLEN=$((GEFALLEN + 1)); }

gleich() {
    if [[ "$2" == "$3" ]]; then ok "$1: $2"; else
        nein "$1: $2 statt $3"; fi
}

drin() {
    if grep -aq -- "$2" "$3"; then ok "$1"; else
        nein "$1 (nicht gefunden: $2)"; fi
}

nicht_drin() {
    if grep -aq -- "$2" "$3"; then nein "$1 (gefunden: $2)"; else
        ok "$1"; fi
}

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "HAERTUNG: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# Ein Lauf. $1 Kommandozeile, $2 Ausgabedatei, Rest: QEMU-Argumente.
# Rueckgabe: 21 = der Kernel hat sich selbst beendet, 63 = er ist an
# einer Ausnahme stehengeblieben.
lauf() {
    local app=$1 out=$2
    shift 2
    timeout 120 qemu-system-x86_64 -kernel "$TMPD/k.img" -m 512 \
        -append "$app" -serial "file:$out" -display none -no-reboot \
        -cpu max "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    return $?
}

feld() { grep -a "$2" "$1" | tail -1 | sed -E "s/.*$3=([0-9a-fx]+).*/\1/"; }

echo "== 0. bauen =="
if ! ./tools/build-kernel.sh "$TMPD/k.img" >"$TMPD/bau.log" 2>&1; then
    tail -20 "$TMPD/bau.log"
    echo "HAERTUNG: der Bau ist gefallen"
    exit 1
fi
ok "das Abbild steht"

# ---------------------------------------------------------------------
echo "== 1. W^X: keine Seite ist schreibbar UND ausfuehrbar =="
rc=0; lauf "" "$TMPD/voll.log" || rc=$?
gleich "der volle Lauf kommt durch" "$rc" 21
drin "der Durchgang meldet sich" "hard: splits=" "$TMPD/voll.log"
gleich "Verstoesse beim Nachzaehlen der TABELLEN" \
    "$(feld "$TMPD/voll.log" 'hard: splits' viol)" 0
# Die Gegenprobe zur Zahl selbst: OHNE den Durchgang muessen es viele sein.
rc=0; lauf "nowx" "$TMPD/nowx.log" || rc=$?
gleich "ohne den Durchgang laeuft der Kern auch" "$rc" 21
V=$(feld "$TMPD/nowx.log" 'hard: splits' viol)
if [[ ${V:-0} -gt 100 ]]; then
    ok "und dann sind es $V Seiten, die W und X zugleich sind"
else
    nein "ohne den Durchgang muessten es viele sein, es sind $V"
fi

echo "== 2. der Kerncode ist nicht mehr beschreibbar =="
rc=0; lauf "nokbd nosched noproc nofs noring3 wxwrite" "$TMPD/wxw.log" || rc=$?
gleich "der Schreibversuch in .text bleibt stehen" "$rc" 63
drin "und zwar als Schutzverletzung beim Schreiben" "err=0x3" "$TMPD/wxw.log"
nicht_drin "der Kern hat die Zelle NICHT bekommen" "hard: got=" "$TMPD/wxw.log"
rc=0; lauf "nokbd nosched noproc nofs noring3 wxwrite nowx" "$TMPD/wxw0.log" || rc=$?
gleich "derselbe Schreibversuch ohne W^X kommt durch" "$rc" 21
drin "und die Zelle steht danach anders da" "hard: got=0x90" "$TMPD/wxw0.log"

echo "== 3. aus Kerndaten laesst sich nichts ausfuehren =="
rc=0; lauf "nokbd nosched noproc nofs noring3 wxexec" "$TMPD/wxe.log" || rc=$?
gleich "der Sprung in einen Datenrahmen bleibt stehen" "$rc" 63
nicht_drin "der Aufruf ist nie zurueckgekommen" "came back" "$TMPD/wxe.log"
rc=0; lauf "nokbd nosched noproc nofs noring3 wxexec nonx" "$TMPD/wxe0.log" || rc=$?
gleich "derselbe Sprung ohne NX kommt zurueck" "$rc" 21
drin "und das ret im Datenrahmen lief wirklich" "came back" "$TMPD/wxe0.log"

echo "== 4. Wachseiten unter den Kernstapeln =="
G=$(feld "$TMPD/voll.log" 'hard: guard' guard)
if [[ ${G:-0} -ge 5 ]]; then
    ok "gelegte Wachseiten: $G"
else
    nein "es muessten mehrere Wachseiten sein, es sind $G"
fi
rc=0; lauf "kblow" "$TMPD/kb.log" || rc=$?
gleich "der Stapelueberlauf bleibt stehen" "$rc" 63
drin "und wird als Wachseite BENANNT" "WACHSEITE" "$TMPD/kb.log"
drin "es ist ein Schreibzugriff auf eine fehlende Seite" "err=0x2" "$TMPD/kb.log"
nicht_drin "er hat den Nachbarn nicht erreicht" "blow survived" "$TMPD/kb.log"
rc=0; lauf "kblow noguard" "$TMPD/kb0.log" || rc=$?
gleich "OHNE Wachseite laeuft derselbe Ueberlauf durch" "$rc" 21
drin "und schreibt still in den Nachbarn" "blow survived" "$TMPD/kb0.log"

echo "== 5. ASLR: die Stapel liegen nicht zweimal gleich =="
: >"$TMPD/aslr.txt"
for i in $(seq 1 12); do
    lauf "nokbd nofs" "$TMPD/a$i.log" >/dev/null 2>&1
    grep -a 'hard: guard=' "$TMPD/a$i.log" | tail -1 >>"$TMPD/aslr.txt"
done
UN=$(sed -E 's/.*ustack=(0x[0-9a-f]+).*/\1/' "$TMPD/aslr.txt" | sort -u | wc -l)
KN=$(sed -E 's/.*kstack=(0x[0-9a-f]+).*/\1/' "$TMPD/aslr.txt" | sort -u | wc -l)
if [[ $UN -ge 6 ]]; then ok "verschiedene Nutzerstapel in 12 Starts: $UN"
else nein "zu wenig Streuung im Nutzerstapel: $UN von 12"; fi
if [[ $KN -ge 6 ]]; then ok "verschiedene Kernstapel in 12 Starts: $KN"
else nein "zu wenig Streuung im Kernstapel: $KN von 12"; fi
rc=0; lauf "noaslr" "$TMPD/na.log" || rc=$?
gleich "mit noaslr laeuft der Kern weiter" "$rc" 21
gleich "und der Versatz ist dann null" \
    "$(feld "$TMPD/na.log" 'hard: guard' kstack)" 0x0

echo "== 6. der ELF-Lader weist W-und-X-Segmente ab =="
drin "der Fehlercode ist da" "R_WX" kernel/elf.fi
drin "und er wird gezaehlt" "ELF_WX_REFUSED" kernel/elf.fi

echo "== 7. die IOMMU wird gelesen und gemeldet =="
rc=0; lauf "" "$TMPD/io1.log" -machine q35,kernel-irqchip=split \
    -device intel-iommu,intremap=on || rc=$?
gleich "mit -device intel-iommu laeuft der Kern" "$rc" 21
drin "und er findet die DMAR-Tabelle" "hard: iommu=vt-d" "$TMPD/io1.log"
drin "mit genau einer Einheit" "units=1" "$TMPD/io1.log"
rc=0; lauf "" "$TMPD/io2.log" -machine q35 || rc=$?
gleich "ohne die Einheit laeuft er auch" "$rc" 21
drin "und sagt ehrlich, dass keine da ist" "hard: iommu=keine" "$TMPD/io2.log"

echo "== 8. alle Prozessoren, nicht nur der erste =="
rc=0; lauf "" "$TMPD/smp4.log" -smp 4 || rc=$?
gleich "vier Prozessoren mit dem ganzen Schutz" "$rc" 21
gleich "auch dann keine W-und-X-Seite" \
    "$(feld "$TMPD/smp4.log" 'hard: splits' viol)" 0
drin "und alle drei weiteren tragen SMEP/SMAP" "guard: aps=3" "$TMPD/smp4.log"

echo "== 9. die Zeigerpruefung der Systemaufrufe =="
if python3 tools/haertung/zeiger.py >"$TMPD/z.log" 2>&1; then
    ROH=$(grep -c '^   ROH:' "$TMPD/z.log" || true)
    ok "der Aufrufgraph laeuft durch ($(grep 'Systemaufrufe mit Behandler' "$TMPD/z.log" | tr -s ' ' | cut -d: -f2) Systemaufrufe)"
    printf '        %s\n' "$(grep 'davon mit mindestens einem Zeiger' "$TMPD/z.log" | tr -s ' ')"
    printf '        %s\n' "$(grep 'davon alle Zeiger geprueft' "$TMPD/z.log" | tr -s ' ')"
else
    nein "tools/haertung/zeiger.py ist gefallen"
fi

echo
echo "HAERTUNG: $BESTANDEN bestanden, $GEFALLEN gefallen"
[[ $GEFALLEN -eq 0 ]]
