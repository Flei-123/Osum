# Runde K10 — die Oberfläche

**Stand: 26.08.2026.** Runde K7 gab Osum einen Bildschirm: 800 × 600
Bildpunkte, eine Textkonsole darauf, `/dev/fb` für Ring 3. Sie endete mit
einem zugegebenen Mangel, und der steht wörtlich in `kernel/fb.fi`:

> „Der Preis ist benannt: die Konsole überträgt ihre geänderten Zeilen aus
> dem Zweitpuffer und übermalt dabei, was ein Programm in dieselben Zeilen
> gelegt hat. Zwei Zeichner auf einer Fläche vertragen sich, solange sie
> verschiedene Zeilen nehmen. **Ein Fenstersystem wäre die Antwort darauf
> und ist nicht diese Runde.**"

Diese Runde ist es. Drei Stücke, und alle drei in Firn:

* **`kernel/ps2m.fi`** — das Zeigegerät am zweiten Anschluss des 8042,
  IRQ 12, Drei- und Vier-Oktett-Pakete, Rad, Anschlag an den Bildrändern.
* **`kernel/wm.fi`** — der Fensterserver: Fenster anlegen, verschieben,
  Größe ändern, schließen; Stapelreihenfolge; Eingabefokus;
  Ereigniszustellung; **Bereichsverfolgung**, damit nur das Neue gemalt
  wird.
* **`kernel/ttf.fi`** — ein TrueType-Leser und ein Rasterer mit
  **Kantenglättung**, ganz in Firn. Kein FreeType, kein stb_truetype,
  keine Gleitkommazahl.

Dazu zwei Anwendungen in Ring 3, neun Aufrufe in der nativen ABI und ein
Testläufer, der über den QEMU-Monitor **echte Mausbewegungen, Klicks und
Tastendrücke** in die laufende Maschine speist und das Ergebnis auf dem
Bildschirmfoto nachrechnet.

**Abnahme:** `bash tools/wm/run.sh` (Abschnitt 15 von `./test.sh`) —
**103 Zusagen, 0 Fehler.** `./test.sh` insgesamt: **1228 Zusagen**, davon
14 von 15 Abschnitten grün; die eine rote Zeile gehört Abschnitt 14 (Netz)
und ist auf `main` dieselbe — siehe Abschnitt 9.

---

## 1. Was auf dem Schirm passiert

Nach `gfx wm wmhold` auf der Kommandozeile:

```
wm: mount=1
ttf: mono  glyphs=96  upm=2048  asc=14  desc=3  lh=19  kern=0   selftest 12 / 12
ttf: sans  glyphs=96  upm=2048  asc=13  desc=3  lh=18  kern=220 selftest 12 / 12
mouse: id=3  packets=0  selftest 10 / 10
wm: 800x600  cursor=1  dirty=1  focus=1  arena=524288
wm:   selftest 17 / 17
wm: term win=0  cols=56  rows=20  cell=10x19
wclick: passed 10 / 10
wmbench: compose full=6801 us  small=198 us  factor=3434
wmbench: glyph cold=80130 us  warm=134 us  factor=59798 (je 95 Zn)
wm: hold
```

Auf dem Bildschirm stehen dann **zwei Fenster** auf einem Schreibtisch:

* **`Terminal -- sh`** bei (24, 40), Malfläche 560 × 380, ein Zeichenraster
  von **56 × 20 Zellen zu 10 × 19 Bildpunkten** in DejaVu Sans Mono bei
  16 Bildpunkten. Darin läuft mit `wmshell` eine **echte Shell von der
  Platte** — dieselbe `/bin/sh`, die Runde K6 gebaut hat.
* **`Klick mich`** bei (420, 330), Malfläche 260 × 150, angelegt von einem
  **Programm in Ring 3**, das den Rahmenpuffer nicht kennt und nur ein
  Handle hat.

Beide haben eine Titelleiste in einer **Proportionalschrift** (DejaVu
Sans, 15 Bildpunkte, mit Unterschneidung), einen Rahmen, der die
Beleuchtung anzeigt, und ein Schließfeld. Darüber ein **Mauszeiger** aus
schwarzem Umriss und weißer Füllung.

Was man tun kann: das Fenster **anklicken** (es kommt nach vorn und
bekommt den Fokus), an der **Titelleiste ziehen**, an der unteren rechten
Ecke die **Größe ändern**, auf das rote Feld klicken und es **schließen**.
Tippen geht in genau das Fenster, das den Fokus hat.

### Die Worte der Kommandozeile

| Wort | Wirkung |
|---|---|
| `wm` | Zeigegerät, Fensterserver und Schriften an |
| `wmhold` | am Ende fünf Sekunden stillhalten (für das Foto und die Eingabe) |
| `wmshell` | im Terminalfenster wirklich `/bin/sh` starten |
| `nodirty` | **Gegenprobe**: ohne Bereichsverfolgung, immer der ganze Schirm |
| `nofocus` | **Gegenprobe**: jede Taste an *jedes* Fenster |
| `nomouse` | **Gegenprobe**: kein Zeigegerät, kein Zeiger |
| `nompoll` | **Gegenprobe**: nur IRQ 12, keine Abfrage des Bausteins |
| `ttfdump` | acht Glyphen als Text und als Prüfsumme auf die serielle Leitung |

