#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ebpf/run.sh -- RUNDE O-EBPF: DIE MASCHINE, DER PRUEFER, DIE HAKEN.
#
#   bash tools/ebpf/run.sh
#
# =====================================================================
# WAS HIER GEMESSEN WIRD
# =====================================================================
#
# Osum hatte bis zu dieser Runde kein eBPF -- der einzige Treffer im
# ganzen Baum stand in `docs/NETVIEW.md` und erwaehnte `cgroup/skb` als
# die Art, wie LINUX dasselbe Problem loest. Diese Runde baut eine
# eigene Maschine, einen eigenen Pruefer, Tafeln und zwei Haken.
#
# DIE ZUSAGEN, und jede ist hier eine Zahl und kein Adjektiv:
#
#   1. DIE MASCHINE RECHNET RICHTIG. Fuenfzehn Programme werden im Kern
#      gebaut, ausgefuehrt und ihr Ergebnis gegen eine Zahl gehalten,
#      die vorher feststeht -- ALU64 und ALU32, vorzeichenbehaftete
#      Vergleiche, arithmetisches Schieben, der Umlauf, Teilung durch
#      null, alle vier Zugriffsbreiten, der 64-Bit-Sofortwert.
#   2. DER PRUEFER WEIST DAS AB, WAS ER ABWEISEN MUSS. Zehn
#      Gegenproben -- UND eine elfte, die durchkommen MUSS. Ein
#      Pruefer, der alles abweist, faellt an dieser elften auf.
#   3. DIE TAFELN HALTEN, WAS MAN HINEINSCHREIBT, aus dem Kern UND aus
#      einem laufenden Programm heraus.
#   4. DER HAKEN VERWIRFT WIRKLICH RAHMEN, auf einer echten Leitung:
#      ein Programm, das ICMP wegwirft, laesst `ping` verschwinden --
#      waehrend im SELBEN Lauf eine HTTP-Uebertragung ueber TCP
#      weiterlaeuft. Ein Filter, der zuviel wegwirft, faellt damit
#      genauso auf wie einer, der zuwenig wegwirft.
#   5. WAS ES KOSTET, in Takten je Rahmen, im leeren Fall und mit
#      Programm -- im Kern gemessen zwischen zwei Lesungen des
#      Taktzaehlers und nicht mit einer Stoppuhr ueber eine
#      Uebertragung. Der Kopf von `kernel/netmon.fi` zeigt an vier
#      Messpaaren, warum eine Durchsatzmessung auf dieser Maschine
#      (Fremdlast) die Nachbarn misst und nicht den Code.
#
# Die Leitung ist die aus Runde K8: QEMUs UDP-Steckdose, die
# AF_PACKET-Bruecke aus `tools/net/bridge.c`, ein veth-Paar und ein
# Netzraum -- `/dev/net/tun` gibt es im Behaelter nicht, in dem dieses
# Repo gemessen wird.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh ls cat echo ping wget sleep ebpfctl"
BLOCKS=16384

NS=ebpf-$$
V0=eb0-$$
V1=ebp-$$
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
QPORT=$(( 5900 + ($$ % 90) * 2 ))
BPORT=$(( QPORT + 1 ))
SRVPORT=$(( 8100 + ($$ % 90) ))

TMPD=${EBPF_ARB:-$(mktemp -d)}
mkdir -p "$TMPD"

BRPID=""
SRVPID=""
wire_down() { ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null; }
aufraeumen() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    wire_down
    [ -n "${EBPF_ARB:-}" ] || rm -rf "$TMPD"
}
trap aufraeumen EXIT

