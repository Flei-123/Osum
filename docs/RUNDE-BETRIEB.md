# RUNDE BETRIEB — Namensauflösung, Schlüsselverwaltung, Serverseite

**Zweig:** `betrieb`, Arbeitsbaum `/root/osum-betrieb`, abgezweigt von `ota`
(`c160d79`) · **Wirt:** AMD EPYC 7571, 12 Kerne, Linux x86-64, KVM ·
**Firn:** `a751b3db` (festgenagelt in `vendor/firn/COMMIT`) ·
**Ein Lauf:** `bash tools/betrieb/vorbereiten.sh $OUT` und danach
`bash tools/betrieb/run.sh`

Diese Runde macht die Punkte **2, 3 und 4** der Liste „WAS NOCH FEHLT —
für den Betrieb gegen einen echten Server" am Ende von `docs/OTA.md`.
Punkt 1 (AVX-512) ist eine eigene, parallel laufende Runde und wird hier
nicht angefasst.

---

## 0. Die drei wichtigsten Ergebnisse

*(werden am Ende dieses Dokuments mit Zahlen wiederholt)*

1. **`ota` holt ein Update über einen NAMEN, Ende zu Ende.** In
   `/etc/ota.conf` steht seit dieser Runde `quelle=https://pkg.betrieb.test:…`
   statt einer IPv4-Adresse; `/bin/fetch` löst den Namen selbst auf und
   prüft das Zertifikat **gegen denselben Namen**. Der Auflöser ist gegen
   `dig` gemessen und gegen einen Fälscher gehärtet, der falsche Antworten
   vor die richtige schiebt.
2. **Ein kompromittierter Schlüssel ist kein Totalverlust mehr.** Es gibt
   einen zweiten vertrauten Schlüssel im Abbild, einen geordneten
   Schlüsselwechsel als signierte Kette (ein Gerät, das zwei Wechsel
   verpasst hat, holt sie in einem Zug nach) und eine Sperrliste, die das
   Gerät sich **merkt** — sonst fängt sie nur, was der Rückschrittsschutz
   ohnehin fängt.
3. **Der Prüfstand ist eine Veröffentlichungskette geworden.** Ein Befehl
   macht aus einem Stand eine signierte Auslieferung, die Fassungsnummer
   wird in einem Register geführt, das nie zurückgeht, jede je
   veröffentlichte Fassung bleibt abrufbar, und der geheime Schlüssel
   liegt nicht mehr offen auf der Baumaschine.

---

## 1. Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `lib/libc/dnswire.fi` | 448 | DNS (RFC 1035) als reine Oktettarbeit — **kein Systemaufruf**, deshalb ohne ein Paket prüfbar |
| `lib/libc/dns.fi` | 456 | die Steckdose: `/etc/resolv.conf`, gewürfelter Quellport, Kennung, 0x20, Frist mit Wiederholung, mehrere Server |
| `kernel/user/host.fi` | 331 | `/bin/host` — das Messgerät gegen `dig` |
| `kernel/user/dnswt.fi` | 393 | 19 von Hand gebaute, feindliche Nachrichten |
| `tools/ota/schluesselbund.py` | 294 | der geheime Schlüssel: verschlüsselt, und das Signieren getrennt vom Bauen |
| `tools/ota/veroeffentlichen.py` | 407 | Register, Vorrat, Archiv, Sperrliste, Kettensätze |
| `tools/betrieb/dnsdienst.py` | 244 | Nameserver **und Fälscher** |
| `tools/betrieb/dnsvergleich.py` | 176 | `/bin/host` gegen `dig`, 20 Namen |
| `tools/betrieb/run.sh` | 421 | der Läufer |
| `tools/betrieb/vorbereiten.sh` | 104 | Pakete, Zertifikate, Bund, vier Auslieferungen, Abbild, Platte |
| `tools/betrieb/crt-wirt.s` | 74 | zwei Zeilen Unterschied: dasselbe Programm auf dem Wirt |
| `tools/betrieb/wirt.sh` · `masse.py` | 20 · 66 | Bauhelfer |

Geändert:

| Datei | was |
|---|---|
| `kernel/user/dhcp.fi` | Option 6 wird gelesen; `/etc/resolv.conf` wird geschrieben; `fallback`-Zeilen bleiben stehen; `dns1..3` in `/etc/network.conf` |
| `kernel/app/fetch.fi` | ein **Name** in der URL wird aufgelöst und ist zugleich der Name fürs Zertifikat |
| `kernel/user/ota.fi` | OTA2, Schlüsselkette, Ersatzschlüssel, Sperrliste (gemerkt), `name=` freiwillig |
| `kernel/user/opk.fi` | der Ersatzschlüssel gilt auch für Paket- und INDEX-Signaturen |
| `tools/install/build.sh` | `/system/ersatz.pub`, `/system/SCHLUESSELGEN`, `dhcp` und `host` im Abbild, Apps bauen mit `FIRNLIB=<repo>/lib` |
| `tools/ota/verzeichnis.py` | erzeugt OTA2 |
| `tools/ota/server.py` | liefert auch Unterpfade aus (`v/2/VERZEICHNIS`) |

**Berührte Dateien, vollständig** (die Runden MERGE-3 und AVX arbeiten
parallel): `lib/libc/dns.fi`, `lib/libc/dnswire.fi` (beide neu),
`kernel/user/host.fi`, `kernel/user/dnswt.fi` (neu),
`kernel/user/dhcp.fi`, `kernel/user/ota.fi`, `kernel/user/opk.fi`,
`kernel/app/fetch.fi`, `tools/install/build.sh`, `tools/ota/server.py`,
`tools/ota/verzeichnis.py`, `tools/ota/schluesselbund.py` (neu),
`tools/ota/veroeffentlichen.py` (neu), alles unter `tools/betrieb/`
(neu), `docs/RUNDE-BETRIEB.md` (neu). **`kernel/sched.fi`,
`kernel/cpu.fi` und `kernel/kmain.fi` sind NICHT angefasst.**

---

## 2. Die Messstrecke: derselbe Auflöser in zwei Ladern

Ein Programm unter `kernel/user/` ist ein gewöhnliches statisches ELF,
und Osums Systemaufrufe tragen **Linux' Nummern** (Runde K4). Deshalb
läuft `/bin/host` nicht nur auf Osum, sondern auch direkt auf dem Wirt —
mit **derselben Binärdatei aus demselben Quelltext**, übersetzt vom
selben `firnc`. Der einzige Unterschied sind zwei Zeilen Startcode
(`tools/betrieb/crt-wirt.s`): Osums Lader übergibt den Argumentblock in
`rdi`, Linux legt ihn auf den Stapel.

Das ist kein Trick, sondern das, was die Messung dieser Runde erst
bezahlbar macht: **zwanzig echte Namen bei einem echten Nameserver gegen
`dig` zu halten kostet Sekunden statt zwanzig QEMU-Starts.** Und danach
läuft dieselbe Datei in QEMU auf Osum und beweist, dass es dort auch
geht.

---

## 3. TEIL 1 — die Namensauflösung

### 3.1 Was vorher da war, gemessen und nicht geglaubt

`docs/OTA.md` schätzte „~50 Zeilen" und nannte drei Bausteine, die schon
dastünden. Zwei davon stimmten nicht:

| Behauptung | Befund |
|---|---|
| „`vendor/firn/lib/net/dns.fi` ist im festgenagelten Vorrat" | **Stimmt** — aber er spricht **TCP** auf Port 53 (er sagt es in seinem eigenen Kopf), kennt nur A-Sätze, hat keinen Zwischenspeicher und keine Härtung gegen Fälschungen. Für einen Browser reicht das; als Vertrauensanker eines Update-Weges nicht. Und er ist `--profile=app`, also für `/bin/ota` (`profile kernel`) unbenutzbar. |
| „`dhcp.fi` kennt den Nameserver bereits" | **Stimmt nicht.** `kernel/user/dhcp.fi` liest die Optionen 1, 3, 51, 53 und 54 — **Option 6 wurde übersprungen**. `grep -n 'dns' kernel/user/dhcp.fi` auf dem Ausgangsstand: null Treffer. |
| „`/etc/resolv.conf` schreibt niemand" | Stimmt. |

Deshalb ist es kein 50-Zeilen-Nachtrag geworden, sondern ein eigener
Auflöser — **904 Zeilen in zwei Dateien**, davon 448 ohne einen einzigen
Systemaufruf.

