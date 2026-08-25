# Runde K7 — der Bildschirm

**Stand: 25.08.2026.** Bis zu dieser Runde war Osums Konsole die
**serielle Schnittstelle**. Auf einem echten Bildschirm sah man nichts.
Der Multiboot-Kopf **verlangte** seit Commit `c4427fa` einen linearen
Rahmenpuffer — damit ein Multiboot-Lader unter UEFI nicht auf einem
Textmodus besteht, den es dort nicht gibt — und **benutzt** hat ihn
niemand. `KERNELWECHSEL.md` in OrientOS führte das als offenen Punkt 4.3.

Diese Runde benutzt ihn.

Abnahme: `bash tools/gfx/run.sh` (Abschnitt 12 von `./test.sh`),
**74 Zusagen**. `./test.sh` insgesamt: **12 Abschnitte, 938 Zusagen,
0 Fehler** — die 175 Zusagen des Kernabschnitts sind unverändert.

---

## 1. Was auf dem Bildschirm erscheint

Nach `gfx` auf der Kommandozeile:

```
fb: 800x600x32  pitch=3200  src=vbe  phys=0xfd000000  win=0x3f400000
    huge=1  cols=100  rows=37  back=0x20d000  uc=0
fb: selftest 13 / 13
        fbbench: direct    fill=1457 us  scroll=1293 us  line=894 us
        fbbench: buffered  fill=1454 us  scroll=1264 us  flush=1173 us  line=891 us
fb: console mirrored to screen
```

Ab der letzten Zeile geht **jedes Oktett**, das über `serial.put` läuft,
auch auf den Bildschirm: die Bootmeldungen des Kernels, die
Ausnahmeberichte, die Ausgabe jedes Prozesses in Ring 3 und die der
Shell. Eine Textkonsole von 100 × 37 Zeichen in einem eigenen
8 × 16-Zeichensatz, mit Zeilenumbruch, Rollen, Vorder- und
Hintergrundfarbe und einer Textmarke. **Die serielle Ausgabe bleibt
unverändert bestehen** — sie ist die Grundlage aller bisherigen Tests, und
sie ist es weiterhin.

Ohne das Wort `gfx` ändert sich **nichts**: kein Modus wird gesetzt, kein
Rahmen abgebildet, `serial.put` spiegelt nicht. Die Runden 52 bis K6
messen Zeile für Zeile, was sie vorher gemessen haben.

### Die Worte der Kommandozeile

| Wort | Wirkung |
|---|---|
| `gfx` | Bildschirm an, 800 × 600 × 32 |
| `fbbig` | 1024 × 768 statt 800 × 600 (zwei 2-MiB-Kacheln) |
| `nodbl` | ohne Zweitpuffer — direkt auf die Karte |
| `fbuc` | das Fenster ohne Zwischenspeicher abbilden (PCD/PWT) |
| `nocursor` | ohne Textmarke |
| `fbtest` | das Prüfbild zeichnen |
| `fbuser` | das Programm in Ring 3 laufen lassen, das /dev/fb bespielt |
| `fbhold` | am Ende rund vier Sekunden stillhalten, damit ein Bildschirmfoto entstehen kann |

---

## 2. Woher der Rahmenpuffer kommt — zwei Wege

**Weg 1, vom Lader (`src=mb`).** Multiboot 1, Flag-Bit 12: Adresse,
Breite, Höhe, Zeilenlänge, Bit je Bildpunkt und die Lage der drei
Farbfelder stehen in der Informationsstruktur (Spezifikation 3.3,
Oktett 88 aufwärts). Das ist der Weg unter Limine — BIOS wie UEFI — und
der einzige, der auf echter Hardware trägt.

**Weg 2, von der Karte selbst (`src=vbe`).** Und das ist der Weg, den
diese Abnahme geht, aus einem gemessenen Grund:

```
mb: flags=0x24f
```

Bit 12 ist `0x1000`; in `0x24f` ist es **nicht gesetzt**.
`qemu-system-x86_64 -kernel` hat keinen Multiboot-Lader mit Videoteil.
Ein Kernel, der sich hier auf den Lader verlässt, hat keinen Bildschirm —
und ein Testlauf, der nur den Multiboot-Weg kennt, hätte in QEMU
überhaupt nichts zu messen.

Also stellt der Kern den Modus selbst ein. Die Karte ist der
Bochs-VBE-Aufsatz von QEMU (PCI `1234:1111`, Klasse 03), gesteuert über
zwei Kurzworttore (`0x1CE` Index, `0x1CF` Wert); die Adresse des linearen
Puffers steht in BAR0 des Geräts. Das ist ein richtiger Treiber, kein
Kniff: dieselben Register bedienen Bochs, QEMU und VirtualBox. Er liest
zurück, was die Karte **wirklich** genommen hat, und gibt auf, wenn sie
etwas anderes gesetzt hat als verlangt.

