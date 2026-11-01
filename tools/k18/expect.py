#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k18/expect.py -- DIE ZWEITE FASSUNG DER RECHNUNG.

Runde K18 kodiert vier Dinge nach dem Handbuch: das Wort fuer
IA32_PERF_CTL, das Wort fuer IA32_HWP_REQUEST, das Wort fuer
IA32_MISC_ENABLE und die Skalierung eines Bildpunktes.  Dazu kommen die
zwei Rechnungen ueber den Akku (Prozent und Restzeit).

Ein Test, der die Ausgabe des Kernels gegen eine Konstante haelt, die
derselbe Mensch aus demselben Kopf abgeschrieben hat, misst nichts.
Deshalb steht die Rechnung hier NOCH EINMAL -- aus dem Handbuch und
nicht aus `kernel/pwr/pwr.fi`.  Wenn beide dasselbe sagen, ist es
wahrscheinlich richtig; wenn nicht, ist eine der beiden falsch, und das
ist genau die Auskunft, die ein Test geben soll.

Das ist dieselbe Bauart wie `tools/ttf/raster.py` in Runde K10 (eine
zweite Rasterung desselben Umrisses) und `tools/k15/layout.py` in
Runde K15 (die Anordnung gegen sich selbst gerechnet).

DIE QUELLEN, Absatz fuer Absatz -- Intel SDM Band 4 (Model-Specific
Registers) und Band 3, Kapitel 14/15:

  IA32_PERF_CTL (0x199)
      Bits 15:8   das gewuenschte Verhaeltnis zum Bustakt
      Bit  32     "Turbo Engage Disable" -- eine 1 nimmt die Turbostufe
                  zurueck
  IA32_HWP_REQUEST (0x774)
      Bits 7:0    Minimum_Performance
      Bits 15:8   Maximum_Performance
      Bits 23:16  Desired_Performance (0 = die Hardware entscheidet)
      Bits 31:24  Energy_Performance_Preference, 0 = nur Leistung,
                  255 = nur Sparsamkeit
  IA32_MISC_ENABLE (0x1A0)
      Bit  16     Enhanced Intel SpeedStep Technology Enable
      Bit  38     Turbo Mode Disable (verkehrt herum: 1 SPERRT)

VERWENDUNG
    expect.py perfctl <ratios> <profil>
    expect.py hwp     <ratios> <profil>
    expect.py misc    <orig>   <profil>
    expect.py skala   <rgb> <von> <nach>
    expect.py akku    <rest> <voll> <rate> <zustand>

<ratios> ist das Wort, das der Kernel als `ratios` meldet:
min | basis<<8 | max<<16.  Alle Zahlen duerfen dezimal oder mit 0x
geschrieben werden.  Ausgabe: eine Zahl, dezimal.
"""
import sys

SPAREN, MITTE, LEISTUNG = 0, 1, 2

MISC_EIST = 1 << 16
MISC_NOTURBO = 1 << 38
PERF_NOTURBO = 1 << 32


def num(s):
    return int(s, 0)


def parts(ratios):
    return ratios & 0xFF, (ratios >> 8) & 0xFF, (ratios >> 16) & 0xFF


def perfctl(ratios, prof):
    lo, basis, hi = parts(ratios)
    r = {SPAREN: lo, MITTE: basis, LEISTUNG: hi}[prof]
    w = (r & 0xFF) << 8
    if prof == SPAREN:
        w |= PERF_NOTURBO
    return w


def hwp(ratios, prof):
    lo, basis, hi = parts(ratios)
    if prof == SPAREN:
        return lo | (basis << 8) | (255 << 24)
    if prof == MITTE:
        return lo | (hi << 8) | (128 << 24)
    return basis | (hi << 8)


def misc(orig, prof):
    w = orig & ~(MISC_EIST | MISC_NOTURBO)
    if prof == SPAREN:
        w |= MISC_EIST | MISC_NOTURBO
    elif prof == MITTE:
        w |= MISC_EIST
    return w


def skala(v, von, nach):
    if von == 0:
        return 0
    out = 0
    for schieb in (16, 8, 0):
        k = (v >> schieb) & 0xFF
        k = min(255, k * nach // von)
        out |= k << schieb
    return out


def akku(rest, voll, rate, zustand):
    if voll == 0:
        p = 0
    else:
        p = min(100, (rest * 100 + voll // 2) // voll)
    if rate in (0, 0xFFFFFFFF):
        m = 0
    else:
        set_2 = (voll - rest) if (zustand & 2) else rest
        m = 0 if set_2 <= 0 and (zustand & 2) else (set_2 * 60) // rate
    return p, m


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    b = sys.argv[1]
    a = [num(x) for x in sys.argv[2:]]
    if b == "perfctl":
        print(perfctl(a[0], a[1]))
    elif b == "hwp":
        print(hwp(a[0], a[1]))
    elif b == "misc":
        print(misc(a[0], a[1]))
    elif b == "skala":
        print(skala(a[0], a[1], a[2]))
    elif b == "akku":
        p, m = akku(a[0], a[1], a[2], a[3])
        print("%d %d" % (p, m))
    else:
        print("unbekannt: %s" % b, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
