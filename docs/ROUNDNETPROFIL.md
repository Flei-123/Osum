# Runde NETPROFIL — eine Adresse je Netz

*30.08.2026 · Zweig `netprofil`, abgezweigt von `mergeline2` (76935fe) ·
`main`, `mergeline`, `mergeline2` bleiben unberührt · Abnahme:
`tools/netprofil/run.sh`, Abschnitt 31 in `./test.sh`*

Jede Zahl in dieser Datei kommt aus einem Lauf auf diesem Rechner. Wo
etwas nicht gemessen werden konnte, steht das ausdrücklich dabei.

---

## 1. Der Befund, bevor irgendetwas gebaut wurde

Osum hatte **genau eine Hardwareadresse**: die aus dem EEPROM
beziehungsweise aus der Gerätekonfiguration der Karte, in jedem Netz,
für immer. `kernel/inet.fi` fragte an vier Stellen direkt
`netdev.mac_at`, und was dort herauskam, stand als Absender in jedem
Ethernet-Rahmen.

Das ist eine Kennung, an der sich ein Mensch über Standorte hinweg
verfolgen lässt — jedes WLAN, jedes Café, jeder Flughafen sieht dieselben
sechs Oktette. Android und iOS haben deshalb seit 2020 den umgekehrten
Standardfall.

**WLAN gab und gibt es in Osum nicht.** Nachgeprüft: Treffer für
`wlan|wifi|ssid|wpa` gibt es nur in `kernel/netview.fi`, `kernel/kmain.fi`,
`kernel/bsec.fi` und `kernel/share.fi`, und alle sind Kommentare oder
Namen ohne 802.11 dahinter. Der Netzstapel steht auf virtio-net
(`kernel/virtio.fi`) und Intel 8254x (`kernel/e1000.fi`), verteilt durch
`kernel/netdev.fi`. Ein WLAN-Treiber ist **nicht** Teil dieser Runde;
was er bräuchte, steht in Abschnitt 8.

---

## 2. Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/netprof.fi` | 454 | die MAC-Richtlinie im Kern: Überlagerung je Karte, Würfeln, der Weg zurück |
| `kernel/user/nprof.fi` | 1200 | der Profilspeicher in Ring 3 — Datei, Format, Rechte, Verbindungsaufbau |
| `kernel/user/netprof.fi` | 542 | `/bin/netprof`, die Kommandozeile |
| `kernel/user/npt.fi` | 376 | `/bin/npt`, der Messläufer der Abnahme |
| `tools/netprofil/run.sh` | 669 | die Abnahme |
| dazu | | `virtio.fi` (Steuerwarteschlange), `e1000.fi` (RAL/RAH), `netdev.fi` (Verteilung), `inet.fi` (die vier Stellen), `sys.fi` (zwei Aufrufe), `settings.fi` (die achte Seite), `locale/de,en` |

### 2.1 Die drei Stufen — und warum sie **je Profil** stehen

```
geraet   die Adresse der Karte, unverändert
netz     einmal gewürfelt, in der Profildatei gemerkt, danach immer
         wieder dieselbe          <- Vorgabe für ein neues Profil
immer    bei jeder Verbindung neu gewürfelt
```

Eine globale Einstellung wäre falsch, und das ist keine Geschmacksfrage:
dasselbe Gerät braucht im Heimnetz die echte Adresse (dort hängt die
DHCP-Reservierung des Routers und oft ein Filter daran) und im Café genau
keine. Eine Richtlinie, die man beim Betreten des Hauses umschalten muss,
wird nicht umgeschaltet.

Die Vorgabe für ein neues Profil ist `netz` und **nicht** `geraet`: wer
nichts sagt, bekommt den Schutz. Die Stufe, die man ausdrücklich wählen
muss, ist die, die weniger schützt.

### 2.2 Die zwei Bits