Nach `fb.init` weiß der Rest des Kernels nicht mehr, welcher der beiden
Wege gegangen wurde. Er sieht eine Adresse, eine Größe und eine
Zeilenlänge.

---

## 3. Wo der Rahmenpuffer liegt

`boot.s` bildet das **erste Gigabyte** mit 2-MiB-Seiten ab. Der
Rahmenpuffer liegt bei QEMU auf `0xFD000000` — weit darüber.

`apic.fi` hat für genau dieses Problem seit Runde K2 acht Plätze zu 2 MiB
am oberen Ende des Kernel-Seitenverzeichnisses (virtuell `0x3F000000`
aufwärts, Einträge 504 bis 511) und eine Belegungsliste in
`pci.K2_SCALARS + 0x80`. Das Verzeichnis ist das **eine**, das jeder
Adressraum von `proc.fi` erbt — deshalb funktioniert die Abbildung auch,
wenn ein Prozess läuft.

`fb.fi` benutzt **dieselbe Liste mit derselben Kodierung** (Block + 1) und
nimmt sich `n` **aufeinanderfolgende** freie Plätze, damit ein Puffer über
2 MiB im Kernel an einem Stück liegt:

| Auflösung | Oktette | Kacheln | Fenster |
|---|---:|---:|---|
| 800 × 600 × 32 | 1 920 000 | 1 | `0x3F400000` |
| 1024 × 768 × 32 | 3 145 728 | 2 | `0x3F400000` |

`tools/gfx/run.sh` hält `WIN_SLOTS`, `WIN_FIRST`, `WIN_VIRT` und
`HUGE_SIZE` in `fb.fi` und `apic.fi` **gegeneinander** und prüft, dass
`fb.WIN_LIST` wirklich `pci.K2_SCALARS + apic.S_WIN` ist. Ein
Auseinanderlaufen dieser Zahlen fiele sonst erst auf, wenn zwei Treiber
sich gegenseitig die Abbildung überschreiben.

---

## 4. Der Zeichensatz

`kernel/font.fi`, 8 × 16, 0x20 bis 0x7E — 95 Glyphen zu 16 Oktetten,
zusammen **1520**. Ein gesetztes Bit ist Vordergrundfarbe, Bit 7 ist die
linke Spalte.

Portiert aus OrientOS' `kernel/src/drivers/font.rs` (Rust, 221 Zeilen).
Die Glyphen sind dort einmalig aus DejaVu Sans Mono (Bitstream-Vera,
freie Weitergabe erlaubt) auf ein 8 × 16-Raster gerastert worden; hier
liegt nur das Ergebnis als reine Bitmaske. Kein Zeichensatzleser im
Kernel, 1520 Oktette Kosten.

**„Portiert" heißt nicht „ungefähr abgeschrieben".**
`tools/gfx/run.sh` liest die Tabelle aus `kernel/font.fi` und aus der
Rust-Quelle und vergleicht sie **Oktett für Oktett**:

```
OK  font.fi ist die Vorlage, Oktett fuer Oktett (1520 Oktette gegen die
    Rust-Vorlage, 0 verschieden)
```

Liegt OrientOS nicht daneben, prüft der Abschnitt nur noch Form und Größe
und sagt das ausdrücklich.

**Warum die Tabelle in den Datenbereich kopiert wird.** Stufe 0 von Firn
kennt kein `const` auf einem Feld (SPEC 14, Punkt 5 — nur ganze Zahlen und
Wahrheitswerte); der Übersetzer sagt das mit *„'const' supports only
integer and bool types in stage 0"*. Eine Tabelle ist hier deshalb
dasselbe wie jede andere veränderliche Größe des Kernels: sie liegt im
**Datenbereich** (`kdata + 0x2F100`), und `font.load` legt sie einmal beim
Start dorthin — als zehn Stücke zu 152 Oktetten, weil ein einziges
Zeichenkettenliteral von 1520 Oktetten zwar übersetzt, aber keine Zeile
mehr ist, die ein Mensch liest.

---

## 5. Die Messungen

QEMU 7.2.22, **TCG** (kein KVM auf dieser Maschine — `/dev/kvm` gibt es
nicht), ein Prozessor, 256 MiB, `-vga std`. Zeitbasis ist der
Prozessorzähler (`apic.tsc`, kalibriert in `hw.stage`); jeder Wert ist der
Mittelwert aus **fünf** Durchläufen. Beide Wege werden in **einem** Lauf
gemessen, auf derselben Maschine und mit demselben Zähler — zwei
QEMU-Starts wären zwei Maschinen.

800 × 600 × 32, also 1 920 000 Oktette je Bild:

| Vorgang | ohne Zweitpuffer | mit Zweitpuffer |
|---|---:|---:|
| voller Bildaufbau (`clear`) | **1 457 µs** | 1 454 µs + 1 173 µs Übertragung |
| ein Rollvorgang (`scroll`) | **1 293 µs** | 1 264 µs + Übertragung |
| **eine Textzeile** (80 Zeichen + Umbruch) | **894 µs** | **891 µs** |

