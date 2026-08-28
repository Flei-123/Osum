# RUNDE AHCI -- DIE PLATTE, DIE EIN ECHTER PC HAT

28.08.2026, Zweig `ahci` (von `mergeline`, nicht nach `main`).

## Das Problem, gemessen

In `kernel/` lagen `nvme.fi` und `virtio.fi`, sonst nichts an DMA-Platten.
Der einzige Weg zu einer SATA-Platte war ATA PIO ueber die Ports von 1986 --
und den gibt es nur, wenn die Firmware auf IDE-Kompatibilitaet steht. Auf
einem gewoehnlichen PC mit SATA-SSD und AHCI-Firmware fand Osum **keine
Platte**: kein Start, keine Installation.

## Was gebaut wurde

* `kernel/ahci.fi` (rund 900 Zeilen): PCI-Klasse `01:06:01` finden, ABAR
  aus **BAR5** abbilden, BIOS/OS-Handoff, HBA-Reset, Port-Enumeration
  ueber PI, Befehlsliste + FIS-Empfangsbereich + Befehlstafel einrichten,
  `IDENTIFY DEVICE`, LBA48 `READ DMA EXT` / `WRITE DMA EXT` /
  `FLUSH CACHE EXT` ueber H2D-Register-FIS. Bis acht Sektoren in einem
  Befehl ueber eine PRDT von acht Eintraegen.
* `DEV_AHCI` (5) in `kernel/blk.fi` -- die vierte Erweiterung dieser
  Schnittstelle **ohne ein zusaetzliches Argument** und ohne eine Zeile in
  `fs.fi`.
* `hw.sata` und das Befehlszeilenwort `ahci` in `kernel/hw.fi`.
* Fuenf Seiten in `kdata` (0x7A000..0x7F000), eingetragen in
  `kstate.fi` und `tools/kernel/memmap.py`.
* `tools/ahci/run.sh` -- der Abnahmeabschnitt, Punkt 29 in `test.sh`.
* `docs/REALHW.md` -- **was auf echter Hardware trotzdem schiefgehen kann**,
  und die Frage nach dem Legacy-IDE/PIO-Rueckfallweg.

## Drei Fehler, die erst die Messung gezeigt hat

1. **ABAR ist BAR5, nicht BAR0.** Ein aus `nvme.fi` abgeschriebener
   Treiber scheitert hier sofort.
2. **`why=8`: die Port-Enumeration ging vor FRE.** `PxSIG` ist kein
   Register, das der Controller von sich aus fuellt -- dort steht, was
   das Laufwerk in seinem ersten D2H-FIS geschickt hat, und EMPFANGEN
   kann der Port erst mit eingetragenem FIS-Bereich und gesetztem FRE.
   Ausserdem steht die Verbindung nach dem HBA-Reset nicht sofort. Die
   erste Fassung fand mit angehaengter Platte nichts.
3. **Die Gegenprobe `nobm` lief in die Zeitschranke des Laeufers.** Nach
   dem ersten unbeantworteten Befehl wartete jeder der tausenden
   Dateisystembloecke die volle Spanne ab. Eine abgelaufene Schranke
   toetet das Geraet jetzt (`dead=1 alive=0`) -- ein Fehler des
   Laufwerks (TFES) dagegen nicht, der ist erholbar.

## Die Zahlen (KVM, `-cpu host`, AMD EPYC 7571, QEMU 7.2.22)

```
ahci: blocks=16384  lbasz=512  port=0  ports=1  slots=32  master=1
ahci: one wr=1  rd=1  pre=0  same=1
ahci: many wr=1  rd=1  n=4096  same=1
ahci: format 1  mount=1
ahci: wrote=30  read=30  same=1
ahci: list .:2 ..:2 sata.txt:1
ahci:   cmds=197  errs=0  dead=0  alive=1
```

Und der WIRT liest das Abbild nach: Sektor 4096 traegt 512 mal `0x5A`,
die Sektoren 5000..5007 tragen je ihr EIGENES Muster, Sektor 5008 ist
unberuehrt, und der Text des Dateisystems steht in der Datei.

| Abschnitt | Ergebnis |
|-----------|----------|
| `tools/ahci/run.sh` | **62 gruen, 0 rot** |
| `tools/pci/run.sh` (Gegenprobe auf Rueckschritt) | 98 gruen, 0 rot |
| `tools/kernel/run.sh` | 176 gruen, 0 rot |
| `tools/kernel/memmap.py` | 69 Bereiche, 0 Kollisionen |

Vier Gegenproben, in denen die Messung zusammenbricht: Controller ohne
Platte (`why=8`), Maschine ohne AHCI (`mode=ide`), ohne Busmaster-Bit
(alles schlaegt fehl, **das Abbild bleibt leer**), und derselbe Lauf
unter TCG (auch gruen).
