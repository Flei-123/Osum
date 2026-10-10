#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge2/eingabe.sh -- remote input (click/type): config, emergency stop, sign. Acceptance run.
#
#   bash tools/bridge2/eingabe.sh [<workdir>]
#
# 1. config: Justin's permissions file has `input = yes`, the shipped default and the
#    public build have `input = no`; every key of both files is one jarvisd really parses
#    (the German keys of the old files were silently ignored since the English rename).
# 2. VM (KVM, bridge image of tools/bridge/build.sh, script mode):
#    probe injects (kernel permit) -> status says "Sign on screen: YES"
#    EMERGENCY STOP `jarvisctl input off` -> next injection REFUSED (counter-proof: before it worked),
#    status says ENGAGED -> `input on` (root) releases -> injection works again.
# 3. the bar compiles with the red JARVIS field, jarvisd with the stop message.
# The bridge round trip itself (job -> device -> result, input=no refused) is tools/bridge2/kette.sh
# (its permissions file has `input = yes`) -- run it for the full chain.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
if [ -n "${1:-}" ]; then W=$1; mkdir -p "$W"; else W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
[ -w /dev/kvm ] && ACC=(-accel kvm -cpu host) || ACC=()

echo "== 1. config files =="
chk() { # <file> <expected input value>
    local f=$1 want=$2
    python3 - "$f" "$want" <<'PY'
import re, sys
src = open("kernel/app/jarvisd.fi", encoding="latin-1").read()
keys = set(re.findall(r'var s_\w+: \[u8; \d+\] = "(\w+)\\0', src))
bad = []; inp = None
for l in open(sys.argv[1], encoding="utf-8"):
    m = re.match(r'^(\w+)\s*=\s*(.*?)\s*$', l)
    if not m: continue
    if m.group(1) not in keys: bad.append(m.group(1))
    if m.group(1) == "input": inp = m.group(2)
if bad: print("unknown keys:", ",".join(bad)); sys.exit(1)
if inp != sys.argv[2]: print("input =", inp); sys.exit(2)
PY
}
chk assets/jarvis/rechte-justin.conf yes && ok "rechte-justin.conf: all keys parsed by jarvisd, input = yes" || bad "rechte-justin.conf (keys or input)"
chk assets/jarvis/rechte.conf no && ok "rechte.conf (shipped default): all keys parsed, input = no" || bad "rechte.conf (keys or input)"
grep -q 'IMAGE_PROFILE" = public \] && grep -Eq' tools/usbimg/build.sh && ok "build.sh refuses input = yes in the public profile" || bad "no public guard in build.sh"
grep -q '^input      = no' tools/usbimg/build.sh && ok "build.sh default permissions: input = no" || bad "build.sh default lacks input = no"

echo "== 2. build =="
bash vendor/firn/fetch-firnc.sh > "$W/fetch.log" 2>&1
bash tools/bridge/build.sh "$W/b" 0 > "$W/bau.log" 2>&1 && ok "kernel + jarvisctl + jarvisd build" || { bad "bridge build"; tail -8 "$W/bau.log"; }
export FIRNLIB="$ROOT/lib"
vendor/firn/bin/firnc kernel/user/taskbar.fi -o "$W/tb.elf" > "$W/tb.log" 2>&1 && ok "taskbar (red JARVIS field) compiles" || { bad "taskbar does not compile"; head -8 "$W/tb.log"; }

echo "== 3. emergency stop in the VM =="
cat > "$W/g.sh" <<'G'
echo ==A==
jarvisctl input
jarvisctl input key 30 0
echo ==B==
jarvisctl input
jarvisctl input off
echo ==C==
jarvisctl input key 30 0
jarvisctl input
echo ==D==
jarvisctl input on
jarvisctl input key 30 0
jarvisctl input
echo ==E==
exit
G
SPEC="/bin/ /etc/ /etc/jarvis/ /var/ /var/jarvis/ /t/"
for p in sh ls cat echo jarvisctl; do SPEC="$SPEC /bin/$p=$W/b/$p.elf"; done
cp assets/jarvis/rechte-justin.conf "$W/rechte.conf"
SPEC="$SPEC /etc/jarvis/permissions.conf=$W/rechte.conf /t/g.sh=$W/g.sh"
python3 tools/osum/mkfs.py build "$W/v.img" 16384 $SPEC > "$W/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$W/mkfs.txt"; }
timeout 150 qemu-system-x86_64 "${ACC[@]}" -kernel "$W/b/k.mb" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 gfx fbres=1280x800 script=sh /t/g.sh;exit" \
    -serial "file:$W/v.txt" -display none -no-reboot \
    -drive "file=$W/v.img,format=raw,if=ide,index=0" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$W/q.log" 2>&1
sec() { sed -n "/==$1==/,/==$2==/p" "$W/v.txt" | tr -d '\r'; }
a=$(sec A B); b=$(sec B C); c=$(sec C D); d=$(sec D E)
echo "$a" | grep -aq 'Sign on screen:   no' && ok "before: no sign (nobody typed)" || bad "A: sign should be 'no'"
echo "$a" | grep -aq 'injected' && ok "probe injects a key with input permitted" || bad "A: no 'injected'"
echo "$b" | grep -aq 'Sign on screen:   YES' && ok "after the injection the kernel says: sign on screen = YES" || bad "B: sign not YES"
echo "$b" | grep -aq 'emergency stop ON' && ok "jarvisctl input off engages the emergency stop" || bad "B: stop not engaged"
echo "$c" | grep -aq 'injected' && bad "COUNTER-PROOF: injection still worked after the stop" || ok "after the stop the injection is REFUSED"
echo "$c" | grep -aq 'ENGAGED' && ok "status shows the stop: ENGAGED" || bad "C: status lacks ENGAGED"
echo "$d" | grep -aq 'emergency stop off' && echo "$d" | grep -aq 'injected' && ok "input on (root) releases it, injection works again" || bad "D: release failed"

echo; echo "EINGABE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
