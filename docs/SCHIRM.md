# RUNDE SCHIRM -- die Oberflaeche auf einem grossen Bildschirm

Diese Runde hat EINE Frage gestellt: sieht Osum auf einem echten
Bildschirm benutzbar aus, oder nur auf den 1024x768, mit denen bisher
gemessen wurde? Die Antwort war beim Start: nein. Auf einem
2560x1440-Schirm und auf einem 3840x2160-Schirm lief derselbe Kern in
**800x600**, und niemand hat es gemerkt, weil keine Messung je einen
grossen Schirm angeboten hatte.

Alle Zahlen unten sind Mitschnitte, die in `docs/messungen/schirm/`
liegen; alle Bilder sind Bildschirmfotos aus QEMU in
`docs/bilder/schirm/`. Es steht hier keine Behauptung ohne Messwert
oder Bild.

Ausgangsstand: `main` @ 163984d, `kernel/fb.fi` 2.910 Zeilen.
Werkzeuge der Runde: `tools/schirm/build.sh` (Kern, Programme, Platte)
und `tools/schirm/boot.sh` (ein Start, ein Foto, ein Mitschnitt).

---

## 1. Bestandsaufnahme: woher kommt die Aufloesung?

Es gibt drei Wege, und sie beantworten die Frage verschieden.

| Weg | wer bestimmt die Aufloesung | Meldung im Mitschnitt |
|---|---|---|
| UEFI/BIOS ueber Limine (`osum-usb.img`) | der **Lader** (GOP bzw. VBE), der Kern uebernimmt, was dasteht | `src=mb` |
| `qemu -kernel`, kein Lader | der **Kern** selbst ueber die Bochs-Register | `src=vbe` |
| Befehlszeile `fbres=BxH` | der Mensch | `quelle=1` |

Die Zeile, die das seit dieser Runde sagt, ist neu:

    fb: 2560x1440x32  pitch=10240  src=vbe  ...
    fb: skala x1  quelle=2  streifen=1  mm=650

`quelle`: 0 = eingebaute Vorgabe, 1 = Befehlszeile, 2 = EDID der Tafel.
`skala` = Vervielfachung der Schrift, `streifen` = der Rahmenpuffer
passt nicht am Stueck in die Fensterplaetze, `mm` = Bildbreite in
Millimetern aus dem EDID.

### 1.1 Vorher: 800x600, egal welcher Schirm

Basis 163984d, QEMU-Tafel 2560x1440 bzw. 3840x2160
(`docs/messungen/schirm/vor1440.txt`, `vor4k.txt`):

    fb: 800x600x32  pitch=3200  src=vbe  ...
    wm: 800x600  cursor=1  dirty=1  focus=1

Auch mit `fbres=2560x1440` blieb es bei 800x600 -- das Wort gab es
nicht. Bild: `docs/bilder/schirm/vor-2560x1440.png` (800x600 auf einem
WQHD-Schirm) und `vor-3840x2160.png`.

### 1.2 Der Fehler dahinter: der EDID-Block wurde falsch gelesen

Der Kern las die native Aufloesung STARR aus dem Zeitlagensatz ab
Oktett 54 des EDID-Blocks. Dieser Satz ist aber nur dann eine
Zeitlage, wenn die Tafel ihn dorthin legt. Auf dem 4K-Schirm liegt dort
ein TEXTSATZ, und aus Buchstaben wurden Zahlen:

    fb: nat=0x1034      <- statt 3840x2160
    fb: 800x600x32  quelle=0

Behoben in `kernel/vmode.fi`:

* **alle vier** Saetze des Basisblocks werden gelesen, Saetze mit
  Pixeltakt null (Text, Grenzwerte) uebersprungen, die groesste
  Flaeche gewinnt (`dtd_scan`);
* Erweiterungsbloecke (CTA-861) werden mitgelesen (`EDID_BYTES` 384);
* und wenn ueberhaupt keine Zeitlage dasteht, entscheiden die acht
  Kurzsaetze ab Oktett 38 (`std_scan`).

Der letzte Punkt ist gemessen und kein Vorsichtshalber: **QEMU meldet
fuer einen 3840x2160-Schirm ueberhaupt keine Zeitlage.** Der Pixeltakt
einer 4K-Zeitlage passt nicht in die sechzehn Bit des EDID-Feldes, also
laesst der Erzeuger den Satz weg. Der rohe Block (aus dem Mitschnitt
gelesen) endet mit `... 000010 0000...0278`: vier Saetze, keiner davon
eine Zeitlage, Oktett 126 = 2 Erweiterungen, die die Karte dann aber
als Nullen liefert.

