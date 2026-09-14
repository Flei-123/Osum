# Runde ENERGIE — Ausschalten, Neustart und Abmelden aus der Oberfläche

**Zweig:** `energie` · **Grundlage:** `main` = `ae381a3` · **Datum:** 13.09.2026
**Punkt der Offenliste:** `P-003` (Priorität 1)

---

## 1. Worum es ging

Bis zu dieser Runde ließ sich dieses System **nur über die Befehlszeile**
ausschalten — `/bin/shutdown`, getippt in ein Terminalfenster. Ein Rechner,
den man nur mit einem getippten Befehl ausmachen kann, ist kein
Alltagssystem.

Gebaut wurde deshalb **ausschließlich Oberfläche**. Das saubere
Herunterfahren gab es schon vollständig, und es wurde **nicht nachgebaut** —
eine zweite Abschaltroutine neben `init.shutdown` wäre genau die zweite
Wahrheit, gegen die der Kopf von `tools/check-ui.sh` argumentiert.

---

## 2. Bestandsaufnahme zuerst — was schon da war

Die Offenliste ist vom 12.09. Nachgemessen am Baum ergab sich, dass der
**Kern seinen Teil längst kann**:

| Stück | Wo | Zustand |
|---|---|---|
| ACPI S5 (Abschaltung) | `kernel/power.fi::acpi_off` | fertig: FADT holen, DSDT nach `_S5_` absuchen, `PM1a_CNT`/`PM1b_CNT` schreiben |
| Neustart | `kernel/power.fi::acpi_reset` | fertig: FADT-`RESET_REG` → Anschluss `0xCF9` → 8042, in dieser Reihenfolge |
| Sauberes Herunterfahren | `kernel/user/init.fi::shutdown` | fertig: SIGTERM an jeden Dienst → 2 s Frist → SIGKILL → `sync` → `umount_all` → ACPI |
| Der Weg dorthin | `/run/svc.cmd` | fertig: `/bin/shutdown` schreibt eine Zeile, Prozess 1 liest sie |
| Syscall 169 | `kernel/sys.fi::do_reboot` | fertig, nur für `root` (`perm.is_root`) |

Der Zweig `k18-power` ist gegenüber `main` **leer** (`git log main..k18-power`
= 0 Commits) — die Kernarbeit ist längst gemergt.

**Die Lücke war also nicht der Kern, sondern zweierlei:** kein Knopf, und —
das war die Überraschung — **ein Auslieferungsabbild ohne `init`**.

---

## 3. Was gebaut wurde

### 3.1 Der Energieknopf im Startmenü (`kernel/user/launcher.fi`)

Unten links, gegenüber von „Ausführen". Er **misst sich selbst** aus Text
plus Polsterung — dieselbe Rechnung wie der Knopf rechts und aus demselben
Grund (Runde ECHTHARDWARE-1: eine feste Breite ist in der nächsten Sprache
abgeschnitten).

Alle Bedienelemente kommen aus `wlib`; `tools/check-ui.sh` bleibt grün.

### 3.2 Das Klappmenü

Drei Punkte über `wlib.menu_open`: **Ausschalten · Neustart · Abmelden**.
Es klappt nach oben auf — unter dem Knopf ist die Leiste, und dort ist nie
Platz. Der Menütext steht als **eine Zeile je Eintrag** im Katalog
(`power.menu`), `POWER_N` daneben im Quelltext.

### 3.3 Die Sicherheitsabfrage

Über `wlib.dlg_wahl`, mit dem gefährlichen Wort auf dem Knopf
(„Ausschalten", nicht „OK"). Tastatur: Eingabe und Flucht führt `wlib`.

**Hier steckte der ernsteste Fehler dieser Runde — siehe Abschnitt 5.**

### 3.4 Abmelden, ehrlich benannt