Ohne das Wort `wm` ändert sich **nichts**: `wm: skipped`, kein
Zeichensatz wird gelesen, kein Zeigegerät aufgesetzt, und die Textkonsole
aus Runde K7 spiegelt weiter wie zuvor. Die Runden 52 bis K9 messen Zeile
für Zeile, was sie vorher gemessen haben.

---

## 2. Das Zeigegerät

Es hängt am **selben Baustein wie die Tastatur**. Der 8042 hat zwei
Anschlüsse; der zweite liegt auf IRQ 12. Der Aufsetzweg steht in
`kernel/ps2m.fi` Schritt für Schritt, weil jede Vertauschung eine eigene
Art hat zu scheitern: Anschluss ein (`0xA8`), Kommandooktett lesen und
Bit 1 setzen (IRQ 12 zulassen) sowie Bit 5 löschen (Takt nicht anhalten),
`0xFF` (Rücksetzen, Antwort `0xFA 0xAA 0x00`), der **Radgriff**
(Abtastrate 200, 100, 80, dann Kennung abfragen — meldet das Gerät `3`,
schickt es vier Oktette je Paket statt drei) und zuletzt `0xF4`.

`mouse: id=3` — QEMUs Maus **hat** ein Rad, und der Treiber liest es.

**Der ganze Aufsetzweg läuft mit abgeschalteten Unterbrechungen.** Das ist
nicht Vorsicht, sondern notwendig: die Antworten des Geräts kommen über
*dasselbe Tor* wie später die Pakete. Wäre IRQ 12 dabei offen, läse die
Behandlungsroutine die Antwort weg, `take` bekäme das nächste Oktett und
der Aufsetzweg wäre um eines verschoben — ein Fehler, der sich als „das
Gerät hat kein Rad" tarnt.

### 2.1 Zehn Zusagen, die der Treiber selbst prüft

`mouse: selftest 10 / 10`. Darunter die beiden, die man verwechselt:

* **Eine Bewegung nach unten macht `y` größer**, obwohl die Maus nach
  unten *negativ* meldet. (Die Maus zählt y nach oben, der Bildschirm nach
  unten.)
* **Ein Überlaufpaket bewegt den Zeiger nicht.** Bit 6/7 des ersten
  Oktetts sagen, dass der Wert nicht mehr in neun Bit passte; er ist dann
  unbrauchbar, die Tasten aber nicht.

Dazu der Anschlag an allen vier Rändern, die Klickzählung an der *Flanke*
(Loslassen ist kein Klick) und der Anker: **Bit 3 des ersten Oktetts ist
immer gesetzt**, und was das nicht erfüllt, wird gezählt statt benutzt.

### 2.2 Der ehrliche Befund über IRQ 12 in QEMU

Die Aufgabe hat ihn vorweggenommen: *„Wenn PS/2 in QEMU zickt, ist USB-HID
der Ausweg — dann sag es und begründe."* PS/2 zickt, aber anders als
erwartet, und der Ausweg war nicht nötig. Was gemessen wurde:

Die **erste** Fassung der Wartschleife am Ende des Laufes war ein
Leerlauf (`while apic.tsc() < bis { poll; compose }`), ohne die Maschine
je herzugeben. Darin kam **genau eine** Unterbrechung an, und danach
nichts mehr: `irqs=1 packets=0 status=0x3d` — das Zustandstor meldete
„es liegt ein Oktett vom zweiten Anschluss bereit", und die Leitung blieb
stumm. Der Eintrag der Umleitungstabelle war dabei in Ordnung
(`gsi=0x2e`: Vektor 46, nicht maskiert).

Zwei Gegenmittel wurden gebaut, und **beide** stehen noch im Baum, weil
beide etwas messen:

1. **Der Rückfall auf Abfrage.** `wm.poll` sieht selbst im Baustein nach
   (Zustandstor Bit 0 und Bit 5) und holt ein Oktett ab, wenn eines da
   ist. Nachsehen und Lesen laufen mit abgeschalteter Unterbrechung —
   sonst holt die Behandlungsroutine dasselbe Oktett und die Paketgrenze
   verschiebt sich. Gemessen: **ohne** diese Klammer 18 verworfene Oktette
   bei 17 Paketen, **mit** ihr keines.
2. **Die Wartschleife gibt die Maschine her** (`sched.sleep_ticks`). Das
   war ohnehin nötig — die Anwendung in Ring 3 lief in dieser Zeit *nicht*
   und holte ihre Klickereignisse nicht ab, was im Bild als fehlender
   Klickfleck erschien und im Mitschnitt an gar nichts.

Nach (2) trägt **IRQ 12 allein**. Das ist gemessen und steht als Zusage
im Läufer: mit `nompoll` (Abfrage aus) kommen dieselben **15 Pakete** an,
der Zeiger landet auf demselben Bildpunkt (740, 599), der Klick erreicht
dasselbe Fenster — und `polls=0`. Im Regellauf teilen sich beide Wege die
Arbeit: `irqs=31 davon leer=16 abgefragt=45`.

„Leer" ist der dritte gemessene Befund: holt die Abfrage ein Oktett,
während die Unterbrechung dafür schon unterwegs ist, läuft die
Behandlungsroutine auf einen **leeren** Ausgabepuffer, und `in al, 0x60`
gibt das zuletzt gelesene Oktett noch einmal. Ohne die Prüfung auf Bit 0
wandert dieses Gespenst als Paketanfang in die Zustandsmaschine. Mit ihr:
`drops=0`.

