# OSUM AUF ECHTER HARDWARE

Diese Datei ist in Runde MERGE-2 aus ZWEI Dateien desselben Namens
zusammengelegt worden. Die Runden HWNET und AHCI haben unabhaengig
voneinander `docs/REALHW.md` angelegt -- die eine ueber Netzkarten, die
andere ueber Platten. Beide Texte stehen hier vollstaendig und
unveraendert; keiner von beiden ist ein Auszug des anderen.

* **Teil A -- Netz.** Welche Netzkarte Osum findet, was `e1000` kann,
  HTTPS aus Ring 3, der Wurzelzertifikatsspeicher.
* **Teil B -- Platte.** Welche Platte Osum findet, was die
  Firmware-Einstellung "SATA MODE" aendert, der IDE/PIO-Rueckfallweg.

---

## TEIL A -- NETZ

*(urspruenglicher Titel: OSUM AUF ECHTER HARDWARE -- was geht, was nach dieser Runde geht, was fehlt)*

Runde HWNET, 28.08.2026. Zweig `hwnet`, abgezweigt von `mergeline`
(e9fcc1c).

**Was diese Datei ist.** Eine Bestandsaufnahme, Geräteklasse für
Geräteklasse, für den einen Zweck: Justin will OrientOS auf einem
gewöhnlichen PC oder Laptop installieren und dort den JARVIS-Helfer
laufen lassen. Jede Zeile sagt, was es HEUTE gibt, was NACH DIESER RUNDE
geht und was WEITER FEHLT -- und bei jeder Behauptung steht, woher die
Zahl kommt.

**Was diese Datei NICHT ist.** Ein Bericht über gemessene Hardware. Auf
diesem Rechner liegt kein Testbrett. Alles, was hier über einen echten
Chip steht, ist entweder aus einem Datenblatt oder aus dem Quelltext
gelesen; gemessen wurde ausschließlich in QEMU. Wo das den Unterschied
macht, steht es in der Zeile.

---

## DIE TABELLE