Dieses System hat **noch keine Anmeldung** (`P-002`, der Schreibtisch läuft
als `root`). Ein Punkt „Abmelden", der eine Sitzung beendet, die es nicht
gibt, wäre eine Behauptung. Was er wirklich tut: **er startet den
Schreibtisch neu** (`/bin/desktop`). Das steht so im Quelltext und wird
nicht als Sitzungsende ausgegeben. Sobald Lauf 2 (Zweig `anmeldung`) die
Anmeldung bringt, ist hier **eine Zeile** zu ändern — die Stelle ist
`pw_abmelden`.

### 3.5 Das Abbild bekommt einen Prozess 1

`tools/usbimg/build.sh` legte **weder `/bin/init` noch `/etc/inittab` noch
ein Verzeichnis `/run`** ins Abbild (mit `mkfs.py list` nachgemessen).
Damit fiel `/bin/shutdown` auf dem Stick **immer** auf seinen Notweg
zurück: `sync` und ACPI, ohne dass ein einziger Dienst ein Signal bekommt.

Jetzt werden `init` und `svc` mitgebaut, `/etc/inittab` und `/etc/ziel`
liegen im Abbild, `/run` existiert, und die Pflichtliste prüft alle drei
(**61 statt 58 Pfade**).

Die `inittab` ist absichtlich kurz. Die Oberfläche steht **nicht** darin:
`kgui.desk_start` startet sie selbst aus dem Kern. Die Konsole läuft nur im
Ziel `konsole`; im Ziel `grafik` steht sie **gar nicht** in der Tafel, und
beide Alternativen wurden gemessen und verworfen:

* mit `ctrl` würde ein `exit` im Terminalfenster den ganzen Rechner ausschalten;
* mit `respawn` startet sie endlos neu — **gemessen 71 Mal in zwanzig
  Sekunden** (`sh: ready` / `sh: bye` im Wechsel), weil auf einem
  Schreibtisch niemand an dieser Konsole sitzt.

---

## 4. Der Weg, den ein Klick nimmt

```
Energieknopf  →  Menü  →  Rückfrage  →  bestätigt
                                          │
                    ┌─────────────────────┴─────────────────────┐
                    │ 1. eine Zeile nach /run/svc.cmd           │  der richtige Weg
                    │    → init: SIGTERM · Frist · SIGKILL      │
                    │      · sync · umount_all · ACPI           │
                    └─────────────────────┬─────────────────────┘
                                          │ nach 500 ms keine Antwort
                    ┌─────────────────────┴─────────────────────┐
                    │ 2. selbst: sync + Syscall 169             │  der Notweg
                    │    → kernel/sys.fi::do_reboot → ACPI      │
                    └───────────────────────────────────────────┘
```

**Warum der Notweg gebraucht wird, gemessen:** im grafischen Betrieb
startet `kgui.desk_start` Schreibtisch, Leiste und Starter **direkt**. Im
Mitschnitt steht `desk: start /bin/desktop pid=2`, aber **nie**
`osum: pid1 init` — Prozess 1 ist in diesem Lauf nicht init, und die Zeile
nach `/run/svc.cmd` hat dort keinen Leser.

Die Zeile wird trotzdem **zuerst** geschrieben: derselbe Starter läuft auch
auf einem System **mit** init (Serverbetrieb, `/etc/ziel = konsole`), und
dort ist der Weg über Prozess 1 der einzig richtige — nur er kennt die
Dienste und ihre Kennungen.

Der Notweg ist ehrlich **weniger**: kein Dienst bekommt SIGTERM. Aber
`sync` läuft, und das ist der Teil, der Datenverlust verhindert. Es sind
dieselben zwei Aufrufe, die `/bin/shutdown -f` seit Runde INIT macht — eine
dritte Fassung gibt es nicht.

---

## 5. Der Fehler, den die Abnahme gefunden hat

**Die Fluchttaste schaltete den Rechner aus.**

Gemessen im Lauf `one-nein`: im Dialog Escape gedrückt, und der Mitschnitt
sagte

```
launcher: energie tat 1
power: init sagt ab
power: acpi pm1a=0x604 s5typ=0
```

