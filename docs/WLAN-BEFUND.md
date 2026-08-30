# WLAN-BEFUND

**Runde WLAN, 30.08.2026. Zweig `wlan`, abgezweigt von `mergeline2`
(b010f75).**

Diese Datei ist Schritt 0 der Runde und ihr wichtigstes Ergebnis. Sie
wurde geschrieben, BEVOR eine Zeile Quelltext entstand, und danach nur
noch um die Zahlen ergaenzt, die die Runde tatsaechlich erreicht hat.

`docs/REALHW.md` sagt ueber WLAN in allen drei Spalten dasselbe:

> | **WLAN** | nichts | nichts | ALLES: 802.11-MAC, Firmwareladen,
> Netzwahl, WPA2/3-Supplicant, Regulatorik |

Der Auftrag dieser Runde war, das zu aendern. Der Befund vorweg, damit
niemand ihn ueberliest:

> **Osum verbindet sich nach dieser Runde NICHT mit einem WLAN, und es
> wird sich auch nach der naechsten nicht verbinden.** Was diese Runde
> baut, ist die haelfte des Weges, die man OHNE eine Karte bauen und
> OHNE eine Karte MESSEN kann. Die andere haelfte braucht ein Stueck
> Blech, das es auf diesem Rechner nicht gibt, und sie ist die
> groessere.

---

## 1. WOHER DIE ZAHLEN IN DIESER DATEI KOMMEN

Drei Arten von Aussagen, und jede ist im Text gekennzeichnet:

* **[gemessen]** — auf DIESEM Rechner ausgefuehrt, die Ausgabe steht
  darunter oder ist mit dem Befehl reproduzierbar.
* **[aus dem Quelltext]** — aus einem oeffentlichen Quelltext gelesen,
  der zum Zeitpunkt des Lesens auf diesem Rechner lag. Es steht dabei,
  welcher Baum in welchem Stand.
* **[aus der Norm / dem Datenblatt]** — aus einer Spezifikation
  entnommen, ohne dass irgendetwas davon hier nachgeprueft werden
  konnte.

**Es gibt in dieser Datei keine einzige Aussage der Art „auf einem
echten Chip gemessen".** Auf diesem Rechner liegt kein Testbrett, und
eine WLAN-Karte schon gar nicht.

Die Baeume, aus denen gelesen wurde:

| Baum | Stand | wie geholt |
|---|---|---|
| `torvalds/linux` | `08dbfad3f5040f5bdb6c529da20d6d4e81fefd72`, 2026-08-29 | `git clone --depth 1 --filter=blob:none --sparse` |
| `w1.fi/hostap.git` | `168f9755d9d0b90eb0f31147330c4d8a1fc7f4d6`, 2026-08-27 | `git clone --depth 1` |
| hostapd 2.10 | Freigabe-Tarball von w1.fi | `curl` |
| `kernel-firmware/linux-firmware` | `main`, geholt 2026-08-30 | `WHENCE` und HTTP-Kopfzeilen |

---

## 2. WELCHE CHIPS AUF JUSTINS ZIELHARDWARE REALISTISCH SIND

`docs/REALHW.md` nennt drei Familien. Alle drei sind bestaetigt — die
PCI-Nummern stehen so im Linux-Treiber:

### Intel AX200 / AX201 / AX210

[aus dem Quelltext, `drivers/net/wireless/intel/iwlwifi/pcie/drv.c`
des oben genannten Linux-Standes]

    Zeile 489  {IWL_PCI_DEVICE(0x2723, PCI_ANY_ID, iwl_ax200_mac_cfg)}
    Zeile 487  {IWL_PCI_DEVICE(0xA0F0, PCI_ANY_ID, iwl_qu_long_latency_mac_cfg)}
    Zeile 492  {IWL_PCI_DEVICE(0x2725, PCI_ANY_ID, iwl_ty_mac_cfg)}
    Zeile 1016 IWL_DEV_INFO(iwl_rf_hr, iwl_ax200_name, DEVICE(0x2723))
    Zeile 1022 IWL_DEV_INFO(iwl_rf_gf, iwl_ax210_name, DEVICE(0x2725))

