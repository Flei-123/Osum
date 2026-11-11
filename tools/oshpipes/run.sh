#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS="sh cat echo head wc sort grep uniq seq tr tee true false sleep"
BLOCKS=16384
CASE_TIMEOUT=${CASE_TIMEOUT:-120}
MUTANT_TIMEOUT=${MUTANT_TIMEOUT:-40}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc is missing: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "OSHPIPES: skipped, qemu-system-x86_64 is not available"
    exit 0
fi

run_kernel() {
    local limit=$1 image=$2 append=$3 out=$4
    shift 4
    timeout "$limit" $QEMU_X86 -kernel "$image" -m 128 -append "$append execlog" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

run_case() {
    local limit=$1 kernel=$2 image=$3 name=$4 script=$5
    local copy="$TMPD/live-$name.img"
    cp "$image" "$copy"
    run_kernel "$limit" "$kernel" "osum nokbd nosched noproc nofs noring3 script=$script" \
        "$TMPD/$name.txt" -drive "file=$copy,format=raw,if=ide,index=0"
    local rc=$?
    rm -f "$copy"
    return $rc
}

transcript() {
    awk '/^==BEGIN==$/ {f=1; next} /^==END==$/ {f=0} f' "$1" \
        | grep -vE '^(elf: |key: |osum: |user fault: |acpiev: |thermal: |\*\*\*)' \
        | sed -E 's/^\[[0-9]+\] [0-9]+$/[job]/; s/^\[[0-9]+\] -> /[done] -> /' \
        | tr -d '\r'
}

build_prog() {
    local name=$1 source=$2 out=$3 profile="" crt="$TMPD/crt.o"
    grep -qa '^profile app' "$source" && { profile=--profile=app; crt=""; }
    "$FIRNC" $profile -c "$source" -o "$TMPD/$name.o" >"$TMPD/e-$name" 2>&1 || return 1
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$out" $crt "$TMPD/$name.o" \
        2>>"$TMPD/e-$name" || return 1
    strip --strip-all "$out"
}

echo "== 1. build: kernel and ${PROGS// /, } =="
for f in boot isr switch smp hv; do
    as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" || bad "$f.s does not assemble"
done
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s does not assemble"
"$FIRNC" kernel/kmain.fi -o "$TMPD/k.o" >"$TMPD/e-kernel" 2>&1 \
    && "$FIRNC" kernel/uprog.fi -o "$TMPD/u.o" >>"$TMPD/e-kernel" 2>&1 \
    && ld -n -T "$LDSCRIPT" \
        --defsym=KERNEL_MAIN="_F0.kernel_main" \
        --defsym=KERNEL_TRAP="_F0.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F0.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F0.tasks__main" \
        --defsym=KERNEL_USER_START="_F0.proccopy__user_start" \
        --defsym=KERNEL_AP_MAIN="_F0.smp__ap_main" \
        --defsym=USER_MAIN="_F0.u_enter" \
        -o "$TMPD/k.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" "$TMPD/smp.o" "$TMPD/hv.o" \
        "$TMPD/k.o" "$TMPD/u.o" 2>"$TMPD/ld.err" \
    && objcopy -O elf32-i386 "$TMPD/k.elf" "$TMPD/k.mb" 2>/dev/null \
    && ok "kernel built" \
    || { bad "kernel build failed"; head -8 "$TMPD/e-kernel" "$TMPD/ld.err" | sed 's/^/        /'; echo "OSHPIPES: $pass passed, $fail failed"; exit 1; }
for p in $PROGS; do
    build_prog "$p" "kernel/user/$p.fi" "$TMPD/$p.elf" || { bad "$p does not build"; head -6 "$TMPD/e-$p" | sed 's/^/        /'; }
done
[ "$fail" -eq 0 ] && ok "userland programs built"

printf 'banana\napple\ncherry\n' > "$TMPD/three.txt"
for i in $(seq 1 12); do echo "line $i"; done > "$TMPD/nums.txt"

cat > "$TMPD/t1.sh" <<'SCRIPT'
echo ==BEGIN==
seq 1 100000 | wc -l
seq 1 100000 | head -n 2
cat /d/three.txt | sort | uniq -c | wc -l
cat /d/nums.txt | grep 1 | tee /o.txt | wc -l
wc -l < /o.txt
echo x | cat | cat | cat
true | false
echo last-false=$?
false | true
echo last-true=$?
cat /d/three.txt | sort | head -n 1
echo ==END==
SCRIPT
cat > "$TMPD/t1.want" <<'WANT'
100000
1
2
3
4
4
x
last-false=1
last-true=0
apple
WANT

cat > "$TMPD/t2.sh" <<'SCRIPT'
echo ==BEGIN==
cat /nope > /o.txt 2>&1
cat /o.txt
cat /nope 2>&1 | wc -l
cat /nope 2>> /e.txt
cat /nope 2>> /e.txt
wc -l < /e.txt
echo err 2> /e3.txt 1>&2
cat /e3.txt
echo a > /o.txt
echo b >> /o.txt
cat < /o.txt | wc -l
cat /nope 2>&1 > /o2.txt | wc -l
echo ==END==
SCRIPT
cat > "$TMPD/t2.want" <<'WANT'
cat: cannot open /nope
1
2
err
2
1
WANT

cat > "$TMPD/t3.sh" <<'SCRIPT'
echo ==BEGIN==
true && echo yes
false && echo no
echo s=$?
false || echo alt
true || echo no2
echo s=$?
false && echo x || echo y
true && echo x || echo y
sleep -m 400 &
echo fg
wait
seq 1 3 | wc -l > /bg.txt &
wait
cat /bg.txt
false | true || echo not-run
echo end
echo ==END==
SCRIPT
cat > "$TMPD/t3.want" <<'WANT'
yes
s=1
alt
s=0
y
x
[job]
fg
[done] -> 0
[job]
[done] -> 0
[done] -> 0
3
end
WANT

make_spec() {
    local sh_elf=$1 spec="/bin/" p
    for p in $PROGS; do
        if [ "$p" = sh ]; then spec="$spec /bin/sh=$sh_elf"; else spec="$spec /bin/$p=$TMPD/$p.elf"; fi
    done
    echo "$spec"
}
DATA="/d/ /d/three.txt=$TMPD/three.txt /d/nums.txt=$TMPD/nums.txt"
CASES="/t/"
for c in t1 t2 t3; do CASES="$CASES /t/$c.sh=$TMPD/$c.sh"; done

build_image() {
    bash tools/mkfsfi/mkfs.sh build "$1" $BLOCKS $(make_spec "$2") $DATA $CASES > "$TMPD/mkfs.txt" 2>&1
}

build_image "$TMPD/disk.img" "$TMPD/sh.elf" && ok "image built" \
    || { bad "mkfs failed"; head -5 "$TMPD/mkfs.txt" | sed 's/^/        /'; }

check_case() {
    local name=$1 label=$2 rc
    run_case "$CASE_TIMEOUT" "$TMPD/k.mb" "$TMPD/disk.img" "$name" "sh /t/$name.sh;exit"
    rc=$?
    if [ "$rc" -ne 21 ]; then
        bad "$label: QEMU exit code $rc, expected 21"
        tail -5 "$TMPD/$name.txt" | sed 's/^/        /'
        return
    fi
    transcript "$TMPD/$name.txt" > "$TMPD/$name.got"
    if diff -u "$TMPD/$name.want" "$TMPD/$name.got" > "$TMPD/$name.diff"; then
        ok "$label"
    else
        bad "$label"
        sed 's/^/        /' "$TMPD/$name.diff" | head -20
    fi
}

echo "== 2. transcripts =="
check_case t1 "pipelines run concurrently (>64 KiB through a pipe, early reader exit, last-stage status)"
check_case t2 "redirections: 2>&1, 1>&2, 2>>, >>, <, order of redirections"
check_case t3 "&&, ||, background jobs, background pipelines, wait"

mutant() {
    local name=$1 label=$2 pattern=$3 replacement=$4 case=$5
    local msrc="$TMPD/user/sh-$name.fi" rc
    [ -d "$TMPD/user" ] || cp -r kernel/user "$TMPD/user"
    python3 -I - "$pattern" "$replacement" kernel/user/sh.fi "$msrc" <<'PY' || { bad "$label: mutation does not apply"; return; }
import sys
pattern, replacement, source, out = sys.argv[1:5]
text = open(source).read()
if pattern not in text:
    sys.exit(1)
open(out, "w").write(text.replace(pattern, replacement, 1))
PY
    build_prog "sh-$name" "$msrc" "$TMPD/sh-$name.elf" \
        || { bad "$label: mutant does not build"; head -4 "$TMPD/e-sh-$name" | sed 's/^/        /'; return; }
    build_image "$TMPD/mut.img" "$TMPD/sh-$name.elf" || { bad "$label: mutant image failed"; return; }
    run_case "$MUTANT_TIMEOUT" "$TMPD/k.mb" "$TMPD/mut.img" "mut-$name" "sh /t/$case.sh;exit"
    rc=$?
    transcript "$TMPD/mut-$name.txt" > "$TMPD/mut-$name.got"
    if [ "$rc" -eq 21 ] && diff -q "$TMPD/$case.want" "$TMPD/mut-$name.got" >/dev/null; then
        bad "counter-probe: $label stays green"
    else
        ok "counter-probe: $label turns red"
    fi
}

echo "== 3. counter-probes (mutated shells must fail) =="
mutant seqwait "stages waited one by one (no concurrency)" \
    "        carry = out_r
" \
    "        ulib.wait_code(stage_pid[k as usize])
        stage_pid[k as usize] = 0
        carry = out_r
" t1
mutant keepw "write end kept open in the shell (reader never sees EOF)" \
    "        close_fd(out_w)
" "" t1
mutant noerrdup "2>&1 ignored" \
    "            ulib.sys(ulib.SYS_DUP2, 1, 2, 0)
" "" t2
mutant noand "&& treated as ;" \
    "skip = (sep == K_AND && status != 0) ||" "skip = false ||" t3

echo "OSHPIPES: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
