# Runde RING — der Completion-Ring im geteilten Speicher

Zweig `ring`, Arbeitsbaum `/root/osum-ring`, abgezweigt von `async`
(e057901). **Nicht nach `main`, `mergeline`, `mergeline2`, `handle` oder
`async` gemergt.**

Gemessen am 30.08.2026 auf AMD EPYC 7571, QEMU mit `-accel kvm`,
TSC 2 202 226 kHz (2,2016 GHz), **ein Kern**.

---

## Was diese Runde ist, in einem Satz

Runde ASYNC hatte den Auftrag — Zustandsautomat, Lebensdauer, Abbruch,
Abräumung. Sie hatte nur einen teuren **Weg**: ein Systemaufruf je
Abgabe und einer je Abholung. Diese Runde ersetzt **genau diesen Weg**
und sonst nichts. Der Auftrag, seine Zustände, seine
Lebensdauerrechnung und der feste 32-Oktett-Fertigsatz sind Zeile für
Zeile die aus `async.fi`.

Was neu ist, sind zwei Ringpuffer in Speicher, den sich der Kern und
das Programm **teilen**.

---

## Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/ring.fi` | 1055 | **neu**: Ringtafel (8 Ringe à 128 Oktett), Kopf/Schwanz, die Kopierregel, die Maskierung, Überlaufzählung, Weckregel, Abräumung |
| `kernel/sys.fi` | +846 | die sechs Aufrufe ab 1986, `ring_setup`/`ring_map`/`ring_enter`/`ring_close`, die Ernte, die Weiche der Fertigmeldung, die Abgabewache im Arbeitsfaden |
| `kernel/uprog.fi` | +975 | `u_ring` (41 Zusagen aus Ring 3), `u_rbench` (die Messung) |
| `kernel/proc.fi` | +124 | die siebte Kachel (`RING_BASE`), `map_at`, `page_unmap`, kein Erben beim `fork` |
| `kernel/kmain.fi` | +167 | die Runde, die Leckzahlen, die Rahmenprobe, die Modusworte |
| `kernel/kstate.fi` | +75 | zwei Bereiche in `kdata`, fünf Modusbits, zwölf Zähler, `KDATA_SIZE` 0x90000 → 0x92000 |
| `kernel/user/ringt.fi` | 289 | **neu**: `/bin/ringt` — dasselbe von der Platte, über die libc |
| `lib/libc/io.fi` | +201 | `ring_setup/map/close/enter/kick/put/reap/room/…`, der Ringkopf |
| `lib/libc/kcall.fi` | +10 | die fünf Nummern (RING_INFO **nicht**) |
| `kernel/async.fi` | +18 | `cqe_id` — die Kennung eines Auftrags von außen |
| `kernel/arch/x86_64/boot.s` | 1 | `KDATA_SIZE` — dieselbe Zahl wie in `kstate.fi` |
| `tools/ring/run.sh` | 584 | **neu**: der Testläufer, 120 Zusagen |
| `tools/kernel/memmap.py` | +9 | die zwei neuen Bereiche in der Speicherkarte |

Zusammen **2408 eingefügte Zeilen**, davon 1055 neues Kernmodul.

---

## Der Entwurf

### Wo der Ring liegt

Nicht in `kdata`. Der Ring liegt in Rahmen, die `mem.frame_run` **am
Stück** besorgt und die in den Adressraum des Programms abgebildet
werden. Der Kern erreicht ihn über die physische Adresse (eine
Adresse für den ganzen Ring), das Programm über eine virtuelle.

`proc.PRIV_SLOTS` wächst dafür von 6 auf **7**. Die siebte Kachel
beginnt bei `0x40C00000` — **genau dort, wo `BIG_TOP` aufhört**. Das ist
der ganze Grund für diese Adresse: die Kachel liegt außerhalb *beider*
`mmap`-Fenster (das alte endet bei `MMAP_TOP` = 0x400F0000, das große
wächst von `BIG_TOP` nach unten). `munmap` auf eine Ringseite gibt
deshalb `-EINVAL`, **ohne eine einzige Sonderregel** — `do_unmap` nimmt
nur Adressen innerhalb der Fenster an. Ein Programm kann seinem eigenen
Kern die Seiten unter dem Ring nicht wegziehen; die Zusage
`grund-kein-munmap` misst genau das.