Herstellernummer ist in allen Faellen 0x8086. Die Angaben aus
`REALHW.md` (8086:2723 / A0F0 / 2725) sind damit richtig.

**Ein Unterschied, den REALHW.md nicht macht und der teuer ist.** AX200
ist eine EIGENSTAENDIGE PCIe-Karte (M.2, Cyclone Peak): der ganze
Chip — MAC, Basisband, Funkteil — sitzt auf der Karte, und der Rechner
sieht ein gewoehnliches PCI-Geraet.

AX201 ist **CNVi** (Companion RF). Bei CNVi liegt der MAC-Teil IM
CHIPSATZ (PCH) des Rechners, und auf der M.2-Karte sitzt nur noch das
Funkteil; die beiden reden ueber eine Intel-eigene Verbindung
miteinander. Das ist der Grund, warum AX201 unter der PCH-Nummer
(0xA0F0 bei Tiger Lake, weitere je Chipsatzgeneration) auftaucht und
nicht unter einer Kartennummer. Fuer einen eigenen Treiber heisst das:
**AX201 ist nicht „AX200 mit anderer Nummer".** Der Zugangsweg zum Chip
ist ein anderer, die Firmware ist eine andere (`-cc-a0-` vs. die
Qu/QuZ-Reihe), und einen CNVi-Treiber ohne Intels Unterlagen zu
schreiben ist deutlich schwerer als einen fuer eine PCIe-Karte.

**Folgerung fuer die Treiberwahl:** wenn ueberhaupt ein Intel-Treiber,
dann **AX200 (8086:2723)** und nur der. Das ist eine Karte, die man
kaufen und einstecken kann, sie steckt in sehr vielen Laptops von
2019–2021, und sie ist ein normales PCI-Geraet.

### MediaTek MT7921

[aus dem Quelltext] Der Treiber liegt unter
`drivers/net/wireless/mediatek/mt76/`. Er ist der einzige der drei mit
einer halbwegs offenen Beschreibung des Kommandoformats, und die
Firmware ist deutlich kleiner. Er ist damit der beste Kandidat, wenn
man EINE Karte kaufen darf, um sie zu unterstuetzen — aber er ist nicht
der Chip, der in Justins vorhandenen Geraeten steckt, und ein Treiber
fuer einen Chip, den niemand hat, ist eine Behauptung.

### Qualcomm QCA6390

[aus dem Quelltext] `drivers/net/wireless/ath/ath11k/`. Der Chip redet
NICHT ueber ein selbstbeschreibendes Register-/Ringmodell, sondern ueber
**MHI** (Modem Host Interface) und darueber ueber **QMI**, ein
Nachrichtenprotokoll mit eigener Serialisierung, das aus Qualcomms
Modemwelt stammt. Das heisst: bevor auch nur ein Rahmen fliegt, muss man
zwei zusaetzliche Protokollschichten bauen, die mit 802.11 nichts zu tun
haben. **Fuer einen eigenen Kernel ist QCA6390 der teuerste der drei.**
Er scheidet aus.

---

## 3. DIE FIRMWARE: GROESSE UND LIZENZ

[gemessen — HTTP-`content-length` von
`gitlab.com/kernel-firmware/linux-firmware/-/raw/main/…`, 2026-08-30]

| Datei | Oktette |
|---|---:|
| `intel/iwlwifi/iwlwifi-cc-a0-77.ucode` (AX200/AX201) | 1.368.100 |
| `intel/iwlwifi/iwlwifi-ty-a0-gf-a0-89.ucode` (AX210) | 1.679.080 |
| `intel/iwlwifi/iwlwifi-so-a0-gf-a0-89.ucode` (AX211) | 1.737.012 |

Dazu kommt bei den AX210-Generationen eine zweite Datei, die PNVM
(„Platform Non-Volatile Memory", die Regulatorik- und
Plattformtabellen): `intel/iwlwifi/iwlwifi-ty-a0-gf-a0.pnvm` und
Geschwister [aus `WHENCE`, Zeilen 737–1079].

**Lizenz.** [aus dem Quelltext, `WHENCE` Zeile 1352]

    Licence: Redistributable. See LICENCE.iwlwifi_firmware for details

