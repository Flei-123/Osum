#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
ULD=kernel/user/user.ld
PROGS="sh ls cat echo rm df touch mkdir fsrbig fsrv fsck"
RUNS=${FSRBM_RUNS:-16}
PAR=${FSRBM_PAR:-3}
PROBE_MIN_DAMAGED=${FSRBM_PROBE_MIN:-1}

TMPD=$(mktemp -d)
WT=""
cleanup() {
    [ -n "$WT" ] && git worktree remove --force "$WT" >/dev/null 2>&1
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() {
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, expected $op $want"; fi
}

[ -x "$FIRNC" ] || { echo "firnc0 missing: $FIRNC"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "FSRBM: skipped, qemu-system-x86_64 missing"; exit 0; }

build_user() {
    as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
    for p in $PROGS; do
        "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
            || { bad "$p.fi does not compile"; sed 's/^/        /' "$TMPD/e$p" | head -6; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null
        strip --strip-all "$TMPD/$p.elf" 2>/dev/null
    done
}

run_series() {
    local kernel=$1 tag=$2
    mkdir -p "$TMPD/runs-$tag"
    export FSR_KERNEL="$kernel" FSR_WRITER="fsrbig" FSR_MARKER="fsrbig: start"
    export FSR_MINMS=${FSRBM_MINMS:-400} FSR_SPANMS=${FSRBM_SPANMS:-4000}
    seq 1 "$RUNS" | xargs -P "$PAR" -I{} sh -c \
        "bash tools/fsrobust/crash.sh $TMPD/j.img $TMPD/runs-$tag {} '' 2>&1" > "$TMPD/crash-$tag.log" 2>&1
    sort -t= -k2 -n "$TMPD/crash-$tag.log" | grep '^lauf=' | sed 's/^/        /'
}

echo "== 1. build =="
bash tools/build-kernel.sh "$TMPD/k.mb" >"$TMPD/build.txt" 2>&1 \
    && ok "kernel built" || { bad "kernel build"; tail -8 "$TMPD/build.txt" | sed 's/^/        /'; echo "FSRBM: $pass passed, $fail failed"; exit 1; }
build_user
SPEC="/bin/ /tmp/ /dev/ /proc/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
bash tools/mkfsfi/mkfs.sh build "$TMPD/j.img" 65536 --v3 --inodes=512 --journal --time=1780000000 $SPEC >"$TMPD/mk.txt" 2>&1 \
    && ok "journal image built" || bad "mkfs with journal"

WT="$TMPD/nofix"
git worktree add -q --detach "$WT" HEAD >/dev/null 2>&1 || bad "worktree for the control kernel"
python3 - "$WT/kernel/fs/fs.fi" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
block = """        if ofsj.enabled(state) && ofsj.room(state) < 8 {
            if !free_flush(state) {
                return n
            }
"""
if s.count(block) != 1:
    print("anchor not found")
    sys.exit(1)
open(p, "w").write(s.replace(block, "        if ofsj.enabled(state) && ofsj.room(state) < 8 {\n"))
PY
[ $? -eq 0 ] && ok "control source without the bitmap flush before the journal chunk" || bad "control source patch"
(cd "$WT" && FIRNLIB="$WT/lib" bash tools/build-kernel.sh "$TMPD/knofix.mb" >"$TMPD/build2.txt" 2>&1) \
    && ok "control kernel built" || { bad "control kernel build"; tail -5 "$TMPD/build2.txt" | sed 's/^/        /'; }

echo
echo "== 2. one large write call, killed after the first journal chunk window: $RUNS kills =="
run_series "$TMPD/k.mb" fix
n_l=$(grep -c '^lauf=' "$TMPD/crash-fix.log")
n_w=$(grep '^lauf=' "$TMPD/crash-fix.log" | grep -c 'wirt=[1-9]')
n_f=$(grep '^lauf=' "$TMPD/crash-fix.log" | grep -c 'fsck=[1-9]')
n_b=$(grep '^lauf=' "$TMPD/crash-fix.log" | grep -vc 'rc2=21')
num "runs completed" "$n_l" eq "$RUNS"
num "runs that did not come up again" "$n_b" eq 0
num "damaged images (host check)" "$n_w" eq 0
num "damaged images (fsck)" "$n_f" eq 0

echo
echo "== 3. control: the same kills without the bitmap flush must damage images =="
run_series "$TMPD/knofix.mb" nofix
c_w=$(grep '^lauf=' "$TMPD/crash-nofix.log" | grep -c 'wirt=[1-9]')
num "damaged images with the control kernel" "$c_w" ge "$PROBE_MIN_DAMAGED"

echo
echo "FSRBM: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
