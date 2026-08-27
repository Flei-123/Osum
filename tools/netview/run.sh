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
# THE WIRE is the one round K8 built (`tools/net/bridge.c`): QEMU's
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
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }

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

# `/etc/` is on this image because of the second addendum: `netview
# fallback <word>` writes `/etc/netview.conf`, and a directory that is
# not there is not a place a file can be created. The first run of
# section 8f said exactly that, out loud, because `conf_write` reports
# its failure instead of half-succeeding quietly.
SPEC="/bin/ /etc/"
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

gcc -O2 -o "$TMPD/bruecke" tools/net/bridge.c 2>"$TMPD/gcc.err" \
    && ok "tools/net/bridge.c: the wire of round K8 is built" \
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

# run_script <script> <outfile> [extra-kernel-words] [no-nic]
#
# The third argument is what the second addendum measures with: the
# WHOLE difference between "it fails" and "it works" has to be one word
# on the kernel command line, with the same image, the same script and
# the same wire. Anything else and the two runs are not comparable.
run_script() {
    local script=$1 out=$2 extra=${3:-} nonic=${4:-}
    local net="$NETARGS"
    [ -n "$nonic" ] && net=""
    local NET=()
    if [ -z "$nonic" ]; then
        NET=(-netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT"
             -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc")
    fi
    cp "$TMPD/disk.img" "$TMPD/live.img"
    rm -f "$out"
    timeout 240 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$BASE $net $extra script=$script" \
        -serial "file:$out" -display none -no-reboot \
        "${NET[@]}" \
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

# =====================================================================
echo "== 5. the symbols: seven drawings, measured before anything is drawn =="
# =====================================================================
# The design rules of the addendum are checked BEFORE the machine boots,
# because they are properties of the drawings and not of the run: the
# contrast of every role against the panel it lies on, in both schemes,
# and the SILHOUETTES of the seven signs against each other. The second
# one is the colour-blind test: flatten every colour to one and the
# shapes still have to differ.
if python3 tools/netview/icons.py pruefe > "$TMPD/icons.txt" 2>&1; then
    ok "tools/netview/icons.py: every rule of the addendum holds"
    grep -aE '  (dark|light) ' "$TMPD/icons.txt" | sed 's/^/        /'
    grep -aE 'vs ' "$TMPD/icons.txt" | sed 's/^/        /'
else
    bad "the icons break a rule of the addendum"
    sed 's/^/        /' "$TMPD/icons.txt" | head -20
fi
n=$(grep -acE '  (dark|light) ' "$TMPD/icons.txt")
num "roles whose contrast was computed against the panel (4.5:1 or better)" "$n" eq 8
n=$(grep -ac 'ZU AEHNLICH\|ZU WENIG' "$TMPD/icons.txt")
num "rules broken" "$n" eq 0
python3 tools/netview/icons.py kern "$TMPD/netmark.fi" >/dev/null 2>&1
if cmp -s "$TMPD/netmark.fi" kernel/netmark.fi; then
    ok "kernel/netmark.fi is the drawing, octet for octet -- one source, two places"
else
    bad "kernel/netmark.fi does not match assets/netview/mark-*.txt"
fi

# =====================================================================
echo "== 6. the two displays, on a real screen =="
# =====================================================================
# THE POINT OF THIS SECTION IS THE SECOND SHOT. Windows has ONE icon in
# the corner and it describes the machine; here the network is a
# property of the PROCESS, so the corner cannot say it. The measurement
# is therefore in two halves:
#
#   the CORNER  -- four boots, four states of the machine, four icons
#   the BUTTONS -- ONE boot with FOUR programs in FOUR views, and four
#                  different marks on four buttons of the same bar
#
# and both halves are read out of the PICTURE, pixel by pixel, at the
# coordinates the taskbar itself reported on the serial line. A bar that
# reported one thing and drew another would fail here and not pass
# quietly -- that is the lesson of round K7B and it is why nothing in
# this section is judged by eye.
SHOTS=${NVSHOTS:-docs/shots/netview}
mkdir -p "$SHOTS"
GPROGS="schreibtisch leiste einstellungen launcher explorer widgetdemo locate netview edit sh echo ls cat ps"
MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
GBASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs"

grc=0
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null
for pgm in $GPROGS; do
    "$FIRNC" "kernel/user/$pgm.fi" -o "$TMPD/g$pgm.o" > "$TMPD/ge$pgm" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/g$pgm.elf" "$TMPD/crt.o" "$TMPD/g$pgm.o" 2>/dev/null \
        && strip --strip-all "$TMPD/g$pgm.elf" \
        || { bad "the graphical userland does not build: $pgm"; sed 's/^/        /' "$TMPD/ge$pgm" | head -6; grc=1; }
done
[ "$grc" = 0 ] && ok "the graphical userland builds ($(echo $GPROGS | wc -w) programs)"

python3 tools/netview/icons.py bauen "$TMPD/icons" > "$TMPD/ib.txt" 2>&1 \
    && ok "the eight symbols are built into OSYM files" \
    || bad "tools/netview/icons.py bauen failed"
python3 tools/k15/tree.py "$TMPD/baum" > "$TMPD/baum.log" 2>&1 \
    || bad "tools/k15/tree.py failed"

printf '# taskbar.conf\nedge=bottom\nheight=28\nwidth=104\nautohide=0\nontop=1\n' \
    > "$TMPD/taskbar.conf"

# THIRD ADDENDUM: the same file with another edge in it. The panel has
# to appear beside the bar on all four edges, and the only way to
# measure that is to boot the bar on all four.
set_edge() { # edge
    printf '# taskbar.conf\nedge=%s\nheight=28\nwidth=104\nautohide=0\nontop=1\n' \
        "$1" > "$TMPD/taskbar.conf"
}

mk_gimage() { # image theme-file
    local img=$1 th=$2
    local ARGS=(build "$img" 4096 /lib/
        "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
    local q
    for q in $GPROGS; do ARGS+=("/bin/$q=$TMPD/g$q.elf"); done
    ARGS+=("/bin/files@/bin/explorer")
    ARGS+=(/etc/ "/etc/theme=$th" "/etc/taskbar.conf=$TMPD/taskbar.conf")
    ARGS+=(/etc/netview/)
    for q in state-nocarrier state-noip state-noroute state-online \
             mark-filtered mark-faked mark-none sys-faking \
             tile-fake tile-net tile-hide; do
        ARGS+=("/etc/netview/$q=$TMPD/icons/$q")
    done
    while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel")
    while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
    python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfsg.txt" 2>&1
}

# gshot <name> <theme> <extra-cmdline> [wire]
gshot() {
    local name=$1 th=$2 extra=$3 wire=${4:-} drive=${5:-}
    local sock="$TMPD/gm-$name.sock" out="$TMPD/$name.txt" ppm="$TMPD/$name.ppm"
    rm -f "$out" "$ppm" "$sock"
    mk_gimage "$TMPD/gd-$name.img" "$th" || { bad "mkfs for $name failed"; return 1; }
    cp -f "$TMPD/gd-$name.img" "$TMPD/gl-$name.img"
    local NET=()
    if [ -n "$wire" ]; then
        NET=(-netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT"
             -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc")
    fi
    # 600 AND NOT 300, and the reason is measured: `gshot` already waits
    # up to 240 seconds for `wm: hold`, and a run that also drives the
    # mouse spends another fifty on top -- the script, the pauses, the
    # ping and the screendump. On a machine where another suite is
    # booting QEMUs at the same time (which is normal in this
    # repository) that crossed 300 and the picture was simply missing,
    # with the runner saying "no screenshot" and no reason. 420 was not
    # enough either: the run that drives a mouse spends sixteen seconds
    # on the script alone, and a boot to `wm: hold` under a competing
    # suite has been seen at three hundred and eighty.
    timeout 600 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
        -append "$GBASE $extra" -serial "file:$out" -display none -no-reboot \
        -vga std -monitor "unix:$sock,server,nowait" \
        -drive "file=$TMPD/gl-$name.img,format=raw,if=ide,index=0" \
        "${NET[@]}" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 1600 ]; do
        grep -qaE '^wm: hold' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15
        i=$((i + 1))
    done
    # ONLINE needs the gateway to have ANSWERED, and nothing here sends
    # traffic on its own. A ping from the Linux side fills the address
    # cache -- which is exactly what "there is a way to the first hop"
    # means, and why the state is not simply "an address is configured".
    if [ "$wire" = "ping" ]; then
        ip netns exec "$NS" ping -c 4 -i 0.3 -W 2 "$OSUM_IP" >/dev/null 2>&1
        sleep 2
    fi
    # THIRD ADDENDUM: drive the machine before the picture is taken.
    # `sendkey meta_l-a` is a REAL key through the PS/2 controller, and
    # so it is the only way to find out whether the Super key arrives at
    # `kbd.fi` -- which, before this addendum, it did not.
    if [ -n "$drive" ] && [ -s "$drive" ]; then
        python3 tools/wm/monitor.py "$sock" "$drive" 0.12 \
            > "$TMPD/$name.mon" 2>&1
        sleep 2
    fi
    python3 tools/gfx/screenshot.py "$sock" "$ppm" 30 > "$TMPD/$name.shot" 2>&1
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    # AND SAY WHY WHEN THERE IS NO PICTURE. "no screenshot" on its own
    # sent this round chasing a click that had in fact worked.
    if [ ! -s "$ppm" ]; then
        echo "        no picture for $name; qemu said:"
        tail -3 "$TMPD/$name.qemu" 2>/dev/null | sed 's/^/        /'
        tail -2 "$TMPD/$name.shot" 2>/dev/null | sed 's/^/        /'
        return 1
    fi
    return 0
}

png() { python3 - "$1" "$SHOTS/$2.png" <<'PYX' 2>/dev/null
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
PYX
}

# WHAT THE BAR REPORTS IS INSIDE ITS OWN WINDOW; WHAT THE PICTURE HAS IS
# THE SCREEN. The offset between the two is the position of the bar's
# window, which the bar also reports (`taskbar: geom ... x= y=`). The
# first run of this section forgot that and measured the icon against the
# wrong 62 pixels -- so the offset is read out of the log and never
# assumed.
# THE WHOLE LINE OR NOTHING. Three programs write to this one serial
# line at the same time, and a line that another program wrote into the
# middle of is not a measurement -- the first version took `tail -1` of
# anything starting with `taskbar: geom`, got a spliced line, read no
# offset, quietly used 0 and then measured the top-left corner of the
# screen against a taskbar icon. It said `falsch 54 von 54` and it was
# right; the icon was perfect and the question was wrong. So: only a
# line that matches END TO END counts, and if there is none, the runner
# says so instead of assuming a zero.
gx_of() { grep -aoE '^taskbar: geom edge=[0-9]+ x=[0-9]+ y=[0-9]+ ' "$1" | tail -1 | grep -oE 'x=[0-9]+' | cut -d= -f2; }
gy_of() { grep -aoE '^taskbar: geom edge=[0-9]+ x=[0-9]+ y=[0-9]+ ' "$1" | tail -1 | grep -oE 'y=[0-9]+' | cut -d= -f2; }
st_of()  { grep -aoE '^taskbar: state s=[0-9]+' "$1" | tail -1 | cut -d= -f2; }
st_x()   { grep -aoE '^taskbar: state s=[0-9]+ x=[0-9]+' "$1" | tail -1 | grep -oE 'x=[0-9]+' | cut -d= -f2; }
st_y()   { grep -aoE '^taskbar: state s=[0-9]+ x=[0-9]+ y=[0-9]+' "$1" | tail -1 | grep -oE 'y=[0-9]+$' | cut -d= -f2; }

echo "   the CORNER: four states of the machine, four boots, four icons"
declare -A WANT=( [nocarrier]=0 [noip]=1 [noroute]=2 [online]=3 )
wire_down
for cs in nocarrier noip noroute online; do
    case $cs in
        nocarrier) EX="netvdemo"; W="" ;;
        noip)      EX="netvdemo nic"; W="1" ;;
        noroute)   EX="netvdemo nic nip=$OSUM_IP/24 ngw=$HOST_IP"; W="1" ;;
        online)    EX="netvdemo nic nip=$OSUM_IP/24 ngw=$HOST_IP"; W="ping" ;;
    esac
    if [ -n "$W" ]; then wire_up; bridge_up; fi
    if gshot "st-$cs" "assets/netview/theme-dark" "$EX" "$W"; then
        L="$TMPD/st-$cs.txt"; P="$TMPD/st-$cs.ppm"
        png "$P" "state-$cs"
        got=$(st_of "$L")
        num "$cs: the kernel reported state" "${got:-99}" eq "${WANT[$cs]}"
        x=$(st_x "$L"); y=$(st_y "$L")
        GX=$(gx_of "$L"); GY=$(gy_of "$L")
        if [ -z "$GX" ] || [ -z "$GY" ]; then
            bad "$cs: the bar never reported an unspliced position"
            GX=0; GY=0
        fi
        if [ -n "$x" ] && [ -n "$y" ]; then
            x=$((x + GX)); y=$((y + GY))
            r=$(python3 tools/netview/checkshot.py "$P" "$x" "$y" \
                "assets/netview/state-$cs.txt" assets/netview/theme-dark 2>&1)
            case "$r" in ok*) ok "$cs: the icon is on the screen at $x,$y -- $r" ;;
                         *)   bad "$cs: $r" ;; esac
        else
            bad "$cs: the bar did not report where it drew the icon"
        fi
    else
        bad "$cs: no screenshot"
    fi
    if [ -n "$W" ]; then bridge_down; wire_down; fi