Also: **weitergeben ja, veraendern nein.** Das ist fuer Osum
handhabbar, hat aber eine Folge, die genau hier festgehalten gehoert:

> **Osum ist STATISCH gelinkt (Roadmap A9). Eine 1,4-MiB-Blob mit
> „keine Veraenderung erlaubt" darf NICHT in ein GPL-2.0-Abbild
> hineingelinkt werden.** Die Firmware muss zur Laufzeit von der Platte
> gelesen werden — eine Datei unter `/lib/firmware/`, die der Treiber
> oeffnet. Das ist genau der Weg, den Linux geht, und er ist auch fuer
> Osum der einzig gangbare. Er bedeutet aber, dass der WLAN-Treiber
> NICHT vor dem Dateisystem hochkommen kann; WLAN ist damit
> struktureller als Ethernet ein spaeter Dienst und kein Frueh-Treiber.

Zum Vergleich: das ganze heutige Osum-Abbild (Kern + Userland) ist
kleiner als eine dieser Firmware-Dateien. [gemessen: `kernel/` und
`lib/` zusammen 161.220 Zeilen Firn in 243 Dateien]

---

## 4. WIE GROSS DER TREIBER WIRKLICH IST

Das ist die Zahl, die entscheidet, ob Schritt 3 der Runde in den Rahmen
passt. Alle Zeilenzahlen [gemessen] mit
`find … -name '*.c' -o -name '*.h' | xargs wc -l` auf dem oben
genannten Linux-Stand.

| Teil | Zeilen | Dateien |
|---|---:|---:|
| `net/wireless/` (cfg80211 — Konfiguration, Regulatorik, Netzwahl) | 57.551 | |
| `net/mac80211/` (der 802.11-MAC in Software) | 94.382 | |
| `drivers/net/wireless/intel/iwlwifi/` **gesamt** | **185.962** | **285** |
| davon `pcie/` (Bus, Ringe, Interrupts) | 15.942 | |
| davon `fw/` (Firmwareformat, Laden, API) | 30.760 | |
| davon `mvm/` (die Betriebsart der AX-Reihe) | 56.442 | |
| davon `mld/` (die neuere Betriebsart) | 34.296 | |
| davon `cfg/` (Chiptabellen) | 2.192 | |
| davon `dvm/` (alte Chips, hier gegenstandslos) | 27.614 | |
| `drivers/net/wireless/mediatek/mt76/` | 123.038 | |
| `drivers/net/wireless/ath/ath11k/` | 82.939 | |

Und die Gegenseite, der Supplicant [gemessen, hostapd 2.10]:

| Teil | Zeilen |
|---|---:|
| `src/rsn_supp/` (der 4-Wege-Handschlag, Klientenseite) | 12.799 |
| davon `wpa.c` allein | 5.267 |
| `src/common/wpa_common.c` (PTK/PMK-Ableitung, KDE) | 3.737 |
| `src/common/ieee802_11_defs.h` (nur die Rahmenformate) | 3.380 |
| `src/common/ieee802_11_common.c` (IE-Zerlegung) | 4.332 |
| `src/common/sae.c` (WPA3) | 2.517 |
| `src/common/dragonfly.c` (die Gruppe unter SAE) | 252 |
| `src/crypto/` gesamt | 34.334 |
| `src/` gesamt | 380.699 |

Und die Stuecke, die diese Runde wirklich braucht, einzeln [gemessen]:

    src/crypto/sha1-prf.c            67
    src/crypto/sha1-pbkdf2.c         92
    src/crypto/aes-ccm.c            212
    src/crypto/aes-unwrap.c          80
    src/crypto/aes-omac1.c          173   (AES-CMAC)
    src/crypto/aes-internal-enc.c   131
    src/crypto/aes-internal.c       845   (Tabellen)

**Was daraus folgt.**

1. Die **Protokoll- und Kryptohaelfte** ist klein. Der eigentliche
   4-Wege-Handschlag ist bei hostapd ~5.300 Zeilen, und davon ist der
   groesste Teil FT, PMKSA-Zwischenspeicher, TDLS, WNM und
   802.1X/EAP — alles Dinge, die ein Rechner, der sich mit dem WLAN zu
   Hause verbindet, nicht braucht. Die Krypto darunter ist in Summe
   unter 1.600 Zeilen. **Das passt in eine Runde.**
