#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/demux/vergleich.py -- was Osum dekodiert hat, gegen ffmpeg.

"Klingt richtig" ist kein Beweis. Dieses Skript stellt die Abtastwerte
nebeneinander und rechnet drei Zahlen aus:

  1. Der MITTLERE und der GROESSTE Fehler je Abtastwert, in Einheiten
     des 16-Bit-Wertes (also 1 = ein LSB von 32768).
  2. Der EFFEKTIVWERT des Fehlers gegen den Effektivwert des Signals --
     der Stoerabstand des eigenen Dekodierers gegen den fremden, in dB.
  3. Der FFT-Vergleich: das Betragsspektrum beider Seiten ueber das
     ganze Stueck, und der groesste Unterschied je Frequenzlinie in dB.
     Ein Fehler, der in der Zeit klein aussieht, aber eine Spiegel-
     frequenz erzeugt, faellt hier auf und sonst nirgends.

MP3 IST NICHT BITGENAU DEFINIERT. ISO/IEC 11172-4 verlangt fuer einen
"vollstaendig uebereinstimmenden" Dekodierer einen Effektivfehler unter
2^-15 der Vollaussteuerung gegen die Referenz -- also unter EINEM
16-Bit-Schritt. Genau das wird hier gemessen; ein Vergleich Oktett fuer
Oktett waere die falsche Frage.

    python3 tools/demux/vergleich.py <osum.raw> <ffmpeg.raw> <kanaele>
                                     [--json <datei>] [--name <name>]
"""
import json
import math
import struct
import sys


def lade(pfad):
    d = open(pfad, "rb").read()
    n = len(d) // 2
    return list(struct.unpack("<%dh" % n, d[:n * 2]))


def fft(x):
    """Radix-2, iterativ, ohne numpy -- der Wirt soll nichts brauchen."""
    n = len(x)
    j = 0
    x = list(x)
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            x[i], x[j] = x[j], x[i]
    laenge = 2
    while laenge <= n:
        ang = -2 * math.pi / laenge
        wl = complex(math.cos(ang), math.sin(ang))
        for i in range(0, n, laenge):
            w = complex(1)
            for k in range(laenge // 2):
                u = x[i + k]
                v = x[i + k + laenge // 2] * w
                x[i + k] = u + v
                x[i + k + laenge // 2] = u - v
                w *= wl
        laenge <<= 1
    return x


def spektrum(v, punkte=4096):
    """Mittleres Betragsspektrum ueber alle vollen Bloecke."""
    n = len(v) // punkte
    if n == 0:
        return []
    akku = [0.0] * (punkte // 2)
    for b in range(n):
        blk = [complex(v[b * punkte + i], 0.0) for i in range(punkte)]
        # Hann-Fenster: ohne es ist jede Kante eine Stufe und das
        # Spektrum ein Kamm.
        for i in range(punkte):
            blk[i] *= 0.5 - 0.5 * math.cos(2 * math.pi * i / punkte)
        f = fft(blk)
        for i in range(punkte // 2):
            akku[i] += abs(f[i])
    return [a / n for a in akku]


def fehler(a, b, off, ch, fenster, schritt):
    """Mittlerer Betragsfehler bei einem Versatz von `off` Rahmen."""
    if off >= 0:
        ia, ib = off * ch, 0
    else:
        ia, ib = 0, (0 - off) * ch
    n = min(len(a) - ia, len(b) - ib, fenster)
    if n <= 0:
        return None
    s = 0
    k = 0
    i = 0
    while i < n:
        s += abs(a[ia + i] - b[ib + i])
        k += 1
        i += schritt
    return s / max(1, k)


def suche_versatz(a, b, ch, weit=1500):
    """Zwei Stufen: grob in Vierer-, dann fein in Einerschritten."""
    bester, wert = 0, None
    k = -weit
    while k <= weit:
        f = fehler(a, b, k, ch, 20000, 8)
        if f is not None and (wert is None or f < wert):
            bester, wert = k, f
        k += 4
    fein, wert = bester, None
    k = bester - 6
    while k <= bester + 6:
        f = fehler(a, b, k, ch, 80000, 2)
        if f is not None and (wert is None or f < wert):
            fein, wert = k, f
        k += 1
    return fein


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    a = lade(sys.argv[1])
    b = lade(sys.argv[2])
    ch = int(sys.argv[3])
    name = "?"
    jout = None
    k = 4
    while k < len(sys.argv):
        if sys.argv[k] == "--json":
            jout = sys.argv[k + 1]
            k += 2
        elif sys.argv[k] == "--name":
            name = sys.argv[k + 1]
            k += 2
        else:
            k += 1

    if len(a) == 0 or len(b) == 0:
        print("vergleich: eine Seite ist leer (osum=%d ffmpeg=%d)"
              % (len(a), len(b)))
        return 1

    # DER VERSATZ. Ein MP3-Dekodierer hat eine Anlaufzeit (529
    # Abtastwerte in der Filterbank, dazu der erste halbe Rahmen), und
    # ffmpeg SCHNEIDET sie ab, wenn der Behaelter sie ausweist --
    # Matroska und MP4 tun das, eine rohe .mp3-Datei ohne Xing-Rahmen
    # nicht. Ein Vergleich, der das nicht beruecksichtigt, misst den
    # Versatz und nicht den Dekodierer.
    versatz = suche_versatz(a, b, ch)
    if versatz >= 0:
        a = a[versatz * ch:]
    else:
        b = b[(0 - versatz) * ch:]
    n = min(len(a), len(b))
    d = [a[i] - b[i] for i in range(n)]
    absd = [abs(x) for x in d]
    mittel = sum(absd) / n
    groesst = max(absd)
    rms_e = math.sqrt(sum(x * x for x in d) / n)
    rms_s = math.sqrt(sum(x * x for x in b[:n]) / n)
    snr = 99.0
    if rms_e > 0 and rms_s > 0:
        snr = 20.0 * math.log10(rms_s / rms_e)

    # FFT nur ueber den linken Kanal, und nur ueber so viel, wie in eine
    # Zweierpotenz passt.
    links_a = a[0:n:ch]
    links_b = b[0:n:ch]
    punkte = 4096
    m = (min(len(links_a), len(links_b)) // punkte) * punkte
    fftmax = 0.0
    fftband = -1
    if m >= punkte:
        sa = spektrum(links_a[:m], punkte)
        sb = spektrum(links_b[:m], punkte)
        gipfel = max(sb) if sb else 1.0
        schwelle = gipfel * 1e-4  # -80 dB unter dem Gipfel: darunter ist Rauschen
        for i in range(len(sa)):
            if sb[i] < schwelle:
                continue
            r = 20.0 * math.log10((sa[i] + 1e-12) / (sb[i] + 1e-12))
            if abs(r) > fftmax:
                fftmax = abs(r)
                fftband = i

    print("vergleich %s: n=%d  versatz=%d  mittel=%.4f  max=%d  rms=%.4f  "
          "snr=%.1f dB  fft_max=%.2f dB (Linie %d)"
          % (name, n, versatz, mittel, groesst, rms_e, snr, fftmax, fftband))
    if jout:
        with open(jout, "w") as f:
            json.dump({"name": name, "n": n, "versatz": versatz,
                       "mittel": mittel,
                       "max": groesst, "rms": rms_e, "snr_db": snr,
                       "fft_max_db": fftmax, "fft_linie": fftband,
                       "laenge_osum": len(a), "laenge_ffmpeg": len(b)}, f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
