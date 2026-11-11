#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
HERE=tools/unterbau
AM=tools/abimatrix
. tools/lib/tmpdir.sh
D=${ABI_OUT:-$(mktemp -d)}
mkdir -p "$D"
osum_tmp_guard "${ABI_OUT:-}" "$D"
[ -n "${KEEP:-}" ] && trap - EXIT
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
[ -z "${NOKVM:-}" ] || KVM=()
SMP=${SMP:-1}
TMO=${TMO:-420}
export FIRNLIB="$ROOT/lib"
BBDYN=${BBDYN:-/root/bbdyn/busybox}
STONES=${STONES-/root/stones}

for t in musl-gcc "$QEMU" python3; do command -v "$t" >/dev/null 2>&1 || { echo "ABIMATRIX: $t missing, skipped"; exit 0; }; done
LDREAL=$(readlink -f "${LDSO:-/lib/ld-musl-x86_64.so.1}" 2>/dev/null || true)
[ -r "$LDREAL" ] || LDREAL=/usr/lib/x86_64-linux-musl/libc.so
[ -r "$LDREAL" ] || { echo "ABIMATRIX: no musl libc.so, skipped"; exit 0; }
{ [ -r "$BBDYN" ] && [ -r "$STONES/python3" ]; } || { echo "ABIMATRIX: proof stones missing (tools/unterbau/build-stones.sh), skipped"; exit 0; }
. "$HERE/image.sh"

echo "== 1. build the fixture programs (musl, dynamic) =="
mkdir -p "$D/bin"
for src in $AM/fixtures/*.c; do
    n=$(basename "$src" .c)
    musl-gcc -O1 -g0 -pthread -o "$D/bin/$n" "$src" 2> "$D/cc-$n.err" || { echo "ABIMATRIX: $n does not build"; head -5 "$D/cc-$n.err"; exit 1; }
done

echo "== 2. kernel, guest script, image =="
KNEW=${KERNEL:-$D/k-new.mb}
if [ -z "${KERNEL:-}" ]; then build_kernel "$ROOT" "$KNEW" || { echo "ABIMATRIX: kernel does not build"; tail -8 "$KNEW.log"; exit 1; }; fi
printf 'one\ntwo\nthree\n' > "$D/pruef.txt"
echo 'echo BB end' > "$D/bb.sh"
python3 $AM/genguest.py "$D/am.sh" $AM/registry.tsv $AM/counter.tsv || exit 1
EXTRA_SPEC="$(stones_spec "$STONES") /etc/am.sh=$D/am.sh"
UB_BLOCKS=${UB_BLOCKS:-262144} build_image "$ROOT" "$D/img" || { echo "ABIMATRIX: image does not build"; tail -5 "$D/img/mkfs.txt"; exit 1; }

echo "== 3. boot: every registry command in one guest =="
boot "$KNEW" "$D/img/disk.img" "busybox sh /etc/am.sh" "$D/am.ser"
echo "        qemu rc=$?, $(grep -ac '^AM ' "$D/am.ser") result lines"

echo "== 4. external stages =="
: > "$D/ext.tsv"
if [ -n "${ABI_EXT:-}" ]; then
    export ABI_FXWD=${ABI_FXWD:-/root/fxhp} ABI_OUT=$D
    while IFS=$'\t' read -r id group kind expected command; do
        case "$id" in ''|'#'*) continue ;; esac
        [ "$kind" = ext ] || continue
        bash -c "$command" > "$D/ext-$id.log" 2>&1; rc=$?
        case $rc in 0) st=PASS ;; 77) st=SKIP ;; *) st=FAIL ;; esac
        printf '%s\t%s\t%s\n' "$id" "$st" "$(tail -n 1 "$D/ext-$id.log" | cut -c1-120)" >> "$D/ext.tsv"
        echo "        $id: $st"
    done < $AM/registry.tsv
else
    echo "        not run (ABI_EXT=1 runs the Firefox stages)"
fi

echo "== 5. the matrix =="
python3 $AM/report.py --registry $AM/registry.tsv --counter $AM/counter.tsv --serial "$D/am.ser" --ext "$D/ext.tsv" \
    --known-red $AM/known-red.txt --tsv "$D/matrix.tsv" --md "$D/matrix.md" | tee "$D/report.txt"
rc=${PIPESTATUS[0]}
[ -z "${WRITE_DOC:-}" ] || cp "$D/matrix.md" docs/linux-abi-matrix.md
[ -z "${KEEP:-}" ] || echo "kept: $D"
exit $rc
