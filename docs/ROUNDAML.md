# RUNDE AML -- ein Interpreter fuer die Sprache der Firmware

Zweig `aml`, abgezweigt von `mergeline2` (b010f75), 30.08.2026.
Abnahme: `bash tools/aml/run.sh` (Abschnitt 31 in `./test.sh`).

---

## 1. WORUM ES GEHT

Ein PCI-Geraet hat vier Unterbrechungsstifte (INTA..INTD). Welcher davon
an welcher Leitung des I/O-APIC haengt, steht **nicht im Geraet**. Es
steht in einer Tabelle, die die Firmware in einer Sprache namens AML
hinterlegt hat, im Objekt `_PRT` der Wurzelbruecke.

Bis zu dieser Runde hat Osum stattdessen das Register 0x3C der
PCI-Konfiguration gelesen ("Interrupt Line"). Das ist kein Register des
Geraets, sondern ein **Notizzettel**: die Firmware traegt dort ein, was
sie eingerichtet hat, und niemand zwingt sie dazu. Auf den meisten
Brettern steht die richtige Zahl darin. Auf manchen steht 0 oder 0xFF,
und hinter einer PCI-Bruecke steht dort die Leitung **vor** der Bruecke.

`docs/REALHW.md` hat das seit Runde HWNET als die gefaehrlichste offene
Stelle gefuehrt. Diese Runde schliesst sie.

---

## 2. WAS GEBAUT WURDE

Vier Dateien, zusammen **4024 Zeilen**:

| Datei | Zeilen | Was darin steht |
|---|---:|---|
| `kernel/amlns.fi` | 548 | der Namensraum: Knoten, Namen, die Suchregel der Spezifikation, die Halde |
| `kernel/amlobj.fi` | 554 | Objekte (Ganzzahl, Zeichenkette, Puffer, Paket, Verweis), OperationRegion und Felder, Ressourcenbeschreibungen |
| `kernel/amlev.fi` | 1549 | die Ausfuehrung: Ausdruecke, Steuerfluss, Methodenaufrufe, die Grenzen |
| `kernel/aml.fi` | 1373 | die Erklaerungen laden, `_PRT` auswerten, die Routentafel, der Rueckfall, die Meldungen |

Dazu:

| Datei | Zeilen | Was darin steht |
|---|---:|---|
| `tools/aml/disasm.py` | 758 | **dieselbe Kodierung ein zweites Mal**, in Python, von Hand nach ACPI Kapitel 20 -- die Gegenrechnung |
| `tools/aml/run.sh` | 514 | die Abnahme, 53 Zusagen |

Geaendert: `kernel/pci.fi` (+`cfg_write8`), `kernel/nvme.fi`,
`kernel/e1000.fi`, `kernel/virtio.fi`, `kernel/xhci.fi` (je eine Zeile:
die Leitung kommt jetzt aus `aml.gsi_or_line`), `kernel/kstate.fi`
(Modusbits, `AML_OFF`), `kernel/kmain.fi` (die Stufe, die Modusworte),
`kernel/arch/x86_64/boot.s` (Kernstapel 65536 -> 131072, siehe 6.3),
`tools/kernel/memmap.py`, `test.sh`.

---

## 3. WAS AUSDRUECKLICH NICHT GEBAUT WURDE

* **Kein Nachbau von ACPICA.** Der Auftrag war "so gross wie noetig und
  so klein wie moeglich".
* **Keine Thermalregelung, kein S4.**
* **Kein S3.** Nur entworfen, siehe Abschnitt 8.
* **Keine GPE-Behandlung im laufenden Betrieb.** Das war Ziel Nummer
  drei und ausdruecklich an Ziel 1 und 2 gekoppelt; es steht in
  Abschnitt 8 mit dem, was fehlt.
* **Kein `IndexField`, kein `BankField`.** Beide werden beim Laden
  ERKANNT und **uebersprungen** -- es entsteht kein Knoten. Ein Knoten,
  der beim Lesen falsche Zahlen liefert, ist schlimmer als keiner.
