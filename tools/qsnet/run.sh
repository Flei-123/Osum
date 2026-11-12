#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
SCALES=${*:-"1 2"}
MODES=${QSNET_MODES:-"dark light"}

cat > "$TMPD/script.txt" <<'SCRIPT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 5
taste meta_l-a
warteauf 'qs: open' || 30
warte 2
foto 01-open
klickauf qskachel1
warteauf 'qsnet: page open' || 30
warte 3
foto 02-net
taste esc
warte 3
SCRIPT

diff_px() {
    python3 -I - "$1" "$2" <<'PY'
import sys
def load(p):
    d = open(p, "rb").read()
    f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f, d[at+1:]
fa, a = load(sys.argv[1]); fb, b = load(sys.argv[2])
if fa != fb:
    print(-1); sys.exit()
n = sum(1 for i in range(0, len(a) - 2, 3) if a[i:i+3] != b[i:i+3])
print(n)
PY
}

for mode in $MODES; do
for sc in $SCALES; do
    echo "== ui_scale $sc, $mode =="
    res=1280x800; [ "$sc" != 1 ] && res=1920x1080
    D="$TMPD/$mode-s$sc"
    for try in 1 2; do
        rm -rf "$D"
        bash tools/design/eh6.sh "$D" res=$res uiscale=$sc mode=$mode accel=kvm tafel=nein drehbuch="$TMPD/script.txt" \
            > "$TMPD/$mode-s$sc.log" 2>&1
        grep -aq 'qsnet: page open' "$D/serial.txt" 2>/dev/null && break
    done
    S="$D/serial.txt"
    if [ -n "${QSNET_OUT:-}" ]; then
        mkdir -p "$QSNET_OUT/$mode-s$sc"; cp "$D"/*.ppm "$S" "$QSNET_OUT/$mode-s$sc/" 2>/dev/null
    fi
    if [ ! -s "$D/02-net.ppm" ]; then bad "scale $sc: no pictures"; continue; fi
    if grep -aq 'qsnet: page open' "$S"; then ok "scale $sc: a click on the network tile opens the network page"
    else bad "scale $sc: no 'qsnet: page open'"; fi
    if grep -aqE 'qsnet: state=[0-9]+ kind=[0-9]+ rows=[0-9]+' "$S"; then ok "scale $sc: the page reports state, link kind and network count"
    else bad "scale $sc: no state report"; fi
    n=$(diff_px "$D/01-open.ppm" "$D/02-net.ppm")
    if [ "$n" -gt 5000 ]; then ok "scale $sc: the panel picture changed ($n pixels)"
    else bad "scale $sc: the panel looks the same after the click ($n pixels)"; fi
    n0=$(diff_px "$D/01-open.ppm" "$D/01-open.ppm")
    if [ "$n0" = 0 ]; then ok "scale $sc: counter-proof -- identical pictures differ by 0 pixels"
    else bad "scale $sc: counter-proof broken ($n0)"; fi
    if grep -aq 'qs: closed by escape' "$S"; then ok "scale $sc: Escape still closes the panel"
    else bad "scale $sc: Escape did not close the panel"; fi
    tiles=$(grep -a '^qs: kachel n=' "$S" | grep -ao 'kachel n=[0-9]*' | sort -u | wc -l)
    if [ "$tiles" -ge 3 ] && [ "$tiles" -le 8 ]; then ok "scale $sc, $mode: $tiles tiles, only working ones (3 to 8)"
    else bad "scale $sc, $mode: $tiles tiles reported"; fi
done
done
bash tools/qsnet/wifi.sh ${SCALES%% *} || fail=$((fail+1))
echo; echo "QSNET: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
