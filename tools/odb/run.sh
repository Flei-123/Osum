#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/odb/run.sh -- gate for the ODB debug agent (kernel/user/odbd.fi) driven by the REAL host client
# (tools/odbc), over a QEMU chardev socket on COM2 (docs/ODB.md).
#
# Fast image like tools/sshd/run.sh: kernel + a handful of programs + mkfs.py disk, inittab starts odbd.
# What is proven (each with a control):
#   1. hello/auth + info          control: wrong token is refused (exit 4), no token is refused
#   2. exec (stdout, exit code)   control: unknown program -> nonzero
#   3. push/pull (sha256 + crc)   control: host-side sha256 of the pulled file equals the original
#   4. ps / kill                  control: pid gone after kill
#   5. logs
#   6. reboot, agent comes back
#   7. agent off                  image without the inittab line / conf enable=0: no answer
#   8. latency / throughput numbers (tools/odbc/bench.py against the real odbd)
#
#   bash tools/odb/run.sh                  all of it
#   ODB_KEEP=<dir> bash tools/odb/run.sh   keep the build (kernel, programs) in <dir> for reuse
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/marke-env.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh ls cat echo id whoami sleep wc true false seq svc init ps kill reboot shutdown cp rm mkdir mount odbd"
BLOCKS=8192
ODBC="python3 -I $ROOT/tools/odbc/odbc.py"

TMPD=$(mktemp -d)
QPID=""
cleanup() {
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1: '$2', expected '$3'"; fi; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc missing"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "ODB: skipped, no qemu"; exit 0; }
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm"; else ACCEL="-accel tcg"; fi

# ---------------------------------------------------------------- build
B=${ODB_KEEP:-$TMPD/b}
mkdir -p "$B"
echo "== 1. build: kernel + $(echo $PROGS | wc -w) programs =="
as --64 -o "$B/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
if [ ! -f "$B/k0.mb" ]; then
    ./tools/build-kernel.sh "$B/k0.mb" --stufe 0 >"$B/e" 2>&1 \
        || { bad "kernel does not compile"; tail -8 "$B/e"; echo "ODB: $pass passed, $fail failed"; exit 1; }
fi
for p in $PROGS; do
    [ -f "$B/$p.elf" ] && continue
    "$FIRNC" "kernel/user/$p.fi" -o "$B/$p.o" >"$B/e$p" 2>&1 \
        || { bad "$p.fi does not compile"; head -6 "$B/e$p" | sed 's/^/        /'; echo "ODB: $pass passed, $fail failed"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$B/$p.elf" "$B/crt.o" "$B/$p.o" 2>/dev/null || { bad "ld $p"; exit 1; }
    strip --strip-all "$B/$p.elf"
done
ok "built (kernel $(stat -c%s "$B/k0.mb") octets, odbd $(stat -c%s "$B/odbd.elf") octets)"

# ---------------------------------------------------------------- images
TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
BADTOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
printf '%s' "$TOKEN" > "$TMPD/token"
printf '%s' "$BADTOKEN" > "$TMPD/badtoken"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'odbd:respawn:/sbin/odbd\nvic:respawn:/bin/victim 300\nende:ctrl:/bin/sleep 600\n' > "$TMPD/inittab_on"
printf 'ende:ctrl:/bin/sleep 600\n' > "$TMPD/inittab_off"
printf 'enable=1\n' > "$TMPD/conf_on"
printf 'none /dev devfs\nnone /proc proc\n' > "$TMPD/fstab"
head -c 300000 /dev/urandom > "$TMPD/blob.bin"
BLOBSUM=$(sha256sum "$TMPD/blob.bin" | cut -d' ' -f1)
printf 'line one\nline two\n' > "$TMPD/data.txt"

SPEC=""
for p in $PROGS; do
    case $p in
        init) SPEC="$SPEC /sbin/init=$B/$p.elf@755:0:0" ;;
        odbd) SPEC="$SPEC /sbin/odbd=$B/$p.elf@755:0:0" ;;
        *)    SPEC="$SPEC /bin/$p=$B/$p.elf" ;;
    esac