### 3.2 Warum das Format von der Steckdose getrennt ist

`lib/libc/dnswire.fi` enthält **keinen Systemaufruf**. Deshalb lässt sich
jede Falle, an der selbstgebaute Auflöser sterben, prüfen, **ohne ein
Paket zu schicken**: die Nachricht wird in `kernel/user/dnswt.fi` von
Hand gebaut und dem Zerteiler hingelegt.

Und derselbe Umstand löst ein zweites Problem: die Datei übersetzt
**unter beiden Bauarten** — `profile kernel` für `/bin/ota` und
`--profile=app` für `/bin/fetch`. Es gibt **eine** Umsetzung, nicht zwei,
die auseinanderlaufen. Dafür baut `tools/install/build.sh` die
`kernel/app/`-Programme seit dieser Runde mit `FIRNLIB=<repo>/lib`;
`std.*` und `tls.*` findet der Übersetzer weiterhin über
`<Verzeichnis des Übersetzers>/../lib`.

**Ein Befund am Rande, der Zeit gekostet hat:** `import libc.net` in
`lib/libc/dns.fi` bekam unter `--profile=app` Firns `std.net`
untergeschoben (`'AF_INET' is not exported by module 'net'`) — der
Übersetzer führt Modulnamen **je Übersetzung**, nicht je Datei. Statt in
einem der beiden Bäume umzubenennen, stehen die sechs Aufrufe, die der
Auflöser wirklich braucht (Steckdose, `bind`, `sendto`, `recvfrom`,
`close`, `sockaddr_in`), jetzt in `dns.fi` selbst.

### 3.3 Die drei Schranken bei der Namenskompression

Ein Name in einer DNS-Antwort darf sagen „der Rest von mir steht an
Stelle N". N darf rückwärts, vorwärts oder auf sich selbst zeigen. Jede
einzelne der folgenden Schranken ist zu wenig:

1. **Strikt rückwärts** (Ziel < Stelle des Zeigers). Damit ist eine
   Schleife unmöglich.
2. **Höchstens 8 Sprünge.** Die Rückwärtsregel allein lässt in einer
   Nachricht von 64 KiB noch eine Kette von 16 000 Einzelschritten zu —
   richtig beantwortet und trotzdem eine Rechenlast, die ein Fremder
   bestimmt.
3. **Der zusammengesetzte Name bleibt unter 255**, jede Marke unter 64.
   Sonst schreibt eine Kette *gültiger* Rückwärtszeiger einen beliebig
   langen Namen in einen Puffer fester Größe.

Dazu: reservierte Markenbits (`0b01`, `0b10`) werden abgelehnt, `rdlength`
wird gegen das Ende der Nachricht geprüft, eine CNAME-Kette ist auf 8
Glieder begrenzt, und ein Satz mit **fremdem Besitzernamen** wird nicht
genommen — das ist der klassische Beipack einer Vergiftung.

### 3.4 Was ein Fälscher erraten muss

| Feld | Bits | woher |
|---|---:|---|
| Kennung (TXID) | 16 | `getrandom` |
| Quellport | ~16 | `getrandom`, **und wirklich gebunden** |
| Schreibweise (0x20) | 1 je Buchstabe | `getrandom` |

**Der Quellport ist hier keine Formsache.** Osums Kern vergibt für eine
UDP-Steckdose, die *nicht* gebunden wurde, den Port
`40000 + (zähler & 4095)` (`kernel/inet.fi`, `sock_sendto`) — ein
**Zähler** über 4096 Werte. Wer den vorigen Port kennt, kennt den
nächsten. Deshalb bindet dieser Auflöser immer selbst; misslingt das
achtmal, bricht er ab, statt still auf den Zähler zurückzufallen.

**Ein Fremdpaket beendet den Versuch nicht.** Es wird gezählt und
weggeworfen, und es wird bis zum Ablauf der Frist weiter gewartet. Sonst
genügte einem Angreifer, *schneller* zu sein als der Nameserver; so muss
er *richtig* raten.

Geprüft wird außerdem, **von wem** das Paket kam: Adresse des Servers,
den wir gefragt haben, und Port 53.

### 3.5 `/etc/resolv.conf` — und keine fest eingebaute Adresse

