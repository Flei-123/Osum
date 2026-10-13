#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/unterbau/run.sh -- what does a big Linux program (Firefox, LibreOffice) need under the hood, and what does OrientOS give it?
#
#   /root/jarvis/bin/heavy bash tools/unterbau/run.sh            # every test, new kernel, prints a table + gates
#   ONLY="t_mem t_dl" bash tools/unterbau/run.sh                 # a subset
#   KEEP=1 UB_OUT=/some/dir bash tools/unterbau/run.sh           # keep the serial logs
#   OLDKERNEL=1 ...                                              # also run the counter-proofs on the kernel of $OLDREF
#
# Every test is a small real C program (musl, dynamic, like Firefox: PT_INTERP + libc.so) that prints lines
#   T <test>.<check> PASS|FAIL|GAP <detail>
# One boot per test (a crash or a hang in one test must not hide the others). The table is the "Lueckenliste" of
# docs/RUNDE-UNTERBAU-FIREFOX.md; accept.txt lists the checks that must PASS (the gate); fixed.txt lists the checks that
# were fixed in this round: on the kernel of $OLDREF they must NOT pass (the counter-proof that the check measures something).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
HERE=tools/unterbau
OLDREF=${OLDREF:-553ef06c}
D=${UB_OUT:-$(mktemp -d)}
mkdir -p "$D"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$*"; }
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
SMP=${SMP:-1}
TMO=${TMO:-150}
export FIRNLIB="$ROOT/lib"

for t in musl-gcc "$QEMU" python3; do command -v "$t" >/dev/null 2>&1 || { echo "UNTERBAU: $t missing, skipped"; exit 0; }; done
LDSO=${LDSO:-/lib/ld-musl-x86_64.so.1}
LDREAL=$(readlink -f "$LDSO" 2>/dev/null || true)
[ -r "$LDREAL" ] || LDREAL=/usr/lib/x86_64-linux-musl/libc.so
[ -r "$LDREAL" ] || { echo "UNTERBAU: no musl libc.so, skipped"; exit 0; }

echo "== 0. text constants of the kernel files this round touched (firnc1 aborts SILENTLY on one that is too long) =="
python3 - kernel/fs/procfs.fi kernel/sys/sys.fi kernel/sched/proc.fi kernel/sched/signal.fi kernel/sched/sched.fi > "$D/texte.txt" 2>&1 <<'PY'
import re, sys
bad = n = 0
for p in sys.argv[1:]:
    s = open(p, 'rb').read().decode('utf-8', errors='surrogateescape')
    for m in re.finditer(r'var (\w+): \[u8; (\d+)\] = "((?:[^"\\]|\\.)*)"', s):
        real = m.group(3).replace('\\0', '\0').replace('\\n', '\n').replace('\\\\', '\\')
        n += 1
        if int(m.group(2)) != len(real):
            bad += 1; print("WRONG %s %s: field %s, text %d" % (p, m.group(1), m.group(2), len(real)))
print("CHECKED %d WRONG %d" % (n, bad))
PY
if grep -q 'WRONG 0$' "$D/texte.txt"; then ok "$(grep -o 'CHECKED [0-9]*' "$D/texte.txt") text constants, all as long as their field"; else bad "a text constant does not fit its field"; sed 's/^/        /' "$D/texte.txt"; fi

echo "== 1. build the test programs (musl, dynamic) =="
mkdir -p "$D/bin" "$D/lib"
TESTS=""
for src in $HERE/t_*.c; do
    n=$(basename "$src" .c)
    if [ -n "${ONLY:-}" ] && ! echo " $ONLY " | grep -q " $n "; then continue; fi
    if musl-gcc -O1 -g0 -pthread -Wno-unused-result -o "$D/bin/$n" "$src" -I$HERE -ldl -lrt 2> "$D/cc-$n.err"; then TESTS="$TESTS $n"; else bad "$n does not build"; head -5 "$D/cc-$n.err" | sed 's/^/        /'; fi
done
for l in libub1 libub2 libub3; do
    extra=""; [ $l = libub2 ] && extra="-L$D/lib -lub1"
    musl-gcc -O1 -shared -fPIC -o "$D/lib/$l.so" $HERE/$l.c $extra 2> "$D/cc-$l.err" || { bad "$l does not build"; cat "$D/cc-$l.err" | head -3; }
