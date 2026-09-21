#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/look/umlaut.py -- ein Umlaut auf dem Schirm, Bildpunkt fuer Bildpunkt.

Teil A dieser Runde hat EINE deutsche Zeichenkette nachgerastert
("Ausführen", 438 Tintenpunkte, 0 falsch) und damit bewiesen, dass der
Weg Katalog -> UTF-8-Dekodierer -> cmap -> Rasterer funktioniert. Der
dritte Nachtrag braucht mehr: FUENF VERSCHIEDENE Zeichen, darunter ein
grosser Umlaut und das Eszett, aus vier verschiedenen Bedienelementen.

Der Grund ist nicht Gruendlichkeit um ihrer selbst willen. `ä` und `ü`
stehen im Katalog, `ß` und `Ö` kommen dort seltener vor, und ein
Zeichensatz, der bei 339 Zeichen geschnitten wurde, kann genau an so
einer Stelle eine Luecke haben, die bei "Ausführen" nie auffaellt.

WAS DIESES PROGRAMM VON HAND ABNIMMT. Die gemeldete Lage eines Textes
ist FENSTERBEZOGEN (`wlib: text ... x= base=`), das Bild ist es nicht.
Dazwischen liegen zwei Zahlen: der Fensterrahmen und die Titelleiste.
Beide werden hier NICHT geraten, sondern aus dem Mitschnitt geholt --
`wm: win ... x= y=` nennt die AEUSSERE Lage, und die Innenkante liegt
zwei Bildpunkte rechts und 22 darunter davon. Dieselben zwei Zahlen
benutzt Teil A, und dieselben nennt tools/desktop/run.sh.

  umlaut.py <serial> <ppm> <fenstertitel> <text> [toleranz] [--kette]

RUNDE UMLAUT2: `--kette` misst mit `checkshot tkette` statt `ttext`.
Beide vergleichen jeden Tintenpunkt gegen dieselbe Rasterung; `tkette`
baut die Zeile aber ERST Buchstabe fuer Buchstabe auf, bevor es
vergleicht, und erwartet damit das Richtige, wo zwei Umrisse einander
ueberlappen. Bei "Akzentfarbe unverändert übernommen" sind das 8 von
1567 Punkten -- `ttext` nennt sie falsch, `tkette` nicht, und das Bild
ist beide Male dasselbe und richtig. Die Messung wird dadurch strenger
und nicht weicher: `tkette` prueft zusaetzlich die Reihenfolge des
Mischens (siehe tools/gfx/checkshot.py).