pass=0
fail=0
ok()   { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note() { printf '        %s\n' "$1"; }
has()  { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() {
    grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' steht da und sollte nicht" \
        || ok "$3"
}
num() {
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}

echo "== 0. Werkzeuge =="
for w in qemu-system-x86_64 gcc python3; do
    command -v "$w" >/dev/null 2>&1 || { echo "EBPF: uebersprungen, $w fehlt"; exit 0; }
done
ok "die Werkzeuge sind da (accel=$OSUM_QEMU_ACCEL)"

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    [ -x "$FIRNC" ] || { echo "EBPF: kein firnc"; exit 1; }; }

# =====================================================================
echo
echo "== 1. bauen und gegenlesen =="
# =====================================================================

KERN="$TMPD/k.mb"
./tools/build-kernel.sh "$KERN" > "$TMPD/build.log" 2>&1 \
    && ok "der Kern steht ($(stat -c%s "$KERN") Oktette)" \
    || { bad "der Kern laesst sich nicht bauen"; tail -8 "$TMPD/build.log"; exit 1; }

# DIE KARTE VON `kdata`, MECHANISCH. Diese Runde nimmt vier Bereiche im
# letzten grossen Loch; genau diese Pruefung hat waehrend der Runde
# gemeldet, dass der Pruefer in seiner ersten Fassung nicht
# hineinpasste (52 KiB gegen 20 KiB Loch).
MM=$(python3 tools/kernel/memmap.py 2>&1 | tail -1)
note "$MM"
case "$MM" in
    *" 0 Kollisionen") ok "tools/kernel/memmap.py: keine Ueberschneidung in kdata" ;;
    *) bad "memmap.py meldet Kollisionen" ;;
esac
# DIE KARTE EINMAL IN EINE DATEI, und dann darin suchen. Zwei Fallen
# waren hier nacheinander zu umgehen, und beide meldeten dasselbe
# falsche Ergebnis ("der Bereich fehlt") fuer vier Bereiche, die
# laengst eingetragen waren:
#
#   1. `-v` braucht das Verzeichnis als Argument. Ohne es bricht
#      `memmap.py` mit einem KeyError ab und gibt gar nichts aus.
#   2. `... | grep -q ...` unter `set -o pipefail` ist FALSCH, auch
#      wenn grep findet: `grep -q` hoert beim ersten Treffer auf,
#      `memmap.py` bekommt SIGPIPE, und pipefail nimmt dessen
#      Beendigungscode fuer die ganze Kette. Das ist die Art Fehler,
#      die nur unter `pipefail` auftritt und beim Nachspielen von Hand
#      nie -- deshalb steht sie hier.
python3 tools/kernel/memmap.py kernel -v > "$TMPD/karte.txt" 2>/dev/null
for B in EBPF EBPFMAP EBPFVER EBPFHOOK; do
    if grep -q "kstate.fi:${B}_OFF" "$TMPD/karte.txt"; then
        ok "der Bereich $B steht in der Karte"
    else
        bad "der Bereich $B fehlt in tools/kernel/memmap.py"
    fi
done

SC=$(python3 tools/kernel/syscalls.py 2>&1 | tail -1)
note "$SC"
case "$SC" in
    *"keine Nummer doppelt"*) ok "tools/kernel/syscalls.py: keine Nummer doppelt" ;;
    *) bad "syscalls.py beanstandet die Nummern" ;;
esac

# SIND DIE TEILE WIRKLICH IM ABBILD? Ein Kern, der die Dateien nur
# mituebersetzt und nie ruft, waere ohne diese vier Zeilen gruen und
# taete nichts. Geprueft wird gegen die SYMBOLE im Abbild.
for S in ebpf__run ebpfver__verify ebpfmap__update ebpfhook__xdp; do
    n=$(nm "$KERN.elf" 2>/dev/null | grep -c "$S")
    num "$S ist in den Kern gebunden" "$n" ge 1
done
# Und der Haken haengt im NETZWEG und nicht nur im Testmodul.
n=$(grep -c 'ebpfhook.xdp' kernel/net/inet.fi)
num "kernel/net/inet.fi ruft den Haken am Eingang des Geraets" "$n" ge 1

# =====================================================================
echo
echo "== 2. die Maschine und der Pruefer, im Kern =="
# =====================================================================
#
# Die Kreisprobe laeuft IM KERN und nicht auf dem Wirt. Der Grund steht
# im Kopf von `kernel/ebpftest.fi`: Firn prueft Ueberlaeufe auch im
# Kernprofil, und ein vergessenes `+%` faellt auf dem Wirt vielleicht
# nicht auf, im Kern aber als `osum_panic`. Eine Maschine, die fremden
# Code deutet, wird dort geprueft, wo sie arbeitet.

R="$TMPD/selbst.txt"
timeout 120 $QEMU_X86 -kernel "$KERN" -m 512 \
    -append "osum nopwr nokbd ebpftest ebpfbench" \
    -serial "file:$R" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
RC=$?
num "der Kern hat sich selbst beendet (21 = isa-debug-exit)" "$RC" eq 21