done
SPEC="$SPEC /bin/victim=$B/sleep.elf"
DIRS="/bin/ /sbin/ /etc/ /dev/ /proc/ /run/@755:0:0 /d/ /tmp/@777:0:0 /var/ /var/crash/"
mkimg() { # out inittab [extra spec...]
    local out=$1 it=$2; shift 2
    python3 tools/osum/mkfs.py build "$out" $BLOCKS $DIRS $SPEC \
        /etc/passwd=$TMPD/passwd@644:0:0 /etc/inittab=$it@644:0:0 \
        /etc/fstab=$TMPD/fstab@644:0:0 /etc/odb.token=$TMPD/token@600:0:0 ${NOCONF:-/etc/odb.conf=$TMPD/conf_on@644:0:0} \
        /d/data.txt=$TMPD/data.txt@644:0:0 "$@" >"$TMPD/mkfs.txt" 2>&1 \
        || { bad "mkfs.py failed"; sed 's/^/        /' "$TMPD/mkfs.txt" | head -5; return 1; }
}
mkimg "$TMPD/on.img" "$TMPD/inittab_on" && mkimg "$TMPD/off.img" "$TMPD/inittab_off" && NOCONF=" " mkimg "$TMPD/noconf.img" "$TMPD/inittab_on" || { echo "ODB: $pass passed, $fail failed"; exit 1; }
ok "images: agent on / agent off"

# ---------------------------------------------------------------- qemu
SOCK="$TMPD/odb.sock"
start_qemu() { # image comlog [extra qemu args]
    local img=$1 log=$2; shift 2
    rm -f "$SOCK"
    timeout 1200 qemu-system-x86_64 $ACCEL -kernel "$B/k0.mb" -m 512 -smp 2 \
        -append "${APPEND:-osum vfs nokbd}" -display none "$@" \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -serial "file:$log" \
        -chardev "socket,id=odb,path=$SOCK,server=on,wait=off" -serial chardev:odb \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    QPID=$!
    local i=0
    while [ $i -lt 50 ] && [ ! -S "$SOCK" ]; do sleep 0.1; i=$((i+1)); done
    [ -S "$SOCK" ]
}
stop_qemu() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; QPID=""; }
od() { timeout "${ODB_T:-60}" $ODBC --port "unix:$SOCK" --token-file "$TMPD/token" "$@"; }

echo "== 2. boot, hello/auth, info ($ACCEL) =="
cp "$TMPD/on.img" "$TMPD/live.img"
T0=$(date +%s%N)
start_qemu "$TMPD/live.img" "$TMPD/com1.log" || { bad "qemu did not start"; exit 1; }
if ODB_T=90 od wait 80 >"$TMPD/wait.txt" 2>&1; then
    ok "agent answers after $(( ($(date +%s%N)-T0)/1000000 )) ms"
else
    bad "agent did not answer"; head -5 "$TMPD/wait.txt"; tr -d '\000' < "$TMPD/com1.log" | tail -15 | sed 's/^/        /'
    echo "ODB: $pass passed, $fail failed"; exit 1
fi
if [ -n "${ODB_HOLD:-}" ]; then   # dev mode: keep the guest up for manual odbc sessions
    echo "HOLD: odbc --port unix:$SOCK --token-file $TMPD/token ... (${ODB_HOLD}s)"
    echo "unix:$SOCK $TMPD/token" > "$B/hold.txt"; cp "$TMPD/token" "$B/hold.token"
    sleep "$ODB_HOLD"; exit 0
