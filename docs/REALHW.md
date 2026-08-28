# ECHTE HARDWARE: WELCHE PLATTE OSUM FINDET UND WELCHE NICHT

Stand: Runde AHCI, 28.08.2026. Alles hier Behauptete ist gemessen; wo
etwas NICHT gemessen ist, steht das dabei.

Dieses Dokument beantwortet eine einzige Frage: **Was passiert, wenn
Osum auf einem gewoehnlichen PC startet und eine Platte sucht?**

---

## 1. DIE FUENF WEGE ZU EINEM BLOCKGERAET

`kernel/blk.fi` ist die ganze Schnittstelle zwischen Dateisystem und
Platte: Block lesen, Block schreiben, 512 Oktette. Dahinter liegen
fuenf Umsetzungen.

| Nr | Konstante   | Datei         | Was es ist                            | Auf echter Hardware? |
|----|-------------|---------------|---------------------------------------|----------------------|
| 0  | `DEV_RAM`   | `blk.fi`      | Rahmen aus dem Speicher               | immer, aber fluechtig |
| 1  | `DEV_ATA`   | `blk.fi`      | ATA PIO ueber Port 0x1F0, Meister     | **ja** -- der Rueckfallweg |
| 3  | `DEV_ATA1`  | `blk.fi`      | dasselbe, Sklave (Bit 4 im Laufwerksregister) | ja |
| 2  | `DEV_NVME`  | `nvme.fi`     | NVMe ueber DMA, M.2                   | ja, seit etwa 2015 |
| 4  | `DEV_USB`   | `usb.fi`      | USB-Stick, Bulk-Only-Transport + SCSI | ja |
| 5  | `DEV_AHCI`  | `ahci.fi`     | **SATA im nativen AHCI-Modus**        | **ja -- der Normalfall seit 2010** |

Nummer 5 ist neu. Vor dieser Runde fehlte sie, und das bedeutete: auf
einem PC mit SATA-SSD und einer Firmware im AHCI-Modus -- also dem
haeufigsten Rechner, den es gibt -- fand Osum **keine Platte**. Kein
Start, keine Installation.

---

## 2. WAS DIE FIRMWARE-EINSTELLUNG "SATA MODE" AENDERT

Fast jedes BIOS/UEFI hat einen Punkt `SATA Mode`, `SATA Configuration`
oder `Storage Option ROM` mit den Werten **AHCI**, **RAID** und
**IDE / Legacy / Compatibility**. Der Wert entscheidet, mit welcher
PCI-Klasse sich derselbe Chip meldet:

| Einstellung | PCI-Klasse | Was Osum benutzt | Geschwindigkeit |
|-------------|-----------|------------------|-----------------|
| **AHCI** (empfohlen) | `01:06:01` | `ahci.fi`, DMA | der Controller bewegt die Oktette selbst |
| **IDE / Legacy** | `01:01:xx` | `blk.fi`, ATA PIO | 256 `in ax, dx` je Block, durch den Prozessor |
| **RAID** | `01:04:xx` | **nichts** | Osum findet keine Platte |

### Was der Treiber dazu sagt

`ahci.fi` sucht bei einem Fehlschlag ein zweites Mal, und zwar nach der
IDE-Klasse. Findet er sie, meldet er:

```
ahci: mode=ide  set BIOS to AHCI
```

Das ist eine Aussage, aus der hervorgeht, was zu tun ist. Ein Treiber,
der in diesem Fall einfach nichts findet, laesst den Benutzer im
Dunkeln -- und genau das war die erste Fassung.

Gemessen in `tools/ahci/run.sh`, Abschnitt 6: auf der QEMU-Maschine
`pc` gibt es keinen AHCI-Controller, sondern einen IDE-Chipsatz der
Klasse `01:01`. Der Lauf muss `mode=ide` melden **und** die PCI-Liste
muss die Klasse `01:01` zeigen -- ohne die zweite Haelfte sagte die
erste nichts.

**RAID-Modus ist nicht abgedeckt.** Ein Controller in RAID meldet
Klasse `01:04` und braucht einen herstellereigenen Treiber
(Intel RST, AMD RAIDXpert). Osum hat keinen und wird keinen bekommen.
Wer Osum auf so einem Rechner starten will, stellt die Firmware auf
AHCI um. (Achtung: ein bereits installiertes Windows startet nach
diesem Wechsel unter Umstaenden nicht mehr, bis man ihm den
AHCI-Treiber beibringt. Das ist kein Osum-Problem, aber es ist gut,
es vorher zu wissen.)

---

## 3. GIBT ES EINEN LEGACY-IDE/PIO-RUECKFALLWEG? JA.