done

echo "   SECOND ADDENDUM: online AND faking -- the two signs beside each other"
# THE CASE THE WHOLE SIGN EXISTS FOR. The machine is genuinely online:
# carrier, address, and a gateway that answered. And the preference is
# `always`, so every new program gets a faked network anyway. The state
# icon on its own would be TRUE AND MISLEADING at the same time, which
# is the one thing a round about not lying may not ship.
#
# So the picture has to carry BOTH signs, and both are read back out of
# it at the coordinates the bar itself reported.
wire_up; bridge_up
if gshot "st-faking" "assets/netview/theme-dark" \
    "netvdemo nic nip=$OSUM_IP/24 ngw=$HOST_IP nvfall=2" "ping"; then
    L="$TMPD/st-faking.txt"; P="$TMPD/st-faking.ppm"
    png "$P" "state-online-faking"
    num "faking: the machine really is online" "$(st_of "$L")" eq 3
    GX=$(gx_of "$L"); GY=$(gy_of "$L")
    if [ -z "$GX" ] || [ -z "$GY" ]; then
        bad "faking: the bar never reported an unspliced position"
        GX=0; GY=0
    fi
    fl=$(grep -aoE '^taskbar: faking fb=[0-9]+ x=[0-9]+ y=[0-9]+' "$L" | tail -1)
    if [ -n "$fl" ]; then
        fb=$(echo "$fl" | grep -oE 'fb=[0-9]+' | cut -d= -f2)
        fx=$(echo "$fl" | grep -oE ' x=[0-9]+' | tr -d ' x=')
        fy=$(echo "$fl" | grep -oE 'y=[0-9]+$' | cut -d= -f2)
        num "faking: the bar read the preference as 'always'" "${fb:-9}" eq 2
        r=$(python3 tools/netview/checkshot.py "$P" "$((fx + GX))" "$((fy + GY))" \
            assets/netview/sys-faking.txt assets/netview/theme-dark 2>&1)
        case "$r" in ok*) ok "faking: the sys-faking sign is on the screen at $((fx+GX)),$((fy+GY)) -- $r" ;;
                     *)   bad "faking: sys-faking: $r" ;; esac
    else
        bad "faking: the bar never said where it drew the faking sign"
    fi
    # AND THE STATE ICON IS STILL THERE, BESIDE IT, SAYING THE TRUTH
    # ABOUT THE MACHINE. The faking sign ADDS to it, it does not replace
    # it -- a person who wants to know whether there is a cable must
    # still be able to find out.
    sx=$(st_x "$L"); sy=$(st_y "$L")
    if [ -n "$sx" ] && [ -n "$sy" ]; then
        r=$(python3 tools/netview/checkshot.py "$P" "$((sx + GX))" "$((sy + GY))" \
            assets/netview/state-online.txt assets/netview/theme-dark 2>&1)
        case "$r" in ok*) ok "faking: and 'online' is still there beside it -- $r" ;;
                     *)   bad "faking: the state icon went missing: $r" ;; esac
        num "faking: the faking sign comes FIRST (further left)" "$fx" lt "$sx"
    else
        bad "faking: the bar did not report the state icon"
    fi
