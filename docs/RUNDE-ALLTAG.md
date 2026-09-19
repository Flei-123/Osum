# Runde ALLTAG — Ausschalten, Ziehen, Reiter, Zeilennummern

**Zweig:** `alltag-explorer` · **Stand:** 19.09.2026 · **Grundlage:** `main` (2f37b74d)

Vier Punkte aus Justins Offenliste, alle „sichtbar für den Menschen":
der Ausschalt-Knopf, Drag-and-Drop im Dateimanager, Reiter im
Dateimanager, und ein Editor, der mehr kann als `nano`.

Was hier steht, ist **gemessen**. Wo etwas nicht erreicht wurde, steht es
als nicht erreicht da, mit der Messung, die es zeigt.

---

## 0. Was zuerst nachgesehen wurde — und was dabei herauskam

Der Auftrag nannte Zeilennummern (`wlib:7383`, `explorer.fi:2218`,
`edit.fi:1421`) und beschrieb einen Zustand. Beides stimmte nicht mit dem
überein, was im Arbeitsbaum lag. **Vor der ersten Änderung nachgemessen:**

| | Behauptung im Auftrag | Gemessen |
|---|---|---|
| Arbeitsbaum | — | stand auf Zweig `feedback`, Stand 29.08. |
| `explorer.fi` | 1736 Zeilen | **3943** auf `main` |
| `wlib.fi` | Zeile 7383 | Datei hatte 3215 Zeilen; auf `main` 7805 |
| Taskleiste | `taskbar.fi` | im Baum hieß sie `leiste.fi`; auf `main` `taskbar.fi` |
| P-003 Ausschalten | „GUI fehlt" | **fertig** seit `c0e4beed`, liegt auf `main` |
| S-002 Drag-and-Drop | „Explorer nicht angeschlossen" | **gebaut** in `f1e38aa2`, lag unvermischt auf `runde-clip2` |

Der Auftrag beschrieb also einen Stand von vor drei Wochen. Hätte ich
losgebaut, hätte ich `f1e38aa2` ein zweites Mal geschrieben — und dabei
die zwei Fehler wiederholt, die dort erst die Messung gefunden hat.

**Deshalb die erste Handlung dieser Runde: nachsehen und rückfragen, nicht bauen.**

### Die Werkzeugkette war kaputt

`vendor/firn/bin` und `lib` gehörten zu einem **anderen** Commit als
`vendor/firn/COMMIT` verlangt (`.gebaut` sagte `a751b3db`, verlangt war
`7b4c22b1`). Neu bauen ging nicht: der gepinnte Firn-Commit ist auf
GitHub **weg** (`upload-pack: not our ref`) und in `/root/firn` nicht
vorhanden.

Gefunden hat es `/root/osum-w-bild/vendor/firn/` — **genau dieser Pin**,
mit gültiger `.gebaut`-Marke und vollständigem `lib/fui` (16 Dateien).
Von dort übernommen; die alten liegen als `lib.alt-a751b3db` daneben.

> **Falle für die nächste Runde:** die `fui` aus `/root/firn-ra`,
> `-xmm` oder `-ton` ist **zu neu** und bricht mit
> `wave2 has no element tooltip_place` / `outline_at not exported by ttf`.

---

## 1. (a) P-003 — der Ausschalt-Knopf

**Nicht gebaut, sondern belegt.** Er ist seit Runde ENERGIE (`c0e4beed`,
13.09.) auf `main`; `git merge-base --is-ancestor c0e4beed main` bestätigt
es. Ihn ein zweites Mal zu bauen hätte eine zweite Wahrheit neben
`init.shutdown` gestellt.

Fünf Bilder, ein Lauf (`belege/alltag/a-energie/`):

| Bild | Was darauf steht |
|---|---|
| 01 | Schreibtisch, Taskleiste, Uhr — die Maschine läuft |
| 02 | Startmenü nach Super, Knopf **Power** unten links |
| 03 | Energiemenü: **Shut down / Restart / Sign out** |
| 04 | Rückfrage „Really shut down the computer?" — der Fokus (oranger Ring) liegt auf **Cancel**, nicht auf der Tat |
| 05 | nach Flucht: Menü zu, Maschine läuft weiter |

