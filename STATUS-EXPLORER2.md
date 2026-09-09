# STATUS — RUNDE EXPLORER-2

**Zweig** `explorer2`, abgezweigt von `merge9` bei `cad06fb`.
**Arbeitsbaum** `/root/osum-explorer2` (eigener Worktree; in `merge9`
wurde nicht gearbeitet, dort lief parallel die Runde TÜRSCHLOSS).
**Nicht gemergt, nicht im Abbild.**

Justins Vorgabe war ein Satz: der Dateimanager muss können, was
Windows-Explorer, Nautilus, Dolphin und Thunar **alle** können.

---

## 1. Was vorher war

Der geprüfte Befund (Jarvis, 09.09.2026, gegen `merge9 cad06fb`):

Der Explorer konnte Baum, sortierbare Tabelle, Zurück/Vor/Hinauf,
Doppelklick, Kontextmenü mit Umbenennen/Löschen/Neuer Ordner/ZIP.

Er konnte **nicht**: einfügen, ausschneiden, Ordner kopieren,
Mehrfachauswahl, Eigenschaften, Seitenleiste, Breadcrumbs, Filter,
Symbolansicht, versteckte Dateien, Konflikt- und Fortschrittsdialog,
Rückgängig, Öffnen-mit.

Und drei Dinge waren nicht nur „fehlend", sondern falsch:

* **Umbenennen war Kopieren und Löschen.** Bei einem *Verzeichnis*
  kopiert diese Schleife nichts (`read` auf ein Verzeichnis gibt
  EISDIR) und löscht danach das Original. Einen Ordner umbenennen hieß
  in diesem System: **den Ordner verlieren.**
* Die Zeit-Spalte zeigte `--`, obwohl OFS v3 seit Runde OFS3 echte
  Zeitstempel führt. Der Dateikopf behauptete noch, das Dateisystem
  habe keine.
* `explorer.fi:1638` und `:1665` prüften **beide** `if welches == 4`;
  der zweite Zweig — der Netzzugriff-Menüpunkt — war unerreichbar.

---

## 2. Die Tafel: Punkt → Stand → Beleg

Belege sind Zeilen der seriellen Leitung aus dem Abnahmelauf
(`tools/explorer2/run.sh`) und die Bilder unter
`.explorer2-shots/`. Kein Punkt steht auf „sieht gut aus".

| # | Punkt | Stand | Beleg |
|---|---|---|---|
| 1 | Zwischenablage Strg+C/X/V, Dateien **und** Ordner rekursiv, über den Systembus | **fertig** | `explorer: clip n=8 schnitt=0` · `explorer: paste n=7 sprung=1 rc=0` · Bild `12-eingefuegt` |
| 2 | Umbenennen über `SYS_RENAME`, F2, Konfliktdialog | **fertig** | `explorer: rename rc=0` · `explorer: dlgrect` · Quelltext: `io.rename` in `expakt.fi`, alte Kopierschleife in `explorer.fi` weg · Bild `17-umbenennen` |
| 3 | Mehrfachauswahl im Framework (Strg-Klick, Shift-Bereich, Rahmen, Strg+A) | **fertig** | `explorer: sel n=8 anker=3` · `wlib.sel_*`-API · Bild `11-auswahl` |
| 4 | Eigenschaften (Alt+Enter), Ordnergröße rekursiv, drei echte Zeiten | **fertig** | `explorer: taste 288` → `explorer: props zeilen=8 bytes=14 stueck=1` · Bild `14-eigenschaften` |
| 5 | Zeit-Spalte gefüllt, sortierbar, Ortszeit wie die Taskleiste | **fertig** | `explorer: zeit mtime=… mit=9 von=9 tzoff=120` — **9 von 9** Einträgen tragen eine echte Zeit |
| 6 | Seitenleiste mit Orten + Datenträgern, Breadcrumb, Strg+L | **fertig** | `explorer: orte n=5 traeger=…` · `explorer: krume n=2` · `explorer: krume n=2 feld=1` · Bild `16-pfadfeld` |
| 7 | Tastenkürzel-Standardsatz | **fertig** | `taste 1` (Strg+A) · `taste 3` (Strg+C) · `taste 22` (Strg+V) · `taste 273` (F2) · `taste 276` (F5) · `taste 288` (Alt+Enter) · `taste 304 an=1/an=0` (Strg+H) |
| 8 | Fortschritt abbrechbar, **kein** stummer Fehlschlag | **fertig** | `expakt.fehler_schluessel` bildet jeden `rc` auf einen Katalogtext ab; `explorer: fehler rc=` |
| 9 | Rückgängig (Strg+Z) für Umbenennen, Verschieben, Korb | **fertig** | `explorer: undo art=… rc=0` nach echtem Umbenennen |
| 10 | Öffnen mit…, Neue Datei, Symbolansicht mit Miniaturen | **fertig** | `explorer: openwith n=…` · `explorer: mini w= h=` · `explorer: view` |
| 11 | Grenzen: MAXENT 96→4096, NAMEB 32→256, Historie 8→64; toter Zweig weg | **fertig** | `MAXENT = 4096` · `NAMEB = 256` · `HISTN = 64` · `explorer: modell n=… ueberlauf=0` · `if welches == 4` nur noch **einmal** |
| 12 | Werkzeugleiste mit Symbolen statt `<` `>` `^` | **fertig** | `wlib.icon_button(icons.NAV_BACK/FORWARD/UP)`; die Zeichen `t_zur/t_vor/t_auf` sind aus dem Quelltext verschwunden |

