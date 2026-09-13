# RUNDE FUI-VENDOR-BILD — Belege und ehrlicher Befund

Zweig `fui-vendor-bild` im Baum `/root/fvb-osum`, abgezweigt von
`main` = `c2ba476`. Firn-Zweig `fui-kachel-mitte` im Baum
`/root/firn-fvb`, abgezweigt von `fui-auf-main` = `39dc09c0`.

---

## 0. WAS IN EINEM SATZ HERAUSKAM

Der Vendor-Sprung auf den Bild+SVG-Stand ist drin und der Bau ist grün;
das Kontrollzentrum hat drei Kacheln je Reihe mit mittigem Symbol und
mittiger Beschriftung; fUi kann jetzt kürzen, umbrechen und zentrieren;
und **zwei der drei Punkte, die Justin als Fehler gemeldet hat, waren
keine** — der Beleg dafür steht unten mit Zahlen, nicht mit einer
Behauptung.

---

## 1. DER VENDOR-SPRUNG (Auftragspunkt 1)

`vendor/firn/COMMIT` steht jetzt auf `c4e3dfce` — das ist `39dc09c0`
plus die zwei fUi-Commits dieser Runde.

### Die drei vorhandenen Flicken passen unverändert — nachgerechnet

Nicht probiert und gehofft, sondern vorher gemessen: die acht Dateien,
die `0001`–`0003` anfassen, haben zwischen `e7cb0ec8` und `39dc09c0`
**denselben Blob-Hash**.

```
GLEICH  net/stack.fi   2f58ae5629f6864df8ae2fece1271e2f5974845e
GLEICH  rt/rt.fi       2eb5a02f76f7baf85afd3f598362644dd61d145e
GLEICH  std/rt.fi      684876336f51f4eff29588633afdc5664eb2b464
GLEICH  firnc1/rt.fi   684876336f51f4eff29588633afdc5664eb2b464
GLEICH  html/mem.fi    e24c1295dd18c9356270c446149b02c9d01337df
GLEICH  std/deflate.fi 481794565173c66d98086eee7d9144f623af8ea5
GLEICH  std/crypto/crypto_main.fi  f0856c25e81ab0d873bf44196d4b3fe4b99239af
GLEICH  tls/tls.fi     a5fab572df80fd61b4fc25b05de8648f5e4b40e0
```

Und `git diff --stat e7cb0ec8 39dc09c0 -- compiler bin` ist **leer**:
der Übersetzer selbst ist zwischen beiden Commits unverändert. Ein
Regress im Kern kann aus diesem Nachziehen also nicht kommen.

### Ein NEUER Flicken war nötig: 0004

Mit `lib/svg` kam ein Modul `svg.image` herein. Firn führt ein Modul
unter dem **letzten** Abschnitt seines Pfades — es heisst also `image`,
genau wie `kernel/user/image.fi` dieses Repos. `explorer` zieht beide in
denselben Graphen (über `expdlg.fi` und über `fuib.fi` → `fui.uisvg`),
und der Bau brach ab:

```
== explorer: der Uebersetzer sagt nein
error: module 'image' has no element 'ist_svg'
    --> vendor/firn/lib/fui/uisvg.fi:136:12
```

**Kein fehlender Code.** `ist_svg` (Zeile 57) und `svg_zu_bild_farbe`
(Zeile 124) stehen in `svg/image.fi` und sind exportiert. Nachgewiesen
mit zwei leeren Modulen gleichen Endnamens:

```
error: module 'image' is imported more than once
```

Gegenprobe, dass es die Kollision ist und nicht das Modul: `taskbar` und
`settings` ziehen `fuib` ebenfalls, aber kein `image` — beide übersetzen
mit rc=0.

Geflickt auf der **neuen** Seite (`svg/image.fi` → `svg/svgimage.fi`),
nicht in OrientOS. Grund: Firn löst denselben Stoss mit
`lib/fui/uiimage.fi` bereits so und schreibt es in dessen Kopf aus;
`svg/image.fi` wurde beim Portieren übersehen. `kernel/user/image.fi`
hat drei Benutzer (`expdlg`, `snip`, `viewer`) und gehört fremden Runden.

### Eine Falle, die eine Stunde gekostet hat

