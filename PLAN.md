# RUNDE GLAS — Bauplan und Schnittstellen

Zweig `glas`, Arbeitsbaum `/root/osum-glas`. (Der vorige Inhalt dieser Datei
gehoerte der Runde WMPLUGIN und steht unveraendert in der Geschichte:
`git show HEAD~1:PLAN.md`.)

Ziel, in Justins Worten: **die Eckenrundung stufenlos regeln und die
Taskleiste (und Fenster) transparent bzw. als Milchglas haben** — einstellbar
auf der Seite "Darstellung", sofort sichtbar, und ein Neustart ueberlebt es.

Das ist **kein Neubau**. Alles, was diese Runde braucht, ist in vier Schichten
schon da und wird nur verbunden:

* Runde THEME/LOOK hat die **Formmarken** (`/etc/shapes/*.shape`,
  `met[M_RADIUS_*]` in `kernel/user/wlibc.fi`) — es fehlt nur eine Zahl, die
  sie ueberstimmt.
* Runde PAINT hat im Kern **genau eine** Stelle, die ein rundes Rechteck malt
  (`wm.fill_round`, `kernel/ui/wm.fi:1452`) und **genau eine**, die mischt
  (`wm.blend`, `:3973`, wortgleich mit `fb.blend` und `wlibc.blend`).
* Ring 3 hat **genau eine** Stelle fuer dasselbe (`wlibc.rrect`, `:1214`, und
  die Vektorbruecke `fuib.tafel`, die sie beim Ausfall selbst ruft).
* Runde PAINT hat den Weg **Ring 3 → Kern fuer aufgeloeste Formzahlen**
  (`WM_FORM` = 2115, `wlibc.form_push` → `sysgui` → `wm.set_form`).

Diese Runde legt also **vier Zahlen** in die Vorlagen-Sprache, schickt sie
durch den vorhandenen Weg und **mischt beim Zusammensetzen**.

---

## 0. Was schon steht (vorgefunden, nicht von dieser Runde gebaut)

| Sache | Ort | Zustand |
|---|---|---|
| Vorlagen-Sprache, 7+1 Schluessel, jeder andere wird GEZAEHLT | `kernel/user/template.fi:255 parse_key` | steht |
| 10 Vorlagen | `assets/themes/*.preset` | steht |
| Formmarken, 25 Stueck, aus `/etc/shapes/<shape>` | `kernel/user/wlibc.fi:2453 ff.` | steht |
| `/etc/theme.conf` lesen, **Aenderung erkennen ohne Neustart** | `wlibc.conf_key:3897`, `theme_poll:5141`, `theme_sum:4768` | steht |
| Formzahlen an den Kern | `wlibc.form_push:5337` → `sys.WM_FORM` → `wm.set_form:1284` | steht, 9 Plaetze |
| rundes Rechteck, kantengeglaettet (4x4-Abtastung je Eckpunkt) | `wm.fill_round:1452` / `wm.corner_cov` | steht |
| Alpha-Mischung | `wm.blend:3973`, `fb.blend/pixel_a/hline_a/fill_a` | steht, wird nirgends fuer Fenster benutzt |
| Fensterflaeche auf den Schirm | `wm.paint_win:5214` → `wm.fb_row:6035` (wortweise Kopie, **deckend**) | steht |
| Schieberegler | `wlib.slider:2609`, `slider_setz`, `slider_bahn` | steht |
| Seite "Darstellung" | `kernel/user/settings.fi:3999 ff.` (`R_DARST`) | steht |
| Abnahme, 81 Zusagen, 0 rot | `tools/themestore/run.sh` | steht — **keine davon wird abgeschwaecht** |

Die Taskleiste ist ein gewoehnliches Fenster ohne Schmuck (`F_NODECO`,
`WS_LAYER = L_TOP`) und laeuft in Ring 3 (`kernel/user/taskbar.fi`). Sie kann
nicht wissen, was unter ihr liegt — **Transparenz und Milchglas gehoeren
deshalb in den Kern**, in die eine Zeile, die ihre Flaeche auf den Schirm
kopiert. Das ist die Begruendung fuer den ganzen Zuschnitt unten.

---

## 1. Die Sprache: vier neue Schluessel

In `/etc/theme.conf` **und** in jeder `*.preset`:

| Schluessel | Typ | Bereich | Vorgabe, wenn die Zeile fehlt |
|---|---|---|---|
| `radius` | Zahl | 0..24 (geklemmt) | `radius_window` des Formsatzes aus `shape=` |
| `taskbar_alpha` | Zahl | 0..100 (geklemmt, 100 = deckend wie heute) | 100 |
| `window_alpha` | Zahl | 0..100 (geklemmt) | 100 |
| `taskbar_blur` | Zahl | 0..16 (geklemmt, 0 = aus) | 0 |

**DIE SICHERHEITSZUSAGE BLEIBT WORTGLEICH:** jeder Schluessel ist eine ZAHL
oder ein Wort aus einer festen Menge. `parse_key` zaehlt weiter jeden anderen
Schluessel als schlecht; `command=/bin/sh` wird weiter gezaehlt. Die Liste
waechst von 8 auf 12 Namen, und keine der vier neuen Zeilen kann einen Pfad,
einen Befehl oder ein Kennwort tragen — ein nicht-numerischer Wert ist
**ungueltig und wird als schlecht gezaehlt**, nicht stillschweigend auf 0
gesetzt.

`shape=classic|modern|osum` bleibt und ist ab jetzt **nur noch die
Voreinstellung des Radius**: es setzt den Startwert, `radius=` sticht ihn.

---

## 2. Die Zahlen, auf die sich alle Module einigen (VERBINDLICH)

Diese Tabelle ist der Vertrag. Wer eine Zahl aendert, aendert sie in beiden
Modulen im selben Commit — `tools/themestore/run.sh` haelt die Listen
gegeneinander (wie schon heute fuer `WF_*` gegen `FM_*`).

**Formplaetze** — `sys.WF_*` in `kernel/sys/sys.fi` **und** `wm.FM_*` in
`kernel/ui/wm.fi`, dieselben Nummern:

```
 0 RADIUS       (steht)      Eckenradius des Fensterrahmens, 0..24
 1 SHADOW       (steht)
 2 SHADOW_R     (steht)
 3 SHADOW_C     (steht)
 4 SHADOW2      (steht)
 5 SHADOW_R2    (steht)
 6 GRAD         (steht)
 7 CAPTION      (steht)
 8 MOTION       (steht)
 9 TB_ALPHA     NEU  Deckkraft der Taskleiste in Prozent, 0..100
10 WIN_ALPHA    NEU  Deckkraft gewoehnlicher Fenster in Prozent, 0..100
11 BLUR         NEU  Radius des Milchglases unter der Leiste, 0..16
12 GLASS_KEY    NEU  0xRRGGBB, die Grundfarbe der Leisten-/Fensterflaeche
FORM_SLOTS = 13 (war 9)
```

**Marken in `wlibc`** — `M_*`, heute 0..24, `M_COUNT = 25`:

```
25 M_TB_ALPHA    0..100
26 M_WIN_ALPHA   0..100
27 M_TB_BLUR     0..16
M_COUNT = 28
```
Der freie Radius bekommt **keinen eigenen Platz**: er wird beim Aufloesen in
`M_RADIUS_WINDOW/PANEL/BUTTON/INPUT` **hineingeschrieben**. Damit kommt er
ohne eine einzige neue Abfrage an jeder Stelle an, die heute schon einen
Radius malt — das ist der ganze Trick und der Grund, warum diese Runde klein
bleibt.

**Die Regel dafuer, wortwoertlich umzusetzen (Modul `marken`):**

```
nach dem Laden der Formdatei, in reload_inner UND in theme_probe:
  wenn /etc/theme.conf eine Zeile radius= hatte:
      r = klemm(wert, 0, 24)
      met[M_RADIUS_WINDOW] = r
      met[M_RADIUS_PANEL]  = r
      met[M_RADIUS_BUTTON] = r
      met[M_RADIUS_INPUT]  = r
  sonst: nichts — die Formdatei gilt wie bisher.
```
Dass ein Knopf von 26 Bildpunkten Hoehe bei `radius=24` nicht zur Ellipse
wird, muss **niemand** hier abfangen: `wlibc.rrect` und `wm.fill_round`
klemmen `r` selbst auf `min(w,h)/2`. Und weil beide nur die ECKEN anders
fuellen, **verschiebt kein Radius den Innenraum** — Text bleibt, wo er ist.
Das ist eine Eigenschaft der vorhandenen Funktionen und wird in Abschnitt 11
nachgemessen, nicht angenommen.

---

## 3. Wie Transparenz gemacht wird — und warum nicht flach

