# WLAN

**Runde WLAN-2, 06.09.2026. Zweig `wlan2`, abgezweigt von `merge6`
(a92fa00), mit dem Zweig `wlan` darin.**

Diese Datei loest `docs/WLAN-BEFUND.md` ab, wo sie ihr widerspricht,
und ergaenzt sie, wo nicht. Der Befund von Runde WLAN bleibt gueltig
und lesenswert -- er hat die Zahlen, die den Aufwand einordnen. Was
sich geaendert hat, steht hier.

Der Befund vorweg, in derselben Strenge wie beim letzten Mal:

> **Osum verbindet sich nach dieser Runde NICHT mit einem WLAN.** Es
> gibt keinen Treiber, und auf diesem Rechner kann es keinen geben.
> Was diese Runde gebracht hat: der Protokollstapel ist jetzt gegen
> ein ZWEITES, unabhaengiges Programm gemessen statt nur gegen sich
> selbst; es gibt eine Naht, an der ein Treiber andocken wird; und
> ein Rechner mit einem USB-WLAN-Stick SAGT JETZT, welcher Chip darin
> steckt, statt zu schweigen.

---

## 1. WAS SICH GEGENUEBER RUNDE WLAN GEAENDERT HAT

### 1.1 S2 ist geschlossen: gegen ein zweites Programm gemessen

Runde WLAN hat ihre eigene groesste Schwaeche so aufgeschrieben:

> **S2** -- Der 4-Wege-Handschlag ist gegen sich selbst und gegen die
> Normvektoren der Primitiven gemessen, **nicht gegen einen echten
> Zugangspunkt**. PRF und PBKDF2 stimmen oktettgleich mit hostapds
> Vektoren; dass die richtigen Oktette in der richtigen Reihenfolge in
> die PRF gehen, folgt aus dem Text der Norm und nicht aus einer
> Messung gegen ein zweites Programm.

Das ist die Fehlerklasse, gegen die Selbstvergleich blind ist: wer
beim Ableiten des PTK zweimal dieselbe falsche Annahme trifft --
einmal beim Bauen, einmal beim Pruefen --, bekommt zweimal dasselbe
falsche Ergebnis und sieht gruen.

`tools/wlan/gegenstelle.py` ist die Antwort: ein **vollstaendiger
WPA2-PSK-Authenticator**, also die Gegenseite, der

* mit Osum **keine einzige Zeile** teilt,
* unter sich **OpenSSL** benutzt (`hashlib`, `cryptography`) und nicht
  `lib/crypto/`,
* aus einem anderen Text abgeleitet ist (IEEE Std 802.11-2016 12.7),
* bei **jedem Lauf neue Zufallszahlen** wuerfelt -- also gerade nicht
  die Vektoren nachspielt, gegen die Osum schon geprueft war.

### 1.2 Der Massstab hat selbst einen Massstab

Ein selbst geschriebener Pruefer ist erst dann einer, wenn er geeicht
ist. `--selbsttest` rechnet die **echte Aufzeichnung von 2007** nach,
die schon in `tools/wlan/mitschnitt.txt` liegt (das WPA2-Netz
`Coherer` mit dem Passwort `Induction`): PMK, PTK und die Pruefwerte
der Nachrichten 2, 3 und 4 stimmen **oktettgleich** mit dem ueberein,
was damals wirklich auf dem Draht stand. Erst danach darf die
Gegenstelle Osum pruefen. [gemessen: 5 Zusagen, 0 Fehler]

### 1.3 S4 ist geschlossen: der boesartige Zugangspunkt

> **S4** -- Nichts davon ist gegen einen boesartigen Zugangspunkt
> gemessen. [...] Er prueft nicht, ob ein Zugangspunkt, der sich
> absichtlich falsch verhaelt, den Automaten in einen Zustand bringt,
> in dem er Daten unverschluesselt annimmt.

Ein echter Zugangspunkt kann das nicht pruefen, weil er sich an die
Norm haelt. Ein selbst geschriebener kann es. Die Gegenstelle hat
einen Schalter `boese`, und der Abschnitt faehrt damit: falscher
Pruefwert in Nachricht 3, Schluesseldaten **ohne** Key Wrap,
Nachricht 3 ohne Nachricht 1, Nachricht 4 zuerst. Osum lehnt jeden
Fall ab und installiert in keinem einen Schluessel.

### 1.4 Es gibt eine Naht zum Blech