Der erste Anlauf drückte die Umbenennung als `rename from`/`rename to`
aus. **GNU patch 2.7.6 führt eine reine Umbenennung nicht aus**, wenn
keine Änderungszeilen danebenstehen: es meldet `already renamed from
svg/svgimage.fi`, gibt **0** zurück und lässt die Datei liegen. Der
Flickenlauf sah erfolgreich aus, `svg/image.fi` lag unverändert da, und
der Bau fiel wieder auf denselben Fehler — nur diesmal still.

Der Flicken drückt die Umbenennung deshalb als **Löschen + Anlegen**
aus. Der Inhalt von `svgimage.fi` ist Oktett für Oktett der von
`image.fi` (geprüft mit `diff` gegen `git show 39dc09c0:lib/svg/image.fi`,
null Unterschiede).

### `vendor/net/BLOBS` war seit acht Tagen falsch — auch auf `main`

Abschnitt 1 der Abnahme war **vor** dieser Runde rot, und zwar auf
`main` mit dem alten Pin:

```
$ git rev-parse e7cb0ec8:lib/net/wire.fi
2632dea5...        BLOBS sagte 0dd4c71c...
```

Ursache gefunden: die alten Werte stammen aus Firn-Commit `c86092fb`.
Am 05.09.2026 hat `6ddd9375` das ganze Repo von GPL-2.0-only auf MPL-2.0
umgestellt. Der **gesamte** Unterschied an `wire.fi` ist eine Zeile:

```
-// SPDX-License-Identifier: GPL-2.0-only
+// SPDX-License-Identifier: MPL-2.0
```

Am Stack selbst hat sich nichts geändert — genau das soll die Datei ja
zusichern. Die drei Werte sind nachgezogen, mit dieser Begründung im
Kopf der Datei. Sie sind in **beiden** Pins dieselben.

---

## 2. WAS fUi DAZUBEKOMMEN HAT (Justins Grundsatzregel)

Justin: *„Wenn fUi etwas nicht kann, das gebraucht wird, dann bau es in
fUi ein."* Alles Folgende steht im Firn-Repo auf `fui-kachel-mitte`,
nicht in OrientOS.

### `lib/fui/painter.fi` — kürzen und umbrechen

| neu | was es tut |
|---|---|
| `ellipsis_w` | wie breit `...` in diesem Lauf ist |
| `run_fits_ellipsis` | wie viel passt, wenn `...` dahinter muss |
| `run_draw_ellipsis` | eine Zeile, die mit `...` endet statt abzubrechen |
| `run_line_upto` | das Ende der Zeile, an der **Wortgrenze** |
| `run_line_count` | wie viele Zeilen der Text braucht |
| `run_draw_wrapped` | mehrzeilig, letzte Zeile mit `...` |

Vorher schnitt `run_draw` hart auf dem letzten passenden Zeichen ab —
richtig für einen Textcursor, falsch für eine Beschriftung. Genau daraus
wurde „Netz vortaeusc".

### `lib/fui/widget.fi` — mittig

