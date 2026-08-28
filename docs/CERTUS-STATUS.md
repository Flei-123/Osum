# Certus — was der Browser heute wirklich kann

**Stand:** 28.08.2026 · **Zweig:** `certus` (von `mergeline`) · **Wirt:**
AMD EPYC 7571, 12 Kerne, Linux x86-64, QEMU 7.2.22 mit `-accel kvm`

Dieses Dokument fasst **nicht die Doku zusammen**. Jede Zahl darin ist in
dieser Runde gemessen worden, mit einem Werkzeug, das im Repo liegt, und
wo eine Zahl aus einer **früheren** Runde übernommen ist, steht das dabei.

---

## 0. Woher Certus kommt, in einem Absatz

Certus ist Justins Browser. Er ist in den Runden **B1 bis B6** im
Firn-Baum entstanden (`vendor/firn/COMMIT` = `a751b3dbf`) und war bis zu
dieser Runde ein **Linux-Programm mit einem X11-Fenster**. Diese Runde
bringt ihn nach Osum. Sie hat den Motor **nicht angefasst** — kein
Element, keine Eigenschaft, keine Zeile Layout ist in dieser Runde
dazugekommen. Was dazugekommen ist, steht in Abschnitt 4.

| Teil | Zeilen |
|---|---:|
| `lib/js` — die JavaScript-Maschine | 28 718 |
| `lib/browser` — Baumbau, DOM-Bindung, Bilder, Fenster | 15 291 |
| `lib/css` — Zerteiler, Selektoren, Kaskade | 9 703 |
| `lib/html` — Zerteiler der Marken, Entitäten | 9 353 |
| `lib/layout` — Kastenbaum und Geometrie | 8 150 |
| `lib/net` — URL, TCP, HTTP/1.1, DNS | 6 502 |
| `lib/paint` — Leinwand, Anzeigeliste, PNG, JPEG | 4 329 |
| `lib/tls` — TLS 1.3, DER, X.509 | 3 285 |
| `lib/dom` — Knoten, API, Vorgabe-Stilblatt | 2 914 |
| `lib/font` — TrueType lesen und rastern | 1 910 |
| **zusammen** | **90 155** |

Gezählt mit `tools/certus/inventar.py vendor/firn/lib`.

---

## 1. Die drei Quoten gegen FREMDE Testsammlungen

Diese Runde hat sie **selbst nachgefahren** (`tools/certus/quoten.sh`),
mit dem festgenagelten Übersetzer aus `vendor/firn`. Nichts ist
gefiltert; ein Fall, der eine Eigenschaft braucht, die es nicht gibt,
zählt als Fehler wie jeder andere.

| | Fälle | bestanden | Quote |
|---|---:|---:|---:|
| **HTML** — html5lib-Baumbau (aus web-platform-tests) | 1936 | **1837** | **94,89 %** |
| **LAYOUT** — Web Platform Tests, Korpus B2 | 186 | **97** | **52,15 %** |
| **JS** — test262 von tc39, repräsentative Stichprobe | 3493 | **2603** | **74,52 %** |

Zum Vergleich, **aus Runde B2 übernommen und hier NICHT neu gemessen**:
ein echtes Chromium 141 schafft auf demselben Layout-Korpus 138 / 186 =
74,19 %.

Das Layout in der Breite, aus demselben Lauf:

```
b2                        97 / 186   tests   52.15 %     3975 / 4867   checks
vertical                   0 / 171   tests    0.00 %     3277 / 7984   checks
grid                       3 / 22    tests   13.64 %       59 / 151    checks
script                     6 / 92    tests    6.52 %      564 / 1874   checks
all but script           100 / 379   tests   26.39 %     7311 / 13002  checks
```

Die JavaScript-Fehler nach Ursache (Stichprobe): `throw` 872, `parse` 8,
`crash` 8, `timeout` 2. `throw` heißt fast immer: ein eingebautes Objekt,
das es nicht gibt.

---

## 2. Was der Motor an Tabellen wirklich führt

Gezählt aus den Tabellen, die der Motor beim Laufen liest — nicht aus
einer Aufzählung in einem Text.

