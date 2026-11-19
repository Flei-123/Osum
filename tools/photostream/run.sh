#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/photostream/run.sh -- jarvisd JPEG photo job: stage times, size options, stream header, refusal without permit.
#
#   bash tools/photostream/run.sh [<workdir>]
set -uo pipefail
cd "$(dirname "$0")/../.."
if [ -n "${1:-}" ]; then W=$1; mkdir -p "$W"; else W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
[ -w /dev/kvm ] && ACC=(-accel kvm -cpu host) || ACC=()

BUILD=${PHOTOSTREAM_BUILD:-}
if [ -z "$BUILD" ]; then
    BUILD=$W/b
    bash tools/bridge/build.sh "$BUILD" 0 > "$W/build.log" 2>&1 && ok "kernel + jarvisd build" || { bad "bridge build"; tail -8 "$W/build.log"; }
fi

cat > "$W/g.sh" <<'G'
echo ==A==
jarvisd -s
jarvisd -j /var/jarvis/a.jpg q=60,w=1280
echo ==B==
jarvisctl screenshot 600
jarvisd -j /var/jarvis/b.jpg q=60,w=1280
echo ==C==
jarvisctl screenshot 600
jarvisd -j /var/jarvis/c.jpg q=50,w=640
echo ==D==
jarvisctl screenshot 600
jarvisd -j /var/jarvis/d.jpg q=40,w=960
echo ==E==
jarvisctl screenshot 600
jarvisd -j /var/jarvis/e.jpg h=1,t=300
echo ==F==
cat /var/jarvis/e.jpg
echo ==G==
exit
G
cat > "$W/rechte.conf" <<'CONF'
server         = 10.9.0.1:8443
servername     = jarvis.test
roots          = /etc/ssl/roots.pem
commands       = no
read           = /var/jarvis/
write          = /var/jarvis/
list           = /var/jarvis/
screenshot     = yes
sysinfo        = yes
max_output     = 65536
max_file       = 4194304
log            = /var/log/jarvisd.log
work_file      = /var/jarvis/output.txt
permit_file    = /var/jarvis/screenshot-permit
CONF
: > "$W/empty.pem"
SPEC="$(cat "$BUILD/spec.txt") /etc/jarvis/permissions.conf=$W/rechte.conf /etc/ssl/roots.pem=$W/empty.pem /t/ /t/g.sh=$W/g.sh"
bash tools/mkfsfi/mkfs.sh build "$W/v.img" 16384 $SPEC > "$W/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$W/mkfs.txt"; }
timeout 240 qemu-system-x86_64 "${ACC[@]}" -kernel "$BUILD/k.mb" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 gfx fbres=1280x800 script=sh /t/g.sh;exit" \
    -serial "file:$W/v.txt" -display none -no-reboot \
    -drive "file=$W/v.img,format=raw,if=ide,index=0" -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$W/q.log" 2>&1
sec() { sed -n "/==$1==/,/==$2==/p" "$W/v.txt" | tr -d '\r'; }
photo() { sec "$1" "$2" | grep -a '^jarvisd: photo' | head -1; }
field() { sed -n "s/.* $1=\([0-9x]*\).*/\1/p" <<< "$2"; }
a=$(sec A B); la=$(photo B C); lb=$(photo C D); lc=$(photo D E); ld=$(photo E F)
echo "$a" | grep -aq 'no screenshot permit' && ok "refused without permit (counter-probe)" || bad "A: refusal missing ($(echo "$a" | tail -2 | tr '\n' ' '))"
for pair in "1280x800:$la:full" "640x400:$lb:640" "960x600:$lc:960"; do
    want=${pair%%:*}; rest=${pair#*:}; line=${rest%:*}; tag=${rest##*:}
    [ "$(field size "$line")" = "$want" ] && ok "$tag: size $want, bytes $(field bytes "$line"), grab $(field grab "$line") ms, scale $(field scale "$line") ms, encode $(field encode "$line") ms" || bad "$tag: expected $want ($line)"
done
[ "$(field bytes "$lb")" -lt "$(field bytes "$la")" ] 2>/dev/null && ok "640 px smaller than 1280 px" || bad "640 px not smaller ($lb | $la)"
[ -n "$ld" ] && ok "stream mode with a different last hash returns a frame at once" || bad "E: no frame ($ld)"
python3 -I - "$W/v.txt" <<'PY' && ok "stream file: J + 20 digits + newline + JPEG start" || bad "F: stream header not found in the output"
import re, sys
d = open(sys.argv[1], 'rb').read()
i = d.find(b'==F==')
m = re.search(rb'J\d{20}\n\xff\xd8\xff', d[i:])
sys.exit(0 if m else 1)
PY
echo "PHOTOSTREAM: $pass passed, $fail failed"
[ "$fail" = 0 ]
