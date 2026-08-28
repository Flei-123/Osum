# Zwischenstand — Runde CERTUS

**Zweig:** `certus`, von `mergeline`. **Nicht nach `main` mergen.**
**Stand:** 28.08.2026

Der vollständige Bericht mit allen Zahlen und der Liste „kann / kann
nicht" steht in **`docs/CERTUS-STATUS.md`**. Diese Datei ist das
Protokoll: was passiert ist, in der Reihenfolge, in der es passiert ist.

---

## Die eine Zeile, um die es ging

```
osum$ certus http://10.0.2.2:34521/index.html /w/s.ppm 1
elf: start 6 entry=0x401000e8 ustack=0x4007f000 bytes=2064938 pages=505
CERTUS roots=0 body=508 font=53724 render=1 got=1 dochigh=530 vw=800 vh=560
osum$ certus -> 0

800x530  Hintergrund #ffffff  Tinte 46252 (10.91 %)  dunkel 7154  Baender 4
```

Certus lädt eine Seite über TCP, baut den Baum, kaskadiert, legt aus,
rastert die Schrift aus `/lib/sans.ttf` und malt — **als gewöhnlicher
Ring-3-Prozeß von Osum**, mit dessen Dateisystem, dessen Netz und dessen
Adressraum. Die 7154 dunklen Bildpunkte sind der Text; ein Browser, der
nur Kästen malt, hätte Tinte und keine davon.

---

## Was in den Zweig hereingeholt wurde

| Zweig | Warum |
|---|---|
| `poll` | Der Ereignisring. Certus braucht ihn heute *nicht* (er liest blockierend), aber ohne Deskriptor am Fenster dreht jede GUI-Anwendung eine Schleife mit `nanosleep` — siehe `docs/CERTUS-STATUS.md` 4.4. |
| `paint` | Alpha-Mischung und Kantenglättung. Konflikt waren nur die elf neu gemalten Netzsicht-Bilder; die Fassung aus `paint` gewinnt, weil sie mit der neuen Mischung entstanden ist. |

`hwnet` (TLS 1.3 in Ring 3, `/bin/fetch`, e1000) wurde **nicht**
hereingeholt, und das ist eine Entscheidung: **Certus bringt seine eigene
TLS-Schicht mit** (`lib/tls`, 3285 Zeilen, TLS 1.3 mit Kettenprüfung aus
Runde B5). Ein Browser, der `/bin/fetch` aufruft, um eine Seite zu holen,
gäbe die Verbindung aus der Hand — und mit ihr die Sitzungswiederverwendung,
die Umleitungen und die Fehlerbehandlung. Was er von Osum braucht, sind
**Steckdosen**, und die hat Osum seit Runde K8.

---

## Die Schritte, mit dem, was jeder gekostet hat

### 1 · Die Meßwerkzeuge (`tools/certus/`)

* `inventar.py` — zählt aus den Tabellen, die der Motor liest.
* `quoten.sh` — fährt die drei Prüfstände gegen FREMDE Sammlungen neu:
  html5lib, Web Platform Tests, test262.
* `host_render.py` — läßt Certus auf dem Wirt eine echte Seite laden,
  fotografiert das Fenster mit `xwd` **von der Serverseite** und hält es
  gegen ein echtes Chromium.
* `speicher.py` — rechnet aus einer `strace`-Aufzeichnung aus, wieviel
  Adressraum wirklich gebraucht wird.
* `pixel.py` — zählt Tinte, dunkle Punkte und Textbänder in einem PPM.
* `run.sh` — die Abnahme der Runde.

### 2 · Ein Fehler in `vendor/firn/fetch-firnc.sh`, den niemand gemerkt hatte

`cp -rL` löste die neun symbolischen Verweise in `lib/` auf. Acht davon
zeigen **innerhalb** von `lib` (`lib/std/rt.fi -> ../rt/rt.fi` und so
weiter), und weil ein Firn-Modul nach seinem *Dateinamen* heißt, waren
`lib/rt/rt.fi` und `lib/std/rt.fi` danach **zwei Module namens `rt`**.
Jedes Programm, das beide Wege im Abhängigkeitsbaum hat — also der ganze
Browser, weil `lib/paint/png.fi` den zweiten nimmt — brach mit **40
Fehlern** ab.

