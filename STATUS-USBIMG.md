# Runde USBIMG — Zwischenstand

Zweig `usbimg` (aus `mergeline`), **nicht** nach `main` gemergt.
Stand: 28.08.2026, alle Zahlen unten sind gemessen, keine geschätzt.

---

## Was jetzt da ist

```sh
bash tools/usbimg/build.sh /tmp/usbimg     # -> /tmp/usbimg/osum-usb.img
bash tools/usbimg/run.sh   /tmp/usbrun     # die Abnahme, unter KVM
```

**Abnahme: 46 bestanden, 0 gescheitert.** Laufzeit rund fünf Minuten.

Das Abbild: **123 731 968 Oktette (118 MiB)**, GPT mit zwei Partitionen —
EFI (FAT32, 96 MiB) und Wurzel (OFS v3, 20 MiB).

---

## 1. Das USB-Abbild (`tools/usbimg/build.sh`)

| | |
|---|---|
| Kern | 2 904 576 Oktette, Multiboot 1, ELF32‑Hülle |
| Programme in Ring 3 | **43** Stück |
| Symbole nach `/etc/netview/` | **11** Stück |
| Wurzelabbild | 20 971 520 Oktette, OFS v3 |
| Pflichtpfade nachgezählt | **24** |
| UTF‑8‑Umlautfolgen im Wurzelabbild | **43** |

**Ein Abbild, zwei Startwege.** `limine bios-install` schreibt den
BIOS‑Teil in den MBR‑Bereich, `/EFI/BOOT/BOOTX64.EFI` ist der
UEFI‑Weg. Beide sind gemessen (Abschnitte 4 und 5 der Abnahme).

**Die Wurzel ist ein Boot‑Modul und keine Partition.** Der Stick soll auf
einem Rechner starten, dessen Plattencontroller wir nicht kennen — das
herauszufinden ist ja sein Zweck. Läge die Wurzel auf einer Partition,
müsste der Kern dieses Gerät lesen können, um überhaupt bis zu der
Meldung zu kommen, die sagt, dass er es nicht kann.

`kernel/bootmod.fi` kann das seit Runde K10 und `kmain.osum` nimmt es
seither als Wurzelplatte — aber `osum` kehrt sofort zurück, wenn der
Fensterserver die Shell besitzt. Diese Runde hat denselben Weg deshalb
in `kmain.surface` (Abschnitt 2) nachgetragen. Gemessen:
`osum: from module 0x561000 blocks=40960`, `wm: mount=1`,
`ttf: mono glyphs=366`.

Partition 2 trägt dasselbe Dateisystem trotzdem noch einmal — für einen
Rechner, dessen Controller sich als lesbar herausstellt, und für
`/bin/install` aus Runde INSTALL.

---

## 2. Der Fehler der letzten Runde: die fehlenden Dateien

Das vorige Bootabbild enthielt weder `locale/de` noch `locale/en` noch
die Symbole in `/etc/netview/`. Der Fehler sah wie einer des Zeichenwerks
aus und lag im Abbildbau.

Jetzt liest `build.sh` das **fertige** Dateisystem mit `mkfs.py list`
zurück und bricht ab, wenn einer von **24 Pflichtpfaden** fehlt:

```
/usr/share/locale/de/messages   /usr/share/locale/en/messages
/lib/sans.ttf  /lib/mono.ttf  /lib/icons.ttf
/users/root/config/locale
/etc/netview/{state-online,state-nocarrier,state-noip,state-noroute,
              mark-filtered,mark-faked,mark-none,sys-faking,
              tile-fake,tile-net,tile-hide}
/etc/theme  /etc/taskbar.conf
/bin/{schreibtisch,leiste,netview,explorer}  /boot/osum.mb
```

Und im Bild wird nachgemessen, dass die Sprache nicht nur **da liegt**,
sondern auch **benutzt wird**:

```
DER UMLAUT STEHT IM BILD: 'Ausführen' bei x=329 Grundlinie=298:
    100% der 84 Tintenpunkte, 100% der 331 Gegenpunkte
GEGENPROBE: 'Ausfuehren' steht NICHT da (bester Wert 70%)
GEGENPROBE: 'Run'        steht NICHT da (bester Wert 74%)
'Programm suchen:'  100% der 143 Tintenpunkte
'kein Netz'         100% der  63 Tintenpunkte
```

`tools/usbimg/suchtext.py` sucht die Zeile im **ganzen** Bild, gerastert
mit `tools/ttf/raster.py` — der zweiten Fassung des Rasterers aus
`kernel/ttf.fi`, in einer anderen Sprache geschrieben. Es wird also
nicht gegen sich selbst geprüft.

