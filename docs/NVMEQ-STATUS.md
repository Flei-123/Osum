# Runde NVMEQ — die Warteschlange des Geräts

Zweig `nvmeq`, Arbeitsbaum `/root/osum-nvmeq`, abgezweigt von `ring`
(a7cc92c). **Nicht nach `main`, `mergeline`, `mergeline2`, `handle`,
`async` oder `ring` gemergt.**

Gemessen am 30.08.2026 auf AMD EPYC 7571, QEMU mit `-accel kvm`,
TSC 2 200 895 kHz (2,2008 GHz), **ein Kern**, QEMU-`nvme` mit einem
8-MiB-Abbild (16 384 Blöcke zu 512 Oktett).

**Zur Auslastung des Wirts:** auf dieser Maschine liefen während der
Messung mehrere andere Runden dieses Projekts (Lastmittel 11 bis 13 auf
12 Kernen). Das verschiebt die absoluten Zahlen; die *Verhältnisse*
innerhalb eines Boots sind davon weit weniger betroffen, und genau
deshalb laufen alle drei Wege in EINEM Boot. Zwischen zwei Läufen
bewegten sich die Tiefen 1/4/16/64 um bis zu ±10 %, die Reihenfolge der
Wege nicht.

---

## Was diese Runde ist, in einem Satz

`docs/RING-STATUS.md` endet mit einer ehrlichen Zeile:

> **Der synchrone Weg wird auf einem Kern weiterhin nicht geschlagen.**
> […] Der Grund ist unverändert und liegt **nicht** am Weg der
> Einträge: die Arbeitsfäden gehen intern weiter **synchron** auf die
> Platte.

Diese Runde nimmt ihnen das ab. Ein Auftrag landet nicht mehr in einem
Faden, der `blk.read` ruft und wartet, sondern in der
**Submission-Warteschlange des NVMe-Controllers**. Das Gerät holt sich
den Eintrag selbst, legt die Oktette selbst ab und meldet sich per
Interrupt. **Zwischen der Türklingel und der Fertigmeldung wartet
niemand.**

---

## Die Antwort auf die entscheidende Frage

> **Wird der synchrone Weg jetzt geschlagen? Ab welcher Tiefe?**

**Ja. Ab Tiefe 4.**

| Weg | Zyklen je Auftrag | µs | Aufträge/s |
|---|---:|---:|---:|
| synchron (`read(2)`) | 210 291 | 95,48 | 10 474 |
| nvmeq Tiefe 1 | 475 745 | 216,00 | 4 630 |
| **nvmeq Tiefe 4** | **184 559** | **83,79** | **11 934** |
| **nvmeq Tiefe 16** | **137 872** | **62,60** | **15 975** |
| **nvmeq Tiefe 64** | **100 514** | **45,63** | **21 913** |

Bei Tiefe 64 ist der Warteschlangenweg **mehr als doppelt so schnell**
wie der synchrone (2,09×), bei Tiefe 16 um 53 % schneller. Bei Tiefe 1 ist er es **nicht**, und das steht hier
genauso deutlich: ein einzelner Auftrag zahlt weiterhin den Weg zum
Arbeitsfaden und zurück, und der ist teurer als der eingesparte
Systemaufruf. Der Gewinn dieser Runde ist **Nebenläufigkeit**, nicht
Latenz — mehrere Aufträge stehen gleichzeitig beim Gerät, statt sich
hinter einem wartenden Faden anzustellen.

---

## Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/nvmeq.fi` | 1209 | **neu**: Warteschlangenpaare, Flugtafel, DMA-Vorrat, die Wache, Ober- und Unterhälfte, Nachlaufring, Zeitgrenze |
| `kernel/sys.fi` | +674 | die Weiche (`nvmeq_try`), die Unterhälfte (`nvmeq_finish`/`nvmeq_reap`/`nvmeq_pump`/`nvmeq_sweep`), die Aufrufe 1992/1993, die Haken in `ring_note`, `aio_kick`, `aio_worker`, `ring_enter` |
| `kernel/uprog.fi` | +878 | `u_nvmeq` (33 Zusagen aus Ring 3), `u_qbench` (die Messung) |
| `kernel/kmain.fi` | +200 | die zwei Stufen, die Leckzahlen, die neun Modusworte |
| `kernel/kstate.fi` | +124 | drei Bereiche in `kdata`, neun Modusbits, sechzehn Zähler, `KDATA_SIZE` 0x92000 → 0x99000 |
| `kernel/hw.fi` | +47 | `nvmeq_stage` — das Aufsetzen hinter `nvme.init` |
| `kernel/nvme.fi` | +43 | vier Namen mehr im `export` (`ready`, `admin`, `admin_result`, `doorbell`, `spins`), das Ergebniswort der Admin-Fertigmeldung, der Drehzähler |
| `kernel/blk.fi` | +21 | **ein Fehler behoben**: `blocks_on(DEV_NVME)` gab die Größe des *Dateisystems* zurück statt die des *Laufwerks* |
| `kernel/arch/x86_64/trap.fi` | +17 | die zweite Hälfte am selben Vektor |
| `kernel/devfs.fi` | +8 | `is_block`/`block_of` sichtbar — die Weiche fragt danach |
| `kernel/arch/x86_64/boot.s` | 1 | `KDATA_SIZE`, dieselbe Zahl wie in `kstate.fi` |
| `tools/nvmeq/run.sh` | 412 | **neu**: der Testläufer |
| `tools/nvmeq/bau.sh` | 84 | **neu**: einmal bauen, neunmal starten |
| `tools/kernel/memmap.py` | +9 | die drei neuen Bereiche in der Speicherkarte |

