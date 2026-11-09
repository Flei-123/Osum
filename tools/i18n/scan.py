#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

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
FALLBACK = re.compile(r"\b[A-ZÄÖÜa-zäöü]*(ue|ae|oe)[a-z]{2,}\b")
FALLBACK_OK = {"guest", "queue", "value", "values", "true", "blue",
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
    "kernel/user/fuiapp/wlib.fi",
    "kernel/user/fuiapp/wlib/wlax.fi",
    "kernel/user/fuiapp/wlib/wlbase.fi",
    "kernel/user/fuiapp/wlib/wldraw.fi",
    "kernel/user/fuiapp/wlib/wlevent.fi",
    "kernel/user/fuiapp/wlib/wlstate.fi",
    "kernel/user/fuiapp/wlib/wlwidget.fi",
    "kernel/user/wlibc.fi",
    "kernel/user/wlibc/wcbase.fi",
    "kernel/user/wlibc/wcgfx.fi",
    "kernel/user/wlibc/wcpaint.fi",
    "kernel/user/uitheme/thapply.fi",
    "kernel/user/uitheme/thbase.fi",
    "kernel/user/uitheme/thedge.fi",
    "kernel/user/uitheme/thfile.fi",
    "kernel/user/uitheme/thload.fi",
    "kernel/user/uitheme/thprobe.fi",
    "kernel/user/uitheme/thpush.fi",
    "kernel/user/uitheme/thquery.fi",
    "kernel/user/wlibc/wcstart.fi",
    "kernel/user/msg.fi",
    "kernel/ui/wm.fi",
    "kernel/ui/wm/wmtrust.fi",
]

QUELLEN = ["kernel"]
EXCEPTIONS = ["kernel/user/i18nt.fi"]


def literale(line):
    aus = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            break
        if c == '"':
            j = i + 1
            buf = []
            while j < n:
                if line[j] == "\\" and j + 1 < n:
                    buf.append(line[j:j + 2])
                    j += 2
                    continue
                if line[j] == '"':
                    break
                buf.append(line[j])
                j += 1
            aus.append("".join(buf))
            i = j + 1
            continue
        i += 1
    return aus


def erlaubt(text):
    t = text.strip()
    if not t:
        return True
    if t.startswith("/"):
        return True
    if re.match(r"^[a-z0-9]+: ", t):
        return True
    if re.match(r"^[a-z0-9_]+(\.[a-z0-9_]+)+(\\0)*$", t):
        return True
    if re.match(r"^[ ]?[a-z0-9_]+=", t):
        return True
    return False


def list_check(root):
    if len(sys.argv) > 1:
        return
    missing = [r for r in OBERFLAECHE
             if not os.path.isfile(os.path.join(root, r))]
    if missing:
        for r in missing:
            print("scan: EXECUTED, BUT NOT THERE: %s" % r)
        raise SystemExit(2)


def check(path_2, streng):
    treffer = []
    try:
        roh = open(path_2, "rb").read().decode("utf-8", "replace")
    except OSError:
        print("scan: EXECUTED, BUT NOT THERE: %s" % path_2)
        raise SystemExit(2)
    for nr, line in enumerate(roh.split("\n"), 1):
        for lit in literale(line):
            if erlaubt(lit):
                continue
            klar = lit.replace("\\0", "").replace("\\n", " ") \
                      .replace("\\t", " ")
            for w in WOERTER:
                if w in klar:
                    treffer.append((path_2, nr, w, klar.strip()))
                    break
            else:
                if not streng:
                    continue
                m = FALLBACK.search(klar)
                if m and m.group(0).lower() not in FALLBACK_OK \
                        and len(klar.strip()) > 6:
                    treffer.append((path_2, nr, m.group(0), klar.strip()))
    return treffer


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    list_check(root)
    surface = []
    rest = []
    for basis in QUELLEN:
        start = os.path.join(root, basis)
        if not os.path.isdir(start):
            continue
        for folder, _dirs, dateien in os.walk(start):
            for d in sorted(dateien):
                if not d.endswith(".fi"):
                    continue
                p = os.path.join(folder, d)
                rel = os.path.relpath(p, root).replace(os.sep, "/")
                if rel in EXCEPTIONS:
                    continue
                if rel in OBERFLAECHE:
                    surface += check(p, True)
                else:
                    rest += check(p, False)
    for path_2, nr, word_2, text in surface:
        print("%s:%d: '%s' in \"%s\"" % (path_2, nr, word_2, text[:70]))
    print("gefunden: %d" % len(surface))
    print("not in the catalog, but counted (own windows and"
          " uebersetzt): %d" % len(rest))
    for path_2, nr, word_2, text in rest:
        print("    %s:%d: '%s'" % (path_2, nr, word_2))
    return 1 if surface else 0


sys.exit(main())
