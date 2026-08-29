# Runde ASYNC — die Zwischenstufe zwischen Handle und Ring

Zweig `async`, Arbeitsbaum `/root/osum-async`, abgezweigt von `handle`
(5a0e23a) und mit `poll` (33e10ed) zusammengeführt. **Nicht nach `main`,
`mergeline` oder `mergeline2` gemergt.**

Gemessen am 29.08.2026 auf AMD EPYC 7571, QEMU mit `-accel kvm`,
TSC 2 201 568 kHz (2,2016 GHz).

---

## Warum diese Runde zwischen HANDLE und RING steht

Runde HANDLE hat die **Lebensdauer** eines Kernobjekts geordnet:
Verweiszähler, generationsbehaftete Handle-Nummern, Abbruch-Token, kein
Free während ein Auftrag läuft. Sie hatte nur einen Mangel — sie hatte
keinen Kunden. `handle.req_begin` und `handle.req_end` standen im
**selben Systemaufruf** nebeneinander, und dazwischen konnte nichts
geschehen. Eine Zusage über asynchrone Lebensdauer, die nie asynchron
geprüft wird, ist eine Behauptung.

Diese Runde legt zwischen die beiden einen Zustandswechsel, einen
Arbeitsfaden und beliebig viele Zeitscheiben eines anderen Prozesses.
Erst damit ist die Zusage von Runde HANDLE **prüfbar** — und sie hält.

Google hat 2023 berichtet, dass rund **60 % der eingereichten
Linux-Kernel-Exploits aus io_uring** stammten. Die Ursache war nicht der
geteilte Speicher und nicht die Ringform, sondern genau diese Schicht:
ein Auftrag, der ein Objekt meint, das inzwischen ein anderes ist.
Deshalb hat hier **jede Zusage eine Gegenprobe**, die sie absichtlich
kaputtmacht.

---

## Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/async.fi` | 924 | **neu**: Auftragstafel (64 Aufträge à 80 Oktett), Zustände, Fertigmeldungsringe je Prozess, Abbruch, Prozesstod, Ausführungssperre |
| `kernel/sys.fi` | +840 | die sechs Aufrufe ab 1980, `aio_submit`/`aio_wait`/`aio_cancel`, die Ausführung, der Arbeitsfaden, `fsync`, `open_named` |
| `kernel/uprog.fi` | +701 | `u_async` (32 Zusagen aus Ring 3), `u_asyncfs` (7 auf einem Dateisystem), `u_abench` (die Messung) |
| `kernel/kmain.fi` | +207 | die Runde, die Leckzahlen, die Modusworte |
| `kernel/user/aiot.fi` | 333 | **neu**: `/bin/aiot` — dasselbe von der Platte, über die libc |
| `lib/libc/io.fi` | +141 | `aio_read/write/open/close/fsync/poll`, `aio_wait/cancel/state`, die vier Felder einer Fertigmeldung, `fsync` |
| `lib/libc/kcall.fi` | +28 | die Nummern und `aio_submit_call` (fünf Argumente) |
| `kernel/kstate.fi` | +93 | drei Bereiche in `kdata`, sechs Modusbits, zwölf Zähler, `KDATA_SIZE` 0x80000 → 0x90000 |
| `kernel/sched.fi` | +39 | `K_AIO`, `poll_kick_one` |
| `kernel/errno.fi` | +11 | `ESTALE` (116), `ECANCELED` (125) — zwei Werte, die es ohne Asynchronität nicht geben konnte |
| `kernel/tasks.fi` | +8 | die neue Fadenart verteilen |
| `kernel/arch/x86_64/boot.s` | 1 | `KDATA_SIZE` — dieselbe Zahl wie in `kstate.fi` |
| `tools/async/run.sh` | 467 | **neu**: der Testläufer, 108 Zusagen |
| `tools/kernel/memmap.py` | +8 | die drei neuen Bereiche in der Speicherkarte |
| `test.sh` | +13 | Abschnitt 10c |

Zusammen **3807 eingefügte Zeilen**, davon 924 neues Kernmodul.

