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

---

## 5. Was gebaut wurde

### 5a. Die Reserve

`mem.frame_alloc` bleibt, wie es war, und ist ab jetzt der Weg DES
KERNS: er darf bis auf den letzten Rahmen zuteilen, denn er ist
derjenige, der den Notfall behandeln muss.

Neu ist `mem.frame_alloc_user`, der `RESERVE_FRAMES` Rahmen frueher
aufhoert. **Der Unterschied zwischen den beiden Funktionen IST die
Reserve** — es braucht keinen zweiten Vorrat und keine eigene Liste,
nur eine Grenze, die der eine sieht und der andere nicht.

`proc.map_page` biegt darauf ab, und das ist die einzige noetige
Stelle: `brk`, `mmap`, der wachsende Stapel und `fork` gehen alle
durch ihn.

Groesse: ein Zweiundfuenfzigstel des Speichers, mindestens 64 Rahmen
(256 KiB), hoechstens 512 (2 MiB). Die Untergrenze ist nicht geraten —
eine Seitentabelle ist ein Rahmen, einen Prozess abzuraeumen kostet im
schlimmsten Fall eine Handvoll davon, dazu der Puffer fuers Melden und
was das Dateisystem beim Synchronisieren anfasst.

### 5b. `do_brk` ist ehrlich geworden

Statt den alten Bruch zurueckzugeben und die schon abgebildeten Seiten
verfallen zu lassen, wird der Bruch dorthin gesetzt, wo er wirklich
steht. Die Absage bleibt eine Absage — er ist nicht bis `want`
gewachsen, und eine libc liest das als Fehlschlag —, aber kein Rahmen
ist mehr verloren.

### 5c. Die Auswahl

`sys.oom_pick` nimmt **den groessten beendbaren Verbraucher**.
`T_UPAGES` wird in `proc.map_page`/`page_drop` mitgezaehlt, damit die
Zahl im Notfall sofort dasteht — im Notfall die Seitentabellen aller
Prozesse abzulaufen hiesse, ausgerechnet dann viel Arbeit zu tun, wenn
nichts mehr geht.

Geschuetzt sind: `pid <= 1`, alles was nicht `K_USER` ist, und jeder
mit `T_OOMSAFE`. Den Vermerk bekommt, was durch `kgui.desk_spawn_n`
startet — Schreibtisch, Taskleiste, Starter, Einstellungen, Anmeldung.

Findet sich niemand, wird **niemand** genommen und die ehrliche Absage
bleibt die Antwort. Das ist der Normalfall dieser Runde, nicht der
Ausnahmefall.

### 5d. Vorher synchronisieren

`sys.oom_handle` ruft `do_sync`, **bevor** jemand stirbt, und sagt erst
dann auf der Leitung, wen es trifft. Die Reihenfolge ist der ganze
Unterschied zwischen "der Speicher ist wieder da" und "die Datei ist
halb geschrieben".

### 5e. Die Reihenfolge war falsch, und das war der zweite Fund

Der Messlauf lief bei `vectors()`, lange VOR `desk_start`. Der Fresser
hat den Speicher leergeraeumt, bevor es eine Oberflaeche gab, die man
haette verschonen koennen — die Messung haette nichts belegt. Mit
`desk` uebernimmt jetzt `kgui.speicherdruck_gui` und startet die
Fresser NACH dem Schreibtisch, ohne auf sie zu warten (`wait_for`
wuerde den Fensterserver anhalten).

---

## 6. Die Abnahme

`bash tools/oom/run.sh` — **37 Zusagen, 0 Fehler.**

    == 2. ein Fresser: ehrliche Absage statt Freeze ==
      der Kern hat sich selbst beendet (QEMU-Code 21)
      der Fresser bekam eine ehrliche Absage und hat sie ueberlebt
      jeder Rahmen ist zurueck: 30749 vorher, 30749 nachher

    == 3. die Reserve greift, und sie ist gezaehlt ==
      die Reserve steht: 512        sie hat wirklich abgewiesen: 1
      Gegenprobe noreserve: res=0
      ohne Reserve frisst er weiter: 122624 statt 120576 KiB

    == 4. die harten Faelle ==
      drei Fresser gleichzeitig / 64 MiB: das System lebt, kein Rahmen weg
      Fresser mit offener Datei auf echter Platte

    == 5. DIE ABNAHME ==
      Schreibtisch (pid 2), Taskleiste (pid 3), Starter (pid 4) laufen
      getroffen hat es nur die Fresser (pid 6, 8)
      beide Fenster stehen danach noch, wm dreht weiter
      Bild: docs/shots/oom/oom-desktop.png