| Klasse | Was es heute gibt | Nach dieser Runde | Fehlt weiter | Was auf einem gewöhnlichen PC/Laptop erwartet wird |
|---|---|---|---|---|
| **Netz, kabelgebunden** | NUR `kernel/virtio.fi` -- ein paravirtueller Chip, den es auf echter Hardware NICHT gibt | `kernel/e1000.fi` (Intel 8254x/82574) + `kernel/netdev.fi`, das den Treiber anhand der PCI-Nummern wählt. In QEMU gemessen: 20/20 Pings, 262144 Oktett TCP, 0 Prüfsummenfehler, 0 Wiederholungen | Realtek RTL8168/8169 (der häufigste Chip überhaupt), Intel I219/I225, Broadcom, Aquantia | I219-LM/V (8086:15B7/15B8/0D4E …) auf Business-Laptops, RTL8168 (10EC:8168) auf fast jedem Consumer-Board, I225/I226 (8086:15F3/125B) auf neueren |
| **WLAN** | nichts | nichts | ALLES: 802.11-MAC, Firmwareladen, Netzwahl, WPA2/3-Supplicant, Regulatorik | Intel AX200/AX201/AX210 (8086:2723/A0F0/2725), MediaTek MT7921, Qualcomm QCA6390 |
| **Platte, NVMe** | `kernel/nvme.fi` + `kernel/blk.fi` (DEV_NVME), DMA, Warteschlangen, IRQ | unverändert | Namespaces > 1, Fehlerbehandlung bei fehlerhaftem Medium | Samsung/WD/SK-Hynix M.2 -- Klasse 01:08:02, herstellerunabhängig durch die Spezifikation |
| **Platte, SATA/AHCI** | **NICHTS.** `pci.fi` kennt die Konstanten `SUB_SATA` (0x06) und `PROGIF_AHCI` (0x01) und benutzt sie nirgends. Es gibt KEINE Datei `ahci.fi`. Was es gibt, ist ATA-PIO auf 0x1F0 (`blk.fi`, DEV_ATA) -- das ist der Legacy-IDE-Weg | unverändert (diese Runde hat den Netzweg gebaut, nicht den Plattenweg) | AHCI-Treiber: Port-Register, Kommandolisten, FIS, NCQ-frei reicht | Jeder Rechner ohne NVMe: Intel PCH SATA (8086:xxxx, Klasse 01:06:01), AMD FCH. Ein SATA-Controller im AHCI-Modus antwortet NICHT auf 0x1F0 -- ohne AHCI-Treiber sieht Osum die Platte nicht |
| **Grafik** | `kernel/fb.fi`: linearer Rahmenpuffer über Multiboot-Flag-Bit 12 (vom Lader), ODER die Bochs-/QEMU-Register 0x1CE/0x1CF, ODER die PCI-BAR der Karte. `kernel/vmode.fi` schaltet Modi über VBE | unverändert | Kein echter GPU-Treiber, kein KMS, keine Beschleunigung -- und das ist die richtige Entscheidung | Auf echter Hardware liefert der UEFI-GOP-Rahmenpuffer über Limine genau das, was Bit 12 verspricht. Der Weg trägt auf Intel-, AMD- und Nvidia-Systemen gleichermaßen, weil er von der Firmware kommt und nicht vom Chip |
| **Eingabe, PS/2** | `kernel/kbd.fi` (Port 0x60, IRQ 1), `kernel/ps2m.fi` (Maus) | unverändert | -- | Auf Desktops fast immer noch da (der 8042 lebt im Chipsatz weiter). **Auf vielen modernen Laptops NICHT**: dort hängt die Tastatur an einem internen USB- oder I²C-HID-Gerät |
| **Eingabe, USB-HID** | `kernel/xhci.fi` + `kernel/usb.fi`: xHCI, Geräteaufzählung, HID-Boot-Protokoll für Tastatur UND Maus, umgesetzt in PS/2-Abtastcodes (`usb.fi` Zeile 37 ff.) | unverändert | Keine HID-Report-Deskriptoren (nur das Boot-Protokoll), kein I²C-HID, kein Touchpad-Protokoll (Präzisions-Touchpads melden über Report-Deskriptoren) | USB-Tastatur/Maus: geht über das Boot-Protokoll. Laptop-Touchpad über I²C-HID: geht NICHT |
| **USB-Hostcontroller** | `kernel/xhci.fi` (xHCI 1.0, Klasse 0C:03:30) | unverändert | EHCI/UHCI/OHCI (alte Ports), USB-3-Hubs in der Tiefe, Isochronübertragungen | Jeder Rechner seit ~2012 hat xHCI, meist Intel/AMD im Chipsatz. Das ist der richtige und einzige nötige Controller |
| **ACPI/Strom** | `kernel/acpi.fi`: RSDP-Suche, RSDT/XSDT, MADT (Prozessoren, I/O-APIC), FADT für das Abschalten. `kernel/pwr.fi`: C-Zustände, P-Zustände über MSR, `kernel/batt.fi`: Akku über die ACPI-Tabellen | unverändert | KEIN AML-Interpreter. Ohne den gibt es kein `_PRT` (Interrupt-Routing der PCI-Steckplätze), kein `_CRS`, keine Thermalzonen-Ereignisse, kein Deckelschalter, kein sauberes S3 | Genau hier wird es auf echter Hardware ernst: die Zuordnung PCI-Steckplatz → GSI kommt auf einem echten Brett aus dem AML-Objekt `_PRT`. Diese Runde liest stattdessen das Interrupt-Line-Register aus der Konfiguration (was die Firmware ausgefüllt hat). Das ist auf den meisten Brettern richtig und auf manchen nicht |
| **TPM** | nichts im Kernel. `kernel/user/key.fi` und `bsec.fi` nennen TPM nur in Kommentaren als das, was es NICHT benutzt | unverändert | TPM-2.0-Treiber (TIS/CRB auf 0xFED40000), PCR-Erweiterung, Versiegeln | Auf jedem Rechner seit 2016 vorhanden (fTPM in der CPU oder dTPM). Für Justins Zweck (Helfer, Update) NICHT nötig; für „Schlüssel, den man nicht wegtragen kann" schon |
| **Ton** | nichts. Kein `hda.fi`, kein `ac97.fi` | unverändert | ALLES: HD-Audio-Controller, Codec-Aufzählung, Widget-Graph, Streams | Intel HDA (Klasse 04:03:00) auf praktisch jedem Brett. Für Justins Zweck nicht nötig |