2. Der **Treiber** ist es nicht. Selbst wenn man `dvm`, `mld`, `mei`
   und die Chiptabellen abzieht, bleiben `pcie` + `fw` + `mvm` =
   **103.144 Zeilen** [gemessen: 15.942 + 30.760 + 56.442]. Ein
   knochiger Eigenbau, der nur AX200 kann, nur 802.11n-Raten, kein
   Stromsparen, kein Scan-Offload, keine Fehlerbehandlung, waere
   optimistisch geschaetzt **6.000 bis 10.000 Zeilen** — und diese
   Schaetzung ist die unsicherste Zahl in dieser Datei, weil sie eine
   Extrapolation und keine Messung ist. Sie ist aus dem Verhaeltnis
   gebildet, das `e1000.fi` (~900 Zeilen Firn) zu Linux' `e1000`
   (~15.000 Zeilen C) hat: ungefaehr Faktor 15, wenn man alles
   weglaesst, was nicht der eine Zweck ist.
3. **Der Unterschied zwischen e1000 und AX200 ist nicht der Faktor,
   sondern die Firmware.** Bei `e1000.fi` gab es einen
   Registersatz, ein Datenblatt und einen Ring. Bei einem AX200 gibt es
   eine 1,4-MiB-Firmware in einem TLV-Format, das man erst zerlegen
   muss, ein Kontextinformations-Blatt, das dem Chip sagt, wo im
   Hauptspeicher seine Strukturen liegen, eine
   Kommando-/Antwort-Nummerierung mit ueber hundert Kommandos, deren
   Bedeutung NUR in Linux' Kopfdateien steht, und eine
   Startreihenfolge, bei der jeder Schritt auf ein Ereignis der
   Firmware wartet. **Es gibt kein oeffentliches Datenblatt fuer den
   AX200.** Was es gibt, ist `iwlwifi` — und das ist GPL-2.0, also
   lesbar und ableitbar, aber es ist eine Umsetzung und keine
   Beschreibung.

---

## 5. WAS SICH IN QEMU PRUEFEN LAESST

Die Antwort ist kuerzer als erhofft: **nichts von der Hardware.**

[gemessen auf diesem Rechner]

    $ qemu-system-x86_64 --version
    QEMU emulator version 7.2.22 (Debian 1:7.2+dfsg-7+deb12u18+b3)

    $ qemu-system-x86_64 -device help | grep -icE 'wifi|802\.11|wlan|iwl|ath|mt79'
    2

Und die beiden Treffer sind:

    267:name "athlon-v1-x86_64-cpu"
    268:name "athlon-x86_64-cpu"

**QEMU hat kein einziges 802.11-Geraet.** Die vollstaendige Liste unter
„Network devices" enthaelt e1000, e1000e, i8255x, ne2k, pcnet, rtl8139,
tulip, usb-net, virtio-net — alles Ethernet. Es gibt keinen `-device
iwlwifi`, es gibt keinen Weg, einen AX200 zu emulieren, und es hat auch
nie einen gegeben.

Was Linux stattdessen benutzt (`mac80211_hwsim`) ist ein LINUX-Modul,
das mac80211 gegen sich selbst laufen laesst. Es simuliert keinen Chip,
es simuliert die Luft — und es setzt voraus, dass man mac80211 schon
hat. Fuer Osum ist es nutzlos.

**Daraus faellt die Bauweise dieser Runde heraus, und das ist der
einzige Grund, warum sie ueberhaupt ein Ergebnis hat:**

> Alles, was nicht die Karte ist, wird **nicht in QEMU** gemessen,
> sondern auf dem WIRT, gegen dieselben Firn-Quelltexte, die der Kern
> spaeter binden wird. Das ist genau das Werkzeug, das die Runden
> TUNNEL und UPDATE fuer Ed25519 gebaut haben (`tools/*/orakel`) — ein
> Programm in Firn, das auf Linux laeuft, `lib/…` bindet, eine Zeile
> liest und eine Zeile antwortet. Ein 802.11-Rahmen ist eine Folge von
> Oktetten; ob er richtig zerlegt wird, haengt an keiner Karte.