Jetzt `cp -a`, und danach wird genau der eine Verweis aufgelöst, der aus
`lib` herauszeigt.

### 3 · Die Bestandsaufnahme

90 155 Zeilen Browser, 116 HTML-Elemente, 67 CSS-Eigenschaften, 12
Anzeigearten, 13 Selektorformen, 122 JavaScript-Eingebaute, 66
DOM-Schnittstellen, PNG und JPEG, TLS 1.3.

Selbst nachgemessen:

| | | |
|---|---:|---:|
| HTML (html5lib, 1936 Fälle) | **1837** | **94,89 %** |
| Layout (WPT, Korpus B2, 186) | **97** | **52,15 %** |
| JavaScript (test262, Stichprobe 3493) | **2603** | **74,52 %** |

Auf dem Wirt, gegen das echte Netz: `example.com` in **0,18 s**, 103 424
Tintenpunkte, 2531 dunkle, **2 Textbänder — genau die zwei, die Chromium
findet**. Das Bild vom X-Server und die Leinwand, die der Browser selbst
herausschreibt, sind **Bildpunkt für Bildpunkt gleich**.
`en.wikipedia.org/wiki/Linux` über HTTPS in 3,67 s, 13 Bänder.

### 4 · Die Portierung — und die drei Dinge, die Osum fehlten

**Die gute Nachricht zuerst:** `strace -c` sagt, Certus benutzt
**vierzehn** Systemaufrufe, und **Osum hatte alle vierzehn**. Die
POSIX-Schicht aus Runde K4 mit den Nummern von Linux hat gereicht.

Was fehlte, war anderes:

1. **`/proc/self`** — der Sammler von Firn scannt den Stapel konservativ
   und muß das Betriebssystem nach dessen Boden fragen. `gc_init()` gab
   `false`, Certus gab **90** zurück.
2. **SSE war aus.** `guard: cr4=0x20` in jedem Startprotokoll seit Runde
   62. Jedes Programm bis hierher war Ganzzahlarithmetik; ein Browser ist
   es von vorn bis hinten nicht. `cvtsi2sd %rax,%xmm0` → `vector=6`,
   **#UD auf einem gültigen Befehl**. Jetzt `cr4=0x620`.
3. **Die `xmm`-Register müssen beim Umschalten gerettet werden.** Sonst
   rechnet ein Prozeß mit den Zahlen eines anderen — kein Absturz,
   sondern eine falsche Zahl in einem Layout. `fxsave`/`fxrstor` in
   `switch.s`, 528 Oktette unter dem Registerrahmen, und derselbe Bereich
   in `sched.frame_build` mit `mxcsr = 0x1F80`.

Und der Adressraum: gemessen braucht `example.com` **47 550 464 Oktette**
(nicht die 37 920 768, die gleichzeitig offen sind — der Zeiger geht
nicht zurück, siehe `do_unmap`). Osum gab 6 750 208. Die große Arena
wächst von **6 auf 192 MiB**; `tools/certus/run.sh` prüft nach, daß die
private Gegend `0x50000000` nicht erreicht, damit der Ablehnungsfall in
`tools/osum/run.sh` gültig bleibt.

### 5 · Das Fenster und das Bündel

`lib/certus/oswin.fi` — dieselbe Form wie `lib/browser/x11.fi`, aber über
die Aufrufe des Fensterservers. `lib/certus/certus_main.fi` — die
Anwendung; der Kopfteil ist Zeile für Zeile der von `window_main.fi` aus
Runde B5, damit der Unterschied genau dort liegt, wo er liegen muß.
`/apps/certus.osp/` — Anzeigename **Certus**, elf Schlüsselwörter, eine
Weltkugel als Symbol, `start` als zweiter Name auf `/bin/certus`.

### 6 · Das Fenster, fotografiert von der anderen Seite

```
CERTUS ... win=1 blits=1 blitpx=424000
800x600  Hintergrund #ffffff  Tinte 97752  dunkel 18108  Farben 295  Baender 8
```

424 000 Bildpunkte in **einem** `WIG_BLIT`. Und die Probe, die eine
Tintenzählung nicht ersetzen kann: auf dem Schirm der emulierten
Grafikkarte stehen **genau 24 000** Bildpunkte `#0033aa` (das ist
300 × 80) und **genau 8000** `#cc0000` (200 × 40) — die zwei Kästen, die
die Seite verlangt hat.