* **Kein `Concat`, `Match`, `ToString`, `Mid`, `Fatal`, `Load`,
  `Unload`, `ToBCD`, `FromBCD`, `Wait`.** Sie geben ERR_OPCODE (5).

---

## 4. WIE `_PRT` IN QEMU WIRKLICH AUSSIEHT

Das ist der Grund, warum die Messung etwas wert ist. QEMUs `_PRT` ist
**keine fertige Tabelle**, sondern eine Methode (157 Oktette AML):

```
Method(\_SB.PCI0._PRT, 0) {
    Store(Package(0x80){}, Local0)
    Store(Zero, Local1)
    While(LLess(Local1, 0x80)) {
        Store(ShiftRight(Local1, 2), Local2)
        Store(And(Add(Local1, Local2), 3), Local3)
        If (LEqual(Local3, Zero)) { Store(Package(4){0,0,LNKD,0}, Local4) }
        If (LEqual(Local3, One))  {
            If (LEqual(Local1, 4)) { Store(Package(4){0,0,LNKS,0}, Local4) }
            Else                   { Store(Package(4){0,0,LNKA,0}, Local4) }
        }
        If (LEqual(Local3, 2)) { Store(Package(4){0,0,LNKB,0}, Local4) }
        If (LEqual(Local3, 3)) { Store(Package(4){0,0,LNKC,0}, Local4) }
        Store(Or(ShiftLeft(Local2, 16), 0xFFFF), Index(Local4, 0))
        Store(And(Local1, 3), Index(Local4, 1))
        Store(Local4, Index(Local0, Local1))
        Increment(Local1)
    }
    Return(Local0)
}
```

Um das auszuwerten, braucht man: veraenderbare Pakete, `Index` als
**Verweis** (nicht als Wert), Store in ein Paketelement, `While` mit
Abbruchbedingung, `If`/`Else`, acht Ortsvariablen, die Rechen- und
Vergleichsoperatoren und Namen in Paketen, die auf Geraete zeigen.

Und dann geht es weiter: die Leitung steht nicht im Paket, sondern im
Link-Geraet.

```
Method(\_SB.LNKA._CRS, 0) { Return(IQCR(PRQ0)) }

Method(\_SB.IQCR, 1) {
    Name(PRR0, Buffer(11){0x89,6,0,9,1, 0,0,0,0, 0x79,0})  // im RUMPF!
    CreateDWordField(PRR0, 5, PRRI)
    If (LLess(Arg0, 0x80)) { Store(Arg0, PRRI) }
    Return(PRR0)
}

OperationRegion(\_SB.PCI0.S08.P40C, PCI_Config, 0x60, 4)
Field(P40C) { PRQ0,8, PRQ1,8, PRQ2,8, PRQ3,8 }
```

Also zusaetzlich: **ein `Name` mitten in einem Methodenrumpf** (der bei
jedem Aufruf neu entsteht und der Aufrufinstanz gehoert, nicht der
Tabelle), ein Feld **in einem Puffer**, eine **OperationRegion im
PCI-Konfigurationsraum**, deren Geraetenummer aus dem naechsten `_ADR`
oberhalb kommt (`\_SB.PCI0.S08._ADR` = 0x00010000, also 00:01.0, der
PIIX3), und eine Ressourcenbeschreibung, aus der die Leitung gelesen
wird (Extended Interrupt Descriptor 0x89, die Zahl bei Versatz 5).

Das ist der ganze Weg, und dieser Interpreter geht ihn.

---

## 5. DIE MESSUNGEN

Alle Zahlen aus `bash tools/aml/run.sh`, QEMU 7.2 mit KVM, Maschine
`pc` (i440fx), 128 MiB, ein Prozessor.
**Auf diesem Rechner liegt kein Testbrett. Nichts davon ist auf echter
Hardware gemessen.**

### 5.1 Der Namensraum

