# RUNDE PROTOKOLL — der Ringpuffer, die Absturzberichte, das Panik-Bild

Zweig `protokoll`, abgezweigt von `merge6`, Arbeitsbaum `/root/osum-protokoll`.
Nicht gepusht, nicht verschmolzen.

Roadmap B1 („Protokollierung — höchster Nutzen pro Aufwand der ganzen
Liste") und B2 („Absturzberichte").

---

## Worum es ging, in einem Absatz

Die Fehlersuche auf echter Hardware war blind. Jeder Treiber dieses
Kernels sagt, was er tut — genau einmal, in dem Augenblick, in dem er es
tut, auf eine serielle Leitung. Justins Brett hat keine (LSR liest 0xFF
zurück). Alles, was ein Treiber dort hinschrieb, existierte für ihn
nicht. Und wenn es knallte, sagte der Kern `*** EXCEPTION 14 #PF` und
fünf nackte Zahlen — Zahlen, die man nur mit `objdump` und *genau* dem
Abbild, aus dem der abgestürzte Kern gebaut wurde, lesen kann. Die Runde
EINSPRUNG hat zwei Stunden damit verbracht, **eine** solche Zahl
zurückzurechnen.

Jetzt gibt es einen Ringpuffer im Speicher, der den Absturz überlebt,
einen Panik-Bildschirm, der Namen und Quellzeilen zeigt, und einen
Bericht auf der Platte, der den Neustart überlebt.

---

## Die Zahlen (`tools/protokoll/run.sh`, 55 Zusagen, 0 Fehler)

| Abnahmepunkt | verlangt | gemessen |
|---|---|---|
| (a) 4 Kerne × 10 000 Zeilen | 40 000, keine verloren, keine verschränkt | `zeilen=40000 gesamt=40000 ring=510 rotiert=39490 kaputt=0` |
| (b) Panik-Bildschirm | ≥ 5 aufgelöste Symbole + Datei:Zeile | **17** auf dem Schirm, 16 auf der Leitung, alle 16 Register |
| (c) Bericht nach Neustart | liegt in `/var/crash`, wird angezeigt | ja, mit 9 aufgelösten Symbolen |
| (d) Ring-3-Nullzeiger | Bericht, System läuft weiter | Bericht mit Programmnamen; `echo WEITERLAEUFT` danach |
| (e) 1 Mio. gefilterte `debug`-Aufrufe | < 100 ms | **14 ms** (KVM), 131 ms unter TCG |

Zu (e), ehrlich und ohne Ausrede: unter reiner Emulation (TCG) sind es
131 ms. Die Abnahmeschwelle ist eine Aussage über den Preis eines
Befehls, und ein Emulator, der jeden Befehl erst übersetzt, kann diese
Aussage nicht treffen. `tools/protokoll/run.sh` nimmt deshalb KVM, wenn
es da ist, misst sonst TCG **und sagt beide Zahlen**. Es entschärft die
Prüfung nicht — es benennt, was sie misst.

---

## Was gebaut wurde

### 1. Der Ring — `kernel/klog.fi` (neu)

510 Einträge zu 128 Oktetten in `kdata` bei `LOG_OFF = 0xB0000`. Ein
Eintrag trägt Laufnummer, Zeit (ns seit Start), pid, Kernnummer, Stufe,
Quelle (8 Zeichen) und Text (88 Zeichen).

**Warum in `kdata` und nicht aus dem Rahmenverwalter.** Der erste
Eintrag dieses Kernels fällt, bevor es einen Rahmenverwalter gibt, und
der letzte fällt in einem Kern, dessen Rahmenverwalter gerade kaputt
gegangen ist. Ein Protokoll, das genau dann weg ist, wenn man es
braucht, ist keines.

**Die Ein-Kern-Regel.** Vier Kerne schreiben gleichzeitig. Ohne Riegel
bekäme man nicht vertauschte, sondern *ineinandergeschriebene* Zeilen.
Die Sperre ist ein `cas`-Wort **im Ring selbst**, genommen mit
abgeschalteten Unterbrechungen und je Kern wiedereintrittsfähig (ein
Treiber protokolliert aus einem Interrupt-Handler heraus).

