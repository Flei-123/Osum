#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    read_all.py -- den seriellen Mitschnitt read_all, OBWOHL er verwoben ist.
"""
import re


def text(path):
    try:
        with open(path, "rb") as f:
            roh = f.read()
    except OSError:
        return ""
    return roh.replace(b"\x00", b"").decode("utf-8", "replace")


def zaehle(s, mark):
    """Wie oft eine Marke vorkommt -- unabhaengig von Zeilengrenzen."""
    return s.count(mark)


def numbers_after(s, mark, key="pid=", span=80):
    """Alle Zahlen, die NACH einer Marke innerhalb von `weite` Zeichen
    unter `schluessel` stehen. So ueberlebt die Messung eine fremde
    Zeile mitten im Satz."""
    aus = []
    for m in re.finditer(re.escape(mark), s):
        window = s[m.end():m.end() + span]
        t = re.search(re.escape(key) + r"(-?\d+)", window)
        if t:
            aus.append(int(t.group(1)))
    return aus


def geom(s, mark):
    """`<marke> x=.. y=.. w=.. h=..` -- die vier Zahlen, jede einzeln
    gesucht, damit eine fremde Einstreuung dazwischen nichts kaputt
    macht."""
    aus = []
    for m in re.finditer(re.escape(mark), s):
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


def app_count(s):
    """Wie viele Eintraege der Starter selbst gezaehlt hat."""
    t = re.findall(r"launcher: suche \[[^\]]*\] treffer=(\d+) apps=(\d+)", s)
    return (int(t[-1][0]), int(t[-1][1])) if t else (0, 0)


def window(s):
    """Jede vom FENSTERSERVER gemeldete Fensterlage.

    ACHTUNG, hier lag ein Fehler: gesucht wurde nach `id=<n> x=..`, und
    das trifft AUCH die Knopfliste der Leiste --

        wm: fen     i=0 id=7 x=24 y=40 w=560 h=380   das Fenster
        taskbar: btn i=0 id=7 x=42 y=7  w=34  h=26   sein Knopf

    Beide sagen `id=7` und meinen etwas anderes. Wer sie mischt, misst
    ein 560x380 grosses Fenster, das ploetzlich 34x26 ist, und nennt
    das "Groesse aendern geht nicht". Also nur `wm: fen`.
    """
    aus = {}
    for m in re.finditer(
            r"wm: fen i=\d+ id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s):
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
        path = re.match(r"(\S+)", f)
        pid = re.search(r"pid=(-?\d+)", f)
        aus.append((path.group(1) if path else "?",
                    int(pid.group(1)) if pid else None))
    return aus


def starter_window(s, width=440, height=300):
    """Wo das Startmenue WIRKLICH steht.

    Nicht aus `launcher: geom` -- diese Zeile wird vom DHCP-Dienst
    zerschossen (gemessen: 'launcher: geom 1x='). Der FENSTERSERVER
    meldet dieselbe Lage in einer viel kuerzeren Zeile
    (`id=11 x=8 y=452 w=440 h=300`), und kurze Zeilen ueberleben das
    Gedraenge auf der Leitung. Gesucht wird nach der GROESSE, die der
    Starter sich gibt -- die steht als Festwert in launcher.fi.
    """
    f = window(s)
    for i in sorted(f, reverse=True):
        for x, y, w, h in f[i]:
            if w == width and h == height:
                return i, x, y
    return None