Ein Ring wird **nicht geerbt**: `proc.copy_space` überspringt die
Ringkachel. Ein Kind, das die Seiten geerbt hätte, sähe Fertigmeldungen
seines Vaters und könnte in einen Ring schreiben, der ihm nicht gehört.
Dieselbe Entscheidung wie bei `mmap` auf /dev/fb in Runde K7.

Im Kern liegen zwei Seiten, und beide sind das, was dem Programm
**nicht** gehören darf:

| Bereich | Adresse | Größe | was |
|---|---|---:|---|
| `RNG_OFF` | 0x90000 | 0x1000 | Ringtafel (8 × 128), Zuordnung Auftrag → Ring (64 Worte), Skalare |
| `RSC_OFF` | 0x91000 | 0x1000 | **die Kopierfläche**, 32 Aufgaben × 64 Oktett |

`memmap.py` rechnet nach: **76 Bereiche, 0 Kollisionen.**

### Der Ring selbst

```
+0x0000  der Kopf, eine EIGENE Seite
           MAGIC "SUM RING", Fassung, Längen, Masken, Versätze
           SQ_HEAD  Kern schreibt      SQ_TAIL  Programm schreibt
           CQ_TAIL  Kern schreibt      CQ_HEAD  Programm schreibt
           FLAGS (Bit 0 = WECKEN), DROPPED, OVER, BYTES, ID
+0x1000  Abgabering:  sqe  × 64 Oktett   (Art, fd, Puffer, Länge, Kennzahl)
+...     Fertigring: 2·sqe × 32 Oktett   (Kennung, Kennzahl, Ergebnis, Art)
```

Der Kopf bekommt eine eigene Seite. Das kostet 4096 Oktett und ist
Absicht: Kopf und Schwanz liegen damit nicht in derselben Cache-Zeile
wie die Sätze, und ein Rechenfehler in einem Satzindex kann nicht in den
Kopf hineinlaufen.

**Der Fertigring ist doppelt so lang wie der Abgabering.** Daraus folgt,
dass er nicht überlaufen kann: es gibt nie mehr Meldungen als abgegebene
Aufträge, und mehr offene Aufträge als Ringplätze lässt der Kern nicht
zu. Das Verhältnis 1:2 ist kein Puffer, sondern ein Beweis.

**Der Fertigsatz ist unverändert der aus `async.fi`** — 32 Oktett,
dieselben vier Felder. `aio_id`, `aio_udata`, `aio_result` und `aio_op`
aus der libc lesen ihn weiter. Wer von `aio_wait` auf den Ring umzieht,
ändert den Abholweg und keine Auswertung.

### Die sechs Aufrufe (1986..1991)

```
1986  ring_version()                              -> 1
1987  ring_setup(saetze, flaggen)                 -> HANDLE
1988  ring_map(h)                                 -> Adresse im Programm
1989  ring_enter(h, abgeben, mindestens, tmo_ms)  -> Zahl abgegeben
1990  ring_close(h)                               -> 0
1991  ring_info(was, arg)                         -> Innenzahl, NUR mit `uring`
```

1986 war die nächste freie Nummer: 1980..1985 gehören ASYNC, davor ist
der höchste Osum-Aufruf 1951, und `CAP_BASE` fängt bei 2000 an.
`RING_INFO` steht **nicht** in der libc — es gibt Innenzahlen des Kerns
heraus, und ein Testfenster, das im Regelbetrieb offen bleibt, ist eine
Hintertür.

### Der Ring ist ein HANDLE

