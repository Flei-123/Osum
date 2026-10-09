#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/comp/chrome.sh -- docs/COMPOSITOR.md stage S6b: THE FRAME, THE TITLE BAR, THE CAPTION BUTTONS AND THE TITLE TEXT IN RING 3.
#
#   bash tools/comp/chrome.sh        (start it through /root/jarvis/bin/heavy; capture.sh then builds in its own $TMPDIR)
#
# `wmd` (kernel/user/wmd.fi) composes the chrome of every plain framed window itself (numbers from the chrome page, WM_TABLE with argument 1) and
# judges the WHOLE outer rectangle of the window against the picture of the kernel (wm.fi = the oracle).
#
# Gates: chrome composed in at least one window per cycle with real pixel counts (frame, title text, caption symbols); NOT ONE judged pixel differs;
# the area judged now includes the frame and the bar (the judged area is bigger than the client area alone).
# THE LESSON OF S6a (a judge that shares a bug with the oracle sees nothing): three more checks that do not go through the oracle:
#   (1) the PICTURE ALONE: tools/comp/chrome_check.py reads the kernel's screenshot and asks whether the bar has the table's height and colour, the
#       title text stands inside it and about in the middle, each of the three buttons carries a symbol in the middle of its cell, the corner is round;
#   (2) a HOVER scene: the pointer stands on the close button; the picture must show the red face and wmd must still judge 0 differences;
#   (3) the COUNTER-PROOF `nochrome=1`: wmd leaves a magenta hole where the chrome goes and still judges it: the judge MUST see thousands of pixels.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

mkdreh() { # mkdreh <file> <pointer x,y>
    cat > "$1" <<DREH
warteauf 'launcher: ready' || 90
warte 25
klick 24,780
warte 4
klickauf start_File Explorer
warte 14
fahre $2
warte 40
foto s
taste f12
warte 3
DREH
}
mkdreh "$D/dreh.txt" 1250,780
run() { # run <name> <extra words> [capture argument]  (DREH=<file> picks another drehbuch)
    bash tools/design/capture.sh "$D/$1" uitrace=yes accel=kvm drehbuch="${DREH:-$D/dreh.txt}" \
        "extra=wigapp=/bin/wmd${WMDARGS:+,$WMDARGS} wighalt=150 $2" "progs=desktop taskbar settings launcher explorer edit sh echo ls cat theme wmd" "${@:3}" \
        > "$D/$1.log" 2>&1
    grep -a "FEHLGESCHLAGEN" "$D/$1.log" | head -3
}
stats() { # stats <serial>  ->  cycles, max compared, sum compared, sum differ, median compose_us
    grep -a '^wmd: cycle ' "$1" | awk '{
        n++; for (i = 1; i <= NF; i++) { split($i, kv, "=");
            if (kv[1] == "compared") { c = kv[2]; if (c > cm) cm = c; cs += c }
            if (kv[1] == "differ") ds += kv[2]
            if (kv[1] == "compose_us") { u = kv[2]; us[n] = u } }
    } END { m = 0; if (n > 0) { for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (us[j] < us[i]) { t = us[i]; us[i] = us[j]; us[j] = t }; m = us[int((n + 1) / 2)] } printf "%d %d %d %d %d\n", n, cm, cs, ds, m }'
}
maxkv() { # maxkv <serial> <key>
    grep -a '^wmd: cycle ' "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1 == k && $2 + 0 > m { m = $2 + 0 } END { print m + 0 }'
}
sumkv() {
    grep -a '^wmd: cycle ' "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1 == k { s += $2 } END { print s + 0 }'
}

echo "== 1. the desktop with the chrome composed in ring 3 =="
run chr "" window_alpha=100 shadow=on
S="$D/chr/serial.txt"
grep -a '^wmd:' "$S" | sed 's/^/        /' | head -60
grep -aq '^wmd: ready screen=' "$S" && ok "wmd found the screen and the window table page" || bad "wmd did not start ($(grep -a '^wmd:' "$S" | head -2 | tr '\n' ' '))"
read N CM CS DS UM < <(stats "$S")
CHW=$(maxkv "$S" chrome); CHP=$(maxkv "$S" chromepx); TXP=$(maxkv "$S" titlepx); CPP=$(maxkv "$S" capspx)
echo "        cycles=$N max_area=$CM compared_sum=$CS differ_sum=$DS compose_us_median=$UM chrome_windows=$CHW chrome_px=$CHP title_px=$TXP symbol_px=$CPP"
[ "${N:-0}" -ge 5 ] && ok "$N stable cycles were judged" || bad "only ${N:-0} stable cycles"
[ "${CHW:-0}" -ge 1 ] && ok "wmd composed the chrome of $CHW window(s) in one cycle" || bad "no chrome was composed (chrome=$CHW)"
[ "${CHP:-0}" -ge 20000 ] && ok "the chrome wrote $CHP pixels in one cycle" || bad "the chrome wrote only ${CHP:-0} pixels"
[ "${TXP:-0}" -ge 60 ] && ok "the title text wrote $TXP pixels" || bad "the title text wrote only ${TXP:-0} pixels"
[ "${CPP:-0}" -ge 60 ] && ok "the caption symbols wrote $CPP pixels" || bad "the caption symbols wrote only ${CPP:-0} pixels"
[ "${CS:-0}" -gt 0 ] && [ "${DS:-1}" = 0 ] && ok "$CS pixels judged over all cycles, 0 differ from the kernel's picture (frame, bar, buttons, title included)" || bad "differing pixels: ${DS:-?} of ${CS:-0}"
[ "${UM:-99999}" -le 8000 ] && ok "composing a frame in ring 3 took ${UM} us (median of the cycles) (budget 8000)" || bad "composing took ${UM:-?} us, median (budget 8000)"