**Nicht erreicht:** Die Protokollzeilen (`energie auf`, `energie wahl=`,
`energie tat`) schreibt dieser Stand **nicht** — alle sieben gesuchten
Muster kamen leer zurück. Der Beleg ist das Bild, nicht die Textzeile.

---

## 2. (b) S-002 — die Ortsleiste nimmt an, und der Papierkorb auch

`runde-clip2` gemerged (1 Commit, 0 dahinter, konfliktfrei). Der Zweig
hatte die Ortsleiste **ausdrücklich ausgenommen**: „ein Ort ist ein
Sprungziel und kein Ordner". Das stimmt für den Sprung und nicht für die
Sache — hinter jedem Ort steht ein Pfad, und ein Pfad ist ein Ordner.

**Gebaut** (nur `explorer.fi` und `exporte.fi`; `wlib` nur gelesen):

* `exporte.place_is_trash(i)` — fragt den **Pfad** (`trash.korb_von`),
  nicht den übersetzten Text. Eine Abfrage auf „Trash" wäre in der
  nächsten Sprache still falsch.
* `exporte.place_droppable(i)` — Überschriften und Datenträger nehmen nichts an.
* `explorer.ablegen_ort` — Papierkorb über `expakt.in_korb` (schreibt die
  `.info` mit, also umkehrbar), jeder andere Ort über denselben Weg wie
  die Tabelle.
* `explorer.ablegen_pfad` — der gemeinsame Rumpf. Zwei Kopien derselben
  zwanzig Zeilen wären zwei Orte für jeden Fehler darin.
* `zieh_ziel_an`/`aus` — die Statuszeile sagt, **was** gezogen wird.

**Gemessen im laufenden System** (`belege/alltag/b-ziehen/`), mit `ls` in
der Shell, vorher und nachher, im selben Boot:

```
vorher   /data        alpha.txt beta.txt gamma.txt delta.txt
                      epsilon.txt zeta.md bilder/ notizen/
         /data/bilder rot.ppm blau.ppm

  alpha.txt -> Ordner bilder (Tabelle)   expl: drop* rc=0
  beta.txt  -> Ort "Pictures"            expl: droport rc=0
  zeta.md   -> Papierkorb                explorer: trash rc=0 id=1

nachher  /data        gamma.txt delta.txt epsilon.txt bilder/ notizen/
         /data/bilder rot.ppm blau.ppm alpha.txt beta.txt
         /.papierkorb 1  1.info
```

`1.info` ist der Unterschied zwischen wegwerfen und löschen: sie trägt
den Herkunftspfad, `trash.back` kann es zurückholen.

> **Das Plattenabbild vom Wirt zu lesen misst hier NICHTS.** Die Wurzel
> kommt als `-initrd`, also als RAM-Platte; `pruef/root.img` ist nach
> drei Verschiebungen Oktett für Oktett dasselbe wie vorher.

**Nicht erreicht, mit Grund:**

* **Keine Ziehgrafik unter dem Zeiger, keine Ziel-Hervorhebung während
  der Fahrt.** Ein Programm erfährt von einer Ziehbewegung genau zweimal
  etwas — `K_DRAG` beim Verlassen der Zeile, `K_DROP` beim Loslassen. Die
  Bewegung dazwischen bleibt in `wlib.on_move`. Ein Bild, das dem Zeiger
  folgt, bräuchte jede Zwischenlage und ließe sich nur in `wlib` malen —
  und `wlib` gehört in dieser Runde einem anderen Arbeiter. Was ohne
  fremden Code geht, ist gebaut: die Statuszeile zeigt „Ziehe: alpha.txt"
  (auf Bild 06 von `c-reiter` zu sehen).

---

## 3. (c) Reiter im Dateimanager

`explorer.fi` hatte **keinen einzigen** Reiter (die Treffer auf `tab_`
waren die Dateitabelle). Gebaut auf dem vorhandenen `wlib.K_TABS` —
benutzt, nicht geändert.

Ein Reiter ist **ein Pfad**. Kein zweites Modell, kein zweites Fenster.
Beim Wechsel wird `pfad` getauscht und neu gelesen — derselbe Weg, den
`place_walk` und `tree_walk` seit jeher gehen.

**Gemessen** (`belege/alltag/c-reiter/`, ein Boot, sieben Bilder):