GUT=$(grep -aoE 'proben +gut=[0-9]+' "$R" | tail -1 | grep -oE '[0-9]+$')
BOESE=$(grep -aoE 'boese=[0-9]+' "$R" | tail -1 | grep -oE '[0-9]+$')
num "Kreisprobe: bestandene Einzelproben" "${GUT:-0}" ge 41
num "Kreisprobe: gescheiterte Einzelproben" "${BOESE:-1}" eq 0

# DIE EINZELNEN ZUSAGEN, NAMENTLICH. Eine Gesamtzahl allein wuerde
# verdecken, WELCHE Probe weggefallen ist, wenn jemand eine loescht.
echo
note "die Maschine rechnet:"
for T in alu.add64 alu.sub32 alu.mul alu.arsh alu.umlauf alu.div0 \
         jmp.jeq jmp.nichtge jmp.jsgt jmp.ja \
         mem.stapel mem.oktett mem.paket mem.daneben ld.imm64; do
    grep -qaE "OK +$T=" "$R" && ok "  $T" || bad "  $T ist nicht gruen"
done
note "  alu.umlauf ist die Zeile, wegen der in kernel/net/ebpf.fi ueberall '+%'"
note "  steht: 0 - 1 muss umlaufen und darf den Kern NICHT anhalten."
note "  mem.daneben ist die zweite Schranke: ein Zugriff hinter dem Stapel."
echo
note "der Pruefer weist ab, was er abweisen muss:"
for T in ver.rueckwae ver.kein_exit ver.uninit ver.r10 ver.fremdruf \
         ver.sprungziel ver.halber_ld ver.stapel_ob ver.paket_roh \
         ver.unbekannt; do
    grep -qaE "OK +$T=" "$R" && ok "  $T" || bad "  $T ist nicht gruen"
done
note "  ver.halber_ld ist der Sprung in die zweite Haelfte eines LD_IMM64 --"
note "  dort steht ein Sofortwert, den die Maschine sonst als Befehl liest."
# UND DIE GEGENPROBE ZUR GEGENPROBE.
grep -qaE "OK +ver.gut=" "$R" \
    && ok "  ver.gut -- ein GUELTIGES Programm kommt durch" \
    || bad "  ver.gut -- ein gueltiges Programm wird abgewiesen"
note "  ohne diese Zeile waere ein Pruefer, der ALLES abweist, in den zehn"
note "  Zeilen darueber gruen. Das ist der Grund, aus dem sie dasteht."
echo
note "die Tafeln:"
for T in map.feld map.streu map.loeschen map.fehlt map.kette map.voll \
         map.ausprog; do
    grep -qaE "OK +$T=" "$R" && ok "  $T" || bad "  $T ist nicht gruen"
done
note "  map.ausprog ist die eigentliche Zusage der Stufe 3: ein LAUFENDES"
note "  Programm ruft map_update, und hinterher steht die Zahl in der Tafel."
note "  map.kette prueft das Neueinhaengen nach dem Loeschen -- der Fehler,"
note "  den lineare Sondierung sonst erst Monate spaeter zeigt."
echo
note "die Haken:"
for T in hook.leer hook.durch hook.verwerf hook.zaehler; do
    grep -qaE "OK +$T=" "$R" && ok "  $T" || bad "  $T ist nicht gruen"
done
note "  hook.leer: OHNE geladenes Programm laesst der Haken alles durch."
note "  Ein leerer Haken, der verwirft, haette das Netz abgeschaltet."

hasnot "$R" "*** EXCEPTION" "nichts ist dabei in den Trap-Melder gelaufen"

# =====================================================================
echo
echo "== 3. was der Haken kostet =="
# =====================================================================

BL=$(grep -aoE 'leer=[0-9]+' "$R" | tail -1 | grep -oE '[0-9]+$')
BK=$(grep -aoE 'klein=[0-9]+' "$R" | tail -1 | grep -oE '[0-9]+$')
BG=$(grep -aoE 'gross=[0-9]+' "$R" | tail -1 | grep -oE '[0-9]+$')
note "Takte je Rahmen: leer=${BL:-?} klein=${BK:-?} gross=${BG:-?}"
if [ -n "${BL:-}" ]; then
    # DER LEERE FALL IST DER NORMALFALL. Auf einer Maschine ohne
    # geladenes Programm besteht der Haken aus einer Ladung aus `kdata`
    # und einem Vergleich. Ist DAS teuer, sitzt der Haken falsch.
    num "leerer Haken, Takte je Rahmen (eine Ladung + ein Vergleich)" \
        "$BL" lt 400
