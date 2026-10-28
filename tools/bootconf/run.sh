#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$T/usr" "$T/bin" "$T/c"
cp -r kernel/user/. "$T/usr/"
cp tools/bootconf/bootconftest.fi "$T/usr/"
USRC="$T/usr" bash tools/sync/build.sh "$T/bin" 0 bootconftest cat shasum sh echo > "$T/b.txt" 2>&1 && ok "programs build" || { bad "programs build"; head -15 "$T/b.txt"; echo "BOOTCONF: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel build"; echo "BOOTCONF: $pass passed, $fail failed"; exit 1; }

ENTRY='    protocol: multiboot1\n    path: boot():/osum.mb\n    cmdline: modfs osum gfx wm script=x\n'
printf "timeout: 5\ndefault_entry: 1\n\n/Prod\n$ENTRY" > "$T/c/single.conf"
printf "timeout: 5\n\n/Prod\n$ENTRY" > "$T/c/nodef.conf"
printf "timeout: 5\ndefault_entry: 1\n\n/Prod\n$ENTRY\n/Windows Boot Manager\n    protocol: efi_chainload\n    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n" > "$T/c/dual.conf"
printf "timeout: 5\r\ndefault_entry: 1\r\n\r\n/Prod\r\n    protocol: multiboot1\r\n    path: boot():/osum.mb\r\n    cmdline: a\r\n\r\n/Other\r\n    protocol: multiboot1\r\n    path: boot():/osum.mb\r\n" > "$T/c/crlf.conf"
printf "timeout: 5\ndefault_entry: 1\n\n/Prod\n    protocol: multiboot1\n    path: boot():/osum.mb\n    cmdline: a" > "$T/c/noeol.conf"
printf "default_entry: 1\n/Prod\n$ENTRY\n/Prod (update)\n    protocol: multiboot1\n    path: boot():/osum-b.mb\n    cmdline: old\n\n/Third\n    protocol: multiboot1\n    path: boot():/osum.mb\n" > "$T/c/hasb.conf"
printf "default_entry: 1\n/Prod\n$ENTRY\n/Third\n    protocol: multiboot1\n    path: boot():/osum.mb\n\n/Late (update)\n    path: boot():/osum-b.mb\n" > "$T/c/badb.conf"
printf "default_entry: 1\n\n/Prod\n    protocol: multiboot1\n    path: boot():/EFI/prod/osum.mb\n    cmdline: a\n" > "$T/c/otherpath.conf"
printf "default_entry: 3\n\n/Prod\n$ENTRY" > "$T/c/def3.conf"
printf "default_entry: 1\n\n//Sub\n$ENTRY" > "$T/c/sub.conf"
printf "timeout: 5\n" > "$T/c/noentry.conf"
printf "timeout: 5\ndefault_entry: 1\n\n/Prod\n    protocol: multiboot1\n    path: boot():/EFI/prod/osum.mb\n    cmdline: a\n\n/Windows Boot Manager\n    protocol: efi_chainload\n    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n" > "$T/c/espdir.conf"
printf "default_entry: 1\n\n/Prod\n    protocol: multiboot1\n    path: boot():/EFI/prod/osum.mb\n    cmdline: a\n\n/Prod (update)\n    protocol: multiboot1\n    path: boot():/EFI/prod/osum-b.mb\n    cmdline: a\n\n/Windows Boot Manager\n    protocol: efi_chainload\n    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n" > "$T/c/espdirb.conf"
printf "default_entry: 1\n\n/Prod\n    protocol: multiboot1\n    path: boot():/EFI/prod/osum.mb\n\n/Other\n    protocol: multiboot1\n    path: boot():/EFI/zzz/osum-b.mb\n" > "$T/c/espdirx.conf"
cp tools/bootconf/hp-limine.conf "$T/c/hp.conf"
python3 - "$T/c" <<'PY'
import sys
d = sys.argv[1]
t = open(d + "/hp.conf", encoding="latin1").read()
t = t.replace("default_entry: 1\n", "default_entry: 1\n", 1)
open(d + "/hp2.conf", "w", encoding="latin1").write(t.replace("\n/Advanced\n", "\n/Advanced\n", 1) + "\n/Windows Boot Manager\n    protocol: efi_chainload\n    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n")
PY
CASES="single nodef dual crlf noeol hasb badb otherpath def3 sub noentry espdir espdirb espdirx hp hp2"
FILES=(); for c in $CASES; do FILES+=("/t/$c.conf=$T/c/$c.conf"); done
: > "$T/o.all"
ACC=tcg; [ -e /dev/kvm ] && ACC=kvm
group=0
set -- $CASES
while [ $# -gt 0 ]; do
    group=$((group+1))
    : > "$T/s.sh"
    for c in "${@:1:3}"; do
        printf 'echo ==%s==\nbootconftest /t/%s.conf /t/%s.out\nshasum /t/%s.out\n' "$c" "$c" "$c" "$c" >> "$T/s.sh"
    done
    printf "echo ==END$group==\necho pad\necho pad\necho pad\n" >> "$T/s.sh"
    if [ $# -gt 3 ]; then shift 3; else set --; fi
    python3 tools/osum/mkfs.py build "$T/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        /bin/sh=$T/bin/sh.elf /bin/bootconftest=$T/bin/bootconftest.elf /bin/shasum=$T/bin/shasum.elf /bin/cat=$T/bin/cat.elf /bin/echo=$T/bin/echo.elf \
        "${FILES[@]}" "/t/s.sh=$T/s.sh" > "$T/mkfs.txt" 2>&1 || tail -3 "$T/mkfs.txt"
    timeout 300 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k0.img" -m 512 \
        -append "osum vfs nokbd script=sh /t/s.sh;exit" \
        -serial "file:$T/o$group.txt" -display none -no-reboot \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    cat "$T/o$group.txt" >> "$T/o.all"
done
cp "$T/o.all" "$T/o.txt"
tr -cd '\11\12\15\40-\176' < "$T/o.txt" | tr -d '\r' > "$T/o.klar"
cp "$T/o.klar" "${BOOTCONF_OUT:-/dev/null}" 2>/dev/null
nxt() { local seen=0 r=""; for c in $CASES END1 END2 END3 END4 END5 END6 END7 END8; do [ $seen = 1 ] && { r=$c; break; }; [ "$c" = "$1" ] && seen=1; done; echo "$r"; }
for c in $CASES; do
    n=$(nxt $c)
    awk -v a="==$c==" -v b="==$n==" 'index($0,a)==1{f=1;next} index($0,b)==1{f=0} f' "$T/o.klar" > "$T/p.$c"
    st=$(python3 tools/bootconf/reference.py "$T/c/$c.conf" "$T/c/$c.ref")
    got=$(sed -n 's/^status=\([0-9]*\) .*/\1/p' "$T/p.$c" | head -1)
    if [ "$got" = "$st" ]; then ok "$c: status $st"; else bad "$c: status got '$got' want '$st'"; fi
    if [ "$st" = 0 ]; then
        want=$(sha256sum < "$T/c/$c.ref" | cut -d' ' -f1)
        grep -q "${want:0:24}" "$T/p.$c" && ok "$c: output equals the reference byte for byte" || bad "$c: output differs from the reference"
    else
        grep -q '^shasum: ' "$T/p.$c" || grep -qi 'cannot\|no such' "$T/p.$c" && ok "$c: no output file written" || bad "$c: output file exists after refusal"
    fi
done
python3 - "$T/c/hp.conf" "$T/c/hp.ref" <<'PY' && ok "hp layout: every other entry byte-identical (entries 2..N and header)" || bad "hp layout: other bytes changed"
import re, sys
orig = open(sys.argv[1], encoding="latin1").read()
new = open(sys.argv[2], encoding="latin1").read()
def blocks(t):
    parts = re.split(r"(?m)^(?=/)", t)
    return parts
ob, nb = blocks(orig), blocks(new)
assert len(nb) == len(ob) + 1
assert ob[0].replace("default_entry: 1", "default_entry: 2") == nb[0]
assert ob[1] == nb[1]
assert "(update)" in nb[2] and "osum-b.mb" in nb[2] and "module_path: boot():/root.img" in nb[2]
assert ob[2:] == nb[3:]
PY
grep -aiqE 'panic|kernel fault|page fault|exception' "$T/o.klar" && bad "fault on the serial line" || ok "0 faults"
grep -aq '^kernel: done' "$T/o.klar" && ok "the kernel finished" || bad "kernel did not finish"
echo "BOOTCONF: $pass passed, $fail failed"
[ "$fail" = 0 ]
