#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
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
    GRAU_TOL = 40
    c = collections.Counter()
    for k in range(0, len(px), 3):
        c[(px[k], px[k + 1], px[k + 2])] += 1
    grau = [(f, n) for f, n in c.most_common(40)
            if max(f) - min(f) <= GRAU_TOL]
    top = grau[:6] or c.most_common(6)
    ws = sum((b - r) * n for (r, g, b), n in top)
    wt = sum(n for _, n in top)
    return (ws / wt if wt else 0.0), top


def anteil(px, color_2):
    n = sum(1 for k in range(0, len(px), 3)
            if (px[k], px[k + 1], px[k + 2]) == color_2)
    return 100.0 * n / (len(px) // 3)


def window_aus_serial(path_2):
    if not os.path.exists(path_2):
        return []
    try:
        t = open(path_2, "rb").read().decode("utf-8", "replace")
    except OSError:
        return []
    return sorted(set(re.findall(r"^(\w+): ready", t, re.M)))


def main(run_2, beleg):
    os.makedirs(beleg, exist_ok=True)
    zeilen = []
    vorher = {}
    for d in sorted(glob.glob(os.path.join(run_2, "*/"))):
        tag = os.path.basename(d.rstrip("/"))
        ready = window_aus_serial(os.path.join(d, "serial.txt"))
        for ppm in sorted(glob.glob(os.path.join(d, "*.ppm"))):
            base = os.path.basename(ppm)[:-4]
            png = os.path.join(beleg, f"{tag}--{base}.png")
            subprocess.run([sys.executable,
                            os.path.join(HIER, "ppm2png.py"), ppm, png],
                           check=False)
            w, h, px = read_ppm(ppm)
            bs, top = blaustich(px, w, h)
            md5 = hashlib.md5(px).hexdigest()
            eq = ""
            if md5 in vorher:
                eq = f" **BYTE-GLEICH mit {vorher[md5]}**"
            else:
                vorher[md5] = f"{tag}/{base}"
            flaechen = "  ".join(f"`#{r:02x}{g:02x}{b:02x}` {100.0*n/(w*h):.0f}%"
                                 for (r, g, b), n in top[:3])
            zeilen.append(
                f"| `{tag}` | `{base}` | {w}×{h} | **{bs:+.1f}** | "
                f"{flaechen} | {', '.join(ready) or '—'}{eq} |")
    header = ("# BEFUND — Abnahme MERGE-10\n\n"
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
        header + "\n".join(zeilen) + "\n")
    print(f"{len(zeilen)} images, FINDING.md written to {beleg}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