| | |
|---|---:|
| DSDT | 6476 Oktette |
| Knoten im Namensraum | **346** |
| davon Geraete / Methoden / Regionen / Felder | 51 / 104 / 7 / 20 |
| Arena hoechstens belegt | **91608 Oktett** |
| davon Knotentafel (2048 Plaetze zu 32 Oktett) | 65536 |
| davon Halde (Puffer, Pakete, Methodenrahmen) | 26072 |
| Rahmen aus dem Rahmenverwalter | 64 (256 KiB) |
| **nach dem Verwerfen freie Rahmen** | **genau so viele wie vorher (31214)** |

Der Namensraum liegt **nicht** in `kdata`. Er kommt aus
`mem.frame_run(64)` und geht am Stueck zurueck. In `kdata` bleibt eine
Seite (`AML_OFF` = 0x85000): die Skalare und die Routentafel
(128 Eintraege zu 16 Oktett). Das ist der ganze bleibende Speicher:
**4 KiB statt 256 KiB**.

### 5.2 Die Zeit

| | |
|---|---:|
| DSDT parsen | **1532 us** (1,5 ms) |
| `_PRT` auswerten, 128 Steckplaetze | **4753 us** (4,8 ms) |
| zusammen | **6,3 ms** |
| Bootzeit ohne Interpreter (`noaml`), Median aus 5 | 2503 ms |
| Bootzeit mit Interpreter, Median aus 5 | 2565 ms |

**Ehrlich zur zweiten Zahl:** die Bootzeit misst den ganzen QEMU-Lauf
samt Start und Beendigung und schwankt um mehrere zehn Millisekunden.
Die belastbare Zahl ist die, die der Kernel selbst mit dem Zyklenzaehler
nimmt: **6,3 ms**. Die Bootzeitmessung ist nur die Gegenprobe, dass
keine Groessenordnung dazwischenliegt.

Warum `_PRT` dreimal so lange braucht wie das Parsen: 128 Durchlaeufe
mit je gut vierzig Termen. Die fuenf Link-Geraete werden dabei
**zwischengespeichert** -- ohne das liefen `_STA`, `_CRS` und `IQCR`
vierhundertmal statt zwanzigmal, und die Halde ging aus (gemessen: 103
statt 128 Eintraege, Fehler ERR_HEAP).

### 5.3 Die Opcode-Abdeckung

`tools/aml/disasm.py hist` zaehlt in QEMUs DSDT **56 verschiedene
Opcodes** (1516 Vorkommen). Der Interpreter meldet seine Koennen-Liste
selbst (`aml: can` / `canext` / `canpair`, zusammen **101 Formen**), und
der Testlaeufer haelt beides gegeneinander:

```
in der Tabelle vorkommend: 56 verschiedene Opcodes
davon unterstuetzt:        56
Abdeckung:                 100%
```

**Wichtig, damit die 100 % nicht schoengerechnet sind:** der Laeufer
prueft ZUSAETZLICH, dass jeder Opcode, den der Interpreter im Lauf
WIRKLICH angefasst hat (36 Stueck, gemeldet als `aml: op`), auch in der
Koennen-Liste steht. Eine Liste, die von der Wirklichkeit abweicht,
faellt damit auf.

Die 101 Formen decken **nicht** die ganze Sprache. Was fehlt, steht in
Abschnitt 3.

### 5.4 Der Kernstapel

| | |
|---|---:|
| das Laden der DSDT allein | 12624 Oktett |
| tiefster Punkt insgesamt (beim `_PRT`) | **42240 Oktett** |
| Wache (STACK_LIMIT) | 57344 |
| Kernstapel | 131072 (vorher 65536) |
| tiefste Verschachtelung | 6 (Grenze 32) |

---

## 6. DIE DREI DINGE, DIE BEIM BAUEN SCHIEFGINGEN

Sie stehen hier, weil sie im Quelltext als Kommentar stehen und weil
jede von ihnen eine Messung war, keine Vermutung.

