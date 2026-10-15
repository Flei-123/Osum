#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/apprights2/run.sh -- W-APPRIGHTS AR-2 in QEMU: persistence (/etc/apprights.conf), manifest ceiling (perm=),
# kernel enforcement of clipboard.read/write, notify, audio.play and net (netview), with counter-probes.
#
#   bash tools/apprights2/run.sh
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
    && ok "apprights builds" || { bad "build"; head -20 "$TMPD/b.txt"; echo "APPRIGHTS-AR2: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel"; tail -15 "$TMPD/k.txt"; echo "APPRIGHTS-AR2: $pass passed, $fail failed"; exit 1; }

# ---- bundles
mkdir -p "$TMPD/bd"
printf 'name=Probe\ninfo=all six rights\nperm=notify,clipboard.read,clipboard.write,audio.play,net,mic\nnet=real\n' > "$TMPD/bd/probe.info"
printf 'name=Narrow\ninfo=notify only\nperm=notify\n' > "$TMPD/bd/narrow.info"
printf 'name=Nodecl\ninfo=declares nothing\n' > "$TMPD/bd/nodecl.info"
printf 'name=Sysapp\ninfo=shipped by the image\n' > "$TMPD/bd/sysapp.info"
printf 'system\n' > "$TMPD/bd/SYSTEM"

