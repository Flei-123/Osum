# Runde SCHLAF (K-018, zweite Hälfte) — der Ruhezustand bekommt seine übrigen Träger

**Stand:** 15.09.2026 · Zweig `schlaf`, abgezweigt von `main` (`0a1d067`) ·
Abnahme: `bash tools/suspend/run.sh` · Nummernvorrat: kdata
`0x121000..0x126000` (**vorher zugeteilt**), Modusindizes **1020..1029**
(belegt 1020..1026), Kommandozeilenwörter `schlafarm`, `schlafpruef`,
`schlaf`, `schlafhw`, `schlafkaputt`, `noschlaf`, `schlafmess`.

---

## 1. Der Satz, um den es geht

**Ein System mit laufenden Prozessen geht auf die Platte, QEMU wird
beendet, ein neuer Kern startet, findet das Abbild von selbst und
spielt es ein — und ein Prozess, der vorher gerechnet hat, rechnet
danach richtig weiter.**

Die Vorrunde `suspend` hat den **Träger** gebaut und ehrlich
hingeschrieben, dass die Maschine noch nicht wirklich schläft. Diese
Runde baut die fünf Punkte, die dort als rote Punkte standen. Was sie
**nicht** baut, steht in Abschnitt 8 und nicht in einer Fußnote:
**S3 ist weiterhin nur gemessen, nicht gebaut** — und der Sprung in den
gesicherten Registersatz hinein ebenfalls nicht.

---

## 2. Der Unterschied zur Vorrunde, in einem Satz

Die Vorrunde lief in **einem** Kernlauf: sie schrieb das Abbild, verwarf
den Zustand im Speicher und holte ihn zurück. Das misst den Träger — aber
nichts zwang den Kern, den Zustand wirklich verloren zu haben. Bitkarte,
Seitentabellen und Arbeitsspeicher standen die ganze Zeit unverändert da.

Diese Runde misst über den **Hochlauf**. Je Zyklus zwei QEMU-Läufe mit
**derselben Plattendatei**, und dazwischen wird QEMU **beendet**:

| Lauf | Kommandozeile | was er tut |
|---|---|---|
| A | `osum schlafarm acpiev` | Prozesse anlegen, rechnen lassen, sichern, Gast **beenden** |
| B | `osum schlafpruef acpiev` | der Hochlauf findet das Abbild **von selbst**, spielt ein, vergleicht |

Zwischen A und B ist der Arbeitsspeicher wirklich weg. Was B erreicht,
steht ausschließlich auf der Platte.

---

## 3. Die sechs Punkte, einzeln

### Punkt 1 — Starterkennung · **steht**

`schlaf.boot_check` hängt in `kmain.fi` hinter `susp.late`. Die Stelle ist
die halbe Runde: **hinter** der Plattenmessung (ohne Platte kein Abbild),
**vor** allem, was Rahmen anfordert (das Einspielen legt Rahmen an genau
die physischen Adressen zurück, an denen sie lagen).

Geprüft wird in dieser Reihenfolge, und die Reihenfolge ist die
Begründung:

1. **MAGIC und Fassung** — ohne sie wäre alles Weitere ein Lesen von Zufall.
2. **Die Hardware-Kennung** — **vor** der Prüfsumme. Ein Abbild einer
   anderen Maschine ist auch dann falsch, wenn es in sich stimmig ist,
   und dieser Fall ist der gefährlichere: er sieht gesund aus.
3. **Die Prüfsumme über die ganze Nutzlast** — erst danach gilt irgendetwas.

#### Die Hardware-Kennung, und warum gerade diese

Die Vorrunde hat gemessen: **`hwsig = 0x0`**, QEMU führt keine Hardware
Signature. Eine Kennung, die auf der Zielmaschine immer 0 ist,
unterscheidet nichts — *jedes* Abbild hätte sie.

Gebraucht wird eine Zahl, die (a) sich zwischen zwei Maschinen
unterscheidet, (b) auf derselben Maschine über einen Neustart **gleich**
bleibt und (c) ohne Dateisystem zu haben ist. Genommen werden fünf Werte,
über `bootmod.crc32` gemischt:

| Größe | warum |
|---|---|
| FACS-`hwsig` | auf Blech ist sie der richtige Weg und soll dort führen |
| Plattengröße in Blöcken | stärkstes frühes Einzelmerkmal; ein Abbild von einer 64-MiB-Platte gehört nicht auf eine mit 2 GiB |
| `cpuid` Blatt 1 EAX | Familie/Modell/Stepping |
| `cpuid` Blatt 1 EDX | die Merkmalsbits — ein Abbild von einer Maschine ohne SSE2 darf nicht auf einer mit laufen, der FPU-Bereich hätte ein anderes Format |
| Rahmenzahl der Bitkarte | ein Abbild mit Rahmen jenseits des vorhandenen Speichers ist nicht einspielbar |

**Was das nicht ist: eine Seriennummer.** Zwei identisch ausgestattete
Maschinen haben dieselbe Kennung. Das ist hinnehmbar — sie unterscheidet
sich in genau den Größen, deren Verschiedenheit das Einspielen
*gefährlich* machen würde. Wer eine echte Seriennummer will, nimmt die
SMBIOS-UUID; die liegt in Runde TRESOR und hängt an Tabellen, die zu
diesem Zeitpunkt noch nicht gelesen sind.

**Gemessen:** `hw=0x38f388a2`, und zwar **in beiden Läufen derselbe Wert**
— die Kennung ist über den Neustart stabil. Das ist eine Zusage der
Abnahme und nicht nur eine Zeile hier.

### Punkt 2 — CPU-Register und `cr3` · **steht, mit einer benannten Grenze**

Gesichert werden `rsp`, `rbp`, `rbx`, `r12`–`r15`, die Rücksprungadresse
(aus `[rbp+8]`), `cr3` und die Flaggen, dazu eine Kennung `REGSBAK!`,
damit ein leerer Satz auffällt.

Der Weg, den die Vorrunde nennt, stimmt: `switch.s` sichert für den
Kontextwechsel jedes Register auf den Stapel. Mit **einem** Unterschied,
der alles ausmacht:

> **Der Stapel überlebt den Schlaf nicht.** `context_switch` darf die
> Register auf dem Stapel lassen, weil der Stapel im Speicher stehen
> bleibt. Ein Ruhezustand verliert den Speicher. Deshalb gehen die
> Register in eine kdata-Seite, die selbst Teil des Abbilds ist.

`r12`–`r15` sind dabei, obwohl der Auftrag sie nicht verlangt: die
AMD64-Aufrufordnung führt sie als erhaltend, und ein Rücksprung ohne sie
käme in eine Funktion zurück, deren Rechnung zur Hälfte fehlt.

**Die Grenze, und sie steht hier und nicht in einer Fußnote:** gesichert,
eingespielt und Wort für Wort verglichen wird der Satz vollständig. Ein
**Sprung hinein** — ein `restore_regs`, das `rsp`/`rip` wirklich setzt und
die Ausführung dort fortsetzt — ist **nicht gebaut**. Er braucht einen
Kernstapel, der an derselben virtuellen Adresse wieder liegt, und das
sichert diese Runde nur für die **Prozesse** zu (Punkt 4), nicht für den
Kernstapel selbst. Was statt eines Sprungs gemessen wird, steht in
Abschnitt 5: ein Prozess rechnet über den Schlaf hinweg weiter, und das
prüft Register und Seitentabellen an der Stelle, an der es zählt.

### Punkt 3 — FPU/XSAVE-Bereich · **steht**

`fpu.area_size` sagt, wie groß er auf dieser Maschine ist — gemessen,
nicht geraten: **512 Oktette**, `mode=1` (FXSAVE), weil `cpuid` Blatt 13
hier nichts Größeres anbietet (`xcr0=0x0`, `need=0`). Er passt damit in
die reservierte Seite; wäre er größer als 4096, sichert diese Runde ihn
**nicht** und sagt das über `SL_FPUWHY` (`FW_BIG`).

Gesichert wird der Bereich der laufenden Aufgabe, **mit `fpu.sync_here`
davor**. Im Bereich einer laufenden Aufgabe steht sonst das, was der
letzte Kontextwechsel dort abgelegt hat — nicht ihr jetziger Zustand.
`fpu.fi` hat genau diesen Fehler einmal gehabt und dafür `sync_here`
gebaut; diese Runde macht ihn nicht noch einmal.