`lib/wlan/geraet.fi` legt fest, welche **vier** Dinge ein
802.11-Geraet koennen muss:

| Aufruf | wofuer |
|---|---|
| `senden(rahmen, laenge)` | Auth, Assoc, Nachricht 2 und 4, Daten |
| `empfangen(puffer, platz)` | Beacon, Auth-/Assoc-Antwort, Nachricht 1 und 3, Daten |
| `kanal_setzen(kanal, band)` | der Suchlauf ist "Kanal setzen und hoeren" |
| `schluessel_setzen(art, kennung, schluessel)` | nach dem Handschlag |

Alles andere, was ein echter Treiber koennen muss -- Firmware laden,
Ringe, Interrupts, Rateneinstellung, Stromsparen --, ist **seine**
Sache und steht nicht in der Tafel. Eine Naht, die die Eigenheiten der
Karte durchreicht, ist keine Naht.

Die eine Ausnahme ist `schluessel_setzen`, und sie ist begruendet: bei
Ethernet gibt es nichts Vergleichbares, bei WLAN entschluesselt in
aller Regel die **Karte**, weil CCMP bei 300 MBit/s in Software teuer
ist. Ein Geraet, das das nicht kann, sagt es (`kann_ccmp = false`),
und dann rechnet `lib/wlan/ccmp.fi`. **Beide Wege muss die Naht
tragen** -- sonst muss man sie aufmachen, sobald die erste Karte da
ist.

**Diese Tafel ist bewusst busfrei.** Sie war nie ein PCI-Ding. Das ist
der Grund, warum Justins Zwischenruf mitten in der Runde -- es ist ein
USB-Stick und keine PCIe-Karte -- **keinen Umbau erzwungen hat**.

### 1.5 Ein Rechner mit WLAN-Stick sagt jetzt, was er hat

Siehe Abschnitt 3. Das ist die praktisch wichtigste Zeile der Runde.

---

## 2. WARUM NICHT GEGEN hostapd -- GEMESSEN, NICHT GEMEINT

Der Auftrag sagte: gegen `hostapd` messen, notfalls gegen
`mac80211_hwsim`. Das waere die erste Wahl gewesen und wurde ernsthaft
versucht. Der Befund, damit ihn niemand ein zweites Mal erarbeiten
muss [alles gemessen am 06.09.2026 auf diesem Rechner]:

| Weg | Ergebnis |
|---|---|
| `hostapd` aus Debian installieren | **geht.** 2.10, laeuft. |
| `wpa_supplicant` aus Debian | **geht.** laeuft. |
| `hostapd_cli EAPOL_RX` | `Unknown command 'EAPOL_RX'` |
| `hostapd_cli MGMT_RX_PROCESS` | `Unknown command` |
| `hostapd_cli DATA_TEST_CONFIG` | `Unknown command` |
| `hostapd -d driver=none` | laeuft bis `AP-ENABLED`, leitet PSK/GMK/GTK ab -- aber es geht **kein Rahmen hinein** |
| `hostapd driver=wired` auf einem veth | laeuft bis `AP-ENABLED`, **empfaengt** ueber AF_PACKET echte EAPOL-Rahmen, verarbeitet sie aber nicht: `IEEE 802.1X: Ignore STA - 802.1X not enabled` |
| `hostapd_cli NEW_STA` | `OK`, startet aber **keinen** 4-Wege-Handschlag |
| `wpa_supplicant -D wired` | `WPA: drop TX EAPOL in non-IEEE 802.1X mode` |
| `modprobe mac80211_hwsim` | `Module not found` -- dieser Kern (7.0.14-5-pve, Proxmox, LXC) hat **kein** `drivers/net/wireless/` |
| `/dev/net/tun` | fehlt -- dieselbe Wand wie in Runde K8, siehe `tools/net/bridge.c` |

**Der Kern der Sache:** Debian baut `hostapd` und `wpa_supplicant`
**ohne `CONFIG_TESTING_OPTIONS`**. Damit fehlen genau die Befehle, mit
denen man einen Handschlag ohne Funkgeraet einspeisen koennte. Und der
`wired`-Treiber ist in hostapd fest auf 802.1X/EAP verdrahtet -- die
WPA-PSK-Zustandsmaschine haengt nicht daran.

