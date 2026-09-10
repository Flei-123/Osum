# RUNDE GRAFIK-1 — das Fundament fuer echte Grafikbeschleunigung

Zweig `grafik`, Arbeitsbaum `/root/osum-grafik`, ausgehend von `main`
(bc23cc7). Diese Runde baut KEINEN Grafikkartentreiber. Sie klaert, was
auf Justins echter Hardware ueberhaupt moeglich ist, entwirft die
Schicht, hinter der ein solcher Treiber spaeter stecken kann, und baut
das erste Backend dahinter — in Software, damit es etwas gibt, das
messbar ist.

---

## ETAPPE A — DIE ERHEBUNG

### Was Osum vor dieser Runde ueber seine Grafik wusste

Eine Zeile in `hwdiag.fi`:

    hwdiag: fb 1280x800  bpp=32  pitch=5120  src=vbe  phys=0xfd000000  cols/rows=160/50

Und in der PCI-Liste eine Zeile mit Klasse `03`. Das ist alles. Keine
Adressbereiche, kein Hersteller im Klartext, nichts darueber, was
zwischen dem gezeichneten Bild und der Tafel liegt. Fuer eine
Treiberplanung reicht das nicht: ein Treiber besteht in seinem Kern
daraus, in Register zu schreiben, und wo die Register liegen, steht in
den BARs — die niemand ausgelesen hat.

### Was `kernel/grafik.fi` jetzt sagt

    grafik: -------------------- OSUM GRAFIK-ERHEBUNG --------------------
    grafik: gpu anzahl=1
    grafik: gpu bdf=00:02.0  id=1234:1111  herst=QEMU/Bochs-VBE  klasse=03:00:00  rev=02
    grafik: gpu bar0=0xfd000000  gross=16 MiB  (speich, 32, vorlad)
    grafik: gpu bar2=0xfebf0000  gross=4 KiB  (speich, 32)
    grafik: quelle vbe (der Kern hat den Modus selbst gesetzt)  phys=0xfd000000  oktette=4096000  bpp=32
    grafik: weg tafel=1280x800  bild=1280x800  gezogen=NEIN  pitch=5120/5120
    grafik: puffer zweit=ja  streifen=nein  uncached=nein  uiskala=1  presents=0
    grafik: bildspeicher in bar0 der gpu
    grafik: stand treiber=KEINER  3d=KEINES  opengl=NEIN  vulkan=NEIN
    grafik: stand alles wird vom hauptprozessor gezeichnet (fb.fi)
    grafik: -------------------- ENDE DER ERHEBUNG -----------------------

Aufgerufen mit dem Wort `grafik` auf der Kommandozeile, direkt hinter
`hwdiag.stage` und damit **bevor irgendein Treiber hochgezogen wird**.
Ohne das Wort ist es ein Zeichenkettenvergleich und sonst nichts.

**Es fasst nichts an.** Kein Register wird geschrieben, kein Modus
gesetzt, keine Uebernahme versucht. Ein Bericht, der etwas veraendert,
beschreibt nicht mehr den Zustand, den er beschreiben soll.

### Die Gegenproben, ohne die der Bericht nichts beweisen wuerde

Ein Bericht, der seine Zahlen aus einer Tabelle im Kernel naehme, saehe
genauso aus. Also wurde gegen **verschiedene** Hardware gemessen:

| Aufbau | Ergebnis |
|---|---|
| Standard (Bochs-VBE) | `1234:1111`, bar0 16 MiB bei `0xfd000000` |
| `-vga vmware` | `15ad:0405`, bar0 **16 Oktett (tor)**, bar1 16 MiB |
| `-device secondary-vga` | `anzahl=2`, `03:00` vor `03:80`, fb in bar0 der **richtigen** |
| ohne das Wort `gfx` | gpu-Zeilen stehen, Bildspeicher `KEINE` |
| `--gui off` | baut, laeuft, PCI-Haelfte vollstaendig |

