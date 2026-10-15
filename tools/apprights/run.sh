#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/apprights/run.sh -- W-APPRIGHTS stage 1: KERNEL-ENFORCED per-app microphone right, measured in QEMU.
#
#   bash tools/apprights/run.sh
#
# Guest: /bin/apprights forks children that label themselves `app:<name>` (sticky kernel label, like a started
# app bundle) and read the microphone through SYS_OSUM_AUDREAD. No sound card in the VM: "ALLOWED nodev" = the
# kernel let the call through to the (absent) device, "DENIED" = the kernel refused it before the device.
#   1. default deny: app with no grant -> DENIED
#   2. grant `mic` by the person (unlabelled tool) -> ALLOWED; other app stays DENIED (grants are per app)
#   3. revoke -> DENIED again
#   4. an app cannot grant itself (labelled caller -> REFUSED), mask unchanged
#   5. the person's own process (unlabelled) is never gated
#   6. unknown right name / bad app name are refused
#   7. COUNTER-PROBE: a kernel built with label_allows() always true lets the default-deny app through,
#      so the DENIED lines above are caused by the check and by nothing else
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
TMPD=$(mktemp -d)
POL=lib/apprights/policy.fi
cp "$POL" "$TMPD/policy.orig"
trap 'cp "$TMPD/policy.orig" "$POL"; rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
PROGS="sh cat echo apprights"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
    && ok "apprights builds" || { bad "build"; head -20 "$TMPD/b.txt"; echo "APPRIGHTS: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel"; tail -15 "$TMPD/k.txt"; echo "APPRIGHTS: $pass passed, $fail failed"; exit 1; }
cat > "$TMPD/s.sh" <<'EOS'
echo ==DEFAULT==
apprights get probe
apprights trymic probe
echo ==USER==
apprights trymic -
echo ==GRANT==
apprights set probe mic
apprights get probe
apprights trymic probe
echo ==OTHER==
apprights trymic other
echo ==REVOKE==
apprights set probe
apprights get probe
apprights trymic probe
echo ==SELF==
apprights trygrant probe
apprights get probe
echo ==BAD==
apprights set probe nonsense
apprights set bad/name mic
echo ==MULTI==
apprights set probe mic notify net
apprights get probe
echo ==END==
EOS
runvm() { # kernel out
    python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
        "/t/s.sh=$TMPD/s.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$1" -m 512 \
        -append "osum vfs script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$2.raw" -display none -no-reboot \
        -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$2.raw" > "$TMPD/$2.klar"
}
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
runvm "$TMPD/k0.img" main
O="$TMPD/main.klar"
part "$O" DEFAULT USER > "$TMPD/p1.txt"; part "$O" USER GRANT > "$TMPD/p2.txt"; part "$O" GRANT OTHER > "$TMPD/p3.txt"
part "$O" OTHER REVOKE > "$TMPD/p4.txt"; part "$O" REVOKE SELF > "$TMPD/p5.txt"; part "$O" SELF BAD > "$TMPD/p6.txt"
part "$O" BAD MULTI > "$TMPD/p7.txt"; part "$O" MULTI END > "$TMPD/p8.txt"
has "$TMPD/p1.txt" "apprights: probe mask=0" "default: no grants"
has "$TMPD/p1.txt" "trymic: DENIED" "1. default deny: app without grant cannot read the microphone"
hasnot "$TMPD/p1.txt" "ALLOWED" "1. and was not let through"
has "$TMPD/p2.txt" "trymic: ALLOWED" "5. the person's own (unlabelled) process is not gated"
has "$TMPD/p3.txt" "set ok 1" "2. the person grants mic"
has "$TMPD/p3.txt" "mask=1 mic" "2. mask shows mic"
has "$TMPD/p3.txt" "trymic: ALLOWED" "2. granted app reaches the device"
hasnot "$TMPD/p3.txt" "DENIED" "2. and is not denied"
has "$TMPD/p4.txt" "trymic: DENIED" "2. another app without grant stays denied"
has "$TMPD/p5.txt" "set ok 0" "3. revoke"
has "$TMPD/p5.txt" "mask=0" "3. mask back to 0"
has "$TMPD/p5.txt" "trymic: DENIED" "3. revoked app is denied again"
has "$TMPD/p6.txt" "trygrant: REFUSED" "4. an app cannot grant itself"
hasnot "$TMPD/p6.txt" "GRANTED ITSELF" "4. no self grant happened"
has "$TMPD/p6.txt" "probe mask=0" "4. mask unchanged after the attempt"
has "$TMPD/p7.txt" "unknown: nonsense" "6. unknown right name refused"
has "$TMPD/p7.txt" "set fail 22" "6. bad app name refused (EINVAL)"
has "$TMPD/p8.txt" "mask=" "multi: several rights in one set"
grep -qa "mic" "$TMPD/p8.txt" && grep -qa "notify" "$TMPD/p8.txt" && grep -qa "net" "$TMPD/p8.txt" \
    && ok "multi: mic notify net listed" || bad "multi: names missing"
# 7. COUNTER-PROBE: check always true
python3 - "$POL" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
a="    let app: u64 = label_app(label)\n    if app == 0 {\n        return true\n    }\n    return (get_mask(app) & bit) != 0\n"
assert a in s
open(p,'w').write(s.replace(a,"    return true\n"))
PY
./tools/build-kernel.sh "$TMPD/k1.img" --stufe 0 > "$TMPD/k1.txt" 2>&1 \
    && ok "counter-probe kernel (check disabled) builds" || { bad "counter-probe kernel"; tail -8 "$TMPD/k1.txt"; }
cp "$TMPD/policy.orig" "$POL"
if [ -s "$TMPD/k1.img" ]; then
    runvm "$TMPD/k1.img" non
    part "$TMPD/non.klar" DEFAULT USER > "$TMPD/n1.txt"
    has "$TMPD/n1.txt" "trymic: ALLOWED" "7. COUNTER-PROBE: without the check the ungranted app gets through"
    hasnot "$TMPD/n1.txt" "DENIED" "7. COUNTER-PROBE: no DENIED without the check"
fi
echo "APPRIGHTS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
