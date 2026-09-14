# Runde ACPI-EREIGNISSE — der Weg vom Knopf zum Kern

**Zweig:** `acpi-ereignisse` · **Grundlage:** `main` = `cb3a68a` · **Datum:** 14.09.2026
**Punkt der Offenliste:** `K-003` („ACPI nur Tabellen + S5 — kein AML-Interpreter,
keine Ereignisse (Deckel, Einschalttaste)")

---

## 1. Worum es ging

Osum konnte sich seit Runde K13 **abschalten**: `power.acpi_off` liest die FADT,
sucht `_S5_` in der DSDT und schreibt den Schlafwert in `PM1a_CNT`. Runde ENERGIE
hat den Knopf dazu gebaut. Der Weg **vom Knopf zum Ausschalten** war fertig.

Was fehlte, war der Weg **vom Hardware-Ereignis zum Knopf**. Wer auf einem Laptop
die Einschalttaste drückt, schaltet damit nichts ab — er zieht eine Leitung, den
SCI. Was danach passiert, ist Sache des Betriebssystems, und wenn es nichts tut,
passiert nichts.

Schlimmer noch, und es stand seit Runde BLECHVIER in `kernel/hw.fi`: weil dieser
Kern die GPE-Methoden nicht ausführen **konnte**, hat er beim Start **alle**
GPE-Bits abgeschaltet. Das war richtig — ein Ereignis, dessen Statusbit nie
gelöscht wird, hält die Leitung dauerhaft gezogen und die Maschine steht in einem
Unterbrechungssturm. Aber es hieß eben auch: kein Deckel, keine Taste, kein Akku.

---

## 2. Zuerst der Zweig `aml` — und was er schon konnte

Der Auftrag sagte: **prüfe zuerst, was dort steht.** Das Ergebnis war eindeutig.

Der Zweig `aml` (`2cfdd26`, 30.08.2026) bringt einen **echten** AML-Interpreter
mit: vier Dateien, 4024 Zeilen, Namensraum mit der Suchregel der Spezifikation,
Operationsregionen für SystemMemory/SystemIO/PCI_Config, Felder, Ausdrücke,
`If`/`Else`/`While`/`Return`, Methodenaufrufe mit `Arg`/`Local`, `CreateXField`,
Schritt- und Tiefengrenzen. Er wertet QEMUs `_PRT` aus — und das ist dort **keine
Tabelle, sondern eine Methode** mit einer `While`-Schleife über 128 Durchläufe,
veränderbaren Paketen, `Index`, `ShiftLeft`, `And`, `Or` und Verweisen auf fünf
Link-Geräte, deren `_CRS` wiederum eine zweite Methode ruft, die im Rumpf einen
Puffer anlegt und ein PIIX3-Register aus dem PCI-Konfigurationsraum liest.

**Er wurde hereingeholt, nicht nachgebaut.** Sein Testlauf (`tools/aml/run.sh`)
läuft auf diesem Zweig weiter: **52 von 53 Zusagen grün** beim ersten Versuch.

### Die eine rote — und zwei Kollisionen, die kein Textverschmelzer sehen konnte

Der Zweig ist von `b010f75` abgezweigt und damit **zwei Wochen hinter main**. Vier
Konflikte, zwei davon echte Kollisionen — genau die Sorte, für die dieses Projekt
`tools/kernel/memmap.py` gebaut hat:

| Was | Der Zweig nahm | In main liegt dort | Jetzt |
|---|---|---|---|
| Modusbits | Wort 11 ab Bit 0 (704…712) | `M_ASYNC`…`M_ASTRESS` (Runde ASYNC), `M_MODUL`/`M_MODULAUS` | Wort 12 ab Bit 4 (772…780) |
| Seite in `kdata` | `AML_OFF` = 0x85000 | `ROOT_OFF` (Runde ROOTSEL) | 0xF2000 |
| Kernstapel | 65536 → 131072 | steht längst auf 262144 | bleibt 262144 |

Die Modusbits hätten bedeutet: `aml` auf der Kommandozeile schaltet den
Asynchronweg mit ein. Die Seite hätte bedeutet: der Interpreter schreibt in die
Skalare von `rootsel.fi`. **Beide Zweige waren für sich grün**, keine gemeinsame
Zeile — der Textverschmelzer konnte nichts sehen. `memmap.py` hat die zweite
gefunden, die rote Zusage von `tools/aml/run.sh` die erste.

---

## 3. Das Pflichtenheft — gemessen, nicht geschätzt

Ein vollständiger AML-Interpreter ist eine Lebensaufgabe. Die Frage war deshalb
nicht „wie baut man einen", sondern **welchen Ausschnitt brauchen Einschalttaste,
Deckel und Akku**. Dieselbe Methode wie beim Assembler: nicht raten, welche
Befehle vorkommen könnten, sondern die Tabellen nehmen, die es gibt, und zählen.

`tools/aml/asl/lid.asl` und `hart.asl` sind Laptop-Tabellen als ASL, nach ACPI 6.4
Kapitel 9.4 (`_LID`), 10.2 (`_BST`/`_BIF`/`_BIX`) und 5.6.4 (die GPE-Methoden).
`hart.asl` ist die Fassung, die weh tut: eingebetteter Controller mit
`EmbeddedControl`-Region und `_REG`, Mutex mit `Acquire`/`Release`, serialisierte
Methoden, `Sleep`, `Stall`, `CondRefOf`, `Divide` mit zwei Zielen, `SizeOf`,
`Concatenate`, `_OSI`, ein `While` in einer GPE-Methode.

`tools/aml/pflichtenheft.py` übersetzt sie mit `iasl`, lässt den **unabhängigen**
Leser aus `tools/aml/disasm.py` darüber laufen und hält das Ergebnis gegen die
Kann-Liste — die nicht abgeschrieben, sondern aus `kernel/aml.fi` (`report_can`)
**abgelesen** wird.

```
KANN-Liste             101 Opcodes (79 einfach, 19 erweitert, 3 Paare)
lid.aml                 26 verschiedene Opcodes, Abdeckung 100 %
hart.aml                42 verschiedene Opcodes, Abdeckung 100 %
laptop.aml              24 verschiedene Opcodes, Abdeckung 100 %
zusammen                43 verschiedene, NICHT ABGEDECKT: keine
```

**Für Einschalttaste, Deckel und Akku fehlt kein einziger Opcode.** Was fehlt,
liegt nicht in der Sprache, sondern in der Umgebung:

* der Adressraum **`EmbeddedControl`** — `kernel/amlobj.fi` kennt SystemMemory,
  SystemIO und PCI_Config, und auf einem Laptop stehen Deckel und Akku hinter dem
  eingebetteten Controller;
* **`_OSI`** als aufrufbare Methode (die Firmware fragt, wer da läuft, und
  schaltet danach ganze Zweige der DSDT frei oder tot);
* und vor allem **der ganze Weg SCI → GPE → `_Lxx` → `Notify`**, den diese Runde
  gebaut hat.

---

## 4. Was gebaut wurde

`kernel/acpiev.fi`, rund 1200 Zeilen:

* **`acpi_mode_on`** — die Umschaltung in den ACPI-Modus (siehe 5.1).
* **`irq`** — der SCI-Behandler. Er liest die Statusregister, **löscht** sie und
  merkt vor. Mehr nicht. **Erst löschen, dann behandeln**: andersherum geht ein
  Ereignis verloren, das während der Methode eintrifft — bei einem Deckel, den
  man schnell zu- und aufklappt, der Unterschied zwischen „gesperrt" und
  „gesperrt und bleibt es".
* **`pump`** — hier läuft AML, **nicht im Behandler**. Eine `_Lxx`-Methode darf
  `Sleep` rufen, einen Mutex nehmen und über den Embedded Controller lesen; das
  dauert Millisekunden. Derselbe Aufbau wie `ehci.poll` und `gfx.disp_poll`.
* **`collect_gpe`** — sammelt `\_GPE._Lxx`/`_Exx` und schaltet **genau die** Bits
  scharf, für die es eine Methode gibt. Alles andere bleibt aus, wie seit
  BLECHVIER.
* **`handle_notify`** — ordnet `Notify(Gerät, Code)` zu und fragt danach `_LID`,
  `_BST`/`_BIF` oder `_PSR` ab.
* **`selftest`** (`evself`) — rechnet nach, was ohne Hardware prüfbar ist.

Dazu:

* `amlev.fi`: **`Notify` merkt sich, WELCHES Gerät und WELCHEN Code**, nicht nur
  wie oft. Ein **Ring** von 16, weil eine einzige GPE-Methode mehrere `Notify`
  absetzen darf.
* `aml.fi`: **`ns_hold`/`ns_drop`/`eval_node`**. Der Namensraum wird **nur
  gehalten, wenn es etwas zu halten gibt** — ein Server ohne Deckel und ohne Akku
  zahlt keine 256 KiB für nichts.
* `sys.fi`: zehn Felder an `osum_pwrget`. `PG_EVCHANGE` und `PG_BTN` **leeren, was
  sie lesen** — sonst ginge ein Ereignis zwischen zwei Abfragen verloren, oder das
  Energiemenü ginge immer wieder auf.
* `taskbar.fi`: Akku auf Ereignisse, Warnung bei 20 % und 10 % über
  `wlib.noti_post`.
* `launcher.fi`: die Taste öffnet das **Energiemenü** — wer sie aus Versehen
  streift, soll nicht seine offenen Fenster verlieren.

---

## 5. Die fünf Fehler, die die Messung gefunden hat

Jeder davon sah aus wie „es funktioniert nicht", und jeder hatte eine andere
Ursache. Sie stehen hier, weil sie zusammen die Runde sind.

### 5.1 Der ACPI-Modus war nie eingeschaltet

Die erste Fassung trug die SCI-Leitung ein, schaltete die GPE-Bits scharf, gab die
Taste frei — und zählte nach `system_powerdown` **genau null** Unterbrechungen
(`irqs=0`, bei richtigem `pm1a=0x600`).

**Ein x86 startet im Legacy-Modus.** Solange `SCI_EN` (Bit 0 von `PM1a_CNT`) nicht
steht, gehen Taste, Deckel und Akku als **SMI an die Firmware** und nicht als SCI
an das Betriebssystem. Der Weg hinüber ist ein Schreibzugriff (ACPI 6.4, 16.3.2):
der Wert aus `ACPI_ENABLE` auf den Anschluss aus `SMI_CMD`, danach auf `SCI_EN`
warten. `SMI_CMD == 0` ist **kein Fehler** — dann gibt es keinen Legacy-Modus.

### 5.2 Die PM1-Register brauchen echte 16-Bit-Zugriffe

Danach: immer noch `irqs=0`. Der Grund stand im Register selbst — geschrieben
wurde ein Wort als **zwei Oktette**, und der Chipsatz verwarf es **still**.
Zurückgelesen stand in `PM1a_EN` (Anschluss 0x602) weiter `0x0000`, die Taste war
also nie freigegeben. Mit `arch.dev_out16` steht `0x0100` darin.

Gemessen, nicht vermutet: die Runde hat den Wert **vor und nach** dem Schreiben auf
die Leitung gelegt, bis der Unterschied dastand.

### 5.3 Der Messlauf selbst war der dritte Fehler

Der Abnahmekern läuft mit `-device isa-debug-exit` und ist bei `kernel: done`
fertig, **bevor** die Leerlaufaufgabe — in der `pump` steht — je drankommt. In der
Ausgabe sah das aus wie „der SCI kommt nicht an"; in Wahrheit war der Kern schon
aus, als die Taste gedrückt wurde. `acpiev.wait_loop` (`evwait`) hält ihn so lange
an, wie die Messung braucht.

### 5.4 `_BIF` wurde nie gelesen

Deckel und Netzteil gingen, der Ladestand blieb 0. In der Ausgabe:

```
acpiev: bst node=366 typ=4 n=4 rem=3850 full=0
```

`_BST` **lief**, das Paket stimmte, die Restkapazität war auf das Oktett genau
die, die die AML-Methode ausgerechnet hatte (77 × 50 = 3850) — und die Prozentzahl
blieb 0, weil der **Nenner** fehlte. Die Spezifikation sagt, `_BIF` sei bei
`Notify(…, 0x81)` neu zu lesen, und das ist richtig; nur schickt kein Brett beim
**Start** ein 0x81.

### 5.5 Die Taste, die jemand anders abholte

Zuletzt, im vollen Schreibtisch: `irqs=1 stsor=0x0101` — der Behandler ist
gelaufen und **hat** das Tastenbit gelesen — und trotzdem kein `ev taste`. Die
Meldung hing an `E_BTN`, also an genau dem Wort, das `button_take` beim Abholen
**löscht**. Die Leiste fragt jede Runde, der Starter auch; die Taste war weg,
bevor die Meldezeile sie sehen konnte. Gezählt wird jetzt mit `E_BTNN`.

### 5.6 (Und im Schreibtisch lief `pump` gar nicht)

`acpiev.pump` stand in der Leerlaufaufgabe — dem richtigen Ort, **wenn** ein
Ablaufplaner läuft. Der Schreibtisch dieses Abbilds läuft mit `nosched`. Der
Deckel schloss sich, und kein Sperrbildschirm kam: nicht weil der Weg kaputt war,
sondern weil niemand die Kurbel drehte. `pump` steht jetzt auch in
`kgui.fi::wait_wm`.

---

## 6. Die Abnahme

### 6.1 Die Einschalttaste — echt, kein Nachbau

`system_powerdown` am QEMU-Monitor **ist** der Druck auf die Taste: QEMU setzt
`PWRBTN_STS` und zieht den SCI.

```
acpiev: ev taste
acpiev: ready=1 why=0 sci=9 gpearm=5 meth=5 lid=1 batt=1 pct=77 ac=0
        irqs=1 sts=0x0101 pm1en=0x0100 ioapic=0x0000a025 mode=3
        pumpn=704 ev=1 pwrb=1
```

`sts=0x0101` ist `PWRBTN_STS` (Bit 8); `ioapic=0xa025` ist Vektor 37,
pegelgesteuert, low-aktiv, **nicht maskiert**; `mode=3` heißt „in den ACPI-Modus
umgeschaltet". Gemessen **im vollen Schreibtisch**, mit Akku und Deckel.

### 6.2 Deckel und Akku

QEMU 7.2 hat **weder Deckel noch Akku** (`-device battery` erst ab QEMU 8.2, ein
Deckelgerät gibt es bis heute nicht). **Das ist ein Befund und keine Ausrede.**
`tools/acpiev/asl/laptop.asl` baut beide nach — und zwar **anders** als
`tools/k18/ssdt.py` es konnte: dort musste `_BST` ein konstantes Paket sein, weil
`kernel/batt.fi` die Tabellen nur absucht. **Hier sind es Methoden**, die aus einer
Operationsregion lesen, mit `If`/`Else` verzweigen, mit `Multiply` rechnen und ihr
Paket mit `Index`/`Store` zur Laufzeit zusammenbauen — eine Tabelle, die
`batt.fi` **nicht** lesen kann und die deshalb misst, ob der Interpreter läuft.

| Schritt | gesetzt | gemessen |
|---|---|---|
| 1 Deckel auf, 77 % | `lid=1 pct=77` | `lid=1 pct=77 ac=0` |
| 2 Deckel **zu** | `lid=0` | `lid=0 pct=77` |
| 3 Deckel auf, 40 % | `lid=1 pct=40` | `lid=1 pct=40` |
| 4 am Netz, lädt | `pct=41 ac=1` | `lid=1 pct=41 ac=1` |

Zwischen der Zahl, die der Messlauf in den Speicherplatz legt, und der Zahl in
`acpiev.batt_percent` liegen `_BST`, ein `Multiply`, ein `Index`, ein `Store`, das
Auspacken des Pakets und die Prozentrechnung gegen `_BIF`. Schritt 4 ist der Fall,
für den der `Notify`-Ring sechzehn Plätze hat: **eine** GPE-Methode setzt **zwei**
`Notify` ab, und beide kommen an.

### 6.3 Die Bilder

* **`belege/acpiev/20-deckel.png`** — Deckel zu → **der Sperrbildschirm**:

  ```
  acpiev: fake gpe b=0x03
  acpiev: deckel zu -- gesperrt
  desk: start /bin/lock  pid=6
  sperre: Sperrer neu, pid=7
  lock: rect id=0 kind=1 x=440 y=276 w=404 h=20
  ```

  und im Bild das Kennwortfeld an genau dieser Stelle. Vorher 222 Farben
  (Schreibtisch), nachher 76 und eine Fläche von 1 004 360 gleichen Bildpunkten.

* **`belege/acpiev/10-leiste-akku.png`** und die Gegenprobe **`12-ohne-akku.png`**
  (dieselbe Zeile ohne die Tabelle). Der Unterschied liegt auf das Rechteck genau
  in der Statusecke (x 1016…1198 der Leiste); das Spaltenprofil zeigt die
  zusätzlichen Glyphen, die ohne Akku fehlen.

* **`belege/acpiev/30-taste.png`** — der Lauf zu 6.1.

### 6.4 Die Gegenproben

| Wort | erwartet | gemessen |
|---|---|---|
| `noacpiev` | nichts aufgesetzt | `why=4`, `gpearm=0`, `ioapic=0x10000` (maskiert), kein Ereignis |
| `evnohold` | kein Namensraum | `why=3`, `gpearm=0`, kein Ereignis |
| `evself` | Rechnung stimmt | `selbst name ok`, `selbst reg ok` |

Der Selbsttest rechnet nach: `_L1B` → Bit 0x1B pegelgesteuert, `_E03` → Bit 3
flankengesteuert, die Registerrechnung über zwei Blöcke mit `GPE1_BASE` — und, die
wichtigste Zeile, **`_LID` ist keine GPE-Methode** (`I` ist keine Hexziffer). Wer
`_LID` als Bit 0x1D liest, schaltet ein Bit scharf, das niemandem gehört.

### 6.5 Was die Wache verhindert hat

Die erste Fassung der Tabelle legte ihre Methoden auf 0x10…0x12 — „Bits, die QEMU
nicht benutzt". Der Kern fand sie (`meth=5`) und schaltete sie **nicht** scharf
(`on=0`), und er hatte recht: QEMUs GPE0-Block ist vier Oktette lang, also die
Bits 0…15. Bit 0x10 liegt außerhalb; `gpe_sts_port` gibt dafür 0, und ein Bit ohne
Register lässt sich nicht freigeben. **Die Wache hat gehalten, statt in einen
fremden Anschluss zu schreiben.**

---

## 7. Was ohne echte Hardware offen bleibt

Ehrlich und vollständig:

1. **Dass ein echtes Brett das GPE-Bit wirklich zieht.** Deckel- und
   Akkuereignisse werden auf QEMU von Hand ausgelöst (`evfake`), weil es dort
   keine Hardware gibt, die es täte. Gemessen ist alles **dahinter**: die Methode,
   das `Notify`, `_LID`/`_BST`/`_PSR`, der Wert, der Sperrbildschirm. Nicht
   gemessen ist die eine Leitung. **Die Einschalttaste ist davon ausgenommen** —
   die zieht QEMU wirklich.
2. **Der Unterbrechungssturm.** Dass das Löschen des Statusbits ihn verhindert,
   ist die Zusage von Abschnitt 5 in `kernel/hw.fi` — auf QEMU gibt es praktisch
   keine aktiven GPEs, also lässt es sich dort nicht auslösen.
3. **Der `EmbeddedControl`-Adressraum.** `hart.asl` benutzt ihn, und der
   Interpreter kennt ihn **nicht**. Auf einem echten Laptop hängen Deckel und Akku
   fast immer daran. Das ist die nächste Runde, und das Pflichtenheft dafür steht
   in Abschnitt 3.
4. **`_OSI`.** Dieselbe Sache: Firmware, die ganze Zweige ihrer DSDT davon abhängig
   macht, wer da läuft, bekommt von diesem Interpreter keine Antwort.
5. **Dass das Energiemenü auf den Tastendruck aufgeht**, ist am Bild noch nicht
   gemessen: der Starter kommt in diesem Abbild versteckt hoch. Der Weg ist
   gebaut, und der Druck kommt nachweislich bis in Ring 3 (`PG_BTN`).

`tools/acpiev/brett.sh` ist die Anleitung dafür: welche Kernelzeile, welche Zeile
in der Ausgabe was bedeutet, welcher Handgriff am Gerät welche Zahl ändern muss,
und was zu tun ist, wenn `meth=0` herauskommt.

---

## 8. Die Zahlen

```
memmap.py        111 Bereiche, 12 Vektoren, 205 Modusnamen, 0 Kollisionen
check-ui.sh      173 Dateien, 0 Verstöße -- PASSED
tools/aml/run.sh 52 von 53 grün beim Hereinholen; die eine rote war die
                 Modusbit-Kollision und ist behoben
Kern             5 296 848 Oktette (Stufe 0, gui=on)
Abbild           136 314 880 Oktette (130 MiB), GPT, EFI 96 MiB + Wurzel 32 MiB
DSDT parsen      1358 us (QEMU, 346 Knoten)
Namensraum       256 KiB Arena, ~90 KiB belegt -- nur gehalten, wenn es
                 Ereignisgeräte gibt
```

---

## 9. Dateien

| Datei | Was |
|---|---|
| `kernel/acpiev.fi` | neu — SCI, GPE, `_Lxx`, `Notify`, Deckel/Akku/Taste |
| `kernel/aml.fi` | `ns_hold`/`ns_drop`/`eval_node` |
| `kernel/amlev.fi` | `Notify`-Ring (Gerät + Code statt nur Zähler) |
| `kernel/sys.fi` | zehn Felder an `osum_pwrget` |
| `kernel/kgui.fi`, `kernel/tasks.fi` | `pump` in beiden Schleifen |
| `kernel/user/taskbar.fi` | Akku auf Ereignisse, Warnung 20 %/10 % |
| `kernel/user/launcher.fi` | Taste öffnet das Energiemenü |
| `tools/aml/pflichtenheft.py` | das gemessene Pflichtenheft |
| `tools/aml/asl/`, `tools/acpiev/asl/` | die Tabellen als ASL-Quelltext |
| `tools/acpiev/shot.sh`, `taste.sh` | die Abnahme mit Bildern |
| `tools/acpiev/brett.sh` | **was auf Justins Brett nachzumessen ist** |