Ein hostapd ohne Testschalter und ohne Funkgeraet ist also **kein
Handschlagpartner**. Die Wahl stand zwischen "hostapd selbst
uebersetzen" und "die Gegenseite selbst schreiben". Es wurde die
zweite, und sie ist aus einem Grund die bessere: die eigene
Gegenstelle kann **absichtlich falsch spielen** (Abschnitt 1.3). Ein
echter Zugangspunkt kann das nicht, und die interessanten Fehler eines
Supplicanten liegen genau dort.

---

## 3. DER USB-STICK -- DIE FRAGE, DIE GERADE WIRKLICH OFFEN IST

Mitten in der Runde kam von Justin die Berichtigung: in seinem Rechner
(Ryzen, Gigabyte B450M S2H) steckt **keine PCIe-WLAN-Karte**, sondern
ein **USB-WLAN-Stick**, dessen Modell und Chip niemand kennt.

Das aendert die Reihenfolge, aber nicht die Naht. Und es macht eine
Aufgabe wichtiger als jeden Treiber: **herausfinden, welcher Chip es
ist.** Denn die USB-WLAN-Welt hat mindestens fuenf Familien, die
untereinander nichts gemeinsam haben -- anderer Firmwareweg, andere
Register, andere Kommandostruktur. Ein Treiber fuer den falschen Chip
ist nicht "halb richtig", er ist nutzlos.

`lib/wlan/usbchip.fi` loest das mit dem billigsten Mittel, das es
gibt: es erkennt den Chip an seiner USB-Nummer und **sagt seinen
Namen**. Auf einem Rechner mit einem solchen Stick steht ab jetzt auf
der Tafel:

    wifi-usb: Realtek RTL8812AU (0bda:8812), kein Treiber

**Das ist die Zeile, die Justin fotografieren soll.** Sie ist der
Unterschied zwischen einem Rechner, der schweigt, und einem, der sagt,
was ihm fehlt -- derselbe Gedanke wie bei Runde HWNET (RTL8168) und
Runde BLECH (Intel I225), hier aber mehr wert, weil die Antwort die
naechste Runde bestimmt.

Die Tabelle hat **40 Nummern** ueber fuenf Familien:

| Familie | Chips | Linux-Treiber | Anmerkung |
|---|---|---|---|
| Realtek (0x0BDA) | RTL8188EU, 8192CU, 8192EU, 8812AU, 8821AU, 8821CU, 8822BU, 8187 | `rtl8xxxu` bzw. die Baeume ausserhalb des Kerns | **mit Abstand am haeufigsten** bei billigen Sticks |
| MediaTek (0x0E8D) | MT7601U, MT7610U, MT7612U, MT7921AU | `mt7601u`, `mt76x0u/x2u`, `mt7921u` | der offenste der fuenf, kleinste Firmware |
| Ralink (0x148F) | RT5370, RT5372, RT3070, RT3072 | `rt2800usb` | alt, aber in Umlauf |
| Atheros (0x0CF3) | AR9271, AR7010 | `ath9k_htc` | freie Firmware |
| Broadcom (0x0A5C) | BCM43xx | `brcmfmac` | |

Dazu die Fremdnummern, unter denen dieselben Chips verkauft werden:
TP-Link (0x2357), Netgear (0x0846), Edimax (0x7392).

**Woher die Nummern kommen und was das wert ist.** Sie sind aus den
Treibertabellen des Linux-Baums uebernommen. Sie sind **nicht
gemessen** -- auf diesem Rechner steckt kein Stick. Genau deshalb
**benennt** die Datei nur und tut nichts: eine Nummer, die man nicht
nachgesehen hat, darf keinen Treiber ausloesen. `kernel/usb.fi` bindet
folgerichtig **keinen** WLAN-Treiber, und der Abschnitt misst das
ausdruecklich.

---

## 4. WAS GEMESSEN WURDE

`bash tools/wlan/run2.sh`, Abschnitt 43 der Abnahme.
**22 Zusagen, 0 Fehler.**

Dazu laeuft der geerbte Abschnitt 42 (Runde WLAN) auf dieser Grundlage
unveraendert weiter: **185 Zusagen, 0 Fehler**.

| Was | Zahl |
|---|---|
| Die Gegenstelle gegen die echte Aufzeichnung von 2007 | 5 Zusagen |
| Vollstaendige 4-Wege-Handschlaege gegen die Gegenstelle, jedes Mal mit **neuen** Zufallszahlen | **40** |
| davon einig ueber PMK, PTK, alle vier Pruefwerte, GTK und dessen Nummer | alle 40 |
| CCMP in **beide** Richtungen in jedem Lauf (AP verschluesselt/Osum oeffnet und umgekehrt) | alle 40 |
| Boesartige Faelle, die Osum ablehnen muss | 5 |
| USB-Nummern, die Familie **und** Klarnamen richtig ergeben | 15 geprueft von 40 in der Tabelle |
| Neue Zeilen in `lib/wlan/` | 1.341 |

