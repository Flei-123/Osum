#!/usr/bin/env bash
# tools/netview/run.sh -- ROUND NETVIEW: FOUR NETWORKS, ONE MACHINE.
#
# What has to be proved, and none of it by assertion:
#
#   1. THE DEFAULT DID NOT MOVE. `real` is what every process got before
#      this round. The whole of `tools/net/run.sh` runs unchanged against
#      the changed kernel, and the number it prints has to be the number
#      it printed before.
#   2. `none` FAILS AT ONCE. Not after a timeout -- at once, and with
#      -ENETUNREACH and not with something invented.
#   3. `faked` SUCCEEDS AT ONCE. The connection comes up, the HTTP status
#      is 204, the body is empty, and the whole exchange is measured IN
#      MICROSECONDS. A faked view that ran into a time limit would be
#      worse than being offline, so the time is the measurement and not
#      a footnote.
#   4. `faked` PUTS NOTHING ON THE WIRE. The octet counter of the CARD
#      DRIVER (`virtio.tx_frame`, printed as `nv: wire_o=`) has to be 0
#      after a run in which a faked program did everything above --
#      against a control run of the same image in `real`, where it is
#      not.
#   5. `filtered` LETS EXACTLY ITS LIST THROUGH. The same target, once on
#      the list and once not, in the same boot.
#   6. TWO PROCESSES, TWO VIEWS, AT THE SAME TIME. This is the real
#      claim of the round: the view hangs on the PROCESS. One `real` and
#      one `faked` program run concurrently against the same server, and
#      the server has to see exactly one of them.
#
# THE WIRE is the one round K8 built (`tools/net/bruecke.c`): QEMU's
# virtio-net over a UDP socket to a bridge process, from there over
# AF_PACKET onto a veth pair into a network namespace with the Linux
# kernel on the other end. Nothing here talks to itself.
#
# Usage:  bash tools/netview/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
PROGS="sh ls cat echo ping wget netview nvcheck ps"
BLOCKS=4096

# The names carry the process number for the same reason round K12 gave
# them one in `tools/net/run.sh`: several suites of this repository are
# measured at the same time, and `ip netns del` in the preparation of one
# of them would otherwise tear the wire out from under another.
NS=nvnet-$$
V0=nv0-$$
V1=v1
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
HTTP_PORT=8000
QPORT=$(( 5800 + ($$ % 90) * 2 ))
BPORT=$(( QPORT + 1 ))

TMPD=$(mktemp -d)
BRPID=""
SRVPID=""

cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
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

num() { # name value op expected
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "${value:-}" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, expected $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' should not be there" || ok "$3"; }

# `nvc: <tag>_<key> <value>` out of the acceptance program.
nvc() { # file tag key
    grep -aoE "^nvc: $2_$3 [0-9]+" "$1" 2>/dev/null | tail -1 | awk '{print $3}'
}
# `nv: <key>=<value>` out of the kernel's own end-of-run report.
kv() { # file key
    grep -aoE "^nv: $2=[0-9]+" "$1" 2>/dev/null | tail -1 | cut -d= -f2
}

# -ENETUNREACH is 101 and `nvcheck` reports a negative answer as
# 1000000 + the number, so that one unsigned column carries both.
ENETUNREACH=1000101

for t in qemu-system-x86_64 ip gcc python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "NETVIEW: skipped, $t is missing"; exit 0; }
done
ip netns list >/dev/null 2>&1 || { echo "NETVIEW: skipped, no network namespaces here"; exit 0; }

# =====================================================================
echo "== 1. building: the kernel out of both compilers, and the programs =="
# =====================================================================
bash vendor/firn/hole-firnc.sh >/dev/null || { echo "hole-firnc.sh failed"; exit 1; }

for s in 0 1; do
    if bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/b$s.log" 2>&1; then
        ok "firnc$s: the kernel with kernel/netview.fi in it builds ($(stat -c%s "$TMPD/k$s.mb") octets)"
    else
        bad "firnc$s: the kernel does not build"
        sed 's/^/        /' "$TMPD/b$s.log" | head -15
    fi
done
[ -f "$TMPD/k0.mb" ] || { echo "NETVIEW: $pass passed, $((fail + 1)) failed"; exit 1; }

as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s does not assemble"
for s in 0 1; do
    if [ "$s" = 0 ]; then cc=$FIRNC; else cc=$FC1; fi
    rc=0
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" > "$TMPD/e$p$s" 2>&1 || {
            bad "firnc$s does not compile $p.fi"
            sed 's/^/        /' "$TMPD/e$p$s" | head -8; rc=1; continue; }
        ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" \
            2>"$TMPD/ld$s.err" || { bad "firnc$s: ld fails on $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    [ "$rc" = 0 ] && ok "firnc$s: $(echo $PROGS | wc -w) programs, /bin/netview and /bin/nvcheck among them"
done

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/${p}0.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/disk.img" $BLOCKS $SPEC \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "mkfs.py: an image with /bin/netview and /bin/nvcheck on it" \
    || bad "mkfs.py failed"

