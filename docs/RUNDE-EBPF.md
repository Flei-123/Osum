<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Runde O-EBPF — eine kleine Maschine im Kern, und ein Pruefer davor

Vor dieser Runde gab es in Osum kein eBPF. Der einzige Treffer im ganzen
Baum stand in `docs/NETVIEW.md` und erwaehnte `cgroup/skb` als die Art,
wie **Linux** dasselbe Problem loest. Es gab keine Maschine, keinen
Pruefer, keine Tafeln, keinen Haken.

Was jetzt da ist: ein Deuter fuer den klassischen eBPF-Befehlssatz, ein
Pruefer, der vor dem Laden nachsieht, zwei Arten von Tafel, zwei Haken im
Netzweg und ein Werkzeug in Ring 3, das das alles benutzt.

**Jede Zahl in diesem Bericht kommt aus `tools/ebpf/run.sh`.** Der Lauf
war **81 von 81 gruen, 0 rot**, als diese Datei geschrieben wurde. Wo
eine Zahl fehlt, steht, dass sie fehlt.

---

## 1. Warum ueberhaupt

Bis hierher konnte Osum Rahmen senden und empfangen (Runde K8), einem
Prozess sein eigenes Netz geben (NETVIEW) und zaehlen, wer wieviel
verbraucht (NETMON). Was es nicht konnte: **eine Entscheidung aufnehmen,
die nicht schon im Kern steht.** Wer einen Rahmen nach einer neuen Regel
verwerfen wollte, musste `kernel/inet.fi` aendern, neu uebersetzen und
neu starten — also den Kern anfassen, um eine Frage zu beantworten, die
mit dem Kern nichts zu tun hat.

Der Befehlssatz ist der klassische eBPF-Satz, weil er fuer genau das
entworfen wurde und weil es fertige Uebersetzer dafuer gibt — nicht,
weil Linux ihn hat.

---

## 2. Was gebaut ist

| Datei | Zeilen | was darin steht |
|---|---:|---|
| `kernel/ebpf.fi` | 909 | **Die Maschine.** Der Deuter: r0..r10, ALU32/ALU64, Spruenge, Laden und Speichern in vier Breiten, `CALL`, `EXIT`. |
| `kernel/ebpfver.fi` | 787 | **Der Pruefer.** Zwei Durchgaenge ueber das Programm, Registerarten je Befehlsstelle, Zusammenfuehrung ueber alle Wege. |
| `kernel/ebpfmap.fi` | 465 | **Die Tafeln.** Feld und Streutafel, 64-Bit-Schluessel auf 64-Bit-Werte. |
| `kernel/ebpfhook.fi` | 308 | **Die zwei Tueren.** Am Eingang des Geraets (XDP-artig) und am Sockel je Prozess. |
| `kernel/ebpftest.fi` | 740 | **Die Kreisprobe im Kern**, 41 Einzelproben, und das Probeprogramm der Runde. |
| `kernel/user/ebpfctl.fi` | 330 | **Das Werkzeug in Ring 3.** |
| `tools/ebpf/run.sh` | 467 | **Der Testlaeufer.** |

Dazu: vier Bereiche in `kdata`, fuenf Systemaufrufe, fuenf Modusworte,
der Haken in `kernel/inet.fi`.

### 2.1 Kein JIT, und das ist eine Entscheidung

Ein JIT waere schneller und er waere hier falsch. Er schreibt
Maschinencode in eine Seite und springt hinein; jeder Fehler darin ist
ein Fehler **mit Kernrechten**, und er ist nicht mehr zu pruefen,
nachdem er geschrieben wurde. Der Deuter kann jeden einzelnen Zugriff im
Augenblick des Zugriffs noch einmal ansehen — und er tut es auch (die
**zweite Schranke**, Abschnitt 4.3). Was das kostet, steht in
Abschnitt 6 als gemessene Zahl.

### 2.2 Umlaufrechnung ueberall

