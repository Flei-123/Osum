# Runde K16 — der Übersetzer läuft auf dem System selbst

**Zweig:** `k16-selfhost` · **Abnahme:** Abschnitt 22 von `./test.sh`
(`tools/k16/run.sh`) · **Nummernvorrat:** kdata `0x49000..0x4C000`,
Systemaufrufe `1900..1999`, `test.sh`-Abschnitt 22, Logbuch hier,
Testläufer in `tools/k16/`.

---

## Der Satz, um den es geht

**Osum hat auf sich selbst ein Firn-Programm übersetzt, gebunden und
ausgeführt — und was dabei herauskam, ist Oktett für Oktett dasselbe,
was derselbe Übersetzer auf Linux aus derselben Quelle macht.**

Der Mitschnitt, wörtlich, aus dem seriellen Anschluss der Maschine:

```
osum$ firnc probe.fi > /probe.s
elf: seg 5 v=0x40100000 f=0x317000 filesz=1463095 memsz=1463095 w=0 x=1
elf: seg 4 v=0x40266000 f=0x47e000 filesz=151737 memsz=151737 w=0 x=0
elf: start 4 entry=0x401000e8 ustack=0x4007f000 kstack=0x306000 bytes=1614832 pages=396
osum$ firnc -> 0
osum$ fas /probe.s -o /probe
osum$ fas -> 0
osum$ /probe
osum hat mich uebersetzt
osum$ /probe -> 42
```

Und danach, auf dem Wirt, aus dem Plattenabbild zurückgelesen:

| Vergleich | Ergebnis |
|---|---|
| `.s` von Osum ↔ `.s` vom Wirt | **zeichengleich**, 14.909 Oktette |
| ELF von Osum ↔ ELF vom Wirt | **zeichengleich**, 8.192 Oktette |

Das ist der Fixpunktgedanke aus Firns Runde 31, eine Ebene höher: dort
war es *derselbe Übersetzer auf demselben System*, hier ist es
*derselbe Übersetzer auf zwei Systemen*.

---

## 1. Die Zahl, die alles entschieden hat

Ein vollständiger x86-64-Assembler ist ein Lebenswerk. Der Übersetzer
braucht keinen. Gemessen über alle Programme dieses Userlands **und**
über `firnc1` selbst — 1.533.513 Zeilen Assemblertext:

| | |
|---|---:|
| verschiedene Mnemoniken | **58** |
| verschiedene Paare aus Mnemonik und Operandenform | **96** |
| Direktiven | **8** |
| Speicherausdrücke | **4** (`[reg]`, `[reg+N]`, `[rbp-N]`, `[rip + name]`) |

Kein Indexregister, kein Maßstab, kein Segment. Das ist kein Assembler
für x86-64 — das ist ein Assembler für die Sprache, die
`lib/firnc1/codegen.fi` spricht, und deshalb passt er in **eine Datei**
(`kernel/user/fas.fi`, rund 2.400 Zeilen Firn).

Die Häufigkeiten, damit man sieht, wie schief die Verteilung ist:

```
mov      993.790     movabs   127.442     add       66.878
jmp       62.648     lea       45.489     push      29.852
call      23.138     pop       23.082     movzx     19.725
ret       17.183     leave     17.181     cmp       15.123
...
cvtsd2ss       1     movd           1     divsd          1
```

## 2. `fas` — der Assembler und Binder in Firn

**Was fehlte.** `firnc` hört bei einem `.s` auf und ruft dann
`/usr/bin/as` und `/usr/bin/ld`. Auf Osum gibt es die nicht und wird es
nicht geben: zwei Programme aus einem anderen Projekt in einer anderen
Sprache. Solange der Übersetzer sie braucht, kann er auf diesem System
nicht arbeiten, egal wie vollständig der Kernel darunter ist.

**Drei Entscheidungen, die ihn kurz halten:**

1. **Jeder Sprung ist ein `rel32`, jede Verschiebung ein `disp32`.** Ein
   echter Assembler wählt die kürzeste Form und muss dafür iterieren,
   bis sich nichts mehr bewegt. Hier steht jede Befehlslänge nach dem
   ersten Blick fest → **zwei** Durchgänge genügen, nicht *n*. Preis:
   ein paar Prozent größere Programme.
2. **Keine Verschiebungseinträge, kein Objektformat.** Ein Firn-Programm
   ist EINE Übersetzungseinheit; alle Namen darin sind innere Namen.
   Nach Durchgang 1 stehen die vier Abschnittslängen fest, daraus die
   Adressen, und in Durchgang 2 ist jede Marke eine Zahl.