fi
od info >"$TMPD/info.txt" 2>&1; rc=$?
is "info exit code" "$rc" "0"
grep -qi "${MARKE_PRODUKT}\|osum" "$TMPD/info.txt" && ok "info names the os" || { bad "info: no os name"; head -8 "$TMPD/info.txt"; }
note "$(head -6 "$TMPD/info.txt" | tr '\n' ' ')"
ncpu=$(sed -n 's/^cpus=//p' "$TMPD/info.txt" | head -1)
# The fast image boots with `-kernel` and no firmware tables: CS_COUNT ("cores the firmware reported") is 0 there. The desktop image
# (kgui autostart) reports the real count (QEMU 2, VBox 3); only the field itself is required here.
[ -n "${ncpu:-}" ] && ok "info has cpus ($ncpu; 0 = no firmware tables in the fast image)" || bad "info: no cpus field"
[ "$(grep -c '^idle_core=' "$TMPD/info.txt")" = "${ncpu:-0}" ] && ok "info idle_core line per cpu" || bad "info idle_core lines != cpus"
grep -q '^idle_pct=' "$TMPD/info.txt" && ok "info has idle_pct" || bad "info: no idle_pct"
grep -q '^uart_overruns=[0-9]' "$TMPD/info.txt" && ok "info has uart_overruns ($(sed -n 's/^uart_overruns=//p' "$TMPD/info.txt"))" || bad "info: no uart_overruns"
out=$(od exec cat /proc/odb 2>&1); case "$out" in *"odb=0"*"rx_overruns="*) ok "/proc/odb without odb=1: odb=0 + rx_overruns";; *) bad "/proc/odb: $out";; esac
$ODBC --port "unix:$SOCK" --token-file "$TMPD/badtoken" info >/dev/null 2>&1; is "wrong token refused (exit)" "$?" "4"
$ODBC --port "unix:$SOCK" info >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "no token refused (exit $rc)" || bad "no token accepted"
od info >/dev/null 2>&1; is "right token still works after refusals" "$?" "0"

echo "== 3. exec =="
out=$(od exec echo hello odb 2>&1); is "exec echo" "$out" "hello odb"
od exec /bin/false >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "false -> exit $rc" || bad "false returned 0"
out=$(od exec 'exit 7' 2>&1); rc=$?; is "exit code 7 passes through" "$rc" "7"
od exec /bin/nonexistent-prog >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "unknown program -> exit $rc" || bad "unknown program returned 0"
out=$(od exec cat /d/data.txt 2>&1); is "cat data file" "$(echo "$out" | head -1)" "line one"
out=$(od exec --argv /bin/echo a b c 2>&1); is "exec --argv (no shell)" "$out" "a b c"
out=$(od exec --argv cat /d/data.txt 2>&1); is "exec --argv bare name -> /bin/" "$(echo "$out" | head -1)" "line one"
od exec --argv /bin/nonexistent-prog >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "exec --argv unknown program -> exit $rc" || bad "exec --argv unknown program returned 0"

echo "== 3b. shell (pty) =="
cat > "$TMPD/shellcase.py" <<'PYEOF'
import sys, time
sys.path.insert(0, sys.argv[1])
from odb import frame as F, proto
from odb.client import Session, read_token_file
sock, token = sys.argv[2], sys.argv[3]
s = Session.open("unix:" + sock, token=read_token_file(token))
s.login(timeout=10)
print("F", s.hello_info.get("features"))
def run(name, items, send, timeout=30):
    out = bytearray()
    def on_frame(f):
        if f.type == F.DATA:
            st, b = proto.dec_data(f.payload)
            if st == proto.STDOUT:
                out.extend(b)
    def start(fid):
        send(fid)
    try:
        r = s.request("shell", items, on_frame=on_frame, on_start=start, timeout=timeout)
        return out, r, None
    except proto.AgentError as e:
        return out, None, e.code
# 1. interactive: type commands, read them back, exit code passes through
def talk(fid):
    time.sleep(1.0)
    s.send_stream(fid, proto.STDIN, b"echo pty-hello-one\n")
    time.sleep(1.0)
    s.send_stream(fid, proto.STDIN, b"exit 5\n")