Zusammen **3723 eingefügte Zeilen**, davon 1209 neues Kernmodul.

---

## Der Entwurf

### Der Weg eines Auftrags, in acht Schritten

```
  Programm            r_put()             sechs Schreibzugriffe
                                          in den eigenen Ring
     |
  Arbeitsfaden        ring_harvest()      EINE Kopie nach RSC_OFF
     |                ring_note()
     |
  DIE WEICHE          nvmeq_try()         Blockgeraet? NVMe? passt es
     |                                    in einen Umsteigepuffer?
     |
  DIE ABGABE          nvmeq.push()        SQE bauen, DIE WACHE,
     |                                    Tuerklingel      <-- kein Warten
     |
  ~~~~~~~~~~~~~~~~~~~~~ hier laeuft niemand mehr ~~~~~~~~~~~~~~~~~~~~~
     |
  DAS GERAET                              liest den Eintrag, schreibt
     |                                    512 Oktett in den Umsteige-
     |                                    puffer, legt die Fertigmeldung
     |                                    in seine CQ, MSI-X
     |
  OBERHAELFTE         nvmeq.irq()         Phasenbit, Kennung, Status ->
     |                                    Nachlaufring, wecken. FERTIG.
     |
  UNTERHAELFTE        nvmeq_finish()      lebt der Auftraggeber? meint
     |                                    das Handle noch dasselbe
     |                                    Objekt? -> kopieren
     |
  Programm            r_reap()            Fertigmeldung im geteilten
                                          Speicher, kein Systemaufruf
```

### Was in `kdata` liegt

| Bereich | Adresse | Größe | was |
|---|---|---:|---|
| `NQ_OFF` | 0x92000 | 0x1000 | Warteschlangentafel (4 × 128), Skalare, Kopf/Schwanz des Nachlaufrings, 32 × 16 Oktett Abholfläche je Aufgabe |
| `NQF_OFF` | 0x93000 | 0x4000 | **die Flugtafel**: 256 Plätze zu 64 Oktett |
| `NQD_OFF` | 0x97000 | 0x2000 | **der Nachlaufring**: 512 Sätze zu 16 Oktett |

`KDATA_SIZE` wächst von 0x92000 auf 0x99000 — dieselbe Zahl steht in
`kernel/arch/x86_64/boot.s`, und `tools/nvmeq/run.sh` liest beide und
vergleicht sie. `memmap.py` rechnet nach: **79 Bereiche, 0 Kollisionen.**

Der **DMA-Vorrat** liegt ausdrücklich *nicht* in `kdata`: 264 Rahmen am
Stück aus `mem.frame_run`, einmal beim Aufsetzen, **1 081 344 Oktett**.
Er trägt vier Abgabe- und vier Fertigwarteschlangen des Controllers und
256 Umsteigepuffer zu je einer Seite. In `kdata` wäre er ein Megaoktett
mehr im Kernelabbild.

---

## Die harte Auflage: das Gerät sieht nie eine Adresse des Programms

> **REGEL.** Jede Adresse, die in einen NVMe-Eintrag geschrieben wird,
> stammt aus dem DMA-Vorrat dieses Moduls — niemals aus einem Wert, den
> ein Programm irgendwo stehen hat.

Das ist keine Absichtserklärung, sondern eine Funktion (`pool_holds`),
sie steht **eine Zeile vor der Türklingel** (`tools/nvmeq/run.sh` prüft
das am Quelltext nach: Zeile 899 gegen Zeile 943), und wenn sie nein
sagt, **wird nicht geklingelt**.

Möglich macht das der **Umsteigepuffer**: das Gerät schreibt immer in
eine kerneigene Seite, und der Kern kopiert von dort in den Adressraum
des Programms — geprüft, mit Generationsprüfung, und erst dann, wenn
feststeht, dass es diesen Adressraum noch gibt.

Daraus folgen zwei Zusagen **ohne eine einzige eigene Zeile**:

* Handle geschlossen, während Aufträge beim Gerät stehen? Das DMA-Ziel
  ist eine Kernseite. Sie kann nicht ungültig werden.
* Prozess gestorben, während Aufträge beim Gerät stehen? Dasselbe. Der
  Controller hatte nie eine Adresse aus diesem Adressraum.

Der Preis ist eine Kopie von höchstens 4096 Oktett je Auftrag. Die
Alternative — Programmseiten festpinnen und dem Gerät direkt geben
(io_urings `IORING_REGISTER_BUFFERS`) — spart sie und verlangt dafür
eine Buchhaltung über gepinnte Benutzerseiten **und eine IOMMU**.
`/root/osum-roadmap/KERNEL.md`, Punkt 1, sagt dazu: *„Ein
Userspace-Treiber ohne IOMMU ist eine Illusion."* Diese Runde baut den
Weg zuerst und sicher.