3. **Der Anlauf ist eingebaut.** `--crt NAME` hängt den Text von
   `kernel/user/crt.s` an die Quelle: `_start`, `osum_panic`, die drei
   Signalroutinen und ihre Zähler. Das ist nicht gespart, sondern
   richtig — der Anlauf gehört zum Binder, wie `crt1.o` bei jedem
   anderen Unix, nur dass er hier nachlesbar in der Datei steht.

**Gemessen** (`tools/k16/run.sh`, Teil 1, ohne QEMU):

| Zusage | Zahl |
|---|---:|
| Programme dieses Userlands, die `fas` übersetzt und bindet | **54 von 54** |
| davon gegen `as`+`ld` gehalten: gleiche Ausgabe, gleicher Code | **16 von 16** |

Die 16 laufen mit echten Argumenten und echter Eingabe (`sort`, `grep`,
`wc`, `head`, `tail`, `uniq`, `cut`, `tr`, `seq` …) und ihr ganzer
Mitschnitt wird Oktett für Oktett verglichen — nicht „ist nicht
abgestürzt".

**Gegenproben:** ein unbekannter Befehl bricht mit Zeilennummer *und*
dem Wort ab; eine Quelle ohne `_start` bricht ab; ein Sprung auf einen
Namen, den es nicht gibt, bricht ab. Und die Gegenprobe zur Gegenprobe:
dieselbe Quelle ohne den Fehler läuft und gibt 5 zurück.

## 3. Was im Kern gefehlt hat — vier Löcher, vier Zahlen

Der Auftrag war ausdrücklich: Lücken **im Kern** schließen, nicht im
Übersetzer umgehen. Es waren vier, und jede hat eine gemessene Zahl
hinter sich.

### 3a. Der Argumentblock lag nicht auf dem Stapelzeiger

`firnc` erzeugt für ein `fn main` sein eigenes `_start`:

```
_start:
    xor rbp, rbp
    mov rdi, rsp        <- Linux: argc liegt AUF dem Stapel
    and rsp, -16
    call _F1.main
```

Osum legte den Block an `ARGS_BASE` und den Stapelzeiger 16 Oktette
darunter. Ein Programm, das der **unveränderte** `firnc` gebaut hat,
fand seine Argumente also nicht. Und der Block, den `elf.write_args`
seit Runde K1 baut, hat *genau die Form von Linux*: argc, dann die
Zeiger, dann eine Null — `tools/k11/hostcrt.s` nutzt das seit K11 in die
andere Richtung. Es fehlten 16 Oktette.

`kernel/elf.fi`: `T_USTACK = proc.ARGS_BASE` statt `ARGS_BASE - 16`.
Die 52 Programme mit `crt.s` merken nichts davon (sie lesen rdi);
geändert hat sich eine Zahl in der Startzeile, und
`tools/osum/run.sh` ist mitgezogen.

### 3b. Der Stapel war 28 KiB groß und wuchs nicht

`firnc` ist auf Osum daran gestorben: `#PF` bei `cr2=0x3fff9348`, also
**31.928 Oktette unter dem Stapelboden** — ein einziger Rahmen von
`firnc1` ist so groß.

Gemessen auf dem Wirt mit `setrlimit(RLIMIT_STACK)`:

| | |
|---|---:|
| `firnc1` braucht Stapel für eine Quelle ohne Einbindungen | **90 KiB** |
| dasselbe für eine Quelle mit `import ulib` | **256 KiB** |
| Osum hatte | 28 KiB |
| Osum hat jetzt | **504 KiB** |

`ARGS_BASE` ist von `0x40008000` auf `0x4007F000` gezogen, `BRK_BASE`
von `0x40020000` auf `0x40080000`. Dazwischen liegen 504 KiB, und die
Seiten darin **werden nicht im Voraus genommen** — hätte `space_build`
126 Rahmen je Prozess reserviert, wäre jede Rahmenzählung dieses
Projekts eine andere. Sie kommen bei Bedarf: `proc.grow_stack`,
ausgelöst vom Seitenfehler, so wie es jedes Unix macht.

Bedingungen, eng gefasst, damit nicht jeder Programmierfehler zu einer
stillen Speicherzuteilung wird: Adresse zwischen `STACK_FLOOR` und
`ARGS_BASE`, Seite **nicht** vorhanden, Prozess ist ein Nutzerprozess.
Was *nicht* geprüft wird: ob die Adresse in der Nähe von rsp liegt.
Linux erlaubt 64 KiB darunter; `firnc1` hat Rahmen von über 31 KiB, und
die genaue Grenze zu raten wäre schlechter, als den Bereich als Ganzes
zu nehmen.

