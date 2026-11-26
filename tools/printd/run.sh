#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/printd/run.sh -- print spooler, printer registry, mDNS finder, job options.
# Printer side: CUPS ippeveprinter in a network namespace (like tools/print/run.sh);
# DNS-SD side: tools/printd/responder.py answers _ipp._tcp queries.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/brand-env.sh
ROOT=$(pwd)

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "${2:-}" = "$3" ]; then ok "$1: $2"; else bad "$1: '${2:-}', expected '$3'"; fi; }
kv() { grep -aoE "^printd: $2 = .*" "$1" 2>/dev/null | tail -1 | sed 's/^printd: [a-z_]* = //' | tr -d '\r'; }
has() { if grep -aqF -- "$3" "$2"; then ok "$1"; else bad "$1 (missing: $3)"; fi; }
lacks() { if grep -aqF -- "$3" "$2"; then bad "$1 (found: $3)"; else ok "$1"; fi; }

for t in qemu-system-x86_64 python3 ip ippeveprinter; do
    command -v "$t" >/dev/null 2>&1 || { echo "PRINTD: skipped, $t missing"; exit 0; }
done

TMPD=$(mktemp -d)
NS=pd-$$
V0=pd0-$$
V1=pd1
BPORT=$(( 16600 + ($$ % 300) * 2 ))
QPORT=$(( BPORT + 1 ))
BRPID=""
PIDS=""
cleanup() {
    for p in $PIDS; do kill "$p" 2>/dev/null; done
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns pids "$NS" 2>/dev/null | xargs -r kill 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

. tools/lib/firnenv.sh

echo "== 1. programs build =="
for prog in ipprint printd; do
    if FIRNLIB="$ROOT/lib" "$FIRNC" -c --profile=app -o "$TMPD/$prog.o" kernel/app/$prog.fi > "$TMPD/cc-$prog.log" 2>&1; then
        ok "firnc --profile=app: $prog.fi"
    else
        bad "$prog.fi does not compile"; head -20 "$TMPD/cc-$prog.log" | sed 's/^/        /'
        echo "PRINTD: $pass passed, $fail failed"; exit 1
    fi
    undef=$(nm -u "$TMPD/$prog.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
    [ -z "$undef" ] && ok "$prog: no undefined symbol" || bad "$prog undefined: $undef"
    ld -T kernel/user/user.ld -o "$TMPD/$prog.elf" "$TMPD/$prog.o" 2>"$TMPD/ld-$prog.err" \
        && ok "$prog: ld" || { bad "$prog: ld fails"; head -3 "$TMPD/ld-$prog.err"; }
    strip --strip-all "$TMPD/$prog.elf" 2>/dev/null
done

HWNET_PROGS="sh ls cat echo" bash tools/hwnet/build.sh "$TMPD/s0" 0 > "$TMPD/b0.txt" 2>&1 \
    || { bad "kernel build"; tail -8 "$TMPD/b0.txt" | sed 's/^/        /'
         echo "PRINTD: $pass passed, $fail failed"; exit 1; }
ok "kernel and userland built"
K="$TMPD/s0/k.mb"
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c"

printf 'Short letter to grandma\n' > "$TMPD/kurz.txt"
printf 'Line one\nLine two\n' > "$TMPD/probe.txt"
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
printf 'Testdrucker=ipp://10.9.0.1:8631/ipp/print\ndefault=Testdrucker\n' > "$TMPD/printers.conf"

mkimg() { # <image> [printers.conf]
    local extra=()
    [ -n "${2:-}" ] && extra=("/etc/printers.conf=$2")
    bash tools/mkfsfi/mkfs.sh build "$1" 16384 \
        /bin/ /etc/ /lib/ /doc/ \
        "/bin/sh=$TMPD/s0/sh.elf" "/bin/ls=$TMPD/s0/ls.elf" \
        "/bin/cat=$TMPD/s0/cat.elf" "/bin/echo=$TMPD/s0/echo.elf" \
        "/bin/ipprint=$TMPD/ipprint.elf" "/bin/printd=$TMPD/printd.elf" \
        "/lib/mono.ttf=$ROOT/assets/osum-mono.ttf" \
        "/lib/sans.ttf=$ROOT/assets/osum-sans.ttf" \
        "/etc/passwd=$TMPD/passwd" "${extra[@]}" \
        "/doc/kurz.txt=$TMPD/kurz.txt" "/doc/probe.txt=$TMPD/probe.txt" \
        > "$TMPD/mkfs.txt" 2>&1
}
mkimg "$TMPD/a.img" "$TMPD/printers.conf" && ok "image with printers.conf" || { bad "mkfs a"; echo "PRINTD: $pass passed, $fail failed"; exit 1; }
mkimg "$TMPD/b.img" "" && ok "image without printers.conf" || { bad "mkfs b"; echo "PRINTD: $pass passed, $fail failed"; exit 1; }

ip netns del "$NS" 2>/dev/null
ip netns add "$NS" 2>/dev/null || { echo "PRINTD: skipped, no network namespaces"; exit 0; }
ip link add "$V0" type veth peer name "$V1"
ip link set "$V1" netns "$NS"
ip netns exec "$NS" ip addr add 10.9.0.1/24 dev "$V1"
ip netns exec "$NS" ip link set "$V1" up
ip netns exec "$NS" ip link set lo up
ip link set "$V0" up
ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
"$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!

mkdir -p "$TMPD/sp1" "$TMPD/sp2"
cat > "$TMPD/a4.conf" <<'CONF'
ATTR keyword media-default iso_a4_210x297mm
ATTR keyword media-supported iso_a4_210x297mm,na_letter_8.5x11in
ATTR mimeMediaType document-format-supported image/pwg-raster,application/pdf
ATTR resolution pwg-raster-document-resolution-supported 300dpi,600dpi
ATTR keyword pwg-raster-document-type-supported black_1,sgray_8
CONF
ip netns exec "$NS" ippeveprinter -r off -p 8631 -a "$TMPD/a4.conf" -vvv \
    -k -d "$TMPD/sp1" "Testdrucker" > "$TMPD/p1.log" 2>&1 & PIDS="$PIDS $!"
ip netns exec "$NS" ippeveprinter -r off -p 8632 -f application/pdf \
    -k -d "$TMPD/sp2" "Nurpdf" > "$TMPD/p2.log" 2>&1 & PIDS="$PIDS $!"
sleep 2

lauf() { # <image> <script> <out>
    local to=240; [ -e /dev/kvm ] || to=600
    local kvm=""; [ -e /dev/kvm ] && kvm="-enable-kvm"
    timeout $to qemu-system-x86_64 -kernel "$K" -m 512 $kvm \
        -append "osum nokbd nosched noproc nofs nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0 script=$2;exit" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$1,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cd" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

echo "== 2. queue, options, cancel, serve =="
lauf "$TMPD/a.img" "printd printers;printd submit - /doc/kurz.txt --copies 3 --color mono --media iso_a4_210x297mm;printd submit - /doc/probe.txt;printd cancel 2;printd list;printd serve --once;printd list;printd status 1;printd status 2;printd status 9" "$TMPD/o_a.txt"
has "registry lists the printer" "$TMPD/o_a.txt" "printd: printer = Testdrucker=ipp://10.9.0.1:8631/ipp/print"
is "printers counted" "$(kv "$TMPD/o_a.txt" printers)" "1"
has "job 1 queued" "$TMPD/o_a.txt" "printd: job = 1"
has "job 2 submitted" "$TMPD/o_a.txt" "printd: job = 2"
has "cancel of job 2" "$TMPD/o_a.txt" "printd: state = canceled"
has "list before serve: job 1 queued" "$TMPD/o_a.txt" "printd: job = 1 queued ipp://10.9.0.1:8631/ipp/print kurz.txt"
has "list before serve: job 2 canceled" "$TMPD/o_a.txt" "printd: job = 2 canceled ipp://10.9.0.1:8631/ipp/print probe.txt"
has "list after serve: job 1 done" "$TMPD/o_a.txt" "printd: job = 1 done ipp://10.9.0.1:8631/ipp/print kurz.txt"
is "serve ran exactly one job" "$(kv "$TMPD/o_a.txt" ran)" "1"
has "status 1 done rc 0" "$TMPD/o_a.txt" "printd: rc = 0"
has "status of an unknown job" "$TMPD/o_a.txt" "printd: state = nojob"
NF=$(ls "$TMPD/sp1"/*.pwg 2>/dev/null | wc -l)
is "printer spooled one file (the canceled job never left)" "$NF" "1"
grep -aE "copies|print-color-mode|media " "$TMPD/p1.log" | head -6 | sed 's/^/        /'
has "printer saw copies=3" "$TMPD/p1.log" "copies"
has "printer saw monochrome" "$TMPD/p1.log" "monochrome"

echo "== 3. refusals and registry edits =="
lauf "$TMPD/a.img" "printd submit - /doc/kurz.txt --copies 0;printd submit - /doc/kurz.txt --pages 3-1;printd submit nosuch /doc/kurz.txt;printd submit - /doc/missing.txt;printd add pdfonly ipp://10.9.0.1:8632/ipp/print;printd default pdfonly;printd printers;printd submit - /doc/kurz.txt;printd serve --once;printd status 3;printd list;printd remove pdfonly;printd remove pdfonly;printd printers" "$TMPD/o_b.txt"
is "bad copies refused" "$(grep -ac 'printd: state = options' "$TMPD/o_b.txt")" "2"
has "unknown printer refused" "$TMPD/o_b.txt" "printd: state = noprinter"
has "missing file refused" "$TMPD/o_b.txt" "printd: state = nofile"
has "default switched to pdfonly and used" "$TMPD/o_b.txt" "printd: printer = pdfonly=ipp://10.9.0.1:8632/ipp/print"
has "job to the PDF-only printer failed" "$TMPD/o_b.txt" "printd: state = failed"
is "failure code 7 (format refused)" "$(kv "$TMPD/o_b.txt" rc)" "7"
has "spool state persists across boots (job 1 of the first boot)" "$TMPD/o_b.txt" "printd: job = 1 done ipp://10.9.0.1:8631/ipp/print kurz.txt"
NF2=$(ls "$TMPD/sp2"/* 2>/dev/null | wc -l)
is "no job reached the PDF-only printer" "$NF2" "0"
has "second remove reports unknown printer" "$TMPD/o_b.txt" "printd: state = noprinter"

echo "== 4. DNS-SD finder =="
ip netns exec "$NS" python3 tools/printd/responder.py 10.9.0.1 8631 "Findbar" "ipp/print" > "$TMPD/resp.log" 2>&1 & PIDS="$PIDS $!"
sleep 1
lauf "$TMPD/b.img" "printd find --add;printd printers;printd default Findbar;printd submit - /doc/kurz.txt;printd serve --once;printd status 1" "$TMPD/o_c.txt"
has "responder saw the query" "$TMPD/resp.log" "query from 10.9.0.2"
has "printd found the printer" "$TMPD/o_c.txt" "printd: found = Findbar=ipp://10.9.0.1:8631/ipp/print"
is "count" "$(kv "$TMPD/o_c.txt" count)" "1"
has "registered by find --add" "$TMPD/o_c.txt" "printd: printer = Findbar=ipp://10.9.0.1:8631/ipp/print"
has "job to the found printer done" "$TMPD/o_c.txt" "printd: state = done"
kill $(echo "$PIDS" | awk '{print $NF}') 2>/dev/null
sleep 1
lauf "$TMPD/b.img" "printd find;printd printers" "$TMPD/o_d.txt"
is "control: without a responder nothing is found" "$(kv "$TMPD/o_d.txt" count)" "0"
lacks "control: nothing registered" "$TMPD/o_d.txt" "printd: found ="

echo "PRINTD: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