Eine Zeile, rc=0 wenn kein Bildpunkt abweicht.
"""
import os
import re
import subprocess
import sys

BORDER = 2
TITLE = 22

WIN = re.compile(
    rb"wm: win nr=\d+ id=\d+ z=\d+ layer=\d+ hidden=(\d+) deco=(\d+) "
    rb"x=(\d+) y=(\d+) w=(\d+) h=(\d+).*?t=\[([^\]]*)\]")

# RUNDE MERGE-2: DIE GANZE TAFEL, MIT z UND LAGE -- fuer die Frage, was
# UEBER dem gemessenen Fenster liegt. Siehe `frei_bis`.
WINZ = re.compile(
    rb"wm: win nr=\d+ id=\d+ z=(\d+) layer=(\d+) hidden=(\d+) deco=(\d+) "
    rb"x=(\d+) y=(\d+) w=(\d+) h=(\d+).*?t=\[([^\]]*)\]")


def frei_bis(roh, titel, y0, y1, x0):
    """Bis zu welchem x die Zeile y0..y1 rechts von x0 UNVERDECKT ist.

    WAS VERDECKT IST, KANN NICHT GEMESSEN WERDEN -- und darf nicht als
    falsch gerastertes Zeichen gezaehlt werden. `themetest` laesst zum
    Bild absichtlich einen Dialog offen ("EIN DIALOG BLEIBT OFFEN",
    kernel/user/themetest.fi); der liegt bei 230,258 und schneidet die
    letzten fuenf Zeichen von `Übernehmen` ab. Der Rasterer meldete
    dafuer "333 von 526 Tintenpunkten falsch" -- und die falschen sind
    genau die, die auf dem Bild gar nicht stehen.

    Gemessen wird deshalb bis zur linken Kante des naechsten Fensters,
    das WEITER OBEN liegt und diese Bildzeilen schneidet. Das ist
    strenger als es klingt: die sichtbaren Zeichen muessen weiterhin
    Bildpunkt fuer Bildpunkt stimmen, und ist gar nichts sichtbar,
    faellt die Zusage.
    """
    eigen = None
    fenster = []
    for m in WINZ.finditer(roh):
        e = dict(z=int(m.group(1)), hidden=m.group(3) != b"0",
                 deco=m.group(4) == b"1", x=int(m.group(5)),
                 y=int(m.group(6)), w=int(m.group(7)), h=int(m.group(8)),
                 t=m.group(9).decode("utf-8", "replace"))
        fenster.append(e)
        if e["t"] == titel and not e["hidden"]:
            eigen = e
    if eigen is None:
        return None
    grenze = None
    for e in fenster:
        if e["hidden"] or e["z"] <= eigen["z"] or e is eigen:
            continue
        # der AEUSSERE Kasten, Rahmen und Titelleiste eingeschlossen
        ex0 = e["x"] - (BORDER if e["deco"] else 0)
        ey0 = e["y"] - (TITLE if e["deco"] else 0)
        ex1 = e["x"] + e["w"] + (BORDER if e["deco"] else 0)
        ey1 = e["y"] + e["h"] + (BORDER if e["deco"] else 0)
        if ey1 <= y0 or ey0 >= y1:
            continue
        if ex1 <= x0:
            continue
        if grenze is None or ex0 < grenze:
            grenze = ex0
    return grenze


def fenster(roh, titel):
    """Die AEUSSERE Lage des Fensters mit diesem Titel.

    HIER wird NICHT am Foto abgeschnitten, und das ist kein Versehen:
    der Fensterserver schreibt seine Tafel (`wm: win nr=...`) ERST NACH
    `wm: hold`, also nach der Aufnahme. Sie beschreibt trotzdem genau
    den Augenblick der Aufnahme -- danach bewegt in diesem Aufbau
    niemand mehr ein Fenster, denn `wmhold` ist das Ende der
    Ereignisschleife. Schneidet man hier mit ab, findet man gar kein
    Fenster mehr.
    """
    treffer = None
    for m in WIN.finditer(roh):
        if m.group(7).decode("utf-8", "replace") == titel:
            treffer = m
    if treffer is None:
        return None
    if treffer.group(1) != b"0":
        return None          # verborgen -- da steht nichts auf dem Bild
    return (int(treffer.group(3)), int(treffer.group(4)),
            int(treffer.group(5)), int(treffer.group(6)),
            treffer.group(2) == b"1")


def bis_zum_foto(roh):
    """Der Mitschnitt BIS ZU DEM AUGENBLICK, in dem das Bild entstand.

    tools/look/shot.sh wartet auf `wm: hold` und macht dann den
    Bildschirmabzug. Was danach auf den Draht geht, steht NICHT auf dem
    Bild -- und es ist nicht wenig: `themetest` schaltet unter `themegui`
    weiter zwischen hell und dunkel um und malt sich dabei immer wieder
    neu. Von 58 gemeldeten "Übernehmen" dieses Laufs liegen 30 hinter dem
    Foto, und die letzte davon ist dunkel (fg=16317180 bg=1976635),
    waehrend das Bild die helle zeigt (fg=988970 bg=16777215).

    Nimmt man einfach die LETZTE Meldung, vergleicht man ein helles Bild
    gegen dunkle Erwartungsfarben und bekommt "526 von 526 Tintenpunkten
    falsch" -- eine Zahl, die wie ein kaputter Zeichensatz aussieht und
    keiner ist. Eine Messung muss den Zustand zum Zeitpunkt der Aufnahme
    benutzen, nicht den letzten, den es je gab.
    """
    i = roh.find(b"wm: hold")
    return roh if i < 0 else roh[:i]


def gemalt(roh, text):
    """Die zuletzt VOR dem Foto gemeldete Lage dieses Textes.

    Auf den seriellen Draht schreiben fuenf Prozesse gleichzeitig, also
    wird NICHT bis zum Zeilenende gelesen, sondern der ERWARTETE Text
    als Anker benutzt -- genauso, wie Teil A es tut. Eine Zeile, die ein
    anderes Programm zerschnitten hat, traegt ihren Anfang trotzdem.
    """
    roh = bis_zum_foto(roh)
    # RUNDE SOFTUI: zwischen `bg=` und `t=` darf stehen, was spaetere
    # Runden dort anfuegen (`tw=` aus THEMESTORE, `ax=`/`ay=` aus
    # SOFTUI). Die Zusage haengt am ANKER -- dem erwarteten Text -- und
    # nicht an der Reihenfolge der Felder davor. Vorher hat sie an der
    # Reihenfolge gehangen und ist beim naechsten Feld umgefallen.
    pat = (rb"kind=(\d+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)(?: [a-z]+=\d+)* t="
           + re.escape(text.encode("utf-8")))
    treffer = list(re.finditer(pat, roh))
    if not treffer:
        return None
    m = treffer[-1]
    return tuple(int(m.group(i)) for i in range(1, 6))


def rgb(v):
    return [str((v >> 16) & 255), str((v >> 8) & 255), str(v & 255)]


# ================================================ RUNDE GLAS (nachtrag)
# DERSELBE PRUEFER FUER EINE ZEILE IM TERMINALFENSTER.
#
# Der Anlass: auf jeder Aufnahme der Runde GLAS stand
# "KEIN EINZIGES GERT!" -- `wm.term_putc` hat die zwei Oktette des Ä
# verschluckt. Kein Werkzeug dieses Baums konnte das melden: dieses
# hier misst nur, was Ring 3 ueber `wlib: text` meldet, und das
# Terminal malt durch den KERN, Zelle fuer Zelle, in der
# Festbreitenschrift.
#
# `--gitter` misst genau diesen Fall. Die Lage kommt NICHT aus einer
# Rechnung dieses Programms, sondern aus der Zeile, die der Kern selbst
# druckt (`wm: termgitter win= x= y= cellw= cellh= asc= px=`): Spalte c
# beginnt bei x + c * cellw, die Grundlinie der Zeile r liegt bei
# y + r * cellh + asc. Gerechnet wird dann von `checkshot.py tgrid`,
# demselben zweiten Rasterer, den tools/wm/run.sh seit Runde K10
# benutzt.
GITTER = re.compile(
    rb"wm: termgitter win=(\d+) x=(\d+) y=(\d+) cellw=(\d+) cellh=(\d+)"
    rb" asc=(\d+) px=(\d+)")


def gitter(roh):
    treffer = None
    for m in GITTER.finditer(roh):
        treffer = m
    if treffer is None:
        return None
    return tuple(int(treffer.group(i)) for i in range(2, 8))


def grundfarben(ppm, x0, y0, x1, y1):
    """Grund und Schrift einer Terminalzeile, AUS DEM BILD gelesen.

    Die Farben eines Terminalfensters kommen aus dem Farbschema und
    stehen auf keiner Leitung -- anders als bei `wlib: text`, wo das
    Programm sein `fg=`/`bg=` selbst meldet. Sie sind aber im Bild
    eindeutig: der Grund ist die haeufigste Farbe der Zeile, die
    Schrift die, die am weitesten von ihm entfernt ist. Zwischentoene
    liegen zwischen beiden und koennen keines von beiden sein.
    """
    b = open(ppm, "rb").read()
    if not b.startswith(b"P6"):
        return None
    felder = []
    at = 2
    while len(felder) < 3:
        while at < len(b) and b[at:at + 1].isspace():
            at += 1
        if b[at:at + 1] == b"#":
            while b[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        a = at
        while at < len(b) and not b[at:at + 1].isspace():
            at += 1
        felder.append(int(b[a:at]))
    at += 1
    w, h = felder[0], felder[1]
    zaehl = {}
    for y in range(max(y0, 0), min(y1, h)):
        for x in range(max(x0, 0), min(x1, w)):
            o = at + (y * w + x) * 3
            p = (b[o], b[o + 1], b[o + 2])
            zaehl[p] = zaehl.get(p, 0) + 1
    if not zaehl:
        return None
    hg = max(zaehl, key=lambda k: zaehl[k])
    vg = max(zaehl, key=lambda k: sum(abs(k[i] - hg[i]) for i in range(3)))
    return vg, hg


def term_pruefen(serial, ppm, text, zeile, spalte, tol, zeichen):
    roh = open(serial, "rb").read()
    g = gitter(roh)
    if g is None:
        print("umlaut: [%s] keine `wm: termgitter`-Zeile im Mitschnitt"
              % zeichen)
        return 1
    x0, y0, cw, chh, asc, px = g
    ax = x0 + spalte * cw
    ay = y0 + zeile * chh + asc
    farben = grundfarben(ppm, ax, ay - asc, ax + len(text) * cw, ay + 4)
    if farben is None:
        print("umlaut: [%s] die Zeile %d ist im Bild nicht zu finden"
              % (zeichen, zeile))
        return 1
    vg, hg = farben
    r = subprocess.run(
        ["python3", "tools/gfx/checkshot.py", "tgrid", ppm,
         "assets/osum-mono.ttf", str(px), str(x0), str(y0),
         str(cw), str(chh), str(zeile), str(spalte)]
        + [str(v) for v in vg] + [str(v) for v in hg] + [text, tol],
        capture_output=True, text=True)
    kopf = r.stdout.strip().split("\n")[0] if r.stdout else r.stderr.strip()
    print("umlaut: [%s] termgitter zeile=%d spalte=%d x=%d y=%d "
          "fg=%02x%02x%02x bg=%02x%02x%02x tol=%s -- %s"
          % (zeichen, zeile, spalte, ax, ay, vg[0], vg[1], vg[2],
             hg[0], hg[1], hg[2], tol, kopf))
    for z in r.stdout.strip().split("\n")[1:]:
        print("        " + z)
    return r.returncode


def main(argv):
    if len(argv) < 4:
        print("umlaut: <serial> <ppm> <fenstertitel> <text> [toleranz]")
        print("        <serial> <ppm> --gitter=<zeile>,<spalte> <text> "
              "[toleranz]")
        return 2
    kette = "--kette" in argv
    argv = [x for x in argv if x != "--kette"]
    # `--gitter=zeile,spalte` steht an der Stelle des Fenstertitels:
    # eine Terminalzeile hat keinen, sie hat ein Raster.
    if argv[2].startswith("--gitter="):
        text = argv[3]
        zeichen = "".join(sorted(set(c for c in text if c in "äöüÄÖÜß")))
        if not zeichen:
            print("umlaut: %r traegt gar keinen Umlaut" % text)
            return 2
        zeile, spalte = (int(v) for v in argv[2].split("=", 1)[1].split(","))
        return term_pruefen(argv[0], argv[1], text, zeile, spalte,
                            argv[4] if len(argv) > 4 else "0", zeichen)
    serial, ppm, titel, text = argv[0], argv[1], argv[2], argv[3]
    tol = argv[4] if len(argv) > 4 else "0"
    zeichen = "".join(sorted(set(c for c in text if c in "äöüÄÖÜß")))
    if not zeichen:
        print("umlaut: %r traegt gar keinen Umlaut" % text)
        return 2
    roh = open(serial, "rb").read()

    w = fenster(roh, titel)
    if w is None:
        print("umlaut: [%s] kein sichtbares Fenster '%s'" % (zeichen, titel))
        return 1
    wx, wy, ww, wh, deco = w
    t = gemalt(roh, text)
    if t is None:
        print("umlaut: [%s] '%s' wurde nicht gemalt" % (zeichen, text[:40]))
        return 1
    kind, tx, tb, fg, bg = t

    ix = wx + (BORDER if deco else 0)
    iy = wy + (TITLE if deco else 0)
    ax, ay = ix + tx, iy + tb

    # EIN TEXT, DER UEBER SEIN FENSTER HINAUSRAGT, IST NICHT MESSBAR.
    # Nicht weil der Rasterer irrt, sondern weil dort das NAECHSTE
    # Fenster steht und dessen Bildpunkte im Bild stehen.
    #
    # Das ist kein gedachter Fall: im Aufbau mit vier Fenstern ist der
    # Dateimanager 396 breit, seine Spalte "Größe" faengt bei x=368 an
    # und ist 44 breit. Geprueft man stumpf, meldet der Rasterer 72
    # falsche Bildpunkte und man sucht den Fehler in der Schrift. Der
    # Anfang allein reicht als Pruefung nicht -- es ist das ENDE, das
    # hinausragt.
    sys.path.insert(0, os.path.join("tools", "ttf"))
    import raster
    schrift = raster.Schrift("assets/osum-sans.ttf", 15)
    stellen = list(schrift.stellen(text))
    breite = ((stellen[-1][1] >> 6) if stellen else 0) + 12
    if tx + breite > ww:
        print("umlaut: [%s] '%s' laeuft von x=%d bis %d aus einem Fenster "
              "heraus, das %d breit ist -- nicht messbar"
              % (zeichen, text[:30], tx, tx + breite, ww))
        return 1

    # NUR DER SICHTBARE TEIL. `frei_bis` sagt, wo das naechste Fenster
    # anfaengt; alles ab dort steht nicht auf dem Bild.
    hoch = 20
    grenze = frei_bis(roh, titel, ay - hoch, ay + 6, ax)
    if grenze is not None:
        sicht = text
        for k, (c, x26) in enumerate(stellen):
            if ax + (x26 >> 6) + 12 > grenze:
                sicht = text[:k]
                break
        if not sicht.strip() or not any(c in "äöüÄÖÜß" for c in sicht):
            print("umlaut: [%s] '%s' ist ab x=%d verdeckt -- vom Umlaut "
                  "ist nichts zu sehen" % (zeichen, text[:30], grenze))
            return 1
        if sicht != text:
            print("        verdeckt ab x=%d -- gemessen wird '%s'"
                  % (grenze, sicht))
        text = sicht

    r = subprocess.run(
        ["python3", "tools/gfx/checkshot.py",
         "tkette" if kette else "ttext", ppm,
         "assets/osum-sans.ttf", "15", str(ax), str(ay)]
        + rgb(fg) + rgb(bg) + [text, tol],
        capture_output=True, text=True)
    kopf = r.stdout.strip().split("\n")[0] if r.stdout else r.stderr.strip()
    print("umlaut: [%s] kind=%d %s x=%d y=%d tol=%s -- %s"
          % (zeichen, kind, titel, ax, ay, tol, kopf))
    for z in r.stdout.strip().split("\n")[1:]:
        print("        " + z)
    return r.returncode


if __name__ == "__main__":
    os.chdir(os.environ.get("OSUM_ROOT", "."))
    sys.exit(main(sys.argv[1:]))