else
    bad "faking: no screenshot"
fi
bridge_down; wire_down

# THE COUNTER-CHECK, and without it the shot above proves nothing: the
# SAME machine, the SAME wire, the preference left at `off`. The sign
# must NOT be there, and the pixels where it stood must be empty.
wire_up; bridge_up
if gshot "st-nofake" "assets/netview/theme-dark" \
    "netvdemo nic nip=$OSUM_IP/24 ngw=$HOST_IP" "ping"; then
    L="$TMPD/st-nofake.txt"
    has "$L" "taskbar: notfaking fb=0" "counter-check: with the preference off the bar draws no sign"
    hasnot "$L" "taskbar: faking fb=" "counter-check: and it never reported drawing one"
else
    bad "counter-check: no screenshot"
fi
bridge_down; wire_down

echo "   THE PROBE: four programs, four views, one bar, one picture"
# The marks the bar reported, per button: `taskbar: btn i=N ... netv=V mkx=X mky=Y`
mk_line() { grep -aE "^taskbar: btn i=$2 " "$1" | tail -1; }

for scheme in dark light; do
    wire_up; bridge_up
    if gshot "four-$scheme" "assets/netview/theme-$scheme" \
        "netvdemo nic nip=$OSUM_IP/24 ngw=$HOST_IP" "ping"; then
        L="$TMPD/four-$scheme.txt"; P="$TMPD/four-$scheme.ppm"
        png "$P" "four-views-$scheme"
        GX=$(gx_of "$L"); GY=$(gy_of "$L")
        if [ -z "$GX" ] || [ -z "$GY" ]; then
            bad "$scheme: the bar never reported an unspliced position"
            GX=0; GY=0
        fi
        seen_r=0; seen_1=0; seen_2=0; seen_3=0
        for b in 0 1 2 3 4 5 6 7 8 9; do
            line=$(mk_line "$L" "$b")
            [ -z "$line" ] && continue
            # NO `netv=` MEANS `real`. The bar stopped printing the
            # normal case: three programs share this serial line and a
            # line about nothing is how two of them end up written into
            # the middle of each other's words.
            v=$(echo "$line" | grep -oE 'netv=[0-9]+' | cut -d= -f2)
            mx=$(echo "$line" | grep -oE 'mkx=[0-9]+' | cut -d= -f2)
            my=$(echo "$line" | grep -oE 'mky=[0-9]+' | cut -d= -f2)
            case "${v:-0}" in
                0) seen_r=$((seen_r+1)) ;;
                1) name=mark-filtered; seen_1=$((seen_1+1)) ;;
                2) name=mark-faked;    seen_2=$((seen_2+1)) ;;
                3) name=mark-none;     seen_3=$((seen_3+1)) ;;
            esac
            if [ "${v:-0}" != 0 ] && [ -n "$mx" ]; then
                mx=$((mx + GX)); my=$((my + GY))
                r=$(python3 tools/netview/checkshot.py "$P" "$mx" "$my" \
                    "assets/netview/$name.txt" "assets/netview/theme-$scheme" 2>&1)
                case "$r" in ok*) ok "$scheme: button $b carries $name at $mx,$my -- $r" ;;
                             *)   bad "$scheme: button $b, $name: $r" ;; esac
            fi
        done
        num "$scheme: buttons whose process sees the REAL network (no mark)" "$seen_r" ge 1
        num "$scheme: buttons marked filtered" "$seen_1" eq 1
        num "$scheme: buttons marked faked" "$seen_2" eq 1
        num "$scheme: buttons marked none" "$seen_3" eq 1
        # THE COUNTER-CHECK: the unmarked button must be EMPTY where a
        # mark would be. A checker that only ever looks where it expects
        # something is a checker that would pass on a bar that draws the
        # same mark on everything.
        rl=$(grep -aE '^taskbar: btn i=[0-9]+ ' "$L" | grep -av 'netv=' | tail -1)
        if [ -n "$rl" ]; then
            rx=$(echo "$rl" | grep -oE ' x=[0-9]+' | tr -d ' x=')
            ry=$(echo "$rl" | grep -oE ' y=[0-9]+' | tr -d ' y=')
            r=$(python3 tools/netview/checkshot.py "$P" "$((rx + GX + 3))" "$((ry + GY + 5))" \
                assets/netview/mark-faked.txt "assets/netview/theme-$scheme" --nicht 2>&1)
            case "$r" in ok*) ok "$scheme: and the REAL one carries nothing -- $r" ;;
                         *)   bad "$scheme: the real button has a mark: $r" ;; esac
        fi
        has "$L" "taskbar: icons=4 marks=3 sys=1" "$scheme: the bar found all eight pictures"
    else
        bad "$scheme: no screenshot of the four views"
    fi
    bridge_down; wire_down