# =====================================================================
# The wire, the bridge, the server, and one run of QEMU.
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
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off \
        >/dev/null 2>&1
}
wire_down() {
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
}
bridge_up() {
    "$TMPD/bruecke" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" &
    BRPID=$!
    sleep 0.4
}
bridge_down() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    wait "$BRPID" 2>/dev/null
    BRPID=""
    sleep 0.2
}

gcc -O2 -o "$TMPD/bruecke" tools/net/bruecke.c 2>"$TMPD/gcc.err" \
    && ok "tools/net/bruecke.c: the wire of round K8 is built" \
    || bad "bruecke.c does not compile"

# A server that COUNTS. Every request it answers is one line in its log,
# and that count is what section 4 holds the two concurrent processes
# against.
cat > "$TMPD/httpsrv.py" <<'PY'
import http.server, socketserver, sys
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def do_GET(self):
        b = b"a page from the linux kernel side, 46 octets.\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)
        sys.stderr.write("served %s\n" % self.path)
        sys.stderr.flush()
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", int(sys.argv[1])), H) as s:
    s.serve_forever()
PY

server_up() {
    rm -f "$TMPD/httpd.log"
    ip netns exec "$NS" python3 "$TMPD/httpsrv.py" "$HTTP_PORT" \
        > "$TMPD/httpd.out" 2> "$TMPD/httpd.log" &
    SRVPID=$!
    sleep 1
}
server_down() {
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    SRVPID=""
    sleep 0.3
}

BASE="osum nokbd nosched noproc nofs noring3"
NETARGS="nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0"

# run_script <script> <outfile>
run_script() {
    local script=$1 out=$2
    cp "$TMPD/disk.img" "$TMPD/live.img"
    rm -f "$out"
    timeout 240 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$BASE $NETARGS script=$script" \
        -serial "file:$out" -display none -no-reboot \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/live.img,format=raw,if=ide,index=0" \
        >/dev/null 2>&1
}

# =====================================================================
echo "== 2. the four views, in ONE boot, against a real Linux server =="
# =====================================================================
# Everything in this section runs in the same machine, one after the
# other, out of the same shell. A difference between two lines can
# therefore not come from the wire, the server or the image -- there is
# only one of each.
wire_up
bridge_up
server_up
run_script "/bin/nvcheck real $HOST_IP $HTTP_PORT;/bin/netview none /bin/nvcheck none $HOST_IP $HTTP_PORT;/bin/netview faked /bin/nvcheck faked $HOST_IP $HTTP_PORT;/bin/netview -a $HOST_IP:$HTTP_PORT filtered /bin/nvcheck filtok $HOST_IP $HTTP_PORT;/bin/netview -a 10.9.0.77:1 filtered /bin/nvcheck filtno $HOST_IP $HTTP_PORT;exit" \
    "$TMPD/four.txt"
server_down
bridge_down
wire_down
F="$TMPD/four.txt"
cp "$F" "$TMPD/keep-four.txt"

echo "   real -- the wire, unchanged"
num "real: the view the process reports"        "$(nvc "$F" real view)"   eq 0
num "real: connect answered"                    "$(nvc "$F" real conn)"   eq 0
num "real: the HTTP status of the python server" "$(nvc "$F" real status)" eq 200
num "real: octets of BODY (the page the server sent)" "$(nvc "$F" real body)" eq 46
num "real: octets in total, header and body"    "$(nvc "$F" real bytes)"  ge 100
r_conn=$(nvc "$F" real conn_us)
ok "real: connect took ${r_conn:-?} us over the veth"

echo "   none -- the cable is pulled"
num "none: the view the process reports"        "$(nvc "$F" none view)"   eq 3
num "none: the network reports itself as down"  "$(nvc "$F" none ready)"  eq 0
num "none: connect said -ENETUNREACH"           "$(nvc "$F" none conn)"   eq $ENETUNREACH
num "none: octets of body"                      "$(nvc "$F" none body)"   eq 0
num "none: and it said so IN MICROSECONDS, not after a timeout" \
    "$(nvc "$F" none conn_us)" lt 20000

echo "   faked -- a network that leads nowhere"
num "faked: the view the process reports"       "$(nvc "$F" faked view)"  eq 2
num "faked: the network reports itself as UP"   "$(nvc "$F" faked ready)" eq 1
num "faked: the address it believes it has (198.51.100.2, TEST-NET-2)" \
    "$(nvc "$F" faked ip)" eq 3325256706
num "faked: connect SUCCEEDED"                  "$(nvc "$F" faked conn)"  eq 0
num "faked: and the reachability check got 204 No Content" \
    "$(nvc "$F" faked status)" eq 204
num "faked: the BODY is EMPTY -- nothing was loaded" \
    "$(nvc "$F" faked body)" eq 0
num "faked: and yet a well-formed header DID arrive (octets)" \
    "$(nvc "$F" faked bytes)" ge 40