### 6.1 Die Halde ging aus (ERR_HEAP)

Jeder Methodenaufruf nahm einen Rahmen von 400 Oktetten und gab ihn nie
zurueck. Beim Auswerten von `_PRT` sind das vierhundert Aufrufe:
196296 Oktett gebraucht, 192 KiB da. Ergebnis: 103 statt 128 Eintraege.

**Behoben zweifach:** (a) ein Methodenaufruf, der eine ZAHL
zurueckgibt und keinen neuen Namen angelegt hat, setzt den
Schiebezeiger der Halde zurueck -- ein Stapel, kein Haufen; (b) die
fuenf Link-Geraete werden zwischengespeichert.

### 6.2 Zwischenergebnisse auf der Halde machten die Schleifengrenze wertlos

Erste Fassung: jedes Zwischenergebnis eines Ausdrucks kam auf die Halde.
Eine Schleife ohne Ende haette dann die Halde leergeraeumt, bevor die
Schrittgrenze greift -- und die Abnahme haette "Halde voll" gemeldet, wo
sie "Endlosschleife" pruefen wollte.

**Behoben:** jeder Aufrufer von `ev` gibt einen Platz von 24 Oktetten
mit, und der steht auf dem Firn-Stapel. Auf die Halde kommt nur, was
einen Rumpf hat: Puffer, Pakete, Zeichenketten, Methodenrahmen.

### 6.3 Der Rekursionstest hat den Kernstapel ueberschrieben

Mit einer Tiefengrenze von 48 hat `amldeep` den Kernstapel von 65536
Oktetten gerissen. Zu sehen war es daran, dass die Zeichenkette, die den
Fehler melden sollte, danach nicht mehr da war: die Ausgabe brach mitten
im Wort ab (`aml: deep` statt `aml: deep err=6`), und der Kernel blieb
zwei Stufen spaeter stehen.

**Behoben dreifach:**

1. **Eine Wache, die misst statt raet.** `stage` merkt sich den
   Stapelzeiger; jede Verschachtelungsstufe rechnet nach, wie weit sie
   sich davon entfernt hat. Ueber STACK_LIMIT gibt es ERR_DEPTH -- den
   definierten Fehler, aus einer Messung. Wie viele Oktette eine Stufe
   kostet, entscheidet der Uebersetzer und nicht der Quelltext; eine
   Zahl wie "48" ist deshalb eine Vorsichtsgrenze und keine Wache.
2. **Die grossen Auswerterfunktionen aufgeteilt.** Firn legt die
   Zwischenplaetze ALLER Zweige einer Funktion in EINEM Rahmen an. Mit
   allen Zweigen in `ev_inner` kostete eine Stufe rund 1600 Oktette.
   Dasselbe beim Laden: `load_term` in einen kleinen Verteiler und ein
   `load_leaf` aufgeteilt hat den Stapelbedarf des Ladens von **26592
   auf 12624 Oktett** halbiert.
3. **Der Kernstapel ist von 65536 auf 131072 gewachsen**
   (`kernel/arch/x86_64/boot.s`). 42240 Oktette waren zwei Drittel der
   alten Groesse -- zu wenig Abstand fuer eine DSDT, die tiefer
   verschachtelt ist als die einer virtuellen Maschine. Der Preis sind
   64 KiB mehr `.bss`; im Abbild auf der Platte steht davon kein
   einziges Oktett.

---

## 7. DIE ABNAHME -- 53 Zusagen, 0 gefallen

### Die Zusage, an der die Runde haengt (Abschnitt 5 des Laeufers)

Eine e1000-Netzkarte auf 00:03.0, Stift A. `_PRT` fuehrt ueber LNKC auf
das PIIX3-Register 0x62, und dort steht die 11. Der Kernel traegt GSI 11
in den I/O-APIC ein, ein Rechner im anderen Netzwerknamensraum schickt
zehn Pings:

| | mit der Leitung aus `_PRT` | mit `amlwrong` (um eins verschoben) |
|---|---:|---:|
| GSI eingetragen | 11 | 12 |
| **Unterbrechungen angekommen** | **13** | **0** |
| Pings beantwortet | 10 | 9 |

**Warum die zweite Zeile die wichtige ist:** die Karte arbeitet auch
ohne Unterbrechung weiter, per Abfrage -- deshalb kommen selbst mit der
falschen Leitung noch Antworten. Wer die Antworten zaehlt, misst nichts.
Gezaehlt werden die Unterbrechungen, und die sind 13 gegen 0.

### Die uebrigen Abschnitte

1. **Zahlen und Karte:** `memmap.py` ohne Kollision (78 Bereiche), die
   Modusbits 704..719 gehoeren nur dieser Runde, die Wache liegt unter
   dem halben Kernstapel.
2. **Namensraum gegen die zweite Fassung:** die DSDT kommt vollstaendig
   ueber die serielle Leitung (6476 Oktette), `disasm.py` liest sie
   unabhaengig, und **die Namen stimmen Zeichen fuer Zeichen ueberein**
   (346 Stueck, Mengenvergleich, nicht nur die Anzahl). Dazu die fuenf
   Namen, an denen die Runde haengt, einzeln geprueft.
3. **Opcode-Abdeckung:** 56 von 56, und jeder ausgefuehrte Opcode steht
   in der Koennen-Liste.
4. **`_PRT`:** 128 Eintraege; fuer jedes Geraet mit einem Stift sagen
   `_PRT` und das Register 0x3C **dasselbe** (zwei unabhaengige Wege zur
   selben Zahl, weil SeaBIOS die PIIX3-Register nach derselben Tabelle
   programmiert); 00:03.0 Stift A liegt auf GSI 11.
5. *(siehe oben)*
6. **Kaputtes AML (`amlbad`):** die DSDT wird auf die halbe Laenge
   abgeschnitten, die Laenge im Kopf luegt weiter. Ergebnis: definierter
   Fehler (ERR_OPCODE = 5), `prtok=0`, Routentafel leer, **Rueckfall auf
   das Interrupt-Line-Register greift** (`aml=999 line=11`), keine
   Prozessorausnahme, `kernel: done`. Die ECHTE Tabelle bleibt dabei
   unangetastet -- gearbeitet wird auf einer Kopie in der Halde, weil
   `batt.fi` und `power.fi` sie danach noch lesen.
   Dazu `noaml`: der Zustand vor dieser Runde, unveraendert.
7. **Schleife ohne Ende (`amlloop`):** `Method(TSTL,0){While(One){}}`,
   als AML-Oktette hingeschrieben. Schrittgrenze greift (ERR_BUDGET = 7),
   `_PRT` bleibt unberuehrt, die Maschine faehrt fertig hoch.
8. **Rekursion (`amldeep`):** `Method(TSTR,0){TSTR()}`. Tiefengrenze
   greift (ERR_DEPTH = 6), kein Stapelueberlauf, keine Ausnahme.
9. **Kein Leck:** Rahmen vorher = Rahmen nachher (31214), und der
   Namensraum hat wirklich Rahmen gekostet.
10. **Messungen** (siehe Abschnitt 5).

### Was daneben gruen geblieben ist

Bestehende Abschnitte, auf demselben Rechner nachgefahren:

| Abschnitt | Ergebnis |
|---|---|
| `tools/kernel/run.sh` | 176 gruen, 0 rot |
| `tools/pci/run.sh` | 98 gruen, 0 rot |
| `tools/smp/run.sh` | 59 gruen, 0 rot |
| `tools/net/run.sh` | 75 gruen, 0 rot |
| `tools/k18/run.sh` | 170 gruen, 0 rot |
| `tools/k17/run.sh` | 157 gruen, **1 rot** |