out, r, err = run("talk", {"cols": 100, "rows": 30}, talk)
print("T1", err, r.geti("exit", -1) if r else None, b"pty-hello-one" in out, len(out))
# 2. cmd= runs a script under the pty
out, r, err = run("cmd", {"cmd": "echo scripted-ok; exit 4"}, lambda fid: None)
print("T2", err, r.geti("exit", -1) if r else None, b"scripted-ok" in out)
# 3. resize while the shell runs: RESP ok=1, the shell is alive afterwards
state = {}
def rs(fid):
    time.sleep(1.0)
    state["rid"] = s.send_resize(120, 40)
    time.sleep(1.5)
    s.send_stream(fid, proto.STDIN, b"echo after-resize\n")
    time.sleep(1.0)
    s.send_stream(fid, proto.STDIN, b"exit 0\n")
out, r, err = run("resize", {}, rs)
resp = [f for f in s.stray if f.id == state.get("rid") and f.type == F.RESP]
print("T3", err, len(resp), b"after-resize" in out)
# 4. cancel: ERR ECANCEL, and the agent takes the next request
def cn(fid):
    time.sleep(1.0)
    s.cancel(fid)
out, r, err = run("cancel", {}, cn)
print("T4", err)
r = s.request("exec", {"cmd": "echo alive-after"}, timeout=20)
print("T5", r.geti("exit", -1))
# 5. END(stdin) = ^D ends an idle shell
def eof(fid):
    time.sleep(1.0)
    s.end_stream(fid, proto.STDIN)
out, r, err = run("eof", {}, eof)
print("T6", err, r.geti("exit", -1) if r else None)
s.close()
PYEOF
ODB_T=180 timeout 180 python3 -I "$TMPD/shellcase.py" "$ROOT/tools/odbc" "$SOCK" "$TMPD/token" >"$TMPD/shell.txt" 2>&1
grep -q '^T1 None 5 True' "$TMPD/shell.txt" && ok "shell: typed echo comes back, exit 5 passes through" || { bad "shell interactive"; head -12 "$TMPD/shell.txt"; }
grep -q '^T2 None 4 True' "$TMPD/shell.txt" && ok "shell cmd= script runs under the pty (exit 4)" || bad "shell cmd="
grep -q '^T3 None 1 True' "$TMPD/shell.txt" && ok "shell resize answered, shell alive after" || bad "shell resize"
grep -q '^T4 ECANCEL' "$TMPD/shell.txt" && ok "shell cancel -> ECANCEL" || bad "shell cancel"
grep -q '^T5 0' "$TMPD/shell.txt" && ok "agent serves exec after a cancelled shell" || bad "agent stuck after shell cancel"
grep -q '^T6 None' "$TMPD/shell.txt" && ok "END(stdin) ends the shell (^D)" || bad "shell eof"
note "$(tr '\n' ' ' < "$TMPD/shell.txt" | cut -c1-200)"
grep -q '^F .*shell' "$TMPD/shell.txt" && ok "hello features list shell" || bad "features lack shell"

echo "== 4. push / pull =="
od push "$TMPD/blob.bin" /tmp/blob.bin >"$TMPD/push.txt" 2>&1; is "push exit" "$?" "0"
note "$(tail -1 "$TMPD/push.txt")"
od pull /tmp/blob.bin "$TMPD/back.bin" >"$TMPD/pull.txt" 2>&1; is "pull exit" "$?" "0"
note "$(tail -1 "$TMPD/pull.txt")"
is "pulled sha256 == original" "$(sha256sum "$TMPD/back.bin" 2>/dev/null | cut -d' ' -f1)" "$BLOBSUM"

