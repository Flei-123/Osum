#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/appfs/run.sh -- S-010 file sandbox in QEMU: a labelled app whose manifest says `sandbox=files` and that holds no
# `fs.home` grant may read its own /data/<name> and the shared system areas, write only /data/<name>, and create no links.
#   bash tools/appfs/run.sh
# Bundles: box (sandbox=files), boxhome (sandbox=files + perm=fs.home), plain (no sandbox line), sysapp (SYSTEM file).
# Counter-probes: (a) confinement check disabled in lib -> the DENY lines turn OK, (b) write check at open removed -> write
# outside the data folder succeeds, (c) no `load` after boot -> not confined yet (documented limit).
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
cnt() { [ "$(grep -ac -- "$2" "$1")" = "$3" ] && ok "$4" || bad "$4 -- expected $3 x '$2', got $(grep -ac -- "$2" "$1")"; }
TMPD=$(mktemp -d)
FSP=lib/apprights/fspolicy.fi
SYS=kernel/sys/sys.fi
cp "$FSP" "$TMPD/fsp.orig"; cp "$SYS" "$TMPD/sys.orig"
trap 'cp "$TMPD/fsp.orig" "$FSP"; cp "$TMPD/sys.orig" "$SYS"; rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
PROGS="sh cat echo apprights"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
    && ok "programs build" || { bad "build"; head -20 "$TMPD/b.txt"; echo "APPFS: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel"; tail -15 "$TMPD/k.txt"; echo "APPFS: $pass passed, $fail failed"; exit 1; }

mkdir -p "$TMPD/bd"
printf 'name=Box\ninfo=confined\nperm=notify\nsandbox=files\n' > "$TMPD/bd/box.info"
printf 'name=Boxhome\ninfo=confined, may ask for home\nperm=fs.home\nsandbox=files\n' > "$TMPD/bd/boxhome.info"
printf 'name=Plain\ninfo=no sandbox line\nperm=notify\n' > "$TMPD/bd/plain.info"
printf 'name=Sysapp\ninfo=shipped by the image\nsandbox=files\n' > "$TMPD/bd/sysapp.info"
printf 'system\n' > "$TMPD/bd/SYSTEM"
printf 'top secret\n' > "$TMPD/secret.txt"
printf 'doc\n' > "$TMPD/doc.txt"
printf 'other\n' > "$TMPD/other.txt"

cat > "$TMPD/s1.sh" <<'EOS'
echo ==LOAD==
apprights load
apprights list
echo ==READ==
apprights tryfs read box /etc/secret.txt
apprights tryfs read box /data/dokumente/doc.txt
apprights tryfs read box /data/other/x.txt
apprights tryfs read box /data/box/../other/x.txt
apprights tryfs read box /data/box/../../etc/secret.txt
apprights tryfs read box /lib/sans.ttf
apprights tryfs read box /bin/sh
apprights tryfs read box /apps/box.osp/INFO
echo ==WRITE==
apprights tryfs write box /data/box/new.txt
apprights tryfs read box /data/box/new.txt
apprights tryfs write box /data/other/new.txt
apprights tryfs write box /etc/new.txt
apprights tryfs write box /tmp/new.txt
apprights tryfs write box /bin/evil
apprights tryfs write box /data/box/../other/new.txt
echo ==UNLINK==
apprights tryfs unlink box /etc/secret.txt
apprights tryfs unlink box /data/other/x.txt
apprights tryfs unlink box /data/box/new.txt
echo ==LINK==
apprights tryfs link box /data/box/ln
echo ==FREE==
apprights tryfs read - /etc/secret.txt
apprights tryfs write - /data/other/new.txt
apprights tryfs unlink - /data/other/new.txt
apprights tryfs link - /data/ln
apprights tryfs read plain /etc/secret.txt
apprights tryfs write plain /etc/new.txt
apprights tryfs read sysapp /etc/secret.txt
apprights tryfs read unknown /etc/secret.txt
echo ==HOME==
apprights tryfs read boxhome /etc/secret.txt
apprights set boxhome fs.home
apprights tryfs read boxhome /etc/secret.txt
apprights tryfs write boxhome /data/other/new.txt
apprights set boxhome
apprights tryfs read boxhome /etc/secret.txt
apprights tryfs write boxhome /data/other/new2.txt
echo ==END==
EOS
cat > "$TMPD/s3.sh" <<'EOS'
echo ==NOLOAD==
apprights tryfs read box /etc/secret.txt
echo ==END==
EOS
mkimg() {
    python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /apps/ /data/ /data/other/ /data/dokumente/ \
        "/etc/secret.txt=$TMPD/secret.txt" "/data/dokumente/doc.txt=$TMPD/doc.txt" "/data/other/x.txt=$TMPD/other.txt" \
        /apps/box.osp/ /apps/boxhome.osp/ /apps/plain.osp/ /apps/sysapp.osp/ \
        "/apps/box.osp/INFO=$TMPD/bd/box.info" "/apps/boxhome.osp/INFO=$TMPD/bd/boxhome.info" \
        "/apps/plain.osp/INFO=$TMPD/bd/plain.info" "/apps/sysapp.osp/INFO=$TMPD/bd/sysapp.info" \
        "/apps/sysapp.osp/SYSTEM=$TMPD/bd/SYSTEM" \
        $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
        "/t/s1.sh=$TMPD/s1.sh" "/t/s3.sh=$TMPD/s3.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
}
runvm() {
    timeout 170 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$1" -m 512 \
        -append "osum vfs script=sh /t/$3;exit" \
        -serial "file:$TMPD/$2.raw" -display none -no-reboot \
        -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$2.raw" > "$TMPD/$2.klar"
}
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
fsl() { grep -a '^tryfs: ' "$1" | sed 's/^tryfs: //' | tr '\n' ' '; }