Eine gewürfelte Adresse muss im **ersten Oktett** das Bit *lokal
verwaltet* (0x02) tragen und darf **nicht** Multicast (0x01) sein
(IEEE 802-2014, 8.2). Ohne das erste behauptet sie, aus dem Nummernkreis
eines Herstellers zu stammen; mit dem zweiten ist sie als Absender ein
Rahmen, den jeder Vermittler still wegwirft.

`netprof.roll` setzt und löscht die beiden in `normalise()`, und die
Abnahme prüft es über **20 000 Würfe** — nicht über einen: bei
zufälligen Oktetten bliebe eine fehlende Maske mit 75 Prozent
Wahrscheinlichkeit unentdeckt.

### 2.3 Die Datei

`/etc/netprofile.conf`, **eine Zeile je Profil**, Felder mit `:` getrennt
— dasselbe Format wie `/etc/passwd` und `/etc/group`, aus demselben
Grund: man kann es mit `cat` lesen und mit `edit` reparieren, wenn das
Werkzeug einmal nicht startet.

```
# name:kennung:sicherheit:bezug:ip:maske:gateway:dns:macart:macwert:auto:vorrang:zuletzt
heim:net0:offen:fest:10.0.2.99:255.255.255.0:10.0.2.2::netz:fe14ade33182:1:10:1788069441
cafe:net0:offen:dhcp:::::immer::0:20:0
```

`macwert` sind **zwölf Hexziffern ohne Trenner**. Nicht `fe:14:...`, weil
der Doppelpunkt in dieser Datei das Feldtrennzeichen ist — eine Adresse
mit Trennern ergäbe sechs zusätzliche Felder. Gelesen wird trotzdem
beides (auch mit `:` oder `-`), damit ein von Hand eingetragener Wert
nicht abgelehnt wird.

**Rechte: 0o600 root:root**, nicht 0o644 wie `/etc/passwd`. In `macwert`
steht bei der Stufe `netz` eine dauerhafte Kennung dieser Maschine in
diesem Netz, und in dieselbe Zeile gehört später das WLAN-Passwort.

Geschrieben wird über **vier Schritte** (`.neu` schreiben → alte Datei
nach `.alt` → `.neu` an ihren Platz → `.alt` löschen), genau wie
`passwd` seit Runde MULTIUSER. Der Grund steht im Quelltext und ist
gemessen: `rename` dieses Kernels **überschreibt nicht** (Runde K14,
`fs.rename_path`). Der erste Lauf dieser Runde legte das erste Profil an
und meldete danach bei jedem weiteren Speichern „die Profildatei ist
nicht schreibbar" — `-EEXIST`.

**Kaputt und unvollständig sind zwei verschiedene Dinge.** Kaputt heißt:
die Zeile hat kein Format mehr (zu wenig Felder, eine MAC, die keine
ist, eine Sicherheitsart, die es nicht gibt). Unvollständig heißt: das
Format stimmt, die Angaben reichen noch nicht zum Verbinden. Das Erste
wird gezählt, gemeldet und übersprungen; das Zweite bleibt sichtbar und
bearbeitbar, und `netprof an` sagt, was fehlt. Auch das kam aus einem
Fehlschlag: `netprof setz heim bezug fest` schrieb eine Zeile, die der
Prüfer danach als kaputt verwarf — und das Profil, das man gerade
angelegt hatte, war weg.

---

## 3. Was die Karte wirklich zulässt — gemessen, nicht behauptet

Es gibt **zwei** Adressen, und sie sind nicht dieselbe:

* **die Adresse im Rahmen.** Osum baut jeden Ethernet-Kopf selbst
  (`net.wire.eth_build`). Was als Absender darin steht, entscheidet
  allein `kernel/netprof.fi`. Das geht auf **jeder** Karte.
* **die Adresse der Karte.** Ihr Empfangsfilter lässt nur durch, was an
  sie gerichtet ist. Wer die Absenderadresse ändert, ohne den Filter
  mitzuziehen, **sendet unter neuem Namen und hört unter dem alten**.