| | Zahl |
|---|---:|
| HTML-Elementnamen mit fester Atom-Nummer | **116** |
| Attributnamen mit fester Atom-Nummer | 8 |
| Elemente im Vorgabe-Stilblatt (`lib/dom/ua.css`) | **82** |
| **CSS-Eigenschaften** (`P_COUNT` in `lib/css/cascade.fi`) | **67** |
| CSS-Anzeigearten (`display:`) | **12** |
| Selektorformen | **13** |
| Verknüpfer (Nachfahre, Kind, Geschwister) | 4 |
| Attributoperatoren (`=`, `~=`, `\|=`, `^=`, `$=`, `*=`, Existenz) | 7 |
| JavaScript-Eingebaute mit eigener Nummer | **122** + zweite Tafel |
| JavaScript-Schlüsselwörter | 38 |
| DOM-Schnittstellen für Skripte | **66** |
| Bildformate | **2** (PNG, JPEG) |

Die 12 Anzeigearten: `block`, `inline`, `inline-block`, `none`,
`list-item`, `flex`, `inline-flex`, `grid`, `table`, `table-row`,
`table-cell`, `inline-table`. (`grid` ist als *Wert* da; das Layout dazu
ist es nicht — siehe die 3/22 oben.)

Die 13 Selektorformen: Typ, `*`, `.klasse`, `#id`, `[attr]`, `:hover`,
`:first-child`, `:last-child`, `:only-child`, `:nth-child`,
`:nth-last-child`, `:not()`, `:root`.

---

## 3. KANN / KANN NICHT

Das ist die Liste, um die es geht. Sie ist so ehrlich, wie sie sein kann:
alles unter „kann" ist in dieser Runde entweder gemessen oder steht in
einer Tabelle, die der Motor liest.

### Kann

* **HTML lesen wie ein Browser.** Der ganze Baumbau der WHATWG, 94,89 %
  der offiziellen Sammlung, mit Fehlerbehebung, `<template>`, fremden
  Inhalten (SVG/MathML) und den Kuriositätsmodi.
* **CSS zerteilen und kaskadieren.** 67 Eigenschaften, 13 Selektorformen,
  Spezifität, Ursprünge (Benutzeragent / Autor / `!important`), Vererbung,
  `style=`-Attribute.
* **Fließtext mit Kastenmodell auslegen.** Blockfluss, Zeilenkästen mit
  Umbruch, Rand-Zusammenfall (auch das Durchfallen), Innenabstand, Rahmen,
  `box-sizing`, Floats, `position: relative/absolute`, ein Flex-Container
  in einer Achse, `margin-trim` (21/26 der WPT-Gruppe, wo Chromium 0 hat).
* **Malen.** Anzeigeliste, Leinwand, Farben, Hintergründe, abgerundete
  Ecken, Schatten, `opacity`, Mischmodi, Beschnitt.
* **Text rastern.** Eigener TrueType-Leser und -Rasterer, Kerning,
  Metriken. Ohne Schriftdatei bleibt es bei Kästen — und genau das
  misst diese Runde, indem sie **dunkle** Bildpunkte zählt.
* **Bilder darstellen.** PNG (mit Deflate) und Baseline-JPEG, mit der
  Größenlogik von CSS 2.1 10.3.2, den `width`/`height`-Attributen für ein
  Bild, das noch nicht da ist, und `loading="lazy"`.
* **Ins Netz gehen.** Eigener URL-Zerleger, eigener TCP-Stapel, HTTP/1.1
  mit Verbindungswiederverwendung, Umleitungen, `Content-Length` und
  Chunked, eigener Namensauflöser (DNS über UDP).
