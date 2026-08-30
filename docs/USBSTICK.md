# Osum vom USB-Stick — und was der Rechner uns dabei verrät

Runde USBIMG. Diese Seite ist für **den Menschen vor dem echten Rechner**
geschrieben, nicht für einen Testläufer.

---

## 1. Was der Stick ist

Ein Abbild, das mit `dd` auf einen USB-Stick geschrieben wird und dann
sowohl über **BIOS** als auch über **UEFI** startet. Er installiert
nichts, er verändert die Festplatte nicht, er schreibt nirgendwo hin.
Er startet, sagt, **was in diesem Rechner steckt**, und bleibt stehen.

Genau diese Auskunft entscheidet, welche Treiber als nächstes gebraucht
werden — und sie lässt sich nicht raten, nur messen.

---

## 2. Das Abbild bauen

```sh
bash tools/usbimg/build.sh /tmp/usbimg
```

Heraus kommt `/tmp/usbimg/osum-usb.img`, rund **118 MiB**.
Das Skript baut vorher alles neu: den Kern, die Programme in Ring 3, die
Symbole, das OFS‑Dateisystem — und es **zählt danach nach**, dass die
Sprachdateien, die drei Schriften und die elf Symbole wirklich im
fertigen Dateisystem liegen. Fehlt eines, bricht es ab.

Braucht: `sgdisk`, `mkfs.vfat`, `mtools` (`mcopy`, `mmd`), `python3`
und Limine. Liegt Limine woanders:

```sh
LIMINE_DIR=/pfad/zu/limine bash tools/usbimg/build.sh /tmp/usbimg
```

---

## 3. Auf den Stick schreiben

**Erst nachsehen, welches Gerät der Stick ist.** `dd` auf die falsche
Platte ist nicht rückgängig zu machen.

```sh
lsblk -o NAME,SIZE,MODEL,TRAN
```

Der Stick ist der mit `TRAN=usb` und der passenden Größe. Dann:

```sh
sudo umount /dev/sdX*            # falls etwas eingehängt ist
sudo dd if=/tmp/usbimg/osum-usb.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

`of=/dev/sdX` — die **ganze Platte**, nicht `/dev/sdX1`. Das Abbild
bringt seine eigene Partitionstafel mit.

Unter Windows tut es Rufus im Modus „DD‑Image“ oder `balenaEtcher`.

---

## 4. Davon starten

Beim Einschalten das Bootmenü der Firmware öffnen — je nach Hersteller
`F12`, `F11`, `F8`, `Esc` oder `Entf`. Dort den Stick wählen.

* Steht er **zweimal** da, einmal mit `UEFI:` davor und einmal ohne:
  beide funktionieren. Für die Diagnose ist der **Unterschied
  interessant** — der Bericht sagt in der ersten Zeile selbst, auf
  welchem Weg er gestartet ist.
* **Secure Boot muss aus sein.** Limine ist nicht von Microsoft
  signiert. Im Firmware‑Menü unter „Security“ → „Secure Boot“ →
  `Disabled`.
* Startet nichts: „CSM“ / „Legacy Boot“ einschalten und den Eintrag
  **ohne** `UEFI:` nehmen.

Nach dem Start kommt ein Menü mit drei Einträgen und **10 Sekunden**
Bedenkzeit:

| Eintrag | Was er tut |
|---|---|
| **Hardware‑Diagnose (bleibt stehen)** | *Der Eintrag, um den es geht.* Druckt den Bericht und hält an. Nichts läuft weiter, nichts wird geschrieben. Ablesen oder fotografieren, dann ausschalten. |
| **Diagnose und danach der Schreibtisch** | Derselbe Bericht, danach fährt die Oberfläche hoch. Der Bericht steht dann nur noch auf der seriellen Leitung. |
| **Nur der Schreibtisch (deutsch)** | Ohne Diagnose. |

---

## 5. Wo die serielle Ausgabe herauskommt

Der Kern schreibt **jede** Zeile auf **COM1, 0x3F8, 115200 8N1** —
immer, ohne Schalter, ohne Kommandozeilenwort. Der Bildschirm ist eine
*Kopie* davon (`fb.set_echo`), nicht das Original.

* **Echter serieller Anschluss** (9‑poliger Stecker am Mainboard oder
  ein Pfostenstecker `COM1` darauf): Nullmodemkabel zu einem zweiten
  Rechner, dort `screen /dev/ttyUSB0 115200` oder
  `picocom -b 115200 /dev/ttyUSB0`.
* **Kein serieller Anschluss** (die Regel bei neuen Geräten): dann eben
  nicht — dafür gibt es den Eintrag „bleibt stehen“. Der Bildschirm
  zeigt genau dasselbe, und ein Handyfoto reicht.

Ein USB‑zu‑Seriell‑Adapter **am zu messenden Rechner** nützt nichts:
der Kern kennt nur das alte Tor 0x3F8, nicht den Adapter.

---

## 6. Was abzulesen ist

Der Bericht sieht so aus (echte Ausgabe, gemessen unter KVM):

```
hwdiag: ==================== OSUM HARDWARE-DIAGNOSE ====================
hwdiag: firmware=BIOS  vgarom=0xc0000  smbios=0xf59f0  rsdp=0xf59d0
hwdiag: cpu vendor=AuthenticAMD  hersteller=AMD
hwdiag: cpu family=23  model=1  stepping=2  maxleaf=0xd
hwdiag: cpu brand=AMD EPYC 7571 32-Core Processor
hwdiag: mem usable=523775 KiB  top=0x1ffe0000  frames=131072
hwdiag: fb 800x600  bpp=32  pitch=3200  src=vbe  phys=0xfd000000  cols/rows=100/37
hwdiag: pci devices=6
hwdiag: pci 00:00.0 8086:1237  class=06 sub=00 prog=00
hwdiag: pci 00:01.1 8086:7010  class=01 sub=01 prog=80
hwdiag: pci 00:03.0 8086:100e  class=02 sub=00 prog=00
hwdiag: disk IDE    bdf=0x9 8086:7010
hwdiag: net -- was netdev daraus macht:
netdev: c0=e1000 bdf=0x18
hwdiag: ==================== ENDE DER DIAGNOSE ========================
hwdiag: ANGEHALTEN. Der Bildschirm bleibt so stehen.
```

Zeile für Zeile:

**`firmware=`** — `BIOS` oder `UEFI`. Multiboot 1 hat **kein Feld**
dafür, also wird es an drei Spuren gemessen, und alle drei stehen
daneben: die Signatur `0xAA55` am VGA‑ROM (`vgarom=`), der
SMBIOS‑Anker im F‑Segment (`smbios=`) und der ACPI‑Zeiger (`rsdp=`).
Zwei von dreien müssen fehlen, damit `UEFI` dasteht. Wer eine
CSM‑Firmware hat, sieht das an den Rohwerten selbst. **Das ist ein
Befund, kein Beweis** — die Rohwerte sind der wichtigere Teil der Zeile.

**`cpu vendor=` / `hersteller=`** — AMD oder Intel. Das entscheidet
mehr, als es aussieht: Runde KVMFIX hat zwei Fehler gefunden, die *nur*
auf AMD tödlich sind (`sysret` legt SS anders an, und
`IA32_TEMPERATURE_TARGET` gibt es dort gar nicht).

**`cpu family=` / `model=`** — **mit** den erweiterten Feldern. Ohne die
wäre jeder Ryzen „Familie 15“ und jeder Core „Familie 6, Modell 5“ —
Zahlen, mit denen niemand einen Treiber aussucht.

**`mem usable=`** — was die Speicherkarte des Laders als benutzbar
gemeldet hat, in KiB. `top=` ist die höchste Adresse darin.

**`fb …`** — Breite, Höhe, Farbtiefe, Zeilenlänge, Herkunft
(`multiboot` = die Firmware hat ihn gesetzt, `vbe` = der Kern hat ihn
selbst gefunden) und die physische Adresse. Steht hier
`fb=KEINER`, hat die Oberfläche auf diesem Gerät nichts zum Zeichnen.

**`pci …`** — **jedes** Gerät auf dem Bus mit `bus:gerät.funktion`,
`hersteller:gerät` und Klasse/Unterklasse/Schnittstelle. Das ist die
Liste, aus der die Treiberarbeit danach abgeleitet wird. Interessant
sind vor allem Klasse `01` (Massenspeicher), `02` (Netz) und `0c`
(USB).

**`disk …`** — welcher Plattencontroller gefunden wurde: `NVMe`, `AHCI`,
`IDE`, `andere` — oder `disk=KEINER`. Steht dort `NVMe`, kann Osum ihn
schon; steht dort `AHCI`, ist das die nächste Treiberrunde.

**`netdev: c0=…`** — welchen Treiber der Kern für die Netzkarte
**gewählt** hat (`virtio-net` oder `e1000`). Steht dort stattdessen

```
netdev: no driver for 0x10ec:0x8168
```

dann ist genau das die Zeile, die Justin abschreiben soll: Hersteller
und Gerät der Karte, für die ein Treiber fehlt.
`net=KEINE KARTE` heißt: gar kein Ethernet auf dem Bus.

**Und der Kern hängt in keinem dieser Fälle.** Findet er keine Platte
und keine Karte, sagt er das und läuft weiter — der Bericht ist auch
dann vollständig. Das ist gemessen (`tools/usbimg/run.sh`, Abschnitt 7)
und nicht behauptet.

---

## 7. Was Justin mitbringen soll

Ein Foto des Bildschirms nach dem Eintrag „Hardware‑Diagnose“ reicht.
Wichtig sind:

1. die `firmware=`‑Zeile **samt** der drei Rohwerte,
2. `cpu vendor` und `cpu family/model`,
3. **alle** `pci`‑Zeilen,
4. die `disk`‑Zeile,
5. jede Zeile mit `no driver for`.

Startet der Stick **gar nicht**, ist auch das ein Befund — dann bitte
notieren, wie weit er kam: Firmware‑Menü, Limine‑Menü, schwarzer
Bildschirm, oder eine Meldung von Limine.

---

## 8. Der Aufbau des Abbilds

```
GPT
├── Partition 1  EFI System (EF00), FAT32, 96 MiB, "OSUM-EFI"
│   ├── /EFI/BOOT/BOOTX64.EFI     der UEFI-Weg
│   ├── /limine-bios.sys          der BIOS-Weg
│   ├── /limine.conf              das Menü (auch unter /boot/)
│   ├── /osum.mb                  der Kern (Multiboot 1, ELF32-Hülle)
│   └── /root.img                 die Wurzel als BOOT-MODUL
└── Partition 2  Linux (8300), "OSUM-ROOT"
    └── dasselbe OFS-v3-Dateisystem noch einmal, als Partition