### Die vier Fehler, die dieser Lauf gefunden hat

Sie standen **alle vier im neuen Python und keiner in Osum**. Das
gehoert hierher, weil es die eigentliche Nachricht des Abschnitts ist:
der neue Pruefer hat sich an Osum geeicht und nicht umgekehrt.

1. **AKM 3 als SHA-256 angenommen.** Falsch: `ist_sha256_akm` in
   `lib/wlan/wpa.fi` sagt 5, 6, 8, 9, 18. Die 3 aus dem
   Key-Info-Feld ist die *Schluesselbeschreibungs-Version* und nicht
   der AKM. Zwei verschiedene Zahlen mit demselben Wert an
   benachbarten Stellen -- eine schoene Falle.
2. **Die Antwort von `gtk` hat zwei Felder** (Schluessel und Nummer);
   der Laeufer verglich die ganze Zeile mit dem Schluessel.
3. **In der AAD stehen drei Adressen** (18 Oktette), nicht zwei.
4. **Die Paketnummer steht in der Nonce hoechstwertig zuerst** und
   wird **nicht** gedreht -- gedreht wird nur im CCMP-Kopf. Genau der
   Fehler, den Runde WLAN in ihrer ersten Fassung auch gemacht hatte
   und den derselbe Vektor gefunden hat.

Nach der Berichtigung stimmt `gegenstelle.py` oktettgleich mit dem
Vektor IEEE Std 802.11-2012 M.6.4 -- und mit Osum.

### Eine Wache, die berichtigt werden musste

Der geerbte Abschnitt 42 wurde auf `merge6` beim ersten Lauf **rot**:

    FAIL  irgendwo steht eine WLAN-PCI-Nummer

Die Meldung stimmte, der Schluss daraus nicht. In `kernel/netdev.fi`
stehen seit Runde BLECH drei Zeilen `tab_line(0x8086, 0x2723, 0x00)`
und in `kernel/chipname.fi` die Namen dazu. Das ist **kein Treiber** --
es ist Punkt 1 der Fortsetzungsliste aus `WLAN-BEFUND.md` Abschnitt 8,
den eine andere Runde inzwischen erledigt hat. Die dritte Spalte von
`tab_line` ist der Treiber, und sie ist `0x00`.

Die Wache prueft jetzt, dass keine WLAN-Nummer an einen **Treiber
gebunden** ist -- plus die Gegenprobe, dass die Namen ueberhaupt noch
dastehen. Sonst wuerde sie gruen, indem der Fortschritt verschwindet.

---

## 5. WAS NUR AUF ECHTEM BLECH PRUEFBAR IST

Unveraendert die ehrlichste Liste dieser Runde. Nichts davon ist hier
gemessen, und nichts davon kann hier gemessen werden.

| # | Was | warum nicht hier |
|---:|---|---|
| 1 | Dass ein Stick ueberhaupt erkannt wird | QEMU hat kein USB-WLAN-Geraet; in QEMU meldet `usb: skipped` |
| 2 | Die **Zeile** `wifi-usb: ... kein Treiber` auf dem Schirm | dito -- sie erscheint nur, wenn wirklich ein Stick steckt |
| 3 | Ob die VID/PID in der Tabelle die **richtige** ist | die Nummern sind aus Linux uebernommen, nicht an einem Geraet abgelesen |
| 4 | Firmware in den Chip schieben | braucht den Chip |
| 5 | Bulk-Endpunkte, Ringe, Interrupts | braucht den Chip |
| 6 | Ein Rahmen, der wirklich durch die Luft geht | braucht eine Antenne |
| 7 | Ein Suchlauf, der wirklich ein Netz findet | dito |
| 8 | Die ETSI-Tabelle gegen die geltende Fassung von EN 300 328 | braucht einen Konformitaetsbericht, kein Blech -- aber gemacht ist es nicht |
| 9 | Der Durchsatz | braucht alles davor |

**Was Justin tun kann und was es bringt:** ein Osum-Abbild dieses
Zweiges auf dem Ryzen booten, mit eingestecktem Stick, und die
`wifi-usb:`-Zeile fotografieren. Damit steht die VID/PID fest, und
damit steht fest, welcher **eine** Treiber sich zu bauen lohnt. Ohne
diese Zeile ist jeder Treiber geraten.

