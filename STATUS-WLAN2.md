# STATUS — RUNDE WLAN-2

**06.09.2026. Zweig `wlan2`, Arbeitsbaum `/root/osum-wlan2`, 10 Commits
auf `merge6` (a92fa00). Nicht gepusht, nicht gemergt.**

Die ausfuehrliche Fassung mit Begruendungen steht in `docs/WLAN.md`.
Hier stehen die Zahlen.

---

## DAS ERGEBNIS IN EINEM SATZ

**Osum verbindet sich nicht mit einem WLAN — es gibt keinen Treiber, und
auf diesem Rechner kann es keinen geben.** Was diese Runde gebracht
hat: der Protokollstapel ist gegen ein **zweites, unabhaengiges
Programm** gemessen statt nur gegen sich selbst, es gibt eine **Naht**,
an der ein Treiber andocken wird, und ein Rechner mit einem
USB-WLAN-Stick **sagt jetzt, welcher Chip darin steckt**.

---

## MESSWERTE

| | |
|---|---:|
| Abschnitt 42 (geerbt, Runde WLAN) | **185 Zusagen, 0 Fehler** |
| Abschnitt 43 (neu, `tools/wlan/run2.sh`) | **43 Zusagen, 0 Fehler** |
| Kernabbild | 4.190.956 Oktette, baut |
| Bootlauf in QEMU | Abbruchwert **21** (sauber), 153 Zeilen, `kernel: done` |

Im Einzelnen, Abschnitt 43:

| Was | Zahl |
|---|---:|
| Die Gegenstelle gegen die echte Aufzeichnung von 2007 geeicht | 5 |
| Vollstaendige 4-Wege-Handschlaege, **jedes Mal neue Zufallszahlen** | **40** |
| davon einig ueber PMK, PTK, alle vier Pruefwerte, GTK und dessen Nummer | alle 40 |
| CCMP in **beide** Richtungen je Lauf | alle 40 |
| Boesartige Faelle im Handschlag, die Osum ablehnt | 5 |
| Boesartige Faelle im ganzen Weg (`weg.py`), in denen **null** Schluessel ins Geraet gehen | 6 |
| USB-Nummern mit richtiger Familie **und** Klarnamen | 15 von 40 geprueft |
| Zusagen aus einem **echten Lauf** von `/bin/wlan` in Osum | 8 |
| Neue Zeilen in `lib/wlan/` und `kernel/user/wlan.fi` | 1.748 |

---

## WAS NEU IST

| Datei | Zeilen | was |
|---|---:|---|
| `tools/wlan/gegenstelle.py` | 655 | ein **unabhaengiger** WPA2-Authenticator, an der echten Aufzeichnung geeicht |
| `tools/wlan/handschlag.py` | 337 | Osums Supplicant gegen die Gegenstelle, glaeubig und boese |
| `tools/wlan/weg.py` | 223 | der ganze Weg, und was passiert, wenn jemand luegt |
| `tools/wlan/prog.sh` | 117 | baut ein Abbild mit `/bin/wlan` und ruft es in Osum auf |
| `tools/wlan/run2.sh` | 240 | Abschnitt 43 der Abnahme |
| `lib/wlan/device.fi` | 281 | die **Naht**: vier Aufrufe, die ein 802.11-Geraet koennen muss |
| `lib/wlan/testdevice.fi` | 234 | ein Geraet, dessen Luft zwei Puffer sind. **Kein Treiber** |
| `lib/wlan/connect.fi` | 458 | der ganze Weg als Vorgang, ueber der Naht |
| `lib/wlan/usbchip.fi` | 368 | 40 USB-Nummern auf Familie und Klarnamen |
| `kernel/user/wlan.fi` | 348 | `/bin/wlan` |
| `kernel/usb.fi` | +43 | die Zeile, die den Stick benennt |

---

## DIE DREI DINGE, DIE ZAEHLEN

### 1. S2 und S4 aus `WLAN-BEFUND.md` sind geschlossen

Runde WLAN hatte selbst aufgeschrieben, dass ihr Handschlag **nur gegen
sich selbst** gemessen war. Dagegen ist Selbstvergleich blind: zweimal
dieselbe falsche Annahme gibt zweimal dasselbe falsche Ergebnis.

`tools/wlan/gegenstelle.py` ist ein vollstaendiger WPA2-Authenticator,
der mit Osum **keine Zeile teilt**, OpenSSL statt `lib/crypto/` benutzt
und **bei jedem Lauf neue Zufallszahlen** wuerfelt. Vorher eicht er sich
an der echten Aufzeichnung von 2007 (`Coherer`/`Induction`) — erst wenn
seine Rechnung oktettgleich mit dem echten Draht stimmt, darf er Osum
pruefen.

Und weil er selbst geschrieben ist, kann er **absichtlich falsch
spielen** — das kann ein echter Zugangspunkt nicht, und dort liegen die
interessanten Fehler.

### 2. Die Naht traegt USB *und* PCIe

`lib/wlan/device.fi` sagt vier Dinge zu: senden, empfangen, Kanal
setzen, Schluessel setzen. Sonst nichts. Sie war nie ein PCI-Ding —
**deshalb hat Justins Zwischenruf mitten in der Runde (USB-Stick statt
PCIe-Karte) keinen Umbau erzwungen.**

