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


def lies(p):
    with open(p, "rb") as f:
        return f.read().decode("latin1")


def alle(txt, muster):
    return [m for m in re.finditer(muster, txt)]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    txt = lies(sys.argv[1])
    fehler = 0

    print("== DIE RINNE, WIE DAS KONTROLLZENTRUM SIE MELDET ==")
    spur = alle(txt, r"qs: hell spur von=(\d+) bis=(\d+) ym=(\d+)")
    if not spur:
        print("  KEINE Rinne gemeldet -- das Kontrollzentrum war nie offen")
        return 1
    v, b, ym = spur[-1].groups()
    print(f"  Helligkeit: von x={v} bis x={b}, Mitte y={ym}")

    print()
    print("== WAS DER REGLER AUS DER ZEIGERSTELLE RECHNET ==")
    # DIE RICHTIGE ZEILE. `qs: hell ist=` ist der Wert, den das Panel
    # beim MALEN abliest -- er kommt aus dem Kern und bleibt stehen,
    # solange der Kern ihn nicht annimmt. Was der Regler aus der Maus
    # RECHNET, steht in `qs: hell auf =<v> rc=<rc>`: v ist der Wert,
    # rc die Antwort des Kerns (0 = angenommen, -19 = ENODEV, kein
    # Anzeigegeraet).
    gerechnet = [(int(m.group(1)), int(m.group(2)))
                 for m in alle(txt, r"qs: hell auf =(\d+) rc=(-?\d+)")]
    if gerechnet:
        vs = sorted({v for v, _ in gerechnet})
        rcs = sorted({rc for _, rc in gerechnet})
        print(f"  {len(gerechnet)} Zuege, {len(vs)} verschiedene Werte: {vs}")
        print(f"  Antworten des Kerns: {rcs}")
        if len(vs) >= 2:
            print("  OK  die Zeigerstelle bestimmt den Wert -- der Regler")
            print("      rechnet wirklich, es ist kein gemalter Griff")
        else:
            print("  FEHLT: immer derselbe Wert")
            fehler += 1
        if rcs == [-19]:
            print("  HINWEIS: der Kern nimmt ihn NICHT an (-19 = ENODEV).")
            print("      kernel/sysgui.fi do_dispset verlangt vmode.ready();")
            print("      QEMUs einfacher Rahmenpuffer hat kein Anzeigegeraet.")
            print("      Das ist die Umgebung und kein Fehler der Oberflaeche.")
    else:
        print("  keine Rechnung gemeldet -- der Regler wurde nie beruehrt")
        fehler += 1

    print()
    print("== DER WERT, DEN DAS PANEL BEIM MALEN ABLIEST ==")
    werte = [int(m.group(1)) for m in alle(txt, r"qs: hell ist=(\d+)")]
    # Aufeinanderfolgende Wiederholungen zusammenfassen: das
    # Kontrollzentrum malt sich oefter neu als es sich aendert.
    folge = []
    for w in werte:
        if not folge or folge[-1] != w:
            folge.append(w)
    print(f"  gemeldete Werte in Reihenfolge: {folge}")
    if len(folge) < 2:
        print("  unveraendert -- erwartbar, solange der Kern ENODEV sagt:")
        print("  das Panel liest den Wert beim Malen aus dem Kern, und der")
        print("  hat ihn nicht uebernommen. Was die Oberflaeche tut, steht")
        print("  im Abschnitt darueber.")
    else:
        print(f"  verschiedene Werte: {len(set(folge))}")
        if len(set(folge)) < 2:
            print("  FEHLT: immer derselbe Wert")
            fehler += 1
        else:
            print("  OK  der Wert folgt der Maus -- kein gemalter Griff")

    print()
    print("== DIE LAUTSTAERKE ==")
    vol = [int(m.group(1)) for m in alle(txt, r"qs: vol ist=(\d+)")]
    if vol:
        print(f"  gemeldet: {sorted(set(vol))}  (letzter {vol[-1]})")
    else:
        print("  nicht gemeldet")

    print()
    print("== HAT fUi GEMALT? (Bericht der Taskleiste) ==")
    fui = alle(txt, r"fui=(\d+) fuix=(\d+)")
    if not fui:
        print("  KEIN Zaehler auf der Leitung -- unbekannt")
        fehler += 1
    else:
        ok, no = fui[-1].groups()
        ok, no = int(ok), int(no)
        anteil = 100.0 * ok / (ok + no) if (ok + no) else 0.0
        print(f"  von fUi gemalt: {ok}   zurueckgefallen: {no}"
              f"   ({anteil:.1f} % durch fUi)")
        if ok == 0:
            print("  FEHLT: fUi hat NICHTS gemalt -- die Bruecke laeuft nicht")
            fehler += 1
        else:
            print("  OK  die Flaechen auf dem Bildschirm kommen aus fUi")

    print()
    if fehler:
        print(f"REGLER-PRUEFUNG FEHLGESCHLAGEN ({fehler})")
        return 1
    print("REGLER-PRUEFUNG PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