Firn prueft Ueberlaeufe **auch im Kernprofil**: `a + b` ruft bei
Ueberlauf `osum_panic`, und der Kern ist tot. Fuer den Kern selbst ist
das richtig. Hier nicht: eBPF rechnet laut Befehlssatz umlaufend, und
das Programm, das umlaufen laesst, ist ein **fremdes**. Stuende in
`ebpf.fi` ein einziges geprueftes `+`, waere das ein Weg, den Kern mit
drei Befehlen anzuhalten.

Jede Rechnung, die ein fremder Wert erreichen kann, benutzt deshalb
`+%`, `-%`, `*%`. Aus demselben Grund steht dort kein `as i32` und kein
`as i64` — auch diese Umwandlungen sind geprueft. Vorzeichen werden mit

```
fn sext(v: u64, bits: u64) -> u64 {
    let m: u64 = 1 << (bits - 1)
    return (v & ((1 << bits) - 1) ^ m) -% m
}
```

arithmetisch erweitert, arithmetisch geschoben wird mit `sar`. Die Probe
`alu.umlauf` im Testlaeufer ist genau diese Zeile: `0 - 1` muss
`0xFFFFFFFFFFFFFFFF` ergeben und darf den Kern nicht anhalten.

---

## 3. Die Maschine

Elf Register zu 64 Bit. `r10` ist der Stapelzeiger und **nur lesbar**;
der Stapel ist 512 Oktette gross, liegt in `kdata` und wird vor jedem
Lauf geloescht (sonst saehe ein Programm, was das vorige dort
liegenliess). Ein Befehl ist ein 64-Bit-Wort; der einzige Befehl, der
zwei Zellen belegt, ist `LD_IMM64` (0x18).

**Die harte Schranke.** Ein Lauf fuehrt nie mehr als `MAX_TICKS` = 4096
Befehle aus. Das ist die einzige Zusage der Maschine, die **nicht**
davon abhaengt, dass der Pruefer recht hat.

Gebaut ist: ALU64 und ALU32 (ADD, SUB, MUL, DIV, OR, AND, LSH, RSH, NEG,
MOD, XOR, MOV, ARSH), die Spruenge (JA, JEQ, JGT, JGE, JSET, JNE, JSGT,
JSGE, JLT, JLE, JSLT, JSLE) in der 64- und der 32-Bit-Fassung, LDX/STX/ST
in B/H/W/DW, `LD_IMM64`, `CALL`, `EXIT`.

**Nicht gebaut:** die atomaren Befehle (`BPF_ATOMIC`, 0xDB/0xC3) und die
Byte-Dreher (`BPF_END`). Sie werden als unbekannter Befehl **abgewiesen**,
nicht falsch gedeutet — siehe den Fehler in Abschnitt 8.2.

### 3.1 Die Kernfunktionen

| Nr | Name | was sie tut |
|---:|---|---|
| 1 | `map_lookup` | Adresse des Wertes, oder 0 |
| 2 | `map_update` | setzen/anlegen, 0 = gut |
| 3 | `map_delete` | loeschen |
| 4 | `ticks` | der Tickzaehler des Kerns |
| 5 | `trace` | ein Zaehler, damit ein Programm sich bemerkbar machen kann |

Eine neue Funktion braucht eine Nummer hier **und** einen Eintrag im
Pruefer; sonst ist sie nicht erreichbar.

---

## 4. Der Pruefer — was er zusagt

Ohne ihn ist die ganze Runde ein Einfallstor.

1. **Das Programm endet.** Jeder Sprung geht vorwaerts; ein
   Rueckwaertssprung wird abgewiesen. Damit gibt es keine Schleife, und
   ein Programm mit `n` Befehlen fuehrt hoechstens `n` Befehle aus.
2. **Jeder Sprung landet auf einem Befehl** — innerhalb des Programms
   und auf einer Befehlsgrenze, also nie in der zweiten Haelfte eines
   `LD_IMM64`, wo ein Sofortwert steht, den die Maschine sonst als
   Befehl lesen wuerde.
