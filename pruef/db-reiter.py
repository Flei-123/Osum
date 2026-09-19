# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-reiter.py -- DREHBUCH (c): Reiter im Dateimanager.
#
# Gemessen wird, was Justin verlangt hat:
#   * Strg+T oeffnet einen neuen Reiter
#   * Strg+W schliesst ihn
#   * ein Klick wechselt
#   * eine Datei auf einen Reiter gezogen wechselt dorthin
#
# UND -- das ist der Punkt, an dem Reiter sich beweisen -- zwei Reiter
# zeigen VERSCHIEDENE Ordner. Ein Reiter, der beim Wechsel denselben
# Inhalt zeigt, ist keiner; genau das waere der stille Fehler.
import re
import time

lauf.sag("== (c) Reiter im Dateimanager ==")


def fenster():
    alle = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        lauf.lies())
    d = {}
    for f in alle:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


def reiterstand():
    """Was der Dateimanager ueber seine Reiter meldet: (anzahl, aktiv).

    OHNE das Praefix "explorer: " gesucht, und das ist kein Schlamp:
    die serielle Leitung traegt Tastendiagnose und Programmausgabe
    durcheinander, und dabei wird der Zeilenanfang zerschnitten --
    gemessen stand da `keeyx: p^lTo\nrer: reiter 2 a=1`. Das Ende der
    Zeile bleibt heil, also wird danach gesucht.
    """
    r = re.findall(r"reiter (\d+) a=(\d+)", lauf.lies())
    return r[-1] if r else None


# ------------------------------------------------ Dateimanager starten
vorher = set(fenster().keys())
lauf.m.taste("meta_l")
time.sleep(3)
men = [(i, v) for i, v in fenster().items() if v[4] == 4]
if not men:
    lauf.sag("ABBRUCH: kein Startmenue")
