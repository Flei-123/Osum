# STRUKTUR — die Ordnung des Kernbaums

Runde **O-STRUKTUR**, Arbeitsbaum `/root/osum-w-struktur`, Zweig
`struktur2`, abgezweigt von `main` (`7e68da55`). Erhebung vom
17.09.2026.

Justins Wunsch, wörtlich: Osum soll „gut organisiert und strukturiert"
und „modular" sein. Diese Runde **ordnet**, sie baut nichts Neues. Der
Beweis dafür sind die Tests und die Symboltabelle, nicht ein Eindruck.

Alle Zahlen in diesem Dokument sind **gemessen**, mit Werkzeugen, die
unter `tools/struktur/` liegen und die jeder nachrechnen kann.

---

## 0. Die kurze Antwort

| Frage | Antwort |
|---|---|
| Wie viele Dateien hat `kernel/`? | 353 `.fi` — aber nur **137** landen im Abbild |
| Wie groß ist der Kern wirklich? | **171 212 Zeilen** in diesen 137 Dateien |
| Was ist der Rest? | 188 Dateien `kernel/user/`, 15 `kernel/app/` — **eigene Programme**, nicht der Kern |
| Hält der Baum eine Schichtordnung ein? | **899 von 946 Kanten (95,0 %)** ja, **47** nein |
| Gibt es Zyklen? | **Einer**, und er umfasst **93 der 137 Dateien** |
| Was kostet ein Umzug? | **Eine Zeile je Aufrufer.** Keine einzige Aufrufstelle im Rumpf |
| Was verhindert den großen Umbau? | **113 der 126** flachen Dateien werden in `tools/` **mit Pfad** genannt |
| Lässt sich `sys.fi` (14 243 Z.) teilen? | **Heute nicht sauber** — die Begründung steht in Abschnitt 6 |
| Nebenbefund | `tools/server/run.sh` ist **schon auf `main` rot** (4 passed, 13 failed) — Abschnitt 5b |

---

## 1. Was der Kern überhaupt ist

`kernel/` enthält 353 `.fi`-Dateien. Das Kernabbild besteht **nicht**
aus ihnen allen. `tools/build-kernel.sh` übersetzt zwei Wurzeln:

```
firnc -o k.o      kernel/kmain.fi
firnc -o uprog.o  kernel/uprog.fi
```

Firn liest von einer Wurzel aus über `import` den ganzen Baum. Alles,
was von keiner der beiden Wurzeln erreichbar ist, liegt zwar im
Verzeichnis, ist aber **nicht im Abbild**.

`tools/struktur/huelle.py` rechnet das aus:

| Menge | Dateien | Zeilen |
|---|---:|---:|
| gesamt unter `kernel/` | 353 | 318 884 |
| **KERN** (ab `kmain.fi`) | **137** | **171 212** |
| UPROG (ab `uprog.fi`) | 1 | 3 896 |
| AUSSEN (nicht im Abbild) | 215 | 143 776 |

Das AUSSEN verteilt sich auf `kernel/user/` (188 — die Programme:
`ls`, `sh`, `explorer`, `taskbar` …), `kernel/app/` (15),
`kernel/arch/aarch64/` (2, der andere Prozessor) und 10 flache
Gegenfassungen (`gfx-aus.fi`, `wg-aus.fi`, `ext4-aus.fi` …), die
`build-kernel.sh` bei Bedarf an die Stelle des Originals kopiert.

> **Das ist der erste Befund dieser Runde.** Die Aussage „`kernel/` hat
> 137 Dateien mit 168 000 Zeilen" stimmt für den Kern — aber im
> Verzeichnis liegen daneben noch einmal 215 Dateien mit 143 776
> Zeilen, die **keine Kerndateien sind**. Wer den Kern ordnen will,
> muss zuerst wissen, welche Dateien dazugehören. Sieben Namen gibt es
> sogar doppelt (`crash`, `hwid`, `netmon`, `netview`, `nidx`, `power`,
> `wmplug` — je einmal im Kern und einmal unter `user/`); sie stören
> einander nicht, weil sie in getrennten Übersetzungen liegen.

---

## 2. Der entscheidende Befund: ein Umzug kostet fast nichts

