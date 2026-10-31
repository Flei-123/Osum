#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
MOCK=${QSMEDIA_MOCK:-/root/jarvis/data/projects_kb/orientos/reports/mockups/qsmedia.png}
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat orientbus act mediad"
cat > "$TMPD/dreh.txt" <<'DEOF'
warteauf 'launcher: ready' || 120
warte 6
klick 300,200
warte 1
tippe act call media.publish title=Demo-Song state=playing artist=Tester app=Demo can_prev=1 can_next=1
taste ret
warte 4
taste meta_l-a
warteauf 'qs: open' || 30
warte 3
foto 01-open
DEOF
bash tools/design/eh6.sh "$TMPD/o" res=1280x800 uiscale=1 mode=light accel=kvm progs="$PROGS" drehbuch="$TMPD/dreh.txt" > "$TMPD/o.log" 2>&1
S="$TMPD/o/serial.txt"
if [ -n "${QSMEDIA_OUT:-}" ]; then mkdir -p "$QSMEDIA_OUT"; cp "$TMPD"/o/*.ppm "$S" "$TMPD/o.log" "$QSMEDIA_OUT/" 2>/dev/null; fi
if [ ! -s "$TMPD/o/01-open.ppm" ]; then
    bad "no picture: $(tail -n 3 "$TMPD/o.log" | tr '\n' ' ')"
    echo "QSMEDIA-SSIM: $pass passed, $fail failed"; exit 1
fi
python3 -I tools/design/ppm2png.py "$TMPD/o/01-open.ppm" "$TMPD/shot.png" > /dev/null 2>&1
geo=$(grep -aoE 'qs: geo x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$S" | tail -1)
row=$(grep -aoE 'qs: medien +x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$S" | tail -1)
if [ -z "$geo" ] || [ -z "$row" ]; then
    bad "no panel geometry or media row report"
else
    gx=$(echo "$geo" | sed -E 's/.* x=([0-9]+).*/\1/'); gy=$(echo "$geo" | sed -E 's/.* y=([0-9]+).*/\1/')
    rx=$(echo "$row" | sed -E 's/.* x=([0-9]+).*/\1/'); ry=$(echo "$row" | sed -E 's/.* y=([0-9]+).*/\1/')
    sc=$(python3 -I tools/mockup/ssim.py "$MOCK" "$TMPD/shot.png" "$((gx + rx - 8)),$((gy + ry - 8))" "$TMPD/crop.png" 2>&1 | tail -1)
    [ -n "${QSMEDIA_OUT:-}" ] && cp "$TMPD/crop.png" "$QSMEDIA_OUT/crop.png" 2>/dev/null
    v=$(echo "$sc" | sed -n 's/.*"ssim": *\([0-9.]*\).*/\1/p')
    python3 -I -c "import sys; sys.exit(0 if float('${v:-0}') >= 0.95 else 1)" && ok "mockup match: $sc" || bad "mockup match: $sc"
fi
echo; echo "QSMEDIA-SSIM: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
