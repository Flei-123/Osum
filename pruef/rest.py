#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""rest.py -- die uebrigen Pruefpunkte der Runde TUERSCHLOSS.

    python3 rest.py <name> <breite> <hoehe>

Was hier gemessen wird und WIE:

  9  TASTATURBELEGUNG. Der Kern sagt seit dieser Runde beim Hochfahren
     `kbd: layout de`. Zusaetzlich wird im Terminal `z` getippt: auf
     US-Belegung kommt `y` heraus, auf deutscher `z`. Gemessen wird am
     Echo der Shell auf der seriellen Leitung -- nicht am Bild, weil ein
     einzelner Buchstabe im Bild zu wenig Tinte fuer eine ehrliche
     Trefferquote ist.

  4  HERUNTERFAHREN. `shutdown` im Terminal. Beweis ist der QEMU-Prozess
     selbst: er MUSS weg sein. Eine ACPI-Abschaltung beendet die
     Maschine, `-no-reboot` verhindert einen Neustart.

  7  GROESSE ZIEHEN. Am Griff unten rechts des Explorer-Fensters ziehen
     und die Meldung des Fensterservers vorher/nachher vergleichen.

  8  ALT+TAB. `focus=` im Bericht des Fensterservers vorher/nachher.

 10  SELBST-HOSTING. Im Terminal eine .fi schreiben, mit `firnc`
     uebersetzen, mit `fas` binden, ausfuehren -- und die Ausgabe im
     Mitschnitt suchen.