# hello window == maxchunk: one frame in flight (VBox uart2 has no flow control)
HELLO=$(python3 -I - "$ROOT/tools/odbc" "$SOCK" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
from odb.client import Session
s = Session.open("unix:" + sys.argv[2])
h = s.hello()
print(h.geti("maxchunk"), h.geti("window"))
s.close()
PYEOF
)
set -- $HELLO
[ -n "${1:-}" ] && [ "${1:-0}" = "${2:-1}" ] && ok "hello window == maxchunk ($1/$2)" || bad "hello window '$2' != maxchunk '$1'"
# small pulls: END goes out right behind the last data frame, no resend wait (was ~1 s per resend, hung on VBox)
for sz in 1 100 8192 8193 20000; do
    head -c $sz /dev/urandom > "$TMPD/small.bin"
    od push "$TMPD/small.bin" /tmp/small.bin >/dev/null 2>&1
    T0=$(date +%s%N)
    od pull /tmp/small.bin "$TMPD/small.back" >"$TMPD/smallpull.txt" 2>&1; rc=$?
    MS=$(( ($(date +%s%N)-T0)/1000000 ))
    if [ $rc = 0 ] && cmp -s "$TMPD/small.bin" "$TMPD/small.back"; then ok "pull $sz octets identical (${MS} ms)"; else bad "pull $sz octets (exit $rc)"; fi
    [ "$MS" -lt 6000 ] && ok "pull $sz octets within 6 s (no END stall)" || bad "pull $sz octets took ${MS} ms"
done
rewinds=$(grep -o '[0-9]* rewinds' "$TMPD/pull.txt" | grep -o '^[0-9]*' | head -1)
[ "${rewinds:-0}" = "0" ] && ok "300 kB pull: 0 rewinds" || bad "300 kB pull: ${rewinds} rewinds"

echo "== 5. ps / kill =="
# Victim: /bin/victim (a copy of sleep, respawned by init). NOT the `ende` sleep: when that one dies, init shuts the guest down.
od ps >"$TMPD/ps.txt" 2>&1; is "ps exit" "$?" "0"
PID=$(awk '/victim/ {print $1; exit}' "$TMPD/ps.txt")
if [ -n "$PID" ]; then
    ok "victim visible in ps (pid $PID)"
    od kill "$PID" >/dev/null 2>&1; is "kill exit" "$?" "0"
    sleep 1
    od ps 2>&1 | awk -v p="$PID" '$1==p' | grep -q victim && bad "pid $PID still there" || ok "pid $PID gone"
else
    bad "no victim in ps"; head -12 "$TMPD/ps.txt" | sed 's/^/        /'
fi

echo "== 6. logs =="
out=$(od logs -n 20 2>&1); rc=$?
is "logs exit" "$rc" "0"
[ -n "$out" ] && ok "logs not empty ($(echo "$out" | wc -l) lines)" || bad "logs empty"

echo "== 7. numbers (bench.py against the real odbd) =="
timeout 150 python3 -I tools/odbc/bench.py --port "unix:$SOCK" --token-file "$TMPD/token" --mib 0.25 >"$TMPD/bench.txt" 2>&1 \
    && ok "bench ran" || bad "bench failed"
tail -8 "$TMPD/bench.txt" | sed 's/^/        /'

echo "== 7b. idle cost (agent asleep between polls) =="
sleep 5   # 3 s of quiet put the agent into slow polling
QREAL=$(pgrep -P "$QPID" | head -1); [ -n "$QREAL" ] || QREAL=$QPID
cpu_ticks() { awk '{print $14+$15}' "/proc/$QREAL/stat" 2>/dev/null; }
C0=$(cpu_ticks); sleep 5; C1=$(cpu_ticks)
PCT=$(( (C1 - C0) * 100 / 500 ))   # ticks are 1/100 s; 5 s window -> percent of one host core
note "qemu used ${PCT}% of a host core while idle (before: ~100+ with the busy loop)"
[ "$PCT" -le 60 ] && ok "idle agent is off the CPU (${PCT}% of one core, limit 60)" || bad "idle agent burns ${PCT}% of a core"
od info >/dev/null 2>&1; is "agent answers after the idle phase (wake preamble)" "$?" "0"

