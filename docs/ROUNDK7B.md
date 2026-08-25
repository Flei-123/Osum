# Runde K7B — sieben rote Zusagen nach dem Verschmelzen

Runde K7 (Grafik) war auf ihrem Zweig grün. Nach dem Verschmelzen von
K7, K9 (Signale, Terminals, Uhr, Zufall) und K8 (Netz) in `main` waren
sieben Zusagen des Grafikabschnitts rot — und zwar **nur die, in denen
Text vorkommt**. Farben, Geometrie, Linien, Doppelpufferung, Zeitmessung
und alle Gegenproben blieben grün.

Diese Datei sagt, was es war, wie es gefunden wurde und was daraus
folgt.

---

## 1. Der Befund

    FAIL  Zeile 14 bildpunktgenau: 'OSUM K7 FRAMEBUFFER 01234' -- 3200 Bildpunkte, 410 falsch
    FAIL  Zeile 15 bildpunktgenau: 'abcdefghijklm ABCDEFGHIJK' -- 3200 Bildpunkte, 525 falsch
    FAIL  der ganze Bildschirm gegen den seriellen Mitschnitt -- 900 Zellen, 9803 falsch
    FAIL  und der Text ebenso, bildpunktgenau (1024x768) -- 3200 Bildpunkte, 410 falsch
    FAIL  der ganze Bildschirm gegen den Mitschnitt der Shell -- 1491 Zellen, 13580 falsch
    FAIL  die Zeile der Shell steht bildpunktgenau auf dem Schirm -- 2560 Bildpunkte, 390 falsch
    FAIL  und die Zeile, mit der das Skript endet, ebenso -- 512 Bildpunkte, 99 falsch

410 von 3200 sind dreizehn Prozent — grob drei bis vier Zeichen von
fünfundzwanzig. Aus dieser Zahl liest niemand heraus, was los ist. Das
war der erste Mangel und er lag im Werkzeug, nicht im Kernel.

## 2. Wie es gefunden wurde

`tools/gfx/schau.py` zählte falsche Bildpunkte. Jetzt nennt es die
abweichenden Zellen **einzeln, mit Soll und erkanntem Ist** — das Ist
wird gegen alle 95 Glyphen des Zeichensatzes gehalten, nicht geraten.
Dazu kam der Unterbefehl `lesen`: das Bild zurück in Text.

    $ python3 tools/gfx/schau.py lesen pat.ppm kernel/font.fi 13 4
    800x600, 100 Spalten, 37 Zeilen
     13 |                                                ##                   |
     14 |      7             01234                                            |
     15 |                                                                     |
     16 |  :                                                                  |

Damit war es in einem Blick klar: **`7`, `01234` und `:` stehen da,
jeder Buchstabe fehlt.** Das ist kein Zeichenfehler, keine verrutschte
Spalte und kein Cursor — das sind fehlende Glyphen, und zwar genau die
ab 0x40.

Bestätigt wurde es am laufenden Kern, nicht am Quelltext: `kdata` liegt
bei 0x1E1000, der Zeichensatz also bei 0x210100. Über den QEMU-Monitor:

    (qemu) pmemsave 0x210000 0x800 "dmp.bin"

Der Vergleich mit `kernel/font.fi` sagt:

    kaputte Glyphen: 48 von 95
    40(@) 41(A) ... 6f(o)
    kaputter Bereich: 0x2F300 .. 0x2F600

## 3. Die Ursache

    kernel/fb.fi      const FB_OFF:   u64 = 0x2F000      (Runde K7)
    kernel/fb.fi      const FONT_OFF: u64 = 0x2F100
    kernel/kstate.fi  const SIG_OFF:  u64 = 0x2F000      (Runde K9)

**Zwei Runden haben dieselbe Seite von `kdata` genommen.**

K7 las die Karte in `kstate.fi`, fand `CAP_NONCE_OFF` als letzten
Bereich und 0x30000 als damaliges `KDATA_SIZE`, nahm sich die letzte
freie Seite — und schrieb die Konstante **in `fb.fi` statt in die
Karte**. K9 las dieselbe Karte, sah 0x2F000 unbelegt (weil es dort nicht
stand) und legte die Signaltabelle dorthin.

Der Signalblock der Aufgabe 1 liegt bei
`SIG_OFF + 1 * 32 Signale * 24 Oktette = 0x2F300` und ist 768 Oktette
lang. Er wird genullt, wenn die Aufgabe entsteht — also **nachdem**
`fb.init` den Zeichensatz geladen hat. Genullt werden damit die Oktette
0x300..0x600 des Zeichensatzes, das sind die Glyphen
`(0x300/16)+0x20 = 0x40` bis `(0x600/16)+0x20-1 = 0x6F`: **`@` bis `o`**.
Der Rest des Zeichensatzes blieb stehen, deshalb waren Ziffern und
Satzzeichen noch da.

