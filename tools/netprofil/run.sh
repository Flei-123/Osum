#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/netprofil/run.sh -- RUNDE NETPROFIL, GEMESSEN.
#
# ==================================================================
# WAS DIESE RUNDE BEHAUPTET UND WAS HIER NACHGERECHNET WIRD
# ==================================================================
#
# Osum hatte bis zu dieser Runde GENAU EINE Hardwareadresse -- die aus
# dem EEPROM der Karte, in jedem Netz, fuer immer. Das ist eine Kennung,
# an der sich ein Mensch ueber Standorte hinweg verfolgen laesst; Android
# und iOS haben deshalb seit 2020 den umgekehrten Standardfall.
#
# Diese Runde baut die Netzprofile und die MAC-Richtlinie darin. Was hier
# gemessen wird, ist jede einzelne Zusage daraus:
#
#   1. DIE ZWEI BITS. Eine gewuerfelte Adresse MUSS im ersten Oktett
#      "lokal verwaltet" (0x02) tragen und darf nicht Multicast (0x01)
#      sein. Gemessen ueber 20 000 Wuerfe, nicht ueber einen -- bei einem
#      einzelnen Wurf bliebe eine fehlende Maske mit 75 Prozent
#      Wahrscheinlichkeit unentdeckt.
#   2. DIE DREI STUFEN, an der wirksamen Adresse:
#        `geraet` -> die Adresse der Karte, unveraendert
#        `netz`   -> ueber Trennen UND ueber einen NEUSTART hinweg
#                    dieselbe; nach Loeschen und Neuanlegen eine ANDERE
#        `immer`  -> zwei Verbindungen, zwei verschiedene Adressen
#   3. WAS DIE KARTE WIRKLICH ZULAESST. Nicht behauptet: gesetzt,
#      ZURUECKGELESEN, gemeldet. Fuer virtio-net mit und ohne
#      Steuerwarteschlange und fuer e1000.
#   4. DER DRAHT. `tcpdump` auf der Linux-Seite sagt, welche
#      Absenderadresse wirklich auf der Leitung stand, und der
#      Neighbour-Cache des Linux-Kernels sagt es ein zweites Mal. Zwei
#      Zeugen, keiner davon aus diesem Repo.
#   5. DHCP UEBERLEBT DEN WECHSEL. `busybox udhcpd` vergibt nach dem
#      Adresswechsel eine Adresse, und der Vertrag steht auf der NEUEN
#      Hardwareadresse -- nachgelesen in seiner eigenen Vergabeliste.
#   6. EINE HALB GESCHRIEBENE PROFILDATEI haengt das System nicht auf:
#      die kaputten Zeilen werden GEZAEHLT und gemeldet, die uebrigen
#      Profile bleiben benutzbar.
#   7. DIE RECHTE. Ein gewoehnlicher Nutzer kommt an die Datei nicht
#      heran und kann die Hardwareadresse nicht setzen.
#
# ==================================================================
# DIE GEGENPROBEN -- jede ein Lauf, in dem die Messung ZUSAMMENBRICHT
# ==================================================================
#
#   `fixedrand`          die Zufallsquelle liefert fuer immer 0x5A. Dann
#                        sind alle Wuerfe gleich und die Zusage ueber
#                        `immer` MUSS fallen. Ohne diesen Lauf bewiese
#                        "zwei verschiedene Adressen" nur, dass zwei
#                        Zahlen ungleich waren.
#   `nomacvq`            die Steuerwarteschlange von virtio-net wird
#                        nicht ausgehandelt. Die KARTE kann ihre Adresse
#                        dann nicht mehr aendern -- der Draht traegt die
#                        neue, die Karte die alte, und der Kern muss das
#                        SAGEN statt es zu umgehen.
#   `nomacvq nomacset`   dazu: die Ueberlagerung wirkt nicht. Dann steht
#                        die ECHTE Adresse auf dem Draht, und tcpdump
#                        muss sie sehen. Das ist die Gegenprobe, ohne die
#                        Punkt 4 nichts beweist.
#
# ==================================================================
# DER DRAHT
# ==================================================================
#
# Derselbe wie in Runde K8 (`tools/net/bridge.c`): QEMUs UDP-Backend,
# eine AF_PACKET-Bruecke, ein veth-Paar und ein Netzwerknamensraum.
# `/dev/net/tun` gibt es im Behaelter, in dem dieses Repo gemessen wird,
# nicht.
#
# Aufruf:  bash tools/netprofil/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
PROGS="sh ls cat echo netprof npt dhcp ping su id"
BLOCKS=8192
WUERFE=${NP_WUERFE:-20000}

NS=npro-$$
V0=np0-$$
V1=np1
HOST_IP=10.9.0.1
QPORT=$(( 13000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))
CARDMAC=52:54:00:aa:bb:cc
FESTMAC=0a:1b:2c:3d:4e:5f

TMPD=$(mktemp -d)
BRPID=""
DHPID=""
TDPID=""
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$DHPID" ] && kill "$DHPID" 2>/dev/null
    [ -n "$TDPID" ] && kill "$TDPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