*Warum keine der acht `atomic.L_*`:* `kstate.LOCK_COUNT` ist 8, alle
acht sind vergeben, und der Platz dahinter gehört `TCPU_OFF`. Ein
neunter Platz hätte die Sperrentafel über die Kerntafel geschoben.

**Die Laufnummer wird ZULETZT geschrieben.** Ein Leser aus Ring 3 nimmt
die Sperre nicht (er darf den Kern nicht anhalten, nur weil er liest);
er erkennt einen halb geschriebenen Eintrag daran, dass die Laufnummer
noch die alte ist.

**Der schnelle Weg.** Ein Aufruf unterhalb der Schwelle kostet einen
Lesezugriff, einen Vergleich und einen Rückgang — sonst nimmt niemand
`debug` in eine heiße Schleife, und dann steht beim Fehlersuchen wieder
nichts da. Gemessen: mit dem Riegel erst in `emit` kostete ein
gefilterter Aufruf 254 ns (TCG), mit dem Riegel ausgeschrieben in `say`
131 ns. Der Unterschied ist **ein** Funktionsaufruf mit sieben
Argumenten.

Der Zähler der gefilterten Aufrufe steht je Kern und wird **ohne**
`lock` erhöht. Ein `lock xadd` auf ein gemeinsames Wort wäre in einer
Millionenschleife auf vier Kernen der teuerste Befehl des Systems — und
würde eine Zahl schützen, die niemand genau braucht.

**EIN Format, an einer Stelle.** `klog.line_at` baut die Zeile:

```
[      12345] 0/17 I nvme  : Regler gefunden, BAR0 0xfebd0000
 ^ µs seit    ^ ^  ^ ^       ^
   Start      | |  | Quelle  Text
              | pid Stufe
              Kernnummer
```

Serielle Ausgabe, `/dev/klog`, `/proc/klog` und `/bin/log` nehmen alle
denselben Weg. Es gibt keine zweite Stelle, an der dieses Format steht.

Befehlszeile: `logdebug` (alles aufzeichnen und ausgeben), `logall`
(alles aufzeichnen, nur ab `warn` seriell — die Einstellung für die
Suche auf echter Hardware), `logquiet` (aufzeichnen ab `info`, seriell
nur Fehler).

### 2. Symbole und Quellzeilen im Abbild — `tools/kernel/symtab.py`, `kernel/ksymtab.fi` (neu)

Aus

```
kspur:     0x143aa1   0x1621c0   0x11e934
```

wird

```
absturz.knall_b+0x0013 (absturz.fi:572)
sys.do_krach+0x008b (sys.fi:6552)
sys.dispatch+0x21b9 (sys.fi:2055)
```

`symtab.py` liest das **fertig gebundene** Abbild (`nm` für die Symbole,
`readelf --debug-dump=decodedline` für die Zeilen — Firn erzeugt seit
`compiler/src/dwarf_line.rs` selbst DWARF) und schreibt daraus eine
Assemblerdatei mit einer flachen, sortierten Tabelle in `.rodata`.
`ksymtab.fi` macht zwei Binärsuchen daraus, zwanzig Zeilen.

**Zweimal binden, und danach nachrechnen.** Die Tabelle entsteht aus dem
gebundenen Abbild — vorher gibt es keine Adressen. Also: einmal binden
mit dem Stummel `kernel/arch/x86_64/osym.s`, Tabelle erzeugen, noch
einmal binden. Das geht nur auf, wenn der zweite Durchgang keine
Funktionsadresse verschiebt (die Tabelle liegt in `.rodata`, und
`.rodata` steht im Bindeskript hinter `.text` und `.utext`) — und das
wird **nicht geglaubt, sondern gemessen**: `nm` auf beide Abbilder, und
wenn eine Adresse gewandert ist, bricht der Bau ab. Ein falscher Name
wäre schlimmer als gar keiner.

**Der Preis, gemessen und nicht geschätzt: 643 072 Oktette** (4 926 220
gegen 4 283 148), 5 190 Symbole und 65 914 Zeileneinträge.
`tools/build-kernel.sh --ohne-symbole` baut ohne beides; dann zeigt der
Panik-Bildschirm wieder Adressen.

