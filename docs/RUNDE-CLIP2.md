# RUNDE CLIP-2 — S-002: das Ziel einer Ziehbewegung

**Zweig `runde-clip2` auf `main` `2f37b74d`. Gemessen am 18.09.2026.
Läufer `tools/clip2/run.sh`: 32 grün / 0 rot.**

---

## Was in der Offenliste stand, und was wirklich war

`S-002` sagte:

> „Drag-and-Drop: kein Ziel — `drag_put` (Quelle) existiert, und
> `drag_take`/`drag_an`/`drag_drop` stehen inzwischen in `wlib`
> (`:7383-7393`) und `ulib` (`:943-966`). Genommen wird nur im Editor
> (`edit.fi:1421`); der Dateimanager hat weiterhin kein Drop-Ziel
> (`explorer.fi:2218` nennt `drag_take` nur im Kommentar)"

**Der erste Teil stimmt. Der zweite war zu kurz gegriffen — aber diesmal
in die ANDERE Richtung als bei `P-002` und `P-005/P-006`.** Dort lag
mehr im Baum als die Liste behauptete. Hier lag WENIGER: es fehlte nicht
nur ein Aufruf im Dateimanager, es fehlten **zwei Nähte in der
Bibliothek**, und ohne sie kann kein Programm dieses Systems ein
Ablegeziel sein.

### Die Bestandsaufnahme, Glied für Glied

| Stelle | Was dort wirklich stand |
|---|---|
| `kernel/bus/bus.fi:1119-1184` | `drag_set`/`drag_get`/`drag_types`/`drag_active`/`drag_clear` — der Bus ist **vollständig** |
| `kernel/sys/sys.fi:2048-2051` | `BUS_DRAGSET/GET/CLEAR/INFO` = 15..18 — die Aufrufe **stehen** |
| `kernel/user/wlibc.fi:2149-2167` | die vier Durchreichungen — **stehen** |
| `kernel/user/wlib.fi:7775-7788` | dieselben vier, über die Bibliothek — **stehen** |
| `kernel/user/ulib.fi:1057-1081` | dazu `drag_type_path` — **steht** |
| `kernel/user/explorer.fi:2763` | `ziehen()` ruft `drag_put` — die **Quelle steht** |
| `kernel/user/edit.fi:1421` | der Editor nimmt beim Start — das **Vorbild steht** |

**Was fehlte, war nichts davon.** Es fehlte:

1. **Die Meldung beim Loslassen.** `wlib.on_up` (vorher `:6048`) kannte
   das Loslassen, gab es aber an **kein** Programm weiter. Schlimmer:
   der Rumpf stieg bei `if s_down != 0` sofort aus — und `s_down` ist
   bei einer Ziehbewegung, die in einem **anderen** Fenster angefangen
   hat, null. Ein Dateimanager konnte vom Ablegen also gar nichts
   erfahren, ohne `wlibc` an `wlib` vorbei zu rufen (und damit an
   `noclip` vorbei).

2. **Die Meldung beim Anfangen.** Das kam erst durch die MESSUNG heraus
   und ist der eigentliche Fund dieser Runde — siehe unten.

---

## Der Fund, den erst die Messung gebracht hat

Nach der ersten Naht (`K_DROP`) lief der Läufer, und der Zug wurde
gefahren — aber es wurde **nichts abgelegt**. Die serielle Leitung sagte
warum:

```
explorer: sel n=2 anker=2 rahmen=1
explorer: sel n=3 anker=2 rahmen=2
```

**`rahmen=2`, und kein einziges `expl: zieh`.** `wlib.on_move` deutete
die Bewegung als **Mausrahmen** (Punkt 3 der Runde EXPLORER-2) — die
Auswahl wuchs, der Ziehplatz blieb leer, und `on_up` fand beim
Loslassen folgerichtig nichts vor.

Der Grund liegt im Dateimanager: **`ziehen()` hing am Doppelklick.**
`explorer.fi:2488` ruft es in `K_LIST`, also aus `open()` heraus. Ein
echtes Ziehen — drücken, fahren, loslassen — kam dort nie an. Der Pfad
landete nur dann auf dem Bus, wenn jemand die Datei **öffnete**.

Deshalb hat diese Runde eine **zweite** Naht: `K_DRAG`. Wer mit
gedrückter Taste eine Zeile verlässt, bekommt **einmal je Zug** eine
Meldung, und das Programm entscheidet, was auf den Bus kommt — die
Bibliothek kennt keine Dateipfade.

Ohne die Messung wäre diese Runde mit „Drop-Ziel gebaut" abgeschlossen
worden, und Drag-and-Drop hätte weiterhin nicht funktioniert.