cat > "$TMPD/s1.sh" <<'EOS'
echo ==LOAD0==
apprights load
apprights get probe
apprights get narrow
apprights get nodecl
apprights get sysapp
echo ==DENY==
apprights try clipr probe
apprights try clipw probe
apprights try notify probe
apprights try audio probe
apprights try net probe
echo ==USER==
apprights try clipr -
apprights try clipw -
apprights try notify -
apprights try audio -
apprights try net -
echo ==GRANT==
apprights set probe clipboard.read clipboard.write notify audio.play net
apprights try clipr probe
apprights try clipw probe
apprights try notify probe
apprights try audio probe
apprights try net probe
echo ==OTHER==
apprights try clipr narrow
apprights try net narrow
echo ==ONEBIT==
apprights set probe notify
apprights try notify probe
apprights try clipr probe
apprights try clipw probe
apprights try audio probe
apprights try net probe
echo ==REGRANT==
apprights set probe clipboard.read clipboard.write notify audio.play net
echo ==CEIL==
apprights set nodecl notify
apprights get nodecl
apprights set narrow notify mic
apprights get narrow
apprights set narrow notify
apprights get narrow
echo ==SELFCEIL==
apprights trygrant narrow
echo ==CONF==
cat /etc/apprights.conf
echo ==END==
EOS
cat > "$TMPD/s2.sh" <<'EOS'
echo ==B2PRE==
apprights get probe
apprights try clipr probe
apprights try notify probe
apprights try net probe
echo ==B2LOAD==
apprights load
apprights get probe
apprights get narrow
apprights get nodecl
apprights try clipr probe
apprights try clipw probe
apprights try notify probe
apprights try audio probe
apprights try net probe
apprights trymic probe
apprights try clipr narrow
apprights try notify narrow
echo ==B2EDIT==
echo nodecl notify,mic >> /etc/apprights.conf
echo weird frobnicate >> /etc/apprights.conf
echo narrow net,notify >> /etc/apprights.conf
apprights load
apprights get nodecl
apprights get narrow
echo ==B2REVOKE==
apprights set probe
apprights try clipr probe
apprights try net probe
cat /etc/apprights.conf
echo ==END==
EOS
cat > "$TMPD/s3.sh" <<'EOS'
echo ==NOLOAD==
apprights get probe
apprights try clipr probe
apprights try notify probe
apprights try net probe
echo ==END==
EOS
cat > "$TMPD/s4.sh" <<'EOS'
echo ==LOAD0==
apprights load
echo ==CEIL==
apprights set nodecl notify
apprights get nodecl
echo ==END==
EOS
mkimg() { # fresh disk with all four scripts
    python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /apps/ \
        /apps/probe.osp/ /apps/narrow.osp/ /apps/nodecl.osp/ /apps/sysapp.osp/ \
        "/apps/probe.osp/INFO=$TMPD/bd/probe.info" "/apps/narrow.osp/INFO=$TMPD/bd/narrow.info" \
        "/apps/nodecl.osp/INFO=$TMPD/bd/nodecl.info" "/apps/sysapp.osp/INFO=$TMPD/bd/sysapp.info" \
        "/apps/sysapp.osp/SYSTEM=$TMPD/bd/SYSTEM" \
        $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
        "/t/s1.sh=$TMPD/s1.sh" "/t/s2.sh=$TMPD/s2.sh" "/t/s3.sh=$TMPD/s3.sh" "/t/s4.sh=$TMPD/s4.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
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

# ================= boot 1 =================
mkimg
runvm "$TMPD/k0.img" b1 s1.sh
O="$TMPD/b1.klar"
part "$O" LOAD0 DENY > "$TMPD/p_load.txt"; part "$O" DENY USER > "$TMPD/p_deny.txt"; part "$O" USER GRANT > "$TMPD/p_user.txt"
part "$O" GRANT OTHER > "$TMPD/p_grant.txt"; part "$O" OTHER ONEBIT > "$TMPD/p_other.txt"; part "$O" ONEBIT REGRANT > "$TMPD/p_one.txt"
part "$O" CEIL SELFCEIL > "$TMPD/p_ceil.txt"; part "$O" SELFCEIL CONF > "$TMPD/p_self.txt"; part "$O" CONF END > "$TMPD/p_conf.txt"
has "$TMPD/p_load.txt" "apprights: load 3 ceilings" "load: 3 ceilings (probe, narrow, nodecl; SYSTEM bundle has no slot)"
has "$TMPD/p_load.txt" "probe mask=0" "load: nothing granted by loading (default deny)"
has "$TMPD/p_load.txt" "narrow mask=0 ceil=16" "ceiling of narrow = notify (manifest perm=notify)"
has "$TMPD/p_load.txt" "nodecl mask=0 ceil=0" "manifest without perm= -> ceiling 0"
has "$TMPD/p_load.txt" "sysapp mask=0 ceil=none" "SYSTEM bundle gets no ceiling slot"
[ "$(grep -ac 'try: DENIED' "$TMPD/p_deny.txt")" = 4 ] && ok "default deny: clipboard.read, clipboard.write, notify, audio.play all DENIED" || bad "default deny: expected 4 DENIED, got $(grep -ac 'try: DENIED' "$TMPD/p_deny.txt")"
has "$TMPD/p_deny.txt" "try: view=3" "default deny: net view is none (3)"
hasnot "$TMPD/p_deny.txt" "ALLOWED" "default deny: nothing let through"
[ "$(grep -ac 'try: ALLOWED' "$TMPD/p_user.txt")" = 4 ] && ok "the person's own process is never gated (4 x ALLOWED)" || bad "unlabelled process gated"
has "$TMPD/p_user.txt" "try: view=0" "the person's own process keeps the real network view"
[ "$(grep -ac 'try: ALLOWED' "$TMPD/p_grant.txt")" = 4 ] && ok "granted: clipboard.read, clipboard.write, notify, audio.play ALLOWED" || bad "granted rights not allowed ($(grep -ac 'try: ALLOWED' "$TMPD/p_grant.txt") of 4)"
has "$TMPD/p_grant.txt" "try: view=0" "granted net: view is real (0)"
has "$TMPD/p_other.txt" "try: DENIED" "another app (narrow) stays denied"
has "$TMPD/p_other.txt" "try: view=3" "another app (narrow) has no network"
[ "$(grep -ac 'try: ALLOWED' "$TMPD/p_one.txt")" = 1 ] && ok "one bit: only notify ALLOWED" || bad "one bit: expected exactly 1 ALLOWED, got $(grep -ac 'try: ALLOWED' "$TMPD/p_one.txt")"
[ "$(grep -ac 'try: DENIED' "$TMPD/p_one.txt")" = 3 ] && ok "one bit: clipboard.read, clipboard.write, audio.play DENIED" || bad "one bit: expected 3 DENIED"
has "$TMPD/p_one.txt" "try: view=3" "one bit: net revoked -> view none at once"
has "$TMPD/p_ceil.txt" "set fail 1" "ceiling: grant on a manifest without perm= refused (EPERM)"
has "$TMPD/p_ceil.txt" "above the manifest ceiling" "ceiling: refusal explained"
has "$TMPD/p_ceil.txt" "nodecl mask=0 ceil=0" "ceiling: nodecl still has nothing"
has "$TMPD/p_ceil.txt" "narrow mask=0 ceil=16" "ceiling: narrow notify+mic refused as a whole, mask unchanged"
has "$TMPD/p_ceil.txt" "narrow mask=16 notify ceil=16" "ceiling: narrow notify alone is allowed"
has "$TMPD/p_ceil.txt" "mask=16 notify ceil=16" "ceiling: grant inside the ceiling works"
has "$TMPD/p_self.txt" "trygrant: REFUSED" "an app cannot grant itself (or raise its ceiling)"
has "$TMPD/p_conf.txt" "probe " "conf: probe line written"
has "$TMPD/p_conf.txt" "narrow notify" "conf: narrow line written"
hasnot "$TMPD/p_conf.txt" "nodecl" "conf: refused grant is not persisted"

# ================= boot 2: SAME disk, kernel table starts empty =================
runvm "$TMPD/k0.img" b2 s2.sh
O="$TMPD/b2.klar"
part "$O" B2PRE B2LOAD > "$TMPD/q_pre.txt"; part "$O" B2LOAD B2EDIT > "$TMPD/q_load.txt"
part "$O" B2EDIT B2REVOKE > "$TMPD/q_edit.txt"; part "$O" B2REVOKE END > "$TMPD/q_rev.txt"
has "$TMPD/q_pre.txt" "probe mask=0" "restart: the kernel table is empty again"
[ "$(grep -ac 'try: DENIED' "$TMPD/q_pre.txt")" = 2 ] && ok "restart without load: clipboard.read and notify DENIED (grants are not in RAM)" || bad "restart without load: expected 2 DENIED"
has "$TMPD/q_pre.txt" "try: view=3" "restart without load: net none"
has "$TMPD/q_load.txt" "apprights: load 3 ceilings" "restart: load registers the ceilings again"
has "$TMPD/q_load.txt" "applied=2" "restart: load applied the 2 saved grants"
has "$TMPD/q_load.txt" "clamped=0" "restart: nothing had to be clamped"
has "$TMPD/q_load.txt" "narrow mask=16 notify ceil=16" "restart: grant survived (narrow notify)"
has "$TMPD/q_load.txt" "nodecl mask=0 ceil=0" "restart: nodecl still has nothing"
[ "$(grep -ac 'try: ALLOWED' "$TMPD/q_load.txt")" = 5 ] && ok "restart: probe clipr clipw notify audio + narrow notify ALLOWED after load (5)" || bad "restart: expected 5 ALLOWED, got $(grep -ac 'try: ALLOWED' "$TMPD/q_load.txt")"
has "$TMPD/q_load.txt" "try: view=0" "restart: probe net back to real"
has "$TMPD/q_load.txt" "trymic: DENIED" "restart: mic was never granted -> still denied"
has "$TMPD/q_load.txt" "try: DENIED" "restart: narrow has no clipboard.read"
has "$TMPD/q_edit.txt" "clamped=2" "hand-edited conf above the ceiling: 2 lines clamped (nodecl mic, narrow net)"
has "$TMPD/q_edit.txt" "bad=1" "hand-edited conf: unknown right line skipped and counted"
has "$TMPD/q_edit.txt" "nodecl mask=0 ceil=0" "manifest without perm= got nothing from the conf file"
has "$TMPD/q_edit.txt" "narrow mask=16 notify ceil=16" "narrow got only notify (net clamped away)"
has "$TMPD/q_rev.txt" "try: DENIED" "revoke after restart: denied"
has "$TMPD/q_rev.txt" "try: view=3" "revoke after restart: net none"
hasnot "$TMPD/q_rev.txt" "probe " "revoke removes the probe line from the conf file"

# ================= counter-probe (c): fresh disk, boot without load =================
mkimg
runvm "$TMPD/k0.img" b3 s3.sh
part "$TMPD/b3.klar" NOLOAD END > "$TMPD/r3.txt"
has "$TMPD/r3.txt" "try: DENIED" "(c) fresh disk, no load: denied"

# ================= counter-probe (a): label_allows() always true =================
python3 - "$POL" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
a = "    let app: u64 = label_app(label)\n    if app == 0 {\n        return true\n    }\n    return (get_mask(app) & bit) != 0\n"
assert a in s
open(p, 'w').write(s.replace(a, "    return true\n"))
PYEOF
./tools/build-kernel.sh "$TMPD/ka.img" --stufe 0 > "$TMPD/ka.txt" 2>&1 \
    && ok "(a) counter-probe kernel (check disabled) builds" || { bad "(a) kernel"; tail -8 "$TMPD/ka.txt"; }
cp "$TMPD/policy.orig" "$POL"
if [ -s "$TMPD/ka.img" ]; then
    mkimg
    runvm "$TMPD/ka.img" ba s1.sh
    part "$TMPD/ba.klar" DENY USER > "$TMPD/na.txt"
    [ "$(grep -ac 'try: ALLOWED' "$TMPD/na.txt")" = 4 ] && ok "(a) COUNTER-PROBE: without the check ungranted clipboard/notify/audio get through" || bad "(a) counter-probe did not turn the DENIED lines into ALLOWED"
    has "$TMPD/na.txt" "try: view=0" "(a) COUNTER-PROBE: without the check the network view stays real"
fi

# ================= counter-probe (b): ceiling check removed =================
python3 - "$POL" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
a = "        if ((mask & P_ALL) & (P_ALL - ceils[s as usize])) != 0 {\n            return E_CEIL\n        }\n"
assert a in s
open(p, 'w').write(s.replace(a, ""))
PYEOF
./tools/build-kernel.sh "$TMPD/kb.img" --stufe 0 > "$TMPD/kb.txt" 2>&1 \
    && ok "(b) counter-probe kernel (ceiling check removed) builds" || { bad "(b) kernel"; tail -8 "$TMPD/kb.txt"; }
cp "$TMPD/policy.orig" "$POL"
if [ -s "$TMPD/kb.img" ]; then
    mkimg
    runvm "$TMPD/kb.img" bb s4.sh
    part "$TMPD/bb.klar" CEIL END > "$TMPD/nb.txt"
    has "$TMPD/nb.txt" "nodecl mask=16 notify" "(b) COUNTER-PROBE: without the ceiling check a manifest without perm= receives a grant"
fi
echo "APPRIGHTS-AR2: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