Ein gleichmaessiges Alpha ueber die ganze Leistenflaeche macht **auch die
Schrift durchsichtig**. Genau daran zerbricht die Zusage "4,5:1" der Runde
THEME: helle Schrift auf einem hellen Hintergrundbild.

**Deshalb: SCHLUESSELFARBE UND ABSTANDSALPHA.** Der Kern bekommt mit
`GLASS_KEY` die Farbe, mit der Ring 3 die Leistenflaeche ausgefuellt hat
(`C_PANEL` bzw. `C_WINDOW_BG`). Beim Kopieren einer Zeile gilt je Bildpunkt:

```
d   = |r-kr| + |g-kg| + |b-kb|            // Abstand zur Grundfarbe, 0..765
a   = alpha + (100 - alpha) * min(d, 96) / 96      // in Prozent, 0..100
ziel = blend(untergrund, punkt, a * 255 / 100)
```

* Ein Bildpunkt der **Flaeche** (d = 0) bekommt genau `taskbar_alpha` — die
  Leiste wird durchsichtig.
* Ein Bildpunkt der **Schrift oder eines Symbols** (d gross) bekommt 100 —
  die Schrift bleibt **voll deckend** und ihr Kontrast ist Zahl fuer Zahl der
  von heute.
* Die kantengeglaetteten **Raender eines Zeichens** liegen dazwischen und
  bekommen genau dazwischen — deshalb `min(d,96)/96` und keine Schwelle: eine
  Schwelle haette Treppen an jeden Buchstaben gemalt.

Drei Multiplikationen und eine Division je Bildpunkt, kein Speicher, keine
zweite Rechenart. **`blend` bleibt die eine Stelle, die mischt.**

Zusaetzlich eine harte Untergrenze `taskbar_alpha >= 20`: eine Leiste, die man
gar nicht mehr sieht, ist keine Einstellung, sondern ein Fehlerbild.

---

## 4. Wie Milchglas gemacht wird

Im Kern, in der Zeile vor dem Kopieren der Leistenflaeche:

1. Der Ausschnitt unter der Leiste (der schon fertig gemalte Zweitpuffer,
   also Hintergrundbild **und** alle tieferen Fenster) wird in einen
   Streifenpuffer kopiert.
2. **Drei Durchgaenge Kastenweichzeichner, separierbar, mit laufender Summe.**
   Waagerecht, senkrecht, waagerecht — je Bildpunkt eine Addition und eine
   Subtraktion je Kanal, **O(1) und nicht O(r)**. Naiv waere bei r = 16 das
   33-fache, und das ist der Unterschied zwischen 60 Bildern und Ruckeln.
3. Aufhellen bzw. Abdunkeln um eine feste Stufe, je nachdem, ob der laufende
   Satz hell oder dunkel ist (`FM_GLASS_KEY` sagt es: Helligkeit der
   Grundfarbe ueber/unter 50 %).
4. Dieser Streifen ist der **Untergrund** fuer Abschnitt 3.

**Der Zwischenspeicher, und die Bedingung dafuer.** Die Uhr in der Leiste
macht jede Sekunde Schmutz, obwohl sich unter der Leiste nichts geaendert hat.
`wm` fuehrt deshalb `S_GLASSGEN`: **in `compose` hochgezaehlt, sobald in dieser
Bildrunde irgendetwas UNTER der Leiste gemalt wurde** (die Hintergrundfuellung
oder ein Fenster, dessen Rechteck das Leistenrechteck schneidet). Ist
`S_GLASSGEN` gleich dem Stand des Streifens **und** sind Leistenrechteck,
Radius und Blur unveraendert, wird der Streifen **wiederverwendet**. Jeder
andere Fall rechnet neu.

**Und genau hier geht so etwas erfahrungsgemaess kaputt.** Heute wird die
Leiste deckend kopiert, also hat nie jemand gepruft, ob das, was unter ihr
liegt, neu gemalt wird. `compose` malt zwar den ganzen Schmutzbereich von unten
nach oben neu — **aber** der Schmutz eines bewegten Fensters ist heute sein
altes und sein neues Rechteck, und ob das Leistenrechteck dabei ist, ist
Zufall. Sobald die Leiste mischt, ist es kein Zufall mehr: **jedes
Schmutzrechteck, das das Leistenrechteck schneidet, muss das Leistenrechteck
in voller Breite enthalten** (sonst mischt die halbe Leiste neu und die andere
Haelfte zeigt Schlieren). Das ist Modul `kern`, Punkt 5, und Modul `abnahme`
misst es mit zwei Bildern und einer Zahl.

