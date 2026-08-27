#!/usr/bin/env bash
# tools/netmon/run.sh -- ROUND NETMON: WHO USED HOW MUCH, MEASURED.
#
# The round claims four things and every one of them is a number that
# comes out of a run of QEMU on a real wire, not out of a comment:
#
#   1. THE COUNTER IS RIGHT. A file of a size the HOST decided is
#      fetched by /bin/wget, and the kernel's per-program payload
#      counter is held against that size. The difference is the HTTP
#      header and it is printed rather than hidden.
#   2. THE COUNTER COSTS ALMOST NOTHING. The same image moves the same
#      megaoctet twice -- once counting, once with `nonetmon` -- and the
#      two throughputs are printed in KiB/s with the difference in
#      percent. If it were expensive it would be in the wrong place, and
#      this is the run that would say so.
#   3. THE ATTRIBUTION IS RIGHT. Two programs use the wire in the same
#      boot, one a lot and one a little. Not the sum -- the SPLIT has to
#      be right, and a counter that only gets the sum right is a counter
#      that could have been global.
#   4. WIRE IS NOT PAYLOAD. The octets on the card are more than the
#      octets the program saw, and the run says by how much and why.
#
# The wire is the one round K8 built: QEMU's UDP socket backend, the
# AF_PACKET bridge of `tools/net/bruecke.c`, a veth pair and a network
# namespace -- `/dev/net/tun` does not exist in the container this
# repository is measured in.
#
# Usage:  bash tools/netmon/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo ping wget netstat sleep"
# `/var/net/` has to exist on the image: the history file lives there.
BLOCKS=4096

NS=nmon-$$
V0=nm0-$$
V1=nmp-$$
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
QPORT=$(( 5800 + ($$ % 90) * 2 ))
BPORT=$(( QPORT + 1 ))

TMPD=$(mktemp -d)
BRPID=""
QPID=""
SRVPID=""

cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
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

num() { # name value op expected
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "${value:-}" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, expected $op $want"; fi
}

has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' should not be there" || ok "$3"; }

nicval() { grep -aoE "^nic: $2=[0-9]+" "$1" 2>/dev/null | tail -1 | cut -d= -f2; }
# The counter line is `netmon: on=... lookup=... hit=...`; the bench line
# starts `netmon: bench` and also contains ` hit=`. Taking the last line
# beginning with `netmon:` therefore read the wrong one, which is how
# `lookup` came back empty during development. Pin it to the right line.
monval() { grep -a "^netmon: on=" "$1" 2>/dev/null | tail -1 \
           | grep -aoE "(^|[ :])$2=[0-9]+" | tail -1 | cut -d= -f2; }

# ------------------------------------------------------- the tools
bash vendor/firn/hole-firnc.sh >/dev/null || { echo "hole-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc0 is missing"; exit 1; }
for t in qemu-system-x86_64 ip gcc python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "NETMON: skipped, $t is not available"; exit 0; }
done
ip netns del "$NS" 2>/dev/null
if ! ip netns add "$NS" 2>/dev/null; then
    echo "NETMON: skipped, network namespaces are not available here"
    exit 0
fi
ip netns del "$NS" 2>/dev/null

# =====================================================================
echo "== 1. build: the kernel with netmon.fi, and /bin/netstat =="
# =====================================================================
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/$f.s" 2>/dev/null || bad "$f.s does not assemble"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"

build_stage() { # 0 = firnc0, 1 = firnc1
    local s=$1 cc p
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    "$cc" kernel/kmain.fi -o "$TMPD/k$s.o" >"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s does not compile the kernel"; sed 's/^/        /' "$TMPD/e$s" | head -8; return 1; }
    "$cc" kernel/uprog.fi -o "$TMPD/u$s.o" >>"$TMPD/e$s" 2>&1 \
        || { bad "firnc$s does not compile uprog.fi"; return 1; }
    ld -n -T "$LDSCRIPT" \
        --defsym=KERNEL_MAIN="_F$s.kernel_main" \
        --defsym=KERNEL_TRAP="_F$s.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F$s.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F$s.tasks__main" \
        --defsym=KERNEL_USER_START="_F$s.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F$s.smp__ap_main" \
        --defsym=USER_MAIN="_F$s.u_enter" \
        -o "$TMPD/k$s.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
        "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k$s.o" "$TMPD/u$s.o" 2>"$TMPD/ld$s.err" \
        || { bad "firnc$s: ld failed"; return 1; }
    objcopy -O elf32-i386 "$TMPD/k$s.elf" "$TMPD/k$s.mb" 2>/dev/null
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" >"$TMPD/e$p$s" 2>&1 \
            || { bad "firnc$s does not compile $p.fi"; sed 's/^/        /' "$TMPD/e$p$s" | head -6; return 1; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>/dev/null \
            || { bad "firnc$s: ld failed on $p"; return 1; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return 0
}
build_stage 0 || { echo "NETMON: $pass passed, $fail failed"; exit 1; }
ok "firnc0: kernel + $(echo $PROGS | wc -w) programs, /bin/netstat among them"
if [ "${NETMON_FAST:-0}" = 1 ]; then
    note "firnc1 skipped (NETMON_FAST=1)"
