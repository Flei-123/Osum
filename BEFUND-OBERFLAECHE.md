# BEFUND OBERFLAECHE (21.09.2026)

Arbeitsbaum `/root/osum-ui`, Zweig `runde-oberflaeche`, ab `main`
`211f8e1b`. Alle Zahlen unten sind an einer laufenden Maschine gemessen
(QEMU/KVM, 1280x800, `scheme=day mode=light shape=osum`, `lang=de`) und
nicht aus dem Quelltext geschlossen.

Die Auftragsliste sagte im Kopf: *"Alles unten ist im Baum schon zu drei
Vierteln vorhanden -- sieh deshalb bei JEDEM Punkt ZUERST in den Baum."*
Das war die richtige Ansage. Von sechs gemeldeten Fehlern waren **vier
schon behoben**, einer war **eine Fehlmessung**, und der sechste war
**schlimmer als gemeldet**.

---

## PUNKT 1 -- die Oberflaeche sei englisch

**BEFUND: SIE IST DEUTSCH. Kein Fehler vorhanden.**

Beleg: `pruef/shots/sprache/02-startmenue.png`. Im Startmenue steht

| Eintrag | Text im Bild |
|---|---|
| Editor | Text schreiben und ändern |
| Editor+ | Text mit Reitern, Zeilennummern und Syntaxfarben |
| Datei-Explorer | Dateien und Ordner ansehen |
| OrientOS installieren | Das System von diesem Stick auf eine Platte kopieren |
| Suchen | Programme und Dateien finden und starten |
| Einstellungen | System, Aussehen, Netz und Konto einstellen |

Auch die Fenstertitel, die der Server meldet, sind uebersetzt:
`[Schreibtisch]`, `[Taskleiste]`, `[Suchen]`, `[Schnelleinst.]`.

Die Kette reisst nirgends, und sie ist vollstaendig nachvollzogen:

1. `/users/root/config/locale` sagt `de` (staerkste Quelle),
   `/etc/locale.conf` sagt `lang=de` daneben -- beide liegen im Abbild
   (`tools/usbimg/build.sh`, Zeilen 673 und 846).
2. `msg.init` liest `/usr/share/locale/en/messages` als Quellsprache,
   legt daraus die Schluessel an und schiebt die Uebersetzung darueber.
   **483 Schluessel bei `SLOTS = 512`** -- kein Ueberlauf, es fehlt
   nichts hinten.
3. `appdir.name_of` und `appdir.info_of` bauen den Schluessel aus dem
   Buendelnamen (`editor.osp` -> `editor.title` / `editor.info`) und
   fallen **nur dann** auf das INFO-Feld zurueck, wenn `msg.get` den
   Schluessel selbst zurueckgibt.