Kommt der Stick nicht in der Tabelle vor, sagt die Zeile nichts -- dann
hilft ersatzweise die vorhandene USB-Zeile
`usb: ... id=XXXX:YYYY cls=...`, die es schon vor dieser Runde gab.
Auch die genuegt.

---

## 6. WIE WEIT IST DER WEG JETZT

Dieselbe Tabelle wie in `WLAN-BEFUND.md` Abschnitt 7, mit den Etappen
auf USB umgestellt und dem neuen Stand. Die Anteile sind Schaetzungen
und als solche gekennzeichnet; die Staende sind Messungen.

| Etappe | Anteil | Stand |
|---|---:|---|
| 802.11-Rahmen verstehen und sicher zerlegen | 8 % | **fertig, gemessen** |
| Kanaele und Regulatorik | 3 % | **fertig, gemessen** |
| Krypto darunter | 10 % | **fertig, gegen Normvektoren gemessen** |
| 4-Wege-Handschlag als Automat | 9 % | **fertig -- jetzt auch gegen ein ZWEITES Programm** |
| CCMP | 5 % | **fertig, gegen Normvektor UND Gegenstelle** |
| Der Weg als Vorgang (Suchlauf→Wahl→Handschlag→Schluessel→Daten) | 4 % | **fertig, ueber der Naht gemessen** |
| Die Naht zum Geraet | 2 % | **fertig, gemessen** |
| Den Stick BENENNEN | 1 % | **fertig** |
| SAE (WPA3-Anmeldung) | 5 % | offen, ohne Vektoren nicht sinnvoll pruefbar |
| 802.11w (BIP/IGTK) | 3 % | offen |
| **USB-Treiber: Endpunkte, Firmware, Ringe, Kommandos** | **35 %** | **offen, braucht den Stick** |
| **Regulatorik gegen das, was die Firmware zulaesst** | **5 %** | **offen, braucht den Stick** |
| Einbau in `netdev.fi`, Profile, Oberflaeche | 5 % | offen |
| Durchsatz, Roaming, Stromsparen | 5 % | offen, braucht den Stick |

**Fertig: ungefaehr 42 %.** Und derselbe Satz wie beim letzten Mal,
damit die Zahl nicht falsch gelesen wird:

> Von dem Rest liegen **rund 45 Prozentpunkte** hinter einem Stueck
> Blech, das hier nicht steckt. Der Anteil, der ohne Hardware
> erreichbar ist, ist mit dieser Runde bis auf SAE und 802.11w
> ausgeschoepft.

---

## 7. WAS AN DIESER RUNDE SCHIEFGEHEN KANN, obwohl alles gruen ist

* **T1 -- Die Gegenstelle ist von derselben Person geschrieben wie der
  Rest.** Sie benutzt eine andere Bibliothek und einen anderen
  Normtext, aber sie teilt einen Kopf. Ein *Missverstaendnis* der Norm
  -- nicht ein Tippfehler, sondern ein falsch verstandener Satz --
  koennte in beiden stecken. Dagegen hilft nur die Eichung an der
  echten Aufzeichnung (Abschnitt 1.2), und die deckt genau einen
  Handschlag ab: WPA2-PSK mit HMAC-SHA1. **Die SHA-256-AKM ist gegen
  keinen echten Draht geeicht**, nur gegen zwei Programme.
* **T2 -- Die USB-Nummern sind abgeschrieben, nicht abgelesen.** Wenn
  in Justins Stick ein Chip sitzt, dessen Nummer hier fehlt oder falsch
  zugeordnet ist, sagt die Zeile den falschen Namen. Deshalb steht in
  Abschnitt 5 ausdruecklich, dass auch die rohe `usb:`-Zeile genuegt.
* **T3 -- Die Naht ist an genau einer Umsetzung gemessen**
  (`pruefgeraet.fi`), und die ist ein Puffer. Ob sie einen echten
  USB-Treiber traegt -- Bulk-Endpunkte, Warteschlangen, Interrupts,
  Rahmen, die in Stuecken ankommen --, ist eine **Behauptung**, bis der
  erste Treiber daran haengt. Die vier Aufrufe sind aus dem
  hergeleitet, was `zustand.fi` braucht, nicht aus dem, was ein
  USB-Chip liefert.