### 3. Die Zeile, die Justin fotografieren soll

    wifi-usb: Realtek RTL8812AU (0bda:8812), kein Treiber

Ein Rechner, der schweigt, ist kaputt. Einer, der sagt, was ihm fehlt,
ist einer, an dem man weiterarbeiten kann.

---

## WAS DIE RUNDE AN FEHLERN GEFUNDEN HAT

**Sieben, und sechs davon lagen im neuen Pruefer, nicht in Osum.** Das
ist die eigentliche Nachricht: der neue Massstab hat sich an Osum
geeicht und nicht umgekehrt.

Im neuen Python:
1. AKM 3 als SHA-256 angenommen (richtig sind 5, 6, 8, 9, 18).
2. Die Antwort von `gtk` hat zwei Felder, nicht eins.
3. In der CCMP-AAD stehen **drei** Adressen (18 Oktette), nicht zwei.
4. Die Paketnummer steht in der Nonce hoechstwertig zuerst und wird
   **nicht** gedreht — gedreht wird nur im CCMP-Kopf.
5. Das erste Oktett des EAPOL-Rumpfes ist die Beschreibungsart (**2** =
   RSN), nicht die 3, die daneben im Kopf fuer „EAPOL-Key" steht.

In Osum-Quelltext, gefunden von `weg.py`:

6. **`verbinden.fi` fuetterte den Automaten nach der Netzwahl nicht mit
   Authentifizierung und Assoziation.** Der glaeubige Weg endete
   deshalb mit **zwei Schluesseln im Geraet**, waehrend `darf_daten`
   falsch blieb — genau die halbe Verbindung, gegen die `zustand.fi`
   gebaut ist. Der Automat hat sie gemeldet, wie vorgesehen.

Und einer in der eigenen Ausgabe:

7. **`/bin/wlan` meldete „PMK vorab gerechnet (PBKDF2-SHA1, 4096
   Runden)" und rechnete nichts dergleichen.** Der Satz ist heraus.
   Eine Meldung ueber eine Rechnung, die nicht stattfindet, ist genau
   die Sorte Behauptung, gegen die diese Runde geschrieben ist — und
   sie waere fast durchgegangen, weil sie plausibel klang.

---

## WARUM NICHT GEGEN hostapd — gemessen, nicht gemeint

| Weg | Ergebnis |
|---|---|
| `hostapd` 2.10 aus Debian | installiert, laeuft |
| `hostapd_cli EAPOL_RX` / `MGMT_RX_PROCESS` / `DATA_TEST_CONFIG` | **`Unknown command`** — Debian baut ohne `CONFIG_TESTING_OPTIONS` |
| `hostapd driver=none` | bis `AP-ENABLED`, aber **kein Rahmen geht hinein** |
| `hostapd driver=wired` auf veth | **empfaengt** echte EAPOL-Rahmen, verarbeitet sie nicht: `IEEE 802.1X: Ignore STA` |
| `wpa_supplicant -D wired` | `WPA: drop TX EAPOL in non-IEEE 802.1X mode` |
| `modprobe mac80211_hwsim` | **`Module not found`** — dieser Kern hat kein `drivers/net/wireless/` |
| `/dev/net/tun` | fehlt (dieselbe Wand wie Runde K8) |

Ein hostapd ohne Testschalter und ohne Funkgeraet ist kein
Handschlagpartner.

---

## WAS NUR AUF ECHTEM BLECH PRUEFBAR IST

1. Dass ein Stick ueberhaupt erkannt wird (in QEMU: `usb: skipped`).
2. Die Zeile `wifi-usb: … kein Treiber` auf dem Schirm.
3. Ob die VID/PID in der Tabelle die **richtige** ist — die Nummern
   sind aus Linux uebernommen, nicht an einem Geraet abgelesen.
4. Firmware in den Chip schieben.
5. Bulk-Endpunkte, Ringe, Interrupts.
6. Ein Rahmen, der wirklich durch die Luft geht.
7. Ein Suchlauf, der wirklich ein Netz findet.
8. Der Durchsatz.

Dazu, ohne Blech, aber ungemacht: die ETSI-Tabelle gegen die geltende
Fassung von EN 300 328.

---

## DER NAECHSTE SCHRITT — UND ER KOSTET EIN FOTO

**Justin bootet ein Osum-Abbild dieses Zweiges auf dem Ryzen, mit
eingestecktem Stick, und fotografiert die `wifi-usb:`-Zeile.**

Steht der Stick nicht in der Tabelle, genuegt die rohe Zeile
`usb: … id=XXXX:YYYY cls=…`, die es schon vorher gab. Alternativ
`wlan chips` im laufenden System und der Aufdruck des Sticks.

Erst danach steht fest, welcher **eine** Treiber sich lohnt
(~3.000–5.000 Zeilen). Muesste man vorher raten, waere es
RTL8812AU/8821CU — aber „am haeufigsten" ist eine Wahrscheinlichkeit
und keine Messung, und ein Treiber fuer den falschen Chip ist nutzlos.

**Stand insgesamt: ~42 % des Weges zu „verbindet sich mit dem
heimischen WLAN". Rund 45 Prozentpunkte davon liegen hinter Hardware,
die hier nicht steckt.**