*Warum die Tabellen im Abbild liegen und nicht auf der Platte:* der
Panik-Bildschirm entsteht in einem Kern, der gerade gestorben ist. Er
kann keinen Block mehr lesen.

### 3. Der Panik-Bildschirm — `kgui.panikbild`, Naht `gfx.panikbild`

Der ganze Bildschirm, rot, direkt auf den Rahmenpuffer: Vektor und Name,
`rip` **aufgelöst**, alle sechzehn Register, die Rückverfolgung
aufgelöst, die letzten Protokollzeilen, die Kernnummer, und in der
letzten Zeile der Pfad des Berichts auf der Platte.

**Das ist die einzige erlaubte Ausnahme von der wlib-Regel, und sie ist
dokumentiert** (ausführlich im Kopf von `kgui.panikbild`). Die Regel
dieses Projekts lautet: alles, was ein Mensch sieht, entsteht in Ring 3
und geht durch `wlib`. Ein Panik-Bildschirm wird gebraucht, *wenn der
Kern gestorben ist* — dann läuft kein Prozess mehr weiter, der
Fenstserver ist womöglich genau das, was kaputt ist (Justins Absturz von
Runde STARTKNOPF kam aus `wm.fi`), es darf keine Sperre mehr genommen
und kein Rahmen mehr angefordert werden. Ein Panik-Bildschirm über
`wlib` wäre ein Panik-Bildschirm, der genau dann nicht erscheint, wenn
er gebraucht wird. Es gibt keine zweite Stelle im Kern, die ohne `wlib`
etwas Sichtbares erzeugt; die Messtafel am oberen Rand geht über
`wm.messzeile` und damit über den Fensterserver.

Die Messtafel der Runde BLECHFÜNF (24 × 48 Zeichen) bleibt und läuft
davor — sie reicht für Vektor, RIP und vier rohe Adressen und für nichts
sonst.

### 4. Der Bildschirm wird WIRKLICH GELESEN — `tools/protokoll/schirmtext.py`

Ein Testläufer, der zählt, wie viele Pixel nicht rot sind, misst nicht
„fünf aufgelöste Symbole" — er misst, dass irgendetwas gemalt wurde. Und
ein Läufer, der statt des Bildes die serielle Ausgabe liest, misst den
*anderen* Weg; gerade der Panik-Bildschirm ist für die Maschine gebaut,
die keine serielle Leitung hat.

`schirmtext.py` holt die Glyphen aus `kernel/font.fi`, legt über das PPM
ein Raster von 8 × 16, macht aus jeder Zelle wieder sechzehn Oktette und
schlägt sie in der Glyphentafel nach. Das ist keine Zeichenerkennung mit
Wahrscheinlichkeiten, sondern die exakte Umkehrung des Zeichnens.
Zellen, die zu keiner Glyphe passen, werden `?` — davon gab es im
Abnahmelauf 0.

### 5. Absturzberichte — `kernel/absturz.fi` (neu)

`/var/crash/<sekunden>.txt` plus die leere Marke `/var/crash/NEU`. Im
Bericht: Kopf (Art, Zeit, Fassung, Kern, pid, Programmname), alle
Register, die aufgelöste Rückverfolgung, die letzten 50 Protokollzeilen.

* **Ring-3-Absturz:** der Kern ist gesund, es wird ganz normal
  geschrieben. Der Prozess stirbt, das System läuft weiter.
* **Kernel-Panik:** es wird *versucht*, mit `fs.frei` als Riegel — hält
  dieser Kern die Dateisystemsperre schon, ist der Absturz *im*
  Dateisystem passiert, und dann wird nicht geschrieben, sondern
  gemeldet, dass nicht geschrieben wurde. Das ist weniger, als `kdump`
  unter Linux kann, und mehr als nichts; es steht hier, damit niemand
  den Bericht für eine Garantie hält.

Beim nächsten Start sieht `absturz.init` nach der Marke — **nach** dem
Einhängen der Wurzel und nicht vorher; der erste Anlauf lief unmittelbar
hinter `filesystem(state)` und sah damit die RAM-Platte des Selbsttests,
nicht die Wurzel mit `/var/crash`. Die Antwort kommt als **Zahl** über
`sys 1860/KL_CRASH` heraus; angezeigt wird sie in Ring 3 von
`/bin/absturz`. Der Kern malt hier nichts.