* **T4 -- `verbinden.fi` ist gegen keinen boesartigen Verlauf
  gemessen.** Der Handschlag ist es (Abschnitt 1.3), der Automat
  darunter ist es erschoepfend (Runde WLAN: 30.940 Folgen), aber der
  Draht dazwischen -- die Datei, die beides verbindet -- hat nur den
  glaeubigen Weg gesehen.
* **T5 -- Unveraendert S1 und S3 aus `WLAN-BEFUND.md`:** die
  802.11-spezifische CCMP-Konstruktion haengt an einem einzigen
  veroeffentlichten Vektor (jetzt immerhin gegen ein zweites Programm
  nachgerechnet), und die ETSI-Tabelle ist aus Normtexten
  abgeschrieben, nicht aus einem Konformitaetsbericht. **Ein Rechner,
  der auf einem verbotenen Kanal sendet, ist ein Rechtsproblem und
  kein Fehler.** Solange kein Treiber existiert, sendet nichts.

---

## 8. FORTSETZUNGSLISTE

Aufsteigend nach Aufwand. „Stick?" sagt, ob der Punkt den Stick
braucht.

| # | Was | Aufwand | Stick? |
|---:|---|---|---|
| 1 | Die `wifi-usb:`-Zeile am echten Blech ablesen und die VID/PID festhalten | ein Foto | **JA** |
| 2 | `verbinden.fi` gegen boesartige Verlaeufe messen (T4) | ~200 Zeilen | nein |
| 3 | 802.11w (BIP-CMAC-128, IGTK) erkennen UND umsetzen | ~350 Zeilen | nein |
| 4 | Ein Ring-3-Programm `wlan` (suchen, verbinden, Zustand) plus Kachel, ueber `wlib` | ~700 Zeilen | nein |
| 5 | SAE (WPA3): P-256 auf `big.fi`, hunting-and-pecking | ~900 Zeilen | nein -- aber ohne Vektoren nicht sinnvoll pruefbar |
| 6 | **USB-Treiber fuer GENAU DEN Chip aus Punkt 1**: Endpunkte, Firmware ueber Bulk, Register, Kommandos, Ringe | **~3.000-5.000 Zeilen** | **JA** |
| 7 | Regulatorik gegen das, was die Firmware zulaesst | ~400 Zeilen | **JA** |
| 8 | Einbau in `netdev.fi`/`netprof.fi`, Profilverwaltung | ~400 Zeilen | teilweise |
| 9 | Durchsatz, Roaming, Stromsparen, 802.11ac-Raten | offen | **JA** |

**Der naechste Schritt ist Punkt 1 und er kostet ein Foto.** Alles
danach haengt daran. Wuerde man vorher einen Treiber waehlen muessen,
waere die Wahl die **RTL8812AU/8821CU-Familie** -- Realtek ist bei
billigen Sticks mit Abstand am haeufigsten --, aber „am haeufigsten"
ist eine Wahrscheinlichkeit und keine Messung, und ein Treiber fuer den
falschen Chip ist nutzlos.

---

## 9. DIE DATEIEN DIESER RUNDE

| Datei | Zeilen | was |
|---|---:|---|
| `lib/wlan/geraet.fi` | 281 | die Naht: vier Aufrufe, die ein 802.11-Geraet koennen muss |
| `lib/wlan/pruefgeraet.fi` | 234 | ein Geraet, dessen Luft zwei Puffer sind. **Kein Treiber, keine Emulation** |
| `lib/wlan/verbinden.fi` | 458 | der ganze Weg als Vorgang, ueber der Naht |
| `lib/wlan/usbchip.fi` | 368 | 40 USB-Nummern auf Familie und Klarnamen |
| `tools/wlan/gegenstelle.py` | 655 | ein **unabhaengiger** WPA2-Authenticator, an der echten Aufzeichnung geeicht |
| `tools/wlan/handschlag.py` | 337 | Osums Supplicant gegen die Gegenstelle, glaeubig und boese |
| `tools/wlan/run2.sh` | 220 | Abschnitt 43 der Abnahme |
| `kernel/usb.fi` | +43 | die Zeile, die den Stick benennt |

Alles Neue unter `lib/` haelt die Regel des `lib/`-Baums: keine
`profile`-Zeile, kein `import` ausser auf `lib/`, kein Allokator, kein
Systemaufruf, aller Zustand beim Aufrufer. Nur deshalb kann
`tools/wlan/orakel.fi` denselben Quelltext auf dem Wirt messen, den der
Kern bindet.