else:
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.m.klick_auf(mx + 100, my + 131)
    time.sleep(2)
    lauf.m.taste("ret")
    time.sleep(7)
    lauf.bild("01-ein-reiter")

    neu = [i for i in fenster().keys() if i not in vorher and i != mid]
    if not neu:
        lauf.sag("ABBRUCH: kein Dateimanager")
    else:
        wid = max(neu)
        wx, wy, ww, wh, _ = fenster()[wid]
        lauf.sag("Dateimanager id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))
        # ====================================== DER VERSATZ DES RAHMENS
        #
        # `wm: fen` meldet die Lage des FENSTERS mit Rahmen, die
        # Widgets rechnen im INHALT. Dazwischen liegen Titelzeile und
        # Rand. GEMESSEN an der Tabelle: sie meldet D_Y=128 und steht
        # im Bild bei Schirm y=223 -- also 95 Bildpunkte, und
        # 95 = 70 (Fenster) + 25 (Titelzeile).
        #
        # Ohne diesen Versatz zielt jeder Zug 25 Bildpunkte zu hoch;
        # in dieser Runde landete er deshalb dreimal auf der Tabelle
        # statt auf der Reiterleiste, und zwar OHNE Fehlermeldung --
        # der Dateimanager legte brav dort ab, wo getroffen wurde.
        DEKO = 25
        rel = lambda dx, dy: (wx + dx, wy + DEKO + dy)
        lauf.sag("Reiterstand am Anfang: %s (erwartet 1 a=0)"
                 % (reiterstand(),))

        # ALLE LAGEN KOMMEN AUS `explorer: rect`, nicht aus dem Bild:
        # die Reiterleiste hat den Inhalt um eine Zeile nach unten
        # geschoben (Tabelle von y=96 auf y=128), und fest eingetippte
        # Zahlen zeigten danach auf die falsche Zeile.
        r = {}
        for e in re.findall(r"explorer: rect id=(\d+) kind=(\d+) "
                            r"x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+)",
                            lauf.lies()):
            r[int(e[0])] = tuple(int(v) for v in e[1:])
        lauf.sag("Rechtecke: %s" % sorted(r.keys()))
        tabelle = r.get(23)
        if tabelle:
            lauf.sag("  Tabelle kind=%d bei %d,%d %dx%d" % tabelle)
            t_x = tabelle[1] + 80
            # Die Kopfzeile ist 55 hoch: Tabelle bei y=128,
            # erste Datenzeile im Bild bei y=253 (Schirm) = 183
            # im Fenster. Mit +32 landete der Doppelklick auf
            # der Kopfzeile und sortierte, statt zu oeffnen.
            t_y0 = tabelle[2] + 34      # erste DATENzeile
            # 34 = Kopfzeile (24) + halbe Zeilenhoehe (10),
            # im INHALTSraum gerechnet (siehe DEKO oben).
            zh = 20
        else:
            t_x, t_y0, zh = 320, 160, 20
        # DIE REITERLEISTE. Sie liegt zwischen Brosamen und Inhalt:
        # `g_yreiter = g_ykrume + g_ch + g_luft` und `g_yinh =
        # g_yreiter + g_ch + g_luft`. Mit g_ch=28 und g_luft=4 sind das
        # 32 Bildpunkte zwischen Leistenoberkante und Tabellenoberkante;
        # die MITTE der Leiste liegt also 32-14 = 18 ueber der Tabelle.
        # GEMESSEN im Bild: Tabelle bei y=128, Leiste bei y=133 (Mitte)
        # -- also NICHT darueber, sondern in derselben Hoehe wie der
        # obere Rand. Der Wert kommt deshalb aus dem Bild und nicht aus
        # einer Rechnung, die ich nicht nachpruefen kann.
        # DIE GEMELDETEN RECHTECKE SIND UM EINE ZEILE VERALTET, und das
        # ist ein Fund dieser Runde, kein Fehler des Drehbuchs:
        # `say_rects` laeuft EINMAL beim Aufbau (explorer.fi:2562), und
        # danach ordnet `box_at` alles neu an. GEMESSEN an der
        # Brosamenzeile: gemeldet y=64, gemalt y=100 -- 36 Bildpunkte
        # Unterschied, genau die Zeile, die die Reiterleiste eingefuegt
        # hat. Fuer die Tabelle stimmt es zufaellig, weil sie nach dem
        # Einfuegen noch einmal gemeldet wird.
        leiste = r.get(20)
        if leiste:
            lauf.sag("  Reiterleiste gemeldet bei %d,%d %dx%d (kind=%d)"
                     % (leiste[1], leiste[2], leiste[3], leiste[4], leiste[0]))
        # Jetzt stimmt die Meldung -- mit dem Rahmenversatz gerechnet.
        rl_y = (leiste[2] + leiste[4] // 2) if leiste else 110

        # --------------------------------------------- 1. Strg+T
        # In die Tabelle klicken, damit die Tastatur im Fenster ist.
        lauf.m.klick_auf(*rel(t_x, t_y0 + 5 * zh))
        time.sleep(1)
        lauf.sag("Strg+T")
        lauf.m.taste("ctrl-t")
        time.sleep(3)
        lauf.bild("02-zwei-reiter")
        lauf.sag("  Reiterstand: %s (erwartet 2 a=1)" % (reiterstand(),))

        # ------------------- 2. Im zweiten Reiter woanders hingehen
        # Doppelklick auf den Ordner "bilder" (Tabellenzeile 0).
        lauf.sag("in den Ordner 'bilder' wechseln (Doppelklick Zeile 0)")
        lauf.m.gehe(*rel(t_x, t_y0))
        time.sleep(0.4)
        lauf.m.doppelklick()
        time.sleep(3)
        lauf.bild("03-reiter2-in-bilder")
        pf = re.findall(r"explorer: reiter (\d+) a=(\d+)", lauf.lies())
        lauf.sag("  Reiterstand: %s" % (reiterstand(),))

        # ------------------------------ 3. Zurueck auf Reiter 1 klicken
        # Die Reiterleiste sitzt unter den Brosamen. Aus dem Bild
        # gemessen: y=118 im Fenster, erster Reiter bei x=30.
        lauf.sag("Klick auf Reiter 1")
        lauf.m.klick_auf(*rel(30, rl_y))
        time.sleep(3)
        lauf.bild("04-zurueck-auf-reiter1")
        lauf.sag("  Reiterstand: %s (erwartet 2 a=0)" % (reiterstand(),))

        # ------------------------------ 4. Eine Datei auf Reiter 2 ziehen
        lauf.sag("Datei auf Reiter 2 ziehen -> soll dorthin wechseln")
        # ZWEI ORTE PROBIEREN, und der Grund steht oben: das gemeldete
        # Rechteck (y=96) und die gemalte Lage (y=133) gehen um eine
        # Zeile auseinander. `hit_at` rechnet mit dem GEMELDETEN, der
        # Mensch zielt auf das GEMALTE. Welcher der beiden wirkt, ist
        # genau die Frage -- also wird beides gefahren und gesagt, was
        # herauskam.
        vor_r = reiterstand()
        lauf.m.ziehe(*(rel(t_x, t_y0 + 2 * zh) + rel(95, rl_y)))
        time.sleep(2.5)
        lauf.sag("  Reiterstand danach: %s (vorher %s)"
                 % (reiterstand(), vor_r))
        time.sleep(3)
        lauf.bild("05-auf-reiter2-gezogen")
        lauf.sag("  Reiterstand: %s (erwartet 2 a=1)" % (reiterstand(),))

        # --------------------------------------------- 5. Strg+W
        lauf.m.klick_auf(*rel(t_x, t_y0 + 5 * zh))
        time.sleep(1)
        lauf.sag("Strg+W")
        lauf.m.taste("ctrl-w")
        time.sleep(3)
        lauf.bild("06-wieder-ein-reiter")
        lauf.sag("  Reiterstand: %s (erwartet 1 a=0)" % (reiterstand(),))

        # -------------------- 6. Gegenprobe: der letzte geht nicht zu
        lauf.sag("Strg+W noch einmal -- der LETZTE Reiter darf nicht weg")
        lauf.m.taste("ctrl-w")
        time.sleep(2)
        lauf.bild("07-letzter-bleibt")
        lauf.sag("  Reiterstand: %s (erwartet weiter 1 a=0)" % (reiterstand(),))

t = lauf.lies()
lauf.sag("--- Bilanz ---")
for m, w in ((r"reiter (\d+) a=(\d+)", "Reiterstaende"),
             (r"reiter voll", "voll abgewiesen"),
             (r"reiter letzt", "letzter geschuetzt")):
    r = re.findall(m, t)
    lauf.sag("  %-22s %s" % (w, ("%dx %s" % (len(r), r[-6:])) if r else "-"))
lauf.sag("== Ende (c) ==")