*Zum Benachrichtigungsdienst:* die Runde SYSTEMBUS baut einen; solange
es ihn in diesem Baum nicht gibt, ist `/bin/absturz` der gekapselte
Übergang — **eine** Stelle, an der aus der Zahl ein Text wird. Wer den
Dienst später hat, ersetzt genau diese Datei und nichts sonst.

### 6. Der Weg nach Ring 3

* **Aufruf 1860** (`SYS_OSUM_KLOG`): Zahlen abfragen, eine Zeile *nach
  Laufnummer* holen, eine Zeile schreiben, die Schwellen setzen (nur
  Wurzel — eine Schwelle auf `error` von einem beliebigen Programm aus
  wäre die einfachste Art, Spuren verschwinden zu lassen).
* **Aufruf 1861** (`SYS_OSUM_KRACH`): der Testauslöser, mit **zwei**
  Riegeln — `krach` muss auf der Kernel-Befehlszeile stehen *und* der
  Rufer muss Wurzel sein. Ein Systemaufruf, mit dem jedes Programm den
  Kern anhalten kann, ist eine Tür, die man nicht offen lässt.
* **`/dev/klog`** — der Ring als Oktettstrom, lesbar mit `cat`,
  beschreibbar mit `echo … >`. Ehrlich gesagt und im Quelltext notiert:
  der Ring dreht sich beim Lesen weiter, ein `cat` bekommt keinen
  zusammenhängenden Schnappschuss.
* **`/proc/klog`** — die letzten Zeilen, so viele wie in die eine Seite
  passen, die eine procfs-Datei hat; die erste Zeile sagt, wie viele es
  insgesamt sind.
* **`/bin/log`** — liest **nach Laufnummern** und merkt deshalb, wenn
  ihm etwas entgangen ist (`log: entgangen: Zeilen N`). Filter nach
  Anzahl, Quelle, Stufe und Alter; `-f` läuft mit wie `tail -f`; `-z`
  zeigt die Zahlen; `-p` schreibt; `-q` setzt die Schwelle.
* **`/bin/absturz`** — Bericht anzeigen, auflisten, Marke löschen.
* **`/bin/krach`** — `kern`, `ud`, `prog`.

Eine Oberfläche für die Protokollansicht wurde **nicht** gebaut; sie
gehört nach Ring 3 über `wlib` und liest denselben Aufruf 1860.

### 7. Die Treiber

`nvme`, `xhci`, `usb`, `ahci`, `e1000` und `fs` melden ihre Ereignisse
über `klog` (Regler gefunden, BAR unbrauchbar, Anschluss lässt sich
nicht zurücksetzen, Superblock-Kennung falsch, eingehängt …), mit Stufe
und mit einer Quelle, die als `static mut` im Modul steht und deshalb
nicht aus Versehen anders geschrieben werden kann.

**Was NICHT gemacht wurde, und warum das eine Entscheidung ist:** die
bestehenden `serial.puts`-Zeilen wurden *nicht* umgeleitet. Rund dreißig
Testläufer dieses Baums lesen die serielle Ausgabe Zeile für Zeile und
zählen dort Zahlen ab; eine Runde, die alle diese Zeilen mit einem
Protokollkopf voranstellt, macht diese Läufer blind, ohne dass jemand
etwas gewinnt. Die Log-Schnittstelle steht daneben und wächst; das ist
das „schrittweise" aus dem Auftrag, wörtlich genommen.

---

## Zwei Fehler, die diese Runde gefunden hat

**1. `krach prog` lief seelenruhig durch.** Der erste Anlauf schrieb den
Nullzeiger als gewöhnlichen Lesezugriff hin, dessen Ergebnis niemand
benutzt — firnc hat ihn weggelassen. Ein `__mmio_read64` darf nicht
verschoben, zusammengefasst oder entfernt werden; genau diese Zusage
wird hier gebraucht. (Und: ein Nullzeiger *im Kern* faultet gar nicht,
weil dieser Kern das erste Gigabyte eins zu eins abbildet — der
Testauslöser liest deshalb von `0x700000000000`.)

