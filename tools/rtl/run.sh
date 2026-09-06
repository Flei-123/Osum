#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/rtl/run.sh -- RUNDE RTL: DER CHIP, DEN MAN ANFASSEN KANN.
#
# Runde HWNET hat zwei Treiber gegeneinander gemessen (virtio-net und
# e1000) und im eigenen Bericht aufgeschrieben, warum sie den Realtek
# NICHT gebaut hat: QEMU habe nur `-device rtl8139`, und der 8139 sei
# "nicht derselbe Chip" wie der 8168/8169 -- vier feste Sendepuffer statt
# Deskriptorringen. Ein Treiber ohne Messung sei eine Behauptung.
#
# Diese Runde widerspricht dem an genau einer Stelle, und die ist
# nachpruefbar: der RTL8139 ab Revision 0x20 hat einen ZWEITEN
# Betriebszustand, den C+-Modus, und in dem hat er Deskriptorringe --
# dieselben, die der 8169 hat. QEMU emuliert diesen Zustand
# (`currCPlusTxDesc`, `cplus_enabled` stehen im Programm). Damit ist die
# Ringmechanik messbar, und gemessen wird sie hier.
#
# WAS DAS BEWEIST UND WAS NICHT, weil genau das der strittige Punkt ist:
#
#   BEWIESEN  Deskriptorringe, OWN-Protokoll, DMA in beide Richtungen,
#             das Einsammeln fertiger Sendedeskriptoren, Ringueberlauf,
#             Unterbrechungen mit Zurueckschreiben des ISR, Verbindung
#             weg und wieder da, die vier Oktett Pruefsumme am Rahmenende.
#             Das ist derselbe Quelltext, den ein 8168 ausfuehren wuerde.
#   NICHT     Der Sendeanstoss sitzt beim 8169 auf 0x38 statt auf 0xD9,
#             die Verbindung steht in PHYstatus 0x6C statt in MSR 0x58,
#             und der PHY haengt an MDIO statt fest im Chip. Diese drei
#             Stellen sind aus dem Datenblatt und haben nie geantwortet.
#             Ebenso der ganze I219-Zweig in `kernel/e1000.fi`.
#
# DER DRAHT ist der aus Runde K8 (`tools/net/bridge.c`): QEMUs
# UDP-Steckdose auf der einen Seite, eine AF_PACKET-Bruecke in ein
# veth-Paar auf der anderen, und ein Netzraum mit dem Linux-Kern darin.
# `/dev/net/tun` gibt es in diesem Behaelter nicht.
#
# DIE GEGENPROBEN, jede ein Lauf, in dem die Messung zusammenbrechen muss:
#
#   ohne `nic`  dasselbe Abbild fasst die Karte nie an: der Ping bekommt
#               nichts
#   nicnobm     das Busmasterbit wird weggenommen: der Chip darf Register
#               beantworten, aber keinen Deskriptor holen
#   ne2k_pci    eine Karte MIT DEMSELBEN HERSTELLER (10EC:8029), fuer die
#               es keinen Treiber gibt -- sie muss mit ihren Nummern
#               genannt werden, nicht stillschweigend uebergangen
#   rev < 0x20  ein RTL8139B hat keinen C+-Modus. Die Tabelle muss ihn
#               ablehnen, obwohl die Geraetenummer dieselbe ist
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"

NS=rtl-$$
V0=rt0-$$
V1=rt1
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
QPORT=$(( 13000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))