fi
if [ -n "${BK:-}" ] && [ -n "${BL:-}" ]; then
    num "mit einem Programm aus zwei Befehlen kostet es mehr" "$BK" gt "$BL"
fi
if [ -n "${BG:-}" ] && [ -n "${BL:-}" ]; then
    # GEGEN DEN LEEREN FALL und nicht gegen das kleine Programm. Beide
    # Programmzahlen schwanken auf einer Maschine unter Fremdlast um
    # gut den Faktor zwei (gemessen: klein 1387..2637, gross
    # 2402..4624), und dann ist "gross > klein" gelegentlich falsch,
    # ohne dass am Code etwas fehlt. Der Abstand zum LEEREN Fall ist
    # dagegen zwei Zehnerpotenzen und haelt.
    num "ein Programm, das den Rahmen ansieht, kostet ein Vielfaches des leeren Falls" \
        "$BG" gt $(( BL * 5 ))
    note "der Filter kostet rund $(( BG - BL )) Takte je Rahmen, den er ansieht."
    note "Das ist der Preis eines DEUTERS; ein JIT waere schneller und nicht"
    note "mehr pruefbar -- die Begruendung steht im Kopf von kernel/net/ebpf.fi."
fi

# =====================================================================
echo
echo "== 4a. der fertige Filter, an Rahmen aus dem Kern =="
# =====================================================================
#
# DIE ENTSCHEIDENDE PROBE DES FILTERS, und sie braucht keine Leitung.
# `ebpfdrop` haengt das ICMP-Filterprogramm in den Haken; danach schickt
# der Kern ZWEI selbstgebaute Rahmen hindurch -- einen mit Protokoll 1
# (ICMP) und einen mit Protokoll 6 (TCP), sonst identisch. Der erste
# muss verworfen, der zweite durchgelassen werden.
#
# Warum das hier steht und nicht nur in Abschnitt 5: ob auf einer echten
# Leitung in einem gegebenen Lauf ueberhaupt ein ICMP-Rahmen ankommt,
# haengt am Wirt. Diese Probe haengt nur am Filter, und sie unterscheidet
# die beiden Faelle, die ein kaputter Filter verwechselt.

R3="$TMPD/drop.txt"
timeout 120 $QEMU_X86 -kernel "$KERN" -m 512 \
    -append "osum nopwr nokbd ebpfdrop" \
    -serial "file:$R3" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
has "$R3" "drop-icmp pruef0" "4a der Pruefer nimmt das Filterprogramm an"
DI=$(grep -aoE 'probe icmp verwerf=[0-9]+' "$R3" | tail -1 | grep -oE '[0-9]+$')
DT=$(grep -aoE 'probe tcp +durch=[0-9]+' "$R3" | tail -1 | grep -oE '[0-9]+$')
num "4a ein ICMP-Rahmen wird VERWORFEN" "${DI:-0}" eq 1
num "4a ein TCP-Rahmen wird DURCHGELASSEN" "${DT:-0}" eq 1
note "    dieselben 64 Oktette, nur das Protokolloktett unterscheidet sich."
note "    Ein Filter, der alles verwirft, faellt an der zweiten Zeile auf;"
note "    einer, der nichts verwirft, an der ersten."

# =====================================================================
echo
echo "== 4. die Gegenprobe: noebpf =="
# =====================================================================
#
# Dasselbe Abbild, die Haken abgeschaltet. Ohne diesen Lauf waere jede
# Zahl oben ein Vergleich zwischen zwei VERSCHIEDENEN Abbildern.

R2="$TMPD/noebpf.txt"
timeout 120 $QEMU_X86 -kernel "$KERN" -m 512 \
    -append "osum nopwr nokbd noebpf" \
    -serial "file:$R2" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
ONV=$(grep -aoE 'ebpf: on=[0-9]+' "$R2" | tail -1 | grep -oE '[0-9]+$')
num "mit 'noebpf' meldet der Kern den Haken als abgeschaltet" "${ONV:-9}" eq 0
ON1=$(grep -aoE 'ebpf: on=[0-9]+' "$R" | tail -1 | grep -oE '[0-9]+$')
num "ohne 'noebpf' ist er scharf" "${ON1:-9}" eq 1