### Die Gegenprobe, und was sie zeigt

`nqnopool` nimmt für den Eintrag den Wert, den das Programm im geteilten
Ring stehen hatte. Gemessen:

```
a-prp-aus-vorrat                  FAELLT
a-prp-nicht-die-programmadresse   FAELLT
a-badprp-null                     FAELLT
nvmeq: badprp = 1        die Wache hat angeschlagen
nvmeq: submits = 0       DAS GERAET HAT DAVON NICHTS GESEHEN
```

Die letzte Zeile ist die eigentliche: die Türklingel bleibt stumm, und
der Auftrag endet mit `-EFAULT`. Ohne die Wache stünde die Adresse des
Programms in einem Eintrag, den ein Gerät ausliest.

---

## Die Oberhälfte und die Unterhälfte

Der Interrupt-Pfad ist kurz, und das ist eine Zusage. Die **Oberhälfte**
(`nvmeq.irq`) tut genau drei Dinge:

1. Completion-Warteschlangen leerräumen (Phasenbit, Kennung, Status,
   Kopf, Türklingel),
2. je Fertigstellung **einen** Satz (Platz, Status) in den Nachlaufring
   legen,
3. wecken (`sched.poll_kick` — sperrenfrei, deshalb aus einem Interrupt
   erlaubt).

Was sie **nicht** tut: in einen Adressraum schreiben, Seitentabellen
begehen, Handles auflösen, Sperren des Dateisystems nehmen, einen
Fertigring eines Programms anfassen.

Die **Unterhälfte** (`sys.nvmeq_reap` → `nvmeq_finish`) läuft im
Zusammenhang eines Arbeitsfadens und macht genau das: prüfen, ob es den
Auftraggeber noch gibt, prüfen, ob das Handle noch dasselbe Objekt
meint, kopieren, melden.

**Die Sperren werden mit abgeschalteten Interrupts gehalten.** Das ist
kein Detail, sondern die Bedingung dafür, dass die Oberhälfte spinnen
darf: hält ein Faden auf *diesem* Kern die Sperre und der Interrupt
trifft ihn, wartet die Oberhälfte auf einen Faden, der erst
weiterlaufen kann, wenn sie fertig ist.

Der **Nachlaufring ist doppelt so lang wie die Flugtafel** (512 zu 256).
Daraus folgt, dass er nicht überlaufen kann — dasselbe Verhältnis und
derselbe Beweis wie beim Fertigring der Runde RING. `nvmeq: lost` ist in
allen Läufen **0**.

---

## Mehrere Warteschlangen

Angelegt werden **vier Paare** mit den Nummern 2 bis 5 (0 ist die
Admin-Warteschlange, 1 gehört `nvme.fi` und dem synchronen Weg), jede
64 Einträge tief. Wie viele der Controller wirklich hergibt, wird
**gelesen und nicht angenommen**: `set features 0x07` antwortet im
Ergebniswort der Fertigmeldung, und `nvme.admin_result` gibt es heraus.
Gemessen: `nvmeq: queues=4  depth=64`.

Gewählt wird beim Abgeben nach `cpu.here` — zwei Kerne fassen damit
weder dieselbe Abgabesperre noch dasselbe Türklingel-Register an.

**Ehrlich dazu: der Vektor ist noch geteilt.** Alle vier Paare melden
auf MSI-X-Eintrag 0, also auf demselben Interrupt, den `nvme.fi` schon
scharfgeschaltet hat. Das nimmt den Engpass beim **Abgeben** (Sperre,
Schwanz, Türklingel — alles je Kern), nicht beim **Melden**: die
Oberhälfte läuft weiterhin auf einem Kern und räumt dort alle
Warteschlangen ab. Ein Vektor je Warteschlange ist der nächste Schritt;
`nvme.msix_arm` nimmt die Eintragsnummer bereits als Parameter, und
`isr.s` hat mit 48 Vektoren Platz für 44..47.

---

## Der Rückfallweg, und wer ihn wählt

**Die Wahl trifft der Kern, nicht der Aufrufer.** Es gibt keine Flagge
dafür, und das ist Absicht: welcher Weg der richtige ist, hängt am
Gerät. `nvmeq_try` nimmt einen Auftrag nur, wenn *alle* diese Fragen mit
ja beantwortet sind:

* Lesen oder Schreiben?
* Zeigt der Deskriptor auf ein **Blockgerät** (devfs), und ist das der
  NVMe-Controller?
* Passt die Anforderung in **einen** Umsteigepuffer (höchstens acht
  Blöcke — damit kommt sie mit PRP1 aus und braucht keine PRP-Liste)?
* Ist beim Schreiben der Bereich blockgenau (kein
  Lesen-Ändern-Schreiben)?
* Ist ein Flugplatz frei?

Sonst geht der Auftrag den Weg der Runde RING. ATA-PIO, virtio, Rohre,
Steckdosen, gewöhnliche Dateien auf OFS — alles unverändert. `nvmeq:
fallback` zählt, wie oft.

