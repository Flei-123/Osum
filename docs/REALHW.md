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
* **Teil C -- Netz, zweiter Anlauf (Runde RTL, 30.08.2026).** Der
  Realtek RTL8168/8169, der Intel I219, und warum Teil A den Realtek zu
  Unrecht fuer unpruefbar gehalten hat. Teil A bleibt unveraendert
  stehen; Teil C sagt, welcher seiner Saetze nicht mehr gilt.

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
| **Eingabe, PS/2** | `kernel/kbd.fi` (Port 0x60, IRQ 1), `kernel/ps2m.fi` (Maus) | unverändert im Verhalten, aber nicht mehr allein: `kbd.on_code` ist jetzt der gemeinsame Trichter, in den PS/2, USB-HID und I²C-HID münden. Der Super-Latch (Runde NETVIEW) gilt für alle drei -- gemessen als Regression | -- | Auf Desktops fast immer noch da (der 8042 lebt im Chipsatz weiter). **Auf vielen modernen Laptops NICHT**: dort hängt die Tastatur an einem internen USB- oder I²C-HID-Gerät |
| **Eingabe, USB-HID** | `kernel/xhci.fi` + `kernel/usb.fi`: xHCI, Geräteaufzählung, HID-Boot-Protokoll für Tastatur UND Maus | **RUNDE HID:** `kernel/hidrep.fi` zerlegt Berichtsbeschreibungen (Usage Pages, Usages, Report IDs, Input/Output/Feature, Logical Min/Max, Report Size/Count, Collections, Push/Pop). `usb.fi` holt sie mit `GET_DESCRIPTOR(0x22)` an der **Schnittstelle** und schaltet auf `SET_PROTOCOL 1`. Damit: mehr als sechs Tasten gleichzeitig (NKRO), alle acht Zusatztasten (Alt und Super kamen über USB vorher NIE an), mehr Knöpfe, Rad an beliebiger Bitlage, Geräte mit Report IDs, Geräte **ohne** Boot-Protokoll. Das Boot-Protokoll bleibt als Rückfallweg | Keine Output-Reports (Tastatur-LEDs), keine Feature-Reports zur Laufzeit, kein Hotplug-Neuzerlegen bei mehreren HID-Schnittstellen an einem Gerät | USB-Tastatur/Maus/Tablet: geht. `-device usb-tablet` (Klasse 03:00:00, kein Boot-Protokoll) wurde vorher **abgelehnt** und läuft jetzt |
| **Eingabe, I²C-HID** | **NICHTS.** Auf vielen Laptops damit GAR KEINE Eingabe | **RUNDE HID:** `kernel/i2chid.fi`. Designware/LPSS-I²C über PCI gesucht und an `IC_COMP_TYPE == 0x44570140` nachgeprüft; HID-over-I²C (HID-Descriptor-Register, Report-Descriptor-Register, Eingaberegister); Gerätesuche über einen **Ersatzweg** (siehe unten) | **Kein AML-Interpreter**, also kein `_CRS`-Auswerten, kein `_DSM`, kein `GpioInt`. Und: der ganze Registerteil ist **nur aus der Spezifikation** -- QEMU hat keinen Designware-I²C | Ultrabooks mit ELAN/Synaptics-Touchpad an I²C. Ob es dort wirklich läuft, ist **nicht gemessen** |
| **Eingabe, Touchpad** | **NICHTS** | **RUNDE HID:** Multitouch-Berichte aus der Berichtsbeschreibung: Tip Switch, Contact Identifier, Contact Count, X/Y je Finger. Daraus Zeiger (relativ aus zwei Lagen, mit Kontaktnummer, damit der Zeiger beim Fingerwechsel nicht springt), Klick und Zwei-Finger-Rollen. Mündet über `gfx.mouse_packet` in denselben Zeiger wie die PS/2-Maus | Alle weiteren Gesten (drei Finger, Kneifen, Randstreifen, Tippen statt Klicken) -- das ist eine eigene Runde. Palm Rejection | Präzisions-Touchpads melden ausschließlich über Report-Deskriptoren; genau das geht jetzt |
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
4. **Die Tastatur hängt an I²C-HID** (viele Ultrabooks). Nach Runde HID
   gibt es dafür einen Weg (`kernel/i2chid.fi`), aber er ist **nicht auf
   echtem Blech gemessen** -- QEMU hat keinen Designware-I²C. Es kann
   sein, dass er auf Anhieb geht; es kann auch sein, dass er am ersten
   Register stehenbleibt. USB-Tastatur einstecken hilft weiterhin
   zuverlässig, und mit dem generischen Weg jetzt auch für Geräte ohne
   Boot-Protokoll.
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

## TEIL C -- NETZ, ZWEITER ANLAUF

Runde RTL, 30.08.2026. Zweig `rtl`, abgezweigt von `mergeline2`
(a919787). Der ausfuehrliche Bericht steht in `docs/ROUNDRTL.md`; hier
steht nur, was sich fuer *"Osum auf einem gewoehnlichen PC"* geaendert
hat.

### C.0 WELCHER SATZ AUS TEIL A NICHT MEHR GILT

Teil A schreibt unter der Ueberschrift *"RTL8168/8169 -- geprueft und
NICHT gebaut, mit Begruendung"*:

> QEMU hat `-device rtl8139`, und das ist NICHT derselbe Chip. […] Ein
> Treiber fuer den 8139 wuerde ueber den 8168 **nichts** beweisen.