**Zu dem einen roten, ehrlich:** es ist "DIESELBE SHELL-SITZUNG, Oktett
fuer Oktett" -- der Vergleich einer Tastatursitzung ueber USB mit
derselben ueber PS/2. Die Tasten werden dort mit festen Wartezeiten
(0,8 s) in den QEMU-Monitor getippt, und der Test ist auf diesem Wirt
zeitabhaengig. **Gegengeprueft am unveraenderten Zweigstand** (b010f75,
eigener Arbeitsbaum, derselbe Rechner, einmal unter Last und einmal
allein):

| | gruen | rot |
|---|---:|---:|
| b010f75 ohne diese Runde, unter Last | 151 | **7** |
| b010f75 ohne diese Runde, allein | 153 | **5** |
| dieser Zweig, allein | **157** | **1** |

Der Fehler ist also aelter als diese Runde und auf diesem Wirt flatterig;
der Zweig mit dem Interpreter schneidet dabei besser ab als der ohne.
Ich habe ihn NICHT abgeschaltet und auch nicht "wegerklaert" -- er steht
hier mit den Zahlen, mit denen er gemessen wurde.

### Was sonst noch gruen geblieben ist

* GUI-Bau (`--gui on`), **GUI-loser Serverbau** (`--gui off`, 2502392
  Oktette), Bau ohne Tunnel und Bau mit dem **selbstgehosteten
  Uebersetzer** (`--stufe 1`) -- alle vier booten und werten `_PRT` aus
  (128 Eintraege).
* Kein Test wurde abgeschaltet.

---

## 8. WAS AUF ECHTER HARDWARE TROTZDEM SCHIEFGEHEN KANN

Diese Liste ist der wichtigste Teil dieses Dokuments. Auf diesem Rechner
liegt kein Testbrett; alles unten ist begruendete Erwartung und keine
Messung.

1. **Der Namensraum passt nicht.** 2048 Knoten reichen fuer QEMU (346)
   mit grossem Abstand. Die DSDT eines Laptops hat oft das Zehnfache an
   Oktetten; ob sie unter 2048 Namen bleibt, ist unbekannt. Passiert es
   nicht: ERR_NODES (2), Rueckfall auf 0x3C. **Kein Absturz, aber auch
   kein `_PRT`.**
2. **Die Halde reicht nicht.** 192 KiB. Eine `_PRT`-Methode, die mehr
   Pakete baut, oder ein Brett mit mehr Bussen: ERR_HEAP (3), Rueckfall.
3. **Der Kernstapel reicht nicht.** 42240 Oktette bei QEMU. Eine tiefer
   verschachtelte DSDT kommt hoeher. Ueber 57344 greift die Wache:
   ERR_DEPTH, Rueckfall. **Die Wache ist gemessen, nicht geraten -- aber
   sie ist an EINER DSDT gemessen.**
4. **`EmbeddedControl`.** Auf fast jedem Laptop haengen `_BST`, der
   Deckelschalter und die Luefter am Embedded Controller. Dieser
   Interpreter kennt SystemMemory, SystemIO und PCI_Config und **sonst
   nichts**: ERR_REGION (10). Fuer `_PRT` ist das in aller Regel egal
   (die Link-Register sitzen im Chipsatz), fuer `_STA` eines Geraets
   hinter dem EC nicht.
5. **`IndexField` und `BankField`** werden uebersprungen. Steht ein
   Link-Register hinter einem IndexField, findet `_CRS` seinen Namen
   nicht: ERR_NOTFOUND (9), Rueckfall.
6. **`SystemMemory` ausserhalb der identisch abgebildeten Gigabytes**
   gibt ERR_REGION statt eines Seitenfehlers -- richtig, aber es heisst
   auch: eine DSDT, die ueber eine solche Region gehen muss (QEMUs
   HPET-Region bei 0xFED00000 ist so eine), scheitert dort.