---

## Was gebaut wurde

### `kernel/user/wlib.fi`

| Stelle | Was |
|---|---|
| `:345` | `const K_DROP = 18` — die Meldung „hier wurde abgelegt" |
| `:362` | `const K_DRAG = 19` — die Meldung „hier fängt ein Zug an" |
| `:4036` | `drop_an(bool)` — ein Fenster meldet sich als Ziel an |
| `:4051` | `drag_starts()` / `drop_count()` — Zähler für die Abnahme |
| `:6142` | `fire(d, K_DROP, zeile, w)` in `on_up` — **vor** der `s_down`-Frage |
| `:6292` | `fire(dd, K_DRAG, …)` in `on_move` — statt des Mausrahmens |

Zwei Entscheidungen, die im Quelltext begründet stehen:

* **Die Frage nach dem Ziehplatz kommt VOR `s_down`.** Eine
  Ziehbewegung zwischen zwei Programmen kennt kein gemeinsames `wlib` —
  gefragt wird der **Bus** und kein Zustand der Bibliothek.
* **Ohne `drop_an` passiert nichts.** Ein Programm, das mit einer
  fremden Ziehbewegung nichts anfangen kann, zieht weiter seinen
  Mausrahmen und merkt von alledem nichts — dieselbe Regel wie bei
  `sel_an`. Genau das prüft die Gegenprobe.

### `kernel/user/explorer.fi`

| Stelle | Was |
|---|---|
| `:2336` | `wlib.drop_an(true)` — der Dateimanager ist Ziel |
| `:2516` | `K_DRAG` → `ziehen(idx)`, legt den Pfad auf den Bus |
| `:2528` | `K_DROP` → `ablegen(...)` für Tabelle **und** Baum |
| `:2859` | `ablegen()` — die Ablegefunktion |

**Wohin abgelegt wird:** auf einen **Ordner** in der Tabelle → in diesen
hinein; auf eine **Datei** oder ins Leere → in den **angezeigten**
Ordner. Auf eine Datei zu zielen und sie zu treffen wäre ein Fehlgriff
mit Folgen.

**Verschoben wird, nicht kopiert** — über `expakt.einfuegen`, also
dieselbe Funktion wie Strg+V, also `dateiop.verschiebe` → `io.rename`
(`P-018`: der Verzeichniseintrag wird umgehängt, die Oktette werden
nicht angefasst).

---

## Der zweite Fehler, den die Messung gefunden hat

Der erste Entwurf von `ablegen()` rief `expakt.copy_remember(false)` —
und `einfuegen` nimmt ohne `ist_schnitt` den Zweig `dateiop.kopiere`
(`expakt.fi:505`). Die Platte danach:

```
da /data/alpha.txt        ino=105
da /data/bilder/alpha.txt ino=116      <- eine ZWEITE Datei
inode anders 104 116
```

**Die Datei lag zweimal da.** Von außen — und auf jedem Bildschirmfoto —
sieht das wie ein gelungenes Verschieben aus. Der Läufer hat es
gefunden, weil er die **Inodenummer** vergleicht und nicht das Bild.
Behoben mit `copy_remember(true)`.

---

## Die Messung

`bash tools/clip2/run.sh` — eine Maschine, ein Drehbuch mit **echten
Maus-Ereignissen** (`ziehvon`: drücken, in acht Schritten fahren,
loslassen), serielle Leitung gegen die Erwartung, und das
**Plattenabbild danach vom Wirt gelesen** (`tools/clip2/lies.py`, auf
dem Leser aus `tools/fsrobust/check.py`).

### Die Kette, wie sie auf der Leitung steht

```
expl: zieh /data/notizen
explorer: drops 1
expl: drop /data/notizen q=/data gleich
expl: zieh /data/alpha.txt
explorer: drops 2
expl: drop /data/alpha.txt q=/data/bilder
expl: drop* rc=0 z=0
```

### Die fünf Punkte

| # | Was | Ergebnis |
|---|---|---|
| 1 | **Die Naht.** `wlib` meldet `K_DROP` | **3 Ablegungen** gemeldet |
| 2 | **Die Tat.** alpha.txt auf `bilder` gezogen | `weg /data/alpha.txt`, `da /data/bilder/alpha.txt`, `rc=0` |
| 3 | **Die Inode.** verschoben ≠ kopiert | **`inode gleich 105`**, `inhalt ok eins` |
| 4 | **Das Ziel ohne Ordner.** auf eine Datei abgelegt | landet im angezeigten Ordner |
| 5 | **Der Leerlauf.** Ablegen im selben Ordner | `gleich`, kein Dialog, `notizen` unverändert |

