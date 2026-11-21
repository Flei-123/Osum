#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnt() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
PROGS="sh ls cat echo sleep orientbus act settingsd xrcli"
echo "== 1. build =="
. tools/lib/firnenv.sh
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 && ok "programs build" \
    || { bad "programs do not build"; tail -8 "$TMPD/b.txt"; echo "XRCLI: $pass passed, $fail failed"; exit 1; }
bash tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 && ok "kernel builds" \
    || { bad "kernel does not build"; tail -5 "$TMPD/k.txt"; echo "XRCLI: $pass passed, $fail failed"; exit 1; }

printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
cat > "$TMPD/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
settingsd serve 0 &
sleep 1
echo ==STATUS==
xremote status
echo ==ID==
xremote id
echo ==SHORT==
xremote fixed abc
echo ==ON==
xremote on
echo ==USAGE==
xremote bogus
echo ==START==
tool hello-from-start
echo ==MISSING==
nosuchtool
echo ==DONE==
act stop
EOS

image() { # out with-bundle
    local out=$1 bundle=$2
    local A=(build "$out" 16384 /bin/ /t/ /tmp/ /var/ /var/log/ /etc/ /etc/actions.d/ /etc/orientbus/ /apps/
        "/etc/settings.schema=etc/settings.schema"
        "/etc/actions.d/settings.actions=etc/actions.d/settings.actions"
        "/etc/orientbus/policy=etc/orientbus/policy"
        "/etc/passwd=$TMPD/passwd" "/t/g.sh=$TMPD/g.sh")
    local p
    for p in sh ls cat echo sleep orientbus act settingsd; do A+=("/bin/$p=$TMPD/bin/$p.elf@755:0:0"); done
    if [ "$bundle" = 1 ]; then
        A+=(/apps/xremote.osp/ /apps/xremote.osp/bin/ "/apps/xremote.osp/bin/xremote=$TMPD/bin/xrcli.elf@755:0:0"
            /apps/tool.osp/ "/apps/tool.osp/start=$TMPD/bin/echo.elf@755:0:0")
    fi
    bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1
}
run_case() {
    local name=$1
    cp "$TMPD/$name.img" "$TMPD/live-$name.img"
    timeout 240 qemu-system-x86_64 -kernel "$TMPD/k0.img" -m 256 \
        -append "osum vfs bus nokbd nosched noproc nofs noring3 script=sh /t/g.sh;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rm -f "$TMPD/live-$name.img"
}
echo "== 2. images =="
image "$TMPD/with.img" 1 && ok "image with the xremote bundle" || { bad "mkfs with"; tail -3 "$TMPD/mkfs.txt"; }
image "$TMPD/without.img" 0 && ok "image without a bundle" || bad "mkfs without"

echo "== 3. boot with the bundle =="
run_case with
W="$TMPD/with.txt"
has "$W" "usage: xremote [status|id|password|fixed <pw>|random|on|off]" "a bare command name finds /apps/xremote.osp/bin/xremote"
has "$W" "enabled:" "status prints the enabled line"
has "$W" "service:" "status prints the service line"
has "$W" "password needs 8-32" "a short fixed password is refused locally"
has "$W" "needs a confirmation" "switching on is a critical setting and asks for a confirmation"
has "$W" "hello-from-start" "a bundle without bin/<name> falls back to its start entry"
has "$W" "sh: cannot run nosuchtool" "an unknown command still fails"

echo "== 4. COUNTER-PROOF: boot without the bundle =="
run_case without
W="$TMPD/without.txt"
has "$W" "sh: cannot run xremote" "without the bundle the command is not found"
hasnt "$W" "usage: xremote" "and the xremote command never ran"

echo
echo "XRCLI: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