### Punkt 4 — Arbeitsspeicher der Prozesse · **steht — die eigentliche Messgröße**

Die Vorrunde schrieb 63 Blöcke Prüfstandsmuster. Hier gehen **Rahmen** ins
Abbild: **gemessen 18** bei zwei Prozessen.

Neu in `proc.fi`: `frame_count` und `frame_at`. Was sie zählen, ist die
ganze Entscheidung:

* **Gezählt** werden die **Datenseiten** des Benutzers — Programmtext,
  Daten, Stapel. Sie sind der Zustand, der den Schlaf überleben muss.
* **Nicht gezählt** werden die **Seitentabellen** (PML4, PDPT, PD, PT).
  Sie werden beim Wiederanlauf neu aufgebaut, und ein eingespielter alter
  Tabellenrahmen zeigte auf Adressen, die es nicht mehr gibt.
  (`space_pages` zählt sie mit, weil es die Freigabe abbildet — diese
  beiden Funktionen ausdrücklich nicht.)
* **Nicht gezählt** werden **eingeblendete** Rahmen (`PAGE_SHARED`): sie
  gehören dem Adressraum nicht. Ein Ruhezustand, der sie mitschreibt,
  legte fremden Besitz doppelt ab.

Die Reihenfolge ist fest und muss es sein — `frame_count` und `frame_at`
gehen dieselben Tabellen in derselben Richtung ab. Wäre sie es nicht,
legte der Wiederanlauf den Inhalt von Rahmen 7 an die Adresse von Rahmen 9.

Neu in `mem.fi`: **`reserve_frame`** — „nimm *diesen* Rahmen". Ohne ihn
hielte die Bitkarte den eingespielten Rahmen für frei, der nächste
`frame_alloc` gäbe ihn ein zweites Mal aus, und zwei Teile des Kerns
schrieben von da an in dieselbe Seite.

**Der große Puffer liegt nicht in kdata.** Ein Rahmen ist 4096 Oktette,
ein Block 512 — acht Blöcke je Rahmen, durch **den einen** Sektorpuffer
geschoben. Damit braucht diese Runde für beliebig viele Rahmen genau vier
Kilooktette Puffer, so wie der Auftrag es verlangt.

### Punkt 5 — Gerätezustand · **steht**

Abgelegt und wiederhergestellt werden Zeitgeber (`TICKS`), Tastatur
(Lampen über `kbd.locks`/`locks_set`, Belegung) und Grafik (Breite, Höhe,
Schrittweite, ob bereit). `restore_devs` setzt den Zeitgeberstand zurück —
eine Uhr, die nach dem Aufwachen bei null anfängt, ließe jede Zeitrechnung
im Kern rückwärts laufen — und die Lampen mit Schmutzmarke, damit der
nächste Durchlauf sie an die Hardware schickt.

**Der Inhalt des Bildspeichers wird hier nicht gesichert**, und das ist
Absicht: er ist Arbeitsspeicher und geht über Punkt 4 mit. Zwei Stellen
für eine Wahrheit veralten.

### Punkt 6 — S3 · **NICHT gebaut, bewusst**

Der Auftrag sagt: *„Schaffst du S3 nicht, ist das in Ordnung — dann
liefere 1–5 vollständig und schreib S3 als offen hin. Ein halb gebautes S3
ist schlimmer als keins."*

**S3 ist nicht gebaut.** Das ist eine Entscheidung mit Grund und keine
ausgegangene Zeit:

Der Aufwachvektor in die FACS zu schreiben ist **eine Zeile** — und genau
das ist die Falle. Was daran hängt, ist das Trampolin 16 → 32 → 64 Bit an
einer Adresse unter 1 MiB. Die Vorrunde hat das Problem benannt, und die
Prüfung hat es bestätigt: `smp` hat ein Trampolin, aber es startet aus
einem **definierten** Zustand — der Kern hat den Bereich selbst
beschrieben und niemand sonst war dazwischen. Aus S3 kommt die Maschine
aus einem Zustand zurück, in dem SeaBIOS zwischen dem Einschlafen und dem
Einsprung gelaufen ist und den Speicher unter 1 MiB angefasst haben kann.

