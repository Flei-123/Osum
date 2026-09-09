#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/belege.py -- AUS EINEM ABNAHMELAUF EINEN BELEGSTAPEL.

    python3 tools/design/belege.py <laufverzeichnis> <belegverzeichnis>

Je Bild wird abgelegt:

  * das Bild als PNG (verlustfrei, ein Zehntel der PPM-Groesse)
  * eine Zeile in BEFUND.md: was zu sehen ist, und der gemessene
    BLAUSTICH (B-R, flaechengewichtet ueber die sechs haeufigsten
    Flaechenfarben)

WARUM JE BILD EINE BESCHREIBUNG UND NICHT NUR "ok": ein Beleg, der nur
sagt, dass ein Bild entstanden ist, belegt nichts. Der PROGRAMM-AUDIT
hat gezaehlt, dass zuletzt sechs von acht Bildern eines Laufs Oktett
fuer Oktett gleich waren -- alle sechs waren "ok". Deshalb steht hier
je Bild, WELCHE Fenster der Mitschnitt zu diesem Zeitpunkt gemeldet
hat, und ob das Bild sich vom vorherigen unterscheidet.
"""
import os, sys, glob, hashlib, collections, subprocess, re

HIER = os.path.dirname(os.path.abspath(__file__))


def read_ppm(p):
    d = open(p, "rb").read()
    parts, i = [], 0
    while len(parts) < 4:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while d[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        s = i
        while i < len(d) and not d[i:i + 1].isspace():
            i += 1
        parts.append(d[s:i])
    i += 1
    w, h = int(parts[1]), int(parts[2])
    return w, h, d[i:i + w * h * 3]


def blaustich(px, w, h):
    """B-R, gewichtet ueber die sechs haeufigsten Farben (die Flaechen).

    Nicht ueber das ganze Bild: Text und Symbole sind bunt und wuerden
    das Mittel verwaschen. Was hier gemessen wird, ist der Farbton der
    FLAECHEN -- und um den geht es, wenn jemand sagt "das Grau ist blau".
    """
    c = collections.Counter()
    for k in range(0, len(px), 3):
        c[(px[k], px[k + 1], px[k + 2])] += 1
    top = c.most_common(6)
    ws = sum((b - r) * n for (r, g, b), n in top)
    wt = sum(n for _, n in top)
    return (ws / wt if wt else 0.0), top


def anteil(px, farbe):
    n = sum(1 for k in range(0, len(px), 3)
            if (px[k], px[k + 1], px[k + 2]) == farbe)
    return 100.0 * n / (len(px) // 3)


def fenster_aus_serial(pfad):
    """Welche Programme haben sich in diesem Lauf bereit gemeldet."""
    if not os.path.exists(pfad):
        return []
    try:
        t = open(pfad, "rb").read().decode("utf-8", "replace")
    except OSError:
        return []
    return sorted(set(re.findall(r"^(\w+): ready", t, re.M)))


def main(lauf, beleg):
    os.makedirs(beleg, exist_ok=True)
    zeilen = []
    vorher = {}
    for d in sorted(glob.glob(os.path.join(lauf, "*/"))):
        tag = os.path.basename(d.rstrip("/"))
        ready = fenster_aus_serial(os.path.join(d, "serial.txt"))
        for ppm in sorted(glob.glob(os.path.join(d, "*.ppm"))):
            base = os.path.basename(ppm)[:-4]
            png = os.path.join(beleg, f"{tag}--{base}.png")
            subprocess.run([sys.executable,
                            os.path.join(HIER, "ppm2png.py"), ppm, png],
                           check=False)
            w, h, px = read_ppm(ppm)
            bs, top = blaustich(px, w, h)
            md5 = hashlib.md5(px).hexdigest()
            gleich = ""
            if md5 in vorher:
                gleich = f" **BYTE-GLEICH mit {vorher[md5]}**"
            else:
                vorher[md5] = f"{tag}/{base}"
            flaechen = "  ".join(f"`#{r:02x}{g:02x}{b:02x}` {100.0*n/(w*h):.0f}%"
                                 for (r, g, b), n in top[:3])
            zeilen.append(
                f"| `{tag}` | `{base}` | {w}×{h} | **{bs:+.1f}** | "
                f"{flaechen} | {', '.join(ready) or '—'}{gleich} |")
    kopf = ("# BEFUND — Abnahme MERGE-10\n\n"
            "Je Bild: die Auflösung, der gemessene **Blaustich B−R** "
            "(flächengewichtet über die sechs häufigsten Flächenfarben; "
            "0 = neutrales Grau, positiv = blaustichig), die drei größten "
            "Flächen und die Programme, die sich in diesem Lauf bereit "
            "gemeldet haben.\n\n"
            "Ein Bild, das mit einem früheren **byte-gleich** ist, wird als "
            "solches ausgewiesen — genau das war der Mangel, den der "
            "PROGRAMM-AUDIT gefunden hat (sechs von acht Bildern gleich, "
            "alle als „ok“ verbucht).\n\n"
            "| Lauf | Bild | Größe | B−R | größte Flächen | `ready` im Lauf |\n"
            "|---|---|---|---|---|---|\n")
    open(os.path.join(beleg, "BEFUND.md"), "w", encoding="utf-8").write(
        kopf + "\n".join(zeilen) + "\n")
    print(f"{len(zeilen)} Bilder, BEFUND.md geschrieben nach {beleg}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
