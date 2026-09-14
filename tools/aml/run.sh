#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/aml/run.sh -- DER AML-INTERPRETER, GEMESSEN.
#
# ==================================================================
# WORUM ES GEHT
# ==================================================================
#
# Bis zu dieser Runde hat Osum die Unterbrechungsleitung eines PCI-
# Geraets aus dem Register 0x3C seiner Konfiguration gelesen. Das ist
# kein Register des Geraets, sondern ein Notizzettel der Firmware. Die
# Wahrheit steht im AML-Objekt `_PRT`, und um es zu lesen, braucht es
# einen Interpreter fuer AML. Diese Runde baut ihn.
#
# ==================================================================
# WAS HIER WIRKLICH GEMESSEN WIRD -- und was nicht
# ==================================================================
#
# GEMESSEN wird auf QEMU 7.2, Maschine `pc` (i440fx). Deren DSDT ist
# 6476 Oktette lang, hat 360 Namen und -- das ist der Punkt -- ein
# `_PRT`, das KEINE fertige Tabelle ist, sondern eine METHODE mit einer
# While-Schleife ueber 128 Durchlaeufe, Paketen, `Index`, `ShiftLeft`,
# `And`, `Or` und Verweisen auf fuenf Link-Geraete. Deren `_CRS`
# wiederum ruft eine zweite Methode auf, die einen Puffer anlegt, ein
# `CreateDWordField` darauf setzt und ein PIIX3-Register aus dem
# PCI-KONFIGURATIONSRAUM liest. Wer das auswerten kann, hat keinen
# Spielzeug-Parser.
#
# NICHT GEMESSEN wird echte Hardware. Auf diesem Rechner liegt kein
# Testbrett. Jede Zahl unten kommt aus QEMU, und wo das den Unterschied
# macht, steht es dabei -- so wie in `docs/REALHW.md` seit Runde HWNET.
#
# DIE ZUSAGE, AN DER DIE RUNDE HAENGT, ist Abschnitt 5: der
# Unterbrechungsvektor kommt WIRKLICH an, wenn die Leitung aus `_PRT`
# in den I/O-APIC eingetragen wird -- und er kommt NICHT an, wenn
# dieselbe Leitung um eins verschoben eingetragen wird (`amlwrong`).
# Ohne diese Gegenprobe waere "wir haben eine Zahl gewonnen" keine
# Messung, sondern eine Behauptung: das Geraet arbeitet naemlich auch
# per Abfrage weiter, nur eben ohne Unterbrechung.
#
# Aufruf:  bash tools/aml/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

TMPD=$(mktemp -d)
NS=amlns; V0=amlv0; V1=amlv1
HOST_IP=10.9.0.1; OSUM_IP=10.9.0.2
BPORT=45311; QPORT=45312
BRPID=""

aufraeumen() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$TMPD"
}
trap aufraeumen EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

