# Runde UMLAUT2 -- echte Umlaute ueberall, wo Text auf dem Schirm steht

Im Programmstarter stand `Text schreiben und aendern`, waehrend zwei
Zeilen tiefer `Ausführen` schon richtig erschien. Runde LOOK hatte
diesen einen Satz geholt und dazu einen Pruefer gebaut. Trotzdem stand
die Umschrift wieder da.

Diese Runde beantwortet die Frage, warum -- und schliesst die Luecke.

---

## 1. WARUM DER VORIGE PRUEFER DAS NICHT GEFUNDEN HAT

`tools/i18n/translit.py` liest zwei Quellen: `locale/de/*` und
`assets/apps/*.osp/INFO`. Beide waren sauber. Der Satz kam trotzdem auf
den Schirm, weil er aus einer DRITTEN Quelle stammt:

| Quelle | wer liest sie | war geprueft |
|---|---|---|
| `locale/de/messages`, `locale/de/icons` | `msg.fi` zur Laufzeit | ja |
| `assets/apps/*.osp/INFO` (`name=`, `info=`) | `appdir.fi` | seit LOOK |
| **`kernel/**/*.fi` -- einkompilierte Zeichenketten** | der Uebersetzer | **nein** |

Die dritte ist die groesste. `/bin/power`, `/bin/opk`, `/bin/vpn`,
`/bin/fas`, `/bin/passwd`, `/bin/su` und ein Dutzend mehr tragen ihren
ganzen Text im Quelltext -- sie haben kein Fenster und holen nichts aus
einem Katalog. Und auch Fensterprogramme haben Beschriftungen, die
nicht im Katalog stehen (`themetest.fi`, `speicher.fi`).

**Ein Pruefer, der den Quelltext nicht liest, kann diesen Fehler nicht
finden.** Deshalb `tools/i18n/quellen.py`.

---

## 2. DIE DREI KLASSEN

Nicht jede deutsche Zeichenkette im Quelltext gehoert auf Umlaute
umgestellt. `quellen.py` teilt sie in drei Klassen und begruendet jede.

**SICHTBAR** -- Beschriftung, Ausgabe, Fehlermeldung. Was ein Mensch
liest. HIER gehoeren echte Umlaute hin, ohne Ausnahme.

**MITSCHNITT** -- was ein Fensterprogramm oder der Kernel auf die
serielle Leitung schreibt: `leiste: knopf i=0 id=5`,
`speicher: gross i=`, `desktop: keine Flaeche`. `docs/I18N.md` nimmt
diese Zeilen ausdruecklich aus, und zwar aus einem Grund, der nichts
mit Bequemlichkeit zu tun hat: **die Abnahme greppt nach ihnen.** Ein
uebersetzter Mitschnitt machte jeden Testlaeufer sprachabhaengig.
Erkannt wird die Klasse daran, dass die Datei ein Fenster aufmacht
(`import wlib`/`wlibc`) oder im Kernel liegt UND die Zeichenkette
nirgends anders hingeht als in `say`/`kv`/`sag`/`serial.*` -- landet
sie an einem Bedienelement, ist sie SICHTBAR.

**MARKE** -- was mit einer EINGABE verglichen wird: Unterbefehl
(`opk zurueck`), Schalter (`--quelle`), Pfad, Dateiname, Schluessel.
Dieselbe Ausnahme wie in `docs/I18N.md` ("Befehlsname: nein") und
dieselbe wie `keys=` in den Buendeln: **man muss es tippen koennen,
auch ohne Umlauttaste.**

Eine Marke darf ASCII bleiben -- sie darf aber nicht die EINZIGE Form
sein. Die Hilfe zeigt seit dieser Runde `opk zurück`, und wer das
abtippt, muss ankommen. Sechs Marken nehmen deshalb jetzt beide
Schreibungen:

    opk zurueck | zurück        opk pruefen | prüfen
    vpn schluessel | schlüssel  power waerme | wärme
    dispctl zurueck | zurück    dispctl saettigung | sättigung

---

## 3. DIE ANNAHME, DIE FALSCH WAR: "EIN UMLAUT MACHT DEN TEXT LAENGER"

Der Auftrag dieser Runde vermutete, jede Ersetzung sprenge Puffer:
"Ein ü sind ZWEI Oktette statt einem." Das stimmt nicht, und es ist
gemessen:

| vorher | Oktette | nachher | Oktette |
|---|---|---|---|
| `ue` | 2 | `ü` | 2 |
| `ae` | 2 | `ä` | 2 |
| `oe` | 2 | `ö` | 2 |
| `ss` | 2 | `ß` | 2 |
| `Groesse` | 7 | `Größe` | 7 |
| `Kapazitaet` | 10 | `Kapazität` | 10 |

Die UMSCHRIFT ist schon zwei Oktette lang. **Alle 42 Zeichenketten
dieser Runde haben nach der Ersetzung exakt dieselbe Oktettzahl wie
vorher** -- 42 von 42, nachgerechnet in `tools/i18n/spalten.py`. Kein
einziger Puffer musste wegen der Oktettzahl wachsen.