3. **Das Programm endet mit `EXIT`**, und kein Weg laeuft ueber das Ende
   hinaus.
4. **Kein uninitialisiertes Register wird gelesen.** Beim Start sind nur
   `r1` (Paketanfang), `r2` (Paketende) und `r10` gesetzt. An einer
   Sprungmarke gilt ein Register nur dann als gesetzt, wenn es auf
   **jedem** Weg dorthin gesetzt war (Schnittmenge).
5. **`r10` ist nur lesbar.** Ein beschreibbarer Stapelzeiger wuerde die
   Bereichspruefung aushebeln.
6. **Jeder Speicherzugriff liegt nachweislich im erlaubten Bereich.**
   Der Pruefer verfolgt je Register eine **Art**: `UNBEKANNT`, `PAKET`
   (mit konstantem Abstand), `PAKETENDE`, `STAPEL` (mit konstantem
   Abstand), `TAFELWERT`. Ein Stapelzugriff wird statisch nachgerechnet;
   ein Paketzugriff verlangt, dass das Programm vorher gegen `r2`
   geprueft hat.
7. **Aufrufe nur auf angemeldete Kernfunktionen.**
8. **Nur bekannte Befehle** — samt der Betriebsart (`op & 0xE0`), sonst
   wird ein atomarer Befehl als gewoehnlicher Speicherzugriff gedeutet.

Der Durchgang laeuft **einmal von vorn nach hinten**, und das reicht,
weil alle Spruenge vorwaerts gehen: wenn Stelle `k` betrachtet wird, sind
alle Wege dorthin schon gesehen.

### 4.1 Was der Pruefer NICHT prueft — die ehrliche Liste

Eine behauptete Sicherheit ist schlimmer als eine eingestandene Luecke,
weil sich auf die behauptete jemand verlaesst.

**(a) Keine Wertebereiche — kein `tnum`, keine Intervalle.** Linux
verfolgt zu jedem Register, welche Werte es annehmen kann, und laesst
deshalb `r1 += r3` mit geprueftem `r3` zu. Dieser Pruefer kennt nur
**konstante** Abstaende. Sobald ein Zeiger um einen unbekannten Wert
verschoben wird, wird er `UNBEKANNT` und jeder Zugriff darueber
abgewiesen. Das ist sicher, weist aber auch gueltige Programme ab — **zu
streng, nicht zu lasch.**

**(b) Der Zeiger aus `map_lookup` ist nicht benutzbar.** Er bekommt die
Art `TAFELWERT`, und darauf ist kein Zugriff erlaubt, weil der Pruefer
keine Laenge dazu kennt. Ein Programm kann einen Zaehler damit **nicht**
an Ort und Stelle erhoehen; es muss `map_update` rufen. Das ist der
groesste Unterschied zum Vorbild und der Grund, aus dem das
`count-icmp`-Programm in `ebpfctl` eine 1 schreibt, statt zu zaehlen.

**(c) Keine Rueckwaertssprunge, also keine Schleifen.** Linux erlaubt
seit 5.3 begrenzte Schleifen mit Wertebereichsanalyse. Wer hier eine
Schleife braucht, muss sie ausrollen.

**(d) Keine Unterprogramme** (`BPF_PSEUDO_CALL`).

**(e) Kein Nebenlaeufigkeitsmodell.** Zwei Prozessoren, die dasselbe
Programm gleichzeitig laufen lassen, teilten sich die Tafeln ohne Sperre.
In dieser Runde ist das folgenlos, **weil** alle Haken aus `K_NETD`
heraus laufen und dort `atomic.L_NET` gehalten wird — also nie zwei
zugleich. Diese Zusage steht in `inet.fi` und nicht im Pruefer; wer den
Haken woandershin haengt, muss sie neu pruefen.

**(f) Keine Laufzeitschranke ausser der Befehlszahl.** Ein Programm mit
512 erlaubten Befehlen haelt den Netzweg so lange auf, wie 512 Befehle
dauern.