**Gegenprobe:** `nostackgrow` auf der Kernel-Befehlszeile. Damit stirbt
der Übersetzer wieder an einem Seitenfehler, der Zähler `stackgrow`
bleibt bei **0**, und nichts wird übersetzt. Im Regellauf entstehen
**38** Seiten.

### 3c. Das Abbildfenster war 1 MiB groß

`firnc1`, für Osum gebunden: 1.462.583 Oktette Text + 151.737 Oktette
Konstanten = **1.618.392 Oktette**. Das Fenster `0x40100000..0x401FFFFF`
war 1 MiB.

`proc.IMAGE_END` steht jetzt bei `0x40400000` — drei 2-MiB-Kacheln statt
einer halben. Dafür kann das private Seitenverzeichnis eines Prozesses
seit dieser Runde **mehrere Seitentabellen** tragen (`proc.pt_for`, bei
Bedarf angelegt, mit dem Prozess wieder freigegeben).

**Eine echte Grenze, ausgesprochen statt verschwiegen:** `fb.USER_BASE`
ist `0x40200000`, also genau die zweite Kachel. Ein Prozess kann von
hier an ein Abbild über 1 MiB haben **oder** den Rahmenpuffer abbilden,
nicht beides. `map_huge` sagt das klar (0 zurück, `mmap` daraus
`-ENOMEM`) statt die beiden stillschweigend zu verwechseln. Kein
Programm dieses Systems will beides.

### 3d. Die Halde war 832 KiB groß

`firnc1` braucht insgesamt **3 MiB Adressraum** (gemessen mit
`setrlimit(RLIMIT_AS)`, Halbierungssuche) — davon rund 1 MiB Halde. Die
alte Halde zwischen `brk` und `MMAP_TOP` waren 851.968 Oktette, und
nach 3b sind es 458.752.

Neu ist die **große Arena**: 6 MiB zwischen `proc.BIG_FLOOR`
(`0x40600000`) und `proc.BIG_TOP` (`0x40C00000`), in drei Kacheln des
privaten Seitenverzeichnisses, die es vorher nicht gab. Sie wird erst
angefasst, wenn die alte Halde voll ist — **additiv**, damit die
Adressen, die `tools/posix/run.sh` seit Runde K4 misst, dieselben
bleiben.

**Gegenprobe:** `nobigmem`. Ohne die Arena kommt der Übersetzer nicht
durch, und nichts wird übersetzt.

### 3e. Und eine Zahl, die nichts mit dem Übersetzer zu tun hat

Der **Kernelstapel** stand beim Bau dieser Runde bei 16.208 von 16.384
Oktetten — 176 Oktette Luft. Der Ausleger (unten) hatte seine
Ortsvariablen zuerst in `elf.build`, und die stehen während `load` →
`fs.read_at` → Plattentreiber, dem tiefsten Punkt des ganzen Kernels,
noch da. Damit war der Stapel voll (16.384 von 16.384) und der
Stufe-1-Kernel starb.

Die Arbeit steht jetzt in `elf.aufloesen`, einer Funktion, die **vorher
fertig** ist; was sie hinterlässt, sind zwei Zeiger in kdata. Gemessen
danach: **15.328** (Stufe 0) und **15.240** (Stufe 1). Das ist keine
Geschmacksfrage, das war ein Absturz.

## 4. Die Schicht unter dem Doppelklick (für Runde K15)

`kernel/ftype.fi` — **eine** Tabelle im Kern, 32 Sätze zu 128 Oktetten:

```
+0   used      +8   action    +16  magoff   +24  maglen
+32  magic[16] +48  ext[16]   +64  prog[48] +112 label[16]
```

`action`: `A_NONE` (0), `A_EXEC` (1, die Datei selbst starten),
`A_OPEN` (2, `prog` starten mit der Datei als Argument).

**Eingebaut sind acht Arten:** `elf` (magisch `7F E L F`, A_EXEC),
`script` (magisch `#!`, A_EXEC), `.fi` → `/bin/firun`, `.s` →
`/bin/fas`, `.sh` → `/bin/sh`, `.txt`/`.md`/`.log` → `/bin/edit`.