**Abnahmestand:** 48 Prüfungen gut, 1 offen im vorletzten Lauf (die
Ctrl+Z-Prüfung, deren *Drehbuch* falsch war — siehe §5), danach grün.

---

## 3. Was ins Framework ging, nicht in den Dateimanager

Der Auftrag verlangte, dass neue Fähigkeiten **ins Framework** gehören,
damit andere Programme sie erben. Das ist eingehalten:

* **`kernel/user/wlib.fi` — die Mehrfachauswahl.** Eine Liste konnte
  genau *eine* Zeile tragen (`D_VAL`); „die drei markieren und löschen"
  war in **keinem** Programm dieses Systems ausdrückbar. Neu:
  `sel_an/sel_hat/sel_setz/sel_leeren/sel_alle/sel_bereich/sel_anker/sel_zahl`.
  Das Bitfeld liegt beim **Aufrufer** — 4096 Zeilen sind 512 Oktett,
  und die je Widget vorzuhalten hieße, sie 160-mal vorzuhalten, auch
  für Knöpfe und Beschriftungen. Ohne angemeldetes Bitfeld verhält sich
  alles wie vorher.
* **`kernel/wm.fi` — Umschalttasten im Klick.** Ein Klick trug nur die
  Maustasten; Strg-Klick war von einem gewöhnlichen Klick nicht zu
  unterscheiden. Die Maske hat oberhalb der drei Maustasten Platz:
  Bit 3 (`M_SHIFT`) und Bit 4 (`M_CTRL`) tragen sie mit.
* **`lib/libc/io.fi` — `rename`.** War nie da, obwohl `SYS_RENAME` seit
  Runde K14 existiert. Genau deshalb hat der Dateimanager kopiert.
* **`kernel/user/dateiop.fi` (neu, 510 Zeilen)** — Kopieren,
  Verschieben, rekursiv Löschen, Größe und Stücke zählen. Verschieben
  ist `rename`, und nur bei `EXDEV` Kopie+Löschen. Zeitstempel und
  Rechte werden nachgezogen, blockweise mit `MAX_IO` 4096, und eine
  **kurz geschriebene Datei ist ein Fehler** und keine Datei.
* **`kernel/kbd.fi` — die Tasten, die es nicht gab** (siehe §4).

Der Dateimanager selbst ist in fünf Bausteine zerlegt, die einzeln
übersetzen: `expmodell` (Einlesen, Sortieren, Zeit), `exporte` (Orte,
Breadcrumb), `expakt` (Ablage, Umbenennen, Undo, Konflikte), `expdlg`
(Eigenschaften, Öffnen-mit, Miniaturen), `explorer` (Oberfläche).

---

## 4. Drei Tastatur-Befunde, die niemand vermutet hätte

Ohne diese drei wären die Kürzel aus Punkt 7 **Fiktion** gewesen — das
Programm hätte sie behandeln können, sie wären nie angekommen.

1. **Die F-Tasten hat dieses System nie gehabt.** Die Tabelle in
   `kbd.translate` reicht bis Abtastcode 57; F1 fängt bei 0x3B an, und
   was darüber lag, gab eine Null zurück — die Taste wurde lautlos
   verschluckt. F2 und F5 *konnten* nicht gehen, egal was ein Programm
   tut. Jetzt gehen sie als `ESC [ 11..21 ~` heraus.
2. **Alt+Eingabe und die Alt-Pfeile gingen in den Kürzelring** des
   Fensterservers (Runde TILING nimmt *jede* Taste mit Alt) und kamen
   bei keinem Fenster an: `wm: hot c=28 mod=1 act=0`, und nichts
   passiert. Sie sind Anwendungs- und keine Fensterkürzel und gehen
   jetzt als `ESC [ n ; 3 ~` an das Fenster.
3. **Strg+H und Strg+N waren nicht unterscheidbar.** Strg+H ist Oktett
   8 — das ist der Rückschritt. Strg+N ist 14 — das ist die Pfeiltaste
   hoch. Diese **zwei** gehen als `ESC [ 30..31 ; 5 ~`; die anderen
   vierundzwanzig bleiben Steueroktette, Shell und Editor merken nichts.

---

## 5. Vier Fehler, die erst der Lauf gezeigt hat

Alle vier waren im Quelltext unsichtbar und nur durch Messen zu finden.