**Warum kein USB-HID.** PS/2 trägt, der Baustein ist seit Runde 59
aufgesetzt, QEMU baut ihn bei `-machine pc` immer ein — und der
QEMU-Monitor kann ihn von außen bedienen (`mouse_move`, `mouse_button`).
Ohne das hätte diese Runde keine Messung, sondern eine Behauptung. Ein
USB-HID-Weg braucht davor einen xHCI-Treiber, Endpunkte, Deskriptoren und
eine Warteschlange; das ist eine Runde für sich und stünde hier als
halbfertiges Stück.

---

## 3. Der Fensterserver

### 3.1 Wo er läuft, und warum das gesagt gehört

**Im Kernel.** Das ist eine Entscheidung und keine Bequemlichkeit: ein
Fensterserver in Ring 3 braucht eine Nachrichtenschicht, die Speicher
zwischen Prozessen **teilt** — der Fensterpuffer muss in zwei
Adressräumen liegen —, und die hat dieser Kernel nicht. `mmap` kennt
anonyme Seiten und den Rahmenpuffer, sonst nichts (Runde K4/K7).

Was das kostet: den Schutz zwischen Server und Anwendung. Was es **nicht**
kostet: den Schutz zwischen den Anwendungen, und das ist der, um den es
beim Fenstern geht. Eine Anwendung sieht ihr Rechteck und kann nicht
danebenschreiben; sie sieht den Bildschirm nicht und weiß nicht, wo sie
liegt. Der Weg nach Ring 3 führt über ein Speicherobjekt, das zwei
Prozesse abbilden können — das ist die nächste Runde und steht unten unter
„was offen bleibt".

### 3.2 Anwendungen reden über Handles

Wie die Aufgabe es verlangt, und nicht über einen zweiten Weg. Ein
Fenster ist ein `K_CHANNEL` aus `kernel/cap.fi` mit Rechten:

| Recht | erlaubt |
|---|---|
| `R_WRITE` | `wm_fill`, `wm_text`, `wm_write`, `wm_flush` |
| `R_READ` | `wm_event` — Ereignisse abholen |
| `R_MANAGE` | `wm_move`, `wm_close` |

Neun Aufrufe ab **2100**, im Zahlenraum der nativen ABI und nicht bei den
POSIX-Nummern — weil ein Fenster ein Handle ist und kein Deskriptor: es
wird nicht geerbt, es hat Rechte, und wer es nicht bekommen hat, hat kein
Fenster.

**Das Objekt hinter dem Handle trägt zwei Zahlen:** unten den Platz in der
Fenstertafel, oben die laufende Nummer des Fensters. Wird ein Platz nach
dem Schließen neu vergeben, passt die laufende Nummer nicht mehr, und das
alte Handle trifft das neue Fenster **nicht**. Das ist dieselbe Regel wie
bei den Generationen der Handle-Tabelle, eine Stufe tiefer.

`wclick: passed 10 / 10` — und **die Hälfte davon sind Ablehnungen**, wie
bei `u_caps` und `u_fb`: ein Handle, das es nicht gibt, ein Fenster, das
geschlossen wurde, eine Größe, die kein Fenster ergibt.

### 3.3 Was der Server selbst prüft

`wm: selftest 17 / 17`. Die Kernaussagen:

* Ein zweites Fenster liegt **über** dem ersten, und der Treffer an einer
  Stelle, die beide bedecken, ist das obere. **Heben** ändert das.
* Der **Fokus** liegt bei genau einem Fenster, und eine Taste kommt dort
  an — und **nur** dort. (Mit `nofocus` bei beiden; genau daran hängt der
  Wert der Zusage.)
* Das Malen bleibt **im** Fenster: ein Bildpunkt jenseits der Kante wird
  nicht geschrieben, der letzte darin schon.
* Verschieben ändert die Stelle, nicht den Inhalt — und der schmutzige
  Bereich deckt **beide** Stellen, die alte und die neue. Ohne das bliebe
  ein Fenstergespenst stehen.
* Schließen schließt die **Lücke** in der Stapelreihenfolge.
* **Die Größe ändern** geht bis zur Größe, für die der Puffer geholt
  wurde, und darüber hinaus nicht — ein Fenster, das über seinen eigenen
  Puffer hinauswächst, wäre ein Schreibzugriff daneben. Ein
  Terminalfenster rechnet sein Raster dabei neu.

### 3.4 Die Wiederherstellung des Hintergrunds

Der Zeiger hinterlässt keine Spur, und zwar ohne ein gerettetes Rechteck:
bewegt er sich, werden **beide** Rechtecke schmutzig — das alte und das
neue. `compose` malt dort den Schreibtisch, dann die Fenster von unten
nach oben, dann den Zeiger. Ein gerettetes Rechteck wäre der zweite Weg
dahin und müsste bei jedem Fensterwechsel nachgezogen werden.

Gemessen wird es an der Stelle, an der es zählt: nach dem **Schließen**
eines Fensters steht dort wieder der Schreibtisch (0 von 2400 Bildpunkten
falsch) und dort, wo es das Terminalfenster verdeckte, wieder dessen
Fläche (0 von 3000 falsch).

