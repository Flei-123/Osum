#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sdk/run.sh -- THE SDK, MEASURED (docs/SDK.md).
#   bash tools/sdk/run.sh      (VM part: /root/jarvis/bin/heavy bash tools/sdk/run.sh)
# 1 manifest lint: the template passes, 14 broken manifests are each refused for the RIGHT reason
# 2 osdk new/check/build for kind app and kind service (net= derived from perm)
# 3 guest: the SDK-built app runs from /apps/hello.osp/start; the SDK-built bus service
#   answers rpcc (kernel/user/rpc.fi) with "pong"
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$PWD/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
O="python3 tools/sdk/osdk.py"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
[ -x vendor/firn/bin/firnc ] || { echo "SDK: firnc0 missing"; exit 1; }

echo "== 1. manifest lint =="
$O new org.example.hello --dir "$TMPD/hello" >/dev/null && $O check "$TMPD/hello" >/dev/null && ok "template passes" || bad "template refused"
# <mutation (sed on INFO)> | <expected text in the refusal>
while IFS='|' read -r sedx want; do
    rm -rf "$TMPD/m"; cp -r "$TMPD/hello" "$TMPD/m"; sed -i "$sedx" "$TMPD/m/INFO"
    out=$($O check "$TMPD/m" 2>&1); rc=$?
    if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$want"; then ok "refused: $want"; else bad "not refused for '$want' ($sedx)"; fi
done <<'EOT'
/^name=/d|missing required key 'name'
s/^id=.*/id=Hello/|id 'Hello'
s/^id=.*/id=org.example.explorer/|collides with a system app
s/^version=.*/version=1.0/|version '1.0'
s/^manifest=2/manifest=3/|manifest=3
s/^perm=.*/perm=root/|unknown permission 'root'
s/^perm=.*/perm=net,net/|permission 'net' twice
s/^perm=.*/perm=net\nnet=none/|contradicts perm
$a service=other.thing|outside the app's namespace
$a service=hello.averyveryverylongservice|at most 16 octets
$a wat=1|unknown key 'wat'
$a version=0.2.0|duplicate key 'version'
$a opens=.txt|opens '.txt'
$a needs=os>1|needs 'os>1'
EOT
{ printf '#%01100d\n' 0; printf 'name=Z\ninfo=y\nfassung=1\n'; } > "$TMPD/long"
out=$($O check "$TMPD/long" 2>&1); echo "$out" | grep -qF "launcher keys end at octet" && ok "late launcher keys are caught (1023 octets)" || bad "long-head INFO accepted"

echo "== 2. new / check / build =="
$O new org.example.pingsvc --kind service --dir "$TMPD/svc" --perm net >/dev/null || bad "new service"
$O build "$TMPD/hello" --out "$TMPD/o1" > "$TMPD/b1.txt" 2>&1 && ok "app builds: $(tail -1 "$TMPD/b1.txt" | cut -c1-90)" || { bad "app build"; cat "$TMPD/b1.txt"; }
$O build "$TMPD/svc" --out "$TMPD/o2" > "$TMPD/b2.txt" 2>&1 && ok "service (rpc.fi) builds: $(tail -1 "$TMPD/b2.txt" | cut -c1-90)" || { bad "service build"; cat "$TMPD/b2.txt"; }
grep -q '^net=none' "$TMPD/o1/apps/hello.osp/INFO" && ok "no net perm -> net=none in the bundle INFO" || bad "net=none missing"
grep -q '^net=real' "$TMPD/o2/apps/pingsvc.osp/INFO" && ok "perm net -> net=real" || bad "net=real missing"
grep -q SYSTEM "$TMPD/o1/mkfs.lines" && bad "SYSTEM marker in a third-party bundle" || ok "no SYSTEM marker"
printf 'x' > "$TMPD/hello/src/rpc.fi"; out=$($O build "$TMPD/hello" --out "$TMPD/o3" 2>&1); echo "$out" | grep -qF "shadows an SDK module" && ok "src file shadowing an SDK module refused" || bad "shadowing accepted"
rm "$TMPD/hello/src/rpc.fi"

echo "== 3. guest =="
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SDK: skipped guest, qemu missing"; echo "SDK: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit; }
mkdir -p "$TMPD/bin"
bash tools/sync/build.sh "$TMPD/bin" 0 sh ls cat echo sleep rpcc > "$TMPD/bb.txt" 2>&1 || { bad "guest tools build"; cat "$TMPD/bb.txt"; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 && ok "kernel builds" || bad "kernel build"
cat > "$TMPD/s.sh" <<'EOS'
echo ==APP==
/apps/hello.osp/start
echo rc=$?
cat /apps/hello.osp/INFO
echo ==SVC==
/apps/pingsvc.osp/start 3000 &
sleep -m 400
rpcc one pingsvc ping
rpcc one pingsvc "echo sdk works"
rpcc one pingsvc nonsense
EOS
A=(build "$TMPD/d.img" 8000 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /var/log/)
for p in sh ls cat echo sleep rpcc; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
A+=(/apps/)
for o in o1 o2; do while read -r l; do [ "$l" = /apps/ ] && continue; A+=("$l"); done < "$TMPD/$o/mkfs.lines"; done
A+=("/t/s.sh=$TMPD/s.sh")
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; }
timeout 150 qemu-system-x86_64 -accel "$( [ -e /dev/kvm ] && echo kvm || echo tcg )" -smp 1 -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd bus script=sh /t/s.sh;exit" -serial "file:$TMPD/g.txt" -display none -no-reboot \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/g.txt" > "$TMPD/g.klar"
grep -aq '^hello from hello' "$TMPD/g.klar" && grep -aq '^rc=0' "$TMPD/g.klar" && ok "the SDK-built app runs from /apps/hello.osp/start" || bad "app did not run"
grep -aq '^manifest=2' "$TMPD/g.klar" && grep -aq '^id=org.example.hello' "$TMPD/g.klar" && ok "bundle INFO with manifest v2 is on the image" || bad "INFO missing"
awk '/==SVC==/{f=1} f' "$TMPD/g.klar" > "$TMPD/svc.txt"
grep -aq '^pong' "$TMPD/svc.txt" && ok "SDK-built service answers 'ping' with 'pong' over rpc.fi" || bad "no pong"
grep -aq '^sdk works' "$TMPD/svc.txt" && ok "echo through the service" || bad "no echo"
grep -aq '^code 2' "$TMPD/svc.txt" && ok "unknown verb -> status 2 (E_NOMETHOD)" || bad "no E_NOMETHOD"
echo "SDK: $pass passed, $fail failed"
[ "$fail" = 0 ]