Beim Bauen dieses Werkzeugs ist eine Stelle aufgefallen, die es wert
ist, notiert zu werden: mit `--deckung 200` statt 255 kam derselbe Text
auf **85 %** statt auf 100 %. Erst bei voller Deckung ist die Farbe im
Bild die reine Vordergrundfarbe; schon bei 200 mischt der Rasterer rund
ein Fünftel Untergrund ein.

---

## 3. Der Fehler der letzten Runde: die ASCII‑Umschrift

Der Auftrag sagte, in `locale/de/messages` stünde kein einziger echter
Umlaut. **Das stimmte für diesen Zweig nicht mehr** — die Datei trägt
25 echte Umlaute in 21 Zeilen (`Übernehmen`, `Auflösung`, `lässt`,
`ließ`, `Größe`, `Öffnen`, `Löschen`, `für`, `über`).

Damit es so bleibt, misst die Abnahme jetzt drei Dinge (Abschnitt 3):

```
locale/de/messages: 21 Zeilen mit echten UTF-8-Umlauten
ASCII-Umschriften im angezeigten deutschen Text: 0
Oktettrechnung stimmt: 25 Umlaute, 4753 Zeichen, 4778 Oktette (4753 + 25)
```

Die dritte Zeile ist die, um die es beim Zählen wirklich geht: **ein `ü`
sind zwei Oktette.** 4753 Zeichen ergeben 4778 Oktette, und die
Differenz ist genau die Zahl der Umlaute. Geprüft wird nur **rechts vom
Gleichheitszeichen** — die Schlüssel links sind englisch und bleiben es,
und ein Kommentar darf schreiben, was er will.

---

## 4. Die Hardware‑Diagnose (`kernel/hwdiag.fi`, 620 Zeilen)

Ein Wort auf der Kommandozeile (`hwdiag`), und der Kern berichtet —
**auf die serielle Leitung und auf den Bildschirm**. Ohne zweiten Satz
Druckbefehle: seit Runde K7 spiegelt `fb.set_echo` jedes Oktett aus
`serial.put` in den Rahmenpuffer. Zwei Ausgabewege, ein Aufruf.

Er steht in `kernel_main` **vor** jeder Stufe, die ein Gerät wirklich
hochzieht (`netsvc.stage`, `hw.disk`, `usb_stage`). Hängt eine davon auf
fremder Hardware, ist der Bericht, aus dem hervorgeht **warum**, schon
vollständig gedruckt.

Was er meldet, gemessen auf diesem Rechner (AMD EPYC 7571, unter KVM):

```
hwdiag: firmware=BIOS  vgarom=0xc0000  smbios=0xf59f0  rsdp=0xf59d0
hwdiag: cpu vendor=AuthenticAMD  hersteller=AMD
hwdiag: cpu family=23  model=1  stepping=2  maxleaf=0xd
hwdiag: cpu brand=AMD EPYC 7571 32-Core Processor
hwdiag: mem usable=523775 KiB  top=0x1ffe0000  frames=131072
hwdiag: fb 800x600  bpp=32  pitch=3200  src=vbe  phys=0xfd000000  cols/rows=100/37
hwdiag: pci devices=6
hwdiag: pci 00:01.1 8086:7010  class=01 sub=01 prog=80
hwdiag: disk IDE    bdf=0x9 8086:7010
netdev: c0=e1000 bdf=0x18
```

**UEFI oder BIOS wird gemessen, nicht behauptet.** Multiboot 1 hat kein
Feld dafür — `kernel/hwid.fi` hält in seinem Kommentar ausdrücklich
fest, dass ein EFI‑Systemtisch auf diesem Weg nie ankommt. Also drei
Spuren, und **alle drei stehen als Rohwert in der Zeile**: die Signatur
`0xAA55` am VGA‑ROM, der SMBIOS‑Anker im F‑Segment, der ACPI‑Zeiger.
Zwei müssen fehlen, damit `UEFI` dasteht. Derselbe Stick, derselbe Kern:

| | BIOS (SeaBIOS) | UEFI (OVMF) |
|---|---|---|
| `firmware=` | `BIOS` | `UEFI` |
| `vgarom=` | `0xc0000` | `nein` |
| `smbios=` | `0xf59f0` | `nein` |
| `rsdp=` | `0xf59d0` | `nein` |
| Rahmenpuffer | `800x600 src=vbe` | `1280x800 src=multiboot` |

Die zweite Spalte ist der Beweis, dass die Zeile ein Messgerät ist und
keine Konstante.

**Und CPUID mit den erweiterten Feldern.** Ohne sie wäre jeder Ryzen
„Familie 15“ und jeder Core „Familie 6, Modell 5“. `family=23 model=1`
ist Zen 1 (17h) — korrekt für einen EPYC 7571.