**Ja, und er ist aelter als der AHCI-Treiber.** `kernel/blk.fi` spricht
seit Runde 62 ATA PIO ueber die festen Ports:

* `0x1F0` Daten, `0x1F1` Fehler, `0x1F2` Sektorzahl,
  `0x1F3`..`0x1F6` die Blocknummer und das Laufwerk, `0x1F7` Befehl
  und Status (`blk.ata_select_on`, `blk.ata_read_on`,
  `blk.ata_write_on`)
* Zwei Laufwerke: Meister (`DEV_ATA`) und Sklave (`DEV_ATA1`), der
  Unterschied ist Bit 4 des Laufwerksregisters
* `IDENTIFY` (0xEC) fuer die Groesse (`blk.identify`, `blk.capacity`)
* Ein zweiter Versuch nach `ata_recover` bei Lese- und bei
  Schreibfehlern (`ata_read_twice`, `ata_write_twice`)

### Seine drei ehrlichen Grenzen

1. **LBA28, also 128 GiB.** Der Treiber legt die oberen vier Bits der
   Blocknummer in das Laufwerksregister; mehr passt dort nicht hinein.
   `blk.capacity` schneidet die von `IDENTIFY` gemeldete Zahl deshalb
   dort ab, statt eine Platte zu melden, die er nicht lesen kann. Eine
   1-TB-Platte im IDE-Modus erscheint als 128 GiB.
2. **Jedes Oktett geht durch den Prozessor.** 256 `in ax, dx` je Block
   von 512 Oktetten. Das ist der Preis, den der Kopf von `nvme.fi`
   ausrechnet, und er ist der Grund, warum es die anderen Treiber gibt.
3. **Er braucht einen Controller, der die alten Ports bedient.** Ein
   Rechner ohne jedes IDE-Kompatibilitaetsfenster -- moderne
   Notebooks, alles mit reinem NVMe -- hat diese Ports nicht.

### Wann er greift

Der Rueckfallweg ist **kein automatischer Notnagel**: `blk.fi` waehlt
nicht selbst. Welches Geraet die Wurzel traegt, entscheidet der
Aufrufer (`kmain.fi`, das Installationsprogramm, die Befehlszeile) ueber
`blk.use_ata` / `blk.use_ahci` / `blk.use_nvme` / `blk.use_at`. Was
diese Runde geliefert hat, ist der Treiber und die Erkennung; **die
automatische Treiberwahl beim Start ist NICHT gebaut** und steht als
naechster Schritt an (siehe Abschnitt 6).

---

## 4. WAS AM 28.08.2026 WIRKLICH GEMESSEN WURDE

Alles unter `-accel kvm -cpu host`, also auf der echten CPU des Wirtes
(AMD EPYC 7571), plus derselbe Lauf unter TCG zur Gegenprobe. Wirt:
QEMU 7.2.22.

| Was | Ergebnis |
|-----|----------|
| Controller ueber PCI-Klasse `01:06:01` gefunden | ja, `00:03.0 8086:2922`, ABAR = BAR5 |
| Groesse aus `IDENTIFY DEVICE` | 16384 Sektoren (= die 8 MiB des Abbilds) |
| Sektorgroesse aus `IDENTIFY DEVICE` | 512 |
| ein Sektor geschrieben und zurueckgelesen | gleich, Oktett fuer Oktett |
| acht Sektoren in EINEM Befehl (4096 Oktette) | gleich, je Sektor eigenes Muster |
| Dateisystem darauf (format, mount, schreiben, lesen, auflisten) | gruen |
| Befehle im ganzen Lauf | 197, davon 0 Fehler, 0 Zeitueberschreitungen |
| Der WIRT liest das Abbild nach | Text da, Sektor 4096 = 512x `0x5A`, Sektoren 5000..5007 je eigenes Muster, Sektor 5008 unberuehrt |
| dasselbe unter TCG | Oktett fuer Oktett dasselbe |

Und die vier Gegenproben, in denen die Messung zusammenbricht:

| Gegenprobe | Ergebnis |
|-----------|----------|
| AHCI-Controller **ohne** Platte | `init failed why=8`, keine erfundene Groesse |
| Maschine `pc` (kein AHCI, nur IDE) | `mode=ide  set BIOS to AHCI` |
| **ohne Busmaster-Bit** (`nobm`) | jede Uebertragung schlaegt fehl, `dead=1 alive=0`, **das Abbild bleibt LEER** |
| ohne KVM | der Laeufer sagt es und faellt auf TCG zurueck, statt einen Beweis zu behaupten |

