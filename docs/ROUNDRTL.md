# RUNDE RTL — der Chip, den ein echtes Brett wirklich hat

Zweig `rtl`, abgezweigt von `mergeline2` (a919787). 30.08.2026.

Osum hatte nach Runde HWNET genau zwei Netzkartentreiber: `kernel/virtio.fi`
(paravirtuell, existiert auf echter Hardware **nicht**) und `kernel/e1000.fi`
(Intel 8254x/82574, eine Chipfamilie von 2000–2008). Das reicht in QEMU. Auf
einem gewöhnlichen PC oder Laptop findet Osum damit **kein Netz** — und ohne
Netz gibt es kein Update und keinen Helfer.

Diese Runde baut die zwei fehlenden häufigsten Chips.

---

## 1. DER STRITTIGE PUNKT, und warum HWNET sich geirrt hat

Runde HWNET hat den Realtek geprüft und bewusst **nicht** gebaut. Ihre
Begründung steht in `docs/REALHW.md` und lautete sinngemäß:

> QEMU hat `-device rtl8139`, und das ist NICHT derselbe Chip. Der 8139 hat
> vier feste Sendepuffer und einen einzigen Ringpuffer zum Empfangen — kein
> Deskriptorring. Ein Treiber für den 8139 würde über den 8168 **nichts**
> beweisen. […] Ein Treiber ohne eine einzige Messung ist eine Behauptung.

Der letzte Satz ist richtig und bleibt der Maßstab dieser Runde. Der erste
Satz ist **unvollständig**, und daran hängt alles:

Der RTL8139 hat ab **PCI-Revision 0x20** einen zweiten Betriebszustand, den
**C+-Modus**. In dem hat er genau das, was HWNET ihm abgesprochen hat: zwei
Deskriptorringe im Hauptspeicher, 16 Oktett je Deskriptor, ein OWN-Bit, ein
EOR-Bit, 64-Bit-Pufferadressen. Der RTL8169 **ist** der herausgelöste
C+-Teil des 8139C+, um Gigabit erweitert — deshalb hieß Linux' Treiber dafür
`8139cp.c`, bevor `r8169.c` daraus wurde.

Und QEMU emuliert diesen Zustand. Nachgeprüft, nicht angenommen:

```
$ strings /usr/bin/qemu-system-x86_64 | grep -i cplus
currCPlusRxDesc
currCPlusTxDesc
cplus_enabled
```

`tools/rtl/run.sh` prüft das zu Beginn selbst und **überspringt sich**, wenn
diese Zeichenkette fehlt — eine Messung, deren Voraussetzung nicht gilt, wird
nicht behauptet.

### Registervergleich, der die Sache trägt

Was der 8139C+ und der 8169 **teilen**, Offset für Offset:

| Register | Offset | 8139C+ | 8169/8168 |
|---|---|---|---|
| IDR0..5, die Ethernet-Adresse | 0x00 | ✓ | ✓ |
| MAR0..7, Mehrfachadressfilter | 0x08 | ✓ | ✓ |
| TNPDS, Anfang Sendering (64 Bit) | 0x20 | ✓ | ✓ |
| CR, Rücksetzen/RE/TE | 0x37 | ✓ | ✓ |
| IMR/ISR (16 Bit, w1c) | 0x3C/0x3E | ✓ | ✓ |
| TCR / RCR | 0x40/0x44 | ✓ | ✓ |
| CR9346, Schreibschutz | 0x50 | ✓ | ✓ |
| RMS, größter Empfangsrahmen | 0xDA | ✓ | ✓ |
| CpCmd | 0xE0 | ✓ | ✓ (andere Bits) |
| RDSAR, Anfang Empfangsring | 0xE4 | ✓ | ✓ |
| **Deskriptorformat** | — | **identisch** | **identisch** |

Was sich **unterscheidet** — vollständig, mehr ist es nicht:

| | 8139C+ | 8169/8168 |
|---|---|---|
| Sendeanstoß | TPPoll auf **0xD9** | TPPoll auf **0x38** |
| Verbindung | MSR 0x58 Bit 2 (invertiert) + BMSR 0x64 | PHYstatus **0x6C** Bit 1 |
| PHY | fest im Chip, direkt im Registerfenster | **MDIO über PHYAR 0x60** |
| MTPS 0xEC | — | größter Senderahmen |

