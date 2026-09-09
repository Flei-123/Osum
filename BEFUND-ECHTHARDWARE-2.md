# BEFUND ECHTHARDWARE-2 — Justins zweite Blech-Rückmeldung

**09.09.2026.** Repo `/root/osum-merge9`, Zweig `merge9`.
Ausgangsstand `f47f99e`, Endstand `39f4cc2`. **Nichts gepusht.**
Abbild `/srv/store/abbilder/orientos-usb-20260909-39f4cc2.img` —
**nicht** als aktuell markiert.

Alles hier steht mit Beleg: entweder eine Zeile der seriellen Leitung
oder eine Zahl aus einem Bild. Wo etwas nicht nachweisbar war, steht das
ausdrücklich dabei.

---

## 0. Die wichtigste Erkenntnis: die panic-Meldung führt in die Irre

Justin hat abgelesen:

```
panic: integer overflow in 'u64 - u64' at kernel/user/wlib.fi:969:25
```

**Die Datei heißt `wlibc.fi` und die Zeile ist 970.** Das ist kein
Lesefehler von ihm — die serielle Leitung schreibt die Meldung *mitten
in eine andere Zeile hinein*, weil zwei Prozesse gleichzeitig schreiben:

```
taskbar: field panic: integer overflow in 'u64 - u64'
         at kernel/user/wlibc.fi:970:25net x=2012 y=8 w=248 h=64 lines=1
```

Wer das vom Foto abliest, liest `wlib` und eine Zahl daneben. Spalte 25
der Zeile 970 ist wörtlich `x - i`.

**Für künftige Runden:** eine panic-Zeile vom Foto ist ein *Hinweis*,
keine Adresse. Nachstellen, bis sie im eigenen Log steht.

---

## 1. Die harten Fehler (A)

### A1 — der panic, und warum er das weiße Fenster erklärt

`drop_shadow` (`wlibc.fi:956`) malt `reach` Schattenringe **um** ein
Fenster; der linke Rand eines Ringes liegt bei `x - i`. Steht das
Fenster näher als `reach` am Schirmrand — bei `x=0` also immer —, ist
das in `u64` keine negative Zahl, sondern eine in der Nähe von 2^64.

Es schlägt nur unter `shape=osum` zu (unter `classic` ist `strength` 0
und die Funktion kehrt sofort um), und `shape=osum` bringt der Stick erst
seit Runde ECHTHARDWARE-1 mit.

**Getroffen hat es die Einstellungen** — deshalb waren *zwei* von Justins
Befunden dieselbe Ursache: der panic **und** das weiße Fenster.

*An der Wurzel behoben:* `wlibc.fi` hat jetzt `sub()` — dieselbe
sättigende Subtraktion, die `wlib.fi` längst hat. Der Ring wird
**beschnitten** (Breite/Höhe um den fehlenden Teil verringert) und nicht
verschoben; verschoben säße der Schatten schief unter dem Fenster.
Dazu `rring()`: `w - 2 * k` lief unter null, sobald der Fokusring breiter
ist als das halbe Bedienelement — bei `uiscale=2` ist er doppelt so breit,
das Element aber nicht zwangsläufig.

**Beleg:** `pruef/einst.py`, Lauf `einst1` = panic, Lauf `einst2` und
`Feinst` (fertiges Abbild) = **0 panics**.

### A2 — das weiße Einstellungsfenster

`assets/apps/settings.osp/INFO` ist **2101 Oktette** lang, und `name=`
steht das zweite Mal bei Oktett **1236**. `appdir.fi` las **1023**. Der
Eintrag wurde nie gefunden, das Bündel fehlte im Verzeichnis, die App
hatte nichts anzuzeigen.

Die Vorrunde hat das *gesehen* und sich bewusst dagegen entschieden
("ein größerer Puffer verschöbe die Grenze nur"). Das Argument stimmt für
sich, geht aber am Fall vorbei: eine Grenze, die von einer normalen Datei
mit Erklärungskopf gerissen wird, ist zu eng gewählt.

