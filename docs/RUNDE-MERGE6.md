# Runde MERGE-6 — vier fertige Zweige zu einem Stand

*05.09.2026 · Arbeitsbaum `/root/osum-merge6`, Zweig `merge6`, aus `hidweg` 1493451 („VIELKERN 2/n")*

Zusammengeführt, in dieser Reihenfolge:

| # | Zweig | Commit | was er bringt |
|---|---|---|---|
| 1 | `vielkern3` | f1f7420 | KSTACK\_CUR je Kern, Zeilensperre, der Inodepuffer unter `atomic.L_FS`, Ring 3 auf **allen** Kernen |
| 2 | `design` | b90c110 | Design-Marken (Schrift, Höhe, Zeit), 4er-Raster, Taskleiste und Schreibtisch auf `wlib` |
| 3 | `werkzeug` | 932be3a | `/bin/taskmgr`, Kontrollzentrum, 62 Dateien, +4275 Zeilen |
| 4 | `laden` | d73336c | App-Store mit echten `.opk`-Paketen |

Nicht nach GitHub gepusht. Die vier Quellbäume wurden nicht angefasst;
für die Vergleichsmessungen liefen eigene, abgekoppelte Arbeitsbäume
(`/tmp/m6-ref` auf `design`, `/tmp/m6-wzref` auf `werkzeug`).

---

## 0. Das Ergebnis in einem Satz

**`merge6` ist noch nicht reif, `hidweg` zu ersetzen.** Die vier Gewinne
sind alle da und einzeln nachgemessen, und das Zusammenführen hat
sieben Fehler zutage gefördert, von denen sechs behoben sind. Der
siebte — eine Glyphenbühne, die der ganzen Maschine gehört — bringt in
**einem von fünf Läufen** mit vier Kernen ein Ring-3-Programm um. Das
ist zu viel für einen Stand, der die Grundlinie werden soll.

---

## 1. Die Abnahme, Punkt für Punkt

| Auflage aus dem Auftrag | Ergebnis | wo |
|---|---|---|
| `./test.sh` grün | siehe Abschnitt 7 | `/tmp/m6-testsh.log` |
| `tools/themestore/run.sh` grün, Kontraste ≥ 4,5 / ≥ 3,0 | **81 Zusagen, 0 Fehler** | Abschnitt 2 |
| 4er-Raster: 92 % dürfen nicht abrutschen | **92 % (691 von 744)** — Zahl für Zahl wie in der Design-Runde | Abschnitt 3 |
| `/bin/taskmgr` startet, Prozesse, „Beenden", Graphen, Bild | teilweise — Abschnitt 5 | `docs/shots/merge6/` |
| App-Store: Paket installieren und starten, Bild | **nicht gefahren** (Abschnitt 8) | — |
| VIELKERN: welcher Prozess auf welchem Kern | **38 von 40 Zusagen**, der Kern-Nachweis steht | Abschnitt 4 |
| Sieben Design-Ansichten am zusammengeführten Stand | **7 Bilder**, `.design-shots/merge6/` | Abschnitt 3 |

---

## 2. Was das Zusammenführen an Konflikten hatte

`vielkern3`, `design` und `laden` gingen **konfliktfrei** herein.
`werkzeug` hatte drei Textkonflikte und zehn Bildkonflikte — und das
war zu erwarten: er baut auf `wlib` auf, das `design` breit verändert
hat.

### 2.1 `kernel/cpu.fi` — beide Runden nahmen dasselbe freie Wort

VIELKERN 3 legt `C_SYSCALLS` auf Versatz 160 im Satz des Kerns,
WERKZEUGE `C_IDLETICKS` auf **dieselbe** 160. Beide sind am selben Tag
aus 1493451 abgezweigt und haben unabhängig voneinander das nächste
freie Wort genommen.

Aufgelöst **nicht** mit *ours/theirs*: `C_SYSCALLS` behält die 160,
weil `isr.s` sie fest einträgt (`.set CPU_SYSCALLS, 160`) und der
Systemaufruf-Einsprung sie ohne Firn dazwischen benutzt — ein Zähler,
den nur Firn anfasst, kann umziehen, einer im Assembler nicht.
`C_IDLETICKS` wird 168; der Satz ist `kstate.CPU_BYTES` = 256 groß,
belegt sind damit 176.

Hätte man das weggedrückt, wäre eine der beiden Zahlen still
verschwunden: `abw` (der Beweis „Ring 3 lief wirklich auf diesem Kern")
oder die Auslastung je Kern.

### 2.2 `kernel/kgui.fi` — zweimal dieselbe Abhilfe

Beide Runden haben denselben Fehler gefunden — `desk: start … pid=0`
ohne Grund — und dieselbe Abhilfe gebaut (`elf.say_reason` aus
`kstate.ELF_ERR`). Genommen ist die von VIELKERN 3, weil sie **nach**
`serial.nl`/`zeile_aus` steht und `say_reason` eine eigene Zeile
schreibt. Zweimal gerufen stünde der Grund zweimal auf der Leitung.

### 2.3 `test.sh` — beide vergaben Abschnitt 40

Verfahren wie bei BLECH/OTA weiter oben im Skript: beide bleiben,
WERKZEUGE wird 41. Die Nummer ist eine Überschrift, die Reihenfolge
macht die Stelle.

### 2.4 Zehn PNG

Ein Binärkonflikt hat keine inhaltliche Auflösung. Die Bilder wurden
deshalb nicht ausgewählt, sondern von `tools/themestore/run.sh` am
**zusammengeführten** Stand neu erzeugt.

---

## 3. Das 4er-Raster: 92 % gehalten

`tools/design/runde.sh` am zusammengeführten Stand, fünf Maschinen
gleichzeitig, sieben Ansichten, dann `tools/design/messen.py`:

| Messgröße | Runde OBERFLÄCHE (b90c110) | **merge6** |
|---|---|---|
| Gemeldete Längen auf dem Viererraster | 671 von 724 = **92 %** | 691 von 744 = **92 %** |
| Klickflächen unter 32 px | 2 von 86 | **2 von 89** |
| Vorkommende Höhen von Bedienelementen | 26, 28, 32, 166, 320 | **dieselben** |
| Listenzeile | 28 px, Faktor 1,86 | **28 px, 1,86** |
| 01-schreibtisch leer/abgeschnitten/überlappend | 0 / 0 / 0 | **0 / 0 / 0** |
| 02-startmenue | 2 / 3 / 0 | **2 / 3 / 0** |
| 03-explorer | 0 / 7 / 0 | **0 / 7 / 0** |
| 04-dialog | 0 / 8 / 0 | **0 / 8 / 0** |

Bilder: `.design-shots/merge6/01-…07-…png`, Zahlen in
`.design-shots/merge6/messwerte.json`.

**Aber der erste Lauf sagte etwas anderes**, und das gehört hierher:
vor der Reparatur aus Abschnitt 4.2 meldete `messen.py` für Explorer
und Dialog **2855 bzw. 2861 überlappende Bildpunkte**, wo die
Design-Runde 0 hatte. Das war kein Fehler an der Oberfläche, sondern
zerschossene Messzeilen — dieselbe Ursache wie in Abschnitt 4.2. Nach
der Reparatur steht 0 gegen 0.

### 3.1 Was hier NICHT stimmt und nicht dieser Runde gehört

Der Klickpfad zum Umbenennen-Dialog (`04-dialog`) läuft ins Leere:

```
klickauf fmbar0   -> 102,106  (rect 80,92 44x28)
warteauf explorer: menurect -> da
klickauf emenue0  -> 133,140  (rect 88,126 90x28)
warteauf explorer: dlgrect   -> NICHT DA
```

**Nachgemessen im abgekoppelten Baum `/tmp/m6-ref` auf `design`
b90c110, gleiches Drehbuch: Zeile für Zeile dasselbe.** Der Fehler ist
älter als dieses Zusammenführen und gehört der Runde OBERFLÄCHE.
Das Bild `04-dialog` zeigt deshalb das offene Menü statt des Dialogs.

---

## 4. Die Fehler, die NUR das Zusammenführen erzeugt hat

Keiner der vier Zweige zeigt sie allein. Das ist der eigentliche Ertrag
dieser Runde.

### 4.1 Zwei Prüfstände waren tot

`tools/design/capture.sh` und `tools/multicore/run.sh` löschen ein
Bündel **bei Namen** (`widgets.osp`), weil dessen Programm nicht in
ihrer Programmliste steht und `mkfs.py` sonst abbricht. WERKZEUGE hat
ein zweites Bündel dazugelegt:

```
FEHLGESCHLAGEN: mkfs
mkfs: '/bin/taskmgr' gibt es nicht
```

Ohne den ersten Läufer gibt es keine Rastermessung, ohne den zweiten
keine Vielkern-Abnahme. Gemessen am zusammengeführten Stand **vor** der
Reparatur: `tools/multicore/run.sh` **17 grün / 22 rot**, davon 21 allein
an der fehlenden Platte.

Genommen ist der Riegel, den WERKZEUGE für `tools/themestore/build.sh`
gebaut hat: `bundle.py nur=<Programmliste>` überspringt jedes Bündel,
dessen Programm nicht auf **dieser** Platte liegt. Damit ist die
Messgrundlage wieder genau die der Design-Runde, und der nächste neue
Bündelname bricht nichts mehr.

### 4.2 Ein `write` aus Ring 3 war kein `write` mehr

**Der Fund mit der größten Reichweite.** `sys.write_of` kopiert Text aus
Ring 3 nach `kstate.BLOCK_OFF` und gibt ihn von dort an das Terminal.
`BLOCK_OFF` ist **ein** Puffer von 4096 Oktetten in der Datenseite und
gehört der ganzen Maschine. Solange Ring 3 auf Kern 0 blieb, war das
richtig; VIELKERN 3 (5fe74f6) hat Ring 3 auf **alle** Kerne freigegeben,
und WERKZEUGE misst an **Zeilen** der seriellen Leitung. Einzeln konnte
es keine der beiden Runden merken.

Gemessen, vier Kerne, voller Schreibtisch:

```
er: treffetaskmgr: start bww=7=i5=3 n2ame= [bTerhmin=al5] ex2ec=4c/asppcs/...
```

Drei Zeilen ineinander. Die Zeile `wlib: win id=…`, aus der
`tools/toolbench/klickplan.py` **jede** Klickkoordinate holt, war
überhaupt nicht mehr zu finden:

```
plan: ZIEL NICHT GEFUNDEN: spalte 1 -- klickplan: keine 'wlib: win'-Zeile im Mitschnitt
```

| | `wlib: win`-Zeilen im Lauf b1 |
|---|---|
| Zweig `werkzeug` allein | 2 |
| merge6 vorher | **0** |
| merge6 nachher | 1 (die des Hauptfensters) |

Die Abhilfe ist die Sperre, die VIELKERN 3 schon gebaut hat:
`serial.zeile_an`/`zeile_aus` — je Kern wiedereintrittsfähig, also
verklemmt sie sich nicht gegen sich selbst, und begrenzt, also
verschluckt ein Kern, der mit ihr in der Hand stirbt, die Ausgabe der
anderen nicht. Sie lag bis hierher **nur** um die Zeilen, die der Kern
schreibt; Ring 3 ging daran vorbei. `sys.conout` zieht sie über beides
und deckt zweierlei ab: den **Puffer** (kein zweiter Kern kopiert
währenddessen nach `BLOCK_OFF`) und die **Reihenfolge**.

### 4.3 Der doppelte `wigapp`-Start

OBERFLÄCHE und WERKZEUGE haben unabhängig voneinander dieselbe Lücke
geschlossen — `wigapp=/bin/NAME` galt nur auf dem Fensterserver-Pfad
und nicht auf dem Schreibtisch — und beide ihren Block an eine **andere**
Stelle von `kgui.desk_start` geschrieben. Git hat beide behalten:

```
desk: start /bin/taskmgr                   pid=8
desk: start /bin/taskmgr,melde,takt,500    pid=0
```

Genommen ist der Block von WERKZEUGE, und der Grund steht in den zwei
Zeilen: er **zerlegt** die Argumente am Komma, der andere nahm die ganze
Zeichenkette als Pfad — das ist die `pid=0`-Zeile. Die Wirkung war nicht
eine Zeile zu viel: der Aufgabenverwalter lief dadurch **ohne** `melde`
und meldete keine einzige seiner Zeilen. Acht rote Zusagen, und an ihm
war nichts kaputt.

### 4.4 Der Aufgabenverwalter rechnete mit getippten Zahlen

Er ist auf einem Zweig entstanden, der die Runde OBERFLÄCHE nicht
kannte. Drei Längen lagen wirklich neben dem Viererraster, und
Spaltenbreiten stehen in **jedem** Rechteck, das die Tabelle meldet:

```
CW_PID   62 -> 64      62 / 4 = 15,5
CW_CPU   82 -> 84      82 / 4 = 20,5
CW_CORE  62 -> 64
Fenster  y = 14 -> 16  14 / 4 = 3,5
Knopf    h = ch + 2 = 34 -> ch = 32   (das IST die Marke hit_min)
Reserve  6 + 16 = 22 -> 24            (snap_up, weil sie ABGEZOGEN wird)
Zeile    text_h(px_ui()) = 18 -> type_lh(TY_BODY) = 20
```

Was schon richtig lag (752, 524, 116, 104, 112), geht jetzt trotzdem
durch `snap_up`. Eine Regel, die nur im Kommentar steht, hält bis zur
nächsten Runde.

Dazu eine zweite Stelle: `tools/toolbench/run.sh` hatte die Fensterlage
als `--window=20,14` fest getippt, also dieselben zwei Zahlen an zwei
Stellen. Das Programm meldet seine Lage jetzt selbst
(`taskmgr: start bw= bh= wx= wy=`), der Läufer liest sie.

### 4.5 Die Glyphenbühne — **offen, und der Grund für das „noch nicht"**

`wig.glyph_into` baut die Antwort auf einen `WIG_GLYPH` in **einem**
Puffer der Datenseite zusammen (`base(state) + STAGE_OFF`): sechs
Kopfworte (Breite, Höhe, links, oben, Laufweite, Zahl der Bildpunkte),
dann die Bildpunkte, dann alles am Stück nach Ring 3. Zeichnen zwei
Programme auf zwei Kernen gleichzeitig, steht im Kopf die Breite des
einen Zeichens und dahinter die Bildpunkte des anderen — und der Klient
rechnet `gw * gh` auf Zahlen, die nicht zusammengehören:

```
panic: integer overflow in 'u64 * u64' at kernel/user/wlibc.fi:1128:8
```

Der Aufgabenverwalter starb dann genau **eine Zeile** nach
`taskmgr: start`. Es sah aus wie ein Fehler in ihm.

**Die Gegenprobe, die es festnagelt** — derselbe Kern, dieselbe Platte,
dieselbe Befehlszeile, nur die Zahl der Kerne getauscht:

| | Panics | `taskmgr: zeile`-Zeilen |
|---|---|---|
| `-smp 1` | **0** | **212** |
| `-smp 4`, fünf Läufe | **1 von 5** | 83 / 78 / 80 / 56 / 0 |

Eingebaut ist eine Bühnensperre nach demselben Muster wie in VIELKERN 3
(je Kern wiedereintrittsfähig, begrenzt, `wig.buehne_verloren` zählt).
Sie **senkt** die Rate, sie schließt sie **nicht**. Ehrlich: damit ist
der Fund benannt und gemessen, aber nicht erledigt — der Weg
`ttf.glyph` → `ttf.g_pixel` → Bühne hat mehr geteilten Zustand als die
eine Bühne, und das ist eine eigene Runde.

---

## 5. Der Aufgabenverwalter am zusammengeführten Stand

`tools/toolbench/run.sh`, bester Lauf ohne Nebenlast: **26 von 34**.
Auf dem Zweig `werkzeug` allein, im abgekoppelten Baum nachgemessen:
**37 Zusagen, 0 Fehler**.

Grün und einzeln nachgemessen:

* die Kennzahlen der Runde (Leerlauf je Kern, Seiten je Prozess, Kern je
  Prozess) mit ihren Gegenproben — `idle <= ticks` auf jedem Kern,
  Prozesse mit und ohne eigenen Adressraum kommen beide vor, mehr als
  ein Kern trägt Prozesse;
* das Fenster steht: kein Rechteck ragt hinaus, 10 gemessene
  Beschriftungen, 0 leere, 0 abgeschnittene, 0 überlappende;
* der Verlaufsgraph ist **gemalt**: 11 gemeldete Messpunkte, 11 im Bild
  gefunden, 0 daneben, die Enden auf den Bildpunkt nachgerechnet;
* das Kontrollzentrum: sechs Kacheln, Klick in die Ecke öffnet, der
  Helligkeitsregler meldet, die Kachel Dunkelmodus schaltet und
  schreibt `/etc/theme.conf`.

Rot, und die Ursache steht in 4.5: alles, was **nach** dem Panic käme —
Sortieren, Wählen, „Prozess beenden".

Bilder: `docs/shots/merge6/taskmgr-allein.png`,
`taskmgr-liste.png`, `kontrollzentrum.png`, `kontrollzentrum-dunkel.png`.

---

## 6. VIELKERN: der Kern-Nachweis, und der Puffer auf Bestellung

`tools/multicore/run.sh` nach der Reparatur aus 4.1: **38 grün, 2 rot**.

```
-smp 4 r3alle   R3W 0  R3K 4  Kerne in der Maske 4  abw 0  Ausnahmen 0
                r3: syscalls c0=119 c1=79 c2=6 c3=0  summe=204  abw=0
-smp 8 r3alle   R3W 0  R3K 6  Kerne mit Systemaufrufen 5  abw 0
                r3: syscalls c0=198 c1=18 c2=558 c3=0 c4=9 c5=45 c6=0 c7=0  summe=828  abw=0
```

Der Nachweis, welcher Prozess auf welchem Kern lief, **gelingt
weiterhin** — und `abw=0` heißt: die Summe der je Kern über die GS-Basis
gezählten Systemaufrufe stimmt mit `kstate.SYSCALLS` überein.

Die zwei roten:

* `/bin/settings kommt nicht hoch` — **Last, nicht Regress.** Der Läufer
  wartet auf fünf Messtafeln und bricht dann ab; unter Nebenlast startet
  das vierte Programm später. Derselbe Kern, dieselbe Platte, ohne
  Nebenlast: `desk: start /bin/settings pid=8`.
* `der Bruch trifft keine Ring-3-Aufgabe` (Abschnitt 9, Gegenprobe zum
  Riegel) — der Bruch **kommt** (`ohne den Riegel bricht die Maschine
  wieder` ist grün), er trifft nur nicht die erwartete Gattung.

### 6.1 `fs.inode_get` — behoben, und jetzt auch **erzwungen**

Nachgesehen, Zeile für Zeile: der Befund aus VIELKERN 3 ist **wirklich
behoben und nicht nur beschrieben**. 858c4b8 stellt `inode_get`,
`inode_set`, `inode_init`, `used_inodes`, `free_blocks`,
`file_truncate`, `entry_at` und `symlink_path` unter `enter`/`leave`
(`atomic.L_FS`, je Kern wiedereintrittsfähig), und Abschnitt 3 des
Läufers zählt an der Quelle nach, dass kein Weg daran vorbeikommt.

Was fehlte, war der Nachweis am **laufenden** Kern. Eine Zusage über
Text fällt, wenn jemand die Sperre entfernt — und sie fällt **nicht**,
wenn die Sperre dasteht und nicht wirkt. Der Fund selbst war bis hierher
eine Beobachtung (`pid=0` auf dem vollen Schreibtisch) und hing daran,
wie der Ablaufplaner den Lauf gerade legte.

`fsrace` auf der Befehlszeile bestellt ihn: `smp.run_phase` startet
**alle** Kerne im selben Augenblick, jeder liest 20 000 Mal die Art
**seines** Inodes — aus einem **eigenen** Inodeblock, denn `buf_in`
fasst einen Block und nicht einen Inode.

```
smp: fsrace kerne=4  runden=20000  blind=0  fehler=0
smp: fsrace   c0 inode=1=0  c1 inode=5=0  c2 inode=9=0  c3 inode=13=0

smp: fsrace kerne=4  runden=20000  blind=1  fehler=31506
smp: fsrace   c0 inode=1=18784  c1 inode=5=3480  c2 inode=9=5436  c3 inode=13=3806
```

**0 gegen 31 506** von 80 000 Lesungen — jede zweite bis dritte falsch.
`fsblind` nimmt dafür den **wörtlichen** Rumpf, den `inode_get` vor
VIELKERN 3 hatte (`fs.inode_get_blind`), keine Nachbildung. Eine Zusage,
deren Gegenprobe nicht fällt, ist eine Behauptung.

Neu im Prüfstand: `tools/multicore/run.sh` Abschnitte 10, 11 und 12
(= `test.sh` Abschnitt 40).

### 6.2 Die übrigen Ein-Kern-Reste, an der Quelle gezählt

`tools/multicore/onecore.py` liest die Kernquellen und zählt jede
Funktion, die einen Puffer der **Datenseite** (`state + kstate.X_OFF`)
als Arbeitsfläche nimmt, ohne dass ein Sperrwort in ihrem Rumpf steht.

```
einkern gesperrt=13 offen=60
offen in: elf.fi, fs.fi, hw.fi, kgui.fi, sys.fi, sysgui.fi, uio.fi
```

Der größte Posten ist **`kernel/sys.fi`** — dreiundvierzig Funktionen um
`kstate.NAME_OFF` (Pfade aus Ring 3, 4096 Oktett) und
`kstate.BLOCK_OFF` (der Umschlagpuffer, 4096 Oktett). `sys.dispatch`
nimmt **keine** Sperre; `do_open` kopiert den Pfad nach `NAME_OFF` und
arbeitet danach daraus. Zwei Ring-3-Prozesse auf zwei Kernen in `open`
öffnen damit den Namen des jeweils anderen. Das ist dieselbe Fehlerform
wie `KSTACK_CUR` und `fs.buf_in`, eine Etage höher und viel breiter.

Die Zahl ist **keine Fehlerliste** — das Werkzeug liest Text und keine
Abläufe —, sondern ein **Vertrag**: Abschnitt 12 des Läufers lässt sie
nicht wachsen, ohne dass jemand aufschreibt, warum. Die Ausgabe (4.2)
ist zuerst drangekommen, weil sie die einzige ist, deren Bruch eine
**Abnahme** zum Lügen bringt.

---

## 7. `./test.sh` und `tools/themestore/run.sh`

`tools/themestore/run.sh` am zusammengeführten Stand:

```
THEMESTORE: 81 passed, 0 failed
```

Darin die Zusagen, um die es dem Auftrag ging: jede Vorlage hält ihre
Kontrastlatte (4,5:1 Text, 3,0:1 Bedienelemente, 7:1 wo
`contrast=high` steht), **zweimal gerechnet** — einmal im System, einmal
auf dem Wirt — und Zahl für Zahl gleich; die Gegenprobe fällt (eine
Vorlage auf einem absichtlich schlechten Schema **wird** als geringer
Kontrast erkannt); und in keiner der zehn Aufnahmen eine leere,
abgeschnittene oder überlappende Beschriftung.

`./test.sh` (64 Abschnitte, 10 gleichzeitig) wurde gestartet und lief
innerhalb dieser Runde NICHT zu Ende. Die fertigen Abschnitte stehen in
`STATUS-MERGE6.md`; die eine Zusage, die dabei wirklich rot war
(`posix` 133/1, `SYS_OSUM_CPUSTAT` fehlte in der libc), ist behoben und
einzeln auf 134/0 nachgemessen. Eine Zahl, die niemand gesehen hat, ist
keine Abnahme -- deshalb steht hier kein Gesamtergebnis.

---

## 8. Was diese Runde **nicht** eingelöst hat

* **`tools/loader/run.sh` ist nicht gefahren.** Der Läufer braucht das
  offene Internet und `/srv/store` auf diesem Wirt — beides ist da
  (`curl … VERZEICHNIS` → 200, acht Pakete unter `/srv/store/osum`) —,
  aber seine QEMU-Abschnitte haben Fristen bis 3600 s, und die Runde ist
  vorher an den Fehlern aus Abschnitt 4 hängengeblieben. Der Zweig
  `laden` ging konfliktfrei herein und ist von keinem der Funde
  berührt; abgenommen ist er damit trotzdem nicht. **Offene Auflage.**
* Die Glyphenbühne (4.5) ist gemessen, nicht geschlossen.
* Die dreiundvierzig Wege in `sys.fi` (6.2) sind gezählt, nicht
  gesperrt.
* `04-dialog` (3.1) ist älter als diese Runde und bleibt rot.

---

## 9. Ist `merge6` reif, `hidweg` zu ersetzen?

**Nein — noch nicht.** Begründung in drei Zeilen:

1. **Dafür spricht viel.** Alle vier Gewinne sind gleichzeitig da und
   einzeln nachgemessen: 92 % Raster (unverändert), 81/0 im
   Vorlagenladen, der Kern-Nachweis von VIELKERN mit `abw=0`, der
   Aufgabenverwalter mit Fenster, Graph und Kontrollzentrum. Sechs
   Fehler, die nur beim Zusammenführen sichtbar werden, sind gefunden
   und behoben — zwei davon hatten ganze Prüfstände lahmgelegt.
2. **Dagegen spricht einer, und der reicht.** Ein Ring-3-Programm stirbt
   in **einem von fünf** Läufen mit vier Kernen an einer Glyphenbühne,
   die der ganzen Maschine gehört (4.5). Ein Stand, der Grundlinie sein
   soll, darf nicht in zwanzig Prozent der Läufe ein Fenster verlieren —
   und jede Abnahme, die danach misst, misst dann Rauschen.
3. **Was fehlt, ist benannt und klein genug:** die Bühne und der
   Glyphen-Zwischenspeicher unter eine gemeinsame Sperre (oder je Kern),
   dazu `tools/loader/run.sh` einmal durchfahren. Danach ist der Stand
   reif — und `tools/multicore/run.sh` Abschnitte 10–12 sowie
   `onecore.py` sind der Prüfstand, der es beim nächsten Mal sofort
   sagt.
