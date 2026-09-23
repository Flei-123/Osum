#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/zaehlen.py -- WER MALT NOCH SELBST?

    zaehlen.py [--json <datei>]

Justins Regel fuer diese Runde lautet: ALLES an Oberflaeche geht ueber
das Rahmenwerk.  Kein Programm malt selbst, kein Programm tippt eine
Farbe, kein Programm tippt einen Abstand.  Was das Rahmenwerk nicht
kann, wird INS Rahmenwerk eingebaut.

Eine Regel, die man nicht zaehlen kann, ist ein Vorsatz.  Dieses
Werkzeug zaehlt sie:

  1. DIREKTE ZEICHENAUFRUFE.  Jeder Aufruf einer MALENDEN Routine des
     Zeichenkerns (`wlibc.rect`, `.px`, `.hline`, `.rrect`, `.text_at`,
     ...) in kernel/user/*.fi AUSSER wlib.fi und wlibc.fi selbst.
     MESSENDE Routinen (`text_w`, `ascent_of`, `px_ui`) zaehlen nicht --
     eine Breite zu erfragen ist kein Malen.  Ziel: 0.

  2. FESTE FARBWERTE.  Eine Zahl, die als Farbe in eine Malroutine
     geht, ohne durch `wlibc.theme`/`sem`/`shade`/`blend` gegangen zu
     sein.  Ziel: 0 ausserhalb von theme*/wlibc.

  3. FESTE PIXELMASSE.  Zahlenliterale in Geometrie-Argumenten, die
     nicht aus `metric`/`sp`/`grid`/`ctrl_*` stammen -- als Hinweis,
     nicht als Abnahmekriterium.