| Schritt | Meldung |
|---|---|
| Start | 1 Reiter, beschriftet „data" |
| Strg+T | `reiter 2 a=1` |
| Ordner wechseln | Reiter 2 zeigt `/data/bilder`, Reiter 1 weiter `/data` |
| Klick auf Reiter 1 | `reiter 2 a=0`, der Inhalt wechselt mit |
| Datei auf Reiter 2 ziehen | `reiter 2 a=1` — Brosamen, Tabelle und Statuszeile zeigen alle `/data/bilder` |
| Strg+W | `reiter 1 a=0` |
| Strg+W nochmal | `reiter letzt` — **Gegenprobe**, der letzte bleibt |

### Drei Funde, und der dritte hat die Runde aufgehalten

1. **Ein Widget ohne `box_*` wird nie gemalt.** Der erste Entwurf lag
   zwischen zwei `box_end()` — es entstand, wurde gezählt und erschien
   nicht. Gemessen: `explorer: rect` meldete id=21..25 und **kein id=20**.
2. **Zwei Reiter hießen beide „data".** Strg+T öffnet im selben Ordner.
   Jetzt steht die Nummer davor: „1 data", „2 bilder".
3. **`K_DROP` sagt nicht, auf welchem Reiter abgelegt wurde.**
   `wlib.on_up` rechnet die Zeile unter dem Zeiger **nur** für `K_LIST`
   und `K_TABLE` aus (`wlib.fi:6136`); jedes andere Widget bekommt
   `MAXWD`. Das Ablegen **kam an** — gemessen `dropziel id=20 r=20` —,
   aber `reiter_wechsel(MAXWD)` stieg sofort wieder aus. Von außen sah es
   aus, als käme gar nichts an. Die Nummer wird jetzt mit
   `wlib.tab_x`/`tab_w` und `wlib.win_cx` nachgerechnet — denselben
   Funktionen, die wlib für den **Klick** benutzt.

---

## 4. (d) Der Editor: Zeilennummern und Statuszeile

`edit.fi` ist ein **Terminal**-Editor (`import ulib`, `tools`; kein
`import wlib`; Ausgabe über VT100-Fluchtfolgen). Was in einem Terminal
geht, ist gebaut:

* **Nummernspalte**, rechtsbündig, Breite **wächst mit der Datei** (zwei
  Stellen bei 12 Zeilen, fünf bei 1000). Fest wäre entweder
  verschwendeter Platz oder eine abgeschnittene Nummer — G-010.
* **Statuszeile** `Z 1/12  S 1  UTF-8  gesichert`, rechtsbündig, damit
  die Zahlen beim Tippen nicht springen.
* **Strg-P** schaltet die Spalte um; die Tastenzeile sagt „^P Numbers".

**Drei Stellen, nicht eine:** die Nummer muss in `draw`, in `draw_line`
**und** in `place` stehen. Fehlt sie in `draw_line`, verschwindet sie
genau in der Zeile, in der geschrieben wird; fehlt sie in `place`, steht
der Schreibzeiger mitten in der Nummer.

**Warum Strg-P und nicht Strg-N:** 14 ist schon die Pfeiltaste nach oben
der PS/2-Tastatur (`key`, seit Runde K6). Der Zweig `k == 14` im
Tastenblock wird **nie** erreicht — der erste Entwurf hatte ihn trotzdem,
und auf dem Bild sah es aus, als täte die Taste nichts.

**Gemessen**, Zelle für Zelle aus dem Bildschirmfoto (8×16 je Zeichen,
`belege/alltag/d-editor/`). Bildzeile 10 trägt den Text „zehn":

```
mit Nummern          XX.XXXX     "10" + Trennspalte + "zehn"
nach Strg-P          XXXX        "zehn" ab Spalte 0
nach Strg-P zurück   XX.XXXX
```

---

## 5. (e) Syntaxhervorhebung — NICHT ERREICHT

Und der Grund ist gemessen, nicht geschätzt: **die Textkonsole kennt von
SGR nur 0 und 7.** `kernel/drv/con/ansi.fi` schreibt es im Kopf selbst
aus: „WAS SIE NICHT KANN: Farben (SGR 30..47), Rollbereiche, alternative
Schirme."