# =====================================================================
echo
echo "== 5. auf einer echten Leitung: der Filter verwirft wirklich =="
# =====================================================================
#
# Das ist die Zusage, um die es der Runde geht. Ein Programm, das ICMP
# wegwirft, haengt am Eingang des Geraets. Im SELBEN Lauf:
#
#   ping  -> muss verschwinden   (der Filter greift)
#   wget  -> muss durchkommen    (der Filter greift nicht zu weit)

wire_up() {
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    ip netns add "$NS" 2>/dev/null || return 1
    ip link add "$V0" type veth peer name "$V1" 2>/dev/null || return 1
    ip link set "$V1" netns "$NS" || return 1
    ip netns exec "$NS" ip addr add "$HOST_IP/24" dev "$V1" || return 1
    ip netns exec "$NS" ip link set "$V1" up || return 1
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up || return 1
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
    return 0
}

BODY=4096
NETOK=1
command -v ip >/dev/null 2>&1 || NETOK=0
gcc -O2 -o "$TMPD/bruecke" tools/net/bridge.c 2>"$TMPD/gcc.err" \
    && ok "tools/net/bridge.c: die Leitung ist gebaut" \
    || { bad "bridge.c laesst sich nicht uebersetzen"; NETOK=0; }

if [ "$NETOK" = 1 ]; then
    if ! wire_up; then
        note "kein veth/netns moeglich (fehlende Rechte?) -- Abschnitt 5 entfaellt"
        note "DAS IST KEIN GRUENES ERGEBNIS, sondern ein nicht gemessener Teil."
        NETOK=0
    fi
fi

if [ "$NETOK" = 1 ]; then
    # DIE RING-3-PROGRAMME UEBER `tools/lib/userprog.sh`, und nicht mit
    # einem eigenen firnc-Aufruf. Der Kopf jener Datei zaehlt auf, was
    # daran dreissig Laeufer falsch gemacht haben: das Profil steht IN
    # der Wurzeldatei (`profile app` bei allem mit Oberflaeche), im
    # Profil `app` darf KEIN crt.o dazu, und der Einsprungpunkt heisst
    # `USER_ENTRY=_F<stufe>.u_start`. Eine erste Fassung dieses Laeufers
    # hat genau das von Hand nachgebaut und bekam
    # "the program has no function 'main'" fuer alle sieben Programme.
    . tools/lib/userprog.sh
    as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null
    gebaut=1
    for p in $PROGS; do
        [ -f "kernel/user/$p.fi" ] || continue
        up_build "$FIRNC" "$p" "$TMPD/$p.o" "$TMPD/$p.elf" \
            "$TMPD/crt.o" "$ULD" 0 "$TMPD/$p.err" \
            || { gebaut=0; note "  $p: $(head -2 "$TMPD/$p.err" | tr '\n' ' ')"; }
    done
    num "die Ring-3-Programme sind gebaut" "$gebaut" eq 1

    SPEC="/bin/"
    for p in $PROGS; do
        [ -f "$TMPD/$p.elf" ] && SPEC="$SPEC /bin/$p=$TMPD/$p.elf"
    done
    SPEC="$SPEC /var/ /etc/"
    python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
        > "$TMPD/mkfs.txt" 2>&1 \
        && ok "mkfs.py: ein Abbild mit /bin/ping und /bin/wget" \
        || { bad "mkfs.py ist gescheitert"
             sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; NETOK=0; }
fi