---

## WIE DIESE ZAHLEN ZUSTANDE KAMEN

* Netzwerktreiber vorher: `grep -rln 'e1000\|8139\|rtl8\|igb\|ixgbe' --include=*.fi kernel/` → nur `nvme.fi`, `pci.fi`, `virtio.fi`, und in den ersten beiden sind es Konstanten. Netzkartentreiber: **genau einer**.
* Aufrufstellen des einen Treibers, die diese Runde umlenken musste: gezählt aus `git diff mergeline..HEAD` **56 geänderte Zeilen in sieben Dateien** -- 17 in `inet.fi`, 17 in `netsvc.fi`, 16 in `share.fi`, je 2 in `hwid.fi` und `trap.fi`, je 1 in `wg.fi` und `netview.fi`. Alle mechanisch auf `netdev.` umgestellt; die übrigen Nennungen von `virtio` in diesen Dateien stehen in Kommentaren und sind absichtlich stehen geblieben, weil sie über den virtio-Treiber reden und nicht über die Schnittstelle.
* AHCI: `grep -rn 'ahci\|AHCI' --include=*.fi kernel/` → **nur** `pci.fi:PROGIF_AHCI` (eine unbenutzte Konstante). Es gibt keinen AHCI-Treiber. Bestätigt.
* TLS vorher: `grep -rln 'tls\|https' --include=*.fi kernel/ lib/` → 0 Treffer im eigenen Baum. ABER: `vendor/firn/lib/tls/` (3285 Zeilen) und `vendor/firn/lib/std/crypto/` (5106 Zeilen) lagen seit dem festgenagelten Commit `a751b3db` im Baum und wurden nie benutzt.

---

## WAS DIESE RUNDE GEBAUT HAT, mit den gemessenen Zahlen

### `kernel/netdev.fi` -- welcher Treiber, entschieden vom Bus

Vorher gab es keine Abstraktion: `inet.fi` rief `virtio.tx_frame` direkt
auf. Jetzt gibt es eine Tabelle:

    1AF4:1000 / 1041   virtio-net    kernel/virtio.fi   (Runde K8)
    8086:100E,100F,1015,1026,1028,10D3   Intel 8254x/82574   kernel/e1000.fi

Alles andere auf Klasse 02:00 wird **mit seinen Nummern genannt**:

    netdev: no driver for 0x10ec:0x8139
    nic: no device

Gemessen mit `-device rtl8139`. Das ist der Satz, den ein echtes Brett
braucht: eine Maschine, die nicht funktioniert, muss sagen, WELCHER Chip
darin steckt, statt still zu bleiben.

### `kernel/e1000.fi` -- ein Chip, den es wirklich gibt

BAR0 als Speicherbereich, Softwarerücksetzung, Adresse aus RAL/RAH (und
ersatzweise aus dem EEPROM über EERD), zwei Ringe zu je 32 Deskriptoren,
2048-Oktett-Puffer, INTx über den I/O-APIC (diese Familie hat kein
MSI-X, und der Treiber behauptet es auch nicht).

**Gemessen in QEMU (`tools/hwnet/run.sh`), dieselbe Abnahme zweimal:**

