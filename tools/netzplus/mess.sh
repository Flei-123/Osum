#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/netzplus/mess.sh -- DER PRUEFSTAND DER RUNDE NETZPLUS.
#
# Wird von tools/netzplus/run.sh eingebunden (`. tools/netzplus/mess.sh`)
# und enthaelt NUR die Mechanik: Draht, Bruecke, QEMU, Bauen. Die
# Zusagen stehen im Laeufer daneben, damit man sie an einer Stelle liest.
#
# Die Bauart ist die von tools/net/run.sh (Runde K8) und bewusst keine
# neue: dort ist gemessen und aufgeschrieben, warum es eine veth-Strecke
# mit AF_PACKET-Bruecke ist und kein TAP (/dev/net/tun gibt es in diesem
# Behaelter nicht) und warum die Pruefsummenauslagerung auf beiden Enden
# aus muss (CHECKSUM_PARTIAL ueber veth -- ein Stack, der die Pruefsumme
# PRUEFT, wirft solche Rahmen zu Recht weg).
#
#   Osum in QEMU <--virtio-net--> QEMU <--UDP auf loopback-->
#   tools/net/bridge <--AF_PACKET--> veth V0 | V1 <--> Linux im
#   Namensraum NS, 10.9.0.1/24; Osum ist 10.9.0.2/24
#
# WAS DIESE RUNDE ANDERS MISST ALS K8: dort war der Draht schnell und
# ohne Verzoegerung. Fensterskalierung zeigt sich aber ERST, wenn das
# Bandbreiten-Verzoegerungs-Produkt groesser ist als das Fenster --
# ueber loopback ist die Laufzeit ~0, und dann ist ein 64-KiB-Fenster
# nie die Grenze. Deshalb steht hier `delay` im Vordergrund.
set -uo pipefail

# --- Namen haengen an der Prozessnummer (Lehre aus Runde K12: mehrere
# Arbeitsbaeume messen gleichzeitig und reissen einander sonst den
# Namensraum weg).
NS=nzp-$$
V0=nz0-$$
V1=v1
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
# DIE ZWEI ANSCHLUESSE, UND WARUM SIE UNTEN LIEGEN MUESSEN.
#
# Das war der Fehler, der diese Runde eine knappe Stunde gekostet hat.
# Erst standen sie bei 20000 + PID % 20000 -- und damit mitten im
# FLUECHTIGEN BEREICH, den Linux selbst vergibt
# (/proc/sys/net/ipv4/ip_local_port_range, hier 32768-60999). Der Kern
# hatte den Anschluss dann laengst an einen anderen Prozess gegeben,
# bevor QEMU ihn binden konnte.
#
# WIE ES SICH ZEIGTE, und warum es so schwer zu sehen war: die Bruecke
# meldete `to_qemu=9`, der Kern meldete `rx_f=0`. Beide Seiten arbeiteten
# also fehlerfrei -- die Rahmen gingen nur an einen Anschluss, an dem
# niemand mehr lauschte. Kein Fehler, keine Meldung, nur eine Messung,
# die nichts misst. `ping` bekam 100 % Verlust, und der erste Verdacht
# fiel auf den eigenen Stack, der nachweislich in Ordnung war.
#
# Jetzt derselbe Bereich, den tools/net/run.sh seit Runde K12 benutzt:
# unterhalb von 32768, gerade Zahl fuer QEMU, ungerade fuer die Bruecke.
QPORT=$(( 5000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))

# DIE BEFEHLSZEILE, und warum sie NICHT der volle Kern ist.
#
# `tools/net/run.sh` startet den Kern mit `nokbd nosched noproc nofs
# noring3` -- ohne Tastatur, ohne Aufgabenprobe, ohne Dateisystemprobe,
# ohne Ring-3-Probe. Diese Runde hat erst mit `osum nopwr` gemessen, also
# dem VOLLEN Startlauf, und dabei GEMESSEN, was das kostet: der Kern
# steht dann so lange in den Selbstproben, dass `nc` auf der anderen
# Seite den Verbindungsversuch laengst aufgegeben hat -- `listening=7`
# steht da, `accepted=0` daneben, und keine einzige Zahl kommt heraus.
#
# Gemessen wird der Netzstapel, nicht der Startlauf. Also dieselbe
# Befehlszeile wie in K8.
NZP_BASE=${NZP_BASE:-"nokbd nosched noproc nofs noring3"}

BRPID=""
QPID=""

