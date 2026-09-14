# Speicherdruck / OOM (K-002)

Punkt K-002 der Offenliste, woertlich: *"Speicherdruck/OOM — keine
Auswahl, keine Reserve. Bei vollem RAM friert das System ein."*
Quelle: ROADMAP A10.

Dieser Bericht haelt ZUERST fest, wie es sich heute wirklich verhaelt,
und zwar bevor eine Zeile am Kern geaendert wurde. Der Befund ist
teilweise ANDERS als die Offenliste behauptet, und das ist das
wichtigste Ergebnis der Messung.

---

## 1. Das Werkzeug der Messung

`kernel/uprog.fi` bekommt zwei Programme:

* **`P_HOG` (64)** — frisst Speicher, bis nichts mehr kommt, und sagt
  bei jedem Schritt, wie weit er ist. Die laufende Ausgabe ist der
  ganze Punkt: ohne sie sieht ein gestorbener Fresser genauso aus wie
  ein haengender, und genau diese Unterscheidung ist der Befund.
* **`P_HOGWRITE` (65)** — derselbe Fresser, aber er schreibt VORHER
  eine Datei mit bekanntem Inhalt und haelt sie offen. Stirbt er
  mitten darin, muss die Datei trotzdem heil sein.

Gesteuert ueber die Kommandozeile (`kernel/kstate.fi`, Wort 15):
`memhog`, `memhogn`, `hogwrite`, und die Gegenproben `nooom`,
`noreserve`, `oomsay`, `koom`.

Der Messlauf `speicherdruck()` in `kernel/kmain.fi` schreibt die Zahl
der freien Rahmen VOR und NACH dem Lauf auf die Leitung. Die
Anfangszahl steht dort, bevor der erste Fresser startet — was schon
auf der Leitung steht, bleibt lesbar, auch wenn der Rechner danach
einfriert.

### Die erste Messung war falsch, und warum das wichtig ist

Der Fresser benutzte zuerst `brk`. Er meldete `fail=448` — nach 448
KiB. Das sah aus wie ein sauberes "kein Speicher" bei 120 MiB freiem
Arbeitsspeicher und war keines:

    BRK_BASE = 0x40080000, MMAP_TOP = 0x400F0000
    0x400F0000 - 0x40080000 = 0x70000 = 458.752 Oktette = 448 KiB

Das ist das Ende des ADRESSRAUMS zwischen Bruch und Abbildungsbereich,
nicht das Ende des Speichers. Wer hier aufhoert zu messen, berichtet
eine Zusage, die er nie geprueft hat. Der Fresser benutzt seit dieser
Erkenntnis `mmap`, das nach der alten Halde in der grossen Arena
(`proc.BIG_FLOOR`..`BIG_TOP`, rund 186 MiB) weiterlaeuft und 128 MiB
Arbeitsspeicher wirklich leerraeumen kann.

---

## 2. Der Befund: so stirbt es heute

Gemessen mit dem Kern aus diesem Baum, QEMU, `-m 128` und `-m 64`.

### 2a. Ein Fresser, 128 MiB

    speicherdruck: frei=30750        (30750 Rahmen = 120 MiB)
    hog: start #1
    hog: kib=2048 ... hog: kib=120832
    hog: fail=122624                 (119 MiB gefressen)
    hog: ende
    speicherdruck: code=0
    speicherdruck: nach=30750        (ALLE Rahmen zurueck)
    speicherdruck: lebt=1
    kernel: done                     (QEMU-Code 21)

### 2b. Drei Fresser gleichzeitig, 128 MiB

    speicherdruck: frei=30750
    hog: fail=41728 / 38912 / 41728  (zusammen wieder rund 119 MiB)
    speicherdruck: code=0 0 0
    speicherdruck: nach=30750
    speicherdruck: lebt=1

### 2c. Drei Fresser, 64 MiB

    speicherdruck: frei=14366
    hog: fail=18688 / 16640 / 21504
    speicherdruck: nach=14366
    speicherdruck: lebt=1

### 2d. Fresser mit offener Datei, 128 MiB

    hogwrite: start #1
    hogwrite: wrote=64
    hogwrite: fail=122624
    speicherdruck: nach=30750

### Was daraus folgt

**Der `mmap`-Weg friert NICHT ein.** Er gibt eine ehrliche Absage,
der Prozess ueberlebt sie, der Kern raeumt jeden Rahmen wieder auf
(30750 vorher, 30750 nachher — kein einziger verloren) und laeuft bis
`kernel: done` weiter. Das gilt bei 128 MiB wie bei 64 MiB, mit einem
Fresser wie mit dreien, mit und ohne offene Datei.

Der Grund steht in `kernel/sys.fi`, `do_mmap`: schlaegt
`proc.map_page_zero` fehl, kommt `neg(errno.E_NOMEM)` zurueck — ein
richtiger Fehlercode, den ein Programm lesen kann.

**Die Aussage der Offenliste ist in dieser Form also nicht mehr
zutreffend**, und das gehoert in den Bericht, statt einen Freeze zu
inszenieren, den es an dieser Stelle nicht gibt.

---

## 3. Was WIRKLICH kaputt ist

Nicht der Freeze — die **stille Luege von `brk`**.

`kernel/sys.fi`, `do_brk`:

    if proc.map_page_zero(state, me, p, true, false) == 0 {
        return cur                   // <-- der ALTE Bruch
    }

Linux beantwortet eine Absage tatsaechlich mit dem alten Bruch, und der
Kommentar darueber beruft sich darauf. Der Unterschied ist, was davor
passiert: Osum hat die Seiten bis `p` da schon abgebildet und BEHAELT
sie. Der Aufrufer sieht den alten Wert, haelt das fuer "nicht
gewachsen" — und die Rahmen dazwischen sind weg, ohne dass irgendwer
sie noch besitzt. Bei jedem fehlgeschlagenen `brk` erneut.

Dazu kommt: es gibt **keine Reserve**. Faellt der letzte Rahmen an
einen Nutzerprozess, steht der Kern fuer alles, was er im Notfall noch
tun muesste — melden, synchronisieren, aufraeumen — ohne Speicher da.
Dass heute nichts einfriert, liegt daran, dass `do_mmap` sauber
zurueckweist, nicht daran, dass der Notfall behandelt waere. Es gibt
auch **keine Auswahl**: stirbt etwas, dann der Zufaellige, der gerade
gefragt hat — nie der groesste Verbraucher, und der Fensterserver
waere so wenig geschuetzt wie jeder andere.

---

## 4. Was diese Runde daraus macht

1. **Reserve** — ein Vorrat an Rahmen, an den nur der Kern kommt.
2. **`do_brk` ehrlich machen** — bei Fehlschlag das schon Abgebildete
   zurueckgeben, statt es verfallen zu lassen.
3. **Auswahl** — trifft es jemanden, dann den groessten beendbaren
   Verbraucher; Prozess 1, Fensterserver und Taskleiste sind
   ausdruecklich geschuetzt.
4. **Vorher synchronisieren** — Dateisystempuffer auf die Platte,
   bevor etwas beendet wird.