**2. Die Ring-3-Rückverfolgung bestand aus Stapelzeigern.** `spur_sagen`
hielt jede Zahl zwischen `0x400000` und `0x40400000` für Code — und
darin liegt auch der Benutzerstapel (`proc.ARGS_BASE` = `0x4007F000`).
Ein Bericht dieser Runde zeigte acht Einträge, davon acht Stapelzeiger
und keine einzige Rücksprungadresse. Jetzt sind es zwei getrennte
Bereiche: der Stummel unten und das geladene Programm ab `0x40100000`.
Der Fehler ist älter als diese Runde.

---

## `kdata` wächst: 0xB0000 → 0xC0000

Der Ring braucht 64 KiB am Stück, frei waren 16. Statt ihn auf 128
Einträge zu kürzen (bei vier schreibenden Kernen sind 128 Zeilen ein
halber Wimpernschlag) wächst `kdata` um dieselben 64 KiB, mit denen es
schon Merge 2 und Runde BLECH-ECHT haben wachsen lassen. Es liegt in
`.bss`; im Abbild steht davon kein Oktett. Die Zahl steht zweimal
(`kstate.fi`, `boot.s`) — `tools/protokoll/run.sh` und `tools/hv/run.sh`
vergleichen sie. `tools/kernel/memmap.py` kennt den Bereich und meldet 0
Kollisionen.

---

## Geändert / neu

**Neu:** `kernel/klog.fi`, `kernel/ksymtab.fi`, `kernel/absturz.fi`,
`kernel/arch/x86_64/osym.s`, `kernel/user/log.fi`,
`kernel/user/crash.fi`, `kernel/user/noise.fi`,
`tools/kernel/symtab.py`, `tools/protokoll/run.sh`,
`tools/protokoll/schirmtext.py`, `STATUS-PROTOKOLL.md`.

**Geändert:** `kstate.fi` (LOG_OFF, KDATA_SIZE, vier Modusworte),
`boot.s`, `arch/x86_64/smp.fi` (Phase PH_LOG, `lograce`, `logbank`),
`arch/x86_64/trap.fi` (aufgelöste Rückverfolgung, SPUR_MAX 5→16,
Registerblock, beide Berichtswege, die zwei Textbereiche), `kmain.fi`,
`sys.fi` (1860/1861), `devfs.fi` (`/dev/klog`), `procfs.fi`
(`/proc/klog`), `kgui.fi` (`panikbild`), `gfx.fi` + `gfx-aus.fi` (die
Naht), `fs.fi` (`frei`, `ready`, klog), `nvme/ahci/e1000/xhci/usb.fi`
(klog), `user/ulib.fi`, `tools/build-kernel.sh` (zwei Durchgänge,
`--ohne-symbole`), `tools/kernel/memmap.py`, `test.sh` (Abschnitt 42).

---

## Was `./test.sh` gesagt hat

`tools/protokoll/run.sh` selbst: **55 Zusagen, 0 Fehler**, als Abschnitt
42 angemeldet.

Der Gesamtlauf hat vier Regressionen in FREMDEN Läufern aufgedeckt, und
alle vier waren echte Folgen dieser Runde. Sie sind behoben und einzeln
nachgemessen:

| Läufer | was war | jetzt |
|---|---|---|
| `tools/kernel` | `k0.o: undefined symbols` (osym_tab) und `'fs: mount unformatted=0' fehlt` | **176 / 0** |
| `tools/pci` | dasselbe undefinierte Symbol | **98 / 0** |
| `tools/posix` | `SYS_OSUM_KLOG: kernel 1860, libc missing` | **134 / 0** |
| `tools/net`, `tools/hwnet`, `tools/rtl` | dasselbe undefinierte Symbol | nachgezogen |

Die zwei Ursachen dahinter sind der Preis dieser Runde und stehen im
zweiten Commit ausgeschrieben:

* **Ein Dutzend Läufer bindet den Kernel mit einer eigenen `ld`-Zeile.**
  Eine neue Objektdatei einzuführen heißt, diese Liste zu pflegen — und
  sie ist beim nächsten Läufer wieder unvollständig. Deshalb steht der
  Stummel `osym_tab` als **schwaches Symbol in `boot.s`**: `boot.s` ist
  in jeder dieser Zeilen dabei, und die erzeugte Tabelle des zweiten
  Durchgangs überschreibt es, ohne dass `ld` mit „multiple definition"
  antwortet.