Der zweite Punkt geht nicht auf jeder Karte. Gemessen:

| Karte | geht es? | wie |
|---|---|---|
| **virtio-net (modern)** | **ja** | Befehl `VIRTIO_NET_CTRL_MAC_ADDR_SET` (Klasse 1, Befehl 1) auf einer **dritten Warteschlange**. Diese Runde hat sie gebaut. |
| virtio-net, Adressfeld beschreiben | **nein** | QEMU nimmt den Schreibzugriff in `virtio_net_set_config` nur an, solange weder `VIRTIO_NET_F_CTRL_MAC_ADDR` **noch** `VIRTIO_F_VERSION_1` ausgehandelt sind. Osum handelt VERSION_1 aus (ohne es läge jedes Feld an einem anderen Versatz), also verpufft er: gesetzt, zurückgelesen, alte Adresse. |
| **e1000 (Intel 8254x)** | **ja** | zwei Schreibzugriffe auf RAL/RAH. Der Empfangsfilter liest sie bei jedem Rahmen. |
| eine Karte ohne Treiber | nein | `netdev.set_mac_on` gibt `false`, und das wird als `false` gemeldet. |

`set_mac_on` **liest in jedem Fall zurück** und vergleicht. Was dabei
herauskommt, steht in `MG_HWOK` und wird von `/bin/netprof stand` und
der Einstellungsseite ausgesprochen — nicht versteckt.

Der ausgehandelte Merkmalssatz mit Steuerwarteschlange:
`features=0x100830020` (MAC=Bit 5, STATUS=16, CTRL_VQ=17, CTRL_MAC=23,
VERSION_1=32). Mit dem Wort `nomacvq`: `features=0x100010020`.

**Ein Fehler, der eine halbe Stunde gekostet hat und deshalb hier
steht:** `VIRTIO_NET_CTRL_MAC_ADDR_SET` ist **1**, nicht 5.
`VIRTIO_NET_CTRL_MAC_TABLE_SET` ist 0. Mit der falschen Nummer antwortete
QEMU sauber auf der Warteschlange — mit `VIRTIO_NET_ERR` im
Antwortoktett, und die Karte behielt ihre Adresse.

---

## 4. Die Aufrufe

**Bereich 1330..1339**, im Hunderterblock, den Runde K8 dem Netz
zugewiesen hat. Ausdrücklich **nicht** ab 1980 (dort liegt Runde ASYNC
mit sechs Nummern, und Runde RING vergibt daneben gerade weitere) und
**nicht** ab 2000 (das ist die zweite Nummerierung, die Handle-ABI aus
OrientOS). Geprüft mit `python3 tools/kernel/syscalls.py --zweige` über
alle 60 Zweige dieses Repos.

```
1330 osum_macget(was, karte)          -> Zahl
1331 osum_macset(was, adresse, karte) -> 0            NUR root
```

`macget`: `MG_MAC0/1` die wirksame Adresse, `MG_HW0/1` die der Karte,
`MG_ACTIVE`, `MG_HWOK`, `MG_SETTABLE`, `MG_ROLL0/1` (würfelt, root),
`MG_ROLLS`, `MG_CHANGES`, `MG_POLICY` (die drei Stufen als eine Zahl,
0x020100 — damit Ring 3 sie nicht abschreibt).

Die Adresse geht in **Leserichtung** über den Aufruf: `aa:bb:cc:dd:ee:ff`
ist `0x0000AABBCCDDEEFF`. Intern hält `netprof.fi` das erste Oktett in
den niedrigsten acht Bit, weil es so aus dem Gerätebereich kommt; in
`sys.fi` steht deshalb eine Umrechnung und keine Zuweisung.

