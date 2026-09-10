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

---

## ETAPPE C — DER SOFTWARE-RASTERER

`kernel/r3dsoft.fi`: Dreiecksrasterung mit Kantenfunktionen,
Tiefenpuffer (acht Oktette je Bildpunkt), flache Beleuchtung,
Texturen mit Zweierpotenzmassen. `kernel/r3dtest.fi` baut daraus einen
texturierten Wuerfel und misst ihn.

### Die Zahlen

Gemessen unter **KVM** (TCG waere wertlos), 60 Bilder je Lauf, Stufe 0:

| Aufloesung | ns je Bild | Bilder je Sekunde | loeschen | rastern |
|---|---|---|---|---|
| 1280x720 | 21 269 964 | **4,70** | 13,6 ms | 7,5 ms |
| 2560x1440 | 84 751 700 | **1,17** | 54,2 ms | 30,5 ms |

Faktor 4,0 bei vierfacher Bildpunktzahl — der Rasterer skaliert linear,
wie er soll.

**DIE INTERESSANTESTE ZAHL IST NICHT DIE BILDRATE, SONDERN DAS
VERHAELTNIS: das Loeschen kostet MEHR als das Zeichnen** (bei 1440p 54
gegen 30 Millisekunden). Der Wuerfel bedeckt sechs Prozent des Bildes;
geloescht wird immer die ganze Flaeche, Farbe UND Tiefe. Wer diese Zahl
verbessern will, faengt beim Loeschen an und nicht beim Rasterer.

### Warum es so langsam ist, und was das NICHT ist

Es liegt **nicht** am Algorithmus und **nicht** am Speicher. Gemessen:

* Eine reine Schreibschleife in Osum kostet **1,32 ms je MiB** (rund 5 ns
  je Zugriff). Dieselbe Schleife mit `volatile` auf dem Wirt: 3,10 ns.
  Osum ist also nur Faktor 1,6 von einer `volatile`-Schleife entfernt.
* Aber eine Schleife, die der Uebersetzer optimieren DARF, kostet auf
  demselben Wirt **0,10 ns** je Zugriff. Der Abstand zu Osum ist Faktor
  **50**.

Der Grund steht im erzeugten Assembler und ist nachgezaehlt mit
`firnc --emit=asm --opt-level=release-fast`:

1. **Firn inlinet nicht.** Jedes `fx_mul` ist ein echtes `call`. In der
   inneren Schleife standen sechzehn davon plus `farbe_an` mit bis zu
   zwoelf weiteren. Von Hand ausgeschrieben brachte das 0,45 -> 0,77
   Bilder je Sekunde (Faktor 1,7).
2. **Firn haelt keine Werte in Registern.** Auch bei `release-fast`
   wird jedes Zwischenergebnis auf den Stapel geschrieben und wieder
   gelesen; ein `x = x + 1` sind mehrere Speicherzugriffe. Ein
   Versuchsbau mit `--opt-level=release-fast` fuer den ganzen Kern war
   30 Prozent kleiner und **gleich schnell** (0,74 gegen 0,77) — die
   Optimierungsstufe aendert daran nichts.

Zum Vergleich derselbe Kern, mit dem selbstgehosteten Uebersetzer
gebaut: **2,00 statt 4,70 Bilder je Sekunde** — firnc1 erzeugt noch
einmal deutlich langsameren Code als firnc0.

**Das heisst:** Die Bildrate misst hier zu einem grossen Teil den
UEBERSETZER, nicht den Rasterer. Ein Faktor 10 bis 50 laege in
Registerhaltung und Inlining, ohne eine Zeile am Algorithmus zu aendern.
Das ist eine Aussage ueber Firn und gehoert in eine Firn-Runde.

### Fuenf Fehler, die die Messung gefunden hat

Alle fuenf haetten ein Bild erzeugt, das plausibel aussieht:

1. **0x3D000 war schon vergeben** — dort liegt der Fensterserver aus
   Runde K10/K11. Rasterer und Fensterserver haben sich gegenseitig den
   Zustand ueberschrieben: `gemalt` zaehlte 111 Millionen Bildpunkte,
   der Schirm blieb schwarz. Das ist derselbe Fehler, den `kstate.fi`
   VIERMAL als Kommentar traegt und fuer den `tools/kernel/memmap.py`
   gebaut wurde — und die Karte meldete null Kollisionen, **weil der
   neue Bereich bei ihr nicht eingetragen war**. Ein Pruefer prueft nur,
   was er kennt. Jetzt steht der Bereich dort, liegt auf 0xAC000, und
   die Karte rechnet 92 Bereiche.