echo "== 7c. shot / input / crashdump =="
# shot pattern=1: the agent's own test image (no screen needed); decoded on the host (zlib + unfilter) and compared pixel by pixel
od shot "$TMPD/pat100.png" --pattern --scale 100 >"$TMPD/shot.txt" 2>&1; is "shot pattern scale=100 exit" "$?" "0"
note "$(tail -1 "$TMPD/shot.txt")"
python3 -I tools/odb/pngcheck.py "$TMPD/pat100.png" 320 200 >"$TMPD/pc.txt" 2>&1; rc=$?
is "shot 320x200 pixel-exact" "$rc" "0"; [ "$rc" = 0 ] || sed 's/^/        /' "$TMPD/pc.txt"
od shot "$TMPD/pat.png" --pattern >/dev/null 2>&1; is "shot default scale exit" "$?" "0"
python3 -I tools/odb/pngcheck.py "$TMPD/pat.png" 160 100 >"$TMPD/pc.txt" 2>&1; rc=$?
is "shot default scale = 50 -> 160x100 pixel-exact" "$rc" "0"; [ "$rc" = 0 ] || sed 's/^/        /' "$TMPD/pc.txt"
od shot "$TMPD/pat25.png" --pattern --scale 25 >/dev/null 2>&1
python3 -I tools/odb/pngcheck.py "$TMPD/pat25.png" 80 50 >"$TMPD/pc.txt" 2>&1; is "shot scale=25 -> 80x50 pixel-exact" "$?" "0"
od shot "$TMPD/patq.png" --pattern --scale 100 --quant 3 >"$TMPD/shotq.txt" 2>&1; is "shot --quant 3 exit" "$?" "0"
python3 -I tools/odb/pngcheck.py "$TMPD/patq.png" 320 200 3 >"$TMPD/pc.txt" 2>&1; rc=$?
is "shot --quant 3: pixels == test image with 3 low bits dropped" "$rc" "0"; [ "$rc" = 0 ] || sed 's/^/        /' "$TMPD/pc.txt"
python3 -I tools/odb/pngcheck.py "$TMPD/patq.png" 320 200 >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "quant control: dropped bits are really gone (lossless check fails)" || bad "quant 3 image equals the lossless one"
[ "$(stat -c %s "$TMPD/patq.png")" -lt "$(stat -c %s "$TMPD/pat100.png")" ] && ok "quant 3 PNG smaller ($(stat -c %s "$TMPD/patq.png") < $(stat -c %s "$TMPD/pat100.png") bytes)" || bad "quant 3 PNG not smaller"
od shot "$TMPD/x.ppm" --pattern --format ppm >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "shot ppm refused (exit $rc)" || bad "shot ppm accepted"
printf 'garbage' > "$TMPD/junk.png"; python3 -I tools/odb/pngcheck.py "$TMPD/junk.png" 320 200 >/dev/null 2>&1; is "pngcheck control: junk rejected" "$?" "2"
python3 -I - "$TMPD/pat100.png" "$TMPD/pat_bad.png" <<'PYEOF'
import sys, zlib, struct
d = bytearray(open(sys.argv[1], "rb").read())
d[-30] ^= 1   # flip a byte inside the IDAT data; CRC check must catch it
open(sys.argv[2], "wb").write(d)
PYEOF
python3 -I tools/odb/pngcheck.py "$TMPD/pat_bad.png" 320 200 >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "pngcheck control: damaged PNG rejected (exit $rc)" || bad "pngcheck accepted a damaged PNG"
out=$(od input key a 2>&1); rc=$?; is "input key exit" "$rc" "0"; case "$out" in "ok n="[1-9]*) ok "input key: $out";; *) bad "input key: '$out'";; esac
out=$(od input text "hello 42" --delay-ms 1 2>&1); rc=$?; is "input text exit" "$rc" "0"; case "$out" in "ok n="[1-9]*) ok "input text: $out";; *) bad "input text: '$out'";; esac
out=$(od input text "ab" 2>&1); rc=$?; is "input text without delay exit" "$rc" "0"; case "$out" in "ok n="[1-9]*) ok "input text (no delay_ms): $out";; *) bad "input text (no delay_ms): '$out'";; esac
for lay in de us uk; do
    out=$(od input text 'yz<>|@\~' --layout $lay --delay-ms 1 2>&1); rc=$?; is "input text layout=$lay exit" "$rc" "0"
    case "$out" in "ok n="[1-9]*) ok "input text layout=$lay: $out";; *) bad "input text layout=$lay: '$out'";; esac
