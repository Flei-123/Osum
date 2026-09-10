# RUNDE BLECHVIER -- der Zeitgeber, das Blech unter uns, und ein Kern, der sich selbst misst

Repo `/root/osum-blechhid`. Auslöser: Justins Deep-Research-Ergebnis mit
fünf Befunden. Vier davon haben sich als richtig erwiesen, einer als
falsch, und beim Nachmessen ist ein sechster aufgetaucht, den niemand
gesucht hat.

## BEFUND 1 -- die Messtafel war selbst die Ursache der drei Hertz. RICHTIG.

Bestätigt: `gfx.tafel_tick` lief IM Zeitgeberbehandler, mit `IF=0`. Die
Rechnung stimmt: 396 531 us Vollbild-Blit bei UC, 10 ms Periode, also
39,6 aufgelaufene Marken, von denen GENAU EINE gerettet wird (Intel SDM
Bd. 3, 10.8.4: ein Bit je Vektor in IRR und ISR, alles darüber fällt
still weg). 1 / 0,3965 = 2,52 Hz gegen Justins gemessene rund 3.

**RICHTIGSTELLUNG zum EOI:** der Bericht sagt, das EOI stehe erst in
Zeile 391. Das ist der Durchfall am Ende des Behandlers. Der
Zeitgeberzweig schreibt sein EOI seit jeher weit vorne, vor allem
anderen. Die Koaleszenz kam nicht vom EOI, sondern von `IF=0`.

Gebaut: Herzschlag und Messtafel laufen in einem unteren Stück MIT
eingeschalteten Unterbrechungen. Ein Schlag, der da hineinfällt, zählt
seine Marke und kehrt um, ohne `sched.on_tick` zu rufen -- das würde aus
einer geschachtelten Unterbrechung heraus den Stapel wechseln. Die Marken
kommen aus `rdtsc` statt aus der Zahl der Schläge, mit stehengelassenem
Rest und einer Obergrenze von einer Sekunde.

**Gemessen am fertigen Abbild:** `16 ISR US 317 MAX 33468 VERL 13
SPAET 25`. Fünfundzwanzig Zeitgeberschläge sind in einen laufenden
Anstrich gefallen und wurden gerettet -- ohne diesen Umbau wären genau
das die verlorenen gewesen. Und `8 TAKT ... HZ 99`: die Rate steht als
Zahl da, aus einer von der Unterbrechung unabhängigen Uhr.

## BEFUND 2 -- die PIT-Eichung. RICHTIG in der Sache, aber nachgemessen statt umgebaut.

`grep` bestätigt: kein PM_TMR, kein 0x80000007, kein 0xC0010064, kein
TSC-Deadline. Geeicht wird gegen PIT Kanal 2.

**Zwei Teilbefunde sind aber FALSCH:** die Warteschleife hat längst einen
Zähler und gibt nach rund einer Sekunde auf, statt zu hängen
(`apic.pit_wait`). Und der Teilerwert ist `DIV_16 = 0x3` -- bei der
Eichung UND im Betrieb derselbe. Der Hinweis auf 0xB gegen 0x1 trifft
diesen Baum nicht.

Gebaut: der ACPI-Zeitgeber (feste 3,579545 MHz, von SMIs nicht zu
verfälschen) misst dieselbe Zyklenzahl ein zweites Mal, und die
Abweichung steht in Promille auf der Tafel. **Gemessen: `9 EICH LSR 60
PIT 2200 PM 2199 ABW 0`** -- in QEMU stimmen die zwei Uhren überein. Auf
Justins Ryzen entscheidet genau diese Zahl, ob der Umbau fällig ist. Ihn
vorher zu machen wäre eine Behauptung gewesen.

Ein Fehler dabei, gemessen und behoben: die erste Fassung las den
Zähler in vier Oktettzugriffen zusammen und bekam 33 489 Zyklen je
Sekunde statt 2,2 Milliarden. Der Zähler läuft während der vier Zugriffe
weiter; er will in EINEM 32-Bit-Zugriff gelesen werden.

## BEFUND 3 -- GPE und IOMMU. RICHTIG, und der Diagnoseteil steht.

`grep` bestätigt: null Treffer für GPE, SCI, SMI_CMD, DMAR, IVRS, iommu.
`hw.blech_stage` liest jetzt die FADT, schaltet **alle** GPE-Bits ab
(erst freigeben, dann Status leeren -- RW1C) und liest die IVRS.

**Gemessen: `17 BLECH GPE 16 ST 00 IVR 0000 CTL 0 PMT B008`.** Sechzehn
GPE-Bits abgeschaltet, im Status stand nichts an, keine IVRS in QEMU.
Auf Justins Brett wird genau diese Zeile sagen, ob es dort einen
GPE-Sturm gegeben hätte und ob seine IOMMU wirklich übersetzt.

## BEFUND 4 -- MMIO write-back? WIDERLEGT, und zwar gemessen.

`apic.map_device` setzt seit jeher `PAGE_PCD | PAGE_PWT`, und JEDER
Treiber geht durch diese eine Funktion (xhci, nvme, ahci, e1000, r8169,
ehci, virtio, vmode). Aber "steht im Quelltext" ist nicht "steht in der
Seitentafel" -- genau dieser Unterschied hat beim Rahmenpuffer drei
Runden gekostet. Also zurückgelesen:

**`14 WAHL ... MMU 0FB`** -- PRESENT|WRITE|PWT|PCD|ACCESSED|DIRTY|HUGE.
Der xHCI-Registersatz ist unbeschreibbar abgebildet. Befund 4 ist damit
nicht bloß bestritten, sondern gemessen widerlegt.

## BEFUND 5 -- die drei richtig gebauten Sachen. Bestätigt, nicht angefasst.

