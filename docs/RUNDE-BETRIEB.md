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

## 0. Der Lauf in einer Zeile

> **`bash tools/betrieb/run.sh` — 95 Zusagen grün, 0 rot.**
> Darin: **19 von 19** feindlichen DNS-Nachrichten abgewehrt (ohne ein
> Paket zu schicken), **21 von 21** echten Namen gleich wie `dig`,
> **24 Köder** eines Fälschers gezählt und verworfen ohne eine falsche
> Antwort, **7 von 7** Gegenproben zur Schlüsselverwaltung bestanden,
> und ein Gerät, das **drei Fassungen** zurücklag, ist über einen
> **Namen** aktuell geworden. Dreizehn echte QEMU-Starts.

## 0.1 Die drei wichtigsten Ergebnisse

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
| `lib/libc/dnswire.fi` | 502 | DNS (RFC 1035) als reine Oktettarbeit — **kein Systemaufruf**, deshalb ohne ein Paket prüfbar |
| `lib/libc/dns.fi` | 543 | die Steckdose: `/etc/resolv.conf`, gewürfelter Quellport, Kennung, 0x20, Frist mit Wiederholung, mehrere Server |
| `kernel/user/host.fi` | 330 | `/bin/host` — das Messgerät gegen `dig` |
| `kernel/user/dnswt.fi` | 353 | 19 von Hand gebaute, feindliche Nachrichten |
| `tools/ota/schluesselbund.py` | 294 | der geheime Schlüssel: verschlüsselt, und das Signieren getrennt vom Bauen |
| `tools/ota/veroeffentlichen.py` | 442 | Register, Vorrat, Archiv, Sperrliste, Kettensätze |
| `tools/betrieb/dnsdienst.py` | 222 | Nameserver **und Fälscher** |
| `tools/betrieb/dnsvergleich.py` | 174 | `/bin/host` gegen `dig`, 20 Namen |
| `tools/betrieb/run.sh` | 471 | der Läufer |
| `tools/betrieb/vorbereiten.sh` | 107 | Pakete, Zertifikate, Bund, vier Auslieferungen, Abbild, Platte |
| `tools/betrieb/crt-wirt.s` | 76 | zwei Zeilen Unterschied: dasselbe Programm auf dem Wirt |
| `tools/betrieb/wirt.sh` · `masse.py` | 20 · 64 | Bauhelfer |

Geändert:

| Datei | was |
|---|---|
| `kernel/user/dhcp.fi` | Option 6 wird gelesen; `/etc/resolv.conf` wird geschrieben; `fallback`-Zeilen bleiben stehen; `dns1..3` in `/etc/network.conf` |
| `kernel/app/fetch.fi` | ein **Name** in der URL wird aufgelöst und ist zugleich der Name fürs Zertifikat |
| `kernel/user/ota.fi` | OTA2, Schlüsselkette, Ersatzschlüssel, Sperrliste (gemerkt), `name=` freiwillig |
| `kernel/user/opk.fi` | der Ersatzschlüssel gilt auch für Paket- und INDEX-Signaturen |
| `tools/install/build.sh` | `/system/ersatz.pub`, `/system/SCHLUESSELGEN`, `dhcp` und `host` im Abbild, Apps bauen mit `FIRNLIB=<repo>/lib` |
| `tools/ota/listing.py` | erzeugt OTA2 |
| `tools/ota/server.py` | liefert auch Unterpfade aus (`v/2/VERZEICHNIS`) |

**Berührte Dateien, vollständig** (die Runden MERGE-3 und AVX arbeiten
parallel): `lib/libc/dns.fi`, `lib/libc/dnswire.fi` (beide neu),
`kernel/user/host.fi`, `kernel/user/dnswt.fi` (neu),
`kernel/user/dhcp.fi`, `kernel/user/ota.fi`, `kernel/user/opk.fi`,
`kernel/app/fetch.fi`, `tools/install/build.sh`, `tools/ota/server.py`,
`tools/ota/listing.py`, `tools/ota/schluesselbund.py` (neu),
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
Auflöser — **1 045 Zeilen in zwei Dateien**, davon 502 ohne einen
einzigen Systemaufruf.

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

