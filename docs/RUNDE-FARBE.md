# RUNDE FARBE (15.09.2026, Zweig `farbe`)

Die drei Farb- und Gestaltungspunkte `A-021`, `A-022`, `A-023` aus
`/root/osum-roadmap/OFFEN.md`, einzeln gemessen. Grundlage: `main`
`0a1d067`.

**Die Kurzfassung: ein echter Sachfehler (`A-021`, behoben und
fotografiert), siebzehn rohe Farbwerte, von denen nach Einzelpruefung
SECHZEHN zu Recht roh sind und einer ein echter Fehler war (`A-022`),
und eine Zusage, die die falsche Frage gestellt hat (`A-023`) — plus
ein Messfehler, den erst die neue Zusage sichtbar gemacht hat.**

Abnahme `tests/theme/run.sh`: **vorher 82 gruen / 9 rot, nachher 98
gruen / 0 rot.** (98 und nicht 91, weil `A-023` je Bild jetzt ZWEI
Zusagen macht statt einer — die Flaeche und die Unterscheidbarkeit.)

Weitere Abnahmen: `tools/check-ui.sh` **PASSED**,
`tools/build-kernel.sh` baut (5 818 068 Oktette),
`python3 tools/kernel/memmap.py` meldet **0 Kollisionen** (125
Bereiche). Kein kdata-Bereich und keiner der zugeteilten Modusindizes
1030–1039 wurde gebraucht.

---

## Die Tabelle

| Punkt | Vorher | Nachher | Zustand |
|---|---|---|---|
| `A-021` `text-secondary` auf `surface-hover` | 4,03:1, 4 Zusagen rot | 6,9–7,1:1, alle gruen | **behoben** |
| `A-022` rohe Farbwerte im Zeichencode | 17 | **0** | **behoben** (1 echter Fehler, 16 begruendet) |
| `A-023` `surface` unter den drei haeufigsten | 4 Zusagen rot | 14 Zusagen gruen | **die Zusage war falsch, mit Beleg geaendert** |
| *Nebenbefund* Foto ohne Fenster | still, unbemerkt | Marke statt Rennen | **behoben** |

---

## 1. `A-021` — `text-secondary` war wirklich zu dunkel

**Vorher 4,038:1, nachher 6,974:1. Vier Zusagen, alle gruen.**

Die Empfehlung der Vorrunde (`N_400` → `N_300`) ist **nachgerechnet und
bestaetigt**, nicht uebernommen. Nachgerechnet wurde mit einem eigenen
Skript, `tools/theme/wcag_check.py`, und zwar **bewusst anders** als
`model.py`: `model.py` spiegelt die Festkommarechnung des Kerns Bit fuer
Bit (das ist sein Zweck), waere also bei einem Fehler in dieser
Arithmetik *gemeinsam mit dem Kern falsch* und perfekt einig. Das neue
Skript rechnet in Gleitkomma geradeaus aus dem WCAG-2.1-Text. Beide
kommen auf dieselben Zahlen — damit ist die Rechnung selbst abgesichert.

### Alle Rollenpaarungen, alle Schemata, hell UND dunkel

Gerechnet wurden **110 Paarungen** (11 neutrale Paarungen × 5 Schemata ×
2 Modi), nicht nur die vier gemeldeten:

```
unter der Schwelle VORHER  (text-secondary = N_400 dunkel): 4
unter der Schwelle NACHHER (text-secondary = N_300 dunkel): 0
```

Die betroffenen vier, vorher → nachher:

| Schema | `surface-hover` | `N_400` (alt) | `N_300` (neu) | Soll |
|---|---|---|---|---|
| `day/dark` | `#334155` | **4,038** | **6,974** | 4,5 |
| `paper/dark` | `#44403c` | **4,073** | **6,896** | 4,5 |
| `night/dark` | `#334155` | **4,038** | **6,974** | 4,5 |
| `midnight/dark` | `#3f3f46` | **4,075** | **7,066** | 4,5 |

**Und die Gegenprobe, nach der die Aufgabe ausdruecklich fragt — wird
`N_300` irgendwo anders knapp?** Nein. Die engste andere Paarung ist
gegen `surface-raised` (`N_800`), und dort steht `N_300` bei **9,853**
(day/night), **10,183** (paper), **10,078** (midnight) — weit ueber der
Schwelle. Keine einzige Paarung verschlechtert sich durch die Aenderung;
die vier betroffenen verbessern sich, alle uebrigen bleiben gleich.