Das sind 1,3 GiB/s für den Bildaufbau und 1,6 GiB/s für die Übertragung.

### 5.1 Was die Blockbefehle gebracht haben

Die erste Fassung schrieb jeden Bildpunkt einzeln über
`__mmio_write32`/`__mmio_read64`. Gemessen, dieselbe Maschine:

| | vorher | nachher | Faktor |
|---|---:|---:|---:|
| voller Bildaufbau | 11 611 µs | 1 457 µs | **8,0** |
| Rollvorgang | 10 310 µs | 1 293 µs | **8,0** |
| Übertragung des Zweitpuffers | 15 882 µs | 1 173 µs | **13,5** |

`rep stosq` für Flächen, `rep movsq` für Bildbereiche und die
Übertragung. Firn gibt den Assemblertext unverändert weiter; die drei
Register, die `rep` verändert, stehen als `clobber` daneben, und
`clobber("memory")` dazu — ohne sie hält der Übersetzer sie für unberührt
und rechnet mit einem Wert, den `rep` längst weggezählt hat.

`tools/gfx/run.sh` hält die Werte gegen eine großzügige Obergrenze
(100 ms). Die Grenze fängt genau den Fall ab, dass die Blockbefehle
wieder zu einer Schleife aus Einzelzugriffen werden.

### 5.2 Was das Zeichnen einer Glyphe gekostet hat

Die erste Fassung von `glyph` rief `pixel` je Bildpunkt. `pixel` liest bei
**jedem** Aufruf Zeichenziel, Zeilenlänge, Breite und Höhe erneut aus dem
Datenbereich und prüft zwei Grenzen — sechs Speicherzugriffe für einen
Schreibzugriff. Eine Glyphe sind 128 Bildpunkte, eine Textzeile achtzig
Glyphen:

| | vorher | nachher | Faktor |
|---|---:|---:|---:|
| eine Textzeile (80 Zeichen) | 3 200 µs | **894 µs** | **3,6** |

Eine Konsole, die eine Zeile langsamer schreibt, als ein **voller**
Bildaufbau kostet (1 457 µs), ist verkehrt herum gebaut. Jetzt werden die
vier Größen einmal geholt, die Zelle einmal auf ihre Grenzen geprüft und
dann Zeile für Zeile geschrieben. Die Grenzprüfung je Bildpunkt entfällt,
weil `cols` und `rows` aus Breite und Höhe abgeleitet sind: eine Zelle
innerhalb des Rasters liegt immer ganz im Bild. Liegt sie es doch nicht,
geht es über `pixel`, und dann sind die Grenzen wieder da.

### 5.3 Was die doppelte Pufferung wirklich kostet — und was nicht

**Ehrlich gesagt: unter TCG gewinnt sie nichts an Zeit.** Ein voller
Bildaufbau kostet mit Zweitpuffer 1 173 µs **mehr** (die Übertragung), und
eine Textzeile kostet mit und ohne praktisch dasselbe (891 gegen 894 µs).

Der Grund steht in einer zweiten Messung. Mit `fbuc` wird das Fenster
**ohne Zwischenspeicher** abgebildet (PCD und PWT gesetzt) — auf echter
Hardware der Unterschied zwischen „jeder Bildpunkt geht einzeln über den
Bus" und „eine Cachezeile auf einmal":

| | ohne `fbuc` | mit `fbuc` |
|---|---:|---:|
| voller Bildaufbau | 1 457 µs | 1 465 µs |

**Kein Unterschied.** QEMUs TCG modelliert keine Zwischenspeicher; der
Rahmenpuffer der Karte ist für den Gast Arbeitsspeicher wie jeder andere.
Damit ist der eine Effekt, der die Doppelpufferung auf echter Hardware
bezahlt macht, in dieser Umgebung **nicht messbar** — und eine Zahl, die
man nicht messen kann, wird hier auch nicht behauptet.

Was **doch** für den Zweitpuffer spricht und was gemessen ist:

1. **Die Übertragung ist bereichsweise.** `fb.dirty` merkt sich, welche
   Bildzeilen sich geändert haben; ein Zeilenumbruch überträgt nur die
   sechzehn Zeilen der Textzelle (51 200 Oktette), nicht das ganze Bild.
   Deshalb kostet die Textzeile mit Zweitpuffer nichts extra, obwohl die
   volle Übertragung 1 173 µs kostet.
2. **Kein halbes Bild.** Ein Bildschirmfoto während eines direkten
   Bildaufbaus kann einen halb gemalten Zustand zeigen; über den
   Zweitpuffer ist der Wechsel ein einziges `rep movsq`.

Wer die Zahl ohne Zweitpuffer will, schreibt `nodbl` — dann fehlt die
zweite Messzeile ganz, und `tools/gfx/run.sh` prüft, dass sie fehlt.

---