7. **`_PRS`/`_SRS`, der Weg, den QEMU nicht braucht.** In QEMU hat
   SeaBIOS die PIIX3-Register schon programmiert, `_STA` meldet
   "eingeschaltet", und der Zweig, der ein abgeschaltetes Link-Geraet
   ueber `_SRS` einschaltet, **ist gebaut, aber nie gelaufen**. Auf
   einem Brett, das seine Links nicht vorprogrammiert, laeuft in dieser
   Runde zum ersten Mal Code, den nichts geprueft hat. Das ist die
   Stelle, an der ich am ehesten mit einem Fehler rechne.
8. **Mehrere PCI-Wurzelbruecken.** Der Interpreter geht ALLE `_PRT` im
   Baum durch und nimmt die Busnummer aus dem `_BBN` des Elternknotens.
   Was er NICHT tut: `_PRT` einer PCI-zu-PCI-Bruecke weiter unten
   aufloesen (die Stiftdrehung ueber Bruecken hinweg,
   `pin_neu = (pin + slot) % 4`). Ein Geraet hinter einer Bruecke findet
   deshalb keinen Eintrag und faellt auf 0x3C zurueck -- also genau auf
   den Weg, der dort besonders oft falsch ist.
9. **Nebenlaeufigkeit.** Der Interpreter laeuft EINMAL beim Start, auf
   einem Prozessor, bevor Aufgaben laufen. `Acquire` gibt sofort
   Erfolg, `Release` tut nichts. Sobald AML spaeter im Betrieb laufen
   soll (GPE, Ziel drei), stimmt das nicht mehr.
10. **`Sleep` und `Stall` tun nichts.** Ein `_SRS`, das nach dem
    Schreiben eine Wartezeit erwartet, bekommt sie nicht.
11. **Die Fehler sind erkannt, nicht behoben.** Der Rueckfall bringt
    genau den Zustand von vor dieser Runde zurueck. Wo 0x3C falsch war,
    ist es nach einem AML-Fehler wieder falsch.

---

## 9. S3 (STANDBY) -- ENTWURF, NICHT GEBAUT

Der Auftrag sagt ausdruecklich: entwerfen und aufschreiben, nicht halb
bauen. Also hier, was es braeuchte, und was davon heute da ist.

### Was heute da ist

* `acpi.table` findet die FADT (Runde K13, fuer `_S5_`).
* `power.acpi_off` schreibt SLP_TYP/SLP_EN in PM1a/PM1b -- **derselbe
  Mechanismus**, den S3 braucht, nur mit einem anderen Wert.
* Der Interpreter kann jetzt ein `Name(\_S3_, Package(){...})` lesen und
  daraus SLP_TYPa und SLP_TYPb holen. Das ist der einzige Teil, den
  diese Runde wirklich dazugetan hat.

### Was fehlt, in der Reihenfolge, in der es gebaut werden muesste

1. **`\_S3_` auswerten** und die zwei Werte behalten. *(Der Interpreter
   kann es; es fehlt der Aufruf und der Platz in `kdata`. Klein.)*
2. **Den Wachaufruf-Vektor eintragen.** Die Firmware springt beim
   Aufwachen an eine Adresse, die im **FACS** steht (Versatz 24,
   `firmware_waking_vector`, 32 Bit, real mode). Es braucht also ein
   Stueck 16-Bit-Code, das den Prozessor zurueck in den langen Modus
   bringt -- praktisch dasselbe Trampolin wie `smp.s` (Runde K5), aber
   aus dem echten Modus statt aus dem Schutzmodus.
3. **Den Prozessorzustand retten und wiederherstellen.** GDT, IDT, TSS,
   CR0/CR3/CR4, EFER, die MSRs von `syscall`, der lokale APIC, der
   I/O-APIC. Der Prozessor kommt aus S3 wie nach einem Kaltstart.
4. **`_PTS(3)` vor dem Schlafen und `_WAK(3)` nach dem Aufwachen
   aufrufen.** Beides sind Methoden mit einem Argument, beide gibt es
   auf jedem echten Brett, und **beide laufen ueber diesen
   Interpreter** -- das ist der Grund, warum S3 ohne AML nie ging.
