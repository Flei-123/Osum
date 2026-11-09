#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

PAT = re.compile(r"0x(?:00)?([0-9A-Fa-f]{6})\b")
PAT_RGB = re.compile(r"\brgb\(\s*state\s*,\s*(0x[0-9A-Fa-f]{1,2}|\d{1,3})"
                     r"\s*,\s*(0x[0-9A-Fa-f]{1,2}|\d{1,3})"
                     r"\s*,\s*(0x[0-9A-Fa-f]{1,2}|\d{1,3})\s*\)")

FILES = [
    "kernel/ui/wm.fi",
    "kernel/user/wlibc.fi",
    "kernel/user/fuiapp/wlib.fi",
    "kernel/user/taskbar.fi",
    "kernel/user/taskbar/tbbase.fi",
    "kernel/user/taskbar/tbhover.fi",
    "kernel/user/taskbar/tbinput.fi",
    "kernel/user/taskbar/tblayout.fi",
    "kernel/user/taskbar/tbmetrics.fi",
    "kernel/user/taskbar/tbpaint.fi",
    "kernel/user/taskbar/tbpopup.fi",
    "kernel/user/taskbar/tbstatus.fi",
    "kernel/user/desktop.fi",
    "kernel/user/settings.fi",
    "kernel/user/settings/setaccount.fi",
    "kernel/user/settings/setbase.fi",
    "kernel/user/settings/setbuild.fi",
    "kernel/user/settings/setcore.fi",
    "kernel/user/settings/setdevice.fi",
    "kernel/user/settings/setpages.fi",
    "kernel/user/settings/setsystem.fi",
    "kernel/user/explorer.fi",
    "kernel/user/launcher.fi",
    "kernel/user/locate.fi",
    "kernel/user/widgetdemo.fi",
]

ALLOWED_CONSTS = ("const RGB24", "const RGB_WHITE", "const RGB_BLACK",
                  "const RGB_BAD", "const ACCENT_BLACK",
                  "const STRUT_MAX", "const PROBE_IN", "const PROBE_OUT",
                  "const CURSOR_BODY", "const CURSOR_EDGE")
ALLOWED_FN = {
    "kernel/user/wlibc.fi": ["fn primitives_builtin", "fn platte", "fn plate_ink"],
    "kernel/user/taskbar/tbstatus.fi": ["fn glas_say"],
    "kernel/user/taskbar/tbmetrics.fi": ["fn schild_say"],
    "kernel/ui/wm.fi": [
        "fn deco_fallback",
        "fn term_palette",
        "fn glass_mix",
        "fn selftest_glas",
        "fn td_paint",
        "fn tab_publish",
        "fn paint_switcher",
        "fn fps_overlay",
        "fn sig_colour",
        "fn cg_mal",
        "fn measure_reason",
        "fn messzeile",
        "fn mess_gruen",
        "fn mess_rot",
        "fn mess_weiss",
        "fn mess_gelb",
    ],
}


def is_colour(code, m):
    end = m.end()
    if end < len(code) and code[end] in "0123456789abcdefABCDEF":
        return False
    return len(code[m.start():end]) in (8, 10)


def scan(path, rel):
    text = open(path, encoding="utf-8", errors="replace").read()
    inside = False
    hits = []
    uses = 0
    allowed = ALLOWED_FN.get(rel, [])
    for no, line in enumerate(text.split("\n"), 1):
        if allowed:
            if any(line.startswith(fn) for fn in allowed):
                inside = True
            elif line.startswith("}"):
                inside = False
        code = line.split("//", 1)[0]
        uses += code.count("theme(") + code.count("theme_semantic(")
        if not code.strip() or inside:
            continue
        if any(code.lstrip().startswith(c) for c in ALLOWED_CONSTS):
            continue
        for m in PAT.finditer(code):
            if is_colour(code, m):
                hits.append((rel, no, code.strip()))
        for m in PAT_RGB.finditer(code):
            hits.append((rel, no, code.strip()))
    return hits, uses


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    hits = []
    uses = 0
    seen = 0
    given = len(sys.argv) > 1
    missing = [] if given else [
        r for r in FILES if not os.path.isfile(os.path.join(root, r))]
    if missing:
        for r in missing:
            print("rawcolour: LISTED BUT NOT THERE: %s" % r)
        print("rawcolour: files 0 tokens 0 raw %d" % len(missing))
        return 2
    dupes = sorted({r for r in FILES if FILES.count(r) > 1})
    if dupes:
        for r in dupes:
            print("rawcolour: LISTED TWICE: %s" % r)
        return 2
    for rel in FILES:
        p = os.path.join(root, rel)
        if not os.path.isfile(p):
            continue
        seen += 1
        h, u = scan(p, rel)
        hits += h
        uses += u
    for rel, no, code in hits:
        print("%s:%d: %s" % (rel, no, code))
    print("rawcolour: files %d tokens %d raw %d" % (seen, uses, len(hits)))
    return 0 if not hits else 1


if __name__ == "__main__":
    sys.exit(main())
