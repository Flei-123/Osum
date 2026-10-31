#!/usr/bin/env bash
#
#   bash tools/netzui/durchsatz.sh
#
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo wget netmeter sleep"
BLOCKS=16384

NS=nzui-$$
V0=nz0-$$
V1=nzp-$$
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
QPORT=$(( 5600 + ($$ % 90) * 2 ))
BPORT=$(( QPORT + 1 ))
TMPD=$(mktemp -d)
BRPID=""; QPID=""; SRVPID=""

cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$QPID" ]  && kill "$QPID" 2>/dev/null
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { echo "  ok   $*"; pass=$((pass+1)); }
bad() { echo "  FAIL $*"; fail=$((fail+1)); }
note(){ echo "       $*"; }
num() { # text wert op soll
    local t=$1 v=$2 op=$3 s=$4
    if [ -z "$v" ]; then bad "$t: keine Zahl gefunden"; return; fi
    if [ "$v" -"$op" "$s" ] 2>/dev/null; then ok "$t: $v"; else bad "$t: $v (erwartet $op $s)"; fi
}

for t in qemu-system-x86_64 ip gcc python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "NETZUI-DURCHSATZ: uebersprungen, $t fehlt"; exit 0; }
done
ip netns del "$NS" 2>/dev/null
if ! ip netns add "$NS" 2>/dev/null; then
    echo "NETZUI-DURCHSATZ: uebersprungen, Netzraeume gehen hier nicht"
    exit 0
fi
ip netns del "$NS" 2>/dev/null

echo "== 1. bauen =="
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>/dev/null \
        || bad "$f.s assembliert nicht"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"

"$FIRNC" kernel/kmain.fi -o "$TMPD/k0.o" >"$TMPD/e0" 2>&1 \
    || { bad "der Kern uebersetzt nicht"; sed 's/^/        /' "$TMPD/e0" | head -10; \
         echo "NETZUI-DURCHSATZ: $pass passed, $((fail)) failed"; exit 1; }
"$FIRNC" kernel/uprog.fi -o "$TMPD/u0.o" >>"$TMPD/e0" 2>&1 || bad "uprog.fi"
ld -n -T "$LDSCRIPT" \
    --defsym=KERNEL_MAIN="_F0.kernel_main" \
    --defsym=KERNEL_TRAP="_F0.trap__entry" \
    --defsym=KERNEL_SYSCALL="_F0.sys__entry" \
    --defsym=KERNEL_TASK_MAIN="_F0.tasks__main" \
    --defsym=KERNEL_USER_START="_F0.proc__user_start" \
    --defsym=KERNEL_AP_MAIN="_F0.smp__ap_main" \
    --defsym=USER_MAIN="_F0.u_enter" \
    -o "$TMPD/k0.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
    "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k0.o" "$TMPD/u0.o" 2>"$TMPD/ld.err" \
    || { bad "ld scheitert am Kern"; sed 's/^/        /' "$TMPD/ld.err" | head -5; }
objcopy -O elf32-i386 "$TMPD/k0.elf" "$TMPD/k0.mb" 2>/dev/null
[ -s "$TMPD/k0.mb" ] && ok "der Kern ist gebaut ($(stat -c%s "$TMPD/k0.mb") Oktette)" \
    || { bad "kein Kernabbild"; echo "NETZUI-DURCHSATZ: $pass passed, $fail failed"; exit 1; }

for p in $PROGS; do
    UPROF=""; UCRT="$TMPD/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    "$FIRNC" $UPROF -c "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$p.fi uebersetzt nicht"; sed 's/^/        /' "$TMPD/e$p" | head -6; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" $UCRT "$TMPD/$p.o" 2>/dev/null \
        || { bad "ld scheitert an $p"; continue; }
    strip --strip-all "$TMPD/$p.elf"
done
[ -s "$TMPD/netmeter.elf" ] && ok "/bin/netmeter ist gebaut" || bad "/bin/netmeter fehlt"

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
SPEC="$SPEC /var/ /var/net/ /etc/"
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
    > "$TMPD/mkfs.txt" 2>&1 && ok "ein Abbild mit /bin/netmeter" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

gcc -O2 -o "$TMPD/bruecke" tools/net/bridge.c 2>"$TMPD/gcc.err" \
    && ok "die Bruecke zum Draht ist gebaut" \
    || bad "tools/net/bridge.c uebersetzt nicht"