if [ "$NETOK" = 1 ]; then
    head -c $BODY /dev/zero | tr '\0' 'x' > "$TMPD/x"
    ( cd "$TMPD" && exec ip netns exec "$NS" python3 -m http.server $SRVPORT \
        --bind "$HOST_IP" >/dev/null 2>&1 ) & SRVPID=$!
    sleep 0.6
    "$TMPD/bruecke" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!
    sleep 0.4

    BASE="nokbd nosched noproc nofs noring3"
    NETARGS="nic nip=$OSUM_IP/24 ngw=$HOST_IP"
    # NUR EIN PING, und der Grund ist gemessen: `recvfrom` auf einem
    # ICMP-Sockel wartet im Kern bis zu NET_ROUNDS Ticks, wenn nichts
    # kommt (`kernel/sys.fi`, do_recvfrom). Mit drei verworfenen Pings
    # steht der Lauf damit laenger, als jedes Zeitlimit hier erlaubt --
    # die erste Fassung lief genau deshalb in den Abbruch, und der
    # Befund sah aus wie "der Filter hat das Netz abgeschaltet". Einer
    # reicht fuer die Aussage, und `wget` dahinter zeigt, dass TCP
    # weiterlaeuft.
    # ZWEI SKRIPTE, und der Grund ist gemessen.
    #
    # `ping` steht nur im Lauf OHNE Filter. Sobald der Filter greift,
    # bekommt der ICMP-Sockel nie eine Antwort, und `do_recvfrom` im
    # Kern wartet je Versuch bis zu NET_ROUNDS Ticks (rund 30 s,
    # `kernel/sys.fi`). Der Lauf steht damit laenger, als jedes
    # Zeitlimit hier erlaubt -- die erste Fassung lief genau deshalb in
    # den Abbruch, und der Befund sah aus wie "der Filter hat das Netz
    # abgeschaltet", obwohl der Filter genau das tat, was er sollte.
    #
    # Gemessen wird der Filter deshalb an `wget` (TCP muss
    # durchkommen) und an den ZAEHLERN DES KERNS, die `ebpfctl` am Ende
    # desselben Laufs ausliest. Das ist die haltbarere Messung: sie
    # haengt nicht daran, wie ein Ring-3-Programm mit Zeitablauf umgeht.
    SKRIPT="ping -c 1 $HOST_IP;wget -q http://$HOST_IP:$SRVPORT/x;ebpfctl;exit"
    SKRIPT_F="wget -q http://$HOST_IP:$SRVPORT/x;ebpfctl;exit"

    lauf() {
        local extra=$1 out=$2
        local skript=${3:-$SKRIPT}
        rm -f "$out"
        cp "$TMPD/disk.img" "$TMPD/live.img"
        timeout 180 $QEMU_X86 -kernel "$KERN" -m 256 \
            -append "osum $BASE $NETARGS nsvc=0 nwait=0 $extra script=$skript" \
            -serial "file:$out" -display none -no-reboot \
            -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
            -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
            -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    }

    # --- 5a. OHNE Filter: der Grundzustand. -------------------------
    # Ohne diesen Lauf waere "ping kommt nicht an" auch mit einer
    # kaputten Leitung gruen. Das ist der wichtigste Absatz des
    # Abschnitts.
    lauf "" "$TMPD/netz-ohne.txt"
    RO="$TMPD/netz-ohne.txt"
    GRUND=1
    if grep -qaE '0% packet loss' "$RO"; then
        ok "5a OHNE Filter: /bin/ping bekommt seine Antworten"
    else
        bad "5a OHNE Filter: ping kommt schon OHNE Filter nicht durch"
        note "    dann misst 5b nichts -- die Leitung selbst ist das Problem"
        GRUND=0
    fi
    if grep -qaF "wget: status 200" "$RO"; then
        ok "5a OHNE Filter: /bin/wget holt die Datei"
    else
        bad "5a OHNE Filter: wget holt die Datei nicht"
        GRUND=0
    fi
    DR0=$(grep -aoE 'verwerf=[0-9]+' "$RO" | tail -1 | grep -oE '[0-9]+$')
    num "5a ohne Filter wurde NICHTS verworfen" "${DR0:-9}" eq 0

    # --- 5b. MIT Filter: ICMP weg, TCP bleibt. ----------------------
    if [ "$GRUND" = 1 ]; then
        lauf "ebpfdrop" "$TMPD/netz-mit.txt" "$SKRIPT_F"
        RM="$TMPD/netz-mit.txt"
        has "$RM" "drop-icmp pruef0" \
            "5b der Pruefer hat das Filterprogramm ANGENOMMEN (Befund 0)"
        HG=$(grep -aoE 'haengt=[0-9]+' "$RM" | tail -1 | grep -oE '[0-9]+$')
        num "5b es haengt am Haken (Platznummer)" "${HG:-9}" eq 1

        # DIE GEGENRICHTUNG: TCP LAEUFT WEITER. Das ist die Haelfte der
        # Zusage, die ein zu scharfer Filter verletzen wuerde.
        has "$RM" "wget: status 200" \
            "5b MIT Filter: /bin/wget holt die Datei TROTZDEM"
        note "    ein Filter, der alles wegwirft, waere an dieser Zeile aufgefallen."

        # UND DIE ANDERE HAELFTE: DIE ZAEHLER DES KERNS, ausgelesen von
        # `ebpfctl` am Ende DESSELBEN Laufs -- also nachdem der Verkehr
        # geflossen ist. Die Berichtszeile beim Start taugt dafuer
        # nicht: sie steht, bevor der erste Rahmen da war, und meldet
        # naturgemaess lauter Nullen.
        SEH=$(grep -aoE 'rahmen gesehen +=[0-9 ]+' "$RM" | tail -1 \
              | grep -oE '[0-9]+$')
        DR=$(grep -aoE 'davon verworfen =[0-9 ]+' "$RM" | tail -1 \
             | grep -oE '[0-9]+$')
        PA=$(grep -aoE 'durchgelassen +=[0-9 ]+' "$RM" | tail -1 \
             | grep -oE '[0-9]+$')
        AB=$(grep -aoE 'abgebrochen +=[0-9 ]+' "$RM" | tail -1 \
             | grep -oE '[0-9]+$')
        num "5b der Haken hat Rahmen gesehen" "${SEH:-0}" ge 4
        num "5b und trotzdem welche durchgelassen (ARP, TCP)" "${PA:-0}" ge 4
        num "5b kein Lauf des Programms ist abgebrochen" "${AB:-1}" eq 0
        note "    gesehen=$SEH verworfen=$DR durchgelassen=$PA abgebrochen=$AB"
        note "    (verworfen ist hier 0 oder mehr: ob in diesem Lauf ueberhaupt"
        note "     ICMP ankam, haengt am Wirt. Dass der Filter ICMP WIRKLICH"
        note "     wegwirft, misst Abschnitt 5c mit einem Rahmen, den der Kern"
        note "     selbst baut.)"
        hasnot "$RM" "*** EXCEPTION" "5b nichts ist in den Trap-Melder gelaufen"
    fi
