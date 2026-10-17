#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsfit/run.sh -- Settings pages must fit a 1024x768 screen (host only, no VM, <1 s).
#
#   bash tools/settingsfit/run.sh [<git-rev>]     (rev = read the files from that commit; the control run)
#
# Checks (found in the 1024x768 pictures of tools/settingsui/run.sh, window 984 wide, right column ~366):
#   1. the fixed column widths of the two Network tables (usage, connections) sum to <= 366
#      (428 cut the last header "Program" to "Pro");
#   2. the strings that sit on ONE line in a ~300 px column (resolution note, address book button,
#      accent help line, acrylic head) are <= 38 characters in en and de (longer ones end in "...").
set -uo pipefail
cd "$(dirname "$0")/../.."
REV=${1:-}
get() { if [ -n "$REV" ]; then git show "$REV:$1"; else cat "$1"; fi; }
get kernel/user/settings.fi > "${TMPDIR:-/tmp}/fit.$$.fi"
get locale/en/messages > "${TMPDIR:-/tmp}/fit.$$.en"
get locale/de/messages > "${TMPDIR:-/tmp}/fit.$$.de"
trap 'rm -f "${TMPDIR:-/tmp}"/fit.$$.*' EXIT
python3 - "${TMPDIR:-/tmp}/fit.$$" <<'P'
import re, sys
b = sys.argv[1]
src = open(b + ".fi", encoding="latin1").read()
fail = 0
def ok(c, m):
    global fail
    print(("  OK    " if c else "  FAIL  ") + m)
    if not c: fail += 1
for name in ("c_nprog", "c_nconn"):
    v = [int(x) for x in re.findall(name + r"\[\d+ as usize\] = (\d+)", src)]
    ok(len(v) == 4 and sum(v) <= 366, "%s column sum %d <= 366" % (name, sum(v)))
keys = ["settings.display.res.note1", "settings.display.res.note2", "konto.ui.book", "settings.p.acc2", "settings.blur.head"]
for lang in ("en", "de"):
    d = {}
    for ln in open("%s.%s" % (b, lang), encoding="utf8"):
        if " = " in ln:
            k, v = ln.rstrip("\n").split(" = ", 1)
            d[k] = v
    for k in keys:
        ok(k in d and len(d[k]) <= 38, "%s %s: %d chars <= 38" % (lang, k, len(d.get(k, "")) ))
print("SETTINGSFIT: %d failed" % fail)
sys.exit(1 if fail else 0)
P