`bash tools/betrieb/run.sh`, dreizehn Abschnitte. Die ersten neun laufen
auf dem Wirt (Sekunden), die letzten vier in QEMU auf Osum
(dreizehn echte Starts, unter Last des Wirts rund vierzig Minuten).

### 6.1 Das Format: 19 feindliche Nachrichten, ohne ein einziges Paket

`kernel/user/dnswt.fi`, gegen `lib/libc/dnswire.fi`. **19 grün, 0 rot**,
und der Läufer prüft zusätzlich, dass das Programm überhaupt **endet**
(Zeitgrenze 60 s) — die ersten sechs Fälle bringen einen Zerteiler ohne
Sprungschranke zum Hängen, und ein hängender Lauf ist ein roter Lauf.

| Fall | Antwort |
|---|---|
| Zeiger auf sich selbst | abgelehnt |
| Zeiger **nach vorn** | abgelehnt |
| Rückwärtskette über MAX_JUMPS (100 Sprünge, jeder echt nach unten) | abgelehnt |
| Name über 255 Oktett (6 Marken zu 63) | abgelehnt |
| Marke reicht über das Ende der Nachricht | abgelehnt |
| reservierte Markenbits (`0b10`) | abgelehnt |
| `rdlength` über das Ende hinaus | `R_FORMAT` |
| falsche Kennung | `R_MISMATCH` |
| **0x20: ein Buchstabe der zurückgesendeten Frage anders geschrieben** | `R_MISMATCH` |
| fehlendes QR-Bit | `R_NOTQUERY` |
| NXDOMAIN | `R_NXDOMAIN` |
| gültige A-Antwort mit Kompression | `R_OK`, 10.1.2.3 |
| CNAME-Kette | `R_OK`, verfolgt |
| **CNAME-Schleife a→b→a** | endet mit `R_LOOP`, statt zu hängen |
| Satz mit **fremdem Besitzernamen** (Beipack einer Vergiftung) | `R_NODATA`, der Wert wird **nicht** übernommen |
| TC-Bit | `R_TRUNCATED` |
| würfelt 0x20 wirklich? (zwei Anfragen, verschiedener Zufall) | 7 von 7 Buchstaben unterscheiden sich |
| leere Marke `a..b` in der Anfrage | abgelehnt |
| Marke über 63 Oktett in der Anfrage | abgelehnt |

### 6.2 `/bin/host` gegen `dig` — 21 echte Namen

Gemessen gegen `1.1.1.1`, verglichen wird die **Menge** der Adressen
(ein Name hinter einem Lastverteiler gibt bei jeder Frage eine andere
Auswahl heraus; ein Vergleich „erste Zeile gegen erste Zeile" wäre bei
jedem zweiten Lauf rot, ohne dass etwas falsch wäre).

**21 von 21 gleich, 0 verschieden.** Darin: gewöhnliche Namen,
CNAME-Ketten (`de.wikipedia.org`, `www.github.com`, `mail.google.com`),
AAAA, Namen mit Bindestrich und Ziffern, Wurzelserver, **und zwei
NXDOMAIN** — über den *Status* verglichen, nicht über eine leere Ausgabe,
weil „keine Adresse" und „den Namen gibt es nicht" zwei verschiedene
Aussagen sind.