Nichts Neues erfunden: `ring_setup` legt ein Objekt der Art `OK_RING`
an — die Art stand seit Runde HANDLE vorgemerkt und war bis heute
unbenutzt — und gibt ein Handle darauf. Benutzen braucht `R_WRITE`,
Abbauen `R_MANAGE`. Kein `R_TRANSFER` und kein `R_DUP`: ein Ring ist
geteilter Speicher zwischen dem Kern und **genau einem** Adressraum; ein
Handle darauf in einem anderen Prozess wäre ein Handle auf Seiten, die
dort gar nicht abgebildet sind.

Daraus folgt Zusage (f) **ohne eine eigene Zeile**: die Handle-Tafel ist
pro Aufgabe und ihre Generationen sind mit der pid gewürfelt. Ein
Handle-Wert aus einem fremden Prozess löst gar nicht erst auf.

---

## Die harte Auflage: genau eine Kopie

Der Abgabering liegt im Speicher des Programms. Es kann jeden Eintrag
jederzeit ändern — auch während der Kern ihn liest, auf einem zweiten
Kern, mitten in einem Wort.

> **REGEL 1.** Ein Abgabesatz wird beim Einlesen **einmal** vollständig
> in kerneigenen Speicher kopiert (`RSC_OFF`, 64 Oktett je Aufgabe), und
> danach arbeitet der Kern **ausschließlich** mit dieser Kopie. Niemals
> wird ein Feld ein zweites Mal aus dem geteilten Speicher gelesen.

Auch der Schwanzzeiger wird **genau einmal** gelesen (`ring.pending`) —
ein zweites `kstate.get` auf dieselbe Stelle wäre schon die halbe Lücke.

> **REGEL 2.** Kein Zeiger aus dem geteilten Speicher ist ein Index.
> Jeder Index entsteht aus dem Kopf (der dem Kern gehört) plus einer
> laufenden Nummer und wird **maskiert** — mit einer Maske aus der
> **Kerntafel**, nicht aus dem Kopf im geteilten Speicher. Zusätzlich
> wird die Zahl der anliegenden Sätze gegen die Ringlänge geprüft.

Der Fertigring braucht dieselbe Vorsicht andersherum: sein **Kopf**
gehört dem Programm. Gerechnet wird wickelnd (`-%`) und das Ergebnis
gegen die Ringlänge geprüft; ein Kopf vor dem Schwanz macht den Ring
„voll“ — das ist die sichere Seite, denn dann wird nichts
hineingeschrieben.

---

## Die Weckregel, ausdrücklich

Wenn das Abgeben keinen Systemaufruf mehr kostet, muss irgendjemand
merken, dass etwas abgegeben wurde. Das ist die größte Fehlerquelle
dieser Bauart, deshalb steht sie hier ausgeschrieben.

**Das Programm**

1. schreibt seine Abgabesätze,
2. schreibt **danach** den Schwanz (`sq_tail`),
3. liest **danach** das Flaggenwort im Ringkopf,
4. ruft `ring_enter` als Anstoß, **wenn** darin `R_F_WAKEUP` steht.

**Der Kern** (der *letzte* Arbeitsfaden, der schlafen gehen will)

1. setzt `R_F_WAKEUP` in **jedem** angemeldeten Ring,
2. setzt eine Speicherschranke (`atomic.barrier`),
3. **sieht noch einmal** in alle Ringe (`ring.any_pending`),
4. legt sich erst hin, wenn dann immer noch nichts da war.

Die beiden Folgen sind spiegelbildlich — schreiben → lesen gegen
schreiben → lesen —, und genau das schließt das Fenster: wer zuerst
schreibt, wird vom anderen gesehen. Die Schranke ist nicht Kosmetik: x86
ordnet einen Schreibzugriff **nicht** gegen ein späteres Lesen, und ohne
sie dürfte der Prozessor die Prüfung aus Schritt 3 vor den
Schreibzugriff aus Schritt 1 ziehen.

Gezählt wird das mit `ring.awake`: jeder Faden meldet sich an und ab
(`atomic.fetch_add`/`fetch_sub` — **nicht** `kstate.add`, das rechnet
seit Runde 72 geprüft, und ein Herunterzählen wäre dort die Addition
einer riesigen Zahl; der Kern ist beim ersten Anlauf genau daran
gestorben).

