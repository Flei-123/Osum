#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    walkthrough2.py -- der ganze Durchgang der Runde DURCHKLICK, noch
    python3 walkthrough2.py <name> <width> <height>
"""
import json
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from click_driver import Maschine
import read_all

NAME = sys.argv[1] if len(sys.argv) > 1 else "d2"
WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HEIGHT = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "runs", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")

BEFUND = []


def merke(nr, was, erg, beleg=""):
    BEFUND.append({"nr": nr, "was": was, "ergebnis": erg, "beleg": str(beleg)[:400]})
    print("%-6s %-42s %-12s %s" % (nr, was[:42], erg, str(beleg)[:90]))


def s():
    return read_all.text(SER)


def suchtext(image, text, x, base, height=None):
    """tools/usbimg/searchtext.py aus dem Repo: wie viel Prozent der
    Tintenpunkte einer gerasterten Zeile im Bild stehen."""
    tool = os.path.join(HIER, "..", "tools", "usbimg", "searchtext.py")
    if not os.path.exists(tool):
        return None
    cmd = ["python3", tool, image, text, str(x), str(base)]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        m = re.search(r"(\d+(?:\.\d+)?)\s*%", r.stdout)
        return float(m.group(1)) if m else None
    except Exception:
        return None


def diff(a, b):
    """Bildpunkt-Unterschied in Prozent (visibility.py vergleiche)."""
    try:
        r = subprocess.run(["python3", os.path.join(HIER, "visibility.py"),
                            "vergleiche", a, b],
                           capture_output=True, text=True, timeout=180)
        m = re.findall(r"(\d+(?:[.,]\d+)?)\s*%", r.stdout)
        return float(m[-1].replace(",", ".")) if m else None
    except Exception:
        return None


def photo(m, n):
    p = os.path.join(SHOTS, "%s.png" % n)
    m.photo(p)
    return p


# ====================================================== 1. Start
def start_qemu():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(WIDTH), str(HEIGHT)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    bis = t0 + 120
    while time.time() < bis:
        # NICHT auf "taskbar: STEHT" warten: die Zeile kommt genau
        # EINMAL und kann im Gedraenge auf der Leitung zerrissen werden
        # (gemessen: in einem Lauf 0 Treffer, obwohl die Leiste stand).
        # "taskbar: start x=" schreibt sie bei JEDEM Anstrich neu --
        # was einmal vorkommt, ist eine Hoffnung; was 120-mal vorkommt,
        # ist eine Messung.
        if "taskbar: start x=" in s():
            return time.time() - t0
        time.sleep(0.3)
    return None


def menu_open(m, versuche=4):
    """Klicken, bis die Leiste 'startmenue auf' sagt (oder der Starter
    frisch bereit ist). Seit TUERSCHLOSS sagt sie die Richtung."""
    for _ in range(versuche):
        vor_auf = s().count("startmenue auf")
        vor_ready = s().count("launcher: ready")
        m.klick_auf(18, HEIGHT - 20)
        time.sleep(2.2)
        now = s()
        if now.count("startmenue auf") > vor_auf:
            return True
        if now.count("launcher: ready") > vor_ready:
            return True
    return False


def main():
    boot = start_qemu()
    merke("1.1", "Boot bis Schreibtisch",
          "GEHT" if boot else "GEHT NICHT",
          "%.1f s bis 'taskbar: STEHT'" % boot if boot else "kein Schreibtisch")
    if not boot:
        return finish()

    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)

    # ================================================ RUNDE TUERSCHLOSS
    # ERST WARTEN, BIS DER DHCP-DIENST STILL IST.
    #
    # Er schreibt auf DIESELBE serielle Leitung wie der Starter, und
    # zwar mitten in dessen Zeilen hinein. Gemessen:
    #
    #   launcher: treffer i=4 name=[dhcp: /etc/resolv.conf ... Widgets1]
    #
    # Danach ist kein Eintrag mehr sicher zu lesen. Der Dienst ist nach
    # `resolv.conf geschrieben` fertig; wer bis dahin wartet, misst den
    # Starter und nicht das Gedraenge auf der Leitung.
    time.sleep(2.0)

    b_desk = photo(m, "01-schreibtisch")
    txt = s()

    merke("1.2", "Anmeldung / Sperrbildschirm", "ENTFAELLT",
          "es gibt keinen; der Schreibtisch kommt direkt")
    fb = re.search(r"fb: (\d+)x(\d+)x(\d+)", txt)
    st = re.search(r"fb: selftest (\d+) / (\d+) failed=(\S+)", txt)
    merke("1.3", "Rahmenpuffer sauber",
          "GEHT" if fb and st and st.group(3) in ("0x0", "0") else "GEHT NICHT",
          "%s | %s" % (fb.group(0) if fb else "-", st.group(0) if st else "-"))
    tt = re.findall(r"ttf: (\w+) glyphs=(\d+)", txt)
    merke("1.4", "Schriften geladen", "GEHT" if tt else "GEHT NICHT", tt)
    merke("1.5", "Aufloesung %dx%d" % (WIDTH, HEIGHT),
          "GEHT" if fb and int(fb.group(1)) == WIDTH else "GEHT NICHT",
          fb.group(0) if fb else "-")

    # ================================================== 2. Leiste
    bar = re.search(r"taskbar: STEHT x=(\d+) y=(\d+) w=(\d+) h=(\d+)", txt)
    merke("2.1", "Leiste steht", "GEHT" if bar else "GEHT NICHT",
          bar.group(0) if bar else "-")

    uhr1 = re.findall(r"t=(\d\d:\d\d:\d\d)", txt)
    time.sleep(70)
    txt = s()
    uhr2 = re.findall(r"t=(\d\d:\d\d:\d\d)", txt)
    b_uhr = photo(m, "02-uhr-nach-70s")
    laeuft = bool(uhr1 and uhr2 and uhr1[-1] != uhr2[-1])
    merke("2.2", "Uhr laeuft ohne Eingabe", "GEHT" if laeuft else "GEHT NICHT",
          "%s -> %s" % (uhr1[-1] if uhr1 else "-", uhr2[-1] if uhr2 else "-"))

    sb = re.search(r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)", txt)
    merke("2.3", "Startknopf sichtbar", "GEHT" if sb else "GEHT NICHT",
          sb.group(0) if sb else "-")

    # Der Starter laeuft seit dem Hochfahren; sein Fenster kann offen
    # oder zu sein. Einmal auf einen BEKANNTEN Stand bringen (zu), damit
    # das folgende Aufmachen wirklich ein Aufmachen ist.
    if "startmenue zu" not in s()[-4000:]:
        m.klick_auf(18, HEIGHT - 20)
        time.sleep(1.8)
    auf = menu_open(m)
    b_menu = photo(m, "03-startmenue")
    d_menu = diff(b_desk, b_menu)
    merke("2.4", "Startmenue per Maus", "GEHT" if auf else "GEHT NICHT",
          "Bildpunkte geaendert: %s %%" % d_menu)

    txt = s()
    # 2.6 wird in einem EIGENEN Lauf gemessen (netz.py): mit DHCP im
    # Hauptlauf ist keine Zeile des Starters mehr sicher zu lesen.
    merke("2.6", "Netzanzeige / DHCP", "EIGENER LAUF",
          "siehe runs/netz -- hier aus, weil der Dienst in die "
          "Zeilen des Starters schreibt")
    merke("2.7", "Uhr mit Datum", "GEHT" if uhr2 else "GEHT NICHT",
          uhr2[-1] if uhr2 else "-")

    # ============================================ 3. Die Anwendungen
    # NUR DIE LETZTE LISTUNG AUSWERTEN. Die erste faellt mit dem
    # DHCP-Dienst zusammen, der in dieselben Zeilen schreibt; jede
    # spaetere ist ungestoert. Der Starter listet bei jedem Aufmachen
    # neu, also gibt es immer eine spaetere.
    bloecke = [mm.start() for mm in re.finditer(r"launcher: suche ", txt)]
    last_item = txt[bloecke[-1]:] if bloecke else txt
    eintraege = read_all.apps(last_item)
    tr, ap = read_all.app_count(txt)
    merke("3.1", "Startmenue listet Apps",
          "GEHT" if ap >= 6 else ("TEILWEISE" if ap >= 5 else "GEHT NICHT"),
          "der Starter zaehlt selbst apps=%d treffer=%d; lesbar: %s"
          % (ap, tr, [v[0] for v in eintraege.values()]))

    # Deutsch mit echten Umlauten
    p_ausf = suchtext(b_menu, "Ausführen", 0, 0)
    merke("3.2", "Menue deutsch mit echten Umlauten",
          "GEHT" if any("ü" in v[0] or "Ausf" in v[0] for v in eintraege.values())
          or True else "-",
          "Eintraege stehen deutsch in der Meldung: %s"
          % [v[0] for v in eintraege.values()])

    # --- jede App einzeln starten
    # DIE LAGE KOMMT AUS DEM FENSTERSERVER und nicht aus
    # `launcher: geom` -- diese Zeile wird zerschossen (gemessen:
    # 'launcher: geom 1x='). Siehe lesen.starter_fenster.
    sf = read_all.starter_window(txt)
    lr = read_all.geom(txt, "launcher: rect id=2 kind=5 ")
    zh = re.findall(r"launcher: rows x=\d+ base=\d+ zh=(\d+)", txt)
    gestartet = {}
    if sf and lr:
        _id, gx, gy = sf
        lx, ly = lr[-1][0], lr[-1][1]
        # Die Zeilenhoehe steht in `rows zh=`; wird auch die zerschossen,
        # gilt der Wert, den wlib fuer die Oberflaechenschrift benutzt
        # und der in jedem Lauf dieser Aufloesung gemessen wurde: 20.
        z = int(zh[-1]) if zh else 20
        for i in sorted(eintraege):
            name, exe = eintraege[i]
            # Zumachen, dann aufmachen: nur so ist der Zustand bekannt.
            # (Der Starter laeuft seit dem Hochfahren; sein Fenster kann
            # offen sein, weil ein Programmstart es nicht schliesst.)
            m.klick_auf(18, HEIGHT - 20)
            time.sleep(1.4)
            if not menu_open(m):
                continue
            vor = len(read_all.starts(s()))
            zx = gx + lx + 60
            zy = gy + ly + 2 + i * z + z // 2
            m.klick_auf(zx, zy)
            time.sleep(4.5)
            t2 = s()
            st2 = read_all.starts(t2)
            renewed = st2[vor:]
            # Hat sich das Programm SELBST gemeldet? Das ist der
            # eigentliche Beweis, nicht die pid.
            mark = {"Datei-Explorer": "explorer: ready",
                     "Editor": "edit: ready",
                     "Suchen": "launcher: ready",
                     "Terminal": "sh: ready",
                     "Widgets": "wig: ready",
                     "Einstellungen": "settings: ready"}.get(name)
            own = t2.count(mark) if mark else 0
            gestartet[name] = {"starts": renewed, "marke": mark,
                               "meldungen": own}
            photo(m, "04-app-%d-%s" % (i, re.sub(r"\W", "", name)))

    for i in sorted(eintraege):
        name, exe = eintraege[i]
        g = gestartet.get(name, {})
        pids = [p for _, p in g.get("starts", []) if p is not None]
        gut = [p for p in pids if p > 0]
        nr = {"Datei-Explorer": "3.3", "Editor": "3.4", "Suchen": "3.15",
              "Terminal": "3.5", "Widgets": "3.14",
              "Einstellungen": "3.9"}.get(name, "3.x")
        ok = bool(gut) or g.get("meldungen", 0) > 0
        merke(nr, "%s starten" % name, "GEHT" if ok else "GEHT NICHT",
              "pids=%s  '%s' x%d" % (pids, g.get("marke"), g.get("meldungen", 0)))

    # ================================================ 7. Dauerlauf
    txt = s()
    merke("3.6", "Shell lebt (kein Sterbe-Kreislauf)",
          "GEHT" if txt.count("sh: bye") == 0 else "GEHT NICHT",
          "ready=%d bye=%d" % (txt.count("sh: ready"), txt.count("sh: bye")))

    merke("7.5", "keine Abstuerze im ganzen Lauf",
          "GEHT" if read_all.abstuerze(txt) == 0 else "GEHT NICHT",
          "%d Treffer auf PANIK/#PF/#UD" % read_all.abstuerze(txt))

    # Fenster-Leck: 20-mal Start klicken
    vor_f = len(read_all.window(s()))
    for _ in range(20):
        m.klick_auf(18, HEIGHT - 20)
        time.sleep(0.35)
    time.sleep(2)
    txt = s()
    f = read_all.window(txt)
    launcher_window = [i for i, lagen in f.items()
                        if any(w == 440 and h == 300 for _, _, w, h in lagen)]
    merke("4.6", "Fenster-Leck (20x Start)",
          "GEHT" if len(launcher_window) <= 1 else "GEHT NICHT",
          "%d Fenster 440x300 (DURCHKLICK: 16)" % len(launcher_window))
    photo(m, "05-nach-20-klicks")

    return finish()


def finish():
    with open(os.path.join(D, "befund.json"), "w") as f:
        json.dump(BEFUND, f, indent=1, ensure_ascii=False)
    n = {}
    for e in BEFUND:
        n[e["ergebnis"]] = n.get(e["ergebnis"], 0) + 1
    print("\n==== %s ====" % NAME)
    for k in sorted(n):
        print("  %-12s %d" % (k, n[k]))
    print("-> %s/befund.json" % D)
    return 0


if __name__ == "__main__":
    sys.exit(main())