---

## 5. Robustheit: findet er nichts, sagt er es

Gemessen (Abschnitt 7):

```
hwdiag: pci=KEIN GERÄT -- der Bus antwortet nicht
hwdiag: disk=KEINER -- kein Plattencontroller auf dem Bus
hwdiag: net=KEINE KARTE -- kein Ethernet auf dem Bus
hwdiag: ==================== ENDE DER DIAGNOSE ====================
```

**Eine ehrliche Einschränkung dazu.** Eine x86‑Maschine ohne
Plattencontroller lässt sich mit QEMU nicht bauen: der PIIX3 der
`pc`‑Maschine und der ICH9‑AHCI der `q35`‑Maschine gehören zum Chipsatz
und sind auch mit `-nodefaults` da (nachgemessen: `pc` → `disk IDE
8086:7010`, `q35` → `disk AHCI 8086:2922`). `isapc` hat keinen
PCI‑Bus, startet diesen Kern aber nicht. Die Lage wird deshalb mit
`nopci` hergestellt — dem Gegenprobenwort, das `kernel/hw.fi` seit
Runde K2 genau dafür hat. Dazu die Gegenprobe: **dieselbe** Maschine mit
Bus meldet ihren IDE‑Controller sehr wohl.

Und eine fremde Karte, die dieser Kern nicht bedienen kann:

```
netdev: no driver for 0x10ec:0x8139      (rtl8139)
```

Der Kern läuft danach bis zum Ende des Berichts weiter — gemessen.

---

## 6. DER DRITTE FEHLER, DEN NUR DIE ECHTE CPU ZEIGT

Nach den beiden aus Runde KVMFIX, und von derselben Art.

`user.run` gab dem Ausflug nach Ring 3 einen Rahmen als Stapel, setzte
in dessen Blatteintrag das **Benutzerbit** und gab den Rahmen mit
`mem.frame_free` zurück — **ohne das Bit wieder zu löschen**. Der
Rahmenverwalter merkt sich beim Freigeben genau diesen Rahmen als
nächsten Kandidaten (`FRAME_HINT`); der nächste Anforderer ist bei
`gfx wm` der Arbeitsbereich des Schriftlesers, und dessen erster Zugriff
ist ein **Schreibzugriff des Kernels auf eine Seite mit Benutzerbit**.

Mit CR4.SMAP — und das haben alle CPUs seit Broadwell und Zen:

```
*** EXCEPTION 14 #PF  err=0x3  cr2=0x1b97000
    rip=0x120575 = _F0.kstate__set+0x53
```

`err=0x3`: die Seite ist da (Bit 0), es war ein Schreiben (Bit 1), aus
Ring 0. `cr2` war Oktett für Oktett die Adresse, die `run` eine Zeile
vorher freigegeben hatte.

Die vier Läufe, die das festgenagelt haben:

| Lauf | Ergebnis |
|---|---|
| TCG + Platte | `wm: hold`, Bild da |
| **KVM + Platte** | **EXCEPTION 14 #PF err=0x3** |
| KVM + `noring3` | `wm: hold`, Bild da (der Ausflug fällt aus) |
| KVM nach dem Fix | `wm: hold`, Bild da |

Behoben in `kernel/arch/x86_64/user.fi` (`unmap_user`): das Benutzerbit
im **Blatteintrag** wird gelöscht, bevor der Rahmen zurückgeht. Nur im
Blatt und nur für diese eine Seite — die Bits der drei Ebenen darüber
gehören auch dem Programmtext in `.utext`.

**Das ist ein Fehler, der Justins Rechner getroffen hätte**, nicht nur
eine Messung: jede CPU mit SMAP wäre beim Start des Schreibtischs
gestorben.

Nebenbei aufgefallen und ebenfalls gemessen: `hwdiag.stage` bekam beim
ersten Versuch `cmd = 0x560000` — den Anfang des Haldenblocks, der
inzwischen auf der Zeichenkette des Laders steht. Genau die Falle, vor
der der Kommentar bei `hw.parse` warnt. Gelesen wird jetzt
`hw.cmd_copy`.

---

## 7. Die Abnahme im Überblick (`tools/usbimg/run.sh`)