**(g) Die atomaren Befehle fehlen ganz** — sie werden abgewiesen.

**(h) Der Pruefer selbst ist nicht bewiesen.** Er ist ein Stueck
Software wie jedes andere und kann irren. Deshalb gibt es die zweite
Schranke.

### 4.2 Die Befunde

| Wert | Name | wann |
|---:|---|---|
| 0 | `V_OK` | angenommen |
| 1 | `V_BACKJUMP` | ein Sprung nach hinten |
| 2 | `V_TARGET` | Ziel ausserhalb oder auf halbem Befehl |
| 3 | `V_NOEXIT` | endet nicht mit `EXIT` |
| 4 | `V_UNINIT` | Register gelesen, bevor es gesetzt war |
| 5 | `V_R10` | `r10` als Ziel |
| 6 | `V_MEM` | Zugriff, dessen Bereich nicht nachweisbar ist |
| 7 | `V_CALL` | unbekannte Kernfunktion |
| 8 | `V_OP` | unbekannter Befehl |
| 9 | `V_LEN` | zu lang, zu kurz, halber `LD_IMM64` |
| 10 | `V_STACKOFF` | Stapelzugriff ausserhalb des Stapels |
| 11 | `V_MAPPTR` | Zugriff ueber einen Tafelzeiger |

`ebpfctl` gibt den Befund aus **und** die Stelle, an der es scheiterte —
ohne die Stelle waere "abgewiesen" eine Meinung.

### 4.3 Die zweite Schranke

Die Maschine prueft jeden Speicherzugriff **noch einmal**, zur Laufzeit,
obwohl der Pruefer das schon zugesagt hat. Das ist keine doppelte Arbeit
aus Zaghaftigkeit: der Unterschied zwischen "der Pruefer irrt und ein
Programm wird abgewiesen" und "der Pruefer irrt und ein fremdes Programm
schreibt in `kdata`" ist der ganze Unterschied zwischen einem Fehler und
einer Luecke.

Erlaubt sind genau zwei Gebiete: der Paketpuffer `[data, data_end)` und
der eigene Stapel. Die Rechnung laeuft umlaufend und faengt damit auch
den Fall ab, dass `p + n` ueberlaeuft.

---

## 5. Die Tafeln und die Haken

**Zwei Arten.** Das **Feld** (Schluessel = Index) kann nicht volllaufen
und nichts verlieren — die Tafel fuer Zaehler. Die **Streutafel**
(64-Bit-Schluessel, lineare Sondierung) ist die Tafel fuer "welche
Absender habe ich gesehen". Vier Tafeln zu je 64 Eintraegen.

Beim Loeschen aus der Streutafel wird die Kette hinter dem Loch **neu
eingehaengt**; ohne das waere ein Schluessel, der beim Einfuegen ueber
diesen Platz hinweggelaufen ist, danach nicht mehr zu finden. Die Probe
`map.kette` prueft genau das — der Fehler zeigt sich sonst erst Monate
spaeter.

**Zwei Haken.** `K_XDP` am Eingang des Geraets, `K_SOCK` am Sockel je
Prozess. Beide antworten `PASS` oder `DROP`; sie **veraendern den Rahmen
nicht** (kein `XDP_TX`, kein `bpf_redirect`) — was mit einem halb
umgeschriebenen Rahmen geschieht, haengt an Laengen und Pruefsummen, die
dieser Pruefer nicht nachrechnet.

**Ein abgebrochenes Programm laesst durch.** Das ist eine Entscheidung:
ein Filter, der bei einem eigenen Fehler alles verwirft, nimmt die
Maschine vom Netz — und zwar genau dann, wenn niemand mehr hinschauen
kann. Der Zaehler `abbruch=` steht daneben, damit es auffaellt.

### 5.1 Wo der Haken steht, und warum genau dort

In `inet.pump`, in dieser Reihenfolge:

```
netmon.frame_seen(...)     <- zaehlen: was auf dem Draht war, war auf dem Draht
ebpfhook.xdp(...)          <- HIER
learn(...) / icmp_catch(...)
wg.rx_hook(...) / share.inbound(...)
stack.net_input(...)
```

**Nach** der Zaehlung, weil ein verworfener Rahmen trotzdem ueber die
Leitung kam und in der Abrechnung stehen muss. **Vor** allem anderen,
weil ein verworfener Rahmen dann wirklich nichts mehr kostet.

Dass er **vor `icmp_catch`** steht, ist gemessen und nicht geraten: die
erste Fassung setzte ihn dahinter, und Abschnitt 5b meldete, dass `ping`
trotz geladenem ICMP-Filter weiter Antworten bekam — `icmp_catch` faengt
die Echo-Antwort selbst ab, bevor der Stack sie sieht. Ein Haken am
Eingang muss der erste sein, der den Rahmen sieht, sonst filtert er nur
das, was vor ihm niemand haben wollte.

---

## 6. Die Zahlen

Aus `tools/ebpf/run.sh`. Die Maschine trug waehrend der Messung
Fremdlast (Lastmittel 20–30 auf 12 Kernen), weshalb **keine
Durchsatzmessung** angegeben wird — der Kopf von `kernel/netmon.fi`
zeigt an vier Messpaaren, dass so eine Messung dann die Nachbarn misst
und nicht den Code.

### 6.1 Die Kreisprobe

**41 von 41 Einzelproben gut, 0 boese.** Aufgeschluesselt:

* **15 Proben der Maschine** — `alu.add64`, `alu.sub32`, `alu.mul`,
  `alu.arsh`, `alu.umlauf`, `alu.div0`, `jmp.jeq`, `jmp.nichtge`,
  `jmp.jsgt`, `jmp.ja`, `mem.stapel`, `mem.oktett`, `mem.paket`,
  `mem.daneben`, `ld.imm64`.
* **11 Proben des Pruefers** — zehn Gegenproben, die abgewiesen werden
  **muessen**, und `ver.gut`, das durchkommen muss. Ohne diese elfte
  waere ein Pruefer, der alles abweist, in den zehn anderen gruen.
* **9 Proben der Tafeln**, darunter `map.ausprog`: ein **laufendes**
  Programm ruft `map_update`, und hinterher steht die Zahl in der Tafel.
* **4 Proben der Haken**, darunter `hook.leer`: ohne geladenes Programm
  laesst der Haken alles durch.

### 6.2 Was der Haken kostet

Takte je Rahmen, im Kern gemessen: derselbe Rahmen 2000 mal durch den
Haken, zwischen zwei `rdtsc`. Das ist eine Eigenschaft des Codes.

| Fall | Takte je Rahmen |
|---|---:|
| **leer** (Haken da, kein Programm) | **34–69** |
| ein Programm aus zwei Befehlen (`r0 = PASS; exit`) | 1 387–2 637 |
| ein Programm, das den Rahmen ansieht (13 Befehle) | 2 402–4 624 |

Der Lauf, aus dem die uebrigen Zahlen dieses Berichts stammen, ergab
`leer=56 klein=2492 gross=3924`.

Die Spannen sind die Streuung ueber mehrere Laeufe auf der belasteten
Maschine; die Groessenordnung ist stabil.

**Der leere Fall ist der Normalfall** und er ist der einzige, der fuer
eine Maschine ohne geladenes Programm zaehlt: eine Ladung aus `kdata`
und ein Vergleich, rund **40 Takte**. Bei 1,5 GHz sind das etwa 27
Nanosekunden — gegen rund 12 Mikrosekunden, die ein 1500-Oktett-Rahmen
auf einer Gigabitleitung selbst braucht. Das ist ein Promille.