Die dritte Zeile ist die wichtigste: sie ist der Beweis, dass die
Oktette wirklich per DMA gewandert sind. Ohne das Busmaster-Bit darf
der Controller Register beantworten, aber nichts aus dem Speicher
holen -- und dann steht hinterher nichts in der Datei auf dem Wirt.

Laeufer: `bash tools/ahci/run.sh`.

---

## 5. WAS AUF ECHTER HARDWARE TROTZDEM SCHIEFGEHEN KANN

Ehrlich aufgezaehlt. QEMU ist ein sehr braver AHCI-Controller; die
folgenden Punkte hat kein Lauf dieser Runde beruehren koennen.

1. **Die Uebergabe von der Firmware (BIOS/OS handoff).** Ein UEFI hat
   den Controller selbst benutzt -- es hat von dort gebootet. `ahci.fi`
   hat den Handoff ueber `CAP2.BOH` und `BOHC` gebaut, aber unter QEMU
   ist `CAP2.BOH` null und der ganze Block ist ein Durchlauf. **Er ist
   nie ausgefuehrt worden.** Gibt die Firmware nicht her, meldet der
   Treiber `why=5`.
2. **Anlaufzeiten.** Eine mechanische Festplatte braucht nach `SUD`
   Sekunden, bis sie antwortet. Die Schranken hier sind Zaehlschleifen
   (`RESET_LIMIT` = 2 Millionen Schritte), keine Uhren. Auf einem
   schnellen Prozessor koennen sie zu kurz sein. Eine SSD ist sofort
   da; eine Platte mit Staggered Spin-Up moeglicherweise nicht.
3. **Mehrere Geraete am selben Controller.** `find_disk` nimmt den
   ERSTEN Port mit ATA-Kennung. Auf einem Rechner mit zwei SATA-Platten
   ist das nicht zwingend die, auf der Osum liegt. Der Treiber legt die
   anderen Ports wieder still (`port_setup`, `quiet`), aber er kann
   nicht waehlen.
4. **Port-Multiplier und ATAPI.** Beide werden erkannt und
   uebersprungen. Ein optisches Laufwerk (`SIG_ATAPI`) wird nicht
   angesprochen.
5. **64-Bit-Adressen.** `CAP.S64A` wird gelesen und weggeschrieben,
   aber nicht ausgewertet: dieser Kernel legt alle Puffer in das erste
   Gigabyte, das `boot.s` flach abbildet, also stehen die oberen 32 Bit
   ohnehin auf null. Ein Controller ohne 64-Bit-Faehigkeit ist damit
   kein Problem -- aber ein Kernel mit hoher Haelfte waere einer.
6. **Kein NCQ, ein Befehlsplatz von 32.** Der Treiber wartet nach jedem
   Befehl. Das kostet Leistung, nicht Richtigkeit.
7. **Der Treiber fragt ab, statt sich unterbrechen zu lassen.** Das ist
   Absicht (`fs.fi` haelt ueber eine Blockoperation die Unterbrechungen
   aus, `sched.irq_save`), aber es heisst: waehrend eines Blockes
   dreht der Prozessor Leerlaufrunden statt `hlt` zu machen. Auf einer
   langsamen Platte ist das spuerbar.
8. **`SPIN_LIMIT` ist eine Zaehlschleife, keine Uhr.** Sie steht auf
   1 Million, weil unter KVM jeder Registerzugriff ein VM-Austritt ist
   (ein bis zwei Mikrosekunden). Auf blankem Blech laufen dieselben
   Schleifen um Groessenordnungen schneller, die Schranke ist dort also
   deutlich kuerzer als eine Sekunde. Fuer eine SSD reicht das mit
   grossem Abstand; fuer eine anlaufende mechanische Platte
   moeglicherweise nicht.

---

## 6. WAS ALS NAECHSTES FEHLT

* **Automatische Treiberwahl beim Start.** Osum hat jetzt fuenf
  Blockgeraete, aber niemand waehlt beim Start selbstaendig zwischen
  ihnen. Ein `blk.probe(state)`, das NVMe, AHCI, ATA und USB der Reihe
  nach fragt und das erste nimmt, das eine Platte liefert, ist der
  naechste Schritt -- und `ahci.present` / `ahci.ide_mode` /
  `nvme.present` liefern dafuer schon die Antworten.
* **Der zweite harte Blocker.** Dieses Dokument behandelt nur die
  Platte.
* **Ein Lauf auf echtem Blech.** Alles oben ist unter KVM gemessen,
  also auf der echten CPU, aber mit nachgebauten Geraeten. Der
  30.08.2026 ist die erste Gelegenheit, die Punkte aus Abschnitt 5 zu
  pruefen.