gleich() { # beschreibung soll ist
    if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 -- soll '$2', ist '$3'"; fi
}
num() { # beschreibung wert op soll
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl gefunden (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

# EIN WERT AUS EINER `aml:`-ZEILE. Die Meldungen haben die Form
#   aml: tables=1 nodes=346 heap=91608 us=1680 err=0
# also wird nach "name=" gesucht und bis zum naechsten Leerzeichen gelesen.
w() { # datei name
    grep -a -o -m1 "$2=[0-9]*" "$1" 2>/dev/null | head -1 | sed 's/.*=//' \
        | tr -d '\r\000'
}
# DASSELBE, ABER NUR AUS DEN ZEILEN DES INTERPRETERS. `err=` steht auch
# in Meldungen anderer Untersysteme; wer stumpf die erste Fundstelle in
# der Datei nimmt, misst irgendetwas. Das ist derselbe Fehler, den
# tools/k18/run.sh in seinem Kopf beschreibt.
aw() { # datei name
    grep -a '^aml:' "$1" 2>/dev/null | grep -o -m1 "$2=[0-9]*" | head -1 \
        | sed 's/.*=//' | tr -d '\r\000'
}

# EINE ZUSAGE UEBER EINEN SOLCHEN WERT. Ein FEHLENDER Wert faellt durch
# -- ein Vergleich, der besteht, weil beide Seiten leer sind, ist keiner.
sagt() { # datei name soll beschreibung
    local got; got=$(aw "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- '$2=' steht nicht in der Ausgabe"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2=$got)"
    else bad "$4 -- $2=$got, erwartet $3"; fi
}

bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "AML: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi

K="$TMPD/osum.mb"
bash tools/build-kernel.sh "$K" >/dev/null 2>&1 || {
    echo "AML: der Kernel laesst sich nicht bauen"; exit 1; }

lauf() { # append out [qemu-args...]
    local append=$1 out=$2
    shift 2
    timeout 120 $QEMU_X86 -kernel "$K" -m 128 -append "$append" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $? > "$out.rc"
}

echo "== 1. die Zahlen, die Karte und die Modusbits =="

# Der kdata-Bereich dieser Runde steht in kstate.fi UND in der
# Speicherkarte. Genau hier hat dieses Projekt viermal denselben Fehler
# gemacht (siehe tools/kernel/memmap.py).
if python3 tools/kernel/memmap.py kernel >/dev/null 2>&1; then
    ok "die kdata-Karte ist ueberschneidungsfrei (memmap.py)"
else
    bad "memmap.py meldet eine Kollision"
    python3 tools/kernel/memmap.py kernel -v 2>&1 | tail -5
fi
grep -q 'AML_OFF' tools/kernel/memmap.py \
    && ok "der Bereich AML_OFF steht in der Speicherkarte" \
    || bad "AML_OFF fehlt in tools/kernel/memmap.py"

# DIE MODUSBITS DIESER RUNDE. Sie lagen auf Wort 11 ab Bit 0 (704..712)
# -- auf dem Zweigstand vom 30.08.2026 war Wort 11 ganz frei. Beim
# Hereinholen nach main (14.09.2026) stellte sich heraus, dass dort
# laengst M_ASYNC..M_ASTRESS (Runde ASYNC) und M_MODUL/M_MODULAUS
# (Runde MODUL) stehen: EIN Wort, ZWEI Bedeutungen, und `aml` auf der
# Kommandozeile haette den Asynchronweg mitgeschaltet. Die Bits liegen
# jetzt auf Wort 12 ab Bit 4 (772..780); Bit 0..3 gehoeren dort EHCI
# und BLK. Diese Pruefung ist der Grund, warum es aufgefallen ist --
# sie bleibt, nur der Vorrat wandert mit.
fremd=$(grep -rn --include='*.fi' -E '^const M_[A-Z0-9_]+: u64 = 7(7[2-9]|80)' kernel/ \
        | grep -vE 'M_(AML|AMLDUMP|NOAML|AMLBAD|AMLLOOP|AMLDEEP|AMLLEAK|AMLPRT|AMLWRONG)' || true)
[ -z "$fremd" ] && ok "die Modusbits 772..780 gehoeren nur dieser Runde" \
                || { bad "fremde Modusbits im Vorrat dieser Runde"; echo "$fremd"; }

# UND DIE GEGENPROBE ZUR GEGENPROBE: die Bits, die der Zweig FRUEHER
# hatte, muessen jetzt jemand anderem gehoeren. Stuende dort nichts,
# waere die Verschiebung sinnlos gewesen.
grep -rq --include='*.fi' -E '^const M_ASYNC: u64 = 704' kernel/ \
    && ok "Wort 11 Bit 0 gehoert wieder Runde ASYNC (M_ASYNC)" \
    || bad "M_ASYNC steht nicht mehr auf 704 -- die Verschiebung stimmt nicht"


# Der Kernstapel steht in boot.s und die Wache in amlev.fi. Die Wache
# MUSS deutlich unter dem Stapel liegen, sonst schuetzt sie nicht.
stack=$(grep -A20 '^kernel_stack_bottom:' kernel/arch/x86_64/boot.s \
        | grep -m1 '\.skip' | sed 's/.*\.skip *//')
limit=$(grep -m1 '^const STACK_LIMIT' kernel/amlev.fi | sed 's/.*= *//')
num "der Kernstapel ist gewachsen" "$stack" ge 131072
num "die Stapelwache liegt unter dem halben Stapel" \
    "$(( stack / 2 - limit ))" ge 0

echo
echo "== 2. der Namensraum -- gegen eine zweite, unabhaengige Fassung =="

# Der Kernel legt die ACPI-Tabellen als Hexzeilen auf die Leitung;
# tools/aml/disasm.py liest DIESELBEN Oktette noch einmal, in Python,
# von Hand nach der Spezifikation. Wo beide auseinandergehen, hat einer
# von beiden unrecht.
lauf "osum aml amldump nopwr" "$TMPD/dump.txt"
gleich "der Lauf mit amldump endet sauber" "21" "$(cat "$TMPD/dump.txt.rc")"

python3 - "$TMPD/dump.txt" "$TMPD" <<'PYEOF'
import re, sys
log, out = sys.argv[1], sys.argv[2]
cur = None
n = 0
for line in open(log, 'rb').read().decode('latin1').splitlines():
    line = line.strip('\x00\r')
    m = re.match(r'^amltab (\d+) sig=(\S+) len=(\d+)$', line)
    if m:
        cur = {'sig': m.group(2), 'len': int(m.group(3)), 'd': bytearray()}
        continue
    if line.startswith('amlhex ') and cur is not None:
        cur['d'] += bytes.fromhex(line[7:].strip())
        if len(cur['d']) >= cur['len']:
            open('%s/%s.bin' % (out, cur['sig']), 'wb').write(bytes(cur['d']))
            n += 1
            cur = None
print("tabellen=%d" % n)
PYEOF

if [ -f "$TMPD/DSDT.bin" ]; then
    ok "die DSDT ist vollstaendig ueber die Leitung gekommen ($(stat -c%s "$TMPD/DSDT.bin") Oktette)"
else
    bad "die DSDT kam nicht vollstaendig an"
fi

lauf "osum aml nopwr" "$TMPD/ok.txt"
gleich "der Lauf mit aml endet sauber" "21" "$(cat "$TMPD/ok.txt.rc")"
sagt "$TMPD/ok.txt" err 0 "der Namensraum wurde ohne Fehler gebaut"

if [ -f "$TMPD/DSDT.bin" ]; then
    python3 tools/aml/disasm.py ns "$TMPD"/*.bin > "$TMPD/ns.txt" 2>/dev/null
    # `disasm.py` zaehlt jede ERKLAERUNG, der Kernel jeden KNOTEN --
    # `Scope(\_SB)` steht in QEMUs DSDT dreimal und ist EIN Knoten.
    # Verglichen wird deshalb die Zahl der VERSCHIEDENEN vollen Namen.
    # Namen, die INNERHALB eines Methodenrumpfes stehen (QEMU: drei),
    # legt der Kernel beim Laden NICHT an -- er ueberspringt die Rumpfe
    # und legt sie erst beim Aufruf an, so wie es die Spezifikation
    # verlangt (sie gehoeren der Aufrufinstanz, nicht der Tabelle).
    # Also werden sie hier auf beiden Seiten weggelassen.
    awk '$2=="Method"{print $1}' "$TMPD/ns.txt" | sort -u > "$TMPD/meth.txt"
    awk '{print $1}' "$TMPD/ns.txt" | grep '^\\' | sort -u > "$TMPD/alle.txt"
    python3 - "$TMPD/alle.txt" "$TMPD/meth.txt" > "$TMPD/tabnamen.txt" <<'PY2'
import sys
meth = set(l.strip() for l in open(sys.argv[2]) if l.strip())
for l in open(sys.argv[1]):
    n = l.strip()
    if not n:
        continue
    if any(n.startswith(m + ".") for m in meth):
        continue
    print(n)
PY2
    sort -u -o "$TMPD/tabnamen.txt" "$TMPD/tabnamen.txt"
    py_n=$(wc -l < "$TMPD/tabnamen.txt")
    py_dev=$(awk '$2=="Device"{print $1}' "$TMPD/ns.txt" | sort -u | wc -l)
    py_m=$(awk '$2=="Method"{print $1}' "$TMPD/ns.txt" | sort -u | wc -l)
    py_r=$(awk '$2=="OperationRegion"{print $1}' "$TMPD/ns.txt" | sort -u | wc -l)
    k_n=$(aw "$TMPD/ok.txt" nodes)
    k_dev=$(aw "$TMPD/ok.txt" devs)
    k_m=$(aw "$TMPD/ok.txt" methods)
    k_r=$(aw "$TMPD/ok.txt" regions)
    gleich "Knoten: Kernel und Python zaehlen dasselbe" "$py_n" "$k_n"
    gleich "Geraete: Kernel und Python zaehlen dasselbe" "$py_dev" "$k_dev"
    gleich "Methoden: Kernel und Python zaehlen dasselbe" "$py_m" "$k_m"
    gleich "Regionen: Kernel und Python zaehlen dasselbe" "$py_r" "$k_r"

    # NICHT NUR DIE ANZAHL, SONDERN DIE NAMEN SELBST. Zwei Listen
    # gleicher Laenge koennen verschiedene Namen enthalten; erst der
    # Mengenvergleich sagt, dass der Kernel WIRKLICH denselben
    # Namensraum gebaut hat wie die unabhaengige Fassung.
    lauf "osum aml amlprt nopwr" "$TMPD/ns-kernel.txt"
    grep -a '^aml: ns ' "$TMPD/ns-kernel.txt" | awk '{print $3}' | sort -u \
        > "$TMPD/knamen.txt"
    unterschied=$(comm -3 "$TMPD/tabnamen.txt" "$TMPD/knamen.txt" | wc -l)
    if [ "$unterschied" = "0" ]; then
        ok "die NAMEN stimmen Zeichen fuer Zeichen ueberein ($(wc -l < "$TMPD/knamen.txt") Stueck)"
    else
        bad "$unterschied Namen unterscheiden sich"
        comm -3 "$TMPD/tabnamen.txt" "$TMPD/knamen.txt" | head -10 | sed 's/^/        /'
    fi

    # Die Geraete, an denen diese Runde haengt, MUESSEN im Namensraum
    # stehen -- geprueft an der unabhaengigen Fassung.
    for n in '\_SB.PCI0._PRT' '\_SB.LNKA._CRS' '\_SB.LNKD._SRS' \
             '\_SB.PCI0.S08.P40C' '\_SB.PRQ0'; do
        if awk -v n="$n" '$1==n{f=1} END{exit !f}' "$TMPD/ns.txt"; then
            ok "der Namensraum enthaelt $n"
        else
            bad "im Namensraum fehlt $n"
        fi
    done
else
    bad "ohne DSDT kein Vergleich"
fi

echo
echo "== 3. die Opcode-Abdeckung =="

python3 - "$TMPD/ok.txt" "$TMPD/can.txt" "$TMPD/seen.txt" <<'PYEOF'
import re, sys
log, canout, seenout = sys.argv[1], sys.argv[2], sys.argv[3]
can, seen = set(), set()
for l in open(log, 'rb').read().decode('latin1').splitlines():
    l = l.strip('\x00\r')
    m = re.match(r'aml: can (0x[0-9a-f]+)', l)
    if m:
        can.add(int(m.group(1), 16))
    m = re.match(r'aml: canext (0x[0-9a-f]+)', l)
    if m:
        can.add(0x5B00 | int(m.group(1), 16))
    m = re.match(r'aml: canpair (0x[0-9a-f]+)', l)
    if m:
        can.add(0x9200 | int(m.group(1), 16))
    m = re.match(r'aml: op (0x[0-9a-f]+)', l)
    if m:
        seen.add(int(m.group(1), 16))
    m = re.match(r'aml: extop (0x[0-9a-f]+)', l)
    if m:
        seen.add(0x5B00 | int(m.group(1), 16))
open(canout, 'w').write("".join("0x%04x\n" % x for x in sorted(can)))
open(seenout, 'w').write("".join("0x%04x\n" % x for x in sorted(seen)))
print("can=%d seen=%d fehlend=%s"
      % (len(can), len(seen), sorted(hex(x) for x in seen - can)))
PYEOF

fehlend=$(python3 - "$TMPD/can.txt" "$TMPD/seen.txt" <<'PYEOF'
import sys
can = set(int(l, 16) for l in open(sys.argv[1]))
seen = set(int(l, 16) for l in open(sys.argv[2]))
print(len(seen - can))
PYEOF
)
gleich "jeder wirklich ausgefuehrte Opcode steht in der Koennen-Liste" "0" "$fehlend"

if [ -f "$TMPD/DSDT.bin" ]; then
    python3 tools/aml/disasm.py deckung "$TMPD/can.txt" "$TMPD"/*.bin \
        > "$TMPD/deckung.txt" 2>/dev/null
    cat "$TMPD/deckung.txt" | sed 's/^/    /'
    d=$(grep -o 'Abdeckung: *[0-9]*' "$TMPD/deckung.txt" | sed 's/.*: *//')
    num "die Abdeckung der in QEMUs DSDT vorkommenden Opcodes" "$d" ge 95
fi

echo
echo "== 4. _PRT -- die Leitung aus der Firmware statt aus 0x3C =="

sagt "$TMPD/ok.txt" prtok 1 "_PRT wurde ausgewertet"
sagt "$TMPD/ok.txt" routes 128 "die Routentafel hat einen Eintrag je Steckplatz und Stift"

# Die entscheidende Gegenrechnung: fuer JEDES Geraet mit einem Stift
# muessen `_PRT` und das Interrupt-Line-Register dasselbe sagen. In QEMU
# tun sie das, weil SeaBIOS die PIIX3-Register nach derselben Tabelle
# programmiert -- zwei unabhaengige Wege zur selben Zahl.
mismatch=0
paare=0
while read -r line; do
    a=$(echo "$line" | sed -n 's/.* aml=\([0-9]*\).*/\1/p')
    l=$(echo "$line" | sed -n 's/.* line=\([0-9]*\).*/\1/p')
    [ -z "$a" ] && continue
    paare=$((paare+1))
    [ "$a" != "$l" ] && mismatch=$((mismatch+1))
done < <(grep -a '^aml: gsi ' "$TMPD/ok.txt")
num "Geraete mit einem Unterbrechungsstift" "$paare" ge 2
gleich "_PRT und das Register 0x3C sagen bei allen dasselbe" "0" "$mismatch"

# Und die Zahl selbst, damit nicht beide gemeinsam falsch liegen: die
# Netzkarte steht in QEMU auf 00:03.0, Stift A. `_PRT` fuehrt ueber
# LNKC auf das PIIX3-Register 0x62, und dort steht die 11.
zeile=$(grep -a '^aml: gsi 00:03.0' "$TMPD/ok.txt" | head -1)
gsi=$(echo "$zeile" | sed -n 's/.* aml=\([0-9]*\).*/\1/p')
gleich "00:03.0 Stift A liegt laut _PRT auf GSI 11" "11" "${gsi:-fehlt}"

echo
echo "== 5. DIE ZUSAGE: der Unterbrechungsvektor kommt wirklich an =="

if [ "$(id -u)" != "0" ] || ! command -v ip >/dev/null 2>&1; then
    echo "  (uebersprungen: dieser Abschnitt braucht root und ip(8))"
else
    gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null \
        && ok "tools/net/bridge.c: die Leitung nach draussen ist gebaut" \
        || bad "bridge.c laesst sich nicht uebersetzen"

    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    ip netns add "$NS"
    ip link add "$V0" type veth peer name "$V1"
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add "$HOST_IP/24" dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off \
        >/dev/null 2>&1

    NETBASE="osum aml nokbd nosched noproc nofs noring3 nic nopwr"
    NETARGS="nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=900"

    ping_lauf() { # append out
        "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" >/dev/null 2>&1 & BRPID=$!
        sleep 0.4
        ( timeout 120 $QEMU_X86 -kernel "$K" -m 256 -append "$1" \
            -serial "file:$2" -display none -no-reboot \
            -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
            -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cc" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 ) &
        local qp=$!
        sleep 2
        ip netns exec "$NS" ping -c 10 -i 0.2 -W 1 "$OSUM_IP" >/dev/null 2>&1
        wait $qp 2>/dev/null
        kill "$BRPID" 2>/dev/null; BRPID=""
        sleep 0.3
    }

    ping_lauf "$NETBASE $NETARGS" "$TMPD/nic-ok.txt"
    ping_lauf "$NETBASE $NETARGS amlwrong" "$TMPD/nic-bad.txt"

    g_ok=$(grep -a '^aml: gsi 00:03.0' "$TMPD/nic-ok.txt" | sed -n 's/.* aml=\([0-9]*\).*/\1/p')
    irq_ok=$(w "$TMPD/nic-ok.txt" 'nic: irqs')
    icmp_ok=$(w "$TMPD/nic-ok.txt" 'nic: icmp')
    irq_bad=$(w "$TMPD/nic-bad.txt" 'nic: irqs')
    icmp_bad=$(w "$TMPD/nic-bad.txt" 'nic: icmp')

    gleich "die Karte wird mit der Leitung aus _PRT eingetragen" "11" "${g_ok:-fehlt}"
    num "MIT der Leitung aus _PRT kommen Unterbrechungen an" "${irq_ok:-0}" ge 1
    num "und die Karte beantwortet die Pings" "${icmp_ok:-0}" ge 5
    # DIE GEGENPROBE. Um eins verschoben eingetragen, kommt KEINE
    # Unterbrechung mehr an. Dass die Karte per Abfrage trotzdem
    # weiterarbeitet, ist genau der Grund, warum hier die Unterbrechungen
    # gezaehlt werden und nicht die Antworten.
    gleich "mit der FALSCHEN Leitung kommt keine einzige Unterbrechung an" \
        "0" "${irq_bad:-fehlt}"

    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
fi

echo
echo "== 6. kaputtes AML -- definierter Fehler und Rueckfall =="

lauf "osum aml amlbad nopwr" "$TMPD/bad.txt"
gleich "die Maschine faehrt trotz kaputter DSDT fertig hoch" "21" "$(cat "$TMPD/bad.txt.rc")"
hat "$TMPD/bad.txt" "kernel: done" "der Kernel kommt bis zum Ende"
e=$(aw "$TMPD/bad.txt" err)
num "es gibt einen DEFINIERTEN Fehler (nicht 0)" "${e:-0}" ge 1
sagt "$TMPD/bad.txt" prtok 0 "_PRT wurde NICHT fuer gueltig erklaert"
sagt "$TMPD/bad.txt" routes 0 "die Routentafel bleibt leer"
# Und der Rueckfall traegt: die Zeilen zeigen aml=999 (nichts gefunden)
# und trotzdem eine Leitung aus dem Register.
grep -qa 'aml: gsi 00:03.0 pin=1 aml=999 line=11' "$TMPD/bad.txt" \
    && ok "der Rueckfall auf das Interrupt-Line-Register greift (line=11)" \
    || bad "der Rueckfall greift nicht"
grep -qa 'EXCEPTION' "$TMPD/bad.txt" \
    && bad "es gab eine Prozessorausnahme" \
    || ok "keine Prozessorausnahme"

lauf "osum noaml nopwr" "$TMPD/no.txt"
gleich "ohne Interpreter (noaml) laeuft die Maschine wie vorher" "21" "$(cat "$TMPD/no.txt.rc")"
hat "$TMPD/no.txt" "aml: abgestellt" "noaml schaltet den Interpreter wirklich ab"

echo
echo "== 7. eine Schleife, die nicht endet =="

lauf "osum aml amlloop nopwr" "$TMPD/loop.txt"
gleich "die Maschine bleibt nicht stehen" "21" "$(cat "$TMPD/loop.txt.rc")"
l=$(grep -a -o -m1 'aml: loop err=[0-9]*' "$TMPD/loop.txt" | sed 's/.*=//')
gleich "die Schrittgrenze greift (ERR_BUDGET = 7)" "7" "${l:-fehlt}"
sagt "$TMPD/loop.txt" routes 128 "und _PRT ist davon unberuehrt"

echo
echo "== 8. Rekursion bis zur Grenze =="

lauf "osum aml amldeep nopwr" "$TMPD/deep.txt"
gleich "die Maschine bleibt nicht stehen" "21" "$(cat "$TMPD/deep.txt.rc")"
d=$(grep -a -o -m1 'aml: deep err=[0-9]*' "$TMPD/deep.txt" | sed 's/.*=//')
gleich "die Tiefengrenze greift (ERR_DEPTH = 6)" "6" "${d:-fehlt}"
hat "$TMPD/deep.txt" "kernel: done" "der Kernel kommt bis zum Ende"
grep -qa 'EXCEPTION' "$TMPD/deep.txt" \
    && bad "es gab eine Prozessorausnahme" \
    || ok "kein Stapelueberlauf, keine Ausnahme"

echo
echo "== 9. kein Leck =="

lauf "osum aml amlleak nopwr" "$TMPD/leak.txt"
v=$(grep -a -o -m1 'vorher=[0-9]*' "$TMPD/leak.txt" | sed 's/.*=//')
n=$(grep -a -o -m1 'nachher=[0-9]*' "$TMPD/leak.txt" | sed 's/.*=//')
if [ -z "${v:-}" ] || [ -z "${n:-}" ]; then
    bad "die Rahmenzahlen fehlen in der Ausgabe"
else
    gleich "nach dem Verwerfen des Namensraums sind alle Rahmen zurueck" "$v" "$n"
    num "der Namensraum hat wirklich Rahmen gekostet" "$v" ge 64
fi

echo
echo "== 10. die Messungen =="

us=$(aw "$TMPD/ok.txt" us)
prtus=$(aw "$TMPD/ok.txt" prtus)
heap=$(aw "$TMPD/ok.txt" heap)
nodes=$(aw "$TMPD/ok.txt" nodes)
stackh=$(aw "$TMPD/ok.txt" stack)
tiefe=$(aw "$TMPD/ok.txt" tiefe)
ladest=$(aw "$TMPD/ok.txt" ladest)
zeilen=$(cat kernel/aml.fi kernel/amlns.fi kernel/amlobj.fi kernel/amlev.fi | wc -l)
printf '    DSDT parsen:            %s us\n' "$us"
printf '    _PRT auswerten:         %s us\n' "$prtus"
printf '    Namensraum:             %s Knoten\n' "$nodes"
printf '    Arena benutzt:          %s Oktett (davon %s Knotentafel)\n' \
    "$heap" "$(( $(grep -m1 '^const NMAX' kernel/amlns.fi | sed 's/.*= *//') * 32 ))"
printf '    Kernstapel, Laden:      %s Oktett\n' "$ladest"
printf '    Kernstapel, hoechstens: %s Oktett (Wache %s)\n' "$stackh" "$limit"
printf '    Verschachtelung:        %s (Grenze %s)\n' "$tiefe" \
    "$(grep -m1 '^const DEPTH_MAX' kernel/amlev.fi | sed 's/.*= *//')"
printf '    Zeilen Quelltext:       %s\n' "$zeilen"

num "das Parsen bleibt unter zehn Millisekunden" "${us:-99999}" le 10000
num "_PRT bleibt unter fuenfzig Millisekunden" "${prtus:-99999}" le 50000
num "der Kernstapel bleibt unter der Wache" \
    "$(( limit - ${stackh:-999999} ))" ge 0

# Bootzeit vorher/nachher. `noaml` ist der Zustand VOR dieser Runde --
# derselbe Kernel, nur ohne den Interpreter. Der Unterschied ist der
# Preis der Runde und keine Schaetzung.
mess_boot() { # append -> ms (Median aus fuenf)
    local i t0 t1
    : > "$TMPD/zeiten.txt"
    for i in 1 2 3 4 5; do
        t0=$(date +%s%N)
        lauf "$1" "$TMPD/boot.txt"
        t1=$(date +%s%N)
        echo $(( (t1 - t0) / 1000000 )) >> "$TMPD/zeiten.txt"
    done
    sort -n "$TMPD/zeiten.txt" | sed -n '3p'
}
b_ohne=$(mess_boot "osum noaml nopwr")
b_mit=$(mess_boot "osum aml nopwr")
printf '    Bootzeit ohne aml:      %s ms (Median aus 5, ganzer QEMU-Lauf)\n' "$b_ohne"
printf '    Bootzeit mit aml:       %s ms (Median aus 5, ganzer QEMU-Lauf)\n' "$b_mit"
# EHRLICH GESAGT: dieser Unterschied misst den ganzen QEMU-Lauf samt
# Start und Beendigung und schwankt von Lauf zu Lauf um mehrere zehn
# Millisekunden. Die belastbare Zahl ist die, die der Kernel SELBST
# nimmt (us + prtus oben, zusammen rund 6 ms); diese hier ist nur die
# Gegenprobe, dass keine Groessenordnung dazwischenliegt.
num "der Interpreter bremst den Start um weniger als 200 ms" \
    "$(( b_mit - b_ohne ))" le 200

echo
echo "=================================================================="
printf 'AML: %d Zusagen, %d gefallen\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
