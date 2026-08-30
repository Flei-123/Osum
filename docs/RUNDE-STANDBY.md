# RUNDE STANDBY — echter Schlaf, und zwar tief

Warum es diese Runde gibt: Justins Windows-Laptop wird im zugeklappten
Zustand im Rucksack warm und ist am Ziel leer. Das ist kein Defekt,
das ist die Bauart. Seit Windows 8 heißt der Schlaf **Modern Standby**
(S0ix), und S0ix ist kein Schlafzustand, sondern ein sehr leiser
Betriebszustand: der Prozessor darf in tiefe C-Zustände, Dienste dürfen
aufwachen, und ein einziger Treiber, der seine Aufweckquelle nicht
abgibt, hält die ganze Maschine wach.

Osum macht das anders. **S3** (Suspend to RAM): der Prozessor wird
abgeschaltet, die Geräte werden abgeschaltet, es bleibt der Speicher im
Selbstauffrischbetrieb und der Teil des Chipsatzes, der auf das
Wecksignal hört. **S4** (Suspend to Disk): der Zustand kommt auf die
Platte, danach geht die Maschine wirklich aus. Kein S0ix. Was schläft,
schläft.

---

## 1. Was gebaut wurde

| Datei | Zeilen | Was darin steht |
|---|---:|---|
| `kernel/sleep.fi` | 2306 (neu) | \_S3/\_S4 aus der DSDT, Gerätesicherung, der Schlafübergang, der Aufwachpfad, Aufweckquellen, Deckelrichtlinie, `/etc/deckel.conf`, das S4-Abbild samt Prüfung, das Schlafprotokoll, die Proben |
| `kernel/arch/x86_64/isr.s` | +296 | Das Trampolin: Realmodus → Protected Mode → Long Mode, `wake_save`/`wake_regs`, die Übergangs-Seitentafel, die Schattenkopie |
| `kernel/time.fi` | +72 | `time.nachziehen` — die Uhr aus der RTC nachziehen |
| `kernel/arch/x86_64/apic.fi` | +52 | `apic.resume` — den APIC ohne Neumessung wieder aufsetzen |
| `kernel/kstate.fi` | +86 | Der Zustandsbereich `STBY_OFF` und die Modusbits der Runde |
| `kernel/kmain.fi` | +37 | `sleep.parse`, `sleep.aufsetzen`, `sleep.stage` |
| `kernel/kernel.ld` | +12 | `__save_begin` — der Anfang des beschreibbaren Abbildbereichs |
| `tools/standby/lauf.py` | 221 (neu) | Der Läufer: ein S3-Lauf von außen, über QMP |

Summe: **2795 hinzugefügte Zeilen**, 5 geänderte.

---

## 2. Die vier Fallen auf dem Rückweg

Der Weg in den Schlaf ist eine Zeile — `out PM1a_CNT, (SLP_TYPa<<10)|SLP_EN`.
Der Weg zurück hat vier Anläufe gekostet, und jeder Fehler steht als
Kommentar an der Stelle, an der er passiert ist.

### 2.1 QEMU schreibt beim Aufwachen das Kernabbild neu

QEMU behandelt das Aufwachen aus S3 als **Maschinenreset**, und bei
jedem Reset schreibt `rom_reset` (hw/core/loader.c) alle geladenen
Abbilder erneut in den Speicher — auch das mit `-kernel` übergebene.
`.text` und `.rodata` sind danach unverändert, `.data` steht wieder auf
den Anfangswerten, `.bss` ist null. Damit war der gesamte
Kernzustand weg.

Gemessen in `-d int,cpu_reset`:

```
v=0e e=0008 cpl=0 IP=0008:00100478 CR2=00100478 CR3=00000000
EFER=0000000000000500   -> danach v=08, danach Triple fault
```

Gegenmittel: eine **Schattenkopie** von `[__save_begin, kernel_end)` in
Rahmen oberhalb des Abbilds, die das Trampolin zurückholt, bevor der
erste Zugriff auf eine Seitentafel oder einen Stapel passiert.
Abschaltbar mit `noschatten`.

