#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/media1/wavcheck.py -- WAS WIRKLICH IN DER TONDATEI STEHT.

QEMU schreibt mit `-audiodev wav,path=...` genau die Oktette in eine
Datei, die es an eine Soundkarte geschickt haette. Das ist der einzige
Weg, Ton mechanisch zu messen statt ihn anzuhoeren -- und Anhoeren ist
in einem Testlauf keine Messung.

Dieses Programm liest so eine Datei und druckt Zeilen der Form

    wavcheck: name=zahl

Jede Zahl ist eine Tatsache ueber die Datei, keine Meinung. Der Laeufer
tools/media1/run.sh haelt sie gegen die Zusagen der Runde.

    wavcheck.py <datei.wav> [--erwartet-hz 440] [--rahmen 48000]
                [--vergleich referenz.wav]

WAS GEMESSEN WIRD

  frames            Rahmen in der Datei
  rate/channels     Kopf der Datei (muss 48000 / 2 sein)
  loud_first/last   erster und letzter Rahmen mit |Wert| > 1000
  signal_frames     loud_last + 1 -- die LAENGE des Nutzsignals
  tail_zero         Rahmen hinter signal_frames, die exakt null sind
  silent            1, wenn die GANZE Datei exakt null ist
  peak              groesster Betrag
  dc_milli          Gleichanteil des linken Kanals, mal 1000
  lr_equal          1, wenn beide Kanaele Wert fuer Wert gleich sind
  peak_hz_milli     Spitze der FFT (parabolisch verfeinert), mal 1000
  thdn_db_milli     alles ausser der Spitze, gegen die Spitze, in dB
  gaps              Nullstrecken > 8 Rahmen INNERHALB des Signals --
                    das ist die Aussetzerprobe: ein leergelaufener
                    Ringpuffer hinterlaesst genau so eine Luecke

MIT --vergleich zusaetzlich

  cmp_exact         1, wenn JEDER Wert Bit fuer Bit gleich ist
  cmp_maxdiff       groesster Unterschied in Einheiten des letzten Bits
  cmp_rms_ratio_ppm (RMS der Datei / RMS der Referenz) * 1e6 -- damit
                    laesst sich eine erwartete Daempfung auf ppm genau
                    pruefen