Mit Filter kostet ein angesehener Rahmen rund **2 400–3 300 Takte**
(etwa 1,6–2,2 Mikrosekunden bei 1,5 GHz), also grob **200 Takte je
gedeutetem Befehl**. Das ist der Preis eines Deuters und der Betrag, den
ein JIT einsparen wuerde.

### 6.3 Der fertige Filter, an Rahmen aus dem Kern

Die entscheidende Probe des Filters, und sie braucht keine Leitung:
`ebpfdrop` haengt das ICMP-Filterprogramm in den Haken, danach schickt
der Kern **zwei selbstgebaute Rahmen** hindurch — dieselben 64 Oktette,
nur das Protokolloktett im IP-Kopf unterscheidet sich.

```
ebpf: drop-icmp pruef0 haengt=1
ebpf: probe icmp verwerf=1      <- Protokoll 1, verworfen
ebpf: probe tcp  durch=1        <- Protokoll 6, durchgelassen
```

Diese Probe haengt **nur am Filter**. Ob auf einer echten Leitung in
einem gegebenen Lauf ueberhaupt ein ICMP-Rahmen ankommt, haengt am Wirt
— das ist keine Grundlage fuer eine Zusage. Ein Filter, der alles
verwirft, faellt an der zweiten Zeile auf; einer, der nichts verwirft,
an der ersten.

### 6.4 Auf einer echten Leitung

Ein Programm, das ICMP verwirft und alles andere durchlaesst, am Eingang
des Geraets; dieselbe Uebertragung einmal ohne und einmal mit Filter,
ueber ein veth-Paar, einen Netzraum und die AF_PACKET-Bruecke aus
Runde K8.

| | ohne Filter | mit Filter |
|---|---|---|
| `ping` | `0% packet loss` | (nicht mehr gemessen, siehe unten) |
| `wget` | `status 200`, 4096 Oktette | `status 200`, 4096 Oktette |
| Zaehler `verwerf=` beim Start | 0 | 0 |
| Zaehler nach dem Verkehr (`ebpfctl`) | — | `gesehen` ≥ 4, `durch` ≥ 4, `abbruch` = 0 |

Dass **TCP weiterlaeuft**, waehrend der Filter haengt, ist die Haelfte
der Zusage, die ein zu scharfer Filter verletzen wuerde — sie wird hier
gemessen. Die andere Haelfte (ICMP wird wirklich verworfen) misst
Abschnitt 6.3, weil sie dort nicht vom Wirt abhaengt.

**`ping` steht nur im Lauf ohne Filter**, und das ist eine gemessene
Entscheidung: sobald der Filter greift, bekommt der ICMP-Sockel nie eine
Antwort, und `do_recvfrom` wartet je Versuch bis zu `NET_ROUNDS` Ticks
(rund 30 s, `kernel/sys.fi`). Der Lauf steht damit laenger als jedes
Zeitlimit des Laeufers — die erste Fassung lief genau deshalb in den
Abbruch, und der Befund sah aus wie "der Filter hat das Netz
abgeschaltet", obwohl der Filter tat, was er sollte.

Der Lauf, aus dem dieser Bericht stammt, ergab `gesehen=10 verworfen=1
durchgelassen=9 abgebrochen=0` — der Filter hat den einen ICMP-Rahmen
erwischt und die neun anderen (ARP, TCP) durchgelassen, waehrend `wget`
im selben Lauf seine 4096 Oktette bekam.

### 6.5 Der Weg aus Ring 3

`ebpfctl` baut die Befehle, schickt sie mit Aufruf 1405 hinunter, der
Pruefer sieht sie an, das Programm haengt sie an:

```
osum$ ebpfctl bad
ebpfctl: ABGEWIESEN, Befund = 1        <- V_BACKJUMP, die Schleife
osum$ ebpfctl drop-icmp
ebpfctl: der Pruefer nimmt es an
ebpfctl: haengt am Eingang an
osum$ ebpfctl
ebpfctl: haken an = 1
  geladen         = 1
```

Damit ist die Kette vollstaendig: Aufruf, Kopie, Pruefung, Haken, Tafel.