Beide Zweige waren **für sich** grün, und der Textverschmelzer konnte
nichts sehen: es überschnitt sich keine gemeinsame Zeile, nur zwei
Adressen.

**Es war nicht K9s Zeilendisziplin.** Die Vermutung, der Text laufe jetzt
durch das Terminal und dabei ändere sich Echo, Cursor oder Umbruch, war
naheliegend und falsch: `tty.emit` ruft für die Konsole `serial.put`, und
darunter hängt der Spiegel — der Bytestrom ist Oktett für Oktett
derselbe wie vorher. Der Beweis steht im Bild: die Zeichen **standen an
der richtigen Stelle**, sie waren nur leer. Ein Weg-Fehler hätte sie
verschoben, verdoppelt oder ergänzt.

**Es war auch nicht der Merge.** Die von Hand aufgelösten Kollisionen
(K_FB=7/K_TTY=8/K_SOCK=9, die zwei fehlenden Klammern in `sys.fi`) waren
richtig aufgelöst. Es war ein Fehler von **Runde K7**: die Konstante
gehörte in die Karte und stand woanders.

## 4. Was geändert wurde

**`kernel/kstate.fi`** — der Bereich steht jetzt in der Karte, und er ist
umgezogen:

    const FB_OFF: u64 = 0x3C000
    const FB_MAX: u64 = 4096

**`kernel/fb.fi`** — `FB_OFF` 0x3C000, `FONT_OFF` 0x3C100. Die Datei
führt denselben Wert ein zweites Mal, weil Firn keine Konstante eines
anderen Moduls in einen `const` einsetzt; dass die beiden gleich sind,
wird nachgerechnet statt gehofft.

**`tools/kernel/karte.py`** (neu) — rechnet **38 Bereiche aus vier
Dateien** paarweise gegeneinander, prüft, dass keiner über `KDATA_SIZE`
hinausragt, und verlangt, dass jede `_OFF`-Konstante entweder in der
Karte steht oder ausdrücklich als „kein `kdata`" erklärt ist. Ohne den
letzten Punkt schützt eine Karte nur das, woran jemand gedacht hat.
`-v` zeichnet die Belegung samt Lücken:

           ---- frei 0x36800..0x37000 (2 KiB)
      0x37000..0x3B000  TTY          kstate.fi:TTY_OFF
      0x3B000..0x3C000  RAND         kstate.fi:RAND_OFF
      0x3C000..0x3D000  FB           kstate.fi:FB_OFF
           ---- frei 0x3D000..0x40000 (12 KiB)

**`tools/gfx/schau.py`** — nennt abweichende Zellen einzeln:

    $ schau.py text pat.ppm kernel/font.fi 14 0 "OSUM X7 FRAMEBUFFEQ 01234"
    3200 Bildpunkte geprueft, 37 falsch
      2 abweichende Zellen:
        Zeile 14 Spalte 5: soll 'X' (0x58), ist 'K' -- 16 Bildpunkte falsch
        Zeile 14 Spalte 18: soll 'Q' (0x51), ist 'R' -- 21 Bildpunkte falsch

Dazu `lesen`. Beides gilt für `text`, `konsole` und `finde`.

**`tools/gfx/run.sh`** — Abschnitt 3 heißt jetzt „die Fensterplätze und
die Speicherkarte von kdata" und hat zwei neue Zusagen:

  * die Karte hat keine Kollision (38 Bereiche),
  * **die Gegenprobe zum Prüfer selbst**: in einer *Kopie* des
    Kernelverzeichnisses wird `FB_OFF` auf 0x2F000 zurückgesetzt, und der
    Prüfer **muss** anschlagen und `KOLLISION: FB` melden. Ein
    Kollisionsprüfer, der nie etwas findet, ist von einem, der nichts
    prüft, nicht zu unterscheiden.

**`kernel/tty.fi`** — nur ein Kommentar, aber er stand falsch da. K9
schrieb, `SINK_SCREEN` falle zurück, „solange K7 sich nicht eingetragen
hat". K7 ist eingetragen, und trotzdem tun `SINK_SERIAL` und
`SINK_SCREEN` dasselbe — **mit Absicht**: der Spiegel hängt *unter*
`serial.put`, nicht über der Zeilendisziplin. Ein Spiegel in `tty.emit`
sähe die Bootmeldungen vor `tty.init`, die Registerauszüge einer Ausnahme
und alles, was `serial.puts` unmittelbar schreibt, **nicht** — und genau
die will man auf einem Bildschirm sehen, denn wer einen Bildschirm
braucht, hat keine serielle Leitung. Der Schalter bleibt stehen für den
Tag, an dem der Schirm eine eigene Fläche bekommt.