# every window that had its chrome composed prints its geometry; the picture must show each of them (the terminal's own title bar, the file manager's
# own strip with the server's buttons over it)
# (the LAST line of each window: its focus changes while the scene runs, the picture shows the end state)
GEOS=$(grep -a '^wmd: chrome-geo ' "$S" | cut -d' ' -f3- | awk '{ k = $3 " " $4 " " $5 " " $6; if (!(k in last)) order[++n] = k; last[k] = $0 } END { for (i = 1; i <= n; i++) print last[order[i]] }')
NG=$(echo "$GEOS" | grep -c . || true)
[ "${NG:-0}" -ge 2 ] && ok "$NG windows had their chrome composed (a server title bar and a window with its own strip)" || bad "only ${NG:-0} chrome-geo lines"
GEO=""
NSTRIP=0; NBAR=0
while read -r LINE; do
    [ -n "$LINE" ] || continue
    set -- $LINE
    echo "        chrome-geo: $LINE"
    [ "$2" = 1 ] && NSTRIP=$((NSTRIP+1)) || NBAR=$((NBAR+1))
    [ "$1" = 1 ] && GEO="$LINE"
    # the other windows' rectangles: pixels inside them are not this window's (the file manager overlaps the terminal's bar)
    OCC=$(echo "$GEOS" | awk -v me="$3 $4 $5 $6" '{ if (($3 " " $4 " " $5 " " $6) != me) printf "%s,%s,%s,%s;", $3, $4, $5, $6 }')
    OCC="$OCC" python3 tools/comp/chrome_check.py "$D/chr/s.ppm" $LINE > "$D/pic.txt" 2>&1 && ok "the PICTURE shows the chrome of this window where the numbers say" || bad "the picture does not show the chrome the numbers promise"
    sed 's/^/        /' "$D/pic.txt"
done <<< "$GEOS"
[ "$NBAR" -ge 1 ] && [ "$NSTRIP" -ge 1 ] && ok "the picture was checked for a window with a server title bar and for one with its own strip" || bad "picture checks: $NBAR with a title bar, $NSTRIP with its own strip"

echo "== 2. the pointer on the close button: the red face, still 0 differences =="
if [ -n "$GEO" ]; then
    read _F _C GX GY GOW GOH GBO GTH GCW GSK _REST <<< "$GEO"
    # on the close button but away from its symbol in the middle (the pointer arrow reaches 12 points right and 19 down)
    CXP=$((GX + GOW - GBO - GCW + GCW * 3 / 4))
    CYP=$((GY + GBO + 8))
    mkdreh "$D/dreh2.txt" "$CXP,$CYP"
    DREH="$D/dreh2.txt" run hov "" window_alpha=100 shadow=on
    S2="$D/hov/serial.txt"
    read N2 CM2 CS2 DS2 UM2 < <(stats "$S2")
    HV=$(maxkv "$S2" hover)
    echo "        cycles=$N2 compared_sum=$CS2 differ_sum=$DS2 hover_code_max=$HV pointer=$CXP,$CYP"
    [ "${HV:-0}" -ge 1 ] && ok "the chrome page carried a hovered button (code $HV)" || bad "no cycle saw a hovered button"
    [ "${CS2:-0}" -gt 0 ] && [ "${DS2:-1}" = 0 ] && ok "hover: $CS2 pixels judged, 0 differ" || bad "hover: differing pixels: ${DS2:-?} of ${CS2:-0}"
    GEO2=$(grep -a '^wmd: chrome-geo 1 ' "$S2" | tail -n 1 | cut -d' ' -f3-)
    if [ -n "$GEO2" ] && [ -s "$D/hov/s.ppm" ]; then
        PTR="$CXP,$CYP" python3 tools/comp/chrome_check.py "$D/hov/s.ppm" $GEO2 hover > "$D/pic2.txt" 2>&1 && ok "hover: the PICTURE shows the red close button and the other symbols" || bad "hover: the picture is wrong"
        sed 's/^/        /' "$D/pic2.txt"
    else
        bad "hover: no chrome-geo line or no picture"
    fi
else
    bad "hover: no geometry from section 1"
fi

echo "== 3. counter-proof: nochrome -- a magenta hole where the chrome goes, still judged =="
WMDARGS="nochrome=1" run nch "" window_alpha=100 shadow=on
S3="$D/nch/serial.txt"
read N3 CM3 CS3 DS3 UM3 < <(stats "$S3")
CHP3=$(sumkv "$S3" chrome)
echo "        cycles=$N3 compared_sum=$CS3 differ_sum=$DS3 chrome_windows=$CHP3"
[ "${CHP3:-1}" = 0 ] && ok "nochrome: wmd composed the chrome of no window" || bad "nochrome: wmd composed the chrome of $CHP3 windows anyway"
[ "${DS3:-0}" -ge 5000 ] && ok "nochrome: the judge sees the missing chrome ($DS3 differing pixels)" || bad "nochrome: only ${DS3:-0} differing pixels, the chrome is not judged"

echo
echo "CHROME: $pass passed, $fail failed"
[ "$fail" = 0 ]
