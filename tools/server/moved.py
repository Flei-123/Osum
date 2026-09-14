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
    # ===================================== RUNDE ROTABSCHNITTE (14.09.2026)
    # Dreizehn umgezogene Funktionen, an denen seither WEITERGEARBEITET
    # wurde. Jede einzeln nachgesehen -- keine ist eine Neuschrift des
    # Umzugs, alle haben einen Commit mit Namen:
    #
    # Die ENGLISCH-Etappen haben Bezeichner umbenannt. Der Rumpf ist
    # danach zeichenweise anders, tut aber dasselbe:
    "wm_bench": "ENGLISCH ETAPPE 2: voll->full, klein->small",
    "tile_dirty": "ENGLISCH ETAPPE 2: zu->close_path",
    "gfx_bench": "ENGLISCH ETAPPE 2: umbenannte Bezeichner",
    "desk_spawn_n": "ENGLISCH ETAPPE 2: umbenannte Bezeichner",
    "wm_list": "ENGLISCH ETAPPE 2: umbenannte Bezeichner",
    "i18n_bench": "ENGLISCH ETAPPE 6: umbenannte Konstanten",
    #
    # Und hier ist wirklich Verhalten dazugekommen:
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


# DIE COMMITS, IN DENEN DER UMZUG PASSIERT IST. Gegen DIESEN Stand
# wird gefragt, ob ein Name beim Umzug schon in der Zieldatei stand.
UMZUG_COMMIT = {
    "kernel/kgui.fi": "5c3d87d",
    "kernel/kutil.fi": "5c3d87d",
    "kernel/sysgui.fi": "1903abb",
}


def namen_beim_umzug(ziel):
    """Die Funktionsnamen, die ZIEL beim Umzug schon hatte."""
    c = UMZUG_COMMIT.get(ziel)
    if not c:
        return set()
    roh = subprocess.run(["git", "show", "%s:%s" % (c, ziel)],
                         capture_output=True)
    if roh.returncode != 0:
        return set()
    return set(funktionen(roh.stdout.decode("utf8", "replace")))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    basis = sys.argv[1]
    schlecht = 0
    for alt, neu, praefixe, neue_namen in UMZUEGE:
        beim_umzug = namen_beim_umzug(neu)
        spaeter = 0
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
                # RUNDE ROTABSCHNITTE: EINE FUNKTION, DIE ES BEIM UMZUG
                # NOCH GAR NICHT GAB, IST KEIN BEFUND DES UMZUGS.
                #
                # Dieser Pruefer fragt "war der Umzug ein Umzug". Was
                # SPAETER in kgui.fi/sysgui.fi dazugeschrieben wurde --
                # `panikbild` (Runde PROTOKOLL), die `grace_*` und
                # `board_*` (ECHTHARDWARE-6), `input_pulse` (HIDWEG) --
                # stand nie in kmain.fi und kann deshalb auch nicht
                # "beim Umzug veraendert" worden sein.
                #
                # Gemessen am 14.09.2026: von den 74 gemeldeten Namen
                # waren ALLE 74 erst nach dem Umzug (5c3d87d/1903abb)
                # entstanden -- kein einziger war beim Umzug schon da.
                # Der Pruefer meldete also 74-mal "neu geschrieben" fuer
                # Code, der mit dem Umzug nichts zu tun hat, und wurde
                # damit rot, sobald irgendjemand irgendwo eine neue
                # Funktion anlegte.
                #
                # Nachgesehen wird deshalb im Stand ZUM ZEITPUNKT DES
                # UMZUGS: stand der Name schon in der Zieldatei, ist es
                # ein echter Befund (er muesste dann aus dem Original
                # kommen und tut es nicht). Kam er spaeter, geht er den
                # Umzug nichts an und wird nur gezaehlt.
                if name in beim_umzug:
                    abweichend.append((name, "steht nicht im Original"))
                else:
                    spaeter += 1
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
        if spaeter:
            print("      (%d Funktionen sind erst NACH dem Umzug"
                  " entstanden und gehoeren nicht dazu)" % spaeter)
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