Das Bild ist 1280x800 und hat 177 verschiedene Farben; die Taskleiste
(30,41,59) ist vom Schreibtisch (102,103,107) unterscheidbar. Ein
schwarzes oder einfarbiges Bild hiesse, der Schreibtisch malt nicht
mehr — und genau das faellt hier auf.

`tools/check-ui.sh` bleibt gruen.

---

## 7. Was bewusst offen bleibt

* **Kein Auslagern.** Es gibt keine Platte als Speicher-Ersatz, also
  bleibt bei vollem RAM nur Absagen oder Toeten. Das ist eine bewusste
  Grenze dieser Runde und kein Versehen.

* **Die Auswahl kennt nur Seiten, nicht Wichtigkeit.** Der groesste
  beendbare Verbraucher ist eine stumpfe Regel. Sie ist
  nachvollziehbar und wiederholbar — bei Gleichstand gewinnt der
  erste, derselbe Zustand trifft also immer denselben Prozess. Eine
  Regel mit Gewichten (`oom_score_adj`) waere klueger und wurde
  bewusst nicht gebaut.

* **Keine Warnung vor dem Notfall.** Es gibt keine Schwelle, bei der
  das System sagt "der Speicher wird knapp", bevor es eng wird.

* **Die Meldung steht auf der Leitung, nicht im Fenster.** Der Auftrag
  erlaubte eine Meldung "Programm X wurde wegen Speichermangels
  beendet" ueber fUi/wlib. Sie wurde NICHT gebaut: der Notfall wird im
  Kern behandelt, und ein Fenster von dort aus zu oeffnen hiesse, im
  Speichernotfall Speicher fuer eine Oberflaeche zu verlangen. Der
  richtige Weg waere ein Dienst, der die Zeile liest und das Fenster
  im Benutzerraum aufmacht — eine eigene Runde.

* **`hogwrite` kam im Messlauf nicht bis zum Schreiben.** Die Zusage
  "eine vor dem Ereignis geschriebene Datei ist danach heil" ist damit
  fuer den Fall belegt, dass der Fresser die Datei anlegt, und nicht
  fuer den Fall, dass er mitten im `write` stirbt. Der Unterschied ist
  klein, aber er ist da, und er steht hier statt in einer Zusage, die
  mehr behauptet als sie zeigt.

---

## 8. Die anderen Laeufer

Die Runde fasst den Rahmenzuteiler an, den jeder Teil des Systems
benutzt. Also wurden die Laeufer mitgemessen, die davon abhaengen:

    tools/mem/run.sh       50 bestanden, 0 gescheitert
    tools/kernel/run.sh   176 bestanden, 0 gescheitert
    tools/oom/run.sh       37 bestanden, 0 gescheitert
    tools/check-ui.sh      PASSED
    tools/posix/run.sh    149 bestanden, 1 gescheitert  <-- siehe unten

**Der eine POSIX-Fehler gehoert NICHT zu dieser Runde.** Er lautet
`SYS_OSUM_WECHSEL: kernel 1704, libc missing` — der Kern nennt den
Aufruf `SYS_OSUM_WECHSEL`, die libc `SYS_WECHSEL`, und der Laeufer
vergleicht die Namen. Gegengeprueft auf `main` OHNE eine einzige
Aenderung dieser Runde: derselbe Fehler, dieselbe Zeile.

Dass die Zahl 1704 auch als `kstate.RESERVE_FRAMES` vorkommt, ist ein
Zufall und keine Kollision: das eine ist eine Aufrufnummer in
`sys.fi`, das andere ein Feldabstand in der `kdata`-Seite. Zwei
getrennte Namensraeume, die nichts voneinander wissen.