# ---------------------------------------------------------------- Draht
# wire_up [Verlust Richtung Osum] [Verlust Richtung Linux] [Verzoegerung]
#
# Zwei getrennte qdiscs mit Absicht: netem sitzt am AUSGANG. Verlust auf
# V1 (im Namensraum) ist das, was Linux sendet und Osum neu zusammensetzen
# muss; Verlust auf V0 ist das, was Osum sendet und OSUM SELBST neu
# uebertragen muss.
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
    # Die Warteschlange muss tief genug sein: ein Fenster von 256 KiB bei
    # 1460 Oktetten sind ~180 Rahmen unterwegs. netem nimmt ohne `limit`
    # 1000; das wird hier hingeschrieben, damit ein spaeter groesserer
    # Puffer nicht still an der Warteschlange verhungert und das dann als
    # "Fensterskalierung bringt nichts" gemessen wird.
    local lim=10000
    if [ -n "${1:-}" ] || [ -n "${3:-}" ]; then
        ip netns exec "$NS" tc qdisc add dev "$V1" root netem limit $lim \
            ${1:+loss $1} ${3:+delay $3} >/dev/null 2>&1
    fi
    if [ -n "${2:-}" ] || [ -n "${3:-}" ]; then
        tc qdisc add dev "$V0" root netem limit $lim \
            ${2:+loss $2} ${3:+delay $3} >/dev/null 2>&1
    fi
}

wire_down() {
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
}

bridge_up() {
    "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" &
    BRPID=$!
    sleep 0.4
}

bridge_down() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    wait "$BRPID" 2>/dev/null
    BRPID=""
    sleep 0.2
}

# qemu_bg <Abbild> <append> <Ausgabe> [weitere Argumente...]
qemu_bg() {
    local image=$1 append=$2 out=$3
    shift 3
    rm -f "$out" "$out.rc"
    ( timeout "${NZP_TIMEOUT:-180}" $QEMU_X86 -kernel "$image" -m 256 -append "$append" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$out.rc" ) &
    QPID=$!
}

qemu_wait() {
    wait "$QPID" 2>/dev/null
    QPID=""
}

await_line() { # Datei Text Sekunden
    local i
    for i in $(seq 1 $(( ${3:-20} * 5 ))); do
        [ -f "$1" ] && grep -qaF "$2" "$1" && return 0
        sleep 0.2
    done
    return 1
}

# Liest `nic: <name>=<zahl>` aus der seriellen Ausgabe.
val() { sed -n "s/^nic: $2=\([0-9-]*\).*/\1/p" "$1" 2>/dev/null | tail -1; }

# ---------------------------------------------------------------- Bauen
# Baut Kernel + Userland mit firnc0 nach $TMPD/k0.mb.
nzp_build() {
    local f
    for f in boot isr switch smp hv; do
        as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" || return 1
    done
    as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || return 1
    "$FIRNC" kernel/kmain.fi -o "$TMPD/k0.o" >"$TMPD/e0" 2>&1 || {
        echo "--- firnc kmain.fi:" >&2; head -20 "$TMPD/e0" >&2; return 1; }
    "$FIRNC" kernel/uprog.fi -o "$TMPD/u0.o" >>"$TMPD/e0" 2>&1 || {
        echo "--- firnc uprog.fi:" >&2; head -20 "$TMPD/e0" >&2; return 1; }
    ld -n -T "$LDSCRIPT" \
        --defsym=KERNEL_MAIN="_F0.kernel_main" \
        --defsym=KERNEL_TRAP="_F0.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F0.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F0.tasks__main" \
        --defsym=KERNEL_USER_START="_F0.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F0.smp__ap_main" \
        --defsym=USER_MAIN="_F0.u_enter" \
        -o "$TMPD/k0.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
        "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k0.o" "$TMPD/u0.o" 2>"$TMPD/ld0.err" || {
        echo "--- ld:" >&2; head -10 "$TMPD/ld0.err" >&2; return 1; }
    objcopy -O elf32-i386 "$TMPD/k0.elf" "$TMPD/k0.mb" 2>/dev/null || return 1
    gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>"$TMPD/gcc.err" || return 1
    return 0
}

# ------------------------------------------------- eine Durchsatzmessung
# durchsatz <Ausgabedatei> <Bytes> <Verzoegerung|""> <Verlust v1|""> <Verlust v0|"">
#
# Linux -> Osum (nsvc=1, "sink"): der Wirt schiebt mit `nc`, Osum
# schluckt und rechnet selbst Oktette/Mikrosekunden aus. Der Wert, der
# zaehlt, ist `kib_per_s` AUS OSUM -- nicht die Zeit, die die Shell
# stoppt; die enthaelt Aufbau und Abbau der Verbindung.
durchsatz() {
    local out=$1 bytes=$2 delay=${3:-} l1=${4:-} l0=${5:-} extra=${6:-}
    dd if=/dev/urandom of="$TMPD/payload.bin" bs=1024 count=$((bytes/1024)) 2>/dev/null
    wire_up "$l1" "$l0" "$delay"
    bridge_up
    qemu_bg "$TMPD/k0.mb" \
        "$NZP_BASE nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=1 nport=7 nbytes=$bytes $extra" "$out"
    if await_line "$out" "nic: listening=7" 40; then
        ip netns exec "$NS" timeout "${NZP_NC_TIMEOUT:-120}" nc -q 1 "$OSUM_IP" 7 \
            < "$TMPD/payload.bin" >/dev/null 2>&1
    fi
    qemu_wait
    bridge_down
    wire_down
}