**Warum `N_300` und nicht `N_200`:** `N_200` raeumt die Schwelle auch
(8,2–8,4), ebnet aber den Unterschied zwischen `text-primary` (`N_50`)
und `text-secondary` weiter ein — und *gedaempft zu sein* ist der ganze
Sinn dieser Rolle. Die Zahl verlangt `N_200` nicht, also bleibt es bei
der schwaecheren Aenderung.

### An BEIDEN Stellen geaendert

Genau das war die Lehre der Runde KLEINKRAM (vier von fuenf Ursachen
waren zweite Implementierungen im Rueckstand), deshalb in **einem**
Commit:

* `kernel/user/wlibc.fi:3044` — der Kern.
* `tools/theme/model.py:328` — das Modell.

Der Test vergleicht beide gegeneinander (`run.sh` Abschnitt 4 und 5,
`diff` der Rollentabellen), eine einseitige Aenderung waere also sofort
rot geworden — und **das ist der Grund, warum diese Zusage als Riegel
taugt.**

### Auf den Fotos

`docs/bilder/farbe/dark.png`, `midnight.png`. Nachgezaehlt im Bild:

```
dark       alt N_400 #94a3b8 :      0 Punkte
           neu N_300 #cbd5e1 :    284 Punkte
           hover       #334155 :   3956 Punkte
midnight   alt N_400 #a1a1aa :      0 Punkte
           neu N_300 #d4d4d8 :    284 Punkte
           hover       #3f3f46 :   3956 Punkte
```

**Die alte Farbe kommt im Bild ueberhaupt nicht mehr vor** — null
Bildpunkte, nicht „seltener". Die neue steht mit 284 Punkten auf 3 956
Punkten `surface-hover`. Die Aenderung ist also wirklich auf dem
Schirm angekommen und nicht nur in einer Tabelle.

---

## 2. `A-022` — 17 rohe Farbwerte, und nur EINER war ein Fehler