### 1.3 Nachher

| Tafel | vorher | nachher, ohne Befehlszeile | Quelle |
|---|---|---|---|
| 1024x768 | 1024x768 | 1024x768 | EDID |
| 1920x1080 | 800x600 | **1920x1080** | EDID |
| 2560x1440 | 800x600 | **2560x1440** | EDID |
| 3840x2160 | 800x600 | **2048x1152** | EDID-Kurzsatz |
| 3840x2160 mit `fbres=3840x2160` | 800x600 | **3840x2160**, Schrift x2 | Befehlszeile |

Auf dem 4K-Schirm sind 2048x1152 nicht die native Aufloesung, aber der
groesste Wunsch, den die Tafel in QEMU ueberhaupt nennt -- und die
2,6-fache Flaeche von 800x600. Auf echter Hardware kommt die
Aufloesung ohnehin vom Lader (Abschnitt 5).

16:9 und 16:10 machen keinen Unterschied: `1280x800` (16:10) und
`1920x1080` (16:9) werden beide uebernommen; die Kurzsatz-Auswertung
kennt alle vier Seitenverhaeltnisse des EDID (16:10, 4:3, 5:4, 16:9).

---

## 2. Schrift und Skalierung

Gerastert wird die Konsolenschrift aus einem 8x16-Raster, die
Oberflaechenschrift ueber `ttf.fi`. Der Faktor steht seit dieser Runde
in `fb.fi` (`S_FSCALE`, `S_UISCALE`) und richtet sich nach der Hoehe
des Schirms; `uiscale=N` auf der Befehlszeile ueberschreibt ihn.

Gemessen auf 3840x2160 (`docs/messungen/schirm/a4k.txt`):

    ttf: mono  glyphs=366  upm=2048  asc=29  desc=7  lh=38
    wm: term win=0  cols=28  rows=10  cell=20x38

gegen 1024x768 (`a1024.txt`):

    ttf: mono  ...  asc=14  desc=3  lh=19
    wm: term win=0  cols=56  rows=20  cell=10x19

Die Zellhoehe verdoppelt sich also wirklich (19 -> 38 Bildpunkte). Das
war der Fehler, den Certus hatte -- Osum hat ihn an dieser Stelle
NICHT mehr.

Was er aber hatte, und was erst das Bild gezeigt hat: die Schrift wuchs,
die Masse der Bedienelemente nicht. Auf 3840x2160 lagen die Eintraege
des Starters UEBEREINANDER, weil eine Textzeile 38 Bildpunkte hoch in
eine Listenzeile von 20 gemalt wurde
(`docs/bilder/schirm/zwischen-3840x2160-metriken-ungespreizt.png`).
Behoben in `kernel/user/wlibc.fi`: `metric()` gibt Laengen mal dem
Faktor zurueck, Hundertstel (`M_SHADOW`, `M_TONE`, `M_DIVIDER`,
`M_GRAD`) unveraendert. Ergebnis:
`docs/bilder/schirm/nach-3840x2160.png` -- die Liste steht sauber
untereinander.

Dazu zwei weitere Stellen, die in Bildpunkten dachten:

* `wlib.window(...)` nimmt die Masse jetzt als LOGISCHE Groesse und
  multipliziert sie mit dem Faktor (danach auf den Schirm gedeckelt).
  Ein Starterfenster von 440x300 ist auf 4K 880x600 statt eines
  Briefmarkenfensters in der Ecke.
* `taskbar.conf: height=32` ist eine logische Hoehe und wird mit dem
  Faktor multipliziert; eine 32 Bildpunkte hohe Leiste konnte auf 4K
  keine 38 Bildpunkte hohe Zeile mehr zeigen.

---

## 3. Tempo

`fbbench` misst den Bildpuffer (Vollbild fuellen, rollen, eine Linie,
und den Weg des Zweitpuffers auf den Schirm), `wmbench` den
Fensterserver (ein volles Zusammensetzen gegen ein kleines, und das
Rastern von 95 Zeichen kalt gegen warm). Alle Werte in Mikrosekunden,
QEMU mit KVM, ein Kern.

