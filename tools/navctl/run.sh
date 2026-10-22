#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/navctl/run.sh -- TABS NODE (kernel/user/tabsnode.fi) AND VIRTUAL LIST (kernel/user/rowlist.fi).
#
#   heavy bash tools/navctl/run.sh
#
# scenedemo in `nav` mode shows a tab strip and a list of 20000 rows. Only the rows
# in view are nodes (7 of 20000: the scene stays at 13 nodes). The run drives it on
# the machine of the stick (tools/design/eh6.sh) and reads the status lines
# `scenedemo: nav tab= top= sel= built= nodes=`:
#   Enter on the focused row selects it, Down moves, PgDn moves by a page and scrolls,
#   End / Home jump, the wheel scrolls 3 rows per notch, a click selects the row under
#   the pointer, a click on a tab switches the page (the list disappears from the tree),
#   Left / Right on the focused strip wrap around.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cat > "$TMPD/dreh.txt" <<'DREH'
warteauf 'scenedemo: nav tab=0' || 150
warte 4
foto 00-start
taste tab
warte 0.6
taste tab
warte 0.6
taste tab
warte 0.6
taste tab
warte 0.6
taste ret
warte 1.5
taste down
warte 1
taste down
warte 1
taste down
warte 1
taste pgdn
warte 1.5
taste end
warte 1.5
foto 01-end
taste home
warte 1.5
fahre 230,210
warte 1
rad -2
warte 1.5
rad 1
warte 1.5
foto 02-wheel
klick 230,202
warte 1.5
foto 03-click
klick 190,119
warte 1.5
foto 04-info
klick 108,119
warte 1.5
taste left
warte 1.5
taste right
warte 1.5
foto 05-list
DREH

EH_MKFS_EXTRA="/proc/" bash tools/design/eh6.sh "$TMPD/o" res=1280x800 accel=kvm tafel=nein moreprogs=scenedemo \
    "extra=vfs wigapp=/bin/scenedemo,nav lang=en" drehbuch="$TMPD/dreh.txt" > "$TMPD/o.log" 2>&1
S="$TMPD/o/serial.txt"
if [ -n "${NAVCTL_OUT:-}" ]; then mkdir -p "$NAVCTL_OUT"; cp "$TMPD"/o/*.ppm "$S" "$NAVCTL_OUT/" 2>/dev/null; fi
if [ ! -s "$S" ]; then
    bad "no serial output: $(tail -n 3 "$TMPD/o.log" | tr '\n' ' ')"
    echo "NAVCTL: $pass passed, $fail failed"; exit 1
fi

python3 -I - "$S" <<'PY'
import re, sys
lines = [l for l in open(sys.argv[1], "rb").read().decode("latin-1").splitlines()]
rx = re.compile(r"scenedemo: nav tab=(\d+) top=(\d+) sel=(-|\d+) built=(\d+) nodes=(\d+)")
st = []
for l in lines:
    m = rx.search(l)
    if m:
        t, top, sel, b, n = m.groups()
        st.append((int(t), int(top), -1 if sel == "-" else int(sel), int(b), int(n)))

def ok(c, msg):
    print(("  OK    " if c else "  FAIL  ") + msg)
    return 0 if c else 1

fails = 0
def want(label, pred):
    global fails
    for s in st:
        if pred(s):
            fails += ok(True, label)
            return
    fails += ok(False, label + " -- states: " + " ".join("%d/%d/%d" % (s[0], s[1], s[2]) for s in st[:30]))

want("start: tab 0, top 0, no selection, 7 rows built", lambda s: s[:4] == (0, 0, -1, 7))
want("Enter on the focused row selects row 0", lambda s: s[0] == 0 and s[2] == 0 and s[1] == 0)
want("Down x3 moves the selection to row 3", lambda s: s[0] == 0 and s[2] == 3 and s[1] == 0)
want("PgDn moves by a page (7) and scrolls: sel 10, top 4", lambda s: s[:3] == (0, 4, 10))
want("End jumps to the last row: sel 19999, top 19993, 7 built", lambda s: s[:4] == (0, 19993, 19999, 7))
want("Home jumps back: sel 0, top 0", lambda s: s[0] == 0 and s[1] == 0 and s[2] == 0 and any(x[1] == 19993 for x in st))
want("wheel down 2 notches: top 3 then 6 (3 rows per notch)", lambda s: s[1] == 6 and s[2] == 0)
want("wheel up 1 notch: top 3 again", lambda s: s[1] == 3 and s[2] == 0 and any(x[1] == 6 for x in st))
want("click on a row selects it (row 5 under the pointer at top 3)", lambda s: s[0] == 0 and s[1] == 3 and s[2] == 5)
want("click on the tab 'Info' switches the page", lambda s: s[0] == 1)
want("click on the tab 'Liste' brings the list back with its position", lambda s: s[0] == 0 and s[1] == 3 and s[2] == 5 and any(x[0] == 1 for x in st))
want("Left on the strip wraps to the last tab", lambda s: s[0] == 2)
list_nodes = [s[4] for s in st if s[0] == 0 and s[3] == 7]
fails += ok(bool(list_nodes) and max(list_nodes) <= 16, "20000 rows, the scene holds at most %d nodes" % (max(list_nodes) if list_nodes else -1))
fails += ok(any(s[0] != 0 and s[4] < 10 for s in st), "on another tab the list is not in the tree (%s nodes)" % ",".join(str(s[4]) for s in st if s[0] != 0)[:20])
print("FAILS %d" % fails)
sys.exit(1 if fails else 0)
PY
rc=$?
if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
grep -aq 'panic' "$S" && bad "panic on the serial line" || ok "no panic"
echo "NAVCTL: python $([ "$rc" -eq 0 ] && echo ok || echo FAIL), $pass passed, $fail failed"
[ "$fail" -eq 0 ]
