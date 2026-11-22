#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir from prep-apps.sh with GUI packages}
OUT=${2:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${2:-}" "$OUT"
EXPECT=${GUIAPPS_EXPECT:-tools/linuxapps/guiapps-expected-red.txt}
CONF=$(realpath --relative-to="$PWD" "${GUIAPPS_CONF:-tools/linuxapps/guiapps.conf}")
EXPECT=$(realpath --relative-to="$PWD" "$EXPECT")
mkdir -p "$OUT/shots"
OUT=$(realpath "$OUT")
NAMES=$(grep -v '^#' "$CONF" | cut -d'|' -f1 | tr '\n' ' ')
bash tools/linuxapps/guiapps-watch.sh "$OUT/run" "$OUT/shots" $NAMES > "$OUT/watch.log" 2>&1 &
WATCHER=$!
python3 -I - "$OUT/sample.pdf" <<'PY'
import sys
body = b"BT /F1 24 Tf 40 100 Td (Hello Osum) Tj ET"
objs = [
    b"<</Type/Catalog/Pages 2 0 R>>",
    b"<</Type/Pages/Kids[3 0 R]/Count 1>>",
    b"<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 200]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>",
    b"<</Length %d>>stream\n" % len(body) + body + b"\nendstream",
    b"<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>",
]
out = b"%PDF-1.4\n"
offsets = []
for i, obj in enumerate(objs, 1):
    offsets.append(len(out))
    out += b"%d 0 obj" % i + obj + b"endobj\n"
xref = len(out)
out += b"xref\n0 6\n0000000000 65535 f \n" + b"".join(b"%010d 00000 n \n" % o for o in offsets)
out += b"trailer<</Root 1 0 R/Size 6>>\nstartxref\n%d\n%%%%EOF\n" % xref
open(sys.argv[1], "wb").write(out)
PY
EXTRA="/etc/guiapps.sh=$PWD/tools/linuxapps/guest-guiapps.sh@755 /etc/guiapps.conf=$PWD/$CONF@644 /usr/share/guiapps/@755 /usr/share/guiapps/sample.pdf=$OUT/sample.pdf@644" \
    SPEC=${SPEC:-$WD/run/spec.txt} GUI=1 GUI_EXTRA="settingsd apprights orientbus" BLOCKS=${BLOCKS:-4800000} INODES=${INODES:-40000} TMO=${TMO:-2400} MEM=${MEM:-3072} DONE=FX-END \
    KARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace script=sh /etc/fx.sh;exit" \
    bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-guiapps-boot.sh "$OUT/run" > "$OUT/run.log" 2>&1
kill "$WATCHER" 2>/dev/null
ser=$OUT/run/ser.clean
SPECS=""
for name in $NAMES; do
    geometry=$(awk -v n="$name" '$0 ~ "^GUIAPP begin "n"$" {on=1; next} $0 ~ "^GUIAPP end "n"$" {on=0} on && /wayd: window c=/ {print}' "$ser" | tail -1 | sed -n 's/.* x=\([0-9]*\) y=\([0-9]*\) inx=\([0-9]*\) iny=\([0-9]*\) w=\([0-9]*\) h=\([0-9]*\).*/\1 \2 \3 \4 \5 \6/p')
    [ -n "$geometry" ] || continue
    set -- $geometry
    SPECS="$SPECS $name:$(($1 + $3)),$(($2 + $4)),$5,$6"
done
python3 -I tools/linuxapps/guiappcheck.py "$OUT/shots" $SPECS > "$OUT/pixels.txt" 2>&1
pass=0
fail=0
printf 'APP-MATRIX name toolkit category starts window drawn input exit\n' > "$OUT/matrix.txt"
while IFS='|' read -r name toolkit category _ _; do
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    section=$(awk -v n="$name" '$0 ~ "^GUIAPP begin "n"$" {on=1; next} $0 ~ "^GUIAPP end "n"$" {on=0} on' "$ser")
    windows=$(grep -ac 'wayd: window c=' <<< "$section")
    state=$(grep -aoE "GUIAPP (alive|exited) $name( rc=[0-9]+)?" <<< "$section" | awk '{print $2 ($4 != "" ? "(" $4 ")" : "")}')
    drawn_ok=$(grep -a "^$name " "$OUT/pixels.txt" | grep -o 'drawn_ok=[01]' | cut -d= -f2)
    input_ok=$(grep -a "^$name " "$OUT/pixels.txt" | grep -o 'input_ok=[01]' | cut -d= -f2)
    starts=no
    [ -n "$state" ] && starts=yes
    win=no
    [ "${windows:-0}" -gt 0 ] && win=yes
    drawn=no
    [ "${drawn_ok:-0}" = 1 ] && drawn=yes
    inp=no
    [ "${input_ok:-0}" = 1 ] && inp=yes
    verdict=ok
    [ "$win" = yes ] && [ "$drawn" = yes ] || verdict=red
    want=ok
    grep -qx "$name" "$EXPECT" && want=red
    echo "APP-MATRIX $name $toolkit $category $starts $win $drawn $inp ${state:-none}" >> "$OUT/matrix.txt"
    if [ "$verdict" = "$want" ]; then pass=$((pass + 1)); printf '  OK    %s is %s (window=%s drawn=%s input=%s)\n' "$name" "$verdict" "$win" "$drawn" "$inp"
    else fail=$((fail + 1)); printf '  FAIL  %s is %s, expected %s (window=%s drawn=%s input=%s)\n' "$name" "$verdict" "$want" "$win" "$drawn" "$inp"; fi
done < "$CONF"
cat "$OUT/matrix.txt"
echo "GUIAPPS-GATE: $pass matched, $fail differ"
[ "$fail" -eq 0 ]