| Tafel | fill (Vollbild) | scroll | flush (Zweitpuffer -> Schirm) | compose full | compose small |
|---|---|---|---|---|---|
| 1024x768 | 241 | 497 | 407 | 1.885 | 30 |
| 1920x1080 | 1.432 | 1.772 | 1.522 | 4.033 | 33 |
| 2560x1440 | 2.567 | 2.506 | 3.444 | 11.201 | 91 |
| 3840x2160 | 4.153 | 5.423 | 5.763 | 16.201 | 42 |

Drei Aussagen, alle aus diesen Zahlen:

1. **Doppelte Pufferung gibt es**, und sie ist eingeschaltet: die
   `back=`-Adresse in der `fb:`-Zeile ist nicht null, `fbbench`
   misst `direct` und `buffered` getrennt, und `flush` ist der Weg vom
   Zweitpuffer auf den Schirm.
2. **Es wird NICHT jedes Mal alles gemalt.** Das ist der Unterschied
   zwischen `compose full` und `compose small`: 16.201 gegen 42
   Mikrosekunden auf 4K, ein Faktor von 386. Der Fensterserver malt
   den schmutzigen Bereich, und ein Fenster zu verschieben kostet
   deshalb den kleinen Wert, nicht den grossen.
3. Die Zeiten wachsen ungefaehr mit der Flaeche (1024x768 -> 3840x2160
   ist die 10,5-fache Flaeche, `fill` ist 17-mal so teuer). Das ist
   erwartbar, solange in Bildpunkten gerechnet wird, und es ist der
   Grund, warum der Streifenbetrieb (Abschnitt 4) auf grossen Schirmen
   spuerbar ist.

Zum Vergleich der Basisstand bei 800x600 auf demselben Wirt
(`vor1440.txt`): `fill=282  scroll=322  flush=195  compose full=1.185`.
Die Basis war nicht schneller -- sie hatte nur ein 20-mal kleineres
Bild.

---

## 4. Die drei behobenen Maengel, jeweils mit Messung

### Mangel 1: auf jedem grossen Schirm 800x600 (Abschnitt 1.2)

* vorher: `fb: 800x600x32` auf 2560x1440 und auf 3840x2160.
* nachher: `fb: 2560x1440x32 ... quelle=2` bzw. `2048x1152 ... quelle=2`.
* Belege: `vor1440.txt`/`vor4k.txt` gegen `a1440.txt`/`v4kauto.txt`,
  Bilder `vor-2560x1440.png` gegen `nach-2560x1440.png`.

### Mangel 2: ueber 2048 Bildpunkten maximierte kein Fenster mehr

Der Selbsttest des Fensterservers wurde in dieser Runde um eine
Fehlerbitmaske erweitert (`wm: selftest N / M  failed=0x...`, wie sie
`tile.fi` schon hatte). Sie zeigte auf 2560x1440:

    wm: selftest 26 / 30  failed=0x58c04200  mw=2  max=0

`mw=2` heisst: das Fenster entstand. `max=0` heisst: `maximize` gab
false. Der Weg dahin ist `fit_work` -> `resize_win`, und dort stand ein
fester Deckel:

    if w < 32 || h < 16 || w > 2048 || h > 2048 { return false }

Jeder Schirm ueber 2048 Bildpunkten Breite reisst ihn -- also jedes
WQHD- und jedes 4K-Geraet. Die Grenze, die es wirklich gibt, ist der
Puffer des Fensters, und die wird zwei Zeilen tiefer geprueft. Ersetzt
durch `MAX_W_HARD`/`MAX_H_HARD` (4096x2304).

* nachher, 2560x1440 und 3840x2160: `wm: selftest 30 / 30 ... max=1`.

### Mangel 3: die Oberflaeche wuchs nicht mit (Abschnitt 2)

* vorher (4K): Fenster von 440x300 in der Ecke, Listeneintraege
  uebereinander, Selbsttest `fb: 12 / 13  failed=0x200` und
  `wm: 29 / 30  failed=0xc0c200`.
* nachher (4K): `fb: selftest 13 / 13  failed=0x0`,
  `wm: selftest 30 / 30`, Fenster 880x600, Listenzeilen getrennt.
* Bilder: `zwischen-3840x2160-metriken-ungespreizt.png` gegen
  `nach-3840x2160.png`.