**Was das nicht beweist:** dass der Speicher den Schlaf überlebt — denn
genau das gleicht es aus. Alles andere beweist es weiterhin (siehe 4.1).

### 2.2 Die Schattenkopie wurde zu früh gezogen

Sie stand zuerst vor Schritt 5 des Schlafpfades. Damit kamen `S_WALL`,
`S_MONO` und `S_DOWN_MS` beim Aufwachen als Null zurück; der Bericht
sagte `nach=0 down=0`, und `nachziehen` gab bei `wall_vor == 0` auf —
die Uhr wurde nie nachgezogen. Was der Aufwachpfad lesen soll, muss
**vor** der Kopie geschrieben sein.

### 2.3 `wake_save` rettet nur die aufgerufenen-erhaltenen Register

Es rettet, was die Aufrufvereinbarung verlangt: rbx, rbp, r12..r15, rsp
und die Rücksprungadresse. Alles, was der Übersetzer in rax, rcx, rdx,
rsi, rdi oder r8..r11 hielt, ist nach dem Aufwachen der Zustand, den das
Trampolin hinterlassen hat. Das hat zweimal gekostet:

* `down` stand im Bericht bei **4013181850 ms** — sechsundvierzig Tagen.
* Und schlimmer: **der Zustandszeiger selbst** lag in einem solchen
  Register. Solange im Aufwachpfad noch Debug-Marken standen, legte der
  Übersetzer ihn zufällig in ein erhaltenes Register und alles ging gut;
  ohne die Marken rechnete er anders, und der Kern schrieb sein `kstate`
  an eine Adresse aus dem Trampolin. Kein Absturz, keine Ausgabe, gar
  nichts.

Gegenmittel: der Aufwachpfad ist eine eigene Funktion `aufgewacht`, die
ihren Zustandszeiger aus `WAKE_REGS+136` **unter 1 MiB** holt.

Derselbe Fehlertyp traf die Ausgabefunktion `roh_aus`: die Warteschleife
liest mit `in al, dx` nach rax; wurde sie an einer Stelle eingesetzt, an
der das Argument in rax lag, fiel der geprüfte Wandel `u64 as u8` mit
„integer overflow“ um. Das Oktett wird jetzt gebildet, bevor gewartet
wird.

### 2.4 `apic.init` misst auf dem Aufwachpfad

`apic.calibrate` wartet in `pit_wait` bis zu **zwei Millionen**
Ein-/Ausgabezugriffe lang auf Kanal 2 des PIT. Auf dem Aufwachpfad
antwortet der Kanal unter TCG nicht zuverlässig, die Schleife lief voll
aus, und der Kern stand halbe Minuten — so lange, dass selbst die
Hauptschleife von QEMU nicht mehr zum Zug kam und der QMP-Anschluss
stumm blieb.

Neu: `apic.resume` setzt den APIC ohne Messung wieder auf, mit dem vor
dem Schlaf gemessenen Wert. Es ist dieselbe Maschine.

---

## 3. Messungen

Messwirt: QEMU 7.2, **TCG** (kein KVM), `-m 128`, `-global
PIIX4_PM.disable_s3=0`, Läufer `tools/standby/lauf.py`.

### 3.1 Kommen sie zurück? — 100 von 100

Zehn Startläufe zu je zehn Runden (`standby s3loop`, `--runden 10`):

```
standby: reihe n=10 ok=10      (zehnmal, ohne Ausnahme)
```

**100 von 100 Anläufen kamen sauber zurück.** Nicht 97 — 100.

| Größe | Median | Min | Max |
|---|---:|---:|---:|
| Befehl bis Schlaf | **6,5 ms** | 1 | 27 |
| Wecksignal bis laufende Sitzung | **9 ms** | 5 | 34 |
| Zurückgeholte Geräte | 14 | 14 | 14 |