---

## Der Entwurf in drei Sätzen

1. **Ein Auftrag hält eine zählende Referenz auf sein Ziel.** Bei der
   Abgabe holt `aio_submit` ein Abbruch-Token aus `handle.req_begin`;
   das zählt am Objekt einen Auftrag „in Flug" mit. Schließt der Prozess
   sein Handle, fällt der Verweiszähler auf null — und der Eintrag der
   offenen Dateien bleibt trotzdem stehen, bis das Token zurückgegeben
   ist. Wer zuletzt geht, macht das Licht aus.
2. **Vor jedem Zugriff wird gefragt, ob das Handle noch dasselbe meint.**
   `handle.req_object` vergleicht Handle-Platz, Handle-Generation und
   Objektgeneration. Passt eines nicht: `-ESTALE`, und nicht die neue
   Datei.
3. **Genau eine Fertigmeldung je Auftrag.** Jeder Zustandsübergang, der
   einen Auftrag „wegnimmt", ist ein `lock cmpxchg` und keine Abfrage
   mit anschließendem Schreiben. Ein Abbruch markiert nur; gemeldet wird
   von dem, der den Auftrag hat.

### Die Zustände

```
frei ──submit──► angelegt ──Arbeitsfaden──► läuft ──► fertig ──► (Meldung, frei)
                     │                        │       fehlgeschlagen
                     │                        └─────► abgebrochen
                     └──cancel──► abgebrochen ──────► (Meldung, frei)

                 angelegt ◄── rearm ── wartet   (nur `poll`: readiness → completion)
```

`wartet` ist der Zustand, der aus dieser Runde eine Brücke macht statt
einer Warteschleife — siehe unten.

### Die Speicherkarte

`kdata` war nach Runde HANDLE bis 0x7F380 belegt. Diese Runde lässt es
auf **0x90000** wachsen (dieselbe Zahl in `kstate.fi` **und** in
`kernel/arch/x86_64/boot.s`; `tools/async/run.sh` Abschnitt 1 vergleicht
beide) und nimmt vier Seiten davon:

| Bereich | Adresse | Größe | was |
|---|---|---:|---|
| `AIO_OFF` | 0x80000 | 0x2000 | die Auftragstafel, 64 × 80 Oktett |
| `ACQ_OFF` | 0x82000 | 0x8000 | die Fertigmeldungsringe, 32 Aufgaben × 1024 |
| `ASC_OFF` | 0x8A000 | 0x1000 | Sperre, Reihum-Zeiger, Prüfstandshalt, Kratzfläche |
| `APATH_OFF` | 0x8B000 | 0x2000 | der Pfadvorrat der asynchronen `open`, 64 × 128 |

`memmap.py` rechnet nach: **74 Bereiche, 0 Kollisionen.**

---

## Die sechs Pflichtfälle, und was sie wirklich abfangen

Alle sechs werden aus **Ring 3** geprüft (`uprog.u_async`), jede Zusage
einzeln vom Läufer nachgelesen. Gearbeitet wird auf Röhren: die gibt es
ohne Dateisystem, ihre Enden haben ungleiche Rechte, und sie haben einen
echten Verweiszähler, den man beim Abräumen beobachten kann.