## 6. Wie die Bildschirmfotos geprüft werden

Ein Testlauf, der einen Kernel startet und „kein Absturz" meldet, sagt
über einen Bildschirm **gar nichts**: ein Treiber, der in den falschen
Speicher schreibt, stürzt nicht ab, er zeigt nur nichts.

Deshalb macht `tools/gfx/run.sh` echte Bildschirmfotos über den
QEMU-Monitor. Der Ablauf:

1. QEMU läuft mit `-display none -vga std` und einem Monitor an einem
   Unix-Socket.
2. Der Kern hält auf das Wort `fbhold` hin rund **vier Sekunden** still
   und meldet das seriell (`fb: hold`).
3. `tools/gfx/schuss.py` sieht die Zeile, ruft `screendump` und wartet,
   bis die Datei eine Größe hat, **die sich nicht mehr ändert** — ein halb
   geschriebenes PPM ist ein Bild, das jeden Vergleich verliert, und zwar
   ohne Hinweis darauf, warum.
4. `tools/gfx/schau.py` rechnet das PPM nach.

`schau.py` kann fünf Dinge, und jedes ist eine Zusage:

| Unterbefehl | prüft |
|---|---|
| `groesse` | Breite und Höhe — **der** Beweis, dass der Bildmodus gesetzt wurde |
| `punkt` | die Farbe an einer Stelle |
| `flaeche` | wie viele Bildpunkte eines Rechtecks **nicht** die erwartete Farbe haben |
| `text` | eine Textzeile **bildpunktgenau** gegen den Zeichensatz |
| `konsole` | das **ganze Bild** gegen den seriellen Mitschnitt |
| `finde` | dasselbe für eine gesuchte Zeile, damit im Fehlerfall dasteht, *welche* |
| `font` | `font.fi` gegen die Rust-Vorlage |

Der Zeichensatz wird dabei **immer aus `kernel/font.fi` gelesen**, nie aus
einer Kopie: geprüft werden soll der, der im Kernel steht.

### 6.1 Text ist nicht „irgendwas Helles"

`text` und `konsole` prüfen an **jeder der 128 Stellen jeder Glyphe**, ob
dort Vorder- oder Hintergrundfarbe steht — genau so, wie die Bitmaske es
sagt. Ein Zeichen, das um einen Bildpunkt verrutscht ist, fällt durch;
eines mit der falschen Glyphe auch.

```
OK  Zeile 14 bildpunktgenau: 'OSUM K7 FRAMEBUFFER 01234'
    (3200 Bildpunkte geprueft, 0 falsch)
```

### 6.2 „Beide Ausgaben zeigen dasselbe" — als Rechnung

`konsole` ist die stärkste Zusage dieser Runde. Der serielle Mitschnitt
wird ab dem Punkt, an dem der Spiegel angeht, durch **dieselbe
Zustandsmaschine** geschickt, die `fb.putc` ist (Umbruch am Zeilenende,
Rollen, Tabulator, Wagenrücklauf, Rücktaste); das Ergebnis wird mit dem
Zeichensatz gemalt und **das ganze Bild** dagegen gehalten.

```
OK  der ganze Bildschirm gegen den seriellen Mitschnitt
    (911 Zellen, 116608 Bildpunkte, 0 falsch)
OK  der ganze Bildschirm gegen den Mitschnitt der Shell
    (1488 Zellen, 190464 Bildpunkte, 0 falsch)
```

Das prüft in einem Zug: den Zeichensatz, die Zellenrechnung, den
Zeilenumbruch bei Spalte 100, **das Rollen** und den Gleichlauf beider
Ausgaben. Und es hat eine Gegenprobe: gegen den Mitschnitt eines
**anderen** Laufs geht dieselbe Rechnung nicht auf.

---

## 7. Die Gegenprobe

> *Ohne Gegenprobe beweist ein grüner Test nichts — so wird es in diesem
> Projekt gehalten.*

Abschnitt 6 von `tools/gfx/run.sh` fährt **denselben Kernel** mit
**derselben Kommandozeile**, wartet **genauso lange** und macht **genauso
ein Bildschirmfoto**. Nur das Wort `gfx` fehlt.

Damit das überhaupt geht, hängt `fbhold` **nicht** an `gfx`: der Kern
hält auch ohne Bildschirm still. Wäre das Warten an den Bildschirm
gebunden, wäre die Gegenprobe ein anderer Lauf — und ein Vergleich zweier
verschiedener Läufe beweist nichts.

Ergebnis:

```
OK  das Foto ist 720x400 -- VGA-Textmodus, kein Bildmodus gesetzt
OK  Feld 1 ist NICHT rot            (10000 von 10000 Bildpunkten falsch)
OK  Feld 2 ist NICHT gruen          (10000 von 10000 Bildpunkten falsch)
OK  die Textzeile steht NICHT da    (3200 Bildpunkte geprueft, 540 falsch)
OK  die untere rechte Ecke von 800x600 liegt ausserhalb des Bildes
```