---

## 5. Der Zuschnitt: sechs Module, KEINE gemeinsame Datei

| Modul | Dateien, die es aendert (und NUR die) |
|---|---|
| **A `marken`** | `kernel/user/wlibc.fi`, `kernel/user/template.fi`, `kernel/sys/sys.fi`, `assets/themes/*.preset`, `assets/shapes/*.shape`, `tools/themestore/build.sh` |
| **B `kern`** | `kernel/ui/wm.fi`, `kernel/gfx/fb.fi`, `kernel/sys/sysgui.fi` |
| **C `widget`** | `kernel/user/wlib.fi`, `kernel/user/fuib.fi` |
| **D `leiste`** | `kernel/user/taskbar.fi` |
| **E `seite`** | `kernel/user/settings.fi`, `locale/*` (nur neue Textmarken) |
| **F `abnahme`** | `tools/themestore/run.sh`, `tools/themestore/shotcheck.py`, `tools/themestore/glascheck.py` (neu), `docs/RUNDE-GLAS.md` (neu), `docs/shots/glas/` |

`kernel/sys/sys.fi` (nur Konstanten, Modul A) und `kernel/sys/sysgui.fi` (nur
Weiterleitung, Modul B) sind absichtlich getrennt — beide beruehren `WM_FORM`,
aber an zwei Enden und in zwei Dateien.

Reihenfolge der Abhaengigkeit, falls etwas nicht baut: **A und B koennen sofort
und unabhaengig**, weil beide nur Zahlen aus der Tabelle in Abschnitt 2
benutzen. C, D, E lesen ihre Werte ueber die von A zugesagten Funktionen. F
kann seine Abschnitte schreiben, bevor irgendetwas davon laeuft.

---

## 6. Modul A — `marken` (die Sprache und die Zahlen)

1. `template.parse_key`: vier Namen dazu (`radius`, `taskbar_alpha`,
   `window_alpha`, `taskbar_blur`). Jeder liest **nur Ziffern**; alles andere
   → `return false` (also gezaehlt). Gelesener Wert wird geklemmt. Dazu vier
   Leser `radius_at(i)`, `tba_at(i)`, `wa_at(i)`, `blur_at(i)` neben den
   vorhandenen `scheme_at` usw., und `theme apply` schreibt sie nach
   `/etc/theme.conf`.
2. `wlibc.conf_key`: dieselben vier Schluessel aus `/etc/theme.conf`.
   Zahlenwerte in `usr_radius` (−1 = keine Zeile), `met[M_TB_ALPHA]`,
   `met[M_WIN_ALPHA]`, `met[M_TB_BLUR]`.
3. `wlibc.reload_inner` **und** `theme_probe`: die Regel aus Abschnitt 2 nach
   dem Laden der Formdatei anwenden.
4. `wlibc.theme_sum`: die vier Werte **mit in die Pruefsumme**. Ohne das
   meldet `theme_poll` "nichts geaendert" und **die Aenderung wirkt erst nach
   einem Neustart** — genau die Zusage, die diese Runde gibt.
5. `wlibc.form_push`: vier weitere `form_one`-Aufrufe (TB_ALPHA, WIN_ALPHA,
   BLUR, GLASS_KEY). `GLASS_KEY` ist `theme_live(C_PANEL)` fuer die Leiste;
   die Fensterflaeche meldet der Kern selbst aus `DK_*`, siehe Modul B.
6. **Neue oeffentliche Leser** (das ist die Schnittstelle fuer C/D/E):
   `wlibc.radius()` → 0..24, `wlibc.tb_alpha()` → 0..100,
   `wlibc.win_alpha()` → 0..100, `wlibc.tb_blur()` → 0..16,
   `wlibc.set_radius(r)`, `wlibc.set_tb_alpha(a)`, `wlibc.set_win_alpha(a)`,
   `wlibc.set_tb_blur(b)` (setzen + `theme_apply`, fuer die Sofortwirkung der
   Regler, **ohne** Datei — die Datei schreibt Modul E).
   Alle acht in den `export`-Block.
7. `assets/themes/*.preset`: vier Zeilen je Vorlage, **mit unterschiedlichen
   Werten** — mindestens drei verschiedene `radius`, mindestens drei
   verschiedene `taskbar_alpha`, mindestens eine Vorlage mit
   `taskbar_blur > 0`. Der Kopfkommentar jeder Datei sagt, WARUM dieser Wert
   zu dieser Vorlage gehoert (`terminal` scharf, `abendrot` weich, …).
   Der gemessene Kontrastblock im Kopf bleibt stehen.
