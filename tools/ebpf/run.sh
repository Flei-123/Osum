#!/usr/bin/env bash
#
#   bash tools/ebpf/run.sh
#
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

MM=$(python3 tools/kernel/memmap.py 2>&1 | tail -1)
note "$MM"
case "$MM" in
    *" 0 Kollisionen") ok "tools/kernel/memmap.py: keine Ueberschneidung in kdata" ;;
    *) bad "memmap.py meldet Kollisionen" ;;
esac
#
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

for S in ebpf__run ebpfver__verify ebpfmap__update ebpfhook__xdp; do
    n=$(nm "$KERN.elf" 2>/dev/null | grep -c "$S")
    num "$S ist in den Kern gebunden" "$n" ge 1
done
n=$(grep -c 'ebpfhook.xdp' kernel/net/inet.fi)
num "kernel/net/inet.fi ruft den Haken am Eingang des Geraets" "$n" ge 1

# =====================================================================
echo
echo "== 2. die Maschine und der Pruefer, im Kern =="
# =====================================================================
#

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
    num "leerer Haken, Takte je Rahmen (eine Ladung + ein Vergleich)" \
        "$BL" lt 400
fi
if [ -n "${BK:-}" ] && [ -n "${BL:-}" ]; then
    num "mit einem Programm aus zwei Befehlen kostet es mehr" "$BK" gt "$BL"
fi
if [ -n "${BG:-}" ] && [ -n "${BL:-}" ]; then
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
    #
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

    if [ "$GRUND" = 1 ]; then
        lauf "ebpfdrop" "$TMPD/netz-mit.txt" "$SKRIPT_F"
        RM="$TMPD/netz-mit.txt"
        has "$RM" "drop-icmp pruef0" \
            "5b der Pruefer hat das Filterprogramm ANGENOMMEN (Befund 0)"
        HG=$(grep -aoE 'haengt=[0-9]+' "$RM" | tail -1 | grep -oE '[0-9]+$')
        num "5b es haengt am Haken (Platznummer)" "${HG:-9}" eq 1

        has "$RM" "wget: status 200" \
            "5b MIT Filter: /bin/wget holt die Datei TROTZDEM"
        note "    ein Filter, der alles wegwirft, waere an dieser Zeile aufgefallen."

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

    lauf "" "$TMPD/ctl.txt" "ebpfctl bad;ebpfctl drop-icmp;ebpfctl;exit"
    RC3="$TMPD/ctl.txt"
    has "$RC3" "ebpfctl: ABGEWIESEN" \
        "6 ein kaputtes Programm wird abgewiesen, und Ring 3 erfaehrt es"
    BEF=$(grep -aoE 'ABGEWIESEN, Befund = [0-9]+' "$RC3" | tail -1 \
          | grep -oE '[0-9]+$')
    num "6 der Befund ist V_BACKJUMP (1), also der Rueckwaertssprung" \
        "${BEF:-0}" eq 1
    has "$RC3" "ebpfctl: der Prüfer nimmt es an" \
        "6 ein gueltiges Programm wird angenommen"
    has "$RC3" "ebpfctl: hängt am Eingang an" \
        "6 und Ring 3 haengt es an den Haken"
    LD=$(grep -aoE 'geladen +=[0-9 ]+' "$RC3" | tail -1 | grep -oE '[0-9]+$')
    num "6 ebpfctl liest die Zaehler des Kerns (geladen)" "${LD:-0}" ge 1
    hasnot "$RC3" "*** EXCEPTION" "6 nichts ist dabei gefallen"
fi

echo
echo "EBPF: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