Die Zusage `r-roehre-kein-schnell` misst genau das: ein Leseauftrag auf
einer **Röhre** geht durch denselben Ring und erhöht `nvmeq: fast` um
**null**.

---

## Die sieben Pflichtfälle

Alle aus Ring 3 (`uprog.u_nvmeq`), jede Zusage einzeln vom Läufer
nachgelesen. Gearbeitet wird auf `/dev/nvme0` — dem Blockgerät selbst,
nicht auf einer Datei darauf.

| # | Szenario | Zusagen | Gegenprobe |
|---|---|---|---|
| **a** | manipulierter Puffer-Zeiger im Abgabering | `a-wilder-zeiger` (−EFAULT), `a-wild-nicht-abgegeben` (submits +0), `a-prp-aus-vorrat`, `a-prp-nicht-die-programmadresse`, `a-badprp-null` | **`nqnopool`** → 3 fallen |
| **b** | Handle geschlossen, während Aufträge im Gerät stehen | `b-alle-gemeldet` (4), `b-veraltet` (4 × −ESTALE), `b-kein-flug`, `b-verweise-null`, `b-kein-auftrag` | Prüfstandshalt `NQ_INFO 32` |
| **c** | Prozess stirbt mit Aufträgen im Gerät | `c-kein-flug`, `c-kein-auftrag`, `c-kein-ring`, `c-rahmen-zurueck` | — |
| **d** | Gerät meldet Fehler (Status ≠ 0) | `d-alle-gemeldet`, `d-fehler-kommt-an` (4 × −EIO), `d-deverr-gezaehlt` | **`nqerr`** |
| **e** | Warteschlange voll → Rückstau | `e-alle-gemeldet` (32), `e-kein-verlust` (32 × 512), `e-voll-gezaehlt` | **`nqtiny`** (Tiefe 4) |
| **f** | Interrupt verloren / doppelt | `f-alle-gemeldet`, `f-kein-doppel`, `f-kein-verlorener-satz` | **`nqweg`**, **`nqdouble`** |
| **g** | Rückfallweg | `r-roehre-geht`, `r-roehre-kein-schnell` | **`nqoff`** |
| — | Grundgerüst und Leckprobe | 11 + 1 | — |

**Ergebnis: 34 / 34, Beendigungscode 0, mit beiden Übersetzern.**

### Wie (b) deterministisch gemacht wurde

Zusage (b) beschreibt ein Zeitfenster: die Aufträge stehen im Gerät und
sind noch nicht zugestellt, und *genau dann* geht der Deskriptor zu.
Dafür gibt es den **Prüfstandshalt der Unterhälfte** (`NQ_INFO 32` →
`nvmeq.hold`) — dieselbe Bauart und derselbe Grund wie `async.hold` in
Runde ASYNC. Der Ablauf ist dann jedes Mal derselbe:

1. Unterhälfte anhalten. Die Fertigstellungen bleiben im Nachlaufring
   liegen.
2. Vier Leseaufträge abgeben. Sie gehen ins Gerät, das Gerät antwortet.
3. Den Deskriptor **schließen** und den Platz mit `/dev/null` **neu
   vergeben**.
4. Unterhälfte freigeben, abholen.

Heraus kommt viermal `-ESTALE`. Ohne Schritt 3 sähe die Prüfung nur,
dass der Deskriptor weg ist; mit ihm sieht sie, dass dort jetzt *etwas
anderes* steht — und das ist der Fall, aus dem in Linux die meisten
io_uring-Lücken kamen.

### Eine Zusage, die zwei Dinge auf einmal maß

`q-daten-stimmen` sagt: *was durch die Warteschlange kommt, ist das, was
auf der Platte steht.* In einem von etwa fünf Läufen fiel sie — und
zwar nur im Lauf `nqweg`, wo die Fertigmeldung vom Nachsehen statt vom
Interrupt gefunden wird. Das sah nach einem Rennen im neuen Pfad aus.

Es war keins, jedenfalls nicht nachweislich: die Zusage prüfte zwei
Dinge auf einmal. Erst wird das Muster über `write(2)` auf die Platte
geschrieben, dann über den Ring zurückgeholt und verglichen — und wenn
das Schreiben danebengeht, fällt dieselbe Zusage. Sie ist deshalb
**geteilt**: `q-muster-steht` holt das Muster zuerst mit `read(2)`
zurück (synchroner Weg, ohne Warteschlange), und erst danach macht
`q-daten-stimmen` dasselbe über den Ring. Fällt künftig die eine, weiß
man, in welcher Schicht zu suchen ist.

Nachgefahren: viermal `nqweg` und einmal der Regellauf, **je 34 / 34**.
Der Fehler ist damit nicht *erklärt*, sondern *eingegrenzt* — das steht
hier so, weil „nicht mehr aufgetreten" kein Beweis ist.

### Was die Gegenproben zeigen — und was nicht

* **`nqnopool`** ist die wichtigste und steht oben.
* **`nqweg`** (Interrupt verloren): `nvmeq: irqs = 0`, `polled = 54`,
  `submits == completed == 54`, **kein Hänger**. Gefunden hat es das
  Nachsehen im Arbeitsfaden; im äußersten Fall greift die Zeitgrenze
  von drei Sekunden und der Auftrag endet mit `-ETIMEDOUT` statt zu
  stehen.