Die Streuung ist die des Wirts, nicht die des Kerns: derselbe Kern auf
demselben Abbild, gemessen über eine Stunde auf einer geteilten
Maschine.

### 3.2 Die Uhr

Vor dem Schlaf werden beide Uhren gemerkt: die monotone (steht während
S3) und die des CMOS (läuft weiter). Beim Aufwachen wird die Differenz
in den Zyklenzähler zurückgerechnet.

| Wirklich geschlafen | `nach=` im Bericht |
|---:|---:|
| 2 s | 2 |
| 3 s | 3 |
| 4 s | 4 |
| 8 s | 8 |

Gegenprobe `nortcsync` (der Nachzug wird weggenommen): `nach=0` — die
Systemzeit geht danach um genau die Schlafdauer nach. **Der Test fällt,
wie er soll.**

### 3.3 S4

Auf einer IDE-Platte von 64 MiB:

```
standby: s4 schreiben seiten=118 oktett=60928 ms=1144 lba=2048
```

118 Blöcke, **60928 Oktette**, **1144 ms**. Verdichtet wird mit
Nullaufhebung: ein Block aus lauter Nullen wird übersprungen.

---

## 4. Die Tests, die wirklich rot werden können

### 4.1 `s3keep` — was vorher da war, muss nachher da sein

„Kein Absturz“ ist kein Ergebnis. Vor dem Schlaf wird `/standby.txt`
angelegt und mit 512 Oktetten eines bekannten Musters beschrieben; die
Inodennummer wird gemerkt — das ist hier der offene Verweis. Nach dem
Schlaf wird über **dieselbe** Nummer gelesen und Oktett für Oktett
verglichen. Dazu wird gewartet, bis der Markenzähler sich wieder bewegt.

```
standby: keep nach ino=4 read=512 gleich=1 laeuft=1 ticks=276
```

Über zwei Reihenläufe zu je zehn Runden: **20 von 20 gleich, 20 von 20
laufen wieder**. Das Muster hängt an der Rundennummer — ein
Dateisystem, das nichts mehr schreibt und nur den alten Inhalt
zurückgibt, würde durchfallen.

**Warum das etwas beweist:** die RAM-Platte liegt in Rahmen, die
`mem.frame_run` **oberhalb** des Kernabbilds vergeben hat. Die
Schattenkopie aus 2.1 deckt nur `[__save_begin, kernel_end)` und fasst
diese Rahmen nicht an. Was hier überlebt, hat wirklich den Schlaf
überlebt.

Erster Anlauf dieser Probe stand bei **1 von 10**: sie legte in jeder
Runde neu an, und `create_path` gab ab der zweiten Runde 0 zurück, weil
der Name schon da war. Der Fehler lag in der Probe, nicht im Schlaf —
er steht hier, weil eine Probe, deren erstes Ergebnis rot war, mehr
wert ist als eine, die nie rot war.

### 4.2 Das S4-Abbild und drei Angriffe

Ein Rechner, der ein fremdes oder kaputtes Ruheabbild einspielt, ist
danach kaputt, und zwar auf eine Art, die niemand mehr versteht. Also
wird geprüft, und beim ersten Fehler startet die Maschine **normal**.

| Fall | `w=` | Ergebnis |
|---|---:|---|
| unverändert | 1 | gültig |
| **verfälschter Rumpf** (ein Oktett gekippt) | **9** | verworfen |
| fremde Kernversion | 5 | verworfen |
| fremde Hardware-Signatur (Feld gefälscht) | 6 | verworfen |
| **wirklich andere Maschine** (256 statt 128 MiB) | 6 | verworfen |

Der verfälschte Rumpf ist der wichtigste Eintrag der Tabelle: er kam
**vorher durch alle vier Prüfungen hindurch**. Der Kopf war durch
`H_SUM` gedeckt, der Rumpf durch gar nichts. Neu ist `H_BODYSUM`, eine
Summe über alle geschriebenen Rumpfblöcke, die beim Start nachgerechnet
wird. Das kostet einen zweiten Durchlauf über das Abbild — bei 118
Blöcken wenige Millisekunden.