# --------------------------------------------------------------- Draht
wire_up() {
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
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
wire_down(){ ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null; }
bridge_up(){ "$TMPD/bruecke" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!; sleep 0.4; }
bridge_down(){ [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; wait "$BRPID" 2>/dev/null; BRPID=""; sleep 0.2; }

BODY=1048576
cat > "$TMPD/httpsrv.py" <<'PY'
import http.server, socketserver, sys, time
N = int(sys.argv[2])
BODY = (b"0123456789abcdef" * ((N // 16) + 1))[:N]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        # /langsam TROEPFELT: derselbe Inhalt, aber ueber rund fuenf
        # Sekunden verteilt. Das ist der Lauf, in dem die MESSUNG und der
        # DOWNLOAD gleichzeitig laufen -- und damit der einzige, in dem
        # sich zeigen laesst, dass die Rate waehrend der Last steigt und
        # danach faellt. Bei voller Geschwindigkeit ist ein Megaoktett
        # ueber diesen Draht in unter einer Sekunde durch und faellt
        # komplett in eine einzige Messzeile.
        if self.path.endswith("langsam"):
            stueck = len(BODY) // 10
            for i in range(10):
                self.wfile.write(BODY[i * stueck:(i + 1) * stueck])
                self.wfile.flush()
                time.sleep(0.5)
        else:
            self.wfile.write(BODY)
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
class T(socketserver.ThreadingTCPServer):
    daemon_threads = True
with T(("0.0.0.0", int(sys.argv[1])), H) as s:
    s.serve_forever()
PY
srv_up(){ ip netns exec "$NS" python3 "$TMPD/httpsrv.py" 8000 "$BODY" > "$TMPD/httpd.log" 2>&1 & SRVPID=$!; sleep 1; }
srv_down(){ [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; SRVPID=""; }

qemu_bg() {
    local append=$1 out=$2
    rm -f "$out"
    ( timeout 180 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 -append "$append" \
        -serial "file:$out" -display none -no-reboot \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cd" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$out.rc" ) &
    QPID=$!
}

BASE="nokbd nosched noproc nofs noring3"
NETARGS="nic nip=$OSUM_IP/24 ngw=$HOST_IP"

# =====================================================================
echo "== 2. die Zaehler unter echter Last =="
wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live.img"
#
qemu_bg "osum $BASE $NETARGS nsvc=0 nwait=0 script=netmeter 6;exit" \
    "$TMPD/ruhe.txt"
wait "$QPID" 2>/dev/null; QPID=""
srv_down; bridge_down; wire_down

wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live.img"
qemu_bg "osum $BASE $NETARGS nsvc=0 nwait=0 script=wget -q http://$HOST_IP:8000/x;netmeter 6;exit" \
    "$TMPD/lauf.txt"
wait "$QPID" 2>/dev/null; QPID=""
srv_down; bridge_down; wire_down

R="$TMPD/lauf.txt"
if [ ! -s "$R" ]; then
    bad "die Maschine hat nichts auf die serielle Leitung geschrieben"
    echo "NETZUI-DURCHSATZ: $pass passed, $fail failed"; exit 1
fi
Q="$TMPD/ruhe.txt"
echo "-- LAUF A (Ruhe), /bin/netmeter --"
grep -a '^netmeter:' "$Q" | sed 's/^/       /'
echo "-- LAUF B (nach dem Download), /bin/netmeter --"
grep -a '^netmeter:' "$R" | sed 's/^/       /'

nA=$(grep -ac '^netmeter: t=' "$Q")
nB=$(grep -ac '^netmeter: t=' "$R")
num "Messzeilen in Lauf A" "$nA" ge 5
num "Messzeilen in Lauf B" "$nB" ge 5

maxruhe=$(grep -a '^netmeter: done' "$Q" | grep -aoE 'maxr=[0-9]+' | cut -d= -f2)
num "Zusage 1 -- Spitzenrate im RUHELAUF" "${maxruhe:-}" lt 20000
drxruhe=$(grep -a '^netmeter: done' "$Q" | grep -aoE 'drx=[0-9]+' | cut -d= -f2)
num "Zusage 1b -- empfangene Oktette im Ruhelauf" "${drxruhe:-}" lt 20000

rxB=$(grep -a '^netmeter: t=0 ' "$R" | grep -aoE ' rx=[0-9]+' | tr -d ' ' | cut -d= -f2)
untergrenze=$(( BODY * 90 / 100 ))
obergrenze=$(( BODY * 3 / 2 ))
num "Zusage 4 -- die Karte hat mindestens 90% der Datei gezaehlt" "${rxB:-}" ge "$untergrenze"
num "Zusage 4b -- und nicht unsinnig mehr (Rahmenkoepfe)" "${rxB:-}" le "$obergrenze"
if [ -n "${rxB:-}" ]; then
    note "Datei $BODY Oktette, von der Karte gezaehlt $rxB"
    note "($(( rxB * 100 / BODY ))%) -- der Aufschlag sind Ethernet-, IP-"
    note "und TCP-Koepfe sowie die Bestaetigungen (netmon.fi: Draht != Nutzlast)."
fi

maxlast=$(grep -a '^netmeter: done' "$R" | grep -aoE 'maxr=[0-9]+' | cut -d= -f2)
if [ -n "${maxlast:-}" ] && [ "${maxlast:-0}" -gt 20000 ]; then
    ok "Zusage 2 -- Spitzenrate unter Last: $maxlast Oktette/s"
    if [ "${maxruhe:-0}" -lt 100 ]; then rv=$maxlast; else rv=$(( maxlast / (maxruhe + 1) )); fi
    num "Zusage 2b -- Spitze zu Ruhe" "$rv" gt 10
else
    note "Zusage 2 -- keine Spitze in Lauf B (der Download war vor der"
    note "ersten Messsekunde fertig). Die bewegten Oktette stehen oben;"
    note "dass die RATE daraus richtig gebildet wird, misst"
    note "tools/netzui/run.sh an festen Zahlen."
fi

# ZUSAGE 3 -- DANACH FAELLT SIE WIEDER.
letzte=$(grep -a '^netmeter: t=' "$R" | tail -1 | grep -aoE 'rrx=[0-9]+' | cut -d= -f2)
num "Zusage 3 -- am Ende von Lauf B wieder in Ruhe" "${letzte:-}" lt 20000

# =====================================================================
echo "== 2c. die Rate WAEHREND der Last -- der troepfelnde Download =="
wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live.img"
qemu_bg "osum $BASE $NETARGS nsvc=0 nwait=0 script=wget -q http://$HOST_IP:8000/langsam &;netmeter 10;exit" \
    "$TMPD/waehrend.txt"
wait "$QPID" 2>/dev/null; QPID=""
srv_down; bridge_down; wire_down

W="$TMPD/waehrend.txt"
echo "-- LAUF C (Messung WAEHREND des Downloads) --"
grep -a '^netmeter:' "$W" | sed 's/^/       /'

bewegt=$(grep -a '^netmeter: t=' "$W" | grep -aoE 'rrx=[0-9]+' | cut -d= -f2 \
         | awk '$1 > 5000' | wc -l)
num "Zusage 2 -- Sekunden mit echtem Durchsatz (>5 KiB/s)" "$bewegt" ge 5
maxw=$(grep -a '^netmeter: done' "$W" | grep -aoE 'maxr=[0-9]+' | cut -d= -f2)
num "Zusage 2b -- Spitzenrate waehrend der Last" "${maxw:-}" gt 50000
spaet=$(grep -a '^netmeter: t=' "$W" | tail -2 | grep -aoE 'rrx=[0-9]+' \
        | cut -d= -f2 | sort -n | tail -1)
if [ -n "${spaet:-}" ] && [ -n "${maxw:-}" ] && [ "$spaet" -lt "$maxw" ]; then
    ok "Zusage 3b -- die Rate am Ende ($spaet) liegt unter der Spitze ($maxw)"
else
    bad "Zusage 3b -- die Rate faellt nicht: Ende $spaet, Spitze $maxw"
fi
drxw=$(grep -a '^netmeter: done' "$W" | grep -aoE 'drx=[0-9]+' | cut -d= -f2)
num "Zusage 4c -- waehrend der Messung bewegte Oktette" "${drxw:-}" ge "$(( BODY / 3 ))"

echo "== 3. Traeger und Verbindungsrate, wie die Seite sie zeigt =="
link=$(grep -a '^netmeter: start' "$R" | grep -aoE 'link=[0-9]+' | cut -d= -f2)
spd=$(grep -a '^netmeter: start' "$R" | grep -aoE 'speed=[0-9]+' | cut -d= -f2)
num "der Traeger steht (NG_LINK)" "${link:-}" eq 1
if [ "${spd:-0}" = 0 ]; then
    ok "die Verbindungsrate ist 0 = unbekannt -- virtio ohne SPEED_DUPLEX,"
    note "und die Oberflaeche schreibt dafuer das Wort 'unbekannt' hin."
else
    ok "die Karte meldet eine Verbindungsrate: $spd Mbit/s"
fi

echo
echo "NETZUI-DURCHSATZ: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