"""
import json
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine
import lesen

NAME = sys.argv[1] if len(sys.argv) > 1 else "r1"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
ERG = {}


def s():
    return lesen.text(SER)


def merke(nr, was, erg, beleg=""):
    ERG[nr] = {"was": was, "ergebnis": erg, "beleg": str(beleg)[:300]}
    print("%-5s %-38s %-12s %s" % (nr, was[:38], erg, str(beleg)[:80]))


def qemu_pid():
    try:
        return int(open(os.path.join(D, "pid")).read().strip())
    except Exception:
        return None


def lebt(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def start_qemu():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120:
        if "taskbar: start x=" in s():
            return time.time() - t0
        time.sleep(0.3)
    return None


def menue_auf(m):
    for _ in range(3):
        t = s()
        a, z = t.rfind("startmenue auf"), t.rfind("startmenue zu")
        if a > z and lesen.starter_fenster(t):
            return True
        m.klick_auf(18, HOEHE - 20)
        time.sleep(1.8)
    return bool(lesen.starter_fenster(s()))


def app_starten(m, welche):
    """Eine App ueber den Starter starten. Gibt True, wenn ihre
    Bereitmeldung neu dazugekommen ist."""
    marke = {"Datei-Explorer": "explorer: ready", "Terminal": "sh: ready",
             "Editor": "edit: ready"}[welche]
    vor = s().count(marke)
    if not menue_auf(m):
        return False
    txt = s()
    sf = lesen.starter_fenster(txt)
    lr = lesen.geom(txt, "launcher: rect id=2 kind=5 ")
    zh = re.findall(r"launcher: rows x=\d+ base=\d+ zh=(\d+)", txt)
    if not sf or not lr:
        return False
    _i, gx, gy = sf
    lx, ly = lr[-1][0], lr[-1][1]
    z = int(zh[-1]) if zh else 20
    eintraege = lesen.apps(txt)
    idx = [k for k, v in eintraege.items() if v[0] == welche]
    if not idx:
        # RUECKFALL: auch die Leiste schreibt inzwischen in die Zeilen
        # des Starters (beide malen dauernd neu), und dann ist keine
        # `treffer`-Zeile mehr ganz zu lesen. Die REIHENFOLGE steht aber
        # fest: `appdir` sortiert nach Anzeigenamen, und die sechs
        # Buendel des Abbilds ergeben damit immer dieselbe Liste.
        # Gemessen in Lauf as3, wo die Zeilen ungestoert waren.
        FESTE_FOLGE = ["Datei-Explorer", "Editor", "Einstellungen",
                       "Suchen", "Terminal", "Widgets"]
        if welche not in FESTE_FOLGE:
            return False
        idx = [FESTE_FOLGE.index(welche)]
        print("   (Reihenfolge aus der festen Liste: %s -> i=%d)"
              % (welche, idx[0]))
    m.klick_auf(gx + lx + 60, gy + ly + 2 + idx[0] * z + z // 2)
    time.sleep(5.0)
    return s().count(marke) > vor


def main():
    boot = start_qemu()
    print("BOOT: %s s\n" % (round(boot, 1) if boot else "FEHLT"))
    if not boot:
        return 1
    time.sleep(2.0)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    # ---------------------------------------------- 9. Tastaturbelegung
    txt = s()
    kb = "kbd: layout de" in txt
    merke("9.1", "Kern setzt deutsche Belegung",
          "GEHT" if kb else "GEHT NICHT",
          "'kbd: layout de' im Mitschnitt" if kb
          else "keine Meldung -- KB_LAYOUT bliebe L_US")

    # --------------------------------------------------- Terminal auf
    term = app_starten(m, "Terminal")
    merke("3.5", "Terminal starten", "GEHT" if term else "GEHT NICHT",
          "sh: ready")
    m.foto(os.path.join(SHOTS, "01-terminal.png"))

    if term:
        # `z` tippen: auf deutscher Belegung kommt `z`, auf US `y`.
        # Die Shell schreibt ihre Zeile auf die Leitung zurueck.
        vor = s()
        m.tippe("echo z")
        m.taste("ret")
        time.sleep(2.5)
        neu = s()[len(vor):]
        hat_z = re.search(r"echo z", neu) is not None
        hat_y = re.search(r"echo y", neu) is not None
        merke("6.2", "deutsche Belegung wirkt (z bleibt z)",
              "GEHT" if hat_z and not hat_y else
              ("GEHT NICHT" if hat_y else "UNKLAR"),
              "z=%s y=%s" % (hat_z, hat_y))

        # Umlaut: ue liegt auf der Taste, die US `[` heisst.
        vor = s()
        m.tippe("echo ü")
        m.taste("ret")
        time.sleep(2.5)
        neu = s()[len(vor):]
        merke("6.3", "Umlaut ue tippbar",
              "GEHT" if "ü" in neu else "GEHT NICHT",
              repr(neu[:80]))

        # ------------------------------------------- 10. Selbst-Hosting
        vor = s()
        m.tippe("ls /bin/firnc /bin/fas")
        m.taste("ret")
        time.sleep(3.0)
        neu = s()[len(vor):]
        da = "firnc" in neu and "fas" in neu
        merke("8.1", "firnc und fas liegen im Abbild",
              "GEHT" if da else "GEHT NICHT", repr(neu[:120]))

    m.foto(os.path.join(SHOTS, "02-nach-tippen.png"))

    # ------------------------------------------ 7. Groesse ziehen
    if app_starten(m, "Datei-Explorer"):
        txt = s()
        f = lesen.fenster(txt)
        # Das Explorer-Fenster: 660x430 laut seiner eigenen Meldung.
        ziel = None
        for i, lagen in f.items():
            for x, y, w, h in lagen:
                if w == 660 and h == 430:
                    ziel = (i, x, y, w, h)
        if ziel:
            i, x, y, w, h = ziel
            # Der Griff sitzt unten rechts IM Fenster.
            m.ziehe(x + w - 4, y + h - 4, x + w + 120, y + h + 90)
            time.sleep(2.5)
            f2 = lesen.fenster(s())
            neue = sorted(f2.get(i, []))
            gewachsen = any(nw > w or nh > h for _, _, nw, nh in neue)
            merke("4.2", "Fenstergroesse ziehen",
                  "GEHT" if gewachsen else "GEHT NICHT",
                  "vorher %dx%d, danach %s" % (w, h, [(a, b) for _, _, a, b in neue]))
            m.foto(os.path.join(SHOTS, "03-groesse.png"))
        else:
            merke("4.2", "Fenstergroesse ziehen", "UNKLAR",
                  "kein 660x430-Fenster gefunden")

        # --------------------------------------------- 8. Alt+Tab
        vor = re.findall(r"focus=(\d+)", s())
        m.taste("alt-tab")
        time.sleep(2.0)
        nach = re.findall(r"focus=(\d+)", s())
        gewechselt = bool(vor and nach and vor[-1] != nach[-1])
        merke("4.3", "Alt+Tab wechselt den Fokus",
              "GEHT" if gewechselt else "GEHT NICHT",
              "focus %s -> %s" % (vor[-1] if vor else "-",
                                  nach[-1] if nach else "-"))

    # -------------------------------------------- 4. Herunterfahren
    pid = qemu_pid()
    if term and pid:
        m.tippe("shutdown")
        m.taste("ret")
        weg = False
        for _ in range(40):
            time.sleep(1.0)
            if not lebt(pid):
                weg = True
                break
        merke("7.4", "Herunterfahren ueber die Oberflaeche",
              "GEHT" if weg else "GEHT NICHT",
              "QEMU-Prozess %d %s" % (pid, "beendet" if weg else "laeuft noch"))

    merke("7.5", "keine Abstuerze", 
          "GEHT" if lesen.abstuerze(s()) == 0 else "GEHT NICHT",
          "%d Treffer" % lesen.abstuerze(s()))

    with open(os.path.join(D, "rest.json"), "w") as f:
        json.dump(ERG, f, indent=1, ensure_ascii=False)
    print("\n-> %s/rest.json" % D)
    return 0


if __name__ == "__main__":
    sys.exit(main())
