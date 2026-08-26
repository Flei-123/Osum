# Runde K11 — man kann auf Osum arbeiten

Vor dieser Runde konnte auf Osum **niemand eine Datei schreiben oder
ändern**. Es lief nur, was vorher hineinkompiliert worden war. Das ist der
Unterschied zwischen einem Vorführsystem und einem benutzbaren, und diese
Runde macht ihn weg: ein bildschirmorientierter Editor, zwanzig Werkzeuge
und eine Shell, die eine Sprache ist.

Der Zweig heißt `k11-tools`. Alles Neue steht in `kernel/user/` (die
Programme), `kernel/ansi.fi` (neu), `kernel/kbd.fi`, `kernel/serial.fi`,
`kernel/kstate.fi`, `kernel/elf.fi`, `kernel/sys.fi` und
`tools/k11/`. `kernel/fb.fi` und `kernel/font.fi` sind **nicht angefasst**
— dort arbeitet Runde K10.

---

## 1. Der Editor

`/bin/edit`, 1200 Zeilen Firn, Ring 3, über die tty-Schicht.

### Woran die Bedienung sich orientiert — und warum

An **nano** (und damit an `pico`), nicht an `vi`. Drei Gründe, und der
dritte ist der eigentliche:

1. **Modenlos.** Es gibt keinen Zustand, in dem `dd` etwas anderes tut als
   `dd`. Wer den Editor zum ersten Mal sieht, kann tippen.
2. **Jeder Befehl ist ein Steuerzeichen und damit EIN Oktett.** Genau das
   schickt `sendkey ctrl-o` über den QEMU-Monitor — der Testlauf bedient
   also dieselben Tasten wie ein Mensch, und nicht eine Hintertür.
3. **`vi` bräuchte die Fluchttaste als Befehl.** Die Fluchttaste ist aber
   auch das erste Oktett jeder Pfeiltaste (`ESC [ A`). Ein modaler Editor
   muss deshalb auf ein **Zeitlimit** warten, um beides zu unterscheiden —
   und ein Zeitlimit ist genau die Sorte Sache, die eine Messung
   wetterfühlig macht. Modenlos gibt es das Problem nicht.

### Was er kann

| | |
|---|---|
| Datei | öffnen, sichern (`^O`), verlassen mit Rückfrage (`^X`), neue Datei anlegen |
| Bewegen | Pfeile, `^A`/`^E` (Zeilenanfang/-ende), `Pos1`/`Ende`, `^Y`/`^V` und `Bild↑`/`Bild↓` (Seite), `^T`/`^G` (Anfang/Ende der Datei), `^B`/`^F` (Wort zurück/vor) |
| Ändern | einfügen, `Rücktaste`, `Entf`/`^D`, Zeile trennen (`Eingabe`), Zeilen verbinden (Rücktaste am Zeilenanfang), Tabulator |
| Ausschneiden | `^K` schneidet eine Zeile heraus, mehrfach hintereinander sammelt; `^U` fügt ein |
| Suchen | `^W` sucht (läuft am Dateiende um), `^R` sucht und ersetzt (`y`/`n`/`a`) |
| Rückgängig | `^Z`, in Gruppen: zusammenhängendes Tippen ist **eine** Gruppe, ein Ersetzen-alle ebenfalls |
| Anzeige | `^C` sagt Zeile/Zeilen, Spalte, Oktette; Kopfbalken mit Namen und `Modified`; Meldungszeile; Tastenzeile |
| Lange Zeilen | werden **geschoben**, nicht umgebrochen; ein `$` am Rand sagt, dass es weitergeht |

### Abweichungen von nano — aufgeschrieben statt verschwiegen