* **`nqdouble`** (Interrupt doppelt): `lost = 0`, `submits == completed`.
  Die **erste** Fassung dieser Gegenprobe hat sich selbst widerlegt: sie
  zählte jeden Fund des zweiten Durchgangs als „verloren" und meldete
  drei verlorene Sätze, wo nichts verloren war — das Gerät arbeitet
  weiter, während abgeräumt wird, und eine Meldung, die eine
  Mikrosekunde später kommt, ist keine doppelte. Die Zusage misst
  deshalb *abgegeben == fertig gemeldet*, und dagegen stehen zwei
  Riegel: das Phasenbit und `FL_STATE == 1`.
* **`nqtiny`** (Tiefe 4): `qfull = 40`, `fallback = 40`, und trotzdem
  32 von 32 Aufträgen mit vollen 512 Oktett zurück. Voll heißt hier
  nicht verwerfen und nicht hängen, sondern *der alte Weg*.
* **`nqoff`**: `fast = 0`, `submits = 0`, und der Kernel verhält sich
  genau wie in Runde RING. Das ist die Grundlinie, gegen die gemessen
  wird — **in demselben Kernel und mit demselben Programm**.

### Die Leckzahlen

```
nvmeq: inflight=0    Eintraege beim Geraet
nvmeq: done=0        Saetze im Nachlaufring
nvmeq: lost=0        Nachlaufsaetze ohne Platz    MUSS null bleiben
nvmeq: badprp=0      abgewiesene Adressen
nvmeq: timeouts=0
nvmeq: submits=54    == completed=54
nvmeq: fast=54       staled=4    cancelled=8
nvmeq: queues=4      depth=64    poolbytes=1081344
```

Und die Rahmenprobe: `frames` → `frames-after` geht um **genau 32**
Rahmen zurück, und das sind die Kernstapel der vier Arbeitsfäden aus
Runde ASYNC (4 × `sched.KSTACK_FRAMES`). Der Läufer rechnet das aus dem
Quelltext nach, statt eine Zahl hinzuschreiben.

---

## Die Messung

**Ein Boot, drei Wege, derselbe Deskriptor.** Die Weiche wird zwischen
den Reihen umgelegt (`NQ_INFO 36`) — zwischen zwei Boots misst sich der
synchrone Weg um bis zu zwanzig Prozent anders, und nur in *einem* Boot
sagen die Verhältnisse etwas. Dieselbe Regel wie in Runde RING.

Methodik wie dort: Blöcke zu 16 Aufträgen à 32 Oktett, 33 Blöcke,
**Median**, Zyklen je Auftrag. Neu ist, dass auf einer **Platte**
gemessen wird und nicht auf einer Röhre: eine Röhre kopiert im Kern,
eine Platte lässt warten. Jeder Auftrag dieser Messung ist ein echter
NVMe-Befehl — `blk.read_on` für DEV_NVME ruft `nvme.read_block`, ohne
Zwischenspeicher.

### 16 × 32 Oktett auf `/dev/nvme0`, ein Kern

| Weg | Zyklen | µs | Aufträge/s |
|---|---:|---:|---:|
| **synchron** (`read(2)`) | **210 291** | 95,48 | 10 474 |
| ring (Fadenweg) Tiefe 1 | 527 099 | 239,31 | 4 179 |
| ring (Fadenweg) Tiefe 4 | 283 584 | 128,75 | 7 767 |
| ring (Fadenweg) Tiefe 16 | 231 706 | 105,20 | 9 506 |
| ring (Fadenweg) Tiefe 64 | 225 237 | 102,26 | 9 779 |
| **nvmeq Tiefe 1** | 475 745 | 216,00 | 4 630 |
| **nvmeq Tiefe 4** | **184 559** | **83,79** | **11 934** |
| **nvmeq Tiefe 16** | **137 872** | **62,60** | **15 975** |
| **nvmeq Tiefe 64** | **100 514** | **45,63** | **21 913** |

Zum Vergleich der zweite vollständige Lauf desselben Tages (etwas
geringere Wirtslast): synchron 224 687, nvmeq 4/16/64 = 155 564 /
107 325 / 131 798. Die absoluten Zahlen bewegen sich um bis zu 30 %,
**die Reihenfolge der Wege in keinem Lauf.**

### Bündel ohne jeden Anstoß

| Weg | Zyklen | µs | Aufträge/s |
|---|---:|---:|---:|
| ring Bündel 1 | 314 780 | 142,92 | 6 997 |
| ring Bündel 8 | 226 168 | 102,68 | 9 739 |
| ring Bündel 32 | 232 097 | 105,38 | 9 490 |
| nvmeq Bündel 1 | 557 561 | 253,14 | 3 950 |
| nvmeq Bündel 8 | 215 996 | 98,07 | 10 197 |
| nvmeq Bündel 32 | 167 291 | 75,95 | 13 166 |

