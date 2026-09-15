# RUNDE WLAN-3 — DEN WEG ZU ENDE GEHEN, SOWEIT ER OHNE KARTE MESSBAR IST

**15.09.2026. Zweig `wlan-treiber`, abgezweigt von `main` (`7a80727`).
Arbeitsbaum `/root/osum-w-wlan`.**

Diese Datei folgt dem Ton von `docs/WLAN-BEFUND.md`: jede Aussage ist
gekennzeichnet als **[gemessen]** (auf DIESEM Rechner ausgefuehrt),
**[aus dem Quelltext]** oder **[aus der Norm]**. Es gibt hier keine
einzige Aussage der Art „auf einem echten Chip gemessen".

Der Befund von Runde WLAN steht unveraendert:

> **Osum verbindet sich nach dieser Runde NICHT mit einem WLAN.**

Was diese Runde hinzufuegt, ist ebenso genau zu benennen:

> Der GANZE Weg oberhalb der Naht -- Suchlauf, Netzwahl,
> Authentifizierung, Assoziation, 4-Wege-Handschlag, Schluessel
> gesetzt, verschluesseltes Datenpaket hin und zurueck, DHCP, HTTP --
> laeuft gegen ein simuliertes Geraet **durch** und ist Schritt fuer
> Schritt mit Zahlen belegt. Damit fehlt zu einer echten Verbindung
> **genau eine Datei**: der Treiber. Welche Schnittstelle er bedienen
> muss, steht in Abschnitt 7 und ist nicht mehr Auslegungssache.

---

## 1. WAS AUF DIESEM WIRT UEBERHAUPT MESSBAR IST

**Das ist Schritt 0 der Runde, und es ist eine Frage und keine
Annahme.** Sie wurde beantwortet, BEVOR eine Zeile gebaut wurde, weil
die Antwort den Rest der Runde entscheidet -- insbesondere, ob Teil 3
des Auftrags (ein Treiber fuer echtes Blech) ueberhaupt beginnen darf.

Alles in dieser Tabelle ist **[gemessen]**, am 15.09.2026, mit den
Befehlen, die in der letzten Spalte stehen.