* `^B`/`^F` springen ein **Wort** (nano: ein Zeichen).
* `^T`/`^G` gehen an **Anfang/Ende der Datei** (nano: Rechtschreibung/Hilfe).
* `^R` ist Suchen-und-Ersetzen (nano: `^\`; der Backslash ist über
  `sendkey` nicht erreichbar).
* `^O` sichert **sofort** unter dem bekannten Namen und fragt nur, wenn es
  keinen gibt (nano fragt immer).
* Beim Sichern bekommt **jede** Zeile ihren Zeilenumbruch, auch die
  letzte. Eine Datei ohne abschließenden Umbruch kann dieser Editor lesen,
  aber nicht schreiben.

### Beide Ausgabewege

Der Editor spricht VT100. Auf der **seriellen Leitung** kommt das
unverändert an — dort sitzt ein Terminal. Der **Bildschirm** dieser
Maschine hatte keines: `fb.putc` (Runde K7) kennt Zeilenumbruch,
Wagenrücklauf, Tabulator und Rücktaste, alles andere malt es als
Fragezeichen. Ohne weiteres stünden auf dem Schirm die Steuerzeichen
selbst.

Deshalb gibt es **`kernel/ansi.fi`**: ein Fluchtfolgenautomat, der sich in
`serial.put` zwischen die Leitung und `fb.echo` setzt — eine Zeile in
`kernel/serial.fi`. Damit bleibt alles erhalten, was Runde K7 wollte (die
Bootmeldungen vor `tty.init`, der Registerauszug einer Ausnahme, jedes
`serial.puts` gehen weiter auf den Schirm); neu ist nur, dass eine
Fluchtfolge jetzt etwas **tut** statt gemalt zu werden.

Er kann CUP (`H`/`f`), CUU/CUD/CUF/CUB, ED (`J` mit 0/1/2), EL (`K` mit
0/1/2), SGR (`m` mit 0 und 7) und DECTCEM (`?25h`/`?25l`) — genau die
Menge, die der Editor benutzt, und keine Folge mehr. Was er nicht kann:
Farben, Rollbereiche, alternative Schirme.

### Die Tastatur

`kernel/kbd.fi` war „der Beweis, dass der Unterbrechungsweg geht": eine
Tabelle, ein Zeichen, keine Zusatztasten. Damit kann man `ls` tippen und
sonst nichts. Runde K11 hat ergänzt:

* **Umschalt** (beide Seiten, Drücken und Loslassen) mit einer zweiten
  Tabelle — Großbuchstaben und die obere Zeichenreihe.
* **Steuerung**: `STRG-A` ist 1, `STRG-Z` ist 26.
* **Die Zusatztasten** (Vorzeichen `0xE0`) als echte Fluchtfolgen:
  runter `ESC[B`, links `ESC[D`, rechts `ESC[C`, Pos1 `ESC[H`, Ende
  `ESC[F`, Bild↑ `ESC[5~`, Bild↓ `ESC[6~`, Entf `ESC[3~`.

**Was mit Absicht gleich bleibt:** die Pfeiltaste **nach oben** ist
weiterhin das einzelne Oktett **14**. Daran hängt Abschnitt 11 von
`tools/userland/run.sh` („die Zeile von vorhin"), und die Shell liest
genau diese Zahl seit Runde K6. Der Editor versteht deshalb *beides* — 14
und `ESC[A` — als „nach oben". Und es wird weiterhin **genau eine** Zeile
`key: ` je Taste gemeldet, auch wenn die Taste drei Oktette schickt;
Abschnitt 7 von `tools/kernel/run.sh` zählt diese Zeilen.

---

## 2. Der Werkzeugkasten

Zwanzig neue Programme, alle in Firn, alle eigene ELF-Dateien von der
Platte, keines mit einem undefinierten Symbol.

`find` · `sed` · `diff` · `patch` · `tar` · `gzip` · `gunzip` · `xargs` ·
`du` · `top` · `mount` · `umount` · `basename` · `dirname` · `tee` ·
`cut` · `tr` · `seq` · `env` · `which` — dazu `edit` und das gemeinsame
Modul `kernel/user/tools.fi` (Ausgabepuffer, Mustervergleich, Pfade).

### Gegen Linux geprüft

`tools/k11/run.sh` lässt jedes Werkzeug auf Osum über dieselben Vorlagen
laufen wie das GNU-Gegenstück auf dem Wirt und hält die Mitschriften
**Oktett für Oktett** gegeneinander:

* **`find`** — `-type f`, `-name MUSTER`, ohne Bedingung, `-maxdepth N`,
  `-empty`, `-type d`. Die Reihenfolge geht auf beiden Seiten durch
  `sort`: OFS liefert Einträge in Einfügereihenfolge, ext4 in
  Streuwertreihenfolge, und das ist eine Eigenschaft des Dateisystems und
  nicht des Werkzeugs.
* **`sed`** — `s///g`, `-n Np`, `Nd`, `/muster/p`, `s/^…/`, `s/…$/`.
* **`cut`** — `-d Z -f LISTE`, `-c LISTE`.
* **`tr`** — Bereiche, `-d`, `-s`.
* **`basename`**, **`dirname`** — samt der Sonderfälle `/` und Endung.
* **`seq`** — eine, zwei und drei Zahlen.
* **`diff -u`** — Kopfzeilen, `@@`-Blöcke und drei Zeilen Umfeld, gegen
  `diff -u --label ALT --label NEU`.

### tar und gzip gegen die echten

Für ein Dateiformat ist das die einzige ehrliche Prüfung, und sie läuft in
**beide Richtungen**:

* Osums `tar` packt einen Baum → **GNU tar** packt ihn aus → `diff -r`
  gegen den Ausgangsbaum.
* **GNU tar** (`--format=ustar`) packt → Osums `tar -xf` packt aus →
  dieselben Dateien.
* Osums `gzip` packt (fester Huffman-Baum, LZ77 mit Streuwertketten) →
  **GNU gunzip** packt aus → Oktett für Oktett dieselbe Datei.
* **GNU gzip -9** packt (dynamische Huffman-Bäume!) → Osums `gunzip`
  packt aus → dieselbe Datei.
* Unkomprimierbare Daten (2048 Oktette aus `/dev/urandom`-artigem
  Material) gehen als **gespeicherte Blöcke** hinaus und wachsen um
  weniger als ein Prozent, statt durch die Huffman-Bäume um ein Achtel
  größer zu werden.

`kernel/user/flate.fi` ist die ganze Implementierung: CRC-32 ohne Tabelle,
Auspacken für alle drei Blockarten (gespeichert, feste Bäume, eigene Bäume
samt der Lauflängenkodierung ihrer Codelängen, Dekodierer nach dem
`puff`-Verfahren aus zlib) und Einpacken mit den festen Bäumen.

### patch in allen drei Kombinationen

* Osums `diff` → Osums `patch` → die Datei ist die neue (und auf der
  **Platte** stehen dieselben Oktette).
* Osums `diff` → **GNU patch** → dieselbe Datei.
* **GNU diff** → Osums `patch` → dieselbe Datei.

### Bewusste Abweichungen

* **`du`** zählt Blöcke zu 1024 Oktetten, aufgerundet, über die **Größe**
  der Dateien; ein Verzeichnis selbst zählt **null**. Linux zählt den
  wirklich belegten Platz, und dort hat ein Verzeichnis 4096 Oktette —
  beides Eigenschaften des Wirtsdateisystems, nicht des Werkzeugs. Die
  Erwartung wird deshalb aus denselben Dateien mit derselben Regel
  gerechnet.
* **`which`** hat auf diesem System **einen** Suchpfad: `/bin`. Es gibt
  kein `$PATH`; die Shell hängt seit Runde K6 `/bin/` vor einen Namen ohne
  Schrägstrich.
* **`sed`** und **`tr`** suchen eine **Teilzeichenkette** mit `^` und `$`
  als Ankern, keinen regulären Ausdruck. Eine Ausdrucksmaschine ist eine
  Runde für sich, und `grep` dieses Userlands tut seit K6 dasselbe. Ein
  `sed`, das eine Maschine *behauptet*, wäre die schlimmere Lösung: dann
  liest jemand `s/[0-9]*//` und bekommt etwas, das aussieht, als hätte es
  geklappt.
* **`top`** läuft ohne `-n` endlos und endet mit STRG-C (seit Runde K9 ein
  echtes SIGINT aus der Zeilendisziplin). Es zeichnet keinen Schirm — der
  Editor ist das Programm, das den Schirm anfasst; ein zweites davon wäre
  eine zweite Stelle, an der die Terminalkenntnis steht.
* **`mount`/`umount`** kennen keine Gerätenamen und keine Typen: dieses
  System hat **ein** Dateisystem auf **einer** Platte. `umount` ist keine
  Attrappe — danach findet `ls /` wirklich nichts mehr, und es lässt sich
  auch **kein Programm mehr starten**, weil sie auf der Platte liegen.
  Genau das ist die Gegenprobe.
* **`xargs`** kann höchstens **sieben** Worte je Aufruf anhängen:
  `proc.MAX_ARGS` ist acht, samt Programmname. Ein `-n` darüber wird
  abgelehnt statt still gekürzt.

---

## 3. Die Shell

### Was vorgefunden wurde

Nachgesehen, nicht geraten (`kernel/user/sh.fi`, Stand `f4c58d1`): Röhren
mit bis zu vier Stufen über Zwischendateien, `<`, `>`, `>>`, `2>`, `;`,
`&` und `wait`, einfache und doppelte Anführungszeichen, `$NAME`, `$?`,
`$!`, Zuweisungen `NAME=wert` vor einem Befehl, die eingebauten Befehle
`cd`, `pwd`, `exit`, `export` und `wait`, ein Zeileneditor mit Rücktaste
und „die Zeile von vorhin", und `/bin/` als einzigen Suchpfad.

**Was fehlte:** alles, was ein Skript zu einem Programm macht. Kein `if`,
kein `for`, kein `while`, kein `case`, keine Funktionen, kein `test`,
keine Stellungsparameter. Ein Skript war eine Liste von Befehlen.

### Was jetzt dasteht

* `if` / `elif` / `else` / `fi`
* `while` … `do` … `done` und `until` … `do` … `done`
* `for NAME in WORTE` … `do` … `done`
* `case WORT in MUSTER|MUSTER) … ;; *) … esac` (mit `*` und `?`)
* Funktionen `name() { … }` — auch auf einer Zeile —, mit
  Stellungsparametern, `return N` und einer eigenen Tiefe von acht
* `break`, `continue`, `shift`, `:`
* `test` und `[` **eingebaut**: `-e -f -d -r -s` (Dateien), `-n -z`
  (Zeichenketten), `= !=` (Vergleich), `-eq -ne -lt -le -gt -ge` (Zahlen),
  `!` davor
* `$#`, `$0` … `$9`, `${NAME}`
* **`export` erreicht jetzt das Kind.** Runde K6 hatte das Wort und
  schrieb in ihre Doku: *„Die Markierung erreicht kein Kind: `exec` hat in
  diesem Kernel keine Umgebung. Es steht hier, damit die Shell das Wort
  hat und die Runde danach etwas, woran sie es hängen kann."* Das ist
  diese Runde.

### Der Zuschnitt

Die Maschinerie von K6 bleibt **Zeile für Zeile stehen**. Darüber liegt
eine Schicht, die den Text in **Anweisungen** zerlegt (getrennt an
Zeilenende und `;`, Anführungszeichen zählen mit, `;;` bleibt stehen) und
die Schlüsselwörter erkennt. Alles, was kein Schlüsselwort ist, geht durch
`run_line` — dieselbe Funktion, dieselbe Ausgabe, dieselben
Beendigungscodes wie in Runde K6. Deshalb misst
`tools/userland/run.sh` weiterhin genau das, was es gemessen hat.

Ein Skript wird als **Ganzes** gelesen, denn nur so kann ein `if` über
mehrere Zeilen gehen. Der interaktive Weg bleibt der von Runde K1: Zeile
für Zeile, mit dem Zeileneditor. Damit der auch weiterhin gemessen werden
kann, bekommt der Text vor dem Zerlegen denselben Durchgang, den
`get_line` Zeichen für Zeichen macht (Oktett 8 nimmt zurück, Oktett 14
setzt die vorige Zeile ein) — sonst wäre Abschnitt 5 von
`tools/userland/run.sh` mit dem zeilenweisen Lesen verschwunden.

### Abweichungen von POSIX

* Die Worte einer `for`-Liste werden **nach** der Ersetzung noch einmal an
  Leerzeichen zerlegt, damit `for i in $LISTE` das tut, was jeder
  erwartet. POSIX trennt früher; diese Shell setzt `$NAME` seit K6 als
  **ein** Wort ein.
* Keine Befehlsersetzung (`` `…` `` / `$(…)`), keine Umlenkung `2>&1`,
  keine Aliase, kein `local`, kein `[[ … ]]`.
* Eine Anweisung darf 255 Oktette haben, ein Skript 16384 und 512
  Anweisungen. Was darüber liegt, wird **abgelehnt** statt gekürzt.
* Eine `while`-Schleife bricht nach 100000 Durchgängen ab. Eine Schleife,
  die nicht endet, macht aus einem Testlauf ein Zeitlimit, und ein
  Zeitlimit misst nichts.

---

## 4. Der Kern

Vier kleine, additive Eingriffe — und ein neues Modul.

| Datei | was |
|---|---|
| `kernel/ansi.fi` | **neu**: VT100 auf der Bildschirmkonsole |
| `kernel/serial.fi` | eine Zeile: `fb.echo` → `ansi.echo` |
| `kernel/kbd.fi` | Umschalt, Steuerung, Zusatztasten |
| `kernel/kstate.fi` | `K11_OFF = 0x3D000`, eine Seite: Tastaturzustand, Terminalautomat, Umgebungsblock |
| `kernel/elf.fi` | `write_env`: die Umgebung auf die Argumentseite, bei `+2048` |
| `kernel/sys.fi` | `SYS_OSUM_SETENV = 1400`, `SYS_OSUM_MOUNT = 1401` |

### Die Aufrufnummern

Die Karte oben in `kernel/sys.fi` hat einen neuen Eintrag:
**`1400..1499 — Runde K11`**.

Zur Vorgabe *„fest ab Nummer 120 aufwärts"*: auf dieser Karte gelesen ist
das der nächste freie **eigene** Hunderterblock, also 1400. Die 120 selbst
ist Linux' `setresgid` und 121 `getpgid` — letztere hat Runde K9 belegt.
Eine eigene Bedeutung für eine Nummer, die Linux vergeben hat, wäre genau
die Übersetzungstabelle, die Regel 1 im Kopf von `sys.fi` vermeidet.

### Die Umgebung

Der Kern hält **einen** Umgebungsblock (`kstate.K11_OFF + ENV_BUF`,
3584 Oktette). Ein Prozess füllt ihn mit `SYS_OSUM_SETENV(buf, len)`; jedes
Programm, das danach gestartet wird, findet ihn auf seiner Argumentseite
bei `+2048` (Anzahl, dann die Zeiger, dann eine Null, dann die
Zeichenketten ab `+2192`). Das ist **kein** `environ` je Prozess — es ist
die Hälfte davon, die eine Shell braucht. Ein echtes `environ` bräuchte
Platz je Aufgabe und gehört in die Runde, die `fork` mit
Kopieren-beim-Schreiben baut.

`kernel/elf.fi` schreibt die Argumente jetzt nur noch bis `+2048`; darüber
liegt die Umgebung. Ein `exec` mit mehr als zwei Kilobyte Argumenten
scheitert dort, wo es vorher bei vier Kilobyte gescheitert wäre.

---

## 5. Gemessen

`tools/k11/run.sh` — Abschnitt 15 der Abnahme. Wie gemessen wird, und
warum es keine Behauptung ist:

1. **Der Editor wird wirklich bedient.** Die Tasten kommen über den
   QEMU-Monitor (`sendkey`) am Tor 0x60 an, laufen durch IRQ1,
   `kernel/kbd.fi` und die Zeilendisziplin — denselben Weg, den eine
   echte Tastatur nimmt. Danach liest der **Wirt** die gesicherte Datei
   **aus dem Plattenabbild** (`mkfs.py cat`) und hält sie Oktett für
   Oktett gegen die Erwartung. Kein Mitschnitt, keine Behauptung.
2. **Beide Ausgabewege zeigen dasselbe.** Derselbe Lauf schreibt auf die
   serielle Leitung *und* auf den Bildschirm. Der Mitschnitt geht durch
   ein Terminal in Python (`tools/k11/vt.py`), das Bildschirmfoto durch
   den Zeichensatzleser aus Runde K7B (`tools/gfx/schau.py lesen`) — und
   der Mitschnitt wird **im selben Augenblick** festgehalten wie das Foto,
   sonst vergleicht man zwei Zeitpunkte miteinander.
3. **Fehlerfälle**: Datei gibt es nicht, Verzeichnis statt Datei, kein
   gzip-Kopf, Text ohne abschließenden Zeilenumbruch (das nächste Zeichen
   klebt daran — genau das ist der Nachweis), eine Zeile mit 900 Zeichen,
   Binärdaten durch `gzip` und zurück.
4. **Gegenproben**: ohne Sichern ändert sich die Platte nicht; ohne
   Umschalttaste gibt es keine Großbuchstaben; auf dem gerechneten Schirm
   steht **keine** rohe Fluchtfolge mehr; ohne `gfx` gibt es kein Bild;
   nach `umount` startet kein Programm mehr von der Platte; nur was
   exportiert ist, kommt beim Kind an; die Speicherkarte von `kdata` hat
   keine Kollisionen und der Bereich dieser Runde steht darin; keine
   Aufrufnummer ist zweimal vergeben.

### Die Zahlen

`bash tools/k11/run.sh` — **85 Zusagen, 0 Fehler.**

| | |
|---|---|
| neue Programme | 21 (20 Werkzeuge + `edit`), dazu die Module `tools.fi` und `flate.fi` |
| neue Dateien im Userland | 6001 Zeilen Firn |
| `edit.fi` | 1400 Zeilen |
| `flate.fi` (deflate, ein- und auspacken) | 683 Zeilen |
| `kernel/ansi.fi` (VT100 auf dem Schirm) | 345 Zeilen |
| der Zweig insgesamt | 10037 Zeilen dazu, 1458 weg |
| Tasten, die der Testlauf wirklich drückt | 8 Läufe über den QEMU-Monitor |
| `gzip`: 20000 Oktette Text | 7979 (GNU `-9`: 5701) |
| `gzip`: 2048 Oktette Zufall | 2071, als gespeicherte Blöcke |
| die Shell aus firnc1 | 279096 Oktette (Runde K6: 147288) |
| das Userland aus firnc1, gesamt | 1987632 von erlaubten 1997152 |

### Der eine Fall, der von der Last der Wirtsmaschine abhängt

`tc netem: one frame in five thrown away` (Abschnitt 9 von
`tools/net/run.sh`, Runde K8) verlangt, dass alle 262144 Oktette durch
eine Leitung kommen, die jeden fünften Rahmen wegwirft. Runde K7B hat
schon aufgeschrieben, dass dieser Fall wetterfühlig ist: unter Last läuft
er in die Dreißig-Sekunden-Sperre von `netsvc.connect_service` und bricht
mit 90000 bis 200000 Oktetten ab.

Auf diesem Zweig gemessen: zweimal rot, **während gleichzeitig andere
Läufe auf derselben Maschine liefen** (2 und 1 KiB/s), und grün, sobald
die Maschine nichts anderes zu tun hatte (**83 KiB/s, 262144 Oktette,
NET: 75 passed, 0 failed**). Der Durchsatz auf der sauberen Leitung ist
auf beiden Zweigen derselbe (6300 bis 6400 KiB/s) — diese Runde hat den
Netzweg nicht verlangsamt, sie hat nur beim Messen daneben gestanden.

---

## 6. Was am Übersetzer aufgefallen ist

**firnc1 bricht bei einem unveränderlichen `static` mit einer Zeichenkette
OHNE MELDUNG mit Beendigungscode 1 ab.** firnc0 übersetzt dasselbe
anstandslos. Der kleinste Nachweis:

```firn
profile kernel
import ulib
export { u_start }
static S: [u8; 6] = "hallo\0"
fn u_start(args: u64) -> u64 {
    ulib.esay_line((&S[0 as usize]) as u64, 0)
    return 0
}
```

```
$ firnc  x.fi -o x.o   ; echo $?     -> 0
$ firnc1 x.fi -o x.o   ; echo $?     -> 1   (keine Ausgabe, keine Datei)
$ sed -i 's/^static S:/static mut S:/' x.fi
$ firnc1 x.fi -o x.o   ; echo $?     -> 0
```

Deshalb stehen die Wörterbücher in `kernel/user/sh.fi` und die Meldungen
in `kernel/user/mount.fi` und `kernel/user/umount.fi` als `static mut` da,
obwohl niemand hineinschreibt. **Das gehört ins Firn-Repository gemeldet**
— nicht hier repariert: `vendor/firn/COMMIT` ist festgenagelt, und der
Übersetzer wird erst nachgezogen, wenn `./test.sh` grün ist.

Zwei Dinge daran sind schlimmer als der Fehler selbst: er ist **still**
(kein Wort auf stderr), und er trifft eine Konstruktion, die in der SPEC
ausdrücklich vorgesehen ist (Abschnitt 14, `statics.rs`: ein `static` ohne
`mut` gehört nach `.rodata`).

---

## 7. Was offen blieb

* **Kein Zeitstempel auf einer Datei.** Ein OFS-Inode ist 128 Oktette groß
  und die sind voll: Typ (8), Größe (8), Verweiszahl (8), elf direkte
  Blöcke (88), ein einfach (8) und ein doppelt indirekter (8) = 128. Es
  ist **kein** Oktett frei. Deshalb hat `find` kein `-newer` und kein
  `-mtime`, `tar` schreibt Zeitstempel **null** (`tar tvf` auf dem Wirt
  zeigt dann 1970 — das ist die Wahrheit und keine Erfindung), und `ls -l`
  hat weiterhin keine Zeitspalte. Wer das will, muss den Inode
  vergrößern, und das ist eine Formatänderung: `kernel/fs.fi`,
  `tools/osum/mkfs.py` und Abschnitt 3 von `tools/posix/run.sh` müssen
  gemeinsam umgestellt werden.
* **`awk` gibt es nicht.** Es stand als „nur, wenn alles andere steht" auf
  der Liste, und alles andere steht — aber knapp: siehe der nächste Punkt.
  Ein halbes `awk` ist schlimmer als keines.
* **DIE PLATTE IST FAST VOLL, und das ist eine harte Grenze.** Das
  Userland aus Runde K6 wiegt aus firnc1 gebaut **1987632** Oktette; die
  Prüfung in `tools/userland/run.sh` verlangt weniger als 1997152. Das
  sind **9520 Oktette Luft**. Die Platte lässt sich nicht vergrößern: die
  Blockbitmap ist EIN Block, also 4096 Bits, also 4096 Blöcke, also
  2 MiB (`kernel/fs.fi`, `BITMAP_BLOCK`). Die nächste Runde, die ein
  Programm dazulegt, muss zuerst die Bitmap mehrblockig machen.
  (Ein Teil davon hat diese Runde selbst verursacht: die Shell ist von
  147288 auf 279096 Oktette gewachsen, weil sie jetzt eine Sprache kann.
  Ein Wörterbuch statt vierzig Zeichenketten auf dem Stapel hat davon
  rund 8000 zurückgeholt.)
* **`gzip` packt schlechter als GNU.** Feste Huffman-Bäume statt eigener:
  20000 Oktette Text werden 7979 statt 5701. Eigene Bäume wären ein
  Huffman-Erzeuger mehr und rund zwei Kilobyte besser.
* **`gzip` nimmt höchstens 64 KiB Eingabe**, `gunzip` gibt höchstens
  256 KiB aus, `diff` und `patch` nehmen 24 KiB und 256 bzw. 512 Zeilen,
  der Editor 64 KiB und 1024 Zeilen. Ein Prozess hat auf dieser Maschine
  1 MiB zwischen `proc.IMAGE_BASE` und `proc.IMAGE_END`, und darin liegen
  auch die Ketten des Packers. Alles davon wird **abgelehnt** statt still
  gekürzt.
* **Der Editor kann keine Datei ohne abschließenden Zeilenumbruch
  schreiben** (lesen schon).
* **`kernel/ansi.fi` kennt keine Farben.** Die Textkonsole hat eine
  Vorder- und eine Hintergrundfarbe; `ESC[31m` wird übergangen.
* **Runde K10 arbeitet parallel an `fb.fi`, `font.fi` und dem
  Fensterdienst.** Diese Runde hat keine der drei Dateien angefasst; die
  nächste freie Seite in `kdata` für sie ist **0x3E000** (0x3D000 ist
  vergeben, siehe `kstate.fi`). `kernel/kbd.fi` gehört jetzt teilweise
  dieser Runde — wer dort eine Maus anschließt, muss die Zusatztasten
  und die Umschalt-/Steuerungszustände stehen lassen.