**Das Sicherheitsnetz darunter, ehrlich gesagt:** die Arbeitsfäden
schlafen ohnehin nur mit einer Frist von einer Sekunde
(`AIO_IDLE_TICKS`). Selbst wenn die Weckregel vollständig versagte, wäre
ein Auftrag spätestens nach einer Sekunde bearbeitet. Ein Hänger im
Wortsinn kann daraus nicht werden, eine Sekunde Verzögerung sehr wohl.
Die Weckregel ist also die **Leistungs**zusage, das Netz die
**Lebendigkeits**zusage.

### Die Abgabewache

Damit „Abgabe ohne Systemaufruf“ nicht nur theoretisch stimmt, wacht
**der erste** Arbeitsfaden nach seiner letzten Arbeit noch `RING_SPIN` =
200 Runden weiter und sieht dabei in die Ringe (`sched.yield_now`, kein
Drehen). Das ist io_urings `sq_thread_idle`. Nur einer wacht — vier
wachende Fäden wären vier Fäden, die sich gegenseitig den Prozessor
abgeben. Und nur, wenn es überhaupt einen angemeldeten Ring gibt: ein
Kernel ohne Ring verhält sich **genau** wie vor dieser Runde, und das
ist die Bedingung dafür, dass die Zusagen von ASYNC und POLL unverändert
weitergelten (ASYNC 108/0, POLL 67/0 nachgefahren).

---

## Die sieben Pflichtfälle, und was sie wirklich abfangen

Alle aus **Ring 3** (`uprog.u_ring`), jede Zusage einzeln vom Läufer
nachgelesen. Gearbeitet wird auf Röhren — aus demselben Grund wie in
HANDLE und ASYNC.

| # | Szenario | Zusagen | Gegenprobe |
|---|---|---|---|
| **a** | Abgabesatz nach der Abgabe geändert | `a-abgegeben`, `a-kopie-haelt`, `a-kopie-puffer`, `a-fremder-puffer-leer` | **`noringcopy`** → 3 fallen |
| **b** | Kopf/Schwanz gelogen (riesig, rückwärts) | `b-riesiger-schwanz`, `b-rueckwaerts-schwanz`, `b-kopf-steht`, `b-badsq-gezaehlt`, `b-danach-heil`, `b-fertigkopf-verbogen` | **`noringsq`** → 15 fallen |
| **c** | Ring voll → Rückstau | `c-acht-in-flug`, `c-rueckstau`, `c-satz-bleibt-da`, `c-kein-verlust`, `c-kein-leck` | — |
| **d** | Prozess stirbt mit Aufträgen im Ring | `d-ring-abgeraeumt`, `d-rahmen-zurueck`, `d-kein-auftrag` | — |
| **e** | Handle geschlossen, Platz neu vergeben | `e-selber-platz`, `e-veraltet` (−ESTALE), `e-nicht-das-neue-ding` | Erbe aus HANDLE/ASYNC |
| **f** | fremder Ring | `f-fremdes-handle-map/enter/close` (−EBADF) | — |
| **g** | alle Arbeitsfäden schlafen | `g-flagge-gesetzt`, `g-nach-anstoss-da`, `g-kicks-gezaehlt` | **`noawork`** |
| — | **ein Auftrag ganz ohne Systemaufruf** | `o-ohne-syscall`, `o-kein-ring-enter`, `o-ernte-gestiegen` | **`noawork`** |

Dazu zehn Zusagen über das Grundgerüst (Kennung, Fassung, Längen, Maske,
ein Auftrag hin und zurück, `munmap` verweigert, Speicherkosten) und die
Leckprobe.

**Ergebnis: 41 / 41, Beendigungscode 0, mit beiden Übersetzern.**

### Wie (a) deterministisch gemacht wurde

Zusage (a) beschreibt ein **Zeitfenster**: der Satz ist kopiert und noch
nicht ausgeführt, und *genau dann* wird er überschrieben. Ohne Eingriff
hinge es an der Zeitscheibe, ob der Test das Fenster trifft.