Die Maschine ging **aus**, obwohl abgebrochen werden sollte. Eine
Rückfrage, deren Abbruch ausschaltet, ist schlimmer als keine.

**Ursache — in `wlib` und nicht im neuen Code.** `on_key` legt die
Fluchttaste eines Dialogs auf `dl_no`, und `dl_no` ist bei mehr als zwei
Knöpfen der **letzte** (`wlib.fi:6974`):

```
dl_ok = dl_btn[0]
dl_no = dl_btn[0]
if nk > 1 { dl_no = dl_btn[nk - 1] }
```

Die Tat stand rechts, also zuletzt — und damit auf der Fluchttaste.

**Behoben ohne `wlib` anzufassen** (dort hängen dreizehn Programme dran):
die **Tat steht jetzt links**, der Abbruch rechts, und der Fokus wird
ausdrücklich auf den Abbruch gelegt (`dlg_button(1)`), damit die
Eingabetaste nicht umgekehrt in die Falle läuft. Das ist nicht die
Anordnung, die Windows wählt — aber die einzige, die mit dieser Bibliothek
**beide** Tastenwege richtig macht.

---

## 6. Abnahme — mit Bildern und Zahlen

Läufer: `pruef/oneshot.py <aus|neu|nein>`. Belege: `belege/energie/`.

### 6.1 Ausschalten (`aus`)

| Schritt | Beleg |
|---|---|
| Startmenü offen | `aus-10-startmenue.png` |
| Energiemenü aufgeklappt | `aus-20-energiemenue.png` — Menü bei `20,610 103×94`, weiß mit Akzent `#2563eb` |
| Rückfrage | `aus-30-abfrage.png` — Dialog bei `470,355 340×90` |
| **QEMU beendet sich** | **`rc=0`** |

Serielle Kette (`aus-belegzeilen.txt`):

```
      79  mb: flags=0x24f
   30534  launcher: energie auf
  169760  launcher: energie wahl=0
  169878  launcher: energie frage=1
  515564  launcher: energie tat 1
  516170  launcher: energie selbst aus
  516457  power: init sagt ab
  516477  power: acpi pm1a=0x604 s5typ=0
```

**`rc=0` ist der Beweis.** Eine ACPI-Abschaltung ergibt 0; der Ausgang des
Prüfstands (`isa-debug-exit`) ergäbe 21.

### 6.2 Neustart (`neu`) — ohne `-no-reboot`

```
      79  mb: flags=0x24f        <- der erste Start
  524841  launcher: energie tat 2
  526316  power: init sagt ab
  526336  power: reset 0xCF9
  526434  mb: flags=0x24f        <- DER ZWEITE START
```

**Der Kern kommt ein zweites Mal hoch.** Ein `halt`, das sich als Neustart
ausgibt, tut das nicht.

### 6.3 Abbrechen (`nein`)

```
   31270  launcher: energie auf
  171330  launcher: energie wahl=0
  171448  launcher: energie frage=1
  295179  launcher: energie abbruch
```

Kein `tat`, kein ACPI, **die Maschine läuft weiter**. Genau die Zusage, die
in Abschnitt 5 einmal gebrochen war.

### 6.4 Dass `sync` wirklich schreibt — mit Gegenprobe

Der Lauf mit dem Startmenü bootet aus einem **Modul** (`modfs`): die Wurzel
liegt im Arbeitsspeicher, `blk.flush` kehrt dort sofort zurück
(`kernel/blk.fi:720`), und ein `sync` ist nachweislich ein Nichts. Ein
Beleg „sync lief" wäre aus so einem Lauf eine Behauptung.

Also `pruef/syncbeleg.py` mit **echter ATA-Platte**:

```
1. schreiben und SAUBER herunterfahren
   QEMU rc=0
   init: herunterfahren · init: reaped · init: umounts=0
   power: acpi pm1a=0x604 s5typ=0
2. dieselbe Platte noch einmal starten
   /beleg.txt nach dem Neustart: DA   (HALLO-ENERGIE)
3. GEGENPROBE: schreiben und die Maschine ABWÜRGEN (kill -9)
   /beleg2.txt nach dem Abwürgen: FEHLT

=> sync WIRKT: nur der saubere Weg hat die Puffer geschrieben.
```