Ein S3, das den Vektor schreibt und dann in einen überschriebenen
Trampolinbereich springt, hängt die Maschine ohne eine einzige Zeile auf
der seriellen Leitung — ein Fehlerbild, das niemand zuordnen kann.

**Was vorliegt und der nächsten Runde zur Verfügung steht:** `\_S3 =
{1,1}`, `\_S4 = {2,2}`, `PM1a_CNT = 0x604`, FACS bei `0x1ffe0000` mit 64
Oktetten — alles aus der Vorrunde, gegen `iasl -d` gegengeprüft, und diese
Abnahme prüft es weiterhin. `schlaf.s3_befund` druckt den Stand bei jedem
Messlauf:

```
schlaf: s3 gemessen=ja gebaut=nein grund=Trampolin unter 1 MiB fehlt
```

---

## 4. Die Messwerte

Wörtlich von der seriellen Leitung, QEMU 7.2.22 unter KVM, `-m 512`.

### Lauf A — sichern und beenden

```
schlaf: == arm zyklus1
schlaf: frei0=128608
schlaf: prozesse n=2
schlaf: rechnung s=55 schritt=11
schlaf: gesichert rahmen=18 regs=1 fpu=1 fpuwhy=ok fpugroe=512 geraete=1 sum=0xd03e9c33 pids=2
schlaf: nachlese sum=0xd03e9c33 soll=0xd03e9c33
schlaf: abbild steht
schlaf: gast wird beendet
```

### Lauf B — neuer QEMU, dieselbe Platte

```
schlaf: == pruef
schlaf: start - abbild=1 why=ok hw=0x38f388a2 hwimg=0x38f388a2 rahmen=18 zurueck=18
        cnt=2013 pat=0xf3f3 bloecke=131072 basis=129024 sum=0xd03e9c33 soll=0xd03e9c33
schlaf: gleich cnt=2013 pat=0xf3f3 regs=1 fpu=1 geraete=1 rahmen=18
schlaf: rechnung s=55 schritt=11 soll=55
schlaf: weitergerechnet=1
schlaf: rahmen gleich frei=128590
```

| Messgröße | Wert |
|---|---|
| Abbild beim Hochlauf **von selbst** erkannt | **ja** (`abbild=1 why=ok`) |
| Hardware-Kennung jetzt / im Abbild | `0x38f388a2` / `0x38f388a2` — **gleich** |
| Gesicherte Rahmen Arbeitsspeicher | **18** |
| Eingespielte Rahmen | **18** — gleich |
| Registersatz im Abbild / zurück | **ja / ja** |
| FPU-Bereich im Abbild / zurück | **ja / ja**, 512 Oktette |
| Gerätezustand im Abbild / zurück | **ja / ja** |
| Zustand nach dem Hochlauf identisch | **ja** (`cnt`, `pat`, Registersatz, Rahmenzahl) |
| Freie Rahmen: `frei_nachher + eingespielt == frei_vorher` | **128590 + 18 == 128608** |
| Verlorene Rahmen | **0** |
| Prüfsumme Zyklus 1 / Zyklus 2 | `0x5c5b7b48` / `0x50323ec2` — **verschieden** |
| Zustand Zyklus 1 / Zyklus 2 | `cnt=2013` / `cnt=2026` — **verschieden** |
| Rechnung des Prozesses nach dem Schlaf | `summe=55 schritt=11`, Gegenrechnung `soll=55` |

---

## 5. Die Zusage, die Register und Seitentabellen wirklich prüft

Der Auftrag verlangt: *ein Prozess, der vor dem Schlafen läuft, muss
danach **weiterrechnen** und ein richtiges Ergebnis liefern — nicht nur
„existieren".*

Dafür gibt es `P_SCHLAF` (`kernel/uprog.fi`, Programmnummer 64). Er führt
eine laufende Rechnung in seiner privaten Seite:

```
+0   Kennung SCHLAF_TAG ("SCHLAFU!")
+8   summe        summe = summe + schritt
+16  schritt      schritt = schritt + 1
+24  wie oft dieser Prozess gelaufen ist
```