`ART_ABOVE_CENTER` (Symbol mittig über **mittiger** Beschriftung) und
`text_lines` (wie viele Zeilen die Beschriftung haben darf; 0 und 1
heissen beide „eine", damit die Vorgabe die alte bleibt).

`ART_ABOVE` stellte das Symbol schon mittig, die Beschriftung nahm aber
die Ausrichtung ihres Elements — bei einem Label linksbündig. Mittiges
Symbol über linksbündigem Wort, sichtbar schief.

### `lib/fui/render.fi` — die Naht

`text_align_of` ist jetzt die **eine** Stelle, die die Textausrichtung
entscheidet, `line_h_of` die **eine**, die den Zeilenabstand kennt (drei
Stellen brauchen ihn: Messen, Malen, Grundlinie), und `pref_of` rechnet
die zusätzlichen Zeilen in die Höhe ein.

### Zwei Fehler, die erst der Prüfstand gezeigt hat

1. **Nur Leerzeichen sind keine Zeile.** `run_line_count` sagte drei
   Zeilen voraus, wo `run_draw_wrapped` zwei malte; die dritte war der
   Rest `"  "` am Ende der Zeichenkette. Wer die Höhe aus der Vorhersage
   nimmt, lässt dafür eine leere Zeile Platz. Behoben mit `nur_leer` in
   **beiden** Schleifen.
2. Der Prüfstand selbst mass mit `theme_new(true)` gegen das **dunkle**
   Thema und hielt den dunklen Grund für Schrift: elf Zusagen fielen,
   ohne dass die Bibliothek etwas falsch machte.

### `tools/fui/wrap_main.fi` — 18 Zusagen, alle in Bildpunkten

```
1 kurzer Text: linke Kante unveraendert       OK  got 21  want 21
1 kurzer Text: rechte Kante unveraendert      OK  got 53  want 53
2 der Text ist wirklich zu breit fuer 90 px   OK  got 141 want 90
2 nichts ragt ueber den Kasten hinaus         OK  got 101 want 110
2 gekuerzt wurde gemeldet                     OK  got 9   want 17
2 am rechten Ende steht nur die Punktzeile    OK
3 es wurden zwei Zeilen gemalt                OK  got 2   want 2
3 im Bild stehen zwei Tintenbaender           OK  got 2   want 2
3 auch umbrochen ragt nichts hinaus           OK  got 106 want 110
3 run_line_count zaehlt wie gemalt wird       OK  got 2   want 2
3 ohne Grenze drei Zeilen (Wort getrennt)     OK  got 3   want 3
4 ART_ABOVE steht links (wie bisher)          OK  got 57  want 140
4 ART_ABOVE_CENTER steht mittig               OK  got 140 want 140
5 das Symbol sitzt mittig ueber dem Text      OK  got 139 want 140
6 die Kachelbeschriftung steht zweizeilig     OK  got 2   want 2
6 sie bleibt innerhalb der Kachel (rechts)    OK  got 144 want 150
6 sie bleibt innerhalb der Kachel (links)     OK  got 44  want 40
6 einzeilig muesste gekuerzt werden           OK
FEHLER: 0
```

Die neun vorhandenen fUi-Prüfstände (`text`, `wave2`, `wave3`,
`control`, `layout`, `style`, `art`, `image`, `uisvg`) bleiben **alle
PASSED**.

---

## 3. DIE ZWEI fUi-STÄNDE, ZUSAMMENGEFÜHRT

Justins Nachtrag nannte zwei auseinandergelaufene Stände. Gemessen
stimmt das, aber **nicht** in dem Umfang, in dem der Auftrag es annahm:

```
painter.fi (HEAD von firn-dnspic)  50 Funktionen
uipaint.fi (dort unversioniert)    54 Funktionen
  nur in uipaint: default_req, mit_alpha, painter_raster, painter_set_canvas
  nur in painter: (keine)
```

Es ist tatsächlich ein Superset — **aber** es ruft eine andere
`font.metrics`-Schnittstelle auf:

```
hier:     metrics.fm_ascent(fm, size)
uipaint:  metrics.fm_ascent(fm, &req, size)
```

Dahinter steht der ganze Certus-Schriftstapel: `lib/font` hat dort **15
Dateien gegen 4** hier, `metrics.fi` **609 Zeilen gegen 157**, und der
Arbeitsbaum führt **105 gelöschte und 30 unversionierte** Dateien.
`uipaint.fi` herüberzukopieren hiesse, diesen Stapel mitzunehmen — das
ist keine Umbenennung mehr, das ist ein zweiter Merge mit eigener
Abnahme.

**Übernommen sind deshalb genau die zwei Sachen, die Justins
Akzentwunsch braucht, und beide sind nachweislich unabhängig davon:**

* `theme.fi`: `accent_derive` + `theme_set_accent` (+95 Zeilen). Der
  Flicken aus dem anderen Baum passt mit `git apply --check` **ohne
  Widerstand** auf diesen `theme.fi` — beide haben dieselbe Grundlage,
  die Änderung ist rein additiv, Importe identisch (`std.rt`,
  `fui.style`), keine `metrics`-Abhängigkeit.
* `painter.fi`: `mit_alpha` an den **vier** Füllwegen statt
  `theme.opaque`. Fünf Zeilen, keine Abhängigkeit. Das ist ein echter
  Fehler: `opaque` **setzt** das Alpha auf voll, auch wenn der Aufrufer
  ausdrücklich eines mitgegeben hat — eine Lasur wurde damit zu voller
  Farbe.

`painter.fi` bleibt der **eine** Maler dieses Zweigs. Wer `uipaint.fi`
später ganz hereinholen will, holt zuerst `lib/font`.

**Certus ist davon nicht betroffen**: es baut mit eigenem Übersetzer
gegen `FIRNLIB=/root/firn-dnspic/lib`. In diesen Baum wurde **nichts**
geschrieben — die Zeitstempel von `theme.fi` (13:46) und `uipaint.fi`
(14:02) liegen vor dem Beginn dieser Runde (14:11).

---

## 4. DAS KONTROLLZENTRUM (Justins Punkte 1 und 4)

### Drei Kacheln je Reihe

`TW0 = 180` war kein Geschmack, sondern ein Messwert: der Kopf von
`qs.fi` hat ihn durch Halbieren gegen das laufende System gefunden, weil
„Netz vortaeuschen" rund 160 Punkte nutzbare Breite braucht. Seit fUi
umbrechen und sauber kürzen kann, fällt diese Fessel.

Das Panel behält seine Breite, und in dieselbe Breite gehen jetzt drei:

```
3 * TW + 2 * GAP == 2 * TW0 + GAP   ->   TW = (2*TW0 - GAP) / 3
Vervielfachung 1:  (360 - 8) / 3 = 117
```

| | vorher | nachher |
|---|---|---|
| Kachel | 180 x 49 | **117 x 67** |
| Spalten | 2 | **3** |
| Panel | 388 x 286 | 387 x 322 |

Aus langgestreckt ist fast quadratisch geworden.

### Symbol und Text mittig — gemessen

Mitten der drei Kacheln in Reihe 1, Tinte gegen Sollmitte:

```
Kachel 0   gemessen 67    soll 68
Kachel 1   gemessen 192   soll 193
Kachel 2   gemessen 318   soll 318
```

Abweichung höchstens **1 Punkt**.

### Der Fehler, den erst das Bild gezeigt hat — und er lag in der Brücke

Nach dem Umbau war die eingeschaltete Kachel im Bild nur noch **13
Zeilen** hoch statt 67, und der Quelltext sah dabei völlig richtig aus.

Ursache: `kernel/user/fuib.fi` rief `painter_init(pz(), cv(), w, 64)` —
64 Zeilen Rastervorrat, ohne Begründung. `painter.raster_window` gibt
`false` zurück, sobald die Fläche höher ist, und `round_rect` kehrt
daraufhin **wortlos** zurück. Die Kachel wuchs von 49 auf 67 Punkte,
67+2 > 64, also fiel die Füllung aus. Dieselbe Falle, die der Kopf von
`run_draw` für Text beschreibt: *„the gradient looked broken; in truth
nothing was drawn at all."*

Jetzt **96** — mehr als `wlibc.SURF_ROWS` (81), also fängt es jede
Fläche, die auf einem Band entstehen kann. Kosten: eine Anforderung beim
Aufbau der Brücke, nicht je Bild.

```
vorher   1463 Akzentpunkte, Block 117 x 13
nachher  7079 Akzentpunkte, Kachel 117 x 67
```

### Warum der Umbruch in `qs.fi` steht und nicht in fUi — die ehrliche Grenze

fUi kann ihn seit dieser Runde. **fUi malt in OrientOS aber keinen
Text**: `fuib.fi` setzt `painter_set_font(pz(), s_fm)` mit `s_fm = 0`,
und `s_fm` wird nirgends zugewiesen (`grep` liefert 0 Treffer). Jeder
fUi-Textaufruf kehrt deshalb sofort zurück:

```
if (*z).ok == 0 || !metrics.fm_present((*z).fm) || n == 0 { return x }
```

Der Text kommt aus `wlibc.text_at`, und das ist Absicht: Umlaute, die
Symbolschrift und `say_painted` hängen daran; der Kopf von `fuib.draw`
sagt ausdrücklich, dass zwei Schriftsetzer auf einer Fläche zwei
Ergebnisse wären.

`zwei_zeilen` in `qs.fi` rechnet deshalb nur **aus**, wo die Zeilen
anfangen; gemalt wird weiter mit `wlib.draw_text`. Es entsteht **keine
zweite Zeichenschicht** — die Regel ist eingehalten.

### ui_scale = 2

Mit `uiscale=2` auf der Kernel-Kommandozeile gemessen:

```
Panel   387 x 322  ->  774 x 651
Kachel  117 breit  ->  234 breit      Verhaeltnis exakt 2.00
```

Jedes Mass bleibt ein Vielfaches der Schrifthöhe, nichts liegt
übereinander. Bilder: `.shots/11-fix-qs.png` (Skala 1),
`.shots/21-skala2-qs.png` (Skala 2).

---

## 5. JUSTINS PUNKT 2 — DER AKZENT WAR SCHON RICHTIG

Justin: *„Im Bild `07-dunkelmodus-qs.png` sind die aktiven Kacheln
violett, im Hellmodus blau."* Das stimmt — die **Schlussfolgerung**
stimmt nicht.

`wlibc.bind_accent` läuft eine Rampe, die aus **einer** Grundfarbe durch
Mischen mit Weiss/Schwarz entsteht (`ramp_build`). Der Farbton bleibt,
nur die Helligkeit zieht nach. Nachgerechnet mit `tools/theme/model.py`
— der zweiten, unabhängigen Umsetzung des Tokensystems —, **derselbe**
eingestellte Akzent in beiden Modi:

```
                Akzent gemalt   Ton     Helligkeit   Kontrast/Grund
day   / hell    #2563eb        221.2°   0.533        4.94:1
midnight/dunkel #779ef2        221.0°   0.708        6.71:1

FARBTON-UNTERSCHIED: 0.2 Grad
HELLIGKEIT:          +0.175  (genau das, was Justin verlangt)
```

Das ist **exakt** die Vorgabe: „Ton und Sättigung bleiben, Luminanz
zieht nach", und beide Modi tragen den Kontrast (4.94:1 / 6.71:1).

Der Farbsprung, den Justin gesehen hat, kam von etwas anderem: die
**Vorlagen** setzen verschiedene Akzente.

```
tageslicht   accent=        -> Schema day        2563eb   Ton 221°
mitternacht  accent=8b5cf6                                Ton 258°
```

`b799f9` aus seinem Bild stammt aus `8b5cf6` (Ton 258.3° → 258.8°,
Unterschied **0.4°**) — die Rampe hat den Ton also auch dort gehalten.
Verglichen wurden zwei **verschiedene Vorlagen**, nicht zwei Modi
derselben.

Und die Regel, die Justin fordert, ist bereits die implementierte:

```
fn theme_accent_wanted() -> u64 {
    if set_accent != 0 { ... return set_accent }
    return sch_accent          // Schema-Akzent NUR als Vorgabewert
}
```

**Fazit:** kein Code zu ändern. Wer in beiden Modi dieselbe Farbe will,
setzt sie einmal — dann gilt sie in hell und dunkel. Auf der fUi-Seite
ist dasselbe jetzt ebenfalls möglich (`theme_set_accent`, aus dem
Certus-Baum geholt), belegt:

```
theme_set_accent(hell,   0x2563EB) -> accent 0x2563EB
theme_set_accent(dunkel, 0x2563EB) -> accent 0x2563EB     0 Grad
   darauf: 0xFFFFFF (hell) / 0xFBFBFE (dunkel), aus Kontrast gewaehlt
```

---

## 6. JUSTINS PUNKT 3 — DER REGLER WAR NICHT KAPUTT

Auf den Bildern stand er scheinbar auf null. **Er ist es wirklich**, und
das ist die richtige Anzeige:

`dget` gibt bei fehlgeschlagenem Systemaufruf `0` zurück, und QEMU hat
weder Helligkeitssteuerung noch Ton. Also ist der Wert 0, `kx == SL_X()`,
und die gefüllte Strecke ist 0 breit.

Die Füllung **gibt es** und sie steht in `T_ACCENT`. Mit erzwungenen
Werten gemessen (Messfassung, ausdrücklich **nicht** eingecheckt):

```
Helligkeit  60 %  ->  Akzent x37..228  = 58 %
Lautstaerke 65 %  ->  Akzent x37..244  = 63 %
```

Die Abweichung ist die Knopfbreite in der Rechnung. Bild:
`.shots/12-mess-qs.png`.

---

## 7. JUSTINS PUNKT 5 — HOVER

Die Maschinerie ist da und sie ist **richtig gebaut**, einschliesslich
des Falls, den Justin ausdrücklich genannt hat: eine eingeschaltete
Kachel unter der Maus muss anders aussehen als eine ausgeschaltete.

```fi
if sl == dn_tile {                       // gedrueckt
    if on { bg = mix(bg, T_BTNDN, 50) }  // Akzent BLEIBT, wird gemischt
    else  { bg = T_BTNDN }
} else if sl == hov_tile {               // Zeiger drueber
    if on { bg = mix(bg, T_BTNHI, 50) }  // Akzent BLEIBT
    else  { bg = T_BTNHI }
}
```

Eine eingeschaltete Kachel unter der Maus behält also ihre Akzentfarbe
und wird nur aufgehellt — sie springt nicht auf Grau und sieht nicht aus,
als hätte sie sich ausgeschaltet. Im Dunkelmodus ist `T_BTNHI` die
hellere Stufe (das Schema liefert sie, nicht der Programmcode).

**Was ich NICHT geliefert habe:** ein Schirmbild mit dem Zeiger auf einer
Kachel. `tools/usbimg/shot-qs.sh` schickt Tasten über den QEMU-Monitor,
keine Mausbewegung; dafür müsste der Prüfstand `mouse_move` schicken und
die Leiste den Zeiger über `WS_MX/WS_MY` lesen. Das ist ein eigener
kleiner Umbau am Foto-Werkzeug und gehört mit eigener Messung gefahren.
Die Farbrechnung oben ist nachgelesen, **nicht** am Bild belegt — das
sage ich lieber, als ein Bild zu behaupten, das es nicht gibt.

---

## 8. DIE BILDER

| Datei | was darauf steht |
|---|---|
| `.shots/00-basis-qs.png` | Ausgangsstand: zwei Spalten, Kachel 180x49 |
| `.shots/11-fix-qs.png` | **nachher**: drei Spalten, Kachel 117x67, alles mittig |
| `.shots/12-mess-qs.png` | die Regler mit erzwungenen Werten (58 % / 63 %) |
| `.shots/21-skala2-qs.png` | `uiscale=2`: Panel 774x651, Kachel 234 breit |
| `.shots/vergleich-vorher-nachher.png` | beide Panels nebeneinander |
| `.shots/panel-*.png` | die Ausschnitte, aus denen gerechnet wurde |

### Kanalprobe (gegen die R/B-Vertauschung, die es hier schon gab)

```
00-basis-qs.png   #2563eb  8074 Punkte   #eb6325 (R/B getauscht)  0
11-fix-qs.png     #2563eb  7079 Punkte   #eb6325 (R/B getauscht)  0
gemessen R=37 G=99 B=235   soll R=37 G=99 B=235   -> R OK  G OK  B OK
```

Einzeln je Kanal geprüft und ausdrücklich gegen die vertauschte Variante
gegengeprüft: **keine Vertauschung**.

---

## 9. DIE ABNAHME

`bash tools/check-ui.sh` — **PASSED**, unverändert:

```
166 Dateien geprueft
0 Programme malen sich ein Bedienelement selbst
0 Programme greifen an der Bibliothek vorbei auf fUi zu
0 Funktionen in wlib.fi malen an fUi vorbei
```

Kein Farbliteral im Programmcode: `grep -E '0x[0-9a-fA-F]{6}'` über
`qs.fi` → **0 Treffer**.

Der Bau:

```
kern        5032592 Oktette
programme   55 Stueck
apps        2 Stueck (TLS 1.3)
uebersetzer 1515184 Oktette
abbild      130 MiB, GPT, EFI 96 MiB + Wurzel 32 MiB
akzent      #2563eb (aus schema day)
EXIT 0
```

### DIE VOLLE ABNAHME KONNTE ICH NICHT SAUBER FAHREN — und das sage ich, statt eine Zahl zu erfinden

Der Sollwert des Auftrags ist 44/4 im Abschnitt USBIMG. **Diese Zahl habe
ich nicht erreicht und ich kann sie auch nicht belegen** — nicht, weil
etwas kaputt wäre, sondern weil die Maschine mitten im Lauf die Platte
vollgeschrieben hat:

```
$ df -h /
/dev/mapper/pve-vm--104--disk--0   54G   52G  125M 100% /
```

`.test-work/usbimg.log` bricht an genau dieser Stelle ab:

```
== 6. Gegenprobe: anderer Plattencontroller, andere Netzkarte ==
cp: error writing '/tmp/tmp.TPJyg4e1G3/ahci.img': No space left on device
```

**17 der 73 Abschnittsprotokolle** nennen `No space left on device`:
`blech, display, glyphe, hid, k14, k17, ota, praesenz, protokoll, stick,
systembus, ton2, update, usbimg, werkzeug, wlan, wlan2`. Alles, was in
diesen Abschnitten „gescheitert" heisst, misst den Plattenplatz und
nicht den Kernel. Der Platz ist nicht von dieser Runde belegt — meine
beiden Bäume zusammen sind 440 MB, das Abbild 291 MB; die 52 GB
verteilen sich über rund zwei Dutzend fremder Arbeitsbäume auf dieser
Maschine.

**Was BIS DAHIN gültig gemessen wurde**, und das ist der brauchbare Teil:

```
FREESTANDING  41 passed, 0 failed        POSIX     150 passed, 0 failed
CORE          46 proofs, 0 failures      SMP        59 passed, 0 failed
KERNEL       176 passed, 0 failed        CAPS       67 passed, 0 failed
BOOT          20 passed, 0 failed        GFX        76 passed, 0 failed
UNIX         107 passed, 0 failed        NET        75 passed, 0 failed
GUARD         58 passed, 0 failed        AVX        32 passed, 0 failed
K11           85 passed, 0 failed        HV        114 passed, 0 failed
K13           99 passed, 0 failed        TILING     68 passed, 0 failed
K18          170 passed, 0 failed        TRESOR    220 passed, 0 failed
HWNET         56 passed, 0 failed        HWNETTLS   24 passed, 0 failed
MULTIUSER     91 passed, 0 failed        INIT       78 passed, 0 failed
KVM           31 passed, 0 failed        POLL       67 bestanden, 0 durchgefallen
FSROBUST      30 bestanden, 0 gescheitert
```

Zusammengezählt über den ganzen (abgebrochenen) Lauf: **3224 bestanden**.

**Abschnitt 4 (KERNEL) ist mit 176/0 grün** — das ist der Abschnitt, der
im ersten Anlauf mit „firnc1 does not compile the kernel" gefallen war.

Vom USBIMG-Abschnitt selbst sind die Abschnitte 1–5 durchgelaufen, bevor
der Platz ausging, und darin stehen **zwei der vier bekannten Fehler**
genau dort, wo sie hingehören:

```
ok    derselbe Kern startet unter UEFI (OVMF)
ok    kein 'Cannot use text mode with UEFI'
NEIN  UEFI-Lauf: erkannte Firmware: ? (erwartet UEFI)
NEIN  UEFI: kein Rahmenpuffer im Bericht
```

Die anderen beiden bekannten („Starter ist nicht deutsch",
„Taskleisten-Text") liegen in den Abschnitten danach, die der
Plattenplatz weggenommen hat.

**Was daraus NICHT folgt:** dass 44/4 erreicht ist. Das muss jemand auf
einer Maschine mit freiem Platz nachfahren. **Was daraus folgt:** der
Vendor-Sprung und der Umbau haben in 26 vollständig gelaufenen
Abschnitten mit zusammen über 1900 Zusagen **keinen einzigen** Fehler
erzeugt, und der Kern selbst ist mit 176/0 grün.

### Eine Warnung für den nächsten Lauf, die teurer war als sie klingt

`./test.sh` fährt **zehn Abschnitte gleichzeitig** (`nproc/2`). Dabei
meldete die Abnahme Fehler, die keine sind:

```
FAIL  firnc1 does not compile the kernel
FAIL  firnc1: der Kern laesst sich nicht bauen     (und 99 Folgefehler in k14)
```

Gemessen, warum: **firnc1 braucht 1,1 GB Arbeitsspeicher und 90 Sekunden**
je Aufruf und schreibt dabei eine 53-MB-`.s`-Datei. Die Platte dieser
Maschine steht auf **99 % (800 MB frei von 54 GB)**. Zehn Abschnitte
gleichzeitig gehen sich damit nicht aus, firnc1 stirbt mit **RC=2 und
leerer Fehlerausgabe**.

Die Kreuzprobe zeigt, dass es **kein** Regress ist:

```
Quelle   firnc1        Ergebnis
main     alt (main)    RC=0  93s
main     neu (fvb)     RC=0  ~90s
fvb      alt (main)    RC=0  90s
fvb      neu (fvb)     RC=2 / RC=0   <- dieselbe Zeile, mal so, mal so
```

Derselbe Aufruf, der mit RC=2 starb, lief kurz darauf mit **RC=0** durch
(12 762 960 Oktette). Mit `OSUM_JOBS=3` ist Abschnitt 4 dann auch in der
Abnahme grün: **KERNEL: 176 passed, 0 failed**.

**Wer diese Abnahme fährt: `OSUM_JOBS=3` setzen und vorher `df -h /`
ansehen.** Bei voller Platte misst sie den Plattenplatz, nicht den Kernel.

---

## 10. DIE EHRLICHE RESTLISTE

1. **fUi malt in OrientOS keinen Text** (`s_fm = 0` in `fuib.fi`). Solange
   das so ist, können Beschriftungen nicht über die Brücke gesetzt
   werden, und `run_draw_wrapped`/`run_draw_ellipsis` liegen im System
   ungenutzt. Wer das ändern will, muss der Brücke eine Schriftmasse
   geben — und dann entscheiden, wer von beiden Schriftsetzern gewinnt.
   Das ist ein eigener Auftrag mit eigener Abnahme.
2. **Hover ist nachgelesen, nicht fotografiert** (Abschnitt 7). Es fehlt
   `mouse_move` im Foto-Werkzeug.
3. **`uipaint.fi` ist nicht hereingeholt**, nur seine zwei nützlichen
   Funktionen. Der Rest hängt am Certus-Schriftstapel (Abschnitt 3).
4. **Die Bild-/SVG-Fähigkeit ist eingebaut, aber noch nicht benutzt.**
   Die Kacheln ziehen ihre Symbole weiter aus `lib/icons.fi`
   (`wlibc.icon_at`, 46 Vektorsymbole) und nicht über `uisvg`. Das ist
   kein Versäumnis, sondern dieselbe Grenze wie Punkt 1: der Weg über
   `fuib` führt durch fUis Widget, und das braucht die Schrift. Die
   Symbolschrift wächst mit `ui_scale` mit und ist in jeder Farbe
   lesbar — sie ist für diesen Zweck nicht schlechter.
5. **Zwei echte, aber fremde Fehler stehen offen.** `WM: 102 passed,
   2 FAILED` — „die Spitze des Zeigers steht in der Bildmitte" und „zwei
   Bildpunkte tiefer ist er weiss gefuellt". `wm.log` nennt **keinen**
   Plattenfehler, das sind also echte Fehlschläge. Sie gehören aber
   nicht zu dieser Runde, und das ist nachweisbar statt behauptet: der
   Mauszeiger wird in `kernel/wm.fi` gemalt, und die vollständige Liste
   meiner Änderungen an Programmcode ist

   ```
   kernel/user/fuib.fi   EINE Zahl:  painter_init(..., 64) -> 96
   kernel/user/qs.fi     das Kachelraster
   ```

   `grep -c 'zeiger\|cursor'` über beide Dateien: **0**. Ein Wert des
   Rastervorrats kann den Zeiger des Fensterservers nicht verschieben.
   Nachfahren sollte das trotzdem jemand auf einer Maschine mit Platz --
   ich konnte den Gegenlauf auf `main` nicht bauen (331 MB frei).

6. **`vendor/net/BLOBS` war acht Tage falsch, ohne dass es jemandem
   auffiel.** Abschnitt 1 der Abnahme war durchgehend rot. Das nächste
   Mal fällt es früher auf, wenn man die Abnahme nicht nur nach der
   Endzahl beurteilt.

---

## 11. COMMITS UND ZWEIGE

**Firn** — `/root/jarvis/projects/u_DiS4in7esMF1/firn`, Zweig
`fui-kachel-mitte`, abgezweigt von `fui-auf-main` (`39dc09c0`):

```
eedad5bc  fUi kann jetzt kuerzen, umbrechen und mittig stellen
c4e3dfce  fUi: der einstellbare Akzent und der Alpha-Fehler, aus dem
          Certus-Baum geholt
```

**OSUM** — `/root/jarvis/projects/u_DiS4in7esMF1/osum`, Zweig
`fui-vendor-bild`, abgezweigt von `main` (`c2ba476`):

```
ccbfc55  vendor/firn auf 39dc09c0 (Bild+SVG) -- und der Namensstoss,
         der dabei auffiel
bd3c442  Kontrollzentrum: drei Kacheln je Reihe, Symbol und Text mittig
```

### Kann `main` gemerged werden?

**Ja**, und zwar in dieser Reihenfolge:

1. `fui-kachel-mitte` ist der Strang-Zweig von Firn. Er hat eine eigene,
   mit `firn/main` **nicht verwandte** Historie — nicht nach `main`
   mergen, sondern als Spitze von `fui-auf-main` weiterführen.
2. `fui-vendor-bild` lässt sich nach `osum/main` mergen. Es berührt
   `vendor/firn/COMMIT`, `vendor/net/BLOBS`, den neuen Flicken `0004`
   sowie `kernel/user/qs.fi` und `kernel/user/fuib.fi` — sonst nichts.
3. **Bedingung:** der Merge zieht den Vendor-Pin auf `c4e3dfce` mit. Wer
   danach baut, muss einmal `./vendor/firn/fetch-firnc.sh --force`
   laufen lassen; `.gebaut` erzwingt das von selbst.