---

## 4. Echte Schriften

### 4.1 Was gelesen wird

`head` (Einheiten je Geviert, Format von `loca`), `hhea` (Aufsteiger,
Absteiger, Zeilenzwischenraum, Zahl der Laufweiten), `maxp`, `hmtx`
(Laufweite je Glyphe), `cmap` **Format 4**, `loca`, `glyf` (Punkte,
gerade Stücke und **quadratische** Bezier — kubische gibt es erst in
OpenType/CFF) und `kern` **Format 0** für die Unterschneidung.

Zusammengesetzte Glyphen werden mit ihrer Verschiebung eingesetzt;
Drehung und Streckung **nicht** — das steht hier und wird nicht behauptet.

### 4.2 Alles in Festkomma

Es gibt keine Gleitkommazahlen in diesem Kernel und es soll keine geben:
`profile kernel` hat keine SSE-Rettung im Kontextwechsel, und eine
Rasterung, die je nach Rundungsmodus anders aussieht, ist nicht
nachprüfbar. Die Rechnung läuft in **26.6** — eine Einheit ist ein
Vierundsechzigstel Bildpunkt:

```
scale  = (px << 16) / upm          16.16
f26(v) = (v * scale) >> 10         Font-Einheit -> 26.6
```

Nachgemessen an `firnc`, **bevor** eine Zeile davon entstand:
`(0-7) / 2` ist `-3` (die Division schneidet zur Null hin ab) und
`(0-7) >> 1` ist `-4` (das Schieben ist arithmetisch, es rundet nach
unten). Beide Fassungen des Rasterers rechnen deshalb an denselben
Stellen mit denselben Zeichen.

### 4.3 Die Füllregel

Nichtnull-Windung mit **4 × 4-Unterabtastung**: vier Abtastzeilen je
Bildzeile, vier Abtastspalten je Bildpunkt. Das gibt siebzehn
Deckungsstufen (0..16) und daraus die Deckkraft `(cov * 255 + 8) / 16`.

Warum nicht die exakte Flächendeckung: sie braucht eine Division je Kante
und Bildzeile und ist an den Selbstüberschneidungen, die TrueType
erlaubt, nicht eindeutig. Vier mal vier ist grob genug zum Nachrechnen und
fein genug, dass man den Unterschied zum 8 × 16-Raster sofort sieht —
gemessen: **1023 von 5600 Bildpunkten** einer Textzeile sind
Zwischenstufen.

### 4.4 Woher die Schriften kommen

**Von der Platte.** Ein Zeichensatzleser, der seinen Zeichensatz im
Kernelabbild trägt, liest keinen. `tools/ttf/schnitt.py` schneidet aus
DejaVu die sieben (mit `kern` acht) Tabellen und 95 Zeichen heraus, die
ein Rasterer braucht:

```
assets/osum-mono.ttf: 96 Glyphen, 95 Zeichen, 14604 Oktette, kern=0 Paare
assets/osum-sans.ttf: 96 Glyphen, 95 Zeichen, 18676 Oktette, kern=220 Paare
```

760 KiB werden zu 15, ohne fontTools und ohne FreeType — reines `struct`,
derselbe Gedanke wie bei `tools/osum/mkfs.py`. Der Testläufer **schneidet
die Dateien neu und vergleicht sie Oktett für Oktett** mit denen im Baum.

### 4.5 Der Zwischenspeicher

Offene Adressierung mit linearem Sondieren, der Schlüssel trägt
Zeichensatz, Größe und Zeichen. Freigegeben wird nichts: eine Oberfläche
benutzt immer wieder dieselben Zeichen in denselben Größen. Der ganze
Arbeitsbereich — Index, Arbeitsfelder des Rasterers und die Bitmasken —
ist **ein Lauf aus 128 Rahmen (512 KiB)** aus dem Rahmenverwalter, nicht
aus dem Kernelhaufen; der ist 256 KiB groß und gehört allen.

---

## 5. Die Messungen

QEMU 7.2.22, **TCG** (kein KVM auf dieser Maschine), ein Prozessor,
256 MiB, `-vga std`. Zeitbasis ist der Prozessorzähler (`apic.tsc`,
geeicht in `hw.stage`).

### 5.1 Zusammensetzen mit und ohne Bereichsverfolgung

Zwanzig Durchläufe je Wert, in **einem** Lauf, auf derselben Maschine und
mit demselben Zähler:

| Vorgang | Zeit |
|---|---:|
| voller Bildaufbau (800 × 600, Schreibtisch + zwei Fenster + Zeiger) | **6 801 µs** |
| nur der Bereich einer Zeigerbewegung (12 × 18) | **198 µs** |
| **Faktor** | **34,3** |

**Und die Gegenprobe, ohne die die Zahl nichts bedeutet.** Mit `nodirty`
wird jede Meldung eines schmutzigen Bereichs zu „der ganze Schirm":

| | mit Bereichsverfolgung | mit `nodirty` |
|---|---:|---:|
| voller Bildaufbau | 6 801 µs | 7 073 µs |
| kleiner Bereich | **198 µs** | **7 485 µs** |