5. **Die Geraete.** Jeder Treiber braucht ein `suspend`/`resume`: PCI-
   Konfiguration retten (BARs, Command, Interrupt Line), Ringe stillegen,
   DMA anhalten, nach dem Aufwachen neu aufsetzen. Das betrifft
   `nvme.fi`, `ahci.fi`, `e1000.fi`, `virtio.fi`, `xhci.fi` und
   `fb.fi`. **Das ist der grosse Teil**, und er hat mit AML nichts zu
   tun.
6. **Der Rahmenpuffer.** Ohne einen echten Grafiktreiber kommt der
   Bildschirm aus S3 nicht von selbst zurueck; die Firmware stellt den
   VBE-Modus nicht wieder her. Auf vielen Brettern ist das der Punkt,
   an dem S3 "funktioniert" und der Schirm trotzdem schwarz bleibt.

**Schaetzung:** Punkt 1 und 4 sind zusammen unter 200 Zeilen. Punkt 2
und 3 sind eine eigene Runde in der Groesse von K5. Punkt 5 ist eine
Runde je Treiberklasse. Punkt 6 braucht einen KMS-Treiber, den Osum
bewusst nicht hat (`docs/REALHW.md`, Zeile "Grafik").

**Und die ehrliche Randnotiz:** S3 laesst sich in QEMU zwar ausloesen,
aber ein "es hat funktioniert" dort sagt ueber ein echtes Brett fast
nichts -- die interessanten Fehler stecken in Punkt 5 und 6, und die
haengen an Hardware, die hier nicht liegt.

---

## 10. GPE (Ziel drei) -- was fehlt

Ebenfalls nicht gebaut, und aus einem Grund, der genannt gehoert: die
Ziele eins und zwei standen erst am Ende der Runde, und Ziel drei war
ausdruecklich daran gekoppelt.

Was es braeuchte: die GPE-Bloecke aus der FADT (GPE0_BLK, GPE1_BLK)
lesen, die Statusbits bei jedem SCI abfragen, und je gesetztem Bit die
Methode `_Lxx` (level) oder `_Exx` (edge) im Bereich `\_GPE` aufrufen --
QEMUs DSDT hat genau eine davon (`\_GPE._E01`, fuer PCI-Hotplug). Der
SCI selbst haengt an der Leitung, die in der FADT steht (`sci_int`), und
die ist in QEMU 9; `_PRT` fuehrt fuer 00:01.3 (den ACPI-Baustein) ueber
LNKS auf dieselbe 9 -- was diese Runde nebenbei bestaetigt hat.

Der Interpreter kann `\_GPE._E01` heute schon ausfuehren. Was fehlt, ist
der Weg vom Unterbrechungsvektor dorthin -- und die Frage aus Punkt 9
oben: AML im laufenden Betrieb braucht echte Mutexe.

---

## 11. WIE MAN ES SELBST NACHRECHNET

```
bash tools/aml/run.sh                     # die ganze Abnahme, 53 Zusagen

# den Namensraum sehen (346 Zeilen):
qemu-system-x86_64 -kernel osum.mb -append "osum aml amlprt" -nographic

# die Tabellen der eigenen Maschine holen und unabhaengig lesen:
qemu-system-x86_64 -kernel osum.mb -append "osum amldump" -serial file:d.log
python3 tools/aml/disasm.py ns   DSDT.bin
python3 tools/aml/disasm.py hist DSDT.bin
python3 tools/aml/disasm.py prt  DSDT.bin
```

Die Modusworte: `aml` (an und melden), `amlprt` (Namensraum und jeder
`_PRT`-Eintrag), `amldump` (Tabellen als Hexzeilen), `amlleak`
(Rahmenzahlen), und die fuenf Gegenproben `noaml`, `amlbad`, `amlloop`,
`amldeep`, `amlwrong`.