done

# The icon sheet: the eight signs at the size they are shown at, in both
# schemes, side by side. Not a measurement -- a picture for a person.
python3 tools/netview/blatt.py "$SHOTS/icons-sheet.png" > "$TMPD/sheet.txt" 2>&1 \
    && ok "the sheet of all eight signs, 1:1 and magnified, light and dark" \
    || bad "tools/netview/blatt.py failed"


# =====================================================================
echo "== 8. SECOND ADDENDUM: the systemwide fallback =="
# =====================================================================
# THE MEASUREMENT IS A DIFFERENCE OF ONE WORD. Same image, same script,
# same wire (or same absence of one); the only thing that changes
# between the runs of 8a and 8b is `nvfall=` on the kernel command
# line. If a program fails in one and works in the other, that
# difference has exactly one cause.
#
# `netview default <cmd>` is what the shell says; it is not a fifth
# view. It asks the kernel the same question the launcher asks for
# every program nobody configured (`appdir.view_for` -> NV_FBVIEW) and
# uses the answer. Written out from a shell so that the acceptance can
# measure it without driving a mouse.

fbk() { grep -aoE "^nv: $2=[0-9]+" "$1" 2>/dev/null | tail -1 | cut -d= -f2; }

echo "   8a. NO NETWORK AT ALL, fallback OFF -- it fails, as it should"
# No `nic` on the command line and no virtio device on the bus: this is
# a machine with the cable pulled, which is the machine the person is
# sitting at when this addendum matters.
run_script "/bin/netview default /bin/nvcheck fboff $HOST_IP $HTTP_PORT;/bin/netview fallback;exit" \
    "$TMPD/fb-off.txt" "nvfall=0" nonic
A="$TMPD/fb-off.txt"
num "8a: the machine reports no carrier"          "$(fbk "$A" link)"   eq 0
num "8a: the preference is off"                   "$(fbk "$A" fallb)"  eq 0
num "8a: so a new program gets the REAL view"     "$(fbk "$A" fbview)" eq 0
num "8a: and the program did get it"              "$(nvc "$A" fboff view)" eq 0
c=$(nvc "$A" fboff conn)
if [ -n "$c" ] && [ "$c" != 0 ]; then
    ok "8a: connect FAILED, as it must on a machine with no network: $c"
else
    bad "8a: connect returned ${c:-nothing} -- it was supposed to fail"
fi
num "8a: nothing was loaded"                      "$(nvc "$A" fboff body)" eq 0
num "8a: and it failed FAST, not into a timeout (us)" \
    "$(nvc "$A" fboff conn_us)" lt 200000

echo "   8b. THE SAME MACHINE, THE SAME COMMAND, fallback WHEN-OFFLINE"
run_script "/bin/netview default /bin/nvcheck fbwo $HOST_IP $HTTP_PORT;/bin/netview fallback;exit" \
    "$TMPD/fb-wo.txt" "nvfall=1" nonic
B="$TMPD/fb-wo.txt"
num "8b: the machine still reports no carrier"    "$(fbk "$B" link)"   eq 0
num "8b: the preference is when-offline"          "$(fbk "$B" fallb)"  eq 1
num "8b: so a new program gets FAKED"             "$(fbk "$B" fbview)" eq 2
num "8b: and the program did get it"              "$(nvc "$B" fbwo view)" eq 2
num "8b: connect SUCCEEDED on a machine with no network" \
    "$(nvc "$B" fbwo conn)" eq 0
num "8b: the reachability check got 204 No Content" \
    "$(nvc "$B" fbwo status)" eq 204
