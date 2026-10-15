#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/alpine/run.sh -- REAL Alpine/musl binaries on Osum (the Vinix bar: Vinix runs Alpine binaries).
#
#   bash tools/alpine/run.sh          # normal run (builds the kernel unless KERNEL=<osum.mb> is given)
#   KERNEL=/path/osum.mb bash tools/alpine/run.sh
#   ALPINE_NET=1 ...                  # download the pinned minirootfs if it is not cached
#   ALPINE_KEEP=1 ...                 # keep the work dir (printed)
#   STAGES="root chroot" ...          # which stages to run (default both)
#
# WHAT IS MEASURED
#   stage "root"   : the unpacked Alpine minirootfs IS the root of the guest image. Alpine's own /sbin/init (busybox init)
#                    boots from /etc/inittab, whose sysinit line runs tools/alpine/probe.sh. ~90 probes: musl loader, dynamic
#                    busybox applets (through the absolute symlinks of Alpine), archives, /proc, /dev, apk-tools 3.
#   stage "chroot" : the guest root is a tiny host (busybox + ld-musl copies); the rootfs lies in /alpine and the probe script
#                    runs after `chroot /alpine` (chroot(2), the musl loader at /lib/ld-musl-x86_64.so.1 INSIDE the jail,
#                    absolute symlinks inside the jail, `..` at the jail root).
#   Each probe prints "AL <name> ok|FAIL [...]"; the run is read from the serial log. KNOWN failures live in
#   tools/alpine/gaps.txt ("<probe> # reason"); a failure NOT listed there fails the gate, a listed one that now passes is
#   reported as FIXED (delete the line). With STONES_KARGS=fremdtrace semantics (always on here) the kernel prints
#   "sys: ENOSYS nr<N>" and "sys: ERR nr<N> e<errno>" lines -> the "kernel gaps" list at the end.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
HERE=$ROOT/tools/alpine
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
TMO=${TMO:-300}
STAGES=${STAGES:-"root chroot"}
SRC=${ALPINE_SRC:-/root/fremdquellen}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$*"; }

for t in "$QEMU" python3 tar sha256sum; do command -v "$t" >/dev/null 2>&1 || { echo "ALPINE: $t missing, skipped"; exit 0; }; done
D=$(mktemp -d)
if [ -n "${ALPINE_KEEP:-}" ]; then echo "ALPINE: work dir $D (kept)"; else trap 'rm -rf "$D"' EXIT; fi

echo "== 0. the pinned minirootfs =="
read -r PFILE PSHA PURL < <(grep -v '^#' "$HERE/ROOTFS.pin" | head -1)
TARBALL=$SRC/$PFILE
if [ ! -r "$TARBALL" ] && [ -n "${ALPINE_NET:-}" ]; then
    mkdir -p "$D/dl" && curl -fsSL -m 300 -o "$D/dl/$PFILE" "$PURL" && TARBALL=$D/dl/$PFILE
fi
[ -r "$TARBALL" ] || { echo "ALPINE: $PFILE not found in $SRC (ALPINE_NET=1 downloads it); skipped"; exit 0; }
if [ "$(sha256sum "$TARBALL" | cut -d' ' -f1)" = "$PSHA" ]; then ok "$PFILE matches the pin ($PSHA)"; else bad "$PFILE does NOT match the pin"; echo "ALPINE: $pass passed, $fail failed"; exit 1; fi
if [ -r "$SRC/SHA256SUMS.txt" ]; then
    grep -q "^$PSHA  $PFILE\$" "$SRC/SHA256SUMS.txt" && ok "pin is also in $SRC/SHA256SUMS.txt" || bad "pin missing in $SRC/SHA256SUMS.txt"
fi
python3 -I "$HERE/mkspec.py" "$TARBALL" "$D/ex" "$D/spec.txt" > "$D/mkspec.txt" && ok "$(cat "$D/mkspec.txt")" || { bad "mkspec failed"; cat "$D/mkspec.txt"; }
python3 -I "$HERE/mkspec.py" "$TARBALL" "$D/ex" "$D/spec-alpine.txt" --prefix=/alpine > /dev/null

echo "== 1. kernel =="
KNEW=${KERNEL:-$D/k.mb}
if [ -z "${KERNEL:-}" ]; then
    ( bash tools/build-kernel.sh "$KNEW" --stufe 1 ) > "$D/kernel.log" 2>&1 && ok "kernel built" || { bad "kernel does not build"; tail -5 "$D/kernel.log"; echo "ALPINE: $pass passed, $fail failed"; exit 1; }
else
    ok "kernel given: $KNEW"
fi

