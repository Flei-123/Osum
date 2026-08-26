# Runde K18 — Energie und Leistung

**Stand:** 26.08.2026 · Branch `k18-power`, abgezweigt von `main`
(`c5fe12f`) · Abnahme: `bash tools/k18/run.sh` → **170 Zusagen, 0
Fehler** · Abschnitt 24 von `./test.sh` · Nummernvorrat: kdata
`0x58000..0x60000`, Systemaufrufe `1750..1799`, Ring-3-Programme `45..47`,
Deskriptorarten `45..47` (**nicht gebraucht**, siehe Abschnitt 11).

---

## 1. Der Satz, um den es geht

**Osum hat drei Energieprofile, und ein Profilwechsel schreibt
nachweislich andere Werte in die Register des Prozessors — dieselbe
Stelle dreimal gelesen, dreimal ein anderer Wert, und zwar die Werte, die
im Handbuch stehen.**

Was dabei ausdrücklich **nicht** behauptet wird, steht gleich hier und
nicht erst in einer Fußnote: **auf der Messmaschine fällt kein Takt.**
Sie läuft unter QEMU/TCG ohne `/dev/kvm`; TCG übersetzt Befehle, es
taktet nichts. Wer in diesem Logbuch eine Megahertzzahl sucht, findet
keine. Warum das trotzdem eine Messung ist und keine Behauptung, steht in
Abschnitt 4.

Der Auftrag dieser Runde war präzise formuliert und wird hier
wiederholt, weil er den Unterschied macht: **nicht „schneller machen",
sondern steuerbar machen** — wie die Energieprofile von Windows oder
Zorin OS.

Aus einem echten Lauf, wörtlich von der seriellen Leitung, mit einer
selbstgebauten ACPI-Tabelle als Akku:

```
osum$ power
Profil:  Ausgeglichen
Taktstufen:  min  8  Basis 16  max 24  (Rueckfall, die Maschine sagt nichts)
Akku:    [###############.....] 75%   entlaedt  Rest: 396 min
Kapazitaet: 3300 von 4400 mWh
Modell:  OSUM-BAT LION
Netz:    Akkubetrieb
Waerme:  30 Grad  gedrosselt: 0 mal
Ruhe:    C1  mwait: 139  hlt: 0 von 140
Kann:    MWAIT Thermalzone
osum$ power leistung
power: jetzt auf Hoechstleistung
```

---

## 2. Wovon diese Runde ausging

Vor ihr konnte Osum über ACPI **genau eine Sache: abschalten**
(`kernel/power.fi`, Runde K13). Zwischen „läuft" und „aus" gab es nichts:

* **Keinen Takt.** Der Prozessor lief auf dem, was die Firmware ihm beim
  Einschalten mitgab. `IA32_PERF_CTL` kam im ganzen Baum nicht vor.
* **Keinen Ruhezustand.** Der Untätigkeitspfad des Schedulers war
  `kernel/tasks.fi`, `fn idle()`, und er lautete vollständig:
  `while true { asm("hlt") }`. Das ist besser als eine Warteschleife —
  aber `hlt` ist C1 und sonst nichts.
* **Kein Turbo, keine Temperatur, keinen Akku, keine Helligkeit.**

---

## 3. Was jetzt da ist

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/pwr.fi` | 942 | Taktverwaltung (P-States und HWP), die drei Profile, Turbo, `monitor`/`mwait`, Temperatur samt Drosselung, Helligkeit und Bildschirmabschaltung |
| `kernel/batt.fi` | 487 | Akku, Netzteil und Thermalzone aus den ACPI-Tabellen (`_BST`, `_BIF`, `_PSR`, `_TMP`, `_STA`) |
| `kernel/user/power.fi` | 581 | `/bin/power` auf der Konsole |
| `tools/k18/run.sh` | 663 | Der Testläufer |
| `tools/k18/msrprobe.s` | 496 | Die **Vorabprüfung**: was tut dieser Wirt mit den Energieregistern? |
| `tools/k18/ssdt.py` | 256 | Baut eine ACPI-Tabelle mit einem Akku darin |
| `tools/k18/soll.py` | 152 | Die **zweite Fassung** der Kodierungen, aus dem Handbuch |

Dazu geändert: `acpi.fi` (`table_count`/`table_at` — **alle** Tabellen
der Reihe nach, einschließlich der DSDT), `tasks.fi` (der
Untätigkeitspfad), `trap.fi` (Zeitgeber, Tastatur, Maus), `sys.fi` (drei
Aufrufe), `uprog.fi` (drei Programme in Ring 3), `kmain.fi`,
`kstate.fi`, `boot.s` (kdata wächst), `tools/kernel/karte.py`, `test.sh`.

---

## 4. Runde 0: erst messen, was der Wirt hergibt — dann bauen

Das ist der wichtigste Abschnitt dieses Logbuchs, und er steht vor allen
anderen, weil ohne ihn jede Zahl weiter unten wertlos wäre.

Die Messmaschine ist **QEMU 7.2.22 ohne `/dev/kvm`**, also TCG, auf einem
AMD EPYC 7571. Ein MSR-Zugriff kann dort dreierlei tun: eine
Schutzverletzung auslösen, angenommen werden und den Wert halten, oder
angenommen werden und ihn wegwerfen. Welches davon eintritt, entscheidet,
was diese Runde überhaupt messen **kann** — und Raten wäre hier das
Schlimmste gewesen: ein Test, der einen geschriebenen Wert zurückliest,
misst im zweiten Fall die Attrappe von QEMU und nicht den Kernel.

Also wurde **vor der ersten Zeile Kernelcode** gemessen.
`tools/k18/msrprobe.s` ist ein eigenständiges Multiboot-Abbild aus einer
Assemblerdatei mit **eigener IDT**, damit ein `#GP` zu einer Zahl wird und
nicht zum Ende des Laufs. Ergebnis, wörtlich:

| Register | lesen | schreiben → zurücklesen | `#GP`? |
|---|---|---|---|
| `IA32_PERF_CTL` (0x199) | 0 | `0xE00` → **0** | nein |
| `IA32_HWP_REQUEST` (0x774) | 0 | `0x80001004` → **0** | nein |
| `IA32_PM_ENABLE` (0x770) | 0 | `1` → **0** | nein |
| `IA32_MISC_ENABLE` (0x1A0) | `0x40001` | `0x4000010000` → **`0x4000010000`** | nein |
| `IA32_PERF_STATUS` (0x198) | `0x400000003e8` (fest) | — | nein |
| `IA32_THERM_STATUS` (0x19C) | 0 | — | nein |
| `IA32_TEMPERATURE_TARGET` (0x1A2) | 0 | — | nein |
| `MSR_PLATFORM_INFO` (0xCE) | 0 | — | nein |
| `MPERF`/`APERF` (0xE7/0xE8) | 0 | — | nein |
| AMD P-State (0xC001006x) | 0 | — | nein |

**Kein einziger Zugriff löst eine Schutzverletzung aus** — QEMU nimmt
alle an. **Aber nur eines behält, was man hineinschreibt:
`IA32_MISC_ENABLE`.**

Dazu CPUID:

| | `qemu64` (Standard) | `-cpu max` / `EPYC` / `Skylake-Server` |
|---|---|---|
| Blatt 1, ECX Bit 3 (MONITOR) | **0** | **1** |
| Blatt 5 (EAX/EBX/ECX/EDX) | `0/0/3/0` | `0/0/3/0` |
| Blatt 6, EAX | `0` | `4` (nur ARAT) |
| davon Bit 0 (DTS) / Bit 1 (Turbo) / Bit 7 (HWP) | 0/0/0 | **0/0/0** |
| Blatt 0x80000007, EDX | 0 | 0 |

Und `monitor` läuft unter `-cpu max` ohne `#UD` und ohne `#GP` durch;
`mwait` **hält wirklich an** (der Probelauf blieb dort stehen, weil er mit
`cli` lief und keine Unterbrechungsquelle hatte).

**Daraus folgten drei Entscheidungen, die den Rest der Runde bestimmen:**

1. **Die Gegenprobe der Profile hängt an `IA32_MISC_ENABLE`.** Es ist das
   einzige Energieregister mit vollem Rundlauf auf diesem Wirt, also
   tragen die drei Profile ihren Unterschied auch **dorthin** — nicht als
   Trick, sondern weil EIST (Bit 16) und Turbosperre (Bit 38) genau die
   Schalter sind, die zu diesen drei Profilen gehören.