| # | Szenario | Zusagen | Gegenprobe |
|---|---|---|---|
| **a** | Handle wird geschlossen, während der Auftrag läuft | `a-auftrag-laeuft`, `a-kein-free-in-flug`, `a-ergebnis-vier`, `a-danach-frei`, `a-kein-leck` | `noflight` aus Runde HANDLE |
| **b** | Slot-Wiederverwendung: alter Auftrag, neues Objekt | `b-selber-platz`, `b-veraltet` (−ESTALE), `b-nicht-das-neue-ding`, `b-kein-leck` | **`noagen`** → beide fallen |
| **c** | Abbruch mitten im Auftrag | `c-angelegt`, `c-abgebrochen`, `c-nach-abbruch-weg`, `c-zweimal-abbrechen`, `c-genau-eine-meldung`, `c-laufender-abbruch`, `c-kein-leck` | — |
| **d** | Prozess stirbt mit laufenden Aufträgen | `d-tod-raeumt-ab`, `d-drei-abgeraeumt` | **`noareap`** → fällt |
| **e** | Warteschlange voll, Zeitgrenze abgelaufen | `e-sechzehn-offen`, `e-warteschlange-voll` (−EAGAIN), `e-nichtblockierend` (0), `e-zeitgrenze` (−ETIMEDOUT), `e-kein-leck` | — |
| **f** | Zwei Prozesse, fremdes Auftrags-Handle | `f-es-gibt-ihn-wirklich`, `f-fremder-zustand` (−EPERM), `f-fremder-abbruch` (−EPERM) | — |

Dazu sieben Zusagen auf einem echten Dateisystem (`u_asyncfs`):
asynchron öffnen, lesen, `fsync`, `close`, ein Pfad, den es nicht gibt.

**Ergebnis: 32 / 32 und 7 / 7, Beendigungscode 0, mit beiden Übersetzern
(firnc0 und firnc1).**

### Wie (b) deterministisch gemacht wurde

Zusage (b) beschreibt ein **Zeitfenster**: der Auftrag ist abgegeben und
noch nicht ausgeführt, und *genau dann* wird das Handle geschlossen und
der Platz neu vergeben. Ohne Eingriff hängt es an der Zeitscheibe, ob
der Test dieses Fenster trifft — und ein Test, der die Fehlerklasse nur
manchmal trifft, ist keiner.

Dafür gibt es den **Prüfstandshalt** (`AIO_INFO 20`): die Arbeitsfäden
nehmen keinen neuen Auftrag an, bis er wieder aufgehoben wird. Er ist
nur im Selbsttestmodus erreichbar — ohne das Wort `async` gibt `AIO_INFO`
`-ENOSYS`, und niemand kann ihn setzen. Ein Testfenster, das im
Regelbetrieb offen bleibt, wäre eine Hintertür.

Die zweite Hälfte der Zusage ist die wichtigere: nach dem veralteten
Auftrag müssen die vier Oktett in der **neuen** Röhre noch da sein.
Geprüft wird das mit `poll(2)` und Zeitgrenze 0 — das liest nichts weg,
es sagt nur, dass etwas da ist. Mit `noagen` sind sie weg: der alte
Auftrag hat sie gelesen. Das ist der io_uring-Fehler, absichtlich wieder
eingebaut.

### Was die Gegenproben zeigen — und was nicht

* **`noagen`** (keine Generationsprüfung): `b-veraltet` und
  `b-nicht-das-neue-ding` fallen. Der alte Auftrag trifft das neue
  Objekt. Das ist die Fehlerklasse, um derentwillen es diese Runde gibt.
* **`noareap`** (kein Aufräumen beim Prozesstod): `d-drei-abgeraeumt`
  fällt, `async: abandoned` bleibt auf 0. **Ehrlich gesagt:**
  `d-tod-raeumt-ab` steht trotzdem, weil eine zweite Verteidigungslinie
  greift — der Arbeitsfaden prüft vor jedem Zugriff, ob der Eigentümer
  noch lebt und noch dieselbe pid hat, und bricht sonst ab. Ohne das
  ausdrückliche Abräumen bleibt die Tafel also nicht dauerhaft voll,
  aber es ist **Zufall statt Zusage**: ob und wann ein Faden den Platz
  wieder anfasst, hängt daran, ob irgendwo Bereitschaft entsteht.
* **`noawork`** (keine Arbeitsfäden, der Abgeber führt selbst aus):
  **sieben** Zusagen fallen, `async: workers` ist 0. Das ist der
  Nachweis, dass die Arbeit im Regelbetrieb wirklich woanders geschieht
  und nicht nur so heißt.

### Die Leckzahlen

Nach einem vollständigen Lauf, in dem jeder Prozess ordentlich geendet
hat:

```
async: used=0        belegte Auftragsplätze
async: live=0        laufende Aufträge
async: lost=0        verlorene Fertigmeldungen
async: inflight=0    Handle-Aufträge noch in Flug
async: objects=0     Einträge in der Objekttafel
async: workers=4     Arbeitsfäden
```

Dagegen gehalten, was passiert ist:

```
async: submitted=25  cancelled=18  stale=1  full=1  timeouts=1
async: abandoned=3   denied=2      posted=22 reaped=22  workruns=29
```

`workruns=29` ist die Zahl, die die erste Fassung entlarvt hätte: dort
waren es für dieselben Aufträge **525 241** (siehe unten).

---

## `poll` → completion: die Brücke, und nur in diese Richtung

Der Zweig `poll` ist in diesen Zweig gemergt. Die Runde POLL hat
`poll(2)` gebaut: sie sagt, was auf einem Deskriptor **jetzt möglich
wäre**. Diese Runde bildet das auf einen Auftrag ab:

```
    io.aio_poll(fd, io.POLLIN, kennzahl)
```

Der Auftrag wird **fertig**, sobald das Ereignis eintritt; sein Ergebnis
ist die `revents`-Maske. Ein Programm, das nur Fertigmeldungen kennt,
kann damit auf Röhren, Steckdosen und Terminals warten, ohne `poll` je
aufzurufen.

**Umgekehrt geht es nicht**, und das ist der Grund, warum completion die
allgemeinere Primitive ist:

* `poll` kann sagen „auf diesem Deskriptor wäre jetzt etwas möglich" —
  es kann nicht sagen „diese Datei ist gelesen und die Oktette stehen in
  deinem Puffer".
* Eine **gewöhnliche Datei ist immer bereit**. Readiness ist für sie
  keine Auskunft; ein `poll`, das auf sie wartete, wartete für immer.
  Genau das steht in `kernel/sys.fi` bei `poll_ready` schon seit Runde
  POLL.
* Readiness braucht **zwei** Systemaufrufe je Operation (fragen, dann
  tun) und hat dazwischen ein Zeitfenster. Completion ist einer.

Technisch: ein `poll`-Auftrag, dessen Ereignis noch nicht da ist, geht in
den Zustand **`wartet`**. `take_new` sieht ihn nicht an. Wieder scharf
gestellt wird er von `async.rearm`, und das ruft der Arbeitsfaden genau
dann, wenn `sched.poll_kick` ihn geweckt hat — also **dieselbe
Weckfolge**, mit der Runde POLL die Wettlaufsituation zwischen „nichts
da" und „ich schlafe" gelöst hat.

Dass dieser Zustand sein muss, war ein gemessener Fehler und keine
Überlegung: die erste Fassung setzte einen solchen Auftrag einfach wieder
auf „angelegt". Das ist eine Warteschleife mit vier Fäden darin. Der
Zähler sprang für drei Aufträge auf **525 241 Durchläufe**, und ein
sterbender Prozess kam aus `drain_task` nicht mehr heraus, weil bei jedem
Blick einer davon gerade „läuft". Nach der Änderung: **29**.

---

## Die Messungen

`bash tools/async/run.sh`, Abschnitt 6. Ein `read` von 32 Oktett aus
einer Röhre, die vor jedem Block mit 512 Oktett (`file.PIPE_CAP`)
gefüllt wird — so blockiert kein einziger Lesevorgang, und gemessen wird
die Schicht und nicht die Wartezeit auf Daten. **Median** aus 33 Blöcken
zu 16 Lesevorgängen, nicht Mittelwert: der Zeitgeber unterbricht.

### Latenz und Durchsatz

| Weg | Zyklen je Auftrag | Latenz | Durchsatz |
|---|---:|---:|---:|
| synchron (`read(2)`, der heutige Weg) | 8 376 | **3,80 µs** | **262 842 /s** |
| asynchron, 1 offener Auftrag | 30 278 | 13,75 µs | 72 711 /s |
| asynchron, 4 offene Aufträge | 16 838 | 7,65 µs | 130 749 /s |
| asynchron, 16 offene Aufträge | 13 552 | **6,16 µs** | **162 453 /s** |
| nur die **Abgabe** (`aio_submit`) | 2 402 | 1,09 µs | — |

