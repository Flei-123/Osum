#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/apprights3/run.sh -- W-APPRIGHTS AR-3 in QEMU: auto-grant of non-sensitive rights for signed (opk plan) packages, /proc/apps,
# with counter-probes (no plan = nothing granted; sensitive rights never).
#
#   bash tools/apprights3/run.sh
#
# Bundles in the image: probe (perm=all six), narrow (perm=notify), nodecl (INFO without perm=), sysapp (SYSTEM file).
# Boot 1 (fresh disk): `load` registers ceilings from the manifests; default deny; grants; ceiling refusals; conf written.
# Boot 2 (SAME disk, new kernel run): the kernel table is empty again (default deny), `load` brings the grants back,
#   a hand-edited conf is clamped to the ceiling, bad lines are skipped, a revoke removes the line.
# Counter-probes: (a) kernel with label_allows() always true -> ungranted app gets through; (b) kernel with the ceiling
#   check removed -> a manifest without perm= can be granted; (c) boot 2 WITHOUT `load` -> still denied.
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
    && ok "apprights builds" || { bad "build"; head -20 "$TMPD/b.txt"; echo "APPRIGHTS-AR3: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel"; tail -15 "$TMPD/k.txt"; echo "APPRIGHTS-AR3: $pass passed, $fail failed"; exit 1; }

# ---- bundles: probe (net,notify,clipboard.read,mic), narrow (notify), nodecl, side (net,mic; NOT in the plan), sysapp (SYSTEM)
mkdir -p "$TMPD/bd"
printf 'name=Probe\nperm=net,notify,clipboard.read,mic\nnet=real\n' > "$TMPD/bd/probe.info"
printf 'name=Narrow\nperm=notify\n' > "$TMPD/bd/narrow.info"
printf 'name=Nodecl\ninfo=declares nothing\n' > "$TMPD/bd/nodecl.info"
printf 'name=Side\nperm=net,mic\n' > "$TMPD/bd/side.info"
printf 'name=Sysapp\nperm=net\n' > "$TMPD/bd/sysapp.info"
printf 'system\n' > "$TMPD/bd/SYSTEM"
printf '00000001\n' > "$TMPD/bd/AKTUELL"
printf 'probe\t00aa\nnarrow\t00bb\nnodecl\t00cc\n' > "$TMPD/bd/PLAN"
cat > "$TMPD/s1.sh" <<'EOS'
echo ==L1==
apprights load
apprights get probe
apprights get narrow
apprights get nodecl
apprights get side
apprights get sysapp
echo ==TRY==
apprights try net probe
apprights try notify probe
apprights try clipr probe
apprights try clipw probe
apprights trymic probe
apprights try net side
echo ==REV==
apprights set probe notify clipboard.read
apprights load
apprights get probe
echo ==AGAIN==
apprights load
echo ==FORGET==
apprights forget probe
apprights get probe
cat /etc/apprights.conf
cat /etc/apprights.seen
apprights load
apprights get probe
echo ==PROC==
cat /proc/apps
echo ==END==
EOS
cat > "$TMPD/s2.sh" <<'EOS'
echo ==L1==
apprights load
apprights get probe
echo ==PROC==
cat /proc/apps
echo ==END==
EOS
mkimg() { # $1 = with | without the opk plan
    local extra=()
    [ "$1" = with ] && extra=(/system/generations/ /system/generations/1/ "/system/AKTUELL=$TMPD/bd/AKTUELL" "/system/generations/1/PLAN=$TMPD/bd/PLAN")
    python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /apps/ \
        /apps/probe.osp/ /apps/narrow.osp/ /apps/nodecl.osp/ /apps/side.osp/ /apps/sysapp.osp/ \
        "/apps/probe.osp/INFO=$TMPD/bd/probe.info" "/apps/narrow.osp/INFO=$TMPD/bd/narrow.info" \
        "/apps/nodecl.osp/INFO=$TMPD/bd/nodecl.info" "/apps/side.osp/INFO=$TMPD/bd/side.info" \
        "/apps/sysapp.osp/INFO=$TMPD/bd/sysapp.info" "/apps/sysapp.osp/SYSTEM=$TMPD/bd/SYSTEM" \
        "${extra[@]}" \
        $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
        "/t/s1.sh=$TMPD/s1.sh" "/t/s2.sh=$TMPD/s2.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
}
runvm() { # kernel out script
    timeout 170 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$1" -m 512 \
        -append "osum vfs script=sh /t/$3;exit" \
        -serial "file:$TMPD/$2.raw" -display none -no-reboot \
        -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$2.raw" > "$TMPD/$2.klar"
}
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

