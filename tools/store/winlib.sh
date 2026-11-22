# SPDX-License-Identifier: GPL-2.0-only
# helpers of the Store window gate parts; sourced by tools/store/run.sh (uses TMPD SOCK QPID SHOTS MODE RES MARK)
wclean() { tr -cd '\11\12\15\40-\176\200-\377' < "$TMPD/w.txt"; }
waitfor() { local i=0; while [ $i -lt $(( $2 * 5 )) ]; do grep -qaF -- "$1" "$TMPD/w.txt" 2>/dev/null && return 0; kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.2; i=$((i + 1)); done; return 1; }
shot() { # <name>: a PPM for the checks, a PNG for the eyes
    python3 tools/gfx/screenshot.py "$SOCK" "$TMPD/$1.ppm" 5 > /dev/null 2>&1
    if [ -n "$SHOTS" ] && [ -s "$TMPD/$1.ppm" ]; then
        mkdir -p "$SHOTS"; python3 -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])" "$TMPD/$1.ppm" "$SHOTS/$1-$MODE-$RES.png" 2>/dev/null
    fi
}
tap() { python3 tools/themestore/click.py "$1,$2" > "$TMPD/k.txt" 2>/dev/null; python3 tools/wm/monitor.py "$SOCK" "$TMPD/k.txt" > /dev/null 2>&1; sleep 1.5; }
key() { local k; for k in "$@"; do echo "sendkey $k" > "$TMPD/t.txt"; python3 tools/wm/monitor.py "$SOCK" "$TMPD/t.txt" 0.15 > /dev/null 2>&1; sleep 0.6; done; sleep 1; }
# the critical call of the window is answered in the SYSTEM dialog (SETBROKER2): wait for it, say yes with J
dlgn() { wclean | grep -ac 'wm: trusted dialog up no='; }
dlgyes() { # <dialogs shown before the question>
    local i=0; while [ $i -lt 20 ]; do [ "$(dlgn)" -gt "$1" ] && break; sleep 1; i=$((i + 1)); done
    sleep 1; key j
}
typetext() { local c; for c in $(echo "$1" | sed 's/./& /g'); do key "$c"; done; }
mark() { MARK=$(wclean | wc -l); }
# a text the window painted AFTER the mark (the trace: `wlib: text ... t=<text>`)
sawlog() { [ "$(wclean | tail -n +"$MARK" | grep -acF -- "store: status $1")" -gt 0 ]; }
waitlog() { local i=0; while [ $i -lt $2 ]; do sawlog "$1" && return 0; sleep 1; i=$((i + 1)); done; return 1; }
sawjob() { [ "$(wclean | tail -n +"$MARK" | grep -acE 't=[0-9]+ %$')" -gt 0 ]; }
sawt() { [ "$(wclean | tail -n +"$MARK" | grep -acF -- "t=$1")" -gt 0 ]; }
waitt() { local i=0; while [ $i -lt $2 ]; do sawt "$1" && return 0; sleep 1; i=$((i + 1)); done; return 1; }
# click the label of the LAST text of that name the window painted (the trace gives its place: x, base line, width)
tapt() {
    local xy
    xy=$(wclean | awk -v want="$1" '
        /wlib: text win=/ {
            i = index($0, " t="); txt = substr($0, i + 3); if (txt != want) next
            match($0, / x=[0-9]+/); x = substr($0, RSTART + 3, RLENGTH - 3)
            match($0, / base=[0-9]+/); b = substr($0, RSTART + 6, RLENGTH - 6)
            match($0, / tw=[0-9]+/); w = substr($0, RSTART + 4, RLENGTH - 4)
            match($0, / ax=[0-9]+/); ax = substr($0, RSTART + 4, RLENGTH - 4)
            match($0, / ay=[0-9]+/); ay = substr($0, RSTART + 4, RLENGTH - 4)
            have = 1; cx = ax + x + w / 2; cy = ay + b - 6 }
        END { if (have) printf "%d %d\n", cx, cy }')
    [ -n "$xy" ] || return 1
    set -- $xy; tap "$1" "$2"
}
# two pictures differ in many points (a dialog is open: its text is not in the trace, its picture is)
differs() { python3 -c "
import sys
from PIL import Image, ImageChops
a = Image.open(sys.argv[1]).convert('RGB'); b = Image.open(sys.argv[2]).convert('RGB')
n = sum(1 for p in ImageChops.difference(a, b).convert('L').getdata() if p > 24)
sys.exit(0 if n > int(sys.argv[3]) else 1)" "$TMPD/$1.ppm" "$TMPD/$2.ppm" "${3:-4000}" 2>/dev/null; }
lastn() { wclean | grep -ao "store: tiles=[0-9]*" | tail -1 | tr -cd '0-9'; }
lasth() { wclean | grep -ao " hits=[0-9]*" | tail -1 | tr -cd '0-9'; }