num() { # name wert op erwartet
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "${wert:-}" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
has()    { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

# Ein Feld aus einer `npt:`-Zeile.
nval() { grep -a "^npt: $2" "$1" 2>/dev/null | tail -1 \
         | grep -aoE "(^|[ ])$3=[0-9a-f]+" | tail -1 | cut -d= -f2; }

# ---------------------------------------------------------- Werkzeuge
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh fehlgeschlagen"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 fehlt"; exit 1; }
for t in qemu-system-x86_64 ip gcc python3 busybox tcpdump; do
    command -v "$t" >/dev/null 2>&1 || { echo "NETPROFIL: uebersprungen, $t fehlt"; exit 0; }
done
ip netns del "$NS" 2>/dev/null
if ! ip netns add "$NS" 2>/dev/null; then
    echo "NETPROFIL: uebersprungen, Netzwerknamensraeume gehen hier nicht"
    exit 0
fi
ip netns del "$NS" 2>/dev/null

. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL

# =====================================================================
echo "== 1. bauen: der Kern mit netprof.fi, /bin/netprof und /bin/npt =="
# =====================================================================
export HWNET_PROGS="$PROGS"
export HWNET_BLOCKS=$BLOCKS
bash tools/hwnet/build.sh "$TMPD" 0 > "$TMPD/b0.txt" 2>&1 \
    && ok "firnc0 baut den Kern und $(echo $PROGS | wc -w) Programme" \
    || { bad "firnc0 baut nicht"; sed 's/^/        /' "$TMPD/b0.txt" | head -12
         echo "NETPROFIL: $pass bestanden, $((fail)) FEHLGESCHLAGEN"; exit 1; }
[ -f "$TMPD/k.mb" ] || { echo "NETPROFIL: kein Abbild"; exit 1; }

# DIE ZWEITE STUFE. Beide Uebersetzer muessen dieselben Dateien nehmen --
# `netprof.fi` ist neu, und eine Datei, die nur firnc0 uebersetzt, bricht
# den Selbstbau aus Runde K16.
if [ -x "$FC1" ]; then
    mkdir -p "$TMPD/s1"
    bash tools/hwnet/build.sh "$TMPD/s1" 1 > "$TMPD/b1.txt" 2>&1 \
        && ok "firnc1 (der Uebersetzer in Firn) baut dasselbe" \
        || { bad "firnc1 baut nicht"; sed 's/^/        /' "$TMPD/b1.txt" | head -10; }
else
    note "firnc1 fehlt -- die zweite Stufe wird nicht gemessen"
fi

undef=""
for p in netprof npt; do
    u=$(nm -u "$TMPD/$p.elf" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -n "$u" ] && undef="$undef $p:$u"
done
[ -z "$undef" ] && ok "kein Programm dieser Runde hat ein undefiniertes Symbol" \
               || bad "undefinierte Symbole:$undef"

python3 tools/kernel/syscalls.py > "$TMPD/sys.txt" 2>&1 \
    && ok "die Aufrufnummern: $(tail -1 "$TMPD/sys.txt")" \
    || { bad "die Aufrufnummern kollidieren"; sed 's/^/        /' "$TMPD/sys.txt"; }
for n in 1330 1331; do
    a=$(grep -acE "u64 = $n\b" kernel/sys.fi)
    b=$(grep -acE "u64 = $n\b" lib/libc/kcall.fi)
    if [ "$a" = 1 ] && [ "$b" = 1 ]; then ok "Aufrufnummer $n: einmal im Kern, einmal in der libc"
    else bad "Aufrufnummer $n: $a im Kern, $b in der libc"; fi
done
python3 tools/kernel/memmap.py kernel > "$TMPD/mem.txt" 2>&1 \
    && ok "die Speicherkarte: $(tail -1 "$TMPD/mem.txt")" \
    || { bad "die Speicherkarte kollidiert"; sed 's/^/        /' "$TMPD/mem.txt" | tail -8; }
grep -q 'NETPROF' tools/kernel/memmap.py \
    && ok "NETPROF_OFF steht in der Karte und wird mitgerechnet" \
    || bad "NETPROF_OFF fehlt in tools/kernel/memmap.py"

BASE="osum nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
qemu_solo() { # <append> <out> [extra...]
    local append=$1 out=$2
    shift 2
    rm -f "$out"
    cp "$TMPD/disk.img" "$TMPD/live.img"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$append" -serial "file:$out" -display none -no-reboot \
        -netdev user,id=n0 -device "virtio-net-pci,netdev=n0,mac=$CARDMAC" \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
}

# =====================================================================
echo "== 2. die zwei Bits, ueber $WUERFE Wuerfe =="
# =====================================================================
qemu_solo "$BASE script=npt $WUERFE;exit" "$TMPD/npt.txt"
N="$TMPD/npt.txt"
has "$N" "npt: ende" "der Messlaeufer /bin/npt ist durchgelaufen"
num "Wuerfe ohne das Bit 'lokal verwaltet'" "$(nval "$N" wuerfel ohne_lokal)" eq 0
num "Wuerfe mit gesetztem Multicast-Bit"    "$(nval "$N" wuerfel multicast)" eq 0
num "verschiedene Adressen unter den ersten 512 Wuerfen" \
    "$(nval "$N" wuerfel verschieden)" eq 512
pk=$(grep -a '^npt: policy' "$N" | grep -oE 'kern=[0-9]+' | cut -d= -f2)
pr=$(grep -a '^npt: policy' "$N" | grep -oE 'ring3=[0-9]+' | cut -d= -f2)
if [ -n "$pk" ] && [ "$pk" = "$pr" ] && [ "$pk" = 131328 ]; then
    ok "die drei Stufen: Kern und Ring 3 nennen dieselben Zahlen ($pk = 0x020100)"
else
    bad "die Stufen laufen auseinander: Kern=$pk Ring3=$pr"
fi
num "Stufe geraet: wirksame Adresse IST die der Karte" "$(nval "$N" geraet gleich)" eq 1
num "Stufe immer: zwei Verbindungen, zwei Adressen"    "$(nval "$N" immer gleich)" eq 0
num "Stufe netz: derselbe Wert, zweimal gesetzt, gleich" "$(nval "$N" netz gleich)" eq 1
mg=$(nval "$N" geraet mac)
[ "$mg" = "525400aabbcc" ] \
    && ok "und die Adresse der Karte ist die, die QEMU vergeben hat ($mg)" \
    || bad "die Adresse der Karte ist $mg, erwartet 525400aabbcc"

qemu_solo "$BASE fixedrand script=npt 200;exit" "$TMPD/fix.txt"
F="$TMPD/fix.txt"
num "GEGENPROBE fixedrand: verschiedene Adressen" "$(nval "$F" wuerfel verschieden)" eq 1
num "GEGENPROBE fixedrand: 'immer' liefert ZWEIMAL dasselbe" \
    "$(nval "$F" immer gleich)" eq 1
note "ohne diesen Lauf bewiese 'zwei verschiedene Adressen' nur, dass zwei Zahlen ungleich waren"

# =====================================================================
echo "== 3. was die Karte wirklich zulaesst =="
# =====================================================================
qemu_solo "$BASE script=npt 100;exit" "$TMPD/c-vq.txt"
qemu_solo "$BASE nomacvq script=npt 100;exit" "$TMPD/c-novq.txt"
qemu_solo "$BASE nomacvq nomacset script=npt 100;exit" "$TMPD/c-none.txt"

d=$(nval "$TMPD/c-vq.txt" split draht); k=$(nval "$TMPD/c-vq.txt" split karte)
if [ -n "$d" ] && [ "$d" = "$k" ] && [ "$d" != "525400aabbcc" ]; then
    ok "virtio-net MIT Steuerwarteschlange: Draht UND Karte tragen $d"
else
    bad "virtio-net mit Steuerwarteschlange: draht=$d karte=$k"
fi
num "  und der Kern meldet 'Karte hat es angenommen'" \
    "$(nval "$TMPD/c-vq.txt" hwok hwok)" eq 1

d=$(nval "$TMPD/c-novq.txt" split draht); k=$(nval "$TMPD/c-novq.txt" split karte)
if [ -n "$d" ] && [ "$d" != "$k" ] && [ "$k" = "525400aabbcc" ]; then
    ok "GEGENPROBE nomacvq: Draht traegt $d, die Karte weiter $k"
else
    bad "GEGENPROBE nomacvq: draht=$d karte=$k -- erwartet wurde ein Unterschied"
fi
num "  und der Kern sagt, dass die Karte es NICHT angenommen hat" \
    "$(nval "$TMPD/c-novq.txt" hwok hwok)" eq 0
num "  und dass diese Kartensorte es dann gar nicht kann" \
    "$(nval "$TMPD/c-novq.txt" hwok settable)" eq 0

d=$(nval "$TMPD/c-none.txt" split draht)
[ "$d" = "525400aabbcc" ] \
    && ok "GEGENPROBE nomacvq+nomacset: die ECHTE Adresse steht auf dem Draht" \
    || bad "GEGENPROBE nomacvq+nomacset: draht=$d, erwartet 525400aabbcc"
num "  und 'immer' liefert dann zweimal dasselbe" \
    "$(nval "$TMPD/c-none.txt" immer gleich)" eq 1

rm -f "$TMPD/e1000.txt"; cp "$TMPD/disk.img" "$TMPD/live.img"
timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
    -append "$BASE script=npt 100;exit" -serial "file:$TMPD/e1000.txt" \
    -display none -no-reboot -netdev user,id=n0 \
    -device "e1000,netdev=n0,mac=$CARDMAC" \
    -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
E="$TMPD/e1000.txt"
d=$(nval "$E" split draht); k=$(nval "$E" split karte)
if [ -n "$d" ] && [ "$d" = "$k" ] && [ "$d" != "525400aabbcc" ]; then
    ok "e1000: RAL/RAH sind schreibbar -- Draht UND Karte tragen $d"
else
    bad "e1000: draht=$d karte=$k"
fi
num "  e1000 meldet 'Karte hat es angenommen'" "$(nval "$E" hwok hwok)" eq 1
note "der Unterschied zwischen den Karten ist echt: virtio braucht einen Befehl"
note "auf einer dritten Warteschlange, e1000 zwei Schreibzugriffe auf ein Register"

# =====================================================================
echo "== 4. die Profildatei, ueber fuenf Neustarts derselben Platte =="
# =====================================================================
# EIGENES ABBILD, MIT /etc DARIN. `tools/hwnet/build.sh` legt nur /bin an
# -- und ohne /etc kann `netprof` nichts speichern. Der erste Lauf dieser
# Runde hat genau das gezeigt: "die Profildatei ist nicht schreibbar",
# fuenfmal hintereinander, und die Ursache war ein fehlendes Verzeichnis
# und kein Rechtefehler.
python3 tools/osum/mkfs.py build "$TMPD/p.img" $BLOCKS "/bin/" "/etc/" \
    /bin/sh="$TMPD/sh.elf" /bin/ls="$TMPD/ls.elf" /bin/cat="$TMPD/cat.elf" \
    /bin/echo="$TMPD/echo.elf" /bin/netprof="$TMPD/netprof.elf" \
    /bin/npt="$TMPD/npt.elf" /bin/dhcp="$TMPD/dhcp.elf" \
    /bin/ping="$TMPD/ping.elf" > "$TMPD/mk1.txt" 2>&1 \
    && ok "ein Abbild mit /etc -- die Profildatei entsteht erst im Betrieb" \
    || { bad "mkfs fehlgeschlagen"; sed 's/^/        /' "$TMPD/mk1.txt" | head -4; }
boot_p() { # <script> <out>
    rm -f "$2"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "$BASE script=$1" -serial "file:$2" -display none -no-reboot \
        -netdev user,id=n0 -device "virtio-net-pci,netdev=n0,mac=$CARDMAC" \
        -drive "file=$TMPD/p.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
macs() { grep -a '^netprof: Adresse jetzt' "$1" | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}'; }

# DAS PROFIL DIESES ABSCHNITTS HAT EINE FESTE ADRESSE, und das ist kein
# Ausweichen, sondern die richtige Trennung: hier wird die MAC-STUFE
# gemessen, nicht der DHCP-Klient. Ein DHCP-Lauf je Verbindung waere
# fuenf zusaetzliche Minuten und ein zweiter Grund, warum ein Fall rot
# werden kann. DHCP steht in Abschnitt 8, auf einem echten Draht, gegen
# einen Server, den dieses Repo nicht geschrieben hat.
#
# GEMESSEN UND HIER FESTGEHALTEN: `netprof aus` nimmt die Adresse weg
# (0.0.0.0), und ein DHCP-Profil kann sich danach NICHT von selbst
# wieder holen -- der eingekaufte Stapel hat keinen Rundruf-Ausgang und
# sucht auch fuer 255.255.255.255 per ARP einen naechsten Sprung, den es
# ohne Adresse nicht gibt. Das steht so schon im Kopf von
# `kernel/user/dhcp.fi` und in docs/ROUNDNETPROFIL.md, und es ist die
# eine Grenze dieser Runde, die ein Benutzer wirklich merkt.
boot_p "netprof neu heim;netprof setz heim bezug fest;netprof setz heim ip 10.0.2.99;netprof setz heim maske 255.255.255.0;netprof setz heim gateway 10.0.2.2;netprof an heim;netprof aus;netprof an heim;cat /etc/netprofile.conf;exit" \
       "$TMPD/p1.txt"
a1=$(macs "$TMPD/p1.txt" | sed -n 1p)
a2=$(macs "$TMPD/p1.txt" | sed -n 2p)
has "$TMPD/p1.txt" "netprof: angelegt: heim" "netprof legt ein Profil an"
if [ -n "$a1" ] && [ "$a1" = "$a2" ]; then
    ok "Stufe netz: nach Trennen und Neuverbinden dieselbe Adresse ($a1)"
else
    bad "Stufe netz: $a1 vs $a2 -- sie haette dieselbe bleiben muessen"
fi
grep -qa '^heim:net0:offen:fest:10.0.2.99:' "$TMPD/p1.txt" \
    && ok "die Zeile steht lesbar in /etc/netprofile.conf" \
    || bad "die Profilzeile fehlt in der Datei"
hex=$(echo "$a1" | tr -d ':')
grep -qa "heim:net0:offen:fest:.*:netz:$hex:" "$TMPD/p1.txt" \
    && ok "und die gewuerfelte Adresse steht als zwoelf Hexziffern darin" \
    || bad "die Adresse steht nicht in der Zeile"
o1=$(printf '%d' "0x${hex:0:2}" 2>/dev/null)
if [ -n "$o1" ] && [ $(( o1 & 2 )) -eq 2 ] && [ $(( o1 & 1 )) -eq 0 ]; then
    ok "das erste Oktett IN DER DATEI ist lokal verwaltet und kein Multicast (0x${hex:0:2})"
else
    bad "das erste Oktett 0x${hex:0:2} traegt die falschen Bits"
fi

boot_p "netprof an heim;exit" "$TMPD/p2.txt"
b1=$(macs "$TMPD/p2.txt" | sed -n 1p)
if [ -n "$b1" ] && [ "$b1" = "$a1" ]; then
    ok "und nach einem NEUSTART ist es immer noch dieselbe ($b1)"
else
    bad "nach dem Neustart: $b1 statt $a1"
fi

# `neu` legt ein Profil MIT DHCP an -- also bekommt es hier wieder eine
# feste Adresse, damit dieser Abschnitt weiter nur die MAC-Stufe misst
# und nicht nebenbei den DHCP-Klienten.
boot_p "netprof loesche heim;netprof neu heim;netprof setz heim bezug fest;netprof setz heim ip 10.0.2.99;netprof setz heim maske 255.255.255.0;netprof setz heim gateway 10.0.2.2;netprof an heim;exit" "$TMPD/p3.txt"
c1=$(macs "$TMPD/p3.txt" | sed -n 1p)
if [ -n "$c1" ] && [ "$c1" != "$a1" ]; then
    ok "nach Loeschen und Neuanlegen eine ANDERE Adresse ($c1 statt $a1)"
else
    bad "nach Loeschen und Neuanlegen kam $c1 -- dieselbe wie vorher"
fi

boot_p "netprof mac heim immer;netprof an heim;netprof aus;netprof an heim;exit" \
       "$TMPD/p4.txt"
d1=$(macs "$TMPD/p4.txt" | sed -n 1p)
d2=$(macs "$TMPD/p4.txt" | sed -n 2p)
if [ -n "$d1" ] && [ -n "$d2" ] && [ "$d1" != "$d2" ]; then
    ok "Stufe immer: zwei Verbindungen, zwei Adressen ($d1, $d2)"
else
    bad "Stufe immer: $d1 und $d2 -- sie haetten verschieden sein muessen"
fi

boot_p "netprof mac heim geraet;netprof an heim;netprof stand;exit" "$TMPD/p5.txt"
grep -qa "wirksame Adresse (Draht): $CARDMAC" "$TMPD/p5.txt" \
    && ok "Stufe geraet: die echte Adresse der Karte, unveraendert" \
    || bad "Stufe geraet: $(grep -a 'wirksame Adresse' "$TMPD/p5.txt" | head -1)"
grep -qa 'ueberlagert:              nein' "$TMPD/p5.txt" \
    && ok "und es steht keine Ueberlagerung mehr" \
    || bad "bei 'geraet' steht noch eine Ueberlagerung"

# =====================================================================
echo "== 5. eine halb geschriebene Profildatei =="
# =====================================================================
cat > "$TMPD/kaputt.conf" <<'EOF'
# von Hand, mit Absicht kaputt
gut:net0:offen:dhcp:::::netz:0a1b2c3d4e5f:1:10:0
halb:net0:offen:dhcp:::
schrott:net0:offen:dhcp:::::netz:ZZZZZZZZZZZZ:1:20:0
wpa:net0:wpa2:dhcp:::::netz::1:30:0
zweitgut:net0:offen:fest:10.0.2.7:255.255.255.0:10.0.2.2::geraet::0:40:0
EOF
python3 tools/osum/mkfs.py build "$TMPD/kap.img" $BLOCKS "/bin/" "/etc/" \
    /bin/sh="$TMPD/sh.elf" /bin/cat="$TMPD/cat.elf" /bin/ls="$TMPD/ls.elf" \
    /bin/netprof="$TMPD/netprof.elf" /bin/dhcp="$TMPD/dhcp.elf" \
    "/etc/netprofile.conf=$TMPD/kaputt.conf@600:0:0" > "$TMPD/mk2.txt" 2>&1 \
    && ok "ein Abbild mit einer absichtlich kaputten Profildatei" \
    || { bad "mkfs fehlgeschlagen"; sed 's/^/        /' "$TMPD/mk2.txt" | head -4; }
rm -f "$TMPD/kap.txt"
timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
    -append "$BASE script=netprof;netprof an gut;exit" \
    -serial "file:$TMPD/kap.txt" -display none -no-reboot \
    -netdev user,id=n0 -device "virtio-net-pci,netdev=n0,mac=$CARDMAC" \
    -drive "file=$TMPD/kap.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
K="$TMPD/kap.txt"
has "$K" "netprof: fehlerhafte Zeilen" "die kaputten Zeilen werden GEMELDET"
n=$(grep -a 'netprof: fehlerhafte Zeilen' "$K" | grep -oE '[0-9]+' | head -1)
num "  und zwar genau so viele, wie kaputt sind" "${n:-0}" eq 3
has "$K" "gut " "das gute Profil steht trotzdem in der Liste"
has "$K" "zweitgut" "und das HINTER den kaputten Zeilen auch"
has "$K" "netprof: Adresse jetzt $FESTMAC" \
    "das gute Profil laesst sich benutzen, mit der Adresse aus der Datei"
hasnot "$K" "wpa " "eine Zeile mit 'wpa2' wird ABGELEHNT statt stumm auf 'offen' gezogen"

# =====================================================================
echo "== 6. die Rechte: /etc/netprofile.conf gehoert root =="
# =====================================================================
python3 - "$TMPD" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it = int(open("kernel/user/pw.fi").read().split("const KOSTEN: u64 = ")[1].split()[0])
def rec(pw, salt):
    dk = hashlib.pbkdf2_hmac('sha256', pw, salt, it, 32)
    return "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(),
                                binascii.hexlify(dk).decode())
open(d + "/passwd", "w").write(
    "root:x:0:0:root:/:/bin/sh\njustin:x:1000:1000:Justin:/home/justin:/bin/sh\n")
open(d + "/group", "w").write("root:x:0:\njustin:x:1000:\n")
open(d + "/shadow", "w").write(
    "root:%s:0:0:99999:7:::\n" % rec(b"rootpass", bytes(range(8))) +
    "justin:%s:0:0:99999:7:::\n" % rec(b"geheim12", bytes(range(8, 16))))
open(d + "/pw.txt", "w").write("geheim12\n")
PY
printf 'gut:net0:offen:dhcp:::::netz:0a1b2c3d4e5f:1:10:0\n' > "$TMPD/eine.conf"
cat > "$TMPD/rechte.sh" <<'SCRIPT'
echo ==BEGIN==
su justin /bin/netprof < /t/pw.txt
su justin /bin/netprof an gut < /t/pw.txt
su justin /bin/netprof neu fremd < /t/pw.txt
echo ==ENDE==
SCRIPT
python3 tools/osum/mkfs.py build "$TMPD/r.img" $BLOCKS "/bin/" "/etc/" "/t/" \
    /bin/sh="$TMPD/sh.elf" /bin/cat="$TMPD/cat.elf" /bin/ls="$TMPD/ls.elf" \
    /bin/id="$TMPD/id.elf" /bin/echo="$TMPD/echo.elf" \
    /bin/su="$TMPD/su.elf@4755:0:0" \
    /bin/netprof="$TMPD/netprof.elf" /bin/dhcp="$TMPD/dhcp.elf" \
    "/etc/passwd=$TMPD/passwd@644:0:0" "/etc/shadow=$TMPD/shadow@600:0:0" \
    "/etc/group=$TMPD/group@644:0:0" "/t/pw.txt=$TMPD/pw.txt@644:0:0" \
    "/t/rechte.sh=$TMPD/rechte.sh@644:0:0" \
    "/etc/netprofile.conf=$TMPD/eine.conf@600:0:0" > "$TMPD/mk3.txt" 2>&1 \
    && ok "ein Abbild mit /etc/shadow und einem Profil 0o600 root:root" \
    || { bad "mkfs fehlgeschlagen"; sed 's/^/        /' "$TMPD/mk3.txt" | head -4; }
rm -f "$TMPD/rechte.txt"
timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
    -append "$BASE script=sh /t/rechte.sh;exit" \
    -serial "file:$TMPD/rechte.txt" -display none -no-reboot \
    -netdev user,id=n0 -device "virtio-net-pci,netdev=n0,mac=$CARDMAC" \
    -drive "file=$TMPD/r.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
R="$TMPD/rechte.txt"
has "$R" "==ENDE==" "der Rechtelauf ist durchgelaufen"
grep -qa 'netprof: kein Profil' "$R" \
    && ok "ein gewoehnlicher Nutzer sieht die Profile gar nicht erst (0o600)" \
    || bad "justin hat die Profildatei gelesen"
hasnot "$R" "netprof: angelegt: fremd" \
    "und er kann kein Profil anlegen -- die Datei bleibt ihm verschlossen"
hasnot "$R" "netprof: Adresse jetzt" \
    "und er kann die Hardwareadresse nicht setzen (Aufruf 1331 ist root-eigen)"

# =====================================================================
echo "== 7. der Draht: was wirklich auf der Leitung stand =="
# =====================================================================
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

gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>"$TMPD/gcc.err" \
    && ok "tools/net/bridge.c: der Draht aus Runde K8 ist gebaut" \
    || { bad "bridge.c uebersetzt nicht"; head -5 "$TMPD/gcc.err" | sed 's/^/        /'; }

draht_lauf() { # <extra-worte> <out> <img>
    wire_up; bridge_up
    ip netns exec "$NS" timeout 60 tcpdump -i "$V1" -e -n -l 'arp or icmp' \
        > "$TMPD/td.txt" 2>/dev/null &
    TDPID=$!
    sleep 0.8
    rm -f "$2"
    timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
        -append "osum $1 nic nip=10.9.0.9/24 ngw=$HOST_IP nsvc=0 nwait=0 script=netprof an heim;ping -c 3 $HOST_IP;netprof stand;exit" \
        -serial "file:$2" -display none -no-reboot \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "virtio-net-pci,netdev=n0,mac=$CARDMAC" \
        -drive "file=$3,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    ip netns exec "$NS" ip neigh show > "$TMPD/neigh.txt" 2>/dev/null
    sleep 0.5
    kill "$TDPID" 2>/dev/null; wait "$TDPID" 2>/dev/null; TDPID=""
    bridge_down; wire_down
}

printf 'heim:net0:offen:fest:10.9.0.2:255.255.255.0:10.9.0.1::netz:0a1b2c3d4e5f:1:10:0\n' \
    > "$TMPD/draht.conf"
python3 tools/osum/mkfs.py build "$TMPD/w.img" $BLOCKS "/bin/" "/etc/" \
    /bin/sh="$TMPD/sh.elf" /bin/cat="$TMPD/cat.elf" /bin/ping="$TMPD/ping.elf" \
    /bin/netprof="$TMPD/netprof.elf" /bin/dhcp="$TMPD/dhcp.elf" \
    "/etc/netprofile.conf=$TMPD/draht.conf@600:0:0" >/dev/null 2>&1

cp "$TMPD/w.img" "$TMPD/w1.img"
draht_lauf "" "$TMPD/w1.txt" "$TMPD/w1.img"
cp "$TMPD/td.txt" "$TMPD/td1.txt"
grep -qaE '^3 (packets )?transmitted, 3 received' "$TMPD/w1.txt" \
    && ok "mit gewuerfelter Adresse erreicht Osum das Gateway (3 von 3 ICMP)" \
    || bad "kein ICMP durch: $(grep -aE 'transmitted' "$TMPD/w1.txt" | head -1)"
grep -qa "$FESTMAC > " "$TMPD/td1.txt" \
    && ok "TCPDUMP: die Absenderadresse auf dem Draht ist $FESTMAC" \
    || { bad "tcpdump sah die neue Adresse nicht"; note "$(head -3 "$TMPD/td1.txt")"; }
grep -qa "$CARDMAC > " "$TMPD/td1.txt" \
    && bad "tcpdump sah AUCH die echte Adresse $CARDMAC auf dem Draht" \
    || ok "und die echte Adresse $CARDMAC stand in keinem einzigen Rahmen"
grep -qa "lladdr $FESTMAC" "$TMPD/neigh.txt" \
    && ok "und der Linux-Kernel hat sie in seinen Neighbour-Cache eingetragen" \
    || { bad "der Neighbour-Cache kennt sie nicht"; note "$(cat "$TMPD/neigh.txt")"; }

cp "$TMPD/w.img" "$TMPD/w2.img"
draht_lauf "nomacvq nomacset" "$TMPD/w2.txt" "$TMPD/w2.img"
grep -qa "$CARDMAC > " "$TMPD/td.txt" \
    && ok "GEGENPROBE nomacset: jetzt steht $CARDMAC auf dem Draht" \
    || { bad "GEGENPROBE: die echte Adresse stand nicht auf dem Draht"
         note "$(head -3 "$TMPD/td.txt")"; }
grep -qa "$FESTMAC > " "$TMPD/td.txt" \
    && bad "GEGENPROBE: die gewuerfelte Adresse stand trotzdem auf dem Draht" \
    || ok "  und die gewuerfelte in keinem Rahmen -- die Ueberlagerung wirkt wirklich"

# =====================================================================
echo "== 8. DHCP ueberlebt den Adresswechsel =="
# =====================================================================
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
printf 'heim:net0:offen:dhcp:::::netz:0a1b2c3d4e5f:1:10:0\n' > "$TMPD/dh.conf"
python3 tools/osum/mkfs.py build "$TMPD/dh.img" $BLOCKS "/bin/" "/etc/" \
    /bin/sh="$TMPD/sh.elf" /bin/cat="$TMPD/cat.elf" /bin/ping="$TMPD/ping.elf" \
    /bin/netprof="$TMPD/netprof.elf" /bin/dhcp="$TMPD/dhcp.elf" \
    "/etc/netprofile.conf=$TMPD/dh.conf@600:0:0" >/dev/null 2>&1

wire_up; bridge_up
: > "$TMPD/udhcpd.leases"
ip netns exec "$NS" busybox udhcpd -f "$TMPD/udhcpd.conf" > "$TMPD/udhcpd.log" 2>&1 &
DHPID=$!
sleep 0.6
cp "$TMPD/dh.img" "$TMPD/dhlive.img"
rm -f "$TMPD/dhcp.txt"
timeout 240 $QEMU_X86 -kernel "$TMPD/k.mb" -m 256 \
    -append "osum nic nip=10.9.0.9/24 ngw=$HOST_IP nsvc=0 nwait=0 script=netprof an heim;ping -c 2 $HOST_IP;netprof stand;exit" \
    -serial "file:$TMPD/dhcp.txt" -display none -no-reboot \
    -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
    -device "virtio-net-pci,netdev=n0,mac=$CARDMAC" \
    -drive "file=$TMPD/dhlive.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
# DIE VERGABELISTE ERST SCHREIBEN LASSEN. `busybox udhcpd` haelt die
# Vertraege im Speicher und schreibt die Datei periodisch -- und auf
# SIGUSR1 sofort. Ohne dieses Signal las `dumpleases` eine halb
# geschriebene Datei und meldete "short read"; das war der einzige rote
# Fall des ersten vollstaendigen Laufs dieser Runde, und er lag nicht am
# Betriebssystem, sondern am Zeitpunkt des Lesens.
kill -USR1 "$DHPID" 2>/dev/null
sleep 0.8
kill "$DHPID" 2>/dev/null; DHPID=""
sleep 0.3
busybox dumpleases -a -f "$TMPD/udhcpd.leases" > "$TMPD/leases.txt" 2>&1
bridge_down; wire_down
H="$TMPD/dhcp.txt"
has "$H" "netprof: Adresse jetzt $FESTMAC" \
    "die Adresse wird VOR dem DHCP-Lauf gewechselt"
grep -qaE 'dhcp: offer ip=10\.9\.0\.(5[0-9]|60)' "$H" \
    && ok "ein OFFER aus busybox udhcpd -- nach dem Adresswechsel" \
    || bad "kein DHCP-Angebot ($(grep -a 'dhcp:' "$H" | head -2 | tr '\n' ' '))"
grep -qaE 'dhcp: (gesetzt|set) ip=10\.9\.0\.(5[0-9]|60)' "$H" \
    && ok "und der Klient hat die Adresse wirklich uebernommen" \
    || bad "der Klient hat die Adresse nicht uebernommen"
hasnot "$H" "dhcp: offer ip=10.9.0.9" \
    "er hat NICHT die Adresse zurueckbekommen, mit der er gebootet hat"
# IN DER ROHEN DATEI NACHSEHEN und nicht in der Ausgabe von
# `dumpleases`: das Format ist binaer, die sechs Oktette stehen
# unveraendert darin, und ein Textwerkzeug dazwischen ist eine
# Fehlerquelle mehr. Gesucht wird die Adresse als OKTETTFOLGE.
inlease() { # <mac mit doppelpunkten>
    python3 - "$TMPD/udhcpd.leases" "$1" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
m = bytes.fromhex(sys.argv[2].replace(':', ''))
sys.exit(0 if m in d else 1)
PY
}
if inlease "$FESTMAC"; then
    ok "DER VERTRAG STEHT AUF DER GEWUERFELTEN ADRESSE (Vergabeliste von udhcpd)"
else
    bad "die Vergabeliste kennt die gewuerfelte Adresse nicht"
    note "$(cat "$TMPD/leases.txt")"
fi
if inlease "$CARDMAC"; then
    bad "die Vergabeliste kennt AUCH die echte Adresse"
else
    ok "und die echte Adresse steht in keinem Vertrag"
fi
grep -qaE '^2 (packets )?transmitted, 2 received' "$H" \
    && ok "mit der per DHCP geholten Adresse erreicht Osum das Gateway" \
    || bad "kein ICMP nach dem DHCP-Lauf"

# =====================================================================
echo "== 9. die Zahlen =="
# =====================================================================
o=$(grep -a '^npt: verbindung_us' "$TMPD/npt.txt" | grep -oE 'ohne_mac=[0-9]+' | cut -d= -f2)
m=$(grep -a '^npt: verbindung_us' "$TMPD/npt.txt" | grep -oE 'mit_mac=[0-9]+' | cut -d= -f2)
s=$(grep -a '^npt: setzen_us' "$TMPD/npt.txt" | grep -oE 'setzen_us=[0-9]+' | cut -d= -f2)
if [ -n "$o" ] && [ -n "$m" ]; then
    ok "Verbindungsaufbau: ohne Adresswechsel $o us, mit $m us (Differenz $((m-o)) us)"
else
    bad "keine Zeitmessung"
fi
[ -n "$s" ] && ok "davon der Adresswechsel selbst: $s us (Befehl auf der Steuerwarteschlange)" \
            || bad "keine Messung des Adresswechsels"
so=$(grep -a '^npt: setzen_us' "$TMPD/c-novq.txt" | grep -oE 'setzen_us=[0-9]+' | cut -d= -f2)
# EHRLICH BENANNT: das ist NICHT "nur die Ueberlagerung". Ohne
# Steuerwarteschlange geht der Treiber trotzdem den anderen Weg -- sechs
# Schreibzugriffe ins Adressfeld des Geraetebereichs und sechs
# Lesezugriffe zum Nachpruefen -- und jeder davon ist unter KVM ein
# Ausstieg aus dem Gast. Deshalb kann diese Zahl GROESSER sein als die
# mit Warteschlange.
[ -n "$so" ] && note "ohne Steuerwarteschlange (Adressfeld schreiben und zuruecklesen): $so us"
by=$(stat -c%s "$TMPD/eine.conf")
note "eine Profilzeile ist $by Oktette; eine Datei mit einem Profil samt Kopfzeilen 304"
kl=$(wc -l < kernel/netprof.fi)
ul=$(wc -l < kernel/user/netprof.fi)
tl=$(wc -l < kernel/user/npt.fi)
rl=$(wc -l < tools/netprofil/run.sh)
ok "Zeilen: kernel/netprof.fi $kl, kernel/user/netprof.fi $ul, kernel/user/npt.fi $tl, dieser Laeufer $rl"

echo
if [ "$fail" -eq 0 ]; then
    echo "NETPROFIL: alle $pass Zusagen bestanden"
    exit 0
else
    echo "NETPROFIL: $pass bestanden, $fail FEHLGESCHLAGEN"
    exit 1
fi
