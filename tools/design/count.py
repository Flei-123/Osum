#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob
import json
import os
import re
import sys

MAL = [
    "px", "rect", "hline", "vline", "frame", "frame3", "rrect", "rframe",
    "rring", "drop_shadow", "shadow_edge", "divider", "text_at",
    "draw_glyph",
]
MEASURE = [
    "text_w", "text_h", "ascent_of", "glyph_w", "mono_cell", "fit",
    "px_ui", "px_mono", "icon_small", "icon_menu", "icon_taskbar",
    "icon_large", "surf_w", "surf_rows", "screen_w", "screen_h",
    "mouse_x", "mouse_y", "mouse_btn", "band_y", "ui_scale", "metric",
    "theme", "sem", "shade", "blend", "get", "grid", "sp",
    "aa_pixels",
]
PRUEFSTAND = {"icont.fi", "themetest.fi", "wlibt.fi"}
KERN = {"uitextat.fi", "uitheme.fi"}

RE_CALL = re.compile(r"\buitextat\.([a-z_0-9]+)\s*\(")
RE_COMMENT = re.compile(r"^\s*//")


def rows(path_2):
    with open(path_2, "rb") as f:
        roh = f.read().decode("latin1")
    return roh.split("\n")


def scan(path_2):
    mal = []
    for nr, z in enumerate(rows(path_2), 1):
        if RE_COMMENT.match(z):
            continue
        code = z.split("//")[0]
        for m in RE_CALL.finditer(code):
            fn = m.group(1)
            if fn in MEASURE or fn not in MAL:
                continue
            mal.append((nr, fn, z.strip()[:100]))
    return mal


RE_MAL_CALL = re.compile(
    r"\b(?:uitextat|hostdraw)\.(" + "|".join(
        ["px", "rect", "hline", "vline", "frame", "frame3", "rrect",
         "rframe", "rring", "drop_shadow", "shadow_edge", "divider",
         "text_at", "icon_at", "icon_draw", "get",
         "mal_flaeche", "mal_tafel", "mal_trenner", "mal_text",
         "mal_balken", "mal_punkt", "mal_rahmen", "mal_linie",
         "mal_kante3",
         "draw_area", "draw_board", "draw_separator", "draw_text",
         "draw_bar", "draw_point", "draw_frame", "draw_line",
         "draw_edge3"]) + r")\s*\(")
RE_NUM = re.compile(r"\b(0x[0-9a-fA-F]{6,8}|\d{5,8})\b")
RE_MASKE = re.compile(r"[&|^]\s*(0x[0-9a-fA-F]+|\d+)\s*$")


def farben(path_2):
    treffer = []
    for nr, z in enumerate(rows(path_2), 1):
        if RE_COMMENT.match(z):
            continue
        code = z.split("//")[0]
        if not RE_MAL_CALL.search(code):
            continue
        for m in RE_NUM.finditer(code):
            v = m.group(1)
            vor = code[: m.start()].rstrip()
            if vor.endswith("&") or vor.endswith("|") or vor.endswith("^"):
                continue
            treffer.append((nr, v, code.strip()[:100]))
    return treffer


def main():
    hier = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "..", "kernel", "user")
    hier = os.path.normpath(hier)
    ergebnis = {"dateien": {}, "summe": 0, "pruefstand": 0, "farben": 0}
    wide = []
    for path_2 in sorted(glob.glob(os.path.join(hier, "*.fi"))):
        name = os.path.basename(path_2)
        if name in KERN:
            continue
        mal = scan(path_2)
        f = farben(path_2)
        if not mal and not f:
            continue
        ist_check = name in PRUEFSTAND
        ergebnis["dateien"][name] = {
            "mal": len(mal), "farben": len(f), "pruefstand": ist_check,
            "stellen": [{"zeile": n, "fn": fn, "text": t} for n, fn, t in mal],
        }
        if ist_check:
            ergebnis["pruefstand"] += len(mal)
        else:
            ergebnis["summe"] += len(mal)
            ergebnis["farben"] += len(f)
        wide.append((name, len(mal), len(f), ist_check))

    print("== direkte Zeichenaufrufe ausserhalb uitextat/hostdraw ==")
    print("%-18s %6s %7s  %s" % ("Programm", "malt", "farben", "Art"))
    for name, m, f, p in wide:
        print("%-18s %6d %7d  %s" % (name, m, f, "PRUEFSTAND" if p else ""))
    print("-" * 46)
    print("Summe (Programme):      %d Zeichenaufrufe, %d feste Farbwerte"
          % (ergebnis["summe"], ergebnis["farben"]))
    print("sum (test benches):   %d  (allowed: they test the kernel)"
          % ergebnis["pruefstand"])

    if "--json" in sys.argv:
        z = sys.argv[sys.argv.index("--json") + 1]
        json.dump(ergebnis, open(z, "w"), indent=1)
    return 0 if ergebnis["summe"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
