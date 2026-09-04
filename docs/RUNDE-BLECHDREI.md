# RUNDE BLECHDREI -- die Messtafel bekommt ein eigenes Stueck Bildschirm

Repo `/root/osum-blechhid`. Auslöser: Justins Fotos vom 04.09.2026, 16:25,
mit Commit `5a7ce4e`, und sein Zwischenruf: *"ich muss ganz schnell sein
mit dem Foto machen, weil kurz darauf der Schreibtisch startet und alles
ueberschreibt."*

## Der Kern der Runde

Ein Messgeraet, das man nur mit Reflexen ablesen kann, ist keines. Die
Tafel wird seit drei Runden aus dem Zeitgeber gemalt und war trotzdem
nach knapp einer Sekunde weg -- weil Konsole, Fensterserver, Taskleiste
und Ring 3 alle auf DIESELBE Flaeche malen und jeder von ihnen gute
Gruende hat, ein Vollbild zu schreiben.

Also wird der Bereich jetzt an der einzigen Stelle gesperrt, durch die
sie alle muessen: in den Zeichengrundlagen (`kernel/fb.fi`).

`S_BAND` sind die obersten Bildzeilen, in die NIEMAND schreiben darf.
`S_BANDOPEN` ist der Schluessel, und den hat nur der Tafelmaler.
Geklemmt wird in `pixel`, `pixel_a`, `hline`, `hline_mask`, `hline_a`,
`blit`, `glyph` -- und in `wm.fb_row`, dem Weg, der die Fensterflaeche
wortweise am `hline` vorbei in den Zweitpuffer kopiert.

Kosten: EINE Pruefung je BILDZEILE (nicht je Bildpunkt), weil der heisse
Weg `copy_words`/`rep stosq` ist.

## Die vier Befunde aus Justins Fotos

**BEFUND 1 -- Zeile 12 (STUFE) fehlte, 9 und 13 auch.** Nicht der
Zeitgeber-Pfad war schuld: 9, 12 und 13 stehen alle in
`tafel_streichen`. Es waren die Zeilen, die sich NICHT aendern. Die
Vorrunde zog nur geaenderte Zeilen nach und malte alles nur dann neu,
wenn sich `wm.composites` bewegt hatte. Der letzte `compose` nach dem
letzten Vollanstrich hat die statischen Zeilen damit dauerhaft
geloescht. Mit dem reservierten Band faellt die ganze Konstruktion weg.

**BEFUND 2 -- farbige Quadrate am rechten Rand.** KEIN Fehler. Das ist
der Herzschlag aus der Runde HAENGER (`fb.herz`, `fb.fi:3560ff`): Feld
links gruen = der normale Weg ueber Zweitpuffer und `flush`, Feld rechts
gelb = direkt in das Fenster der Karte. Dass bei Justin BEIDE blinken,
heisst nach der Legende dort: Zeitgeber laeuft, Bildweg in Ordnung, der
Fehler liegt darueber. Das ist ein Messwert, kein Zeichenfehler.

**BEFUND 3 -- Zeile 11 abgeschnitten ("... HUB 0 KBD").** Zwei Zahlen
fuer eine Sache: `kgui.TAFEL_SP` merkte sich 40 Zeichen, `wm.MESS_SPALTEN`
malte und uebertrug 30. Alles ab Zeichen 31 stand im Zweitpuffer und kam
nie ueber den Bus. Jetzt beide 48.

**BEFUND 4 -- USB-Regression `kbd=0 mouse=0`.** Der Unterschied zwischen
`bdc0d0f` und `f513165` an `kernel/usb.fi` sind 35 Zeilen, und alle
betreffen die Lampen -- am Aufzaehlen wurde nichts geaendert. Geaendert
hat sich die ZEIT: seit BLECHZWEI haelt die Tafel `slot_remap` und
`copy_words` unter `irq_save` zusammen, und auf einem gestreiften
Rahmenpuffer (19,8 MB durch EIN 2-MiB-Fenster) sind das lange Fenster
mit abgeschalteten Unterbrechungen -- mitten in `port_reset`. Die Tafel
malt deshalb nicht mehr, solange `usb.busy` gesetzt ist.