**Was sich sehr wohl aendert, ist die Zahl der ZEICHEN**, und genau
daran haengt eine Beschriftungsspalte:

    Profil:  Höchstleistung        <- 9 Zeichen Beschriftung
    Akku:    [####----] 55 %       <- 9
    Netz:    angesteckt            <- 9
    Waerme:  62 Grad               <- 9  ... und "Wärme:  " sind 8.

Der Puffer stimmt, der Uebersetzer schweigt, und die Tabelle ist
schief. Drei Spalten waren davon betroffen -- `power.fi`, `vpn.fi` und
(schon vorher) `tiling.fi`; drei Puffer sind dafuer um ein Oktett
gewachsen. `tools/i18n/spalten.py` zaehlt die sechs
Beschriftungsspalten dieses Baums von jetzt an in ZEICHEN.

Dazu zwei Stellen, die "vier Zeichen" verlangen und Oktette gezaehlt
haben (`settings.fi`, `passwd.fi`): `müde` sind vier Zeichen und fuenf
Oktette, und drei Zeichen mit einem Umlaut waeren vier Oktette. Beide
zaehlen jetzt Zeichen.

---

## 4. WAS AM BILD NACHGEWIESEN WIRD

Drei Abbilder, in QEMU mit `-accel kvm`, Bilder unter
`docs/shots/umlaut2/`:

* `starter.png` -- der Programmstarter mit den Beschreibungen. Dort
  stand `aendern`.
* `einstellungen.png` -- die Einstellungen.
* `speicher.png` -- der Speicher-Dialog mit den Spalten `Größe` und
  `Größte Dateien`; gerade dort zeigt sich, ob die Spaltenbreiten noch
  stimmen.

Gemessen wird nicht "es sieht gut aus": `tools/look/umlaut.py --kette`
rastert den erwarteten Satz aus derselben Schriftdatei und vergleicht
JEDEN Tintenpunkt an der Stelle, die der Fensterserver gemeldet hat.
Ein abgeschnittener Text faellt durch (die Lage wird vorher gegen die
Fensterbreite gerechnet), ein leerer auch.

Dazu die Spalten am Bild: `Name` bei x=14, `Größe` bei x=224,
`Anteil` bei x=324, `Größte Dateien` bei x=414 -- genau die Summen aus
`lspalten` 210/100/74 und `rspalten` 210/100. Wer die Breite aus der
ZEICHENZAHL rechnete, laege hier daneben.

---

## 5. EIN BEFUND, DER AELTER IST ALS DIESE RUNDE

Beim Nachrechnen am Bild ist ein Unterschied zwischen dem Rasterer im
Kern und dem Vergleichsrasterer (`tools/ttf/raster.py`) aufgefallen,
und zwar nur bei EINEM Zeichen: dem kleinen `ö`. Die linke Punktkuppe
faellt im Kern in einer Spalte schwaecher aus -- drei Bildpunkte,
gemessen an drei voneinander unabhaengigen Stellen (Knopf `Löschen`,
Spaltenkopf `Größe`, Spaltenkopf `Größte Dateien`), jedes Mal genau
drei.

`ä` und `ü` stimmen an denselben Stellen auf den Punkt, und die drei
betroffenen Zeichenketten stehen unveraendert seit Runde LOOK im
Quelltext. Der Unterschied ist also aelter als diese Runde und nicht
von ihr verursacht. Er steht in `tools/umlaut/run.sh` als
OBERGRENZE (`3`) und nicht als Freibrief: waechst die Zahl, wird der
Abschnitt rot. Naeher untersucht gehoert er in eine Runde ueber den
Rasterer.

---

## 6. WAS AB JETZT ROT WIRD

`tools/umlaut/run.sh`, Abschnitt 29 der Abnahme. Fast jede Zusage hat
eine Gegenprobe -- ein Pruefer, der nicht rot werden kann, prueft
nichts. Ein Kommentar in `locale/de/messages` hat einmal woertlich
"HIER STEHEN ECHTE UMLAUTE" behauptet, waehrend keiner drinstand; eine
Behauptung ueber sich selbst ist keine Messung.

Die Gegenproben stellen je EINE Zeile in einer Kopie des Baums zurueck
auf Umschrift und verlangen, dass der Pruefer rot wird:

* der Satz im Buendel (`info=Text schreiben und aendern`),
* eine Zeile im Katalog (`launcher.run = Ausfuehren`),
* die Umlautform in `keys=`,
* eine Beschriftung in einem FENSTERPROGRAMM (`themetest.fi`) --
  die wichtigste, denn hier koennte die Ausnahme "Mitschnitt" zur
  Hintertuer werden,
* eine Meldung eines Befehls (`opk.fi`),
* eine Beschriftung im Speicher-Dialog (`speicher.fi`),
* die zweite Schreibung eines Unterbefehls,
* eine Spalte, um EIN ZEICHEN verkuerzt,
* ein Literal, das nicht mehr in seinen Puffer passt.

Und eine GEGEN-GEGENPROBE: eine neu eingefuegte MITSCHNITT-Zeile mit
Umschrift muss GRUEN bleiben. Sonst ist der Pruefer nur laut und nicht
richtig, und der Naechste, den er grundlos anmeckert, schaltet ihn ab.