done
od input text "a" --layout xx >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "input text unknown layout refused (exit $rc)" || bad "input text layout=xx accepted"
out=$(od input key enter --mods ctrl 2>&1); is "input key with modifier exit" "$?" "0"
out=$(od input mouse 100 50 --button left --action click 2>&1); rc=$?; is "input mouse click exit" "$rc" "0"; case "$out" in "ok n="[1-9]*) ok "input mouse: $out";; *) bad "input mouse: '$out'";; esac
od input key nosuchkey >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "input unknown key refused (exit $rc)" || bad "input unknown key accepted"
od input scroll 3 >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "input scroll refused as unsupported (exit $rc)" || bad "input scroll accepted"
printf 'panic: test dump\nsecond line\n' > "$TMPD/crash.txt"
od crash list >"$TMPD/cl.txt" 2>&1; is "crash list (empty) exit" "$?" "0"
[ -z "$(tr -d ' \n' < "$TMPD/cl.txt")" ] && ok "crash list empty before the dump" || bad "crash list not empty: $(head -2 "$TMPD/cl.txt")"
od push "$TMPD/crash.txt" /var/crash/1760000000.txt >/dev/null 2>&1; is "push crash file exit" "$?" "0"
od crash list >"$TMPD/cl.txt" 2>&1; is "crash list exit" "$?" "0"
grep -q '^1760000000.txt 29 1760000000 panic: test dump' "$TMPD/cl.txt" && ok "crash list line: id size time summary" || { bad "crash list line"; sed 's/^/        /' "$TMPD/cl.txt" | head -3; }
od crash get 1760000000.txt "$TMPD/crash.back" >/dev/null 2>&1; is "crash get exit" "$?" "0"
cmp -s "$TMPD/crash.txt" "$TMPD/crash.back" && ok "crash get content identical" || bad "crash get content differs"
od crash get nosuch.txt "$TMPD/none" >/dev/null 2>&1; rc=$?; [ "$rc" != 0 ] && ok "crash get unknown id refused (exit $rc)" || bad "crash get unknown id returned 0"
od crash clear 1760000000.txt >/dev/null 2>&1; is "crash clear exit" "$?" "0"
od crash list 2>&1 | grep -q 1760000000 && bad "crash dump still listed after clear" || ok "crash dump gone after clear"

echo "== 8. reboot =="
ODB_T=30 od reboot >/dev/null 2>&1; note "reboot exit $?"
sleep 3
if ODB_T=90 od wait 80 >/dev/null 2>&1; then ok "agent back after guest reboot"; else bad "agent not back after guest reboot"; fi
stop_qemu

echo "== 9. agent off =="
cp "$TMPD/off.img" "$TMPD/live.img"
start_qemu "$TMPD/live.img" "$TMPD/com1c.log" || bad "qemu (off)"
ODB_T=25 od wait 15 >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "image without odbd: no answer (exit $rc)" || bad "answer from an image without odbd"
stop_qemu

echo "== 9b. odb=1 on the kernel command line (no /etc/odb.conf) =="
cp "$TMPD/noconf.img" "$TMPD/live.img"
start_qemu "$TMPD/live.img" "$TMPD/com1d.log" || bad "qemu (noconf, no odb=1)"
ODB_T=25 od wait 15 >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "no conf file, no odb=1: no agent (exit $rc)" || bad "agent answered without conf and without odb=1"
stop_qemu
cp "$TMPD/noconf.img" "$TMPD/live.img"
APPEND="osum vfs nokbd odb=1" start_qemu "$TMPD/live.img" "$TMPD/com1e.log" || bad "qemu (noconf, odb=1)"
if ODB_T=60 od wait 40 >/dev/null 2>&1; then
    ok "odb=1 without conf file: agent answers"
    out=$(od exec cat /proc/odb 2>&1); case "$out" in *"odb=1"*) ok "/proc/odb says odb=1";; *) bad "/proc/odb: $out";; esac
else
    bad "odb=1 without conf file: no answer"
fi
stop_qemu

echo "ODB: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