TMPD=$(mktemp -d)
BRPID=""
QPID=""
DHPID=""
MON="$TMPD/mon.sock"
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    [ -n "$DHPID" ] && kill "$DHPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # Name Wert Vergleich Erwartung
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "${value:-}" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' duerfte nicht dastehen" || ok "$3"; }
val() { grep -aoE "^nic: $2=[0-9]+" "$1" 2>/dev/null | tail -1 | cut -d= -f2; }
loss() { grep -oE '[0-9]+% packet loss' "$1" | grep -oE '^[0-9]+'; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
for t in qemu-system-x86_64 ip gcc nc python3 busybox; do
    command -v "$t" >/dev/null 2>&1 || { echo "RTL: uebersprungen, $t fehlt"; exit 0; }
done
ip netns del "$NS" 2>/dev/null
if ! ip netns add "$NS" 2>/dev/null; then
    echo "RTL: uebersprungen, Netzraeume gibt es hier nicht"
    exit 0
fi
ip netns del "$NS" 2>/dev/null
# Der C+-Modus ist der ganze Grund, warum diese Runde ueberhaupt messen
# kann. Fehlt er in dieser QEMU-Fassung, ist jede Zahl darunter wertlos --
# also wird er ZUERST geprueft und nicht angenommen.
# (kein `grep -q` in der Roehre: es beendet `strings` mit SIGPIPE, und
# `set -o pipefail` macht daraus einen Fehlschlag der ganzen Roehre.)
cplus=$(strings "$(command -v qemu-system-x86_64)" 2>/dev/null | grep -c currCPlusTxDesc)
if [ "${cplus:-0}" -eq 0 ]; then
    echo "RTL: uebersprungen, dieses QEMU emuliert den C+-Modus des rtl8139 nicht"
    exit 0
fi

# Ein Monitorbefehl an QEMU. `socat` gibt es in diesem Behaelter nicht,
# also uebernimmt das python3, das die Werkzeugliste ohnehin verlangt.
mon() {
    python3 - "$MON" "$1" <<'PYEOF' >/dev/null 2>&1
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
time.sleep(0.3)
s.setblocking(False)
try:
    s.recv(65536)
except Exception:
    pass
s.setblocking(True)
s.sendall((sys.argv[2] + "\n").encode())
time.sleep(0.5)
s.close()
PYEOF
}

# =====================================================================
echo "== 1. der Bau, mit beiden Uebersetzern =="
# =====================================================================
if bash tools/hwnet/build.sh "$TMPD/s0" 0 > "$TMPD/b0.txt" 2>&1; then
    ok "firnc0: Kernel mit r8169.fi + e1000.fi + netdev.fi, und sieben Programme"
else
    bad "firnc0 baut es nicht"; sed 's/^/        /' "$TMPD/b0.txt" | head -10
    echo "RTL: $pass bestanden, $fail gefallen"; exit 1
fi
if bash tools/hwnet/build.sh "$TMPD/s1" 1 > "$TMPD/b1.txt" 2>&1; then
    ok "firnc1: dasselbe, aus dem in Firn geschriebenen Uebersetzer"
else
    bad "firnc1 baut es nicht"; sed 's/^/        /' "$TMPD/b1.txt" | head -10
fi
K="$TMPD/s0/k.mb"
D="$TMPD/s0/disk.img"

# Der Treiber ist Teil des freistehenden Kerns: keine libc, keine
# Laufzeit und kein einziger `syscall` in Ring 0.
undef=$(nm -u "$TMPD/s0/k.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d' \
        | grep -vE '^(osum_panic|kdata|osym_tab)$')
[ -z "$undef" ] && ok "k.o: kein undefinierter Name ausser osum_panic und kdata" \
                || bad "k.o: undefinierte Symbole: $undef"
n=$(nm "$TMPD/s0/k.o" 2>/dev/null | grep -cE 'r8169__init_on|netdev__driver_for')
num "r8169.fi und die Tabelle stecken wirklich im Abbild (Symbole)" "$n" ge 2

gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>"$TMPD/gcc.err" \
    && ok "tools/net/bridge.c: der UDP/AF_PACKET-Draht ist gebaut" \
    || { bad "bridge.c uebersetzt nicht"; head -5 "$TMPD/gcc.err"; }

# =====================================================================
echo "== 2. die Treibertabelle, ausgefuehrt statt gelesen =="
# =====================================================================
# Dieses Verzeichnis hat keinen RTL8168 und keinen I219 und wird nie einen
# haben. Was es pruefen KANN, ist die WAHL: `nictab` laesst den Kern die
# Tabelle gegen eine eingebaute Nummernliste laufen und je Zeile sagen,
# welcher Treiber es waere. Ohne Karte, ohne Draht, ohne Netz.
rm -f "$TMPD/tab.txt"
timeout 90 qemu-system-x86_64 -kernel "$K" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 nictab nwait=20" \
    -serial "file:$TMPD/tab.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
T="$TMPD/tab.txt"
has "$T" "netdev: tab 0x1af4:0x1000 rev=0x0 -> virtio-net" "1AF4:1000 -> virtio-net"
has "$T" "netdev: tab 0x8086:0x100e rev=0x3 -> e1000"      "8086:100E -> e1000 (82540EM)"
has "$T" "netdev: tab 0x8086:0x10d3 rev=0x0 -> e1000"      "8086:10D3 -> e1000 (82574L)"
has "$T" "netdev: tab 0x8086:0x15b7 rev=0x0 -> i219"       "8086:15B7 -> i219 (I219-LM)"
has "$T" "netdev: tab 0x8086:0x15b8 rev=0x0 -> i219"       "8086:15B8 -> i219 (I219-V)"
has "$T" "netdev: tab 0x8086:0xd4e rev=0x0 -> i219"        "8086:0D4E -> i219 (Tiger Lake)"
has "$T" "netdev: tab 0x10ec:0x8168 rev=0x0 -> r8169"      "10EC:8168 -> r8169 (der haeufigste Chip)"
has "$T" "netdev: tab 0x10ec:0x8169 rev=0x0 -> r8169"      "10EC:8169 -> r8169"
has "$T" "netdev: tab 0x10ec:0x8136 rev=0x0 -> r8169"      "10EC:8136 -> r8169 (RTL8101E)"
has "$T" "netdev: tab 0x10ec:0x8139 rev=0x20 -> r8169"     "10EC:8139 Rev 0x20 -> r8169 (C+-Modus da)"
has "$T" "netdev: tab 0x10ec:0x8139 rev=0x10 -> none  rtl8139 rev < 0x20, no C+ mode" \
    "GEGENPROBE: DIESELBE Nummer, Revision 0x10 -> KEIN Treiber, mit Begruendung"
has "$T" "netdev: tab 0x8086:0x15f3 rev=0x0 -> none  igc silicon" \
    "8086:15F3 (I225) -> erkannt, kein Treiber, Grund genannt"
has "$T" "netdev: tab 0x8086:0x125b rev=0x0 -> none  igc silicon" \
    "8086:125B (I226) -> erkannt, kein Treiber, Grund genannt"
has "$T" "netdev: tab 0x8086:0x1533 rev=0x0 -> none  igb silicon" \
    "8086:1533 (I210) -> erkannt, kein Treiber, Grund genannt"
has "$T" "netdev: tab 0x8086:0x2723 rev=0x0 -> none  wifi" \
    "8086:2723 (AX200) -> erkannt als WLAN, kein Treiber"
has "$T" "netdev: tab 0x14e4:0x1686 rev=0x0 -> none  other vendor" \
    "14E4:1686 (Broadcom) -> anderer Hersteller, kein Treiber"
has "$T" "netdev: tab 0x1234:0x5678 rev=0x0 -> none" \
    "eine Nummer, die es nicht gibt -> none"
hasnot "$T" "0x1234:0x5678 rev=0x0 -> none  " \
    "und fuer die erfundene Nummer wird KEIN Grund behauptet"

# ------------------------------------------------------------ der Draht
wire_up() {
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
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
}
wire_down() { ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null; }
bridge_up() { "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!; sleep 0.4; }
bridge_down() { [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; wait "$BRPID" 2>/dev/null; BRPID=""; sleep 0.2; }

# qemu_bg <nic-device> <append> <out> [weitere Argumente...]
qemu_bg() {
    local nic=$1 append=$2 out=$3
    shift 3
    rm -f "$out" "$MON"
    ( timeout 220 qemu-system-x86_64 -kernel "$K" -m 256 -append "$append" \
        -serial "file:$out" -display none -no-reboot \
        -monitor "unix:$MON,server,nowait" "$@" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "$nic,netdev=n0,id=nic0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$out.rc" ) &
    QPID=$!
}
qemu_wait() { wait "$QPID" 2>/dev/null; QPID=""; }
await_line() { # Datei Text Sekunden
    local i
    for i in $(seq 1 $(( ${3:-20} * 5 ))); do
        [ -f "$1" ] && grep -qaF "$2" "$1" && return 0
        sleep 0.2
    done
    return 1
}

BASE="nokbd nosched noproc nofs noring3"
NETARGS="nic nip=$OSUM_IP/24 ngw=$HOST_IP"

# =====================================================================
echo "== 3. der Bus entscheidet, und sagt es =="
# =====================================================================
wire_up; bridge_up
qemu_bg "rtl8139" "osum $BASE $NETARGS nsvc=0 nwait=60" "$TMPD/bus-rtl.txt"
qemu_wait
bridge_down; wire_down
F="$TMPD/bus-rtl.txt"
has "$F" "10ec:8139 class=02:00:00 network" "die PCI-Durchmusterung findet 10EC:8139 auf Klasse 02:00"
has "$F" "netdev: c0=r8169" "netdev waehlt den Treiber 'r8169' aus der Tabelle"
has "$F" "mac=52:54:00:aa:bb:cc" \
    "die Ethernet-Adresse wurde AUS DEM CHIP gelesen und ist die, die QEMU bekam"
n=$(grep -aoE 'nic: netd=[0-9]+' "$F" | cut -d= -f2)
num "die Netzaufgabe gibt es" "${n:-0}" ge 1

echo "   Gegenprobe: derselbe Hersteller, ein Chip ohne Treiber"
wire_up; bridge_up
qemu_bg "ne2k_pci" "osum $BASE $NETARGS nsvc=0 nwait=60" "$TMPD/bus-ne2k.txt"
qemu_wait
bridge_down; wire_down
R="$TMPD/bus-ne2k.txt"
has "$R" "netdev: no driver for 0x10ec:0x8029" \
    "die unbekannte Karte wird MIT IHREN NUMMERN genannt -- der Satz, den ein Brett braucht"
has "$R" "nic: no device" "und der Kern sagt, dass unter dem Stapel nichts liegt"
hasnot "$R" "netdev: c0=" "kein Treiber hat eine Karte beansprucht, die er nicht fahren kann"

# =====================================================================
echo "== 4. dieselbe Abnahme wie in Runde HWNET, auf dem Realtek =="
# =====================================================================
dd if=/dev/urandom of="$TMPD/quarter.bin" bs=1024 count=256 2>/dev/null

# --- ICMP. Die drei Sekunden sind aus Runde HWNET uebernommen, damit die
# Zahlen vergleichbar bleiben, und nicht als Bequemlichkeitspause.
wire_up; bridge_up
qemu_bg "rtl8139" "osum $BASE $NETARGS nsvc=0 nwait=1500" "$TMPD/ping-rtl.txt"
await_line "$TMPD/ping-rtl.txt" "nic: netd=" 25
sleep 3
ip netns exec "$NS" ping -c 20 -i 0.1 -W 2 "$OSUM_IP" > "$TMPD/pingout.txt" 2>&1
qemu_wait
bridge_down; wire_down
got=$(grep -oE '[0-9]+ received' "$TMPD/pingout.txt" | grep -oE '^[0-9]+')
num "rtl8139: ping -c 20 aus dem Linux-Kern, Antworten" "${got:-0}" ge 19
rtt=$(grep -oE 'min/avg/max/mdev = [0-9.]+/[0-9.]+' "$TMPD/pingout.txt" \
      | awk -F'= ' '{print $2}' | cut -d/ -f2)
[ -n "$rtt" ] && ok "rtl8139: Umlaufzeit, Mittel $rtt ms (QEMU/TCG, ohne KVM)" \
              || bad "rtl8139: keine Umlaufzeit"
num "rtl8139: Unterbrechungen, die der Chip wirklich ausgeloest hat" \
    "$(val "$TMPD/ping-rtl.txt" irqs)" ge 5
num "rtl8139: ICMP-Nachrichten, die der Stapel gezaehlt hat" \
    "$(val "$TMPD/ping-rtl.txt" icmp)" ge 19
num "rtl8139: Rahmen, die der Chip als fehlerhaft meldete" \
    "$(val "$TMPD/ping-rtl.txt" rerr)" eq 0
num "rtl8139: die Verbindung steht am Ende" "$(val "$TMPD/ping-rtl.txt" link)" eq 1

# --- TCP, 256 KiB in Osum hinein
wire_up; bridge_up
qemu_bg "rtl8139" "osum $BASE $NETARGS nsvc=1 nport=7 nbytes=262144" "$TMPD/sink-rtl8139.txt"
await_line "$TMPD/sink-rtl8139.txt" "nic: listening=7" 25
ip netns exec "$NS" timeout 120 nc -q 1 "$OSUM_IP" 7 < "$TMPD/quarter.bin" >/dev/null 2>&1
qemu_wait
bridge_down; wire_down
S="$TMPD/sink-rtl8139.txt"
num "rtl8139: Oktette, die in Osum angekommen sind" "$(val "$S" octets)" eq 262144
num "rtl8139: Rahmen, die der Chip empfangen hat" "$(val "$S" rx_f)" ge 150
num "rtl8139: Abschnitte mit falscher Pruefsumme" "$(val "$S" csum)" eq 0
num "rtl8139: Wiederholungen auf einem sauberen Draht" "$(val "$S" rexmit)" eq 0
num "rtl8139: Rahmen, die der Treiber verwerfen musste (Ring voll)" "$(val "$S" drops)" eq 0
num "rtl8139: Rahmen, die der Chip als fehlerhaft meldete" "$(val "$S" rerr)" eq 0
# DIESE ZWEI ZEILEN SIND DER GEFUNDENE FEHLER, festgenagelt. Mit 32
# Ringplaetzen -- der Zahl, die `e1000.fi` benutzt -- stand hier
# `ooo=41` und `286 KiB/s`: QEMUs rtl8139 wirft einen Rahmen weg, fuer
# den kein Deskriptor frei ist, waehrend QEMUs e1000 ihn beiseitelegt.
# Ein echter 8168 macht es wie der rtl8139. Mit 128 Plaetzen sind beide
# Zahlen null. Wer den Ring wieder verkleinert, faellt hier durch.
num "rtl8139: Abschnitte ausser der Reihe (jeder einer ist ein verlorener Rahmen)" \
    "$(val "$S" ooo)" eq 0
num "rtl8139: Rahmen, die der Chip mangels Ringplatz verwarf" "$(val "$S" rovw)" eq 0
ok "rtl8139: Durchsatz Linux -> Osum: $(val "$S" kib_per_s) KiB/s ($(val "$S" us) us fuer 256 KiB)"

# --- DHCP, aus einem Server, den dieses Verzeichnis nicht geschrieben hat
wire_up; bridge_up
cat > "$TMPD/udhcpd.conf" <<EOF
start 10.9.0.50
end 10.9.0.60
interface $V1
option subnet 255.255.255.0
option router $HOST_IP
option lease 600
lease_file $TMPD/udhcpd.leases
pidfile $TMPD/udhcpd.pid
EOF
: > "$TMPD/udhcpd.leases"
ip netns exec "$NS" busybox udhcpd -f "$TMPD/udhcpd.conf" > "$TMPD/udhcpd.log" 2>&1 &
DHPID=$!
sleep 0.5
cp "$D" "$TMPD/live.img"
qemu_bg "rtl8139" \
    "osum $BASE nic nip=10.9.0.9/24 ngw=$HOST_IP nsvc=0 nwait=0 script=dhcp;ping -c 2 $HOST_IP;exit" \
    "$TMPD/dhcp-rtl.txt" -drive "file=$TMPD/live.img,format=raw,if=ide,index=0"
qemu_wait
kill "$DHPID" 2>/dev/null; DHPID=""
bridge_down; wire_down
H="$TMPD/dhcp-rtl.txt"
grep -qaE 'dhcp: offer ip=10\.9\.0\.(5[0-9]|60)' "$H" \
    && ok "rtl8139: ein OFFER aus busybox udhcpd -- ein Server, den dieses Verzeichnis nicht schrieb" \
    || bad "rtl8139: kein DHCP-Angebot ($(grep -a 'dhcp:' "$H" | head -2 | tr '\n' ' '))"
grep -qaE 'dhcp: ack ip=10\.9\.0\.(5[0-9]|60)' "$H" && ok "rtl8139: und ein ACK dafuer" \
    || bad "rtl8139: kein DHCP-ACK"
grep -qaE '^2 (transmitted|packets transmitted), 2 received' "$H" \
    && ok "rtl8139: und mit dieser Adresse erreicht er das Gateway (ICMP)" \
    || bad "rtl8139: er erreicht das Gateway mit der bezogenen Adresse nicht"

# =====================================================================
echo "== 5. die Gegenproben, in denen die Messung zusammenbrechen muss =="
# =====================================================================
wire_up; bridge_up
qemu_bg "rtl8139" "osum $BASE nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=400" "$TMPD/no.txt"
sleep 3
ip netns exec "$NS" ping -c 4 -i 0.3 -W 1 "$OSUM_IP" > "$TMPD/noping.txt" 2>&1
qemu_wait
bridge_down; wire_down
num "GEGENPROBE ohne den Treiber, verlorene Pakete" "$(loss "$TMPD/noping.txt")" eq 100
has "$TMPD/no.txt" "nic: skipped" "und der Kern sagt, warum"

wire_up; bridge_up
qemu_bg "rtl8139" "osum $BASE $NETARGS nicnobm nsvc=0 nwait=400" "$TMPD/nobm.txt"
sleep 3
ip netns exec "$NS" ping -c 4 -i 0.3 -W 1 "$OSUM_IP" > "$TMPD/nobmping.txt" 2>&1
qemu_wait
bridge_down; wire_down
has "$TMPD/nobm.txt" "master=0" "das Busmasterbit ist wirklich aus"
num "GEGENPROBE ohne Busmaster, verlorene Pakete" "$(loss "$TMPD/nobmping.txt")" eq 100

# =====================================================================
echo "== 6. der volle Ring und der zu grosse Rahmen =="
# =====================================================================
# Zwei Zusagen, die ein Ping nie ausloest, weil sie erst eintreten, wenn
# etwas schiefgeht. `nicself` schaltet dem Chip das Senden ab, fuellt den
# Ring, bis er ueberlaeuft, und wirft dann einen Rahmen hinterher, der
# groesser ist als ein Puffer. Beides mit Zahlen statt mit Zusicherungen.
wire_up; bridge_up
qemu_bg "rtl8139" "osum $BASE $NETARGS nicself nsvc=0 nwait=1800" "$TMPD/self.txt"
await_line "$TMPD/self.txt" "nic: netd=" 25
sleep 3
ip netns exec "$NS" ping -c 6 -i 0.2 -W 1 "$OSUM_IP" > "$TMPD/selfping.txt" 2>&1
qemu_wait
bridge_down; wire_down
SF="$TMPD/self.txt"
line=$(grep -aoE 'r8169: self fit=[0-9]+ drop=[0-9]+ over=[0-9]+ link=[0-9]+ lchg=[0-9]+ rerr=[0-9]+ ovw=[0-9]+ slots=[0-9]+' "$SF" | tail -1)
[ -n "$line" ] && ok "die Selbstpruefung hat gemeldet: $line" \
               || bad "die Selbstpruefung hat nichts gemeldet"
fit=$(echo "$line" | grep -oE 'fit=[0-9]+' | cut -d= -f2)
drp=$(echo "$line" | grep -oE 'drop=[0-9]+' | cut -d= -f2)
ovr=$(echo "$line" | grep -oE 'over=[0-9]+' | cut -d= -f2)
slt=$(echo "$line" | grep -oE 'slots=[0-9]+' | cut -d= -f2)
# 128 Deskriptoren, einer bleibt immer leer -- voll und leer waeren sonst
# derselbe Zustand. Also passen genau 127 hinein.
num "der Empfangs- und Sendering hat 128 Plaetze (gemessen noetig, siehe r8169.fi)" \
    "${slt:-0}" eq 128
num "RINGUEBERLAUF: Rahmen, die in den Ring passten (128 Plaetze, einer bleibt leer)" \
    "${fit:-0}" eq 127
num "RINGUEBERLAUF: die 9 weiteren Versuche wurden ALLE abgewiesen und gezaehlt" \
    "${drp:-0}" eq 9
num "GROESSER ALS MTU: ein Rahmen von 2049 Oktett wurde abgewiesen" "${ovr:-0}" eq 1
has "$SF" "cpcmd=0x3" "der C+-Modus ist wirklich eingeschaltet (CpCmd = TxEnb|RxEnb)"
has "$SF" "rcr=0xe70a" "der Empfangsfilter steht auf 'eigene Adresse + Rundruf'"
has "$SF" "var=1 rev=0x20" "der Chip wurde als 8139C+ erkannt, an seiner PCI-Revision"
# Und nach der Selbstpruefung muss die Karte WIEDER REDEN -- sonst waere
# die Pruefung ein Schaden und kein Nachweis.
num "und danach redet die Karte weiter: Pakete verloren" \
    "$(loss "$TMPD/selfping.txt")" eq 0

# =====================================================================
echo "== 7. die Verbindung weg und wieder da =="
# =====================================================================
wire_up; bridge_up
qemu_bg "rtl8139" "osum $BASE $NETARGS nsvc=0 nwait=2600" "$TMPD/link.txt"
await_line "$TMPD/link.txt" "nic: netd=" 25
sleep 3
ip netns exec "$NS" ping -c 4 -i 0.2 -W 1 "$OSUM_IP" > "$TMPD/l1.txt" 2>&1
mon "set_link nic0 off"
sleep 2
ip netns exec "$NS" ping -c 4 -i 0.2 -W 1 "$OSUM_IP" > "$TMPD/l2.txt" 2>&1
mon "set_link nic0 on"
sleep 3
ip netns exec "$NS" ping -c 4 -i 0.2 -W 1 "$OSUM_IP" > "$TMPD/l3.txt" 2>&1
qemu_wait
bridge_down; wire_down
num "vorher: der Ping kommt durch"           "$(loss "$TMPD/l1.txt")" eq 0
num "Kabel gezogen: NICHTS kommt mehr durch" "$(loss "$TMPD/l2.txt")" eq 100
num "Kabel wieder dran: der Ping kommt WIEDER durch, ohne Neustart" \
    "$(loss "$TMPD/l3.txt")" eq 0
num "und der Treiber meldet die Verbindung am Ende als stehend" \
    "$(val "$TMPD/link.txt" link)" eq 1

# =====================================================================
echo "== 8. die drei Spalten, nebeneinander =="
# =====================================================================
# Dieselbe Abnahme, dieselben Zahlen, drei Chips -- damit Runde HWNET eine
# dritte Spalte bekommt und nicht eine zweite Tabelle.
for dev in virtio-net-pci e1000; do
    wire_up; bridge_up
    qemu_bg "$dev" "osum $BASE $NETARGS nsvc=1 nport=7 nbytes=262144" "$TMPD/sink-$dev.txt"
    await_line "$TMPD/sink-$dev.txt" "nic: listening=7" 25
    ip netns exec "$NS" timeout 120 nc -q 1 "$OSUM_IP" 7 < "$TMPD/quarter.bin" >/dev/null 2>&1
    qemu_wait
    bridge_down; wire_down
    num "$dev: Oktette, die in Osum angekommen sind" \
        "$(val "$TMPD/sink-$dev.txt" octets)" eq 262144
done

printf '   %-16s %10s %8s %8s %8s %6s %8s\n' Chip Oktett KiB/s rx_f irqs csum Wiederh.
for pair in "rtl8139:sink-rtl8139" "virtio-net-pci:sink-virtio-net-pci" "e1000:sink-e1000"; do
    dev=${pair%%:*}; f="$TMPD/${pair#*:}.txt"
    printf '   %-16s %10s %8s %8s %8s %6s %8s\n' "$dev" \
        "$(val "$f" octets)" "$(val "$f" kib_per_s)" "$(val "$f" rx_f)" \
        "$(val "$f" irqs)" "$(val "$f" csum)" "$(val "$f" rexmit)"
done

echo "RTL: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ] || exit 1
