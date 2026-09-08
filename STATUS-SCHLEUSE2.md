# RUNDE SCHLEUSE-2 — WASM VORAB nach Firn übersetzen (AOT)

Zweig `schleuse2`, Basis `schleuse` @ 5ce3f99, Arbeitsbaum `/root/osum-schleuse2`.
Regel 6 aus `/root/osum-roadmap/FREMDSOFTWARE.md`: 90 % für 10 %.

**Der Gedanke:** SCHLEUSE hat einen Deuter gebaut — 158× langsamer als nativ.
Statt den Bytecode zur Laufzeit zu deuten, übersetzen wir ihn auf dem Bauserver
EINMAL nach Firn-Quelltext und bauen ihn mit `firnc` zu einem gewöhnlichen
Osum-Programm. Das ist das wasm2c-Prinzip, und die Einwände, die in SCHLEUSE
gegen C→Firn galten, gelten hier nicht: WASM hat keinen Präprozessor, kein
undefiniertes Verhalten, ~170 Befehle und einen linearen Speicher.

---

## 0. DER FUND, DER DIE RUNDE ENTSCHEIDET — Firn kann umlaufend rechnen

Der Auftrag nannte das als **Kernproblem**: WASM rechnet umlaufend, Firn bricht
bei Überlauf ab. SCHLEUSE hat dafür `wadd`/`wsub`/`wmul` von Hand gebaut
(`kernel/app/wasm.fi`, Zeile 2484–2512) — `wmul` rechnet über vier 32-Bit-Hälften.

**Es war nie nötig.** `firnc` Stufe 0 kennt umlaufende Operatoren, sie stehen in
`/root/firn/SPEC.md` (~Zeile 1238) und sind umgesetzt, nicht nur geplant:

```
+%  -%  *%     umlaufend, NIE geprüft, in jeder Optimierungsstufe
+|  -|  *|     sättigend
```

### Gemessen, nicht geglaubt — der Assembler

`firnc --profile=app --emit=asm` über vier Funktionen:

| Firn | erzeugter Assembler | Prüfung |
|---|---|---|
| `return a + b` | `mov r10,r8` · `add r10,r9` · **`jc .Lchksite`** · Panik-Block | ja |
| `return a +% b` | **`lea r10,[r8+r9]`** | **keine** |
| `return a * b` | `imul` + `jc` + Panik-Block | ja |
| `return a *% b` | **`imul r10,r9`** | **keine** |

Eine einzige Anweisung, kein Sprung, kein Panik-Pfad.

### Korrektheit, gegen Python gegengerechnet

| Ausdruck | Firn | Python | |
|---|---|---|---|
| `(0 -% 1) & 0xffffffff` | 4294967295 | 4294967295 | ✓ |
| `(4294967295 +% 1) & 0xffffffff` | 0 | 0 | ✓ |
| `(123456789 *% 987654321) & 0xffffffff` | 4227814277 | 4227814277 | ✓ |
| `0 -% 1` (u64) | 18446744073709551615 | 18446744073709551615 | ✓ |

**Antwort auf Auftrag Punkt 2: Firn braucht KEINE Spracherweiterung.** Die
Operatoren sind da, sie sind billig, sie sind richtig. Ein Vorschlag für eine
Erweiterung erübrigt sich — der ausführliche Befund steht in Abschnitt 2.

### Nebenfund für den Deuter

`wadd`/`wsub`/`wmul` in `wasm.fi` sind damit überflüssig und teuer: jeder
`i32.add` des Gastes ging durch einen Funktionsaufruf mit Verzweigung, wo ein
`lea` gereicht hätte.

---

## 1. TEMPO — die Zahl, um die es ging

Derselbe Bench wie in SCHLEUSE: `prim.wasm` (Rust, Primzahlen per
Probedivision), Grenze 500000. **Alle drei liefern 41538** — sonst wäre der
Vergleich wertlos.

