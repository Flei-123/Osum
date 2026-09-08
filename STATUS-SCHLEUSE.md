# RUNDE SCHLEUSE — fremde Software auf OrientOS, über WebAssembly

Zweig `schleuse`, Basis `merge8` @ c0f7151, Arbeitsbaum `/root/osum-schleuse`.
Schritt 3 der Liste in Abschnitt 7 von `/root/osum-roadmap/FREMDSOFTWARE.md`.

**Ziel:** zum ersten Mal läuft auf Osum ein Programm, das niemand für Osum
geschrieben hat.

---

## Schritt 0 — die Wegentscheidung, mit Messung

Zwei Wege standen zur Wahl. Beide wurden klein angeprobt, bevor einer gebaut wurde.

### (b) wasm2c — GEPRÜFT UND VERWORFEN, mit Begründung

Der Gedanke: `wasm2c` (aus wabt) übersetzt das WASM-Modul auf dem Bauserver nach C,
das übersetzt dann unser eigener Compiler — dann bräuchten wir gar keine Laufzeit.

Der Haken, und er ist tödlich: **Osum baut mit `firnc`, nicht mit C.** Es gibt im
ganzen Baum keinen C-Compiler, der ein Osum-Binärformat erzeugt. Damit der wasm2c-Weg
trüge, müsste eines von zweien gelten:

1. **C nach Firn übersetzen.** Abschnitt 6 der FREMDSOFTWARE.md hat das schon
   ausgemessen und als Sackgasse eingetragen: c2rust ist der ausgereifteste
   Transpiler überhaupt und produziert 26,5–99 % `unsafe`, **79 % der Roh-Pointer**
   lassen sich nicht überführen; LLM-Übersetzung liegt bei **22 % Erfolgsquote**
   (CRUST-Bench). Und wasm2c-Ausgabe ist der schlimmste denkbare Eingang für so
   etwas: generierter C-Code, der fast nur aus Pointer-Arithmetik auf einem
   linearen Speicher besteht — genau die 79 %, die nicht gehen.
2. **Einen C-Compiler nach Osum bringen.** Das ist ein eigenes, größeres Projekt
   als der Interpreter, den wir stattdessen bauen. Es verschiebt das Problem, es
   löst es nicht.

Dazu kommt: wasm2c erzeugt **pro Modul** neuen C-Code. Jedes neue fremde Programm
wäre ein neuer Übersetzungslauf auf dem Bauserver plus ein neues Binärformat —
Osum könnte nie ein `.wasm` nehmen, das ihm jemand hinlegt. Das ist das Gegenteil
einer Schleuse.

**Entscheidung: (b) fällt weg.** Nicht aus Geschmack, sondern weil die Kette an
einer Stelle reißt, die in der Recherche schon als gerissen vermerkt war.

### (a) Eigene WASM-Laufzeit in Firn — GEWÄHLT

Ein Interpreter nach dem Muster von wasm3, aber nur der Kern: Modul-Parser für die
Binärform, minimale Validierung, Ausführung der Kernbefehle, linearer Speicher,
Tabellen, Importe. Alles in Firn, ring 3, keine fremde Toolchain zur Laufzeit.

**Warum das trägt — gemessen, nicht geschätzt.** Der eigentliche Zweifel war, ob
die Bauserver-Seite überhaupt echte fremde WASM-Programme liefern kann. Sie kann:

| Messung | Ergebnis |
|---|---|
| `rustup target add wasm32-wasip1` | **geht**, Ziel installiert (rustc 1.99.0-nightly) |
| Rust-Hello-World nach `wasm32-wasip1` | **übersetzt**, 2 179 965 Oktett roh |
| dasselbe mit `-C debuginfo=0 -C strip=symbols` | **47 364 Oktett** |
| `clang --target=wasm32` | vorhanden (Debian clang 14), erzeugt gültiges `.wasm` |
| llvm-objcopy für wasm | vorhanden unter `/opt/emsdk/upstream/bin` |

Und die Zahl, die die ganze Runde trägt — die **Importe** des Rust-Hello-World,
aus dem Modul selbst ausgelesen (Sektion 2):

```
IMPORTE: 4
    wasi_snapshot_preview1 :: environ_get
    wasi_snapshot_preview1 :: environ_sizes_get
    wasi_snapshot_preview1 :: fd_write
    wasi_snapshot_preview1 :: proc_exit
```

**Vier.** Nicht 46, nicht 1200. Die Sektionsaufteilung desselben Moduls:

```
  section  1 type      size 103
  section  2 import    size 150
  section  3 function  size 191
  section  4 table     size 5
  section  5 memory    size 3
  section  6 global    size 14
  section  7 export    size 33
  section  9 element   size 85
  section 10 code      size 39525
  section 11 data      size 7222
  section  0 custom    size 30186 + 22655 + 579324 + 977696 + ... (Debug-Info)
```

Der ausführbare Teil ist **~40 KB Code**; die 2,1 MB waren Debug-Info in
Custom-Sections, die ein Interpreter ohnehin überspringt.

**Kosten des gewählten Weges, ehrlich:** ein Interpreter ist laut wasm3-Messung
~11,5× langsamer als nativ. Das ist der Preis, und er wird in dieser Runde
gemessen statt behauptet (Abschnitt Tempo).

---

## Regression — Vorher/Nachher

(wird eingetragen, sobald die Läufe durch sind)

## WASI preview1 — was da ist und was fehlt

(wird eingetragen)

## Fallstricke

(wird eingetragen)