Dabei kam der zweite betriebsartabhängige Fehler heraus: läuft die
Oberfläche, hängt `surface()` das Dateisystem selbst ein und rief nie
`k14_setup` — also gab es im Fenster kein `/proc`, und derselbe Browser,
der auf der seriellen Konsole lief, gab dort **90** zurück.

### 7 · Regression

`tools/osum/run.sh`: **130 bestanden, 0 gefallen** — der ELF-Lader, die
Seitenrechte und der Fall „ein Programm auf `0x50000000` MUSS abgelehnt
werden" halten der 192-MiB-Arena stand.

`tools/kernel/run.sh` unter derselben Last gemessen, beide Zweige
hintereinander auf demselben Wirt (Lastmittel 15–19, weil auf dieser
Maschine parallel fremde Abnahmen laufen):

| | bestanden | gefallen |
|---|---:|---:|
| `mergeline` (Grundlinie, `6b602af`) | 163 | **13** |
| dieser Zweig | **169** | **7** |

Die sieben sind eine Teilmenge der dreizehn und alle im Abschnitt
„Scheduler" — Zählungen von Kontextwechseln in einem festen Zeitfenster,
die unter Last kippen. Sie sind in `TESTFAST-STATUS.md` als lastabhängig
vermerkt und fallen auf der Grundlinie ebenfalls. **Dieser Zweig hat
weniger rote Abschnitte als der, von dem er kommt.**

---

## Ein Unfall, der benannt gehoert: `4d8730c` auf diesem Zweig

Auf `certus` liegt ein Commit, der **nicht zu dieser Runde gehoert**:

    4d8730c MEDIA1 1/n: der AC97-Treiber, die Tonschicht und der erste
            hoerbare Sinus

Wie er hierher kam: dieses Arbeitsverzeichnis (`/root/mg-osum`) wird von
mehreren Runden GLEICHZEITIG benutzt, und ein `git add -A` der Runde
MEDIA1 hat den ausgecheckten Zweig getroffen — also diesen. Dabei hat
derselbe Commit die zu dem Zeitpunkt noch nicht eingecheckten Aenderungen
DIESER Runde an `kernel/proc.fi` und `kernel/sys.fi` (die grosse Arena)
mit eingesammelt. Beides steht seitdem in einem Commit.

Was daraus folgt, und zwar genau das und nichts anderes:

* **Der Baum ist richtig.** Alles, was oben gemessen ist, ist auf diesem
  Baum gemessen — mit dem Tontreiber darin. Er beruehrt weder
  `procfs.fi` noch `switch.s`, `boot.s`, `smp.s` noch irgendetwas unter
  `lib/certus`.
* **Die Runde MEDIA1 verliert nichts.** `kernel/ac97.fi` und
  `kernel/audio.fi` liegen inhaltsgleich (841 bzw. 771 Zeilen) auch auf
  dem Zweig `media1`, unter eigenen Commits.
* **Wer `certus` mergt, bekommt den Tontreiber ein zweites Mal.** Der
  richtige Weg ist, `media1` zuerst zu mergen; dann ist der Inhalt
  bereits da und der Merge von `certus` bringt nur noch, was er soll.

Die Historie wird hier ABSICHTLICH nicht umgeschrieben: jede Zahl in
diesem Dokument und in `docs/CERTUS-STATUS.md` ist auf genau diesem Baum
entstanden, und ein Rebase, der den Baum aendert, machte aus gemessenen
Zahlen behauptete.

---

## Was offen ist

Die vollständige Liste mit Aufwandsschätzung steht in
`docs/CERTUS-STATUS.md` 6. Die drei, die pro Aufwand am meisten bringen:

1. **Klickbare Verweise** — Treffprüfung Bildpunkt → Kasten → `<a href>`.
   Das Layout weiß schon, wo jeder Kasten steht. ½ Runde.
2. **`@media`** — ohne sie liest ein Browser bei fast jeder heutigen Seite
   das falsche Stilblatt. ½ Runde.
3. **Schriftauswahl mit Ersatzweg** — heute gibt es genau eine Schrift.
   1 Runde.

Und im Kern: **ein Deskriptor am Fenster**, damit `poll` einer Anwendung
etwas nützt.
