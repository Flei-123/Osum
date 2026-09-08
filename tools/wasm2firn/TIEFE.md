# Die 276 Ebenen von `yy_reduce` — und warum sie flach werden müssen

## Der Befund

`firnc` (Stufe 0) lässt **200 Verschachtelungsebenen** zu:
`compiler/src/parser.rs`, `const MAX_DEPTH: u32 = 200`.

SQLite überschreitet das — aber nur an **einer einzigen Stelle**:

| Funktion | Tiefe | was es ist |
|---|---|---|
| `f220` = **`yy_reduce`** | **276** | der LALR-Parser von SQLite |
| `f97` | 194 | knapp darunter |
| alle übrigen 1360 | ≤ 54 | unauffällig |

**Eine Funktion von 1362.** Das ist keine grundsätzliche Grenze des
Ansatzes, sondern ein Sonderfall mit einer bekannten Form.

## Die Form

`yy_reduce` fängt so an — gemessen, nicht vermutet:

```
276 × block          (alle hintereinander, ohne einen Befehl dazwischen)
   … Rumpf …
   br_table[…]       springt je nach Regelnummer in genau einen davon
```

Das ist das **Sprungtabellen-Muster**: ein `switch` mit 276 Fällen, den
LLVM als geschachtelte Blöcke ausdrückt, weil WASM kein `goto` hat. Jeder
`br N` verlässt N Ebenen und landet damit hinter dem passenden `block` —
also am Anfang genau eines Falls.

wasm2c trifft dasselbe Muster und löst es mit `goto` und einer
Sprungmarke je Block. Firn hat kein `goto`.

## Die Lösung hier: ein Verteiler statt eines Turms

Ein Turm aus `n` Blöcken, aus dem heraus nur gesprungen wird, ist
gleichwertig zu **einer** Schleife mit einer Fallnummer:

```firn
var fall: u64 = 0            // 0 = der Rumpf, 1..n = die Fälle
while true {
    if fall == 0 {
        … Rumpf …            // ein `br k` setzt fall = n-k und bricht ab
    } else if fall == 1 {
        … was hinter dem innersten block steht …
    } else if fall == 2 {
        …
    }
    break
}
```

Aus **276 Ebenen** wird so **eine** Ebene plus eine Vergleichskette.
Der Kontrollfluss ist derselbe: `br k` aus dem Rumpf heraus bedeutet
„weiter bei dem Code, der hinter dem k-ten `end` steht", und genau das
wählt die Fallnummer aus.

**Kosten:** eine Vergleichskette statt eines Sprungs. Sie läuft einmal je
`yy_reduce`-Aufruf, nicht je Befehl — und `yy_reduce` ist nicht die
heiße Schleife von SQLite, sondern der Parser, der einmal je Anweisung
läuft.

## Warum nicht einfach MAX_DEPTH hochsetzen

Das wäre eine Änderung am Compiler. Der Auftrag sagt: Vorschläge für
Firn gehören in den Bericht, gebaut wird hier nicht am Compiler.
Und der Verteiler ist ohnehin die bessere Form — er erzeugt flachen,
schnell zu übersetzenden Code statt 276 verschachtelter Rahmen.