Dafür wird der **Prüfstandshalt** der Runde ASYNC benutzt (`RING_INFO
20` → `async.hold`): die Arbeitsfäden nehmen keinen neuen Auftrag an.
Der Ablauf ist dann jedes Mal derselbe:

1. Halt an.
2. Abgabesatz hinlegen: lies vier Oktett nach **Puffer A**, Kennzahl
   `0xA1`.
3. `ring_enter(abgeben = 1)`. Jetzt kopiert der Kern — nachweislich,
   denn er gibt „1 abgegeben“ zurück.
4. **Den Satz überschreiben**: schreib nach **Puffer B**, Länge 64,
   Kennzahl `0xBAD`.
5. Halt aus, warten, abholen.

Herauskommen **muss**: Kennzahl `0xA1`, vier Oktett, und sie stehen in
Puffer A. Puffer B ist unberührt.

### Was die Gegenproben zeigen — und was nicht

* **`noringcopy`** (`M_NOCOPY`): der Kern liest Puffer, Länge und
  Kennzahl bei der **Ausführung** noch einmal aus dem geteilten
  Speicher. `a-kopie-haelt` fällt mit **`got=2989`** — das ist `0xBAD`,
  die Kennzahl des Angreifers. Das ist nicht „irgendetwas ging schief“,
  das ist genau der io_uring-Fehler, und der Läufer prüft ausdrücklich
  auf diese Zahl. Die anderen 38 Zusagen stehen trotzdem: sie messen
  etwas anderes, und das gehört dazugesagt.
* **`noringsq`** (`M_NOSQCHK`): der Kern glaubt dem Schwanz. Er
  arbeitet dann eine Million behauptete Abgabesätze ab, und der Ring ist
  danach unbrauchbar — **15 von 41** Zusagen fallen. Er greift dabei
  *trotzdem* nicht daneben, denn der Index wird eine Zeile tiefer
  weiterhin maskiert; die zweite Verteidigungslinie hält. Das ist die
  ehrliche Lesart: die Plausibilitätsprüfung schützt nicht vor dem
  Speicherzugriff, sondern vor dem *Verarbeiten von Müll* — und darauf
  steht alles Weitere.
* **`noawork`**: ohne Arbeitsfäden gibt es keine Ringabfrage.
  `o-ohne-syscall`, `o-ernte-gestiegen` und `g-flagge-gesetzt` fallen.
  Das ist der Nachweis, dass die Abgabe ohne Systemaufruf wirklich von
  einem **anderen** Faden abgeholt wird und nicht heimlich vom
  Abgebenden selbst.

### Die Leckzahlen

```
ring: used=0        belegte Ringplätze
ring: inflight=0    Aufträge, die noch einem Ring zugeordnet sind
ring: aioused=0     belegte Auftragsplätze
ring: overflow=0    Fertigmeldungen ohne Platz
ring: denied=0      gelungene Zugriffe auf einen fremden Ring
ring: awake=0       wache Arbeitsfäden
ring: setups=3      closes=3       badsq=2   badcq=1
```

Und die Zahl, die es ohne diese Runde nicht gab: **die Rahmen.** Ein
Ring ist der erste Speicher dieses Systems, den ein unprivilegierter
Prozess vom Rahmenverwalter bekommt und den nur der Kern zurückgeben
kann. `ring: frames` → `frames-after` geht um genau 32 Rahmen zurück,
und das sind die Kernstapel der vier Arbeitsfäden aus Runde ASYNC
(4 × `KSTACK_FRAMES` = 32), die bei der ersten Abgabe entstehen. Der
Läufer rechnet das aus `sched.KSTACK_FRAMES` und `async.WORKERS` nach,
statt eine Zahl hinzuschreiben.

Die **genaue** Rahmenprobe steht in Ring 3: `d-rahmen-zurueck` misst
vor und nach dem Tod eines Kindes mit eigenem Ring, auf den Rahmen
genau.

---

## Die Messung