Der letzte Fall ist kein gefälschtes Feld, sondern eine wirklich andere
Maschine: dasselbe Abbild, `-m 256` statt `-m 128`. Die
Hardware-Signatur ist `MEM_TOP ^ (Prozessorzahl<<48) ^ (PCI-Zahl<<56)`
und fällt damit von selbst auseinander.

### 4.3 Die Aufweckquellen

Jede Quelle ist einzeln schaltbar, und die Voreinstellung ist
restriktiv: **im Zweifel weckt nichts.** Was in `PM1x_EN` steht, wird
nach dem Schreiben **zurückgelesen** — was dort steht, ist das, was die
Maschine wecken darf; alles andere wäre eine Behauptung über eine
Schreiboperation.

| Befehlszeile | soll | ist | Netztaste | Deckel | USB | RTC | LAN |
|---|---|---|---:|---:|---:|---:|---:|
| `standby s3go` | 0x100 | 0x100 | 1 | 0 | 0 | 0 | 0 |
| `standby s3go wakertc` | 0x500 | 0x500 | 1 | 0 | 0 | 1 | 0 |
| `standby s3go nowake` | 0x0 | 0x0 | 0 | 0 | 0 | 0 | 0 |

Soll und Ist stimmen in jedem Fall bitgenau überein.

**Was hier NICHT bewiesen ist, und das ist wichtig:** dass eine
geschlossene Quelle wirklich nicht weckt. QEMUs `system_wakeup` weckt
die Maschine **unabhängig von `PM1x_EN`** — auch bei `tore=0x0` kam sie
zurück. Der QEMU-RTC-Wecker wiederum löst gar kein Weckereignis aus:
mit `wakertc` und ohne äußeres Signal blieb die Maschine 30 Sekunden
liegen (`geschlafen=True geweckt=False status=suspended`). Beides sind
Eigenschaften des Emulators, nicht des Kerns. Auf echtem Blech ist das
Register das Tor; hier ist nur nachgewiesen, dass **im Tor genau das
steht, was dort stehen soll**. Der Nachweis, dass es hält, gehört auf
Hardware (siehe 6).

### 4.4 Die Deckelrichtlinie und `/etc/deckel.conf`

Fünf Werte, getrennt für Netz- und Akkubetrieb:
`nichts | schirm-aus | s3 | s4 | aus`, dazu eine Frist in Minuten,
nach der aus S3 ein S4 wird — genau das, was Windows nicht tut.

Die Probe schreibt eine Datei, die **absichtlich Unsinn enthält**:

```
# Deckel
netz=schirm-aus
akku=s4
frist=45
unsinn=blah
akku=quatsch
```

Ergebnis:

```
standby: conf verstand=3 netz=1 akku=3 frist=45 src=1
standby: deckel zu netz=0 aktion=3
```

Drei Zuweisungen verstanden, `unsinn=blah` übergangen, und
`akku=quatsch` hat den vorher gelesenen Wert `s4` **stehen gelassen**
statt ihn zu raten. Eine Richtliniendatei, die halb verstanden wird,
ist gefährlicher als gar keine.

### 4.5 Die Gegenproben nach Hausart

| Schalter | Was er wegnimmt | Ergebnis |
|---|---|---|
| `nortcsync` | den Nachzug der Uhr | `nach=0` — die Uhr geht nach ✅ fällt |
| `noschatten` | die Kopie des Abbildbereichs | die Maschine kommt unter `-kernel` **gar nicht** zurück ✅ fällt |
| `nodevsave` | das Sichern des Gerätezustands | `dev=0` — aber sie kommt trotzdem zurück ⚠️ siehe unten |
| `ohnefsync` | das Schreiben der Puffer | `fsync=0` — auf der RAM-Platte ohne Wirkung ⚠️ siehe unten |
| `nowake` | alle Aufweckquellen | `tore=0x0` — QEMU weckt trotzdem ⚠️ siehe 4.3 |