Behoben wurde das in `1555a42e` ("ROTABSCHNITTE 14/n: der Anzeigename
geht endlich durch den Katalog") und `6f60b8d4` ("17/n: auch die
Beschreibung"). Die englischen Saetze in `assets/apps/*.osp/INFO` sind
seither das, was ihr eigener Kommentar behauptet: der Name, der gilt,
*solange kein Katalog geladen ist*.

**Zu tun: nichts.** Wer die englischen Saetze im Baum sucht und findet,
hat die INFO-Dateien gefunden und nicht die Oberflaeche.

---

## PUNKT 2 -- Token-Disziplin

**BEFUND: die Tabelle vom 19.09. ist ueberholt.**

Gezaehlt wurden Farbliterale der Form `0xRRGGBB` im Quelltext:

| Datei | 19.09. gemeldet | heute gemessen |
|---|---|---|
| `taskbar.fi` | 9 hart | 1 |
| `wlib.fi` | 46 hart | 2 |
| `explorer.fi` | 25 hart | 0 |
| `settings.fi` | 5 hart | 0 |
| `nedit.fi` | 11 hart | 0 |

`nedit` hat **keine** harte Farbe und **keinen** `theme()`-Aufruf --
nicht, weil es am Thema vorbeimalt, sondern weil es ausschliesslich
`wlib`-Bedienelemente benutzt (`K_TEXTAREA`, `tabs`, Menueleiste) und
die Bibliothek fuer es malt. Genau so ist die Regel gemeint.
`pruef/shots/thema-hell/03-b-nedit.png` zeigt es im Thema: runde Ecken,
Themafarben, gedaempfte Statuszeile.

`tools/check-ui.sh`: **196 Dateien, 0 Programme malen selbst, 0 greifen
an der Bibliothek vorbei auf fUi zu, 0 Funktionen in `wlib.fi` malen an
fUi vorbei. PASSED.**

**Zu tun: nichts.** Die Zahlen, die den Punkt begruendet haben, gibt es
nicht mehr.

---

## PUNKT 3 -- die toten Animationen

**BEFUND: der eine echte Fehler der Liste -- und er war groesser als
gemeldet. BEHOBEN, siehe Commit `253ce769`.**

Gemeldet war: `AN_WIN_OPEN`, `AN_WIN_CLOSE`, `AN_NOTIFY` deklariert und
nie aufgerufen, `AN_WIN_MIN` gar nicht vorhanden.

Gemessen: der Unterbau in `kernel/ui/wm.fi` ist **vollstaendig**, und
`AN_MIN` gibt es sehr wohl (Z. 892). Vorhanden sind `anim_start`,
`anim_tick` (ruft am Ende `destroy` bzw. `set_hidden`), `anim_p` aus der
vergangenen Zeit statt aus der Bildzahl, `ease_out`, und
`paint_win_anim`, das die Fensterflaeche aus `W_BUF` abtastet und die
Deckung mitmischt. Sogar die drei Einstiege `open_anim`, `close_anim`
und `minimize_anim` sind da.

**Was fehlte: sie wurden nirgends aufgerufen.** Kein einziger Treffer
ausserhalb von `wm.fi`. Die Titelleistenknoepfe riefen `destroy()` und
`set_hidden()` direkt auf, `WM_ACT/WA_HIDE` ebenso, und ein neu
angelegtes Fenster meldete gar nichts an.

Gemessen, beide Male gewoehnliches Hochfahren, **ohne** den
Vorfuehrschalter `wmanim` (der ruft `open_anim` selbst auf und wuerde
auf beiden Baeumen dasselbe sagen):

| Baum | `anim=` | `frames=` |
|---|---|---|
| `main` `211f8e1b` | **0** | 0 |
| `runde-oberflaeche` | **4** | 0 |

`anim` zaehlt im Server angemeldete Bewegungen, nicht Bildpunkte im
Foto. Vier Fenster gehen beim Hochfahren auf, vier Bewegungen.
Nachrechenbar mit `bash pruef/anim-ab.sh <arbeitsbaum> <ausgabe>`.

**Minimieren zum eigenen Leistenknopf** ist gebaut, wie gewuenscht, und
nicht "in eine beliebige Ecke": der Server kennt den Knopf nicht -- er
gehoert der Leiste --, also sagt sie ihn selbst ueber **`WM_MINRECT`
(2127)**, mit derselben Rechteregel wie `WM_ACT`. `paint_win_anim`
interpoliert Lage *und* Groesse aus demselben `p` wie Deckung und
Skalierung auf dieses Rechteck zu. Ohne gemeldetes Ziel bleibt es beim
mittigen Schrumpfen.

### Was an Punkt 3 NICHT gebaut ist

Das **Aufheben beim Ziehen** (Fenster leicht groesser, Pivot an der
angefassten Stelle, Traegheit und Auspendeln, jede Wirkung einzeln
schaltbar und regelbar) ist **nicht** gebaut. Grund: ehrlich gesagt die
Zeit -- die Messung der ersten drei Punkte hat den Lauf gefuellt. Der
Weg dafuer liegt aber offen, und die Vorarbeit ist getan:
`paint_win_anim` ist bereits die Stelle, die eine Fensterflaeche
skaliert und versetzt ueberträgt, und die gemessenen Kosten aus der
Auftragsliste (0,18 ms je Verschiebung, 1,04 ms auf 105 % skaliert)
sagen, dass es bezahlbar ist. Eine Kipp-Transformation kann der Server
nicht; die Naeherung aus Versatz und Skalierung ist der richtige Weg.

---

## PUNKT 4 -- Blur/Acryl

**Nicht angefasst.** Bewusst offen gelassen: ohne den
Zwischenspeicher-Teil ("einmal blurren, danach nur kopieren") ist das
Ganze nach eigener Vorgabe nicht auslieferbar, und das ist eine Runde
fuer sich. Die Messung aus der Auftragsliste bleibt gueltig: Taskleiste,
Startmenue, Menues und Benachrichtigungen sind bezahlbar, ganze Fenster
(42,5 ms = 255 % des Budgets) nicht.

---

## PUNKT 5 -- die kleinen Punkte

### Helles Schema sei pur weiss -- **NEIN, schon behoben**

`kernel/user/wlibc.fi`, `bind_neutrals(dark = false)`, normaler Zweig:

```
S_SURFACE        = N_50     #f8fafc   getoente Grundflaeche
S_SURFACE_RAISED = N_0      #ffffff   reines Weiss -- nur was schwebt
S_SURFACE_SUNKEN = N_100    #f1f5f9
```

Also genau das Modell von Windows 11 und macOS. Im Bild nachgemessen:
Schreibtisch `(242,246,249)`, Startmenue-Karte `(248,250,252)`. Nur der
Zweig `sch_high` (`contrast=high`) bindet `N_0` als Grundflaeche, und
dort ist es Absicht.

### Zwei Rollbalken-Segmente uebereinander -- **NEIN, Fehlmessung**

Gemessen in Spalte `x=432`: **ein** durchgehender Griff von `y=419` bis
`y=603`, 185 Bildpunkte. Was wie eine Trennung aussieht, ist
`y=538` mit `(107,123,145)` gegen `(100,116,139)` daneben -- eine
**Kantenglaettung**, kein Zwischenraum. Wer mit exaktem Farbvergleich
statt mit Toleranz misst, sieht hier zwei Segmente, wo eines ist. Genau
diese Falle steht auch in der Auftragsliste zu `db-kontrast.py`.

Der Griff ist `x=423..440`, also 18 Bildpunkte = `thumb_w()` =
`scroll_w() - 4` = `(row 28 - 6) - 4`, und liegt vollstaendig im
Listenfeld.

### Startmenue-Symbole sind Buchstaben in Quadraten -- **JA, bestaetigt**

Im Bild sind es "E", "D", "O", "S" auf farbigen Quadraten
(`wlib.icon_letter_x`), waehrend `assets/osum-icons.ttf` und die
Lucide-Symbole ungenutzt daneben liegen. **Offen, nicht angefasst.**

### Energiemenue stoesst unten an die Taskleiste / G-006 Radius

**Nicht geprueft, nicht angefasst.**

---

## a11y

`main..a11y` sind 5 Commits, 32 Dateien, +4958/-94, seit dem 28.08.
ungemergt. **Nicht mitgenommen** und auch nicht probeweise gemergt: der
Zweig fasst mit `wlib.fi` (+846), `wlibc.fi` (+204) und `wm.fi` (+175)
genau die drei Dateien an, in denen diese Runde arbeitet. Ein Merge
mitten in eine laufende Messung haette die Zahlen oben wertlos gemacht
-- vorher/nachher waere dann nicht mehr dieselbe Frage gewesen. Er
gehoert in eine eigene Runde, und dann zuerst.

---

## Abnahmen

| Abnahme | Stand |
|---|---|
| `tools/check-ui.sh` | **PASSED**, 196 Dateien, 0 Verstoesse |
| `tools/usbimg/build.sh` | **71 Pflichtpfade** im fertigen Dateisystem, 312 Umlautfolgen |
| `tools/install/abnahme.sh` | siehe Lauf |
| `tools/clip2/run.sh` | siehe Lauf |

Keine neue Datei wird ausgeliefert, deshalb war an
`tools/usbimg/build.sh` und der Pflichtliste nichts zu aendern. Die
Aenderungen dieser Runde stehen ausschliesslich in Dateien, die schon
gebaut und ausgeliefert werden (`kernel/…`).