Ganzzahlen ueberall (deshalb `_milli`): der Laeufer ist eine Shell, und
`[ 4.93 -gt 4.5 ]` gibt es dort nicht.
"""
import argparse
import sys
import wave

import numpy as np


def lade(pfad):
    w = wave.open(pfad, "rb")
    n = w.getnframes()
    d = np.frombuffer(w.readframes(n), dtype="<i2")
    ch = w.getnchannels()
    if ch:
        d = d.reshape(-1, ch)
    return w.getframerate(), ch, w.getsampwidth(), d


def sag(k, v):
    print("wavcheck: %s=%s" % (k, v))


def nullstrecken(x, mindest):
    """Wie viele zusammenhaengende Strecken aus exakten Nullen laenger
    als `mindest` gibt es. Ein Aussetzer im Ringpuffer sieht genau so
    aus -- der Treiber spielt den Puffer, in dem nichts steht."""
    z = (x == 0).astype(np.int8)
    if z.size == 0:
        return 0
    kanten = np.flatnonzero(np.diff(np.concatenate(([0], z, [0]))))
    laeufe = kanten.reshape(-1, 2)
    return int(sum(1 for a, b in laeufe if b - a > mindest))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("datei")
    ap.add_argument("--erwartet-hz", type=float, default=0.0)
    ap.add_argument("--rahmen", type=int, default=0)
    ap.add_argument("--vergleich")
    ap.add_argument("--cmp-rahmen", type=int, default=0,
                    help="nur die ersten n Rahmen vergleichen")
    ap.add_argument("--fft-rahmen", type=int, default=48000)
    a = ap.parse_args()

    try:
        rate, ch, breite, d = lade(a.datei)
    except Exception as e:
        sag("readable", 0)
        print("wavcheck: fehler=%s" % e)
        return 0
    sag("readable", 1)
    sag("rate", rate)
    sag("channels", ch)
    sag("width", breite)
    n = d.shape[0]
    sag("frames", n)
    if n == 0:
        sag("silent", 1)
        sag("peak", 0)
        sag("signal_frames", 0)
        sag("gaps", 0)
        return 0

    L = d[:, 0].astype(np.float64)
    sag("peak", int(np.abs(d).max()))
    sag("silent", 1 if int(np.abs(d).max()) == 0 else 0)
    sag("lr_equal", 1 if ch > 1 and bool((d[:, 0] == d[:, 1]).all()) else 0)

    laut = np.flatnonzero(np.abs(L) > 1000)
    if laut.size:
        sag("loud_first", int(laut[0]))
        sag("loud_last", int(laut[-1]))
        sag("signal_frames", int(laut[-1]) + 1)
        ende = int(laut[-1]) + 1
    else:
        sag("loud_first", -1)
        sag("loud_last", -1)
        sag("signal_frames", 0)
        ende = 0
    # DIE LAENGE UEBER "UNGLEICH NULL" statt ueber "lauter als 1000".
    # Ein Sinus, der auf einem Nulldurchgang endet, hat am Ende hundert
    # leise Rahmen -- die Schwelle 1000 wuerde ihn zu kurz melden. Die
    # Fuellstille am Dateiende ist dagegen EXAKT null.
    nz = np.flatnonzero(L != 0)
    sag("signal_frames_nz", int(nz[-1]) + 1 if nz.size else 0)
    sag("tail_zero", int(np.count_nonzero(L[ende:] == 0)))
    sag("tail_frames", int(n - ende))

    # Aussetzer INNERHALB des Signals. Acht Rahmen sind 167 Mikrosekunden
    # -- kuerzer als ein Ringpuffer-Eintrag (2,67 ms) und laenger als der
    # Nulldurchgang eines Sinus (bei 440 Hz zwei Rahmen).
    sag("gaps", nullstrecken(L[:ende], 8) if ende else 0)

    if ende:
        sag("dc_milli", int(round(L[:ende].mean() * 1000)))
        nf = min(a.fft_rahmen, ende)
        seg = L[:nf]
        S = np.abs(np.fft.rfft(seg))
        f = np.fft.rfftfreq(nf, 1.0 / rate)
        k = int(np.argmax(S))
        dk = 0.0
        if 0 < k < len(S) - 1 and S[k] > 0:
            aa, bb, cc = S[k - 1], S[k], S[k + 1]
            nenner = (aa - 2 * bb + cc)
            if nenner:
                dk = 0.5 * (aa - cc) / nenner
        hz = f[k] + dk * (f[1] - f[0])
        sag("fft_frames", nf)
        sag("peak_hz_milli", int(round(hz * 1000)))
        rest = S.copy()
        lo, hi = max(0, k - 2), min(len(S), k + 3)
        rest[lo:hi] = 0
        thdn = np.sqrt((rest ** 2).sum()) / max(S[k], 1e-9)
        sag("thdn_db_milli", int(round(20 * np.log10(max(thdn, 1e-12)) * 1000)))
        if a.erwartet_hz > 0:
            sag("hz_error_milli", int(round((hz - a.erwartet_hz) * 1000)))
    if a.rahmen:
        got = int(laut[-1]) + 1 if laut.size else 0
        sag("frames_error", got - a.rahmen)

    if a.vergleich:
        try:
            r2, c2, b2, e = lade(a.vergleich)
        except Exception as ex:
            sag("cmp_readable", 0)
            print("wavcheck: cmp_fehler=%s" % ex)
            return 0
        sag("cmp_readable", 1)
        m = min(d.shape[0], e.shape[0])
        if a.cmp_rahmen:
            m = min(m, a.cmp_rahmen)
        sag("cmp_frames", m)
        if m == 0:
            return 0
        aa = d[:m].astype(np.int64)
        bb = e[:m].astype(np.int64)
        diff = np.abs(aa - bb)
        sag("cmp_exact", 1 if int(diff.max()) == 0 else 0)
        sag("cmp_maxdiff", int(diff.max()))
        sag("cmp_over1", int(np.count_nonzero(diff > 1)))
        ra = float(np.sqrt((aa.astype(float) ** 2).mean()))
        rb = float(np.sqrt((bb.astype(float) ** 2).mean()))
        sag("cmp_rms_ratio_ppm", int(round(ra / rb * 1e6)) if rb > 0 else 0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