num "faked: a name resolved to 198.51.100.80" \
    "$(nvc "$F" faked dns)" eq 3325256784
num "faked: connect, in microseconds"           "$(nvc "$F" faked conn_us)" lt 20000
num "faked: reading the answer, in microseconds" "$(nvc "$F" faked read_us)" lt 20000
num "faked: the WHOLE exchange, in microseconds" "$(nvc "$F" faked total_us)" lt 200000

echo "   filtered -- the list, and only the list"
num "filtered: the view the process reports"    "$(nvc "$F" filtok view)" eq 1
num "filtered, target ON the list: connect went to the real server" \
    "$(nvc "$F" filtok conn)" eq 0
num "filtered, target ON the list: the real status" \
    "$(nvc "$F" filtok status)" eq 200
num "filtered, target ON the list: the real body" \
    "$(nvc "$F" filtok body)" eq 46
num "filtered, target NOT on the list: connect still succeeded (it is faked)" \
    "$(nvc "$F" filtno conn)" eq 0
num "filtered, target NOT on the list: 204 and not 200" \
    "$(nvc "$F" filtno status)" eq 204
num "filtered, target NOT on the list: the body is empty" \
    "$(nvc "$F" filtno body)" eq 0

hasnot "$F" "*** EXCEPTION" "not one exception in the whole run"
hasnot "$F" "osum_panic" "and no checked-arithmetic panic"

# =====================================================================
echo "== 3. THE MEASUREMENT OF THE ROUND: not one octet on the wire =="
# =====================================================================
# No bridge and no server this time, and that is deliberate: what is
# counted is what the CARD DRIVER was handed, not what arrived anywhere.
# A frame that is put on a wire nobody listens to still counts.
#
# The two runs differ in ONE word on one command line.
wire_down
run_script "/bin/netview faked /bin/nvcheck faked $HOST_IP $HTTP_PORT;exit" \
    "$TMPD/quiet.txt"
Q="$TMPD/quiet.txt"
cp "$Q" "$TMPD/keep-quiet.txt"
num "faked, with no wire at all: connect STILL succeeded" \
    "$(nvc "$Q" faked conn)" eq 0
num "faked, with no wire at all: still 204" "$(nvc "$Q" faked status)" eq 204
num "faked: octets the program offered and the kernel threw away" \
    "$(kv "$Q" dropped)" ge 1
num "faked: faked connections opened" "$(kv "$Q" opened)" ge 1
num "OCTETS THAT LEFT THE MACHINE (virtio.tx_frame)" "$(kv "$Q" wire_o)" eq 0

echo "   the control: the SAME image, the SAME wire, the word 'faked' left out"
run_script "/bin/nvcheck real $HOST_IP $HTTP_PORT;exit" "$TMPD/loud.txt"
L="$TMPD/loud.txt"
cp "$L" "$TMPD/keep-loud.txt"
num "real, with nobody on the other end: octets that left the machine" \
    "$(kv "$L" wire_o)" ge 1
num "real: nothing was thrown away, because nothing was faked" \
    "$(kv "$L" dropped)" eq 0
num "real: no faked connection was opened" "$(kv "$L" opened)" eq 0

# =====================================================================
echo "== 4. two processes, two views, at the same time =="
# =====================================================================
# THE ACTUAL CLAIM OF THE ROUND. The view hangs on the process, so two
# processes in one system can disagree about whether there is a network.
# One faked program and one real program are started against the SAME
# server in the SAME shell, and the server -- which counts -- has to
# have seen exactly ONE of them.
wire_up
bridge_up
server_up
run_script "/bin/netview faked /bin/nvcheck bgfake $HOST_IP $HTTP_PORT &
/bin/nvcheck fgreal $HOST_IP $HTTP_PORT;/bin/ps;exit" \
    "$TMPD/both.txt"
server_down
bridge_down
wire_down
B="$TMPD/both.txt"
cp "$B" "$TMPD/keep-both.txt"
num "at the same time: the faked process reports view 2" \
    "$(nvc "$B" bgfake view)" eq 2
num "at the same time: the real process reports view 0" \
    "$(nvc "$B" fgreal view)" eq 0
num "the faked one got 204 out of the kernel" "$(nvc "$B" bgfake status)" eq 204
num "the real one got 200 out of the python server" \
    "$(nvc "$B" fgreal status)" eq 200
num "the faked one loaded nothing" "$(nvc "$B" bgfake body)" eq 0
num "the real one loaded the page" "$(nvc "$B" fgreal body)" eq 46
served=$(grep -ac '^served ' "$TMPD/httpd.log" 2>/dev/null)
num "and the python server, which counts, saw EXACTLY ONE of the two" \
    "${served:-0}" eq 1
has "$B" "NET" "/bin/ps has a NET column"

cp "$TMPD"/keep-*.txt "${NVLOGS:-/tmp}/" 2>/dev/null

echo
echo "NETVIEW: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