| Was | wo pruefbar | wie |
|---|---|---|
| Rahmenformate, Beacon-Zerlegung, IE-Wanderung | **Wirt** | Rahmen aus dem Quelltext von `hostap.git` und selbst gebaute; Fuzz gegen Absturz |
| Kanaltabelle, ETSI-Regulatorik | **Wirt** | Tabellen vergleichen |
| Zustandsautomat Auth/Assoc/4-Wege | **Wirt** | Nachrichten in falscher Reihenfolge einspeisen |
| SHA-1, HMAC, PBKDF2, PRF | **Wirt** | RFC 6070 + IEEE-802.11i-Vektoren aus hostapd |
| AES, CMAC, Key Wrap, CCM | **Wirt** | NIST/RFC-Vektoren + OpenSSL ueber Python |
| CCMP (Nonce/AAD/MPDU) | **Wirt** | IEEE Std 802.11-2012 M.6.4, Vektor aus `hostap.git` |
| PCI-Erkennung eines AX200 | **nirgends** | QEMU hat den Chip nicht |
| Firmware laden | **nirgends** | dito |
| Ringe, Interrupts, ein Rahmen auf dem Draht | **nirgends** | dito |
| Suchlauf, der wirklich ein Netz findet | **nirgends** | braucht eine Antenne |

---

## 6. WAS DIESE RUNDE GEBAUT HAT

Gebaut wurden Schritt 1 und Schritt 2. **Schritt 3 (der Treiber) wurde
bewusst NICHT begonnen** — die Begruendung steht in Abschnitt 4 und
Abschnitt 5: er waere nicht messbar, und ein Treiber ohne eine einzige
Messung ist eine Behauptung. Dieselbe Entscheidung, die Runde HWNET
fuer den RTL8168 getroffen hat, aus demselben Grund.

Alles Neue liegt unter `lib/` und nicht unter `kernel/`. Das ist
Absicht und dieselbe Regel, nach der `lib/crypto/sha256.fi` in Runde
SSHD entstanden ist: **keine `profile`-Zeile, kein `import` ausser auf
`lib/`, kein Allokator, kein Systemaufruf, aller Zustand beim
Aufrufer.** Damit laesst sich derselbe Quelltext in den Kern binden, in
ein Ring-3-Programm und in einen Testlaeufer auf dem Wirt, ohne dass
eine Zeile sich aendert — und genau das ist die Voraussetzung dafuer,
dass diese Runde ueberhaupt etwas messen kann.

### Neue Krypto (`lib/crypto/`)

| Datei | was |
|---|---|
| `sha1.fi` | SHA-1 (FIPS 180-4), HMAC-SHA1 (RFC 2104), PBKDF2-HMAC-SHA1 (RFC 2898), PRF-SHA1 (IEEE 802.11i 8.5.1.1) |
| `aes.fi` | AES-128/192/256, Ver- UND Entschluesselung, AES-CMAC (RFC 4493), AES Key Wrap/Unwrap (RFC 3394), AES-CCM (RFC 3610) |

Warum neu und nicht aus `vendor/firn/lib/std/crypto/aes.fi`
uebernommen: die Datei dort sagt in ihrem eigenen Kopf, was sie ist —
AES-128 mit CBC und CFB8. Kein CCM, kein CMAC, kein Key Wrap, und
keine 256-Bit-Schluessel. Fuer CCMP und fuer den AES-CMAC-MIC der
SHA-256-AKM reicht das nicht. `lib/crypto/aes.fi` ist deshalb eine
eigene Datei nach denselben Regeln wie `sha256.fi`.

### Die 802.11-Grundschicht (`lib/wlan/`)