Er beendet sich **nicht** von selbst — der Ruhezustand soll ihn *mitten in
seiner Arbeit* erwischen, nicht nach ihr.

Der Prüfstand sucht diese Seite in den **eingespielten** Rahmen, liest den
Stand und **rechnet unabhängig nach**: `summe` muss `n·(n+1)/2` sein mit
`n = schritt − 1`. Gemessen: `summe=55`, `schritt=11`, `soll=55`. Eine
Zahl, die sich selbst bestätigt, bestätigt nichts — deshalb die
Gegenrechnung.

**Was das zeigt:** der Inhalt eines Benutzerrahmens ist über einen echten
Speicherverlust hinweg byteweise zurückgekommen, und zwar an *die*
Adresse, an der er vorher lag — sonst stünde die Kennung nicht dort.

**Was das nicht zeigt, und es steht hier:** der Prozess wird **nicht**
wieder in die Laufliste gehängt und rechnet nicht weiter *auf dem
Prozessor*. Dafür müsste der Wiederanlauf die Aufgabentafel und die
Kernstapel mitbringen — das ist Punkt 2 in seiner vollen Form, der Sprung
in den gesicherten Zustand. Siehe Abschnitt 8.

---

## 6. Was die Abnahme prüft

`bash tools/suspend/run.sh` — **66 bestanden, 0 gescheitert**.
Die **31 Zusagen der Vorrunde sind unverändert grün**; 35 kamen dazu.

| Abschnitt | Inhalt |
|---|---|
| 1–6 | **unverändert von der Vorrunde** (Speicherkarte, Bau, Vorabmessung, `iasl`-Gegenprobe, zwei Zyklen im selben Lauf, beschädigtes Abbild, check-ui, USB-Abbild) |
| 7 | der zugeteilte Raum: `SCHLAF_OFF` genau `0x121000`, Ende genau `0x126000`, **alle 7 Modusindizes in 1020..1029** |
| 8 | **der echte Zyklus über den Hochlauf** — Gast beendet, Starterkennung, Zustand identisch, Kennung stabil, Punkte 2/3/4/5 einzeln, gesicherte == eingespielte Rahmen, kein verlorener Rahmen |
| 9 | **Weiterrechnen** mit Gegenrechnung und der Prüfung, dass die Rechnung nicht leer ist |
| 10 | **zwei Zyklen**, verschiedene Abbilder *und* verschiedene Zustände |
| 11 | die drei Gegenproben: beschädigt → Prüfsumme · fremde Kennung → Hardware · `noschlaf` → bewusster Kaltstart |

Abschnitt 7 prüft **beide** Nummernräume. Das ist die Lehre aus Welle 1:
dort nahmen `suspend` und `krypto` denselben Modusindex 990/991, weil nur
die *Seiten* vorher vergeben waren.

### Dass die Gegenproben wirklich fallen können

Eine Abnahme, die immer grün ist, misst nichts. Gegengeprüft:

| Fall | Ergebnis |
|---|---|
| leere Platte, kein Abbild | `abbild=0 why=kein Abbild` |
| beschädigte Nutzlast, Kopf steht | `abbild=0 why=Pruefsumme falsch` |
| Kennung im Kopf gekippt | `abbild=0 why=Hardware anders` |
| `noschlaf` bei gültigem Abbild | `abbild=0 why=abgeschaltet` |

---

## 7. Zwei echte Fehler, die die Messung gefunden hat

Beide hätten als „funktioniert eben nicht" durchgehen können. Beide sind
gemessen und nicht geraten.

### 7.1 Der Sektorpuffer, der sich selbst überschrieb

Der Wiederanlauf meldete **`why=Pruefsumme falsch`** bei einem Abbild, das
nachweislich richtig war: die Nachlese im selben Lauf hatte
`sum=0x69af3ae9 soll=0x69af3ae9` gemeldet, und der Kopf auf der Platte trug
dieselbe Zahl.

Die Diagnosezeile zeigte `sum=0x69af3ae9 soll=0x78bfbfd`. Die berechnete
Summe war also **richtig** — die *gespeicherte* war Unsinn. Und
`0x78bfbfd` war keine zufällige Zahl: es ist **`cpuid` Blatt 1 EDX**,
dieselbe Zahl, die der Startlauf als `fpu: f1d=0x78bfbfd` druckt.