## Was neu ist

* **Reserviertes Band**, `fb.set_band` / `band` / `band_lo` / `band_open`.
  Hoehe aus `wm.messhoehe`. Mehr als ein Drittel der Bildhoehe wird
  abgelehnt -- auf 1280x800 faellt es damit von selbst auf das alte
  Verhalten zurueck, und `tools/wm/run.sh` sieht dieselben Koordinaten.
* **Zwei Spalten zu acht Zeilen.** Sechzehn Zeilen uebereinander waeren
  auf 3440x1440 678 Bildpunkte gewesen. Jetzt 390.
* **`messk` aus der BILDBREITE statt aus `uisc`.** `uisc` steht erst nach
  `surface` fest, die Tafel malt schon vorher -- auf 3440 kam damit k=2
  heraus, obwohl k=3 gemeint war. Jetzt `breite / 900`, mindestens 2,
  hoechstens 4. Auf 3440 also 24 x 48 Bildpunkte je Zeichen.
* **Zeile 8 zeigt die ECHTE Rate** (`HZ`), aus `rdtsc` und `time.khz`
  gerechnet -- eine von der Unterbrechung unabhaengige Uhr. Justin
  brauchte dafuer bisher zwei Fotos und eine Rechnung.
* **Zeile 14 (WAHL)**: welcher xHCI-Regler gewonnen hat und mit welcher
  Punktzahl je Regler. Diese Zahlen standen bisher nur auf der seriellen
  Leitung, die Justin nicht hat -- und genau sie erklaeren `kbd=0`.
* **Zeile 15 (BAND)**: Hoehe, Spalten, Zeichen je Zeile, Gesamtbreite.
  Die Tafel kann nicht beweisen, dass sie geschuetzt ist; diese Zeile
  sagt, warum.
* **`notafel`** schaltet das Band ab. Es wird VOR `tafel` geprueft, weil
  `find` das Wort "tafel" auch in "notafel" findet -- wer nur auf
  "tafel" prueft, schaltet mit dem Ausschalter ein.
* **Fenster fangen unter der Arbeitsflaeche an.** Der Schreibtisch legt
  sein Terminalfenster auf feste Koordinaten (x=24, y=40); mit dem Band
  lag es vollstaendig darunter. `wm.create` schiebt nach unten, nie
  hinein, und nur wenn es ein Band gibt.

## Gemessen am fertigen Abbild

Ueber den Lader (OVMF), 3440x1440, zwei xHCI-Regler, Eintrag 1:

```
fb: band=390  kol=2 1
tafel: 8 TAKT   IRQ 5000 MAL 844 LOOP 349 PRE 1 HZ 99
tafel: 12 STUFE ST 38 MAX 38 RND 3392 LOOP 349
tafel: 13 ABBILD PDE 10E3 PAT 01 KCH 1
tafel: 14 WAHL  HC 1/2 P 0,16
tafel: 15 BAND  H 390 KOL 2 SP 48 BR 2364
wm: fen i=0 id=7 x=24 y=390 w=560 h=380
```

Am Bildschirmfoto nachgerechnet: schwarzer Grund 2364 von 2364
Bildpunkten ueber die ganze Bandhoehe, **16 von 16 Zeilen mit Tinte**,
nichts ausserhalb des Bandes, Unterschied zwischen zwei Fotos im
Abstand von 15 s AUSSCHLIESSLICH innerhalb des Bandes (y=12..390).

Regression `tools/wm/run.sh`: **104 passed, 0 failed**.

## Was NICHT bewiesen ist

Der waagerechte Versatz im Fenster-Blit (Titel "inal -- sh") liess sich
in QEMU bei 3440x1440 NICHT nachstellen. Die naechstliegende Erklaerung
ist die Ueberlappung: die alte Tafel war 750 x 678 Bildpunkte gross und
lag ueber x=0..750, y=0..678 -- das Terminalfenster stand bei x=24,
y=40, w=560, also VOLLSTAENDIG darunter. Mit dem reservierten Band
koennen sich die beiden nicht mehr ueberschneiden. Bewiesen ist das
nicht; es ist eine Erklaerung, die das naechste Foto bestaetigt oder
widerlegt.