Gleiche Methodik wie ASYNC: `read` von 32 Oktett vom Leseende einer
Röhre, die vor jedem Block gefüllt wird, 33 Blöcke, **Median**.
`abench` und `rbench` laufen in **einem Boot** — der synchrone Weg misst
sich zwischen zwei Boots um bis zu 20 % anders, und nur in einem Boot
sagen die Verhältnisse etwas.

**Auf einem Kern.** Die Messung läuft in `kmain` vor `smp.stage`, genau
wie die der Runde ASYNC; der zweite Prozessor ist da noch nicht
gestartet. Das ist die Bedingung, unter der der synchrone Weg am besten
dasteht.

### 16 × 32 Oktett — direkt vergleichbar mit ASYNC

| Weg | Zyklen | µs | Aufträge/s |
|---|---:|---:|---:|
| synchron | 8 441 | 3,83 | 260 900 |
| async Tiefe 1 | 34 722 | 15,77 | 63 400 |
| async Tiefe 4 | 18 172 | 8,25 | 121 200 |
| async Tiefe 16 | 14 067 | 6,39 | 156 500 |
| **ring Tiefe 1** | **32 665** | **14,83** | **67 400** |
| **ring Tiefe 4** | **17 164** | **7,79** | **128 300** |
| **ring Tiefe 16** | **13 130** | **5,96** | **167 700** |
| async **nur Abgabe** | 2 422 | 1,10 | 909 000 |
| **ring nur Abgabe** | **136** | **0,062** | **16 190 000** |

### 64 × 8 Oktett — die Tiefen und Bündel über 16

Eine Röhre fasst 512 Oktett (`file.PIPE_CAP`); mehr als 512 Oktett je
Block gehen nicht, ohne dass schon das Füllen blockiert. Deshalb ein
zweiter, in sich vergleichbarer Satz Zahlen.

| Weg | Zyklen | µs | Aufträge/s |
|---|---:|---:|---:|
| synchron | 2 705 | 1,23 | 813 800 |
| ring Tiefe 64 | 6 920 | 3,14 | 318 100 |
| ring **ohne jeden Anstoß**, Bündel 1 | 25 803 | 11,72 | 85 300 |
| ring **ohne jeden Anstoß**, Bündel 8 | 8 578 | 3,90 | 256 600 |
| ring **ohne jeden Anstoß**, Bündel 32 | 6 818 | 3,10 | 322 900 |

### Systemaufrufe je 1000 abgeschlossene Aufträge

Das ist die aussagekräftigste Zahl dieser Runde.

| Weg | Aufrufe je 1000 Aufträge |
|---|---:|
| synchron (`read`) | 1000 |
| Runde ASYNC (`aio_submit` + `aio_wait` mit `min_complete` 16) | 1000 + ≥ 63 = **≥ 1063** |
| Runde RING, gemessen über 6336 Aufträge | **0 bis 1 insgesamt**, also **0 je 1000** |

Die Null ist **gemessen und nicht gerechnet**: in den drei
„ohne Anstoß“-Läufen gingen **6336 Aufträge** durch den Ring
(`rbench: harvest=6336`), und `ring_enter` wurde dabei über mehrere
Läufe hinweg **null- bis einmal** gerufen (`rbench: kicks`). Der Läufer
verlangt höchstens 32 Aufrufe für 6336 Aufträge — absichtlich keine
harte Null: gibt die Abgabewache in einer Pause auf, setzt der Kern die
Weckflagge und das Programm stößt **einmal** an. Genau dafür ist die
Weckregel da, und ein Test, der null verlangt, würde die Regel
bestrafen statt sie zu prüfen. Ein Anstoß je *Pause* — nicht einer je
*Auftrag*: das ist der Unterschied zu allen Zeilen darüber.

**Ehrlich dazu:** `SYS_YIELD` in der Warteschleife ist auf *einem* Kern
unvermeidlich — der Arbeitsfaden bekommt den Prozessor sonst nie — und
in dieser Null nicht enthalten. Gezählt sind die Aufrufe **für Abgabe
und Abholung**, und die sind wirklich null. Auf zwei Kernen fiele auch
das Abgeben des Prozessors weg; die Messung läuft aber bewusst unter
denselben Bedingungen wie die von ASYNC.

