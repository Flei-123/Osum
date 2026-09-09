# EXPLORER-2 — Bauplan und Schnittstellen

Auftrag: `/root/EXPLORER2-AUFTRAG.md` (zwoelf Pflichtpunkte). Arbeitsbaum:
`/root/osum-explorer2`. Dieser Plan zerlegt den Auftrag in **sechs Module,
die parallel gebaut werden** — jedes Modul besitzt seine eigenen Dateien,
und **zwei Module fassen nie dieselbe Datei an**.

## 0. Was schon steht (Stand dieses Plans)

Committet in `af27ce3` (Unterbau, NICHT neu bauen):

* `kernel/kbd.fi` — F-Tasten, Alt+Enter, Alt-Pfeile, Strg+H/Strg+N.
* `kernel/user/wlib.fi` — `KEY_F1..KEY_F10`, `KEY_ALT_*`, `KEY_CTRL_H/N`,
  Mehrfachauswahl `sel_an/sel_hat/sel_setz/sel_leeren/sel_alle/
  sel_bereich/sel_anker/sel_zahl`, Strg-/Umschalt-Klick in `on_down`.
* `kernel/user/dateiop.fi` — `kopiere`, `kopiere_baum`, `verschiebe`,
  `loesche`, `groesse_rekursiv`, `zaehle_rekursiv`, `gibt_es`,
  `ist_verzeichnis`, `fortschritt_an/aus`, `getan_dateien/oktette`,
  `abbrechen`, `letzter_fehler`.
* `kernel/user/korb.fi` — `hinein`, `zurueck`, `loesche_rekursiv`,
  `korb_von`. `lib/libc/io.fi` — `rename`, `stat_mtime/ctime/atime`,
  `set_times`, `stat_mode_of`.

Neu in diesem Grundgeruest (angelegt, uebersetzt, im Kern gebaut):

* `kernel/user/expmodell.fi` — Liste, Zeiten, Sortierung (MAXENT 4096,
  NAMEB 256, Namensblob + Offsettafel, Ortszeit aus `/etc/time.conf`).
* `kernel/user/expakt.fi` — Ablage, Einfuegen, Umbenennen (`io.rename`),
  Papierkorb, Rueckgaengig (64 Schritte), Fehlernummer -> Katalogschluessel.
* `kernel/user/exporte.fi` — Seitenleiste (Orte + `SYS_MNTSTAT`) und
  Brosamenleiste.
* `kernel/user/expdlg.fi` — Eigenschaften, "Oeffnen mit", Neue Datei,
  Miniaturen.
* `kernel/user/explorer.fi` — importiert die vier und meldet beim Start
  ihre Zahlen auf der seriellen Leitung.

Gegenprobe, gemessen am 09.09.2026:

```
export FIRNLIB=$PWD/lib
vendor/firn/bin/firnc kernel/user/explorer.fi -o /tmp/x.o   # fehlerfrei
./tools/build-kernel.sh /tmp/k.mb                            # 5.442.424 Oktette
```

## 1. Gemessene Befunde, an die sich jedes Modul haelt

* **Speicher:** `kernel/proc.fi` gibt einem Prozess
  `IMAGE_BASE 0x40100000 .. IMAGE_END 0x40C00000` = 11 MiB fuer Text,
  Daten und BSS; die anonyme Arena liegt ab `BIG_FLOOR 0x40C00000`.
  `wlibc` holt seine Malflaeche per `map_surface` (anonymes `mmap`) und
  bildet `fb.USER_BASE` NICHT ab — die Warnung "Abbild ueber 1 MiB ODER
  Rahmenpuffer" gilt fuer dieses Programm nicht. Das Modell darf also
  rund 1 MiB BSS belegen; mehr als 2 MiB fasst niemand ohne neue Messung an.
* **Pufferstrategie (Pflichtpunkt 11):** 4096 * 256 = 1 MiB Namen als
  Rechteck ist zu viel und zu leer. Stattdessen: `nblob` 320 KiB, Namen
  hintereinander, `noff[i]` = Anfang. Gemessener Mittelwert eines Namens
  in diesem Baum: 17 Oktette. Ueberlauf wird GEZAEHLT (`ueberlauf()`) und
  in der Statuszeile gesagt, nie stillschweigend verschluckt.