---

## 7. Der Platz in `kdata` und die Nummern

| Bereich | Lage | Groesse |
|---|---|---:|
| `EBPF_OFF` | `0x12C000` | 24 KiB |
| `EBPFMAP_OFF` | `0x132000` | 8 KiB |
| `EBPFVER_OFF` | `0x134000` | 28 KiB |
| `EBPFHOOK_OFF` | `0x13B000` | 4 KiB |

Alle vier stehen in `tools/kernel/memmap.py`; der Kartenpruefer meldet
**133 Bereiche, 0 Kollisionen**.

Systemaufrufe **1405–1409** (`EBPFLOAD`, `EBPFATTACH`, `EBPFMAP`,
`EBPFSTAT`, `EBPFPROG`), vorher mit `syscalls.py --zweige` gegen **alle**
Zweige geprueft. Alle fuenf sind **root only**: wer ein Programm in den
Netzweg haengen kann, kann den Netzverkehr dieser Maschine lesen und
wegwerfen. Linux hat dieselbe Entscheidung nach einer Reihe von Luecken
nachtraeglich getroffen (`kernel.unprivileged_bpf_disabled`); diese Runde
faengt damit an.

Modusworte: `noebpf` (die Gegenprobe), `ebpftest`, `ebpfbench`,
`ebpfdrop`, `ebpfverb` — Indizes 1055–1059.

---

## 8. Die fuenf Fehler, die der Testlaeufer gefunden hat

Sie stehen hier, weil sie zeigen, wofuer die Proben da sind. Alle fuenf
waren im Quelltext unsichtbar und in keinem Fall haette ein Blick sie
gefunden.

**8.1 Die Tafel-Kopfsaetze lagen unter den Eintraegen.** Vier Kopfsaetze
zu 64 Oktetten ab `0x40` enden bei `0x140`, die Eintraege begannen aber
bei `0x100`. Weil `create` seine Eintraege loescht, bevor es den Kopfsatz
schreibt, loeschte **das Anlegen der Tafel 0 den Kopfsatz der Tafel 3**.
Sichtbar wurde es, weil die Probe die Platznummer nachrechnet statt sie
zu glauben: `create` gab 4 zurueck, obwohl nur drei Tafeln vergeben
waren. Eintraege liegen jetzt bei `0x200`.

**8.2 `0xDB` wurde als gewoehnlicher Speicherzugriff gedeutet.** Der
atomare Befehl hat dieselbe Klasse wie `STX`; ohne Pruefung der
Betriebsart (`op & 0xE0`) schrieb die Maschine dort, wo ein atomares
Addieren stehen sollte. Jetzt in Pruefer **und** Maschine abgewiesen.

**8.3 Die Probe loeschte ihre eigenen Zaehler.** Sie lagen erst im
Messpuffer (`bench` schrieb darueber), dann dahinter — und `ebpfhook.init`
loescht ueber `ebpf.init` den **ganzen** Maschinenbereich. Die Probe
meldete `gut=4` statt `gut=41`. Eine Probe, die ihre Zaehler dorthin
legt, wo das Geprueefte aufraeumt, misst sich selbst kaputt.

**8.4 Alle fuenf Systemaufrufe waren unerreichbar.** Sie standen in
`net_call`, aber die Weiche in `sys.fi` laesst nur
`number >= SYS_OSUM_NETGET && number <= SYS_OSUM_SHARE` (also bis 1322)
dorthin — 1405 fiel hindurch, und `ebpfctl` bekam `-ENOSYS` fuer jeden
einzelnen. Genau die Falle, vor der der Kommentar bei MERGE an derselben
Stelle warnt. Jetzt ein eigenes Fenster.