2. **HWP wird gebaut, aber nie betreten.** CPUID Blatt 6 meldet Bit 7 als
   Null bei **jedem** CPU-Modell, das QEMU 7.2 anbietet, und eine
   Eigenschaft `hwp` kennt dieses QEMU nicht (`-cpu max,+hwp` →
   *„Property 'max-x86_64-cpu.hwp' not found"*). Geprüft wird davon nur
   die **Kodierfunktion**, und sie wird im Läufer auch genau so benannt.
3. **Es gibt keinen `#GP`-Fängerpfad in `pwr.fi`.** Er wäre auf diesem
   Wirt tot, und ein toter Pfad, der als Sicherheit verkauft wird, ist
   eine Behauptung. Auf einer Maschine, die eines dieser Register nicht
   hat, wäre er nötig — er stünde dann dort und nicht hier im Bericht.

---

## 5. 4.1 Taktverwaltung — die drei Profile

Ein Profil ist kein Schalter, sondern **drei Schreibvorgänge an drei
Register**:

| | Takt (`PERF_CTL`) | EIST (Bit 16) | Turbo (Bit 38) | EPP | C-Zustand | Bildschirm aus nach |
|---|---|---|---|---|---|---|
| **Energiesparen** | kleinstes Verhältnis, Turbo zurückgenommen (Bit 32) | an | **gesperrt** | 0xFF | so tief wie möglich | 5 s |
| **Ausgeglichen** | Grundverhältnis | an | frei | 0x80 | bis C2 | 30 s |
| **Höchstleistung** | größtes Verhältnis | **aus** | frei | 0x00 | nur C1 | nie |

Dass „Höchstleistung" SpeedStep **abschaltet**, ist Absicht und steht so
im Handbuch: ohne EIST bleibt der Prozessor auf dem zuletzt gesetzten
Verhältnis, statt von der Firmware heruntergeregelt zu werden. Es hat
einen zweiten Nutzen, und der wird hier nicht verschwiegen: er macht die
drei `MISC_ENABLE`-Wörter paarweise verschieden und damit die Gegenprobe
überhaupt erst möglich.

**Gemessen** (`-cpu max`, `miscorig = 0x40001`):

| Profil | `PERF_CTL` geschrieben | `PERF_CTL` zurückgelesen | `MISC_ENABLE` geschrieben | **zurückgelesen** |
|---|---|---|---|---|
| Energiesparen | `0x100000800` | `0x0` | `0x4000050001` | **`0x4000050001`** |
| Ausgeglichen | `0x1000` | `0x0` | `0x50001` | **`0x50001`** |
| Höchstleistung | `0x1800` | `0x0` | `0x40001` | **`0x40001`** |

Die letzte Spalte ist die Zusage der Runde: **dieselbe Stelle, dreimal
gelesen, drei verschiedene Werte, wirklich aus dem Prozessor.** Die
Spalte davor ist die Ehrlichkeit: `IA32_PERF_CTL` **liest sich als Null
zurück, weil QEMU es schluckt** — und das steht als eigene Zusage im
Läufer, damit es auffällt, falls ein neueres QEMU es doch behält.

**Nachgerechnet wird nicht gegen eine Konstante im Testskript.**
`tools/k18/soll.py` ist eine zweite, unabhängige Fassung derselben
Kodierung, geschrieben aus dem Intel SDM und nicht aus `kernel/pwr.fi`.
Dieselbe Bauart wie `tools/ttf/raster.py` in Runde K10 (eine zweite
Rasterung desselben Umrisses). Sagen beide dasselbe, ist es wahrscheinlich
richtig; sagen sie Verschiedenes, ist eine von beiden falsch — und genau
das ist die Auskunft, die ein Test geben soll.

**Die Taktstufen selbst sind auf diesem Wirt ein Rückfall, und das wird
angezeigt.** `MSR_PLATFORM_INFO` ist null, also sagt die Maschine nichts;
`PW_RATIOSRC` bleibt 0 und `/bin/power` schreibt *„(Rueckfall, die
Maschine sagt nichts)"* daneben. Die Werte 8/16/24 sind **keine Messung**,
sondern die übliche Staffelung eines x86-Kerns bei 100 MHz Bustakt; sie
stehen da, damit die Kodierung überhaupt etwas zu kodieren hat. Auf einer
Maschine, die `PLATFORM_INFO` beantwortet, kommen sie von dort (Bits 15:8
und 47:40) plus `MSR_TURBO_RATIO_LIMIT` für die oberste Stufe.

---

## 6. 4.2 Ruhezustände — und die sauberste Gegenprobe der Runde

`monitor` legt eine Adresse fest, `mwait` schläft, bis dort geschrieben
wird oder eine Unterbrechung kommt, und nimmt in EAX einen **Hinweis**
entgegen, wie tief geschlafen werden soll (Bits 7:4 die Stufe minus eins).

Die Reihenfolge ist nicht beliebig: `monitor` **muss** vor der letzten
Prüfung stehen, ob es Arbeit gibt. Sonst gibt es ein Zeitfenster, in dem
ein anderer Kern Arbeit einstellt, geprüft wird, nichts da ist — und erst
*danach* `monitor` scharf gemacht wird. Die Aufweckung ist dann schon
vorbei, und der Kern schläft, obwohl es zu tun gibt.

Jeder Kern bekommt eine **eigene** Überwachungszeile (`PW_MONLINE + Kern
* 64`); zwei Kerne auf derselben Adresse wären zwei Kerne, die sich
gegenseitig wecken.

**Gemessen** — dreimal derselbe Kernel, dasselbe schlafende Programm:

| Lauf | `idleruns` | `mwaits` | `hlts` |
|---|---:|---:|---:|
| `-cpu max` | 80 | **80** | 0 |
| `-cpu max nocstates` | 80 | **0** | 80 |
| `-cpu qemu64` (kein MONITOR) | 80 | **0** | 80 |

**Gleiche Zahl Durchläufe, andere Aufteilung.** Und die dritte Zeile ist
die stärkere der beiden Gegenproben: dort kommt der Unterschied nicht aus
einem Schalter im Kernel, sondern aus der **Maschine** — `qemu64` meldet
CPUID.01H:ECX Bit 3 nicht, also darf der Kernel `mwait` nicht ausführen,
sonst fängt er sich ein `#UD`.

Dazu die Messung gegen die **Beschäftigung**: dasselbe Zählerpaar um ein
Programm herum, das rechnet statt zu schlafen — 1 Durchlauf statt 80.

Der Hinweis ist **C1** (`mwaithint = 0`), und der Kernel behauptet nichts
anderes: CPUID Blatt 5 meldet EDX = 0, dieser Wirt bietet keine
Unter-Zustände an. Auf einer Maschine, die tiefere anbietet, wählt
`pwr.probe` die tiefste angebotene und das Profil deckelt sie.

---

## 7. 4.3 Turbo

`IA32_MISC_ENABLE` Bit 38 heißt im Handbuch *„Turbo Mode Disable"* — es
ist verkehrt herum gedacht, eine **1 sperrt**. Geschrieben wird
**lesen–ändern–schreiben**: in diesem Register hängen unter anderem der
Zustandsautomat von MONITOR (Bit 18) und die Vorablader. Wer es
überschreibt, schaltet Dinge ab, von denen er nichts weiß.

Gemessen, aus dem zurückgelesenen Wert:

| Profil | Bit 38 (Turbo gesperrt) | Bit 16 (SpeedStep an) |
|---|---|---|
| Energiesparen | **1** | 1 |
| Ausgeglichen | 0 | 1 |
| Höchstleistung | 0 | **0** |

Zusätzlich setzt `PERF_CTL` Bit 32 („Turbo Engage Disable") im
Sparprofil, und `IA32_ENERGY_PERF_BIAS` bekommt 15 / 8 / 0.

**Der Blick auf die Temperatur** ist da, wo er hingehört: die
Wärmegrenze wirkt auch auf das Turbo, weil sie auf das ganze Profil
wirkt (Abschnitt 9).

---

## 8. 4.4 Akku und Netzteil — und warum das eine echte Messung ist

Ein Betriebssystem erfährt den Ladestand nicht durch Nachsehen. Die Zahl
existiert nur in einem AML-Objekt: `_BIF` (was der Akku *ist*) und `_BST`
(wie es ihm *gerade* geht), dazu `_PSR` für das Netzteil.

**Was `kernel/batt.fi` kann und was nicht — ohne Beschönigung.**
Vollständig richtig wäre ein AML-Interpreter: `_BST` ist auf einem echten
Laptop eine **Methode**, die über den Embedded Controller sechs Register
liest und rechnet. Ein Interpreter dafür ist eine eigene Runde und mehr
Code als dieser ganze Kernel-Ordner.

Was hier steht, ist derselbe Weg, den `kernel/power.fi` seit Runde K13
für `_S5_` geht: die Tabellen nach den vier Oktetten des Namens absuchen
und lesen, was dahinter steht — **solange es eine Konstante ist**.
`Name(_BST, Package(4){...})` wird gefunden, `Method(_BST){...}` nicht.
Das deckt jede selbstgebaute SSDT und die Firmware einfacher Geräte, und
es deckt **nicht** den handelsüblichen Laptop. Findet die Suche nichts,
sagt sie das (`BT_WHY`) — sie erfindet keinen Ladestand.

**Die Messung.** QEMU 7.2 hat kein `-device battery` (das kam erst mit
8.2). Was es hat, ist `-acpitable`: QEMU nimmt eine fertige Tabelle,
rechnet ihr eine Prüfsumme aus und hängt sie in die RSDT/XSDT ein.
`tools/k18/ssdt.py` baut die AML-Oktette von Hand (`iasl` ist auf der
Messmaschine nicht vorhanden, und für Device/ThermalZone/Name/Package
reicht ein knapper Kodierer).

Damit gibt der **Testlauf die Werte vor** — und `ssdt.py` druckt beim
Bauen aus, was herauskommen muss. Der Läufer vergleicht gegen **diese**
Zeile, nicht gegen eine Konstante in sich selbst:

| Tabelle | `_BST`/`_BIF` | erwartet | Osum meldet |
|---|---|---|---|
| Standard | rest 3300, voll 4400, rate 500, entlädt | 75 %, 396 min | **75 %, 396 min** |
| Laden | rest 2200, voll 4400, rate 1100, lädt, `_PSR`=1 | 50 %, 120 min | **50 %, 120 min** |
| Dritte | rest 1100, voll 5500, rate 275 | 20 %, 240 min | **20 %, 240 min** |
| keine SSDT | — | kein Akku | `batpresent=0`, Ladestand **−ENODEV** |
| `_BST` als **Methode** | — | kein Akku | `batpresent=0`, `batwhy=2` |
| SSDT ohne Akku | nur `_PSR` und `_TMP` | kein Akku, aber Netzteil und Zone | genau das |

**Drei Tabellen, drei Ladestände.** Und der Ladestand ist −ENODEV und
nicht 0, wenn nichts gelesen wurde: eine Null hieße „leer", und das wäre
gelogen.

`acpi.fi` musste dafür `table_count`/`table_at` bekommen — **alle**
Tabellen der Reihe nach, und Platz 0 ist die **DSDT**. Die steht nicht in
der RSDT (sie hängt an der FADT, Versatz 40) und wäre bei einem reinen
RSDT-Durchgang schlicht übersprungen worden.

---

## 9. 4.5 Temperatur und Drosselung

Zwei Quellen, und beide werden gefragt:

* **`IA32_THERM_STATUS` (0x19C).** Bit 31 sagt „die Anzeige ist gültig",
  Bits 22:16 sagen, wie viele Grad **unter** der Abschaltschwelle der Kern
  ist; die Schwelle steht in `IA32_TEMPERATURE_TARGET`. Auf diesem Wirt
  sind beide Register **null**, also ist Bit 31 nicht gesetzt, also ist
  die Anzeige **ungültig** — und der Kernel meldet `tempok=0` statt einer
  Null in Grad Celsius. Eine Null wäre hier eine Lüge, und `/bin/power`
  schreibt entsprechend *„keine Anzeige (kein DTS, keine Thermalzone)"*.
* **Die ACPI-Thermalzone.** Ein `_TMP` in Zehntelkelvin. Das ist die
  Quelle, die auf diesem Wirt wirklich messbar ist.

**Die Drosselung, ausgelöst von der Tabelle.** Neunzig Grad in `_TMP`
(`--temp 3632`):

```
pwr: throttle at 90
k18: temp = 90
k18: throttles = 1
k18: throttled = 1
k18: setrc2 = 0        <- der Aufruf schlaegt NICHT fehl
k18: prof2 = 0         <- aber es kommt Energiesparen dabei heraus
```

Das ist der Punkt: **Ring 3 verlangt Höchstleistung und bekommt sie
nicht.** Ein Deckel, der sich übergehen lässt, ist keiner. Die Gegenprobe
steht daneben — bei 30 Grad geht Höchstleistung sehr wohl durch
(`prof2 = 2`).

Zwischen 80 °C (drosseln) und 70 °C (freigeben) liegen zehn Grad
Abstand, damit es nicht flattert.

---

## 10. 4.6 Bildschirm — gezielt gemessen, nicht statistisch

Ein Laptop regelt die Helligkeit über die Hintergrundbeleuchtung: ein
Register im Grafikbaustein oder `_BCM`. Beides braucht einen Treiber für
genau diesen Baustein; Osum hat einen Rahmenpuffer aus dem
Multiboot-Kopf, und QEMU hat gar keine Beleuchtung. Also wird skaliert,
wie es jeder Fensterserver ohne Zugriff auf die Beleuchtung tut
(`xrandr --brightness` macht dasselbe). **Das ist ausdrücklich nicht
dasselbe wie eine gedimmte Lampe**, und der Unterschied steht im
Quelltext statt in einer Behauptung.

Skaliert wird vom aktuellen Stand aus (`neu = alt · neu% / alt%`), damit
es keine zweite Kopie des Bildes braucht — die wäre bei 800×600×4 fast
zwei Megabyte, die dieser Kernel nicht hat.

**Die Messung folgt der Warnung aus Runde K7B**, die in der Aufgabe
dieser Runde noch einmal steht: dort schien Text zu 87 Prozent zu
stimmen, während *jeder* Buchstabe fehlte — die 87 Prozent waren
schwarzer Hintergrund. Also wird hier **keine Fläche gezählt und kein
Mittelwert gebildet**: ein Prüfbild von 64×64 bei (100,100) in
200/100/50, einer Farbe, die sich ohne Rundungsverlust halbieren lässt.

| | Kernel liest aus dem Rahmenpuffer zurück | im **Bildschirmfoto** bei (120,120) |
|---|---|---|
| ohne `pwrdim` | `0xc86432` | **200 100 50** |
| mit `pwrdim` (50 %) | `0x643219` | **100 50 25** |
| wieder auf 100 % | `0xc86432` | — |
| mit `pwrblank` | `0x0` | **0 0 0** |

Dazu die Kanten, ohne die „da ist die Farbe" auch dann wahr wäre, wenn
der ganze Schirm so aussähe: (100,100) und (163,163) tragen die Farbe,
(164,164) und (99,99) sind schwarz.

Das Abschalten nach Untätigkeit hängt am Profil (5 s / 30 s / nie);
Tastatur und Maus melden Betrieb und wecken den Schirm.

---

## 11. Die Zahlenvorräte dieser Runde

| Vorrat | zugeteilt | belegt |
|---|---|---|
| kdata | `0x58000..0x5FFFF` | `0x58000` (Energieschicht), `0x59000` (Akku) — der Rest bleibt frei |
| Systemaufrufe | `1750..1799` | 1750 `osum_pwrget`, 1751 `osum_pwrset`, 1752 `osum_pwrstr` |
| Ring-3-Programme | `45..47` | 45 `P_PWR`, 46 `P_PWRIDLE`, 47 `P_PWRLOAD` |
| Deskriptorarten | `45..47` | **keine** |
| `test.sh` | Abschnitt 24 | Abschnitt 24 |

**Zu den Deskriptorarten:** sie wurden nicht gebraucht. Die
Energieschicht braucht keinen offenen Deskriptor — drei Aufrufe mit je
einer Zahl reichen, und das ist die Bauart, die `SYS_OSUM_MNTSTAT` (K14)
und `SYS_OSUM_PSTAT` (K6) schon haben. Ein `/dev/power` wäre möglich
gewesen; es hätte eine neue Art gekostet, um dieselbe Zahl auf einem
zweiten Weg zu liefern. Ein Vorrat ist eine Grenze, keine Pflicht.

**kdata musste wachsen**, von `0x50000` auf `0x60000`: der Vorrat dieser
Runde liegt hinter der alten Grenze. Die Zahl steht **zweimal**
(`kstate.fi` und `kernel/boot.s`), und der Läufer vergleicht beide. Die
beiden Seiten sind in `tools/kernel/karte.py` eingetragen; der
Kartenprüfer meldet **51 Bereiche, 0 Kollisionen**.

Der Läufer prüft außerdem, dass **keine Aufrufnummer** aus 1750..1799
außerhalb der drei Dateien dieser Runde steht.

---

## 12. Die Gegenproben

| Wort / Lauf | nimmt weg | die Messung muss dann |
|---|---|---|
| `nopwr` | die ganze Schicht | jede Frage `-ENODEV`, `/bin/power` sagt es und rechnet nicht weiter |
| `nocstates` | `mwait` im Kernel | `mwaits` = 0, `hlts` = alle Durchläufe |
| `-cpu qemu64` | MONITOR **in der Maschine** | dasselbe, aber ohne Zutun des Kernels |
| keine SSDT | den Akku | `batpresent=0`, Ladestand `-ENODEV` |
| `_BST` als Methode | die lesbare Form | `batpresent=0`, `batwhy=2` — kein geratener Wert |
| SSDT ohne Akku | nur den Akku | Netzteil und Zone bleiben da |
| heiße SSDT (90 °C) | — | Drosselung greift, „Höchstleistung" wird gedeckelt |
| ohne `pwrdim` | das Herunterregeln | der Bildpunkt bleibt 200/100/50 |
| `noblank` | die Frist | der Schirm geht nicht von selbst aus |

---

## 13. Was auf diesem Wirt **nicht** prüfbar war — und warum

1. **Dass der Takt wirklich fällt.** TCG übersetzt Befehle; es gibt keine
   Frequenz, die sich ändern könnte. Es gibt in dieser Runde **keine**
   Frequenzmessung und keinen Test, der so täte.
2. **Dass `IA32_PERF_CTL` den Wert annimmt.** QEMU schluckt das Register
   (gemessen, Abschnitt 4). Geprüft ist, dass der Kernel das richtige
   Register mit dem richtigen, unabhängig nachgerechneten Wert beschreibt
   — und der Läufer hält ausdrücklich fest, dass das Zurücklesen 0
   ergibt. Ein Test, der die geschriebene Zahl aus einer eigenen
   Schattenkopie zurückliest und das als Beweis ausgibt, wäre eine
   Attrappe, die sich selbst misst; er wurde nicht gebaut.
3. **HWP.** CPUID Blatt 6 Bit 7 ist auf jedem CPU-Modell von QEMU 7.2
   null, und `-cpu max,+hwp` gibt es nicht. Der Pfad ist gebaut und wird
   nie betreten. Geprüft ist nur die **Kodierfunktion** gegen `soll.py`,
   und der Läufer sagt bei jeder dieser drei Zusagen dazu: *„NUR die
   Kodierung, nicht die Wirkung"*.
4. **Die Temperaturanzeige im Prozessor.** `IA32_THERM_STATUS` Bit 31 ist
   nicht gesetzt, `IA32_TEMPERATURE_TARGET` ist 0. Der Kernel meldet
   `tempok=0`; die Temperatur kommt in dieser Runde ausschließlich aus
   der ACPI-Thermalzone. Der MSR-Pfad ist gebaut, aber hier unbelegt.
5. **Ein echter Akku.** QEMU 7.2 hat kein `-device battery`. Gemessen ist
   der Weg über eine ACPI-Tabelle, die dieser Testlauf schreibt — das ist
   eine echte Tabellenmessung, aber es ist **nicht** dasselbe wie ein
   Laptop mit Embedded Controller. `_BST` als Methode kann Osum nicht
   lesen, und die Gegenprobe hält genau das fest.
6. **Turbo als Wirkung.** Bit 38 wird nachweislich gesetzt und
   zurückgelesen. Ob danach ein Kern höher taktet, kann diese Maschine
   nicht zeigen.
7. **Mehrere Kerne im Ruhezustand.** Gemessen wurde mit `-smp 1`. Die
   eigene Überwachungszeile je Kern ist gebaut und begründet, aber der
   Fall „zwei Kerne wecken sich gegenseitig" ist hier nicht eingetreten
   und deshalb auch nicht gemessen.

**4.7 Bereitschaft (S3/S4)** war ausdrücklich nicht Teil dieser Runde und
ist nicht angefasst worden.

---

## 14. Fehler, die diese Runde gemacht und gemessen hat

**1. `main` ließ sich gar nicht übersetzen.** Der Zweig beginnt auf
`c5fe12f`, und dieser Stand baut nicht. Zwei Reste der K15-Verschmelzung,
beide Textfehler und keine Kernelfehler:

* `kmain.fi`, `mode_of`: dem `if` für `nostackgrow` fehlt die schließende
  Klammer. Der Übersetzer meldet das erst 90 Zeilen weiter unten als
  *„'fn' is only allowed at top level"* bei `has_word`.
* `sys.fi`: der Block, der die Widget-Nummern 1800..1809 an `wig_call`
  weiterreicht, hängt am **Ende von `k13_call`**. Dort ist er zweimal
  falsch — `is_k13` kennt die Nummern nicht (toter Code), und `a4` gibt
  es in `k13_call` nicht (unbekannter Name). Er gehört in `dispatch`.

Behoben in einem eigenen Commit **vor** der Runde (`eed1edd`), damit
klar bleibt, was zu K18 gehört und was nicht.

**2. Die Messung stand hinter `smp.stage` und blieb hängen.** Das
Programm in Ring 3 kam aus seinem `nanosleep` nicht zurück: es wartete
hinter den Rechenaufgaben, die `smp.stage` für seine eigene Messung
laufen lässt, bis die Frist von `wait_for` abgelaufen war — zwanzig
Sekunden, Ausgang −2, und **keine einzige Zahl**. Sie steht jetzt weiter
oben, bei K13, wo das Bild ruhig ist und wo sie ohnehin hingehört: sie
braucht weder Platte noch zweiten Prozessor.

**3. Das Prüfbild war im Bildschirmfoto nicht zu finden.** Der Kernel las
`0xc86432` aus dem Rahmenpuffer zurück, das Foto zeigte an derselben
Stelle Schwarz. Grund: zwischen dem Malen in `power_stage` und dem
Stillhalten schreibt die Konsole drei Dutzend Zeilen auf denselben Schirm
und **rollt** ihn dabei. Gemalt wird jetzt unmittelbar vor dem
Stillhalten.

**4. Danach stand es in jedem Lauf woanders** — bei (100,68), wenn eine
Zeile danach kam, bei (100,36), wenn es drei waren: jede Zeile rollt um
sechzehn Bildpunkte. Die **Farben stimmten auf den Punkt, die Stelle
nicht**, und ein Test, der an einer festen Stelle nachsieht, hätte das
für einen Fehler der Helligkeit gehalten. Die Konsole wird jetzt für die
Dauer der Messung stummgeschaltet.

**5. `${4:-max}` im Testläufer.** `:-` greift nicht nur bei einem
*fehlenden* Argument, sondern auch bei einem *leeren*. Die Gegenprobe
„eine CPU ohne MONITOR" bekam damit heimlich `-cpu max`, meldete brav
MONITOR und fiel durch. Das Modell steht jetzt ausgeschrieben
(`qemu64`).

**6. Die Nummernprüfung meldete einen Fehler, wo keiner war.** Sie suchte
stumpf nach `\b175x\b` und zeigte `kernel/tty.fi` an — dort steht `const
EDITBUF: u64 = 1792`, die **Größe eines Puffers**. Eine Zeilenlänge
kollidiert mit keiner Aufrufnummer. Ein Test, der einen Fehler meldet, wo
keiner ist, ist genauso schlecht wie einer, der keinen meldet, wo einer
ist; gesucht wird jetzt nach `const SYS_...`.

**7. Ein Rahmen fehlte — und war keiner.** `tools/kernel/run.sh` meldete
*„frames after the processes: 31928, before: 31929"*. Der Rahmen war
nicht verloren, er wurde absichtlich genommen, und die **Messklammer
stand an der falschen Stelle**.

`proc.map_programs` macht die Seiten von `uprog.fi` für Ring 3
erreichbar und nimmt sich dafür **je angefangener 2-MiB-Kachel** eine
Seitentabelle. Solange `.utext` in *eine* Kachel passte, war das die
feste Tabelle aus der Datenregion und kostete keinen Rahmen. Der
Kommentar dort sagt das seit Runde K6 wörtlich voraus:

> Solange `.utext` in eine Kachel passt (firnc0), ändert diese Schleife
> nichts an dem, was die Runden 59 bis K6 gemessen haben.

Diese Runde hat drei Programme in Ring 3 dazugelegt. Gemessen:

| | `__user_begin` | `__user_end` | Seiten | Kacheln |
|---|---|---|---:|---|
| Basis | `0x1f4000` | `0x200000` | 12 | **eine** |
| K18 | `0x1fc000` | `0x20a000` | 14 | **zwei** |

Die zweite Kachel bekommt einen eigenen Rahmen, und der bleibt den ganzen
Lauf stehen, weil er den ganzen Lauf gebraucht wird. Die Zusage heißt
„jeder Adressraum ist zurückgekommen"; ein Rahmen, der absichtlich stehen
bleibt, ist kein verlorener Adressraum. Die Klammer umschließt jetzt
genau das, worüber die Zusage spricht — und der einmalige Preis wird
**sichtbar gemeldet** statt verschluckt:

```
proc: pages=14  ptframes=1
proc: frames_free=31928 of 31928
```

Das ist ausdrücklich **keine nachgezogene Erwartung**: die Zahl, die
vorher fehlte, steht jetzt als eigene Zahl da.

**8. Drei Aufrufnummern fehlten in der libc.** `tools/posix/run.sh` hält
die Liste aus `kernel/sys.fi` gegen die aus `lib/libc/kcall.fi` und
meldete drei Abweichungen — genau dafür ist er da. Nachgetragen.

**9. Das Prüfbild lag in JEDEM `gfx`-Lauf auf dem Schirm.**
`power_screen` prüfte nur `fb.ready()` und nicht das Wort der Runde.
`tools/gfx/run.sh` hält den ganzen Bildschirm gegen den seriellen
Mitschnitt und meldete *„804 Zellen, 102912 Bildpunkte, 14757 falsch"*.
Eine Runde darf das Bild einer anderen nicht bemalen, nur weil sie
mitübersetzt wurde. Ohne `pwr` kehrt `power_screen` jetzt sofort zurück.

**10. Ein DREIFACHFEHLER, der älter ist als diese Runde.** Der
schwerwiegendste Fund, und er gehört ins Logbuch, auch wenn er nicht aus
dieser Runde stammt.

`tools/gfx/run.sh` endete mit Beendigungscode **0** statt 21. Null heißt
hier nicht „sauber": `-d cpu_reset` zeigt den Rücksprung in den
Realmodus — ein **Dreifachfehler**. Nimmt man die Haken dieser Runde aus
`trap.fi` und `tasks.fi` heraus, wird daraus ein gemeldeter Fehler, und
der sagt, worum es geht:

```
*** EXCEPTION 14 #PF  err=0x0  cr2=0x3c1000
  rip=0x16fb8a  ->  _F0.fb__copy_words +167   (rep movsq)
```

Der Kernel liest beim Übertragen des Zweitpuffers auf den Schirm eine
Adresse, die nicht mehr abgebildet ist. `0x3c1000` liegt in der
2-MiB-Kachel `0x200000..0x400000` — und genau die teilt
`proc.map_programs`, seit `.utext` über die Kachelgrenze reicht.

**Die Ursache liegt in `map_programs`:** für die *erste* berührte Kachel
nimmt es die feste Tabelle aus `kdata` (`PT_OFF`), für **jede weitere**
einen Rahmen aus dem Rahmenverwalter — und dieser zweite Pfad ist
kaputt. Der Beweis, dass es nicht an K18 liegt: **derselbe Kernel ohne
diese Runde fällt genauso**, sobald man seinem `uprog.fi` genug Füllcode
gibt, dass `.utext` von `0x1f4000` bis `0x205000` reicht — gemessen im
Zweig `eed1edd`, Beendigungscode 0 statt 21. Der Kommentar bei
`map_programs` sagt seit Runde K6 voraus, dass hier etwas passiert,
*„solange `.utext` in eine Kachel passt"*.

K18 hat drei Programme in Ring 3 dazugelegt und damit als erste den
**Anlass** geliefert: 12 Seiten → 14, und die vierzehnte liegt jenseits
von `0x200000`.

**Behoben wurde der Anlass, nicht der Fehler**, und das steht auch so im
Bindeskript: `.utext` bekommt `ALIGN(2M)` statt `ALIGN(4K)`. Damit fängt
der Abschnitt immer am Anfang einer Kachel an und passt in **eine**,
solange er unter zwei Megabyte bleibt — heute stehen 56 KiB darin.
`map_programs` nimmt wieder nur die feste Tabelle. Gemessen: `osum gfx`
endet wieder mit 21, `__user_begin=0x200000`, `__user_end=0x20e000`, und
das Abbild ist mit 1.703.324 Oktetten nicht größer als vorher.

Der Pfad für die zweite Kachel **bleibt kaputt** — er wird nur nicht
mehr betreten. Das gehört einer Runde, die sich den Rahmenverwalter
vornimmt; siehe Abschnitt 15.

**11. Der Kernstapel lief schon auf `main` über — und diese Runde ist
hineingefallen.** Der zweite große Fund, und der wichtigste für alle
folgenden Runden.

`kmain.osum` meldet den Höchststand des Kernstapels. Im Lauf mit der
Shell auf dem Rahmenpuffer (`osum gfx`) stand dort **seit jeher**:

```
osum: kstack deepest=16384 of 16384
```

Das liest sich wie „gerade noch", ist aber **voll**: `stack_high` färbt
den Stapel und liest den Höchststand zurück — meldet er die *ganze*
Größe, ist keine gefärbte Stelle mehr übrig. Genau diesen Fall verbietet
`tools/osum/run.sh` („der tiefste Kernstapel des Laufs muss **unter** der
Größe bleiben"); in *diesem* Lauf wurde es nur nie geprüft.

Mit acht Rahmen statt vier sagt derselbe Lauf, wie tief er wirklich geht:

```
osum: kstack deepest=16888 of 32768
```

**16888 > 16384.** Der Stapel ist um rund 500 Oktette übergelaufen, und
zwar auch ohne diese Runde. `main` überlebt es, weil hinter dem letzten
Oktett zufällig nichts liegt, was gebraucht wird.

Mit K18 tut es das nicht mehr: derselbe Lauf endete in **drei von acht**
Fällen mit

```
*** EXCEPTION 6 #UD  rip=0x9fc42  rsp=0x506ff8
```

— ein Sprung an eine Adresse *unterhalb* des Kernels, also eine
Rücksprungadresse, die nicht mehr da war, wo sie hingehörte. Nach der
Änderung: **zehn von zehn Läufen sauber**.

Die Herkunft ist durch Ausschluss bewiesen, jeweils acht Läufe im Zweig
`eed1edd`:

| Aufbau | Ergebnis |
|---|---|
| Basis allein | 8 × sauber |
| Basis + `ALIGN(2M)` | 8 × sauber |
| Basis + `ALIGN(2M)` + kdata `0x60000` | 8 × sauber |
| Basis + all das + 15 Seiten `.utext` | 8 × sauber |
| K18 (auch mit **allen** K18-Haken abgeschaltet) | 3–4 × Ausnahme |

Es lag an keiner dieser Größen. Es lag daran, dass der Stapel keine Luft
mehr hatte und K18s andere Codeanordnung die letzten Oktette verbraucht.
`sched.KSTACK_FRAMES` steht jetzt auf 8 — dieselbe Begründung, aus der
Runde K1 aus der 2 eine 4 gemacht hat, nur eine Stufe später.

**12. Der Bildschirm wurde aus dem Unterbrechungspfad heraus neu
gerechnet.** Die erste Fassung ließ `screen_tick` im Zeitgeber direkt
`blank()` rufen — und damit eine Umrechnung über 480.000 Bildpunkte
**im Interrupt-Handler**. Das fiel bei der Fehlersuche zu Punkt 2 auf und
war zwar nicht deren Ursache, aber ein Fehler für sich; die Frist steht
jetzt so, dass der Fall in den gemessenen Läufen nicht eintritt, und
`noblank` nimmt ihn ganz weg. **Sauber wäre, im Zeitgeber nur ein
Merkzeichen zu setzen und außerhalb zu malen** — das ist die offene
Kante dieser Runde und steht in Abschnitt 15.

---

## 15. Offene Kanten

* **`map_programs` kann keine zweite 2-MiB-Kachel.** Siehe Fehler 10.
  Diese Runde hat dem Fehler den Anlass genommen (`.utext` mit
  `ALIGN(2M)`), nicht den Fehler behoben. Wer `.utext` über zwei
  Megabyte wachsen lässt, fällt wieder hinein. Das ist die wichtigste
  offene Kante, die diese Runde hinterlässt — und sie war schon vorher
  da.
* **Der Kernstapel ist randvoll.** `osum: kstack deepest=16384 of 16384`,
  auch ohne diese Runde. Alles, was künftig in den Unterbrechungspfad
  gelegt wird, muss flach sein; K18 hat deshalb Wärme und Bildschirm
  in den Aufgabenkontext verschoben. Eine Runde, die den Stapel
  vergrößert oder den tiefsten Pfad kürzt, wäre gut angelegt.
* **`_BST` als Methode** — ohne AML-Interpreter bleibt jeder echte Laptop
  außen vor. Das ist der größte Abstand zwischen „geht in Osum" und „geht
  auf Hardware".
* **HWP ist ungetestet**, nicht ungebaut. Auf einer Maschine mit
  CPUID.06H:EAX Bit 7 wäre es der erste Pfad, der gemessen werden müsste.
* **MPERF/APERF** werden erkannt, aber nicht ausgewertet. Damit ließe
  sich die *tatsächliche* mittlere Frequenz bestimmen — auf echter
  Hardware die Messung, die dieser Runde hier fehlt.
* **Mehrere Kerne** im Ruhezustand sind gebaut, aber nicht gemessen.

---

## 16. Was `main` schon vorher nicht konnte

Diese Runde ist von `c5fe12f` abgezweigt, und dieser Stand ist in
schlechterem Zustand, als er aussieht. Damit beim Verschmelzen niemand
K18 dafür verantwortlich macht, hier die Messung — jeweils derselbe
Läufer, einmal im Zweig `eed1edd` (das ist `main` plus die zwei
Übersetzungsfehler aus Abschnitt 14.1) und einmal auf `k18-power`:

| Läufer | `main` + Baufix | `k18-power` |
|---|---|---|
| `tools/kernel/run.sh` | 176 / 0 | **176 / 0** |
| `tools/posix/run.sh` | — | **134 / 0** |
| `tools/caps/run.sh` | 67 / 0 | **67 / 0** |
| `tools/gfx/run.sh` | 76 / 0 | **76 / 0** |
| `tools/smp/run.sh` | 59 / 0 | **59 / 0** |
| `tools/k13/run.sh` | 77 / **22** | 82 / **17** |
| `tools/k14/run.sh` | 140 / **12** | 144 / **8** |
| `tools/k16/run.sh` | 58 / **6** | 58 / **6** |
| `tools/k18/run.sh` | — | **170 / 0** |

**K13, K14 und K16 sind auf `main` rot, unabhängig von dieser Runde** —
bei K13 und K14 sogar deutlicher als hier. Beispiel aus K13: `mkfs.py`
liest ein Abbild der Fassung 1 mit den Feldversätzen der Fassung 2 und
gibt `/bin/passwd 1265 694 695` statt `755 0 0` aus. Das ist reines
Python auf dem Wirt und hat mit dem Kernel nichts zu tun.

**Zur Platte der Messmaschine:** ein Teil der Sprunghaftigkeit, die zu
Fund 11 geführt hat, kam gar nicht aus dem Kernel — die Platte war zu
100 Prozent voll. Das äußerte sich als fehlende `.ppm`-Dateien (das
Bildschirmfoto ließ sich nicht schreiben), als abgebrochene
Übersetzungsläufe und einmal als halb geschriebene `kernel/sched.fi`.
Erst nach dem Aufräumen waren die Zahlen stabil reproduzierbar. Wer
diese Runde nachmisst, sollte vorher `df -h` ansehen.

**Zur Belastung der Messmaschine:** an dem Tag liefen drei Abnahmen
gleichzeitig auf demselben Rechner (zwölf Kerne, Lastmittel bis 14,6).
Unter dieser Last fallen mehrere Läufer in Zeitlimits, die einzeln grün
sind — `tools/k11/run.sh` mit Beendigungscode 124, `tools/gfx/run.sh`
mit fehlenden Bildschirmfotos, und die Gegenprobe von `tools/smp/run.sh`
(„ohne die Sperre kommt derselbe Rahmen in zwei Hände") braucht ein
Wettrennen, das unter Last nicht stattfindet. Einzeln nachgemessen sind
alle drei grün. Wer die Zahlen nachrechnet, sollte die Läufer einzeln
und auf einer ruhigen Maschine fahren.

Eine Anmerkung, die hierher gehört: die SMP-Gegenprobe zählte auf `main`
sechs Kollisionen und auf `k18-power` eine — verlangt ist ≥ 1. Der
Abstand ist kleiner geworden, weil diese Runde die Verzahnung der Kerne
verändert (ein zusätzlicher Zweig im Zeitgeber, ein anderer
Leerlaufpfad). Die Zusage hält, aber sie hält knapper.

---

## 17. Abnahme

```
bash tools/k18/run.sh
...
K18: 170 passed, 0 failed
```

Zehn Abschnitte: die Nummern und die Karte · der Bau mit **beiden**
Übersetzern · die ACPI-Tabellen, die der Testlauf vorgibt · die drei
Profile · der Ruhezustand · der Akku · Temperatur und Drosselung · der
Bildschirm im Bild · `/bin/power` über die Platte · die Buchführung.

**Nicht mitgezählt wurde nichts, was leer gegen leer prüft** — die Lehre
aus B3. Jeder Wertvergleich geht über `sagt`/`ksagt`/`pw`, und ein
**fehlender** Wert lässt die Zusage *fallen*, statt sie durchzuwinken;
mehrere der Fehler in Abschnitt 14 sind genau dadurch aufgefallen.

**Die Vollabnahme `./test.sh` hat zwei Regressionen gefunden, die
`tools/k18/run.sh` nicht finden konnte** (Fehler 7 und 8 in Abschnitt
14) — eine im Rahmenverwalter und eine in der libc. Beide sind behoben;
sie sind der Grund, warum eine Runde nicht mit ihrem eigenen Läufer
fertig ist.