| | virtio-net-pci | e1000 (82540EM) |
|---|---|---|
| Ping, 20 Anfragen | 20 beantwortet | 20 beantwortet |
| Umlaufzeit, Mittel | 5,75 ms | **5,15 ms** |
| Unterbrechungen | 45 | 43 |
| TCP hinein | 262144 Oktett | 262144 Oktett |
| Rahmen empfangen | 189 | 185 |
| Prüfsummenfehler | 0 | 0 |
| Wiederholungen | 0 | 0 |
| Verworfen (Ring voll) | 0 | 0 |
| Durchsatz | 5710 KiB/s | **3619 KiB/s (63 %)** |
| DHCP von busybox udhcpd | Adresse bezogen | Adresse bezogen |

Der Durchsatzunterschied ist echt und erklärbar: jede Sendung schreibt
ein Register (`TDT`) und jede Prüfung auf Platz liest eines (`TDH`), und
ein MMIO-Zugriff ist unter QEMU/TCG ein Austritt aus der Emulation. Der
virtio-Ring kommt für dasselbe mit Speicherzugriffen aus. Auf echter
Hardware kehrt sich dieser Unterschied nicht um, aber er wird viel
kleiner.

**Zwei Dinge, die dabei gefunden wurden und in den Quelltexten stehen:**

1. QEMU legt einen Rahmen, der die Karte erreicht, BEVOR der Ring
   existiert, für **eine ganze Sekunde** beiseite (`flush_queue_timer` in
   `hw/net/e1000.c`) -- und alles danach wartet mit. Gemessen: eine
   Maschine, die während des Hochlaufs angepingt wird, beantwortet die
   ersten zehn Anfragen gemeinsam nach 935 ms und alles danach in
   Millisekunden. Nach drei Sekunden Ruhe: 0,3 bis 12,9 ms. Das ist eine
   Eigenschaft von QEMU, nicht des Treibers -- eine echte Karte wirft
   solche Rahmen weg.
2. Der festgenagelte TCP/IP-Stapel hat **keinen Rundrufweg nach außen**:
   `net_output` sucht auch für 255.255.255.255 den nächsten Sprung per
   ARP. Gemessen: mit einem Gateway, das niemand beantwortet, verlässt
   der DHCP-Rundruf die Maschine nie (0 UDP-Rahmen auf dem Draht,
   mitgeschnitten). `kernel/user/dhcp.fi` sagt das seit seiner ersten
   Zeile; diese Runde hat es nachgemessen. Es steht in
   `docs/ROADMAP-UPDATE.md` mit dem, was es kosten würde.

### RTL8168/8169 -- geprüft und NICHT gebaut, mit Begründung

Der Auftrag war, zu prüfen, ob der Realtek-Chip mit vertretbarem Aufwand
dazukommt. Das Ergebnis ist ein Nein für DIESE Runde, und zwar aus einem
Grund, der nichts mit Aufwand zu tun hat:

* **QEMU hat `-device rtl8139`, und das ist NICHT derselbe Chip.** Der
  8139 (RTL8139C) hat vier feste Sendepuffer und einen einzigen
  Ringpuffer zum Empfangen -- kein Deskriptorring. Der 8168/8169 hat
  Deskriptorringe wie ein e1000. Ein Treiber für den 8139 würde über den
  8168 **nichts** beweisen; die beiden teilen sich nur den Namen des
  Herstellers.
* Ein 8168-Treiber ließe sich schreiben (die Ringe sind dem e1000 sehr
  ähnlich, das Datenblatt ist halböffentlich, Linux' `r8169.c` ist
  lesbar), aber er wäre **auf diesem Rechner nicht einmal ansatzweise
  testbar** -- weder in QEMU noch an echter Hardware. Ein Treiber ohne
  eine einzige Messung ist eine Behauptung.
* Aufwandsschätzung, damit die Zahl dasteht: ~600 Zeilen in der Bauart
  von `e1000.fi`, plus PHY-Handhabung, plus die C+-Deskriptoren. Eine
  eigene Runde, und sie braucht **ein Brett mit einem 8168 darin** --
  oder mindestens einen Rechner, auf dem Justin es einsteckt und die
  serielle Ausgabe abliest.

### `kernel/app/fetch.fi` -- HTTPS aus Ring 3