Die Gegenprobe ist der Kern dieses Belegs: ohne sie misst man die Platte
und nennt es Herunterfahren.

### 6.5 Die Texte kommen aus dem Katalog

Aus dem Mitschnitt, was `wlib` wirklich gemalt hat:

```
[Power]  [Really shut down the computer?]  [Shut down]  [Cancel]
```

Englisch, weil das Abbild `lang=en` ausliefert. Deutsch steht daneben in
`locale/de/messages`; nichts ist hartkodiert.

---

## 7. Was NICHT geht — und warum

### 7.1 Die Einschalttaste am Rechner (Punkt 5 des Auftrags)

**Geht nicht, und es liegt nicht am fehlenden AML-Interpreter.**

Der Auftrag vermutete `K-003` (kein AML, Zweig `aml` ungemergt) als
Hindernis. Nachgemessen ist es etwas Grundsätzlicheres: **dieser Kern
schaltet ACPI-Ereignisse beim Start ausdrücklich ab.**
`kernel/hw.fi::gpe_block_off` läuft über beide GPE-Blöcke und tut genau
das — erst das Freigaberegister auf 0, dann den Status leeren:

```
serial.out8(en as u16, 0 as u8)      // keine Freigabe mehr
serial.out8(sts as u16, 0xFF as u8)  // Status gelöscht (RW1C)
```

Dazu fehlt der ganze Unterbau: **kein SCI-Handler, keine `SCI_INT` aus der
FADT, kein `PM1a_EVT`-Register wird je gelesen** (`grep` über `kernel/`:
null Treffer für `SCI`, `PM1A_EVT`, `PWRBTN`).

Die Einschalttaste ist ein **Fixed Event** in `PM1x_STS` Bit 8 und bräuchte
dafür kein AML — aber sie bräuchte einen Interrupt, den niemand entgegen-
nimmt, und ein Freigabebit, das dieser Kern beim Start löscht. Das ist eine
eigene Runde im Kern (SCI aufsetzen, GPEs nicht mehr pauschal abschalten),
und sie gehört nicht in eine Runde über Oberfläche. **Also gelassen und
hier gesagt.**

### 7.2 Der Weg über `init` im Desktop-Betrieb

Er ist gebaut, geprüft und **auf einem Abbild mit `/etc/ziel = konsole`
gemessen** (Abschnitt 6.4: `init: herunterfahren`, `reaped`, `umounts`).
Im **grafischen** Betrieb greift er heute nicht, weil der Kern die
Oberfläche selbst startet und dabei nicht über init geht — dort läuft der
Notweg. Das ist kein Fehler dieser Runde, sondern der Zustand des
Systemstarts; die Stelle ist `kernel/kmain.fi::osum` (`wait_long` auf
Prozess 1) gegen `gfx.stage_surface`. Wer das zusammenführt, bekommt den
vollen Weg auch auf dem Schreibtisch, und an dieser Oberfläche ändert sich
dafür **keine Zeile**.

---

## 8. Dateien

| Datei | Was |
|---|---|
| `kernel/user/launcher.fi` | Knopf, Menü, Rückfrage, beide Abschaltwege |
| `locale/de/messages`, `locale/en/messages` | zehn neue Schlüssel `power.*` |
| `tools/usbimg/build.sh` | `init`+`svc` gebaut, `/etc/inittab`, `/etc/ziel`, `/run`, 3 neue Pflichtpfade |
| `pruef/oneshot.py` | Abnahme mit echten Klicks (`aus`/`neu`/`nein`) |
| `pruef/syncbeleg.py` | `sync`-Beleg mit Gegenprobe, echte Platte |
| `belege/energie/` | Bilder, Belegzeilen, Befunde |

`tools/check-ui.sh`: **grün** (166 Dateien, 0 Befunde).