* **Katalog:** `kernel/user/msg.fi` hat `SLOTS = 288`, die Kataloge haben
  **schon heute 316 Schluessel** — 28 fallen beim Laden hinten herunter.
  Ohne Anheben verschwindet jeder neue `explorer.*`-Text. Probe gemacht:
  `SLOTS 512`, `KEYW 48`, `VALW 192` (`kbuf` 24576, `vbuf` 98304)
  uebersetzt und baut.
* **Zeit:** `/etc/time.conf`, `offset=<Minuten>`, gelesen wie
  `taskbar.fi::offset_read` (Zeile ~1541). NICHT `/etc/zeit.conf`.
* **Toter Zweig:** `explorer.fi` hat zweimal `if welches == 4`
  (Menuewahl); der zweite ist unerreichbar und ist der NETVIEW-Punkt.
* **Werkzeugleiste:** `t_zur`/`t_vor`/`t_auf` sind heute `"<" ">" "^"`.

## 2. Modulliste und Dateibesitz

| Modul | besitzt AUSSCHLIESSLICH | Pflichtpunkte |
|---|---|---|
| `modell` | `kernel/user/expmodell.fi` | 5, 11 (Grenzen/Puffer), Sortierung |
| `taten` | `kernel/user/expakt.fi` | 1, 2, 8 (Fehlerkatalog), 9 |
| `orte` | `kernel/user/exporte.fi` | 6 |
| `auskunft` | `kernel/user/expdlg.fi` | 4, 10 |
| `texte` | `locale/de/messages`, `locale/en/messages`, `kernel/user/msg.fi`, `docs/EXPLORER2-TEXTE.md` | Regel "kein Text im Code" |
| `rahmen` | `kernel/user/explorer.fi`, `kernel/user/wlib.fi` | 3, 7, 8 (Dialoge), 10 (Ansicht), 11 (toter Zweig), 12, Layout |

Keine andere Datei wird angefasst. Wer etwas in einer fremden Datei
braucht, findet es unten in der Schnittstelle — sie ist gebaut und
uebersetzt, nicht versprochen.

## 3. Schnittstellen (bereits vorhanden, Signaturen sind bindend)

### 3.1 `expmodell` — das Modell

```
const MAXENT = 4096, NAMEB = 256, BLOB = 327680
lade(dir) -> u64                  // Eintraege oder Kernfehler (ulib.bad)
anzahl() / ueberlauf() / blob_benutzt() -> u64
name_at(e) / groesse_at(e) / art_at(e) / modus_at(e) -> u64  // e = EINTRAG
mtime_at(e) / ctime_at(e) / atime_at(e) -> u64               // Sekunden UTC
ord_at(zeile) -> eintrag          // Ansicht -> Eintrag (immer benutzen!)
ord_finde(eintrag) -> zeile
setz_sort(spalte, rev) / sort_spalte() / sort_rev() / sortiere()
setz_versteckt(bool) / versteckt() -> bool          // Strg+H
setz_filter(ptr) / filter_ptr() -> u64              // Strg+F
tabelle_bauen(kopfzeile) -> zeilen                  // kopf = msg.get("explorer.columns")
tabelle_ptr() -> u64        // stabile Adresse fuer wlib.table/set_text
symbole_ptr() -> u64        // stabile Adresse fuer wlib.row_icons
symbol_fuer(e) -> icon_id
zeit_lade() / zeit_offset() -> Minuten
zeit_text(sekunden, out) -> out   // "JJJJ-MM-TT SS:MM" Ortszeit, 0 -> "--"
melde()                           // `explorer: modell n= blob= ueberlauf= tzoff=`
```

Spalte 0 Name, 1 Groesse, 2 Zeit, 3 Rechte — dieselbe Nummerierung wie
die Spaltenkoepfe. Verzeichnisse stehen in jeder Sortierung oben.

### 3.2 `expakt` — die Taten