Die eigentliche Überraschung dieser Runde, und sie ist eine gute:
**die ganze TLS-Arbeit lag schon im Baum**, festgenagelt über
`vendor/firn/COMMIT` (a751b3db, enthält den Zweig `b5-tls` von Firn):

    vendor/firn/lib/tls/{tls,x509,der,keys}.fi          3285 Zeilen
    vendor/firn/lib/std/crypto/{aes,gcm,chacha,x25519,  5106 Zeilen
                                rsa,ecdsa,sha256,sha512,hkdf,hmac,big}.fi

Benutzt wurde sie nie, weil jedes Programm unter `kernel/user/` mit
`profile kernel` gebaut wird: freistehend, ohne Allokator. Ein
Aufzeichnungsverfahren braucht eine Halde.

`kernel/app/` ist die zweite Bauart eines Ring-3-Programms:
`--profile=app`, die VOLLE Firn-Bibliothek, gebunden mit
`kernel/user/user.ld` und **ohne `crt.s`** -- Firns eigenes `_start`
reicht. Das geht aus zwei Gründen, und beide sind gemessen:

* Osums Systemaufrufe tragen **Linux-Nummern** (Runde K4), auch die
  Steckdosenfamilie (41 socket, 42 connect, 44 sendto, 45 recvfrom),
  9 mmap, 12 brk, 228 clock_gettime, 318 getrandom -- genau die, die
  Firns `std.rt`/`std.net` über die `syscall`-Anweisung absetzen.
* Osums Argumentblock (`kernel/elf.fi`, `write_args`) hat **Linux'
  Form**: argc, dann die Zeiger, dann eine Null.

Erster Beweis, vor dem TLS-Teil: ein Programm mit `std.io` und `std.rt`
(Halde über mmap) lief unverändert in Ring 3 -- `appdemo: argc=3`,
`heap buf len=8`, 325568 Oktett Abbild, 80 Seiten.

**Was `/bin/fetch` ist:** 655712 Oktett auf der Platte, ein einziges
Objekt, **keine einzige undefinierte Marke**. Darin: TLS 1.3, X.509,
RSA, ECDSA, X25519, AES-GCM, ChaCha20-Poly1305, SHA-256/384/512, HKDF.

**Gemessen gegen `openssl s_server` (`tools/hwnet/tls.sh`), über den
e1000 dieser Runde:**

| Fall | Antwort | Was geholt wurde |
|---|---|---|
| gültiges Zertifikat | `verify OK`, Suite 4865 (TLS_AES_128_GCM_SHA256), 10 Datensätze | 4005 Oktett |
| **abgelaufen** | `REFUSED expired` | **nichts** |
| **falscher Name** | `REFUSED wrong_name` | **nichts** |
| **unbekannter Aussteller** | `REFUSED unknown_issuer` | **nichts** |
| **leerer Zertifikatsspeicher** | `REFUSED unknown_issuer` | **nichts** |

Die Verweigerungen SIND die Messung. Eine TLS-Umsetzung, die alles
annimmt, ist schlimmer als keine; der einzige Weg, das zu unterscheiden,
ist, ihr vier schlechte Zertifikate hinzuhalten. Die vier Zertifikate
sind mit Pythons `cryptography` gemacht (`tools/hwnet/mkcerts.py`) --
also nicht mit demselben Code, der sie prüft.

**Gegen das echte Netz** (der Namensraum bekommt über ein zweites
Verbindungspaar und NAT eine Route):

    fetch -q -n example.com https://172.66.147.243/
    fetch: roots 11
    fetch: verify OK
    fetch: certs 4        (Cloudflare -> SSL.com TLS ECC Root CA 2022)
    fetch: depth 4
    fetch: octets 868
    fetch: chunked 1
    fetch: body 559
    fetch: bodysha ff67a9d764d6a2367a187734e697f6a53217db9a21c101d410a113ca871a299d

    curl -s https://example.com/ | sha256sum
    ff67a9d764d6a2367a187734e697f6a53217db9a21c101d410a113ca871a299d

