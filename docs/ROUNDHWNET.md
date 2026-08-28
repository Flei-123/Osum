# Runde HWNET -- eine Netzkarte, die es wirklich gibt, und HTTPS darüber

*28.08.2026 · Zweig `hwnet`, abgezweigt von `mergeline` (e9fcc1c) ·
`main` bleibt unberührt · Bestandsaufnahme:
[REALHW.md](REALHW.md) · offene Punkte:
[ROADMAP-UPDATE.md](ROADMAP-UPDATE.md)*

Jede Zahl in dieser Datei kommt aus einem Lauf auf diesem Rechner. Wo
eine Zahl nicht gemessen wurde, steht sie nicht hier -- und wo etwas
nicht gemessen werden KONNTE, steht das ausdrücklich dabei.

---

## 1. Wofür die Runde da war

Justin will OrientOS auf einem echten Rechner installieren und dort den
JARVIS-Helfer laufen lassen. Zwei Dinge standen dem im Weg, und beide
waren vorher nachgemessen:

1. **Es gab nur virtio-net.** `kernel/` enthielt genau einen
   Netzwerktreiber. Auf einem echten Brett gibt es kein virtio, also kein
   Netz, also keinen Helfer und kein Update.
2. **Es gab kein TLS in Osum.** Ohne TLS kein HTTPS, ohne HTTPS kein
   Paketbezug und keine Verbindung zu JARVIS.

Beides ist nach dieser Runde da. Was danach für echte Hardware immer noch
fehlt, steht vollständig in `docs/REALHW.md`, Klasse für Klasse.

---

## 2. Was gebaut wurde

### `kernel/netdev.fi` -- welcher Treiber, entschieden vom Bus (595 Zeilen)

Vorher rief `kernel/inet.fi` den Treiber **beim Namen**: `virtio.tx_frame`,
zwanzigmal. Insgesamt 67 solche Zeilen in sieben Dateien. Das ist keine
Treiberschnittstelle, das ist eine Treiberadresse.

`netdev.fi` hat dieselbe Form, die die Aufrufer schon benutzten -- jede
Funktion von `virtio.fi` mit demselben Namen und denselben Argumenten --
und darunter eine Tabelle:

    1AF4:1000 / 1041                     virtio-net   kernel/virtio.fi
    8086:100E,100F,1015,1026,1028,10D3   Intel 8254x  kernel/e1000.fi

Eine Karte auf Klasse 02:00, für die es keinen Treiber gibt, wird **mit
ihren Nummern genannt**:

    netdev: no driver for 0x10ec:0x8139

Die Umstellung der Aufrufstellen war mechanisch (ein Wort je Zeile), und
sie ist der Grund, warum DHCP-Klient, `netview`, `netmon` und der Tunnel
unverändert weiterlaufen.

**Eigene Seite im Kernspeicher:** `kstate.NETDEV_OFF = 0x7A000`,
ausdrücklich NICHT in `pci.K2_SCALARS` -- die Seite teilen sich neun
Runden, und Runde NETVIEW hat einen Tag damit verbracht, dass zwei davon
auf denselben acht Oktetten standen. Eingetragen in
`tools/kernel/memmap.py`: 65 Bereiche, 0 Kollisionen.

### `kernel/e1000.fi` -- Intel 8254x/82574 (836 Zeilen)

BAR0 als Speicherbereich, Softwarerücksetzung, Adresse aus RAL/RAH und
ersatzweise aus dem EEPROM, zwei Ringe zu 32 Deskriptoren, 2048-Oktett-
Puffer, INTx über den I/O-APIC (die Familie hat kein MSI-X, und der
Treiber behauptet es nicht). Was er nicht tut -- Prüfsummen- und
Segmentierungsentlastung, Jumbo, Multicast, VLAN, Unterbrechungsdämpfung
-- steht in seinem Kopf, nicht in einer Fußnote.

### `kernel/app/fetch.fi` -- HTTPS aus Ring 3 (655712 Oktett auf der Platte)

Die zweite Bauart eines Ring-3-Programms: `--profile=app`, die volle
Firn-Bibliothek, gebunden mit `kernel/user/user.ld` und **ohne
`crt.s`**. Das geht, weil Osums Systemaufrufe Linux-Nummern tragen und
sein Argumentblock Linux' Form hat. Der ganze TLS-Vorrat der Firn-Runde
B5 lag seit dem festgenagelten Commit im Baum und war nie benutzt worden.

---

## 3. Die Messungen

### 3a. Dieselbe Abnahme auf zwei Chips (`tools/hwnet/run.sh`)

| | virtio-net-pci | e1000 (82540EM) |
|---|---|---|
| Ping, 20 Anfragen | 20 | 20 |
| Umlaufzeit, Mittel | 5,75 ms | 5,15 ms |
| Unterbrechungen | 45 | 43 |
| TCP hinein | 262144 Oktett | 262144 Oktett |
| Rahmen empfangen | 189 | 185 |
| Prüfsummenfehler / Wiederholungen / Verworfene | 0 / 0 / 0 | 0 / 0 / 0 |
| Durchsatz | 5710 KiB/s | 3619 KiB/s |
| DHCP (busybox udhcpd) | Adresse bezogen | Adresse bezogen |
| ohne `nic` | 100 % Verlust | 100 % Verlust |
| `nicnobm` | 100 % Verlust | 100 % Verlust |