done
# the child programs the tests start
for c in $HERE/c_*.c; do [ -e "$c" ] || continue; musl-gcc -O1 -pthread -o "$D/bin/$(basename $c .c)" "$c" 2>> "$D/cc-child.err" || bad "$(basename $c) does not build"; done
# the STATIC programs of the earlier rounds (tools/foreign: the way a musl binary ran on Osum before there was a dynamic loader) -- a regression gate
FOREIGN=""
for f in hello threads forktest locktest; do
    if musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none -o "$D/bin/f_$f" tools/foreign/start.s tools/foreign/osum_main.c tools/foreign/$f.c 2> "$D/cc-f_$f.err"; then FOREIGN="$FOREIGN f_$f"; else bad "f_$f does not build"; head -3 "$D/cc-f_$f.err" | sed 's/^/        /'; fi
done
ok "tests:$TESTS  foreign:$FOREIGN"

build_kernel() { # build_kernel <srcdir> <out.mb>
    ( cd "$1" && bash tools/build-kernel.sh "$2" --stufe 1 ) > "$2.log" 2>&1
}
build_image() { # build_image <srcdir> <outdir>   (user programs of the system + our tests)
    local S=$1 O=$2
    mkdir -p "$O/p"
    as --64 -o "$O/crt.o" "$S/kernel/user/crt.s" || return 1
    local progs="sh ls cat echo"
    for p in $progs; do
        "$S/vendor/firn/bin/firnc1" "$S/kernel/user/$p.fi" -o "$O/p/$p.o" > "$O/p/$p.log" 2>&1 || return 1
        ld -T "$S/kernel/user/user.ld" --defsym=USER_ENTRY="_F1.u_start" -o "$O/p/$p.elf" "$O/crt.o" "$O/p/$p.o" 2>>"$O/p/$p.log" || return 1
        strip --strip-all "$O/p/$p.elf" 2>/dev/null
    done
    local spec="/lib/ /bin/ /tmp/ /etc/ /var/ /var/tmp/ /dev/ /proc/ /sys/ /mnt/ /root/ /run/ /w/"
    for p in $progs; do [ -n "${BBSH:-}" ] && [ "$p" = sh ] && continue; spec="$spec /bin/$p=$O/p/$p.elf"; done
    spec="$spec /lib/ld-musl-x86_64.so.1=$LDREAL"
    # the proof stone busybox (dynamic, musl): as /bin/busybox, and with BBSH=1 ALSO as /bin/sh (system() and popen() call /bin/sh -c)
    if [ -r "${BBDYN:-/nonexistent}" ]; then
        spec="$spec /bin/busybox=$BBDYN /etc/bb.sh=$D/bb.sh /etc/pruef.txt=$D/pruef.txt"
        [ -n "${BBSH:-}" ] && spec="$spec /bin/sh=$BBDYN"
    fi
    for f in "$D"/bin/*; do spec="$spec /bin/$(basename $f)=$f"; done
    for f in "$D"/lib/*.so; do spec="$spec /lib/$(basename $f)=$f"; done
    printf 'root:x:0:0:root:/root:/bin/sh\n' > "$D/passwd"; printf '127.0.0.1 localhost\n' > "$D/hosts"
    spec="$spec /etc/passwd=$D/passwd /etc/hosts=$D/hosts"
    # the files and directories a Linux package set puts under /etc and /usr/share (not kernel business; the real image
    # builder tools/usbimg/build.sh does not ship them yet -- roadmap): stat() by name is what the checks measure.
    printf 'nameserver 10.0.2.3\n' > "$D/resolv.conf"; printf '0123456789abcdef0123456789abcdef\n' > "$D/machine-id"
    printf '<?xml version="1.0"?>\n<fontconfig></fontconfig>\n' > "$D/fonts.conf"; printf 'UTC\n' > "$D/localtime"
    spec="$spec /etc/ssl/ /etc/ssl/certs/ /etc/fonts/ /usr/ /usr/lib/ /usr/share/ /usr/share/fonts/ /usr/share/zoneinfo/"
    spec="$spec /etc/resolv.conf=$D/resolv.conf /etc/machine-id=$D/machine-id /etc/fonts/fonts.conf=$D/fonts.conf /etc/localtime=$D/localtime"
    spec="$spec ${EXTRA_SPEC:-}"
    python3 "$S/tools/osum/mkfs.py" build "$O/disk.img" ${UB_BLOCKS:-98304} --v3 --inodes=1024 $spec > "$O/mkfs.txt" 2>&1
}
boot() { # boot <kernel> <disk> <script> <serial-out>
    cp -f "$2" "$2.live"
    timeout "$TMO" $QEMU "${KVM[@]}" -smp "$SMP" -kernel "$1" -m 512 \
        -append "osum vfs nokbd nosched noproc nofs ${KARGS:-} script=$3;exit" -serial "file:$4" -display none -no-reboot \
        ${NETARGS:-} -drive "file=$2.live,format=raw,if=ide,index=0" -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    local rc=$?; rm -f "$2.live"; return $rc
}
run_all() { # run_all <kernel> <disk> <tag>
    for t in $TESTS; do
        boot "$1" "$2" "/bin/$t" "$D/$3-$t.ser"; rc=$?
        grep -a '^T ' "$D/$3-$t.ser" 2>/dev/null | awk '!seen[$2]++' > "$D/$3-$t.res" || : > "$D/$3-$t.res"
        printf '        %-12s %3d checks   (qemu rc=%s)\n' "$t" "$(wc -l < "$D/$3-$t.res")" "$rc"
    done
    cat "$D"/$3-t_*.res 2>/dev/null | sed 's/^T //' > "$D/$3.all"
}

# the busybox probe script (lines "BB <name> ..." are read back from the serial log)
BBDYN=${BBDYN:-/root/bbdyn/busybox}
# the proof stones live in /root/stones (rebuild: tools/unterbau/build-stones.sh /root/stones); STONES= (empty) switches them off. They run with the network stage by default (STONES_NET=0 switches that off).
STONES=${STONES-/root/stones}; [ -r "$STONES/python3" ] || STONES=""
STONES_NET=${STONES_NET-1}; [ "$STONES_NET" = 0 ] && STONES_NET=""
printf 'eins\nzwei\ndrei\n' > "$D/pruef.txt"
cat > "$D/bb.sh" <<'BBS'
echo "BB echo ok"
x=$(echo sub); [ "$x" = sub ] && echo "BB cmdsubst ok" || echo "BB cmdsubst FAIL"
echo "BB arith $(/bin/busybox expr 6 \* 7)"
echo "BB pipe $(echo a b c | /bin/busybox wc -w)"
echo "BB forloop $(for i in 1 2 3; do printf %s $i; done)"
/bin/busybox sh -c 'echo "BB nested-sh ok"'
(exit 3); echo "BB exitstatus $?"
echo "BB grep $(/bin/busybox grep -c zwei /etc/pruef.txt)"
echo "BB sort $(/bin/busybox sort -r /etc/pruef.txt | /bin/busybox head -1)"
/bin/busybox mkdir /tmp/bbd && /bin/busybox touch /tmp/bbd/f && echo "BB mkdir-touch $(/bin/busybox ls /tmp/bbd)"
echo hello > /tmp/bbd/g; echo "BB redirect $(/bin/busybox cat /tmp/bbd/g)"
echo "BB awk $(/bin/busybox awk 'BEGIN{print 1+2}')"
echo "BB sed $(echo abc | /bin/busybox sed 's/b/X/')"
echo "BB sha256 $(/bin/busybox sha256sum /etc/pruef.txt | /bin/busybox cut -c1-12)"
echo "BB loadavg $(/bin/busybox cut -d' ' -f1 /proc/loadavg)"
echo "BB uptime-cmd $(/bin/busybox uptime >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB df-cmd $(/bin/busybox df /tmp >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB free-cmd $(/bin/busybox free >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB ps-cmd $(/bin/busybox ps >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB date-cmd $(/bin/busybox date >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB head-n $(printf 'a\nb\nc\n' | /bin/busybox head -n 2 | /bin/busybox wc -l)"
echo "BB tail $(/bin/busybox tail -n 1 /etc/pruef.txt)"
echo "BB tr $(echo abc | /bin/busybox tr a-z A-Z)"
echo "BB find $(/bin/busybox find /tmp/bbd -type f | /bin/busybox wc -l)"
echo "BB xargs $(echo 1 2 3 | /bin/busybox xargs -n1 echo | /bin/busybox wc -l)"
/bin/busybox cp /etc/pruef.txt /tmp/p2 && /bin/busybox mv /tmp/p2 /tmp/p3 && /bin/busybox cmp /etc/pruef.txt /tmp/p3 && /bin/busybox rm /tmp/p3 && echo "BB cp-mv-rm ok"
/bin/busybox ln -s /etc/pruef.txt /tmp/lnk 2>/dev/null; echo "BB symlink $(/bin/busybox cat /tmp/lnk 2>/dev/null | /bin/busybox wc -l)"
/bin/busybox chmod 600 /tmp/bbd/g; echo "BB chmod-stat $(/bin/busybox stat -c %a /tmp/bbd/g 2>/dev/null)"
echo "BB id $(/bin/busybox id -u)"
echo "BB uname $(/bin/busybox uname -s >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB hostname $(/bin/busybox hostname >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB pwd $(cd /tmp && /bin/busybox pwd)"
/bin/busybox tar cf /tmp/t.tar /etc/pruef.txt 2>/dev/null; echo "BB tar $(/bin/busybox tar tf /tmp/t.tar 2>/dev/null)"
echo "BB gzip $(/bin/busybox gzip -c /etc/pruef.txt | /bin/busybox gunzip | /bin/busybox wc -l)"
echo "BB diff $(/bin/busybox diff /etc/pruef.txt /etc/pruef.txt >/dev/null && echo same)"
echo "BB seq $(/bin/busybox seq 1 5 | /bin/busybox tail -n 1)"
echo "BB dd $(/bin/busybox dd if=/dev/zero bs=1k count=4 2>/dev/null | /bin/busybox wc -c)"
echo "BB sort-uniq $(printf '2\n1\n2\n' | /bin/busybox sort -n | /bin/busybox uniq -c | /bin/busybox wc -l)"
echo "BB date-fmt $(/bin/busybox date +%Y | /bin/busybox wc -c)"
echo "BB mktemp $(/bin/busybox mktemp /tmp/xXXXXXX >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB realpath $(/bin/busybox realpath /tmp/../etc/pruef.txt 2>/dev/null)"
echo "BB ash-func $(f() { echo $(($1 * 2)); }; f 21)"
echo "BB heredoc $(/bin/busybox cat <<EOT
hd
EOT
)"
echo "BB sed-i $(echo x > /tmp/si; /bin/busybox sed -i 's/x/y/' /tmp/si; /bin/busybox cat /tmp/si)"
echo "BB sleep $(/bin/busybox sleep 1 && echo ok)"
echo "BB bg-wait $(/bin/busybox sleep 1 & p=$!; wait $p; echo ok)"
echo "BB kill $(/bin/busybox sleep 30 & p=$!; /bin/busybox kill $p; wait $p 2>/dev/null; echo done)"
echo "BB mounts $(/bin/busybox cat /proc/mounts >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB mount-cmd $(/bin/busybox mount >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB ip-cmd $(/bin/busybox ip addr >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB ifconfig-cmd $(/bin/busybox ifconfig -a >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB ip-addr $(/bin/busybox ip -4 addr 2>&1 | /bin/busybox grep -c 'inet 10.0.2.15/24 brd 10.0.2.255 scope global eth0')"
echo "BB ip-link $(/bin/busybox ip link 2>&1 | /bin/busybox grep -c '^1: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>')"
echo "BB ip-route $(/bin/busybox ip route 2>&1 | /bin/busybox grep -c -e '^default via 10.0.2.2 dev eth0' -e '^10.0.2.0/24 dev eth0')"
echo "BB top-cmd $(/bin/busybox top -b -n 1 >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB lsof-cmd $(/bin/busybox timeout 5 /bin/busybox ps -o pid,comm >/dev/null 2>&1 && echo ok || echo FAIL)"
echo "BB end"
BBS
[ -n "${BBSCRIPT:-}" ] && cp "$BBSCRIPT" "$D/bb.sh"
echo "== 2. the kernel of this tree and its image =="
KNEW=${KERNEL:-$D/k-new.mb}
if [ -z "${KERNEL:-}" ]; then build_kernel "$ROOT" "$KNEW" && ok "kernel built" || { bad "kernel does not build"; tail -8 "$KNEW.log"; echo "UNTERBAU: $pass passed, $fail failed"; exit 1; }; fi
build_image "$ROOT" "$D/new" && ok "image built" || { bad "image does not build"; echo "UNTERBAU: $pass passed, $fail failed"; exit 1; }

echo "== 3. run the tests on this kernel =="
run_all "$KNEW" "$D/new/disk.img" new
cp "$D/new.all" "${UB_RESULT:-$D/results.txt}" 2>/dev/null
if [ -z "${ONLY:-}" ] || echo " $ONLY " | grep -q " foreign "; then
    echo "== 3b. the static foreign programs of the earlier rounds still run =="
    fchk() { # fchk <name> <pattern that must be there> [pattern that must NOT be there]
        local n=$1; boot "$KNEW" "$D/new/disk.img" "/bin/f_$n" "$D/f_$n.ser"
        if grep -aq -- "$2" "$D/f_$n.ser" && { [ -z "${3:-}" ] || ! grep -aq -- "$3" "$D/f_$n.ser"; }; then ok "foreign $n: $2"; else bad "foreign $n: expected '$2' not found${3:+ or found '$3'}"; grep -a "^th:\|^fork:\|^lk:\|hallo\|vector\|fault" "$D/f_$n.ser" | head -5 | sed 's/^/        /'; fi
    }
    case " $FOREIGN " in *" f_hello "*) fchk hello "^hallo" ;; esac
    case " $FOREIGN " in *" f_threads "*) fchk threads "th: summe=100000 erwartet=100000 OK" "FALSCH" ;; esac
    case " $FOREIGN " in *" f_forktest "*) fchk forktest "exited=1 code=7" "FEHLER" ;; esac
    case " $FOREIGN " in *" f_locktest "*) fchk locktest "lk: fertig" "FALSCH" ;; esac
fi
if [ -r "$BBDYN" ] && { [ -z "${ONLY:-}" ] || echo " $ONLY " | grep -q " busybox "; }; then
    echo "== 3c. proof stone busybox (dynamic musl, $(stat -c%s "$BBDYN") octets): applets + /bin/sh -c =="
    # with the virtio card: `ifconfig -a` lists the interfaces of /proc/net/dev
    KARGS="nic nip=10.0.2.15/24 ngw=10.0.2.2" NETARGS="-netdev user,id=n0 -device virtio-net-pci,netdev=n0" boot "$KNEW" "$D/new/disk.img" "busybox sh /etc/bb.sh" "$D/bb.ser"
    # a kernel trace line (acpiev) can end without a newline just before a probe line: take the probe from the middle of the line
    grep -a -o 'BB [A-Za-z0-9_-]\+ .*\|BB end' "$D/bb.ser" | tr -d '\r' > "$D/bb.res" || : > "$D/bb.res"
    SHA12=$(sha256sum "$D/pruef.txt" | cut -c1-12)
    BBOK=0; BBBAD=0
    bbchk() { # bbchk <name> <expected text>
        local line; line=$(grep -a "^BB $1 " "$D/bb.res" | head -1 | tr -d '\r')
        if [ "$line" = "BB $1 $2" ]; then BBOK=$((BBOK+1)); printf '        BB-OK   %s\n' "$1"; else BBBAD=$((BBBAD+1)); printf '        BB-GAP  %s  (got: %s)\n' "$1" "${line:-nothing}"; fi
    }
    bbchk echo ok; bbchk cmdsubst ok; bbchk arith 42; bbchk pipe 3; bbchk forloop 123; bbchk nested-sh ok; bbchk exitstatus 3
    bbchk grep 1; bbchk sort zwei; bbchk mkdir-touch f; bbchk redirect hello; bbchk awk 3; bbchk sed aXc; bbchk sha256 "$SHA12"
    bbchk loadavg 0.00; bbchk uptime-cmd ok; bbchk df-cmd ok; bbchk free-cmd ok; bbchk ps-cmd ok; bbchk date-cmd ok
    bbchk head-n 2; bbchk tail drei; bbchk tr ABC; bbchk find 2; bbchk xargs 3; bbchk cp-mv-rm ok; bbchk symlink 3; bbchk chmod-stat 600; bbchk id 0
    bbchk uname ok; bbchk hostname ok; bbchk pwd /tmp; bbchk tar etc/pruef.txt; bbchk gzip 3; bbchk diff same; bbchk seq 5; bbchk dd 4096; bbchk sort-uniq 2
    bbchk date-fmt 5; bbchk mktemp ok; bbchk realpath /etc/pruef.txt; bbchk ash-func 42; bbchk heredoc hd; bbchk sed-i y; bbchk sleep ok; bbchk bg-wait ok; bbchk kill done
    bbchk mounts ok; bbchk mount-cmd ok; bbchk ip-cmd ok; bbchk ip-addr 1; bbchk ip-link 1; bbchk ip-route 2; bbchk ifconfig-cmd ok; bbchk top-cmd ok; bbchk lsof-cmd ok
    grep -aq '^BB end' "$D/bb.res" && ok "busybox sh ran its script to the end" || bad "busybox sh did not reach the end of its script"
    # with busybox as /bin/sh: system() and popen() of t_proc
    case " $TESTS " in *" t_proc "*)
        BBSH=1 build_image "$ROOT" "$D/bbsh" && {
            boot "$KNEW" "$D/bbsh/disk.img" "/bin/t_proc" "$D/bbsh-t_proc.ser"
            grep -a '^T ' "$D/bbsh-t_proc.ser" | awk '!seen[$2]++' > "$D/bbsh-t_proc.res"
            for c in proc.system_exit_status proc.popen; do
                grep -a "^T $c " "$D/bbsh-t_proc.res" | head -1 | sed 's/^T /        BB-SH   /'
            done
        } ;;
    esac
    echo "        busybox probes: $BBOK ok / $BBBAD gap"
    # since r696 (AF_NETLINK, NETLINK_ROUTE): `ip` works too -> no known gap left
    [ "$BBBAD" -le "${BBGAP_MAX:-0}" ] && ok "busybox probes: $BBOK ok, $BBBAD gap (<= ${BBGAP_MAX:-0} known)" || bad "busybox probes: $BBBAD gaps (> ${BBGAP_MAX:-0} known)"
    cp "$D/bb.res" "${UB_BB_RESULT:-$D/bb-result.txt}" 2>/dev/null
fi

# 3d. the next proof stones: python3 (musl, dynamic, stdlib as one zip), curl (static libcurl), git (zlib) -- only when STONES points at them
#   STONES=<dir> with: python3, lib/python312.zip, lib/ext/*.so (extension modules for lib-dynload), curl, git (each optional)
if [ -n "${STONES:-}" ] && [ -r "$BBDYN" ] && { [ -z "${ONLY:-}" ] || echo " $ONLY " | grep -q " stones "; }; then
    echo "== 3d. proof stones python3 / curl / git (from $STONES) =="
    # python lives in /usr/bin and its stdlib in /usr/lib (getpath walks up from the executable dir and never tests "/" itself when the
    # executable is directly in /bin -> that needed PYTHONHOME=/ before r698); stones.sh links /bin/python3 -> /usr/bin/python3
    SX="/usr/bin/ /usr/lib/python3.12/ /usr/lib/python3.12/lib-dynload/ /w/"
    [ -r "$STONES/python3" ] && SX="$SX /usr/bin/python3=$STONES/python3 /usr/lib/python312.zip=$STONES/lib/python312.zip"
    [ -r "$STONES/lib/os.pyc" ] && SX="$SX /usr/lib/python3.12/os.pyc=$STONES/lib/os.pyc"   # landmark: getpath finds the prefix by it
    for so in "$STONES"/lib/ext/*.so; do [ -e "$so" ] && SX="$SX /usr/lib/python3.12/lib-dynload/$(basename "$so")=$so"; done
    [ -r "$STONES/curl" ] && SX="$SX /bin/curl=$STONES/curl"
    [ -r "$STONES/git" ] && SX="$SX /bin/git=$STONES/git /share/ /share/git-core/ /share/git-core/templates/"   # empty template dir: no "templates not found" warning
    cp "${STSCRIPT:-$HERE/stones.sh}" "$D/st.sh"
    # host port of the throw-away web server: a free one (two gate runs at once must not collide); the script names the default 18765
    STPORT=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])' 2>/dev/null || echo 18765)
    sed -i "s/18765/$STPORT/g" "$D/st.sh"
    # TLS stone (r697): a throw-away CA/server cert for 10.0.2.2 (the host as seen from the guest); the guest trusts it only via /etc/tls-ca.pem
    TLSPORT=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])' 2>/dev/null || echo 18766)
    sed -i "s/18766/$TLSPORT/g" "$D/st.sh"
    TLS_OK=""
    if [ -n "${STONES_NET:-}" ] && command -v openssl >/dev/null 2>&1 \
       && openssl req -x509 -newkey rsa:2048 -nodes -keyout "$D/tls-key.pem" -out "$D/tls-ca.pem" -days 30 -subj "/CN=10.0.2.2" \
            -addext "subjectAltName=IP:10.0.2.2" >/dev/null 2>&1; then
        TLS_OK=1; SX="$SX /etc/tls-ca.pem=$D/tls-ca.pem"
    fi
    SX="$SX /etc/st.sh=$D/st.sh"
    EXTRA_SPEC="$SX" UB_BLOCKS=${UB_BLOCKS:-262144} build_image "$ROOT" "$D/stone" && {
        # STONES_NET=1: virtio-net with QEMU user networking; the guest reaches a throw-away http server of the host at 10.0.2.2
        NETPID=""
        if [ -n "${STONES_NET:-}" ]; then
            mkdir -p "$D/www"; echo "hello-net" > "$D/www/h.txt"
            python3 -I -m http.server "$STPORT" --bind 127.0.0.1 --directory "$D/www" > "$D/www.log" 2>&1 &
            NETPID=$!
            TLSPID=""
            if [ -n "$TLS_OK" ]; then
                python3 -I "$HERE/tlssrv.py" "$TLSPORT" "$D/tls-ca.pem" "$D/tls-key.pem" "$D/www" > "$D/tls.log" 2>&1 &
                TLSPID=$!
            fi
            NETARGS="-netdev user,id=n0 -device virtio-net-pci,netdev=n0"
        fi
        TMO="${STONES_TMO:-420}" KARGS="${STONES_NET:+nic nip=10.0.2.15/24 ngw=10.0.2.2} ${STONES_KARGS:-}" NETARGS="${NETARGS:-}" boot "$KNEW" "$D/stone/disk.img" "busybox sh /etc/st.sh" "$D/st.ser"
        [ -z "$NETPID" ] || kill "$NETPID" 2>/dev/null
        [ -z "${TLSPID:-}" ] || kill "$TLSPID" 2>/dev/null
        grep -a -o -E 'ST [A-Za-z0-9_-]+( .*)?$' "$D/st.ser" | tr -d '\r' | awk '!seen[$2]++' > "$D/st.res" || : > "$D/st.res"
        STOK=0; STBAD=0
        stchk() { # stchk <name> <expected text>
            local line; line=$(grep -a "^ST $1 " "$D/st.res" | head -1)
            if [ "$line" = "ST $1 $2" ]; then STOK=$((STOK+1)); printf '        ST-OK   %s\n' "$1"; else STBAD=$((STBAD+1)); printf '        ST-GAP  %s  (got: %s)\n' "$1" "${line:-nothing}"; fi
        }
        while read -r n v; do case "$n" in ''|'#'*) continue ;; nettls-*) [ -n "${TLS_OK:-}" ] || continue ;; net-*) [ -n "${STONES_NET:-}" ] || continue ;; esac; stchk "$n" "$v"; done < "$HERE/stones.expect"
        grep -aq '^ST end' "$D/st.res" && ok "stones script ran to the end" || bad "stones script did not reach its end"
        echo "        stones probes: $STOK ok / $STBAD gap"
        [ "$STBAD" -le "${STGAP_MAX:-0}" ] && ok "stones probes: $STOK ok, $STBAD gap" || bad "stones probes: $STBAD gaps (> ${STGAP_MAX:-0})"
        cp "$D/st.res" "${UB_ST_RESULT:-$D/st-result.txt}" 2>/dev/null
        [ -z "${KEEP:-}" ] || cp "$D/st.ser" "$D/st.ser.keep"   # NOT `[ -n ] && cp`: a false test would make the whole &&-group fail and fire the "image does not build" branch
    } || bad "stone image does not build"
fi
echo "== 4. the table =="
awk '{ split($1, a, "."); v[$2]++; t[a[1]]++ } END { for (k in t) ; for (k in v) printf "        count %s=%d\n", k, v[k] }' "$D/new.all" | sort
grep -a -E ' (FAIL|GAP) ' "$D/new.all" | sed 's/^/        /' | head -${SHOWMAX:-200}

echo "== 5. gate: the checks that must pass (accept.txt) =="
[ -n "${REGEN:-}" ] && echo "        (REGEN: the lists are written below from this run and the old-kernel run, not checked)"
while [ -z "${REGEN:-}" ] && read -r name; do
    case "$name" in ''|'#'*) continue ;; esac
    t=${name%%.*}; case " $TESTS " in *" t_$t "*) ;; *) continue ;; esac
    line=$(grep -a "^$name " "$D/new.all" | head -1)
    case "$line" in *" PASS"*) ok "$name" ;; *) bad "$name  ->  ${line:-no line (crash or hang?)}" ;; esac
done < "$HERE/accept.txt"

if [ -n "${OLDKERNEL:-}" ] || [ -n "${OLDK:-}" ]; then
    echo "== 6. counter-proof: the same tests on the kernel from before this round ($OLDREF) must NOT pass the fixed checks (fixed.txt) =="
    KOLD=${OLDK:-}
    [ -z "$KOLD" ] || [ -s "$KOLD" ] || { bad "OLDK=$KOLD is not a kernel file"; KOLD=""; }
    if [ -z "$KOLD" ] && [ -z "${OLDK:-}" ]; then
        WT=$D/oldsrc
        git -C "$ROOT" worktree add --detach "$WT" "$OLDREF" > /dev/null 2>&1 || bad "cannot check out $OLDREF"
        if [ -d "$WT" ]; then
            build_kernel "$WT" "$D/k-old.mb" && ok "old kernel built" || { bad "old kernel does not build"; tail -5 "$D/k-old.mb.log"; }
            KOLD=$D/k-old.mb
            git -C "$ROOT" worktree remove --force "$WT" > /dev/null 2>&1
        fi
    fi
    if [ -s "${KOLD:-/nonexistent}" ]; then
        TESTS_SAVE=$TESTS
        # only the tests that hold fixed checks
        if [ -n "${REGEN:-}" ]; then TESTS=$TESTS_SAVE; else TESTS=""; for t in $TESTS_SAVE; do grep -q "^${t#t_}\." "$HERE/fixed.txt" && TESTS="$TESTS $t"; done; fi
        run_all "$KOLD" "$D/new/disk.img" old
        while [ -z "${REGEN:-}" ] && read -r name; do
            case "$name" in ''|'#'*) continue ;; esac
            t=${name%%.*}; case " $TESTS " in *" t_$t "*) ;; *) continue ;; esac
            line=$(grep -a "^$name " "$D/old.all" | head -1)
            case "$line" in *" PASS"*) bad "counter-proof: $name PASSES on the old kernel -- the check measures nothing" ;; *) ok "counter-proof: $name does not pass on the old kernel (${line:-no line})" ;; esac
        done < "$HERE/fixed.txt"
        cp "$D/old.all" "${UB_OLD_RESULT:-$D/results-old.txt}" 2>/dev/null
        if [ -n "${REGEN:-}" ]; then python3 "$HERE/mkgate.py" "$D/old.all" "$D/new.all" "$HERE" && ok "accept.txt and fixed.txt written"; fi
    fi
fi
echo
echo "UNTERBAU: $pass passed, $fail failed"
[ "$fail" = 0 ]