```
nameserver 192.168.1.1        bis zu vier, in dieser Reihenfolge
options timeout:2 attempts:2
fallback 192.0.2.53           NUR wenn kein nameserver antwortet
```

* `/bin/dhcp` schreibt die `nameserver`-Zeilen aus **DHCP-Option 6** und
  trägt sie zusätzlich als `dns1..dns3` in `/etc/network.conf` ein.
* **`fallback` ist der sichtbare, abschaltbare Rückfall** aus dem
  Auftrag: er steht in einer Datei, die man lesen und löschen kann,
  `/bin/dhcp` **lässt ihn stehen**, wenn es die Datei neu schreibt, und
  ohne die Zeile gibt es ihn nicht. Er wird als **letzter** gefragt, also
  nur, wenn vor ihm niemand geantwortet hat.
* **Im Quelltext des Auflösers steht keine einzige Nameserver-Adresse.**
  Der Läufer zählt nach: `8.8.8.8`, `8.8.4.4`, `1.1.1.1`, `9.9.9.9` —
  je 0 Treffer in `lib/libc/dns.fi`, `lib/libc/dnswire.fi`,
  `kernel/user/host.fi`, `kernel/app/fetch.fi`.
* Eintragung von Hand geht auf zwei Wegen: die Datei schreiben, oder
  `host -s <adresse> <name>` für eine einzelne Frage.

`search`, `domain` und `ndots` werden **gelesen und verworfen**; ein Name
wird gefragt, wie er dasteht. Für eine Update-Quelle ist das richtig (sie
ist ein voller Name), für `ping nachbar` zu wenig — siehe Abschnitt 8.

---

## 4. TEIL 2 — die Schlüsselverwaltung

### 4.1 Das Format: OTA1 wird OTA2

```
OTA2
fassung        <dezimal>
schluesselgen  <dezimal>
kette          <gen>  <64hex neuer pub>  <128hex sig>     (0..n)
gesperrt       <fassung>                                  (0..n)
paket          <name> <fassung> <sha256> <oktette> <datei>
```

**Warum die Kennung mitgeht, obwohl nur Zeilen dazukommen und ein alter
Zerteiler sie überspringen würde: weil er sie überspringen würde.**
`gesperrt` ist eine Sicherheitsaussage; ein Gerät, das sie nicht
versteht, muss ablehnen und nicht einspielen. Aus demselben Grund lehnt
ein Gerät dieser Runde ein **OTA1**-Verzeichnis ab — sonst genügte es,
ihm ein altes, richtig signiertes OTA1-Verzeichnis vorzulegen, um die
Sperrliste loszuwerden.

### 4.2 Der Ersatzschlüssel

`/system/ersatz.pub`, 32 rohe Oktette, ein zweiter vertrauter Schlüssel
im Abbild. Er wird **nur** gefragt, wenn der Hauptschlüssel nein gesagt
hat — beim VERZEICHNIS (`kernel/user/ota.fi`) und beim Paket und beim
INDEX (`kernel/user/opk.fi`). Seine geheime Hälfte liegt ausdrücklich
**nicht** dort, wo gebaut wird, und hat eine **eigene Passphrase**
(`OSUM_ERSATZ_PASS`), damit die Trennung nicht nur gemeint, sondern
gebaut ist. Fehlt die Datei, verhält sich das Gerät genau wie vor dieser
Runde.

### 4.3 Der Schlüsselwechsel als geordneter Vorgang

Ein Kettensatz beglaubigt genau einen Wechsel:

```
kette <gen> <64hex neuer öffentlicher Schlüssel> <128hex sig>
```

Signiert wird die ASCII-Nachricht

```
osum-schluessel<TAB><gen><TAB><64hex>
```

mit dem geheimen Schlüssel der Generation `gen-1` **oder** mit dem
Ersatzschlüssel.

**Die Nachricht fängt mit einem eigenen Wort an**, und das ist kein
Schmuck: ohne diese Trennung könnte eine Wechselsignatur als Signatur
über ein VERZEICHNIS durchgehen und umgekehrt — derselbe Schlüssel,
dieselbe Rechnung, und nur der Inhalt hätte unterschieden.

Der Ablauf auf dem Gerät:

1. Hauptschlüssel, Generation (`/system/SCHLUESSELGEN`, neun Oktett
   fester Breite) und Ersatzschlüssel lesen.
2. VERZEICHNIS und Signatur holen.
3. **Die Kette gehen** — vom eigenen Stand aufwärts, jeden Satz mit dem
   Schlüssel, den der vorige gerade beglaubigt hat. Das geschieht, **bevor**
   die Signatur über das Verzeichnis geprüft ist, und das ist erlaubt,
   weil jeder Satz seine **eigene** Signatur mitbringt. Nichts anderes im
   Verzeichnis wird vorher angesehen.
4. Signatur über das VERZEICHNIS mit dem so gewonnenen Schlüssel; wenn
   das nichts wird, mit dem Ersatzschlüssel.
5. Kennung prüfen.
6. Sperrliste übernehmen, dann den Wechsel auf die Platte schreiben.

**Warum Schritt 6 und nicht Schritt 3:** ein Wechsel, dessen Verzeichnis
danach durchfällt, setzte das Gerät auf einen Schlüssel, von dem es nie
eine gültige Auslieferung gesehen hat. Zuerst muss die neue Generation
**einmal etwas Ganzes** unterschrieben haben. Umgekehrt wird der Wechsel
geschrieben, **auch wenn das Update danach abgelehnt wird** (gesperrte
Fassung, Rückschritt, kein Platz) — ein Schlüsselwechsel ist ein eigener
Vorgang.

### 4.4 Was passiert, wenn ein Gerät den Wechsel verpasst

**Die Frage aus dem Auftrag, in voller Länge beantwortet.**

Jedes VERZEICHNIS trägt die **ganze** Kette, nicht nur den letzten Satz.
Ein Gerät bei Generation 0 sieht also auch die Sätze für 1 **und** 2 und
geht sie der Reihe nach durch: Satz 1 mit dem Schlüssel gen 0, Satz 2 mit
dem Schlüssel gen 1. Danach steht es bei gen 2 und prüft das Verzeichnis
mit dem Schlüssel gen 2. **Ein Gerät, das zwei Wechsel verpasst hat, holt
sie in einem Zug nach** — gemessen, Gegenprobe 7.

Vier Fälle, und alle vier sind bedacht:

| Lage | was geschieht |
|---|---|
| Gerät bei gen *n*, Quelle bei gen *n* | keine Kettenzeile für *n+1*, nichts passiert |
| Gerät bei gen *n*, Quelle bei gen *n+k* | *k* Sätze werden nacheinander gerechnet, das Gerät steht danach bei *n+k* |
| ein Satz fehlt oder ist falsch | die Kette bricht **an dieser Stelle**, das Verzeichnis fällt durch, und es kommt eine **eigene Meldung**: `ota: SCHLUESSELWECHSEL: die Kette ist UNTERBROCHEN`. Das ist ausdrücklich nicht dasselbe wie „kein Wechsel", und die Generation auf der Platte bleibt stehen |
| die Kette ist endgültig verloren | der **Ersatzschlüssel** darf einen Kettensatz signieren. Damit ist der Weg zurück offen, ohne dass ein Gerät ein Ziegelstein wird — und mit der Kehrseite, die hier auch stehen soll: **wer den Ersatzschlüssel hat, kann den Hauptschlüssel nach Belieben wechseln.** Genau dafür ist er da, und genau deshalb gehört er offline |

### 4.5 Die Sperrliste — und warum das Gerät sie sich merken muss

Der Rückschrittsschutz fängt alles, was **älter** ist als die laufende
Fassung. Was er nicht fängt: eine zurückgezogene Fassung, die **neuer**
ist. Gerät bei 4, Fassung 5 zurückgezogen, Fassung 6 die richtige — wer
die (richtig signierte!) Auslieferung 5 aufgehoben hat und sie dem Gerät
vorlegt, kommt an jeder Signaturprüfung und am Rückschrittsschutz vorbei.

Dagegen hilft nur, dass das Gerät die Liste **behält**. Es sieht sie beim
nächsten `ota suchen` (das mit `ota dienst` stündlich läuft) im
signierten VERZEICHNIS und schreibt sie nach `/system/GESPERRT` — 64
Einträge zu je neun Oktetten, feste Breite wie `/system/FASSUNG`. Von da
an ist Fassung 5 für dieses Gerät tot, gleich wer sie anbietet.