Der Schluss war falsch, und zwar aus einem Grund, den Teil A nicht
gesehen hat: der RTL8139 hat **ab PCI-Revision 0x20** einen zweiten
Betriebszustand, den **C+-Modus**, und in dem hat er Deskriptorringe --
dieselben, die der 8169 hat, mit demselben 16-Oktett-Deskriptor,
demselben OWN-Bit, demselben EOR-Bit. Der RTL8169 *ist* der
herausgeloeste C+-Teil des 8139C+; Linux' Treiber dafuer hiess
`8139cp.c`, bevor `r8169.c` daraus wurde.

QEMU emuliert diesen Zustand (`currCPlusTxDesc`, `currCPlusRxDesc`,
`cplus_enabled` im Binaerprogramm von qemu-system-x86_64 7.2). Damit ist
die Ringmechanik hier messbar, ohne ein Brett.

**Der Rest von Teil A gilt weiter, insbesondere sein Massstab:** ein
Treiber ohne eine einzige Messung ist eine Behauptung. Deshalb steht
unten Zeile fuer Zeile, was gemessen ist und was aus dem Datenblatt
kommt.

### C.1 DIE TABELLE, fortgeschrieben

| Klasse | Vor Runde RTL | Nach Runde RTL | Fehlt weiter |
|---|---|---|---|
| **Netz, Realtek** | nichts. `netdev: no driver for 0x10ec:0x8168` | `kernel/r8169.fi`: RTL8169/8168/8111/8101 **und** RTL8139C+. In QEMU gemessen: 20/20 Pings, 262144 Oktett TCP mit **6224 KiB/s**, 0 Pruefsummenfehler, 0 Wiederholungen, 0 Rahmen ausser der Reihe | die PHY-Firmwaretabellen der ueber vierzig 8168-Ausfuehrungen; MDIO auf 8168DP/EP; MSI |
| **Netz, Intel PCH** | nichts. I219 stand in `e1000.fi` als *"bewusst nicht in der Liste"* | der PCH-Zweig in `kernel/e1000.fi`: I217/I218/I219 (dreizehn Geraetenummern). **Datenweg geteilt mit dem gemessenen e1000**, Aufsetzweg aus dem Datenblatt | `e1000_flush_desc_rings` (der Haenger auf Skylake+), PHY-Firmware, K1/LTR |
| **Netz, Intel 2,5G** | nichts | **erkannt, kein Treiber**: `-> none  igc silicon, advanced descriptors`, mit PCI-Nummer | der ganze igc-Treiber (~700 Zeilen, eigenes Deskriptorformat) |
| **Netz, unbekannt** | Nummer genannt | Nummer genannt **und Grund**, wenn der Kern den Chip kennt (igc, igb, WLAN, RTL8139 ohne C+, anderer Hersteller) | -- |
| Netz, virtio / Intel 8254x | siehe Teil A | unveraendert | -- |
| **WLAN** | nichts | nichts. Aber AX200/AX201/AX210 werden in der Tabelle **beim Namen genannt** (`wifi, needs 802.11 + fw`) statt stillschweigend uebergangen | ALLES |

### C.2 WAS AUF DEM DRAHT GEMESSEN WURDE

`bash tools/rtl/run.sh`, QEMU 7.2.22 unter TCG (ohne KVM), derselbe
Draht und dieselbe Methodik wie Teil A: `tools/net/bridge.c`, veth-Paar,
Netzraum mit dem Linux-Kern darin. **67 Zusagen, 0 gefallen.**

| | rtl8139 (C+) | virtio-net-pci | e1000 |
|---|---|---|---|
| Ping, 20 Anfragen | **20 beantwortet** | (Teil A: 20) | (Teil A: 20) |
| Umlaufzeit, Mittel | 5,181 ms | (Teil A: 5,75 ms) | (Teil A: 5,15 ms) |
| TCP hinein | 262144 Oktett | 262144 Oktett | 262144 Oktett |
| **Durchsatz** | **6224 KiB/s** | 6242 KiB/s | 3278 KiB/s |
| Rahmen empfangen | 185 | 188 | 186 |
| Unterbrechungen | 23 | 33 | 19 |
| Pruefsummenfehler | 0 | 0 | 0 |
| Wiederholungen | 0 | 0 | 0 |
| Ausser der Reihe | 0 | -- | -- |
| Verworfen (Ring voll) | 0 | 0 | 0 |
| DHCP von busybox udhcpd | Adresse bezogen | (Teil A) | (Teil A) |

Die Zahlen fuer virtio und e1000 stammen aus DEMSELBEN Lauf und liegen
etwas anders als in Teil A, weil dieser Server mehrere Runden
gleichzeitig faehrt. Die Spalten sind untereinander vergleichbar, weil
sie nacheinander im selben Lauf entstanden sind.

Zusaetzlich gemessen, weil ein Ping es nie ausloest:

| Fall | Ergebnis |
|---|---|
| Sendering absichtlich ueberfuellt | 127 von 128 Plaetzen belegt, die 9 weiteren Versuche **alle** abgewiesen und gezaehlt |
| Rahmen von 2049 Oktett (> Puffer) | abgewiesen, fasst den Ring nicht an |
| Kabel gezogen (`set_link off`) | 100 % Verlust |
| Kabel wieder dran | 0 % Verlust, **ohne Neustart**, `link=1` |
| Rahmen, die der Chip als fehlerhaft meldete | 0 |

### C.3 DER FEHLER, DEN DIE MESSUNG GEFUNDEN HAT