Das ist die Messung, auf der diese ganze Runde steht.

Firn spricht ein Modul unter dem **letzten Teil** des Importpfades an.
In `/root/firn/compiler/src/modules.rs`:

```rust
let target = imp.path.last().cloned().unwrap_or_default();
```

und im Parser (`parser.rs`, `import_decl`):

```rust
let alias = match path.last() { Some(a) => a.clone(), … };
```

**Folge:** nach `import arch.serial` heißt das Modul weiterhin
`serial`. Jede der rund 3 000 Aufrufstellen `serial.putc(…)` bleibt
Zeichen für Zeichen stehen. Ein Umzug ändert **nur die import-Zeile
der Aufrufer** — sonst nichts.

### Der Beweis

Gegenprobe vor dem ersten echten Umzug, beide Bäume aus `/tmp`
übersetzt (damit der eingebettete Pfad beide gleich trifft):

```
kernel/ flach              -> 6 309 184 Oktette, 6858 Symbole
kernel/ mit core/serial.fi -> 6 309 360 Oktette, 6858 Symbole
Symboltabelle: IDENTISCH
```

97 import-Zeilen wurden umgeschrieben, keine einzige Aufrufstelle. Die
176 Oktette Unterschied sind der längere Pfadname `core/serial.fi` in
der Fehlersuchtabelle — kein Code.

> Ein erster, naiver Vergleich (ein Baum aus `kernel/`, einer aus
> `/tmp/ktest`) zeigte einen Unterschied ab Zeichen 41. Der lag
> **allein an den eingebetteten Pfadnamen** (`kernel/kmain.fi` gegen
> `/tmp/ktest/kmain.fi`), nicht am Code. Deshalb steht oben der faire
> Vergleich: beide Bäume aus `/tmp`.

---

## 3. Die Ist-Aufnahme

`tools/struktur/erhebung.py` liest jede `.fi`, sammelt die
`import`-Zeilen und rechnet daraus den Graphen.

### Die größten Dateien des Kerns

| Datei | Zeilen | wird gerufen von | ruft |
|---|---:|---:|---:|
| `sys.fi` | 14 243 | 3 | 57 |
| `wm.fi` | 9 489 | 4 | 19 |
| `kgui.fi` | 8 667 | 1 | 45 |
| `kmain.fi` | 7 651 | 0 | 86 |
| `fb.fi` | 5 019 | 10 | 5 |
| `kstate.fi` | 3 958 | **131** | 0 |
| `uprog.fi` | 3 896 | 0 | 0 |
| `usb.fi` | 3 700 | 7 | 9 |
| `fs.fi` | 3 123 | 16 | 12 |

### Die meistgerufenen Module des Kerns

| Modul | gerufen von |
|---|---:|
| `kstate` | 131 |
| `serial` | 97 |
| `errno` | 45 |
| `mem` | 44 |
| `sched` | 36 |
| `time` | 28 |
| `arch` | 26 |
| `pci` | 25 |

`kstate.fi` ist die Zustandstafel: 131 der 137 Dateien lesen sie, und
sie selbst ruft **niemanden**. Das ist gesund — sie ist das Fundament,
nicht ein Knoten.

### Der Zyklus

**Ein** Zyklus, und er ist groß: **93 der 137 Kerndateien** hängen
wechselseitig zusammen (starke Zusammenhangskomponente, Tarjan). Darin
liegen `sys`, `wm`, `fb`, `gfx`, `proc`, `sched`, `fs`, `vfs`, `usb`,
`inet`, `serial` und 82 weitere.

Das ist in Firn **kein Fehler** — der Übersetzer liest den ganzen Baum
auf einmal, es gibt keine getrennten Objektdateien und keine
Kopfdateien. Aber es sagt genau eines: **keine dieser 93 Dateien lässt
sich einzeln herauslösen**, weder in eine Bibliothek noch in ein
nachladbares Modul, ohne vorher eine Kante zu brechen.

---

## 4. Die Schichtregel

### Die Regel, in einem Satz

> **Ein Modul darf nur Module gleichen oder tieferen Ranges rufen.**