720 × 400 ist der VGA-Textmodus mit dem 9 × 16-Zeichensatz des BIOS —
also **durchaus** Bildpunkte, nur eben keine, die dieser Kernel gemalt
hat. Die Zusage ist deshalb nicht „alles schwarz", sondern: *die Stellen,
die Abschnitt 5 misst, gibt es hier nicht.*

Weitere Gegenproben derselben Art:

* ohne `gfx` meldet der Kern weder Geometrie noch Selbsttest,
* ohne `fbuser` ist das Band, das Ring 3 malt, nicht da,
* mit `nodbl` gibt es keinen Zweitpuffer und keine zweite Messzeile,
* die `konsole`-Rechnung geht gegen einen fremden Mitschnitt nicht auf.

---

## 8. /dev/fb — der Bildschirm für Ring 3

Ein Programm ohne Kernelrechte muss den Schirm bespielen können. Es hat
keinen Torbefehl, kein `cr3`, keine physische Adresse. Was es hat, ist ein
Deskriptor — und was es damit darf, entscheidet der Kernel bei **jedem
einzelnen Aufruf**, mit denselben Prüfungen wie bei einer Datei.

| Aufruf | Verhalten |
|---|---|
| `open("/dev/fb", …)` | **vor** der Prüfung auf ein eingehängtes Dateisystem — der Bildschirm hängt an der Karte, nicht an einer Platte |
| `write` | Oktette an die Stelle, an der die Position steht; hinter dem Ende **0**, wie am Ende einer Datei |
| `read` | liest zurück, was da steht |
| `lseek(fd, 0, SEEK_END)` | die Größe des Bildes — so erfährt ein Programm die Geometrie |
| `fstat` | `S_IFCHR`, `st_size` = Fläche, **`st_blksize` = Zeilenlänge** |
| `mmap(…, MAP_SHARED, fd, 0)` | eine **2-MiB-Kachel** auf `0x40200000`, schreibbar, ohne Ausführungsrecht |

**Die Abbildung ist eine einzige Kachel, kein Feld aus 469 Einträgen.**
Der private Seitenverzeichniseintrag 1 eines Prozesses deckt
`0x40200000..0x403FFFFF`; `proc.map_huge` schreibt dort die physische
Adresse des Rahmenpuffers hinein, mit Benutzerbit und ohne
Ausführungsrecht — ein Bild ist kein Programm. Der Rahmen wird **nicht**
vom Rahmenverwalter geholt: er gehört der Grafikkarte, der Kernel hat ihn
nie besessen und gibt ihn nie zurück. `free_space` läuft die
**Seitentabelle** ab, und eine 2-MiB-Seite hat keine — es gibt also nichts
freizugeben und nichts falsch freizugeben.

`proc.user_ok` musste dafür **große Seiten kennenlernen**. `translate`
kennt Bit 7 seit Runde 62, die Zeigerprüfung nicht — ohne diese Ergänzung
wäre der abgebildete Rahmenpuffer für `write` und `read` unerreichbar
gewesen, obwohl der Prozess ihn beschreiben darf. Die Obergrenze deckt
jetzt zwei Kacheln statt einer; entschieden wird weiterhin beim Durchgehen
der Tabellen, und ein Prozess ohne die Abbildung hat dort keine Seite mit
Benutzerbit.

### 8.1 Was `uprog.u_fb` meldet

Elf Zusagen, und **fast die Hälfte davon ist eine Ablehnung** — eine
Schnittstelle, die nur den richtigen Fall kann, ist keine:

```
fbuser: open fd=3
fbuser: bytes=1920000
fbuser: map=1075838976        (= 0x40200000)
fbuser: passed 11 / 11
```

1. `open("/dev/fb", O_RDWR)` gibt einen Deskriptor.
2. `lseek(fd, 0, SEEK_END)` gibt die Größe des Bildes.
3. `write` an einer Stelle schreibt so viele Oktette, wie es soll.
4. `read` von derselben Stelle gibt zurück, was geschrieben wurde.
5. `write` **hinter** dem Ende gibt 0.
6. `write` aus einer Adresse, die dem Programm nicht gehört, gibt
   `-EFAULT`.
7. `mmap` gibt eine Adresse, und die liegt, wo der Kernel sagt.
8. Durch die Abbildung geschrieben ist durch `read` gelesen — **es ist
   derselbe Speicher**.
9. Ein **nur lesbarer** Deskriptor darf nicht schreiben (`-EBADF`) und
   nicht schreibbar abbilden (`-EACCES`).
10. `mmap` ohne `MAP_ANONYMOUS` auf einen Deskriptor, der kein
    Rahmenpuffer ist, gibt `-ENODEV`.
