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

## 1. Stand der Arbeit

Läuft. Zahlen folgen in dieser Datei, sobald gemessen.

---

## 2. Firn-Syntax, die beim Erzeugen zählt

Gelernt beim Bauen (Stufe-0-`firnc`), damit der Erzeuger nichts Falsches ausgibt:

- **Kein `mut`.** `let x: u64 = 0` ist bereits veränderlich; `let mut` ist ein
  Syntaxfehler. `var` steht für Strukturen/Felder.
- **Feldlängen sind Literale.** `[u8; MAX]` mit `MAX` als Konstante wird
  abgelehnt (schon Fallstrick 8 aus SCHLEUSE).
- **`main` hat die Form `fn main(start: u64) -> i32`** im Profil `app`.
