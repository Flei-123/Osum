#!/usr/bin/env python3
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SNAPSHOT = os.path.join(ROOT, "assets", "palette", "dark.tsv")
PRIMITIVES = os.path.join(ROOT, "assets", "palette", "primitives.tsv")
OUT_FI = os.path.join(ROOT, "kernel", "user", "wlibc", "wcpal.fi")
OUT_CSS = os.path.join(ROOT, "reports", "mockups", "palette-dark.css")
OUT_WM = os.path.join(ROOT, "kernel", "ui", "wm", "wmrole.fi")
ORBIT_TOKENS = os.environ.get(
    "ORBIT_TOKENS", "/root/jarvis/projects/u_DiS4in7esMF1/firnchat/src/gui/tokens.fi")

ROLE_SOURCE = [
    ("base", "tokens_page"),
    ("surface", "tokens_surface"),
    ("surface_raised", "tokens_raised"),
    ("button", "tokens_button"),
    ("button_hover", "tokens_hover"),
    ("button_active", "tokens_selected"),
    ("field", "tokens_field"),
    ("field_focus", "tokens_field_focus"),
    ("border", "tokens_border"),
    ("separator", "tokens_separator"),
    ("text", "tokens_text"),
    ("text_muted", "tokens_text_muted"),
    ("text_disabled", "tokens_text_muted"),
    ("text_on_accent", "tokens_on_primary"),
    ("accent", "tokens_primary"),
    ("accent_hover", "tokens_primary_hover"),
    ("ring", "tokens_ring"),
    ("selection", "tokens_selected"),
    ("selection_text", "tokens_text"),
    ("error", "tokens_error"),
    ("warning", "tokens_warning"),
    ("success", "tokens_success"),
]

SURFACE_BINDINGS = [
    ("S_SURFACE", "surface"),
    ("S_SURFACE_RAISED", "surface_raised"),
    ("S_SURFACE_SUNKEN", "base"),
    ("S_SURFACE_HOVER", "button_hover"),
    ("S_SURFACE_PRESSED", "button_active"),
    ("S_CONTROL", "button"),
    ("S_CONTROL_HOVER", "button_hover"),
    ("S_CONTROL_PRESSED", "button_active"),
    ("S_FIELD", "field"),
    ("S_TEXT_PRIMARY", "text"),
    ("S_TEXT_SECONDARY", "text_muted"),
    ("S_TEXT_DISABLED", "text_disabled"),
    ("S_BORDER", "border"),
    ("S_BORDER_STRONG", "border"),
]

ACCENT_BINDINGS = [
    ("S_ACCENT", "accent"),
    ("S_ACCENT_HOVER", "accent_hover"),
    ("S_ACCENT_PRESSED", "accent_hover"),
    ("S_ON_ACCENT", "text_on_accent"),
    ("S_BORDER_FOCUS", "ring"),
    ("S_SELECTION", "selection"),
    ("S_ON_SELECTION", "selection_text"),
]

STATUS_BINDINGS = [
    ("S_DANGER", "error"),
    ("S_WARNING", "warning"),
    ("S_SUCCESS", "success"),
]


def extract_orbit(path):
    text = open(path, encoding="utf-8").read()
    values = {}
    for m in re.finditer(r"fn (tokens_\w+)\(dark: bool\) -> u32 \{(.*?)\n\}", text, re.S):
        name, body = m.group(1), m.group(2)
        dm = re.search(r"if dark \{\s*return (\d+) // 0x([0-9A-Fa-f]{6})", body)
        if dm is None:
            dm = re.search(r"return (\d+) // 0x([0-9A-Fa-f]{6})", body)
        if dm is None:
            continue
        dec, hexs = int(dm.group(1)), dm.group(2).upper()
        if dec != int(hexs, 16):
            sys.exit("decimal and hex comment disagree in %s" % name)
        values[name] = hexs
    rows = []
    for role, fn in ROLE_SOURCE:
        if fn not in values:
            sys.exit("missing %s in %s" % (fn, path))
        rows.append((role, values[fn], fn))
    return rows