2. **`dreh_y` hatte die Sinusvorzeichen vertauscht** (Zeilen- gegen
   Spaltenvektor-Ordnung). Einem sich drehenden Wuerfel sieht man das
   nicht an — er dreht ja. Gefunden von Zusage 10 des Selbsttests:
   eine Vierteldrehung um Y bringt (1,0,0) nach (0,0,-1), gemessen
   wurde +1.
3. **Die baryzentrischen Gewichte kamen aus einem Kehrwert in 16.16.**
   Bei einem bildschirmfuellenden Dreieck wird der zu null, alle drei
   Gewichte kollabieren, und jeder Bildpunkt tastet denselben Texel ab.
   Auf dem Foto: eine graue Flaeche in der Farbe der Gitterlinie.
   Aufgefallen an der Farbzaehlung ("vier Farben"), nicht am Eindruck.
4. **Die Flaechennormale wurde im Modellraum gerechnet**, das Licht
   steht im Weltraum. Die Beleuchtung war damit von der Drehung des
   Wuerfels unabhaengig.
5. **Die Projektionsmatrix wurde nie gesetzt** und blieb die
   Einheitsmatrix: gar keine Perspektive, der Wuerfel fuellte 97,7
   Prozent des Bildes. Gemessen am umschliessenden Kasten.

### Die Zeitmessung misst sich selbst ihren Massstab

`time.calibrate` laeuft in `kernel_main` dreihundert Zeilen SPAETER als
diese Runde. Vorher ist `TIME_KHZ` null und `mono_ns` faellt auf den
Markenzaehler zurueck — der zaehlt in Zehn-Millisekunden-Schritten und
meldete bei sechzig Bildern glatte **null** Nanosekunden je Bild. Eine
Messung von exakt null waere niemandem aufgefallen, der die Zahl nicht
angesehen haette.

Jetzt kalibriert `r3dtest` selbst, ueber **Kanal 2 des Zeitgebers**:
der laeuft einmal herunter und hebt eine Leitung, die man an Tor 0x61
LESEN kann — der einzige Zeitgeber, der ohne Unterbrechungen geht.

### Der Nachweis

`docs/grafik/wuerfel-1280x720.png` und `-2560x1440.png`, aufgenommen mit
dem Wort `r3dhold` (ohne das haelt der Kern nicht an, und der
Fensterserver malt ueber den Wuerfel — das erste Foto war deshalb
schwarz). Maschinell nachgerechnet statt begutachtet:

* **Zeilenprofil** eines gedrehten Wuerfels: oben 12 Bildpunkte breit,
  in der Mitte 272, unten 76 — ein Koerper, keine Flaeche.