Der Rahmenpuffer **könnte** es — `fb.set_color(state, fg, bg)` nimmt
Vorder- und Hintergrundfarbe, und `apply_color` setzt sie bei jedem
Umschalten schon. Es fehlt genau ein Zweig im Fluchtfolgenleser
(`ansi.fi`, bei `final == 109`, neben den vorhandenen `v == 0` und
`v == 7`).

Das ist **Kerncode** und gehört nicht in diese Runde. Es ist der nächste
sinnvolle Schritt und in einer knappen Stunde zu haben.

**Ebenfalls nicht gebaut: Reiter im Editor.** Sie gehören zur selben
Runde wie die Farben und brauchen dieselbe Vorarbeit.

---

## 6. (f) Das Design-Urteil, mit Bildern und Zahlen

### Was gut ist — und das ist gerechnet, nicht gefühlt

**Der Kontrast.** Nach WCAG 2.1 aus den Bildpunkten des Abzugs gerechnet
(`belege/alltag/f-design/messung.txt`). Verlangt sind **4,5:1**:

| Bereich | gemessen |
|---|---|
| Tabellenzeile | 17,05:1 |
| Ortsleiste | 17,05:1 |
| Statuszeile | 14,93:1 |
| aktiver Reiter | 14,93:1 |
| Menüleiste | 12,78:1 |
| Tabellenkopf | 10,14:1 |
| inaktiver Reiter | 9,01:1 |
| Brosamenleiste | 8,65:1 |

Der schwächste Wert hat fast das Doppelte des Verlangten. Das ist eine
echte Stärke dieser Oberfläche und steht hier, damit sie beim nächsten
Farbwechsel nicht unbemerkt verlorengeht.

**Die Klickflächen** sind einheitlich: Symbolknöpfe 28×28, Brosamen
60×28, alles auf demselben Raster mit 2 Bildpunkten Abstand.

### Was schlecht war — und behoben ist

**Die fünf Symbolknöpfe der Werkzeugleiste waren leer.** Gemessen an der
Zahl der verschiedenen Farben je Knopf:

```
ohne /lib/icons.ttf   [1, 1, 1, 1, 1]        eine Farbe = nichts drin
mit  /lib/icons.ttf   [12, 10, 10, 17, 10]
```

Zum Vergleich: der beschriftete Knopf „Start" daneben hatte immer 19.

**Die Ursache lag nicht im Dateimanager, sondern im Messaufbau:**
`tools/k15/build.sh` legt `mono.ttf` und `sans.ttf` ins Abbild, aber
nicht `osum-icons.ttf`. `tools/usbimg/build.sh` tut es längst (`:745`).
Ohne die Datei findet `wlib.icon_button` seine Zeichen nicht und malt
nichts — **ohne eine Zeile Fehlermeldung**. Genau die Sorte Fehler, die
nur auf einem Bild auffällt.

Vorher/nachher: `belege/alltag/f-design/01-ohne-symbolschrift.png` gegen
`02-mit-symbolschrift.png`.

### Was schlecht ist und offen bleibt

* **Das Energiemenü stößt unten an den Schirmrand** — „Sign out" sitzt
  auf der Kante der Taskleiste (Bild 03 von `a-energie`). Gehört zu
  G-006/G-010.
* **Die Oberfläche ist englisch**, obwohl `locale/de` im Abbild liegt.
  Das ist keine Kleinigkeit für ein System, dessen Quelltext durchgehend
  deutsch ist.
* **Die Spalten „Size" und „Time" zeigen fast nur `--`.** Eine Spalte,
  die nie etwas zeigt, ist verschwendete Breite.
* **Das Terminalfenster deutet keine Fluchtfolgen** (siehe unten).

---

## 7. Die Abnahme — keine Regression

| Abschnitt | vorher | nachher |
|---|---|---|
| `tools/clip2/run.sh` (misst S-002) | 32/0 (Titel von `f1e38aa2`) | **grün 32, rot 0** |
| `tools/k11/run.sh` (misst den Editor) | 85 (GRUNDLINIE.md) | **85 passed, 0 failed** |

Bemerkenswert an clip2 ist Abschnitt 6, weil er die eigentliche Zusage
prüft und nicht das Bild: nach dem Ziehen liegt `alpha.txt` in
`/data/bilder`, hat **dieselbe Inodenummer 105** und denselben Inhalt —
umgehängt mit `io.rename`, nicht kopiert. Die Gegenprobe (Bau ohne
`drop_an`) fällt weiterhin korrekt durch.