**Vorher 17, nachher 0.** Jeder der 17 ist **einzeln** geprueft, wie
verlangt. Das Ergebnis ist unbequem und geht gegen die Erwartung der
Offenliste („echte Arbeit am Fenstermanager"): **sechzehn davon sind zu
Recht roh, und sie durch fUi-Rollen zu ersetzen haette drei Dinge
kaputtgemacht.** Keiner der sechzehn faerbt einen Knopf, ein Fenster
oder den Schreibtisch — keiner ist Gestaltung.

Die Begruendungen stehen **einzeln und namentlich** in
`tests/theme/rawcolour.py`, nicht pauschal. Der Pruefer hatte dafuer
schon den richtigen Mechanismus (Ausnahmen **nach Funktionsnamen**, nie
nach Muster: *„An exception granted by a pattern is an exception that
grows"*); er konnte nur **eine** Funktion je Datei. Das ist jetzt eine
**Liste** — ausdruecklich, damit drei verschiedene Gruende nicht zu
einem verschmelzen und zwei davon unsichtbar werden.

### (a) `sig_colour`, 8 Werte — ein DRAHTFORMAT, keine Farbe

`wm.fi:4844-4864`. Im Signaturbetrieb (`wmsig`) faerbt der Server je
einen Streifen oben und unten an jedem Fenster mit einer Farbe, die aus
der **Bildnummer** faellt. `tools/vsync/zerreiss.py` liest das Foto
zurueck und zaehlt Reissen: zwei verschiedene Signaturfarben in einem
Fenster = ein halb uebertragenes Bild.

**Dieser Leser traegt dieselben acht Dreier in seiner eigenen Tabelle**
(`zerreiss.py:50`). Die acht Werte sind also ein **Vertrag zwischen zwei
Programmen**, so wie ein Paketkopf — und `sig_nr` (`wm.fi:4709`) bildet
die Farbe sogar wieder **zurueck** auf ihre Nummer, was nur funktioniert,
solange die Zuordnung fest ist. Der Kommentar ueber der Funktion sagt
den Grund seit jeher: *„ein Foto wird maschinell gelesen und ein
Unterschied von eins waere keiner."*

Eine Themenrolle hier haette die Reisserkennung **abgeschaltet**: die
acht waeren nicht mehr weit auseinander, und in einem dunklen Schema
fielen mehrere auf fast gleiche Grautoene zusammen.

### (b) `cg_mal`, 1 Wert — eine DECKUNG, keine Farbe

`wm.fi:5906`. `let weiss: u32 = 0xFFFFFF` fuellt den Zeichenpuffer eines
Titelleistenknopfes. Der Puffer haelt **Deckungen**; welche Farbe daraus
wird, entscheidet `cap_glyph` spaeter aus dem Thema des Servers. Weiss
ist das neutrale Element dieser Multiplikation — eine Rolle an dieser
Stelle wuerde das Thema **zweimal** anwenden. Der Kommentar direkt
darueber sagt das bereits ausdruecklich.

### (c) Die Messtafel, 7 Werte — sie IGNORIERT das Thema mit Absicht

`wm.fi:6447`, `6450`, `6491`, `6525`, `6529`, `6533`, `6537`
(`measure_reason`, `messzeile`, `mess_gruen/rot/weiss/gelb`). Das ist die
Diagnosetafel, die **Justin vom echten Schirm abfotografiert**. Sie ist
nicht Teil des Schreibtischs: sie wird ueber alles gemalt, **bevor** es
eine Taskleiste gibt, und sie muss auf einer Maschine lesbar bleiben,
**deren Thema kaputt ist** — genau die Maschine, auf der sie gebraucht
wird. Schwarzer Grund mit gruener/roter/weisser/gelber Tinte ist fuer die
**Kamera** gewaehlt, und `mess_ampel` benutzt gruen-gegen-rot als
**Bedeutung** („hier kam etwas an" / „hier nicht").

Diese Tafel an das Markensystem zu binden hiesse: das eine Instrument,
das funktionieren muss, **wenn das Markensystem falsch ist**, davon
abhaengig zu machen, dass das Markensystem stimmt.

### (d) `taskbar.fi:3598` — DAS war der echte Fehler

`var q: u64 = v & 0xFFFFFF` schneidet das Alpha-Oktett von einem
Bildpunkt ab. Das ist eine **Maske**, keine Farbe — und `rawcolour.py`
kann die beiden der Form nach nicht unterscheiden. Dafuer gibt es bereits
eine benannte Konstante, `wlibc.RGB24`, und **genau diese Aenderung hat
`wlibc.fi:1625` in der Runde MERGE schon einmal gemacht**, mit derselben
Begruendung im Kommentar. `taskbar.fi` war nicht nachgezogen.

Geaendert auf `v & wlibc.RGB24`. **Hier war der Quelltext im Unrecht,
nicht der Pruefer** — deshalb ist das die einzige der 17 Stellen, an der
die *Datei* geaendert wurde und nicht die Ausnahmeliste.

### Der Pruefer misst weiter etwas

Die Gegenprobe im Testlauf laeuft denselben Pruefer auf dem Stand **vor**
der Runde und findet dort weiterhin Treffer:

```
OK    rohe Farbwerte im Zeichencode: 0
OK    Marken, die statt dessen benutzt werden: 195
OK    derselbe Pruefer auf dem Stand vor der Runde: 18
```

**Der Pruefer ist also nicht stumpf geworden**, sondern weiss jetzt
namentlich, welche Farben keine Gestaltung sind.

---

## 3. `A-023` — die Zusage hat die falsche Frage gestellt

**Vorher 4 Zusagen rot, nachher 14 gruen.** Die Offenliste liess offen,
ob die Zusage die falsche Rolle prueft oder die Oberflaeche die falsche
nimmt. **Gemessen wurde beides, an den Bildern — und die Antwort ist
eindeutig: die Oberflaeche ist in Ordnung, die Zusage war es nicht.**

### Was die Bilder zeigen

`tools/theme/shots.sh` (neu) baut dieselben sieben Bilder wie der Test,
laesst sie aber liegen. Nachgezaehlt:

| Schema | `surface` | Punkte | Anteil | Rang |
|---|---|---|---|---|
| `light` | `#f8fafc` | 80 879 | 7,9 % | 4 |
| `green` | `#f8fafc` | 80 879 | 7,9 % | 4 |
| `violet` | `#f8fafc` | 80 879 | 7,9 % | 4 |
| `gold` | `#fafaf9` | 80 879 | 7,9 % | 6 |
| `dark` | `#0f172a` | 80 879 | 7,9 % | 3 |
| `midnight` | `#18181b` | 80 879 | 7,9 % | 3 |

**Achtzigtausendachthundertneunundsiebzig Punkte in allen sechs, auf
dieselben Zeilen genau (y = 92…451, die Fensterflaeche).** Die
Oberflaeche malt `surface` also **ueberall gleich**. Sie nimmt **nicht**
die falsche Rolle, und `surface` **fehlt auch nicht im Bild** — die
Zusage sagte „fehlt", obwohl die Farbe mit 7,9 % dastand.

Die Vermutung der Offenliste („der Schreibtisch malt ueberwiegend
`surface-sunken`") stimmt zwar als Beobachtung — er malt einen **Verlauf**
von `surface-sunken` (oben) nach `surface` (unten), linear je Kanal
(`desktop.fi:204`) —, ist aber **nicht der Grund** fuer den Unterschied
zwischen hell und dunkel: der Verlauf gibt reines `surface` in **jedem**
Schema nur eine einzige Zeile, hell wie dunkel. Die 7,9 % kommen aus dem
**Fensterhintergrund** (`C_WINDOW_BG` → `S_SURFACE`, `wlibc.fi:3235`).

### Warum hell durchfiel und dunkel nicht

Nicht die Oberflaeche unterscheidet sich, sondern die **Rampengeometrie**:

| Schema | \|sunken − surface\| | Verlaufsstufen im Bild |
|---|---|---|
| `gold` | 5 | 6 |
| `light` | 7 | 14 |
| `midnight` | 16 | 31 |
| `dark` | 19 | 47 |

Hell liegen die beiden Rampenstufen dicht beieinander: **wenige, dafuer
breite** Baender, und zwei davon (`#f7f9fb` 10,4 %, `#ffffff` 9,7 %)
schieben sich vor die 7,9 % von `surface`. Dunkel sind es 31 bis 47
**duenne** Baender, von denen keines an 7,9 % heranreicht. Sichtbar ist
das direkt im Bild, Mittelspalte, Verlaufsband y≈593…769: `light` hat
dort **drei** breite Stufen, `midnight` **sieben**, `dark` **zehn**.

**Ein Rang ist hier also gar keine Aussage ueber die Oberflaeche.** Er
misst, wie fein ein Verlauf quantisiert — und das ist eine Eigenschaft
der Rampe, nicht der Zeichenroutine.

### Die neue Zusage — geaendert, nicht entschaerft

Die Rolle wird jetzt an ihrer **Flaeche** gemessen statt an ihrem Rang
(`pixel.py --share`, in Zehntelprozent, weil `sh` nur ganze Zahlen
vergleicht):

* `surface` muss **mindestens 3 %** des Bildes tragen. Gemessen sind es
  **7,9 %** — mehr als das Doppelte; die Zusage bricht, sobald die
  Fensterflaeche halbiert wird. Zum Vergleich: eine einzelne
  Verlaufsstufe kommt nie ueber 0,4 %, ein versehentlich mit einer
  Verlaufsfarbe gemaltes Fenster faellt also durch.
* **Und eine Gegenprobe, die die alte Zusage nicht hatte:** `surface`
  und `surface-sunken` muessen im Bild **verschieden** sein. Genau das
  war der Fehler, den Commit `65d3300` gefunden hat (zwei Rollen auf
  derselben Rampenstufe, der Zeiger aenderte nichts) — **eine Zusage
  ueber den Rang haette ihn nicht bemerkt, eine ueber Verschiedenheit
  schon.** Die Zusage ist damit schaerfer als vorher, nicht weicher.
* **Ausnahme mit Grund:** im Hochkontrastschema sind `surface`,
  `surface-raised` und `surface-sunken` **mit Absicht** alle `N_0` (der
  Zweig `if high`); wer hohen Kontrast braucht, soll Flaechen nicht an
  zarten Helligkeitsstufen unterscheiden muessen, sondern an Raendern.
  Dort wird Gleichheit **gefordert** statt verboten — eine Zusage, die
  dort Verschiedenheit einklagt, wuerde genau das Merkmal verlangen, das
  dieses Schema bewusst weglaesst.

---

## 4. Nebenbefund: ein Foto ohne Fenster, und niemand hat es gemerkt

**Erst die neue Zusage aus `A-023` hat das sichtbar gemacht** — und es
ist genau die Art Fehler, um die es in dieser Runde geht.

Im ersten Lauf mit der neuen Zusage trugen `light` und `dark`
**0,0 %** `surface`, waehrend `green` und `violet` — **dasselbe Schema,
dieselbe Aufloesung**, nur spaeter im Lauf — 7,9 % trugen. Der
Unterschied war nicht das Thema: **das Fenster war noch nicht offen.**

`foto()` wartete auf `wm: hold`. Das heisst aber nur, dass der
**Fenstermanager** steht; die Programme im Schreibtisch startet `kgui`
**danach** (`kgui.fi:3478`, `desk_spawn_n` fuer `/bin/themetest`). Wer
bei `wm: hold` fotografiert, faengt den Schreibtisch mit einer gewissen
Wahrscheinlichkeit **ohne** das Fenster — und die beiden ersten Bilder
verlieren dieses Rennen am oeftesten, weil die Platte dann noch kalt ist.

**Die alte Zusage hat das nie bemerkt**, weil `surface-sunken` den
Verlauf auch ohne Fenster anfuehrt: ein Bild ohne Fenster sah fuer sie
genauso aus wie eines mit. Sie war gegen den Fehler blind, den zu finden
ihr Zweck war.

`foto()` wartet jetzt auf eine **Marke, die der Aufrufer nennt**; die
Bilder warten auf `themetest: gui ready`, das das Programm meldet,
**nachdem** sein Fenster steht (`themetest.fi:538`). Das ist keine
Wartezeit auf Verdacht, sondern die Marke des Programms, das auf dem Bild
stehen soll. Danach messen **alle sieben** Bilder stabil 7,9 %.

---

## Was diese Runde ueber die Offenliste sagt

Von den drei Punkten war **einer** ein echter Sachfehler im Kern
(`A-021`), **einer** zu 16/17 eine falsche Erwartung an den Quelltext
(`A-022` — die Offenliste nannte ihn „echte Arbeit am Fenstermanager";
tatsaechlich war eine einzige Zeile falsch, und die war eine Maske, keine
Farbe), und **einer** eine Zusage, die etwas anderes gemessen hat, als
sie zu messen glaubte (`A-023`).

**Das Muster der Runde KLEINKRAM setzt sich fort, aber mit einer
Ergaenzung.** Dort waren vier von fuenf Ursachen *zweite
Implementierungen, die einer richtigen Kernaenderung nicht nachgezogen
wurden*. Das kam auch hier zweimal vor (`model.py` gegen `wlibc.fi` bei
`A-021`, `taskbar.fi` gegen `wlibc.fi` bei `A-022` — beide Male hatte die
**erste** Stelle recht). Neu ist die andere Sorte:

**eine Zusage, die eine Groesse misst, die von etwas anderem abhaengt als
von dem, was sie pruefen will.** Der Rang einer Farbe haengt an der
Quantisierung eines Verlaufs, nicht an der Zeichenroutine — deshalb war
sie hell rot und dunkel gruen, obwohl die Oberflaeche in beiden Faellen
Bild fuer Bild dasselbe tat. Und weil sie das Falsche mass, war sie
gleichzeitig **blind** fuer ein Bild ohne Fenster.

Die neuen Zusagen sind deshalb bewusst an Groessen gebunden, die nicht
wegdriften koennen: die **Flaeche** einer Rolle (nicht ihr Rang), die
**Verschiedenheit** zweier Rollen (nicht ihre Reihenfolge), und eine
**Marke des Programms** statt eines Rennens gegen den Systemstart.

**Kein Test wurde entschaerft.** Wo eine Erwartung geaendert wurde
(`A-023`), steht der Beleg im Quelltext daneben und oben in diesem
Bericht, und die Zusage ist dabei **schaerfer** geworden. Die vier
Kontrastzusagen aus `A-021` wurden erfuellt und nicht gesenkt — die
Schwelle steht unveraendert auf 4,5:1.

---

## Dateien

| Datei | Was |
|---|---|
| `kernel/user/wlibc.fi` | `A-021`: `text-secondary` dunkel `N_400` → `N_300`, mit Messung im Kommentar |
| `tools/theme/model.py` | `A-021`: dieselbe Aenderung im Modell, im selben Commit |
| `kernel/user/taskbar.fi` | `A-022`: `0xFFFFFF` → `wlibc.RGB24` (Maske, keine Farbe) |
| `tests/theme/rawcolour.py` | `A-022`: Ausnahmen je Datei als **Liste**, jede Funktion einzeln begruendet |
| `tests/theme/run.sh` | `A-023`: Flaeche statt Rang, plus Gegenprobe; `foto()` wartet auf eine Marke |
| `tests/theme/pixel.py` | `A-023`: `--share` (Anteil in Zehntelprozent) |
| `test.sh` | die neuen Zusagennamen in den Sichtbarkeitsfilter |
| `tools/theme/wcag_check.py` | **neu** — WCAG in Gleitkomma, unabhaengig von der Festkommarechnung |
| `tools/theme/shots.sh` | **neu** — die sieben Bilder, und sie bleiben liegen |
| `docs/bilder/farbe/*.png` | die sieben Bilder (verkleinert auf 640×400) |