num "8b: the body is EMPTY -- nothing was loaded" "$(nvc "$B" fbwo body)" eq 0
num "8b: a name still resolved"                   "$(nvc "$B" fbwo dns)" eq 3325256784
num "8b: and it took microseconds"                "$(nvc "$B" fbwo total_us)" lt 200000
# THE NUMBER THIS ADDENDUM STANDS OR FALLS ON. `when-offline` invents a
# whole working network; if one octet of it reached the card driver the
# invention would be a leak.
num "8b: OCTETS THAT LEFT THE MACHINE" "$(kv "$B" wire_o)" eq 0
has "$B" "netview: fallback when-offline" "8b: and /bin/netview says so in words"

echo "   8c. PRECEDENCE: an explicit setting beats the preference"
# A real wire this time, and `always` -- the case where the preference
# would fake everything. A program the person put on `real` must come
# out of it with the real network, or the preference is not a default,
# it is an override.
wire_up; bridge_up; server_up
run_script "/bin/netview real /bin/nvcheck expl $HOST_IP $HTTP_PORT;/bin/netview none /bin/nvcheck expn $HOST_IP $HTTP_PORT;/bin/netview default /bin/nvcheck alw $HOST_IP $HTTP_PORT;exit" \
    "$TMPD/fb-alw.txt" "nvfall=2"
server_down; bridge_down; wire_down
C="$TMPD/fb-alw.txt"
num "8c: the preference is always"                "$(fbk "$C" fallb)"  eq 2
num "8c: a program with NO setting gets faked"    "$(nvc "$C" alw view)" eq 2
num "8c: and reads a 204"                         "$(nvc "$C" alw status)" eq 204
num "8c: EXPLICIT real STAYS REAL under 'always'" "$(nvc "$C" expl view)" eq 0
num "8c: and really reached the python server"    "$(nvc "$C" expl status)" eq 200
num "8c: with the real page (46 octets)"          "$(nvc "$C" expl body)" eq 46
num "8c: EXPLICIT none STAYS NONE under 'always'" "$(nvc "$C" expn view)" eq 3
num "8c: and got -ENETUNREACH, not a faked 204"   "$(nvc "$C" expn conn)" eq $ENETUNREACH
num "8c: it loaded nothing"                       "$(nvc "$C" expn body)" eq 0

echo "   8d. when-offline on a machine that IS online -- back to real"
wire_up; bridge_up; server_up
# The ping comes first ON PURPOSE and it is not a trick. `when-offline`
# asks whether the FIRST HOP has ever answered, and a machine that has
# not spoken yet honestly does not know. One exchange settles it -- and
# on a normal desktop the DHCP client has already had that exchange
# before the first program starts. The limit is written down in
# docs/NETVIEW.md rather than hidden behind a probe of our own.
run_script "/bin/ping -c 2 $HOST_IP;/bin/netview default /bin/nvcheck onl $HOST_IP $HTTP_PORT;/bin/netview fallback;exit" \
    "$TMPD/fb-onl.txt" "nvfall=1"
server_down; bridge_down; wire_down
D="$TMPD/fb-onl.txt"
num "8d: the machine reports itself online"       "$(fbk "$D" link)"   eq 3
num "8d: the preference is still when-offline"    "$(fbk "$D" fallb)"  eq 1
num "8d: but a new program now gets REAL"         "$(fbk "$D" fbview)" eq 0
num "8d: and the program did get it"              "$(nvc "$D" onl view)" eq 0
num "8d: it reached the python server"            "$(nvc "$D" onl status)" eq 200
num "8d: and got the real page"                   "$(nvc "$D" onl body)" eq 46

echo "   8e. changing the preference moves NO RUNNING PROCESS"
# The claim of point 3 of the assignment, measured in one boot: the same
# list of processes before and after the preference is changed, and it
# has to be IDENTICAL -- while the very next program to start comes out
# different. New programs get the new view, running ones keep theirs.
wire_up; bridge_up; server_up
run_script "/bin/netview list;/bin/netview fallback always;/bin/netview list;/bin/netview default /bin/nvcheck late $HOST_IP $HTTP_PORT;exit" \
    "$TMPD/fb-live.txt" "nvfall=0"
server_down; bridge_down; wire_down
E="$TMPD/fb-live.txt"
# The two listings, each of them the lines that name a view. The first
# `netview list` runs before the change, the second after it.
python3 - "$E" "$TMPD/fb-live-a.txt" "$TMPD/fb-live-b.txt" <<'PYX'
import sys, re
raw = open(sys.argv[1], 'rb').read().decode('latin-1').splitlines()
runs, cur, seen = [], None, False
for line in raw:
    if line.startswith('  PID KIND'):
        if cur is not None:
            runs.append(cur)
        cur = []
        continue
    if cur is None:
        continue
    m = re.match(r'^\s*(\d+) (user|kernel)\s+(real|filtered|faked|none)', line)
    if m:
        # The listing includes /bin/netview ITSELF, whose pid differs
        # between the two runs -- so it is matched on view, not on pid.
        cur.append(m.group(3))
    elif line.strip() and not line.startswith(' '):
        runs.append(cur); cur = None
if cur is not None:
    runs.append(cur)
runs = [r for r in runs if r]
open(sys.argv[2], 'w').write(' '.join(runs[0]) if len(runs) > 0 else '')
open(sys.argv[3], 'w').write(' '.join(runs[1]) if len(runs) > 1 else '')
print("listings=%d" % len(runs))
PYX
LA=$(cat "$TMPD/fb-live-a.txt" 2>/dev/null)
LB=$(cat "$TMPD/fb-live-b.txt" 2>/dev/null)
if [ -n "$LA" ] && [ "$LA" = "$LB" ]; then
    ok "8e: every running process kept its view across the change [$LA]"
elif [ -z "$LA" ]; then
    bad "8e: no process listing came back at all"
else
    bad "8e: a running process changed view: before [$LA] after [$LB]"
fi
case "$LA" in
    *faked*) bad "8e: something was already faked before the change" ;;
    "")      ;;
    *)       ok "8e: and none of them was faked to begin with" ;;
esac
num "8e: the preference ends up at always"        "$(fbk "$E" fallb)"  eq 2
num "8e: while the NEXT program to start is faked" "$(nvc "$E" late view)" eq 2
num "8e: and reads a 204 instead of the page"     "$(nvc "$E" late status)" eq 204
has "$E" "netview: fallback always" "8e: /bin/netview reported the change"