Die Liste **wächst nur**. Ein Eintrag verschwindet nie, denn ein
Verzeichnis, das eine Sperre wegließe, wäre genau der Angriff. Das ist
zugleich ihre Grenze: 64 Einträge, und danach wird nichts mehr dazu
genommen (Abschnitt 8).

`ota suchen` schreibt damit **eine** Sache am System, obwohl es sonst
nichts anfasst. Das ist Absicht: eine Sperre, die erst beim Einspielen
gemerkt wird, kommt zu spät.

### 4.6 Wo der geheime Schlüssel liegt — die Entscheidung

`docs/OTA.md` sagte: „wo er auf Dauer liegen soll — Tresor, HSM,
getrennte Signiermaschine —, hat noch niemand entschieden."

**Entschieden: verschlüsselte Datei mit Passphrase, und der
Signierschritt ist vom Bauschritt getrennt.** Die Begründung, in der
Reihenfolge, in der sie zählt:

1. **Die getrennte Signiermaschine ist das Ziel, aber sie ist eine
   Organisation und kein Programm.** Was ein Programm dafür liefern muss,
   ist eine **Schnittstelle**, hinter der der Schlüssel steckt: „hier sind
   Oktette, gib mir eine Signatur". Genau die ist
   `schluesselbund.py signieren`. `veroeffentlichen.py` ruft sie auf und
   hat den geheimen Schlüssel **nie**; wer das Signieren auf eine andere
   Maschine legen will, kopiert die zu signierenden Dateien hinüber und
   die Signaturen zurück. Am Bau ändert sich dafür keine Zeile.
2. **Ein HSM wäre gelogen.** Auf diesem Wirt steckt kein YubiKey und kein
   TPM-gestützter Schlüssel. Eine Umsetzung, die nur so tut, wäre
   schlechter als keine.
3. **Unverschlüsselt auf der Baumaschine ist das, was heute da war, und
   das ist das eigentliche Problem.** Wer die Baumaschine hat, hat damit
   jedes Gerät. Eine Passphrase ändert das nicht vollständig — wer die
   Maschine *während* eines Baus hat, sieht den Schlüssel im Speicher —,
   aber sie nimmt den häufigsten Fall weg: eine Sicherung, ein Abbild,
   eine weggeworfene Platte.

Gebaut: scrypt (n=2¹⁵, r=8, p=1, 16 Oktett Salz, `hashlib` der
Standardbibliothek) für die Ableitung, ChaCha20-Poly1305 für die Hülle,
der Bund als JSON, damit man ihn sichern kann, ohne ein Werkzeug zu
brauchen. Haupt- und Ersatzschlüssel haben **getrennte Passphrasen**.

**Was für die nächste Stufe fehlt** (ehrlich und kurz, *weil* diese Stufe
die Naht schon an der richtigen Stelle hat):