**Dieselben Oktette wie curl, bis auf die letzte Stelle des
Streuwerts.** Damit stimmt jede Schicht darunter: X25519, der
Schlüsselplan, das Aufzeichnungsverfahren, AES-GCM, die
Kettenprüfung -- und der Treiber, über den sie gelaufen sind.

Zwei Fehler wurden dabei gefunden und stehen im Quelltext:
eine Kopfzeile, die ein Oktett zu kurz war (`openssl s_server -www`
verzieh es, Cloudflare nicht -- der Rumpf kam als 0 Oktett zurück), und
die Stückelung von HTTP/1.1, die als Rumpf mitgezählt wurde (571 statt
559).

---

## DER WURZELZERTIFIKATSSPEICHER: woher, und wie er ins Abbild kommt

`tools/hwnet/mkroots.py` schreibt `/etc/ssl/roots.pem`.

* **Woher:** aus `/etc/ssl/certs/ca-certificates.crt` des Wirts, das
  Debian aus Mozillas CA-Liste baut (Paket `ca-certificates`, Quelle
  `certdata.txt` aus NSS, MPL-2.0). Das sind **Daten, kein Code**.
* **Welche:** eine NAMENTLICH aufgeführte Auswahl, zurzeit elf: ISRG
  Root X1/X2 (Let's Encrypt), DigiCert Global Root CA/G2/G3, Baltimore
  CyberTrust, USERTrust RSA, GlobalSign Root CA, AAA Certificate
  Services, GTS Root R1/R4.
* **Warum nicht alle 142:** ein Prozess hat auf Osum **448 KiB Halde**
  (`kernel/sys.fi`: BRK_BASE 0x40080000, MMAP_TOP 0x400F0000). Das ganze
  Bündel sind 200 KiB PEM; `x509.Store` hält jede Wurzel gleichzeitig im
  Speicher. Elf Wurzeln sind 15261 Oktett.
* **Wie ins Abbild:** als gewöhnliche Datei beim Bauen
  (`mkfs.py … /etc/ssl/roots.pem=…`). Beim Installieren käme sie über
  `kernel/user/install.fi` mit.
* **Was daran fehlt:** ein Weg, sie zu ERNEUERN. Eine zurückgezogene
  Wurzel bleibt drin, bis ein neues Abbild kommt. Eigener Punkt in
  `docs/ROADMAP-UPDATE.md`.

---

## DIESE KRYPTOGRAPHIE IST NICHT AUDITIERT

Ausdrücklich, weil es sonst jemand für geprüft hält:

* Sie wurde in Firns Runde B5 gegen OpenSSL und Pythons `cryptography`
  gemessen: 647 Fälle über die Primitiven, davon 49 Gegenproben, die
  fehlschlagen MÜSSEN; 18 Handschlagfälle gegen `openssl s_server` und
  das öffentliche Netz, davon 7 Verweigerungen; 512 KiB Oktett für
  Oktett über dreißig Datensätze; ein Mann in der Mitte, der ein Bit
  umdreht.
* Das ist sehr viel mehr als nichts und sehr viel weniger als ein Audit.
* Sie ist **nicht in jedem Pfad laufzeitkonstant**. Seitenkanäle sind
  nicht untersucht worden.
* Es gibt **keine Widerrufsprüfung** (kein CRL, kein OCSP). Ein
  gestohlenes und zurückgezogenes Zertifikat wird angenommen, solange es
  nicht abgelaufen ist.
* Es gibt **kein Zertifikatspinning** und kein HSTS.

Wer etwas dahinter legt, das wehtut, wenn es gelesen wird, tut das auf
eigene Verantwortung. Für „ein Update-Paket holen, dessen Signatur
ohnehin einzeln geprüft wird" reicht es.

---

## WAS AUF EINEM ECHTEN BRETT ALS NÄCHSTES SCHIEFGEHT

Ehrlich geraten, in der Reihenfolge der Wahrscheinlichkeit -- damit
Justin weiß, wonach er beim ersten Versuch schaut:

1. **Die Netzkarte ist ein Realtek 8168.** Dann sagt die serielle
   Ausgabe seit dieser Runde `netdev: no driver for 0x10ec:0x8168` --
   und das ist der Punkt, an dem die nächste Runde anfängt.
2. **Die Platte hängt an AHCI und nicht an NVMe.** Dann findet der Kern
   sie nicht: `blk.fi` kennt nur ATA-PIO und NVMe. Ein Laptop von 2014
   mit SATA-SSD kommt bis zum Rahmenpuffer und dann nicht weiter.
3. **Das Interrupt-Routing.** Ohne AML-Interpreter wird das
   Interrupt-Line-Register geglaubt. Auf den meisten Brettern hat die
   Firmware es richtig ausgefüllt; wo nicht, kommt kein
   Netzunterbrechungssignal an -- die Karte funktioniert dann trotzdem,
   weil `netd` den Ring auch abfragt, nur langsamer.
4. **Die Tastatur hängt an I²C-HID** (viele Ultrabooks). Dann bleibt die
   Eingabe tot; USB-Tastatur einstecken hilft, weil das
   HID-Boot-Protokoll da ist.
5. **Secure Boot.** Limine ohne Signatur startet nicht. Im UEFI
   abschalten.


---

## TEIL B -- PLATTE

*(urspruenglicher Titel: ECHTE HARDWARE: WELCHE PLATTE OSUM FINDET UND WELCHE NICHT)*

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

---

## Ton (Runde HDA, 30.08.2026)

**Was gemessen ist:** `kernel/hda.fi` hat mit GENAU EINEM Codec geredet --
QEMUs `hda-duplex` (0x1af4:0x0022), vier Knoten, ein Wandler, eine
Buchse, Weglaenge 2. Alles, was unten ueber ein Brett steht, ist eine
Aussage ueber die Spezifikation (Intel High Definition Audio 1.0a) und
NICHT ueber gemessene Hardware.

**Was auf echtem Blech trotzdem fehlen kann:**

| Punkt | Was passiert | Woran man es erkennt |
|---|---|---|
| Buchsenbelegung leer oder falsch | der Treiber waehlt eine Buchse, aus der nichts kommt | `audgraph` drucken: `cfg=` ist 0x00000000 oder `punkt=1` bei allen |
| EAPD ueber GPIO statt ueber Verb 0x70C | alles richtig eingestellt, Lautsprecher bleibt still | `audgraph`: die Buchse hat PINCAP Bit 16 nicht |
| Kopfhoererbuchse | wird beim Aufsetzen einmal gewaehlt; Einstecken im Betrieb schaltet nicht um | fehlende unaufgeforderte Antworten |
| zwei analoge Codecs | der erste mit einem Weg gewinnt -- das kann der falsche sein | `hda_codecaddr` im Bericht |
| Regler ohne DMA-Positionspuffer | wird ERKANNT und auf LPIB umgeschaltet | `posfix` = 1 |
| nur MSI, keine Leitung im I/O-APIC | bleibt abfragend | `irqarmed` = 0 -- der Ton laeuft trotzdem (Gegenprobe `noaudirq`) |
| `SDnFIFOS`/`SDnFIFOW` | Vorgabewerte, nicht angefasst | Knacken bei knappem FIFO |
| HDMI/DisplayPort | wird UEBERSPRUNGEN (digitale Knoten) | kein Ton am Bildschirm |
| Aufnahme | nicht gebaut | -- |

**Die drei Zahlen, die man auf einem fremden Brett zuerst ansieht**
(`osum audio audgraph audsay`):

```
hda: statests 0x....     welche Codecs sich melden
hda: codec 0 p=1 w=1 c=1 p = antwortet, w = Graph gelesen, c = Weg gefunden
hda: bereit ... dac=N pin=M len=L
```

Bleibt `c=0`, ist der Graph gelesen und kein Weg zu einer analogen Buchse
gefunden -- dann sagt `hda-graph:` Knoten fuer Knoten, was der Codec
anbietet und wie die Buchsen bewertet wurden.
