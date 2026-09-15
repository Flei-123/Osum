# Runde WACH (K-018, Abschluss) — der Wiederanlauf: die Prozesse laufen weiter

**Stand:** 15.09.2026 · Zweig `wach`, abgezweigt von `main` (`d5583ee`) ·
Abnahme: `bash tools/suspend/run.sh` → **94 bestanden, 0 gescheitert**
(die **66 Zusagen der Vorrunde unverändert grün**, 28 kamen dazu) ·
Nummernvorrat: kdata `0x127000..0x12C000` (**vorher zugeteilt**),
Modusindizes **1050..1059** (belegt 1050..1054), Kommandozeilenwörter
`wacharm`, `wachpruef`, `nowach`, `wachmess`, `wach`.

---

## 1. Der Satz, um den es geht

**Ein Prozess rechnet. Das System geht auf die Platte, QEMU wird
beendet, ein neuer Kern startet — und derselbe Prozess rechnet auf dem
Prozessor weiter.** Sein Zähler steigt danach, und das Ergebnis stimmt
gegen eine unabhängige Gegenrechnung.

Das ist etwas anderes als das, was die Vorrunde gemessen hat, und der
Unterschied ist die ganze Runde. Die Vorrunde holt den **Inhalt** der
Benutzerrahmen byteweise zurück und rechnet ihn nach — vorbildlich
gemessen. Aber die Zahlen in einem Rahmen stehen dort auch dann, wenn nie
wieder eine Anweisung dieses Prozesses ausgeführt wurde. Sie sind ja von
**vor** dem Schlafen. Ihr eigener Bericht sagt das in Abschnitt 8
wörtlich, und diese Runde baut genau diese zwei Punkte:

1. *„Kein Sprung in den gesicherten Registersatz."*
2. *„Die Prozesse laufen nach dem Wiederanlauf nicht weiter.
   Aufgabentafel, Kernstapel und Seitentabellen werden nicht
   wiederhergestellt — der Prozess wird nicht in die Laufliste
   gehängt."*

---

## 2. Die Hürde der Vorrunde, und warum sie fällt

Die Vorrunde nennt die Bedingung präzise: für einen Sprung in den
gesicherten Zustand *„müsste der **Kernstapel an derselben virtuellen
Adresse** wieder liegen"*. Sie hat es dabei belassen — richtig so, eine
Zusage ohne Messung wäre schlimmer gewesen.

**Nachgesehen, und hier ist die Antwort.** Sie steht in `mem.fi` (Zeile
52) und in `kernel/arch/x86_64/boot.s`:

> **Der Kern bildet den physischen Speicher identisch ab.** `boot.s` baut
> ein Seitenverzeichnis mit 512 Einträgen zu 2 MiB — ein Gibioctet 1:1 —
> und `mem.scan` setzt das für jedes weitere Gibioctet fort. Im
> Kernbereich gilt: **virtuell == physisch**.

Daraus folgt der ganze Weg, und er braucht keine neue Zusicherung,
sondern nur eine, die schon da ist:

* Ein Kernstapel liegt bei `T_KSTACK`, und das ist eine **physische**
  Adresse aus `mem.frame_run` — die wegen der Identitätsabbildung
  zugleich seine virtuelle ist.
* Wer die Rahmen des Kernstapels an **genau dieselben physischen
  Adressen** zurückholt, bekommt ihn damit automatisch an **derselben
  virtuellen Adresse** zurück.
* Das Werkzeug dafür liegt seit der Vorrunde im Baum:
  **`mem.reserve_frame`** — „nimm *diesen* Rahmen". Die Vorrunde hat es
  für die Datenseiten gebaut; es trägt die Kernstapel mit.

### Warum es kein `restore_regs` gibt, das `rsp`/`rip` setzt

Der Auftrag lässt beides zu. Diese Runde baut den Sprung — aber **nicht**
als Gewaltakt, der `rsp` und `rip` mit Assembler überschreibt, sondern
über den Weg, den der Kern für genau diesen Zweck schon hat.

`kernel/arch/x86_64/switch.s` sagt, wie ein Stapel aussieht, von dem aus
eine Aufgabe fortgesetzt wird (ab `rsp` aufwärts): `+0` rflags, `+8`…`+120`
die fünfzehn Register, `+128` die Rücksprungadresse. `context_switch`
poppt genau das und macht `ret`. Und `T_RSP` ist das Feld, in dem steht,
wo dieser Rahmen liegt.