```

**Warum die Wurzel ein Modul ist und keine Partition.** Der Stick soll
auf einem Rechner starten, dessen Plattencontroller wir nicht kennen —
das herauszufinden ist ja sein Zweck. Läge die Wurzel auf Partition 2,
müsste der Kern dieses Gerät lesen können, um überhaupt bis zu der
Meldung zu kommen, die sagt, dass er es nicht kann. Als Modul lädt der
**Lader** sie, über die Firmware, die ihr eigenes Gerät immer lesen
kann. Der Kern braucht dafür keinen einzigen Treiber.

Partition 2 liegt trotzdem daneben: ein Rechner, dessen Controller sich
als lesbar herausstellt, hat damit sofort eine Wurzel auf dem Stick, und
`/bin/install` aus Runde INSTALL findet die Lage vor, für die es gebaut
wurde.

---

## 9. Die Abnahme

```sh
bash tools/usbimg/run.sh /tmp/usbrun
```

Fährt das Abbild **unter KVM auf der echten CPU** — einmal BIOS, einmal
UEFI (OVMF), einmal mit `-device ahci`, einmal mit `e1000`, einmal mit
`rtl8139` (einer Karte, die dieser Kern *nicht* kann) und einmal ganz
ohne Geräte. Zum Schluss ein Bildschirmfoto des Schreibtischs, in dem
das Wort `Ausführen` **bildpunktgenau** nachgewiesen wird — und die
ASCII‑Ersatzschreibung `Ausfuehren` nachweislich *nicht*.