Die VMware-Zeile ist der Beleg, dass wirklich der Konfigurationsraum
gelesen wird: eine andere Karte hat eine andere BAR-Aufteilung, und
genau die steht da. Die Zeile mit zwei Karten ist der Fall eines
Notebooks mit umschaltbarer Grafik — `03:00` (die VGA, an der der
Bildschirm haengt) wird `03:80`/`03:02` (dem reinen 3D-Regler)
vorgezogen, und die Zuordnung des Bildspeichers trifft die richtige.

### Was der Kernel heute ueber den Bildschirm weiss

Alles aus `fb.fi`, nachgelesen und nicht behauptet:

* **Aufloesung** `S_WIDTH`/`S_HEIGHT`, **Farbtiefe** `S_BPP` (32 gefordert;
  ein anderer Wert laesst `init` scheitern), **Schrittweite** `S_PITCH`
  in Oktetten je Bildzeile.
* **Herkunft** — zwei Wege, und nach `init` sieht der Rest des Kernels
  nicht mehr, welcher gegangen wurde:
  1. `SRC_MB` — vom Lader durch Multiboot 1, Flag-Bit 12. Das ist der
     Weg unter Limine, BIOS wie UEFI, und **der einzige, der auf echter
     Hardware traegt**. Unter UEFI ist das mittelbar GOP: der Lader
     fragt GOP und reicht die Zahlen weiter.
  2. `SRC_VBE` — der Kern setzt den Modus selbst, ueber die zwei
     Kurzworttore des Bochs-VBE-Aufsatzes (`0x1CE`/`0x1CF`), Adresse aus
     BAR0. Das ist der Weg unter `qemu -kernel`, weil QEMU keinen
     Multiboot-Videoteil mitgibt (`mb: flags=0x24f`, Bit 12 fehlt).
* **Zweitpuffer** im Arbeitsspeicher, **Streifenbetrieb** wenn der Puffer
  nicht am Stueck in die acht 2-MiB-Fensterplaetze passt,
  **Zwischenspeicher** an/aus.

### Und die eckigen Ecken?

Der Verdaechtige steht in `fb.fi` und heisst `present`. Seit Runde
DISPLAY sind **die Tafel** (`S_PWIDTH`/`S_PHEIGHT` — was die Karte
ausgibt) und **das Bild** (`S_WIDTH`/`S_HEIGHT` — worauf gezeichnet
wird) zwei verschiedene Dinge:

* Sind sie gleich, ist `flush` ein `rep movsq` und jeder Bildpunkt
  kommt unveraendert an.
* Fallen sie auseinander, laeuft `present` — und `present` zieht das
  Bild mit einer Festkommaschrittweite auf die Tafel, Bildpunkt fuer
  Bildpunkt, **mit naechstem Nachbarn und ohne zu mitteln**.

Eine runde Fensterecke ist bei den ueblichen Radien drei bis acht
Bildpunkte gross. Wird ein solches Bild um einen krummen Faktor
gezogen, fallen genau die wenigen Punkte weg, die die Rundung
ausmachen — uebrig bleibt eine Ecke, die eckig **aussieht**, obwohl sie
rund **gezeichnet** wurde. Der Pruefstand sieht das nie, weil dort Tafel
und Bild immer gleich gross sind.

**Das ist eine Hypothese, keine Feststellung.** Die Zeile

    grafik: weg tafel=... bild=... gezogen=JA/NEIN  pitch=.../...

entscheidet sie auf Justins Rechner in einer Sekunde. `gezogen=JA` →
Ursache gefunden. `gezogen=NEIN` → dieser Verdaechtige ist
**ausgeschlossen**, und die Suche muss woanders weitergehen; auch das
spart Arbeit. Die Zeile `presents=` sagt zusaetzlich, ob der lange Weg
im Betrieb ueberhaupt je gegangen wurde.

---

## ETAPPE B — DIE GRAFIKSCHNITTSTELLE

### Die Frage, die zuerst beantwortet werden musste

Darf im Kernel mit Gleitkomma gerechnet werden? Das entscheidet, ob 3D
ueberhaupt in den Kernel gehoert. Die Antwort kommt nicht aus einer
Meinung, sondern aus dem Uebersetzer:

    $ firnc -c --target=x86_64-none /tmp/fptest.fi
    error: floating point (the type f64) is allowed in profile 'kernel'
           only with #[allow_fp] — 'probe' does not have the attribute
      = note: SPEC §2: in the kernel the FPU/SSE registers belong to the
              interrupted thread; whoever touches them must save their
              state himself