Gleicher Rang ist erlaubt (innerhalb einer Schicht kennt man sich),
höherer Rang ist ein Bruch: ein Plattentreiber darf das Fenster nicht
rufen, die Oberfläche aber sehr wohl die Platte.

### Die Ränge

| Rang | Schicht | was darin liegt |
|---:|---|---|
| 0 | `lib` | reine Hilfen: `errno`, `kstate`, `version`, `brand`, `vektor` |
| 1 | `arch` | Prozessor, Unterbrechungen, APIC, FPU — und `serial`/`klog`, die **vor** dem Speicher reden können müssen |
| 2 | `mm` | `mem` |
| 3 | `sched` | Fäden, Prozesse, Zeit, Signale, Rechte, Lader |
| 4 | `bus` | PCI, ACPI, AML, Energie |
| 5 | `dev` | Treiber einzelner Geräte; `diag` (Absturzbericht) |
| 6 | `fs` | Dateisysteme und der Namensraum |
| 7 | `net` | der Netzweg |
| 8 | `gfx` | Rahmenpuffer, Schrift, Anzeigemodus |
| 9 | `ui` | Fenster, Kacheln, Zeiger |
| 10 | `sys` | die Systemaufruftafel — die Naht zu Ring 3 |
| 11 | `glue` | die Verdrahtung (siehe unten) |
| 12 | `boot` | `kmain` |

### Warum es eine Schicht `glue` gibt

Ein Betriebssystem hat Module, deren **Aufgabe** das Greifen nach unten
ist: der Unterbrechungsverteiler `trap` muss Tastatur, Platte, Uhr und
Netz erreichen, sonst verteilt er nichts. Dasselbe gilt für `smp` (Start
der anderen Prozessoren), `tasks` (Daueraufgaben), `schlaf`/`susp`/`wach`
(Energie) und `hw`/`hwdiag`/`hwid` (Geräteübersicht).

Diese als „Bruch" zu zählen wäre unehrlich — sie brechen nichts, sie
**sind** die Verdrahtung. Sie stehen deshalb in `glue`, direkt unter
`boot`.

### Die Messung

```
899 von 946 Kanten halten die Regel   (95,0 %)
 47 brechen sie
```

Der Weg dahin, offen berichtet: die **erste** Zuordnung ergab 117
Brüche. Ein Teil davon war nicht der Baum, sondern mein Modell —
`krypto` rief `blk` und `fs`, also ist es keine reine Bibliothek;
`serial` und `klog` brauchen die Uhr. Nach der Korrektur blieben 47.
**Diese 47 sind echt.**

### Die 47 Brüche, nach Ursache geordnet

| von → nach | Anz. | die Kanten |
|---|---:|---|
| `sched` → `fs` | 9 | `perm`, `async`, `kutil`, `krypto`, `module`, `proc`, `elf`, `uio` → `fs`/`file` |
| `dev` → `gfx` | 8 | `hidin`, `kbd`, `tty`, `usb` → `gfx`; `vgpu` → `cursor`/`fb` |
| `arch` → `sched` | 4 | `ksym`→`modtab`, `klog`→`time`, `hv`→`cap`/`sched` |
| `arch` → `mm` | 4 | `fpu`, `user`, `guard`, `hv` → `mem` |
| `sched` → `bus` | 4 | `share`→`pci`, `proc`→`acpi`/`bus`, `elf`→`pmon` |
| `sched` → `net` | 3 | `share` → `inet`, `netdev`, `netmon` |
| `arch` → `bus` | 2 | `chipname`→`pci`, `apic`→`pci` |
| `sched` → `dev` | 2 | `kutil`→`blk`, `krypto`→`blk` |
| `ui` → `glue` | 2 | `kgui` → `hw`, `trap` |
| `gfx` → `ui` | 2 | `gfx` → `kgui`, `wm` |
| `arch`/`bus`/`diag`/`net`/`fs`/`gfx` → sonstiges | 7 | `serial`→`gfx`, `pwr`→`gfx`, `crash`→`fs`/`gfx`, `netsvc`→`hw`, `procfs`→`hwid`, `gfx`→`sysgui` |

**Die zwei größten Muster sind die eigentliche Erkenntnis:**

