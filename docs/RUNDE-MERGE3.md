# Runde MERGE-3 — `mergeline2` nach `main`, und ein Abbild für echtes Blech

Arbeitsbaum `/root/osum-merge3`, Zweig `merge3`, abgezweigt von `main`
(`018982a`). Gemessen am 01./02.09.2026 auf dem üblichen Wirt
(AMD EPYC 7571, 12 Kerne, 19 GiB, `/dev/kvm` vorhanden).

**Die Runde hatte drei Aufträge, und alle drei sind erledigt.** Was
dabei gefunden wurde, ist mehr als der Merge selbst: vier rote
Abschnitte, von denen drei repariert sind, und die vier alten roten
Abschnitte von `main` sind inzwischen alle grün.

---

## TEIL 1 — DIE UNGESICHERTE ARBEIT ZWEIER RUNDEN

Zwei Runden sind in ihr Zeitlimit gelaufen, bevor sie committen
konnten. Beide Arbeitsbäume sind jetzt gesichert. **Nichts wurde
weggeworfen, nichts halb committet, ohne es zu sagen.**

### (a) `/root/osum-ofs4`, Zweig `ofs4` → Commit `63003c0`

Vorher: **null eigene Commits.** Der ganze Stand lag unversioniert im
Arbeitsbaum.

| Datei | | Was |
|---|---:|---|
| `kernel/fs.fi` | +542 | `grow_to`, `shrink_to`, `shrink_fits`, `shrink_need`, `shrink_room`, `resize_moved`, `resize_cap`; Blockumzug über alle drei Zeigerstufen; Deckel des Zuteilers (`G_CAP`) und Umzugszähler (`G_MOVED`), beide nur im Arbeitsspeicher |
| `kernel/sys.fi` | +97 | `SYS_OSUM_FSRES` (1840): zwölf Auskünfte, zwei Taten (nur root), keine Zeiger aus Ring 3 |
| `lib/libc/kcall.fi` | +2 | dieselbe Nummer in der libc — sonst wird `tools/posix/run.sh` rot |
| `kernel/user/ofs4.fi` | 711 | neu: die Messung in Ring 3 |
| `tools/ofs4/run.sh` | 425 | neu: die Abnahme, acht Abschnitte |
| `tools/ofs4/crash.sh` | 148 | neu: Stromausfall mitten im Größenwechsel |
| `tools/ofs4/pruef.py` | 197 | neu: dieselbe Prüfung auf dem Wirt |
| `docs/OFS4-ENTWURF.md` | 478 | neu: der Entwurf |
| `docs/ROUNDOFS4.md` | 256 | neu: der Bericht der Runde |

**Fertig und grün** (Zahlen der Runde OFS4 selbst, `tools/ofs4/run.sh`,
rc=0, 62 Prüfungen bestanden, 0 gescheitert): online wachsen (eine
Journalumschreibung, 55 ms), online verkleinern (32768 → 2778 Blöcke,
`need`=328 = `moved`=328, 30994 ms), 50 Abschüsse mit SIGKILL ohne einen
einzigen `fsck`-Fehler, genau zwei Größen danach und nie etwas
dazwischen.

**Nicht fertig, ausdrücklich:** die Zählerkarte für Schnappschüsse ist
**nur entworfen** (`docs/OFS4-ENTWURF.md`, Abschnitt 8) und nicht
gebaut. Das war die Entscheidung der Runde und ist die richtige.

**Was MERGE-3 nicht getan hat:** `tools/ofs4/run.sh` wurde hier nicht
erneut gefahren (er braucht über eine halbe Stunde). Die Zahlen sind als
Messung der Runde OFS4 zu lesen. Geprüft wurde nur die Schlüssigkeit:
`sys.fi` ruft genau die Namen, die `fs.fi` ausführt, und
`SYS_OSUM_FSRES` steht in beiden Tafeln auf 1840.

### (b) `/root/osum-ota`, Zweig `ota` → Commit `da48676`

Vorher: drei Commits, aber der Rest ungesichert.

Gerettet wurde die Reparatur eines Tests, **der nichts gemessen hat**:
Fall (e) — dreißigmal der Stecker mitten im Einspielen — stand mit 30
von 30 grün da, und darunter stand `alt=30 neu=0`. Kein einziger Schuss
lag hinter dem Umschalten; die Spanne 1–16 s war geschätzt, gemessen
fängt das Netz erst bei 9,8 s an und geschrieben wird bei 22,7 s.