| Datei | was |
|---|---|
| `rahmen.fi` | Rahmenkopf zerlegen (Verwaltung/Steuerung/Daten), Adressfelder nach ToDS/FromDS, Sequenznummer, QoS, HT-Control; IE-Wanderung mit Laengenpruefung |
| `beacon.fi` | Beacon und Probe Response auswerten: SSID, DS-Kanal, HT/VHT-Kanal, Faehigkeiten, RSN-IE und WPA-IE nach Sicherheitsart, TIM, Country-IE |
| `kanal.fi` | Kanal ↔ Frequenz in allen drei Baendern, ETSI-Tabelle mit erlaubten Kanaelen, Sendeleistung, DFS-Pflicht und Innenraumbindung |
| `zustand.fi` | Der Zustandsautomat: Suchlauf → Authentifizierung → Assoziation → 4-Wege → verbunden, mit definierten Abbruechen |
| `wpa.fi` | Der Supplicant: EAPOL-Key zerlegen, PMK aus Passwort, PTK/GTK ableiten, MIC pruefen und setzen, GTK auspacken, die vier Nachrichten als Automat |
| `ccmp.fi` | CCMP: Nonce und AAD aus dem 802.11-Kopf, Ver-/Entschluesselung, Wiedereinspielschutz ueber die Paketnummer |

### Der Messplatz (`tools/wlan/`)

| Datei | was |
|---|---|
| `orakel.fi` | Ein Programm in Firn, das auf Linux laeuft und dieselben `lib/`-Dateien bindet, die der Kern binden wird. Liest eine Zeile, antwortet eine Zeile. |
| `vektoren.py` | Die Vektoren und der Vergleich. Die Herkunft steht bei jedem einzelnen. |
| `fuzz.py` | Rahmen verstuemmeln und nachsehen, dass nichts danebengreift. |
| `run.sh` | Der Abschnitt, der in `test.sh` haengt. |

**Was NICHT gebaut wurde und warum, im Einzelnen:**

* **Kein Treiber.** Abschnitt 4 und 5.
* **Kein SAE (WPA3-Anmeldung).** SAE braucht eine Gruppe — in der
  Praxis P-256 — mit Quadratwurzeln modulo p und dem
  „hunting-and-pecking"-Verfahren aus RFC 7664. `lib/crypto/big.fi`
  hat Montgomery-Multiplikation und koennte das tragen, aber es gibt
  **keine veroeffentlichten SAE-Testvektoren**, gegen die man das
  pruefen koennte; hostapd prueft SAE ausschliesslich in
  `tests/hwsim/`, also gegen zwei laufende Maschinen. Ungemessene
  Krypto in einem Anmeldepfad ist schlechter als keine. **Was hier
  trotzdem drin ist:** der 4-Wege-Handschlag kann AKM 8 (SAE) —
  Ableitung mit KDF-SHA256 und MIC mit AES-CMAC statt HMAC-SHA1. Wenn
  ein PMK auf anderem Weg da ist, geht der Rest von WPA3.
* **Kein TKIP, kein WEP.** Beide sind gebrochen. Sie werden erkannt
  und benannt, damit ein Netz nicht stumm als „offen" durchgeht, und
  dann abgelehnt.
* **Kein 802.1X / EAP.** Das ist Firmennetz. Justins Ziel ist das
  WLAN zu Hause.
* **Kein Management Frame Protection (802.11w/BIP).** Erkannt und
  gemeldet, nicht umgesetzt.

---

## 7. WIE WEIT IST DER WEG ZU „VERBINDET SICH MIT DEM HEIMISCHEN WLAN"

Ehrliche Schaetzung. Sie ist eine Schaetzung und keine Messung, und die
Begruendung steht daneben, damit man ihr widersprechen kann.

Der Weg in Etappen, mit dem Anteil am Gesamtaufwand, wie er nach
Abschnitt 4 aussieht:

| Etappe | Anteil | Stand |
|---|---:|---|
| 802.11-Rahmen verstehen und sicher zerlegen | 8 % | **fertig, gemessen** |
| Kanaele und Regulatorik | 3 % | **fertig, gemessen** |
| Krypto darunter (SHA-1/PRF/PBKDF2, AES/CMAC/KeyWrap/CCM) | 10 % | **fertig, gegen Normvektoren gemessen** |
| 4-Wege-Handschlag als Automat, WPA2 und WPA3-AKM | 9 % | **fertig, gemessen** |
| CCMP Ver-/Entschluesselung | 5 % | **fertig, gegen den Normvektor gemessen** |
| SAE (WPA3-Anmeldung) | 5 % | offen |
| Der Automat Suchlauf→Auth→Assoc, verdrahtet mit einer Karte | 5 % | **Automat fertig, Verdrahtung offen** |
| **AX200: PCI, Firmware laden, Kontextblatt, Ringe, Interrupts** | **30 %** | offen |
| **AX200: Kommando-/Antwort-API, Suchlauf, Rateneinstellung, Schluesselinstallation in der Firmware** | **20 %** | offen |
| Regulatorik gegen das, was die Firmware zulaesst (LAR/PNVM) | 5 % | offen |
| Einbau in `netdev.fi`, Profilverwaltung, Bedienoberflaeche | 5 % | offen |