**Was dabei aufgefallen ist und im Läufer steht:** der erste Entwurf
dieser Liste hatte `s3.dualstack.eu-central-1.amazonaws.com`,
`google.com`/AAAA, `mail.google.com` und `api.github.com` darin. Alle
vier waren zeitweise rot, **ohne dass etwas falsch war**: diese Zonen
geben je Frage eine Auswahl aus einem großen, wechselnden Vorrat heraus,
und `host` und `dig` bekamen zwei disjunkte Mengen — auch nach drei
Wiederholungen der `dig`-Frage. Ein Prüfstand, der bei richtigem
Verhalten würfelt, misst nichts. Sie sind durch Namen mit **kleiner,
fester** Adressmenge ersetzt (`a.gtld-servers.net`, `b.root-servers.net`,
`c.root-servers.net`, `www.debian.org`, `a.root-servers.net`/AAAA); die
CNAME-Ketten messen weiterhin `de.wikipedia.org` (CNAME auf
`dyna.wikimedia.org`) und `www.github.com` (CNAME auf `github.com`).

Dauer je Auskunft auf dem Wirt: **0–4 ms** (20 Läufe, Mittel 1,7 ms).
Auf Osum in QEMU: **6–7 ms**.

### 6.3 Der Zufall

20 Läufe von `host -v`, dieselbe Frage:

| | |
|---|---|
| verschiedene **Quellports** | 20 von 20 |
| verschiedene **Kennungen** | 20 von 20 |
| Spannweite der Quellports | 2322 … 63326 |
| kleinster Port | ≥ 1024 |
| richtige Antworten | 20 von 20 |

Zum Vergleich, und das ist der Grund für das ausdrückliche `bind`: ohne
es vergäbe Osums Kern `40000 + (zähler & 4095)` — **4096** Werte statt
64512, und der nächste ist aus dem vorigen zu errechnen.

### 6.4 Der Fälscher

`tools/betrieb/dnsdienst.py --boese`, je **6 Köder vor** der richtigen
Antwort:

| Köder | Adresse stimmt trotzdem | Fremdpakete gezählt |
|---|---|---:|
| falsche **Kennung** | ja | 6 |
| falscher **Quellport** (mit falscher Adresse darin) | ja | 6 |
| gekippte **0x20-Schreibweise** | ja | 6 |
| alle drei gemischt | ja | 6 |

**Beide Zahlen zählen.** Ohne „Fremdpakete gezählt" wäre der erste Haken
auch dann grün, wenn gar kein Köder angekommen wäre.

Dazu: eine gekürzte Antwort (TC-Bit) wird als `TRUNCATED` gemeldet; ein
Nameserver, der nicht antwortet, führt zu `TIMEOUT` und **nicht** zu
einer erfundenen Adresse.

### 6.5 Auf Osum: DHCP und ein echter Name

```
dhcp: ack ip=10.0.2.15  lease=86400
dhcp: /etc/network.conf geschrieben, Oktette 103
dhcp: /etc/resolv.conf geschrieben, dns 1
nameserver 10.0.2.3
```

Und dann, mit genau diesem Nameserver, **auf dem Gerät**:

```
osum$ host -v example.com
172.66.147.243
  server 10.0.2.3
  port   13237
  txid   9337
  tries  1
  fremd  0
  ms     7
```

`dig` auf dem Wirt nennt für `example.com` dieselbe Menge
(104.20.23.154, 172.66.147.243).

### 6.6 **Der Beweis der Runde: ein Update über einen NAMEN**

`/etc/ota.conf` trägt `quelle=https://pkg.betrieb.test:18443/v/1` und
**keine** `name=`-Zeile. Auf dem Gerät, Ende zu Ende:

```
ota: quelle https://pkg.betrieb.test:18443/v/1
fetch: aufgeloest 167772674          (= 10.0.2.2)
fetch: verify OK                     (Kette gegen /etc/ssl/roots.pem)
fetch: code 200
ota: fassung dort 1
...
ota: streuwert stimmt hallo-1.opk
opk: Signatur geprueft /tmp/ota/INDEX.sig
opk: Signatur geprueft /tmp/ota/hallo-1.opk
opk: installiert hallo -> 1
ota: BEREIT ZUM NEUSTART
(Neustart)
paket-hallo fassung 1
ota: fassung hier 1
```

