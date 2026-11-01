#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/server/moved.py -- DER UMZUG WAR EIN UMZUG.

Die Runde SERVERBUILD behauptet, `kernel/ui/kgui.fi` und
`kernel/sys/sysgui.fi` seien nicht neu geschriebener Code, sondern
dieselben Funktionen, die vorher in `kernel/kmain.fi` und
`kernel/sys/sys.fi` standen -- Zeile fuer Zeile. Das ist die Art
Behauptung, die man nachrechnen kann, und dann sollte man es auch.

Dieses Werkzeug holt die alten Fassungen aus git, schneidet aus beiden
Seiten die Funktionsrumpfe heraus und vergleicht sie ZEICHENWEISE.
Erlaubt ist genau eine Abweichung, und es ist die, die der Umzug
erzwingt: was vorher `neg(...)` hiess, heisst drueben `sys.neg(...)`,
was `bnum(...)` hiess, heisst `kutil.bnum(...)`. Diese Praefixe werden
vor dem Vergleich wieder abgezogen. Alles andere -- eine geaenderte
Zahl, eine umgestellte Bedingung, eine weggelassene Zeile -- faellt
auf.

    moved.py <basis-commit>

Ausgabe: eine Zeile je Datei, "N von M zeichengleich", und der
Beendigungscode 1, sobald eine einzige Funktion abweicht.
"""
import re
import subprocess
import sys

UMZUEGE = [
    ("kernel/kmain.fi", "kernel/ui/kgui.fi", ["kutil", "gfx"],
     ["stage_graphics", "stage_surface", "stage_hold"]),
    ("kernel/kmain.fi", "kernel/lib/kutil.fi", [], []),
    ("kernel/sys/sys.fi", "kernel/sys/sysgui.fi", ["sys"], []),
]

SEITHER_WEITERENTWICKELT = {
    "surface": "MERGE-2 13 (usbimg): die Aenderung an `surface` geportet",
    "desk_start": "MERGE-2 15/16 (themestore, softui): der Schreibtisch"
                  " startet die Vorlagen mit",
    "wm_bench2": "MERGE-2 16 (softui): neue Messung, im Original nicht da",
    "vmode_stage": "MERGE-2 18 (customres): Kachelbelegung und der eigene"
                   " Selbsttest der Runde",
    "display_hold": "MERGE-2 18 (customres): M_EIGEN/M_EIGENBAD/M_EIGENFRIST",
    "disp_eigen": "MERGE-2 18 (customres): neu, im Original nicht da",
    "wm_call": "MERGE-2 16 (softui): die neuen WM-Felder",
    "do_dispget": "MERGE-2 18 (customres): die vierzehn neuen DG_-Felder",
    "do_dispset": "MERGE-2 18 (customres): DS_CUSTOM, DS_CHECK, DS_SAVE",
    "disp_rc": "MERGE-2 18 (customres): neu, im Original nicht da",
    "wm_bench": "ENGLISCH ETAPPE 2: voll->full, klein->small",
    "tile_dirty": "ENGLISCH ETAPPE 2: zu->close_path",
    "gfx_bench": "ENGLISCH ETAPPE 2: umbenannte Bezeichner",
    "desk_spawn_n": "ENGLISCH ETAPPE 2: umbenannte Bezeichner",
    "wm_list": "ENGLISCH ETAPPE 2: umbenannte Bezeichner",
    "i18n_bench": "ENGLISCH ETAPPE 6: umbenannte Konstanten",
    "graphics": "RUNDE SCHIRM: die Tafel wird nach EDID gefragt, statt"
                " 800x600/1024x768 zu raten",
    "say_max": "RUNDE SCHIRM: die Oberflaeche auf grossem Bildschirm",
    "paint_bench": "RUNDE SCHNELLBILD 2/n: SSE2 fuer das Mischen",
    "gfx_hold": "RUNDE 'Auch das Halten ist Betrieb': die Warteschleife"
                " arbeitet jetzt",
    "wait_wm": "RUNDEN TAFEL/STANDBILD/BLECHZWEI/BLECHFUENF: der"
               " Dauerbetrieb (M_WMDAUER), der Absturzschirm und das"
               " dritte Argument tw",
    "k15_start": "RUNDEN WERKZEUGE 3/n und OBERFLAECHE 2/n: wigapp= mit"
                 " Argumenten ist in eine eigene Funktion gewandert",
    "wig_call": "RUNDE BRUECKE 1/n: der Weg von aussen",
}


def funktionen(text):
    lines = text.split("\n")
    code = [(L[:L.find("//")] if L.find("//") >= 0 else L) for L in lines]
    aus = {}
    i = 0
    while i < len(code):
        m = re.match(r"fn ([a-zA-Z_][A-Za-z0-9_]*)", code[i])
        if m:
            name = m.group(1)
            tiefe = 0
            j = i
            open_2 = False
            while j < len(code):
                tiefe += code[j].count("{") - code[j].count("}")
                if "{" in code[j]:
                    open_2 = True
                if open_2 and tiefe <= 0:
                    break
                j += 1
            aus[name] = "\n".join(lines[i:j + 1])
            i = j + 1
        else:
            i += 1
    return aus


UMZUG_COMMIT = {
    "kernel/ui/kgui.fi": "5c3d87d",
    "kernel/lib/kutil.fi": "5c3d87d",
    "kernel/sys/sysgui.fi": "1903abb",
}


def names_beim_umzug(target):
    """Die Funktionsnamen, die ZIEL beim Umzug schon hatte."""
    c = UMZUG_COMMIT.get(target)
    if not c:
        return set()
    roh = subprocess.run(["git", "show", "%s:%s" % (c, target)],
                         capture_output=True)
    if roh.returncode != 0:
        return set()
    return set(funktionen(roh.stdout.decode("utf8", "replace")))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    basis = sys.argv[1]
    bad = 0
    for alt, new, praefixe, new_names in UMZUEGE:
        beim_umzug = names_beim_umzug(new)
        spaeter = 0
        roh = subprocess.run(["git", "show", "%s:%s" % (basis, alt)],
                             capture_output=True)
        if roh.returncode != 0:
            print("  %s: %s does not exist in %s" % (new, alt, basis))
            bad += 1
            continue
        A = funktionen(roh.stdout.decode("utf8", "replace"))
        with open(new, "rb") as f:
            B = funktionen(f.read().decode("utf8", "replace"))
        eq = 0
        gone = 0
        abweichend = []
        for name, text in B.items():
            if name in new_names:
                gone += 1
                continue
            if name not in A:
                if name in beim_umzug:
                    abweichend.append((name, "steht nicht im Original"))
                else:
                    spaeter += 1
                continue
            t = text
            for p in praefixe:
                t = re.sub(r"(?<![A-Za-z0-9_.])" + p + r"\.", "", t)
            if t == A[name]:
                eq += 1
            else:
                abweichend.append((name, "weicht ab"))
        ganz = len(B) - gone
        print("  %-22s %d of %d functions identical to %s"
              % (new.split("/")[-1], eq, ganz, alt.split("/")[-1]))
        if spaeter:
            print("      (%d functions exist only AFTER the move"
                  " entstanden und gehoeren nicht dazu)" % spaeter)
        for name, warum in abweichend:
            reason = SEITHER_WEITERENTWICKELT.get(name)
            if reason:
                print("      %s: %s -- ERLAUBT: %s" % (name, warum, reason))
                continue
            print("      %s: %s" % (name, warum))
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