### Speicherkosten je Auftrag

**112 Oktett**: 80 für den Auftragssatz (Zustand, Art, Abbruch-Token,
Eigentümer, pid, Puffer, Länge, Kennzahl, Ergebnis, Deskriptor) plus 32
für seinen Platz im Fertigmeldungsring. Die Zahl wird aus dem laufenden
Kernel gelesen (`AIO_INFO 5`), nicht aus dieser Tabelle.

Dazu je Prozess ein Ring von 1024 Oktett (16 Meldungen à 32 plus
Kopfsatz) und je Auftrag 128 Oktett Pfadvorrat für ein mögliches
asynchrones `open`. Insgesamt belegt die Schicht **0x13000 = 77 824
Oktett** in `kdata`, fest, unabhängig von der Last.

### Und die ehrliche Auswertung

**Die Tiefe zahlt sich aus, aber der synchrone Weg wird nicht
geschlagen.** Von 1 auf 16 gleichzeitig offene Aufträge fällt der Preis
je Auftrag von 30 278 auf 13 552 Zyklen — Faktor **2,23**. Damit ist die
Zusage erfüllt, dass mehr offene Aufträge den Preis senken. Er bleibt
aber bei 16 offenen Aufträgen immer noch **1,62-mal so hoch** wie beim
synchronen `read`.

Warum, und was daran diese Runde ist und was nicht:

* **Die Arbeit selbst verschwindet nicht.** Der Arbeitsfaden führt
  denselben `read_of` aus wie der synchrone Weg. Auf **einem** Kern ist
  das dieselbe Rechenzeit plus die Übergabe.
* **Die Übergabe kostet.** 13 552 − 2 402 (Abgabe) − 8 376 (die Arbeit)
  ≈ **2 774 Zyklen** je Auftrag für Aufwecken, Kontextwechsel und das
  Abholen der Meldung. Das ist der Preis der Schicht, und er ist die
  einzige Zahl hier, die diese Runde wirklich verantwortet.
* **Mehrere Kerne helfen heute nicht.** Derselbe Messlauf unter
  `-smp 4`: 13 838 gegen 13 413 Zyklen — im Rauschen. Gemessen, nicht
  vermutet.
* **Der nachweisbare Gewinn ist der Abgeber.** Ein Lesevorgang kostet
  den abgebenden Prozess **2 402 statt 8 376 Zyklen — 71 % weniger**.
  Was er mit der freien Zeit tut, misst diese Runde nicht; dass er sie
  hat, schon.

**Was das für Runde RING heißt:** die Latenzzahlen oben sind kein Urteil
über den Entwurf, sondern über den heutigen Ausführungspfad — vier
Fäden, die synchron arbeiten und sich am Ende noch einen Kopierpuffer
teilen. Der Ring ersetzt genau den teuren Teil (Abgabe und Abholen über
Systemaufrufe) durch geteilten Speicher. Die 2 402 Zyklen der Abgabe
sind der Posten, den er auf nahezu null bringen kann; die 8 376 Zyklen
der Arbeit bleiben, bis der Blockpfad selbst asynchron wird (NVMe-/
AHCI-Warteschlangen, eine spätere Runde).

### Was **nicht** gemessen wurde

* **Kein Durchsatz auf einer Platte.** Die Messung läuft auf einer
  Röhre. Was NVMe oder AHCI mit tiefen Warteschlangen täten, ist nicht
  gemessen und wird hier nicht behauptet.
* **Keine Latenz unter Last.** Alle Zahlen stammen aus einem ruhigen
  System mit einem messenden Prozess.
* **Keine Messung des Ring-Entwurfs.** Runde RING existiert nicht.

---

## Die Fehler, die dabei gefunden wurden

Fünf, alle im Quelltext an ihrer Stelle benannt:

1. **Ein Arbeitsfaden war ein Kind des Abgebers.** `sched.create` trägt
   als Elternteil die laufende Aufgabe ein — und das war der Prozess,
   der zufällig als erster einen Auftrag abgegeben hat. Danach stand ein
   Kernfaden in seiner Kinderliste, und sein nächstes `wait4(-1)` fand
   ihn statt seines wirklichen Kindes und wartete für immer auf eine
   Leiche, die nie kommt. `wait4` war seit Runde K4 richtig und war es
   immer noch — nur die Kinderliste war es nicht mehr.
2. **Ein Abbruch, der nichts tat.** `mark_cancel` markierte bei einem
   laufenden Auftrag nur das Token und ließ den Zustand stehen. Der Faden
   sah danach „läuft", brachte den Auftrag ordentlich zu Ende und meldete
   das **Ergebnis** statt `-ECANCELED`.
3. **Ein Pufferüberlauf im Testprogramm.** `AIO_WAIT` mit `max=4`
   schreibt 128 Oktett; der Puffer war 32 groß. Auf dem Bildschirm stand
   danach der Name einer Zusage als Müll, und das Programm blieb später
   hängen. Ein Puffer, dessen Größe nicht aus derselben Zahl kommt wie
   das Argument, ist ein Fehler, der auf sich warten lässt.
4. **Die Warteschleife statt des Wartens** (siehe oben, 525 241 → 29).
5. **`fsync` verlangte Schreibrecht.** Ein asynchrones `fsync` auf einer
   mit `O_RDONLY` geöffneten Datei blieb still an der Rechteprüfung
   hängen, und der Test wartete fünf Sekunden auf eine Fertigmeldung,
   die nie kam. POSIX erlaubt `fsync` auf einem nur lesbar geöffneten
   Deskriptor ausdrücklich — er schreibt nichts, er drückt das schon
   Geschriebene auf den Träger.

Dazu ein sechster, der beim **Abschreiben des Testläufers** entstand:
`kernel/kernel.ld` sammelt den Ring-3-Code mit dem Muster
`*uprog*.o(.text .text.*)`. Der von `tools/poll/run.sh` übernommene
Läufer nannte die Objektdatei `u0.o` — damit landete `uprog.fi` im
Kerneltext, jedes Programm in Ring 3 fiel beim ersten Befehl, und der
Lauf war trotzdem „sauber" zu Ende: der Kernel sagte nur nichts mehr.
Runde HANDLE hatte denselben Fehler schon einmal.

---

## Was offen bleibt

* **Die Ausführung ist teilweise serialisiert.** `sys.read_of` und
  `sys.write_of` kopieren über **eine** Seite in `kdata`
  (`kstate.BLOCK_OFF`). Für Dateien, eingehängte Dateisysteme, Konsole,
  Terminal und Rahmenpuffer nimmt der Arbeitsfaden deshalb eine Sperre;
  Röhren und Steckdosen laufen ohne. Solange diese eine Seite existiert,
  ist echte Nebenläufigkeit auf Dateien nicht zu haben. Das gehört in
  eine Runde über den Kopierpfad, nicht in diese.
* **Ein blockierender Aufruf bleibt blockierend.** Ein asynchroner `read`
  auf einer leeren Röhre hält den Arbeitsfaden fest, der ihn hat. Die
  Schicht macht aus einem blockierenden Aufruf keinen nicht
  blockierenden — dafür ist `aio_poll` da. Bei vier Fäden und vielen
  solchen Aufträgen kann die Schicht verhungern.
* **`open` hat keine Lebensdauerzusage**, weil es kein Ziel-Handle hat.
  Sein Pfad wird bei der Abgabe kopiert (128 Oktett, längere Pfade geben
  `-ENAMETOOLONG`); alles andere ist gewöhnliches `open`.
* **Kein Verketten von Aufträgen** (io_urings `IOSQE_IO_LINK`), keine
  registrierten Puffer, kein `O_DIRECT`, kein Multishot.