Die Ursache: `hwsig_now` mischte seine fünf Wörter in **`buf`** — denselben
Sektorpuffer, in dem `boot_check` gerade den **Kopf des Abbilds** liegen
hatte. Der Aufruf mitten in der Kopfprüfung überschrieb ihn, und jedes
Feld, das danach gelesen wurde, kam aus fremden Oktetten.

Die Berichtigung ist zweiteilig, weil eine Hälfte allein nur diesen einen
Fall geheilt hätte:

1. `hwsig_now` bekommt ein **eigenes Feld** (fünf Wörter auf dem Stapel).
2. `boot_check` holt den **ganzen Kopf in eigene Werte**, bevor irgendetwas
   anderes den Puffer anfassen darf.

Bemerkenswert daran: die *Gegenprobe* (beschädigtes Abbild) wäre grün
geblieben — sie erwartet ja eine falsche Prüfsumme. Nur der echte Zyklus
war rot. Eine Runde, die nur ihre Gegenproben misst, hätte das gemeldet
als „die Prüfsumme arbeitet".

### 7.2 Die Platte, die niemand gemessen hatte

Der erste Wiederanlauf meldete `why=keine Platte` — auf derselben
Maschine, die wenige Zeilen vorher `ata0 sectors=131072` gedruckt hatte.
Das ist **derselbe Fehler, den die Vorrunde schon einmal hatte**, in neuer
Gestalt: sie hatte `blkdev.fi` statt `blk.fi` gefragt, diese Runde hat
`susp.diskok` gefragt, ohne dass jemand gemessen hatte.

`susp.late` misst die Platte nämlich **nur in seinen eigenen
Betriebsarten** (`suspend`/`suspmess`). Ein normaler Start — und genau das
ist ein Wiederanlauf aus dem Ruhezustand — läuft daran vorbei.

Berichtigung: `susp.ensure_disk` (neu), das nur misst, wenn noch nichts
gemessen ist, und in `boot_check` gerufen wird. Die Starterkennung darf
sich nicht darauf verlassen, dass jemand anderes vorher gemessen hat.

---

## 8. Die roten Punkte dieser Runde, einzeln benannt

Die Vorrunde hat vorbildlich hingeschrieben, was sie nicht kann. Das wird
hier durchgehalten.

1. **Kein Sprung in den gesicherten Registersatz.** Der Satz wird
   gesichert, eingespielt und Wort für Wort verglichen — aber `rsp`/`rip`
   werden nicht gesetzt und die Ausführung nicht dort fortgesetzt. Dafür
   müsste der **Kernstapel** an derselben virtuellen Adresse wieder
   liegen; diese Runde sichert nur die Rahmen der **Prozesse**.
2. **Die Prozesse laufen nach dem Wiederanlauf nicht weiter.** Ihr
   Speicher kommt byteweise zurück und wird nachgerechnet (Abschnitt 5),
   aber die Aufgabentafel, die Kernstapel und die Seitentabellen werden
   **nicht** wiederhergestellt — der Prozess wird nicht in die Laufliste
   gehängt. Was gemessen ist, ist der *Inhalt* seines Speichers, nicht
   seine Fortsetzung auf dem Prozessor.
3. **S3 ist weiterhin nur gemessen.** Aufwachvektor und Trampolin
   16 → 32 → 64 Bit fehlen. Begründung in Abschnitt 3, Punkt 6.
4. **Die Maschine nimmt keinen Strom weg.** Es wird kein
   `SLP_TYP|SLP_EN` nach PM1a_CNT geschrieben. Der Gast wird über
   `isa-debug-exit` beendet — das ist ein echter Verlust des
   Arbeitsspeichers und genau das, was die Messung braucht, aber es ist
   kein ACPI-Ruhezustand.
5. **Nur auf QEMU gemessen.** Auf Blech ist diese Runde nicht gelaufen.
   Auf Blech wäre `hwsig` aus der FACS nicht 0 und würde in der Kennung
   mitführen; der zweite Weg bliebe trotzdem richtig.
