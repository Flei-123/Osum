#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
#
#   python3 tools/i18n/scan.py [wurzel]
#
#
#
#
#
#
#
#
#
import os
import re
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import marke

WOERTER = [
    "Einstellungen", "Darstellung", "Bildschirm", "Benutzer",
    "Farbschema", "Hintergrundbild", "Uebernehmen", "Aufloesung",
    "Zeitzone", "Adresse beziehen", "Kennwort", "Neues Kennwort",
    "Noch einmal", "Taskleiste", "Schreibtisch", "kein Akku",
    "kein Netz", "Programm suchen", "Ausfuehren", "Umbenennen",
    "Loeschen", "Oeffnen", "Neuer Ordner", "Aktualisieren", "Beenden",
    "Nach Name", "Nach Groesse", "Umgekehrt", "Wirklich loeschen",
    "Groesse", "Rechte", "Ansicht", "Stueck", "Oktette", "Ordner",
    "Quelldatei", "gefunden", "geschrieben", "gesetzt fuer",
    "gestartet", "gespeichert", "uebernommen", "kopiert",
    "Eingaben", "Zeichen", "Wurzel",
    "Übernehmen", "Auflösung", "Ausführen", "Löschen", "Öffnen",
    "Nach Größe", "Wirklich löschen", "Größe", "Größte", "Stück",
    "gesetzt für", "Menü", "vortäuschen", "Fläche", "Schlüssel",
    "Zurück", "Nächstes", "Vorwärts", "Ausgewählt", "lädt",
]
ERSATZ = re.compile(r"\b[A-ZÄÖÜa-zäöü]*(ue|ae|oe)[a-z]{2,}\b")
ERSATZ_OK = {"guest", "queue", "value", "values", "true", "blue",
             "aeon", "oeuvre", "cue", "due", "issue", "rue", "sue"}

OBERFLAECHE = [
    "kernel/user/settings.fi",
    "kernel/user/settings/setaccount.fi",
    "kernel/user/settings/setbase.fi",
    "kernel/user/settings/setbuild.fi",
    "kernel/user/settings/setcore.fi",
    "kernel/user/settings/setdevice.fi",
    "kernel/user/settings/setpages.fi",
    "kernel/user/settings/setsystem.fi",
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
    "kernel/user/explorer.fi",
    "kernel/user/explorer/expbase.fi",
    "kernel/user/explorer/expmenu.fi",
    "kernel/user/explorer/expnav.fi",
    "kernel/user/explorer/expwork.fi",
    "kernel/user/launcher.fi",
    "kernel/user/wlib.fi",
    "kernel/user/wlib/wlax.fi",
    "kernel/user/wlib/wlbase.fi",
    "kernel/user/wlib/wldraw.fi",
    "kernel/user/wlib/wlevent.fi",
    "kernel/user/wlib/wlstate.fi",
    "kernel/user/wlib/wlwidget.fi",
    "kernel/user/wlibc.fi",
    "kernel/user/wlibc/wcbase.fi",
    "kernel/user/wlibc/wcgfx.fi",
    "kernel/user/wlibc/wcpaint.fi",
    "kernel/user/wlibc/wctheme.fi",
    "kernel/user/msg.fi",
    "kernel/ui/wm.fi",
    "kernel/ui/wm/wmtrust.fi",
]

#
#
#
QUELLEN = ["kernel"]
AUSNAHMEN = ["kernel/user/i18nt.fi"]


def literale(zeile):
    """Die Zeichenkettenliterale einer Zeile, ohne Kommentare."""
    aus = []
    i = 0
    n = len(zeile)
    while i < n:
        c = zeile[i]
        if c == "/" and i + 1 < n and zeile[i + 1] == "/":
            break
        if c == '"':
            j = i + 1
            buf = []
            while j < n:
                if zeile[j] == "\\" and j + 1 < n:
                    buf.append(zeile[j:j + 2])
                    j += 2
                    continue
                if zeile[j] == '"':
                    break
                buf.append(zeile[j])
                j += 1
            aus.append("".join(buf))
            i = j + 1
            continue
        i += 1
    return aus


def erlaubt(text):
    """Mitschnitte, Pfade und Konfigurationsschluessel."""
    t = text.strip()
    if not t:
        return True
    if t.startswith("/"):
        return True
    # "taskbar: ...", "settings: ...", "i18n: ..." -- ein Mitschnitt.
    if re.match(r"^[a-z0-9]+: ", t):
        return True
    if re.match(r"^[a-z0-9_]+(\.[a-z0-9_]+)+(\\0)*$", t):
        return True
    if t.startswith(marke.PRODUKT + " - Bestaetigung"):
        return True
    if re.match(r"^[ ]?[a-z0-9_]+=", t):
        return True
    return False


#
def liste_pruefen(wurzel):
    if len(sys.argv) > 1:
        return
    fehlt = [r for r in OBERFLAECHE
             if not os.path.isfile(os.path.join(wurzel, r))]
    if fehlt:
        for r in fehlt:
            print("scan: EXECUTED, BUT NOT THERE: %s" % r)
        raise SystemExit(2)


def pruefe(pfad, streng):
    treffer = []
    try:
        roh = open(pfad, "rb").read().decode("utf-8", "replace")
    except OSError:
        print("scan: EXECUTED, BUT NOT THERE: %s" % pfad)
        raise SystemExit(2)
    for nr, zeile in enumerate(roh.split("\n"), 1):
        for lit in literale(zeile):
            if erlaubt(lit):
                continue
            klar = lit.replace("\\0", "").replace("\\n", " ") \
                      .replace("\\t", " ")
            for w in WOERTER:
                if w in klar:
                    treffer.append((pfad, nr, w, klar.strip()))
                    break
            else:
                if not streng:
                    continue
                m = ERSATZ.search(klar)
                if m and m.group(0).lower() not in ERSATZ_OK \
                        and len(klar.strip()) > 6:
                    treffer.append((pfad, nr, m.group(0), klar.strip()))
    return treffer


def main():
    wurzel = sys.argv[1] if len(sys.argv) > 1 else "."
    liste_pruefen(wurzel)
    surface = []
    rest = []
    for basis in QUELLEN:
        start = os.path.join(wurzel, basis)
        if not os.path.isdir(start):
            continue
        for ordner, _dirs, dateien in os.walk(start):
            for d in sorted(dateien):
                if not d.endswith(".fi"):
                    continue
                p = os.path.join(ordner, d)
                rel = os.path.relpath(p, wurzel).replace(os.sep, "/")
                if rel in AUSNAHMEN:
                    continue
                if rel in OBERFLAECHE:
                    surface += pruefe(p, True)
                else:
                    rest += pruefe(p, False)
    for pfad, nr, wort, text in surface:
        print("%s:%d: '%s' in \"%s\"" % (pfad, nr, wort, text[:70]))
    print("gefunden: %d" % len(surface))
    print("not in the catalog, but counted (own windows and"
          " uebersetzt): %d" % len(rest))
    for pfad, nr, wort, text in rest:
        print("    %s:%d: '%s'" % (pfad, nr, wort))
    return 1 if surface else 0


sys.exit(main())