*Behoben:* Puffer 1024 → **8192** an **beiden** Lesestellen
(`eine_datei` **und** `net_user`). Die Meldung bleibt, mit der neuen Zahl.

**Beleg:** vorher `appdir: INFO laenger als 1023 Oktette:
/apps/settings.osp/INFO` auf der Leitung, nachher **keine solche Zeile**.
Fenster **1520×1132** mit Tinte in **jedem** Achtel (2,7 – 16,1 %).

### A3 — Explorer-Spalten überlappen

`explorer.fi:786` setzte `spalten[0..3]` fest auf `186/80/76/108` — ohne
`ui_scale()`. Bei doppelter Schrift passt der Kopf nicht mehr in die
Spalte und läuft in den Nachbarn (Justins Foto: „GrößeZeit Rechte").

**Beleg:** `explorer: spalten 378 528 608 684` → **`382 714 874 1026`**
bei scale 2, **`202 368 448 524`** bei scale 1.

### A4 — Symbol und Text nicht auf gleicher Höhe

Zwei Stellen, beide dieselbe Sorte Fehler:

1. `wlib.list_ein()` gab **fest 22** zurück (16 px Symbol + 6 Abstand,
   geeicht bei scale 1). Bei scale 2 ist das Symbol 32 px breit und lief
   **unter** den Text. `table_ein()` daneben hat es immer richtig gemacht
   (`icon_small() + 4`) — die Liste zieht jetzt gleich, mit Justins
   Vorgabe `+ 6 * scale`.
2. Beide Malstellen setzten das Symbol mit festem `ry + 2` von oben
   statt mittig. In der Taskleiste dasselbe: dort wurde mit `gl_w()` (32)
   gerechnet, gemalt wird aber `icon_h() * scale` (28) — das Symbol saß
   **gemessen 5 px zu hoch** (Knopfmitte 1404, Symbolmitte 1399).

*Behoben:* beide Malstellen rechnen die Zeilenmitte; die Taskleiste nimmt
die **wirklich gemalte** Höhe (`icon_draw_h`).

### A5 — „zerrissene" Fenster: **nicht reproduzierbar**

Justins Foto zeigt weiße Streifen über Terminal und Explorer. Im Nachbau
bei `uiscale=2`: Terminalfenster (48,80)–(1168,840), **0 von 190** ganz
weißen Zeilen, Palette durchgehend `#f1f5f9` / `#0f172a`.

**Ich behaupte nicht, dass es das nicht gibt** — ich konnte es nicht
auslösen. Verdacht: das Foto entstand während eines Neuzeichnens. Steht
als `OFFEN.md` `D-018`; ein zweites Foto im Stillstand würde es klären.

---

## 2. Die Taskleiste (B)

### B6 — winzige Symbole: die Wurzel lag in einer einzigen Funktion

`wlibc.icon_draw` hat das Bild **Punkt für Punkt** ausgegeben, ohne die
Vervielfachung auch nur zu kennen. Jede andere Größe im System nimmt
`ui_scale()` mit — Schrift über `px_ui()`, Knopfhöhen, `gl_w()` —,
dieses eine Blit nicht. Die Leiste wurde doppelt so hoch, das Symbol
blieb 16 Punkte.

*Behoben:* ein Kästchen je Quellpunkt, nächste Nachbarschaft (die Quellen
sind Flächenzeichnungen mit harten Kanten; eine Glättung machte daraus
bei ganzzahliger Vervielfachung nur einen weichen Rand). Dazu `IC_W` und
`MK_W` → `ic_w()` / `mk_w()`, damit der **reservierte Platz** mitwächst.

**Beleg aus dem Bild:** Tintenblock **14 px → 36 px**; vorher zwei
Fragmente (14 + 10), jetzt **ein** Block. Nahaufnahme unten links:
scale 2 = **48 / 36 / 47** px, scale 1 = **24 / 21 / 25** px.

### B7 — „Klick auf das OS-Symbol macht nichts"

**Die Klickfläche war nie das Problem** — der Knopf ist 72×64 und die
Prüfung in `click()` deckt ihn ganz ab. Zu klein war das **Zeichen**:
Tinte von `y=1392` bis `y=1415`, also **24 Punkte in einem 64 Punkte
hohen Knopf**. Wer auf das kleine Zeichen zielt, das er *sieht*, trifft
daneben.

`marke_start` hat drei eingebackene Größen (16/24/32) und keine größere;
die 32er passt auf 60 nutzbare Punkte **genau einmal**, dann bleibt die
Hälfte leer. Jetzt wird die beste Paarung aus Quellgröße und
ganzzahliger Vervielfachung gesucht: **24 × 2 = 48** schlägt 32 × 1.

**Beleg:** `taskbar: marke n=32` → **`n=48`**; im Bild **24 px → 60 px**.
Der Bericht meldet jetzt die *gemalte* Kante, nicht die der Quelle.

### B8 — Super-Taste: **war schon richtig gebaut**

Die Kette `kbd.fi` (0x5B/0x5C, Puls beim Loslassen) → `taskbar.hotkey_step`
→ `startmenue_um` ist vollständig und korrekt. Der Befund der Vorrunde
kam aus einem Lauf, der **18 Sekunden blind schlief** — bei 2560×1440
stand die Leiste da noch nicht, und auf der Leitung standen `usb: port=6
driver=kbd` und `kbd: layout de`.

**Beleg:** `taskbar: klinke seq=1 war=0 taste=0` → `startmenue auf`;
Tippen `ter` filtert **18 → 7** Treffer; Enter startet.

*Konsequenz für den Prüfstand:* nie blind schlafen, sondern aktiv auf
`taskbar: state` warten (bis 90 s).

### B9 — der Tray und „danach geht gar nichts mehr"

**Es ist kein Absturz.** Im ganzen Lauf steht **keine** panic-Zeile.
Nachgestellt in `pruef/kacheln.py` (Lauf `kach3`):

- Kachel **Hide bar** → die **Taskleiste versteckt sich**
  (`taskbar: hide`, Fenster wandert auf `y=1438`, also aus dem Schirm).
  Danach malt die Leiste nicht mehr, die Uhr steht — für den, der
  davorsitzt, ist das System eingefroren.
- Kachel **Network** → schaltet das Netz ab (`t=no network`).

Beide tun genau, was draufsteht. Für den Benutzer sieht die Kombination
aus wie „kaputt" — und genau deshalb hat Justin recht, dass sie dort
nicht hingehören.

*Behoben:* `N_TILE` 6 → **4**. Im Tray stehen nur noch Netz, Dunkelmodus,
Energieprofil, Kacheln. **Ohne Funktionsverlust:** beide entfernten
Schalter stehen längst in den Einstellungen (`settings.taskbar.autohide`
und `settings.netview.choices` mit „faked"). Die Zuordnung läuft über
`tile_of()` statt über sechs umnummerierte Zweige — ein `if t == 3` in
fünf Funktionen gleichzeitig umzuschreiben ist die Sorte Änderung, bei
der eine Stelle vergessen wird und danach „Dunkelmodus" das Netz
abschaltet. `TOP2` rechnet die Reihenzahl statt fester 3.

**Beleg:** Panel **907 → 751** Punkte hoch (2 Reihen statt 3); Lauf
`kach4`: alle vier Kacheln geklickt, **0 panics**, Leiste bleibt stehen,
Uhr läuft weiter.

**Nebenbefund (echter Fehler, nicht behoben):**
`taskbar: size w=2560 h=2 rc=-4` — das Verkleinern auf den 2-Punkt-Streifen
**scheitert** (`wm.resize_win` verlangt `h >= 16`). Die Leiste verschwindet
trotzdem, weil sie zusätzlich verschoben wird; das Wiederauftauchen über
den Streifen kann so nicht zuverlässig funktionieren.

---

## 3. Sprache (C) — es war **ein Wort**, nicht 71 Stellen

Der Auftrag nannte „71 Treffer für deutsche UI-Strings, zentrale
String-Tabelle anlegen". **Die Tabelle gibt es seit Runde I18N**
(`kernel/user/msg.fi`, 320 Plätze, Katalog unter
`/usr/share/locale/<code>/messages`). `init()` liest **immer zuerst**
`locale/en/messages`; Englisch ist die Rückfallsprache **jedes**
Schlüssels, und ein fehlender Schlüssel ergibt nie einen leeren Knopf.

Was den Stick trotzdem deutsch machte, war **eine Zeile in `build.sh`**:

```
printf 'de\n' > "$OUT/locale-de"     # → /users/root/config/locale
```

**Beleg vorher:** `taskbar: lang=de src=1 keys=288` (src=1 = die Wahl des
Benutzers, genau diese Datei).
**Beleg nachher:** `taskbar: lang=en src=1 keys=317`.

Dazu geändert:
- die App-Namen und -Beschreibungen in den `INFO`-Dateien
  (`Datei-Explorer` → `File Explorer`, `Einstellungen` → `Settings`, …) —
  die stehen **nicht** im Katalog, sondern im Bündel.
- `launcher.prompt` = `Search programs`,
  `explorer.columns` = `Name / Size / Modified / Permissions`.

Beide Kataloge bleiben im Abbild; Deutsch ist in den Einstellungen
wählbar. **Code-Kommentare und Bezeichner sind unberührt.**

---

## 4. SVG-Symbole (D) — der Vektorweg ist schon da

Der Auftrag sagt „Es gibt 0 .svg im Repo". Das stimmt, **führt aber in
die falsche Richtung**: das Projekt hat bereits einen skalenfreien
Symbolweg, und er ist in `docs/ICONS.md` ausführlich begründet.

- **Shell-Symbole** (Netz, Akku, Fensterknöpfe, Pfeile, Ordner …) kommen
  aus `assets/osum-icons.ttf` — **42 Glyphen, aus Lucide geschnitten**
  (ISC, `assets/icons/LICENSE.lucide`), gebaut von `tools/icons/build.py`.
  Das sind **Umrisse**, kein Bitmap: sie werden in jeder Größe frisch
  gerastert. Genau die Bibliothek, die Justin selbst nennt.
- Die Wahl ist **gemessen** getroffen worden, nicht behauptet: bei 16 px
  hat Lucide 25,0 volle Bildpunkte je Symbol gegen 11,4 beim Zweitplatzierten.

**Was wirklich offen ist:** die **App-Bündel** (`assets/apps/*/symbol.txt`)
benutzen weiter OSYM-Bitmaps mit 16×16. Die werden seit dieser Runde
ganzzahlig vergrößert — damit sind sie bei scale 2 nicht mehr winzig, aber
sie sind vergrößerte Bitmaps und keine Umrisse. Steht als `OFFEN.md`
`D-017`.

Ich habe **keine** SVG-Dateien ins Repo gelegt: ein zweiter Symbolweg
neben einem vorhandenen, begründeten Vektorweg wäre Doppelarbeit, und
ein Mini-SVG-Rasterer in Firn ist eine eigene Runde wert — nicht ein
Nebenbei-Punkt in einer Fehlerbehebungsrunde.

---

## 5. Tooltips und Rechtsklick (E)

**Infoblase.** Verweilen ≥ 500 ms über einem Taskleisten-Symbol, im Tray
oder auf dem Startknopf zeigt eine Blase. Der Fensterknopf zeigt seinen
**Titel** — bei Justins Auflösung steht der sonst nirgends.

Zwei Dinge, die dabei schiefgingen und beide nur durchs Messen auffielen:

1. Die erste Fassung meldete brav `wlib: tip [...]` und im Bild war
   **nichts** — 0,0 % Tinte auf 300×50 Punkten. `new_win` gibt bei
   `nwn >= MAXWN` einfach `MAXWN` zurück, und die Meldung stand **vor**
   dem Anlegen. `MAXWN` 4 → 5, und die Blase sagt jetzt selbst, wenn sie
   keinen Platz bekommt.
2. `TICK_HZ` ist **100**, also sind 500 ms **fünfzig** Schläge und nicht
   fünfhundert. Mit 500 hätte die Blase erst nach fünf Sekunden gestanden.

**Beleg:** `wlib: tip [Terminal -- sh] x=120 y=1343`, `[169.254.10.1]`,
`[Start]`, `wlib: tip zu` beim Verlassen, **1877 Punkte Tinte** im
gemeldeten Rechteck, 0 panics.

**Kontextmenü.** Rechtsklick auf einen Fensterknopf → **Minimieren /
Anheften**. „Schließen" steht **nicht** darin: `WM_ACT` kennt `WA_RAISE`,
`WA_HIDE` und `WA_TOGGLE` und **kein** `WA_CLOSE` (`kernel/sys.fi:3519`).
Ein Menüpunkt, der nichts tut, wäre schlechter als keiner; sobald der
Kern ein `WA_CLOSE` hat, ist hier eine Zeile zu ändern.

Zwei echte Fehler auf dem Weg:

1. Die Leiste holt ihre Ereignisse **selbst** und ruft `wlib.step` nie.
   `mn_res` — die Antwort „welcher Punkt wurde gewählt" — wird aber
   ausschließlich dort gesetzt. Das Menü klappte auf, nahm Klicks an und
   sagte nie, was gewählt wurde.
2. Danach kam der Klick immer noch nicht an: `menu_open` legt das Menü
   auf die normale Ebene, das **Startmenü** liegt auf `L_TOP` und ist
   880×600 — es deckte die Stelle ab, und der Fensterserver gab den Klick
   folgerichtig ihm. Ein Menü, das aus einer Leiste auf `L_TOP` aufklappt,
   muss selbst auf `L_TOP` liegen.

**Beleg:** `taskbar: kontext btn=1` → `wlib: mnklick x=16 y=40 nohit=0`
→ `taskbar: kontext w=0` (Minimieren ausgeführt), 0 panics.

---

## 6. Zwei eigene Regressionen — vom Prüfstand gefunden

**Beide betrafen `kernel/user/wlib.fi`, und beide fielen NUR in K16 auf.**

Der selbstgehostete Übersetzer `firnc1` bricht an `netmon`, `freunde` und
`powermon` ab, sobald `wlib.fi` über eine stille Grenze wächst: **RC=1,
keine Zeile stdout, keine stderr, 0 Oktette Ausgabe, 4 MB resident** —
also *kein* Speichermangel des Wirts, sondern eine feste Tabelle in
`firnc1`. `firnc0` übersetzt dasselbe klaglos, das Abbild läuft, und nur
K16 sieht es (`131 gebunden, erwartet 134`).

1. Die **ganze Infoblase** (~150 Zeilen) lag zuerst in `wlib.fi`.
   Behoben: in `wlib` bleiben `tip_win_open/close/id` (drei kurze
   Funktionen, die ohne dessen Fenstertafel nicht gingen), der Rest —
   Verweilzeit, Aufmachen, Zumachen, Zeichnen — liegt in `taskbar.fi`.
2. Danach haben **zwanzig Zeilen Diagnose-Spur** dasselbe noch einmal
   ausgelöst. Die Spur ist raus und steht als Kommentar da.

**Einzeln** übersetzt jeder Bestandteil — Vorwärtsaufruf, `new_win`,
`close`+`nwn`, `ticks`+Zeitlogik, `mal_tafel`+`put_text`, sogar 150 Zeilen
Füllcode mit Schleifen. Es ist die **Summe**. `wlib` steckt in dreizehn
Programmen; was dort liegt, kostet in jedem davon.

Dazu: `msg.fi` `SLOTS` 288 → **320** (der Katalog hat 317 Schlüssel; ein
überlaufender Katalog zeigt Schlüssel statt Wörter). **Nicht 352** — das
kostete 9 KiB `.bss` und schob dieselben drei Programme über die Grenze
von `fas`.

**Messfalle, die eine Viertelstunde gekostet hat:** `firnc1` braucht
`export FIRNLIB=$REPO/lib`. **Ohne** die Variable hängt es an stdin und
liefert RC=2 mit leerer Ausgabe — das sieht aus wie derselbe Fehler und
führt zu dem falschen Schluss „war schon vorher kaputt". Ich bin genau
darauf hereingefallen und habe erst durch eine Gegenprobe am
Ausgangsstand gemerkt, dass die Regression **meine** war.

---

## 7. Abnahme

**Beide Auflösungen, vollständiger Durchklick, kein einziger panic.**

| | 2560×1440, `uiscale=2` | 1920×1080, `uiscale=1` |
|---|---|---|
| Leiste steht | ja | ja |
| Sprache | `lang=en src=1 keys=317` | `lang=en src=1 keys=317` |
| Startmenü + `ter` gefiltert | 18 → 7 Treffer | 18 → 7 Treffer |
| Enter startet | `elf: start 19` | `elf: start 19` |
| Explorer-Spalten | `382 714 874 1026` | `202 368 448 524` |
| appdir-INFO-Fehler | **keiner** | **keiner** |
| jede Kachel geklickt | **0 panics** | **0 panics** |
| panics im ganzen Durchklick | **KEINE** | **KEINE** |

**Was ich auf den Bildern sehe** (`/srv/store/belege/orientos-vergleich/20260909-eh2/`):

- `2560/01-startmenue.png` — helles Schema `#f1f5f9`/`#f8fafc`, Akzent
  `#2563eb` auf der gewählten Zeile; Suchfeld oben, darunter die
  gefilterte Liste. Keine überlappenden Texte.
- `2560/02-explorer.png` — Tabelle mit vier Spalten, Köpfe getrennt
  (`382 714 874 1026`), Ordnersymbole auf Höhe der Schrift.
- `2560/03-einstellungen-mit-inhalt.png` — **das vorher weiße Fenster**,
  1520×1132, Tinte in jedem Achtel (2,7 – 16,1 %), Reiterleiste oben.
- `2560/04-kontrollzentrum.png` — vier Kacheln in zwei Reihen (751 statt
  907 Punkte hoch), darunter die zwei Schieber.
- `2560/05-terminal.png` — Textfläche, **0 von 190** ganz weißen Zeilen;
  Justins Streifen sind hier nicht.
- `2560/06-leiste.png` — Nahaufnahme unten links: Tintenblöcke
  **48 / 36 / 47** px. Das OS-Zeichen füllt seinen Knopf.
- `2560/07-tray.png` — Netzsymbol (30 px) + IP + Uhr. **Kein**
  „Kontrollzentrum an/aus", **kein** „Taskleiste an/aus".
- `1920/06-leiste.png` — dieselben Elemente mit **24 / 21 / 25** px,
  also genau halb so groß. Das ist der Beweis, dass skaliert wird.
- `blase/tip-*.png` — die Infoblase über Fensterknopf, Netzfeld,
  Startknopf.
- `kontext/01-kontext.png`, `02-danach.png` — das Kontextmenü und der
  Zustand nach „Minimieren".

**Prüfstände:** WM **104/0** · USERLAND **91/0** · K16 **64/0**.

---

## 8. Was offen bleibt

| ID | Punkt |
|---|---|
| `D-017` | SVG als *Quellformat* — der Vektorweg über `osum-icons.ttf` (Lucide) deckt die Shell ab; die **App-Bündel** benutzen weiter OSYM-Bitmaps |
| `D-018` | „Zerrissene" Fenster — **im Nachbau nicht reproduzierbar**, braucht ein zweites Foto im Stillstand |
| `D-019` | Die stille Grenze in `firnc1` — umgangen, Ursache in `vendor/firn` nicht behoben |
| — | `taskbar: size w=2560 h=2 rc=-4` — das Verkleinern der Leiste auf den Sliver scheitert (`resize_win` verlangt `h >= 16`) |

**Was Justin prüfen sollte:**

1. Startet das Einstellungsfenster jetzt **mit Inhalt**?
2. Sind die Symbole in der Leiste in einer vernünftigen Größe?
3. Öffnet der Klick auf das OS-Zeichen links unten das Startmenü?
4. Steht die Oberfläche auf **Englisch**?
5. Kommen beim Verweilen die Infoblasen?
6. **Die zerrissenen Fenster** — wenn sie noch auftreten: bitte ein Foto,
   und zwar eines, auf dem sich nichts bewegt.
