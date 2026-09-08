#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/vsync/zerreiss.py -- DIE ZERREISSPROBE.

    zerreiss.py <ppm> [<ppm> ...]

WARUM ES DIESES PROGRAMM GEBEN MUSS.

Reissen (tearing) ist das, was man sieht, wenn der Bildschirm ein Bild
ausliest, waehrend es noch geschrieben wird: oben steht der alte
Zustand, unten schon der neue.  Unter QEMU ist das NICHT zu sehen.
`screendump` liest die Bildflaeche als Ganzes, und zwar dann, wenn
gerade niemand schreibt -- ein halb uebertragenes Bild sieht darin aus
wie ein vollstaendiges.  Ein Testlaeufer, der einfach Fotos vergleicht,
misst hier NICHTS und wuerde jede Fassung durchwinken.

Also wird die Frage umgestellt.  Der Fensterserver zaehlt seine Bilder
und faerbt im Signaturbetrieb (`wmsig`) einen Streifen am OBEREN und
einen am UNTEREN Rand JEDES Fensters mit einer Farbe, die aus der
Bildnummer faellt (`wm.sig_colour`, acht Volltoene).  Beide Streifen
entstehen im SELBEN Zeichenlauf und tragen deshalb dieselbe Farbe.

Damit ist Reissen eine Eigenschaft, die ein Programm PRUEFEN kann:

    zwei verschiedene Signaturfarben in EINEM Fenster
    = das Foto hat ein halb uebertragenes Bild erwischt
    = Reissen.

Und die Umkehrung ist die Zusage dieser Runde: steht die Bildgrenze
(`vsync`), MUSS jedes Foto in jedem Fenster GENAU EINE Farbe zeigen.
Die Gegenprobe `nopresent` muss gemischte Bilder finden -- eine Zusage,
die sich nicht brechen laesst, misst nichts.

WIE EIN FENSTER GEFUNDEN WIRD.  Nicht ueber Koordinaten aus dem
Mitschnitt -- die waeren eine zweite Wahrheit ueber denselben
Bildschirm.  Gesucht werden ZEILEN, die ueber viele Bildpunkte hinweg
eine der acht Signaturfarben tragen; das sind die Streifen.  Zwei
Streifen mit demselben linken und rechten Rand gehoeren zum selben
Fenster.  Tragen sie verschiedene Farben, ist es zerrissen.

Ausgabe (eine Zeile je Datei, dann eine Summenzeile):

    <datei> fenster=<n> zerrissen=<n> farben=<liste>
    SUMME bilder=<n> fenster=<n> zerrissen=<n>

Rueckgabe 0, wenn NICHTS zerrissen war, sonst 1.
"""
import sys

# Die acht Signaturfarben aus `wm.sig_colour`, als (r, g, b).
SIG = {
    (0xFF, 0x00, 0x00): 0,
    (0x00, 0xFF, 0x00): 1,
    (0x00, 0x00, 0xFF): 2,
    (0xFF, 0xFF, 0x00): 3,
    (0xFF, 0x00, 0xFF): 4,
    (0x00, 0xFF, 0xFF): 5,
    (0xFF, 0x80, 0x00): 6,
    (0xFF, 0xFF, 0xFF): 7,
}
# Ein Streifen zaehlt erst ab dieser Breite. Schmaler ist ein Zufall aus
# dem Fensterinhalt -- ein Programm darf rot malen.
MIN_BREIT = 40


def ppm_lesen(pfad):
    """Ein binaeres PPM (P6) als (w, h, bytes) lesen."""
    with open(pfad, "rb") as f:
        roh = f.read()
    if not roh.startswith(b"P6"):
        raise ValueError("kein P6-PPM: %s" % pfad)
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(roh) and roh[i:i + 1].isspace():
            i += 1
        if roh[i:i + 1] == b"#":
            while i < len(roh) and roh[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(roh) and not roh[j:j + 1].isspace():
            j += 1
        felder.append(int(roh[i:j]))
        i = j
    i += 1  # das eine Trennzeichen nach <max>
    w, h, _mx = felder
    return w, h, roh[i:i + w * h * 3]


def streifen_der_zeile(w, zeile):
    """Alle Laeufe einer Signaturfarbe in einer Bildzeile.

    Gibt [(x0, x1, farbnummer)] zurueck. Nur Laeufe ab MIN_BREIT.
    """
    aus = []
    x = 0
    while x < w:
        px = (zeile[x * 3], zeile[x * 3 + 1], zeile[x * 3 + 2])
        k = SIG.get(px)
        if k is None:
            x += 1
            continue
        x0 = x
        while x < w:
            q = (zeile[x * 3], zeile[x * 3 + 1], zeile[x * 3 + 2])
            if SIG.get(q) != k:
                break
            x += 1
        if x - x0 >= MIN_BREIT:
            aus.append((x0, x, k))
    return aus


def bild_pruefen(pfad):
    """(fenster, zerrissen, farben) fuer ein Foto."""
    w, h, dat = ppm_lesen(pfad)
    nach_spanne = {}
    for y in range(h):
        zeile = dat[y * w * 3:(y + 1) * w * 3]
        if len(zeile) < w * 3:
            break
        for (x0, x1, k) in streifen_der_zeile(w, zeile):
            nach_spanne.setdefault((x0, x1), []).append((y, k))
    fenster = 0
    zerrissen = 0
    farben = set()
    for (_spanne, treffer) in sorted(nach_spanne.items()):
        ys = [t[0] for t in treffer]
        ks = set(t[1] for t in treffer)
        if len(ys) < 2:
            continue
        # Nur wenn es wirklich ZWEI getrennte Baender sind (oben und
        # unten am Fenster) -- sonst ist es eine einzelne farbige
        # Flaeche und kein Fensterpaar.
        luecke = False
        for a, b in zip(ys, ys[1:]):
            if b - a > 8:
                luecke = True
                break
        if not luecke:
            continue
        fenster += 1
        farben |= ks
        if len(ks) > 1:
            zerrissen += 1
    return fenster, zerrissen, sorted(farben)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    g_f = 0
    g_z = 0
    n = 0
    for pfad in sys.argv[1:]:
        try:
            f, z, farben = bild_pruefen(pfad)
        except (OSError, ValueError) as e:
            print("%s FEHLER %s" % (pfad, e))
            return 2
        n += 1
        g_f += f
        g_z += z
        print("%s fenster=%d zerrissen=%d farben=%s"
              % (pfad.split("/")[-1], f, z,
                 ",".join(str(k) for k in farben) or "-"))
    print("SUMME bilder=%d fenster=%d zerrissen=%d" % (n, g_f, g_z))
    return 1 if g_z else 0


if __name__ == "__main__":
    sys.exit(main())