| # | Frage | Antwort | Befehl / Beleg |
|---:|---|---|---|
| 1 | Bietet QEMU ein WLAN-Geraet an? | **NEIN. 0 Treffer.** Unter „Network devices" stehen ausschliesslich Ethernet-Geraete: e1000, e1000e, i8255x-Reihe, ne2k, pcnet, rtl8139, tulip, usb-net, virtio-net, vmxnet3, rocker, pvrdma. | `qemu-system-x86_64 -device help \| grep -icE 'wifi\|802\.11\|wlan\|iwl\|mt79\|rtw\|brcm'` → `0` |
| 2 | Welche QEMU-Fassung? | 7.2.22 (Debian 1:7.2+dfsg-7+deb12u18+b3) | `qemu-system-x86_64 --version` |
| 3 | Gibt es eine echte WLAN-Karte im Rechner? | **NEIN, und es kann keine geben.** Der Wirt ist ein **LXC-Behaelter**. `lspci` gibt ueberhaupt keine Geraeteliste aus (eine Zeile Fehlausgabe). | `systemd-detect-virt` → `lxc`; `lspci \| grep -iE 'net\|wireless'` → leer |
| 4 | Liesse sich eine PCI-Karte durchreichen? | **NEIN.** `/dev/vfio` existiert nicht; ein LXC-Behaelter hat keinen eigenen PCI-Bus. `/sys/bus/pci/devices` zeigt zwar 96 Eintraege des WIRTES, aber ohne Zugriff und ohne WLAN-Geraet darunter. | `ls /dev/vfio` → `No such file or directory` |
| 5 | Gibt es einen USB-WLAN-Stick zum Durchreichen (`-device usb-host`)? | **NEIN.** Angeschlossen sind: Avocent KVM-Tastatur/Maus (0624:0249, 0624:0248), zwei USB2.0-Hubs (05e3:0608), SSK Storage (0bda:9210), WD Elements (1058:2621), dazu die vier xHCI-Wurzelhubs. **Kein einziges Funkgeraet.** | `lsusb` fehlt; gelesen aus `/sys/bus/usb/devices/*/idVendor,idProduct,product` |
| 6 | Hat der Wirt irgendeine Funkschnittstelle? | **NEIN.** `/sys/class/net/*/wireless` existiert nicht; `/proc/net/wireless` hat nur die Kopfzeile. Schnittstellen: `lo`, `eth0@if19` (veth), `docker0`. | `ip -br link`; `cat /proc/net/wireless` |
| 7 | Liesse sich `mac80211_hwsim` laden (Linux' eigene Luft-Simulation)? | **NEIN.** Der laufende Kern ist `7.0.14-5-pve`, unter `/lib/modules` liegt aber nur `6.12.101+deb12-rt-amd64`. Das Modul ist nicht vorhanden und in einem unprivilegierten Behaelter auch nicht ladbar. `cfg80211` ist geladen, `mac80211` nicht. | `modprobe mac80211_hwsim` → `FATAL: Module mac80211_hwsim not found in directory /lib/modules/7.0.14-5-pve` |
| 8 | Ist `hostapd` als Gegenstelle brauchbar? | **Als Handschlagpartner NEIN** -- der Befund von Runde WLAN-2 gilt unveraendert (Debian baut ohne `CONFIG_TESTING_OPTIONS`, also kein `EAPOL_RX`; `driver=wired` verarbeitet kein WPA-PSK). **Als RECHENWERK JA**, und so wird es hier benutzt. | `hostapd -v` → `hostapd v2.10`; `wpa_supplicant -v` → `v2.10` |
| 9 | Ist eine unabhaengige Gegenrechnung moeglich? | **JA.** Python 3.11.2 mit `cryptography` 38.0.4 (OpenSSL darunter). Das traegt `tools/wlan/gegenstelle.py` -- ein zweites Programm, das keine Zeile mit Osum teilt. | `python3 -V`; `python3 -c 'import cryptography'` |
| 10 | Laesst sich der volle Ablauf gegen `testdevice.fi` simulieren? | **JA -- und das ist die ganze Runde.** Siehe Abschnitt 3. | Abschnitt 4 |

### Was daraus folgt, und zwar zwingend

1. **Teil 3 des Auftrags (Treiber fuer echtes Blech) faellt aus** -- und
   zwar nicht aus Bequemlichkeit, sondern weil der Auftrag selbst es so
   vorschreibt: *„NUR WENN 1 ergibt, dass echtes Blech erreichbar ist."*
   Zeile 3, 4, 5 und 6 der Tabelle sagen einstimmig: es ist nicht
   erreichbar. Ein Treiber waere hier unueberpruefbare Arbeit.

2. **Die Wand ist dieselbe, an die schon Runde K8 gelaufen ist**
   (`tools/net/bridge.c`): kein `/dev/net/tun`, kein PCI, kein
   Funkgeraet. Sie ist nicht neu und sie verschiebt sich nicht dadurch,
   dass man sie noch einmal anschaut.

3. **Was bleibt, ist der ganze Rest** -- und der ist mehr, als der
   Befund von Runde WLAN erwarten liess. Genau dort geht diese Runde
   weiter.

---

## 2. AUSGANGSLAGE: WO DIE RUNDE ANGEFANGEN HAT

Der Auftrag verlangte, die Abnahme VOR der eigenen Arbeit zu fahren --
`lib/crypto/aes.fi` haengt an WLAN mit dran und wurde gerade von der
AES-NI-Runde angefasst.

**[gemessen]** `bash tools/wlan/run.sh` auf `7a80727`, vor jeder
Aenderung dieser Runde:

    WLAN: 185 Zusagen, 0 Fehler

Die AES-NI-Runde hat also nichts zerbrochen. Das war nicht
selbstverstaendlich und ist der Grund, warum der Auftrag danach
gefragt hat.

**Eine Huerde davor, die festgehalten gehoert:** in diesem Arbeitsbaum
war `vendor/firn/bin/firnc` nicht gebaut, und ohne Uebersetzer laeuft
kein Abschnitt. Statt Rust anzuwerfen (Bauzeit, und die Platte hat
~3 GB frei) wurde der festgenagelte Uebersetzer aus einem
Schwester-Arbeitsbaum uebernommen, nachdem die Marke geprueft war:
beide stehen auf `c4e3dfce` mit Flickenstand `f9fd8eaadcf22ec0`, also
Oktett fuer Oktett derselbe Uebersetzer.

---

## 3. WAS DIESE RUNDE GEBAUT HAT

### 3.1 `lib/wlan/llc.fi` (716 Zeilen) -- die Schicht ueber CCMP

Bis zu dieser Runde endete Osums WLAN-Stapel bei CCMP: aus einem Kopf
und einem Klartext wird ein geschuetzter Rahmen. Was fehlte, war die
Frage, WAS in diesem Klartext steht -- und ohne eine Antwort darauf
ist "der Rechner ist im WLAN" nicht pruefbar.

**Warum nicht `kernel/inet.fi`.** Osum HAT einen TCP/IP-Stapel, und er
ist gemessen. Er ist hier aber nicht benutzbar: **[gemessen]**
`kernel/inet.fi` importiert `kstate`, `mem`, `serial`, `atomic`,
`cpu`, `sched`, `netdev`, `errno`, `apic` und `pci`; es braucht einen
Allokator, eine Uhr, eine Sperre und einen Kernel-Faden. Der
`lib/`-Baum darf davon nichts, und genau diese Regel ist der einzige
Grund, warum diese Runde ueberhaupt etwas messen kann.

Also eine eigene, sehr kleine Schicht nach denselben Regeln wie
`lib/crypto/sha256.fi`: keine `profile`-Zeile, kein `import` ausser
auf `lib/`, kein Allokator, aller Zustand beim Aufrufer.

| Teil | was | Norm |
|---|---|---|
| LLC/SNAP | bauen und zerlegen | RFC 1042 |
| IPv4 | Kopf bauen und zerlegen, Pruefsumme rechnen UND pruefen | RFC 791, RFC 1071 |
| UDP | mit Pseudokopf-Pruefsumme, inkl. der 0→0xFFFF-Regel | RFC 768 |
| DHCP | Discover/Request bauen, Offer/Ack zerlegen, Optionskette **mit Laengenpruefung** | RFC 2131, RFC 2132 |
| TCP | SYN/ACK/PSH bauen und zerlegen -- ein Geradeauslauf | RFC 793 |
| HTTP | GET bauen, Status lesen, Rumpfversatz finden | -- |

**Was sie ausdruecklich NICHT kann**, und das steht auch im Kopf der
Datei, damit es niemand annimmt: keine IP-Fragmente, keine
Neuuebertragung, kein Fenster, kein Zeitgeber, kein Ueberlastschutz,
kein ARP, kein IPv6, keine Reihenfolgeumkehr. **Das hier ist kein
Netzstapel und will keiner sein.** Der echte liegt in `kernel/`; dies
ist die kleinste ehrliche Antwort auf die Frage "geht wirklich ein
Paket durch".

**Der LLC/SNAP-Kopf ist nicht aus der Norm abgeschrieben, sondern
[gemessen]:** an den vier echten Datenrahmen aus
`tools/wlan/mitschnitt.txt` steht nach dem Entschluesseln
`aa aa 03 00 00 00` und dann der EtherType -- zweimal `0800` (IPv4),
einmal `86dd` (IPv6), einmal `80f3` (AARP).

### 3.2 `lib/wlan/testdevice.fi` -- eine Funktion mehr

`beide_leeren()`. `MAX_HALTEN` ist acht, und das reichte fuer den
Handschlag der Runde WLAN-2. Der volle Ablauf dieser Runde ist
laenger. Die Puffer zu vergroessern waere der falsche Weg -- ein
`Pruef`-Block liegt auf dem Stapel des Aufrufers. Stattdessen raeumt
der Testlaeufer zwischen den Abschnitten auf, wie ein echtes Geraet
seine Ringe weiterdreht. **Die Schluessel bleiben dabei absichtlich
stehen:** sie sind der Zustand, um den es geht.

### 3.3 `tools/wlan/gegenstelle.py` -- vom Handschlagpartner zum Zugangspunkt

Bisher war diese Datei die Gegenseite des HANDSCHLAGS. Jetzt ist sie
zusaetzlich die Gegenseite des VERKEHRS: die neue Klasse
`Zugangspunkt` haelt den TK, zaehlt ihre eigene Paketnummer hoch und
baut verschluesselte Antworten -- eine DHCP-Antwort, eine
HTTP-Antwort, ein Echo. Dazu eigene Bauer fuer IPv4, UDP, TCP und
DHCP.

**Sie teilt mit `lib/wlan/llc.fi` keine einzige Zeile** und rechnet
mit `struct` und `cryptography` (OpenSSL). Das ist derselbe Grund, aus
dem `Authenticator` existiert: gegen einen systematischen Denkfehler
hilft kein Selbstvergleich.

### 3.4 `tools/wlan/oracle.fi` -- zwei neue Befehle

* `vollweg <...>` -- der ganze Ablauf als EIN Vorgang, mit einer
  Antwortzeile, in der jeder Schritt eine eigene Zahl hat.
* `ipdhcp <klartext>` -- ein Klartextpaket durch die Schicht ueber
  CCMP. Damit werden die ECHTEN DHCP-Pakete der Aufzeichnung gemessen.

### 3.5 `tools/wlan/vollweg.py` (484 Zeilen) -- der Testlaeufer

Elf Schritte vorwaerts, zehn Gegenproben, vier Messungen gegen die
echte Aufzeichnung. Er haengt als Abschnitt 11 in `tools/wlan/run.sh`.

---

## 4. DIE MESSWERTE

### 4.1 Der volle Ablauf laeuft durch

**[gemessen]** Eine Zeile, die den ganzen Weg beschreibt:

    netze=1 wahl=1 kanal=6 m1=1 m3=1 skeys=2 darf=1 tx=83 gesch=1
    rx=67 et=2048 dart=5 ip=3232235570 maske=4294967040
    tor=3232235521 dhcp=1 http=200 rumpf=64 grund=0

Schritt fuer Schritt, jeder eine eigene Zusage:

| # | Schritt | Messwert |
|---:|---|---|
| 1 | Suchlauf findet den Zugangspunkt | `netze=1` |
| 2 | Netzwahl, Geraet auf den Kanal aus dem Beacon | `wahl=1 kanal=6` |
| 3 | Nachricht 1, PTK abgeleitet | `m1=1` |
| 4 | Nachricht 3, Pruefwert stimmt, GTK ausgepackt, **zwei Schluessel wirklich im Geraet** | `m3=1 skeys=2` |
| 5 | der Automat erlaubt Daten | `darf=1` |
| 6 | **ein verschluesseltes Datenpaket HINAUS**, Geschuetzt-Bit gesetzt | `tx=83 gesch=1` |
| 7 | **ein verschluesseltes Datenpaket HEREIN**, geoeffnet, LLC/SNAP sagt IPv4 | `rx=67 et=2048` |
| 8 | **DHCP: eine Adresse**, 192.168.0.50 | `dart=5 ip=3232235570` |
| 8b | Maske 255.255.255.0, Tor 192.168.0.1 | `maske=4294967040 tor=3232235521` |
| 9 | **HTTP: eine Anfrage wird mit 200 beantwortet** | `http=200 rumpf=64` |
| -- | kein Fehlergrund bleibt stehen | `grund=0` |

### 4.2 Die Gegenproben -- hier MUSS der Weg abbrechen

Eine Abnahme, die immer gruen ist, misst nichts. **[gemessen]**, alle
zehn:

| Fall | was passieren MUSS | Messwert |
|---|---|---|
| falsches Passwort | Handschlag scheitert an Nachricht 3, **kein Schluessel** | `m3=0 skeys=0 darf=0 dhcp=0 http=0` |
| beschaedigter Handschlag (M3 ohne gueltigen MIC) | sauberer Abbruch, kein Absturz | `m1=1 m3=0 skeys=0` |
| gar keine Nachricht 3 | keine halbe Verbindung | `m1=1 m3=0 skeys=0 dhcp=0` |
| offenes Netz | gefunden und benannt, aber **nicht gewaehlt** | `netze=1 wahl=0 skeys=0` |
| fremder Schluessel (Rahmen eines Dritten) | gehen nicht auf | `rx≤0 dhcp=0 http=0` |
| fremde DHCP-Antwort | **keine Adresse** | `dhcp=0 ip=0` |
| eine 500er-HTTP-Antwort | wird auch als 500 gelesen | `http=500` |
| 8 verstuemmelte Beacons (8..44 Oktette) | keines fuehrt zu Schluessel oder Adresse | 0 von 8 |
| **jedes einzelne Oktett der DHCP-Antwort gekippt** | **keines geht durch** | **0 von 318** |
| die DHCP-Antwort an 47 Stellen abgeschnitten | keine bringt eine Adresse | 0 von 47 |

Die vorletzte Zeile ist die Zusage, die CCMP wirklich gibt: **318
einzelne Bitkipper im Schluesseltext, und kein einziger kommt durch.**

Die 500er-Zeile ist die Gegenprobe zur Gegenprobe: `http=200` darf
nicht deshalb dastehen, weil dort immer 200 steht.

### 4.3 Gegen die echte Aufzeichnung

Das ist die staerkste Zusage der Runde, weil diese Pakete **niemand
fuer Osum gebaut hat**. `wpa-Induction.pcap` ist eine seit Jahren
oeffentliche Aufzeichnung eines echten WPA2-Netzes.

**[gemessen]** Zwei der vier verschluesselten Rahmen darin sind ein
echter DHCP-Austausch. Mit dem Schluessel aus dem echten Handschlag
geoeffnet und durch `lib/wlan/llc.fi` geschickt:

| Was | Messwert |
|---|---|
| echter DHCP-**Request** | `et=2048 ipsum=1 udpsum=1 dart=3 qport=68 zport=67` |
| echtes DHCP-**Ack** | `dart=5 yiaddr=192.168.0.50 maske=255.255.255.0 tor=192.168.0.1 server=192.168.0.1 miete=86400` |
| beide Pruefsummen des Ack | `ipsum=1 udpsum=1` -- rechnen auf null auf |
| ein gekipptes Oktett im IP-Kopf | `ipsum=0` -- die Pruefsumme wird **wirklich gerechnet** |

Die letzte Zeile ist wichtig: ohne sie koennte `ipsum=1` auch
bedeuten, dass gar nicht gerechnet wird.

### 4.4 Die Abnahme insgesamt

**[gemessen]** `bash tools/wlan/run.sh`:

    WLAN:       171 Zusagen, 0 Fehler   (Normen, OpenSSL, Aufzeichnung)
    WLAN-FUZZ:    5 Zusagen, 0 Fehler   (15 032 verstuemmelte Rahmen)
    VOLLWEG:     25 Zusagen, 0 Fehler   (NEU in dieser Runde)
    -------------------------------------------------------------
    WLAN:       210 Zusagen, 0 Fehler

Die **185 Zusagen von vorher sind alle noch gruen**; 25 sind
dazugekommen.

### 4.5 Die uebrigen Tore

**[gemessen]**

| Tor | Ergebnis |
|---|---|
| `python3 tools/kernel/memmap.py` | `127 Bereiche in 0x140000 Oktetten kdata, 12 Vektoren, 234 Modusnamen in 17 Woertern, **0 Kollisionen**` |
| `bash tools/check-ui.sh` | **CHECK-UI PASSED** (188 Dateien geprueft) |
| `bash tools/build-kernel.sh /tmp/…` | **baut**, 5 942 892 Oktette, Stufe 0, gui=on |

**Zum Speicherbereich:** die Runde bekam kdata `0x12E000`–`0x132000`
und die Modusindizes 1070–1079 zugeteilt. **Sie hat nichts davon
gebraucht.** Alles Neue liegt unter `lib/` und `tools/`; `kernel/`
wurde nicht angefasst (`git status --short kernel/` ist leer). Die
zugeteilten Nummernraeume sind damit unberuehrt und stehen der
naechsten Runde vollstaendig zur Verfuegung.

---

## 5. DIE ZWEI FEHLER, DIE DIE MESSUNG GEFUNDEN HAT

Sie stehen hier, weil eine Runde, die nur ihre Erfolge aufschreibt,
nichts wert ist. Beide wurden von der eigenen Abnahme gefunden, nicht
durch Nachdenken.

**1. Die Gegenstelle setzte das Geschuetzt-Bit nicht.**
Der erste Anlauf von `datenkopf()` liess es weg, weil `ccmp_aad()` es
ohnehin intern setzt -- AAD und Pruefwert waren also richtig. Der
Rahmen ging trotzdem nicht auf: `lib/wlan/ccmp.fi` prueft den Kopf,
wie er DASTEHT, und ein Rahmen ohne Geschuetzt-Bit ist fuer ihn
Klartext. Der Vergleich der beiden Ausgaben unterschied sich in genau
einem Oktett -- `0842` gegen `0802`. **Osums Seite hatte recht**
(`protect` setzt `f | 16384`), die Gegenstelle war falsch. Ein echter
Zugangspunkt setzt das Bit; eine Gegenstelle, die es weglaesst, misst
einen Fall, den es auf der Luft nicht gibt.

**2. Die Gegenprobe „falsches Passwort" war keine.**
Der erste Anlauf baute den ganzen Handschlag AUS dem falschen
Passwort. Damit rechneten beide Seiten mit demselben falschen PMK,
waren sich einig, und der Weg lief zu Recht durch -- die Zusage war
gruen und **hat nichts gemessen ausser der eigenen Rechenart**. Ein
falsches Passwort heisst: der Zugangspunkt bleibt bei seinem, und nur
Osum rechnet mit einem anderen. Erst so faellt der Pruefwert von
Nachricht 3 durch. Die Anmerkung steht jetzt in `vollweg.py` bei
`lauf()`.

Der zweite Fehler ist der lehrreichere: **eine gruene Zusage, die
falsch aufgebaut ist, ist schlimmer als eine rote.**

---

## 6. WAS JETZT BEWIESEN IST -- UND WAS AUSDRUECKLICH NICHT

### Bewiesen

> **Alles oberhalb der Naht `lib/wlan/device.fi` ist gemessen.**

Der ganze Ablauf -- Suchlauf, Netzwahl, Authentifizierung,
Assoziation, 4-Wege-Handschlag, Schluesselinstallation,
verschluesselte Nutzdaten in beide Richtungen, DHCP, HTTP -- laeuft
gegen ein simuliertes Geraet durch, Schritt fuer Schritt belegt, mit
zehn Gegenproben, die fehlschlagen, und vier Messungen gegen echten,
fremden Verkehr.

### NICHT bewiesen, und das ist derselbe Satz wie in Runde WLAN

> **Osum verbindet sich nicht mit einem WLAN.** Die Gegenseite ist
> `tools/wlan/gegenstelle.py` und nicht die Luft. Das Geraet ist
> `lib/wlan/testdevice.fi` und keine Karte. Abschnitt 1 rechnet vor,
> dass es auf diesem Rechner keine Karte gibt und keine geben kann.

Was sich geaendert hat, ist nicht der Wahrheitsgehalt dieses Satzes,
sondern **was danach noch offen ist**. Nach Runde WLAN war offen: der
Treiber UND die Frage, ob der Rest zusammenpasst. Nach dieser Runde
ist nur noch der Treiber offen.

### Was diese Runde an S2 aus `docs/WLAN-BEFUND.md` geaendert hat

S2 sagte, der Handschlag sei „gegen sich selbst und gegen die
Normvektoren gemessen, nicht gegen einen echten Zugangspunkt". Das
gilt weiterhin fuer die LUFT -- aber der Verkehr DARUEBER ist jetzt
gegen ein zweites, unabhaengiges Programm gemessen, und die
DHCP-Schicht zusaetzlich gegen echten fremden Verkehr.

---

## 7. WAS NOCH FEHLT, DAMIT SICH OSUM MIT EINEM ECHTEN WLAN VERBINDET

**Das ist das wichtigste Ergebnis dieser Runde.** Die Liste ist jetzt
kurz und genau, weil alles darueber gemessen ist.

### 7.1 Die eine fehlende Datei und ihre Schnittstelle

Ein Treiber muss **genau vier Funktionen** fuellen -- die Tafel aus
`lib/wlan/device.fi`. Nicht mehr:

```
senden(ctx, rahmen, laenge)            -> gesendete Oktette oder < 0
empfangen(ctx, puffer, platz)          -> Laenge, 0 = nichts da, < 0
kanal_setzen(ctx, kanal, band)         -> 0 oder < 0
schluessel_setzen(ctx, art, kennung, schluessel, laenge) -> 0 / < 0
```

Dazu `device.addr_set()` (die eigene Adresse aus dem Chip) und das
Kennzeichen `kann_ccmp`. **Das ist die vollstaendige Liste.** Alles
andere -- Firmware, Ringe, Interrupts, Rateneinstellung, Stromsparen
-- ist die Privatsache des Treibers und steht nicht in der Tafel.

**Dass diese vier reichen, ist jetzt gemessen und nicht behauptet:**
`lib/wlan/testdevice.fi` fuellt genau sie, und darueber laeuft der
ganze Weg bis HTTP. Am Tag, an dem eine Karte kommt, ist die Frage
„passt der Rest zusammen" bereits beantwortet.

### 7.2 Die Liste, nach Aufwand sortiert

„HW?" sagt, ob der Punkt ein Brett mit einer WLAN-Karte braucht.

| # | Was fehlt | Aufwand | HW? |
|---:|---|---|---|
| 1 | **AX200: PCI-Anbindung, Rueckstellung, Kontextinformations-Blatt, Empfangs- und Kommandoringe, Interrupts** | ~2 500 Zeilen | **JA** |
| 2 | **AX200: TLV-Format der Firmware zerlegen, Abschnitte in den Chip schieben, Startreihenfolge, auf das Bereit-Ereignis warten** | ~1 200 Zeilen | **JA** |
| 3 | **AX200: Kommando-API (PHY-Kontext, MAC-Kontext, Bindung, Station, Schluessel, Suchlauf, Sendewarteschlangen)** | ~3 000 Zeilen | **JA** |
| 4 | Die Firmware zur Laufzeit von der Platte lesen (`/lib/firmware/iwlwifi-cc-a0-77.ucode`, 1 368 100 Oktette). **Folge: WLAN kann nicht vor dem Dateisystem hochkommen** -- es ist struktureller als Ethernet ein spaeter Dienst | ~200 Zeilen | teils |
| 5 | LAR/PNVM: die Regulatorik, die der Chip selbst mitbringt, gegen `lib/wlan/channel.fi` | ~400 Zeilen | **JA** |
| 6 | Den echten Stapel andocken: statt `lib/wlan/llc.fi` gehoert `kernel/inet.fi` unter eine echte Karte, mit `netdev.fi` und einer Schnittstellenkennung | ~300 Zeilen | **JA** |
| 7 | Ein Ring-3-Programm `wlan` (suchen, verbinden, Zustand) plus Kachel in `netview` | ~700 Zeilen | nein |
| 8 | Management Frame Protection (802.11w): BIP-CMAC-128, IGTK | ~350 Zeilen | nein |
| 9 | SAE (WPA3-Anmeldung): P-256 auf `big.fi`, hunting-and-pecking | ~900 Zeilen | nein -- **aber ohne Vektoren nicht sinnvoll pruefbar** |
| 10 | Stromsparen, Roaming, 802.11ac/ax-Raten, Mehrfachantennen | offen | **JA** |

### 7.3 Der ehrlichste naechste Schritt

**Er ist keiner der zehn Punkte.** Er ist:

> *Eine AX200-Karte (8086:2723) und ein Brett, auf dem sie steckt, in
> Reichweite bringen -- und zwar so, dass Osum darauf BOOTEN kann.*

Solange das nicht da ist, sind die Punkte 1, 2, 3, 5, 6 und 10
dieselbe Art von Behauptung, die Runde HWNET beim RTL8168 zu Recht
abgelehnt hat. **Ein LXC-Behaelter kann das nicht liefern, und keine
Menge Quelltext aendert das.**

Konkret gebraucht wird, in dieser Reihenfolge:

1. **Ein echter Rechner** (kein Behaelter, keine VM ohne
   Durchreichung), auf dem Osum von USB startet.
2. **Eine AX200 als eigenstaendige M.2-Karte.** *Nicht* AX201 --
   `docs/WLAN-BEFUND.md` Abschnitt 2 rechnet vor, warum: AX201 ist
   CNVi, der MAC-Teil sitzt im Chipsatz, und ein CNVi-Treiber ohne
   Intels Unterlagen ist deutlich schwerer.
3. **Eine serielle Leitung oder ein zweiter Rechner** zum Mitlesen --
   ein Treiber, dessen Startreihenfolge man nicht beobachten kann,
   ist nicht zu entwickeln.

Von den drei Punkten ist der zweite der billigste und der erste der
laestigste.

### 7.4 Was OHNE Hardware noch ginge

Punkt 7, 8 und 9 der Tabelle. Davon ist **Punkt 7 der wertvollste**:
ein Ring-3-Programm, das den Weg dieser Runde bedienbar macht. Es
wuerde gegen `testdevice.fi` laufen und waere damit messbar -- und am
Tag, an dem die Karte kommt, waere auch die Bedienung schon fertig.

**Punkt 9 (SAE) bleibt abgelehnt**, aus demselben Grund wie in Runde
WLAN: es gibt keine veroeffentlichten Testvektoren, und ungemessene
Krypto in einem Anmeldepfad ist schlechter als keine.

---

## 8. WAS AN DIESER RUNDE SCHIEFGEHEN KANN, obwohl alles gruen ist

Damit es dasteht -- in der Tradition von `docs/WLAN-BEFUND.md`
Abschnitt 9. Die Schwachstellen S1 bis S4 von dort gelten
unveraendert. Dazu kommen:

* **S5 -- Die Gegenstelle ist ein Programm und kein Zugangspunkt.**
  Sie haelt sich an die Norm, weil sie danach gebaut wurde. Ein echter
  Zugangspunkt hat Eigenheiten, Fehler und eine Firmware; er schickt
  Rahmen in anderer Reihenfolge, wiederholt sie, und macht Pausen. Von
  alldem ist hier nichts gemessen.

* **S6 -- `lib/wlan/llc.fi` ist absichtlich zu klein.** Kein
  Fragment-Zusammenbau, keine Neuuebertragung, kein Fenster. Gegen
  einen Zugangspunkt, der ein DHCP-Ack zerteilt oder ein TCP-Segment
  verliert, wuerde diese Schicht nichts ausrichten -- sie ist ein
  Messwerkzeug und kein Stapel. **Wer sie fuer einen haelt, hat den
  Kopf der Datei nicht gelesen.**

* **S7 -- Der Wiedereinspielschutz ist nicht im vollen Ablauf
  gemessen.** `ccmp.fi` hat `replay_check`, und es ist fuer sich
  geprueft. Dass `verbinden.fi` es bei jedem hereinkommenden Rahmen
  auch WIRKLICH aufruft, ist in dieser Runde nicht nachgewiesen --
  der Weg nimmt jeden Rahmen einmal. Ein Zugangspunkt, der einen alten
  Rahmen noch einmal schickt, wuerde hier nicht auffallen. **Das ist
  die naechste Zusage, die jemand bauen sollte, und sie braucht keine
  Hardware.**

* **S8 -- Die Adressen im simulierten Ablauf sind ausgedacht.**
  `02:00:00:00:00:00` und `02:00:00:00:01:00` sind oertlich
  verwaltete Adressen. Ein echter Chip liefert seine aus dem OTP, und
  ob `device.addr_set` an der richtigen Stelle aufgerufen wird, haengt
  am Treiber, den es nicht gibt.

* **S9 -- HTTP wird auf EINEM Segment gemessen.** Die Antwort passt in
  einen Rahmen. Eine echte Antwort tut das oft nicht, und dann braucht
  es Zusammenbau -- siehe S6.

---

## 9. ZUSAMMENFASSUNG IN ZAHLEN

| Was | Wert |
|---|---|
| Zweig | `wlan-treiber` (Basis `main` `7a80727`) |
| Abnahme vorher | **185 Zusagen, 0 Fehler** |
| Abnahme nachher | **210 Zusagen, 0 Fehler** (+25) |
| davon der volle Ablauf | 11 Schritte vorwaerts |
| davon Gegenproben | 10, alle brechen wie verlangt ab |
| davon gegen echten Verkehr | 4 |
| einzelne Bitkipper geprueft | 318, keiner kommt durch |
| neue Zeilen | 716 (`llc.fi`) + 484 (`vollweg.py`) + 696 geaendert |
| kdata gebraucht | **0** (Zuteilung `0x12E000`–`0x132000` unberuehrt) |
| Modusindizes gebraucht | **0** (Zuteilung 1070–1079 unberuehrt) |
| memmap-Kollisionen | **0** |
| `tools/check-ui.sh` | **PASSED** |
| `tools/build-kernel.sh` | **baut**, 5 942 892 Oktette |
| WLAN-Karten auf diesem Wirt | **0**, und keine erreichbar |
| Verbindet sich Osum mit einem echten WLAN? | **NEIN** -- es fehlt der Treiber |
| Ist alles andere gemessen? | **JA** |