1. **`dev` → `gfx` (8 Kanten): der Weg der Ausgabe.** Tastatur, TTY,
   USB und der Anzeigetreiber rufen die Grafik unmittelbar, statt über
   eine Naht. `serial` → `gfx` gehört dazu. Wer das auflösen will,
   braucht eine Konsolennaht, die beides bedient.
2. **`sched` → `fs` (9 Kanten): Rechte und Lader lesen Dateien.**
   `perm` liest `/system/…`, `elf` und `module` laden aus dem
   Dateisystem, `krypto`/`kutil` greifen bis auf `blk` durch.

Beide sind **keine Schlamperei**, sondern gewachsene Abkürzungen. Sie
zu beseitigen ist je eine eigene Runde — diese Runde **benennt und
misst** sie.

---

## 5. Was umgezogen wurde — und was nicht

### Umgezogen (6 Dateien, 14 import-Zeilen)

| Datei | von | nach | import-Zeilen |
|---|---|---|---:|
| `kaesni.fi` | `kernel/` | `kernel/crypto/` | 1 |
| `kshani.fi` | `kernel/` | `kernel/crypto/` | 1 |
| `kargon.fi` | `kernel/` | `kernel/crypto/` | 3 |
| `acpiev.fi` | `kernel/` | `kernel/bus/` | 5 |
| `codecstat.fi` | `kernel/` | `kernel/dev/` | 1 |
| `crash.fi` | `kernel/` | `kernel/diag/` | 3 |

Der Nachweis, dass nichts anderes geschah, steht im Diff: sechs reine
Umbenennungen (0 Einfügungen, 0 Löschungen im Inhalt) und 14 geänderte
import-Zeilen. Die Symboltabelle blieb bei **6858 Symbolen**.

### NICHT umgezogen — und warum

**113 der 126 flach liegenden Kerndateien werden in `tools/` oder
`test.sh` mit vollem Pfad genannt.** Beispiele:

* `tools/build-kernel.sh`, Zeile 241:
  `GFX_DATEIEN="fb wm wig font ttf tile wmplug vmode ansi ps2m kgui sysgui dispsave zeiger"`
  — daraus wird `rm -f "$TMP/kernel/$f.fi"`. Zieht man `fb.fi` nach
  `kernel/gfx/`, **findet dieses `rm` die Datei nicht mehr**, und der
  Serverbau (`--gui off`) bäckt die Grafik still ins Abbild.
* `cp -f kernel/gfx-aus.fi "$TMP/kernel/gfx.fi"` — dasselbe für
  `wg`, `ext4`, `ntfs`, `ps2m`, `tip`.
* `sys.fi` wird in **29** Werkzeugen genannt, `kmain.fi` in 28,
  `wm.fi` in 24, `kstate.fi`/`fs.fi`/`fb.fi` in je 16.

Es gibt **103 Testläufer** unter `tools/*/run.sh`. Eine Datei mit
Pfadnennungen umzuziehen heißt, sie alle mitzuändern — das ist kein
behutsamer Schritt mehr, und der Auftrag dieser Runde lautet
ausdrücklich: *hör auf und dokumentiere, warum es klemmt.*

**Genau hier klemmt es.** Die 13 Dateien ohne jede Pfadnennung in
ausführbarem Code sind: `wechsel`, `wach`, `rand`, `nvme`, `netsvc`,
`mem`, `kshani`, `kargon`, `kaesni`, `crash`, `codecstat`, `async`,
`acpiev`. Sechs davon sind umgezogen.

### 5b. Ein Nebenbefund: der Serverbau ist schon auf `main` rot

Beim Absichern von `tools/build-kernel.sh` ist etwas aufgefallen, das
**nicht** zu dieser Runde gehört, aber gemeldet werden muss.

**Erstens:** in `GFX_DATEIEN` steht `zeiger` — ein Name **ohne Datei**.
Die Runde ENGLISCH (`337c6cbd`) hat `kernel/zeiger.fi` nach
`kernel/cursor.fi` umbenannt und diese Liste nicht mitgezogen. Die
Zeile `rm -f "$TMP/kernel/zeiger.fi"` löscht seither nichts und
**sagt auch nichts** — `rm -f` schweigt über fehlende Dateien.

