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
    for p in $progs; do spec="$spec /bin/$p=$O/p/$p.elf"; done
    spec="$spec /lib/ld-musl-x86_64.so.1=$LDREAL"
    for f in "$D"/bin/*; do spec="$spec /bin/$(basename $f)=$f"; done
    for f in "$D"/lib/*.so; do spec="$spec /lib/$(basename $f)=$f"; done
    printf 'root:x:0:0:root:/root:/bin/sh\n' > "$D/passwd"; printf '127.0.0.1 localhost\n' > "$D/hosts"
    spec="$spec /etc/passwd=$D/passwd /etc/hosts=$D/hosts"
    python3 "$S/tools/osum/mkfs.py" build "$O/disk.img" 98304 --v3 --inodes=1024 $spec > "$O/mkfs.txt" 2>&1
}
boot() { # boot <kernel> <disk> <script> <serial-out>
    cp -f "$2" "$2.live"
    timeout "$TMO" $QEMU "${KVM[@]}" -smp "$SMP" -kernel "$1" -m 512 \
        -append "osum vfs nokbd nosched noproc nofs script=$3;exit" -serial "file:$4" -display none -no-reboot \
        -drive "file=$2.live,format=raw,if=ide,index=0" -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
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
echo "== 4. the table =="
awk '{ split($1, a, "."); v[$2]++; t[a[1]]++ } END { for (k in t) ; for (k in v) printf "        %-5s %d\n", k, v[k] }' "$D/new.all" | sort
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
    if [ -z "$KOLD" ]; then
        WT=$D/oldsrc
        git -C "$ROOT" worktree add --detach "$WT" "$OLDREF" > /dev/null 2>&1 || bad "cannot check out $OLDREF"
        if [ -d "$WT" ]; then
            build_kernel "$WT" "$D/k-old.mb" && ok "old kernel built" || { bad "old kernel does not build"; tail -5 "$D/k-old.mb.log"; }
            KOLD=$D/k-old.mb
            git -C "$ROOT" worktree remove --force "$WT" > /dev/null 2>&1
        fi
    fi
    if [ -s "$KOLD" ]; then
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