| | Zeit | Faktor gegen nativ |
|---|---|---|
| Firn/Rust **nativ** | 0,100 s | **1,00×** |
| **AOT (`wasm2firn` + `firnc`)** | **0,214 s** | **2,14×** |
| Deuter aus SCHLEUSE | 15,99 s | 159,9× |

**Der AOT-Weg ist 74,7× schneller als der Deuter** und liegt bei **2,14×**
gegen nativ. Das Ziel war „unter 5×"; `wasm2c` selbst erreicht ~2,0×, wir
liegen also auf dem Stand der Technik.

Damit ist die These der Runde belegt: Die 158× des Deuters kamen aus dem
**Deuten** (Oktett lesen, verteilen, Stapel im Speicher bewegen) plus Firns
Prüfarithmetik — nicht aus etwas Unvermeidlichem an WASM.

### Übersetzungszeiten

| Schritt | Zeit |
|---|---|
| `wasm2firn` für `sqlite.wasm` (1,34 MB → 664 310 Zeilen Firn) | **4,6 s** |
| `firnc` für `hallo` (1240 Zeilen) | 0,4 s |
| `firnc` für `hello2` (27 046 Zeilen) | 123,7 s |
| `firnc` für `prim` (33 900 Zeilen) | 165,2 s |

Der Übersetzer ist **nicht** der langsame Teil — `firnc` ist es.

---

## 2. Firn-Syntax, die beim Erzeugen zählt

Gelernt beim Bauen (Stufe-0-`firnc`), damit der Erzeuger nichts Falsches ausgibt:

- **Kein `mut`.** `let x: u64 = 0` ist bereits veränderlich; `let mut` ist ein
  Syntaxfehler. `var` steht für Strukturen/Felder.
- **Feldlängen sind Literale.** `[u8; MAX]` mit `MAX` als Konstante wird
  abgelehnt (schon Fallstrick 8 aus SCHLEUSE).
- **`main` hat die Form `fn main(start: u64) -> i32`** im Profil `app`.


---

## 2. Das Umlauf-Problem — gelöst, ohne Spracherweiterung

**Der Auftrag nannte das als Kernproblem und fragte, ob Firn eine
Erweiterung bräuchte. Antwort: nein.**

`firnc` Stufe 0 hat `+% -% *%` (umlaufend) und `+| -| *|` (sättigend)
bereits eingebaut. Sie sind in `/root/firn/SPEC.md` (~Zeile 1238)
beschrieben und im Codegenerator umgesetzt — Beleg in Abschnitt 0 dieser
Datei: ein `lea`, kein `jc`, kein Panik-Block.

Damit sieht die Übersetzung so aus:

| WASM | erzeugtes Firn |
|---|---|
| `i32.add` | `(a +% b) & 4294967295` |
| `i32.sub` | `(a -% b) & 4294967295` |
| `i32.mul` | `(a *% b) & 4294967295` |
| `i64.add` | `a +% b` |
| `i32.div_s` | `i32_div_s(a, b)` — mit Nullprüfung → WASM-Falle |

Die 32-Bit-Werte liegen in den unteren 32 Bit einer `u64` und werden nach
jeder Rechnung mit `& 4294967295` beschnitten. Das ist genau der Weg, den
der Auftrag als „billigster korrekter Weg" beschrieben hat — nur dass die
Rechnung selbst ungeprüft ist und nicht durch einen Funktionsaufruf geht.

**Was der Deuter dafür brauchte:** `wadd`/`wsub`/`wmul` als eigene
Funktionen, `wmul` sogar über vier 32-Bit-Hälften. Jeder `i32.add` des
Gastes war ein Aufruf mit Verzweigung. Das ist ein guter Teil der 158×.

### Division ist kein Sonderweg, sondern eine Falle

WASM verlangt bei Division durch Null und bei `INT_MIN / -1` eine **Falle**,
kein stilles Ergebnis. Beides steht in `i32_div_s`/`i64_div_s` der Laufzeit
und endet über `div_falle()` mit einem Abbruch — nicht mit einer Zahl.