Der Nameserver hat die Frage wirklich gesehen (`FRAGE pkg.betrieb.test
typ 1 txid …` im Protokoll der Gegenstelle), das Zertifikat wurde **gegen
denselben Namen** geprüft, und `ota suchen` hat vorher nichts
installiert.

### 6.7 **Drei Fassungen zurück — und wieder aktuell**

Gerät auf Fassung 1, Quelle auf Fassung 4:

```
ota: fassung hier 1
ota: fassung dort 4
opk: installiert hallo
ota: fassung hier 4
```

Und die alten Fassungen sind **weiter abrufbar** — mit `curl` gegen
dieselbe Gegenstelle geprüft:

| | Code | `fassung` im VERZEICHNIS |
|---|---:|---:|
| `v/1/VERZEICHNIS` | 200 | 1 |
| `v/2/VERZEICHNIS` | 200 | 2 |
| `v/3/VERZEICHNIS` | 200 | 3 |

Der Vorrat hält dabei **3 verschiedene Pakete** für **9 Fassungen**, und
`v/2/hallo-2.opk` hat **4 harte Verknüpfungen** — eine Fassung
vorzuhalten kostet keine Kopie.

### 6.8 Das Register

| Zusage | gemessen |
|---|---|
| geführte Fassung nach vier Auslieferungen | 4 |
| alle vier Fassungen liegen weiter da | `[1, 2, 3, 4]` |
| eine **kleinere** Fassungsnummer wird abgelehnt | `--fassung 2` → „geht zurück (geführt ist 4)" |
| das Register steht danach unverändert | 4 |
| eine **zurückgenommene** Auslieferung behält ihre Nummer | „geführt bleibt 4" |
| und `aktuell` fällt auf die vorige Fassung | „aktuell ist 3" |

### 6.9 Der Schlüsselbund

| Zusage | gemessen |
|---|---|
| der geheime Schlüssel steht **nicht im Klartext** im Bund | scrypt + ChaCha20-Poly1305 |
| mit falscher Passphrase wird **nicht** signiert | `InvalidTag`, keine Signaturdatei |
| Haupt- und Ersatzschlüssel sind verschieden | ja |
| der Ersatzschlüssel im Abbild ist der aus dem Bund | Streuwert gleich |

### 6.10 **Die sieben Gegenproben, einzeln vorgeführt**

Jede auf einer **frischen Kopie** der installierten Platte, jede ein
eigener QEMU-Start, und nach jeder Ablehnung wird nachgesehen, dass
wirklich nichts installiert wurde.

| # | Fall | Antwort des Geräts | installiert? |
|---:|---|---|---|
| 1 | mit einem **fremden** Schlüssel signiert | `ota: SIGNATUR DES VERZEICHNISSES FALSCH -- ABGELEHNT` | nein |
| 2 | mit dem **Ersatzschlüssel** signiert | `ota: mit dem ERSATZSCHLUESSEL geprueft` | **ja** |
| 3 | **gesperrte** Fassung, obwohl sie *neuer* ist | `ota: FASSUNG GESPERRT -- ABGELEHNT, angeboten 5` | nein |
| 4 | **Rückschritt** auf eine ältere Fassung | `ota: RUECKSCHRITT ABGELEHNT` | nein |
| 5 | **Schlüsselwechsel** mit gültiger Kette | `ota: SCHLUESSELWECHSEL angenommen, neue gen 1` | **ja** |
| 6 | Schlüsselwechsel mit **unterbrochener** Kette | `ota: SCHLUESSELWECHSEL: die Kette ist UNTERBROCHEN` — und `schluesselgen` bleibt 0 | nein |
| 7 | Gerät hat **zwei** Wechsel verpasst | `ota: SCHLUESSELWECHSEL angenommen, neue gen 2` in einem Zug | **ja** |

**Sieben Gegenproben, sieben bestanden.**

