# tools/blur -- die Messmittel der Runde BLUR

Drei Werkzeuge, und jedes beantwortet genau eine Frage, die man dem
Bild allein nicht ansieht.

## kehrwert.py -- ist die Abkuerzung erlaubt?

Der Filter teilt je Bildpunkt und Kanal eine Summe durch ihre Anzahl.
Zwoelf ganzzahlige Divisionen je Bildpunkt sind der teuerste Teil des
ganzen Filters (gemessen: 15,32 ms gegen 3,16 ms fuer das Startmenue).
Stattdessen wird mit einem Kehrwert multipliziert -- was nur zulaessig
ist, wenn das Ergebnis in JEDEM vorkommenden Fall exakt dasselbe ist.

    python3 tools/blur/kehrwert.py

Geht alle n von 1 bis 33 und alle Summen von 0 bis n*255 durch --
143 088 Faelle -- und meldet den groessten Fehler. Er muss 0 sein.

## kante.py -- ist der Blur WIRKLICH im Bild?

Die Zaehler des Servers sagen, dass gerechnet wurde. Sie sagen nicht,
dass man es SIEHT -- und genau diese Luecke gab es in dieser Runde
einmal wirklich (der Filter lief, die Leiste kopierte ihren deckenden
Puffer darueber).

    python3 tools/blur/kante.py <bild.png>

Misst nicht die Summe der Unterschiede (die taugt nicht: eine getoente
Flaeche hat kleinere Unterschiede, ohne weichgezeichnet zu sein),
sondern ihre VERTEILUNG: eine harte Kante ist EIN grosser Sprung, eine
weiche ist eine lange Reihe kleiner. Hinter dem Blur muessen die harten
Kanten auf 0 fallen und die weichen Uebergaenge in die Hunderte gehen.

## kosten.c -- was kostet es?

    gcc -O2 -o /tmp/blurkosten tools/blur/kosten.c && /tmp/blurkosten

Der Filter in C, auf denselben Flaechen wie die Auftragsliste, gegen
das 60-Hz-Budget von 16,7 ms. Liefert auch die Kosten einer reinen
Kopie -- also das, was der Zwischenspeicher stattdessen zahlt.

## blurasm.py / asmtest.c -- the assembly loops and their proof

    python3 tools/blur/blurasm.py test     # 20 million cases against the Firn loops written out in C
    python3 tools/blur/blurasm.py check    # the strings in kernel/ui/wm.fi are the text of blurasm.py

r481: the routines `s` (tint + grain, four pixels), `w` (vertical pass, columns in fours) and `x` (horizontal pass, four rows) use SSE2; the scalar
`m`, `v`, `h` do the rest and everything when `fb.simd_ok` is false (`fbnosimd`). The test compares each pair with the same reference, with random alpha
bytes, and checks that xmm0 - xmm15 are returned unchanged. Native timing of one 640 x 416 blur: 8.8 ms scalar, 2.35 ms SSE2.