**Zweitens, und schwerer:** der GUI-lose Bau bricht ab.

```
error: cannot read '.../kernel/fb.fi': No such file or directory
```

Der Grund: `kernel/schlaf.fi`, `kernel/shot.fi` und `kernel/vgpu.fi`
schreiben `import fb`, stehen aber **nicht** in `GFX_DATEIEN` und
bleiben darum im Baum, wenn `fb.fi` daraus entfernt wird. Die drei
kamen aus den Runden SCHLAF/WACH (`c1e9d0b5`, `9217b8f3`), BRIDGE-2
(`e4af3368`) und VIRTIOGPU (`4302107c`).

**Das ist kein Schaden dieser Runde.** Gegenprobe in einem sauberen
`git worktree` auf **unverändertem `main` (`7e68da55`)**:

```
SERVER: 4 passed, 13 failed
RC=1
```

`tools/server/run.sh` ist also **schon vor dieser Runde rot**.

**Was diese Runde deshalb getan hat — und was nicht:**

* `GFX_DATEIEN` bleibt **Zeichen für Zeichen unverändert**, `zeiger`
  eingeschlossen. Eine Aufräumrunde repariert keinen fremden Bau.
* Die Schleife **meldet** jetzt aber, wenn ein Name in der Liste keine
  Datei im Baum hat (`SERVERBUILD-WARNUNG`), statt still
  weiterzulaufen. Sie bricht **nicht** ab — sonst wäre der ohnehin
  rote Serverbau an einer neuen Stelle rot, und die Ursache wäre wieder
  verdeckt.
* Das Suchen statt Buchstabieren (`find … -name "$f.fi"`) hat einen
  zweiten Nutzen: zieht eine spätere Runde `fb.fi` nach `kernel/gfx/`,
  findet die Schleife sie weiterhin. Ohne diese Zeile hätte ein Umzug
  den Serverbau **still** falsch gemacht — genau die Falle aus
  Abschnitt 5.

Ein Trockenlauf zeigt die Falle in drei Zeilen:

```
$ T=$(mktemp -d); mkdir -p "$T/kernel/gfx"; touch "$T/kernel/gfx/fb.fi"
$ f=fb; rm -f "$T/kernel/$f.fi"      # trifft nichts, meldet nichts
$ test -f "$T/kernel/gfx/fb.fi" && echo "Datei lebt noch"
Datei lebt noch
```

**Empfehlung für eine eigene Runde:** entweder `schlaf`, `shot` und
`vgpu` in `GFX_DATEIEN` aufnehmen (dann fehlen ihre Symbole dem
übrigen Kern) oder ihren Zugriff auf `fb` über die Naht `gfx.fi`
führen, wie es Runde SERVERBUILD für die 745 anderen Stellen getan
hat. Das ist dieselbe Arbeit wie die 8 Kanten `dev` → `gfx` aus
Abschnitt 4 — und ein weiteres Argument für die Konsolennaht.

### Bewusst nicht angefasst

* **`kernel/inet.fi`, `netdev.fi`, `netview.fi`, `netmon.fi`** und der
  ganze Netzweg — daran arbeiten gleichzeitig die Runden `ebpf` und
  `netzplus`. **Diese Runde hat an diesen vier Dateien keine Zeile
  geändert.** `netsvc.fi` wäre technisch umziehbar gewesen (keine
  Pfadnennung) und wurde **aus Rücksicht auf den Merge liegengelassen**.
* **`kernel/user/` und `kernel/app/`** — eigene Programme, nicht der
  Kern.
* **Die vier Abbilder `0x00123966`, `0x002B708C`, `0x002C6396`,
  `0x2C9D50`** (je 2,4 MB) im Wurzelverzeichnis: sie sehen nach
  Überbleibseln aus, gehören aber nicht dieser Runde. Nicht angerührt.

---

## 6. `sys.fi`, 14 243 Zeilen — lässt sie sich teilen?

**Heute nicht sauber. Hier ist die Messung statt einer Meinung.**

`sys.fi` hat **268 Funktionen**, davon **0 `pub fn`**. Nach außen
sichtbar ist nur, was die `export`-Liste nennt, und gerufen wird die
Datei von genau **zwei** Modulen: `sysgui.fi` und `tasks.fi`.

