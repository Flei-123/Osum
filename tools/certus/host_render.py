#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/certus/host_render.py -- WAS CERTUS HEUTE WIRKLICH KANN, gemessen.

Dieses Skript behauptet nichts. Es startet einen X-Server, den niemand
sieht (Xvfb), laesst den fertigen Certus aus dem Firn-Baum eine ECHTE
Seite aus dem Netz laden, und zaehlt danach die Bildpunkte:

  * TINTE          -- Punkte, die nicht die Hintergrundfarbe haben. Eine
                      leere Seite hat null davon, und genau daran
                      scheitert ein Browser, der behauptet gemalt zu
                      haben.
  * TEXTBAENDER    -- waagrechte Baender, in denen dunkle Punkte stehen.
                      Ein Kasten ist EIN Band, ein Absatz sind mehrere.
  * FARBEN         -- verschiedene Farben in der Seitenflaeche.

Und weil eine Zahl ohne Gegenstueck nichts wert ist, holt es dieselbe
Adresse mit einem ECHTEN Browser (Chromium, --dump-dom) und haelt die
Textbloecke gegeneinander.

    python3 tools/certus/host_render.py <certus-binary> <url> <name>

Ergebnis: JSON auf stdout, Bilder unter .certus-work/.
"""
import json
import os
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, ".certus-work")


def read_ppm(path):
    b = open(path, "rb").read()
    if not b.startswith(b"P6"):
        return None
    parts = []
    i = 2
    while len(parts) < 3:
        while i < len(b) and b[i:i + 1].isspace():
            i += 1
        j = i
        while j < len(b) and not b[j:j + 1].isspace():
            j += 1
        parts.append(int(b[i:j]))
        i = j
    i += 1
    w, h, _ = parts
    return w, h, b[i:i + w * h * 3]


def read_xwd(path):
    b = open(path, "rb").read()
    hdr = struct.unpack(">25I", b[:100])
    (header_size, _fv, _pf, _pd, pw, ph, _xo, byte_order, _bu, _bbo,
     _bp, bits_per_pixel, bytes_per_line, _vc, _rm, _gm, _bm, _bpr,
     _ce, ncolors, _ww, _wh, _wx, _wy, _wb) = hdr
    off = header_size + ncolors * 12
    px = b[off:]
    out = bytearray(pw * ph * 3)
    bpp = bits_per_pixel // 8
    for y in range(ph):
        row = px[y * bytes_per_line:(y + 1) * bytes_per_line]
        for x in range(pw):
            p = row[x * bpp:x * bpp + bpp]
            if len(p) < 3:
                continue
            if byte_order == 0:
                bl, g, r = p[0], p[1], p[2]
            else:
                r, g, bl = p[-3], p[-2], p[-1]
            o = (y * pw + x) * 3
            out[o] = r
            out[o + 1] = g
            out[o + 2] = bl
    return pw, ph, bytes(out)


def ink_stats(w, h, px, y0=0):
    """Die Zahlen, die eine leere Seite von einer vollen unterscheiden."""
    from collections import Counter
    cnt = Counter()
    for y in range(y0, h):
        base = y * w * 3
        for x in range(w):
            o = base + x * 3
            cnt[px[o:o + 3]] += 1
    if not cnt:
        return {}
    bg = cnt.most_common(1)[0][0]
    ink = sum(v for k, v in cnt.items() if k != bg)
    dark = sum(v for k, v in cnt.items()
               if k[0] < 96 and k[1] < 96 and k[2] < 96)
    rows = []
    for y in range(y0, h):
        base = y * w * 3
        d = 0
        for x in range(w):
            o = base + x * 3
            if px[o] < 96 and px[o + 1] < 96 and px[o + 2] < 96:
                d += 1
        rows.append(d)
    bands = 0
    inband = False
    for d in rows:
        if d >= 3 and not inband:
            bands += 1
            inband = True
        elif d < 3:
            inband = False
    return {
        "breite": w, "hoehe": h - y0,
        "hintergrund": "#%02x%02x%02x" % (bg[0], bg[1], bg[2]),
        "tintenpunkte": ink,
        "tintenanteil": round(ink / float(w * (h - y0)), 5),
        "dunkle_punkte": dark,
        "farben": len(cnt),
        "textbaender": bands,
    }


def free_display():
    for n in range(90, 130):
        if not os.path.exists("/tmp/.X11-unix/X%d" % n):
            return n
    return 129


def chromium_dom(url):
    """Die Gegenstelle: was ein ECHTER Browser auf derselben Seite sieht."""
    exe = shutil.which("chromium") or shutil.which("chromium-browser") \
        or shutil.which("google-chrome")
    if not exe:
        return None
    d = tempfile.mkdtemp(prefix="certus-chrome-")
    try:
        r = subprocess.run(
            [exe, "--headless=old", "--disable-gpu", "--no-sandbox",
             "--user-data-dir=" + d, "--virtual-time-budget=5000",
             "--dump-dom", url],
            capture_output=True, timeout=90)
        return r.stdout.decode("utf-8", "replace")
    except Exception:
        return None
    finally:
        shutil.rmtree(d, ignore_errors=True)


def text_blocks(html):
    """Sichtbare Textbloecke aus HTML, roh und ohne Bibliothek."""
    import re
    html = re.sub(r"(?is)<script.*?</script>", " ", html)
    html = re.sub(r"(?is)<style.*?</style>", " ", html)
    html = re.sub(r"(?is)<head.*?</head>", " ", html)
    parts = re.split(
        r"(?i)<(?:p|div|h[1-6]|li|br|td|tr|section|article)[^>]*>", html)
    out = []
    for p in parts:
        t = re.sub(r"<[^>]+>", " ", p)
        t = re.sub(r"&nbsp;", " ", t)
        t = re.sub(r"&amp;", "&", t)
        t = re.sub(r"\s+", " ", t).strip()
        if len(t) >= 12:
            out.append(t)
    return out


def main():
    binary, url, name = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(WORK, exist_ok=True)
    res = {"url": url, "name": name}

    disp = free_display()
    xvfb = subprocess.Popen(
        ["Xvfb", ":%d" % disp, "-screen", "0", "1280x1024x24"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(200):
        if os.path.exists("/tmp/.X11-unix/X%d" % disp):
            break
        time.sleep(0.05)
    env = dict(os.environ, DISPLAY=":%d" % disp)
    shot = os.path.join(WORK, "%s-eigen.ppm" % name)
    xwdf = os.path.join(WORK, "%s-server.xwd" % name)
    if os.path.exists(shot):
        os.unlink(shot)
    try:
        t0 = time.time()
        p = subprocess.run(
            [binary, url, "/etc/ssl/certs/ca-certificates.crt", "1",
             shot, str(disp)],
            capture_output=True, timeout=180)
        res["dauer_s"] = round(time.time() - t0, 2)
        res["rueckgabe"] = p.returncode
        res["ausgabe"] = p.stdout.decode("utf-8", "replace")[-2000:]
        proc = subprocess.Popen(
            [binary, url, "/etc/ssl/certs/ca-certificates.crt", "0",
             os.path.join(WORK, "%s-egal.ppm" % name), str(disp)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(min(25, max(8, res["dauer_s"] + 4)))
        r = subprocess.run(["xwd", "-name", "Certus", "-out", xwdf],
                           env=env, capture_output=True)
        res["fenster_da"] = (r.returncode == 0 and os.path.exists(xwdf))
        try:
            proc.send_signal(signal.SIGKILL)
            proc.wait(timeout=10)
        except Exception:
            pass
    finally:
        xvfb.terminate()

    if os.path.exists(shot):
        own = read_ppm(shot)
        if own:
            res["eigene_leinwand"] = ink_stats(*own)
    if res.get("fenster_da"):
        sv = read_xwd(xwdf)
        res["server_bild"] = ink_stats(sv[0], sv[1], sv[2], y0=30)

    dom = chromium_dom(url)
    if dom is not None:
        blocks = text_blocks(dom)
        res["chromium_textbloecke"] = len(blocks)
        res["chromium_zeichen"] = sum(len(b) for b in blocks)
        res["chromium_erste"] = blocks[:6]
    print(json.dumps(res, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