def read_snapshot():
    rows = []
    for line in open(SNAPSHOT, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        role, hexs, src = line.split("\t")
        rows.append((role, hexs, src))
    return rows


def write_snapshot(rows):
    os.makedirs(os.path.dirname(SNAPSHOT), exist_ok=True)
    with open(SNAPSHOT, "w", encoding="utf-8") as f:
        f.write("# role\thex\tupstream\n")
        for r in rows:
            f.write("%s\t%s\t%s\n" % r)


def read_primitives():
    rows = []
    for line in open(PRIMITIVES, encoding="utf-8"):
        line = line.rstrip("\n")
        if line and not line.startswith("#"):
            slot, hexs = line.split("\t")
            rows.append((slot, hexs))
    return rows


def render_primitives():
    out = ["fn primitives_builtin() {"]
    for slot, hexs in read_primitives():
        if slot.isdigit():
            out.append("    wcbase.neutral[(%s) as usize] = 0x00%s" % (slot, hexs))
        else:
            out.append("    wcbase.sch_%s = 0x00%s" % (slot, hexs))
    out += ["}", ""]
    return out


def render_fi(rows):
    pal = {r: h for r, h, _ in rows}
    out = ["// SPDX-License-Identifier: GPL-2.0-only", "profile kernel", "", "import wlibc.wcbase", ""]
    for role, _ in ROLE_SOURCE:
        out.append("const DARK_%s: u64 = 0x00%s" % (role.upper(), pal[role]))
        out.append("")
    out += [
        "fn active() -> bool {",
        "    if wcbase.sch_high != 0 {",
        "        return false",
        "    }",
        "    return wcbase.sch_pal != 0",
        "}",
        "",
    ]
    for fn, binds in (("bind_surfaces", SURFACE_BINDINGS), ("bind_accent", ACCENT_BINDINGS), ("bind_status", STATUS_BINDINGS)):
        out.append("fn %s() {" % fn)
        for s, role in binds:
            out.append("    wcbase.sem[(wcbase.%s) as usize] = DARK_%s" % (s, role.upper()))
        out.append("}")
        out.append("")
    out += render_primitives()
    return "\n".join(out)


def render_wm(rows):
    pal = {r: h for r, h, _ in rows}
    out = ["// SPDX-License-Identifier: GPL-2.0-only", "profile kernel", ""]
    for role, _ in ROLE_SOURCE:
        out.append("const ROLE_%s: u64 = 0x%s" % (role.upper(), pal[role]))
        out.append("")
    return "\n".join(out)


def render_css(rows):
    out = [":root[data-theme=\"xoffi-dark\"] {"]
    for role, hexs, _ in rows:
        out.append("    --c-%s: #%s;" % (role.replace("_", "-"), hexs))
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["extract", "write", "check"])
    args = ap.parse_args()
    if args.mode == "extract":
        write_snapshot(extract_orbit(ORBIT_TOKENS))
        return
    rows = read_snapshot()
    fi, css, wm = render_fi(rows), render_css(rows), render_wm(rows)
    if args.mode == "write":
        open(OUT_FI, "w", encoding="utf-8").write(fi)
        os.makedirs(os.path.dirname(OUT_CSS), exist_ok=True)
        open(OUT_CSS, "w", encoding="utf-8").write(css)
        open(OUT_WM, "w", encoding="utf-8").write(wm)
        return
    bad = 0
    for path, want in ((OUT_FI, fi), (OUT_CSS, css), (OUT_WM, wm)):
        have = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if have != want:
            print("DRIFT %s" % os.path.relpath(path, ROOT))
            bad += 1
    if os.path.exists(ORBIT_TOKENS):
        if extract_orbit(ORBIT_TOKENS) != rows:
            print("DRIFT snapshot differs from %s" % ORBIT_TOKENS)
            bad += 1
    else:
        print("note: upstream %s not found, snapshot not compared" % ORBIT_TOKENS)
    print("palette check: %s" % ("FAIL" if bad else "OK"))
    sys.exit(1 if bad else 0)


main()