mkimage() { # mkimage <out.img> <spec lines file> [extra spec...]
    local out=$1 specf=$2; shift 2
    mapfile -t SP < "$specf"
    python3 "$ROOT/tools/osum/mkfs.py" build "$out" ${ALPINE_BLOCKS:-98304} --v3 --inodes=${ALPINE_INODES:-1536} "${SP[@]}" "$@" > "$D/mkfs.log" 2>&1
}
boot() { # boot <disk> <serial-out> [kargs]
    cp -f "$1" "$1.live"
    timeout "$TMO" "$QEMU" "${KVM[@]}" -smp "${SMP:-1}" -kernel "$KNEW" -m 512 \
        -append "osum vfs nokbd nosched noproc nofs fremdtrace ${3:-}" -serial "file:$2" -display none -no-reboot \
        -drive "file=$1.live,format=raw,if=ide,index=0" -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    local rc=$?; rm -f "$1.live"; return $rc
}
# probes of one stage -> $D/<stage>.res ; compares with gaps.txt
evaluate() { # evaluate <stage>
    local st=$1 res=$D/$1.res
    tr -d '\r' < "$D/$st.ser" | grep -a '^AL ' | awk '!seen[$2]++' > "$res"
    grep -aq '^AL end ok' "$res" && ok "[$st] probe script ran to its end" || bad "[$st] probe script did not reach its end (last: $(tail -1 "$res" | cut -c1-60))"
    local nok nfail unk=0 fixed=0 known=0
    nok=$(grep -a -c ' ok$' "$res"); nfail=$(grep -a -c ' FAIL' "$res")
    while read -r _ name rest; do
        [ "$name" = end ] && continue
        if grep -q "^$st:$name \|^$name " "$HERE/gaps.txt" 2>/dev/null; then known=$((known+1)); printf '        GAP     %-24s %s\n' "$name" "$(echo "$rest" | cut -c1-100)"
        else unk=$((unk+1)); printf '        NEW-RED %-24s %s\n' "$name" "$(echo "$rest" | cut -c1-100)"; fi
    done < <(grep -a ' FAIL' "$res")
    # a probe listed as a gap that passed (or never ran)
    while read -r key _; do
        [ -z "$key" ] && continue; case "$key" in '#'*) continue ;; esac
        local pn=${key#*:}; [ "$pn" = "$key" ] || { [ "${key%%:*}" = "$st" ] || continue; }
        if grep -aq "^AL $pn ok\$" "$res"; then fixed=$((fixed+1)); printf '        FIXED   %-24s (delete from gaps.txt)\n' "$pn"; fi
    done < "$HERE/gaps.txt"
    echo "        [$st] $nok ok / $nfail fail ($known known gaps, $unk new, $fixed fixed)"
    [ "$unk" -eq 0 ] && ok "[$st] no failure outside gaps.txt" || bad "[$st] $unk probe(s) fail that are not in gaps.txt"
    [ "$nok" -ge "${MINOK:-40}" ] && ok "[$st] at least ${MINOK:-40} probes ok ($nok)" || bad "[$st] only $nok probes ok"
    cat "$res" > "$D/$st.all"
}
kernel_gaps() { # list distinct ENOSYS numbers and failing syscalls from fremdtrace
    local st=$1
    tr -d '\r' < "$D/$st.ser" | grep -a '^sys: ENOSYS nr' | sort | uniq -c | sed 's/^ */        ENOSYS /' | sort -u >> "$D/enosys.txt"
}

for ST in $STAGES; do
    echo "== stage $ST =="
    case "$ST" in
    root)
        grep -v '^/etc/inittab' "$D/spec.txt" > "$D/spec-root.txt"
        printf '::sysinit:/bin/sh /etc/probe.sh\n::shutdown:/bin/true\n' > "$D/inittab-root"
        mkimage "$D/root.img" "$D/spec-root.txt" /proc/ /sys/ /run/ /w/ "/etc/probe.sh=$HERE/probe.sh" "/etc/inittab=$D/inittab-root" \
            && ok "[root] image built" || { bad "[root] image does not build"; tail -3 "$D/mkfs.log"; continue; }
        boot "$D/root.img" "$D/root.ser"; rc=$?
        echo "        qemu rc=$rc"
        evaluate root; kernel_gaps root ;;
    chroot)
        # host = busybox + the musl loader + inittab; the jail = full rootfs under /alpine
        grep -v '^/alpine/etc/inittab' "$D/spec-alpine.txt" > "$D/spec-ch.txt"
        BB=$D/ex/$(grep -o '^/alpine/bin/busybox=[^@]*' "$D/spec-alpine.txt" | sed 's|.*/ex/||')
        LD=$D/ex/$(grep -o '^/alpine/lib/ld-musl-x86_64.so.1=[^@]*' "$D/spec-alpine.txt" | sed 's|.*/ex/||')
        printf '::sysinit:/bin/chroot /alpine /usr/bin/env CHROOTED=1 /bin/sh /etc/probe.sh\n::shutdown:/bin/true\n' > "$D/inittab-ch"
        printf '::sysinit:/bin/true\n' > /dev/null
        mkimage "$D/ch.img" "$D/spec-ch.txt" /bin/@755 /lib/@755 /etc/@755 /proc/ /dev/ /tmp/ /sbin/ /alpine/proc/ /alpine/sys/ /alpine/run/ \
            "/bin/busybox=$BB@755" "/lib/ld-musl-x86_64.so.1=$LD@755" "/bin/sh->/bin/busybox" "/bin/chroot->/bin/busybox" "/bin/true->/bin/busybox" \
            "/sbin/init->/bin/busybox" "/etc/inittab=$D/inittab-ch" "/alpine/etc/probe.sh=$HERE/probe.sh" \
            && ok "[chroot] image built" || { bad "[chroot] image does not build"; tail -3 "$D/mkfs.log"; continue; }
        boot "$D/ch.img" "$D/chroot.ser"; rc=$?
        echo "        qemu rc=$rc"
        evaluate chroot; kernel_gaps chroot ;;
    esac
done

echo "== kernel gaps seen with fremdtrace (ENOSYS = number the kernel does not implement) =="
[ -s "$D/enosys.txt" ] && sort -u "$D/enosys.txt" || echo "        (none)"
for ST in $STAGES; do
    [ -r "$D/$ST.ser" ] && { echo "        [$ST] failing syscalls (sys: ERR), by number:"; tr -d '\r' < "$D/$ST.ser" | grep -a '^sys: ERR nr' | awk '{print $4, $5}' | sort | uniq -c | sort -rn | head -5 | sed 's/^/          /'; }
done
echo "ALPINE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