* `tools/ota/zeitprobe.sh` (89 Z, neu) — stempelt jede serielle Zeile
  mit der Zeit seit dem Start von QEMU.
* `tools/ota/warte_marke.py` (48 Z, neu) — wartet auf eine **Marke, die
  die Maschine selbst gedruckt hat**, statt auf die Uhr des Wirts.
* `tools/ota/run.sh` — Abschnitt 5 richtet jeden Schuss an einer von
  drei Marken aus und **prüft sich selbst**: kommt kein einziges „neu"
  (oder kein einziges „alt") heraus, fällt der Abschnitt durch. Dazu
  zwei stille Messfehler behoben (Feld 5 statt 6 aus dem Protokoll der
  Gegenstelle, und `df` wurde nie aufgerufen).
* `docs/OTA.md` — Abschnitt 7 mit der Marken-Tabelle.
* `tools/ota/.e5-probe.sh` (269 Z) — **mitgesichert, aber kein Teil der
  Abnahme**: ein abgespeckter Ausschnitt von `run.sh` mit dem ALTEN,
  uhrbasierten Schusszeitpunkt. Steht in der Commit-Botschaft.

**Hinweis:** die Runde OTA arbeitet in diesem Arbeitsbaum weiter (zur
Commit-Zeit liefen dort `tools/ota/run.sh --probe`-Läufe). Der Commit
hat nur festgehalten, was dalag; keine Datei wurde verändert.

---

## TEIL 2 — `mergeline2` NACH `main`

### Der Merge selbst: ein Vorspulen, null Konflikte

```
git rev-list --count main..mergeline2   ->  164
git rev-list --count mergeline2..main   ->    0
git merge-base --is-ancestor main mergeline2  ->  wahr
```

`main` (`018982a`) ist ein **direkter Vorfahr** von `mergeline2`
(`94c12fd`). Der Merge ist deshalb ein Fast-Forward, und es gab **keinen
einzigen Konflikt** — es gab keinen, den es hätte geben können. Das ist
kein Glück, sondern das Ergebnis der Runde MERGE-2: die 164 Commits
enthalten 30 Merge-Commits, in denen 18 Zweige bereits gegeneinander
aufgelöst wurden:

`kvmfix`, `rename-etc`, `k-merge2`, `ahci`, `poll`, `handle`,
`serverbuild`, `multiuser`, `init`, `fsrobust`, `update`, `sshd`,
`usbimg`, `umlaut2`, `themestore`, `softui`, `async`, `customres`.

Die dort getroffenen Konfliktentscheidungen stehen in den jeweiligen
Merge-Botschaften (z. B. die Ausfuhrliste in `kernel/user/wlib.fi`, die
`window_app` aus `paint` **und** `set_menu_title` aus `look` braucht).
MERGE-3 hat daran nichts geändert.

**Folge für die Abnahme:** nach dem Vorspulen ist der Baum von `main`
Datei für Datei derselbe wie der von `mergeline2` (`git diff --stat
mergeline2` = leer). Eine Messung „vorher auf mergeline2" und eine
Messung „nachher auf main" wären daher zweimal dieselbe Messung. Es
wurde deshalb **einmal** gemessen, und diese Zahl gilt für beide.

### Die Abnahme

**Voller Lauf**, `OSUM_JOBS=4`, `accel=auto`, 01.09.2026 19:53–22:30
(2 h 37 min), Protokoll `/root/m3logs/ABNAHME-1-mergeline2.log`:

| | Abschnitte | grün | rot | Zusagen |
|---|---:|---:|---:|---:|
| `main` **vorher** (`018982a`, Zahlen aus `STATUS-MERGE.md`) | 40 | 36 | 4 | 3360 |
| `main` **nachher** (= `mergeline2`, `94c12fd`) | **54** | **50** | **5** | **4309** |

**Wichtig zur Aussagekraft:** auf demselben Wirt lief gleichzeitig die
Runde AVX ihre eigenen vollen Messungen (Lastmittel zeitweise über 30,
bis zu 21 QEMU-Prozesse). Deshalb wurde **jeder rote Abschnitt einzeln
nachgemessen** (`OSUM_JOBS=1`, Lastmittel unter 8) — genau das Verfahren
der Runde MERGE-FINAL.

### DIE VIER ALTEN ROTEN VON `main` SIND ALLE GRÜN

Das ist das erste Ergebnis dieser Runde, und es war nicht erwartet:

| Abschnitt | auf `main` vorher | jetzt |
|---|---|---|
| `k14` | 151 / 1 | **152 / 0** ✅ |
| `k16` | 58 / 6 | **64 / 0** ✅ |
| `tunnelpakete` | 15 / 3 | **grün** ✅ |
| `icons` | 24 / 1 | **25 / 0** ✅ (nach der Reparatur unten) |

### Die fünf roten aus dem vollen Lauf, einzeln nachgemessen

| Abschnitt | voller Lauf | einzeln, ruhiger Wirt | Urteil |
|---|---|---|---|
| `k15` | 249 / 3 | 249 / 3 | **echt** → repariert, jetzt **252 / 0** |
| `icons` | 15 / 12 | 15 / 12 | **echt** → repariert, jetzt **25 / 0** |
| `tresor` | 212 / 7 | 212 / 7 | **echt** → repariert, jetzt **220 / 0** |
| `netview` | 191 / 4 | **192 / 3** | eine Zusage war Last, **drei sind echt** → siehe unten, **offen** |
| `netmon` | 75 / 1 | **76 / 0** | **Lastphantom** — einzeln vollständig grün |

### Der Stand nach den Reparaturen

| | Abschnitte | grün | rot | Zusagen |
|---|---:|---:|---:|---:|
| `main` **vorher** (`018982a`) | 40 | 36 | 4 | 3360 |
| `main` **nachher**, roh gemessen unter Fremdlast | 54 | 50 | 5 | 4309 |
| `main` **nachher**, nach den drei Reparaturen | **54** | **53** | **1** | **4309+** |

Die eine rote ist `netview`, und sie ist unten benannt. **Keiner der
vier alten roten Abschnitte ist noch rot.**

---

## DIE DREI REPARATUREN, JEDE MIT IHRER MESSUNG

### 1. `icons` — das Prüfabbild war zu klein geworden (Commit `78cf416`)

```
  FAIL  mkfs failed
mkfs: the disk is full
```

`bau_img` in `tools/icons/run.sh` baute ein OFS-Abbild von **4096
Blöcken (2 MiB)**. Die neun Programme dieses Abschnitts sind mit
`softui`, `themestore` und `paint` gewachsen, der Baum aus
`k15/tree.py` mit ihnen — es passt nicht mehr hinein. Weil ohne Abbild
nichts in Ring 3 läuft, war das **ein** Fehler mit **elf** Folgefehlern:
der Abschnitt fiel von 24/1 auf 15/12.

**Behoben:** 16384 Blöcke (8 MiB) statt 4096, rund das Vierfache des
Inhalts. Keine Zusage entschärft — das Abbild ist nur groß genug.
**Gemessen: `icons: 25 ok, 0 failed`.** Damit ist auch die alte rote
Zusage von `main` („`lib/icons.fi` lässt sich aus der Karte nicht
reproduzieren") grün.

### 2. `k15` — ein Tippfehler und ein zu kurzes Warten (`78cf416`, `57842e0`)

**(a) `karte` statt `kartv`.** Commit `ad5d5d0` (Runde ASYNC) hat die
Speicherkarte einmal geholt und in `kartv` abgelegt; die Zeile darunter
las weiter `$karte`. Unter `set -u`:

```
tools/k15/run.sh: line 256: karte: unbound variable
  FAIL  der Bereich liegt im zugeteilten Vorrat: '' statt '0x46000 0x49000 '
```

Behoben in `tools/k15/run.sh:256` **und** `tools/wm/run.sh:229` (dort
betraf es nur die Textausgabe, „die Vektortabelle ist
überschneidungsfrei ()", die Zusage selbst hängt an einem eigenen
Aufruf und war grün). Nachgerechnet: `memmap.py kernel -v` meldet für
`WIG` weiterhin `0x46000..0x49000` — der erwartete Wert stimmt
unverändert. → 249/3 wurde 250/2.

**(b) Zwei Bildpunktprüfungen in Abschnitt 9b.**

```
  FAIL  die erste davon steht im Bild -- 8 Zeichen, 372 Tintenpunkte
        geprueft, 283 falsch -- LEER: p m
  FAIL  und der alte Inhalt steht NICHT mehr da -- ging durch
```

**Der Dateimanager war nicht schuld.** In derselben seriellen Ausgabe
steht `explorer: cd /data/bilder` mit `n=2` — er ist hineingegangen und
hat die zwei Dateien gefunden. Nur das **Bild** zeigte nach einer
Sekunde noch die alte Tabelle.

**Die Messung**, mit einer Kopie des Läufers, die nach 9b aussteigt,
sonst Zeile für Zeile gleich:

| Wartezeit | Ergebnis |
|---|---|
| `warte 1.0` | 2 rote Haken |
| `warte 4.0` | **121 passed, 0 failed** |

Ein Neuzeichnen ist mit dieser Zusammenführung teurer geworden: SOFTUI
zeichnet weiche Kanten, PAINT legt einen Fenster-Zwischenpuffer davor.
Die eine Sekunde war auf dem Stand **vor** diesen Runden geeicht. Also
4.0 statt 1.0, mit der Begründung im Quelltext. Es ist keine Zusage
entschärft: dieselben Bildpunkte an derselben Stelle, nur nachdem das
Neuzeichnen sicher durch ist. **Gemessen: `K15: 252 passed, 0 failed`.**

### 3. `tresor` — die Frist, nicht der Kern

```
  FAIL  der Geheimnislauf endet ordentlich: '124', erwartet '21'
```

**124 ist der Rückgabewert von `timeout`.** Sechs weitere Zusagen fielen
mit, weil ihre Zahlen aus der Ausgabe genau dieses Laufs kommen.

**Die Messung**, mit einer Kopie des Läufers, die jede Startdauer
mitschreibt (Wirt ruhig, Lastmittel unter 4):

| Lauf | Dauer |
|---|---:|
| `sec2` (der Geheimnislauf) | **254 s** ← alte Frist: 240 s |
| `mess` | 124 s |
| `orph` | 118 s |
| `backup` | 84 s |

Der längste Lauf liegt **14 Sekunden** über der alten Frist. Mit 900 s
lief derselbe Abschnitt vollständig durch: **220 bestanden, 0
gescheitert**. Gesetzt sind jetzt **480 s** — knapp das Doppelte des
gemessenen Wertes, genug Luft für einen belasteten Wirt und immer noch
eine Frist, die einen echten Hänger abfängt.

---

## WAS OFFEN BLEIBT — ehrlich benannt

### `netview`: der Zustandsknopf „online" (drei Zusagen, echt)

Einzeln nachgemessen, ruhiger Wirt: **192 bestanden, 3 gescheitert.**

```
  FAIL  online: falsch 40 von 82
  FAIL  faking: the state icon went missing: falsch 40 von 82
  FAIL  9a: both Super+A presses became hotkeys: 1, expected eq 2
```

Die ersten beiden sind **dieselbe Prüfung an zwei Stellen**: das
gezeichnete Zeichen für „online" wird an der Stelle, die die Leiste
selbst gemeldet hat, gegen `assets/netview/state-online.txt` gehalten,
und **40 von 82 deckenden Bildpunkten stimmen nicht**. Die drei anderen
Zustandszeichen (`nocarrier` 52/52, `noip` 52/52, `noroute` 68/68) gehen
durch denselben Code und sind **grün** — es ist also nicht der Prüfer
und nicht die Stelle, sondern dieses eine Zeichen. Der wahrscheinliche
Grund ist die Alpha-Mischung aus der Runde PAINT auf einer **gefüllten**
Fläche (`state-online` ist als „ausgefüllter Schirm ohne Abzeichen"
gezeichnet, die anderen drei tragen Umrisse und Abzeichen). Ob die
Zeichnung oder die Maske falsch ist, ist damit **nicht entschieden** —
und eine Maske zu ändern, ohne das entschieden zu haben, wäre genau der
Fehler, den diese Runde bei `icons` gerade aufgeräumt hat.

Die dritte Zusage (`9a: both Super+A presses became hotkeys: 1`) ist
eine Tastenfolge, die einmal statt zweimal ankam.

**Das ist eine Regression gegenüber `main`** (dort war `netview` grün)
und die einzige, die diese Runde nicht behebt. Sie kommt **nicht** aus
dem Merge-Vorgang — der war ein Vorspulen —, sondern aus einem der 164
Commits von `mergeline2`. Sie gehört in eine eigene Runde, die die
Zeichnung des Knopfes gegen die Maske hält und dann entscheidet, welche
von beiden falsch ist.

### `netmon`: geklärt, es war die Last

Im vollen Lauf: 75 / 1, gescheitert an
`files fetched over HTTP through the NAT: 2, expected ge 3` — eine
Netz-Zeitzusage.

Die Nachmessung musste lange warten: `netmon` läuft unter der
wirtweiten Netzsperre `/tmp/osum-netz.lock`, und die parallel laufende
Runde AVX hat sie über Stunden gehalten. Sie ist dann aber gelaufen, auf
ruhigem Wirt: **`NETMON: 76 passed, 0 failed`.** Also ein Lastphantom
und **kein** Schaden aus dem Merge. Nichts zu reparieren.

---

## TEIL 3 — DAS ABBILD FÜR ECHTES BLECH

### Gebaut aus dem gemergten Stand

```
bash tools/usbimg/build.sh /root/m3logs/usbimg
```

| | |
|---|---|
| Abbild | **123 731 968 Oktette** (118 MiB) |
| **SHA-256** | `1bf0609d12be8830f7ed59580f1a77a5e79ff83c1aaf117a6b914981b4df1031` |
| Kern | 3 313 608 Oktette |
| Programme in Ring 3 | 43 |
| Wurzeldateisystem | 20 971 520 Oktette, OFS v3 |
| Aufteilung | GPT: Partition 1 `OSUM-EFI` (EF00, FAT32, 96 MiB), Partition 2 `OSUM-ROOT` (8300, 21 MiB) |
| Pflichtpfade nachgezählt | 24 |
| Umlaute im Wurzelabbild | 126 UTF-8-Folgen |

### Beide Startwege, gemessen

`bash tools/usbimg/run.sh /root/m3logs/usbrun` → **`USBIMG: 46
bestanden, 0 gescheitert`**, unter `-accel kvm -cpu host`, also auf der
echten CPU.

| Weg | Beleg |
|---|---|
| **BIOS** | „der Kern startet unter BIOS von dem Abbild"; `hwdiag: firmware=BIOS`; der Diagnose-Eintrag hält an, und danach kommt kein `kernel: done` mehr |
| **UEFI** (OVMF) | „derselbe Kern startet unter UEFI"; **kein** „Cannot use text mode with UEFI"; `hwdiag: firmware=UEFI`; die Firmware setzt den Rahmenpuffer: `fb 1280x800` |
| Plattencontroller | mit `-device ahci` meldet die Diagnose **AHCI**, mit `-device ide-hd` **IDE** — zwei Aufbauten, zwei Antworten |
| Netzkarten | Intel → `e1000`, virtio → `virtio-net`, und `rtl8139` → `no driver for 0x10ec:0x8139`, danach läuft der Kern bis zum Ende des Berichts weiter |
| ohne Bus / ohne Platte / ohne Karte | der Bericht kommt trotzdem vollständig, statt still zu hängen |

### `kernel/hwdiag.fi` läuft — hier der echte Bericht (BIOS-Lauf)

```
hwdiag: ==================== OSUM HARDWARE-DIAGNOSE ====================
hwdiag: firmware=BIOS  vgarom=0xc0000  smbios=0xf59f0  rsdp=0xf59d0
hwdiag: cpu vendor=AuthenticAMD  hersteller=AMD
hwdiag: cpu family=23  model=1  stepping=2  maxleaf=0xd
hwdiag: cpu brand=AMD EPYC 7571 32-Core Processor
hwdiag: mem usable=2096639 KiB  top=0x7ffe0000  frames=524256
hwdiag: fb 1280x800  bpp=32  pitch=5120  src=multiboot  phys=0xfd000000
hwdiag: pci devices=6
hwdiag: pci 00:01.1 8086:7010  class=01 sub=01 prog=80
hwdiag: pci 00:03.0 8086:100e  class=02 sub=00 prog=00
hwdiag: disk IDE    bdf=0x9 8086:7010
hwdiag: net -- was netdev daraus macht:
netdev: c0=e1000 bdf=0x18
hwdiag: ==================== ENDE DER DIAGNOSE ========================
hwdiag: ANGEHALTEN. Der Bildschirm bleibt so stehen.
```

### Das Bild

`docs/bilder/merge3-schreibtisch.png` — der deutsche Schreibtisch aus
**diesem** Abbild, 800×600, aufgenommen von `tools/usbimg/run.sh`. Darin
bildpunktgenau nachgewiesen: **`Ausführen`** bei x=519 (100 % der 84
Tintenpunkte, 100 % der 331 Gegenpunkte), und die ASCII-Ersatzschreibung
`Ausfuehren` steht nachweislich **nicht** da (bester Wert 70 %), das
englische `Run` auch nicht (74 %).

### Die Anleitung

`docs/AUFSETZEN.md`, 367 Zeilen, für den Menschen vor dem Rechner:
Abbild bauen · mit `dd` auf den Stick (jedes Merkzeichen einzeln
begründet, `bs=4M conv=fsync oflag=direct`, und warum `/dev/sdX` und
nicht `/dev/sdX1`) · was in der Firmware stehen muss (**Secure Boot
aus**, CSM, **SATA Mode = AHCI und nicht RAID**, Fast Boot aus) · was
beim ersten Start passiert (drei Menüeinträge, 10 s) · wie `install
--ja` auf die Platte schreibt — samt der Warnung, dass die installierte
Platte **nur über UEFI** startet, weil `install.fi` keinen
BIOS-Startsektor schreibt · und ein Stufenplan für den Fall, dass der
Bildschirm schwarz bleibt.

---

## WELCHE HARDWARE NICHT UNTERSTÜTZT WIRD

Aus dem Quelltext gelesen, nicht aus dem Gedächtnis. Die ausführliche
Fassung steht in `docs/AUFSETZEN.md`, Abschnitt 8, und in
`docs/REALHW.md`.

### Netz — hier ist die Lücke am größten

* **Geht:** virtio-net (`1AF4:1000/1041`, nur virtuell) und Intel
  8254x/82574, und zwar **genau** diese sechs Nummern:
  `8086:100E, 100F, 1015, 1026, 1028, 10D3` (`kernel/e1000.fi::supports`).
* **Geht nicht:** **Realtek RTL8168/8169/8125** (`10EC:8168/8125`) — der
  häufigste Chip auf Consumer-Brettern. **Intel I217/I218/I219**
  (`8086:153A, 155A, 15B7, 15B8, 0D4E …`) — auf fast jedem
  Business-Notebook; der PHY hängt an der Management-Engine.
  **Intel I210/I211/I225/I226** (igb/igc, anderes Deskriptorformat).
  Broadcom, Aquantia, Marvell.
* **WLAN: gar nichts.** Kein 802.11, kein Firmwareladen, kein WPA.
  Intel AX200/AX201/AX210, MediaTek MT7921, Qualcomm QCA6390 — alle
  nicht. **Bluetooth: gar nichts.**

Jede nicht unterstützte Karte wird **mit ihren Nummern genannt**
(`netdev: no driver for 0x10ec:0x8139`) und nicht verschwiegen.

### Massenspeicher

* **Geht:** NVMe (`01:08:02`), SATA im **AHCI**-Modus (`01:06:01`),
  IDE/ATA-PIO (`01:01:xx`), USB-Massenspeicher (BOT+SCSI über xHCI).
* **Geht nicht:** **SATA im RAID-Modus** (`01:04:xx`, Intel RST / AMD
  RAIDXpert) — dann findet Osum keine Platte; **eMMC und SD-Karten**;
  **SCSI/SAS**; **NVMe mit mehr als einem Namespace**.
* **Grenze IDE:** LBA28 = **128 GiB**. Eine 1-TB-Platte im IDE-Modus
  erscheint als 128 GiB.
* Die **automatische Treiberwahl beim Start ist nicht gebaut** — welches
  Gerät die Wurzel trägt, entscheidet die Kommandozeile bzw. der
  Installer.

### Grafik

* **Geht:** genau **ein** Weg — der lineare Rahmenpuffer, den die
  Firmware hinterlässt (UEFI-GOP über Limine, Multiboot-Flag-Bit 12),
  ersatzweise die Bochs-Register `0x1CE/0x1CF` oder die PCI-BAR.
* **Geht nicht:** **kein einziger GPU-Treiber** (kein i915, kein AMDGPU,
  kein Nouveau), kein KMS, keine Beschleunigung, kein Video-Dekoder,
  keine Helligkeitsregelung, kein Hot-Plug an DisplayPort/HDMI, **kein
  zweiter Bildschirm**. Umschaltbare Grafik: auf die integrierte
  stellen.

### Eingabe

* **Geht:** PS/2 über den 8042 (Port 0x60, IRQ 1); USB-Tastatur und
  -Maus über **xHCI** und das **HID-Boot-Protokoll**.
* **Geht nicht:** **I²C-HID** — daran hängen bei vielen neueren
  Notebooks die eingebaute Tastatur **und** das Touchpad;
  Präzisions-Touchpads; HID-Report-Deskriptoren überhaupt;
  **EHCI/UHCI/OHCI** (reine USB-2.0-Anschlüsse vor ~2012).

### Sonstiges

* **Ton: gar nichts** (kein HD-Audio, kein AC'97). Kein `hda.fi` im Baum.
* **ACPI:** RSDP/RSDT/XSDT, MADT und FADT werden gelesen — **kein
  AML-Interpreter**, also kein `_PRT` (das PCI-Interrupt-Routing kommt
  aus dem Interrupt-Line-Register der Firmware: meistens richtig,
  manchmal nicht), kein `_CRS`, keine Thermalzonen-Ereignisse, **kein
  Deckelschalter**, **kein sauberes S3**.
* **TPM:** nichts. **Drucken, Kamera, Fingerabdruck, Thunderbolt,
  SD-Leser:** nichts.

### Die kurze Antwort für den Projekteigner

**Beste Chancen:** ein Desktop mit UEFI, NVMe- oder SATA-Platte **im
AHCI-Modus**, Intel-Netzkarte der 8254x-Familie oder gar keinem Netz,
PS/2- oder USB-Tastatur, Grafik von der Firmware.

**Schlechteste Chancen:** ein neueres Notebook — Realtek- oder
I219-Netzkarte, I²C-Tastatur und -Touchpad, umschaltbare Grafik. Die
Diagnose kommt dort durch (dafür ist sie gebaut), aber Netz und
eingebaute Tastatur werden fehlen.

---

## RÜCKSICHT AUF DIE PARALLELE RUNDE AVX

Die Runde AVX (Zweig `avx`, von `mergeline2` abgezweigt) fasst
`kernel/sched.fi`, `kernel/cpu.fi`, `kernel/kmain.fi` und den Fangbereich
an. **Diese Runde hat keine dieser Dateien angefasst** — geändert wurden
nur `tools/icons/run.sh`, `tools/k15/run.sh`, `tools/wm/run.sh`,
`tools/tresor/run.sh` und zwei neue Dateien unter `docs/`. Da `main`
außerdem nur auf `mergeline2` vorgespult wurde, liegt der Abzweigpunkt
von `avx` weiterhin direkt in der Geschichte von `main`: AVX kann danach
sauber hineingemergt werden.

---

## DIE COMMITS DIESER RUNDE

| Commit | Was |
|---|---|
| `63003c0` (Zweig `ofs4`) | die ganze Runde OFS4 gerettet |
| `da48676` (Zweig `ota`) | der ungesicherte Rest der Runde OTA gerettet |
| `78cf416` | `icons`-Abbildgröße, `$karte`→`$kartv`, `docs/AUFSETZEN.md`, das Bild |
| `57842e0` | das zu kurze Warten in k15 9b |
| *(siehe `git log`)* | die Frist in `tresor`, dieser Bericht |

Alle Protokolle liegen unter `/root/m3logs/`:
`ABNAHME-1-mergeline2.log` (voller Lauf), `ABNAHME-2-einzeln.log`
(Nachmessung), `ICONS-nachher.log`, `K15-final.log`,
`TRESOR-final.log`, `USBIMG-abnahme.log`, `BUILD-usbimg.log`.
