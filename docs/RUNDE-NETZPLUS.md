# Runde NETZPLUS — die fehlenden Teile des TCP-Stacks

Zweig `netzplus`, ab `main` 7e68da55.

Runde K3 hat einen TCP-Stack geschrieben, der die Zustandsmaschine
vollstaendig hat: alle elf Zustaende, Drei-Wege-Handschlag,
Neuzusammenbau ausser der Reihe, Jacobson/Karn, Nagle, Slow Start,
Fast Retransmit, Persist-Timer. Der Kopf von `vendor/firn/lib/net/tcp.fi`
hat aber auch aufgeschrieben, was fehlt — und das waren genau die Dinge,
die auf einer Strecke mit Laufzeit ueber Durchsatz entscheiden:

> no window scaling, no timestamps, no SACK, no PAWS, no urgent data,
> no reassembly of IP fragments, no path MTU discovery

Diese Runde zieht **vier davon** nach und misst sie. Offen bleiben
Urgent Data und die IP-Fragment-Reassemblierung (unten, „Was offen
bleibt").

---

## 1. Wo die Aenderung liegt, und warum dort

`vendor/firn/lib/net/` ist ein **vendorierter** Baum: er ist nicht
eingecheckt, und `vendor/firn/fetch-firnc.sh` loescht ihn bei jedem Bau
mit `rm -rf` und legt ihn aus dem festgenagelten Firn-Commit neu an.
Eine Aenderung, die nur dort laege, waere beim naechsten `--force`
spurlos weg.

**Gewaehlt: ein Flicken im Osum-Repo**
(`vendor/firn/patches/0006-netzplus-ws-ts-sack-pmtu.patch`), nicht eine
Aenderung drueben in `/root/firn`. Die Gruende, in dieser Reihenfolge:

1. **Der Pin ist die Zusage.** `vendor/firn/COMMIT` = `7b4c22b1` sagt,
   gegen welchen Uebersetzer gemessen wurde. Eine Aenderung drueben
   zwingt zu einem neuen Pin, und der zoege die gesamte
   Firn-Entwicklung seit `7b4c22b1` mit herein — `main` steht dort bei
   `421293f2a`. Dann waere bei jedem Fehler wieder unklar, ob er aus dem
   Kernel oder aus dem Uebersetzer kommt. Genau das soll der Pin
   verhindern.
2. **An `/root/firn` arbeiten parallel andere Runden.** Ein Zweig dort,
   den nur Osum braucht, ist ein Zweig, den jemand anders erbt.
3. **Der Mechanismus haelt die Zusage von `vendor/net/BLOBS`.**
   `fetch-firnc.sh` legt jede Datei, die ein Flicken anfasst, VORHER
   unveraendert nach `lib/.roh/`; Abschnitt 1 von `./test.sh` prueft
   dort. Der Stack „unter uns" ist damit weiterhin nachweislich der des
   Pins — nachgeprueft, alle drei Streuwerte gruen.

Langfristig gehoert der Inhalt nach Firn; `REMOVE-FROM-FIRN.md` fuehrt
das. Solange er dort nicht ist, steht er hier.

---

## 2. Was gebaut wurde

### Stufe 1 — Fensterskalierung (RFC 7323)

**Der Hebel ist nicht die Option, sondern der Puffer.** Was ein Ende
ankuendigen darf, bleibt, was es auch aufheben kann: mehr als
`rcv_free()` anzukuendigen hiesse, Oktette anzunehmen, fuer die kein
Platz ist. Mit `RCV_CAP = 64 KiB` waere `wscale` eine Option, die
ausgehandelt wird und **nichts aendert** — 65535 bleibt 65535, ob mit
Faktor 0 oder ohne Option.

Also: `RCV_CAP` von 64 KiB auf **256 KiB**, `RCV_MASK` und das Feld
`rcv_buf` mit. Der eigene Faktor ist 2 (mal vier); `rcv_window()`
liefert weiterhin den wahren Wert in Oktetten, `rcv_window_field()` den
verschobenen fuers 16-Bit-Feld.

Die Aushandlung folgt RFC 7323 2.2: die Option gilt **nur, wenn sie in
beiden SYN steht**. Waehrend des Handschlags selbst ist das Fenster noch
unskaliert; der Faktor wird gemerkt und erst beim Uebergang nach
ESTABLISHED scharf geschaltet (`opt_arm`). Sonst faengt die Verbindung
mit einem vervierfachten Sendefenster an, das die Gegenseite nie
zugesagt hat.

Der Sendepuffer bleibt bei 64 KiB: diese Runde misst Linux → Osum, und
dort ist der Empfangspuffer die Grenze.

### Stufe 2 — Zeitstempel und PAWS (RFC 7323)

Zeitstempel in jedem Segment, sobald beide Seiten sie angeboten haben.
Der eigene Takt ist `Mikrosekunden >> 10` (~1,05 ms), im Bereich, den
RFC 7323 4.1 verlangt — eine Verschiebung statt einer Division, weil
dieser Stack keine hat.

PAWS verwirft ein Segment, dessen Zeitstempel aelter ist als der zuletzt
gesehene. **Die Ausnahme ist keine Feinheit:** ein Zeitstempelzaehler
laeuft selbst ueber, deshalb gilt ein Unterschied jenseits von 2^31 als
Ueberlauf und nicht als altes Segment, und nach 24 Stunden Ruhe wird
`ts_recent` nicht mehr geglaubt. Ohne beides friert die Verbindung
genau einmal pro Zaehlerumlauf fuer immer ein.

`ts_recent` wird nur von einem Segment fortgeschrieben, das die Luecke
bei `rcv_nxt` schliesst (RFC 7323 4.3).

### Stufe 3 — SACK (RFC 2018), beide Richtungen

**Empfangen:** die Bloecke der Gegenseite sagen, was drueben schon
liegt. **Senden:** die eigenen Loecher (`ooo_lo`/`ooo_hi`) werden
angekuendigt, der zuletzt angekommene Block zuerst (RFC 2018 4).

Die Wiederholung **springt** dann ueber jeden bestaetigten Bereich
(`sack_covered`/`sack_skip`), statt Go-back-N zu fahren, und ein Segment
reicht nie ueber den Anfang des naechsten bestaetigten Blocks hinaus.
Die Sprungschleife hat eine harte Obergrenze — ein Sprung, der nicht
vorankommt, waere sonst eine Endlosschleife im Kernel.

**Die Grenze, die hier wirklich wehtut:** das Datenversatzfeld hat vier
Bit, der Kopf also hoechstens 60 Oktette, also 40 fuer Optionen.
Zeitstempel (12 mit Auffuellung) und vier SACK-Bloecke (34) sind
zusammen 46 — das passt nicht. Die Zahl der Bloecke wird deshalb an dem
gemessen, was frei ist.

### Stufe 4 — Path MTU Discovery (RFC 1191)

Bis hierher setzte der Stack „Don't Fragment" und **warf die Antwort
darauf weg** — eine schwarze Strecke: der Handschlag geht durch, die
Daten nicht, und der Wiederholungstimer schickt dasselbe zu grosse
Segment bis zur Aufgabe.

Jetzt liest `net/stack.fi` ICMP Typ 3 Code 4, holt aus dem
zurueckgeschickten Kopf die Verbindung (Achtung: dort ist die Quelle
*wir*, das Ziel die Gegenseite) und senkt die MSS. Zwei Faelle sind
behandelt: ein Router, der die naechste MTU **nicht** nennt (dann in
Stufen nach RFC 1191 7-1), und eine gefaelschte Nachricht — unter 576
geht es nicht, und **groesser** wird die MSS durch ICMP nie.

---

## 3. Gemessen

Prüfstand: `tools/netzplus/run.sh` (Mechanik in `tools/netzplus/mess.sh`),
Bauart wie Runde K8 — Osum in QEMU auf virtio-net, UDP zur Bruecke,
AF_PACKET auf ein veth-Paar, Linux im eigenen Namensraum, `tc netem` fuer
Verzoegerung und Verlust. **Verzoegerung ist der Punkt:** ueber loopback
ist die Laufzeit ~0, und dann ist ein 64-KiB-Fenster nie die Grenze — eine
Runde, die Fensterskalierung einbaut und ohne Laufzeit misst, sieht nichts.

Linux → Osum, 1 MiB, `nsvc=1`, QEMU/KVM, Wirt unter Fremdlast (Last 20–28).

| Umlaufzeit | vorher | nachher | Faktor |
|---|---|---|---|
| ~0 ms | 5367 KiB/s | **16826–25689 KiB/s** | 3,1–4,8× |
| ~20 ms | 1505 KiB/s | **3785–4275 KiB/s** | 2,5–2,8× |
| ~50 ms | 914 KiB/s | **2224–2329 KiB/s** | 2,4–2,5× |
| ~100 ms | 489 KiB/s | **1219–1220 KiB/s** | 2,5× |

Die Spannen sind zwei Laeufe desselben Standes auf einem Wirt unter
Fremdlast (Last 20–37); die Zahl ohne Verzoegerung schwankt am
staerksten, weil dort der Wirt und nicht das Fenster die Grenze ist.
Der Wert, auf den es ankommt, ist der stabilste: bei 100 ms Umlaufzeit
1219 gegen 1220 KiB/s in zwei Laeufen.

### Die Gegenprobe, die es zur Messung macht

Derselbe Kernel, dieselbe Strecke, 100 ms Umlaufzeit, nur `nzws=0`:

| | Durchsatz | ws_ok | angekuendigtes Fenster |
|---|---|---|---|
| ohne Skalierung | 539 KiB/s | 0 | 65535 |
| mit Skalierung | 1219–1220 KiB/s | 1 | 262140 |

Der Deckel aus Fenster/Umlaufzeit ist bei 64 KiB und 100 ms genau
**640 KiB/s**. Ohne Skalierung bleibt die Messung darunter, mit
Skalierung darueber. Das ist der Beweis — nicht „es ist schneller
geworden", sondern „diese Option hat die rechnerische Grenze gehoben".

### Die Aushandlung, auf dem Draht

```
vorher   Osum SYN/ACK: options [mss 1460]
nachher  Osum SYN/ACK: options [mss 1460,nop,wscale 2,sackOK,TS val ... ecr ...]
```

Linux bietet `[mss 1460,sackOK,TS val ...,nop,wscale 10]` an und schaltet
danach auf `win 63` (also 63 × 2^10) um. Im Verbindungsblock, ausgelesen
bevor er freigegeben wird: `ws_ok=1 snd_ws=10 rcv_ws=2 ts_ok=1 sack_ok=1`.

### Verlust

262144 Oktette, 5 ms Verzoegerung, Verlust auf dem Weg **zu** Osum:

| Verlust | Oktette | ausser der Reihe | SACK gesendet | Durchsatz | PAWS |
|---|---|---|---|---|---|
| 1 % | alle 262144 | — | — | 2470–2862 KiB/s | 0 |
| 5 % | alle 262144 | 61 | 13 Bloecke | 1716–2137 KiB/s | 0 |

`paws=0` ist hier eine echte Zusage und keine Nebensache: ein PAWS, das
im Normalbetrieb zuschlaegt, ist kaputt.

**Und die Gegenrichtung** — Osum oeffnet die Verbindung selbst und
schickt (`nsvc=4`, gegen `tools/net/echosrv.py` auf dem Wirt):

| | gesendet | zurueck | falsch | SACK empfangen | SACK-Wiederholung |
|---|---|---|---|---|---|
| sauber | 262144 | 262144 | 0 | — | — |
| 10 % Verlust | 65536 | 65536 | 0 | 11 Bloecke | 2 |

Der Wirt bestaetigt es unabhaengig: `echoed 262144` bzw. `echoed 65536`.

### Testzahlen

```
tools/netzplus/run.sh   39 passed, 0 failed
tools/k17/run.sh       158 passed, 0 failed   (Sollwert 158/0)
tools/hotplug/run.sh    45 passed, 0 failed   (Sollwert 45/0)
```

**Eine Warnung zum Messen auf diesem Wirt.** Beide Regressionen sind im
ersten Anlauf rot gewesen — `k17` mit 51/98, `net` mit 12/60 — und keine
einzige dieser Meldungen hatte mit dieser Runde zu tun. Im Protokoll
stand jeweils

```
sed: can't read /tmp/tmp.XXXXXXXX/k1.log: No such file or directory
cp: error copying ... : No space left on device
```

Das `mktemp -d`-Verzeichnis wurde **waehrend des Laufs** weggeraeumt, und
die Platte lief auf 100 %. Beides kommt von den anderen Runden, die
gleichzeitig auf dieser Maschine messen (Last 20–37). Mit
`TMPDIR=/root/<eigener Pfad>` und wieder freier Platte sind es 158/0
und 45/0. Wer hier misst und rote Zahlen sieht, prueft **zuerst**
`df -h` und ob das Arbeitsverzeichnis noch existiert.

---

## 4. Zwei Fehler, die die Sprache gefangen hat

Eine Feldlaenge ist in Firn ein **Ganzzahlliteral** (SPEC 12.1); der
Uebersetzer kann sie nicht gegen eine Konstante pruefen. Beide Male
meldete es sich als `panic: index out of bounds` — als Absturz an der
richtigen Stelle, nicht als stiller Datenfehler:

* `stat: [u64; 12]` gegen `ST_COUNT` 17 — der Kern blieb beim ersten
  `tcp_init` stehen.
* `rcv_buf: [u8; 65536]` gegen `RCV_CAP`/`RCV_MASK` 262144/262143 — die
  Maske liess Indizes bis 262143 durch, das Feld war 65536 lang.
  Gefunden beim ersten ankommenden Segment.

Wer eine dieser Zahlen aendert, aendert alle, die dazugehoeren.

## 4b. Der Fehler, den erst der FREMDE Laeufer gefunden hat

Der eigene Laeufer war 39/0 gruen, und die Durchsatzzahlen oben standen
schon. Dann meldete `tools/net/run.sh` — der Laeufer der Runde K8, den
diese Runde nicht geschrieben hat — Abschnitt 7:

```
FAIL  octets Osum sent: 65536, expected eq 262144
FAIL  octets that came back: 0, expected eq 262144
FAIL  'echoed 262144' is missing
```

**Genau ein Sendepuffer, dann Stillstand.** Der eigene Laeufer konnte
das nicht sehen: er misst `nsvc=1`, also Linux → Osum. Kaputt war die
**Gegenrichtung**, in der Osum selbst schiebt.

Die Ursache ist eine Addition:

```
IP 20 + TCP 20 + Zeitstempel 12 + MSS 1460 = 1512 > MTU 1500
```

Mit Zeitstempeln traegt jedes Segment 12 Oktette Optionen. Die Nutzlast
blieb trotzdem bei voller MSS, und `seg_build` gibt bei `total > cap`
eine **0** zurueck — kein Segment, ohne Fehler und ohne Meldung. Der
Sender wartete danach auf Bestaetigungen fuer Oktette, die nie
hinausgingen.

Behoben nach **RFC 6691**: die nutzbare Nutzlast ist `mss - 12`, sobald
Zeitstempel ausgehandelt sind, und Nagle vergleicht gegen dieselbe
Groesse. Bei derselben Gelegenheit wurde der SACK-Sprung auf die
Erholung begrenzt (`in_recovery`): ohne diese Bedingung galten die
Bloecke der Gegenseite auch im Normalbetrieb, und der Sendezeiger waere
ueber Oktette gesprungen, die nie gesendet wurden — ein Loch, das dieser
Stack sich selbst gerissen haette.

**Die Lehre:** ein Laeufer, den man selbst fuer die eigene Aenderung
schreibt, prueft die Richtung, an die man gedacht hat. Die vorhandenen
Laeufer pruefen die anderen. Beide gehoeren vor den Commit.

## 5. Ein Fehler, den erst die Gegenprobe gefunden hat

Nach dem Einbau der drei Abschalter (`nzws=`, `nzts=`, `nzsack=`) ging
**gar nichts** mehr: `net: ip=10.9.0.2` stand da, `nic: listening=7`
stand da — und daneben `accepted=0`, `rx_f=0`, `pumps=0`. Die Bruecke
meldete `to_qemu=9  to_wire=0`: sie schickte Rahmen, die niemand abholte.

Gleichzeitig fiel `tools/net/run.sh` — der unveraenderte Laeufer der
Runde K8 — mit denselben Symptomen. Daraus wurde zuerst geschlossen, es
liege am Wirt (Last 22–28, Platte bei 98 %). **Der Schluss war falsch,**
und zwar aus einem Grund, der sich merken laesst: der K8-Laeufer baut
sich seinen Kernel selbst, mit demselben geflickten `vendor/firn/lib/`.
Er fiel nicht *neben* dem Fehler, sondern *an* ihm.

Die Gegenprobe, die es entschied — Baum auf den ungeflickten Stand
zurueck, denselben Kernel bauen, dieselbe Strecke:

```
ungeflickt  3 von 3 ping, rx_f=8, icmp=3, netd=2   -- laeuft
geflickt    0 von 3 ping, rx_f=0, icmp=0, netd=1   -- laeuft nicht
```

**Die Ursache:** die K2-Skalarseite (`pci.K2_SCALARS`) wird von `hw.fi`,
`inet.fi`, `netsvc.fi`, `fb.fi`, `wg.fi` und weiteren geteilt, und jedes
Modul rechnet seine Offsets selbst aus. Es gibt keine Stelle, die die
Vergabe fuehrt, und der Uebersetzer kann sie nicht pruefen — ein Modul
kennt die Konstanten des anderen nicht. Die drei neuen Schalter lagen
auf `0x3E0` (`netsvc.fi S_BUF`, der Puffer des Netzdienstes), `0x3E8`
(`netsvc.fi S_TASK`, die Nummer der Netzaufgabe) und `0x3F0`
(`inet.fi S_SADDR`). Die Vorgabe „1" in diese Slots zu schreiben loeschte
Pufferzeiger und Aufgabennummer, bevor der Netzdienst sie brauchte.

Behoben: `0x458`/`0x460`/`0x468`, gegen **alle** Module geprueft, die die
Seite benutzen. Danach wieder 3 von 3 ping und `rx_f=7`.

Drei Fehler im Pruefstand selbst kamen bei derselben Jagd heraus und
stehen mit Begruendung im Quelltext: Anschluesse aus dem **fluechtigen**
Portbereich (32768–60999, den Linux selbst vergibt), ein Start mit dem
**vollen** Selbsttestlauf (`nc` gibt auf, bevor der Kern lauscht) und
eine fehlende Aufraeumfalle, durch die abgebrochene Laeufe Namensraum
und veth-Paar stehen liessen.

---

## 6. Was offen bleibt

* **Urgent Data.** Bewusst nicht gebaut. Das URG-Feld ist in der Praxis
  tot (RFC 6093 raet ausdruecklich davon ab, es zu benutzen), und ein
  Weg, der nie gegangen wird, ist ein Weg, der nie gemessen wird.
* **IP-Fragment-Reassemblierung.** Nicht gebaut. Ein Fragment wird nach
  wie vor erkannt und **verworfen**, nicht fuer ein ganzes Datagramm
  gehalten. Mit Path MTU Discovery ist der Druck geringer: die Strecke
  sagt jetzt, wie gross ein Segment sein darf, statt stillzuschweigen.
* **Path MTU Discovery ist die Empfangsseite.** Der Stack **reagiert**
  auf „fragmentation needed" korrekt; was fehlt, ist das periodische
  Wieder-Anheben der MSS nach zehn Minuten (RFC 1191 6.4) und eine
  Messung an einer Strecke mit wirklich kleinerer MTU — auf der
  veth-Strecke dieses Pruefstands tritt der Fall nicht auf. Der Zaehler
  `mtu_down` ist da und bleibt dort 0.
* **Der Sendepuffer** ist weiter 64 KiB. Fuer die Richtung Osum → Linux
  ueber eine Strecke mit Laufzeit waere er die naechste Grenze.
* **D-SACK** (RFC 2883) ist nicht gebaut.