Es gibt also eine Tuer (`#[allow_fp]`), aber sie hat einen Preis: wer
sie benutzt, muss den Vektorzustand selbst sichern. In einer Schleife,
die je Bildpunkt laeuft, ist das nicht bezahlbar. **Also Festkomma** —
dieselbe Entscheidung, die `ttf.fi` und `vektor.fi` schon getroffen
haben.

### Traegt Festkomma fuer 3D? Gemessen, nicht geschaetzt

Die ganze Kette (Modell → Drehung um zwei Achsen → Verschiebung →
Projektion → Bildschirmkoordinaten), 2880 projizierte Eckpunkte, gegen
`float64` als Wahrheit:

| Aufbau | groesster Fehler | mittlerer Fehler |
|---|---|---|
| 16.16, Sinustabelle 1024 | **0,013 Bildpunkte** | 0,006 |
| 16.16, Tabelle 4096 | 0,014 | 0,006 |
| 20.12-Schiebung, Tabelle 4096 | 0,0009 | 0,0004 |

Ein Hundertstel Bildpunkt. Die groessere Tabelle bringt nichts, die
groessere Schiebung braucht niemand. **16.16 mit 1024 Eintraegen
genuegt** — und das ist gemessen und nicht gehofft.

(Ein erster Lauf meldete 3,5 Bildpunkte Fehler. Das war ein Fehler in
der Messung selbst: verglichen wurde eine gerundete Ganzzahl gegen einen
ungerundeten Gleitkommawert, und der Unterschied war die Rundung und
nicht die Rechnung. Steht hier, weil eine Messung, die man einmal falsch
gemacht hat, beim naechsten Mal wieder falsch gemacht wird, wenn niemand
sie aufschreibt.)

### Der Entwurf

Nach demselben Muster wie `gfx.fi`/`gfx-aus.fi`: **Programme reden nie
direkt mit der Hardware, sondern mit dieser Schicht.**

    Anwendung  (Ring 3)
        |
        |  Systemaufrufe
        v
    kernel/r3d.fi        DIE SCHNITTSTELLE  <-- hier steht, WAS geht
        |
        +---> r3d-soft.fi    Software-Rasterer   (diese Runde)
        +---> r3d-<gpu>.fi   ein echter Treiber  (spaeter, wenn ueberhaupt)

Warum eine eigene Schicht und nicht "einfach OpenGL nachbauen": OpenGL
ist eine Zustandsmaschine mit tausend Aufrufen, und ein Nachbau, der
neunzig davon kann, ist kein OpenGL, sondern eine Luege mit einem
bekannten Namen. Diese Schnittstelle ist klein und heisst nicht so wie
etwas, das sie nicht ist.

**Die Zusagen der Schicht** (das, worauf sich ein Programm verlassen
darf, ganz gleich welches Backend darunter steckt):

| Aufruf | Bedeutung |
|---|---|
| `start(ziel, w, h)` | eine Bildflaeche mit Tiefenpuffer aufmachen |
| `clear(farbe, tiefe)` | Farbe und Tiefe zuruecksetzen |
| `matrix(art, m)` | Modell/Ansicht/Projektion setzen, 16.16 |
| `licht(richtung, staerke)` | eine Richtungsquelle |
| `textur(daten, w, h)` | eine Textur binden |
| `dreiecke(punkte, n)` | zeichnen |
| `ende()` | fertig, Bild steht im Ziel |

Alle Zahlen 16.16-Festkomma. Kein Gleitkomma an der Grenze — sonst
muesste die Grenze selbst SSE anfassen.

**Was ausdruecklich NICHT drin ist:** Schattierungsprogramme (Shader),
Mehrfachziele, Verbundoperationen (Blending) ausser dem Tiefentest,
Nebel. Wer das braucht, braucht eine GPU, und dann ist diese
Schnittstelle die falsche Stelle zum Nachruesten.

---

## ETAPPE C, D

*(In Arbeit — Messzahlen und Aufwandsschaetzung folgen in dieser Datei.)*