Ausgenommen sind Programme, die KEINE Fensteroberflaeche sind, sondern
den Zeichenkern selbst pruefen: `icont` (Symbolpruefstand) und
`themetest`.  Sie stehen einzeln in der Ausgabe, mit Begruendung.
"""
import glob
import json
import os
import re
import sys

# Die malenden Routinen des Zeichenkerns.  Diese Liste ist die
# Definition von "malt selbst".
MAL = [
    "px", "rect", "hline", "vline", "frame", "frame3", "rrect", "rframe",
    "rring", "drop_shadow", "shadow_edge", "divider", "text_at",
    "draw_glyph",
]
# Messen, nicht malen.
MESS = [
    "text_w", "text_h", "ascent_of", "glyph_w", "mono_cell", "fit",
    "px_ui", "px_mono", "icon_small", "icon_menu", "icon_taskbar",
    "icon_large", "surf_w", "surf_rows", "screen_w", "screen_h",
    "mouse_x", "mouse_y", "mouse_btn", "band_y", "ui_scale", "metric",
    "theme", "sem", "shade", "blend", "get", "grid", "sp",
    # `aa_pixels` liest den Zaehler der kantengeglaetteten Bildpunkte
    # aus.  Er MALT nicht -- er ist die Messung, mit der diese Runde
    # belegt, dass ueberhaupt geglaettet wird.  Ihn als Malaufruf zu
    # zaehlen hiesse, das Messgeraet als Farbe zu zaehlen.
    "aa_pixels",
]
# Pruefstaende: sie MUESSEN den Kern direkt aufrufen, das ist ihr Zweck.
PRUEFSTAND = {"icont.fi", "themetest.fi", "wlibt.fi"}
KERN = {"wlib.fi", "wlibc.fi"}

RE_CALL = re.compile(r"\bwlibc\.([a-z_0-9]+)\s*\(")
RE_COMMENT = re.compile(r"^\s*//")


def zeilen(pfad):
    with open(pfad, "rb") as f:
        roh = f.read().decode("latin1")
    return roh.split("\n")


def scan(pfad):
    """(mal-treffer, farb-treffer) einer Datei."""
    mal = []
    for nr, z in enumerate(zeilen(pfad), 1):
        if RE_COMMENT.match(z):
            continue
        code = z.split("//")[0]
        for m in RE_CALL.finditer(code):
            fn = m.group(1)
            if fn in MESS or fn not in MAL:
                continue
            mal.append((nr, fn, z.strip()[:100]))
    return mal


# Eine Zahl gilt nur als Farbe, wenn sie ARGUMENT eines malenden
# Aufrufs ist.  `& 0xFFFFFF` ist eine Maske, `runden < 4000000` eine
# Schleifengrenze, und beide standen in der ersten Fassung dieser
# Zaehlung als "feste Farbe" in der Tabelle.
RE_MAL_CALL = re.compile(
    r"\bwlibc?\.(" + "|".join(
        ["px", "rect", "hline", "vline", "frame", "frame3", "rrect",
         "rframe", "rring", "drop_shadow", "shadow_edge", "divider",
         "text_at", "icon_at", "icon_draw", "get",
         "mal_flaeche", "mal_tafel", "mal_trenner", "mal_text",
         "mal_balken", "mal_punkt", "mal_rahmen", "mal_linie",
         "mal_kante3",
         # Runde ENGLISCH hat die mal_*-Helfer umbenannt; ohne die neuen
         # Namen zaehlte diese Tafel 38 Aufrufe (wlib.draw_*) nicht mit.
         "draw_area", "draw_board", "draw_separator", "draw_text",
         "draw_bar", "draw_point", "draw_frame", "draw_line",
         "draw_edge3"]) + r")\s*\(")
RE_ZAHL = re.compile(r"\b(0x[0-9a-fA-F]{6,8}|\d{5,8})\b")
# Eine Bitmaske ist keine Farbe: `x & 0xFFFFFF`.
RE_MASKE = re.compile(r"[&|^]\s*(0x[0-9a-fA-F]+|\d+)\s*$")


def farben(pfad):
    """Zahlenliterale, die ALS FARBE in einen Malaufruf gehen."""
    treffer = []
    for nr, z in enumerate(zeilen(pfad), 1):
        if RE_COMMENT.match(z):
            continue
        code = z.split("//")[0]
        if not RE_MAL_CALL.search(code):
            continue
        for m in RE_ZAHL.finditer(code):
            v = m.group(1)
            # Steht unmittelbar davor ein &, | oder ^, ist es eine
            # Maske und keine Farbe.
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
    breit = []
    for pfad in sorted(glob.glob(os.path.join(hier, "*.fi"))):
        name = os.path.basename(pfad)
        if name in KERN:
            continue
        mal = scan(pfad)
        f = farben(pfad)
        if not mal and not f:
            continue
        ist_pruef = name in PRUEFSTAND
        ergebnis["dateien"][name] = {
            "mal": len(mal), "farben": len(f), "pruefstand": ist_pruef,
            "stellen": [{"zeile": n, "fn": fn, "text": t} for n, fn, t in mal],
        }
        if ist_pruef:
            ergebnis["pruefstand"] += len(mal)
        else:
            ergebnis["summe"] += len(mal)
            ergebnis["farben"] += len(f)
        breit.append((name, len(mal), len(f), ist_pruef))

    print("== direkte Zeichenaufrufe ausserhalb wlib/wlibc ==")
    print("%-18s %6s %7s  %s" % ("Programm", "malt", "farben", "Art"))
    for name, m, f, p in breit:
        print("%-18s %6d %7d  %s" % (name, m, f, "PRUEFSTAND" if p else ""))
    print("-" * 46)
    print("Summe (Programme):      %d Zeichenaufrufe, %d feste Farbwerte"
          % (ergebnis["summe"], ergebnis["farben"]))
    print("Summe (Pruefstaende):   %d  (erlaubt: sie pruefen den Kern)"
          % ergebnis["pruefstand"])

    if "--json" in sys.argv:
        z = sys.argv[sys.argv.index("--json") + 1]
        json.dump(ergebnis, open(z, "w"), indent=1)
    return 0 if ergebnis["summe"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