* **Drei Helligkeitspaare** derselben Texturfarbe (#3a3a3a/#575757 hell,
  #081220/#0c1b30 blau): drei sichtbare Flaechen, verschieden zum Licht.
* **Kastenmitte** bei x=639 gegen Bildmitte 640.
* Bei 1440p derselbe Wuerfel doppelt so gross (554x539 gegen 276x269) —
  die Projektion rechnet mit dem Seitenverhaeltnis und nicht mit
  festen Zahlen.

---

## ETAPPE D — WAS ECHTE BESCHLEUNIGUNG KOSTEN WUERDE

### Die Ausgangslage auf dieser Maschine

Der Pruefstand hat einen Bochs-VBE-Aufsatz (`1234:1111`) — eine
Karte, die es als Silizium nicht gibt. **Fuer Justins echten Rechner
fehlt die Erhebung noch**; genau dafuer ist Etappe A gebaut. Der Satz
`osum gfx grafik hwdiagstop` auf dem Stick liefert die Zeilen, und erst
danach ist die folgende Bewertung auf SEINE Hardware anwendbar.

### Die drei Hersteller, ehrlich bewertet

| | Intel | AMD | NVIDIA |
|---|---|---|---|
| Display-Register offen dokumentiert | **ja, vollstaendig (PRM)** | nur bis DCE11 (Hardware bis 2017) | nein |
| Befehlssatz offen dokumentiert | ja | **ja, sehr gut** | nein (rueckentwickelt) |
| Modus setzen ohne Firmware-Blob | **ja** (bis etwa Alder Lake) | nein (DMCUB, SMU, PSP noetig) | nein (GSP noetig) |
| Modus setzen, Hobby, realistisch | **3–9 Monate** | 6–12 Mon. (alt) / 2–4 Jahre (DCN) | 2–4+ Jahre |

**Intel ist der einzige Hersteller, bei dem man aus VEROEFFENTLICHTER
Dokumentation einen eigenen Treiber schreiben kann.** Die Programmer's
Reference Manuals sind frei als PDF, das Display-Band enthaelt die
Schritt-fuer-Schritt-Reihenfolgen zum Modussetzen. Bei AMD portiert man
AMDs Code (`amd/display/dc`, ueber 400 000 Zeilen), bei NVIDIA portiert
man Nouveaus Code — in beiden Faellen schreibt man keinen eigenen
Treiber, man uebernimmt einen fremden.

Was in den Intel-PRMs NICHT steht und Wochen kostet: das VBT-Format
(welcher Anschluss an welchem Port, Panel-Spannungssequenzen) ist
nirgends offiziell dokumentiert und muss aus dem Linux-i915 gelesen
werden; dazu die PCODE-Mailbox und die Errata.

### Der kleinste sinnvolle erste Schritt — und er ist NICHT Modus-Setzung

Modus-Setzung ist der TEUERSTE Teil, nicht der billigste. Die
vernuenftige Reihenfolge:

**Stufe 0 — den vorhandenen Modus UEBERNEHMEN (4–8 Wochen).**
Die Firmware hat den Modus schon gesetzt. Man muss ihn nicht neu setzen,
sondern nur auslesen und weiterbenutzen:
BAR0 abbilden, Forcewake richtig behandeln (sonst liest man aus allen
Registern nur Nullen), GGTT aufsetzen, `PIPE_SRCSZ`/`PLANE_STRIDE`
auslesen, einen eigenen Puffer in die GGTT haengen und `PLANE_SURF`
darauf umbiegen.
**Ergebnis: echtes Doppelpuffern, VBlank-Unterbrechung, Umschalten ohne
Reissen.** Das ist der beste Nutzen je Woche im ganzen Vorhaben — und
fuer Osum sofort brauchbar, weil `fb.fi` bereits einen Zweitpuffer hat
und nur einen besseren Weg hinaus braucht.

**Stufe 1 — EDID ueber GMBUS/AUX (1–2 Wochen).** Dann weiss der Kern,
was der Bildschirm wirklich kann, statt es zu raten.

**Stufe 2 — echte Modus-Setzung (2–4 Monate, eine Generation, EIN
Ausgang).** Power Wells, CDCLK, PLL, Transcoder, Watermarks,
DP-Link-Training. Die Watermarks sind der Punkt, an dem es still
schiefgeht: falsch gerechnet gibt es keinen Fehler, sondern ein
flackerndes oder schwarzes Bild.

**Stufe 3 — beschleunigtes Kopieren (Blitter, +1,5–2 Monate).** Und
hier die unbequeme Wahrheit: **das Kosten-Nutzen-Verhaeltnis ist
schlecht.** Seit Gen8 gibt es keine einfachen Ringpuffer mehr; man
braucht Execlists, Logical Ring Contexts, PPGTT und
Absturz-Wiederherstellung, BEVOR das erste `XY_SRC_COPY_BLT` laeuft.
Die 80-Prozent-Loesung ist billiger: im Arbeitsspeicher zeichnen und mit
breiten Kopierbefehlen hinausschieben — was Osum heute schon tut.

### Vergleichszahlen, die niemand gern hoert

* **Haiku** arbeitet seit etwa 2006 an `intel_extreme`. Stand 2024/2025
  ist modernes Intel-Modus-Setzen **immer noch nicht durchgaengig
  zuverlaessig**. Mehrere Entwickler, zwanzig Jahre.
* **SerenityOS** hat einen nativen Intel-Treiber — fuer `8086:29c2`,
  einen Chipsatz von 2006, mit fest verdrahteten Modi. Ein sehr aktives
  Projekt kam nie ueber die Generationen vor den DDIs hinaus.
* **FreeBSD, NetBSD und OpenBSD** schreiben **keinen** eigenen
  Intel-Display-Treiber. Alle drei portieren `drm/i915` aus Linux. Wenn
  drei gepflegte Unix-Systeme mit bezahlten Entwicklern das nicht selbst
  schreiben, ist das ein deutliches Signal.
* **Linux i915**, nur der Display-Teil: weit ueber 100 000 Zeilen C, von
  einem bezahlten Intel-Team mit internen Spezifikationen.

### Und Minecraft?

Die Einschaetzung im Auftrag war richtig. Getrennt:

**Minecraft Java als CLIENT: nein.** Gebraucht werden Java 21 (der
Bytecode nutzt Records, Sealed Classes, VarHandles — alte freie JVMs wie
JamVM oder CACAO stehen auf Java 6/7 und sind tot), dazu LWJGL, GLFW,
OpenAL und **OpenGL 3.2 Core Profile**. Der Blocker ist nicht Java,
sondern OpenGL:

* mit echtem GPU-Treiber (DRM/KMS-Nachbau plus Mesa): **3–10
  Personenjahre** fuer EINE GPU-Familie;
* mit Mesa llvmpipe in Software: LLVM portieren (2–6 Personenmonate) und
  dann **1–10 Bilder je Sekunde** bei 720p — technisch "laeuft",
  praktisch eine Diaschau;
* eigenes GL 3.2 schreiben: 2–5 Personenjahre.

Gesamt: **2,5–5 Personenjahre fuer eine unspielbare Diaschau**, 6–15
fuer etwas, das man Spielen nennen darf.

**Minecraft SERVER: ja, das ist ein erreichbares Ziel.** Der Server
braucht keine Grafik, kein GLFW, kein OpenGL — nur Netz, Dateisystem,
Faeden und Zeit. Osum hat davon schon vieles: TCP/IP, ein Dateisystem,
mehrere Prozessoren, POSIX-Aufrufe mit den Nummern von Linux.

Und der billigste Weg zur JVM ist **kein Port, sondern die
Linux-Aufruf-Schnittstelle nachzubilden** und das unveraenderte
OpenJDK-Linux-Abbild laufen zu lassen (6–18 Personenmonate) statt
OpenJDK eine vierte Betriebssystemfamilie beizubringen (18–36).

**Der pragmatischste Weg ueberhaupt** braucht gar kein Java: ein
eigener Server, der das 1.21-Protokoll so weit spricht, dass ein echter
Vanilla-Client sich verbindet, in einer Flachwelt spawnt, laeuft,
Bloecke setzt und chattet — **3000 bis 8000 Zeilen, 2 bis 6 Wochen**,
Protokoll vollstaendig dokumentiert. Alternativ Cuberite portieren
(C++, 1.12-Spielstand, 2–6 Wochen) oder Pumpkin (Rust, 1.21, 1–4
Monate).

**Die Rangfolge nach Aufwand und Nutzen:**

| # | Ziel | Aufwand |
|---|---|---|
| 1 | eigener minimaler 1.21-Server in Firn/C | 2–6 Wochen |
| 2 | Cuberite portieren | 2–6 Wochen |
| 3 | Pumpkin portieren (Rust-Ziel noetig) | 1–4 Monate |
| 4 | Vanilla-Server ueber Linux-Aufruf-Nachbildung | 6–18 Monate |
| 5 | Client mit llvmpipe (1–10 Bilder/s) | +6–12 Monate |
| 6 | Client mit echter Beschleunigung | +3–10 Jahre |

---

## WAS DIESE RUNDE NICHT GETAN HAT

Damit niemand mehr hineinliest, als dasteht:

* **Kein Grafikkartentreiber.** Kein einziges Register einer echten GPU
  wurde geschrieben. Die Erhebung liest, sie fasst nichts an.
* **Kein OpenGL, kein Vulkan, keine Schattierungsprogramme.**
* **Keine Beschleunigung.** Der Rasterer laeuft auf dem Hauptprozessor,
  und 4,7 Bilder je Sekunde bei 720p sind kein Spiel, sondern ein
  Nachweis, dass die Schicht traegt.
* **Kein Beschneiden an der Nahebene.** Dreiecke, die die Kamera
  schneiden, fallen ganz weg. Fuer den Wuerfel reicht das; fuer eine
  Szene, in der man hindurchlaeuft, nicht.
* **Keine Perspektivkorrektur der Texturkoordinaten.** Bei kleinen,
  flachen Flaechen unsichtbar, bei einem langen Boden sehr wohl.
* **Nichts davon laeuft in Ring 3.** `r3d.fi` ist heute eine
  Kernel-Schnittstelle. Die Systemaufrufe dafuer sind eine eigene Runde.

## NAECHSTER SCHRITT

Der eine Satz, der jetzt zaehlt: **`osum gfx grafik hwdiagstop` auf
Justins echtem Rechner**, ein Foto der Diagnosetafel. Daraus wird
ablesbar, welche Grafikeinheit wirklich darin steckt — und die Zeile
`weg tafel=... bild=... gezogen=JA/NEIN` entscheidet nebenbei die Frage
nach den eckigen Ecken.