echo "   8f. the preference survives a reboot -- /etc/netview.conf"
# `netview fallback <word>` writes the file; `netview boot` reads it
# back. Two boots of the same image: the second one is never told
# anything on its command line and has to come up faking all the same.
wire_up; bridge_up
run_script "/bin/netview fallback always;/bin/cat /etc/netview.conf;exit" \
    "$TMPD/fb-w.txt" "nvfall=0"
# The SECOND boot deliberately reuses the image the first one wrote to.
cp "$TMPD/live.img" "$TMPD/persist.img"
rm -f "$TMPD/fb-r.txt"
timeout 240 qemu-system-x86_64 -kernel "$TMPD/k0.mb" -m 256 \
    -append "$BASE $NETARGS script=/bin/netview boot;/bin/netview fallback;exit" \
    -serial "file:$TMPD/fb-r.txt" -display none -no-reboot \
    -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
    -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$TMPD/persist.img,format=raw,if=ide,index=0" >/dev/null 2>&1
bridge_down; wire_down
has "$TMPD/fb-w.txt" "fallback=always" "8f: /etc/netview.conf holds the word, not a number"
num "8f: the first boot ends at always"           "$(fbk "$TMPD/fb-w.txt" fallb)" eq 2
G="$TMPD/fb-r.txt"
# The second boot is told NOTHING on its command line, so the kernel
# starts it at `off`; the only thing that can have moved it is the file.
num "8f: the second boot ends at always, read out of the file alone" \
    "$(fbk "$G" fallb)" eq 2
has "$G" "netview: fallback always" "8f: and 'netview boot' read the file back"

hasnot "$TMPD/fb-wo.txt" "*** EXCEPTION" "8: no exception in the offline run"
hasnot "$TMPD/fb-alw.txt" "*** EXCEPTION" "8: no exception in the 'always' run"

echo


# =====================================================================
echo "== 9. THIRD ADDENDUM: the switch, and the quick settings =="
# =====================================================================
# WHAT HAS TO BE PROVED HERE, and none of it by assertion:
#
#   1. THE SUPER KEY ARRIVES. It did not before this addendum -- 0xE0
#      0x5B fell through `arrow()` and was dropped without a trace. The
#      proof is a REAL key through the PS/2 controller (`sendkey
#      meta_l-a` on the QEMU monitor), and the counter-proof is that the
#      `a` does NOT also land in the focused window as text.
#   2. THE PANEL STANDS AT ALL FOUR EDGES, beside the bar and not under
#      it, laid out against the WORK AREA and not against the screen.
#   3. HOW LONG IT TAKES, in microseconds, from the key press to the
#      panel painted -- on ONE clock, stamped in the keyboard interrupt
#      and read after the paint.
#   4. THE TILE REALLY SWITCHES. Not "the click was received": the
#      machine is genuinely online, the tile is pressed, and the
#      SYS-FAKING SIGN APPEARS IN THE CORNER, read back out of the
#      picture at the coordinates the bar itself reported. And the marks
#      on the running windows must NOT move, because a running process
#      keeps its view.
#   5. THE DEFAULT IS `off` AND `when-offline` IS NEVER REACHED BY
#      ITSELF -- Justin's correction, measured instead of promised.

qsk() { grep -aoE "^qs: open x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+ edge=[0-9]+ up=[0-9]+ us=[0-9]+" "$1" | tail -1; }
qsf() { qsk "$1" | grep -oE "$2=[0-9]+" | cut -d= -f2; }
symln() { grep -aoE "^qs: sym n=$2 x=[0-9]+ y=[0-9]+ to=[0-9]+" "$1" | tail -1; }

echo "   9a. does the Super key arrive at all -- it did not before"
printf 'warte 6\nsendkey a\nwarte 2\nsendkey meta_l-a\nwarte 3\nsendkey esc\nwarte 2\nsendkey meta_l-a\nwarte 3\n' > "$TMPD/dr-key"
if gshot "qs-key" "assets/netview/theme-dark" \
    "netvdemo nic nip=$OSUM_IP/24 ngw=$HOST_IP" "" "$TMPD/dr-key"; then
    L="$TMPD/qs-key.txt"
    has "$L" "hk: super+a" "9a: the kernel saw Super+A and wrote it down"
    has "$L" "qs: open" "9a: and the quick settings opened"
    # THE COUNTER-PROOF, and it is the half that matters. A plain `a` is
    # still a plain `a`; Super+A is NOT also a plain `a`. If the two got
    # mixed up, every opening of this panel would leave a stray letter
    # in whatever window had the focus.
    n_key=$(grep -ac '^key: a$' "$L")
    n_hk=$(grep -ac '^hk: super+a$' "$L")
    num "9a: plain 'a' still reaches the keyboard as a character" "$n_key" eq 1
    # TWO presses in this run: one to open, one to open again after
    # Escape closed it.
    num "9a: both Super+A presses became hotkeys" "$n_hk" eq 2
    num "9a: and Super+A typed NO letter (still exactly one 'key: a')" "$n_key" eq 1
    # AND IT CLOSES. Escape, which only works because the panel takes
    # the focus when it opens -- a panel the keyboard cannot get out of
    # would be worse than none.
    has "$L" "qs: closed by escape" "9a: Escape closes it again"
    num "9a: and it opened twice in one boot" "$(grep -ac '^qs: open ' "$L")" eq 2
else
    bad "9a: no screenshot of the hotkey run"
fi