An k11 sind die zwei Zusagen bemerkenswert, die die Nummernspalte hätte
brechen können: der Kopfbalken mit dem Dateinamen und der Zeilenvergleich
zwischen seriellem Mitschnitt und echtem Bildschirmfoto.

---

## 8. Was der Messaufbau gekostet hat — für die nächste Runde

**Die Tastatur ist DEUTSCH, QEMUs Tastennamen sind US.**

```
sendkey slash  ->  MINUS        aus `ls /data` wurde `ls -data`
sendkey minus  ->  ß            und das listete die Wurzel
shift-dot      ->  :            shift-comma -> ;     backslash -> #
```

In `pruef/klick.py` steht jetzt die deutsche Belegung (`/` = `shift-7`).

**Das Zeichen `>` ist über den Monitor gar nicht erreichbar.** Gemessen
mit `pruef/db-taste.py`, das jeden Kandidaten einzeln schickt und auf der
Leitung nachliest:

```
greater  shift-greater  less  shift-less  0x56  shift-0x56
   -> ALLE: kein einziges Tastenereignis kommt an
```

QEMUs USB-Tastatur schickt den Scancode `0x56` überhaupt nicht. **Eine
Umlenkung lässt sich deshalb nicht tippen:** `echo eins > /data/t1.txt`
wurde zu `echo eins  /data/t1.txt`, die Shell schrieb beide Wörter auf
den Schirm, `echo` meldete **rc=0** — und die Datei entstand nie. Das
sah von außen wie ein kaputtes Dateisystem aus.
→ Testdateien beim **Bau** ins Abbild legen, wie `tools/k11/run.sh:168`.

**Das Terminalfenster deutet keine Fluchtfolgen.** `edit` malt mit
VT100-Folgen; die Konsole versteht sie, das Fenster nicht — auf dem Bild
steht `[?25l[1;1H[7m` als Text. **Vorbestehend, nicht aus dieser Runde:**
`git diff --name-only main..HEAD` nennt unter `kernel/` genau drei
Dateien — `explorer.fi`, `exporte.fi` und `wlib.fi` (letztere nur über
den Merge). Der Editor wird deshalb auf der Konsole gemessen
(`pruef/schuss-konsole.py`), wie k11 es auch tut.

**Weitere Fallen:**

* Ein Zug muss die angefasste **Zeile verlassen**, sonst feuert `wlib`
  kein `K_DRAG`. Ein Zug von y=261 nach y=258 ist kein Zug.
* `wm: fen` meldet den **Fensterrahmen**, Widget-Rechtecke sind
  **inhaltslokal** — dazwischen liegen 25 Bildpunkte Titelzeile. Ohne den
  Versatz landet jeder Zug 25 Bildpunkte zu hoch, ohne Fehlermeldung.
* Die serielle Leitung **zerschneidet Zeilenanfänge** (Tastendiagnose
  mischt sich ein): gemessen `keeyx: p^lTo\nrer: reiter 2 a=1`. Beim
  Suchen nicht auf den Zeilenanfang verlassen.
* `tools/k15/build.sh` baut mit **4096 Blöcken = 2 MiB**; der Explorer
  wiegt mit fUi allein 1,6 MB → `mkfs: the disk is full`. Eigene Fassung
  mit 24576 Blöcken unter `tools/k15/lokal/` (nicht eingecheckt).

---

## 9. Neue Werkzeuge

| Datei | Was |
|---|---|
| `pruef/schuss.py` | hält die Maschine **offen**, ein Drehbuch klickt und fotografiert Schritt für Schritt |
| `pruef/schuss-konsole.py` | dasselbe **ohne** Fensterserver, für Terminalprogramme |
| `pruef/db-energie.py` | (a) der Weg zum Ausschalten |
| `pruef/db-ziehen-pruef.py` | (b) drei Züge, mit `ls` vorher und nachher |
| `pruef/db-reiter.py` | (c) Strg+T, Klick, Ziehen, Strg+W, Gegenprobe |
| `pruef/db-taste.py` | welche QEMU-Taste gibt welches Zeichen |

`pruef/oneshot.py` fuhr genau einen Ablauf und beendete die Maschine
danach; für eine Runde mit mehreren Schritten je Boot reichte das nicht.