Die dritte Zahl, unabhängig von beidem: der Dateimanager selbst meldet
`explorer: cd /data n=8` **vorher** und `n=7` **nachher**, und
`/data/bilder` geht von 2 auf `n=3`.

### Die Gegenprobe — und dass sie wirklich misst

Runde `O-GRUNDLINIE-2` hat dreizehn Gegenproben gefunden, die **nichts**
gemessen haben. Diese hier prüft deshalb zuerst, dass sie **greift**:

1. die Zeile, die entfernt wird, **muss vorher da sein** — geprüft;
2. der Bau **muss danach durchlaufen** — geprüft;
3. der Dateimanager **muss hochkommen** — geprüft (`explorer: ready`);
4. **erst dann** zählt, dass nichts abgelegt wurde.

Mit `drop_an(false)`, bei **identischem Drehbuch** (dieselben Züge
wurden gefahren, `drehbuch fertig, fehler=0`):

```
OK  GEGENPROBE: ohne drop_an meldet wlib kein Ablegen
OK  GEGENPROBE: ohne drop_an legt der Dateimanager nichts ab
OK  GEGENPROBE: alpha.txt blieb in /data
```

Der Läufer stellt den Quelltext über ein `trap` zurück — auch bei
Abbruch. (Gelernt am 18.09., zweimal: nach einem `pkill` blieb
`drop_an(false)` stehen, und der nächste Lauf hätte die Gegenprobe
statt der Sache gemessen.)

---

## Zwei Dinge am Messaufbau, die vorher falsch waren

**1. `uitrace=yes` fehlte.** Der Dateimanager gattert seine ganze
Diagnose hinter `s_dbg` (`explorer.fi:309`), und das schaltet
`/etc/uitrace` ein. Ohne den Schalter kam **kein** `explorer: ready`,
**kein** `rect` — der Läufer fand seine Rechtecke nicht und meldete
„KEIN RECHTECK GEMELDET". Das ist **kein** Fehler dieser Runde: gegen
sauberes `main` (alle Änderungen gestasht) verhält es sich genauso.

**2. Die Inode von „vorher" kam aus dem falschen Abbild.**
`capture.sh` baut **je Aufruf** ein eigenes Abbild (`mkfs.py` mit
`--time=$(date +%s)`) und vergibt dabei andere Inodenummern. Der
Vergleich meldete deshalb „inode anders 104 105" für eine Datei, die
sauber umgehängt worden war. Neu: `vorherbild=ja` legt in `capture.sh`
eine Sicherung des Abbilds **vor dem Start** an, und gemessen wird
gegen die.

---

## Werkzeuge, die dazugekommen sind

| Datei | Was |
|---|---|
| `tools/clip2/run.sh` | die Abnahme, 32 Punkte, mit Gegenprobe |
| `tools/clip2/lies.py` | liest das Abbild vom Wirt: Pfad, Inode, Inhalt |
| `tools/design/drive.py` | neuer Drehbuchbefehl `ziehvon <quelle> <ziel>` — von der Mitte eines gemeldeten Rechtecks in die Mitte eines zweiten |
| `tools/design/capture.sh` | neuer Schalter `vorherbild=ja` |

`ziehvon` fehlte wirklich: `zieheauf` greift die **Ecke** und zieht um
einen Versatz, `ziehespur` bleibt in **einem** Rechteck. Für „Zeile 2
auf Zeile 0" braucht es zwei gemeldete Kästen.

---

## Stand von S-002

**Erledigt und gemessen.** Der Dateimanager ist Quelle **und** Ziel;
abgelegte Dateien kommen im Zielordner an, mit derselben Inode und
demselben Inhalt.

**Was diese Runde NICHT gebaut hat, und das steht hier statt hinterher:**

* **Keine Ziehgrafik unter dem Zeiger.** Dieses System hat keine (siehe
  `explorer.fi:2485` und `edit.fi:1409` — dort steht es seit RUNDE
  SYSTEMBUS ausgeschrieben). Wer zieht, sieht den Zeiger und das
  Ergebnis, nicht das Stück unterwegs.
* **Kein Ablegen auf der Ortsleiste und keins auf dem Schreibtisch.**
  Der Baum nimmt an (immer in den angezeigten Ordner), die Ortsleiste
  nicht: ein Ort ist ein Sprungziel und kein Ordner, den dieser Zweig
  kennt.
* **Kein Ziehen zwischen zwei Fenstern desselben Dateimanagers** —
  gebaut ist es dafür (der Bus trägt es), gemessen ist es **nicht**.
* **Kein Kopieren-statt-Verschieben mit Strg.** Abgelegt wird immer
  verschoben.