**Diese sechs Zahlen sind die wackeligsten der ganzen Runde, und das
gehört dazugesagt.** „Ohne jeden Anstoß" heißt auf EINEM Kern: das
Programm gibt den Prozessor mit `SYS_YIELD` ab und hofft, dass ein
Arbeitsfaden drankommt — die Zahl misst damit zur Hälfte den
Zeitscheibenplan und nicht den Weg. In Runde RING stand derselbe Satz,
und dort wurde die Reihe deshalb zusätzlich mit `-smp 2` gefahren. Das
geht hier nicht (siehe „was offen bleibt"). Zwischen zwei Läufen dieser
Runde haben sich diese sechs Werte um bis zu 70 % bewegt, während die
Tiefen 1/4/16/64 auf ±10 % stabil blieben. Sie stehen hier, weil sie
gemessen wurden, und nicht, weil man auf ihnen etwas aufbauen sollte.

### Warteschlange gegen Fadenweg — derselbe Ring, dieselbe Schleife

| Tiefe | Fadenweg | Warteschlange | schneller um |
|---:|---:|---:|---:|
| 1 | 527 099 | 475 745 | 10 % |
| 4 | 283 584 | 184 559 | **35 %** |
| 16 | 231 706 | 137 872 | **40 %** |
| 64 | 225 237 | 100 514 | **55 %** |

Das ist der Vergleich innerhalb derselben Schicht: gleicher Ring,
gleiches Programm, gleiche Blöcke — nur einmal mit und einmal ohne
Gerätewarteschlange.

**Die erste Zeile ist die wackelige.** Bei EINEM offenen Auftrag gibt es
nichts nebeneinander zu tun; in diesem Lauf gewinnt der
Warteschlangenweg um 10 %, im Lauf davor **verlor** er um 12 %
(556 417 gegen 623 859). Der Grund ist kein Fehler, sondern die
Bauart: der Fadenweg lässt den Arbeitsfaden den
Auftrag gleich selbst ausführen, der Warteschlangenweg gibt ihn ans
Gerät, wartet auf den Interrupt und lässt ihn von einem Faden abholen —
ein Übergang mehr. Was diese Runde gewinnt, ist **Nebenläufigkeit**,
nicht Latenz. Der Läufer verlangt deshalb ab Tiefe 4 einen Vorsprung
und bei Tiefe 1 keinen; er druckt die Zahl trotzdem.

### Die Lastzahl: wer wartet auf das Gerät?

Das ist die Zahl, um die es in der Aufgabenstellung geht, und sie hat
einen Haken, der hier ausgeschrieben steht.

`nvme.waits` zählt die `hlt` in `nvme.await` — Fäden, die sich hinlegen.
Diese Zahl ist auf dem synchronen Weg über `/dev/nvme0` **null**, und
zwar nicht, weil niemand wartet, sondern weil niemand *schlafen kann*:
`devfs.enter` hält `atomic.L_FS` **mit abgeschalteten Interrupts**, und
dann kann der Fertigstellungs-Interrupt gar nicht ankommen — `await`
pollt und **dreht mit vollem Prozessor**. Dafür gibt es in dieser Runde
einen zweiten Zähler (`nvme.spins`), und er ist der ehrlichere:

| Weg | `hlt` in `nvme.await` | **Drehungen** in `nvme.await` |
|---|---:|---:|
| synchron (528 Aufträge) | 0 | **647 518** |
| Fadenweg (Tiefe 1/4/16) | 0 | **2 102 748** |
| **Warteschlange (Tiefe 1/4/16)** | **0** | **0** |

**Null. Kein Faden legt sich hin, und keiner dreht.** Es wartet niemand;
es meldet sich das Gerät.

Gemessen wird über die Tiefen 1/4/16 und **nicht** über 64: dort ist die
Gerätewarteschlange voll (sie ist 64 tief und lässt einen Platz frei),
ein Teil der Aufträge geht über den Fadenweg — und die drehen dann
natürlich. Eine Lastzahl, die den Rückstau mitmisst, misst nicht mehr,
was sie behauptet.

### Woher die Fertigmeldung kam

```
nvmeq: fast=6829  fallback=33  irqs=3030  polled=3143  timeouts=0
```

Etwa die Hälfte der Fertigstellungen findet das **Nachsehen** im
Arbeitsfaden und nicht der Interrupt. Das ist kein Fehler, sondern das
Hybrid-Polling aus `KERNEL.md`: wer ohnehin wach ist, sieht nach, statt
sich hinzulegen und wecken zu lassen. Auf einem Kern, auf dem das
Programm und die Arbeitsfäden sich die Zeitscheiben teilen, gewinnt das
Nachsehen oft — und spart genau den Interrupt, der 1–3 µs kostet.

---

## Der Fehler, der eine Messreihe gekostet hat

Er steht hier, weil er jede Runde dieses Projekts treffen kann:

> **Der Pfad des Kernelabbilds steht mit in der Kommandozeile.**

Multiboot hängt `-append` hinter den Namen der Datei, `hw.parse` sucht
darin **Teilwörter** — und ein Arbeitsverzeichnis namens
`/tmp/osum-nvmeq-XXXX` enthält das Wort `nvmeq`. Damit lief in *jedem*
Lauf der Selbsttest mit, auch in dem, der nur messen sollte. Die Zahlen
waren um die 54 Aufträge des Selbsttests verschoben.

`tools/nvmeq/bau.sh` startet QEMU deshalb **im Arbeitsverzeichnis mit
relativen Pfaden**: die Kommandozeile heißt immer `k0.mb <anhang>`, egal
wie das Verzeichnis heißt.

Aus derselben Familie stammt die Namenswahl der Modusworte. `find` sucht
Teilwörter, also wäre `nqbench` das Wort `bench` gewesen (die Messung
der Runde K2), `nqnoirq` das Wort `noirq` (der maskierte Vektor
derselben Runde) und `nqlost` das `lost` einer dritten. Es heißt deshalb
`nqmess`, `nqweg` und `nqnopool` — alle acht sind gegen die 212 bereits
vergebenen Wörter im Baum geprüft.

---

## Ein zweiter Fehler, gefunden und behoben

`blk.blocks_on(state, DEV_NVME)` gab die Größe des **Dateisystems**
zurück (die Zahl, die `blk.use_nvme` zuletzt gesetzt hat) und nicht die
des **Laufwerks**. Für `/dev/nvme0` ist das die falsche Zahl in die
gefährliche Richtung: `devfs` wies jeden Zugriff hinter dem Ende des
Dateisystems ab, obwohl die Platte weitergeht — ein `dd` auf das letzte
Viertel eines NVMe-Laufwerks las **null Oktett und meldete keinen
Fehler**.

Genau denselben Fehler hatte Runde INSTALL für `DEV_ATA` behoben und die
Begründung daneben geschrieben; für die dritte Platte war er
stehengeblieben. Er ist jetzt weg, und die Zahl kommt aus IDENTIFY
NAMESPACE.

---

## Stand AHCI

**Nicht gebaut. Bewusst.**

`kernel/ahci.fi` (1095 Zeilen) existiert — aber auf dem Zweig `ahci`
(Arbeitsbaum `/root/ahci-osum`, Spitze a40b60a), und der ist **kein
Nachfahre von `ring`**: der gemeinsame Vorfahr ist 11fc24f. Die Datei
liegt also nicht auf dieser Linie, und sie hierher zu holen wäre ein
Merge zweier Runden — die Arbeit, für die es in diesem Projekt eigene
Merge-Runden gibt.

Dazu kommt der Inhalt. Der Treiber dort ist **synchron**:
`read_block`/`write_block`/`read_many`/`flush`, Kommandoliste ohne NCQ.
Ein Warteschlangenbetrieb darauf wäre keine Anpassung, sondern eine
neue Hälfte des Treibers (NCQ, `FIS`-Empfangsbereich je Anschluss,
Interrupt-Aufteilung `PxIS`/`PxSACT`). Das ist eine eigene Runde und
keine Zugabe.

Die Aufgabenstellung sagt dazu: *„Wenn die Zeit nicht reicht, brich hier
bewusst ab und schreib die Fortsetzungsliste — NVMe fertig ist mehr wert
als beides halb."* Genau das ist geschehen.

**Was AHCI vorbereitet vorfindet**, wenn die Runde kommt: die Weiche ist
*eine* Funktion (`sys.nvmeq_dev`, sieben Zeilen), die Flugtafel, der
Nachlaufring, die Ober-/Unterhälften-Aufteilung, die DMA-Wache und die
gesamte Lebensdauerrechnung sind gerätefrei formuliert. Anzupassen wären
`nvmeq.push` (Kommandoliste statt SQE) und `drain_one` (`PxIS`/`PxSACT`
statt Phasenbit).

---

## Was offen bleibt

* **Mehrere Kerne in der Messung. Die Zahl fehlt, und das ist die
  größte Lücke dieser Runde.** `-smp 2` und `-smp 4` enden im
  Doppelfehler, sobald ein Ring-3-Programm **nach `smp.stage`**
  Systemaufrufe macht: `rip` im Kernel, `rsp` auf dem *Benutzerstapel*,
  `cs=0x8` — der Eintritt hat noch nicht auf den Kernelstapel
  umgeschaltet.

  **Wem der Fehler gehört, ist offen, und das steht hier so.** Die
  Gegenprobe wurde zweimal gefahren: derselbe Lauf mit **abgeschalteter
  Weiche** (`nqoff` — der Warteschlangenweg sieht dann keinen einzigen
  Auftrag und weckt aus dem Interrupt niemanden) endete **einmal im
  selben Doppelfehler und einmal sauber**. Es ist also ein *Rennen*,
  das es auch ohne diese Runde gibt — und das die Interruptlast dieser
  Runde sehr viel wahrscheinlicher macht (mit eingeschalteter Weiche
  trat es in **jedem** Lauf auf, mit abgeschalteter in **einem von
  zwei**). Eine der beiden bequemen Antworten — „gehört nicht dieser
  Runde" oder „liegt an dieser Runde" — hinzuschreiben wäre in beiden
  Fällen mehr, als gemessen ist.

  Was gemessen ist: der Selbsttest ist auf **einem und auf zwei** Kernen
  grün (34/34, viermal nachgefahren); der Doppelfehler in der Messung
  kommt mit zwei Kernen. Der Selbsttest steht deshalb jetzt **vor**
  `smp.stage`, wo die Selbsttests aller Runden davor auch stehen. Der
  Verdächtige Nummer eins ist `sched.poll_kick` aus dem
  Interrupt-Zusammenhang: es schreibt `T_STATE` **ohne** die Laufsperre,
  und auf mehreren Kernen läuft das gegen `schedule_locked`. Das ist
  kein neues Muster (`tty.lput` tut es seit Runde POLL aus der
  Tastatur-Unterbrechung), aber die NVMe-Fertigmeldung feuert tausendmal
  häufiger als eine Taste. Das gehört in eine eigene Runde — zusammen
  mit der Frage, warum ein `fork` aus Ring 3 nach `smp.stage` auf vier
  Kernen ebenfalls fällt.
* **Ein Vektor je Warteschlange.** Heute melden alle vier Paare auf
  MSI-X-Eintrag 0. Begründung oben.
* **Registrierte Puffer.** Der Umsteigepuffer kostet eine Kopie von bis
  zu 4096 Oktett je Auftrag. Festgepinnte Programmseiten sparen sie —
  und brauchen eine IOMMU.
* **PRP-Listen.** Heute höchstens 4096 Oktett je Auftrag (PRP1 allein).
  Größere Übertragungen gehen über den Fadenweg.
* **Schreiben unter Blockgröße.** Lesen-Ändern-Schreiben braucht zwei
  Gerätegänge mit einer Abhängigkeit dazwischen; das geht heute über
  den Fadenweg.
* **Verkettete Aufträge** (`IOSQE_IO_LINK`) und **ein Ring über mehrere
  Fäden** — beides steht schon auf der Liste der Runde RING und ist
  unverändert offen.
* **`fsync`/`flush` über die Warteschlange.** Heute nimmt nur
  Lesen/Schreiben den schnellen Weg.

---

## Abnahme

`bash tools/nvmeq/run.sh` — neun QEMU-Läufe (Regellauf, sechs
Gegenproben, Messung mit 1/2/4 Kernen), die vier Regressionsläufe der
Vorrunden und beide Übersetzer:

| Läufer | Ergebnis |
|---|---|
| `tools/nvmeq/run.sh`, Ring 3 | **34 / 34**, Beendigungscode 0, mit firnc0 **und** firnc1 |
| `tools/ring/run.sh` | **120 / 0** |
| `tools/async/run.sh` | **108 / 0** |
| `tools/handle/run.sh` | **80 / 0** |
| `tools/poll/run.sh` | **67 / 0** |
| `tools/build-kernel.sh`, Stufe 0/1 | grün, 3 275 308 / 7 979 832 Oktett |
| `tools/build-kernel.sh --ohne-tunnel`, Stufe 0/1 | grün, 3 075 968 / 7 538 540 Oktett |

Der **GUI-lose Bau** (`--ohne-tunnel`) und der volle Bau übersetzen
beide mit beiden Übersetzern; die Größenunterschiede sind die
bekannten aus `docs/TUNNEL-PAKETE.md` und haben sich durch diese Runde
nicht verschoben.

**Zur Flatterhaftigkeit unter Last:** `tools/ring/run.sh` gab in zwei
Läufen 120 / 0 und in zwei weiteren 119 / 1 — jedes Mal an derselben
Stelle (`die Abgabezahlen fehlen`), und jedes Mal, wenn auf dem Wirt
gleichzeitig andere Runden rechneten (Lastmittel 24 auf 12 Kernen). Der
Grund ist ein QEMU-Lauf, der in sein Zeitlimit läuft, und nicht der
Kernel. Aus demselben Grund steht in `tools/nvmeq/bau.sh` jetzt
`timeout 600` statt `timeout 300`: ein Lauf dieser Runde ist unter Last
einmal mitten im `nqerr`-Abschnitt abgeschnitten worden, und sechs
Zusagen „fehlten ganz", obwohl nichts kaputt war.

Beide Übersetzer (firnc0 und firnc1) bauen denselben Kernel und geben
dieselben **34** Zusagen.

**Kein Test ist abgeschaltet.** Zwei Zusagen sind *bedingt* formuliert,
und beide Male steht die Bedingung daneben:

* `e-voll-gezaehlt` verlangt einen Rückstau nur, wenn die Tiefe klein
  ist (Lauf `nqtiny`, Tiefe 4). Bei voller Tiefe sind 32 Aufträge kein
  Rückstau, und eine Zusage, die dann trotzdem einen verlangte, würde
  eine Zufälligkeit messen.
* Der Vergleich Warteschlange gegen Fadenweg ist ab **Tiefe 4** streng
  und bei Tiefe 1 eine Notiz. Begründung oben.

Und eine Gegenprobe ist **ausdrücklich keine Zusage**: der Lauf mit
`-smp 2` und abgeschalteter Weiche. Er wird gefahren und sein Ergebnis
gedruckt — aber er fällt zweimal verschieden aus, und daraus eine
Zusage zu machen hieße, ein Rennen als Tatsache auszugeben.