Der kleine Fall wird also **das Achtunddreißigfache** teurer, der große
bleibt gleich. Das ist der Unterschied zwischen einer Oberfläche, die man
bedienen kann, und einer, bei der der Zeiger ruckelt: sechs Millisekunden
je Zeigerbewegung sind unter 170 Bildern je Sekunde — bei hundert
Mauspaketen je Sekunde ist die Maschine damit ausgelastet.

### 5.2 Schriftrasterung mit und ohne Zwischenspeicher

95 Zeichen, DejaVu Sans Mono, eine Größe, die noch niemand angefragt hat:

| | Zeit | je Zeichen |
|---|---:|---:|
| frisch gerastert | **80 130 µs** | 843 µs |
| aus dem Zwischenspeicher | **134 µs** | 1,4 µs |
| **Faktor** | **598** | |

843 µs je Glyphe unter TCG sind viel — es sind Umrisse lesen, Bezier
zerlegen, sechzehn Abtastungen je Bildpunkt und eine Einfügesortierung je
Abtastzeile. Genau deshalb gibt es den Speicher, und genau deshalb steht
die Zahl hier: eine Textzeile von 56 Zeichen kostet beim ersten Mal
47 ms und danach 78 µs.

### 5.3 Was der Kernel nach dem Lauf meldet

```
wm: composites=42  blits=64  pixels=10564320  cached=173  hits=971  miss=173
```

173 verschiedene Glyphen (zwei Schriften, drei Größen), 971 Treffer im
Speicher gegen 173 Fehltreffer — **85 Prozent** aller Glyphenanfragen
werden aus dem Speicher beantwortet.

---

## 6. Wie die Bildschirmfotos geprüft werden

Der Weg ist der aus Runde K7 (`tools/gfx/schuss.py` holt über den
QEMU-Monitor ein PPM, `tools/gfx/schau.py` rechnet es nach) und diese
Runde legt zwei Dinge dazu.

### 6.1 Eingabe von außen — `tools/wm/monitor.py`

Ein Fensterserver, der nie eine Maus gesehen hat, ist keiner. Über
denselben Monitor gehen **`mouse_move`, `mouse_button` und `sendkey`** in
die laufende Maschine.

**Warum die Bewegungen klein sind und warum es erst in die Ecke geht.**
Ein PS/2-Paket trägt neun Bit je Achse; QEMU zerlegt größere Bewegungen
in mehrere Pakete, und geht dabei eines verloren, ist der Endpunkt ein
anderer. Ein Testlauf, der auf einen Bildpunkt genau rechnen will, fährt
deshalb zuerst mit sechs Schritten von −120 in die linke obere Ecke — dort
hält der Anschlag und die Vorgeschichte ist gelöscht — und danach mit
Schritten unter 128 an die Stelle, die er meint. Von da an ist der Ort
eine **Rechnung** und keine Hoffnung:

```
OK    der Zeiger landet waagerecht, wo er soll: 740
OK    und senkrecht ebenso: 599
OK    Pakete, die der Treiber zusammengesetzt hat: 15
OK    und KEIN Oktett, das er wegwerfen musste: 0
```

### 6.2 Text: **je Zeichen**, nicht je Fläche

**Die Warnung aus Runde K7B wurde ernst genommen.** Dort schien Text zu
87 Prozent zu stimmen, während in Wahrheit *jeder Buchstabe* fehlte — die
87 Prozent waren schwarzer Hintergrund. Bei einer kantengeglätteten
Schrift gibt es keine Bitmaske mehr, gegen die man Bit für Bit rechnen
kann; es gibt einen **Algorithmus**. Also steht der Algorithmus zweimal
da:

* `kernel/ttf.fi` — im Kernel, in Firn.
* `tools/ttf/raster.py` — auf dem Wirt, in Python, mit denselben
  Verschiebungen und derselben Rundung.

Und der Prüfer zählt nicht Bildpunkte gegen die Fläche, sondern **je
Zeichen**:

1. die **gesetzten** Bildpunkte der Vorlage (Deckkraft > 0),
2. wie viele davon im Bild wirklich mit der erwarteten Mischfarbe stehen,
3. und er **fällt**, wenn ein Zeichen mit Umriss im Bild *keine Tinte*
   hat — egal wie viel Hintergrund stimmt.

```
OK  Zeile 0 des Terminalfensters (23 Zeichen, 1413 Tintenpunkte, 0 falsch)
OK  Zeile 1 des Terminalfensters (28 Zeichen, 1463 Tintenpunkte, 0 falsch)
OK  der Titel des Fensters aus Ring 3, mit Unterschneidung
    (9 Zeichen, 377 Tintenpunkte geprueft, 0 falsch)
```

Und die Gegenprobe zum Prüfer selbst: dieselbe Rechnung auf eine **leere**
Rasterzeile geht *nicht* auf, und sie sagt auch warum —
`1413 falsch -- LEER: O S U M K 1 0 W I N D O W S E R V E R 0 1 2 3`.

Dazu `schau.py glatt`: wie viele Bildpunkte eines Rechtecks sind **weder**
Vorder- **noch** Hintergrundfarbe? Eine Rasterung ohne Kantenglättung hat
davon keinen einzigen und ginge durch alles oben hindurch.

### 6.3 Der Rasterer gegen sich selbst — ohne Umweg über das Bild

`ttfdump` lässt den Kernel acht Glyphen als Text **und als Prüfsumme über
die rohen Deckungswerte** (FNV-1a) ausgeben; `tools/ttf/raster.py
vergleich` rastert dieselben Zeichen selbst und hält Maße, Prüfsumme und
jede Bildzeile dagegen:

```
8 Glyphen, 462 Tintenpunkte: 0 abweichend
```

Und die Gegenprobe zum Vergleich: gegen die *andere* Schrift geht er
nicht auf.

### 6.4 Geometrie: `rechteck`

Die vier Kanten eines Rechtecks haben die Farbe, und **einen Bildpunkt
außerhalb hat sie nicht**. Damit lässt sich nachrechnen, dass ein Fenster
wirklich an der Stelle und in der Größe liegt, an der der Server es führt:

```
OK  der Rahmen des Fensters aus Ring 3 liegt bildpunktgenau
    (Rahmen 264x174 bei (420,330): 0 von 876 Kantenpunkten falsch,
     0 Treffer eine Reihe daneben)
```

---

## 7. Was die Zusagen wirklich zeigen

### 7.1 Der Klick kommt beim richtigen Fenster an

Der Zeiger fährt auf (500, 400), die linke Taste geht herunter und wieder
hoch, und der Zeiger fährt weg (sonst verdeckt er, was er ausgelöst hat).
(500, 400) auf dem Schirm ist **(78, 48) im Fenster** — 500 − 420 − 2 und
400 − 330 − 22. Und genau das meldet Ring 3:

```
wclick: down 78,48
```

Die Anwendung malt daraufhin ein 8 × 8 großes Feld an genau diese Stelle
ihres Fensters, und im Foto steht es an genau der Stelle des Bildschirms:

```
OK  der Fleck, den Ring 3 auf den Klick hin gemalt hat (0 von 64 falsch)
OK  und einen Bildpunkt daneben ist er nicht
OK  ohne Klick ist der Fleck NICHT da
OK  ein Klick auf den Hintergrund kommt bei KEINEM Fenster an
```

### 7.2 Der Eingabefokus — und die Gegenprobe, die ihn beweist

Vier Tastendrücke über `sendkey`:

| | Fenster 0 (Terminal) | Fenster 1 (Fokus) |
|---|---:|---:|
| Regellauf | **0** | **4** |
| mit `nofocus` | **4** | 4 |

Das ist die Zusage aus der Aufgabe, wörtlich: *„mit abgeschaltetem Fokus
darf die Tastatur beim falschen Fenster NICHT ankommen"* — sie kommt dann
an, und darum ist die Null darüber etwas wert.

### 7.3 Verschieben und Schließen, mit der Maus

Gedrückt auf der Titelleiste bei (460, 340), 120 Bildpunkte nach links
oben gezogen, losgelassen: das Fenster steht bei (300, 210), der Rahmen
bildpunktgenau, **der Titel ist mitgewandert** (377 Tintenpunkte, 0
falsch), und an der alten Stelle ist er weg.

Ein Klick auf das rote Feld schließt es: `wmafter: n=1` (vorher 2), der
Rahmen ist fort, und darunter steht wieder, was darunter lag.

### 7.4 Die Shell im Terminalfenster