**Summe fertig: ungefaehr 35 %. Aufgerundet auf die naechste ehrliche
Zahl: ein gutes Drittel.**

Und jetzt der Satz, der dazugehoert, damit das Drittel nicht falsch
gelesen wird:

> **Die restlichen zwei Drittel sind nicht zwei Drittel des Aufwands,
> sie sind zwei Drittel, von denen KEIN EINZIGES Prozent auf diesem
> Rechner messbar ist.** Alles, was noch fehlt, braucht ein Brett mit
> einem AX200 darin. Der Anteil, der ohne Hardware ueberhaupt erreichbar
> war, ist mit dieser Runde weitgehend ausgeschoepft — was danach an
> Protokoll noch fehlt (SAE), sind 5 %.

Anders gesagt: die Runde hat **etwa 85 % dessen erledigt, was sich ohne
eine Karte erledigen laesst**, und **0 % dessen, was eine Karte
braucht**.

---

## 8. FORTSETZUNGSLISTE, nach Aufwand sortiert

Aufsteigend. „Hardware?" sagt, ob der Punkt ein Brett mit einer
WLAN-Karte braucht.

| # | Was | Aufwand | Hardware? |
|---:|---|---|---|
| 1 | `netdev.fi` um eine Klasse 02:80 (Netz, sonstiges) erweitern, damit ein AX200 wenigstens **mit seiner Nummer genannt** wird statt still zu bleiben — genau wie es HWNET fuer den RTL8168 macht | ~60 Zeilen | nein |
| 2 | Beacon-Zerlegung an `netprof.fi` andocken (SSID, Sicherheitsart, Signalstaerke in die Profildatei) | ~200 Zeilen | nein, aber der Zweig `netprofil` muss erst zusammengefuehrt sein |
| 3 | Management Frame Protection (802.11w) erkennen UND umsetzen: BIP-CMAC-128, IGTK | ~350 Zeilen | nein |
| 4 | SAE (WPA3-Anmeldung): P-256 auf `big.fi`, hunting-and-pecking, Commit/Confirm | ~900 Zeilen | nein — **aber ohne Vektoren nicht sinnvoll pruefbar.** Zuerst muesste ein Messplatz gegen `hostapd` im Netzwerk-Namensraum gebaut werden |
| 5 | Ein Ring-3-Programm `wlan` (suchen, verbinden, Zustand) plus Kachel in `netview` | ~700 Zeilen | nein |
| 6 | **AX200: PCI-Anbindung, Rueckstellung, Kontextinformations-Blatt, Empfangs- und Kommandoringe, Interrupts** | ~2.500 Zeilen | **JA** |
| 7 | **AX200: TLV-Format der Firmware zerlegen, Abschnitte in den Chip schieben, Startreihenfolge, auf das Bereit-Ereignis warten** | ~1.200 Zeilen | **JA** |
| 8 | **AX200: Kommando-API (PHY-Kontext, MAC-Kontext, Bindung, Station, Schluessel, Suchlauf, Sendewarteschlangen)** | ~3.000 Zeilen | **JA** |
| 9 | LAR/PNVM: die Regulatorik, die der Chip selbst mitbringt, gegen die eigene Tabelle | ~400 Zeilen | **JA** |
| 10 | Stromsparen, Roaming, 802.11ac/ax-Raten, Mehrfachantennen | offen | **JA** |

**Der ehrlichste naechste Schritt ist nicht Punkt 6.** Er ist: *eine
AX200-Karte und ein Brett, auf dem sie steckt, in Reichweite dieses
Rechners bringen* — sonst sind die Punkte 6 bis 10 dieselbe Art von
Behauptung, die Runde HWNET beim RTL8168 zu Recht abgelehnt hat.

