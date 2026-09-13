# RUNDE FUI-WIN11 -- Belege und ehrlicher Befund

Zweig `fui-win11` im Baum `/root/jarvis/projects/u_DiS4in7esMF1/osum`,
abgezweigt von `main` = 5549984.

---

## 0. ZUERST: DER AUFTRAG GING VON EINER FALSCHEN LAGE AUS

Der Auftrag nennt eine Arbeitsliste ("qs.fi fui=0 roh=9",
"wlib.fi fui=1 roh=96", "launcher.fi roh=5", Ziel "NULL rohe
Malaufrufe ausserhalb von fUi"). **Diese Zahlen stimmen in diesem Baum
nicht**, und das laesst sich in einem Befehl nachrechnen:

```
$ grep -acE 'wlibc\.(rect|hline|vline|frame|frame3|px|rrect|rframe|rring|vrect|vkreis|divider|drop_shadow)\(' kernel/user/*.fi | awk -F: '$2>0{print $2" "$1}'
64 kernel/user/wlib.fi
 6 kernel/user/icont.fi
 3 kernel/user/fuib.fi
```

`qs.fi`, `launcher.fi`, `taskmgr.fi`, `wlibc.fi`, `storage.fi`,
`explorer.fi`, `taskbar.fi`, `settings.fi` haben **null** rohe
Malaufrufe. Und `tools/check-ui.sh` -- die Pruefung, die genau Justins
Regel durchsetzt -- war schon **vor** meiner ersten Zeile gruen:

```
$ bash tools/check-ui.sh
  166 Dateien geprueft
  0 Programme malen sich ein Bedienelement selbst
  0 Programme greifen an der Bibliothek vorbei auf fUi zu
  0 Funktionen in wlib.fi malen an fUi vorbei
CHECK-UI PASSED.
```

**Der Umbau "alles auf fUi" ist in diesem Baum bereits passiert** --
in den Runden 31/32, ueber die Bruecke `kernel/user/fuib.fi`. Die
Architektur ist: Programm -> `wlib` (Fensterverwaltung, Layout,
Zustaende) -> `fuib` -> `lib/fui`. Der Kopf von `fuib.fi` begruendet
das ausfuehrlich: fUi ist *immediate mode*, wlib *retained mode*; wer
sie in einem Schritt tauscht, fasst 23 Programme mit ueber 1300
Aufrufstellen gleichzeitig an.

### Warum "importiere fUi direkt in qs.fi" technisch nicht geht

```
$ vendor/firn/bin/firnc -c kernel/user/qs.fi -o /tmp/qs.o
error: the module 'std.rt' belongs to the standard library and is not
available in profile 'kernel'
   --> vendor/firn/lib/fui/theme.fi:81:1
```

`qs.fi` ist `profile kernel` (es ist Teil der Taskleiste). fUi braucht
`std.rt`. Ein direkter Import ist vom Uebersetzer gesperrt -- und
`tools/check-ui.sh` verbietet ihn zusaetzlich als "eigene Oberflaeche
daneben". Genau dafuer gibt es die Bruecke.

**Also habe ich das getan, was Justin WIRKLICH stoert** (er schreibt
ueber das AUSSEHEN, nicht ueber die Modulstruktur): das
Kontrollzentrum und den Starter im Windows-11-Schnitt, ueber die
vorhandene Bibliothek, ohne die Regel zu brechen.

---

## 1. DIE BILDER

| Datei | was darauf zu sehen ist |
|---|---|
| `01-vorher-desk.png` | Schreibtisch mit **Starter**, Stand `main`. Trefferliste einzeilig, 28 px je Zeile, "Name  --  Beschreibung" in EINER Zeile. |
| `02-vorher-qs.png` | **Kontrollzentrum**, Stand `main`. 388x370. Unter jeder Kachel ein Zustandswort ("an"/"aus"), ueber jedem Regler eine Ueberschrift, Zeile "Akku: keiner". |
| `03-nachher-qs.png` | Kontrollzentrum nach dem Umbau. 388x**286**. Kein Zustandswort, Symbol statt Ueberschrift, aktive Kachel voll in Akzentfarbe. |
| `04-akzent-gruen-qs.png` | **Dasselbe Panel, Vorlage `tafel` (Akzent 15803d)**. Gleiches Layout, gruene statt blauer Kachel -- die Akzentprobe. |
| `05-nachher-starter.png` | Starter nach dem Umbau: Trefferliste **zweizeilig**, Name oben, Beschreibung gedaempft darunter. |
| `06-final-qs.png` | Kontrollzentrum im Endstand (mit dem Starter-Umbau im selben Abbild). |

Dazu die Mitschnitte `01-vorher-abnahme.log` und `05-nachher-abnahme.log`.

---

## 2. WAS SICH MESSBAR GEAENDERT HAT

### Kontrollzentrum (`kernel/user/qs.fi`)

Gemessen im Fenster (`wm: fen id=10`), nicht geschaetzt:

| | vorher | nachher |
|---|---|---|
| Fensterhoehe | 370 | **286** (-84 px, -23 %) |
| Tinte (Textpunkte) im Panel | 2333 | **1871** (-19,8 %) |
| Akzentflaeche im Panel | 4580 Pkt (3,17 %) | **8170 Pkt (7,28 %)** |
| Zustandswoerter "an"/"aus" | 4 (je Kachel eines) | **0** |
| Regler-Ueberschriften | 2 ("Helligkeit", "Lautstaerke") | **0** (Symbol links) |

Die vier Kacheln tragen jetzt echte Vektorsymbole aus `lib/icons.fi`
(gemessen: 84 / 113 / 230 / 136 Tintenpunkte im 16x16-Symbolfeld) statt
der alten festen OSYM-Bilder, die bei `ui_scale=2` nicht mitwuchsen.

**Der Zustand ist die Farbe:** im Nachher-Bild ist genau EINE Kachel
(Reihe 1, Spalte 0) mit 8074 Punkten `#2563eb` voll ausgefuellt -- das
ist die eingeschaltete. Die anderen drei sind weiss. Kein Wort sagt es
mehr, der Farbblock tut es.

### Starter (`kernel/user/launcher.fi` + `wlib.fi`)

Tintenzeilen im Starterfenster, gemessen:

```
VORHER                          NACHHER
 y 146-163 (18 hoch)             y 117-135 (19 hoch)  <- Name
 y 174-191 (18 hoch)             y 140-150 (11 hoch)  <- Beschreibung
 y 202-219 (18 hoch)             y 163-181 (19 hoch)  <- Name
                                 y 186-199 (14 hoch)  <- Beschreibung
```

Aus einer Zeile je Treffer sind zwei geworden. Die Farben belegen die
Hierarchie: Zeile 1 `#0f172a` (Volltext), Zeile 2 `#475569` (T_DIM,
gedaempft) -- genau die Windows-Ordnung.

---

## 3. DIE AKZENTFARBE -- JUSTINS NACHTRAG

### Der Befund "accent= ist leer" stimmt, die Schlussfolgerung nicht

`assets/themes/tageslicht.preset` hat `accent=` (leer). Das ist **kein
Fehler**, sondern ein dokumentierter Wert: der Kopf jeder Vorlage sagt
"accent -- the accent, or empty for the scheme's own". `vorlage.fi`
traegt dafuer `ACC_NONE` und **nicht 0**, weil 0 Schwarz waere und
damit eine echte Farbe.

Die Farbe, die dann gilt, steht im Schema:
`assets/schemes/day.scheme:37: accent=2563eb`. `wlibc.bind_accent`
legt sie auf die Rampe, samt WCAG-Kontrollrechnung, und schreibt sie
nach `sem[S_ACCENT]` -> `comp_role[C_ACCENT]` -> `tok[]` ->
`theme(T_ACCENT)`. `T_ACCENT` und `C_ACCENT` sind beide 15.

**Es gibt also kein fest verdrahtetes Blau.** Nachgerechnet:
`grep -E '0x[0-9a-fA-F]{6}'` findet in `qs.fi` und `launcher.fi`
**null** Farbliterale; alle 36 Farbstellen in `qs.fi` gehen ueber
`wlibc.theme(wlibc.T_*)`.

Was falsch war, war die **Meldung** des Baus: sie schrieb `accent=-`,
und daraus liest sich "es gibt keine". Das ist behoben --
`tools/usbimg/build.sh` schlaegt jetzt nach und meldet die Farbe, die
wirklich gilt:

```
akzent      #2563eb (aus schema day) -- das ist die Farbe, die aktive
            Kacheln, Auswahl und Fokusring tragen
```

### Die Probe: zwei Abbilder, gleiche Quelle, andere Vorlage

| | `#2563eb`-Punkte | `#15803d`-Punkte |
|---|---|---|
| `tageslicht` (Schema-Akzent 2563eb) | **8170** | 0 |
| `tafel` (Vorlagen-Akzent 15803d) | 0 | **8170** |

Dieselbe Zahl, dieselbe Flaeche, dieselben Punkte -- nur die Farbe
wechselt. Die Kachel zieht die eingestellte Akzentfarbe und nichts
anderes.

### Kanalprobe (gegen die R/B-Vertauschung, die es hier schon gab)

```
blau : gemessen #2563eb  soll #2563eb  IDENTISCH   R 37/37  G 99/99  B 235/235
gruen: gemessen #15803d  soll #15803d  IDENTISCH   R 21/21  G 128/128 B 61/61
```

Keine Vertauschung. Gesucht wurde ausdruecklich auch nach `#eb6325`
(R/B getauscht): **0 Punkte** in jedem Bild.

---

## 4. DIE ABNAHME -- NICHTS KAPUTTGEMACHT

```
Basisstand (main):   USBIMG: 44 bestanden, 4 gescheitert
Nach dem Umbau:      USBIMG: 44 bestanden, 4 gescheitert
```

Es sind **dieselben vier**: UEFI-Firmwareerkennung, UEFI-Rahmenpuffer,
"Starter ist nicht deutsch", Taskleisten-Text. Alle vier standen schon
vorher an und haengen nicht an der Oberflaeche.

**Eine Warnung fuer den naechsten Lauf:** ein Zwischenlauf meldete
42/6 -- zwei zusaetzliche Fehler in Abschnitt 6 und 7 ("der Kern kommt
nicht mehr bis zum Ende", "der Bericht bricht ab"). Das war **kein
Regress**, sondern Last: auf der Maschine liefen gleichzeitig zwei
weitere Auftraege und meine eigenen Bauten (load average 3,2). Der
Beleg ist der Mitschnitt selbst -- `fremd.txt` bricht **mitten im
Wort** ab ("...h"), statt `hwdiag: ANGEHALTEN` zu erreichen. Derselbe
Lauf auf ruhiger Maschine: 44/4. Wer diese Abnahme faehrt, sollte die
Maschine in Ruhe lassen.

---

## 5. WAS NOCH ROH MALT -- DIE EHRLICHE RESTLISTE

Ausserhalb der Bibliothek: **nichts**. Innerhalb:

| Datei | rohe Aufrufe | Lage |
|---|---|---|
| `wlib.fi` | 64 | IST die Bibliothek -- irgendwo muessen die Bildpunkte herkommen |
| `icont.fi` | 6 | Symbol-Pruefstand: malt Symbole Punkt fuer Punkt und VERGLEICHT sie |
| `fuib.fi` | 3 | die Naht zu fUi selbst |

Alle drei stehen mit Begruendung in `ERLAUBT_ROH` in
`tools/check-ui.sh`. Aufgeschluesselt nach Funktion in `wlib.fi`
(`roh` = rohe Aufrufe, `fuib` = fragt die Bruecke):

```
paint_tile    roh=12 fuib=2      paint_image   roh=7  fuib=0
paint_check   roh=5  fuib=1      paint_tabs    roh=5  fuib=2
paint_button  roh=4  fuib=2      paint_graph   roh=3  fuib=0
paint_list    roh=3  fuib=1      paint_table   roh=3  fuib=3
draw_board    roh=3  fuib=1      paint_curve   roh=2  fuib=0
paint_entry   roh=2  fuib=2      draw_edge3    roh=2  fuib=0
... sowie je 1: paint_bg, focus_ring, image_paint, paint_choice,
paint_sep, paint_card, paint_menu, draw_area, draw_separator,
draw_frame, draw_line, draw_bar, draw_point
```

Wo `fuib > 0` steht, ist das rohe Malen der **Rueckfall hinter** der
Bruecke (ohne Fensterflaeche kann fUi nicht malen; ein Element, das
dann gar nicht erscheint, waere schlimmer als ein eckiges). Wo
`fuib = 0` steht, ist es eine **begruendete Ausnahme** aus
`AUSNAHMEN_LIB`: Fensterhintergrund, Diagramme (fUi hat dafuer kein
Element), Bildflaechen (die Punkte gehoeren dem Bild), der Trenner mit
der Deckkraft der Formentabelle, die zwei Kanten des klassischen
Erscheinungsbilds.

### Was ich NICHT gemacht habe und warum

* **`wlib.fi` weiter aufloesen.** `paint_tile` (12 roh) und
  `paint_image` (7 roh) sind die dicksten Posten. `paint_image` ist
  eine begruendete Ausnahme und bleibt. `paint_tile` liesse sich
  weiter an die Bruecke haengen -- das ist aber ein Eingriff in das
  Element, das der Schreibtisch, die Leiste und die Einstellungen
  gemeinsam benutzen, und er gehoert mit eigener Abnahme gefahren,
  nicht nebenbei.
* **Die uebrigen Programme.** `taskmgr.fi`, `storage.fi`,
  `themetest.fi` usw. malen bereits nichts roh; an ihnen gibt es
  nichts umzustellen. Was man an ihnen tun KANN, ist dieselbe
  Windows-Politur wie hier (weniger Wort, mehr Symbol) -- das ist
  Gestaltung, nicht Architektur, und es stand nicht im Kern von
  Justins Kritik.
* **Bilder/SVG aus dem Parallelauftrag.** `vendor/firn/lib/fui/image.fi`
  gibt es in diesem Baum nicht, und `git branch -a` zeigt keinen
  fertigen Zweig damit. Ich habe **keine zweite Bildloesung gebaut**
  (das waere gegen die Regel) -- ich habe stattdessen die Symbolschrift
  benutzt, die es schon gibt: `lib/icons.fi`, 46 Vektorsymbole, ueber
  `wlibc.icon_at` in jeder Groesse und jeder Farbe. Damit brauchte
  dieser Umbau den Parallelauftrag gar nicht.

---

## 6. DIE COMMITS

```
a20a671  das Kontrollzentrum im Windows-11-Schnitt
(+2)     ein Foto vom KONTROLLZENTRUM, nicht nur vom Starter
(+3)     der Bau meldet die AUFGELOESTE Akzentfarbe
(+4)     der Starter zweizeilig -- Name oben, Beschreibung darunter
```

Neues Werkzeug: `tools/usbimg/shot-qs.sh` -- fotografiert das
Kontrollzentrum (run.sh fotografiert nur den Starter). Im Kopf stehen
die drei Dinge, an denen der erste Anlauf scheiterte: `wmhold` ist das
Ende und nicht der Betrieb, Super allein oeffnet das Startmenue statt
des Panels, und das Bild kommt per `screendump` aus dem Monitor.

---

## 7. DUNKELMODUS -- JUSTINS PUNKT 4, NACHGERECHNET

`theme.fi` sagt ausdruecklich, `text_on_accent` sei im Dunkelmodus
NICHT Weiss. Nachgemessen an einem dritten Abbild
(`THEMA=mitternacht`, `mode=dark`, Vorlage-Akzent `8b5cf6`), Bild
`07-dunkelmodus-qs.png`:

**Die Schrift auf der aktiven Kachel ist SCHWARZ, nicht Weiss.**

```
Hellmodus  (#2563eb blau):    WEISS  auf Akzent  5,17:1   <- weiss gemalt
                              schwarz auf Akzent 4,06:1
Dunkelmodus(#b799f9 violett): weiss  auf Akzent  2,35:1
                              SCHWARZ auf Akzent 8,94:1   <- schwarz gemalt
```

Das System waehlt die Schriftfarbe also **nach gemessenem Kontrast**
und nicht nach einer festen Regel -- genau das, was `pick_on()` in
`wlibc.fi` tut (es prueft `neutral[N_0]`, `neutral[N_1000]` und
`neutral[N_900]` gegen den Grund und nimmt den besten). Waere hier
Weiss gemalt worden, waere die Aufschrift mit 2,35:1 praktisch
unlesbar.

### Und der Akzent selbst wird verschoben -- mit Grund

Im Bild steht nicht `#8b5cf6`, sondern `#b799f9`:

```
Vorlage #8b5cf6 gegen Panelgrund #27272a : 3,52:1
Gemalt  #b799f9 gegen Panelgrund #27272a : 6,34:1
```

Das ist `bind_accent`: es sucht auf der Akzentrampe den Schritt, der
**beide** WCAG-Regeln zugleich erfuellt (1.4.11 fuer die Flaeche,
1.4.3 fuer die Schrift darauf) und meldet die Verschiebung ehrlich --
die Einstellungen zeigen sie als "Akzent um N Schritte verschoben"
(`theme_accent_moved`, `settings.accent.moved`). Der Kopf von
`bind_accent` begruendet das an genau diesem Fall: "on a green the
readable label is BLACK, so walking the ramp darker to satisfy the
surface rule walks the label rule off a cliff".

**Fazit zu Punkt 4:** die Zusage aus `theme.fi` gilt in diesem Baum,
und zwar gemessen und nicht behauptet. In beiden Modi ist die
Aufschrift der aktiven Kachel lesbar, ohne dass irgendwo eine Farbe
fest steht.

### Die drei Abbilder nebeneinander

| Vorlage | Modus | Akzent laut Konfiguration | im Bild gemalt | Schrift darauf |
|---|---|---|---|---|
| `tageslicht` | hell | `2563eb` (aus Schema `day`) | `#2563eb` unveraendert | weiss |
| `tafel` | hell | `15803d` (aus Vorlage) | `#15803d` unveraendert | weiss |
| `mitternacht` | dunkel | `8b5cf6` (aus Vorlage) | `#b799f9` (Rampe, +Kontrast) | **schwarz** |

In allen drei Faellen traegt dieselbe Kachelflaeche (8074 Punkte) die
jeweils eingestellte Farbe. Kein Farbliteral im Programmcode --
nachgerechnet mit `grep -E '0x[0-9a-fA-F]{6}'` ueber `qs.fi` und
`launcher.fi`: null Treffer.