**Die Netzsicht gilt auch hier.** Ein Prozess unter `faked` erfährt über
1300 eine erfundene Anschrift; erführe er über 1330 die echte
Hardwareadresse, wäre die Täuschung an genau der Stelle durchschaubar, an
der sie am meisten wert ist. Die vier Fälle aus `net_call` stehen in
`mac_call` ausgeschrieben.

Speicher: `NETPROF_OFF = 0x92000`, eine Seite, aus dem Stück, das Merge 06
hinter der Aufgabentafel frei gelassen hat. Ausdrücklich **nicht** der
Rest von `NETDEV_OFF` — dort wächst `e1000.fi` mit einer dritten Einheit
hinein, und genau so sind die vier Kollisionen entstanden, die in
`kstate.fi` stehen. Eingetragen in `tools/kernel/memmap.py`.

---

## 5. Die Bedienung

### `/bin/netprof`

```
netprof                       die Profile auflisten
netprof zeige <name>          ein Profil im Einzelnen
netprof neu <name> [kennung]  anlegen (dhcp, mac=netz, auto=1)
netprof setz <name> <feld> <wert>
netprof mac <name> geraet|netz|immer
netprof loesche <name>
netprof an <name>             verbinden
netprof aus                   trennen
netprof stand                 was gerade wirklich gilt
```

`netprof stand` nennt **drei** Dinge getrennt, die man leicht für eines
hält: die Adresse auf dem Draht, die Adresse der Karte, und ob die Karte
sie angenommen hat. Gehen die ersten beiden auseinander, steht ein Satz
darunter statt einer Zahl.

### Die Einstellungsseite „Netzprofile"

Achter Reiter, hinter „Sprache" — damit die Nummern der anderen sieben
bleiben, was sie sind (dieselbe Regel, die Runde LOOK aufgeschrieben hat,
als sie die Sprachseite zurückholte). Liste der Profile, die drei Stufen,
der Adressbezug, die drei Adressfelder, fünf Knöpfe, und darunter die
zwei Adressen nebeneinander.

**Sie hat keinen eigenen Parser.** Oberfläche und Kommandozeile rufen
beide `kernel/user/nprof.fi` — so, wie `login`, `su` und `passwd` sich
`pw.fi` teilen. Eine Oberfläche mit eigenem Parser für dieselbe Datei
liest sie eines Tages anders als das Werkzeug, und dann steht in der
Liste ein Profil, das `netprof an` nicht findet.

### Umlaute