Die beiden Selbsttests waren dabei selbst mitschuldig und wurden
skalierungsfest gemacht: `fb`-Zusage 9 las die Glyphe an einer festen
Stelle (3,3) statt an `3*fscale`, und `wm`-Zusage 13 legte ein
Terminalfenster von starren 200x100 an, das bei einer Zelle von 20x38
nur noch zwei Zeilen hatte.

Stand aller Selbsttests am Ende der Runde:

| Tafel | fb | wm |
|---|---|---|
| 1024x768 | 13/13 | 30/30 |
| 1920x1080 | 13/13 | 30/30 |
| 2560x1440 | 13/13 | 30/30 |
| 3840x2160 | 13/13 | 30/30 |

(`failed=0xc04200` in der wm-Zeile sind die vier Bits der NICHT
genommenen Gegenprobenzweige -- die Maske zaehlt beide Aeste eines
`if/else`, der Punktestand nur einen.)

---

## 5. Unter dem Lader: das USB-Abbild

Neu gebaut mit `tools/usbimg/build.sh`, 123.731.968 Oktette (118 MiB),
GPT, EFI 96 MiB + Wurzel 20 MiB. Geprueft in QEMU:

| Start | Tafel | Ergebnis |
|---|---|---|
| UEFI (OVMF) | 1920x1080 | `fb: 1920x1080x32  src=mb  quelle=2` |
| BIOS (MBR) | 1920x1080 | `fb: 1920x1080x32  src=mb  quelle=2` |
| UEFI | 2560x1440 | `fb: 2560x1440x32  src=mb  streifen=1` |
| UEFI | 3840x2160 | `fb: 1280x800x32  src=mb` -- **der Lader gibt nur 1280x800** |

Der letzte Fall ist eine Grenze, die der Kern nicht selbst aufheben
kann: nach `ExitBootServices` gibt es kein GOP mehr, und der
Bochs-Weg, ueber den er ohne Lader den Modus setzt, ist auf echter
Hardware nicht da. Wer den Modus will, muss ihn den LADER waehlen
lassen. Deshalb hat `limine.conf` in dieser Runde zwei Eintraege mehr
bekommen (im Abbild nachgeprueft):

    /Osum -- Schreibtisch auf einem WQHD-Schirm (2560x1440)
        resolution: 2560x1440
    /Osum -- Schreibtisch auf einem 4K-Schirm (3840x2160)
        resolution: 3840x2160

Passt die Aufloesung dem Bildschirm nicht, faellt Limine auf seine
Vorgabe zurueck; es bleibt also immer ein Bild.

---

## 6. Was Justin auf echtem Blech pruefen soll

1. **Abbild schreiben.**
   `sudo dd if=osum-usb.img of=/dev/sdX bs=4M conv=fsync status=progress`
2. **Menueeintrag passend zum Schirm waehlen.** Auf einem gewoehnlichen
   Full-HD-Geraet reicht Eintrag 3 ("nur der Schreibtisch"). Auf einem
   WQHD- oder 4K-Bildschirm die beiden neuen Eintraege nehmen -- sonst
   startet der Lader mit dem, was ihm passt, und das war in QEMU auf
   einem 4K-Schirm 1280x800.
3. **Erste Zeile ablesen** (seriell oder Diagnose-Eintrag 1):
   `fb: BREITExHOEHE ... src=... quelle=...`. Steht dort die Aufloesung
   des Bildschirms? `quelle=2` heisst, sie kam aus dem EDID.
4. **Ist die Schrift lesbar?** Bei hoher Aufloesung muss `skala x2` in
   der zweiten `fb:`-Zeile stehen. Wenn nicht: mit `uiscale=2` in der
   Befehlszeile nachhelfen und das melden.
5. **Fenster maximieren** und schauen, ob es die Arbeitsflaeche fuellt
   und die Leiste NICHT ueberdeckt (das war Mangel 2).
6. **Fenster verschieben.** Ruckelt es, oder zieht es Spuren? Der
   schmutzige Bereich soll klein bleiben; Spuren waeren ein Fehler im
   Zusammensetzen.
7. **Die Taskleiste ansehen** -- siehe den offenen Punkt unten. Auf
   1024x768 ist sie vollstaendig; ob sie auf echtem Blech bei hoeheren
   Aufloesungen erscheint, ist die wichtigste Rueckmeldung dieser
   Runde.