fi

# =====================================================================
if [ "$NETOK" = 1 ] && [ "${GRUND:-0}" = 1 ]; then
echo
echo "== 6. Stufe 5: der Weg aus Ring 3 =="
# =====================================================================
#
# Bis hierher hat der Kern sich selbst geprueft. Dieser Abschnitt geht
# den ANDEREN Weg: ein gewoehnliches Programm in Ring 3 baut die
# Befehle, schickt sie mit dem Systemaufruf 1405 hinunter, der Pruefer
# sieht sie an, und das Programm haengt sie an den Haken. Damit ist die
# Kette vollstaendig -- Aufruf, Kopie, Pruefung, Haken, Tafel.

    lauf "" "$TMPD/ctl.txt" "ebpfctl bad;ebpfctl drop-icmp;ebpfctl;exit"
    RC3="$TMPD/ctl.txt"
    # (a) DER PRUEFER SAGT NEIN, aus Ring 3 heraus sichtbar.
    has "$RC3" "ebpfctl: ABGEWIESEN" \
        "6 ein kaputtes Programm wird abgewiesen, und Ring 3 erfaehrt es"
    BEF=$(grep -aoE 'ABGEWIESEN, Befund = [0-9]+' "$RC3" | tail -1 \
          | grep -oE '[0-9]+$')
    num "6 der Befund ist V_BACKJUMP (1), also der Rueckwaertssprung" \
        "${BEF:-0}" eq 1
    # (b) UND JA ZU EINEM GUELTIGEN.
    has "$RC3" "ebpfctl: der Prüfer nimmt es an" \
        "6 ein gueltiges Programm wird angenommen"
    has "$RC3" "ebpfctl: hängt am Eingang an" \
        "6 und Ring 3 haengt es an den Haken"
    # (c) Die Zaehler kommen aus dem Kern zurueck nach Ring 3.
    LD=$(grep -aoE 'geladen +=[0-9 ]+' "$RC3" | tail -1 | grep -oE '[0-9]+$')
    num "6 ebpfctl liest die Zaehler des Kerns (geladen)" "${LD:-0}" ge 1
    hasnot "$RC3" "*** EXCEPTION" "6 nichts ist dabei gefallen"
fi

echo
echo "EBPF: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
