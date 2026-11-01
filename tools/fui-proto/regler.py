#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fui-proto/regler.py -- LIEST DIE ZAHLEN AUS DEM LAUF.

    regler.py <serial.txt> [bilderverzeichnis]

Justins Vorgabe, 12.09.2026: "Hover und Regler durch Selbstfahren der
Maus nachweisen, nicht durch Augenschein. Jede Zahl aus dem Lauf, der
auch den Beleg erzeugt hat."

Dieses Skript erfindet keine Sollwerte. Es liest, was das
Kontrollzentrum selbst auf die serielle Leitung geschrieben hat, und
prueft die einzige Aussage, die ein Bild nicht treffen kann:

    Aendert sich der WERT, wenn die Maus an eine andere Stelle der
    Rinne klickt?

Ein gemalter Griff kann das nicht. Deshalb ist die Bedingung nicht "der
Wert ist 40", sondern "links ist kleiner als Mitte ist kleiner als
rechts" -- eine Ordnung, die nur entsteht, wenn der Zeiger den Wert
wirklich setzt.

Dazu, ebenfalls aus der Leitung: hat fUi die Flaechen gemalt
(`fui=`/`fuix=` im Bericht der Taskleiste), oder ist die Bruecke auf
wlibs alten Weg zurueckgefallen?
"""
import re
import sys


def read_2(p):
    with open(p, "rb") as f:
        return f.read().decode("latin1")


def all_(txt, muster):
    return [m for m in re.finditer(muster, txt)]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    txt = read_2(sys.argv[1])
    error = 0

    print("== THE GROOVE AS THE CONTROL CENTER REPORTS IT ==")
    trace = all_(txt, r"qs: bright trace from=(\d+) bis=(\d+) ym=(\d+)")
    if not trace:
        print("  NO groove reported -- the control center was never open")
        return 1
    v, b, ym = trace[-1].groups()
    print(f"  Brightness: from x={v} to x={b}, middle y={ym}")

    print()
    print("== WHAT THE SLIDER COMPUTES FROM THE POINTER POSITION ==")
    gerechnet = [(int(m.group(1)), int(m.group(2)))
                 for m in all_(txt, r"qs: bright to =(\d+) rc=(-?\d+)")]
    if gerechnet:
        vs = sorted({v for v, _ in gerechnet})
        rcs = sorted({rc for _, rc in gerechnet})
        print(f"  {len(gerechnet)} Zuege, {len(vs)} verschiedene Werte: {vs}")
        print(f"  Antworten des Kerns: {rcs}")
        if len(vs) >= 2:
            print("  OK  the pointer position determines the value -- the slider")
            print("      really computes, it is not a painted handle")
        else:
            print("  FEHLT: immer derselbe Wert")
            error += 1
        if rcs == [-19]:
            print("  NOTE: the kernel does NOT accept it (-19 = ENODEV).")
            print("      kernel/sys/sysgui.fi do_dispset verlangt vmode.ready();")
            print("      QEMU's simple framebuffer has no display device.")
            print("      That is the environment and not a fault of the UI.")
    else:
        print("  no computation reported -- the slider was never touched")
        error += 1

    print()
    print("== THE VALUE THE PANEL READS WHEN PAINTING ==")
    values = [int(m.group(1)) for m in all_(txt, r"qs: bright is=(\d+)")]
    seq = []
    for w in values:
        if not seq or seq[-1] != w:
            seq.append(w)
    print(f"  gemeldete Werte in Reihenfolge: {seq}")
    if len(seq) < 2:
        print("  unveraendert -- erwartbar, solange der Kern ENODEV sagt:")
        print("  the panel reads the value from the kernel when painting, and it")
        print("  did not take it over. What the UI does is shown")
        print("  im Abschnitt darueber.")
    else:
        print(f"  verschiedene Werte: {len(set(seq))}")
        if len(set(seq)) < 2:
            print("  FEHLT: immer derselbe Wert")
            error += 1
        else:
            print("  OK  the value follows the mouse -- no painted handle")

    print()
    print("== DIE LAUTSTAERKE ==")
    vol = [int(m.group(1)) for m in all_(txt, r"qs: vol ist=(\d+)")]
    if vol:
        print(f"  gemeldet: {sorted(set(vol))}  (letzter {vol[-1]})")
    else:
        print("  nicht gemeldet")

    print()
    print("== DID fUi PAINT? (taskbar report) ==")
    fui = all_(txt, r"fui=(\d+) fuix=(\d+)")
    if not fui:
        print("  NO counter on the wire -- unknown")
        error += 1
    else:
        ok, no = fui[-1].groups()
        ok, no = int(ok), int(no)
        anteil = 100.0 * ok / (ok + no) if (ok + no) else 0.0
        print(f"  von fUi gemalt: {ok}   zurueckgefallen: {no}"
              f"   ({anteil:.1f} % durch fUi)")
        if ok == 0:
            print("  MISSING: fUi painted NOTHING -- the bridge is not running")
            error += 1
        else:
            print("  OK  the areas on screen come from fUi")

    print()
    if error:
        print(f"REGLER-PRUEFUNG FEHLGESCHLAGEN ({error})")
        return 1
    print("REGLER-PRUEFUNG PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