Fall 3 ist der, auf den es ankommt und der ohne die gemerkte Liste nichts
messen würde: das Gerät steht auf Fassung 0, bekommt beim ersten Lauf das
Verzeichnis der Fassung 6 zu sehen (`gesperrt 5`) und schreibt die Sperre
nach `/system/GESPERRT`; beim zweiten Lauf wird ihm die **richtig
signierte** Auslieferung 5 vorgelegt — neuer als sein Stand, an jeder
Signatur vorbei — und es lehnt ab.

### 6.11 Ein Befund aus dem Lauf, der den Bau geändert hat

Der erste vollständige Lauf war an einer Stelle rot, und der Grund war
kein Testfehler:

```
opk: Signatur geprueft /tmp/ota/INDEX.sig
opk: SIGNATUR FALSCH -- das Paket wird ABGELEHNT: /tmp/ota/hallo-2.opk
```

`veroeffentlichen.py` legte die Paketsignatur **neben das Paket in den
inhaltsadressierten Vorrat** und benutzte sie wieder. Das Paket ist
unveränderlich — die Signatur darüber hängt aber an einer
**Schlüsselgeneration**. Nach einem Wechsel war die Auslieferung damit in
sich widersprüchlich: `INDEX.sig` und `VERZEICHNIS.sig` trugen den neuen
Schlüssel, die Paketsignatur den alten. Das Gerät hat **richtig**
abgelehnt.

Seitdem liegen die Oktette einmal im Vorrat und die Signatur wird **je
Auslieferung** neu gerechnet. Das kostet 64 Oktett je Paket und Fassung
und macht jede Auslieferung unter **einem** Schlüssel in sich stimmig.
Der Satz, den man daraus mitnimmt: **ein Schlüsselwechsel entwertet jede
Signatur, die mit dem alten Schlüssel gemacht wurde** — auch die, die
schon auf der Platte liegt.

---

## 7. Regressionen

Der Kern ist **nicht angefasst** (`kernel/sched.fi`, `kernel/cpu.fi`,
`kernel/kmain.fi` und alles andere unter `kernel/*.fi` außer den vier
Programmen unter `kernel/user/` und `kernel/app/`). Was diese Runde
ändert, liegt in `kernel/user/`, `kernel/app/`, `lib/libc/` und `tools/`.

Geprüft:

* **Alle Programme übersetzen** — **127 Dateien** unter `kernel/user/`
  einzeln durch `firnc` (`rc=0`, keine einzige Ablehnung), `fetch` unter
  `--profile=app`, und **der Kern baut** (`tools/build-kernel.sh`,
  3 142 432 Oktette). Das Abbild trägt jetzt **38 Programme** statt 36
  (`dhcp` und `host` sind neu darin).
* **Das Abbild installiert sich und kommt hoch** — `install: fertig`,
  Beendigungscode 21, dreizehn Starts in diesem Lauf.
* **`tools/ota/listing.py` erzeugt OTA2**, damit der Läufer der Runde
  OTA gegen den neuen `/bin/ota` weiterläuft. Ein Gerät dieser Runde
  lehnt ein OTA1-Verzeichnis ausdrücklich ab (Abschnitt 4.1); das ist
  eine **gewollte** Verhaltensänderung und keine Regression.
* **`tools/ota/server.py`** liefert zusätzlich Unterpfade aus; der flache
  Weg (nur der letzte Namensteil) bleibt unverändert, und `--abbruch`
  und `--kurz` greifen weiter auf den Basisnamen zu.

Das vollständige Protokoll des Abschlusslaufs liegt als
`docs/RUNDE-BETRIEB.log` daneben.

**Nicht neu gefahren** wurde die vollständige Abnahme (`./test.sh`,
fünfzehn Abschnitte, über hundert QEMU-Starts) — der Wirt trägt zurzeit
mehrere Runden gleichzeitig (Lastmittel um 20 auf 12 Kernen), und ein
Abnahmelauf unter dieser Last misst die Last und nicht den Kern. Das ist
hier als offener Punkt benannt und nicht als erledigt behauptet: **wer
diesen Zweig zusammenführt, muss `./test.sh` und `tools/ota/run.sh`
einmal vollständig fahren.**

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