```
const MAXLIST = 256, MAXUNDO = 64
const K_ERSETZEN=0, K_UMBENENNEN=1, K_UEBERSPRINGEN=2, K_ABBRUCH=3
liste_leeren() / liste_add(pfad) -> bool / liste_zahl() / liste_at(i)
kopieren_merken(schnitt: bool) -> rc     // Strg+C / Strg+X, CT_FILES(+CT_PATH)
schnitt_an() -> bool
ablage_zahl() / ablage_at(i)
einfuegen(zielordner) -> rc              // rename zuerst, sonst Kopie
konflikt_da() -> bool / konflikt_pfad() -> u64 / konflikt_antwort(wahl)
umbenennen(altvollpfad, neuname) -> rc   // io.rename, F2
in_korb(pfad) -> rc / endgueltig(pfad) -> rc
rueckgaengig() -> rc / undo_zahl() / undo_art() / undo_name()
fehler_schluessel(rc) -> ptr auf "explorer.err.*"
letzter_rc() / getan_dateien() / getan_oktette() / abbrechen() / melde()
```

Ablauf beim Einfuegen: `einfuegen` bricht bei einem bestehenden Ziel ab,
setzt `konflikt_da()` und den Pfad; `rahmen` macht den Konfliktdialog auf
(vier Wahlmoeglichkeiten), meldet die Antwort mit `konflikt_antwort` und
ruft `einfuegen` erneut. Jeder rc != 0 geht durch `fehler_schluessel` in
ein Hinweisfenster — **kein stummer Fehlschlag**.

### 3.3 `exporte` — Orte und Weg

```
const MAXORT = 32, MAXKRUME = 12
orte_bauen() -> zeilen        // Orte + Datentraeger aus SYS_MNTSTAT
orte_zahl() / orte_ptr()      // Textblock fuer wlib.list (stabil)
orte_symbole()                // Feld fuer wlib.row_icons (stabil)
ort_text(i) / ort_pfad(i) / ort_ist_traeger(i)
traeger_zahl() / traeger_bloecke(i) / traeger_benutzt(i)
krume_bauen(pfad) -> glieder  // Brosamen; Glied 0 ist die Wurzel
krume_zahl() / krume_text(i) / krume_pfad(i)     // stabile Adressen
melde()                        // `explorer: orte n= traeger=`
```

### 3.4 `expdlg` — Auskuenfte

```
eig_bauen(pfad, name, zeit_fn_oder_0) -> zeilen
eig_ptr() / eig_zeilen() / eig_groesse() / eig_stuecke()
oeffnenmit_bauen() -> n / oeffnenmit_zahl() / oeffnenmit_ptr()
oeffnenmit_name(i) / oeffnenmit_exec(i)
neue_datei(pfad, inhalt_oder_0) -> rc
mini_bereit() / mini_laden(pfad) / mini_breite() / mini_hoehe() / mini_daten()
melde()
```

## 4. Der Katalog (verbindliche Schluessel)

`texte` legt JEDEN dieser Schluessel in **beiden** Dateien an; die anderen
Module rufen nur `msg.get(...)`. Reihenfolge in Listen ist **Vertrag**:
`rahmen` schaltet nach Index.

* Orte: `explorer.place.root|home|docs|pics|downloads|trash|net|volumes`
* Eigenschaften: `explorer.prop.title|name|type|size|contains|created|
  changed|read|rights|owner`
* Arten: `explorer.type.folder|file|program|image|text`
* Fehler: `explorer.err.title|other|noent|acces|exist|nospc|isdir|rofs|
  busy|inval|spawn`
* Konflikt: `explorer.conflict.title`, `explorer.conflict.ask`, und
  `explorer.conflict.buttons` = 4 Zeilen in DIESER Ordnung:
  Ersetzen / Umbenennen / Ueberspringen / Abbrechen (= `K_*` 0..3)
* Kontextmenue `explorer.context` (Ordnung ist Vertrag): Oeffnen,
  Oeffnen mit, Ausschneiden, Kopieren, Einfuegen, Umbenennen, Loeschen,
  Endgueltig loeschen, Neuer Ordner, Neue Datei, Packen (ZIP),
  Entpacken, Netzzugriff, Eigenschaften
* Menueleiste `explorer.menu` = Datei, Bearbeiten, Ansicht, Gehe zu
  * `explorer.menu.file`: Neuer Ordner, Neue Datei, Oeffnen mit,
    Eigenschaften, Aktualisieren, Beenden
  * `explorer.menu.edit`: Ausschneiden, Kopieren, Einfuegen,
    Alles auswaehlen, Rueckgaengig
  * `explorer.menu.view`: Liste, Symbole, Nach Name, Nach Groesse,
    Nach Zeit, Nach Rechten, Umgekehrt, Versteckte Dateien
  * `explorer.menu.go`: Zurueck, Vorwaerts, Hinauf, Zuhause, Papierkorb
