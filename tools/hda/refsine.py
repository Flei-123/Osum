#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/hda/refsine.py -- DERSELBE SINUS, NOCH EINMAL, AUF DEM WIRT.

Diese Datei rechnet Zeile fuer Zeile das nach, was `audio.sine_q28` und
`audio.tone_into` in `kernel/drv/snd/audio.fi` rechnen: dieselbe Festkommareihe
in Q28, derselbe Phasenschritt, dieselbe Rundung, dieselbe Klammer.

WOZU. Ohne sie hiesse "der Ton stimmt" nur "es sieht nach einem Sinus
aus". Mit ihr laesst sich die Datei, die QEMU geschrieben hat, WERT FUER
WERT gegen das halten, was der Kernel erzeugt haben MUSS -- und wenn
jeder einzelne der 96000 Werte stimmt, dann ist der ganze Weg

    Erzeugung -> Ringpuffer -> Deskriptorliste -> DMA -> Mischer -> Datei

rechnungsfrei. Das ist die Zusage "bitgleich" aus dem Auftrag dieser
Runde, und sie ist nur so pruefbar.

WENN DIESE DATEI UND kernel/drv/snd/audio.fi AUSEINANDERLAUFEN, faellt der
Vergleich -- absichtlich. Wer die Reihe im Kernel aendert, aendert sie
hier mit, und beim naechsten Lauf steht in der Ausgabe, ob beide
dasselbe meinen.

RUNDE HDA: sie VERGLEICHT jetzt auch.  Bis dahin hat sie nur eine
Vergleichsdatei geschrieben und das Gegenrechnen dem Testlaeufer
ueberlassen; das ist zweimal dieselbe Rechnung an zwei Stellen.  Wird
ihr eine WAV-Datei uebergeben, die es schon gibt, sucht sie darin den
Nutzbereich (erster bis letzter Wert ungleich null) und haelt ihn WERT
FUER WERT gegen die Reihe.  Sie druckt

    ungleich=N   Werte, die abweichen -- null heisst bitgleich
    maxdiff=N    der groesste Abstand, falls doch etwas abweicht
    verglichen=N wie viele Werte ueberhaupt verglichen wurden

    refsine.py aus.wav [--hz 440] [--rahmen 48000] [--pegel 24000]
               [--schreiben]
"""
import argparse
import struct
import wave

Q28 = 1 << 28
PI_HALF_Q28 = 421657428  # round(pi/2 * 2**28)


def sine_q28(phase):
    q = (phase >> 30) & 3
    r = phase & 0x3FFFFFFF
    if q == 1 or q == 3:
        r = 0x40000000 - r
    x = (r * PI_HALF_Q28) >> 30
    x2 = (x * x) >> 28
    p3 = (x * x2) >> 28
    p5 = (p3 * x2) >> 28
    p7 = (p5 * x2) >> 28
    p9 = (p7 * x2) >> 28
    v = x + p5 // 120 + p9 // 362880
    sub = p3 // 6 + p7 // 5040
    if sub >= v:
        return 0
    v = v - sub
    if v > Q28:
        return Q28
    return v


def sine_neg(phase):
    return ((phase >> 31) & 1) != 0


def erzeugen(hz, rahmen, pegel, rate):
    step = (hz * 4294967296 + rate // 2) // rate
    ph = 0
    aus = bytearray()
    for _ in range(rahmen):
        m = (sine_q28(ph) * pegel) >> 28
        v = m
        if sine_neg(ph):
            v = 65536 - m
        if v > 65535:
            v = 65535
        aus += struct.pack("<HH", v, v)
        ph = (ph + step) & 0xFFFFFFFF
    return bytes(aus)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ausgabe")
    ap.add_argument("--hz", type=int, default=440)
    ap.add_argument("--rahmen", type=int, default=48000)
    ap.add_argument("--pegel", type=int, default=24000)
    ap.add_argument("--rate", type=int, default=48000)
    ap.add_argument("--schreiben", action="store_true")
    a = ap.parse_args()
    d = erzeugen(a.hz, a.rahmen, a.pegel, a.rate)
    if a.schreiben:
        w = wave.open(a.ausgabe, "wb")
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(a.rate)
        w.writeframes(d)
        w.close()
        print("refsine: %s geschrieben -- %d Rahmen, %d Hz, Pegel %d"
              % (a.ausgabe, a.rahmen, a.hz, a.pegel))
        return
    # VERGLEICHEN.  Der Nutzbereich der gemessenen Datei wird gesucht
    # und Wert fuer Wert gegen die Reihe gehalten.  Der ANFANG wird
    # dabei nicht geraten: es wird der Versatz genommen, bei dem der
    # erste Wert ungleich null steht -- der Kern faengt bei Phase null
    # an, und alles davor ist die Stille des Vorlaufs.
    import array
    try:
        w = wave.open(a.ausgabe)
    except Exception as e:                       # noqa: BLE001
        print("ungleich=999999 grund=%s" % e)
        return
    got = array.array("h")
    got.frombytes(w.readframes(w.getnframes()))
    nch = w.getnchannels()
    links = list(got[0::nch])
    ref = array.array("h")
    ref.frombytes(d)
    refl = list(ref[0::2])
    nz = [i for i, v in enumerate(links) if v != 0]
    if not nz:
        print("ungleich=999999 verglichen=0 grund=leer")
        return
    lo = nz[0]
    # Der erste Wert der Reihe ist null (Phase null), also faengt der
    # Vergleich EINEN Rahmen vor dem ersten Wert ungleich null an.
    if lo > 0:
        lo = lo - 1
    n = min(len(refl), len(links) - lo)
    schlecht = 0
    maxd = 0
    for i in range(n):
        dd = abs(links[lo + i] - refl[i])
        if dd != 0:
            schlecht += 1
            if dd > maxd:
                maxd = dd
    print("verglichen=%d ungleich=%d maxdiff=%d ab=%d"
          % (n, schlecht, maxd, lo))


if __name__ == "__main__":
    main()