### Speicherkosten je Ring

| Abgabering | Fertigring | Seiten | Oktett |
|---:|---:|---:|---:|
| 8 | 16 | 2 | 8 192 |
| 32 | 64 | 2 | **8 192** |
| 64 | 128 | 3 | 12 288 |
| 128 | 256 | 5 | 20 480 |

Zum Vergleich: ein Auftrag der Runde ASYNC kostet 112 Oktett
(Auftragssatz + Platz im Fertigmeldungsring). Ein Ring mit 32 Sätzen
kostet 8192 Oktett für **alles** — Kopf, 32 Abgabeplätze und 64
Fertigplätze. Acht Ringe zu 128 Sätzen sind die Obergrenze: 160 KiB, die
ein Programm dem Rahmenverwalter entziehen kann.

---

## Die ehrliche Zeile

**Der synchrone Weg wird auf einem Kern weiterhin nicht geschlagen.**
8441 gegen 13130 Zyklen bei Tiefe 16 — Faktor 1,56 zugunsten von
synchron (in Runde ASYNC war es Faktor 1,62).

Der Grund ist unverändert und liegt **nicht** am Weg der Einträge: die
Arbeitsfäden gehen intern weiter **synchron** auf die Platte, und die
Wege über `kstate.BLOCK_OFF` sind zusätzlich durch die
Ausführungssperre serialisiert. Diese Runde schafft den *Systemaufruf je
Auftrag* ab, nicht die *Wartezeit des Geräts*. Solange die Arbeit selbst
synchron ist, kann Nebenläufigkeit auf einem Kern nichts gewinnen — sie
kostet nur den Weg zum Arbeitsfaden und zurück.

Was diese Runde **wirklich** gewonnen hat:

* **Die Abgabe: 2422 → 136 Zyklen, Faktor 17,8.** Ein `read` abzugeben
  kostet einen Prozess jetzt sechs Schreibzugriffe in eigenen Speicher
  statt eines Systemaufrufs.
* **Die Aufrufe: ≥ 1063 → 0 je 1000 Aufträge**, gemessen.
* **Gegen ASYNC**, also gegen genau die Schicht, deren Abholweg sie
  ersetzt: −6 % (Tiefe 1), −6 % (Tiefe 4), −7 % (Tiefe 16).

Bei Tiefe 1 ist der Unterschied klein, und das hat einen Grund: dort
besteht die Zeit fast vollständig aus dem Weg zum Arbeitsfaden und
zurück (Zeitscheibe, Wecken, Umschalten). Der eingesparte Systemaufruf
ist dort ein kleiner Posten. Der Läufer verlangt bei Tiefe 1 deshalb nur
„nicht schlechter als 10 % über ASYNC“ und begründet das an Ort und
Stelle — eine harte Schranke wäre dort ein Test, der von der Auslastung
des Wirts abhängt.

---

## Was offen bleibt

* **Echte Geräte-Warteschlangen (NVMe/AHCI).** Das ist die Grenze, an
  der alle Zahlen oben hängen. Solange ein Arbeitsfaden synchron auf die
  Platte geht, ist Nebenläufigkeit auf einem Kern ein Verlustgeschäft.
* **Die eine Kopierseite** `kstate.BLOCK_OFF`. `read_of`/`write_of`
  kopieren darüber, und die Ausführungssperre serialisiert alles, was
  kein Rohr und keine Steckdose ist. Das ist der zweite Engpass, und er
  ist unabhängig vom ersten.
* **Registrierte Puffer und Deskriptoren** (io_urings `IORING_REGISTER_*`).
  Ein Puffer wird heute bei jeder Abgabe mit `proc.user_ok` geprüft —
  ein Tabellendurchgang je Seite. Vorab geprüfte, festgepinnte Puffer
  wären der nächste einzelne Posten.