**`nodevsave` ist unter QEMU eine schwache Gegenprobe**, und das steht
hier statt einer Beschönigung: `dev=0` beweist, dass der Kern nichts
zurückgeholt hat, aber die Maschine lief weiter, weil SeaBIOS auf dem
S3-Aufwachpfad Teile des Chipsatzes selbst wieder aufsetzt. Auf echtem
Blech, mit echten PCI-BARs, wäre das tödlich. Der Nachweis fehlt hier
und gehört auf Hardware.

**`ohnefsync` ist auf einer RAM-Platte wirkungslos**, weil es dort
keinen Puffer gibt, der verlorengehen könnte. Der Schalter ist gebaut
und greift (`fsync=0` in der Ausgabe), aber dass er einen Unterschied
macht, ist hier **nicht** gemessen. Dafür braucht es eine Platte mit
`cache=writeback` und einen Lauf, der mitten im Schreiben schläft.

Eine Nebenwirkung dieser Runde: das Wort hieß zuerst `nofsync`, und
`kmain.fi` sucht `nofs` mit derselben Teilwortsuche. Ein Lauf mit
`nofsync` hatte deshalb **gar kein Dateisystem**, und die Probe fiel aus
einem Grund durch, den niemand gemeint hatte. Das Wort heißt jetzt
`ohnefsync`.

---

## 5. Der Werkzeugkasten

`tools/standby/lauf.py` steuert einen S3-Lauf von außen — über **QMP**
und nicht über den Menschenmonitor. Der Grund ist gemessen: der HMP gibt
kein Ende-Zeichen aus, jeder Leser muss raten, wann eine Antwort fertig
ist, und nach `system_wakeup` blieb genau dieses Raten hängen (die
zweite Abfrage antwortete nie). QMP ist zeilenweises JSON mit einer
Antwort je Befehl.

```
tools/standby/lauf.py --abbild osum.mb --anhang "standby s3go" \
    [--wecken-nach 2] [--runden 10] [--platte hd.img] [--speicher 256]
```

Rückgabe: 0, wenn die Maschine wirklich geschlafen hat **und** wieder
aufgewacht ist.

Die Wörter auf der Kernbefehlszeile:

| Wort | Wirkung |
|---|---|
| `standby` | die Runde überhaupt einschalten |
| `s3go` | einmal schlafen |
| `s3loop` | zehnmal schlafen und zählen |
| `s3keep` | die Probe aus 4.1 mitlaufen lassen |
| `s4go` | ein Ruheabbild schreiben |
| `lidgo` | den Deckel zumachen |
| `lidconf` | `/etc/deckel.conf` schreiben, lesen und vorzeigen |
| `wakertc` | den RTC-Wecker als Quelle öffnen |
| `sbsay` | das Schlafprotokoll ausgeben |
| `nowake` `nodevsave` `nortcsync` `noschatten` `ohnefsync` | die Gegenproben |

---

## 6. Was auf echter Hardware zusätzlich nötig wäre

QEMU ist kein Blech. Was hier grün ist, ist dort noch nicht fertig:

1. **Die Grafik.** Ein echter Grafikchip ist nach S3 aus, und sein
   Zustand steht nicht im PCI-Konfigurationsraum. Linux ruft dafür
   entweder das VBE/VGA-BIOS im Realmodus noch einmal auf oder hat einen
   Treiber, der den Modus selbst setzt. Osum hat weder das eine noch
   das andere auf dem Aufwachpfad. Unter QEMU fällt das nicht auf, weil
   der Rahmenpuffer den Reset überlebt. **Ohne diesen Schritt wacht ein
   echter Laptop mit schwarzem Bildschirm auf.** Das ist die größte
   offene Baustelle dieser Runde.
2. **Der Speicher muss wirklich überleben.** Die Schattenkopie aus 2.1
   ist eine Krücke für den Emulator. Auf Blech gehört sie mit
   `noschatten` aus — dann steht und fällt alles damit, dass der
   Chipsatz den Selbstauffrischbetrieb richtig eingestellt hat. Das ist
   Firmware-Arbeit und hier nicht geprüft.