**Der Sprung ist also schon gebaut — er heißt `context_switch`.** Was der
Wiederanlauf liefern muss, ist nur: der Kernstapel mit seinem alten
Inhalt an seiner alten Adresse, `T_RSP` unverändert aus dem Abbild, und
ein Aufgabensatz samt Adressraum, damit der Planer die Aufgabe wählen
*darf*. Dann lädt `switch_to` das `cr3`, `context_switch` poppt die
Register vom wiederhergestellten Stapel, und `ret` springt dorthin zurück,
wo der Prozess eingeschlafen ist — mitten in `sched.sleep_ticks`.

Ein eigenes `restore_regs` wäre der **schlechtere** Weg, und das ist keine
Geschmacksfrage: es müsste dieselbe Registerordnung ein zweites Mal
aufschreiben. Zwei Stellen für eine Wahrheit veralten — denselben Satz
sagt die Vorrunde über den Bildspeicher. Der gesicherte Registersatz aus
`schlaf.fi` bleibt deshalb, was er ist: eine **Prüfgröße**, die Wort für
Wort verglichen wird, nicht der Weg zurück.

---

## 3. Die drei Punkte, einzeln

### Punkt 1 — Aufgabentafel, Kernstapel, Seitentabellen · **steht**

Ins Abbild geht je Prozess ein Auszug des Aufgabensatzes (`TS_*` in
`kernel/wach.fi`): pid, Zustand, Priorität, `T_RSP`, `T_KSTACK`/`T_KTOP`,
Einsprung, Benutzerstapel, Art, Programm, die Kennungen — und **die
Kernstapel selbst**, je Aufgabe 17 Rahmen (`KSTACK_FRAMES + 1`; der
unterste ist die Wache und gehört dazu, weil `free_stack` beide
zusammen zurückgibt).

**Neu gegenüber der Vorrunde: die virtuelle Adresse.** `frame_at` gibt die
*physische* Adresse eines Datenrahmens — zum Sichern reicht das. Zum
Wiederanlaufen nicht: eine Seitentabelle bildet *virtuell auf physisch*
ab, und ein Rahmen, der an der falschen virtuellen Adresse wieder
eingehängt wird, ist derselbe Speicher an der falschen Stelle — der
Prozess läse seinen Stapel, wo seine Daten stehen sollten. Deshalb
`proc.frame_virt_at`, das **dieselben Tabellen in derselben Reihenfolge**
abgeht wie `frame_count`/`frame_at`; nur so meint Eintrag *n* hier und
Eintrag *n* dort denselben Rahmen.

Beim Wiederanlauf, in dieser Reihenfolge und sie ist zwingend:

1. Die Kernstapelrahmen per `mem.reserve_frame` an ihre **alten
   physischen** Adressen. Ist einer davon nicht frei, wird **abgebrochen**
   und nicht überschrieben — ein Kernstapel über fremdem Besitz ist der
   Fehler, den niemand mehr zuordnen kann.
2. Ein Aufgabenplatz von Hand (nicht `sched.create` — das legte einen
   *neuen* Stapel an), Satz genullt, Felder aus dem Abbild, **`T_RSP`
   unverändert**.
3. Ein Adressraum: Tabellen **neu** (`proc.space_build_empty`), Blätter
   aus dem Abbild (`proc.map_restored`).
4. `T_STATE` auf `S_READY` — ab hier darf der Planer wählen.

Zwei Entscheidungen, die benannt gehören:

* **`proc.map_restored` statt `map_frame`.** Der Unterschied ist *ein Bit*
  und er ist die halbe Zusage: `map_frame` setzt `PAGE_SHARED`
  („eingeblendet, gehört dem Adressraum nicht"). Für eine Fensterfläche
  richtig, für die private Seite eines wiederangelaufenen Prozesses
  **falsch, und zwar doppelt** — der Rahmen würde beim Ende des Prozesses
  nicht freigegeben (Leck), und `frame_count` zählte ihn beim *nächsten*
  Schlafen nicht mit: der zweite Ruhezustand verlöre genau den Speicher,
  den der erste gerettet hat.
* **`S_READY` statt des gesicherten Zustands.** Wer `S_SLEEP` war, hatte
  eine Frist in `T_WAKE`, gerechnet gegen den *damaligen* Zeitgeberstand.
  Der neue Kern fängt anders an; eine alte Frist wäre entweder sofort
  fällig oder nie — beides falsch geraten. Wer schlief, wird weckbereit;
  sein Schlaf ist mit dem des ganzen Systems zusammengefallen. Alles
  andere (Warten auf ein Kind, `poll`, angehalten) wird **nicht geraten**,
  sondern kommt als `S_STOP` zurück. Das steht in Abschnitt 6.

### Punkt 2 — der Sprung in den gesicherten Zustand · **steht**

Gemessen an drei Stufen, von denen **keine allein genügt**:

| Stufe | was sie zeigt | gemessen |
|---|---|---|
| zurückgeholt | die Aufgabe steht wieder in der Tafel | `aufgaben=5` |
| auf dem Prozessor | `T_RUNS > 0` — `switch_to` hat sie gewählt | `gelaufen=3` |
| **weitergerechnet** | der Zähler steht **höher** als im Abbild, **und** die Summe passt zu ihrem Schritt | `28 → 106`, `summe=5671 == 5671` |

Stufe 3 ist der Beweis. Stufe 1 allein wäre „existiert", Stufe 2 allein
könnte ein einziger Zug sein, der sofort in einen Fehler läuft.

**Die Vergleichszahl kommt aus dem Abbild.** Das ist keine Feinheit,
sondern eine Berichtigung: in der ersten Fassung stand sie in kdata, und
kdata ist beim nächsten Hochlauf leer — der Prüfer verglich gegen **Null**
und hätte jeden Wert als „gestiegen" durchgehen lassen. Die Abnahme prüft
seitdem ausdrücklich `vorher > 0`.

### Punkt 3 — S3 · **NICHT gebaut, bewusst**

Der Auftrag sagt: *„Schaffst du S3 nicht, ist das in Ordnung — dann
schreib es als offen hin. Ein halb gebautes S3 hängt die Maschine ohne
eine Zeile auf der seriellen Leitung."*

**S3 ist nicht gebaut.** Die Begründung der Vorrunde wurde nicht
übernommen, sondern **nachgeprüft** — und sie trägt. Nachgesehen wurde
das, was die Vorrunde als Hürde nennt, nämlich das Trampolin:

* Das SMP-Trampolin liegt bei `AP_BASE = 0x8000`
  (`kernel/arch/x86_64/smp.s:43`), also unter 1 MiB und auf einer
  Seitengrenze — die `SIPI` trägt nur ein Oktett Adresse.
* `smp.fi` **kopiert es vor jedem Kernstart frisch** aus dem Kernabbild
  dorthin (die Schleife `while blob + i < blob_end`).

Und **genau diese Eigenschaft** ist das, was ein S3-Rückweg braucht: ein
Trampolinbereich, dessen Inhalt der Kern nach dem Aufwachen zuerst neu
schreibt und erst dann anspringt — weil die Firmware zwischen Einschlafen
und Einsprung den Speicher unter 1 MiB angefasst haben kann. Der Weg ist
damit **gangbar und beschrieben**, aber er ist **nicht gebaut und nicht
gemessen**, und eine Wegbeschreibung ist keine Zusage. Was vorliegt,
bleibt wie gehabt: `\_S3 = {1,1}`, FACS `0x1ffe0000`, `PM1a_CNT = 0x604`,
gegen `iasl -d` gegengeprüft; `schlaf.s3_befund` druckt den Stand weiter
bei jedem Messlauf.

---

## 4. Die Messwerte

Wörtlich von der seriellen Leitung, QEMU unter KVM, `-m 512`.
Zwei QEMU-Läufe mit **derselben Plattendatei**, dazwischen wird der Gast
**beendet**.

### Lauf A — anlegen, rechnen, sichern, beenden

```
wach: == arm zyklus 1
wach: prozesse n=3 pids=17,18,19
wach: vorher  runden=31 summe=496
wach: sich.  pid=17 st=3 prog=65 seiten=9
wach: sich.  pid=18 st=1 prog=65 seiten=9
wach: sich.  pid=19 st=1 prog=65 seiten=9
wach: sich.  pid=20 st=1 prog=64 seiten=9
wach: sich.  pid=21 st=1 prog=64 seiten=9
schlaf: gesichert rahmen=45 regs=1 fpu=1 fpuwhy=ok fpugroe=512 geraete=1 pids=2
schlaf: abbild steht
schlaf: gast wird beendet
```

### Lauf B — neuer QEMU, dieselbe Platte

```
schlaf: start - abbild=1 why=ok hw=0x38f388a2 hwimg=0x38f388a2 rahmen=45 zurueck=45
schlaf: gleich cnt=2013 pat=0xf3f3 regs=1 fpu=1 geraete=1 rahmen=45
schlaf: rechnung s=55 schritt=11 soll=55
schlaf: weitergerechnet=1
schlaf: rahmen gleich frei=127934 wach=110 frei1=127934 soll=128089
wach: == pruef
wach: zurueck aufgaben=5 kstapel=85 seiten=45 tafeln=25 why=ok
wach: weiter  vorher=31 nachher=109 summe=5995 soll=5995
wach: weiterlauf=3 gelaufen=3 prozesse=3 alle=1
```

| Messgröße | Wert |
|---|---|
| Aufgabeneinträge zurück in der Tafel | **5** |
| Kernstapelrahmen zurück | **85** = 5 × 17 |
| Datenseiten wieder eingehängt | **45** |
| Seitentabellen + Vektorbereiche neu | **25** |
| Prozesse auf dem Prozessor (`T_RUNS > 0`) | **3** |
| **Zähler über den Ruhezustand** | **31 → 109** (Abnahmelauf: 28 → 106) |
| **Gegenrechnung** `summe == n·(n+1)/2` | **5995 == 5995** (Abnahmelauf: 5671 == 5671) |
| Prozesse, die weiterrechnen / alle davon | **3 / ja** (`alle=1`) |
| Freie Rahmen: `frei1 + eingespielt + wach == frei_vorher` | **127934 + 45 + 110 == 128089** |
| Verlorene Rahmen | **0** |
| Zweiter Zyklus, Zähler | **31 → 109**, Summe `5995` |
| Prüfsumme Zyklus 1 / Zyklus 2 | `0xdaf46834` / `0xbc3218ce` — **verschieden** |

---

## 5. Was die Abnahme prüft

`bash tools/suspend/run.sh` — **94 bestanden, 0 gescheitert**.
Die **66 Zusagen der Vorrunde sind unverändert grün**; 28 kamen dazu.

| Abschnitt | Inhalt |
|---|---|
| 1–11 | **unverändert von den Vorrunden** (Speicherkarte, Bau, `iasl`-Gegenprobe, der Zyklus über den Hochlauf, Weiterrechnen, zwei Zyklen, die drei Gegenproben) |
| **12** | **der Wach-Zyklus**: mehrere Prozesse mit verschiedenen pids, Aufgabentafel zurück, `kstapel == aufgaben × 17`, auf dem Prozessor gewesen, **Zähler steigt**, Gegenrechnung, *alle* laufen weiter, kein verlorener Rahmen |
| **13** | **zwei Wach-Zyklen** mit verschiedenen Abbildern *und* verschiedenen Zuständen |
| **14** | **die Gegenprobe `nowach`**: der Wiederanlauf der Aufgaben ist ab, **der Speicher kommt trotzdem zurück** |
| **15** | der zugeteilte Raum: `WACH_OFF` genau `0x127000`, Ende genau `0x12C000`, alle Modusindizes in 1050..1059 |

### Dass die Gegenproben wirklich fallen können

`nowach` ist bewusst so gebaut, dass es **die beiden Zusagen trennt**: das
Abbild wird weiterhin eingespielt (`abbild=1` — der Speicher kommt
zurück, das ist der Stand der Vorrunde), aber **keine** Aufgabe kommt in
die Laufliste (`aufgaben=0 why=abgeschaltet`). Wäre die neue Zusage nur
ein Nebeneffekt der alten, müsste das auffallen.

---

## 6. Drei echte Fehler, die die Messung gefunden hat

Alle drei hätten als „funktioniert eben" durchgehen können. Alle drei sind
gemessen und nicht geraten.

### 6.1 Die Vergleichszahl, die gegen Null verglich

Der Prüfer meldete `weiter vorher=0 nachher=109` — und die Zusage sah grün
aus. Sie war es nicht: `W_STEP0` steht in **kdata**, und kdata ist beim
nächsten Hochlauf leer. Der Prüfer verglich den Zähler also gegen **Null**
und hätte *jeden* Wert als „gestiegen" durchgehen lassen — auch einen
Prozess, der nie wieder gelaufen wäre.

Berichtigung: der Stand vor dem Schlafen geht **ins Abbild** (zwei Wörter
im Kopf des Aufgabenteils) und wird von dort gelesen. Die Abnahme prüft
seitdem ausdrücklich, dass `vorher > 0` ist — eine Zusage, die gegen nichts
vergleicht, misst nichts.

### 6.2 Die fünf Rahmen, die niemand zählte

Der Wiederanlauf meldete `RAHMEN VERLOREN`, und die Rechnung ging um genau
**fünf** Rahmen bei **fünf** Aufgaben nicht auf — ein Rahmen je Aufgabe.

Die Ursache war nicht ein Leck, sondern eine **unvollständige Zählung**:
der Zähler las die freien Rahmen *vor* `fpu.area_new`, und der
Vektorbereich jeder Aufgabe ist ein Rahmen. Die Zusage war richtig, die
Messung war es nicht. Messpunkt hinter `area_new` gelegt — und das ist
genau der Unterschied, den eine Abnahme finden soll.

### 6.3 Die Rahmenzusage, die zu eng geworden war

Die Vorrunde sagt `frei + eingespielt == frei_vorher`. Das war richtig,
solange der Wiederanlauf nur Datenseiten zurückholte. Diese Runde belegt
zusätzlich Kernstapel und Seitentabellen — die Zusage fiel.

**Sie wurde nicht gelockert, sondern genauer.** Statt „eingespielt" steht
jetzt „eingespielt **+ was der Wiederanlauf selbst genommen hat**", und
die zweite Zahl wird in `wach.fi` als **Differenz der freien Rahmen
gezählt**, nicht geschätzt. Dazu kam ein zweiter Messpunkt: `SL_FREI1`,
die freien Rahmen **unmittelbar nach** dem Wiederanlauf. Gegen den Stand
*danach* zu prüfen wäre falsch — ab dann laufen die wiederangelaufenen
Prozesse, und ein Prozess, der läuft, fordert Speicher an (sein Stapel
wächst über Seitenfehler). Genau das ist ja der Beweis, dass er läuft.

Wer eine Zusage aufweicht, bis sie passt, misst nichts mehr; wer den
fehlenden Posten benennt und mitzählt, misst mehr als vorher.

---

## 7. Die roten Punkte dieser Runde, einzeln benannt

Beide Vorrunden haben vorbildlich hingeschrieben, was sie nicht können.
Das wird hier durchgehalten.

1. **S3 ist weiterhin nur gemessen, nicht gebaut.** Aufwachvektor und
   Trampolin fehlen. Der *Weg* ist in Abschnitt 3 beschrieben und
   nachgeprüft (`AP_BASE = 0x8000`, vor jedem Start neu kopiert) — aber
   eine Wegbeschreibung ist keine Zusage.
2. **Die Maschine nimmt keinen Strom weg.** Es wird kein
   `SLP_TYP|SLP_EN` nach PM1a_CNT geschrieben; der Gast wird über
   `isa-debug-exit` beendet. Das ist ein echter Verlust des
   Arbeitsspeichers und genau das, was die Messung braucht — aber es ist
   kein ACPI-Ruhezustand.
3. **Nur Prozesse mit eigenem Adressraum.** Fäden (`T_SHARED`) gehen
   **nicht** mit: sie teilen den Adressraum eines anderen, und ihn
   getrennt wiederherzustellen hieße, denselben Adressraum zweimal
   aufzubauen. Aufgaben auf dem Kern-PML4 ebenfalls nicht — der neue Kern
   legt seine eigenen an.
4. **Deskriptoren, Signale, Handles und das Arbeitsverzeichnis kommen
   nicht zurück.** Ins Abbild gehen die Felder, die der **Planer**
   braucht, plus die Kennungen. Ein wiederangelaufener Prozess, der eine
   Datei offen hatte, findet sie **nicht** wieder. Für den gemessenen
   Prozess (eine rechnende Schleife) ist das folgenlos; für eine Shell
   wäre es das nicht.
5. **Der FPU-Zustand je Prozess kommt nicht zurück.** `schlaf.fi` sichert
   den Bereich der **laufenden** Aufgabe, nicht den jedes Prozesses. Jeder
   wiederangelaufene Prozess bekommt einen frischen, sauber gesetzten
   Vektorbereich. Ein Prozess mitten in einer Gleitkommarechnung verlöre
   dort seine Zwischenwerte.
6. **Wartende Zustände werden nicht geraten.** Wer `S_SLEEP`/`S_READY`/
   `S_RUN` war, wird weckbereit. Wer auf ein Kind wartete, in `poll` stand
   oder angehalten war, kommt als `S_STOP` zurück — **angehalten und
   nicht falsch fortgesetzt**. Das ist bewusst die vorsichtige Antwort.
7. **Höchstens acht Aufgaben und 448 Datenseiten.** `MAX_SAVE = 8`,
   `MAX_PAGES = 448`. Mehr wird **nicht halb gesichert**, sondern gar
   nicht — eine Aufgabe, deren Seiten nicht mehr in die Tafel passen,
   bleibt ganz draußen. Es ist eine Grenze und keine Zusage.
8. **Nur auf QEMU gemessen.** Auf Blech ist diese Runde nicht gelaufen.
9. **Ein Kern.** Der Wiederanlauf hängt die Aufgaben in die Tafel, ohne
   sich um Kernbindung (`TC_CPU`/Affinität) zu kümmern. Auf einer
   Maschine mit mehreren gestarteten Kernen ist das nicht gemessen.

---

## 8. Was diese Runde am Baum geändert hat

| Datei | Änderung |
|---|---|
| `kernel/wach.fi` | **neu** — die ganze Runde: Aufgabensätze, Kernstapel, Seitentafel, Wiederanlauf, Messung |
| `kernel/kstate.fi` | `WACH_OFF`/`WACH_MAX`, fünf Modusnamen (1050..1054) |
| `kernel/kmain.fi` | `import wach`, die zwei Phasen hinter `osum`, fünf Kommandozeilenwörter |
| `kernel/schlaf.fi` | `buf_addr`, `wach_base`, `wach_reserve`, `SL_FREI1`; `wach.save_tasks` am Ende von `save_image`, `wach.restore_tasks` am Ende von `boot_check`; die Rahmenzusage um den neuen Posten erweitert |
| `kernel/proc.fi` | `frame_virt_at` (+ `pt_data_virt_nth`), `space_build_empty`, `map_restored` |
| `kernel/uprog.fi` | `P_WACH` (Nr. 65), die Schleife, an der das Weiterlaufen gemessen wird |
| `tools/kernel/memmap.py` | der Bereich `WACH` eingetragen |
| `tools/suspend/run.sh` | Abschnitte 12–15 |

### Warum der Sektorpuffer übergeben und nicht geholt wird

`schlaf.fi` ruft `wach.fi`, also darf `wach.fi` **nicht** `schlaf.fi`
rufen — `proc.fi` sagt den Satz wörtlich: *„der Modulgraph muss ein Baum
bleiben"*. Ein `import schlaf` wäre ein Ring gewesen. Also bekommen
`save_tasks`/`restore_tasks` die Adresse des Sektorpuffers als
**Argument**. Das ist nicht nur die Umgehung eines Übersetzerfehlers, es
ist die ehrlichere Schnittstelle: es steht in der Signatur, dass diese
Datei einen *fremden* Puffer benutzt, statt sich still einen zu greifen.

Damit bleibt es bei **einem** Sektorpuffer für den ganzen Ruhezustand —
vier Kilooktette, wie der Auftrag es verlangt. Die Bedingung dafür ist
eine Reihenfolge, und sie wird eingehalten: `save_tasks` läuft **nach**
allem, was `save_image` durch den Puffer schiebt, `restore_tasks`
**nach** dem letzten Lesezugriff von `boot_check`.

---

## 9. Der nächste Schritt

In dieser Reihenfolge, weil jeder auf dem vorigen steht:

1. **Deskriptoren, Signale und das Arbeitsverzeichnis mitsichern.** Erst
   damit überlebt eine *Shell* den Ruhezustand und nicht nur eine
   rechnende Schleife. Das ist Punkt 4 aus Abschnitt 7 und der größte
   Einzelposten.
2. **Den FPU-Bereich je Prozess statt nur den der laufenden Aufgabe.**
   Punkt 5.
3. **S3**, mit dem Aufwachvektor in der FACS und dem Trampolin. Der Weg
   steht in Abschnitt 3: `AP_BASE = 0x8000` wird vor jedem Kernstart neu
   beschrieben, und genau das ist die Eigenschaft, die der Rückweg
   braucht.
4. **Auf Blech messen.** Dort ist `hwsig` aus der FACS nicht 0, und die
   Hardware-Kennung bekommt ihren eigentlichen Träger.
5. **Mit mehreren Kernen messen.** Punkt 9.