# ================= with the signed plan =================
mkimg with
runvm "$TMPD/k0.img" b1 s1.sh
O="$TMPD/b1.klar"
part "$O" L1 TRY > "$TMPD/p_l1.txt"; part "$O" TRY REV > "$TMPD/p_try.txt"; part "$O" REV AGAIN > "$TMPD/p_rev.txt"
part "$O" AGAIN FORGET > "$TMPD/p_again.txt"; part "$O" FORGET PROC > "$TMPD/p_forget.txt"; part "$O" PROC END > "$TMPD/p_proc.txt"
has "$TMPD/p_l1.txt" "auto=2" "load: 2 apps got rights (probe, narrow; nodecl declares nothing)"
has "$TMPD/p_l1.txt" "probe mask=" "probe line"
has "$TMPD/p_l1.txt" "net notify clipboard.read ceil=" "probe: net notify clipboard.read granted from perm="
hasnot "$TMPD/p_l1.txt" "probe mask=21 net notify clipboard.read mic" "probe: mic NOT granted"
has "$TMPD/p_l1.txt" "narrow mask=16 notify" "narrow: notify granted"
has "$TMPD/p_l1.txt" "nodecl mask=0" "nodecl: nothing declared, nothing granted"
has "$TMPD/p_l1.txt" "side mask=0" "side bundle (not in the plan) gets nothing: not signed"
has "$TMPD/p_l1.txt" "sysapp mask=0 ceil=none" "SYSTEM bundle untouched"
has "$TMPD/p_try.txt" "try: view=0" "probe can use the network at once (no manual grant)"
[ "$(grep -ac 'try: ALLOWED' "$TMPD/p_try.txt")" = 2 ] && ok "probe: notify and clipboard.read ALLOWED automatically" || bad "probe: expected 2 ALLOWED"
has "$TMPD/p_try.txt" "try: DENIED" "probe: clipboard.write not declared -> DENIED"
has "$TMPD/p_try.txt" "trymic: DENIED" "probe: mic is declared but sensitive -> DENIED"
has "$TMPD/p_try.txt" "try: view=3" "side: no network"
has "$TMPD/p_rev.txt" "mask=48 notify clipboard.read" "revoked net stays revoked after another load (offer recorded in apprights.seen)"
hasnot "$TMPD/p_again.txt" "auto=1" "second load: nothing new to auto-grant"
has "$TMPD/p_forget.txt" "forgot probe" "forget: reported"
has "$TMPD/p_forget.txt" "probe mask=0" "forget: grants gone"
hasnot "$TMPD/p_forget.txt" "probe net" "forget: no conf line left for probe"
has "$TMPD/p_forget.txt" "net notify clipboard.read ceil=" "reinstall after forget: granted again"
has "$TMPD/p_proc.txt" "# app cpu_ticks wakeups tx_bytes rx_bytes" "/proc/apps: header"
has "$TMPD/p_proc.txt" "probe " "/proc/apps: line for probe"
has "$TMPD/p_proc.txt" "narrow " "/proc/apps: line for narrow"
hasnot "$TMPD/p_proc.txt" "sysapp" "/proc/apps: no line for a system bundle"

# ================= counter-probe: no opk plan -> nothing is auto-granted =================
mkimg without
runvm "$TMPD/k0.img" b2 s2.sh
O="$TMPD/b2.klar"
part "$O" L1 PROC > "$TMPD/q_l1.txt"
has "$TMPD/q_l1.txt" "auto=0" "no plan: nothing auto-granted"
has "$TMPD/q_l1.txt" "probe mask=0" "no plan: probe has no rights (default deny)"

echo "APPRIGHTS-AR3: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