* Ansicht/Status: `explorer.view.list|icons`, `explorer.status.filter`,
  `explorer.status.hidden`, `explorer.status.selected`,
  `explorer.status.overflow`
* Fortschritt: `explorer.progress.title`, `explorer.progress.cancel`
  (dazu die schon vorhandenen `explorer.progress.files|bytes|new`)
* Rueckgaengig: `explorer.undo.done`, `explorer.undo.none`
* Sonstiges: `explorer.newfile`, `explorer.newfile.name`,
  `explorer.openwith.title`, `explorer.confirm_delete_perm`,
  `explorer.filter`, `explorer.tab.new`, `explorer.path`

Bestehende Schluessel behalten ihre Bedeutung; `explorer.context`,
`explorer.menu` und `explorer.menu.*` werden ERWEITERT — wer sie
aendert, aendert sie in beiden Sprachen und sagt `rahmen` die Anzahl.

## 5. Belege auf der seriellen Leitung

Jede neue Faehigkeit bekommt **eine eigene Zeile mit Zahlen**, damit die
Abnahme misst statt zu raten. Vergeben (Modul in Klammern):

```
explorer: modell n=<> blob=<> ueberlauf=<> tzoff=<>     (modell)
explorer: clip n=<> rc=<>                                (taten)
explorer: paste n=<> rc=<>                               (taten)
explorer: rename rc=<>                                   (taten)
explorer: trash rc=<>                                    (taten)
explorer: undo art=<> rc=<>                              (taten)
explorer: orte n=<> traeger=<>                           (orte)
explorer: krume n=<>                                     (orte)
explorer: props zeilen=<> bytes=<> stueck=<>             (auskunft)
explorer: openwith n=<>                                  (auskunft)
explorer: mini w=<>                                      (auskunft)
explorer: sel n=<> anker=<>                              (rahmen)
explorer: key <code>                                     (rahmen)
explorer: view <0|1>                                     (rahmen)
explorer: sort spalte=<> rev=<>                          (rahmen)
explorer: fehler rc=<> key=<>                            (rahmen)
explorer: konflikt wahl=<>                               (rahmen)
```

Dazu bleiben `say_rect/say_rects/say_menurect/say_dlgrect` erhalten und
bekommen die neuen Bedienelemente (Seitenleiste, Brosamenknoepfe,
Filterfeld, Werkzeugknoepfe) dazu.

## 6. Layout (im Bild geprueft)

```
+----------------------------------------------------------+
| Menueleiste                                              |
+----------+-----------------------------------------------+
| Seiten-  | Werkzeugleiste (Symbole) + Brosamen/Pfadfeld  |
| leiste   +-----------------------------------------------+
| Orte     | Inhalt (Tabelle oder Symbolansicht)           |
| Traeger  |                                               |
+----------+-----------------------------------------------+
| Statuszeile                                              |
+----------------------------------------------------------+
```

Alle Hoehen kommen wie heute aus `wlibc.metric/type_lh/space/snap` —
keine getippte Bildpunktzahl. Nichts wird ausserhalb von `wlib`/`wlibc`
gemalt.

## 7. Regeln fuer jedes Modul

1. Nach **jeder** Aenderung muss beides fehlerfrei laufen:
   `export FIRNLIB=$PWD/lib && vendor/firn/bin/firnc kernel/user/explorer.fi -o /tmp/x.o`
   und `./tools/build-kernel.sh /tmp/k.mb`. Ein Stand, der nicht baut,
   ist kein Stand.
2. Kein sichtbarer Text im Quelltext — nur `msg.get(<schluessel>)`.
3. Kein Zeichenaufruf ausserhalb von `wlib`/`wlibc`.
4. Keine Faehigkeit nur behaupten: jede muss verdrahtet sein und sich
   mit einer eigenen `explorer: ...`-Zeile melden.
5. Kommentare deutsch, ohne Umlaute in Bezeichnern, und sie erklaeren
   das WARUM mit dem gemessenen Befund.
6. Zeiger, die an `wlib.set_text`/`row_icons` gehen, muessen statisch
   sein — die Bibliothek liest sie beim naechsten Malen erneut.