* **Rund dreißig Läufer lesen die serielle Ausgabe Zeile für Zeile.**
  Der Rufer schreibt `fs: mount unformatted=`, ruft `fs.mount` und
  schreibt danach die Ziffer — eine Protokollzeile *aus* `mount` heraus
  fällt mitten hinein. Deshalb steht die serielle Schwelle auf `warn`
  und nicht auf `info`: aufgezeichnet wird alles ab `info`, auf die
  Leitung geht ab `warn`, und wer beim Suchen alles sehen will, schreibt
  `logdebug`.

Ausserdem fällt seit dieser Runde die Zeile `  spur rsp=…` aus dem
Vergleich firnc0/firnc1 heraus — und zwar **weil die Runde sie repariert
hat**: solange `spur_sagen` den Benutzerstapel für Code hielt, fand sie
auf beiden Stufen immer acht Zahlen und war deshalb „gleich". Mit den
richtigen Grenzen findet Stufe 0 eine echte Rücksprungadresse und Stufe
1 keine, weil der Code verschieden lang ist. Das ist der Inhalt eines
fremden Stapels, kein Verhalten der Sprache; die Zeile daneben
(`user fault: … -- process killed`) wird weiter Wort für Wort verglichen.

**Nicht von dieser Runde**, auf `merge6` gegengeprüft und dort genauso:

* Abschnitt 1: `vendor/firn/lib/net/stack.fi: 723eaa12… statt
  136851a0…` — der festgenagelte Übersetzer im Arbeitsbaum weicht ab.
* `tools/gfx`: `fb.WIN_LIST ist ''` (grep hält `kernel/fb.fi` für eine
  Binärdatei; die Datei ist Oktett für Oktett dieselbe wie auf `merge6`)
  und `'fb: hold' fehlt` — derselbe Kernel-Aufruf liefert auf `merge6`
  ebenfalls kein `fb: hold`.
* `tools/handle`: zwei ZYKLENSCHRANKEN (`lseek < 700`, `getpid < 450`)
  wurden mit 912 und 663 gerissen. Auf diesem Wirt liefen zur selben
  Zeit die Abnahmen zweier anderer Arbeitsbäume; die Last lag bei 13.
  Das ist eine Messung der Maschine, nicht des Kernels.

Ein vollständiger, ungestörter `./test.sh`-Lauf steht damit noch aus —
die Platte dieses Wirts war während der Messung zu 99 % voll und drei
Abnahmen liefen gleichzeitig. Das ist hier vermerkt und nicht
weggelassen.

---

## Offene Kanten

* **`/proc/klog` passt nicht.** Eine procfs-Datei entsteht in *einer*
  Seite (4096 Oktette); der Ring hält das Sechzehnfache. Es stehen die
  letzten ~28 Zeilen darin, und die erste Zeile sagt, wie viele es
  insgesamt gibt. Wer alles will, nimmt `/dev/klog` oder `/bin/log`.
* **Die Rückverfolgung ist ein Stapelscan**, kein Abschreiten der
  Rahmenzeiger. Sie findet echte Rücksprungadressen *und* alte Reste im
  Stapel; auf dem Panik-Bildschirm dieser Runde sind die ersten drei
  Einträge die Wahrheit und der Rest Altlast. Ein sauberes Abschreiten
  bräuchte `rbp`-Ketten in jedem Kernrahmen oder `.eh_frame` — das
  Bindeskript wirft `.eh_frame` derzeit weg.
* **Der Bericht bei einer Kernel-Panik ist ein Versuch**, keine Zusage.
  Siehe oben.
* **Keine Oberfläche.** Aufgabenverwalter und Einstellungen bekommen die
  Protokollansicht in einer Ring-3-Runde über `wlib`; der Aufruf 1860
  liegt dafür bereit.
* **Vorbestehend, nicht von dieser Runde:** `./test.sh` Abschnitt 1
  meldet auf `merge6` wie hier `vendor/firn/lib/net/stack.fi:
  723eaa12… statt 136851a0…`. Der Arbeitsbaum wurde daran nicht
  angefasst; die Abweichung liegt im festgenagelten Uebersetzer.