else
    build_stage 1 && ok "firnc1: the same, out of the compiler written in Firn" \
                  || bad "firnc1 did not build it"
fi

n=$(nm "$TMPD/k0.o" 2>/dev/null | grep -c 'netmon__frame_seen')
num "netmon.frame_seen is really linked into the kernel" "$n" ge 1
n=$(stat -c%s "$TMPD/netstat0.elf")
num "/bin/netstat, octets" "$n" gt 1000

gcc -O2 -o "$TMPD/bruecke" tools/net/bruecke.c 2>"$TMPD/gcc.err" \
    && ok "tools/net/bruecke.c: the UDP/AF_PACKET wire is built" \
    || { bad "bruecke.c does not compile"; head -5 "$TMPD/gcc.err" | sed 's/^/        /'; }

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf"; done
SPEC="$SPEC /var/ /var/net/"
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py: an image with /bin/netstat on it" \
    || { bad "mkfs.py failed"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; }

# =====================================================================
# the wire
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
bridge_up() { "$TMPD/bruecke" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!; sleep 0.4; }
bridge_down() { [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; wait "$BRPID" 2>/dev/null; BRPID=""; sleep 0.2; }

qemu_bg() {
    local image=$1 append=$2 out=$3
    shift 3
    rm -f "$out"
    ( timeout 180 qemu-system-x86_64 -kernel "$image" -m 256 -append "$append" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$out.rc" ) &
    QPID=$!
}
qemu_wait() { wait "$QPID" 2>/dev/null; QPID=""; }

BASE="nokbd nosched noproc nofs noring3"
NETARGS="nic nip=$OSUM_IP/24 ngw=$HOST_IP"

# A python HTTP server in the namespace that serves a body of a size the
# HOST chose. That size is the truth the counter is measured against.
BODY=65536
cat > "$TMPD/httpsrv.py" <<'PY'
import http.server, socketserver, sys, time
import threading
N = int(sys.argv[2])
BODY = (b"0123456789abcdef" * ((N // 16) + 1))[:N]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # /slow answers after four seconds. The connection is then
        # ESTABLISHED for long enough that `netstat` can be run on it
        # WITHOUT a race -- a connection list measured by hoping to be
        # quick enough would be a flaky test, and this round has seen
        # enough of those in the parallel suites today.
        if self.path.endswith("slow"):
            time.sleep(4)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
class T(socketserver.ThreadingTCPServer):
    daemon_threads = True
with T(("0.0.0.0", int(sys.argv[1])), H) as s:
    s.serve_forever()
PY

srv_up()   { ip netns exec "$NS" python3 "$TMPD/httpsrv.py" 8000 "$BODY" > "$TMPD/httpd.log" 2>&1 & SRVPID=$!; sleep 1; }
srv_down() { [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; SRVPID=""; }

# =====================================================================
echo "== 2. the counter against a file of known size =="
# =====================================================================
wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live1.img"
qemu_bg "$TMPD/k0.mb" \
    "osum $BASE $NETARGS nsvc=0 nwait=0 script=wget -q http://$HOST_IP:8000/x;netstat -p;netstat -s;exit" \
    "$TMPD/c1.txt" -drive "file=$TMPD/live1.img,format=raw,if=ide,index=0"
qemu_wait
srv_down; bridge_down; wire_down
R="$TMPD/c1.txt"
has "$R" "wget: status 200" "/bin/wget fetched the file"
W=$(grep -aoE '^wget: octets [0-9]+' "$R" | tail -1 | awk '{print $3}')
num "what wget itself says it read, octets" "${W:-}" eq $BODY

PAYRX=$(grep -aoE '^wget +[0-9]+ <- +[0-9]+' "$R" | tail -1 | sed 's/.*<- *//')
PAYTX=$(grep -aoE '^wget +[0-9]+ <- +[0-9]+' "$R" | tail -1 | awk '{print $2}')
if [ -z "${PAYRX:-}" ]; then
    bad "the program table has no line for wget"
    grep -a -A 24 'Program ' "$R" | head -28 | sed 's/^/        /'
else
    num "what the KERNEL counted for the program wget, payload in" "$PAYRX" ge $BODY
    D=$(( PAYRX - BODY ))
    num "and the difference to the file itself is the HTTP header, octets" "$D" lt 400
    note "the server sent $BODY octets of body; wget read $PAYRX, of which $D are the"
    note "status line, the headers and the empty line before the body."
    num "and what wget SENT is the request line and nothing else" "$PAYTX" lt 400
fi

CTX=$(grep -aoE '^card octets out +[0-9]+' "$R" | tail -1 | awk '{print $4}')
CRX=$(grep -aoE '^card octets in +[0-9]+' "$R" | tail -1 | awk '{print $4}')
HIT=$(grep -aoE '^  placed on a task +[0-9]+' "$R" | tail -1 | awk '{print $5}')
MISS=$(grep -aoE '^  system \(arp, icmp\) +[0-9]+' "$R" | tail -1 | awk '{print $4}')
if [ -n "${CRX:-}" ] && [ -n "${PAYRX:-}" ]; then
    num "octets the CARD received, which is more than the payload" "$CRX" gt "$PAYRX"
    OV=$(( (CRX - PAYRX) * 100 / PAYRX ))
    note "wire is $OV% more than payload on the receiving side: $CRX against $PAYRX."
    note "That is the Ethernet, IP and TCP headers of every frame plus the"
    note "acknowledgements travelling the other way, and it is why 'data used'"
    note "never matches the size of the file."
fi
num "frames the classifier placed on a process" "${HIT:-}" gt 40
if [ -n "${MISS:-}" ] && [ -n "${HIT:-}" ]; then
    T=$(( HIT + MISS ))
    P=$(( HIT * 100 / T ))
    num "share of frames that could be placed, percent" "$P" ge 80
    note "$MISS of $T frames went to the system bucket: ARP, and the frames of"
    note "a connection whose socket was already closed when they arrived."
fi
hasnot "$R" "*** EXCEPTION" "not one exception in the run"

# =====================================================================
echo "== 3. two programs, one wire: the SPLIT has to be right =="
# =====================================================================
wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live2.img"
qemu_bg "$TMPD/k0.mb" \
    "osum $BASE $NETARGS nsvc=0 nwait=0 script=ping -c 3 $HOST_IP;wget -q http://$HOST_IP:8000/x;netstat -p;exit" \
    "$TMPD/c2.txt" -drive "file=$TMPD/live2.img,format=raw,if=ide,index=0"
qemu_wait
srv_down; bridge_down; wire_down
R="$TMPD/c2.txt"
has "$R" "0% packet loss" "/bin/ping got its answers"
has "$R" "wget: status 200" "and /bin/wget its file"
PW=$(grep -aoE '^wget +[0-9]+ <- +[0-9]+' "$R" | tail -1 | sed 's/.*<- *//')
PP=$(grep -aoE '^ping +[0-9]+ <- +[0-9]+' "$R" | tail -1 | sed 's/.*<- *//')
PPT=$(grep -aoE '^ping +[0-9]+ <- +[0-9]+' "$R" | tail -1 | awk '{print $2}')
if [ -z "${PW:-}" ] || [ -z "${PP:-}" ]; then
    bad "the program table does not have BOTH programs on it"
    grep -a -A 24 'exact octets' "$R" | head -20 | sed 's/^/        /'
else
    ok "both programs are on the table, each with its own row"
    num "ping, payload in (three echo replies)" "$PP" ge 100
    num "ping, payload in, and not more than a handful of replies" "$PP" lt 2000
    num "ping, payload out" "$PPT" ge 100
    num "wget, payload in (the 64 KiB file)" "$PW" ge $BODY
    R1=$(( PW / (PP + 1) ))
    num "wget/ping ratio -- the split, not just the total" "$R1" ge 20
    # ICMP does not go through the pump: `inet.icmp_send` builds the
    # frame and hands it to the card itself. The first measured run of
    # this round had `ping` at wire 0 out and 294 in for that reason.
    PWO=$(grep -aoE '^ping +[0-9]+ <- +[0-9]+ +wire: +[0-9]+' "$R" | tail -1 | sed 's/.*wire: *//')
    num "ping, WIRE out -- the path that does not go through the pump" "${PWO:-}" ge 200
    note "ping used $PP octets and wget $PW in the same boot. A counter that got"
    note "the SUM right and the split wrong would pass a test that added them."
fi

# =====================================================================
echo "== 4. what the counting costs =="
# =====================================================================
# TWO MEASUREMENTS, AND ONLY ONE OF THEM IS ANY GOOD.
#
# The obvious one is a stopwatch: move a megaoctet with the counting on,
# move it again with `nonetmon`, compare. It is printed below because it
# was asked for -- and it is worthless on this machine. There is no
# /dev/kvm here, so QEMU emulates every instruction, and four other
# rounds of this repository were building at the same time (load average
# twenty on twelve cores). Four alternating pairs during development
# came out 2282/2695, 3179/5831, 3484/4363 and 4005/2642 KiB/s: the
# ranges overlap and one pair is the wrong way round.
#
# The one that means something measures the classifier itself.
# `netmonbench` calls `netmon.frame_seen` 65 536 times on a frame the
# kernel builds, between two reads of the cycle counter, three times:
# with the counting off (the floor -- one call, one test, one return),
# with a matching socket (the one-entry cache answers, which is what
# every frame of a running transfer does) and without one (the table is
# walked to the end). The cost per frame follows, and the share of the
# throughput follows from THAT and the frame count of the real run --
# arithmetic done here, in the open, out of numbers that were measured.
speed_run() { # extra-words outfile
    wire_up; bridge_up
    qemu_bg "$TMPD/k0.mb" "$BASE $NETARGS nsvc=1 nport=7000 nbytes=1048576 nwait=300 $1" "$2"
    local i
    for i in $(seq 1 100); do
        [ -f "$2" ] && grep -qaF "nic: listening=" "$2" && break
        sleep 0.2
    done
    sleep 0.3
    ip netns exec "$NS" python3 - "$OSUM_IP" 7000 1048576 <<'PY' >/dev/null 2>&1
import socket, sys
h, p, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
b = bytes(4096)
s = socket.create_connection((h, p), timeout=40)
sent = 0
while sent < n:
    sent += s.send(b[:min(4096, n - sent)])
s.shutdown(socket.SHUT_WR)
s.close()
PY
    qemu_wait
    bridge_down; wire_down
}
speed_run "netmonbench" "$TMPD/s_on.txt"
speed_run "nonetmon" "$TMPD/s_off.txt"

ON=$(nicval "$TMPD/s_on.txt" kib_per_s)
OFF=$(nicval "$TMPD/s_off.txt" kib_per_s)
ONO=$(nicval "$TMPD/s_on.txt" octets)
OFFO=$(nicval "$TMPD/s_off.txt" octets)
num "octets through with the counting on" "${ONO:-}" ge 1048576
num "octets through with the counting off" "${OFFO:-}" ge 1048576

# --- the classifier really ran, and the cache really worked
LK=$(monval "$TMPD/s_on.txt" lookup)
HT=$(monval "$TMPD/s_on.txt" hit)
CH=$(monval "$TMPD/s_on.txt" chit)
CS=$(monval "$TMPD/s_on.txt" cscan)
RXW=$(monval "$TMPD/s_on.txt" sysrx)
num "frames classified during the megaoctet" "${LK:-}" gt 500
num "and placed on the process that owns the connection" "${HT:-}" gt 500
num "walks of the whole socket table -- the cache took the rest" "${CS:-}" le 4
note "$CH of ${LK:-0} frames were answered out of the one-entry cache, ${CS:-0} needed"
note "the table walked. Before the cache existed every frame walked it, and"
note "section 4 of this run is why the cache exists."
has "$TMPD/s_off.txt" "netmon: on=0" "with 'nonetmon' the counting really is off"
n=$(monval "$TMPD/s_off.txt" lookup)
num "and then not one frame was classified" "${n:-}" eq 0

# --- the stopwatch, printed and disbelieved
if [ -n "${ON:-}" ] && [ -n "${OFF:-}" ] && [ "$OFF" -gt 0 ]; then
    note "stopwatch, counting on:  $ON KiB/s"
    note "stopwatch, counting off: $OFF KiB/s"
    D=$(( (OFF - ON) * 1000 / OFF ))
    note "difference $(( D / 10 )).$(( (D % 10 + 10) % 10 ))% -- see the paragraph above; on an idle"
    note "machine with KVM this would be worth reading and here it is not."
fi

# --- the measurement that means something
B=$(grep -a 'netmon: bench ' "$TMPD/s_on.txt" | tail -1)
BOFF=$(echo "$B" | grep -oE 'off=[0-9]+' | cut -d= -f2)
BHIT=$(echo "$B" | grep -oE ' hit=[0-9]+' | cut -d= -f2)
BSCAN=$(echo "$B" | grep -oE 'scan=[0-9]+' | cut -d= -f2)
KHZ=$(echo "$B" | grep -oE 'khz=[0-9]+' | cut -d= -f2)
if [ -z "${BHIT:-}" ] || [ -z "${KHZ:-}" ] || [ "${KHZ:-0}" -eq 0 ]; then
    bad "the classifier bench printed no numbers"
else
    # The three are cycles-per-frame times a hundred.
    ok "one frame, counting switched off:      $(( BOFF / 100 )) cycles (the floor)"
    ok "one frame, cache hit (every frame of a transfer): $(( BHIT / 100 )) cycles"
    note "these are cycles under QEMU's INSTRUCTION EMULATOR -- there is no"
    note "/dev/kvm on this machine, so every guest instruction costs the host"
    note "a few dozen. The number to read is not the absolute cycles, it is"
    note "the share of the transfer below, measured in the same emulator."
    ok "one frame, whole socket table walked:  $(( BSCAN / 100 )) cycles"
    num "the cache is cheaper than the walk, cycles saved per frame" \
        "$(( (BSCAN - BHIT) / 100 ))" gt 0
    # What the counting adds, per frame, in nanoseconds.
    ADD=$(( (BHIT - BOFF) / 100 ))
    NS=$(( ADD * 1000000 / KHZ ))
    ok "so the counting ADDS $ADD cycles = $NS ns to each frame, at $(( KHZ / 1000 )) MHz"
    if [ -n "${LK:-}" ] && [ -n "${ON:-}" ] && [ "$ON" -gt 0 ]; then
        # Seconds the megaoctet took, in milliseconds, out of the
        # throughput the same run printed.
        MS=$(( 1048576 * 1000 / (ON * 1024) ))
        COSTUS=$(( LK * NS / 1000 ))
        PM=$(( COSTUS * 1000 / (MS * 1000) ))
        note "the run moved 1 048 576 octets in $MS ms and classified $LK frames;"
        note "$LK x $NS ns = $COSTUS us of classifying in $MS ms."
        ok "the counting is $(( PM / 10 )).$(( PM % 10 ))% of the time the transfer took"
        num "cost of the counting, tenths of a percent" "$PM" le 50
    fi
fi

# =====================================================================
echo "== 5. the connection list =="
# =====================================================================
wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live3.img"
qemu_bg "$TMPD/k0.mb" \
    "osum $BASE $NETARGS nsvc=0 nwait=0 script=wget -q http://$HOST_IP:8000/slow &;sleep 2;netstat -a;netstat -a;exit" \
    "$TMPD/c3.txt" -drive "file=$TMPD/live3.img,format=raw,if=ide,index=0"
qemu_wait
srv_down; bridge_down; wire_down
R="$TMPD/c3.txt"
has "$R" "Proto Local" "netstat prints the header every netstat prints"
grep -qaE '^tcp +10\.9\.0\.2:[0-9]+ +10\.9\.0\.1:8000' "$R" \
    && ok "the connection of /bin/wget is in the list with both endpoints" \
    || { bad "no connection line with 10.9.0.1:8000 in it"
         grep -a -A 6 'Proto Local' "$R" | head -10 | sed 's/^/        /'; }
grep -qaE '^tcp +10\.9\.0\.2:[0-9]+ +10\.9\.0\.1:8000 +(TIME_WAIT|FIN_WAIT_1|FIN_WAIT_2|LAST_ACK|ESTABLISHED|CLOSE_WAIT|CLOSING)' "$R" \
    && ok "with a TCP state out of the state machine and not a number" \
    || bad "the state column is not one of the eleven names"
# THE COUNTER-CHECK TO THE ROW ITSELF. The socket record was 64 octets
# while it had twelve fields of eight; `sset(S_RXWIRE)` then wrote into
# the next record and switched on its in-use flag, and `netstat` listed
# a connection nobody had opened -- no owner, no port, protocol read out
# of an octet that belonged to somebody else. Any row without an owner
# is that bug coming back.
n=$(grep -acE '^(tcp|udp|icmp) +10\.9\.0\.2:0 +\* ' "$R")
num "rows for a socket that was never opened (the 64-against-96 bug)" "$n" eq 0
grep -qaE '^tcp .*8000 .*wget' "$R" \
    && ok "and the PROGRAM the connection belongs to" \
    || { bad "the program column does not say wget"
         grep -aE '^tcp ' "$R" | head -4 | sed 's/^/        /'; }

# =====================================================================
echo "== 6. the history: a text file, and no double counting =="
# =====================================================================
# `netstat -w` folds what the kernel has counted since the last roll
# into a line per day and a line per month. Running it TWICE has to add
# nothing the second time -- that is the whole point of the watermark,
# and it is the mistake every naive version of this makes.
wire_up; bridge_up; srv_up
cp "$TMPD/disk.img" "$TMPD/live4.img"
qemu_bg "$TMPD/k0.mb" \
    "osum $BASE $NETARGS nsvc=0 nwait=0 script=ping -c 2 $HOST_IP;wget -q http://$HOST_IP:8000/x;netstat -w;netstat -w;netstat -H;cat /var/net/usage;exit" \
    "$TMPD/c4.txt" -drive "file=$TMPD/live4.img,format=raw,if=ide,index=0"
qemu_wait
srv_down; bridge_down; wire_down
R="$TMPD/c4.txt"
n=$(grep -acE '^netstat: programs written [1-9]' "$R")
num "the first roll wrote programs to the file" "$n" ge 1
n=$(grep -acE '^netstat: programs written 0$' "$R")
num "and the SECOND roll wrote nothing -- no double counting" "$n" ge 1
has "$R" "# osum network usage -- period program sent recvd wire-out wire-in" \
    "the file has a header a person can read"
grep -qaE '^2[0-9]{3}-[0-9]{2}-[0-9]{2} wget [0-9]+ [0-9]+ [0-9]+ [0-9]+$' "$R" \
    && ok "a DAY line for wget, in plain text, six fields" \
    || { bad "no day line for wget in /var/net/usage"
         grep -a -A 8 'osum network usage' "$R" | head -10 | sed 's/^/        /'; }
grep -qaE '^2[0-9]{3}-[0-9]{2} wget [0-9]+ [0-9]+ [0-9]+ [0-9]+$' "$R" \
    && ok "and a MONTH line beside it -- that is the '4 GB this month' answer" \
    || bad "no month line for wget"
grep -qaE '^2[0-9]{3}-[0-9]{2} ping ' "$R" \
    && ok "ping has its own rows and is not folded into anything" \
    || bad "no rows for ping"
# The day line and the month line have to agree on the first day of a
# month, which is the only day they can be compared on -- so compare
# what is comparable: the two have the same octets in this one boot.
D=$(grep -aoE '^2[0-9]{3}-[0-9]{2}-[0-9]{2} wget [0-9]+ [0-9]+' "$R" | tail -1 | awk '{print $4}')
M=$(grep -aoE '^2[0-9]{3}-[0-9]{2} wget [0-9]+ [0-9]+' "$R" | tail -1 | awk '{print $4}')
[ -n "${D:-}" ] && [ "${D:-}" = "${M:-}" ] \
    && ok "day and month agree in a boot that spans one day: $D octets" \
    || bad "day $D and month $M disagree"
# THE DATA PROTECTION RULE, tested and not only written down.
n=$(grep -acE '^2[0-9]{3}-[0-9]{2}.*10\.9\.0\.1' "$R")
num "addresses in the history file (there must be NONE)" "$n" eq 0
n=$(grep -acE '^2[0-9]{3}-[0-9]{2}.*:8000' "$R")
num "ports in the history file (there must be NONE)" "$n" eq 0
note "the file records HOW MUCH per program and never WHERE. The live list"
note "in section 5 shows destinations because a person asking now has a right"
note "to know; nothing writes them down."

echo
echo "NETMON: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