Der Kern der Datei ist `dispatch()` (Zeile 2178–2826, **648 Zeilen**):
eine Kette von **120** `if number == …`-Vergleichen, die je an ein
`do_*` weiterreicht.

Der Versuch, die 268 Funktionen den Systemaufrufgruppen zuzuordnen
(Datei, Prozess, Netz, Speicher, Zeit) — danach, welche Module sie
benutzen:

| Gruppe | Funktionen | Zeilen |
|---|---:|---:|
| Prozess (`proc`, `sched`, `signal`, `elf`, `time`) | 61 | 2 651 |
| Datei (`vfs`, `fs`, `file`, `mnt`, `fat`, `ext4` …) | 46 | 1 758 |
| Netz (`inet`, `netdev`, `unixsock`, `wg` …) | 12 | 409 |
| Speicher (`mem`, `uio`) | 1 | 11 |
| Grafik (`gfx`, `sysgui`) | 1 | 22 |
| **mehrere Gruppen zugleich** | **74** | **5 758** |
| keine (reine Hilfen, Konstanten) | 73 | 1 989 |

> **Der Befund: die größte Gruppe ist „mehrere zugleich" — 74
> Funktionen mit 5 758 Zeilen, mehr als jede einzelne Sachgruppe.**

Dazu kommen zwei harte Hindernisse:

1. **Die Konstanten.** Die `export`-Liste umfasst über 400 Namen
   (`SYS_*`, `WM_*`, `DG_*`, `PL_*`, `BUS_*` …). Sie werden von
   `dispatch` **und** von den `do_*` gebraucht. Eine Teilung müsste sie
   in eine eigene Datei ziehen, die dann jede Hälfte importiert —
   machbar, aber das ist ein eigener Schritt mit eigenem Risiko.
2. **Alle 268 Funktionen sind privat.** Sie rufen einander frei
   (`neg`, `copy_in`, `copy_out`, `fget`, `of_of`, `user_word` …). Beim
   Teilen müsste jede über die Schnittlinie gerufene Funktion
   **exportiert** werden — aus einer Datei mit heute 0 `pub fn` würden
   Dutzende neuer öffentlicher Namen. Das ist das Gegenteil von
   „modular": die Naht würde breiter, nicht schmaler.

**Urteil:** eine Teilung von `sys.fi` ist möglich, aber sie ist **eine
eigene Runde** und kein Nebenprodukt einer Aufräumrunde. Der ehrliche
erste Schritt wäre, die über 400 Konstanten nach `kernel/sysnr.fi` zu
ziehen (reine Zahlen, kein Verhalten) und **danach** zu messen, wie
viele Funktionen dann noch über die Schnittlinie greifen. Diese Runde
hat `sys.fi` bis auf **eine import-Zeile** (`crash` → `diag.crash`)
nicht angefasst.

---

## 7. Die Regel, die hält

`tools/struktur/run.sh` prüft die Schichtregel nach und endet mit
Code 1, wenn mehr Kanten brechen als der festgehaltene Deckel erlaubt.

```
bash tools/struktur/run.sh
```

**Der Deckel steht auf 47** — dem heute gemessenen Stand. Ein Skript,
das „0 Brüche" verlangt, wäre ab der ersten Zeile rot und würde
abgeschaltet statt befolgt. Der Deckel darf fallen, nie steigen.

### Die Gegenprobe

Ein Prüfskript, das nichts findet und trotzdem „OK" meldet, gilt in
diesem Repo als Fehler. `run.sh` prüft deshalb **zuerst sich selbst**:
Abschnitt 2 stellt in einer Kopie des Baums einen Regelbruch künstlich
her — `kernel/ahci.fi` (ein Plattentreiber, Rang 5) bekommt ein
`import wm` (die Oberfläche, Rang 9) — und verlangt, dass die Prüfung
anschlägt:

```
== 2. die Gegenprobe: schlaegt die Pruefung ueberhaupt an? ==
kuenstlicher Bruch in kernel/ahci.fi:  vorher 47, nachher 48
GRUEN: die Pruefung schlaegt an (47 -> 48).

STRUKTUR OK
```