* ein Gerät, das den Schlüssel nicht herausgibt (PKCS#11/YubiKey).
  `signieren` wäre dann ein Aufruf statt einer Rechnung; alles darüber
  bliebe gleich.
* ein Protokoll, das jede Signatur mit Zeit, Datei und Grund festhält.
  Heute schreibt `veroeffentlichen.py` das nach `journal.txt` — auf
  derselben Maschine.
* Vier-Augen: zwei Passphrasen für eine Auslieferung. Das ist eine
  Änderung an **einer** Datei und keine am Format.

---

## 5. TEIL 3 — die Serverseite

### 5.1 Der Aufbau einer Auslieferung

```
register.json          die geführte Fassungsnummer
journal.txt            eine Zeile je Vorgang
gesperrt.txt           zurückgezogene Fassungen
pakete/<sha256>.opk    DER VORRAT, inhaltsadressiert
pakete/<sha256>.opk.sig
v/<n>/                 die Auslieferung der Fassung n, vollständig
aktuell/               dasselbe wie die höchste NICHT gesperrte v/<n>
```

`v/<n>/` und `aktuell/` enthalten **harte Verknüpfungen** in den Vorrat.
Eine alte Fassung vorzuhalten kostet deshalb einen Verzeichniseintrag und
keine Kopie; ein Paket, das sich zwischen zwei Fassungen nicht geändert
hat, liegt genau **einmal** auf der Platte. Damit ist „alte Fassungen
weiter vorhalten" keine Platzfrage.

### 5.2 Die geführte Fassungsnummer

```json
{"letzte": 7, "vergeben": [1,2,3,4,5,6,7], "zurueckgenommen": [5]}
```

**Die Regel:** die nächste Fassung ist **immer** `letzte + 1`, und
`letzte` wird geschrieben, **bevor** gebaut wird. Damit verbraucht auch
ein Bau, der mittendrin scheitert, seine Nummer, und eine zurückgenommene
Auslieferung gibt ihre **nicht** zurück.

Warum das wichtig ist: auf dem Gerät steht `/system/FASSUNG`, und die
Zahl darf nur steigen. Würde eine Nummer nach einer Rücknahme neu
vergeben, gäbe es zwei verschiedene, beide richtig signierte
Auslieferungen mit derselben Zahl — und ein Gerät, das die erste schon
hat, würde die zweite als Rückschritt ablehnen. Es wäre für immer auf
einer Fassung stehengeblieben, die es nicht behalten sollte, und niemand
sähe, warum.

`--fassung <n>` (zum Nachstellen alter Läufe) wird abgelehnt, wenn `n`
kleiner oder gleich `letzte` ist.

### 5.3 Die Abstimmung mit Certus und dem Orient-Speicher

Angesehen: `/root/certus-sicher/docs/RUNDE-SICHER.md` (Aktualisierungs­kanal,
`lib/sec/update.fi`) und `/root/orientstore/docs/RUNDE-STORE.md`
(signierter Katalog für Android).

**Was übernommen ist — und es ist das Wesentliche:**

| Baustein | Osum OTA2 | Certus / Orient-Speicher |
|---|---|---|
| Signatur | Ed25519 (RFC 8032), kofaktorlose Prüfgleichung, `s ≥ L` abgelehnt | dieselbe, dieselben Vektoren |
| Vertrauensanker | Schlüssel **im Abbild** (`/system/schluessel.pub`) | Schlüssel **in der App** (`Vertrauen.java`) |
| Einstiegspunkt | ein signierter Katalog (VERZEICHNIS), erst prüfen, dann zerteilen | `index.json` + `index.json.sig`, ebenso |
| Rückschrittsschutz | `fassung` monoton, „gleich ist auch nicht neuer" | `revision`/`versionCode` monoton, dreifach |
| Nutzlastprüfung | SHA-256 der **Datei** aus dem signierten Katalog | ebenso |
| Ablage | inhaltsadressiert (`pakete/<sha256>.opk`) | inhaltsadressiert |
| Wiederaufnahme | `Range`/`206` | `Netz.java`, ebenso |

**Was NICHT übernommen ist, und warum.** Der Orient-Speicher trägt seinen
Katalog als **JSON**; OTA2 ist **TAB-getrennter ASCII-Zeilentext**. Das
ist kein drittes Format, sondern dasselbe Modell in einer anderen
Schreibweise, und der Grund ist eine Zahl: `/bin/ota` ist
`profile kernel` — **kein Allokator, keine Halde**, ein Puffer von 8192
Oktett und ein Zerteiler aus `strneq` und `feld()`. Ein JSON-Zerteiler
in dieser Bauart wäre mehrere hundert Zeilen feindlicher Eingang an genau
der Stelle, an der die Kette hängt. Zeilenweiser TAB-Text wird mit vier
Vergleichen zerteilt.

**Was daraus folgt und hier als offener Punkt steht:** wenn der
Orient-Speicher eines Tages OrientOS-Pakete ausliefern soll (er kann es
schon: `art: "opk"`), braucht es **eine** Umsetzung, die aus dem
Katalog-JSON ein OTA2-VERZEICHNIS macht. Das sind ~40 Zeilen Python auf
der **Server**seite — und ausdrücklich nicht ein zweiter Zerteiler auf
dem Gerät. Die Felder decken sich eins zu eins; nur `kette` und
`gesperrt` hat der Speicher noch nicht.

---

## 6. Der Läufer und die Zahlen

*(wird nach dem Lauf eingesetzt)*

---

## 7. Regressionen

*(wird nach dem Lauf eingesetzt)*

---

## 8. Was für echten Dauerbetrieb noch fehlt

Ehrlich und vollständig, ohne Zeitplan.

1. **AVX-512 tötet `/bin/fetch`.** Unverändert Punkt 1 aus `docs/OTA.md`
   und eine eigene Runde. Solange Osum für Ring 3 weder `CR4.OSXSAVE`
   noch `XCR0` freischaltet und der Kontextwechsel keine Vektorregister
   sichert, ist der Update-Weg auf jedem Rechner mit AVX-512 tot.
   **Diese Runde ändert daran nichts** und misst wie die Runde OTA unter
   `-cpu Haswell`.
2. **Kein Zwischenspeicher und keine TTL.** Jeder Aufruf von `fetch` löst
   neu auf; `ota einspielen` mit *n* Paketen fragt *n+1*-mal. Für ein
   Update ist das gleichgültig (Sekundenbruchteile gegen Megaoktette),
   für ein System mit vielen Verbindungen nicht.
3. **Kein `search`, kein `ndots`, kein `/etc/hosts`.** Ein Name wird
   gefragt, wie er dasteht. Für die Update-Quelle richtig, für
   `ping nachbar` zu wenig.
4. **Kein IDNA.** `münchen.de` geht nicht. Punycode liegt in Certus
   (`lib/net/idna.fi`, 847 Zeilen); für Osum ist das eine eigene Runde
   und für einen Update-Weg ohne Wert.
5. **Kein TCP-Rückfall beim TC-Bit.** Eine Antwort, die nicht in ein
   UDP-Paket passt, wird als `TRUNCATED` **gemeldet** und nicht über TCP
   nachgeholt. Für A- und AAAA-Sätze einer Update-Quelle kommt das nicht
   vor; für eine Zone mit vielen Sätzen schon. Der Weg ist bekannt (RFC
   1035 4.2.2, zwei Oktett Länge davor) und der Zerteiler ist derselbe.
6. **Kein DNSSEC, kein DoT, kein DoH.** Die Antwort ist so weit vertraut,
   wie der Nameserver vertraut ist. Was eine gefälschte Antwort wertlos
   macht, ist die **Zertifikatsprüfung** in `fetch` — und die ist die
   eigentliche Verteidigung. Ein untergeschobener DNS-Eintrag bringt
   einen Angreifer nur an eine Verbindung, die an der Kettenprüfung
   scheitert.
7. **Die Sperrliste ist auf 64 Einträge begrenzt.** Danach wird nichts
   mehr dazugenommen — die Datei hat feste Breite, damit sie einen
   Stromausfall überlebt. Für einen Betrieb über Jahre braucht es
   entweder eine Untergrenze („alles unter *n* ist gesperrt", eine Zahl
   statt einer Liste) oder eine mitwachsende Datei mit eigener Prüfsumme.
   **Die Untergrenze ist der bessere Weg** und ist ~30 Zeilen.
8. **Es gibt keine Rücknahme einer Sperre.** Absicht (Abschnitt 4.5),
   aber es heißt auch: eine versehentlich gesperrte Fassung ist auf jedem
   Gerät, das die Liste gesehen hat, endgültig tot. Der Ausweg ist eine
   neue Fassungsnummer, und das ist billig.
9. **Der Fassungsplan fehlt weiter** (Punkt 5 aus `docs/OTA.md`). Das
   Register zählt jede *Auslieferung*; was die Zahl bedeuten soll und wie
   ein Format-Sprung mehrere Fassungen nacheinander erzwingt, ist nicht
   festgelegt. Der Vorrat und `v/<n>/` sind die Voraussetzung dafür und
   stehen jetzt; die Regel fehlt.
10. **Der Kern ist weiter nicht Teil des A/B-Wechsels**, der
    Wurzelzertifikatsspeicher altert weiter, und die Uhr ist weiter die
    CMOS-Uhr. Alle drei unverändert aus `docs/OTA.md`.
11. **Diese Kryptographie ist nicht auditiert.** Unverändert.
12. **Der Schlüsselbund ist eine Datei auf der Baumaschine.** Siehe
    Abschnitt 4.6: die Naht für eine getrennte Signiermaschine ist da,
    die Maschine nicht.