8. `tools/themestore/build.sh`: die Knoepfe `radius=`, `tbalpha=`,
   `winalpha=`, `blur=` und `wallpaper=<datei>` (fuer die Aufnahmen ueber
   einem gemusterten Hintergrund), und `preset=` liest die vier neuen Zeilen
   aus der Vorlage, **genau wie es heute die sieben liest** — nicht
   abgetippt.

**Gegenprobe, die A selbst liefert:** ein Lauf mit
`script='theme show <id>;exit'` muss `radius=`, `tba=`, `wa=`, `blur=` in der
`theme:`-Zeile melden; ein Lauf mit einer Vorlage, in der `radius=viel` steht,
muss `bad=1` melden.

---

## 7. Modul B — `kern` (mischen, weichzeichnen, Schlieren)

1. `FORM_SLOTS` 9 → 13, die vier neuen `FM_*` aus Abschnitt 2, Klemmen in
   `set_form` (Alpha ≤ 100, Blur ≤ 16, KEY auf `RGB24`).
   **Achtung, die Falle:** `wm.form()` liefert heute `v-1` und speichert
   `v+1`, damit 0 "nie gesetzt" heisst. Fuer die Alphas ist "nie gesetzt"
   aber **100 und nicht 0** — sonst ist die Leiste beim ersten Bild, bevor
   `form_push` lief, unsichtbar. Also ein eigener Leser
   `form_or(state, slot, vorgabe)`, und die Alphas gehen ausschliesslich
   durch ihn.
2. **Die eine Stelle, die mischt, wird eine Zeile breiter.** Neben
   `wm.fb_row` (wortweise Kopie, bleibt unveraendert fuer Alpha 100) entsteht
   `wm.fb_row_a(state, x, y, src, n, alpha, key, grund)`:
   die Schleife aus Abschnitt 3, die **`blend` ruft und sonst nichts rechnet**.
   `fb_row` bleibt der schnelle Weg und wird bei `alpha >= 100` weiter
   genommen — damit ist die Zusage "bei 100 % Bildpunkt fuer Bildpunkt wie
   vorher" nicht behauptet, sondern baulich.
3. `paint_win`, Zweig **ohne** Schmuck (die Taskleiste): Alpha ist
   `FM_TB_ALPHA`, wenn das Fenster `panel_win(state)` ist, sonst
   `FM_WIN_ALPHA`. Zweig **mit** Schmuck: `FM_WIN_ALPHA` fuer die
   Anwendungsflaeche, Schluesselfarbe `deco(DK_TITLE)`/Fensterfarbe. Rahmen,
   Titelleiste und Schatten werden **mit demselben Alpha** gemischt
   (`fill_round` bekommt dafuer einen Alpha-Parameter, der ueber `px_clip` /
   `fb.fill_a` geht — **kein zweites rundes Rechteck**).
4. **Milchglas**, Abschnitt 4: `fn glass_prepare(state, x, y, w, h, r)` in
   `wm.fi`, ein statischer Streifenpuffer `GLASS_MAX` (dokumentierte
   Obergrenze; ist die Leiste groesser, **bleibt Blur aus statt halb zu
   wirken**), drei Durchgaenge mit laufender Summe, Aufhellen/Abdunkeln,
   Zwischenspeicher an `S_GLASSGEN`. Die Zeit je Vollbild in `S_BLURUS` /
   `S_BLURN` / `S_BLURMAX`, gemeldet als **eine Zeile**
   `wm: glas r=<n> px=<n> us=<n> max=<n> cache=<treffer>/<laeufe>` —
   diese Zahl steht spaeter im Abnahmelauf.
5. **Schlierenfreiheit.** In `damage()`: schneidet das gemeldete Rechteck das
   Rechteck der Leiste (`panel_win`) und ist `FM_TB_ALPHA < 100` oder
   `FM_BLUR > 0`, wird es auf die **volle Leistenbreite** aufgezogen. Ein
   Zaehler `S_PANELGROW` sagt, wie oft — die Abnahme liest ihn, damit
   niemand behaupten kann, die Regel sei gelaufen, wenn sie nie zutraf.
