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

  umlaut.py <serial> <ppm> <fenstertitel> <text> [toleranz]

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


def fenster(roh, titel):
    """Die zuletzt gemeldete AEUSSERE Lage des Fensters mit diesem Titel."""
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


def gemalt(roh, text):
    """Die zuletzt gemeldete Lage dieses Textes, fensterbezogen.

    Auf den seriellen Draht schreiben fuenf Prozesse gleichzeitig, also
    wird NICHT bis zum Zeilenende gelesen, sondern der ERWARTETE Text
    als Anker benutzt -- genauso, wie Teil A es tut. Eine Zeile, die ein
    anderes Programm zerschnitten hat, traegt ihren Anfang trotzdem.
    """
    pat = (rb"kind=(\d+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+) t="
           + re.escape(text.encode("utf-8")))
    treffer = list(re.finditer(pat, roh))
    if not treffer:
        return None
    m = treffer[-1]
    return tuple(int(m.group(i)) for i in range(1, 6))


def rgb(v):
    return [str((v >> 16) & 255), str((v >> 8) & 255), str(v & 255)]


def main(argv):
    if len(argv) < 4:
        print("umlaut: <serial> <ppm> <fenstertitel> <text> [toleranz]")
        return 2
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

    r = subprocess.run(
        ["python3", "tools/gfx/checkshot.py", "ttext", ppm,
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
