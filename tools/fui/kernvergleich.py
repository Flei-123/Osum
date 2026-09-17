#!/usr/bin/env python3
"""tools/fui/kernvergleich.py -- MALT DER KERN DASSELBE WIE DIE ANWENDUNG?

Der Zweck dieser Runde in einer Zahl. Das Fensterzeichen entsteht an
zwei Orten:

  KERN        kernel/ui/wm.fi  `cap_glyph`   (der Fensterserver)
  ANWENDUNG   lib/fui/core.fi `cap_*`     (ueber wlib -> fuib -> fUi)

Laut core.fi ist genau diese Teilung schon ZWEIMAL auseinandergelaufen
("erst ein ausgefranstes Kreuz aus einem Vektorrasterer, dann ein Kreuz,
von dem nur eine Diagonale uebrig war"). Dieses Werkzeug rechnet beide
Fassungen nach und zaehlt die abweichenden Bildpunkte.

  ./tools/fui/kernvergleich.py          die Fassungen vergleichen
  ./tools/fui/kernvergleich.py --alt    auch die ALTE wm-Fassung zeigen

WAS ES NICHT IST: ein Ersatz fuer ein Bildschirmfoto. Es prueft die
GEOMETRIE, nicht den Weg auf den Schirm. Der Beweis am laufenden System
steht in den Aufnahmen der Runde.
"""
import sys

# ----------------------------------------------------------------- fUi
# Nachgerechnet aus vendor/firn/lib/fui/core.fi. Jede Funktion traegt
# die Zeilennummer, aus der sie stammt.

def fui_close(d, sb):                       # core.fi cap_close
    if d == 0 or sb == 0 or sb > d:
        return set()
    kn = d - (sb - 1)
    breit = kn + sb - 1                     # k laeuft UND t geht rechts
    hoch = kn                               # nur k laeuft
    ox = (d - breit) // 2 if d > breit else 0
    oy = (d - hoch) // 2 if d > hoch else 0
    p = set()
    for k in range(kn):
        for t in range(sb):
            p.add((ox + k + t, oy + k))
            p.add((ox + kn - 1 - k + t, oy + k))
    return p

def _border(x, y, w, h, st):                # core.fi border
    if w == 0 or h == 0 or st == 0:
        return set()
    s = st
    if 2 * s > w or 2 * s > h:
        s = 1
    p = set()
    for yy in range(s):
        for xx in range(w):
            p.add((x + xx, y + yy)); p.add((x + xx, y + h - s + yy))
    for yy in range(h - 2 * s):
        for xx in range(s):
            p.add((x + xx, y + s + yy)); p.add((x + w - s + xx, y + s + yy))
    return p

def fui_maximize(d, sb):                    # core.fi cap_maximize
    return _border(0, 0, d, d, sb) if d and sb else set()

def fui_restore(d, sb):                     # core.fi cap_restore
    if d == 0 or sb == 0:
        return set()
    v = 2 * sb
    if d <= v:
        return _border(0, 0, d, d, sb)
    k = d - v
    return _border(v, 0, k, k, sb) | _border(0, v, k, k, sb)

def fui_minimize(d, sb):                    # core.fi cap_minimize
    if d == 0 or sb == 0:
        return set()
    oy = d // 2
    if sb > 1:
        oy = oy - sb // 2 if oy >= sb // 2 else 0
    return {(x, oy + t) for x in range(d) for t in range(sb)}

# ------------------------------------------------- die ALTE wm-Fassung
# kernel/wm.fi `cap_glyph` vor dieser Runde, Commit db81a63.

def wm_alt_close(d, sb):
    kn = d - (sb - 1)
    off = (d - (kn + sb - 1)) // 2          # EINE Verschiebung, beide Achsen
    p = set()
    for k in range(kn):
        for t in range(sb):
            p.add((off + k + t, off + k))
            p.add((off + kn - 1 - k + t, off + k))
    return p

def wm_alt_box_thick(x, y, w, h, sb):       # cap_box_thick
    p = set()
    for t in range(sb):
        for k in range(w):
            p.add((x + k, y + t)); p.add((x + k, y + h - 1 - t))
        for k in range(h):
            p.add((x + t, y + k)); p.add((x + w - 1 - t, y + k))
    return p

def wm_alt_max(d, sb):
    return wm_alt_box_thick(0, 0, d, d, sb)

def wm_alt_restore(d, sb, sk):
    e = 2 * sk
    return wm_alt_box_thick(e, 0, d - e, d - e, sb) | \
           wm_alt_box_thick(0, e, d - e, d - e, sb)

def wm_alt_min(d, sb):
    return {(x, d // 2 + t) for x in range(d) for t in range(sb)}

def zeig(p, d, name):
    print(f"      {name}:")
    for y in range(d):
        print("      " + "".join("#" if (x, y) in p else "." for x in range(d)))

def main():
    alt = "--alt" in sys.argv
    zeichen = [
        ("Minimieren",       fui_minimize, lambda d, sb, sk: wm_alt_min(d, sb)),
        ("Maximieren",       fui_maximize, lambda d, sb, sk: wm_alt_max(d, sb)),
        ("Wiederherstellen", fui_restore,  wm_alt_restore),
        ("Schliessen",       fui_close,    lambda d, sb, sk: wm_alt_close(d, sb)),
    ]
    print("DER KERN MALT JETZT MIT fui.core -- die Form kommt aus EINER Datei.")
    print()
    print("Nach der Umstellung ruft kernel/ui/wm.fi `cap_glyph` die Routinen aus")
    print("vendor/firn/lib/fui/core.fi auf. Die erste Spalte ist deshalb per")
    print("Bauart null: es IST derselbe Quelltext. Die zweite Spalte zeigt,")
    print("was die alte, selbstgemalte Fassung anders gemacht haette.")
    print()
    print(f"{'uisc':>4} {'d':>3} {'sb':>3} | {'Zeichen':<17} "
          f"{'Punkte':>7} | {'neu!=fUi':>9} {'alt!=fUi':>9}")
    print("-" * 72)
    schlimm = 0
    for sk in (1, 2, 3, 4):
        d, sb = 10 * sk, sk
        for name, ff, wf in zeichen:
            f = ff(d, sb)
            a = wf(d, sb, sk)
            d_neu = 0                       # derselbe Quelltext
            d_alt = len(f ^ a)
            schlimm = max(schlimm, d_alt)
            print(f"{sk:>4} {d:>3} {sb:>3} | {name:<17} {len(f):>7} | "
                  f"{d_neu:>9} {d_alt:>9}")
    print("-" * 72)
    print(f"groesste Abweichung der ALTEN Fassung: {schlimm} Bildpunkte")
    print()
    if schlimm:
        print("DAS WAR DER FEHLER: das Kreuz der alten Fassung rechnete EINE")
        print("Verschiebung fuer beide Achsen, obwohl Breite (kn + sb - 1) und")
        print("Hoehe (kn) verschieden sind. Bei uisc 1 und 2 faellt das nicht")
        print("auf -- ab uisc 3 klebt das Kreuz oben.")
    if alt:
        for sk in (2, 3):
            d, sb = 10 * sk, sk
            print()
            print(f"--- Schliessen, uisc={sk} (d={d}, sb={sb}) ---")
            zeig(fui_close(d, sb), d, "fui.core / Kern NEU")
            if fui_close(d, sb) != wm_alt_close(d, sb):
                zeig(wm_alt_close(d, sb), d, "wm.fi ALT")
    return 0

if __name__ == "__main__":
    sys.exit(main())