Die Zeilendisziplin aus Runde K9 ist ausdrücklich so gebaut, dass das
**Anzeigegerät austauschbar** ist (`tty.SINK_SCREEN`, mit dem Kommentar
„für den Tag, an dem der Schirm eine eigene Fläche bekommt"). Diese Runde
trägt sich dort ein: **`SINK_WINDOW`** schreibt in ein Fenster des Servers
— **und weiter auf die serielle Leitung**. Das zweite ist kein Rest,
sondern Absicht: der serielle Mitschnitt ist in diesem Projekt die
Grundwahrheit, gegen die ein Bildschirmfoto gerechnet wird. Ginge er hier
verloren, wäre der Text im Fenster gegen nichts mehr zu halten.

`/bin/sh` von der Platte, dasselbe Programm wie in den Runden K1 und K6,
läuft in dem Fenster, und was es schreibt, steht darin:

```
OK  die Shell von der Platte ist gestartet
OK  und sich sauber beendet: 0
OK  die Ausgabe der Shell steht bildpunktgenau in Zeile 9 des Fensters
    (13 Zeichen, 588 Tintenpunkte, 0 falsch)
```

**Welche** Rasterzeile das ist, hängt daran, wie viele Zeilen die Shell
vorher geschrieben hat — also wird sie gesucht statt geraten, und wenn sie
in keiner aufgeht, fällt die Zusage.

Ein Nebenbefund, der dazugehört: die Kommandozeile trägt **ein** Skript
(`script=...`), und es wird von dem gelesen, der zuerst danach greift.
Runde K1 startet eine Shell im Kernelabbild, Runde K6 eine von der Platte
— beide *vor* der Oberfläche. `wmshell` hält jetzt beide zurück. Ohne das
las die erste das Skript weg, und im Fenster stand eine leere
Eingabezeile.

---

## 8. Die vier Fehler dieser Runde

Sie stehen hier, weil sie mehr über den Baum sagen als die grünen Zeilen.

### 8.1 Der Kantenzähler lag auf den Punktflaggen

`SLOTS * 64` ist genau `0x8000`, `MAX_EDGES * 32` ist genau `0xC000`. Der
Zähler der Kanten lag in der ersten Fassung *hinter* dem Kantenfeld — also
auf `0x14000`, und dort liegen die Flaggen der Punkte. Die erste Glyphe
überschrieb ihren eigenen Kantenzähler, `edge_count` gab eine Zufallszahl,
und der Kern las bei `0x40000000` weiter — der ersten Adresse jenseits des
abgebildeten Gigabytes: **`#PF, cr2=0x40000000`**.

Genau die Fehlerklasse, die `tools/kernel/karte.py` seit K7B für `kdata`
abfängt. Im Arbeitsbereich des Rasterers gibt es keinen solchen Prüfer,
also stehen die Rechnungen jetzt als Kommentar neben den Adressen.

### 8.2 Die Einfügesortierung schrieb an `n` statt an `i`

Die Schnittpunkte einer Abtastzeile müssen nach `x` geordnet sein, sonst
stimmt die Windungszahl nicht. Die Einfügesortierung schob die größeren
Werte nach oben und schrieb den neuen dann an das **Ende** statt an die
frei gewordene Stelle.

Solange nichts verschoben werden musste, ist das dasselbe — und genau
deshalb sah es richtig aus: Glyphen mit **zwei** Schnittpunkten je
Abtastzeile (`E`, `I`, `l`, `T`) kamen fehlerfrei heraus. Bei **vier** —
den beiden Schenkeln eines `V`, dem Innenraum eines `R` — ging der eben
verschobene Wert verloren.

Im Bild sah man: **`V` unsichtbar, `R` ausgefüllt.** Die Maße (Breite,
Höhe, linke Kante, Laufweite) waren dabei die ganze Zeit richtig — der
Umriss war gelesen, nur die Füllung war falsch. Gefunden hat es nicht das
Foto, sondern `ttfdump`: die Glyphe als Text auf der seriellen Leitung,
neben die Ausgabe von `tools/ttf/raster.py` gehalten.

### 8.3 `VEC_MOUSE` war `VEC_NVME`

Der Maustreiber bekam **Vektor 44** — und 44 ist seit Runde K2 der Vektor
des NVMe-Reglers. Die Weiche in `trap.fi` ist eine Kette von `if`s; die
Mausbedingung stand vor der NVMe-Bedingung, und damit gingen **alle
Abschlussmeldungen des Reglers an den Maustreiber**: `nvme: irqs=0` statt
`irqs=5`, in jedem Lauf — **auch ohne das Wort `wm`**.

Das ist der schlimmste der vier Fehler dieser Runde, weil er eine Zusage
brach, die mit der Oberfläche nichts zu tun hat, und weil `tools/wm/run.sh`
ihn *nicht* sehen konnte. Gefunden hat ihn **Abschnitt 6 von `./test.sh`**
— genau dafür läuft die ganze Abnahme und nicht nur der Läufer der Runde.

`tools/kernel/karte.py` rechnet seither auch die **Vektortabelle** nach.
Die Regel ist dieselbe wie bei `kdata`: derselbe Name darf mehrfach
dastehen (`trap.fi` und `nvme.fi` führen `VEC_NVME` beide, weil Firn keine
Konstante eines anderen Moduls in einen `const` einsetzt), **zwei
verschiedene Namen dürfen nicht auf derselben Zahl liegen**:

```
  ---- die Vektortabelle ----
   32  VEC_TIMER
   33  VEC_KEYBOARD
   44  VEC_NVME
   45  VEC_NET
   46  VEC_MOUSE
   47  VEC_SPURIOUS
```

Und die Gegenprobe zum Prüfer: setzt man `VEC_MOUSE` in einer Kopie auf
44 zurück, **muss** er anschlagen.

### 8.4 `W_KEYS` lag auf `W_CELLH`

Der Zähler „wie viele Tasten hat dieses Fenster bekommen" bekam den
Versatz `0xA8` im Fensterdatensatz — und dort liegt die Zellenhöhe. Die
Zahl der Tastenereignisse des Terminalfensters war danach **genau seine
Zellenhöhe: neunzehn**, ohne dass eine Taste gedrückt worden wäre.

Dieselbe Sorte Fehler wie Runde K7B, eine Ebene tiefer, und derselbe
Grund: eine Belegung, die nirgends nachgerechnet wird. Für `kdata` gibt es
den Prüfer; für die Felder eines Datensatzes nicht.

Ein fünfter Befund gehört daneben, auch wenn er kein Fehler im Code war:
die Wartschleife am Ende gab die Maschine nicht her, und die Anwendung in
Ring 3 holte ihre Klickereignisse nicht mehr ab. Im Bild fehlte der
Klickfleck, im Mitschnitt stand nichts. Das Gegenmittel war eine Zeile
(`sched.sleep_ticks`), das Finden dauerte länger.

---

## 9. Die Abnahme, und die eine rote Zeile, die nicht dieser Runde gehört

`./test.sh` auf diesem Zweig:

```
FREESTANDING 41 · CORE 46 · KERNEL 175 · OSUM 130 · PCI 97 · POSIX 134 ·
SMP 58 · USERLAND 91 · CAPS 67 · BOOT 20 · GFX 76 · UNIX 107 ·
NET 74 (von 75) · WM 103
14 Abschnitte bestanden, 1 fehlgeschlagen, 1228 Zusagen
```

Die **1126 Zusagen von vorher sind vollständig da** und keine ist
gesunken; dazu kommen die **103** dieser Runde. Die eine rote Zeile steht
in Abschnitt 14 (Netz):

```
FAIL  and all of them arrived: 64240, expected eq 65536
```

Das ist der Fall mit **zehn Prozent Paketverlust auf dem Weg hinaus**
(`tools/net/run.sh`, Abschnitt 9, zweite Hälfte). `docs/ROUNDK7B.md`
Abschnitt 6 nennt genau diese Stelle bereits als „wetterfühlig" und
schreibt sie K8 zu.

**Nachgemessen, statt behauptet.** Derselbe Läufer auf `main` — dem
unveränderten Stand, von dem dieser Zweig ausgeht — auf derselben
Maschine:

```
main:      NET: 66 passed, 9 failed
k10-wm:    NET: 74 passed, 1 failed
```

und die rote Zeile ist dort **wortgleich und zahlengleich** dieselbe
(`64240, expected eq 65536`). Der Fehler ist also älter als diese Runde
und wird von ihr nicht verursacht — sie berührt keinen Netzpfad. Dass
`main` in diesem Lauf schlechter abschnitt, hat einen benennbaren Grund:
`tools/net/run.sh` legt seine Leitung unter **festen globalen Namen** an
(Namensraum `k8net`, veth-Paar `v0`/`v1`, 10.9.0.1/2) und beginnt mit
`ip link del v0`. Laufen zwei Abnahmen aus zwei Arbeitsverzeichnissen
gleichzeitig, reißt die eine der anderen die Leitung unter dem
laufenden TCP-Strom weg. Das gehört K8 und steht hier, damit es nicht
noch einmal jemand sucht.

## 10. Die Speicherkarte

Drei neue Bereiche, und sie stehen in `kernel/kstate.fi` — dort, wo Runde
K7 ihren nicht hingeschrieben hat:

```
0x1D000..0x1E000  MOUSE   der Zustand des Zeigegeraets
0x3D000..0x3F000  WM      Skalare, acht Fenster, acht Ereignisringe
0x3F000..0x40000  TTF     die Zeichensatzplaetze des Schriftlesers
```

`tools/kernel/karte.py` rechnet jetzt **41 Bereiche** paarweise
gegeneinander — und seit dieser Runde zusätzlich die **Vektortabelle**
(siehe 8.3), und der Läufer prüft zusätzlich, dass jeder der drei neuen
Namen wirklich in der Karte steht. Dazu die Gegenprobe zum Prüfer selbst:
legt man `WM_OFF` auf die Seite des Rahmenpuffers, **muss** er anschlagen.

Alles, was groß ist, liegt **nicht** in `kdata`: der Arbeitsbereich des
Schriftlesers (512 KiB) und die Fensterpuffer (je Breite × Höhe × 4)
kommen aus `mem.frame_run`. `mem.frame_free_run` gibt sie beim Schließen
zurück — ohne das wären acht geöffnete und geschlossene Fenster vier
Megabyte, die niemand mehr sieht.

---

## 11. Was offen bleibt

* **Der Server läuft im Kernel.** Der Weg nach Ring 3 führt über ein
  Speicherobjekt, das zwei Prozesse abbilden können (`K_MEMORY` +
  `mmap` darauf). Das ist die nächste Runde; solange es fehlt, steht der
  Satz aus 3.1 hier und nicht in einer Fußnote.
* **Kein `ioctl` für die Fläche.** Eine Anwendung erfährt ihre Größe über
  `wm_info` und über ein `E_RESIZE`-Ereignis, aber sie kann die
  Bildschirmauflösung nicht ändern.
* **Der Rasterer kennt keine Drehung.** Zusammengesetzte Glyphen werden
  mit ihrer Verschiebung eingesetzt, nicht mit ihrer Matrix. Für 0x20 bis
  0x7E in DejaVu kommt das nicht vor; für Umlaute schon.
* **Kein Hinting, keine Unterpixel-Positionierung.** Eine Glyphe wird auf
  ganze Bildpunkte gesetzt; bei kleinen Größen sieht man das an den
  Senkrechten. Der Zwischenspeicher ist auf ganze Bildpunkte gebaut und
  müsste dafür die Bruchteilstellung mit in den Schlüssel nehmen.
* **`kern` Format 0, sonst nichts.** Moderne Schriften legen die
  Unterschneidung in `GPOS`; DejaVu hat beides, und dieser Leser nimmt die
  einfache Tabelle. Ohne `kern` gibt es keine Unterschneidung, und das
  meldet der Läufer als Zahl (0) statt es zu verschweigen.
* **Acht Fenster, 32 Ereignisse je Ring.** Ein Ring, der überläuft,
  verliert das älteste; die Zahl steht in `S_EVDROP`, aber es gibt kein
  Warten und keinen Gegendruck.
* **Keine Sperre um den Fensterserver.** Er läuft auf einem Prozessor;
  unter `-smp 4` würde ein zweiter Kern in denselben Arbeitsfeldern des
  Rasterers schreiben. `tools/wm/run.sh` fährt deshalb mit einem Kern.
* **Der Schriftschnitt hängt an DejaVu auf dem Wirt.** Liegt es nicht
  unter `/usr/share/fonts/truetype/dejavu`, wird die Reproduktion
  übersprungen und der Läufer sagt es — die Dateien im Baum werden
  trotzdem geprüft.