* **HTTPS.** TLS 1.3 vollständig: X25519, AES-GCM, ChaCha20-Poly1305,
  HKDF, SHA-256/384/512, RSA (PKCS#1 und PSS), ECDSA auf P-256/P-384,
  ASN.1/DER, X.509-Kettenbau gegen einen Wurzelspeicher — **mit den
  Ablehnungen**: abgelaufen, falscher Name, unbekannter Aussteller,
  Aussteller ist keine CA, gefälschte Signatur, unbekannte kritische
  Erweiterung. (Zahlen aus Runde B5 übernommen: 647/647 Bausteine mit 49
  Gegenproben, 26/26 Ketten mit 14 Ablehnungen, 18/18 Handschläge.)
* **JavaScript ausführen und die Seite damit ändern.** Ein eigener
  Zerteiler und Deuter (74,52 % test262 in der Stichprobe), an den DOM
  gebunden: `getElementById`, `querySelector(All)`, `createElement`,
  `appendChild`, `textContent`, `innerHTML`, `classList`, `style`,
  Ereignisse mit `addEventListener`, `setTimeout`, `location`. Die
  Reihenfolge der Skripte (parser-blockierend / `async` / `defer` /
  `DOMContentLoaded` / `load`) wird eingehalten, und was ein Skript
  geändert hat, wird **verengt** neu gerechnet statt alles.
* **Scrollen** (die Seite wird einmal in voller Höhe gemalt, das Fenster
  zeigt ein Band), **Verlauf** (zurück/vorwärts), **Adresszeile** — im
  X11-Fenster von Runde B5.
* **Sich gegen Fingerabdrücke wehren** (Runde B6, Kapitel Z): Leinwand
  und `navigator`-Felder werden je Herkunft und Sitzung verrauscht,
  konsistent innerhalb eines Besuchs.

### Kann nicht

* **Kein `float`/`clear` in voller Tiefe, kein Tabellenlayout.** `display:
  table` ist ein *Wert*; ein Tabellenalgorithmus (Spaltenbreiten,
  `colspan`, `border-collapse`) existiert nicht. `css/CSS2/floats`: 2/4.
* **Kein Grid.** 3 von 22 Tests, und die drei bestehen aus anderen
  Gründen.
* **Keine Grundlinienausrichtung über Kästen hinweg.**
  `css/css-flexbox/alignment`: **0 von 7**.
* **Kein `writing-mode`.** `vertical`: **0 von 171**.
* **Keine Schriftauswahl.** `font-family`, `font-weight`, `font-style`,
  `text-decoration`, `list-style` stehen **nicht** in den 67
  Eigenschaften. Fett und kursiv im Vorgabe-Stilblatt sind Attrappen: es
  gibt genau **eine** Schriftdatei und keinen Ersatzweg. Eine Seite mit
  chinesischen oder arabischen Zeichen bleibt leer, wo die eine Schrift
  keine Glyphe hat.
* **Keine Transformationen, keine Übergänge, keine Animationen.** Kein
  `transform`, kein `transition`, kein `@keyframes`, kein `filter`.
* **Keine Verläufe.** `background-image` nimmt ein Bild, keinen
  `linear-gradient()`.
* **Kein `@media`.** Ein responsives Stilblatt wird gelesen und die
  Abfragen werden nicht ausgewertet.
* **Keine Webschriften** (`@font-face`), **kein SVG-Rendering** (der
  Baumbau kennt SVG, der Maler nicht), **kein Canvas-2D-Kontext**, **kein
  WebGL**, **kein WebAudio**.
* **Kein `fetch`/XHR, keine Promises, keine Generatoren, kein `async`.**
  Damit fällt jede moderne JavaScript-Anwendung aus — und zwar bevor sie
  anfängt.
* **Kein `eval`, kein `Function`-Konstruktor, keine Module.**
* **Keine Kekse (Cookies), kein `localStorage`, keine Sitzung über zwei
  Seiten hinweg.** Ein Login ist damit unmöglich.
* **Kein `Set-Cookie`, kein `Cache-Control`, kein Zwischenspeicher.**
  Jeder Ladevorgang holt alles neu.
* **Keine Formulare, die etwas tun.** `<input>`, `<button>`, `<select>`
  werden gelesen und als Kästen ausgelegt; es gibt keine Eingabe, keinen
  Fokus, kein `submit`.
* **Keine Verweise, die man anklicken kann.** `<a href>` ist gestylt
  (`a { color: #0000ee }`) und nicht anklickbar — es gibt keine
  Treffprüfung vom Bildpunkt zum Kasten.
* **Kein Nachladen von `<img src>` im Fenster.** Bilder kommen mit dem
  Auftrag herein (Messstand B5) oder werden vom Fensterprogramm geholt;
  ein Bild, das erst nach dem Layout ankommt, löst keinen Neuaufbau aus.
* **Keine Nebenläufigkeit.** Ein Prozess, ein Faden, keine Arbeiter.
  Solange die Seite lädt, steht das Fenster.
* **Kein HTTP/2, kein HTTP/3, kein Brotli.** HTTP/1.1 und gzip.

---

## 4. Auf Osum: was diese Runde gebaut hat

### 4.1 Die Systemaufrufe, die Certus wirklich braucht

Nicht geraten — mit `strace -c` am laufenden Browser abgelesen
(`tools/certus/`):

| Aufruf | Nr | example.com | Wikipedia | in Osum? |
|---|---:|---:|---:|---|
| `mmap` (anonym) | 9 | 225 | 944 | ja |
| `munmap` | 11 | 170 | 680 | ja |
| `sendto` | 44 | 66 | 70 | ja |
| `read` | 0 | 22 | 22 | ja |
| `close` | 3 | 8 | 8 | ja |
| `open` | 2 | 6 | 6 | ja |
| `setsockopt` | 54 | 5 | 5 | ja |
| `socket` | 41 | 3 | 3 | ja |
| `connect` | 42 | 3 | 3 | ja |
| `recvfrom` | 45 | 3 | 55 | ja |
| `clock_gettime` | 228 | 3 | 175 416 | ja |
| `write` | 1 | 1 | 1 | ja |
| `getrandom` | 318 | — | 3 | ja |

**Vierzehn Aufrufe, und Osum hatte alle vierzehn.** Das ist das
überraschendste Ergebnis dieser Runde: die POSIX-Schicht der Runde K4 mit
den Nummern von Linux hat gereicht. Insbesondere braucht Certus **kein**
`poll` — er liest blockierend. `poll` (Runde POLL, Nummer 7) ist trotzdem
in diesen Zweig geholt, und warum, steht in 4.4.

### 4.2 Was gefehlt hat, und es waren drei Dinge

**(1) `/proc/self`.** Der Sammler von Firn scannt den Stapel
**konservativ** (SPEC 3.5.3) und muss dafür wissen, wo dessen Boden
liegt. Das kann er nicht selbst wissen — das Betriebssystem hat den
Stapel angelegt. Also fragt er, so wie jede Laufzeit auf jedem Unix
fragt: `/proc/self/maps`, ersatzweise `/proc/self/stat`. Osum hatte
`/proc/<pid>/maps` seit Runde K11 und **`self` nicht**, und ein Prozess
kennt seine eigene Nummer erst nach `getpid`. `gc_init()` gab `false`,
und Certus gab **90** zurück. Behoben in `kernel/procfs.fi`.

**(2) SSE war aus.** Jedes Programm, das dieses System je ausgeführt hat,
war Ganzzahlarithmetik — eine Shell, fünfundzwanzig Werkzeuge, ein
Fensterserver, ein Übersetzer. Also fiel achtzehn Runden lang niemandem
auf, dass die Maschine mit **CR0.EM gesetzt und CR4.OSFXSR leer**
hochkommt. Ein Browser ist von vorn bis hinten Gleitkomma. Certus kam bis

```
40181ebb: f2 48 0f 2a c0    cvtsi2sd %rax,%xmm0
```

und der Kern meldete `user fault: vector=6` — **#UD auf einem
vollkommen gültigen Befehl**. In jedem Startprotokoll vor dieser Runde
steht dieselbe Tatsache von der anderen Seite: `guard: cr4=0x20`.
Behoben in `kernel/arch/x86_64/boot.s` und `smp.s`; danach
`guard: cr4=0x620`.

**(3) Der Zustand der `xmm`-Register muss beim Umschalten gerettet
werden.** Sobald Ring 3 rechnen darf, gehören die sechzehn
`xmm`-Register und `mxcsr` zum Zustand einer Aufgabe wie `rbx`. Eine
Umschaltung ohne `fxsave` gäbe einem Prozess die Rechenregister eines
anderen — und das ist kein Absturz, das ist eine **falsche Zahl** in
einem Layout, die niemand je hierher zurückverfolgen würde. Behoben in
`switch.s` (528 Oktette unter dem Registerrahmen, Ausrichtung von Hand)
und in `sched.frame_build` (derselbe Bereich für eine Aufgabe, die noch
nie gelaufen ist, mit `mxcsr = 0x1F80` — alle Ausnahmen maskiert).

### 4.3 Der Adressraum: 6 MiB waren 7,6-fach zu wenig

Gemessen mit `strace -e trace=mmap,munmap` und
`tools/certus/speicher.py`:

| | mmap | munmap | gleichzeitig offen | **insgesamt abgebildet** | größte Einzelabbildung |
|---|---:|---:|---:|---:|---:|
| example.com | 226 | 171 | 37 920 768 | **47 550 464** | 6 057 984 |
| en.wikipedia.org/wiki/Linux | 944 | 679 | 88 952 832 | **114 290 688** | 6 057 984 |

Die vorletzte Spalte ist die, auf die es ankommt, und der Grund steht
über `do_unmap` in `kernel/sys.fi`: *„The pages go back, the bump pointer
does not."* Die Rahmen kommen zurück, der Zeiger nicht — ein Prozess
verbraucht so viel **Adressraum**, wie er insgesamt je abgebildet hat.

Osum gab einem Prozess 458 752 Oktette alte Halde plus 6 291 456 Oktette
große Arena = **6 750 208**. Diese Runde vergrößert die Arena auf
**192 MiB** (`proc.PRIV_SLOTS` 6 → 99, `proc.BIG_TOP` `0x40C00000` →
`0x4C600000`). Die Kacheln entstehen erst, wenn jemand sie anfasst — ein
Programm, das ein MiB braucht, merkt von der Zeile nichts. Weiter geht es
nicht: `tools/osum/run.sh` bindet ein Programm auf `0x50000000` und
verlangt, dass der Lader es ablehnt; `0x4C600000` lässt 58 MiB Luft.

### 4.4 Das Fenster

`lib/certus/oswin.fi` ist das Gegenstück zu `lib/browser/x11.fi` für
Osum: dieselbe Form (`open`, `create_window`, `put_image`, `next_event`,
`flush`, `close`), aber statt des X-Protokolls über eine Unix-Steckdose
sind es sieben Systemaufrufe des Fensterservers im Kern — `WM_CREATE`,
`WM_FILL`, `WM_TEXT`, `WM_EVENT`, `WM_INFO`, `WM_FLUSH`, `WM_CLOSE` und
`WIG_BLIT`/`WIG_SCREEN`.

Drei Grenzen, benannt statt versteckt:

* **Der Schiebepuffer ist eine Seite.** `wig.blit` kopiert Zeile für
  Zeile durch 4096 Oktette, also höchstens 1024 Bildpunkte je Zeile.
  `oswin_put_image` zerlegt selbst.
* **Es gibt keinen Deskriptor am Fenster.** `WM_EVENT` ist ein *Abholen*
  und kein Warten: ohne Ereignis kommt sofort 0 zurück. Eine Anwendung,
  die wartet, muss fragen — schlafen — fragen. **Das ist der Punkt, an
  dem `poll` einer Anwendung wirklich helfen würde**, und es ist der
  Grund, warum dieser Zweig `poll` geholt hat: es fehlt nicht `poll`, es
  fehlt **ein Deskriptor am Fenster**. Solange es keinen gibt, nützt
  Aufruf 7 einem Browser nichts.
* **Ein Fenster ist höchstens 800 × 600** (`wm.MAX_W`/`MAX_H`), und der
  Puffer wird beim Anlegen genommen und nie vergrößert.

Das Bildpunktformat ist `0x00RRGGBB` — dasselbe wie X11s BGRX in 32 Bit,
weshalb `to_bgrx` aus Runde B5 unverändert paßt.

### 4.5 Das Bündel

`/apps/certus.osp/` mit `INFO` (Anzeigename **Certus**, Beschreibung,
elf Schlüsselwörter), `symbol` (eine Weltkugel, 16 × 16, aus
`symbol.txt`) und `start` als **zweitem Namen** auf `/bin/certus` — kein
zweites Exemplar der zwei Megaoktett.

---

## 5. Die erste Seite auf Osum, gemessen

QEMU mit `-accel kvm`, `-m 512`, QEMUs Benutzernetz, ein Webserver auf
dem Wirt, `script=certus http://10.0.2.2:<port>/index.html /w/s.ppm 1`.

Was der Gast selbst meldet:

```
elf: start 6 entry=0x401000e8 ustack=0x4007f000 bytes=2064938 pages=505
CERTUS roots=0 body=222 font=53724 render=1 got=1 dochigh=530 vw=800 vh=560 win=0
osum$ certus -> 0
```

Und das Bild, das er auf **seine eigene Platte** geschrieben hat, aus dem
Abbild zurückgelesen und gezählt (`tools/certus/pixel.py`):

```
800x530  Hintergrund #ffffff  Tinte 29407 (6.94 %)  dunkel 3137  Farben 257  Baender 3
```

**3137 dunkle Bildpunkte** ist die Zahl, auf die es ankommt: das ist
Text, gerastert aus `/lib/sans.ttf`, und nicht ein farbiger Kasten. Ein
Browser, der die Kästen malt und die Buchstaben nicht, hätte Tinte und
keine dunklen Punkte — genau der Fehler, den Runde B5 mit `xwd` gefunden
hat.

Zum Vergleich derselbe Motor auf dem **Wirt**, gegen dieselben Seiten,
mit `xwd` vom X-Server aus fotografiert (`tools/certus/host_render.py`):

| | Dauer | Tinte | dunkel | Bänder | Farben | Chromium sieht |
|---|---:|---:|---:|---:|---:|---|
| `http://example.com/` | 0,18 s | 103 424 | 2 531 | 2 | 341 | 2 Textblöcke |
| `https://en.wikipedia.org/wiki/Linux` | 3,67 s | 19 484 | 3 540 | 13 | 512 | 841 Textblöcke |

Zwei Sätze dazu, und beide sind unbequem:

1. Bei `example.com` findet Certus **genau die zwei Textblöcke**, die
   Chromium findet — die Seite hat zwei. Das Bild vom **Server** und die
   Leinwand, die der Browser selbst herausgeschrieben hat, sind
   **Bildpunkt für Bildpunkt gleich**.
2. Bei Wikipedia stehen 13 Bänder gegen 841 Blöcke. Das ist kein fairer
   Vergleich (13 Bänder sind das erste Sichtfeld, 841 Blöcke das ganze
   Dokument) — aber es ist auch kein gutes Ergebnis: die Seitenleiste,
   die Infobox und die Navigation fehlen, weil Tabellen und `@media`
   fehlen.

---

## 6. Was bis „damit kann man im Alltag surfen" fehlt

Ehrlich, einzeln, mit geschätztem Aufwand. „Runde" heißt hier eine Runde
von der Größe, wie dieses Projekt sie fährt.

| # | Brocken | Warum es ohne nicht geht | Aufwand |
|---|---|---|---:|
| 1 | **Klickbare Verweise** — Treffprüfung Bildpunkt → Kasten → `<a href>` | Ohne sie ist es kein Browser, sondern ein Betrachter. Das Layout weiß schon, wo jeder Kasten steht. | **klein**, ½ Runde |
| 2 | **Schriftauswahl mit Ersatzweg** — `font-family`, `font-weight`, `font-style`, mehrere Dateien, Ersatz je Zeichen | Heute eine einzige Schrift. Jede Seite mit Fettdruck sieht falsch aus, jede nicht-lateinische Seite ist leer. | 1 Runde |
| 3 | **Tabellenlayout** — Spaltenbreiten, `colspan`/`rowspan`, `border-collapse` | Wikipedia, jede Doku, jede Preisliste. `display:table` ist heute nur ein Wort. | 1 Runde |
| 4 | **`@media`** | Ohne sie liest ein Browser bei fast jeder heutigen Seite das *falsche* Stilblatt. Klein im Code, groß in der Wirkung. | **klein**, ½ Runde |
| 5 | **Formulare** — Fokus, Eingabe, `submit`, `POST` | Ohne sie keine Suche, kein Login, kein Formular. | 1 Runde |
| 6 | **Kekse und Speicher** — `Set-Cookie`, `Cookie`, `localStorage` | Ohne sie ist jede Seite ein erster Besuch. Mit 5 zusammen der Unterschied zwischen „lesen" und „benutzen". | ½ Runde |
| 7 | **Bilder im Fenster nachladen** — `<img src>` holen, dekodieren, neu auslegen | Der Dekoder ist da (Runde VIEWER baut JPEG/PNG weiter aus — **darauf aufbauen, nicht doppelt bauen**), die *Schleife* fehlt. | ½ Runde |
| 8 | **Ein Deskriptor am Fenster** (`poll` auf Ereignisse UND Netz) | Solange `WM_EVENT` nur abholt, dreht jede Anwendung eine Schleife mit `nanosleep`. Betrifft jede GUI-Anwendung, nicht nur den Browser. | ½ Runde, im Kern |
| 9 | **Verläufe, Transformationen, Übergänge** | Ohne sie sieht jede heutige Seite *falsch* aus, auch wenn sie lesbar ist. | 1 Runde |
| 10 | **`fetch`/XHR, Promises, `async`** | Die Grenze zwischen „Dokument" und „Anwendung". Ohne sie startet keine moderne Seite. | 2 Runden |
| 11 | **HTTP-Zwischenspeicher, HTTP/2** | Ohne Zwischenspeicher ist jeder Klick ein voller Ladevorgang. | 1 Runde |
| 12 | **Speicher** — 47 MiB Adressraum für example.com | Behoben (192 MiB), aber ein `munmap`, das den Zeiger zurücknimmt, oder eine echte freie Liste wäre die richtige Antwort. Wikipedia braucht 114 MiB. | ½ Runde, im Kern |
| 13 | **Schriftrendering im Fenster** — der Kern rastert für `WM_TEXT`, der Browser für die Seite | Zwei Rasterer im selben Bild. Für die Bedienleiste geht das, für ein Textfeld nicht. | ½ Runde |

**Zusammen: rund elf bis zwölf Runden** bis zu einem Browser, mit dem man
eine Wikipedia-Seite lesen, eine Suche abschicken und einem Verweis
folgen kann. Das ist **nicht** „im Alltag surfen" — dafür fehlen danach
immer noch Nummer 10 und alles, was daran hängt.

**Die drei, die am meisten pro Aufwand bringen: 1, 4 und 2.** Klickbare
Verweise, `@media` und Schriftauswahl sind zusammen etwa zwei Runden und
machen aus einem Bild eine Sache, die man benutzt.

---

## 7. Was in dieser Runde NICHT gemacht wurde, und warum

* **Kein Chromium portiert.** Es ging nie darum. Justin hat auf die Frage
  nach einem Browser geantwortet: „Wir haben ja Certus."
* **Keine Zeile am Motor.** Wer in derselben Runde portiert und
  weiterbaut, weiß hinterher nicht, was wovon kommt.
* **Keine moderne JavaScript-Anwendung geladen.** Der Auftrag sagt es,
  und Abschnitt 3 sagt, warum es auch nichts geworden wäre.
* **Kein Wort an einem bestehenden Test entschärft.** Die einzige Zahl,
  die diese Runde in einem fremden Bereich bewegt hat, ist
  `proc.PRIV_SLOTS` — und `tools/certus/run.sh` prüft ausdrücklich nach,
  daß die private Gegend `0x50000000` nicht erreicht, damit der Fall in
  `tools/osum/run.sh` gültig bleibt.

---

## 8. Nachmessen

```sh
bash tools/certus/run.sh                       # die ganze Abnahme
bash tools/certus/quoten.sh /pfad/zu/firn      # HTML, Layout, JS
python3 tools/certus/inventar.py vendor/firn/lib
python3 tools/certus/host_render.py <certus> http://example.com/ example
python3 tools/certus/speicher.py <strace-datei>
python3 tools/certus/pixel.py <bild.ppm>
```

`tools/certus/quoten.sh` braucht einen **ausgepackten Firn-Commit mit
symbolischen Verweisen** (`git archive | tar -x`). Warum: bis zu dieser
Runde löste `vendor/firn/fetch-firnc.sh` mit `cp -rL` acht Verweise
INNERHALB von `lib` auf und machte aus `lib/rt/rt.fi` und `lib/std/rt.fi`
zwei Module namens `rt`. Jedes Programm, das beide Wege im
Abhängigkeitsbaum hat — also **der ganze Browser**, weil
`lib/paint/png.fi` den zweiten nimmt —, brach mit vierzig Fehlern ab.
Das ist in dieser Runde behoben (`cp -a` plus das Auflösen des einen
Verweises, der aus `lib` herauszeigt); die Bilder unter
`docs/shots/certus/` sind mit der reparierten Fassung entstanden.