* **Der Prozesstod wartet auf laufende Aufträge** (`drain_task`, bis zu
  5 s). Kommt ein Faden nicht zurück, bleibt der Prozess stehen, statt
  eine Kopie in freigegebenen Speicher laufen zu lassen. Ein hängender
  Prozess ist besser als ein Kernel, der fremde Seiten überschreibt —
  aber es ist eine Notbremse und keine Lösung.
* **Die Zahl der Arbeitsfäden ist fest** (vier) und ihre Priorität auch.

---

## Kann Runde RING darauf aufsetzen?

**Ja.** Begründung, Punkt für Punkt gegen `/root/osum-roadmap/KERNEL.md`,
Abschnitt 2:

1. **„Objekt-Handles + Refcounting mit klarer asynchroner Lebensdauer,
   Abbruch-Token von Anfang an"** — steht (Runde HANDLE) und ist jetzt
   **asynchron geprüft** (diese Runde, Fälle a–f, mit Gegenproben).
2. **„Kernintern alles als request → completion modellieren; das heutige
   synchrone ‚read block n' wird zum Sonderfall"** — genau das ist
   passiert: `read`, `write`, `open`, `close`, `fsync` und `poll` laufen
   über die Auftragsschicht, ausgeführt wird über denselben `read_of`,
   den auch `read(2)` benutzt. Kein zweiter Pfad daneben.
3. **„Ring-ABI: feste versionierte Eintragsgröße, Rückstau statt
   Verwerfen"** — die Fertigmeldung ist **schon heute** ein fester Satz
   von 32 Oktett in genau der Form, die der Ring bekommen soll
   (Kennung, Kennzahl, Ergebnis, Art). Der Rückstau ist gebaut und
   gemessen: nie mehr offene Aufträge je Prozess als Ringplätze, der
   siebzehnte gibt `-EAGAIN`, `lost=0`.
4. **„POSIX-read/poll als dünne Schicht darüber"** — `aio_poll` bildet
   readiness auf completion ab, nicht umgekehrt.

Was der Ring dann noch zu tun hat, ist **nur** der Weg der Einträge:
`aio_submit` wird ein Schreibvorgang in den SQ-Ring statt ein
Systemaufruf, `aio_wait` ein Lesevorgang aus dem CQ-Ring. Auftrag,
Zustand, Abbruch, Lebensdauer und Prozesstod bleiben, wie sie hier
stehen — und das ist genau die Reihenfolge, die die Roadmap verlangt und
die Linux nicht eingehalten hat.

**Eine Warnung gehört dazu**: mit geteiltem Speicher kann das Programm
den Auftragssatz **verändern, nachdem der Kernel ihn gelesen hat**. Die
Runde RING muss deshalb jeden Eintrag beim Einlesen **einmal in den Kern
kopieren** und danach nur noch die Kopie ansehen. Alles, was diese Runde
über Lebensdauer sichert, hilft gegen ein zweites Lesen aus dem
geteilten Speicher nicht.

---

## Randnotiz

Der Eigentümer hat am **29.08.2026** entschieden, dass Osum **statisch
gelinkt** wird (Punkt A9 der Roadmap). Für diese Runde hat das eine
sichtbare Folge: `lib/libc` ist Teil jedes Programms, und `/bin/aiot`
ist genau deshalb ein brauchbarer Test der libc-Anbindung — was der
Läufer mit `nm -u` prüft („kein undefinierter Name"), ist bei statischer
Bindung die vollständige Aussage und nicht die halbe.

---

## Abnahme

| Abschnitt | Ergebnis |
|---|---|
| `tools/async/run.sh` (neu) | **108 / 0** |
| `uprog.u_async` aus Ring 3 | 32 / 32 |
| `uprog.u_asyncfs` (Dateisystem) | 7 / 7 |
| `/bin/aiot` über die libc | 27 Zahlen, alle wie erwartet |
| Gegenproben `noagen` / `noareap` / `noawork` | fallen, wie sie sollen |
| beide Übersetzer (firnc0, firnc1) | identisch |