* **Der Mausrahmen fraß den Doppelklick.** Der Rahmen-Zweig dieser
  Runde zog bei *jeder* Bewegung mit gedrückter Taste — auch bei einer
  um null Bildpunkte. Der Testläufer fährt den Zeiger vor jedem Klick
  an die Stelle, also kam zwischen die zwei Klicks eines Doppelklicks
  ein `on_move` auf derselben Zeile; das setzte `D_VAL` neu, und der
  Doppelklick prüft `D_VAL == r`. Ein Doppelklick auf einen Ordner tat
  nichts. **Fix:** ein Rahmen fängt erst bei einer *anderen* Zeile an.
* **Die einzelne Fluchttaste fraß die nächste Taste.** `wlib.decode`
  warf nach einer alleinstehenden Flucht das nächste Oktett weg. Da
  jede Sondertaste selbst mit einer Flucht anfängt, ging nach jedem
  `Esc` genau eine Taste verloren — Alt+Eingabe war die einzige, die
  nie ankam, und es lag nicht an ihr. **Fix:** ist das Zeichen nach
  einer Flucht selbst eine Flucht, fängt die Folge neu an.
* **Ein Ordner in sich selbst brach das ganze Einfügen ab.**
  `expakt.einfuegen` setzte beim ersten solchen Eintrag `i = n_ablage`.
  Strg+A in `/data` wählt auch den Ordner `bilder`; Strg+V dort traf
  ihn als ersten, meldete `paste n=0 rc=-22`, und die acht anderen
  Stücke wurden nie angefasst — es sah aus, als könne dieser
  Dateimanager überhaupt nicht einfügen. **Fix:** dieses eine Stück
  überspringen (`sprung`), den Rest erledigen.
* **Der Testläufer war zu langsam für seinen eigenen Doppelklick.**
  `wlib` nimmt zwei Klicks als Doppelklick bei weniger als 100 Ticks
  (100 Hz, also eine Sekunde). Der Abstand im Drehbuch war 0,22 s, der
  Gast maß **109** Ticks: jedes `self.cmd` geht über den QEMU-Monitor
  und *wartet* auf Antwort, und unter TCG kostet dieser Umlauf ein
  Vielfaches der Schlafzeit.

Und zwei Fehler steckten in der **Abnahme**, nicht im Programm — beide
hätten dem Dateimanager fast einen Mangel angelastet, den er nicht hat:

* `sendkey ctrl-z` kommt im Gast als `^Y` an. Die Platte ist auf die
  deutsche Belegung gestellt, und dort sind Y und Z vertauscht — das
  ist das Z, das QWERTZ seinen Namen gibt. QEMU benennt die Taste nach
  ihrer amerikanischen Beschriftung.
* `overlapping` aus `shotcheck.py` zählt hier falsch: es hält gemeldete
  Textkästen gegeneinander, die Meldungen sind aber über die *ganze
  Laufzeit* gesammelt. Die Statuszeile trug nacheinander drei
  verschiedene Sätze an derselben Stelle — drei richtige Texte, keine
  Überschneidung. Gezählt wird `cut`, das *einen* Text gegen *seinen*
  Platz misst.

---

## 6. Was die Abnahme prüft

`tools/explorer2/run.sh` — eine Maschine, ein Drehbuch, neun Bilder.

Geprüft wird **zweierlei**, und das mit Absicht: dass die Tat geschieht
(serielle Leitung) und dass sie *richtig* geschieht (Quelltext). Drei
Punkte sind von außen nämlich nicht zu sehen — dass Umbenennen
`rename` nimmt, sieht man einer kleinen Datei nicht an; das geht erst
bei einem **Ordner** schief, und dann sind die Daten weg.

Dazu am Läufer zwei Ergänzungen: `ftabzeile<N>` klickt eine *bestimmte*
Zeile der Dateitabelle an (vorher traf ein Drehbuch nur die Mitte, und
welche Zeile dort liegt, hängt an der Anzahl der Dateien), und
`aufnahme.sh` legt die Platte jetzt als **OFS v3 mit Zeiten** an —
ohne das gibt `fs.inode_mtime` für jede Datei 0 zurück, und die
Zeit-Spalte wäre leer geblieben, egal was der Dateimanager tut.

---

## 7. Offen

* **Tabs (Strg+T)** sind als Framework-Widget (`K_TABS`) vorhanden,
  aber im Dateimanager nicht verdrahtet. Der Auftrag ließ das
  ausdrücklich zu („mindestens als Framework-Widget vorbereiten").
* **Drag-and-Drop als Ziel** (etwas ins Fenster *hineinziehen*) fehlt
  weiter; der Explorer ist nur Quelle. Das steht schon im Befund vom
  09.09. unter den Basis-Lücken und ist eine eigene Runde wert.
* Die Miniaturen laden PNG/JPEG über `viewer/jpeg.fi`; sehr große
  Bilder werden gezählt und ausgelassen statt skaliert.