* **Verkettete Aufträge** (`IOSQE_IO_LINK`). Jeder Satz steht für sich.
* **Ein Ring über mehrere Fäden** (`clone`-Geschwister). Ein Ring gehört
  heute genau einer Aufgabe; `T_SHARED`-Fäden bekommen keinen Zugriff.
* **Mehr als ein Kern in der Messung.** `rbench` läuft vor
  `smp.stage`. Die Zahl, die diese Runde am besten aussehen ließe,
  wurde also bewusst nicht erhoben.

---

## Ist NVMe/AHCI als Nächstes der richtige Schritt?

**Ja, eindeutig — und diese Runde ist der Grund dafür.**

Bis hierher war es umgekehrt. Vor HANDLE hätte eine Geräte-Warteschlange
nichts gehabt, woran sie hängen könnte: kein Auftrag, der den Aufruf
überlebt, keine Lebensdauerrechnung, kein Weg, eine Fertigmeldung
zuzustellen. Jetzt steht das alles, und zwar geprüft:

* HANDLE gibt die Lebensdauer (Generation, Verweiszähler, Token),
* ASYNC gibt den Auftrag, der länger lebt als sein Aufruf,
* RING gibt den Weg hinein und hinaus, ohne Systemaufruf.

Was fehlt, ist genau **ein** Stück: dass ein Auftrag am Ende nicht in
einem Faden landet, der `blk.read` ruft und wartet, sondern in einer
Warteschlange, die das Gerät selbst abarbeitet. Die Zahlen sagen das
sehr deutlich — jede Zeile oben, in der der synchrone Weg vorn liegt,
liegt an dieser einen Stelle, und an keiner anderen.

Und die Reihenfolge stimmt auch von der Gefahrenseite her: NVMe schreibt
per DMA in Speicher, den es aus einer Warteschlange liest. Eine
Warteschlange, die auf einem Auftrag ohne Generationsprüfung sitzt, ist
kein Leistungsproblem, sondern ein Schreibzugriff des Geräts in eine
Seite, die inzwischen jemand anderem gehört. Diese drei Runden sind die
Voraussetzung dafür, das überhaupt bauen zu dürfen.

Konkret als nächste Runde:

1. **NVMe zuerst, AHCI danach.** `kernel/nvme.fi` steht schon, und NVMe
   *ist* eine Ringstruktur — Submission Queue und Completion Queue mit
   Kopf und Schwanz, dieselbe Form wie hier, nur mit einem Türklingel-
   Register statt einem Arbeitsfaden.
2. **Ein Auftrag geht direkt in die Geräte-Warteschlange** statt in
   einen Arbeitsfaden. Die Fertigmeldung kommt aus der
   Completion-Warteschlange des Geräts und geht über `ring.post`
   unverändert weiter — der Fertigsatz bleibt derselbe.
3. **Die Ausführungssperre und `BLOCK_OFF` fallen für diesen Pfad
   weg.** DMA geht in vorab gemappte Puffer, nicht durch eine
   Kopierseite.
4. **Die Messung wird dieselbe sein** — `rbench`, dieselben Blöcke,
   derselbe Median —, nur auf einer Datei statt auf einer Röhre. Erst
   dann ist die Frage „schlägt asynchron synchron?“ überhaupt fair
   gestellt.

Planungsreferenz: `/root/osum-roadmap/KERNEL.md`, Punkt 2
(„I/O — die größte Lücke. Completion statt Readiness.“) und Punkt 1
(IOMMU als Voraussetzung für alles, was ein Gerät selbst adressieren
lässt).

---

## Abnahme

| Läufer | Ergebnis |
|---|---|
| `tools/ring/run.sh` | **120 bestanden, 0 gefallen** |
| `tools/async/run.sh` | 108 / 0 |
| `tools/handle/run.sh` | 80 / 0 |
| `tools/poll/run.sh` | 67 / 0 |
| `tools/posix/run.sh` | 134 / 0 |
| `tools/kernel/run.sh` | 176 / 0 |

Beide Übersetzer (firnc0 und firnc1) bauen denselben Kernel und geben
dieselben 41 Zusagen.
