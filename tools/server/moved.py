#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/server/moved.py -- DER UMZUG WAR EIN UMZUG.

Die Runde SERVERBUILD behauptet, `kernel/kgui.fi` und
`kernel/sysgui.fi` seien nicht neu geschriebener Code, sondern
dieselben Funktionen, die vorher in `kernel/kmain.fi` und
`kernel/sys.fi` standen -- Zeile fuer Zeile. Das ist die Art
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

# Welche Datei wohin gezogen ist, und welche Praefixe der Umzug
# erzwungen hat.
UMZUEGE = [
    ("kernel/kmain.fi", "kernel/kgui.fi", ["kutil", "gfx"],
     ["stage_graphics", "stage_surface", "stage_hold"]),
    ("kernel/kmain.fi", "kernel/kutil.fi", [], []),
    ("kernel/sys.fi", "kernel/sysgui.fi", ["sys"], []),
]

# ===================================================== RUNDE MERGE-2
#
# WAS DIESER PRUEFER MISST, UND WAS ER NICHT MESSEN SOLL.
#
# Er soll messen: WAR DER UMZUG EIN UMZUG. Er misst dafuer, ob die
# Rumpfe in kgui.fi/sysgui.fi zeichengleich mit denen sind, die vor
# SERVERBUILD in kmain.fi/sys.fi standen.
#
# Er soll NICHT messen: ob seither jemand an einer dieser Funktionen
# GEARBEITET hat. Genau das tat er aber, und deshalb war er seit
# MERGE-2 13 rot, ohne dass es jemandem auffiel -- der Abschnitt
# `server` lief in keiner Abnahme, weil `serverbuild` seinen Testlaeufer
# hinter `abschnitte_abarbeiten` angemeldet hatte (siehe MERGE-2 11).
# Ein Pruefer, der bei JEDER spaeteren Zeile rot wird, sagt nach der
# zweiten Runde nichts mehr aus.
#
# Deshalb steht hier eine LISTE MIT NAMEN UND GRUENDEN. Sie wird NICHT
# gewachsen, wenn etwas rot ist -- sie wird gewachsen, wenn ein MERGE
# eine der umgezogenen Funktionen bewusst weiterentwickelt hat, und
# dann mit der Nummer dieses Merges. Jede Funktion, die NICHT hier
# steht, macht den Pruefer weiter rot. Das ist der Unterschied
# zwischen einer Ausnahme und einem abgeschalteten Test.
SEITHER_WEITERENTWICKELT = {
    # kgui.fi
    "surface": "MERGE-2 13 (usbimg): die Aenderung an `surface` geportet",
    "desk_start": "MERGE-2 15/16 (themestore, softui): der Schreibtisch"
                  " startet die Vorlagen mit",
    "wm_bench2": "MERGE-2 16 (softui): neue Messung, im Original nicht da",
    "vmode_stage": "MERGE-2 18 (customres): Kachelbelegung und der eigene"
                   " Selbsttest der Runde",
    "display_hold": "MERGE-2 18 (customres): M_EIGEN/M_EIGENBAD/M_EIGENFRIST",
    "disp_eigen": "MERGE-2 18 (customres): neu, im Original nicht da",
    # sysgui.fi
    "wm_call": "MERGE-2 16 (softui): die neuen WM-Felder",
    "do_dispget": "MERGE-2 18 (customres): die vierzehn neuen DG_-Felder",
    "do_dispset": "MERGE-2 18 (customres): DS_CUSTOM, DS_CHECK, DS_SAVE",
    "disp_rc": "MERGE-2 18 (customres): neu, im Original nicht da",
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
            offen = False
            while j < len(code):
                tiefe += code[j].count("{") - code[j].count("}")
                if "{" in code[j]:
                    offen = True
                if offen and tiefe <= 0:
                    break
                j += 1
            aus[name] = "\n".join(lines[i:j + 1])
            i = j + 1
        else:
            i += 1
    return aus


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    basis = sys.argv[1]
    schlecht = 0
    for alt, neu, praefixe, neue_namen in UMZUEGE:
        roh = subprocess.run(["git", "show", "%s:%s" % (basis, alt)],
                             capture_output=True)
        if roh.returncode != 0:
            print("  %s: %s gibt es in %s nicht" % (neu, alt, basis))
            schlecht += 1
            continue
        A = funktionen(roh.stdout.decode("utf8", "replace"))
        with open(neu, "rb") as f:
            B = funktionen(f.read().decode("utf8", "replace"))
        gleich = 0
        weg = 0
        abweichend = []
        for name, text in B.items():
            if name in neue_namen:
                weg += 1
                continue
            if name not in A:
                abweichend.append((name, "steht nicht im Original"))
                continue
            t = text
            for p in praefixe:
                t = re.sub(r"(?<![A-Za-z0-9_.])" + p + r"\.", "", t)
            if t == A[name]:
                gleich += 1
            else:
                abweichend.append((name, "weicht ab"))
        ganz = len(B) - weg
        print("  %-22s %d von %d Funktionen zeichengleich mit %s"
              % (neu.split("/")[-1], gleich, ganz, alt.split("/")[-1]))
        for name, warum in abweichend:
            grund = SEITHER_WEITERENTWICKELT.get(name)
            if grund:
                print("      %s: %s -- ERLAUBT: %s" % (name, warum, grund))
                continue
            print("      %s: %s" % (name, warum))
            schlecht += 1
    return 1 if schlecht else 0


if __name__ == "__main__":
    sys.exit(main())