Der Durchsatzunterschied ist erklärt und nicht wegerklärt: jede Sendung
schreibt ein Register, jede Platzprüfung liest eines, und ein
MMIO-Zugriff ist unter QEMU/TCG ein Austritt aus der Emulation.

### 3b. HTTPS, und vor allem die Verweigerungen (`tools/hwnet/tls.sh`)

Gegen `openssl s_server` -- eine TLS-Umsetzung, die dieses Projekt nicht
geschrieben hat -- über den e1000 dieser Runde:

| Fall | Antwort | geholt |
|---|---|---|
| gültiges Zertifikat | `verify OK`, Suite 4865, 10 Datensätze | 4005 Oktett |
| abgelaufen | `REFUSED expired` | nichts |
| falscher Name | `REFUSED wrong_name` | nichts |
| unbekannter Aussteller | `REFUSED unknown_issuer` | nichts |
| leerer Speicher | `REFUSED unknown_issuer` | nichts |

Und gegen das echte Netz:

    fetch: verify OK · certs 4 · depth 4 · octets 868 · chunked 1 · body 559
    fetch: bodysha ff67a9d764d6a2367a187734e697f6a53217db9a21c101d410a113ca871a299d
    curl -s https://example.com/ | sha256sum
               ff67a9d764d6a2367a187734e697f6a53217db9a21c101d410a113ca871a299d

**Dieselben Oktette wie curl.** Damit stimmt jede Schicht darunter.

---

## 4. Was dabei gefunden wurde -- die drei Fehler mit Zahlen

1. **QEMU parkt einen Rahmen eine Sekunde lang.** Erreicht ein Rahmen die
   Karte, bevor der Empfangsring existiert, legt QEMU ihn beiseite und
   versucht es nach 1000 ms erneut (`flush_queue_timer` in
   `hw/net/e1000.c`) -- und alles danach wartet mit. Gemessen: die ersten
   zehn Pings kommen gemeinsam nach 935 ms zurück, danach alles in
   0,3 bis 12,9 ms. Eigenschaft von QEMU, nicht des Treibers; eine echte
   Karte wirft solche Rahmen weg.
2. **Eine Kopfzeile, ein Oktett zu kurz.** Die Längenzahl der
   HTTP-Kopfzeilen war 44 statt 45, wodurch der letzte Zeilenumbruch
   fehlte. `openssl s_server -www` verzieh es; Cloudflare wartete auf
   einen Kopfteil, der nie endete, und der Rumpf kam als **0 Oktett**
   zurück. Eine Längenangabe, die um eins danebenliegt, ist in jedem Test
   unsichtbar, der mit etwas Nachsichtigem redet.
3. **Die Stückelung von HTTP/1.1 wurde als Rumpf mitgezählt:** 571 statt
   559 Oktett, und der Streuwert stimmte mit nichts überein. `fetch`
   entstückelt jetzt.

Dazu eine vierte Sache, die kein Fehler dieser Runde ist, aber eine
gemessene Lücke: **der festgenagelte Stapel hat keinen Rundrufweg nach
außen.** `net_output` sucht auch für 255.255.255.255 den nächsten Sprung
per ARP. Mit einem Gateway, das niemand beantwortet, verlässt der
DHCP-Rundruf die Maschine nie -- 0 UDP-Rahmen auf dem Draht,
mitgeschnitten. `kernel/user/dhcp.fi` sagt das seit seiner ersten Zeile;
jetzt gibt es die Zahl dazu.

---

## 5. Was NICHT gemessen wurde

* **Kein einziger echter Chip.** Auf diesem Rechner liegt kein Testbrett.
  Alles über echte Hardware in `docs/REALHW.md` ist aus Datenblättern und
  aus dem Quelltext gelesen.
* **Kein RTL8168/8169.** Der Treiber wurde geprüft und bewusst nicht
  gebaut: QEMU hat nur den RTL8139, und das ist ein anderer Chip (feste
  Sendepuffer, ein einziger Empfangsringpuffer statt Deskriptorringen).
  Ein Treiber für den 8139 würde über den 8168 nichts beweisen. Schätzung
  für den 8168: ~600 Zeilen und **ein Brett zum Messen**.
* **Kein e1000e/I219 und kein I225.** Die Nummern stehen im Kopf von
  `e1000.fi` als das, wofür der Treiber ausdrücklich NICHT gedacht ist,
  samt Begründung (Verwaltungsmaschine und PHY-Handschlag bei den PCH-
  Teilen, anderes Deskriptorformat bei igc).
* **Keine Dauerverbindung.** Ob eine TLS-Verbindung über Stunden trägt
  (Schlüsselerneuerung, NAT-Zeitüberschreitungen), ist nicht gemessen.

---

## 6. Die Abnahme

Der Vergleich Grundlinie/danach steht in Abschnitt 7 dieser Datei und in
`/root/mergerun/HWNET-STATUS.md`. Zwei Abschnitte sind neu:

    28. dieselbe Abnahme auf zwei Chips (tools/hwnet/run.sh)
    29. HTTPS aus Ring 3, und die Verweigerungen (tools/hwnet/tls.sh)