6. `wm.selftest` bleibt bei 30/30 und bekommt **zusaetzliche** Faelle:
   `fb_row_a` mit Alpha 0/50/100 gegen von Hand gerechnete Werte, und der
   Weichzeichner gegen eine naiv gerechnete Mitte (dieselbe Zahl ± 1).
7. `sysgui.fi`: nichts als die Rechteprüfung, die schon steht — die vier
   neuen Plaetze gehen durch dasselbe `WM_FORM`. **Keine neue Systemnummer.**

---

## 8. Modul C — `widget` (der Radius kommt ueberall an)

Der Radius kommt aus `met[M_RADIUS_*]` und damit automatisch bei allem an, was
`wlib.draw_radius(rolle)` ruft. **Die Arbeit ist, die Stellen zu finden, die
ihn heute NICHT rufen**, und eine Zahl zu melden, gegen die man das pruefen
kann:

1. Jede Stelle in `kernel/user/wlib.fi`, die eine Flaeche mit fester 0 oder
   einer abgetippten Zahl malt, geht auf `draw_radius(rolle)`. Betroffen sind
   laut `grep` mindestens: Knopf, Eingabefeld, Liste, Karte (`card`),
   Menue, Reiter, Kachel (`tile`), Schieberegler-Bahn und -Griff.
2. **Eine Meldung je Rolle**, einmal je Bild und nicht je Aufruf:
   `wlib: radius rolle=<n> r=<n> typ=<name>` — genau daran misst Modul F
   "der Radius kommt bei jedem Widget-Typ an", und zwar gegen eine
   **Liste von Typen**, nicht gegen eine Gesamtzahl.
3. **Die zweite Zeichenstelle ist bekannt und muss eingefangen werden:**
   `fuib.tafel` schickt das Rechteck an den Vektorzeichner und faellt nur bei
   dessen Ausfall auf `wlibc.rrect` zurueck. Beide Wege bekommen **denselben**
   `r` — das ist schon so, aber `fuib` muss den Wert melden
   (`fuib: tafel r=<n> weg=vektor|rrect`), damit die Abnahme beweisen kann,
   dass nicht ein Weg heimlich eckig malt.
4. **Der Innenraum darf sich nicht verschieben.** `pad_x`, `pad_y`, `row`,
   `ctrl_h` bleiben vom Radius **unberuehrt**; wer hier etwas wie
   `pad + r/2` einbaut, verletzt die Zusage. Gemessen wird es in F durch
   Vergleich der gemeldeten Textkoordinaten bei r = 0, 12 und 24.

---

## 9. Modul D — `leiste` (die Taskleiste)

1. Die Leiste malt ihren Grund und ihre Knoepfe mit `wlibc.radius()` statt
   mit der abgetippten Tabelle bei `taskbar.fi:1357`.
2. **Sie meldet ihre Zahlen:**
   `taskbar: glas alpha=<n> blur=<n> radius=<n> key=<rrggbb>` — eine Zeile,
   nach jedem `theme_poll`, das etwas geaendert hat.
3. `form_push` laeuft schon bei ihr; sicherstellen, dass es **nach jedem**
   erfolgreichen `theme_poll` erneut laeuft (heute nur beim Start), sonst
   wirkt der Regler erst beim naechsten Neustart.
4. Der Grund der Leiste ist **eine einzige Farbe** (`C_PANEL`) — das ist die
   Voraussetzung fuer die Schluesselfarbe aus Abschnitt 3. Ein Verlauf im
   Leistengrund waere ab jetzt ein Fehler; wenn einer drin ist, geht er raus
   und der Grund steht in einem Kommentar.

---

## 10. Modul E — `seite` (die Einstellungen)

Auf `R_DARST`, **vier neue Bedienelemente** mit `wlib.slider`:

| Beschriftung | Bereich | Anzeige |
|---|---|---|
| Eckenrundung | 0..24 | `12 px` rechts daneben |
| Taskleiste Transparenz | 0..100 | `70 %` |
| Fenster Transparenz | 0..100 | `85 %` |
| Milchglas | 0..16 | `8` bzw. `aus` bei 0 |

1. **Sofort sichtbar, ohne Neustart:** jede Meldung des Reglers ruft
   `wlibc.set_radius/set_tb_alpha/set_win_alpha/set_tb_blur` **und**
   `wlibc.form_push()`. Beim Loslassen zusaetzlich `theme_conf_write(...)`.
2. `theme_conf_write` bekommt vier Werte mehr und schreibt vier Zeilen mehr.
   **Die Reihenfolge der vorhandenen Zeilen bleibt** — `tools/desktop/run.sh`
   und `tests/theme/` lesen diese Datei.