Punkt 1 dagegen ist billig und sofort wertvoll: heute sagt eine
Maschine mit einem AX200 gar nichts. Nach Punkt 1 sagt sie
`netdev: no driver for 0x8086:0x2723` — und das ist der Unterschied
zwischen einem Rechner, der kaputt ist, und einem Rechner, der sagt,
was ihm fehlt.

---

## 9. WAS AN DIESER RUNDE SCHIEFGEHEN KANN, obwohl alles gruen ist

Damit es dasteht:

* **S1 — Die 802.11-spezifische Bildung von Nonce und AAD in CCMP ist
  gegen GENAU EINEN veroeffentlichten Vektor gemessen** (IEEE Std
  802.11-2012 M.6.4, uebernommen aus `wlantest/test_vectors.c` von
  `hostap.git`). Die AES-CCM-Rechnung darunter ist gegen OpenSSL ueber
  viele erzeugte Eingaben gemessen, die Konstruktion darueber nur
  einmal. Ein Fehler in einem Fall, den dieser eine Vektor nicht
  beruehrt — etwa ein Rahmen mit vier Adressen oder mit QoS —, wuerde
  hier nicht auffallen.
* **S2 — Der 4-Wege-Handschlag ist gegen sich selbst und gegen die
  Normvektoren der Primitiven gemessen, nicht gegen einen echten
  Zugangspunkt.** PRF und PBKDF2 stimmen oktettgleich mit hostapds
  Vektoren; dass die richtigen Oktette in der richtigen Reihenfolge in
  die PRF gehen, folgt aus dem Text der Norm und nicht aus einer
  Messung gegen ein zweites Programm.
* **S3 — Die ETSI-Tabelle ist aus den Normtexten abgeschrieben, nicht
  aus einem Konformitaetsbericht.** Sie sagt, welche Kanaele in Europa
  erlaubt sind und mit welcher Leistung. Bevor damit jemals wirklich
  gesendet wird, gehoert sie gegen die geltende Fassung von EN 300 328
  und EN 301 893 geprueft. **Ein Rechner, der auf einem verbotenen
  Kanal sendet, ist ein Rechtsproblem und kein Fehler.** Solange kein
  Treiber existiert, sendet nichts — deshalb ist es heute unschaedlich
  und morgen nicht.
* **S4 — Nichts davon ist gegen einen boesartigen Zugangspunkt
  gemessen.** Der Fuzz-Lauf wirft verstuemmelte Rahmen hinein und
  prueft, dass nichts danebengreift. Er prueft nicht, ob ein
  Zugangspunkt, der sich absichtlich falsch verhaelt, den Automaten in
  einen Zustand bringt, in dem er Daten unverschluesselt annimmt.

---

## 10. ZUM ZWEIG `netprofil`

Der Auftrag sagte: pruefen, ob `netprofil` schon brauchbar ist, und
wenn ja, ihn hereinholen statt eine zweite Profilverwaltung zu bauen.

[gemessen, 30.08.2026]

    $ git -C /root/mg-osum log --oneline mergeline2..netprofil
    (leer)
    $ git -C /root/mg-osum diff --stat mergeline2...netprofil
    (leer)

Der Zweig steht auf `76935fe` — einem VORFAHREN von `mergeline2` — und
hat **null eigene Commits**. Im Arbeitsbaum `/root/osum-netprofil`
liegen `kernel/netprof.fi` (454 Zeilen), `kernel/user/netprof.fi`
(1.521) und `kernel/user/npt.fi` (376) als **nicht eingecheckte**
Aenderungen. Die Runde laeuft also noch.

**Es gibt nichts zu mergen.** Ein Merge waere hier ein Griff in einen
fremden, laufenden Arbeitsbaum gewesen — genau das, was der Auftrag
untersagt.

**Was diese Runde stattdessen tut:** sie baut KEINE Profilverwaltung.
`lib/wlan/beacon.fi` liefert SSID, Sicherheitsart, Kanal und
Signalstaerke als reine Rueckgabewerte und speichert nichts. Wo
`netprofil` fertig ist, wird das dort angedockt (Fortsetzungsliste
Punkt 2). Doppelt gebaut wird nichts.
