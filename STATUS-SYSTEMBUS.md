# Runde SYSTEMBUS — der Bericht

Zweig `systembus`, abgezweigt von `merge6` (2aa3f59), Arbeitsbaum
`/root/osum-systembus`. Nicht gemergt, nicht gepusht.

Roadmap: **A3** (Systembus/IPC mit Rechten), **D1–D3** (Zwischenablage,
Drag-and-Drop, Verlauf), **A11** (Benachrichtigungen).

---

## Die Zahlen auf einer Seite

| Läufer | Ergebnis | Anmerkung |
|---|---|---|
| `tools/systembus/run.sh` | **30 / 5** | die fünf roten sind Abschnitt 9, siehe unten |
| `tools/posix/run.sh` | **134 / 0** | Baseline gehalten (merge6: 134/0) |
| `tools/multicore/run.sh` | **39 / 1** | merge6 war 38/2 — **besser**, kein Regress |
| `tools/design/messen.py` | **818 von 872 = 93 %** | Auflage: nicht unter 92 %. merge6: 92 % |
| `tools/themestore/run.sh` | **nicht zu Ende gelaufen** | siehe „Offen“ |

Die Messungen des Busses, aus `tools/systembus/run.sh`, `-smp 4`:

```
busa run=100  abw=0        busb got=100  leer=0
busd vor=0  uid=1000  ruf=-3
bus: ABGELEHNT dienst=0 pid=5 uid=1000 regel=2
buss byt=1048576  us=2683  sum=8590786560  seiten=256
bus: sends=201 recvs=200 denied=1 drops=0
bus: clipsets=100 clipgets=100 segs=1 segseiten=256 sperre=815 verlauf=20
taskbar: text noti ... t=Meldg 2
```

---

## Die Abnahme, Punkt für Punkt

**a) Prozess A schreibt, Prozess B liest identisch, 100 Durchläufe,
4 Kerne, 0 Abweichungen** — **erfüllt.** `busa: run=100 abw=0`,
`busb: got=100 leer=0`. Gemessen wird nicht „B hat etwas bekommen“,
sondern eine **FNV-Prüfsumme je Durchlauf**, die B selbst über den aus
der Zwischenablage gelesenen Text rechnet und an A zurückschickt; A
vergleicht sie mit seiner eigenen. Der Text unterscheidet sich in jeder
Runde, damit ein Leser, der eine alte Ablage liest, *nicht* zufällig
recht behält. Das Signal geht über den Bus (`SEND`/`RECV`), der Inhalt
über die Zwischenablage — die Runde misst damit beide Wege gleichzeitig.

**b) Unberechtigter Prozess wird abgelehnt und geloggt** — **erfüllt.**
`busd` meldet einen Dienst mit `A_ROOT` an, ruft ihn als root (`vor=0`,
die Gegenprobe: derselbe Ruf geht durch), legt dann mit `setuid(1000)`
seine Wurzelrechte ab (`uid=1000`) und ruft erneut: `ruf=-3` (E_DENIED),
dazu die Zeile `bus: ABGELEHNT dienst=0 pid=5 uid=1000 regel=2` und der
Zähler `denied=1`.

**c) 1 MB über geteilten Speicher in unter 5 ms** — **erfüllt: 2683 µs.**
256 Seiten aus `mem.frame_run`, eingeblendet mit `proc.map_frame`;
kopiert wird **kein einziges Oktett**. Die gemessene Zeit ist das
Durchgehen des Megabytes durch den Empfänger. Der Inhalt wird gegen eine
vorher berechnete Summe geprüft (8 590 786 560), damit die Zahl nicht
nur schnell, sondern auch richtig ist.

**e) Benachrichtigung erscheint in der Leiste (Screenshot)** —
**erfüllt.** Bild `.systembus-shots/01-leiste-meldung.png`, dazu der
Bericht der Leiste selbst:
`taskbar: text noti x=790 base=25 ... t=Meldg 2` und
`taskbar: field noti x=786 y=7 w=72 h=26 lines=1`.
Die Meldungen kommen vom Kern (`notidemo`) und gehen denselben Weg wie
jede andere — das Bild belegt den Bus und nicht eine Zeichenroutine.

**d) Screenshot Copy im Editor → Paste im Terminal** — **NICHT
ERBRACHT.** Das ist der ehrliche Teil dieses Berichts.

---

## Was an d) fehlt, und warum

Der **Weg** ist gebaut und gemessen:

* `edit.fi` legt bei STRG-K die ausgeschnittene Zeile auf den Bus und
  fragt bei STRG-U **zuerst den Kern**;
* `sh.fi` hat den eingebauten Befehl `clip` (zeigen, setzen, `-l` für
  den Verlauf);
* dass ein Text so zwischen **zwei Prozessen** wandert, misst Abschnitt 4
  hundertmal auf vier Kernen.

Was fehlt, ist das **Bild** davon. Abschnitt 9 des Läufers tippt über den
QEMU-Monitor `edit /etc/taskbar.conf` in das Terminalfenster des
Schreibtischs. Der Klick kommt an (`taskbar: state clicks=1 acts=1`),
die Tasten kommen **nicht** in der Shell an — `edit: ready` erscheint
nie. Zwei Ursachen sind ausgeschlossen: die Maschine lebt (kein
`panic`, kein `EXCEPTION`), und `wighalt=300` hält den Schreibtisch
lange genug (der erste Versuch lief in `kernel: done`, das ist behoben).
Was übrig bleibt — Fokus des Terminalfensters, Tastenweg vom
Fensterserver in die PTY — habe ich in dieser Runde nicht mehr
auseinandergenommen. Der Läufer meldet es deshalb ROT und nicht
„übersprungen“: fünf rote Zusagen, die genau diese eine Lücke benennen.

Wer das aufnimmt: `tools/systembus/run.sh`, Abschnitt 9, und
`tools/design/drive.py` (dort sind in dieser Runde `klickauf glocke`
und `klickauf tbbtn<N>` dazugekommen).

---

## Zwei Befunde, die den Auftrag korrigieren

**1. `share.fi` ist kein geteilter Speicher.** Der Auftrag sagte „große
Daten über geteilten Speicher (share.fi)“. `kernel/share.fi` ist die
**Internetfreigabe** der Runde NETMON — Weiterleitung, NAT,
DHCP-Server. Geteilten Speicher gab es in diesem System **nicht**; er
ist in dieser Runde entstanden (`bus.seg_new` über `mem.frame_run`,
`proc.map_frame`, `PAGE_SHARED`).

**2. Eine Zwischenablage gab es schon, und sie war zu wenig.** `wig.fi`
hält seit Runde WIG 4096 Oktette bei `CLIP_OFF` mit zwei Systemrufen —
ohne Besitzer, ohne Typ, ohne Verlauf, ohne Rechtefrage. Sie bleibt
unangetastet (was sie misst, misst sie weiter) und ist der Rückfallweg,
wenn der Bus mit `nobus` aus ist. `wlibc.clip_put/clip_take` fällt
darauf zurück — und **das** ist die Gegenprobe, die zeigt, dass die neue
Ablage wirklich die neue ist.

---

## Was gebaut wurde

**Kern**

* `kernel/bus.fi` (neu, rund 1300 Zeilen): 64 Dienste, 128 Nachrichten,
  128 Abos, ein Posteingang je Aufgabe, 64 Segmente, 20 Verlaufsplätze,
  16 Benachrichtigungen, Angebot und Ziehplatz.
* `kernel/kstate.fi`: `BUS_OFF = 0xAC000`, `BUS_MAX = 0x8000`,
  `KDATA_SIZE` 0xB0000 → 0xB4000; Modusbits `M_BUS`, `M_NOBUS`,
  `M_BUSBENCH`, `M_CLIPDEMO`, `M_NOTIDEMO` (Wort 14, war frei).
* `kernel/proc.fi`: neu `map_frame` (ein **fremder** Rahmen in einen
  Adressraum) und `PAGE_SHARED` (Bit 9). `free_pt` und `page_drop` geben
  geteilte Rahmen **nicht** frei — ohne dieses Bit hätte der zweite
  Prozess nach dem Ende des ersten still in neu vergebenen Speicher
  geschrieben. `proc.reap` ruft `bus.forget_task`.
* `kernel/sys.fi`: **ein** Systemruf `SYS_OSUM_BUS = 1960` mit 22 Ops.
  Ein Zweig im Verteiler und nicht zweiundzwanzig — Runde K13 hat
  gemessen, dass dort 112 Oktette Stapel übrig waren.
* `kernel/uprog.fi`: `P_BUSA`, `P_BUSB`, `P_BUSD`, `P_BUSS`.
* `kernel/kmain.fi`: `bus.init` vor dem ersten Nutzerprozess,
  `busround()` mit den drei Läufen und den Zählern.