**K9s Terminalschicht wurde nicht angefasst.** Kein `tty.fi`-Code, keine
Zeilendisziplin, kein Echo, kein Signalweg. Dass Terminal und Bildschirm
zusammenpassen, ist gemessen: das `write(1, ...)` der Shell läuft durch
`tty.write_out` (`sys.fi:823`) und steht bildpunktgenau im Foto.

## 5. Das Ergebnis

Alle sieben Zusagen sind grün, mit denselben Fotos, demselben Prüfer und
denselben Gegenproben:

| Zusage | vorher | nachher |
|---|---:|---:|
| Zeile 14 bildpunktgenau | 410 von 3200 falsch | **0** |
| Zeile 15 bildpunktgenau | 525 von 3200 falsch | **0** |
| ganzer Schirm gegen den Mitschnitt | 9803 von 115200 falsch | **0** (900 Zellen) |
| Text bei 1024x768 | 410 von 3200 falsch | **0** |
| ganzer Schirm gegen den Mitschnitt der Shell | 13580 von 190848 falsch | **0** (1491 Zellen) |
| Zeile der Shell | 390 von 2560 falsch | **0** |
| Schlusszeile des Skripts | 99 von 512 falsch | **0** |

`/dev/fb` aus Ring 3 unverändert 11 von 11, die vier Farbbänder
bildpunktgenau ab y=520.

## 6. Zwei Dinge, die beim Nachziehen mit auffielen

Beide standen schon auf `main`, bevor diese Runde anfing, und beide sind
Verschmelzungsreste — kein Bildcode.

**`tools/net/run.sh` meldete zwei Fehler**, und zwar `k0.o: undefined
symbols: kdata` und dasselbe für `k1.o`. Der Grund ist Runde K7: der
Bildschirmspiegel hängt unter `serial.put`, und damit `fb.fi` weder
`serial` noch `mem` einbinden muss (das wäre ein Kreis im
Abhängigkeitsgraphen), holt sich `fb.kdata()` die Adresse des
Datenbereichs über das Bindersymbol `kdata` aus `boot.s`. K7 hat dafür
`tools/kernel/run.sh` und `tools/pci/run.sh` angepasst; der Netzläufer
entstand **parallel** auf dem K8-Zweig und hat den zweiten erlaubten
Namen beim Verschmelzen nicht mitbekommen. Jetzt steht er dort, mit
Begründung.

**Der Netzabschnitt ist an einer Stelle wetterfühlig**, und das gehört
dazugesagt, weil es beim Abnehmen auffällt. `tc netem: one frame in five
thrown away` verlangt, dass alle 262 144 Oktette ankommen; unter Last der
Wirtsmaschine läuft der Fall in die Dreißig-Sekunden-Sperre von
`netsvc.connect_service` und bricht mit ~90 000 bis ~200 000 Oktetten ab.
Gemessen: auf diesem Zweig einmal grün (47 KiB/s), zweimal rot (1 und
3 KiB/s), dann wieder grün (29 KiB/s); auf `main` unter denselben
Bedingungen grün (9 KiB/s). Der Unterschied zwischen den Zweigen sind
**zwei Adressen in `fb.fi`** und zwei ungenutzte Konstanten — an den
Netzpfad rührt keine Zeile. `docs/ROUNDK8.md` nennt die Sperre selbst als
Grenze des Läufers, nicht des Stacks. Das bleibt offen und gehört K8.

**In `test.sh` hießen drei Abschnitte „12."** — K7, K9 und K8 haben sich
beim Anhängen jede dieselbe Nummer genommen, und im Kopfkommentar fehlte
der Grafikabschnitt ganz. Jetzt 1..14 in der Reihenfolge, in der sie
laufen.

## 7. Was offen bleibt

* **Die Karte ist eine Liste von Hand.** `tools/kernel/karte.py` kennt
  38 Bereiche, weil sie dort eingetragen sind. Der Vollständigkeitstest
  fängt neue `_OFF`-Konstanten ab, aber ein Bereich, der anders heißt
  (`nvme.BUF_A` heißt so), fällt nur auf, wenn ihn jemand einträgt.
  Richtig wäre, dass der Kernel seine Bereiche selbst meldet und der
  Prüfer die Meldung liest.
* **12 KiB `kdata` sind frei** (0x3D000..0x40000), dazu 8 KiB bei
  0x19000 und 12 KiB bei 0x1D000. Die nächste Runde hat Platz — und
  einen Prüfer, der schreit, wenn sie ihn zweimal vergibt.
* Alles aus Runde K7, was dort schon offenstand, steht weiter offen:
  kein Fenstersystem, kein `ioctl` für die Auflösung, der Multiboot-Weg
  ungemessen, kein Write-Combining, keine Sperre um `fb.putc`, nur
  32 bpp, Zeichensatz nur 0x20..0x7E.