---

## 7. Offen, gemessen, nicht behoben

1. ~~**Die Taskleiste erscheint ab 1920x1080 nicht auf dem Schirm.**~~
   **GEFUNDEN UND BEHOBEN, Runde SCHIRM-ECHT (03.09.2026)** -- siehe
   `docs/RUNDE-SCHIRM-ECHT.md`. Der Befund dieser Runde war richtig
   ("nicht die Aufloesung, nicht die Leiste, sondern zwischen
   Fensterpuffer und Zusammensetzen"), und die Ursache lag eine Schicht
   tiefer als vermutet: `wig.blit` -- der einzige Weg, auf dem ein
   Programm aus Ring 3 Bildpunkte in sein Fenster bekommt -- hat jede
   Zeile ABGELEHNT, die breiter war als der Umschlagpuffer
   (`w > MAX_ROW`, MAX_ROW = STAGE_MAX/4 = **1024**). Schreibtisch und
   Taskleiste sind so breit wie der Schirm. Auf 800x600 und 1024x768
   passte das, ab 1280 nicht mehr: ihr `push` gab 0 zurueck, ihr
   Fensterpuffer behielt die Farbe aus `wm.create` (16,20,26 -- genau
   die "eine Farbe" der Pixelprobe oben), und weil ohne Blit auch kein
   `wm.damage` laeuft, wurde die Leiste nie zusammengesetzt.
   Behoben, ohne die Speicherkarte anzufassen: eine zu breite Zeile
   wird in `stuecke(w)` Umschlaege zerlegt statt abgelehnt.
   Gemessen nachher: **100 % x 100 % auf 800x600, 1280x800, 1920x1080
   und 2048x1152**, Leiste sichtbar (`docs/shots/schirm-nach-*.png`).
2. **Rohe Sprachschluessel im Starter.** Im Bild stehen
   `launcher.prompt` und `launcher.run` statt uebersetzter Texte --
   auf jeder Aufloesung, also kein Schirm-Problem, aber sichtbar.
3. **Der Inhalt des Starterfensters fuellt das groessere Fenster nicht
   aus.** Liste und Knopf sitzen nach der Vergroesserung oben links
   statt gespreizt; das Layout rechnet in festen Zahlen.
4. **4K braucht in QEMU `fbres=`**, weil die Tafel dort keine
   4K-Zeitlage meldet (Abschnitt 1.2). Auf echter Hardware ist der
   Lader zustaendig; ob echte 4K-Bildschirme eine Zeitlage liefern,
   kann nur ein Test auf Blech zeigen.
5. **Eingabetreiber** (PS/2, USB-HID) gehoeren der Runde BLECH. Diese
   Runde hat sie nicht angefasst; alle Messungen liefen mit `nokbd`
   oder ohne Eingabe.

---

## 8. Was geaendert wurde

| Datei | was |
|---|---|
| `kernel/vmode.fi` | EDID: alle vier Zeitlagensaetze, Erweiterungsbloecke, Kurzsatz-Rueckfall (`dtd_scan`, `std_scan`, `EDID_BYTES`) |
| `kernel/fb.fi` | Aufloesungswunsch `fbres=`, `uiscale=`, Schrift- und Oberflaechenfaktor, Streifenbetrieb, Zweitpuffer nach echter Geometrie, Fehlerbitmaske im Selbsttest, Zusage 9 skalierungsfest |
| `kernel/kgui.fi` | Aufloesungswahl (Befehlszeile > EDID > Vorgabe), `fb: nat=`-Zeile, `failed=`-Masken im Bericht |
| `kernel/wm.fi` | Deckel 2048 -> `MAX_W_HARD`/`MAX_H_HARD`, Fehlerbitmaske, Zusage 13 in Zellen statt Bildpunkten |
| `kernel/user/wlibc.fi` | `metric()` skaliert Laengen, Hundertstel nicht |
| `kernel/user/wlib.fi` | `window()` nimmt logische Masse und deckelt auf den Schirm |
| `kernel/user/taskbar.fi` | `height=` aus der Konfiguration ist logisch; Groessenaenderung wird berichtet |
| `tools/usbimg/build.sh` | zwei Menueeintraege mit fester Laderaufloesung |
| `tools/schirm/*.sh` | die zwei Werkzeuge dieser Runde |