Kontextgröße aus HCCPARAMS1, BIOS-Handoff über USBLEGSUP, Scratchpad --
alle drei vorhanden und unverändert.

## USB-Regression: der wahrscheinlichste Grund, und er stand in einer Zeile

`port_reset` begann mit:

```
if port_enabled(state, p) { port_clear_changes(state, p); return true }
```

Ein von der FIRMWARE bereits freigeschalteter Anschluss galt als fertig.
Nach unserem `HCRST` sind unsere Steckplätze weg -- das GERÄT behält aber
seine von UEFI vergebene Adresse, bis es einen echten Reset sieht. Wer
den Reset überspringt, vergibt Adresse 1 an ein Gerät, das noch auf die
alte hört: `Address Device` wird quittiert, die Aufzählung gilt als
geglückt, jeder folgende Steuertransfer läuft ins Leere. Und ob die
Firmware ein Gerät angefasst hat, hängt davon ab, ob im Bootmenü eine
Taste gedrückt wurde -- **perfektes Flattern bei unveränderter Zahl von
Unterbrechungen und Ereignissen**, genau Justins Beobachtung.

Jetzt: Rücksetzung bedingungslos, `PSC_PRC` vorher gelöscht (es ist RW1C
und hätte die Warteschleife sofort zurückkehren lassen), Fehlschläge
gezählt statt verschwiegen. Gegenprobe `usbnoreset`. **Gemessen:
`RVR 1 RFL 0`** -- ein Anschluss musste zurückgesetzt werden, obwohl er
schon freigeschaltet war.

Zwei weitere Punkte der Liste waren schon richtig: der Config-Deskriptor
wird zweistufig gelesen (9 Oktette, dann `wTotalLength`), und `SET_REPORT`
schickt `dg(state, d, D_IFACE)` als `wIndex`, nicht hart null.

## DER SECHSTE BEFUND, den niemand gesucht hat: unter UEFI gab es gar keine ACPI-Tabellen

Beim Nachmessen aufgefallen, weil `hw.blech_stage` leer blieb: derselbe
Kern meldet mit SeaBIOS `smp: cpus=1 acpi=1` und über den Lader mit OVMF
`acpi=0`. `find_rsdp` suchte nur in der EBDA und zwischen 0xE0000 und
0x100000 -- den Orten, an denen ein PC-BIOS den Zeiger hinterlässt. Eine
UEFI-Firmware tut das nicht.

**Justins Brett startet UEFI vom Stick. Dieser Kern hat dort noch nie
eine ACPI-Tabelle gesehen:** keine MADT, keine FADT, keine IVRS. Alle
drei Diagnosen dieser Runde wären auf seinem Rechner leer geblieben.

Gesucht wird jetzt zusätzlich in den Bereichen der Multiboot-Speicherkarte
vom Typ 3 und 4 -- genau dort legt UEFI die Tabellen ab.

**Und das hat einen zweiten, tieferliegenden Fehler freigelegt.**
`proc.fi:264` gibt einem Prozess GENAU EINEN Eintrag des Kernel-PDPT mit:
das erste Gibioctet. Eintrag 1 desselben PDPT ist die Fläche des
Prozesses. Kernelspeicher oberhalb eines Gibioctets ist in Prozesskontext
also nicht abgebildet -- und OVMF legt die ACPI-Tabellen bei 2 GiB RAM um
0x7E000000. Solange nur `smp` und `hw.blech_stage` sie lesen (beide vor
dem ersten Prozess), geht es gut. `batt.fi` geht sie später aus der
Schreibtischschleife noch einmal durch, und dann:

```
*** EXCEPTION 14 #PF err=0x0 cr2=0x5fb7d00f   rip in kstate.get8
```

0x0F ist genau `P_REVISION`: es war der gemerkte RSDP selbst. Behoben in
drei Schritten, jeder einzeln gemessen: eine Grenze für jeden
Tabellenzugriff, der RSDP-Zeiger wird vor dem Zugriff geprüft, und der
Suchlauf benutzt dieselbe Grenze. Ab dem ersten Prozess ist die Grenze
ein Gibioctet (`acpi.nur_erstes_gib`, gerufen aus `proc.fi`).

**Die richtige Lösung wäre, die Tabellen beim Start in den unteren
Speicher zu kopieren.** Das ist eine eigene Runde und steht als solche
hier -- nicht als erledigte.

## Am fertigen Abbild gemessen

Über den Lader (OVMF), 3440x1440, zwei xHCI-Regler, Eintrag 1:

```
acpi: gpe=16 sts=0 pmtmr=45064 bits=24 smi=178
acpi: pmhz=2199978015 pit=2200921800 abw=0
smp: cpus=1  acpi=1
fb: band=438  kol=2
tafel:  8 TAKT   IRQ 4970 MAL 841 LOOP 346 PRE 1 HZ 99
tafel:  9 EICH   LSR 60 PIT 2200 PM 2199 ABW 0 FB WC
tafel: 12 STUFE  ST 38 MAX 38 RND 3369 LOOP 346
tafel: 14 WAHL   HC 1/2 P 0,16 RVR 1 RFL 0 MMU 0FB
tafel: 16 ISR    US 317 MAX 33468 VERL 13 SPAET 25
tafel: 17 BLECH  GPE 16 ST 00 IVR 0000 CTL 0 PMT B008
wm: fen i=0 id=7 x=24 y=438 w=560 h=380
```

Am Bildschirmfoto nachgerechnet: **18 von 18 Tafelzeilen mit Tinte**,
schwarzer Grund 2364 von 2364 Bildpunkten über die ganze Bandhöhe, das
Terminalfenster unter dem Band.

Regression `tools/wm/run.sh`: **104 passed, 0 failed**.