* `lib/libc/kcall.fi`: dieselbe Nummer (sonst rot in `tools/posix`).

**Userland**

* `kernel/user/ulib.fi` — der Bus für Terminalprogramme.
* `kernel/user/wlibc.fi` / `wlib.fi` — derselbe Satz für die Oberfläche,
  mit Rückfall auf die alte `wig`-Ablage.
* `kernel/user/sh.fi` — eingebauter Befehl `clip`.
* `kernel/user/edit.fi` — STRG-K auf den Bus, STRG-U vom Bus, und ohne
  Dateinamen gestartet öffnet er, was auf dem **Ziehplatz** liegt.
* `kernel/user/explorer.fi` — legt beim Anfassen einer Zeile den vollen
  Pfad auf den Ziehplatz *und* in die Zwischenablage (`T_PATH|T_TEXT`).
* `kernel/user/taskbar.fi` — viertes Statusfeld `noti`. Null Meldungen
  heißt **kein Feld**, nicht die Ziffer 0 (Regel der Runde STARTKNOPF).

**Werkzeuge**

* `tools/systembus/run.sh` (neu), `test.sh` Abschnitt 42,
  `tools/kernel/memmap.py` (Bereich `BUS`), `tools/design/drive.py`
  (`glocke`, `tbbtn<N>`), `docs/SYSTEMBUS.md`.

---

## Die Ein-Kern-Regel

Die Auflage war: **kein globaler statischer Puffer, den mehrere Kerne
benutzen** (die Befunde zu `fs.inode_get` und `wig.glyph_into` in
`STATUS-MERGE6.md`).

* `kernel/bus.fi` hat **keinen** `static mut` — Abschnitt 2 des Läufers
  zählt nach.
* `sys.do_bus` kopiert in einen Puffer **auf dem Stapel des jeweiligen
  Aufrufs**; der Läufer prüft, dass in dieser Funktion kein
  `state + kstate.` steht.
* Jede Funktion, die die Tafel anfasst, geht durch `take()`/`give()`.
  Der Läufer geht den Aufrufgraphen ab; die Ausnahmeliste steht im
  Prüfer selbst, mit Begründung je Name.
* Die Sperre ist eine **eigene Zelle in der Busseite**, nicht eine der
  acht aus `kstate.LOCK_OFF`: deren Zähler werden in `tools/smp` und
  `tools/multicore` gemessen, und eine neunte Nutzerin hätte
  `lock_total_spins` verschoben.
* Über `copy_in`/`copy_out` wird die Sperre **nicht** gehalten (die
  können einen Seitenfehler auslösen). Erst holen, dann sperren.

---

## Offen

* **d) fehlt als Bild** (siehe oben). Der Weg ist da, der Beweis per
  Screenshot nicht.
* **`tools/themestore/run.sh` nicht zu Ende gelaufen.** Auf dieser
  Maschine liefen während der Messungen bis zu 28 QEMU-Instanzen anderer
  Runden gleichzeitig; der Lauf steht seit über zwanzig Minuten in
  Abschnitt „Laden ohne Konto“. Ein Zwischenstand ohne Endzahl ist keine
  Abnahme, deshalb steht hier keine. Derselbe Grund hat einen
  posix-Lauf auf 50/79 gedrückt — allein nachgefahren: **134/0**.
* `clipdemo` ist als Wort auf der Befehlszeile vorgesehen und tut noch
  nichts.
* Kein Blockieren: `RECV` gibt sofort `-5`, wer warten will, gibt ab und
  fragt wieder. Ein Wartepunkt (`cap.K_PORT` gibt es schon) wäre die
  nächste Runde.
* Verzögerte Übergabe ist gebaut (`OFFER`/`FILL`/`-6`), aber noch von
  keinem Programm benutzt.

---

## Zwei Fallen der Sprache, für die nächste Runde

* `var s: [u8; N] = "…\0"` — **N muss genau die Zahl der Zeichen
  einschließlich der Null sein.** Vier Fehlschläge dieser Runde.
* `0 - e` ist eine **geprüfte** Subtraktion und lässt den Kern beim
  ersten Fehlercode sterben (`panic: integer overflow in 'u64 - u64'`).
  Richtig ist `0 -% e`.
* `*(p) as u64` parst als `*((p) as u64)`. Richtig: `(*(p)) as u64`.
