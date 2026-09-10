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

---

# Nachtrag (08.09.2026): Tiefe kostet firnc **exponentiell**

Der Verteiler war ursprünglich nur gegen die Parsergrenze von 200
Ebenen gedacht. Beim ersten vollständigen `firnc`-Lauf über
`sqlite.fi` zeigte sich ein zweites, viel härteres Problem.

## Der Befund

`firnc` hing über eine Stunde in `escape::Pass::stmt` — einem
Durchgang der semantischen Analyse, der sich **nicht** abschalten
lässt (`--no-pass` kennt ihn nicht, er gehört nicht zum Optimierer).

Gemessen an einem minimalen Programm (nur geschachtelte
`while true`, ein Statement innen):

| Ebenen | firnc |
|---|---|
| 22 | 5 s |
| 24 | 22 s |
| 25 | 41 s |
| 26 | 81 s |

**Faktor ~2 je Ebene** — also `2^Tiefe`. Und zusätzlich **linear in
der Zahl der Anweisungen**:

| Aufbau | firnc |
|---|---|
| Tiefe 20, 50 Anweisungen je Ebene | 49 s |
| Tiefe 20, 100 Anweisungen je Ebene | 90 s |

Kostenmodell also `2^Tiefe · Anweisungen`. Bei den ursprünglichen
67 Ebenen von `f564` ist das astronomisch — der Bau wäre nie fertig
geworden.

## Was daraus folgte

Drei Änderungen an `wasm2firn.py`:

1. **Türme sind schachtelbar.** `im_turm` war ein einziger Schalter:
   sobald ein Turm lief, blieb jeder Turm *innerhalb* davon
   ungeflacht. `f564` hatte dadurch 66 `while true` am Stück.
2. **Schleifen zählen mit.** SQLite schachtelt `block` und `loop` im
   Wechsel (`f878`: 30 Ebenen, 6 davon `loop`). Zählte `turm_messen`
   nur `block`, blieben die Läufe zu kurz zum Flachlegen. Im
   Verteiler ist eine Schleifenebene genauso billig: ein `br` dorthin
   heißt „wieder von vorne", also `fall = 0`.
3. **`TIEFE_DECKEL = 20`.** Ein Verteiler kostet selbst zwei Ebenen
   (`while true` + `if fall == 0`), lohnt sich also erst ab drei
   Blöcken. Unterhalb von Ebene 20 wird nur der klassische lange Turm
   (> `TURM_GRENZE` = 8) flachgelegt, ab Ebene 20 schon jeder Lauf ab
   drei Blöcken.

Gemessener Sweep über `TIEFE_DECKEL` (max. Tiefe in `sqlite.fi`):

| Deckel | 8 | 12 | 16 | 18 | **20** |
|---|---|---|---|---|---|
| max. Tiefe | 43 | 35 | 32 | 27 | **25** |

**Ergebnis: von 67 auf 25 Ebenen.** Nur noch drei Funktionen liegen
über 22, eine davon (`w_fd_readdir`) ist Handarbeit aus
`laufzeit.fi.in` und hat mit dem Übersetzer nichts zu tun.

## Vorschlag an Firn

Der `escape`-Durchgang sollte nicht exponentiell in der
Schachtelungstiefe sein. Ein einfaches Memo je Anweisungsknoten (oder
ein Pfad-Set statt wiederholter `memcmp`-Vergleiche) würde das auf
linear bringen. Der Rückverfolgungs-Stapel zeigt den heißen Pfad:
`escape::Pass::stmt` → `escape::Pass::path` → `memcmp`.

## Und ein echter Fehler im Verteiler

Beim Bau der Prüfung `pruefung/turm.wat` (12 Blockebenen, aus jeder
Ebene ein eigener Ausgang, hinter jedem `end` ein eigener Rest) fiel
auf: **jeder Fall endete mit `break`** — und das verließ den *ganzen*
Verteiler. Fällt der Code aber unten aus einer Blockebene heraus,
müssen die Reste **aller** weiter außen liegenden Ebenen noch laufen.
Deuter und AOT wichen bei 10 von 12 Ebenen ab.

Richtig ist `fall = <nächster Fall>; continue`. Der Fehler war so
lange unsichtbar, weil `TURM_GRENZE = 8` gilt und keine Prüfung
bis dahin einen Turm dieser Länge enthielt.