3. Die Zahlenanzeige wird aus **dem Wert des Reglers** gebildet, nicht aus der
   Variablen daneben. (Zwei Quellen fuer dieselbe Zahl sind genau die Art
   Fehler, die eine Abnahme dann als "Anzeige stimmt nicht" meldet.)
4. **DIE SEITE MUSS WEITER HINEINPASSEN.** Abschnitt 8 der Abnahme misst jedes
   gemeldete Rechteck gegen die Innenhoehe (heute 0 draussen). Vier Regler mit
   vier Beschriftungen sind rund 140 Bildpunkte; die rechte Spalte ist voll.
   **Vorgabe: umordnen, nicht kuerzen** — der Taskleistenblock (Kante,
   Groesse, Ausblenden, Immer oben, Ausrichtung) wandert in die linke Spalte
   unter den Akzent, die rechte Spalte traegt Hintergrundbild + die vier neuen
   Regler. Wenn das nicht reicht: die zwei Kontrastzeilen (`l_kon`, `l_kon2`)
   zu einer zusammenziehen. **Die Pruefung wird nicht angefasst.**
   *Achtung:* `tools/desktop/run.sh` rechnet seine Klicks aus den gemeldeten
   Rechtecken dieser Seite — es darf danach nicht rot sein, und es zu pruefen
   gehoert zu diesem Modul.
5. Jedes neue Widget geht durch `merke(..., R_DARST)`, sonst meldet es sein
   Rechteck nicht und Abschnitt 8/10 misst es nie.

---

## 11. Modul F — `abnahme` (die Zahlen, die das Ergebnis beweisen)

`tools/themestore/run.sh` behaelt **alle 81 Zusagen unveraendert** — bis auf
die beiden, die auf "genau sieben Schluessel" zaehlen; sie werden auf
**"genau elf, und keiner ausserhalb der elf"** gehoben und um die Gegenprobe
erweitert, dass jeder der vier neuen Schluessel **nur Ziffern** annimmt.
Das ist eine **Verschaerfung**, keine Abschwaechung, und der Kommentar sagt
das.

Neu, als Abschnitt 11 "GLAS":

1. **Radius kommt an.** Drei Laeufe mit `radius=0`, `12`, `24`. Je Lauf die
   Liste der `wlib: radius`-Typen; **jeder Typ meldet genau den gesetzten
   Wert** (Knopf, Eingabe, Liste, Karte, Menue, Reiter, Leiste,
   Leistenknopf). Gegenprobe: bei 0 malt `fill_round` kein einziges
   gemischtes Eckpixel (`wm: aapx=0`), bei 24 sind es mehr als 1000.
2. **Der Inhalt sitzt still.** Die gemeldeten Textkoordinaten der drei Laeufe
   sind **Zeichen fuer Zeichen identisch**; Abweichung 0.
3. **Kantengeglaettet.** `glascheck.py` zaehlt entlang jeder Rundung die
   Zwischenfarben: an einer Ecke mit r = 12 muessen **mindestens 8**
   verschiedene Mischstufen vorkommen. Eine Treppe hat genau zwei.
4. **Alpha mischt wirklich.** Lauf mit gemustertem Hintergrundbild und
   `tbalpha=40`. `glascheck.py` nimmt einen Bildpunkt der Leistenflaeche,
   den Bildpunkt derselben Stelle aus dem Lauf **ohne** Leiste und die
   Leistenfarbe und rechnet `blend` **auf dem Wirt** nach: Abweichung ≤ 1 je
   Kanal. Das ist die "Zahl gegen Hand gerechnet".
5. **Milchglas ist wirklich weichgezeichnet.** Varianz des Ausschnitts unter
   der Leiste mit `blur=0` gegen `blur=12`: sie muss um **mindestens die
   Haelfte** sinken. Gegenprobe: ausserhalb der Leiste ist sie unveraendert
   (± 2 %) — sonst hat der Weichzeichner den halben Schirm erwischt.
6. **Die Zeit steht als Zahl im Lauf.** `wm: glas ... us=<n>` wird gedruckt
   und gegen `< 8000` (µs je Vollbild) geprueft, dazu die Trefferquote des
   Zwischenspeichers.