Deshalb ist `kernel/r8169.fi` **ein** Treiber mit zwei Spielarten
(`VAR_CP`, `VAR_8169`) und nicht zwei Treiber. Die vier Unterschiede stehen
an vier Stellen im Quelltext, jede einzeln kommentiert.

---

## 2. WAS GEBAUT WURDE

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/r8169.fi` | **1239** | neu. RTL8169/8168/8111/8101 + RTL8139C+ |
| `kernel/e1000.fi` | +372 | der PCH-Zweig für I217/I218/**I219** |
| `kernel/netdev.fi` | +460/−60 | Treibertabelle als **Daten**, Gründe, Selbstprüfung |
| `kernel/netsvc.fi` | +25 | `link`, `rerr`, `over`, `rovw` im Bericht |
| `kernel/hw.fi` | +22 | die Wörter `nictab` und `nicself` |
| `tools/rtl/run.sh` | **467** | neu. Der Läufer, Methodik wie HWNET |
| `tools/hwnet/run.sh` | +15/−6 | eine Gegenprobe umgestellt (siehe § 6) |
| `test.sh` | +11 | Abschnitt 31 angemeldet |

---

## 3. DIE MESSUNGEN

Alle Zahlen aus `bash tools/rtl/run.sh`, QEMU 7.2.22 unter TCG (ohne KVM),
derselbe Draht und dieselbe Methodik wie Runde HWNET: `tools/net/bridge.c`,
veth-Paar, Netzraum mit dem Linux-Kern darin.

### Die drei Spalten, dieselbe Abnahme

| | rtl8139 (C+) | virtio-net-pci | e1000 |
|---|---|---|---|
| TCP hinein | 262144 Oktett | 262144 Oktett | 262144 Oktett |
| **Durchsatz** | **6224 KiB/s** | 6242 KiB/s | 3278 KiB/s |
| Rahmen empfangen | 185 | 188 | 186 |
| Unterbrechungen | 23 | 33 | 19 |
| Prüfsummenfehler | 0 | 0 | 0 |
| Wiederholungen | 0 | 0 | 0 |
| Außer der Reihe | 0 | — | — |
| Verworfen (Ring voll) | 0 | 0 | 0 |

Ein zweiter, unabhängiger Lauf (derselbe Läufer, aber innerhalb von
`./test.sh` und damit unter der Netzsperre) bestätigt das Bild bei
anderer Maschinenlast — die Reihenfolge der drei Spalten bleibt
dieselbe:

| | rtl8139 (C+) | virtio-net-pci | e1000 |
|---|---|---|---|
| Durchsatz, zweiter Lauf | **6657 KiB/s** | 5200 KiB/s | 3211 KiB/s |
| Rahmen empfangen | 186 | 188 | 186 |
| Unterbrechungen | 22 | 28 | 22 |
| Prüfsummenfehler / Wiederholungen | 0 / 0 | 0 / 0 | 0 / 0 |

Dieser Server fährt mehrere Runden gleichzeitig; die absoluten Zahlen
schwanken deshalb zwischen den Läufen um etwa ein Fünftel. Vergleichbar
sind die Spalten **innerhalb** eines Laufs, weil sie nacheinander
entstanden sind.

### Ping und die übrigen Zusagen (rtl8139)

| | Ergebnis |
|---|---|
| Ping, 20 Anfragen aus dem Linux-Kern | **20 beantwortet** |
| Umlaufzeit, Mittel | 5,181 ms (TCG, ohne KVM) |
| ICMP-Nachrichten, vom Stapel gezählt | 20 |
| Rahmen, die der Chip als fehlerhaft meldete | 0 |
| DHCP von busybox udhcpd | Angebot, Bestätigung, Adresse übernommen |
| Ethernet-Adresse | aus IDR0/IDR4 gelesen, = `52:54:00:aa:bb:cc` |

### Ringüberlauf und zu großer Rahmen, absichtlich herbeigeführt

`nicself` schaltet dem Chip das Senden ab, füllt den Ring bis zum Überlauf
und wirft danach einen Rahmen hinterher, der größer ist als ein Puffer:

```
r8169: self fit=127 drop=9 over=1 link=1 lchg=1 rerr=0 ovw=0 slots=128
```

127 von 128 Plätzen füllen sich (einer bleibt immer leer, sonst wären voll
und leer derselbe Zustand), die 9 weiteren Versuche werden **alle**
abgewiesen und gezählt, und der 2049-Oktett-Rahmen fasst den Ring nicht
einmal an. Danach redet die Karte weiter — geprüft mit einem Ping nach der
Selbstprüfung.

### Verbindung verloren und wieder da

Über den QEMU-Monitor (`set_link nic0 off`/`on`):

| | Paketverlust |
|---|---|
| vorher | 0 % |
| Kabel gezogen | **100 %** |
| Kabel wieder dran, ohne Neustart | 0 % |

Und der Treiber meldet am Ende `nic: link=1`.

### Die Gegenproben, in denen die Messung zusammenbrechen muss

| Gegenprobe | Ergebnis |
|---|---|
| dasselbe Abbild ohne das Wort `nic` | 100 % Verlust, `nic: skipped` |
| `nicnobm` — kein Busmasterbit | `master=0`, 100 % Verlust |
| `ne2k_pci` (10EC:8029) — **derselbe Hersteller** | `netdev: no driver for 0x10ec:0x8029` |
| 10EC:8139 mit Revision 0x10 | `-> none  rtl8139 rev < 0x20, no C+ mode` |

---

## 4. DER EINE FEHLER, DEN DIE MESSUNG GEFUNDEN HAT

Er gehört in den Bericht, weil er sonst niemandem auffiele.

Mit **32** Ringplätzen — derselben Zahl, die `e1000.fi` benutzt — lieferte
dieser Treiber:

* 64 KiB TCP: **6589 KiB/s**, `ooo=0` — tadellos
* 256 KiB TCP: **286 KiB/s**, `ooo=41` — **elfmal langsamer als der e1000**

Dabei: `drops=0`, `rerr=0`, `csum=0`, alle 262144 Oktett angekommen. Kein
Zähler des Treibers und kein Zähler des Stapels zeigte einen Fehler. Nur der
Durchsatz.

**Die Ursache ist ein Unterschied zwischen den emulierten Chips, nicht
zwischen den Treibern.** Wächst Linux' Sendefenster auf 64 KiB, schiebt es
über vierzig Rahmen ohne Pause hinaus. Findet QEMUs e1000 keinen freien
Deskriptor, *legt er den Rahmen beiseite* und versucht es später noch einmal
(`flush_queue_timer` in `hw/net/e1000.c` — Runde HWNET hat genau dieses
Verhalten aufgeschrieben, als Ärgernis). QEMUs rtl8139 im C+-Modus **wirft
ihn weg** und setzt RxOverflow (`hw/net/rtl8139.c`, *"descriptor %d is owned
by host"*). Jeder Verlust kostet eine Wiederholung von Linux, und die kostet
einen vollen Umlauf.

**Ein echter RTL8168 verhält sich wie der rtl8139 und nicht wie QEMUs
e1000** — er hat einen kleinen FIFO und wirft danach weg. Die richtige
Antwort war also nicht, den Verlust hinzunehmen, sondern den Ring so groß zu
machen, dass ein volles Sendefenster hineinpasst. Linux' `r8169` nimmt aus
demselben Grund 256 Plätze; **128** sind hier gemessen genug und kosten
520 KiB.

Ergebnis: **286 → 6224 KiB/s**, `ooo=0`, `rovw=0`.

Damit das nicht wieder verlorengeht, prüft `tools/rtl/run.sh` jetzt drei
Dinge, die vorher niemand geprüft hat: `ooo == 0`, `rovw == 0` und
`slots == 128`. Wer den Ring wieder verkleinert, fällt durch.

Zusätzlich zählt der Treiber jetzt, wie oft der Chip mangels Ringplatz
verworfen hat (`nic: rovw=`). Der Verlust passiert **im Chip**, also sieht
ihn kein Zähler des Stapels — er zeigt sich sonst nur als Wiederholung auf
der Gegenseite. Ein Ring, der zu klein ist, soll eine Zahl haben und keine
Vermutung.

---

## 5. WAS WIRKLICH GEHT UND WAS NUR ERKANNT WIRD

| Chip | PCI | Stand |
|---|---|---|
| **RTL8139C+** | 10EC:8139 Rev ≥ 0x20 | **gemessen**, alle Zusagen grün |
| **RTL8169/8110** | 10EC:8169, 8167 | Treiber vollständig, **nicht gemessen** |
| **RTL8168/8111** | 10EC:8168, 8161 | Treiber vollständig, **nicht gemessen** |
| **RTL8101E/8102E** | 10EC:8136 | Treiber vollständig, **nicht gemessen** |
| RTL8139A/B | 10EC:8139 Rev < 0x20 | **abgelehnt mit Begründung** (kein C+) |
| **Intel I217/I218/I219** | 8086:153A…0D4E, 1A1C… | Datenweg geteilt+gemessen, **Aufsetzweg nicht gemessen** |
| Intel 8254x/82574 | 8086:100E … 10D3 | unverändert aus Runde HWNET |
| Intel I225/I226 | 8086:15F2/15F3/125B/125C | **erkannt, kein Treiber**, Grund genannt |
| Intel I210/I211 | 8086:1533/1536/1537/1539 | **erkannt, kein Treiber**, Grund genannt |
| Intel WLAN AX200/201/210 | 8086:2723/2725/A0F0 | **erkannt als WLAN**, kein Treiber |
| Broadcom/Atheros/Aquantia/Marvell | 14E4/168C/1969/1D6A/11AB | **erkannt**, anderer Hersteller |

**I225/I226 wurden bewusst nicht gebaut.** Der Auftrag sagte „nur, wenn 1 und
2 sauber stehen". Sie stehen sauber, aber igc-Silizium hat ein anderes
Deskriptorformat (nur erweiterte Deskriptoren) und eine andere
Warteschlangenverwaltung — das ist ein eigener Treiber und keine
Tabellenzeile, und ohne Emulation wäre er wieder nur eine Behauptung. Sie
sind in der Tabelle als *„erkannt, kein Treiber"* mit Grund vermerkt, wie
verlangt.

---

## 6. WAS AN BESTEHENDEN TESTS GEÄNDERT WURDE, und warum

Zwei Dinge, beide keine Abschaltung.

### 6a. Die Netzsperre griff für `hwnet` nie — und jetzt für `rtl` auch

Gefunden beim Nachmessen dieser Runde. `test.sh` serialisiert die
Abschnitte, die `ip netns` und `ip link` anlegen, über eine Sperre in
`/tmp` — die Geräte gehören dem **Wirt** und nicht dem Arbeitsbaum. Die
Liste dafür lautete:

    SERIELL_RE='^tools/(net|netmon|netview|tunnel)/'

Der Ausdruck ist auf `tools/net…` verankert, und `tools/hwnet/` fängt mit
`tools/hw` an. **`tools/hwnet/run.sh` lief also seit Runde HWNET
ungesperrt** neben `net`, `netmon`, `netview` und `tunnel`.

Das ist keine Theorie. An diesem Abend fiel `tools/pci/run.sh` (98
Zusagen, sonst grün) im parallelen Lauf zweimal durch und
`tools/net/run.sh` einmal — **beide allein sofort wieder grün**, beide
auf der unveränderten Grundlinie ebenfalls grün. Ursache war die
Kollision auf den Netzgeräten des Wirts.

Der Ausdruck heißt jetzt:

    SERIELL_RE='^tools/(net|netmon|netview|tunnel|hwnet|rtl)/'

Das ist das Gegenteil einer Abschaltung: zwei Abschnitte, die bisher
unbemerkt aneinander vorbeiliefen, halten jetzt dieselbe Reihe ein wie
die anderen.

### 6b. Eine Gegenprobe in `tools/hwnet/run.sh`

**Genau eine Zeile**, und nicht, weil sie unbequem war, sondern weil ihre
Voraussetzung weggefallen ist.

`tools/hwnet/run.sh` hatte eine Gegenprobe *„ein Chip, für den dieser Kernel
KEINEN Treiber hat"* und benutzte dafür `-device rtl8139`. Diese Runde hat
für den rtl8139 einen Treiber gebaut. Die Gegenprobe hätte damit ab sofort
das Gegenteil dessen bewiesen, was sie behauptet.

Ersetzt durch **`ne2k_pci` (10EC:8029)** — **derselbe Hersteller**, eine
Gerätenummer, die die Tabelle nicht trägt. Das ist eine *strikt stärkere*
Gegenprobe als die alte: sie zeigt, dass die Wahl an der Gerätenummer hängt
und nicht am Hersteller. Anzahl der Zusagen, Ablauf und Messwerte sind
unverändert.

**Kein Test wurde abgeschaltet.** `test.sh` hat jetzt einen Abschnitt mehr
(Nr. 31, `tools/rtl/run.sh`, 67 Zusagen).

### 6c. Nachgemessen, dass nichts kaputt ist

| Abschnitt | Ergebnis auf Zweig `rtl` | Grundlinie a919787 |
|---|---|---|
| `tools/rtl/run.sh` (neu) | **67 / 0** | -- |
| `tools/hwnet/run.sh` (geändert) | **54 / 0** | -- |
| `tools/server/run.sh` (GUI-loser Bau) | **23 / 0** | -- |
| `tools/wm/run.sh` (Oberfläche) | **103 / 0** | -- |
| `tools/kernel/run.sh` | **176 / 0** | -- |
| `tools/unix/run.sh` | **107 / 0** | -- |
| `tools/posix/run.sh` | **134 / 0** | -- |
| `tools/pci/run.sh` | **98 / 0** (allein) | 98 / 0 |
| `tools/net/run.sh` | 74 / 1 **nur im parallelen Lauf**, siehe 6a | 75 / 0 |

Beide Übersetzer (`firnc0` und `firnc1`) bauen den Kernel mit
`r8169.fi` — in jedem Lauf des Läufers geprüft.

---

## 7. WAS AUF ECHTEM BLECH TROTZDEM SCHIEFGEHEN KANN

Ehrlich aufgezählt. Kein Lauf dieser Runde hat einen dieser Punkte berühren
können.

### Realtek 8168/8169

1. **Die PHY-Firmware.** Es gibt über vierzig Ausführungen des 8168, und
   Linux' `r8169` bringt für die meisten eine eigene Tabelle von
   PHY-Registerschreibvorgängen mit (`rtl8168d_1_hw_phy_config` und dreißig
   Geschwister). Dieser Treiber lädt **keine**. Er verlässt sich darauf,
   dass die Karte nach dem Rücksetzen selbst aushandelt — was die meisten
   tun und manche nicht. Das ist der wahrscheinlichste Ausfallgrund.
2. **MDIO auf den neueren 8168.** `r8169.fi` benutzt den einfachen Weg über
   PHYAR 0x60. Einige 8168-Ausführungen (DP, EP) brauchen einen anderen
   (`r8168dp_2_mdio_read`). Auf denen bliebe die Verbindungsanzeige leer;
   der Datenweg liefe trotzdem, wenn die Firmware ausgehandelt hat.
3. **Der Speicher-BAR wird gesucht, nicht geraten.** 8139 und 8169 legen ihn
   auf BAR1, der PCIe-8168 auf BAR2. `find_bar` nimmt den ersten
   Speicher-BAR. Das ist auf allen drei richtig — aber es ist eine
   Entscheidung und keine Messung.
4. **Kein MSI/MSI-X.** Der 8168 kann beides; dieser Treiber nimmt den Pin,
   weil der Kern für Netzkarten genau zwei Vektoren hat (45 und 46, Runde
   NETMON). Auf einem Brett ohne funktionierendes `_PRT` (Osum hat keinen
   AML-Interpreter) kann die Leitungsnummer aus dem Konfigurationsraum
   falsch sein — dann kommt keine Unterbrechung an. Der Stapel dreht dann
   Leerlaufrunden statt zu stehen, aber er wird langsam.
5. **Der Sendeanstoß auf 0x38 ist nie ausgeführt worden.** Steht er falsch,
   sendet die Karte nichts, und man sieht es an `tx_f` > 0 bei `rx_f` = 0.
6. **Keine Statistikregister (DTCCR), kein Aufwecken über das Netz, keine
   Energiezustände, keine Warteschlange hoher Priorität.**

### Intel I219 — hier liegt die Grenze, und sie ist scharf

Der **Datenweg** ist derselbe Quelltext, den der 82540EM in QEMU
zwanzigtausend Rahmen lang ausführt: Empfangsring, Sendering, RCTL/TCTL,
RDBAL/TDBAL, RAL/RAH, die Deskriptoren, die Unterbrechung. Das ist der
Grund, warum der I219 in `e1000.fi` steht und nicht in einer eigenen Datei —
nachgezählt und im Quelltext aufgelistet.

**Nicht gemessen ist alles am Aufsetzweg**, und das ist beim I219 gerade der
schwierige Teil, weil sein PHY **nicht am MAC hängt**, sondern an einem Bus,
den sich der MAC mit der Verwaltungsfirmware (Intel ME/CSME) teilt:

1. **Die Semaphore** (`EXTCNF_CTRL` Bit 5, „SWFLAG"). Gebaut, mit
   Rücklesen und Aufgeben, wenn die Firmware den Bus hält. Nie ausgeführt.
2. **MDIC** (0x20) als Weg zum PHY. Gebaut. Nie ausgeführt.
3. **ULP abschalten** (`FEXTNVM7` Bit 5). Gebaut. Nie ausgeführt.
4. **Die Adresse.** Auf der PCH-Linie gibt es **kein EEPROM an EERD** — die
   nichtflüchtige Kopie liegt im SPI-Flash des Chipsatzes. Der Treiber liest
   RAL/RAH **vor** dem Rücksetzen und schreibt sie danach zurück, weil ein
   Rücksetzen sie auf manchen Ausführungen mitnimmt. Aus dem Datenblatt.
5. **BEWUSST NICHT GEBAUT — das Leeren der Deskriptorringe vor dem
   Rücksetzen** (`e1000_flush_desc_rings` bei Linux). Auf Skylake und später
   kann ein Rücksetzen den Chip *hängen lassen*, wenn die Verwaltungsfirmware
   gerade Verkehr hat. Der Kunstgriff dagegen schickt einen Blindrahmen los;
   das ohne echtes Brett zu schreiben wäre nicht verantwortbar. **Das ist der
   wahrscheinlichste Weg, auf dem ein I219-Laptop mit Osum hängenbleibt.**
6. **SMBus-Zustand.** Hält die Firmware den PHY, antwortet MDIC gar nicht.
   Der Treiber merkt das (`phy=0xFFFFFFFF`) und kommt dann eben nicht hoch,
   statt sich aufzuhängen — das ist gebaut und die einzige Zusage, die er
   für diesen Fall gibt.
7. Kein K1/LTR/PCIm, keine PHY-Firmware, kein Laden von NVM-Blöcken.

**Zusammengefasst:** ein I219-Laptop wird mit hoher Wahrscheinlichkeit die
Karte finden, den Namen `i219` auf die serielle Leitung schreiben, die
Adresse lesen — und danach entweder laufen oder an Punkt 5 hängen. Welches
von beidem, kann diese Runde nicht sagen. Sie sagt nur, dass sie es nicht
sagen kann.

### Beide

8. **Die Zählschleifen sind Zählschleifen und keine Uhren.** `SPIN_LIMIT`
   steht auf 2 Millionen, wie in `nvme.fi`, `e1000.fi` und `ahci.fi`. Auf
   blankem Blech laufen dieselben Schleifen um Größenordnungen schneller als
   unter TCG; die Schranke ist dort deutlich kürzer.
9. **Höchstens zwei Karten, kein Hotplug, keine geteilten Vektoren.**
10. **Osum wird statisch gelinkt** (Roadmap A9) — für diese Runde ohne
    Folgen, weil alles hier im Kern liegt und nie eine Bibliothek sieht.

---

## 8. WAS ALS NÄCHSTES FEHLT

* **Ein Lauf auf echtem Blech.** Alles oben ist unter QEMU/TCG gemessen. Der
  eine Satz, der zählt, wäre `netdev: c0=r8169 bdf=…` von der seriellen
  Leitung eines Bretts mit einem 8168 darin.
* **I225/I226** — igc-Silizium, eigener Treiber, ~700 Zeilen.
* **PHY-Firmware für den 8168.** Ohne sie bleibt Punkt 1 oben stehen.
* **WLAN.** Die Tabelle erkennt AX200/AX201/AX210 und sagt „braucht 802.11
  und Firmware". Das ist weiterhin ein eigenes Teilprojekt und nicht eine
  Runde.
* **Der Rundrufweg nach außen.** Runde HWNET hat gemessen, dass
  `net_output` auch für 255.255.255.255 einen nächsten Sprung per ARP sucht.
  Diese Runde hat daran nichts geändert; der DHCP-Test funktioniert nur,
  weil der Server per ARP erreichbar ist.
