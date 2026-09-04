# Runde BLECHFUENF -- der Absturz sichtbar machen, die Tastatur messbar machen

Grundlage: Justins Blechfotos vom 04.09.2026, 18:47, Abbild `cdaf446b`,
Commit `67c6047`. Erster funktionierender Schreibtisch auf echter
Hardware -- und vier Meldungen dazu.

## Was gebaut wurde

1. **Absturzanzeige im Band** (`kgui.absturz`, `trap.report`). Vektor,
   Name, RIP, CR2, Fehlercode, CS, RSP und die Stufe in grosser roter
   Schrift im reservierten Band, eigener unbedingter `flush_rect`, dann
   `halt_forever` statt `power.shutdown` -- mit `absturzhalt`, damit die
   Regressionslaeufe ihren EXIT_TRAP behalten.
   Gegenprobe `knall`: Seitenfehler auf Bestellung.
   GEMESSEN: `EXCEPTION 14 #PF err=0x2 cr2=0x7fffffff0000 rip=0x2c300d`,
   rote Tinte in den Bildzeilen 12..230, und der Unterschied zwischen
   zwei Fotos im Abstand von 15 s ist **null Bildpunkte**.

2. **Zeile 18 TAST** -- je GERAET gezaehlt statt in einer Summe.
   `BER` fertige Transfers, `ARM` gelegte Bloecke, `CC` letzter
   Fertigmeldungscode, `ROH` die ersten acht Oktett des letzten Berichts.
   GEMESSEN in QEMU, acht Tasten von aussen:
   vorher `BER 0 ARM 1 CC 0`, nachher `BER 16 ARM 17 CC 1`, `TAS 8`.

3. **Zeile 19 UHR** -- RTC, Kernuhr und Versatz nebeneinander.
   `tz=<minuten>` auf der Kommandozeile, in allen Schreibtisch-
   Eintraegen `tz=120`. GEMESSEN: `RTC 17:32:45 KRN 19:32:45 TZ 120`.

4. **`pulsled`** -- LED-Herzschlag UND die zwei Blinkfelder am rechten
   Rand nur noch mit diesem Wort. In den Schreibtisch-Eintraegen AUS,
   im neuen Eintrag "Diagnose: Lampe und Blinkfelder" AN.
   GEMESSEN: `LED 1/1/0` statt `37/37/0`, null helle Punkte rechts.

5. **`nopuls`** und der Rueckfall des Pulses. `letzte_marke` wurde in
   JEDER Rueckfallpruefung neu gesetzt -- seit die Schleife wirklich
   laeuft, passen viertausend Runden in eine Marke, und dann feuerte er
   immer. Jetzt gegen die Marke des letzten Anstrichs.

6. **Der Schliessweg gehaertet**: `S_CAPHOV` wird geloescht, Masse und
   Terminalzustand auf null, `fill` und `term_scroll` weisen einen
   Nullpuffer ab. Reproduzieren liess sich Justins Absturz in QEMU
   NICHT -- weder ueber `destroy` noch ueber einen echten Klick auf das
   Kreuz (`zumachen`). Das ist keine Reparatur, das ist eine Absicherung.

7. **Auswahlfarbe** (`wlibc.theme_selfg`). Gemessen aus Justins
   Diagnosezeile: `sel=3104668 selfg=0` -- schwarze Schrift auf
   dunkelblauem Grund, Kontrast 3,7. Die Auswahl WURDE gesetzt und war
   unsichtbar. Jetzt Zusage 4,5:1, sonst der bessere von Schwarz/Weiss.

8. **Band auf zwei Fuenftel**. Zwanzig Zeilen sind 483 Bildpunkte, ein
   Drittel von 1440 sind 480 -- `set_band` lehnte ab (`BAND H 0`,
   gemessen) und mit ihm den Schutz der Vorrunde.

9. `HERZ HZ` heisst jetzt `SCHL` (es war nie eine Frequenz), `RND` ist
   im Quelltext erklaert.

## Belegt am fertigen Abbild

Ueber den Lader (OVMF), 3440x1440, zwei xHCI-Regler, Tastatur und Maus:
`BAND H 486`, **20 von 20 Zeilen mit Tinte**, `HZ 98`, schwarzer Grund
1 036 584 von 1 134 720 Bildpunkten, Aenderungen zwischen zwei Fotos
6 651 im Band und 12 276 darunter.
Regression `tools/wm/run.sh`: **104 passed, 0 failed**.