3. **Die Aufweckquellen im Tor.** Siehe 4.3: dass ein geschlossenes Tor
   hält, ist auf diesem Wirt nicht nachweisbar. Auf Blech ist der Test
   einfach — Deckel zu, LAN-Paket schicken, nachsehen, ob sie liegen
   bleibt — und er ist der eigentliche Punkt der ganzen Runde.
4. **Der Gerätezustand.** `nodevsave` ist unter QEMU zahnlos (4.5).
   xHCI, AHCI und NVMe brauchen auf Blech eine echte
   Wiederinitialisierung, nicht nur die BARs und das Befehlsregister.
5. **Firmware-Eigenheiten.** Manche UEFI-Fassungen springen nicht über
   `firmware_waking_vector`, sondern erwarten den 64-Bit-Eintrag
   `x_firmware_waking_vector`; manche stellen A20 anders ein; manche
   hinterlassen den Prozessor mit gesetztem Cache-Deaktivierbit. Der
   Code liest beide Vektorfelder, aber geprüft ist nur SeaBIOS.
6. **Mehrkern.** Der Schlafpfad hält die anderen Prozessoren an, aber
   der Messwirt lief mit `cpus=1`. Ein Aufwachen mit vier Kernen ist
   ungetestet.

---

## 7. Was später auf den AML-Interpreter gehört

Parallel läuft Runde AML an einem echten Interpreter. Diese Runde hat
den vorhandenen Musterleser aus `power.fi` nur so weit erweitert, wie
sie musste. Diese Stellen gehören umgestellt, sobald AML fertig ist:

1. **`_S3` und `_S4` aus der DSDT.** Heute ein Mustersuchlauf über die
   Tabelle nach `08 5F 53 33 5F 12` mit anschließendem Ablesen der
   ersten beiden Paketglieder. Das funktioniert, weil praktisch jede
   Firmware `\_S3` als `Name(_S3, Package(){...})` mit kleinen
   Konstanten schreibt — es ist aber eine Wette auf eine Kodierung,
   nicht das Auswerten eines Ausdrucks. Ein Paket mit `Buffer` oder
   berechneten Gliedern wird hier falsch gelesen.
2. **Der Deckelschalter.** `_LID` ist eine **Methode**, kein Wert. Ohne
   Interpreter lässt sich der Deckelzustand nicht abfragen, und die
   Quelle `Q_DECKEL` ist deshalb heute nur eine Einstellung ohne
   Hardware dahinter. Das ist die Quelle, die den ganzen Anlass dieser
   Runde ausmacht.
3. **`_PRW` je Gerät.** Welche Quelle an welchem GPE-Bit hängt, steht in
   `_PRW`. Ohne das ist „USB-Tastatur darf wecken“ nicht auf ein Bit
   abbildbar, und die Quellen `Q_USB` und `Q_LAN` sind heute
   Buchhaltung ohne Register.
4. **GPE-Blöcke.** Der Aufwachpfad liest heute nur `PM1a_STS`. Alles,
   was über einen GPE weckt (und das ist auf einem Laptop das meiste),
   erscheint deshalb als „unbekannt“. `wecker_lesen` gehört auf
   GPE0_STS/GPE1_STS erweitert, und die Zuordnung Bit → Quelle kommt aus
   `_PRW`.
5. **`_PTS` und `_WAK`.** ACPI verlangt, dass vor dem Schlaf `_PTS(3)`
   und nach dem Aufwachen `_WAK(3)` aufgerufen wird. Beides sind
   Methoden. Manche Firmware braucht sie, um Lüfter und Rails richtig
   zu schalten. Heute werden sie **nicht** gerufen — unter QEMU ohne
   Folgen, auf Blech ein Risiko.

---

## 8. Was diese Runde nicht geschafft hat

Ehrlich und ohne Umschweife:

* **S4 spielt nicht ein.** Das Abbild wird geschrieben, beim Start
  gefunden und vollständig geprüft (Kennung, Fassung, Kopfsumme,
  Rumpfsumme, Kernversion, Hardware-Signatur) — und dann steht dort
  `s4-abbild gueltig, NICHT eingespielt`. Der Rückweg fehlt: er braucht
  einen Lader, der vor dem Aufsetzen des Speichermanagements Seiten an
  ihre alten physischen Adressen zurückschreibt, und das ist eine eigene
  Runde. Halb gebaut und stillschweigend unwirksam wäre das schlechteste
  Ergebnis; deshalb steht es hier und in der Ausgabe des Kerns.
  Was das Abbild heute enthält, ist der Kernzustandsbereich, **nicht**
  der ganze Speicher — der Plan dafür steht in `sleep.fi` bei
  `s4_schreiben`.
* **Die Frist S3 → S4 entscheidet, aber weckt nicht.**
  `frist_faellig(state, minuten)` gibt die richtige Antwort, und die
  Voreinstellung im Akkubetrieb ist `s3` mit 120 Minuten. Einen Wecker,
  der nach der Frist von selbst aufwacht und nach S4 durchschaltet, gibt
  es noch nicht — er hängt am RTC-Wecker, und der weckt unter QEMU nicht
  (4.3).
* **Das Schlafprotokoll ist noch keine Datei.** Es liegt im Ringpuffer
  (`L_MAX` Einträge: eingeschlafen, aufgewacht, wer geweckt hat, wie
  lange tief) und kommt mit `sbsay` auf die serielle Leitung. Als
  Textdatei unter `/var/` und als Kommandozeilenwerkzeug im Userland ist
  es nicht geschrieben — dafür fehlt der Weg vom Kernzustand ins
  Dateisystem beim Herunterfahren.
* **Kein Lauf auf echtem Blech.** Siehe 6.

---

## 9. Auflagen

* **Bauten grün.** Der GUI-Bau (`gui=on`) ergibt 3378420 Oktette, der
  GUI-lose Serverbau (`--gui off`) 2537740 Oktette. Beide bauen ohne
  Fehler durch.
* **Bestehende Tests, gemessen:**
  * `tools/kernel/run.sh` — **176 passed, 0 failed**. Das ist der
    Abschnitt, der IDT, PIC/PIT, Ring 3, Prozesse und Dateisystem
    prüft, also genau das, was diese Runde angefasst hat.
  * `tools/smp/run.sh` — **59 passed, 0 failed**. Der Abschnitt zum
    APIC, in dem `apic.resume` dazugekommen ist.
  * `tools/freestanding/run.sh` — 41 passed, 0 failed.
  * `tools/core/run.sh` — 46 proofs, 0 failures.
  * `tools/unix/run.sh` — 107 passed, 0 failed.
* **Der vollständige `./test.sh` (53 Abschnitte) konnte nicht zu Ende
  laufen, und der Grund ist ehrlich der falsche:** die Messmaschine
  teilt sich eine 54-GiB-Platte mit den parallel laufenden Runden, und
  sie lief während des Laufs auf 100 % voll. Elf Abschnitte scheiterten,
  und in jedem einzelnen Protokoll steht derselbe Satz:

  ```
  error: cannot write '/tmp/tmp.atWQODvjLo/k0.s': No space left on device (os error 28)
  ```

  Das ist kein Rückschritt im Kern, sondern ein voller Datenträger. Der
  Lauf wurde abgebrochen, damit er den anderen Runden nicht auch noch
  den Platz nimmt. **Der vollständige `./test.sh` gehört auf einer
  freien Platte nachgeholt, bevor dieser Zweig zusammengeführt wird** —
  bis dahin steht hier eine Stichprobe und keine Zusage.
* Kein Test wurde abgeschaltet.
* Kein Messwert in diesem Bericht ist geschätzt. Wo etwas nicht gemessen
  werden konnte, steht das da, statt einer Zahl.