Bleibt die Zahl stehen, endet der Lauf mit Code 1 — **auch wenn der
echte Baum in Ordnung wäre**.

---

## 7b. Die Testzahlen

Alle Läufe auf diesem Zweig, nach den Umzügen. Der Wirt stand während
der Läufe unter Fremdlast (Load 20–55).

| Läufer | Ergebnis | Sollwert | |
|---|---|---|---|
| `tools/k17/run.sh` | **158 passed, 0 failed** | 158/0 | ✅ |
| `tools/hotplug/run.sh` | **45 passed, 0 failed** | 45/0 | ✅ |
| `tools/install/abnahme.sh` | **35 grün, 0 rot** | 35/0 | ✅ |
| `tools/core/run.sh` | 46 proofs, 0 failures | — | ✅ |
| `tools/caps/run.sh` | 67 passed, 0 failed | — | ✅ |
| `tools/struktur/run.sh` | STRUKTUR OK, Gegenprobe 47→48 | — | ✅ |
| Bau `--gui on` | 7044 Symbole, 6 082 728 Oktette | unverändert | ✅ |

### Zwei Läufer, die auch auf `main` rot sind

Beide wurden **im eigenen `git worktree` auf unverändertem `main`
(`7e68da55`) gegengemessen** — sie sind nicht das Werk dieser Runde:

| Läufer | auf `main` | auf `struktur2` |
|---|---|---|
| `tools/server/run.sh` | 4 passed, **13 failed** | (Ursache unverändert, Abschnitt 5b) |
| `tools/module/run.sh` | 68 bestanden, **6 gefallen** | 71 bestanden, **3 gefallen** |

Die drei Fehlschläge von `tools/module/run.sh` auf diesem Zweig
(`Adressen, die mit nm uebereinstimmen: 12, erwartet eq 13`; `rc=21:
der verdorbene Programmtext hat nichts ausgeloest`; `kein
Ausnahmebericht`) treten **wortgleich auch auf `main`** auf und sind
dort eine **Teilmenge von sechs**. Die drei zusätzlichen Fehler des
`main`-Laufs (`Kern mit ps2m`, `ps2m.consume fehlt im gewoehnlichen
Abbild`, `der Kern ohne den Treiber ist kleiner: -6068872`) stammen
daraus, dass zu dieser Zeit ein zweiter Bau im selben Repo lief — ein
Messfehler des Vergleichs, kein Befund.

**Kurz: kein Läufer ist durch diese Runde schlechter geworden.**

## 8. Die Werkzeuge

| Datei | was sie tut |
|---|---|
| `tools/struktur/erhebung.py` | liest alle `.fi`, baut den Graphen, findet Zyklen (Tarjan), misst die Regel. `--json`, `--pruefen` |
| `tools/struktur/huelle.py` | trennt KERN / UPROG / AUSSEN. `--liste kern` |
| `tools/struktur/schichten.txt` | die Zuordnung Modul → Schicht und die Ränge |
| `tools/struktur/run.sh` | die Prüfung mit Deckel und Gegenprobe |
| `tools/struktur/verschiebe.sh` | zieht **ein** Modul um, passt nur die import-Zeilen an |

---

## 9. Was als Nächstes sinnvoll ist

1. **Die Pfadnennungen aus den Werkzeugen entfernen.** Solange
   `tools/build-kernel.sh` `kernel/fb.fi` buchstabiert, ist jede
   Grafikdatei festgenagelt. Ein `finde_modul()` in `build-kernel.sh`,
   das eine Datei im Baum sucht statt sie zu buchstabieren, macht **alle
   113 übrigen Dateien umziehbar**. *Das ist der Hebel dieser ganzen
   Aufgabe* — und eine eigene, klar abgegrenzte Runde.
2. **Die Konsolennaht** — löst die 8 Kanten `dev` → `gfx` und
   `serial` → `gfx`.
3. **`sys.fi`: erst die Konstanten** nach `kernel/sysnr.fi`, dann neu
   messen (Abschnitt 6).
4. **Den Deckel senken**, sobald eine Kante wirklich verschwindet.