**8.5 `copy_in` bekam einen Offset statt einer Adresse.** `copy_in`
schreibt mit `kstate.set8(dst + ...)` **ohne** `state` davorzusetzen,
erwartet also eine absolute Adresse; uebergeben wurde
`prog_at(state, slot) - state`. Die Befehle landeten unterhalb von
`kdata`, der Pruefer sah lauter Nullen und antwortete auf **jedes**
Programm mit `V_NOEXIT` — auch auf ein gueltiges. Gefunden, weil
Abschnitt 6 den Befund fuer ein **gueltiges** Programm nachrechnet und
nicht nur fuer ein kaputtes.

Merkregel, die daraus folgt und im Repo bisher nirgends stand:
**`copy_in`/`copy_out` nehmen absolute Adressen, `kstate.get`/`set`
nehmen Offsets.**

---

## 8a. Die Regression

Vor dem Commit, auf demselben Stand:

| Laeufer | Sollwert | gemessen |
|---|---|---|
| `tools/k17/run.sh` | 158 passed, 0 failed | **158 passed, 0 failed** |
| `tools/hotplug/run.sh` | 45 passed, 0 failed | **45 passed, 0 failed** |
| `tools/ebpf/run.sh` | — (neu) | **81 passed, 0 failed** |

`tools/install/abnahme.sh` ist **nicht** gelaufen: die Maschine hatte
waehrend dieser Runde durchgehend 1–2 GB freien Plattenplatz bei einem
Lastmittel von 20–30, und die Abnahme braucht unter Last bis zu 45
Minuten samt einer vollstaendigen QEMU-Installation. Das ist eine
offene Zusage und keine erfuellte — sie steht in Abschnitt 9 als
naechster Schritt.

---

## 9. Was als naechstes fehlt

In der Reihenfolge, in der es sich lohnt:

1. **Ein `tnum` im Pruefer** (Luecke 4.1a). Ohne Wertebereiche ist
   `r1 += r3` nicht moeglich, und damit faellt jedes Programm durch, das
   einen Rahmen mit berechnetem Abstand liest — also fast jedes echte.
   Das ist die groesste einzelne Einschraenkung.
2. **Der Tafelzeiger benutzbar machen** (Luecke 4.1b): eine Art
   `PTR_TO_MAP_VALUE` mit bekannter Laenge. Erst danach kann ein
   Programm einen Zaehler selbst erhoehen, statt `map_update` zu rufen —
   und erst dann sind die Tafeln das, wofuer es sie gibt.
3. **Ein Uebersetzer oder wenigstens ein Lader fuer fremde Programme.**
   Im Augenblick werden die Befehle im Quelltext zusammengebaut. Ein
   Leser fuer den ELF-Abschnitt, den `clang -target bpf` erzeugt, waere
   der naechste Schritt; der Befehlssatz ist absichtlich derselbe.
4. **Der Sockelhaken wird noch nicht benutzt.** `ebpfhook.sock` ist
   gebaut und geprueft, aber in `inet.sock_recv` nicht eingehaengt —
   Stufe 4 ist damit halb: die Tuer am Geraet steht, die am Sockel ist
   gebaut und nicht aufgehaengt.
5. **Schleifen**, entweder begrenzt und geprueft oder gar nicht.
6. **Die atomaren Befehle**, wenn ein Programm je Zaehler teilen soll.
7. **`tools/install/abnahme.sh`** nachholen, sobald die Maschine Platz
   und Ruhe hat (siehe 8a).

---

## 10. Was diese Runde nicht ist

Sie ist **nicht** Linux' eBPF. Es fehlen die Wertebereichsanalyse, die
Programmarten ausser zweien, die Hilfsfunktionen bis auf fuenf, `perf`-
und Ringpuffer, `BTF`, `bpf_redirect`, das Anhaengen an Tracepoints und
Kprobes und das ganze Werkzeugland drumherum.

Was sie ist: eine Maschine, die fremde Programme im Kern ausfuehrt, ein
Pruefer, der vorher nachsieht und dessen Grenzen aufgeschrieben sind, und
ein Weg von Ring 3 bis in den Netzpfad, der an jeder Stelle gemessen ist.
