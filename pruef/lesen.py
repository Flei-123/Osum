#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""lesen.py -- den seriellen Mitschnitt lesen, OBWOHL er verwoben ist.

DAS PROBLEM, und es hat in dieser Runde zwei Fehlmessungen gekostet:
auf der seriellen Leitung schreiben Schreibtisch, Leiste, Starter, DHCP
und der Kern GLEICHZEITIG. Eine Zeile wie

    launcher: start /apps/explorer.osp/start pid=20

kommt darum als

    launcher: start /e
    ...
    launcher: start /apps/explorer.osp/startdhcp: ack ip=

an -- mit einer fremden Zeile mitten darin. Ein Suchmuster mit `$` am
Ende findet sie nie, und wer daraus "kein Start" schliesst, misst den
Mitschnitt und nicht das System.

DIE ANTWORT DARAUF: nicht auf ganze Zeilen bauen, sondern auf MARKEN,
die fuer sich stehen -- und wo eine Zahl gebraucht wird, sie beim
NAECHSTEN Vorkommen ihres Schluessels holen, nicht am Zeilenende.
"""
import re


def text(pfad):
    try:
        with open(pfad, "rb") as f:
            roh = f.read()
    except OSError:
        return ""
    return roh.replace(b"\x00", b"").decode("utf-8", "replace")


def zaehle(s, marke):
    """Wie oft eine Marke vorkommt -- unabhaengig von Zeilengrenzen."""
    return s.count(marke)


def zahlen_nach(s, marke, schluessel="pid=", weite=80):
    """Alle Zahlen, die NACH einer Marke innerhalb von `weite` Zeichen
    unter `schluessel` stehen. So ueberlebt die Messung eine fremde
    Zeile mitten im Satz."""
    aus = []
    for m in re.finditer(re.escape(marke), s):
        fenster = s[m.end():m.end() + weite]
        t = re.search(re.escape(schluessel) + r"(-?\d+)", fenster)
        if t:
            aus.append(int(t.group(1)))
    return aus


def geom(s, marke):
    """`<marke> x=.. y=.. w=.. h=..` -- die vier Zahlen, jede einzeln
    gesucht, damit eine fremde Einstreuung dazwischen nichts kaputt
    macht."""
    aus = []
    for m in re.finditer(re.escape(marke), s):
        f = s[m.end():m.end() + 120]
        w = {}
        for k in ("x", "y", "w", "h"):
            t = re.search(r"\b%s=(\d+)" % k, f)
            if t:
                w[k] = int(t.group(1))
        if len(w) == 4:
            aus.append((w["x"], w["y"], w["w"], w["h"]))
    return aus


# Welches Buendel zu welchem Anzeigenamen gehoert. Die Zuordnung steht
# in assets/apps/*/INFO und aendert sich nicht im Betrieb -- sie hier zu
# kennen ist ehrlicher, als sie aus einer zerschossenen Zeile zu raten.
BUENDEL = {
    "explorer": "Datei-Explorer",
    "editor": "Editor",
    "launcher": "Suchen",
    "terminal": "Terminal",
    "widgets": "Widgets",
    "settings": "Einstellungen",
}


def apps(s):
    """Die Eintraege des Starters: i -> (Name, exec).

    WARUM NICHT EINFACH DIE ZEILE LESEN. Auf der Leitung schreibt der
    DHCP-Dienst waehrend des Hochfahrens mitten in die Zeilen des
    Starters hinein -- gemessen:

        launcher: treffer i=4 name=[dhcp: /etc/resolv.conf ... Widgets1]

    Der Name ist damit unbrauchbar, der PFAD aber nicht: `/apps/<x>.osp/`
    steht als ganzes Stueck da, weil es kuerzer ist als der Abstand
    zwischen zwei fremden Einstreuungen. Also wird der Eintrag ueber
    SEIN BUENDEL bestimmt und der Anzeigename aus der Zuordnung oben
    geholt. Wo auch der Pfad zerrissen ist, faellt der Eintrag weg --
    lieber eine Luecke als eine erfundene Zeile.
    """
    aus = {}
    for m in re.finditer(r"launcher: treffer i=(\d+)", s):
        i = int(m.group(1))
        f = s[m.end():m.end() + 200]
        t = re.search(r"/apps/(\w+)\.osp/start", f)
        if not t:
            continue
        b = t.group(1)
        aus[i] = (BUENDEL.get(b, b), "/apps/%s.osp/start" % b)
    return aus


def app_zahl(s):
    """Wie viele Eintraege der Starter selbst gezaehlt hat."""
    t = re.findall(r"launcher: suche \[[^\]]*\] treffer=(\d+) apps=(\d+)", s)
    return (int(t[-1][0]), int(t[-1][1])) if t else (0, 0)


def fenster(s):
    """Jede gemeldete Fensterlage `id=<n> x=.. y=.. w=.. h=..`."""
    aus = {}
    for m in re.finditer(r"\bid=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s):
        i = int(m.group(1))
        aus.setdefault(i, set()).add(tuple(int(m.group(k)) for k in (2, 3, 4, 5)))
    return aus


def abstuerze(s):
    """Panik, Seitenfehler, ungueltiger Befehl -- was ein Absturz ist."""
    return len(re.findall(r"PANIK|panic|#PF|#UD|#GP|TRAP|Ausnahme", s))


def starts(s):
    """(pfad, pid) jedes Programmstarts aus dem Starter -- pfad nur so
    weit, wie er ungestoert lesbar war."""
    aus = []
    for m in re.finditer(r"launcher: start ", s):
        f = s[m.end():m.end() + 90]
        pfad = re.match(r"(\S+)", f)
        pid = re.search(r"pid=(-?\d+)", f)
        aus.append((pfad.group(1) if pfad else "?",
                    int(pid.group(1)) if pid else None))
    return aus


def starter_fenster(s, breite=440, hoehe=300):
    """Wo das Startmenue WIRKLICH steht.

    Nicht aus `launcher: geom` -- diese Zeile wird vom DHCP-Dienst
    zerschossen (gemessen: 'launcher: geom 1x='). Der FENSTERSERVER
    meldet dieselbe Lage in einer viel kuerzeren Zeile
    (`id=11 x=8 y=452 w=440 h=300`), und kurze Zeilen ueberleben das
    Gedraenge auf der Leitung. Gesucht wird nach der GROESSE, die der
    Starter sich gibt -- die steht als Festwert in launcher.fi.
    """
    f = fenster(s)
    for i in sorted(f, reverse=True):
        for x, y, w, h in f[i]:
            if w == breite and h == hoehe:
                return i, x, y
    return None