**Zwei Wege zur Art, und der Inhalt geht vor.** Das ist eine
Entscheidung, die man messen kann: `/tarn.fi` heißt wie Firn-Quelltext
und *ist* ein ELF — es wird als `elf` eingeordnet. Der Fall ist der
einzige, an dem sich die beiden Wege *unterscheiden*, und eine Regel,
die nie zu einem Widerspruch führt, ist keine Regel.

### Die Schnittstelle, die K15 nur aufrufen muss

| Nummer | Aufruf | Bedeutung |
|---:|---|---|
| 1900 | `ftype(pfad, aus, len)` | Art einordnen; Satz nach `aus`. Rückgabe: Platz in der Tabelle, `-ENOENT` (Datei fehlt), `-ENOEXEC` (Art unbekannt) |
| 1901 | `fopen(pfad, argv, argc)` | **das ist der Doppelklick.** Rückgabe: Prozessnummer, oder negativ — und dann hat **nichts** gestartet |
| 1902 | `flist(nr, aus, len)` | die Tabelle durchgehen (für ein Menü „Öffnen mit"), `-ENOENT` hinter dem letzten |
| 1903 | `freg(satz, len)` | einen Eintrag setzen oder ersetzen; `len` muss genau 128 sein, sonst `-EINVAL` |

K15 braucht für einen Doppelklick **einen** Aufruf: `fopen`. Was
zurückkommt, ist eine pid — `wait4` darauf gibt den Beendigungscode.
Für ein Kontextmenü: `flist` in einer Schleife, bis `-ENOENT` kommt.
Für „diese Art immer mit …": `freg`.

Der Ring-3-Satz steht ein zweites Mal in `kernel/user/k16.fi` — dasselbe
Verfahren wie bei `mkfs.py` und dem Plattenformat: zwei Fassungen, die
auseinanderlaufen, fallen auf; eine Fassung, die falsch ist, fällt nie
auf.

**Gemessen** (Teil 5 der Abnahme, aus Ring 3): ELF am Inhalt erkannt ·
`.fi` an der Endung · `/tarn.fi` als ELF (Inhalt vor Name) · `.txt` →
`/bin/edit` · 8 Einträge in der Tabelle · `freg` wirkt wirklich (danach
wird `/fremd.zzz` eingeordnet, vorher nicht) · `fopen` auf ein Programm
gibt eine pid.
**Gegenproben:** unbekannte Art → `-ENOEXEC` · Datei fehlt → `-ENOENT` ·
hinter dem letzten Eintrag → `-ENOENT` · Satz falscher Länge →
`-EINVAL` · `fopen` auf einen Pfad, den es nicht gibt, startet **nichts**.

## 5. Der Ausleger (`#!`)

In `execve` im Kern, nicht in der Shell — denn `elf.build` ist die
Stelle, durch die **jeder** Programmstart dieses Systems geht: die
Shell, `exec` aus Ring 3, der Doppelklick von K15, ein Programm, das ein
anderes startet.

Die Regel ist Linux' Regel, wortwörtlich:

```
Datei:   #!/bin/sh -e
Aufruf:  execve("/tmp/x.sh", ["x.sh", "a"])
wird zu: execve("/bin/sh", ["/bin/sh", "-e", "/tmp/x.sh", "a"])
```

Das ursprüngliche `argv[0]` fällt weg. Höchstens **ein** Argument wird
aus der Zeile genommen; alles Weitere darin ist ein Wort dieses einen
Arguments — deshalb geht `#!/usr/bin/env python3` und
`#!/usr/bin/env -S a b` nicht.

**Gemessen:** `/s1.sh` mit `#!/bin/echo ausleger` gibt wörtlich
`ausleger /s1.sh` aus — Ausleger, sein Argument, der Pfad des Skripts,
in dieser Reihenfolge, ohne das alte `argv[0]`.
**Gegenproben:** `#!` im Kreis (`/r1.sh` → `/r2.sh` → `/r1.sh`) endet
nach vier Stufen mit `-ELOOP` (40) und startet nichts · eine Datei ohne
`#!` und ohne ELF-Kopf bleibt `-ENOEXEC`.

## 6. Der Doppelklick auf eine `.fi`

`/bin/firun` ist das Programm, das in der Tabelle für `.fi` steht. Drei
Schritte: `firnc quelle.fi > quelle.s` (Deskriptor 1 in die Datei
umgelenkt), `fas quelle.s -o quelle`, dann `quelle` starten. Der
Rückgabewert sagt die Wahrheit: 0/N vom Programm, **70** vom
Übersetzer, 71 vom Assembler, 72 wenn sich das Fertige nicht starten
ließ.

**Gemessen, beide Richtungen:** `fopen("/probe.fi")` übersetzt, startet
und gibt **42** durch (den Code, den die Quelle nennt).
`fopen("/kaputt.fi")` endet mit **70** — und *nicht* mit 0.

---

## Was NICHT geht — die Grenzen, ausdrücklich

1. **`firnc1` sagt nicht, WO der Fehler ist.** Gemessen am 26.08.2026:
   bei einem Fehler schreibt `firnc1` **keine Zeile** — nicht auf
   Deskriptor 1, nicht auf Deskriptor 2. Es gibt einen Code zurück und
   sonst nichts. (`firnc0`, der Rust-Übersetzer, schreibt eine
   vollständige Meldung mit Zeile, Spalte und unterstrichenem Wort —
   aber der läuft auf Osum nicht.) `/bin/firun` übersetzt den Code
   deshalb in einen Satz („der Übersetzer lehnt ab, Code 1 — im
   Quelltext steht ein Fehler"). Das sagt **welcher Art** der Fehler
   ist, nicht **wo** er steht. Das ist mehr als nichts und weniger als
   genug, und es zu beheben ist eine Runde im Firn-Repo, nicht hier.
2. **`fas` kann kein Gleitkomma.** `movsd`, `mulsd`, `divsd`,
   `cvtsi2sd`, `cvtsd2ss`, `movd` werden ausdrücklich **abgelehnt** —
   mit Zeilennummer, nicht stillschweigend übersprungen. `firnc1`
   erzeugt sie nur für `f64`-Rechnung; kein Programm dieses Userlands
   hat eine, aber `firnc1.fi` selbst hat welche. **Folge: `firnc` kann
   sich auf Osum NICHT selbst übersetzen.** Der Fixpunkt dieser Runde
   ist „Osum übersetzt ein Programm", nicht „Osum übersetzt seinen
   Übersetzer". Was dafür fehlt, ist genau ein SSE-Encoder in
   `fas.fi` — sechs Formen, nachgezählt.
3. **Die Platte ist zu klein für mehr.** OFS hat eine Bitmap von **einem**
   Block: 4096 Bits = 4096 Blöcke = **2 MiB** je Platte, harte Grenze.
   `firnc` allein sind 1,6 MiB. Das Abnahmeabbild hat danach 146 Blöcke
   frei. Für einen Übersetzerlauf über eine Quelle mit Einbindungen
   müssten auch noch die 25 Module von `lib/firnc1/` (rund 1,2 MiB) auf
   die Platte — das geht erst mit einer mehrblockigen Bitmap. Das ist
   eine eigene Runde und berührt `mkfs.py`, `kernel/fs.fi` und
   Abschnitt 3 von `tools/posix/run.sh`.
4. **Nur eine Quelle ohne `import`.** Aus 3 folgt: die Quelle, die Osum
   auf sich selbst übersetzt, kommt ohne Einbindungen aus. Der
   Übersetzer *könnte* mehr — der Adressraum reicht (256 KiB Stapel,
   gemessen), die Platte nicht.
5. **Ein Prozess: großes Abbild ODER Rahmenpuffer.** Siehe 3c.
6. **`fas` wählt nie die kurze Form.** Jeder Sprung ist ein `rel32`,
   jede Verschiebung ein `disp32`. Die Programme sind dadurch messbar
   größer als die von `ld` — bewusst, siehe oben.
7. **Der Doppelklick selbst gehört Runde K15.** Diese Runde liefert die
   Tabelle und das Starten; ein Dateiverwalter, der `fopen` aufruft, ist
   dort.

## Was diese Runde NICHT angefasst hat

Der Weg über den Linux-Wirt bleibt vollständig bestehen:
`vendor/firn/fetch-firnc.sh` baut `firnc0` und `firnc1` weiter wie bisher,
`tools/build-kernel.sh` baut den Kernel weiter mit ihnen, und die
Abschnitte 1 bis 18 der Abnahme messen unverändert dasselbe. Nichts
wurde gelöscht, bevor der Ersatz lief — und der Ersatz *ersetzt* auch
nichts, er kommt daneben.

## Vier Fehler, die diese Runde selbst gemacht hat

Sie stehen hier, weil der nächste, der an dieser Stelle arbeitet, sie
sonst noch einmal macht.

1. **Der Kernelstapel lief über, und zwar unsichtbar.** Der Ausleger
   hatte seine Ortsvariablen zuerst in `elf.build`. Der Stufe-0-Kernel
   lief damit durch (16.336 von 16.384 Oktetten), der Stufe-1-Kernel
   nicht (16.384 von 16.384) — und was man sah, war „QEMU exit code 63"
   in Abschnitt 9, ohne jeden Hinweis auf den Stapel. `firnc0` und
   `firnc1` rechnen Rahmengrößen leicht verschieden aus; wer nur mit
   Stufe 0 misst, sieht so etwas nicht.
2. **Die neue Stapelregel hat eine Gegenprobe von Runde 62
   kaputtgemacht.** `uprog.u_steal` fasst absichtlich `0x40010000` an
   und muss dafür einen `#PF` bekommen. Diese Adresse liegt seit dieser
   Runde *im* Stapelbereich — ohne die Bedingung „nur unterhalb des
   eigenen `T_USTACK`" wäre aus der Gegenprobe eine stille
   Speicherzuteilung geworden, und die Runde hätte eine Zusage von
   damals zerstört, ohne es zu merken. Eine neue Eigenschaft im Kern
   kann eine alte Gegenprobe entwerten; danach muss man suchen.
3. **Der Zeichenvergleich schlug fehl, und schuld war ein Pfadname.**
   `firnc` legt `panic: … at <pfad>:<zeile>:<spalte>` nach `.rodata`.
   Osum hatte `t.fi`, der Wirt `/tmp/k16t.fi` — 8 Oktette Unterschied im
   Text, 8 in `p_filesz`, und ein „NEIN" im Vergleich. Mit demselben
   Argument auf beiden Seiten: zeichengleich. Genau einer der
   „üblichen Verdächtigen", und er ist wirklich der erste, der auftritt.
4. **Ein Programm für Osum hat das gleichnamige für den Wirt
   überschrieben.** `bau_osum fas` schrieb nach `$TMPD/fas` — derselbe
   Name wie der Assembler für den Wirt, den Teil 4 danach noch braucht.
   Auf dem Wirt gestartet gab dieser dann seine Gebrauchsanweisung aus,
   und der Vergleich hatte nichts zu vergleichen. Die Osum-Programme
   liegen jetzt in `$TMPD/o/`.

## Die Zahlen der Abnahme

| | |
|---|---:|
| Zusagen in Abschnitt 22 | **64**, 0 Fehler |
| Programme, die `fas` bindet | 54 von 54 |
| davon gegen `as`+`ld` gehalten | 16 von 16 gleich |
| Kernelstapel, Stufe 0 / Stufe 1 | 15.328 / 15.240 von 16.384 |
| Stapelseiten im Übersetzerlauf | 38 |
| `firnc` für Osum | 1.618.392 Oktette, 396 Seiten |
| Übersetzter Assemblertext | 14.909 Oktette, zeichengleich |
| Erzeugtes Programm | 8.192 Oktette, zeichengleich |

Und die ganze Abnahme, `./test.sh` im Osum-Repo:

```
ALLE 19 ABSCHNITTE BESTANDEN, 1550 Zusagen, 0 Fehler
```

1486 Zusagen standen vorher, 64 kommen hinzu — es ist keine
verschwunden.

## Die Dateien

| Datei | was |
|---|---|
| `kernel/ftype.fi` | die Tabelle „Dateiart → womit öffnen" (neu) |
| `kernel/user/fas.fi` | Assembler und Binder in Firn (neu) |
| `kernel/user/firun.fi` | `.fi` übersetzen und starten (neu) |
| `kernel/user/k16.fi` | der Ring-3-Selbsttest dieser Runde (neu) |
| `kernel/elf.fi` | Ausleger (`#!`), Argumentblock auf dem Stapelzeiger, Argumentseite anlegen |
| `kernel/proc.fi` | mehrere Seitentabellen je Prozess, `grow_stack`, `IMAGE_END`, `BIG_*` |
| `kernel/sys.fi` | vier Aufrufe (1900–1903), die große Arena |
| `kernel/trap.fi` | der Seitenfehler lässt den Stapel wachsen |
| `kernel/kstate.fi` | `K16_OFF` 0x49000, `STACKGROW`, `M_NOBIG`, `M_NOSTACK` |
| `kernel/errno.fi`, `lib/libc/*` | `E_LOOP`, die vier Nummern (beide Listen) |
| `tools/k16/run.sh` | Abschnitt 22 der Abnahme |
| `tools/kernel/memmap.py` | K16 eingetragen |