echo "   9b. the panel at all four edges, laid out against the WORK AREA"
printf 'warte 5\nsendkey meta_l-a\nwarte 3\n' > "$TMPD/dr-open"
for ed in bottom top left right; do
    case $ed in bottom) EN=0 ;; top) EN=1 ;; left) EN=2 ;; right) EN=3 ;; esac
    set_edge "$ed"
    wire_up; bridge_up
    if gshot "qs-$ed" "assets/netview/theme-dark" \
        "netvdemo nic nip=$OSUM_IP/24 ngw=$HOST_IP" "ping" "$TMPD/dr-open"; then
        L="$TMPD/qs-$ed.txt"; P="$TMPD/qs-$ed.ppm"
        png "$P" "qs-$ed"
        if [ -z "$(qsk "$L")" ]; then
            bad "$ed: the panel never reported that it opened"
        else
            num "$ed: the panel reports the edge it was anchored to" \
                "$(qsf "$L" edge)" eq "$EN"
            qx=$(qsf "$L" x); qy=$(qsf "$L" y)
            qw=$(qsf "$L" w); qh=$(qsf "$L" h)
            # IT MUST NOT LIE UNDER THE BAR. The work area the server
            # reports is what is left of the screen after the strut; the
            # panel has to be inside it on every edge, and that is the
            # arithmetic a panel which assumed the screen would get
            # wrong on three edges out of four.
            wl=$(grep -aoE '^taskbar: work +x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$L" | tail -1)
            wx=$(echo "$wl" | grep -oE ' x=[0-9]+' | tr -d ' x=')
            wy=$(echo "$wl" | grep -oE ' y=[0-9]+' | tr -d ' y=')
            ww=$(echo "$wl" | grep -oE ' w=[0-9]+' | tr -d ' w=')
            wh=$(echo "$wl" | grep -oE ' h=[0-9]+' | tr -d ' h=')
            if [ -n "$wx" ] && [ -n "$qx" ]; then
                if [ "$qx" -ge "$wx" ] && [ "$qy" -ge "$wy" ] \
                   && [ $((qx + qw)) -le $((wx + ww)) ] \
                   && [ $((qy + qh)) -le $((wy + wh)) ]; then
                    ok "$ed: the panel is inside the work area ($qx,$qy ${qw}x$qh in $wx,$wy ${ww}x$wh)"
                else
                    bad "$ed: the panel at $qx,$qy ${qw}x$qh is NOT inside the work area $wx,$wy ${ww}x$wh"
                fi
            else
                bad "$ed: no work area reported"
            fi
            # AND THE LAYOUT, read back out of the picture. This is
            # the check that found the two defects the first build of
            # this panel really had -- a label four pixels past its own
            # tile, and two text rows touching. Neither is visible in a
            # source file.
            r=$(python3 tools/netview/kachel.py "$P" "$qx" "$qy" "$qw" "$qh" \
                10 180 74 8 3 28 2>&1 | tail -1)
            case "$r" in ok*) ok "$ed: the tiles hold their labels -- $r" ;;
                         *)   bad "$ed: tile layout: $r" ;; esac
            # AND THE SYMBOLS at the places the panel said it drew them,
            # pixel for pixel. A panel that reported one position and
            # painted another fails here -- the lesson of round K7B,
            # applied to a fifth thing.
            for t in 0 1 2; do
                sl=$(symln "$L" "$t")
                if [ -z "$sl" ]; then bad "$ed: tile $t reported no symbol"; continue; fi
                sx=$(echo "$sl" | grep -oE ' x=[0-9]+' | tr -d ' x=')
                sy=$(echo "$sl" | grep -oE ' y=[0-9]+' | tr -d ' y=')
                case $t in 0) dr=tile-fake ;; 1) dr=tile-net ;; 2) dr=tile-hide ;; esac
                r=$(python3 tools/netview/checkshot.py "$P" "$sx" "$sy" \
                    "assets/netview/$dr.txt" assets/netview/theme-dark 2>&1)
                case "$r" in ok*) ok "$ed: $dr stands at $sx,$sy -- $r" ;;
                             *)   bad "$ed: $dr at $sx,$sy: $r" ;; esac
            done
        fi
    else
        bad "$ed: no screenshot of the panel"
    fi
    bridge_down; wire_down
done
set_edge bottom

echo "   9c. THE NUMBER: from the key press to the panel standing"
# ONE CLOCK, BOTH ENDS. `kbd.fi` stamps CLOCK_MONOTONIC in the keyboard
# interrupt itself; `qs.fi` reads the same clock after the window stands
# and is painted, and prints the difference. Nothing in between is
# estimated, and there is no second clock to disagree with the first.
US=$(qsf "$TMPD/qs-bottom.txt" us)
UP=$(qsf "$TMPD/qs-bottom.txt" up)
if [ -n "$US" ] && [ "$US" -gt 0 ]; then
    ok "9c: key press to WINDOW STANDING: $UP us (waiting for the poll)"
    ok "9c: key press to PANEL PAINTED:   $US us"
    ok "9c: of which the drawing itself:  $((US - UP)) us"
    num "9c: and the whole of it is under a fifth of a second" "$US" lt 200000
else
    bad "9c: no time was measured (us=${US:-nothing})"
fi

echo "   9d. THE TILE REALLY SWITCHES -- online, and faking after one click"
# THE MACHINE IS GENUINELY ONLINE HERE, which is the case the sign
# exists for and the one that is hardest to fake past: the corner must
# be empty where the sign goes before the click and carry it after --
# and the marks on the running windows must not have moved, because a
# preference does not touch a running process.
wire_up; bridge_up
QX=$(qsf "$TMPD/qs-bottom.txt" x); QY=$(qsf "$TMPD/qs-bottom.txt" y)
if [ -z "$QX" ]; then QX=0; QY=0; fi
TX=$((QX + 60)); TY=$((QY + 41))
{
    echo "warte 5"
    echo "sendkey meta_l-a"
    echo "warte 2"
    # Into the corner first and then in steps under 128, for the reason
    # `tools/wm/monitor.py` writes down: a PS/2 packet carries nine bits
    # per axis, and a lost one moves the endpoint somewhere else.
    for _i in 1 2 3 4 5 6 7 8; do echo "mouse_move -120 -120"; done
    x=0; y=0
    while [ $x -lt $TX ] || [ $y -lt $TY ]; do
        dx=$(( TX - x )); [ $dx -gt 100 ] && dx=100; [ $dx -lt 0 ] && dx=0
        dy=$(( TY - y )); [ $dy -gt 100 ] && dy=100; [ $dy -lt 0 ] && dy=0
        echo "mouse_move $dx $dy"
        x=$((x + dx)); y=$((y + dy))
    done
    echo "warte 1"
    echo "mouse_button 1"
    echo "warte 1"
    echo "mouse_button 0"
    echo "warte 4"
} > "$TMPD/dr-click"
# THE PICTURE AND THE SERIAL LINE ARE TWO MEASUREMENTS, and the first
# version of this made the second depend on the first: `if gshot; then
# <everything>; else bad; fi`. When the screendump failed under load the
# runner threw away a serial log that PROVED the click had worked, and
# said only "no screenshot". So the log is read whatever the picture
# did; only the pixel check needs the picture.
gshot "qs-click" "assets/netview/theme-dark" \
    "netvdemo nic nip=$OSUM_IP/24 ngw=$HOST_IP" "ping" "$TMPD/dr-click"