mkimg
runvm "$TMPD/k0.img" b1 s1.sh
O="$TMPD/b1.klar"
for pair in "LOAD READ" "READ WRITE" "WRITE UNLINK" "UNLINK LINK" "LINK FREE" "FREE HOME" "HOME END"; do
    set -- $pair; part "$O" "$1" "$2" > "$TMPD/p_$1.txt"
done
has "$TMPD/p_LOAD.txt" "apprights: load 3 ceilings" "load: 3 ceilings (box, boxhome, plain; SYSTEM bundle has none)"
has "$TMPD/p_LOAD.txt" "app box " "list shows box"
[ "$(fsl "$TMPD/p_READ.txt")" = "DENY DENY DENY DENY DENY OK OK OK " ] && ok "read: secret/documents/other app/dot-dot escapes DENY; /data, /bin, bundle OK" || bad "read lines: '$(fsl "$TMPD/p_READ.txt")'"
[ "$(fsl "$TMPD/p_WRITE.txt")" = "OK OK DENY DENY DENY DENY DENY " ] && ok "write: only /data/box OK (own file reads back); other app, /etc, /tmp, /bin, dot-dot DENY" || bad "write lines: '$(fsl "$TMPD/p_WRITE.txt")'"
[ "$(fsl "$TMPD/p_UNLINK.txt")" = "DENY DENY OK " ] && ok "unlink: outside DENY, own file OK" || bad "unlink lines: '$(fsl "$TMPD/p_UNLINK.txt")'"
[ "$(fsl "$TMPD/p_LINK.txt")" = "DENY " ] && ok "symlink DENY even inside the data folder" || bad "link lines: '$(fsl "$TMPD/p_LINK.txt")'"
[ "$(fsl "$TMPD/p_FREE.txt")" = "OK OK OK OK OK OK OK OK " ] && ok "person's process, unsandboxed app, SYSTEM bundle, unknown app: never gated" || bad "free lines: '$(fsl "$TMPD/p_FREE.txt")'"
[ "$(fsl "$TMPD/p_HOME.txt")" = "DENY OK OK DENY DENY " ] && ok "fs.home: DENY before, OK/OK after grant, DENY/DENY after revoke" || bad "home lines: '$(fsl "$TMPD/p_HOME.txt")'"

python3 - "$FSP" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
a = "    let app: u64 = policy.label_app(label)\n    if app == 0 {\n        return 0\n    }\n    if !policy.confined(app) {"
assert a in s
open(p, 'w').write(s.replace(a, "    return 0\n    let app: u64 = policy.label_app(label)\n    if app == 0 {\n        return 0\n    }\n    if !policy.confined(app) {", 1))
PYEOF
./tools/build-kernel.sh "$TMPD/ka.img" --stufe 0 > "$TMPD/ka.txt" 2>&1 \
    && ok "(a) counter-probe kernel builds" || { bad "(a) kernel"; tail -8 "$TMPD/ka.txt"; }
cp "$TMPD/fsp.orig" "$FSP"
if [ -s "$TMPD/ka.img" ]; then
    mkimg; runvm "$TMPD/ka.img" ba s1.sh
    part "$TMPD/ba.klar" READ WRITE > "$TMPD/na.txt"
    [ "$(fsl "$TMPD/na.txt")" = "OK OK OK OK OK OK OK OK " ] && ok "(a) COUNTER-PROBE: without the confinement check every read gets through" || bad "(a) counter-probe: '$(fsl "$TMPD/na.txt")'"
fi

python3 - "$SYS" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding='latin-1').read()
a = "&& !appfs.write_ok(state, me, buf) {"
assert s.count(a) == 1
open(p, 'w', encoding='latin-1', newline='').write(s.replace(a, "&& false {", 1))
PYEOF
./tools/build-kernel.sh "$TMPD/kb.img" --stufe 0 > "$TMPD/kb.txt" 2>&1 \
    && ok "(b) counter-probe kernel builds" || { bad "(b) kernel"; tail -8 "$TMPD/kb.txt"; }
cp "$TMPD/sys.orig" "$SYS"
if [ -s "$TMPD/kb.img" ]; then
    mkimg; runvm "$TMPD/kb.img" bb s1.sh
    part "$TMPD/bb.klar" WRITE UNLINK > "$TMPD/nb.txt"
    [ "$(fsl "$TMPD/nb.txt")" = "OK OK DENY DENY DENY OK DENY " ] && ok "(b) COUNTER-PROBE: without the write check at open, a write into the readable system area /bin succeeds ($(fsl "$TMPD/nb.txt"))" || bad "(b) counter-probe: '$(fsl "$TMPD/nb.txt")'"
fi

mkimg
runvm "$TMPD/k0.img" b3 s3.sh
part "$TMPD/b3.klar" NOLOAD END > "$TMPD/r3.txt"
has "$TMPD/r3.txt" "tryfs: OK" "(c) no load after boot: not confined yet (documented limit: load runs at desktop start)"
echo "APPFS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