11. **Das Programm rechnet sich seine Geometrie selbst aus.** `fstat`
    gibt `st_size` (die Fläche) und `st_blksize` (die Zeilenlänge);
    daraus folgen Breite (`Zeilenlänge / 4`) und Höhe
    (`Fläche / Zeilenlänge`), und beide stimmen mit dem überein, was der
    Kernel dem Programm als Argument mitgegeben hatte.

Punkt 10 ist wörtlich die Zusage aus Runde K4 (*„ohne MAP_ANONYMOUS gibt
es nichts abzubilden"*). Runde K7 nimmt **eine** Ausnahme davon und ändert
an dem Satz sonst nichts: alles, was nicht der Rahmenpuffer ist, bekommt
weiterhin dieselbe Antwort wie vorher — auch ein Deskriptor, den es gar
nicht gibt. Ein `mmap` sagt damit nicht mehr aus, *welche* Deskriptoren
existieren.

### 8.2 Und im Bild

Das Programm malt vier Streifen über die unteren achtzig Bildzeilen. Das
Bildschirmfoto:

```
OK  der Streifen ist rot     (0 von 16000 Bildpunkten falsch)
OK  der Streifen ist gruen   (0 von 16000 Bildpunkten falsch)
OK  der Streifen ist blau    (0 von 16000 Bildpunkten falsch)
OK  der Streifen ist gelb    (0 von 16000 Bildpunkten falsch)
OK  und eine Bildzeile darueber ist nichts (0 von 800 Bildpunkten falsch)
OK  ohne 'fbuser' ist der Streifen NICHT da
```

Die Grenze sitzt bildpunktgenau bei `y = 520` — was in dem Foto steht, hat
**Ring 3** dort hingelegt, nicht der Kernel.

### 8.3 Zwei Zeichner auf einer Fläche

`/dev/fb` liegt auf der **Karte**, nicht im Zweitpuffer der Konsole. Das
ist die Entscheidung, an der das Gerät entweder ein Gerät ist oder nicht:
wäre es anders, läge dasselbe `/dev/fb` je nach Zugriffsart an zwei
verschiedenen Orten, und ein Programm, das schreibt und danach seine
Abbildung liest, sähe seine eigenen Oktette nicht.

Der Preis ist benannt: die Konsole überträgt ihre geänderten Zeilen aus
dem Zweitpuffer und übermalt dabei, was ein Programm in dieselben Zeilen
gelegt hat. Zwei Zeichner auf einer Fläche vertragen sich, solange sie
verschiedene Zeilen nehmen — und vertragen sich nicht, wenn nicht.
Deshalb schaltet `gfx_user` den Spiegel ab, bevor das Programm läuft. Ein
Fenstersystem wäre die Antwort darauf und ist nicht diese Runde.

Ein `fork` erbt die Abbildung **nicht**: `proc.copy_space` läuft die
Seitentabelle ab, und eine 2-MiB-Seite steht nicht darin. Das Kind muss
`mmap` selbst rufen.

---

## 9. Die Shell auf dem Bildschirm

`/bin/sh` von der Platte, wie in Runde K1 und K6 — nur dass die Ausgabe
diesmal auch auf dem Bildschirm landet. Abschnitt 11 von
`tools/gfx/run.sh` baut das kleinste Userland, das dafür reicht (`sh`,
`echo`, `ls`, `cat`), legt es mit `tools/osum/mkfs.py` auf ein
OFS-Abbild und fährt:

```
osum gfx nocursor fbhold … script=echo OSUM SHELL ON SCREEN;ls /bin;echo DONE
```

```
OK  die Shell hat den Satz seriell gesagt
OK  der ganze Bildschirm gegen den Mitschnitt der Shell
    (1488 Zellen, 190464 Bildpunkte, 0 falsch)
OK  die Zeile der Shell steht bildpunktgenau auf dem Schirm
    (Zeile 4, Spalte 11: 2560 Bildpunkte, 0 falsch)
```

Dafür war **kein einziger Handgriff in der Shell nötig**. Sie schreibt
über `write` auf Deskriptor 1, das ist `K_CONOUT`, das ist `serial.put` —
und das spiegelt. Wer die Shell nur seriell will, lässt `gfx` weg.

---

## 10. Wie der Spiegel funktioniert — und warum er so aussieht

`serial.put` ist die eine Stelle, durch die **jede** Ausgabe dieses
Kernels geht: Bootmeldungen, Ausnahmeberichte, der Tickzähler, die Tasten,
jedes Oktett jedes Prozesses. Genau eine Zeile dort spiegelt alles.

Zwei Dinge standen dem im Weg.

**Erstens der Abhängigkeitskreis.** `fb.fi` bindet weder `serial` noch
`mem`, `pci` oder `apic` ein — sonst wäre der Graph ein Kreis, und Firn
nimmt keinen. Also hat das Modul seine **eigenen** vier Torbefehle, seinen
eigenen Zugriff auf den PCI-Konfigurationsraum und seine eigene
Seitentabellenrechnung: an drei Stellen zwanzig Zeilen gewollte, benannte
Doppelung gegen einen Kreis, den es sonst nicht mehr aufzulösen gäbe. Der
Zweitpuffer kommt deshalb von außen — `kmain` holt ihn aus
`mem.frame_run` und reicht ihn an `fb.init`.

**Zweitens `state`.** `serial.put` hat kein Argument dafür und darf keines
bekommen: die Funktion wird an rund tausend Stellen gerufen, von `kmain`
bis in den Ausnahmebericht hinein, und keine dieser Stellen soll sich für
eine Konsole ändern. `kdata` ist aber ein **Symbol des Binders**
(`kernel/boot.s`, `.globl kdata`), und genau dieselbe Adresse bekommt
`kernel_main` in `rdx`. Ein `lea` holt sie sich also selbst:

```firn
fn kdata() -> u64 {
    return asm("lea rax, [rip + kdata]", out("rax"))
}
```

Das Kernelobjekt hat damit einen zweiten offenen Namen neben
`osum_panic`. `tools/kernel/run.sh` und `tools/pci/run.sh` erlauben ihn
ausdrücklich — **für das Kernelobjekt, nicht für `uprog.o`**: ein Programm
in Ring 3, das `kdata` erreichte, würde in den Kernel greifen und darf ihn
nicht einmal benennen. Was die Prüfung soll, bleibt unverändert: kein
libc, keine Laufzeit, nichts von außerhalb dieses Kernels. Beide Namen
sind in der eigenen Assemblerdatei dieses Kernels definiert.

Kostet der Spiegel etwas, wenn niemand ihn will? Ein `lea` und ein
Speicherzugriff je Oktett — auf einem Weg, der ohnehin auf ein
38400-Baud-Tor wartet.

---

## 11. Die Arithmetik-Falle

In Firn sind `+`, `-` und `*` geprüft und halten den Kern bei Überlauf an
(`osum_panic`). Bildpunktrechnungen (`y * pitch + x * bpp`) werden groß,
und Farbwerte sind Umdeutungen von Bitmustern, keine Zahlen.

Wo eine **Umdeutung** gemeint ist, steht deshalb `+%`, `-%`, `*%` oder
eine Maske:

* `spot(x, y)` ist eine **Adressrechnung**, kein Zählen: `y *% pitch +% x *% 4`.
* `rgb(r, g, b)` **maskiert** die drei Anteile (`& 0xFF`), statt sie zu
  addieren — ein Aufrufer, der 0x1FF übergibt, soll eine Farbe bekommen
  und keinen angehaltenen Kern.
* `twice(color)` verdoppelt ein Bitmuster in ein Achtoktettwort.

Wo eine Subtraktion unter null laufen **könnte**, steht vorher ein `if` —
in `hline` (`len = w - x` nur nach `x < w`), in `scroll`
(`h <= zh` fängt den zu kleinen Bildschirm ab), in `flush`
(`hi <= lo` kehrt sofort zurück).

**Die Linie hat deswegen kein Bresenham-Fehlerglied.** Das läuft von
`-dy` bis `+dx`, müsste also verschoben werden — und eine verschobene
Vergleichskette ist genau die Sorte Code, die man beim Lesen für richtig
hält und die dann bei der senkrechten Linie anhält. Stattdessen gibt der
längere der beiden Abstände die Schrittzahl, und der kürzere wird durch
eine Division darauf verteilt: exakt, vorzeichenfrei, ohne aufsummierten
Fehler. Eine Division je Bildpunkt ist der Preis; Linien sind nicht der
heiße Pfad, Zeichen sind es.

---

## 12. Die dreizehn Zusagen des Kernels über sich selbst

`fb.selftest` läuft **im Kernel**, vor jedem Bildschirmfoto, und meldet
`fb: selftest 13 / 13`. Das ersetzt das Foto nicht — ein Kernel, der in
seinen eigenen Zweitpuffer schreibt und daraus liest, hat noch nichts über
den Bildschirm bewiesen. Es fängt die Fehlerklasse ab, die ein Foto nur
als schwarzes Bild zeigt, ohne zu sagen warum:

1. Die drei Grundfarben sind drei verschiedene Werte.
2. Geschriebener Bildpunkt = gelesener Bildpunkt.
3. Der letzte Bildpunkt liegt noch im Puffer.
4. Außerhalb wird nichts geschrieben und nichts gelesen.
5. Ein Rechteck ist an seinen Ecken gefüllt und einen Bildpunkt daneben
   nicht.
6. Eine Linie trifft ihre beiden Enden.
7. Ein Bildbereich, an eine andere Stelle kopiert, steht dort.
8. Das große A hat in seiner vierten Zeile die Bitmaske `0x18`.
9. Ein gezeichnetes Zeichen hinterlässt Vordergrundfarbe **da**, wo der
   Zeichensatz ein Bit gesetzt hat, und Hintergrund daneben.
10. Die Schreibmarke ist nach einem Zeichen eine Spalte weiter.
11. Ein Zeilenumbruch setzt sie zurück und eine Zeile tiefer.
12. Rollen: was in Zeile 1 stand, steht danach in Zeile 0.
13. … und die letzte Zeile ist danach leer.

---

## 13. Was diese Runde geändert hat

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/fb.fi` | **neu, 1 513** | Rahmenpuffer entgegennehmen (Multiboot **und** Bochs-VBE), Fensterabbildung, Zeichengrundlagen, Zweitpuffer, Textkonsole, `/dev/fb`-Ein-/Ausgabe, der Spiegel |
| `kernel/font.fi` | **neu, 130** | der 8 × 16-Zeichensatz, portiert aus OrientOS |
| `kernel/kmain.fi` | +381 | `graphics`, `gfx_bench`, `gfx_user`, `gfx_hold`, `pattern` |
| `kernel/sys.fi` | +226 | `/dev/fb`: `open`, `read`, `write`, `lseek`, `fstat`, `mmap` |
| `kernel/uprog.fi` | +240 | `u_fb` — das Programm in Ring 3, `u_sys6` |
| `kernel/proc.fi` | +88 | `map_huge`, große Seiten in `user_ok` |
| `kernel/serial.fi` | +14 | eine Zeile in `put`, und der Absatz darüber |
| `kernel/file.fi` | +7 | `K_FB` |
| `tools/gfx/run.sh` | **neu, 407** | 74 Zusagen in elf Abschnitten |
| `tools/gfx/schau.py` | **neu, 385** | das Bildschirmfoto maschinell nachrechnen |
| `tools/gfx/schuss.py` | **neu, 87** | `screendump` über den QEMU-Monitor |
| `tools/kernel/run.sh`, `tools/pci/run.sh` | +2 Stellen | `kdata` als zweiter erlaubter offener Name |
| `test.sh` | +3 | Abschnitt 12 |

Der Datenbereich wächst **nicht**: die Skalare und der Zeichensatz liegen
in der letzten freien Seite, `kdata + 0x2F000`. `KDATA_SIZE` bleibt
`0x30000`.

---

## 14. Was offen bleibt

* **Kein Fenstersystem.** Konsole und `/dev/fb` teilen sich eine Fläche
  und übermalen sich, wenn sie dieselben Zeilen nehmen (Abschnitt 8.3).
  Das ist benannt, nicht behoben.
* **Kein `ioctl`.** Die Geometrie kommt über `fstat` (`st_size` und
  `st_blksize`, Abschnitt 8) — das reicht für Breite, Höhe und
  Zeilenlänge und ist geprüft. Was damit **nicht** geht: die Auflösung
  von Ring 3 aus **ändern**, die Lage der Farbfelder erfragen (der Kernel
  nimmt 32 Bit mit Rot bei 16 an) und den Zweitpuffer von außen
  übertragen. Dafür bräuchte es ein `ioctl` oder eine eigene
  Aufrufnummer.
* **Der Multiboot-Weg ist ungemessen.** `src=mb` ist geschrieben und
  compiliert, aber QEMUs `-kernel` liefert Bit 12 nicht, und dieses Repo
  baut kein ISO. Der Weg lässt sich nur dort messen, wo Lader und Abbild
  zu Hause sind: in OrientOS (`tests/step-2x-*`). **Bis dahin ist er
  Vermutung, kein Ergebnis** — auch wenn die Felder aus der Spezifikation
  abgeschrieben sind.
* **Write-Combining fehlt.** Das Fenster ist entweder mit Zwischenspeicher
  (Vorgabe) oder ohne (`fbuc`) abgebildet. Richtig für einen Rahmenpuffer
  wäre WC über die PAT-MSR. Unter TCG ist der Unterschied nicht messbar
  (Abschnitt 5.3), also wäre es eine Änderung ohne Beleg — und die gehört
  nicht in dieses Projekt.
* **Keine Sperre um die Konsole.** `fb.putc` ist nicht gegen mehrere Kerne
  oder gegen eine Unterbrechung mitten im Zeichnen geschützt. Das ist
  dasselbe, was für `serial.put` seit Runde 59 gilt, und aus demselben
  Grund bisher folgenlos: der Lauf mit vier Kernen (`tools/smp/run.sh`)
  schaltet die Grafik nicht ein. Sobald jemand `gfx` und `-smp 4`
  zusammen fährt, ist es ein Fehler.
* **Nur 32 Bit je Bildpunkt.** 24 und 16 sind in `pixel` vorgesehen
  gewesen und wieder herausgeflogen, weil sie nicht gemessen werden
  konnten: die Karte gibt in QEMU 32. Ein Rahmenpuffer mit anderer Tiefe
  wird abgelehnt statt falsch bedient.
* **Kein Zeichensatz über 0x7E.** Alles außerhalb wird zum Fragezeichen.
* **Getestet in QEMU**, nicht auf echter Hardware — wie alles in diesem
  Repo.