6. **Die Rahmentafel des Prüfstands fasst 448 Einträge.** Mehr
   eingespielte Rahmen werden nicht vermerkt — das *Einspielen* ist davon
   unberührt, nur die Nachrechnung in Abschnitt 5 sähe sie nicht. Bei 18
   gemessenen Rahmen ist das weit weg, aber es ist eine Grenze und keine
   Zusage.
7. **Nur Prozesse mit eigenem Adressraum gehen ins Abbild.** Aufgaben, die
   auf dem Kern-PML4 laufen, haben keine Benutzerdatenseiten und werden
   nicht gesichert.

---

## 9. Was diese Runde am Baum geändert hat

| Datei | Änderung |
|---|---|
| `kernel/schlaf.fi` | **neu** — die ganze Runde |
| `kernel/kstate.fi` | `SCHLAF_OFF`/`SCHLAF_MAX`, sieben Modusnamen, `MODE_WORDS` 16 → 17 |
| `kernel/kmain.fi` | `schlaf.boot_check` hinter `susp.late`, die zwei Phasen hinter `osum`, sieben Kommandozeilenwörter |
| `kernel/proc.fi` | `frame_count`, `frame_at` (+ `pt_data_count`, `pt_data_nth`) |
| `kernel/mem.fi` | `reserve_frame` |
| `kernel/susp.fi` | `hwsig`, `blocks`, `disk`, `diskok`, `ensure_disk` — lesende Auskünfte, damit nichts zweimal gemessen wird |
| `kernel/uprog.fi` | `P_SCHLAF` (Nr. 64), der Prozess, der weiterrechnet |
| `tools/kernel/memmap.py` | der Bereich `SCHLAF` eingetragen |
| `tools/suspend/run.sh` | Abschnitte 7–11 |

### `MODE_WORDS` von 16 auf 17

Das ist **keine selbst genommene Zuteilung**, sondern die Folge einer
gemessenen Enge. Der Runde sind die Modusindizes 1020..1029 zugeteilt; der
Vektor endete bei 16 · 64 = 1024, also lagen 1024..1029 **hinter seinem
Ende**. `tools/kernel/memmap.py` hat genau das gemeldet:

```
M_SCHLAFKAPUTT: Modusindex 1024 liegt hinter dem Vektor (MODE_WORDS * 64 = 1024)
```

Der Kartenprüfer hat die Enge gefunden, nicht ein Gefühl. Das Wachstum
kostet **keine neue Seite**: `MODE_OFF` ist mit `MODE_MAX` `0x1000` eine
ganze Seite, und die Tafel in `kstate.fi` sagt seit Runde K17 wörtlich
*„wird auch das knapp, wächst MODE_WORDS; die Seite fasst 512 Wörter"*.
17 Wörter sind 136 Oktette in einer Seite zu 4096. Der zugeteilte
Indexraum bleibt unangetastet — belegt sind 1020..1026.

---

## 10. Der nächste Schritt

In dieser Reihenfolge, weil jeder Schritt auf dem vorigen steht:

1. **Die Aufgabentafel und die Kernstapel ins Abbild.** Erst damit lässt
   sich ein Prozess nach dem Wiederanlauf wirklich wieder in die
   Laufliste hängen — und erst dann ist der Sprung in den gesicherten
   Registersatz sinnvoll, weil es einen Stapel gibt, auf dem er landen
   kann. Das ist die Grenze aus Abschnitt 8, Punkt 1 und 2.
2. **Die Seitentabellen der Prozesse mitsichern** (oder aus der
   Rahmentafel neu aufbauen). Heute kommen die Rahmen zurück, die
   Tabellen darüber nicht.
3. **S3**, mit dem Aufwachvektor in der FACS und dem Trampolin. Die
   Messwerte liegen seit der Vorrunde vor; was fehlt, ist ein
   Trampolinbereich, dessen Inhalt die Firmware nachweislich nicht
   angefasst hat — also einer, den der Kern nach dem Aufwachen zuerst
   neu schreibt und erst dann anspringt.
4. **Auf Blech messen.** Dort ist `hwsig` aus der FACS nicht 0, und die
   Hardware-Kennung bekommt ihren eigentlichen Träger.