**Die Oberfläche schreibt echtes Deutsch** („gewürfelt", „Löschen",
„hört"). Sie geht durch `msg.fi` und den TrueType-Rasterer, der seit
Runde I18N 339 Zeichen kann; `tools/i18n/translit.py` rechnet es nach
(110 echte Umlautzeichen in `locale/de`, 0 Umschriften).

**Die Kommandozeile nicht**, und das ist kein Versehen: die Textkonsole
dieses Kernels hat **keinen UTF-8-Dekoder**. `serial.put` und
`ansi.echo` nehmen ein Oktett und schlagen es im Zeichensatz nach; ein
„ü" sind zwei Oktette, und auf dem Schirm stünden zwei falsche Zeichen.
Ein Umlaut wäre dort eine Verschlechterung. Sobald die Konsole UTF-8
kann, gehört `kernel/user/netprof.fi` nachgezogen; der Satz steht im Kopf
der Datei.

---

## 6. Die Messungen

Alle unter `-accel kvm`, AMD EPYC 7571, QEMU virtio-net-pci mit
`mac=52:54:00:aa:bb:cc`.

| was | Zeit |
|---|---:|
| Verbindungsaufbau **ohne** Adresswechsel (`osum_netset`, Stapel neu aufgesetzt) | **6–7 µs** |
| Verbindungsaufbau **mit** Adresswechsel (würfeln + `macset` + `netset`) | **128–153 µs** |
| davon der Adresswechsel selbst — Befehl auf der Steuerwarteschlange, mit Rückmeldung und Zurücklesen | **124–148 µs** |
| Adresswechsel ohne Steuerwarteschlange (Adressfeld schreiben und zurücklesen) | **149–191 µs** |

Der Preis der Datenschutzstufe ist also **rund 120 bis 150 µs je
Verbindung**, und er entsteht fast vollständig beim Warten auf die
Antwort der Karte. Er fällt **einmal je Verbindung** an, nicht je Rahmen.

Die Spanne ist echt und nicht geschönt: die Zahl schwankt von Lauf zu
Lauf zwischen zwei Messungen desselben Abbilds, weil ein Ausstieg aus dem
Gast unter KVM von der Wirtslast abhängt.

Bemerkenswert: der Weg **ohne** Steuerwarteschlange ist nicht billiger.
Er ist zwölf MMIO-Zugriffe (sechs schreiben, sechs zurücklesen), und
jeder davon ist unter KVM ein Ausstieg aus dem Gast — genauso teuer wie
das Warten auf eine Warteschlange, nur ohne Wirkung.

| was | Größe |
|---|---:|
| eine Profilzeile | 49 Oktette |
| `/etc/netprofile.conf` mit einem Profil samt drei Kopfzeilen | 304 Oktette |
| Kernelabbild vorher (Stufe 0, gui=on) | 3 112 516 Oktette |
| Kernelabbild nachher | 3 137 156 Oktette |
| **Preis der Runde im Kern** | **24 640 Oktette** |
| Serverabbild (`--gui off`) danach | 2 351 104 Oktette |

Zeilen: `kernel/netprof.fi` 454 · `kernel/user/nprof.fi` 1200 ·
`kernel/user/netprof.fi` 542 · `kernel/user/npt.fi` 376 ·
`tools/netprofil/run.sh` 669. Zusammen **3 241 Zeilen**.

---

## 7. Was die Abnahme misst

`tools/netprofil/run.sh`, neun Abschnitte. Die drei interessantesten
Zusagen kommen **nicht** aus Osum:

* **`tcpdump`** auf der Linux-Seite des veth-Paars sagt, welche
  Absenderadresse wirklich auf der Leitung stand.
* Der **Neighbour-Cache des Linux-Kernels** (`ip neigh`) sagt es ein
  zweites Mal.
* Die **Vergabeliste von `busybox udhcpd`** (`dumpleases`) zeigt, dass
  der DHCP-Vertrag auf der **gewürfelten** Adresse steht — und die echte
  in keinem Vertrag vorkommt.

Die Gegenproben, jede ein Lauf, in dem die Messung zusammenbricht:

| Wort | was zusammenbricht |
|---|---|
| `fixedrand` | die Zufallsquelle liefert für immer 0x5A. Alle Würfe gleich, `immer` liefert zweimal dasselbe. Ohne diesen Lauf bewiese „zwei verschiedene Adressen" nur, dass zwei Zahlen ungleich waren. |
| `nomacvq` | die Steuerwarteschlange wird nicht ausgehandelt. Draht trägt die neue Adresse, die Karte weiter `52:54:00:aa:bb:cc`, `MG_HWOK` = 0, `MG_SETTABLE` = 0. |
| `nomacvq nomacset` | zusätzlich wirkt die Überlagerung nicht. Dann steht die **echte** Adresse auf dem Draht, und tcpdump sieht sie. |

Dazu: fünf Neustarts **derselben Platte** für die Persistenz von `netz`
(gleiche Adresse nach Neustart, andere nach Löschen und Neuanlegen), eine
absichtlich kaputte Profildatei mit drei fehlerhaften Zeilen, und ein
Rechtelauf mit `su justin`.

---

## 7b. Was diese Runde an FREMDEN Abnahmen verändert hat — und was schon vorher rot war

**GEÄNDERT, genau eine Erwartung, und sie ist der Punkt der Runde:**

`tools/net/run.sh` nagelt den ausgehandelten Merkmalssatz von virtio-net
fest. Er ist mit der Steuerwarteschlange ein anderer:

```
vorher  nic: queue=64  features=0x100010020   MAC, STATUS, VERSION_1
jetzt   nic: queue=64  features=0x100830020   dazu CTRL_VQ (17), CTRL_MAC_ADDR (23)
```

Die Zeile im Läufer wurde angepasst, mit der Begründung darüber. Kein
Test wurde abgeschaltet. Die Gegenprobe steht im selben Kern: mit
`nomacvq` steht wieder `0x100010020` da, und die Karte kann ihre Adresse
messbar nicht mehr ändern.

**SCHON VORHER ROT, gemessen im Vergleich mit einem eigenen Arbeitsbaum
auf `mergeline2` (`/root/netprofil-base`, 54bf135):**

| Abschnitt | auf mergeline2 | auf netprofil |
|---|---|---|
| `tools/desktop/run.sh` | `FAIL the settings did not report their geometry -- no clicks can be computed` | **dasselbe, Wort für Wort** |
| `tools/i18n/run.sh` | 9 FAIL (Knopftexte und Bildpunktprüfungen am Einstellungsfenster: `'' erwartet 'Apply'`, `'' erwartet 'Übernehmen'`, …) | 10 FAIL derselben Art; der zehnte ist ein abgestürzter Unterlauf (`alt-k15.txt: No such file or directory`) unter Last 20 auf 12 Kernen |
| `tools/net/run.sh` | 71 bestanden, **4 FAIL** (`/bin/wget` bekam auf dem Draht keine Antwort) | 74 bestanden, **1 FAIL** (`through 20 % loss: 259312 von 262144`) |

Die Ursache der Einstellungs-Fehlschläge steht seit Runde LOOK **im
Quelltext von `kernel/user/settings.fi` selbst**: die Seite
„Darstellung" will 674 Bildpunkte Höhe, das Fenster hat 542, und der
Knopf `apply` liegt bei y=648 — also außerhalb. Diese Runde hat daran
nichts geändert und auch nichts verschlimmert: der neue Reiter ist beim
Start verborgen, und `apply` liegt danach an derselben Stelle wie
vorher (`x=10 y=648 w=140 h=26`, in beiden Bäumen).

Die Fehlschläge in `tools/net/run.sh` sind auf diesem Wirt
lastabhängig — der Bau-Server trug während der Messung drei weitere
Runden gleichzeitig (Lastmittel 15 bis 23 auf 12 Kernen). Der eine
verbliebene ist die TCP-Wiederholung durch 20 Prozent Paketverlust, und
er kam über drei Läufe auf 224 272, 259 312 und 262 144 Oktette — er
wird mit sinkender Last grün. Auf `mergeline2` fielen unter derselben
Last vier ANDERE Zusagen desselben Läufers.

**NEU DAZUGEKOMMEN und grün: `tools/netprofil/run.sh` — 68 von 68
Zusagen**, Abschnitt 31 in `./test.sh`, eingetragen in `SERIELL_RE`
(er baut denselben Namensraum wie net/netmon/netview/tunnel).

**Zwei stille Grenzen nebenbei gefunden und behoben** — beide waren
Fehler, die niemand bemerkt hätte:

* `wlib.MAXWD` war **96**, und `kernel/user/settings.fi` hatte schon vor
  dieser Runde **89** Bedienelemente. Bei Überschreitung gibt `wlib.add`
  stumm die **0** zurück — also die Nummer des ERSTEN Bedienelements.
  Ein Klick auf ein Element, das es nicht gibt, hätte irgendwo eine
  Farbe umgestellt. Jetzt 160.
* `settings.merke` warf alles über **64** weg. 25 der 89 Bedienelemente
  waren damit in keinem Reiter eingetragen — und ein Bedienelement ohne
  Reiter wird von `zeige_reiter` weder versteckt noch gezeigt, es bleibt
  einfach sichtbar. Jetzt ebenfalls 160.

---

## 8. Was für WLAN vorbereitet ist — und was ausdrücklich nicht

### Vorbereitet (steht im Format, wird gelesen und geschrieben)

| Feld / Aufruf | heute | für WLAN |
|---|---|---|
| `kennung` | Name der Schnittstelle (`net0`), Feld 40 Oktette breit | nimmt eine **SSID** auf (höchstens 32 Oktette, IEEE 802.11-2020, 9.4.2.2) |
| `sicherheit` | nur `offen` zulässig, jeder andere Wert wird **abgelehnt** | `wpa2`, `wpa3`, `wpa2-ent` … |
| MAC-Richtlinie | bereits **je Profil**, also je Netz | genau die Granularität, die ein WLAN braucht — nichts umzubauen |
| `netdev.set_mac_on` | verteilt nach Kartenart (virtio, e1000) | eine WLAN-Karte meldet sich als **dritte Art** an und beantwortet dieselbe Funktion |
| `netprof.mac_at_on` | eine Stelle, die sagt, was auf dem Draht steht | unverändert gültig — 802.11 hat dieselben sechs Oktette |
| `vorrang`, `auto`, `zuletzt` | gepflegt, heute nur angezeigt | die Grundlage für „verbinde mit dem besten bekannten Netz" |

### Nicht gebaut, und es gibt dafür auch keinen leeren Knopf

* kein 802.11: keine Firmware, keine Verwaltungsrahmen, keine Beacons
* **kein Suchlauf** und keine Liste sichtbarer Netze. `netprof suche`
  gibt es **nicht** — ein Befehl, der eine leere Liste zurückgibt, sieht
  aus wie ein kaputter Treiber; eine fehlende Fähigkeit sieht aus wie
  eine fehlende Fähigkeit.
* keine Signalstärke
* kein WPA2/WPA3-Handschlag, keine Passwortablage
* keine Regulierungsdomäne, keine Kanalwahl

### Wie groß ein echter WLAN-Treiber daneben wäre — eine ehrliche Schätzung

Diese Runde sind rund **3 000 Zeilen** (Kern, Ring 3, Abnahme
zusammengerechnet). Ein WLAN-Treiber, der auf echter Hardware ein
WPA2-Netz betritt, besteht aus vier Stücken, von denen jedes für sich
größer ist:

1. **Firmware laden und mit ihr reden.** Jede brauchbare Karte (Intel
   iwlwifi, Atheros ath9k/ath10k, Realtek) lädt beim Start einen
   Binärblob und spricht danach über ein herstellereigenes
   Nachrichtenformat mit ihm. Allein das ist mehr Code als der ganze
   virtio-Treiber dieses Repos — und es ist je Chipfamilie **anderer**
   Code. Zum Vergleich: `kernel/e1000.fi` ist 1 100 Zeilen für einen
   Chip, dessen Datenblatt öffentlich und dessen Register stabil sind.
   Für `iwlwifi` rechnet Linux mit einer fünfstelligen Zeilenzahl.
2. **802.11-Verwaltung.** Suchlauf (aktiv und passiv), Beacons lesen,
   Authentication, Association, Reassociation, Deauthentication, die
   Zustandsmaschine dazwischen, Energiesparzustände, Fragmentierung,
   Bestätigungen. Das ist der Teil, den Linux `mac80211` nennt, und
   auch ein sehr sparsamer Nachbau ist mehrere tausend Zeilen.
3. **WPA2/WPA3.** Der Vier-Wege-Handschlag mit PTK/GTK-Ableitung
   (PBKDF2-SHA1 für den PSK, HMAC-SHA1-PRF), CCMP (AES-CCM) für jeden
   Rahmen, dazu für WPA3 SAE — also Rechnen auf einer elliptischen
   Kurve mit Hash-to-Curve. Die Krypta dafür ist teilweise schon da
   (Runde TUNNEL hat ChaCha20/Poly1305 und Curve25519, Runde UPDATE
   Ed25519 und SHA-512), AES-CCM und HMAC-SHA1 sind es nicht.
4. **Regulierung.** Welcher Kanal mit welcher Leistung erlaubt ist,
   hängt vom Land ab. Das ist keine Zeile Code, sondern eine Tabelle und
   eine Verantwortung.

Realistische Größenordnung: **eine Runde von der Größe dieser hier für
den Rahmen (Profile, Suchlauf-Schnittstelle, Zustandsmaschine), plus
eine eigene Runde je Chipfamilie, plus eine Runde nur für WPA.** Also
grob **das Fünf- bis Zehnfache** — und der Teil, der von echter
Hardware abhängt, lässt sich in QEMU nicht messen, weil QEMU keine
802.11-Karte emuliert. Was diese Runde dafür getan hat, ist genau eines:
sie hat die Adresse zu einer Größe gemacht, die **je Verbindung** gesetzt
wird, statt zu einer Eigenschaft der Maschine. Ein Treiber, der später
kommt, muss die Überlagerung nicht neu erfinden.

---

## 9. Was diese Runde NICHT kann — und es steht hier, nicht im Kleingedruckten

* **Nach `netprof aus` holt sich ein DHCP-Profil die Adresse nicht von
  selbst zurück.** `aus` nimmt die Anschrift weg (0.0.0.0), und der
  eingekaufte Stapel (`vendor/firn/lib/net`) hat **keinen
  Rundruf-Ausgang**: er sucht auch für 255.255.255.255 per ARP einen
  nächsten Sprung, den es ohne Adresse nicht gibt. Das steht seit Runde
  DESKTOP im Kopf von `kernel/user/dhcp.fi` und ist die eine Grenze
  dieser Runde, die ein Benutzer wirklich merkt. Der Weg heraus sind drei
  Zeilen im Stapel — und der Stapel ist festgenagelter Vorrat.
* **`auto` und `vorrang` werden gepflegt, aber von niemandem
  ausgeführt.** Es gibt keinen Dienst, der beim Start das Profil mit dem
  besten Vorrang nimmt. Das gehört an `init` (Runde INIT) und ist eine
  eigene Runde. Die Felder stehen im Format, damit sie es dann nicht
  nachträglich tun müssen.
* **`dns` wird gespeichert und sonst nichts.** Dieser Kern hat keinen
  Auflöser. Ein Feld, das etwas vortäuschte, wäre schlimmer als ein
  leeres.
* **Ein Adresswechsel wirft offene Verbindungen weg.** `inet.remac` setzt
  den Stapel neu auf, und `stack.net_init` löscht dessen Sockettabelle.
  Das ist bei einem Adresswechsel richtig — eine TCP-Verbindung, die
  unter einer anderen Hardwareadresse weiterliefe, wäre auf jedem
  Vermittler dazwischen eine Verbindung aus dem Nichts.
* **Zwischen Schritt 2 und 3 des Speicherns gibt es kurz keine
  Profildatei.** Zwei Verzeichnisoperationen lang, ohne Ein-/Ausgabe
  dazwischen. Dieselbe Lücke wie bei `/etc/shadow`, dieselbe Antwort: ein
  `rename`, das nach POSIX ersetzt.
* **Höchstens 16 Profile.** `MAXP` in `kernel/user/nprof.fi`. Die Datei
  wird ganz in einen Puffer von 4 096 Oktetten gelesen; wer mehr braucht,
  ändert zwei Konstanten.
* **Keine echte WLAN-Karte je gesehen.** Alles über virtio-net und e1000
  ist unter QEMU gemessen. Was über echtes Blech gesagt werden kann,
  steht in `docs/REALHW.md` und ist dort als solches gekennzeichnet.
