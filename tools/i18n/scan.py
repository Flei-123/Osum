#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/i18n/scan.py -- STEHT NOCH DEUTSCHER OBERFLAECHENTEXT IM QUELLTEXT?
#
#   python3 tools/i18n/scan.py [wurzel]
#
# Meldet jede Fundstelle und am Ende "gefunden: <n>". Das Ziel ist 0.
# Der Rueckgabewert ist 0, wenn nichts gefunden wurde, sonst 1.
#
# WAS GESUCHT WIRD, und warum es nicht "jedes deutsche Wort" ist:
#
# Dieses Projekt schreibt seine KOMMENTARE und seine MITSCHNITTE auf
# Deutsch, und das soll es auch weiter tun. Ein Pruefer, der jedes
# deutsche Wort im Quelltext anschlaegt, findet dreitausend Treffer und
# wird am zweiten Tag abgeschaltet. Gesucht wird deshalb genau das, was
# Runde I18N verboten hat:
#
#     EIN ZEICHENKETTENLITERAL, DAS AUF DEM BILDSCHIRM LANDEN KANN UND
#     DEUTSCH IST.
#
# Erkannt wird es an drei Dingen zusammen:
#
#   1. Es ist ein Literal in einer .fi-Datei UNTER kernel/user/ oder
#      kernel/ -- also im Quelltext des Systems, nicht in einem Werkzeug
#      des Wirts.
#   2. Es steht NICHT in einem Kommentar.
#   3. Es enthaelt ein Wort aus der Liste unten -- deutsche Woerter, die
#      in diesem Baum WIRKLICH als Oberflaechentext vorkamen, plus die
#      Ersatzschreibungen "ue", "ae", "oe" in einem Wort, das sonst
#      deutsch aussieht.
#
# WAS AUSDRUECKLICH ERLAUBT BLEIBT und deshalb nicht anschlaegt:
#
#   * Mitschnitte fuer Testlaeufer: alles, was mit "<programm>: "
#     anfaengt ("taskbar: knopf i=", "settings: keine Flaeche").
#     Sie gehen auf die SERIELLE LEITUNG und nie auf den Bildschirm, ein
#     Testlaeufer greppt danach, und ein uebersetzter Mitschnitt machte
#     jeden Testlaeufer sprachabhaengig.
#   * Pfade und Konfigurationsschluessel: alles, was mit "/" anfaengt
#     oder wie "modus=" aussieht.
#   * Kommentare. Sie sind die Doku dieses Projekts.
#
# GEGENPROBE. Dieses Programm hat eine, und sie steht in
# tools/i18n/run.sh: eine Datei mit einem eingebauten "Uebernehmen" MUSS
# anschlagen. Ein Pruefer ohne Gegenprobe prueft nichts.
import os
import re
import sys

# Woerter, die in diesem Baum wirklich als Oberflaechentext standen.
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
]
# Ein Wort mit einer Ersatzschreibung darin. Nur in den Dateien der
# OBERFLAECHE angewandt -- im uebrigen Baum stehen englische Woerter wie
# "guest", "queue" und "value", die alle ein "ue" tragen und nichts
# bedeuten. Ein Pruefer, der die anschlaegt, wird abgeschaltet.
ERSATZ = re.compile(r"\b[A-ZÄÖÜa-zäöü]*(ue|ae|oe)[a-z]{2,}\b")
ERSATZ_OK = {"guest", "queue", "value", "values", "true", "blue",
             "aeon", "oeuvre", "cue", "due", "issue", "rue", "sue"}

# DIE OBERFLAECHE. Genau die Dateien, die diese Runde umgestellt hat --
# die fuenf Programme mit einem Fenster, die Widget-Bibliothek darunter
# und der Fensterserver, der die Titelleiste malt. HIER ist das Ziel 0.
OBERFLAECHE = [
    "kernel/user/settings.fi",
    "kernel/user/taskbar.fi",
    "kernel/user/desktop.fi",
    "kernel/user/explorer.fi",
    "kernel/user/launcher.fi",
    "kernel/user/wlib.fi",
    "kernel/user/wlibc.fi",
    "kernel/user/msg.fi",
    "kernel/wm.fi",
]

# Wo AUSSERDEM gesucht wird -- zum BERICHTEN, nicht zum Scheitern.
#
# EHRLICH GEZAEHLT UND NICHT VERSTECKT. Unter kernel/user/ liegen
# ausserdem `power.fi`, `widgetdemo.fi`, `fas.fi` und `firun.fi`. Das sind
# BEFEHLSZEILENPROGRAMME (und eine Widget-Vorfuehrung aus Runde K15);
# ihr Text geht nach stdout, nicht durch den Fensterserver, und diese
# Runde hat sie nicht angefasst. Sie werden trotzdem gezaehlt und
# gemeldet, damit die Zahl "0" nicht dadurch entsteht, dass man
# wegsieht.
QUELLEN = ["kernel"]
AUSNAHMEN = ["kernel/user/i18nt.fi"]


def literale(zeile):
    """Die Zeichenkettenliterale einer Zeile, ohne Kommentare."""
    # Ein Kommentar beginnt bei `//`, aber nicht innerhalb eines
    # Literals. Also von links durchgehen.
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
    # "modus=", "offset=", " x=", " fg=" -- ein Schluessel oder ein Feld.
    if re.match(r"^[ ]?[a-z0-9_]+=", t):
        return True
    return False


def pruefe(pfad, streng):
    treffer = []
    try:
        roh = open(pfad, "rb").read().decode("utf-8", "replace")
    except OSError:
        return treffer
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
    print("ausserhalb dieser Runde (Befehlszeilenprogramme, nicht"
          " uebersetzt): %d" % len(rest))
    for pfad, nr, wort, text in rest:
        print("    %s:%d: '%s'" % (pfad, nr, wort))
    return 1 if surface else 0


sys.exit(main())