7. **Kontrast unter Transparenz.** Je ein Lauf mit **hellem** und **dunklem**
   gemustertem Hintergrundbild bei `tbalpha=40`. `glascheck.py` sucht im Bild
   die Schriftbildpunkte der Leiste und rechnet ihren Kontrast **gegen den
   tatsaechlich gemischten Grund daneben** (nicht gegen die theoretische
   Flaechenfarbe): **≥ 4,5:1 in beiden Faellen**. Gegenprobe: ohne das
   Abstandsalpha aus Abschnitt 3 (Schalter `nokey`) muss dieselbe Messung
   **rot** werden — sonst hat die Messung nie etwas geprueft.
8. **Keine Schlieren.** Ein Fenster halb unter die Leiste schieben, bewegen,
   Bild nehmen; dann derselbe Endzustand **frisch aufgebaut** (Vollbild
   neu). Bildvergleich der Leistenzeilen: **0 abweichende Bildpunkte**.
   Gegenprobe: mit abgeschaltetem Aufziehen (`S_PANELGROW`-Regel aus) muss
   die Zahl **grösser als 0** sein. Dazu `S_PANELGROW > 0` als Beweis, dass
   die Regel ueberhaupt zugetroffen hat.
9. **Es sieht wirklich anders aus.** Sieben Aufnahmen nach
   `docs/shots/glas/`: `radius-0`, `radius-12`, `radius-24`,
   `alpha-100`, `alpha-70`, `alpha-40`, `milchglas`. Jede geht durch
   `shotcheck.py` (nichts leer, nichts abgeschnitten, nichts ueberlappend)
   **und** paarweise durch einen Unterschiedszaehler: je zwei Aufnahmen
   derselben Reihe muessen sich in **mehr als 2 %** der Bildpunkte
   unterscheiden. Ein Mensch, der sie nicht auseinanderhaelt, haette auch
   nichts zu sehen bekommen.
10. **Eine Aenderung ueberlebt den Neustart.** Regler schieben (Klick auf die
    gemeldete Reglerbahn), Datei lesen, Maschine neu starten, gemeldeten Wert
    vergleichen. Dieselbe Bauart wie Abschnitt 6 heute.
11. **Kein zweiter Ort fuer dieselbe Sache** — mechanisch:
    `grep -c 'fn fill_round' kernel/ui/wm.fi` = 1,
    `grep -c 'fn rrect' kernel/user/wlibc.fi` = 1,
    `grep -c 'fn blend' kernel/ui/wm.fi` = 1,
    und im Weichzeichner **keine Schleife ueber `r`** im inneren Rumpf
    (gepruft an der gemessenen Zeit: `us` bei r = 16 hoechstens 1,3-mal
    `us` bei r = 4 — bei einer naiven Fassung waere es das Vierfache).

`docs/RUNDE-GLAS.md` traegt alle diese Zahlen, **auch die, die nicht erreicht
wurden**, und benennt jede Abkuerzung ausdruecklich.

---

## 12. Regeln fuer jedes Modul

1. **Stil der vorgefundenen Datei uebernehmen.** `wm.fi`, `taskbar.fi`,
   `settings.fi` kommentieren deutsch, `wlibc.fi` und `wlib.fi` ueberwiegend
   englisch — *in der jeweiligen Datei so weiterschreiben wie dort schon
   geschrieben wird*. Ganze Saetze, die das WARUM erklaeren, mit der
   gemessenen Zahl daneben. Keine Umlaute in Bezeichnern.
2. **Nichts behaupten ohne Messung.** Jede Zusage braucht eine Zeile aus einem
   wirklich gebooteten Kernel oder ein nachgerechnetes Bild.
3. Nach jeder Aenderung muss `bash tools/build-kernel.sh /tmp/<eigen>.img`
   durchlaufen; ein Stand, der nicht baut, ist kein Stand. Eigene Datei- und
   Socketnamen (`/tmp/glas-<modul>-*`), auf dieser Maschine laufen andere
   Laeufe parallel.
4. **Keine fremde Datei anfassen.** Die Tabelle in Abschnitt 5 ist die Grenze.
   Wer etwas in einer fremden Datei braucht, schreibt es hier hinein statt es
   dort zu aendern.
5. Keine Rekursion im Kern (16 KiB Kernstapel), Schleifen stattdessen.
6. **Kleine, erklaerte Commits auf `glas`.** Kein force-push, kein
   Zweigwechsel, nichts loeschen, was man nicht selbst angelegt hat.
7. `bash tools/themestore/run.sh` muss am Ende **vollstaendig gruen** sein,
   und `tools/check-ui.sh` PASSED bleiben.