Mit **32** Ringplaetzen -- der Zahl, die `e1000.fi` benutzt -- lieferte
der Treiber 64 KiB TCP mit 6589 KiB/s, aber 256 KiB nur mit
**286 KiB/s** und 41 Abschnitten ausser der Reihe. Kein Zaehler des
Treibers und keiner des Stapels zeigte einen Fehler; nur der Durchsatz.

Die Ursache ist ein Unterschied zwischen den **emulierten Chips**:
findet QEMUs e1000 keinen freien Deskriptor, *legt er den Rahmen
beiseite* (`flush_queue_timer`, in Teil A als Aergernis beschrieben);
QEMUs rtl8139 im C+-Modus **wirft ihn weg**. **Ein echter RTL8168
verhaelt sich wie der rtl8139**, nicht wie QEMUs e1000. Also wurde der
Ring auf **128** Plaetze vergroessert (Linux' r8169 nimmt 256), was
520 KiB kostet: **286 -> 6224 KiB/s**, 0 ausser der Reihe.

Fuer echtes Blech heisst das: **ein Netztreiber fuer diesen Kern braucht
mehr als 32 Empfangsdeskriptoren**, sobald die Gegenstelle ein
64-KiB-Fenster benutzt. `e1000.fi` hat weiterhin 32 und kommt in QEMU
damit durch, weil QEMU nachsichtig ist. Auf einem echten 8254x waere das
derselbe Verlust. Das ist ein offener Punkt fuer `e1000.fi`.

### C.4 WAS AUF ECHTER HARDWARE TROTZDEM SCHIEFGEHEN KANN

Ehrlich aufgezaehlt; kein Lauf dieser Runde hat einen dieser Punkte
beruehren koennen. Ausfuehrlich in `docs/ROUNDRTL.md` Abschnitt 7.

**Realtek 8168/8169**

1. **Die PHY-Firmware.** Es gibt ueber vierzig Ausfuehrungen des 8168,
   und Linux bringt fuer die meisten eine eigene Tabelle von
   PHY-Registerschreibvorgaengen mit. Dieser Treiber laedt **keine** und
   verlaesst sich darauf, dass die Karte selbst aushandelt -- was die
   meisten tun und manche nicht. **Der wahrscheinlichste Ausfallgrund.**
2. **MDIO auf 8168DP/EP** braucht einen anderen Weg als PHYAR 0x60.
   Dort bliebe die Verbindungsanzeige leer; der Datenweg liefe trotzdem.
3. **Der Sendeanstoss auf 0x38** (beim 8139C+ ist es 0xD9) ist nie
   ausgefuehrt worden. Steht er falsch, sendet die Karte nichts, und man
   sieht es an `tx_f` > 0 bei `rx_f` = 0.
4. **Kein MSI/MSI-X**, der Pin durch den I/O-APIC. Ohne AML-Interpreter
   kommt die Leitungsnummer aus dem Konfigurationsraum; auf manchen
   Brettern ist sie falsch. Der Stapel dreht dann Leerlaufrunden statt
   zu stehen -- aber er wird langsam.

**Intel I219 -- hier liegt die Grenze, und sie ist scharf**

Der **Datenweg** ist derselbe Quelltext, den der 82540EM in QEMU
zwanzigtausend Rahmen lang ausfuehrt. **Nicht gemessen ist der ganze
Aufsetzweg**, und der ist beim I219 gerade der schwierige Teil, weil sein
PHY nicht am MAC haengt, sondern an einem Bus, den sich der MAC mit der
Verwaltungsfirmware (Intel ME/CSME) teilt:

5. Die Semaphore (`EXTCNF_CTRL` Bit 5), `MDIC`, das Abschalten von ULP
   (`FEXTNVM7` Bit 5) -- alles gebaut, **nie ausgefuehrt**.
6. Die Adresse: auf der PCH-Linie gibt es **kein EEPROM an EERD**. Der
   Treiber liest RAL/RAH **vor** dem Ruecksetzen und schreibt sie danach
   zurueck. Aus dem Datenblatt.
7. **BEWUSST NICHT GEBAUT: `e1000_flush_desc_rings`.** Auf Skylake und
   spaeter kann ein Ruecksetzen den Chip *haengen lassen*, wenn die
   Verwaltungsfirmware gerade Verkehr hat. Der Kunstgriff dagegen
   schickt einen Blindrahmen los; das ohne echtes Brett zu schreiben
   waere nicht verantwortbar. **Das ist der wahrscheinlichste Weg, auf
   dem ein I219-Laptop mit Osum haengenbleibt.**
8. Haelt die Firmware den PHY (SMBus-Zustand), antwortet MDIC gar nicht.
   Der Treiber merkt das (`phy=0xFFFFFFFF`) und kommt dann nicht hoch,
   statt sich aufzuhaengen. Das ist gebaut.

**Beide**

9. Die Schranken sind Zaehlschleifen und keine Uhren (`SPIN_LIMIT` =
   2 Millionen, wie in `nvme.fi`, `e1000.fi`, `ahci.fi`). Auf blankem
   Blech laufen sie um Groessenordnungen schneller.
10. Hoechstens zwei Karten, kein Hotplug, keine geteilten Vektoren.

### C.5 WAS DIE SERIELLE LEITUNG AUF EINEM BRETT SAGEN WIRD

Das ist der praktische Ertrag der Runde. Ein Brett, das nicht ins Netz
kommt, sagt jetzt eines von diesen drei Dingen:

    netdev: c0=r8169 bdf=0x18          <- es gibt einen Treiber
    netdev: c0=i219 bdf=0xfa
    netdev: no driver for 0x8086:0x125b  igc silicon, advanced descriptors
    netdev: no driver for 0x14e4:0x1686  other vendor, no driver
    netdev: no driver for 0x1234:0x5678  <- unbekannt, ohne erfundenen Grund

Und mit dem Wort `nictab` auf der Kommandozeile laesst sich die
Treibertabelle **ohne die Karte** gegen eine eingebaute Nummernliste
fahren -- das ist der einzige Weg, die Wahl fuer einen I219 oder einen
RTL8168 zu pruefen, ohne einen zu besitzen.

---

# TEIL D — DER STAND NACH RUNDE BLECH (02.09.2026)

*Zweig `blech`, abgezweigt von `main` (`163984d`). Diese Tabelle ersetzt
für die genannten Zeilen die Tabelle in Teil A: die dort steht, ist die
vom 28.08.2026.*

**Die ehrlichste Seite des Projekts, und deshalb die wichtigste Regel
für sie: „geht" heißt hier IN `main` UND GEMESSEN.** Es gibt in diesem
Repository Treiber, die gebaut und grün sind und trotzdem auf keinem
Rechner laufen, weil ihr Zweig nicht gemerged ist. Die bekommen eine
eigene Spalte und nicht ein Häkchen.

## DIE TABELLE

| Klasse | Geht (in `main`, gemessen) | Gebaut & grün, aber NICHT in `main` | Geht nicht |
|---|---|---|---|
| **Netz, kabelgebunden** | virtio-net (`1AF4:1000/1041`, nur virtuell); Intel 8254x/82574 — **genau** `8086:100E, 100F, 1015, 1026, 1028, 10D3` (`e1000.fi::supports`) | **Realtek RTL8169/8168/8111/8101 + RTL8139C+** (`kernel/r8169.fi`, Zweig `rtl`, 1239 Z., *tools/rtl/run.sh: 67/0*); **Intel I217/I218/I219** (PCH-Zweig in `e1000.fi`, derselbe Zweig) | Intel I210/I211/**I225/I226** (igb/igc); Broadcom; Aquantia; Marvell |
| **WLAN** | nichts | nichts | **alles** — 802.11-MAC, Firmwareladen, WPA2/3, Regulatorik |
| **Platte, NVMe** | `nvme.fi`, DMA, Warteschlangen, MSI-X; **seit BLECH: mehrere Namensräume** — Liste über CNS 0x02, Größe und Blockformat je Namensraum, Lesen je Namensraum (*gemessen: 3 Namensräume, NSID 1/2/7, Block 0 je Oktett für Oktett gegen das Wirtsabbild*) | — | Einen anderen Namensraum als 1 als **Wurzel** einhängen; Fehlerbehandlung bei fehlerhaftem Medium; Namensraumverwaltung (anlegen/löschen) |
| **Platte, SATA/AHCI** | `ahci.fi` (`01:06:01`), Port-Register, Kommandolisten, FIS | — | **RAID-Modus** (`01:04`) — wird seit BLECH **benannt** (s. u.), aber nicht gelesen |
| **Platte, IDE/ATA** | ATA-PIO auf 0x1F0, Meister und Sklave | — | LBA48 (Grenze bleibt **128 GiB**) |
| **Platte, USB** | Stick über **xHCI**, BOT + SCSI, als `blk.DEV_USB` | Stick über **EHCI** — gelesen und Oktett für Oktett geprüft, aber **noch kein `blk`-Gerät** (`DEV_EHCI` fehlt) | eMMC/SD (`08:05`) — seit BLECH benannt; SCSI/SAS — benannt |
| **Wurzelwahl beim Start** | **seit BLECH gebaut**: `rootsel.fi` sucht NVMe → AHCI → USB → IDE und nimmt den ersten, dessen Wurzel sich wirklich einhängen lässt; die Entscheidung steht im Startbericht | — | Wurzel auf einer FAT- oder ext4-Partition; Wurzel über Netz |
| **USB-Hostcontroller** | **xHCI** (`0C:03:30`); **seit BLECH: EHCI** (`0C:03:20`) — Firmwareübergabe, periodische *und* asynchrone Liste, Aufzählung, HID-Boot-Tastatur, Massenspeicher | — | **UHCI/OHCI** (`0C:03:00/10`) — seit BLECH wenigstens **benannt**; **Split-Übertragungen** (USB-1.1-Gerät am EHCI ohne Begleitregler); Hubs in der Tiefe; isochron |
| **Eingabe, PS/2** | `kbd.fi` (0x60, IRQ 1), `ps2m.fi` | — | — |
| **Eingabe, USB-HID** | Tastatur und Maus über **xHCI** im Boot-Protokoll; **seit BLECH: Tastatur über EHCI** (*gemessen: 6 Tasten, Abtastcodes `23 1e 26 26 18 1c` gegen den AT-Satz 1*) | **HID-Berichtsbeschreibungen** (`hidrep.fi`, 1032 Z.), **I²C-HID + Präzisions-Touchpad** (`i2chid.fi`, 795 Z.), Zweig `hid`, *tools/hid/run.sh: 57/0* | Maus über EHCI (Klasse erkannt, kein Endpunkt bedient) |
| **Grafik** | **ein** Weg: der lineare Rahmenpuffer der Firmware — UEFI-GOP über Limine / Multiboot-Bit 12, ersatzweise Bochs `0x1CE/0x1CF`. **Seit BLECH nachgerechnet** über 7 Karten und 2 Auflösungen (s. u.) | — | **kein GPU-Treiber** (bleibt so); kein KMS; kein zweiter Bildschirm; **umschaltbare Grafik: keine Meldung**; Cirrus und VMware-SVGA liefern in QEMU **gar keinen** Rahmenpuffer |
| **ACPI/Strom** | RSDP/RSDT/XSDT, MADT, FADT; C-/P-Zustände; Akku | — | **kein AML-Interpreter** → kein `_PRT`, kein `_CRS`, keine Thermalzonen, kein Deckelschalter, kein S3 |
| **Ton** | AC'97 (Zweig `media1`) | — | Intel HDA |
| **TPM** | nichts | nichts | TPM 2.0 (TIS/CRB) |

---

## WAS BLECH AN DIESER TABELLE GEÄNDERT HAT — mit den Messungen

### 1. Die Wurzel wird gesucht statt geraten

Vorher entschied die Kommandozeile. `kmain.fi::osum_stage` rief
`blk.use_ata`, und `root_from_part` rief `part.scan(state, blk.DEV_ATA)`
— beide nannten dasselbe Gerät beim Namen.

Dieselbe Maschine, ein NVMe-Riegel mit einem OFS darauf und nichts an
0x1F0, zwei Kerne:

```
main   (163984d):  osum: no drive          <- und dann nichts mehr
blech            :  rootsel: versuch nvme
                    rootsel: nvme -- WURZEL, Bloecke=8192  first=0
                    osum: mount=1   /bin: sh ls cat echo   sh exit=0
```

Ein Bewerber, der nur DA ist, gewinnt nicht: leere NVMe-Platte neben
einer AHCI-Platte mit System →
`rootsel: nvme -- keine Wurzel darauf` / `rootsel: ahci -- WURZEL`.

Und der alte Weg bleibt der erste: mit einer IDE-Wurzel läuft die neue
Suche **null Mal** (gezählt).

### 2. Der RAID-Modus wird beim Namen genannt

Das ist der häufigste Grund, aus dem ein Notebook mit Osum nicht
startet — und es ist **kein fehlender Treiber**. Gemessen mit
`-device megasas` (Klasse 01:04, genau was Intel RST hinstellt):

```
rootsel: 1000:0060 steht im RAID-Modus (01:04)
rootsel: im BIOS "SATA Mode" von RAID/RST auf AHCI stellen, dann neu
rootsel: 1b36:0007 ist ein SD/eMMC-Regler -- kein Treiber
rootsel: reihenfolge: nvme > ahci > ide
```

Ein RST-Treiber müsste undokumentierte Metadaten lesen. Der Umschalter
im BIOS sind zwei Klicks.

### 3. EHCI

```
ehci: bdf=0x20  caplen=32  hcc=0x6880  ports=6  legacy=0x68  handoff=1
ehci: msc blocks=2048  bsize=512
ehci: selftest lba=0  ok=1  sum=16054338  first=100    <- Wirt: 16054338 / 100
ehci: codes 23 1e 26 26 18 1c                          <- h a l l o Eingabe
```

`handoff=1` heißt: das BIOS-Besitzbit ist gefallen (EHCI-Spezifikation
5.1). Auf echtem Blech ist das die häufigste Ursache dafür, dass USB
„manchmal" geht.

### 4. Der Rahmenpuffer, nachgerechnet

Geprüft wird `pitch >= width*bpp/8`, `cols == width/8`,
`rows == height/16`, `phys != 0`. **9 bestanden, 0 gefallen.**
`std`, `qxl`, `bochs-display`, `VGA`, `virtio-vga` liefern
800x600/32/3200; `fbbig` liefert 1024x768/32/4096. **Cirrus und
VMware-SVGA liefern gar keinen Rahmenpuffer** (sie haben die
Bochs-Erweiterung nicht; ihr VBE läuft über INT 10h im realen Modus).
`-vga none`: der Kern sagt `fb=KEINER` und läuft weiter.

---

## WAS AUF EINEM ECHTEN BRETT ALS NÄCHSTES SCHIEFGEHT

Fortgeschrieben aus Teil A, in der Reihenfolge der Wahrscheinlichkeit:

1. **Die Netzkarte ist ein Realtek 8168 oder ein I219.** Der Treiber
   dafür ist gebaut und grün — **aber er ist nicht in `main`.** Bis der
   Zweig `rtl` gemerged ist, sagt die serielle Ausgabe weiterhin
   `netdev: no driver for 0x10ec:0x8168`.
2. **Die eingebaute Tastatur hängt an I²C-HID.** Dasselbe: gebaut und
   grün auf Zweig `hid`, nicht in `main`.
3. **Der SATA-Controller steht im RAID-Modus.** Seit BLECH sagt der Kern
   es und sagt auch, was zu tun ist. Zwei Klicks im BIOS.
4. **Die Netzkarte ist ein I225/I226.** Kein Treiber, und diese Runde hat
   ihn bewusst nicht blind gebaut (siehe `docs/RUNDE-BLECH.md`, „was noch
   fehlt"): QEMU 7.2 kennt weder `igb` noch `igc`, er wäre auf diesem
   Rechner zu keinem Zeitpunkt messbar gewesen.
5. **Das Interrupt-Routing.** Unverändert: ohne AML-Interpreter wird das
   Interrupt-Line-Register geglaubt.
6. **Secure Boot.** Limine ohne Signatur startet nicht. Im UEFI
   abschalten.
7. **Umschaltbare Grafik.** Auf die integrierte stellen — der Kern sagt
   dazu (noch) nichts Verständliches.

---

# TEIL E — WAS DER NACHTRAG ZU BLECH GEÄNDERT HAT (02.09.2026)

Der Eigner hat den igb/igc-Treiber abbestellt und stattdessen bestellt:
**Nummern ja, Treiber nein — und die Ablehnung so nützlich wie möglich.**
Für dieses Dokument heißt das: Die Spalte „Geht nicht" sagt jetzt bei
jeder Zeile **welcher Chip** und **warum**, statt zu schweigen.

## E.1 Was auf der seriellen Leitung steht, wenn nichts geht

Vorher war die einzige Auskunft eine Nummer. Jetzt gibt es **drei
Zeilenarten**, und sie haben verschiedene Aufgaben:

```
netdev: no driver for 0x10ec:0x8029  other vendor, no driver -- kein
  Treiber in diesem Kern  [RTL8029 (ne2000)]
```
> Der **Vertrag**. Der Anfang ist seit Runde HWNET unverändert, weil
> drei Testdateien darauf prüfen. Grund und Klarname hängen hinten dran.

```
netdev: bestand 00:03.0 8086:10d3 82574L (1G) -> e1000
netdev: bestand 00:04.0 1b36:0006 QEMU -> kein Treiber (kein Ethernet-Port)
netdev: bestand 2 geraete, 1 mit treiber, 1 ohne
```
> **Die Liste für Menschen** (`netdev.print_inventory`, neu). Sie läuft
> über die **ganze** PCI-Klasse 02 — also auch über die WLAN-Karte.

```
netdev: tab 0x8086:0x125c rev=0x0 -> none  igc silicon, advanced
  descriptors -- eigener Treiber noetig, e1000 passt NICHT  [I226-V (2,5G)]
```
> **Die Tabelle ohne Chip** (`nictab`). Für I225/I226/I210/I211 ist das
> der **einzig mögliche** Beweis, weil QEMU 7.2 keinen davon hat.

## E.2 Ein Loch, das bis hierher niemand gesehen hat: WLAN war unsichtbar

`netdev.probe` läuft nur über **Klasse 02 Unterklasse 00** (Ethernet).
Eine WLAN-Karte ist **02:80**. Sie tauchte deshalb in *keiner* Liste auf
— weder bei den Treibern noch bei den Abgelehnten. **In einem Notebook
ist sie oft das einzige Netzgerät.** Wer dort ein leeres `netdev:` sah,
musste glauben, der Rechner habe gar keine Netzkarte.

`print_inventory` schließt das. Gemessen mit `-device rocker` (dem
einzigen Klasse-02:80-Gerät in QEMU 7.2) — der Zweig ist also **wirklich
gefahren**, nicht nur gelesen.

**Nicht behoben und ausdrücklich so gewollt:** `probe` selbst bleibt auf
Ethernet beschränkt. Eine Suche, die plötzlich WLAN-Karten beansprucht,
wäre eine Regression in 54 grünen Abschnitten — und einen
802.11-Treiber gibt es hier nicht und wird es so bald nicht geben.

## E.3 Die Tabelle „Netz", fortgeschrieben

| Chip | Stand | Was der Kern sagt |
|---|---|---|
| Intel 8254x / 82574 (`100E, 100F, 1015, 1026, 1028, 10D3`) | **gefahren, gemessen** | `-> e1000`, mit Modellnamen (`82540EM (1G)`, `82574L (1G)`) |
| Intel I217/I218/I219 — **20 von 53** Nummern | **gefahren** (PCH-Zweig in `e1000.fi`) | `-> i219`, mit `I219-LM (1G)` / `I219-V (1G)` |
| Intel I219 — die **übrigen 33** (Tiger Lake … Arrow Lake) | **erkannt, nicht gefahren** | `I219, but this PCH step is not released` |
| Realtek RTL8169/8168/8111/8101 | **gefahren**, Rahmen gemessen | `-> r8169 [RTL8111/8168/8411] (8169/8168, Datenblatt)` |
| Realtek RTL8139C+ (Rev ≥ 0x20) | **gefahren, in QEMU gemessen** | `(8139C+, gemessen)` |
| Realtek RTL8125/8126, Killer E3000 | **gefahren, chipspezifischer Teil ungemessen** | `(8125/8126, Quelle, NICHT gemessen)` |
| Intel I225/I226 — **alle 16** Nummern | erkannt, **kein Treiber** | `igc silicon, advanced descriptors …` + Klarname |
| Intel I210/I211/I350/82575/82576/82580 — **alle 32** | erkannt, **kein Treiber** | `igb silicon, other queue set …` + Klarname |
| Broadcom, Aquantia, Qualcomm/Killer, Marvell, MediaTek, DEC, AMD, VMware | erkannt, **kein Treiber** | `other vendor, no driver …` + Klarname |
| WLAN (Intel, Realtek, Broadcom, Atheros, MediaTek) | erkannt, **kein Treiber, wird es nicht geben** | `wifi, needs 802.11 + fw …` + Klarname |

**181 PCI-Nummern** stehen in `kernel/chipname.fi`, **173 davon von
`pci.ids` bestätigt**, 8 nur aus dem Linux-Quelltext belegt, **0 fehlend**
in den drei Intel-Familien.

## E.4 Zwei Werkzeuge, die diese Tabelle widerlegen können

Ohne sie wäre die Tabelle oben eine Behauptung.

* **`tools/blech/chipnames.py`** — hält jeden Namen gegen `pci.ids` und
  den Linux-Quelltext. **Erster Lauf: 14 Namen falsch**, darunter sieben
  CNVi-Anschlüsse, die als „AX201" ausgegeben wurden (an `8086:02F0`
  kann ein AX201, ein AX203 **oder** ein Wireless-AC 9560 hängen — welches,
  steht erst in der Subsystemnummer).
* **`tools/blech/r8125regs.py`** — hält den RTL8125-Zweig gegen Linux'
  `r8169_main.c`. **Erster Lauf: der Sendeanstoß falsch** (siehe E.5).

Beide sind seit diesem Nachtrag in `tools/blech/run.sh` **angemeldet**
(Abschnitt 10) und laufen bei jeder Abnahme mit.

## E.5 Der Fehler, den nur der Abgleich finden konnte

    r8169.fi, tx_kick:        w8 (state, u, R_TPPOLL25, 64)
    Linux, rtl8169_doorbell:  RTL_W16(tp, TxPoll_8125, BIT(0))

Adresse richtig (0x90), **Breite und Wert vom alten Chip** stehen
geblieben. **Auf einer echten RTL8125:** Chip läuft an, Verbindung steht,
Empfang geht — **und kein einziges Paket verlässt die Karte.** Kein
Absturz, keine Meldung.

Das ist der Grund, warum an dieser Stelle jetzt ein Werkzeug steht: In
QEMU 7.2 **kann** dieser Zweig nicht laufen, also kann kein Test ihn
widerlegen. Der einzige Ersatz ist der zeilenweise Abgleich gegen den
Treiber, der auf echter Hardware läuft.

**Eine Stelle bleibt offen:** Wir schreiben `INT_CFG0` (0x34) Bit 0 = 1.
Linux *upstream* definiert das Bit, benutzt es nie und schreibt dort
`0x00`; unser Wert stammt aus Realteks eigenem Treiber. **Wenn eine
RTL8125 auf echtem Blech keine Unterbrechungen liefert, ist das die erste
Stelle zum Nachsehen.**

## E.6 Was auf einem echten Brett als Nächstes schiefgeht — ergänzt

Die Liste aus Teil D gilt weiter. Neu bzw. präzisiert:

8. **Die Netzkarte ist ein I225/I226 (sehr häufig auf Boards ab 2021).**
   Kein Treiber, und das bleibt vorerst so. Der Kern sagt jetzt aber
   Modell, Nummer und Grund — und `docs/RUNDE-BLECH.md` enthält den
   fertigen Bauplan. **Voraussetzung für einen Treiber: eine echte Karte.**
   QEMU hat bis heute kein `igc`-Modell.
9. **Die Netzkarte ist ein I210/I211 (häufig auf Server- und
   NAS-Boards).** Ebenfalls kein Treiber — aber **billiger nachzurüsten
   als igc**: Für Warteschlange 0 liegen Empfangs- und Senderingregister
   bei igb an **denselben Adressen wie beim gemessenen e1000**
   (`RDBAL 0x02800`, `TDBAL 0x03800`), ebenso `MDIC` und `RAL/RAH`. Es
   bleiben zwei Unterschiede: der Unterbrechungsblock
   (`EICR/EIMS/EIMC/GPIE/IVAR0`) und die Advanced-Deskriptoren.
   **Voraussetzung: QEMU 8.x** — dort gibt es ein `igb`-Gerät, und damit
   wäre der Zweig messbar statt geraten.
10. **Der Laptop hat nur WLAN.** Der Kern nennt jetzt die Karte
    (`print_inventory`), sagt aber ehrlich, dass es dafür keinen Treiber
    gibt und keinen geben wird. Für Netz braucht es einen
    USB-Ethernet-Adapter — und auch der ist **noch nicht** gebaut.

## TEIL H -- EINGABE NACH RUNDE HID (30.08.2026)

### Was jetzt wirklich geht, und woher man das weiß

| Geräteklasse | Läuft | Womit gemessen |
|---|---|---|
| PS/2-Tastatur, PS/2-Maus | ja, unverändert | `tools/kernel/run.sh`, `tools/k17/run.sh` |
| USB-Tastatur, Boot-Protokoll | ja | `-device usb-kbd`, Oktett-für-Oktett gegen den PS/2-Lauf (`tools/k17/run.sh`) |
| USB-Tastatur, Berichtsprotokoll | ja | `-device usb-kbd`, Beschreibung geholt (63 Oktett = HID 1.11 Anhang B.1), zerlegt, `gen=1` |
| USB-Maus | ja | `-device usb-mouse` |
| USB-Zeiger **ohne** Boot-Protokoll | ja -- **vorher abgelehnt** | `-device usb-tablet`, Klasse 03:00:00 |
| Tastatur mit > 6 Tasten gleichzeitig (NKRO) | ja | echte Berichte durch `hidin.report`: 8 aus EINEM Bericht, dann 11 gleichzeitig. **Kein QEMU-Gerät kann das** -- gemessen ist der Weg, nicht ein Gerät |
| Präzisions-Touchpad | Weg gebaut, mit echten Berichten gemessen | 34 Felder aus der von Microsoft vorgeschriebenen Beschreibung; +300 Geräteeinheiten → 100 Bildpunkte, Zwei-Finger → eine Radrastung. **Kein QEMU-Gerät** |
| I²C-HID | Weg gebaut, **Transport nicht gemessen** | siehe unten |

### Was NUR aus der Spezifikation stammt

Ehrlich getrennt, weil es der Unterschied zwischen „läuft" und „müsste
laufen" ist:

* **Jeder Designware-Registerzugriff** (`i2chid.fi`, alles mit
  `dw_`-Präfix, dazu `reg_read`, `versuche`, `poll`). QEMU kennt keinen
  LPSS-I²C (`-device help` listet nur `i2c-ddc` und `smbus-ipmi`).
  Taktzahlen, Warteschlangen-Schwellen und die Abbruchbehandlung stehen
  so da, wie die Unterlagen zum DW\_apb\_i2c es vorschreiben.
* **Ob ein echtes Gerät auf Register 0x0001 antwortet.** Ohne `_DSM`
  wird 0x0001 und danach 0x0020 probiert -- die beiden Werte, die in der
  Praxis vorkommen.
* **Die Berichte des Touchpads und der NKRO-Tastatur.** Ihre
  *Beschreibungen* sind echt und der Zerleger ist gegen einen zweiten
  Zerleger gemessen; dass ein bestimmtes Gerät auch wirklich so meldet,
  ist Spezifikation.

### Der ACPI-Ersatzweg -- und was später auf AML umzustellen ist

Die Runde AML baut einen AML-Interpreter auf dem Zweig `aml`.
**Nachgesehen am 30.08.2026: dieser Zweig zeigt auf denselben Commit wie
`mergeline2` -- er enthält noch keine Zeile.** Gegen eine gedachte
Schnittstelle zu bauen wäre das Schlechteste von beidem, also steht dort
ein Ersatzweg.

Er nutzt aus, dass `_CRS` eine **Ressourcenvorlage** zurückgibt, und die
ist im AML-Oktettstrom eine feste Binärstruktur -- kein Programm. Der
große Ressourcentyp `0x8E` mit Bustyp `0x01` ist eine I²C-Verbindung,
und die Sklavenadresse steht darin an Oktett +16. Diese Struktur lässt
sich in DSDT und SSDT **suchen**, ohne eine einzige AML-Anweisung
auszuführen.

**Gemessen:** in einer gebauten Tabelle mit zwei I²C-Verbindungen und
drei Ködern, die wie eine aussehen, findet er genau die zwei -- und die
Wiederholung derselben Vorlage nicht doppelt. In den **echten** ACPI-
Tabellen, die QEMU stellt (5 Stück), findet er null, was richtig ist.

**Die drei Stellen, die auf AML umzustellen sind** (stehen so auch im
Kopf von `kernel/i2chid.fi`):

| Stelle | Ersatzweg heute | Mit AML |
|---|---|---|
| `i2chid.acpi_scan` | Oktettmuster `0x8E`/Bustyp 1 in DSDT+SSDT suchen | `_CRS` des Geräts auswerten |
| `HDESC_DEFAULT` / `HDESC_ALT` | 0x0001 probieren, dann 0x0020 | `_DSM` Funktion 1 auswerten |
| `i2chid.poll` | abfragen | `GpioInt` aus `_CRS`, echte Meldung |

Grenzen des Ersatzwegs, damit sie niemand suchen muss: wird die
Ressourcenvorlage zur Laufzeit zusammengebaut statt wörtlich in der
Tabelle zu stehen, findet er sie nicht; und er kann eine gefundene
Adresse keinem *Namen* zuordnen, probiert also alle durch.

### Gemessene Latenz

Vom fertigen Bericht bis zum Oktett in der Zeilendisziplin. Median aus
fünf Läufen, QEMU/KVM auf AMD EPYC 7571, 2000 Durchläufe je Messung,
Zeitstempelzähler des Prozessors, umgerechnet mit der von `time.fi`
kalibrierten Taktzahl (~2,2 GHz).

| Weg | Zyklen | ns |
|---|---:|---:|
| PS/2 (fertiger Abtastcode in `kbd.on_code`) | 36 | 16 |
| USB-HID, Boot-Protokoll (8 Oktett) | 814 | 369 |
| USB-HID, generisch (Boot-Tastatur-Beschreibung) | 1885 | 855 |
| I²C-HID, **Softwareanteil** (NKRO, 128 Bit) | 6297 | 2857 |
| Präzisions-Touchpad (34 Felder, 5 Finger) | 9310 | 4226 |

Zwei Dinge dazu, sonst ist die Tabelle irreführend:

1. **PS/2 vergleicht sich nicht fair.** Dort liefert die Hardware EINEN
   fertigen Abtastcode; bei HID kommt ein ganzer Bericht, der erst nach
   seiner Beschreibung zerlegt werden muss. Die 36 Zyklen sind die
   Auswertung eines Codes, die 1885 die eines Berichts.
2. **Die Zeit auf dem Draht fehlt in allen Zeilen** und ist um
   Größenordnungen größer: PS/2 rund 1 ms für elf Bit bei 12,5 kHz, USB
   ein Meldeintervall (1--8 ms), I²C-HID die Übertragung bei 400 kHz.
   QEMU stellt das nicht nach, also steht es hier nicht als Zahl.

Die I²C-Zeile heißt „Softwareanteil", weil der Weg ab dem fertigen
Bericht **buchstäblich derselbe** ist wie bei USB -- dieselbe Funktion.
Sie ist höher als „USB generisch", weil dort eine Tastatur ohne
Anschlagsgrenze mit 128 Bit gemessen wird und nicht eine mit 64.