| Abschnitt | Was |
|---|---|
| 1 | Das Abbild bauen |
| 2 | Was wirklich in der Datei steht: GPT, EF00, Limine im MBR, fünf Dateien auf der EFI‑Partition |
| 3 | Echte Umlaute in `locale/de/messages` + Oktettrechnung |
| 4 | **BIOS**: Start vom Abbild, vollständiger Bericht, `hwdiagstop` hält an |
| 5 | **UEFI** (OVMF): derselbe Kern, kein „Cannot use text mode with UEFI“, `firmware=UEFI` |
| 6 | `-device ahci` → AHCI, `e1000` → e1000, `virtio-net` → virtio, `rtl8139` → `no driver for` |
| 7 | Nichts gefunden → benannt, nicht gehängt; dazu die Gegenprobe mit Bus |
| 8 | Schreibtisch aus dem Modul, deutsche Oberfläche, `Ausführen` bildpunktgenau im Bild |

Alle Läufe mit `-accel kvm -cpu host`. Was darunter kracht, kracht auch
auf Justins Blech — das ist die Lehre aus Runde KVMFIX, und diese Runde
hat sie ein drittes Mal bestätigt.

---

## 8. Was offen bleibt

* **Der Stick ist noch nie auf echtem Blech gelaufen.** KVM ist die
  nächstbeste Sache, aber die Firmware eines echten Mainboards ist
  keine OVMF‑Nachbildung. Das ist der Punkt, für den Justin am 30.08.
  gebraucht wird.
* **Secure Boot.** Limine ist nicht signiert; der Stick verlangt, dass
  Secure Boot aus ist. Ein signierter Weg wäre eine eigene Runde.
* **Kein AHCI‑Treiber.** Die Diagnose *erkennt* AHCI, bedienen kann der
  Kern nur NVMe und IDE. Wenn Justins Rechner AHCI meldet, ist das die
  nächste Treiberrunde.
* **`disk=KEINER` ist unter QEMU nicht direkt herstellbar** (siehe
  Abschnitt 5); der Weg über `nopci` ist ein Ersatz, kein Original.
* **Die Firmware‑Erkennung ist ein Befund, kein Beweis.** Bei einer
  CSM‑Firmware kann sie `BIOS` sagen, obwohl UEFI läuft. Deshalb stehen
  die drei Rohwerte in derselben Zeile.

---

## 9. Was von woanders rot ist — und nachweislich nicht von hier kommt

`tools/i18n/run.sh` ist rot: **30 erfüllt, 13 gescheitert.** Das gehört
in diesen Bericht, auch wenn es nicht diese Runde ist — und dass es
nicht diese Runde ist, wurde **gemessen** und nicht behauptet.

Nachgestellt in einem eigenen Arbeitsbaum auf `mergeline` (Commit
`3e92c27`, dem Stand *vor* dieser Runde) und dort derselbe Läufer:
**ebenfalls 30 erfüllt, 13 gescheitert, dieselben dreizehn Zeilen.**

```
FAIL  der Knopf heisst auf Englisch: '', erwartet 'Apply'
FAIL  und auf Deutsch: '', erwartet 'Übernehmen'
FAIL  das Statusfeld auf Englisch: '', erwartet 'ready'
FAIL  die Taskleiste meldet ihr Netzfeld -- 'leiste: text netz' fehlt
...
```

Das Programm `einstellungen` meldet die Lage seiner Bedienfelder nicht
mehr auf der seriellen Leitung, und die Taskleiste ihr Netzfeld auch
nicht — beides Meldungen, an denen der i18n-Läufer seine
bildpunktgenauen Zusagen festmacht. **Eine eigene Runde**, hier nur
festgehalten.

Ein Nebenbefund ist dabei behoben worden, weil er im Weg stand: das
Abbild in `tools/i18n/build.sh` war mit 4096 Blöcken (2 MiB) zu klein
geworden, seit `/bin/explorer` bei 485 392 Oktetten steht — `mkfs: the
disk is full`, auf **beiden** Zweigen. Jetzt 12288 Blöcke.

Grün geblieben und nachgeprüft: **`tools/kvm/run.sh` 35 erfüllt, 0
gescheitert** — die Runde, die dem Kernel am nächsten steht, und
diejenige, deren Gegenstand (SMAP, `sysret`, MSR) diese Runde angefasst
hat. Ebenso `tools/wm/run.sh`: 103 erfüllt, 0 gescheitert.

---

## Dateien dieser Runde

```
kernel/hwdiag.fi                    neu, 620 Zeilen
kernel/kmain.fi                     hwdiag.stage + Wurzel aus dem Modul in surface()
kernel/arch/x86_64/user.fi          unmap_user -- der dritte KVM-Fehler
tools/usbimg/build.sh               das Abbild
tools/usbimg/run.sh                 die Abnahme, 46 Zusagen
tools/usbimg/suchtext.py            eine Textzeile im ganzen Bild suchen
docs/USBSTICK.md                    die Anleitung für Justin
STATUS-USBIMG.md                    diese Seite
```