SHOT_OK=$?
L="$TMPD/qs-click.txt"; P="$TMPD/qs-click.ppm"
if [ -s "$L" ]; then
    [ "$SHOT_OK" = 0 ] && png "$P" "qs-switch"
    num "9d: the machine really is online" "$(st_of "$L")" eq 3
    has "$L" "qs: tile n=0 to=1" "9d: the tile went from off to on"
    # AND THE REST OF THE SYSTEM SAW IT. The corner sign is drawn by the
    # taskbar out of a KERNEL answer and not out of anything the panel
    # told it -- so this measures the whole path at once: click, system
    # call, kernel state, taskbar poll, pixels.
    GX=$(gx_of "$L"); GY=$(gy_of "$L")
    fl=$(grep -aoE '^taskbar: faking fb=[0-9]+ x=[0-9]+ y=[0-9]+' "$L" | tail -1)
    if [ -n "$fl" ] && [ -n "$GX" ]; then
        fb=$(echo "$fl" | grep -oE 'fb=[0-9]+' | cut -d= -f2)
        fx=$(echo "$fl" | grep -oE ' x=[0-9]+' | tr -d ' x=')
        fy=$(echo "$fl" | grep -oE ' y=[0-9]+' | tr -d ' y=')
        num "9d: the taskbar now says the system is faking" "${fb:-0}" eq 2
        if [ "$SHOT_OK" = 0 ]; then
            r=$(python3 tools/netview/checkshot.py "$P" "$((fx + GX))" "$((fy + GY))" \
                assets/netview/sys-faking.txt assets/netview/theme-dark 2>&1)
            case "$r" in ok*) ok "9d: and the sign is IN THE PICTURE at $((fx+GX)),$((fy+GY)) -- $r" ;;
                         *)   bad "9d: the sign is not in the picture: $r" ;; esac
        fi
    else
        bad "9d: the bar never reported the faking sign"
    fi
    # THE COUNTER-CHECK, out of the same picture: the windows that were
    # already running kept their views. `netvdemo` starts one of each,
    # and one click on a preference may not have moved a single one.
    seen_1=0; seen_2=0; seen_3=0
    for b in 0 1 2 3 4 5 6 7 8 9; do
        line=$(grep -aE "^taskbar: btn i=$b " "$L" | tail -1)
        [ -z "$line" ] && continue
        v=$(echo "$line" | grep -oE 'netv=[0-9]+' | cut -d= -f2)
        case "${v:-0}" in
            1) seen_1=$((seen_1+1)) ;;
            2) seen_2=$((seen_2+1)) ;;
            3) seen_3=$((seen_3+1)) ;;
        esac
    done
    num "9d: the running filtered window kept its view" "$seen_1" eq 1
    num "9d: the running faked window kept its view" "$seen_2" eq 1
    num "9d: the running none window kept its view" "$seen_3" eq 1
else
    bad "9d: the machine wrote no serial log at all"
fi
bridge_down; wire_down

echo "   9e. THE CORRECTION: off is the default and stays it"
# A machine told NOTHING, anywhere: no `nvfall=` on the command line and
# no `/etc/netview.conf` in the image. This is the number Justin's
# correction is about, and it comes off a boot rather than out of a
# comment.
run_script "/bin/netview fallback;/bin/netview default /bin/nvcheck plain $HOST_IP $HTTP_PORT;exit" \
    "$TMPD/fb-plain.txt" "" nonic
D="$TMPD/fb-plain.txt"
num "9e: a machine told nothing has the preference off" "$(kv "$D" fallb)" eq 0
num "9e: so a new program gets the REAL view, not a faked one" "$(kv "$D" fbview)" eq 0
num "9e: and the program did get it" "$(nvc "$D" plain view)" eq 0
has "$D" "netview: fallback off" "9e: and it says so in words"

echo "   9f. the switch has two positions, and neither of them is when-offline"
wire_up; bridge_up; server_up
run_script "/bin/netview fallback on;/bin/cat /etc/netview.conf;/bin/netview default /bin/nvcheck sw1 $HOST_IP $HTTP_PORT;/bin/netview fallback off;/bin/netview default /bin/nvcheck sw2 $HOST_IP $HTTP_PORT;exit" \
    "$TMPD/fb-sw.txt"
server_down; bridge_down; wire_down
E="$TMPD/fb-sw.txt"
has "$E" "netview: fallback always" "9f: 'on' is a spelling of 'always', not a fourth value"
has "$E" "fallback=always" "9f: and the file keeps ONE spelling per value"
hasnot "$E" "when-offline" "9f: the switch never lands on when-offline by itself"
num "9f: with the switch ON a new program is faked" "$(nvc "$E" sw1 view)" eq 2
num "9f: and it reads the invented 204"             "$(nvc "$E" sw1 status)" eq 204
num "9f: with the switch OFF it is real again"      "$(nvc "$E" sw2 view)" eq 0
num "9f: and really reached the python server"      "$(nvc "$E" sw2 status)" eq 200

echo "   9g. the network tile: the address really goes and really comes back"
# NOT THE VIEW OF THE NETWORK -- THE NETWORK. `netview <view>` cannot do
# this and is not supposed to; this is the second tile, and what it does
# is take the machine's address off it. Measured through exactly the two
# calls the tile makes (`nv.net_off`, `nv.net_on`).
wire_up; bridge_up; server_up
run_script "/bin/nvcheck pre $HOST_IP $HTTP_PORT;/bin/netview netoff;/bin/nvcheck gone $HOST_IP $HTTP_PORT;/bin/netview neton $OSUM_IP/24 $HOST_IP;/bin/nvcheck back $HOST_IP $HTTP_PORT;exit" \
    "$TMPD/net-off.txt"
server_down; bridge_down; wire_down
G="$TMPD/net-off.txt"
num "9g: before -- the real page arrives" "$(nvc "$G" pre status)" eq 200
c=$(nvc "$G" gone conn)
if [ -n "$c" ] && [ "$c" != 0 ]; then
    ok "9g: with the address gone, connect FAILS: $c"
else
    bad "9g: connect returned ${c:-nothing} with no address -- it had to fail"
fi
num "9g: and nothing was loaded"                 "$(nvc "$G" gone body)" eq 0
num "9g: afterwards the same page arrives again" "$(nvc "$G" back status)" eq 200
num "9g: with the same 46 octets"                "$(nvc "$G" back body)" eq 46

echo "NETVIEW: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
