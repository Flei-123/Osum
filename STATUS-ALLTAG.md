# STATUS — RUNDE ALLTAG

Zweig `alltag` (Arbeitsbaum `/root/osum-alltag`, Basis `merge6`). **Nicht gepusht, nicht gemergt.**

Abnahme: `bash tools/alltag/run.sh [ordner]` — zehn Abschnitte, jeder mit Gegenprobe.
Mit `ALLTAG_THEMESTORE=1` läuft `tools/themestore/run.sh` am Ende mit.

Sechs kleine Programme, die am ersten Tag fehlen, je als eigenes signiertes `.opk`
im Ladenkatalog: **Sperrbildschirm, Papierkorb, Ausschnittwerkzeug, Bildbetrachter,
ZIP, Taschenrechner.** Jede Oberfläche besteht ausschließlich aus `wlib` — was
fehlte (Bildfläche mit Zoom, Schieberegler, nachträgliche Größe, das Vierer-Raster),
wurde **ins Framework** gebaut und wird von allen benutzt.

## Was der Auftrag verlangte und wo es steht

| Auftrag | Wo | Zustand |
|---|---|---|
| Sperrbildschirm: Leerlauf, Win+L, exklusive Eingabe, Kennwort, sicherer Ausfall | `kernel/user/lock.fi`, `kernel/wm.fi`, `kernel/kstate.fi`, `kernel/sys.fi` (SYS 1850), `kernel/kbd.fi` | grün |
| Papierkorb je Datenträger, Originalpfad + Zeit, Zurück, Leeren, Grenze | `kernel/user/trash.fi`, `papierkorb.fi`, `/etc/papierkorb.conf` | grün, Rückholung byte-gleich |
| Explorer: Entf → Korb, Umschalt+Entf endgültig | `kernel/user/explorer.fi` | grün, beides gemessen |
| Ausschnittwerkzeug: Ausschnitt/Fenster/Vollbild, Verzögerung, PNG + Übergabe | `kernel/user/snip.fi`, `bild.png_datei`, `flate.strom_*` | grün, 99,8 % Bildpunkte wie QEMUs eigenes Foto |
| Bildbetrachter: PNG/JPEG/BMP, Zoom, Drehen, Blättern, Miniaturen | `kernel/user/viewer.fi`, `bild.fi`, `jpeg.fi` | grün, 6 Bilder exakt wie Pillow |
| ZIP packen/entpacken, Kontextmenü im Explorer | `kernel/user/zip.fi` (Deflate aus `flate.fi`) | grün, beide Richtungen gegen Python |
| Taschenrechner: Grund, Prozent, wissenschaftlich, Einheiten, Tastatur | `kernel/user/calc.fi` | grün, 40 Ausdrücke = Python |
| Alles aus dem Laden installierbar | `tools/laden/apps.tab` + sechs gezeichnete Symbole | grün, 6 signierte Pakete eingespielt |
| Jede Oberfläche nur über wlib | `tools/alltag/run.sh` Abschnitt 10 | **0** direkte Zeichenaufrufe |
| Vierer-Raster ≥ 92 % | `tools/design/messen.py`, je Programm geprüft | **100 %** bei allen fünf Fenstern |

## Das Vierer-Raster steht jetzt in der Bibliothek, nicht in den Programmen

Vor dieser Änderung kam jede Länge aus einer Textbreite (Knopf 78, 90, 112) oder aus
der Schrifthöhe (18) — Zahlen, die kein Raster kennen. Gemessen: Rechner 67 %,
Papierkorb 83 %, Sperrbildschirm 43 %.

`wlib` rundet seit dieser Runde selbst (`r4ab`/`r4auf` in `kernel/user/wlib.fi`):

* die **Ecke** eines Kastens (`new_box`, `box_at`) — aufwärts, damit ein Kasten
  unter einer Reiterleiste nicht in sie hineinrutscht;
* die **Höhe** jedes Bedienelements aufwärts, die **Breite** auf den verfügbaren
  Platz abwärts;
* die **Spaltenbreite** eines Gitterkastens abwärts (der Zahlenblock des Rechners).

Ergebnis, gemessen mit `tools/design/messen.py`:

| Fenster | Raster/4 vorher | nachher | Klickflächen < 32 px |
|---|---|---|---|
| rechner | 67 % | **100 %** (100/100) | 1 → **0** von 23 |
| papierkorb | 83 % | **100 %** (24/24) | 0 |
| viewer | 97 % | **100 %** (36/36) | 0 |
| snip | 92 % | **100 %** (40/40) | 1 → **0** von 8 |
| lock | 43 % | **100 %** (16/16) | 1 → **0** von 2 |

Kein Programm rechnet dafür etwas aus; die Programme sind unverändert geblieben.

**Was das Runden kaputtgemacht hat, und wie es aufgefallen ist:** die Kachelhöhe der
Seite „Vorlagen" war `row + 10` = 34, wurde auf 36 aufgerundet, und die zehnte Kachel
fiel unten aus ihrem Kasten. Sichtbar wurde das nicht im Auge, sondern in der Abnahme
der Runde THEMESTORE: „Werkstatt" wurde gemalt und kam im Bild mit **keinem einzigen
Bildpunkt** an (`shotcheck: empty 1`). `tile_h` ist jetzt `row + 8` = 32 — selbst schon
ein Vielfaches von vier, also rundungsfest, und zehn Kacheln haben wieder Luft.

## Die Zahlen des Laufs

```
== ALLTAG: 47 grün, 0 rot ==   (mit ALLTAG_THEMESTORE=1: themestore 81 grün, 0 rot)
```

* **Rechner:** 40 von 40 Ausdrücken stimmen mit Python (relative Schranke 1e-9);
  Gegenprobe: `2++` gibt einen Fehler und keine Null.
* **ZIP:** packen → entpacken byte-gleich (auch im Unterordner); ein mit Python
  erzeugtes Deflate-ZIP wird entpackt; und Pythons `zipfile` liest das Archiv,
  das der Gast geschrieben hat (609 Oktette) — die Richtung, die ein eigener
  Entpacker nicht prüfen kann.
* **Papierkorb:** Liste kennt den Originalpfad, Rückholung byte-gleich, Leeren
  leert; im Dateimanager legt Entf hinein, Umschalt+Entf löscht endgültig
  (Gegenprobe: dabei entsteht kein `.papierkorb`).
* **Bilder:** 6 von 6 gegen Pillow — PNG (RGBA, Farbtafel, Grau) und BMP exakt in
  Summen und Einzelpunkten, JPEG 4:4:4 exakt, 4:2:0 über die Summen.
* **Ausschnitt:** 998 ‰ der Bildpunkte gleich wie QEMUs eigenes Foto desselben
  Schirms (der Rest ist der Mauszeiger, den der Server nach der Aufnahme malt);
  der Bildbetrachter öffnet das PNG und liest daraus dasselbe wie Pillow.
* **Sperre:** falsches Kennwort → bleibt zu; richtiges → auf; der Sperrer stirbt
  mit Absicht → der Kern startet ihn neu und die **Gegenprobe zeigt: ein Absturz
  sperrt nicht auf**; der Wächter liest `/etc/sperre.conf` und sperrt von selbst.
* **Laden:** 6 signierte Pakete eingespielt, 6 Bündel unter `/apps`, der Starter
  zählt 6; Gegenprobe: ein Paket mit gekipptem Oktett wird abgelehnt (0).
* **Bilder der Programme:** `.alltag-shots/` — je Fenster `shotcheck`
  0 leer / 0 abgeschnitten / 0 überlappend.

## Was diese Runde am Kern geändert hat

* `kstate SP_*`: DASS gesperrt ist, steht im Kern. `wm.darf` filtert Taste, Klick
  **und Bildpunkt** (`compose`), `SYS 1850` sperrt auf und nur der eingetragene
  Sperrer darf es; stirbt er, wird er neu gestartet.
* `SYS_RMDIR` (Linux' 84): `rmdir` hat in diesem System vorher **nie** etwas
  entfernt, `unlink` sagt jedem Verzeichnis EISDIR (POSIX-konform, bleibt so).
* Die private Arena eines Prozesses: 6 → 10 MiB, sonst passt das eigene
  Bildschirmfoto (1280×800 = 4 MiB Bildpunkte) nicht hinein.
* `wlib`: `bild` (Bildfläche mit Zoom/Drehung/Ziehen), `slider`, `setz_groesse`,
  `say_rects` (die Bibliothek meldet ihre Anordnung im Format von
  `tools/design/messen.py`), Eingabetaste (10 → KEY_ENTER 13), Fokus für Dialoge,
  vorgetäuschte Umschalttaste (E0 AA/2A).

## Bekannt und **nicht** von dieser Runde

`./test.sh` Abschnitt 1 ist auf dieser Basis rot, und zwar aus zwei Gründen, die
beide älter sind als dieser Zweig: seit Runde STICK schreibt
`vendor/firn/fetch-firnc.sh` in `.gebaut` **Commit UND Flickenstand**, während
`test.sh` dort nur den Commit erwartet, und `vendor/net/BLOBS` nennt den
**ungeflickten** Stand von `net/stack.fi`, den der Flicken
`0001-rundruf-ohne-arp.patch` verändert. Behoben ist das in `merge6` durch
`66be8ae GLYPHE 18/n: Abschnitt 1 war seit Runde STICK rot -- auf JEDEM Zweig`
— ein Commit, der **nach** dem Abzweig dieses Zweigs entstanden ist. Dieser Zweig
fasst `vendor/firn/fetch-firnc.sh` nicht an; beim Zusammenführen verschwindet es.

**Gefunden und behoben (war von dieser Runde):** `tools/posix/run.sh` Abschnitt 1
hält die Systemaufrufnummern des Kerns gegen die der libc — `SYS_OSUM_SPERRE`
stand nur im Kern (1850) und fehlte in `lib/libc/kcall.fi`. Genau derselbe Fehler
wie bei `SYS_OSUM_CPUSTAT` in MERGE-6, jetzt mit derselben Begründung
danebengeschrieben.

## Nachtrag: `merge6` nachgezogen (Commit „ALLTAG 10/n")

Während dieser Zweig gebaut wurde, ist Runde **GLYPHE** (22 Commits) in `merge6`
gelandet. Der Zweig war damit auf einer alten Basis und maß gegen alte Zahlen.
`git merge merge6` ging **ohne Konflikt** durch; danach:

* `./test.sh` Abschnitt 1 ist **grün** — der oben beschriebene Punkt „bekannt und
  nicht von dieser Runde" hat sich damit von selbst erledigt. Einmal
  `vendor/firn/fetch-firnc.sh` laufen lassen genügt nicht, weil das Skript bei
  aktuellem Übersetzer früh aussteigt und `lib/.roh/` dann fehlt; die Datei kommt
  aus dem Baum, der sie schon hat, oder aus einem Lauf mit gelöschtem `.gebaut`.
* `tools/k15/run.sh`: die Zusage „Zeilen der Naht im Kernel" zählt seit GLYPHE
  Code statt Kommentar und ist wieder grün.

## Drei Fehler, die erst der volle Lauf gezeigt hat

1. **Das Abbild war zu klein — an drei Stellen.** `wlib` ist um Bildfläche,
   Schieberegler und Vierer-Raster gewachsen, und jedes Programm trägt das mit.
   `mkfs` sagte „the disk is full": in `tools/k15/run.sh` beim **zweiten** Abbild
   (Farbschema-Gegenprobe, `disk2.img`) und in `tools/k16/run.sh` bei beiden
   Abbildern. Sichtbar wurde es als scheinbar ganz anderer Fehler: der Assembler
   auf Osum kam mit `BIN=6` zurück — das ist `schreib_elf` fehlgeschlagen, also
   kein Platz. Alle drei stehen jetzt auf 8192 Blöcken (32 MiB, Fassung 2 mit
   mehrblockiger Blockkarte).
2. **`tools/gfx/run.sh`, Abschnitt 11.** Der Schirm hat bei 800×600 und 8×16
   genau 37 Zeilen; die Bilanz am Ende eines Laufs ist über die Runden auf 36
   Zeilen gewachsen, damit stand der Satz der Shell eine Zeile zu hoch. Dieser
   eine Lauf bekommt jetzt den Schirm, den QEMUs EDID nennt (1280×800, 50
   Zeilen); gemessen wird dort die Zeilendisziplin, nicht die eingebaute Vorgabe
   — die steht in Abschnitt 2 und bleibt unangetastet. **GFX: 76 grün, 0 rot.**
3. **SSE2 im eigenen Assembler.** `fas` lehnte die Gleitkommabefehle
   ausdrücklich ab („kein Programm dieses Userlands hat eine f64"). Der
   Taschenrechner hat eine, und die IDCT des JPEG-Decoders auch. Die dreizehn
   Befehle, die `firnc1` dafür erzeugt, sind jetzt kodiert und in
   `tools/k16/run.sh` Oktett für Oktett gegen `as`+`ld` gemessen; dazu die
   Paritätsbedingung (`setp`/`setnp`/`setpe`/`setpo`), ohne die `comisd` nicht
   auswertbar ist.

## Zahlen des Nachlaufs

| Lauf | Ergebnis |
|---|---|
| `tools/alltag/run.sh` | **45 grün, 0 rot** |
| `tools/themestore/run.sh` | **81 grün, 0 rot** |
| `tools/gfx/run.sh` | **76 grün, 0 rot** |

`tools/k15/run.sh` ist auf dieser Basis **nicht** grün — und war es vorher auch
nicht: `merge6` selbst hat dort 30 rote Zusagen im letzten Lauf, dieser Zweig 23,
und die verbleibenden sind auf beiden Zweigen dieselben (Dialogfenster von
`widgetdemo`, Starter/Suche). Diese Runde hat dort nichts hinzugefügt.


## Zweig gegen Basis, gemessen — und was die zwei Vollläufe wert waren

**Der erste Vergleich war keiner.** Am 06.09. liefen `test.sh` auf dem Zweig
(`/root/osum-alltag`) und auf der Basis (`/root/osum-alltagbasis`, merge6
a92fa00) GLEICHZEITIG auf derselben Maschine. Ergebnis: 23 rote Abschnitte auf
dem Zweig, 26 auf der Basis — und die Zahlen taugen nichts, aus zwei Gründen,
die beide erst beim Nachsehen aufgefallen sind:

1. `tools/ota`, `update`, `softui`, `look`, `install` und `betrieb` schreiben in
   FESTE Ordner (`/tmp/ota-run`, `/tmp/update-run`, …). Zwei Läufe zur selben
   Zeit überschreiben sich gegenseitig die Abbilder, Schlüssel und seriellen
   Mitschnitte. Was dort rot war, hat niemand gemessen.
2. Zwei Vollläufe sind rund zwanzig QEMU-Instanzen; dazu kamen die Läufe
   anderer Arbeitsbäume (Load 10–22). Jeder Abschnitt mit einer Frist (ota mit
   `warte_marke`, init mit `timeout 240`, die Netzsektionen) misst dann die
   Maschine und nicht den Kern.

Die beiden Läufe liegen als Beleg unter `.test-work/parallel/` in beiden
Bäumen; gezählt wird hier nur, was danach ALLEIN und SERIELL (`OSUM_JOBS=1`)
gelaufen ist. Fremdlast anderer Bäume blieb auch dabei da (1–19 QEMU-Instanzen,
minütlich mitgeschrieben in `/tmp/last-sampler.txt`) — sie steht bei jedem
Ergebnis dabei, wo sie eine Rolle spielt.

### Die vier Abschnitte, die auf dem Zweig rot waren und auf `merge7` allein grün

| Abschnitt | Zweig, allein | Basis merge6, allein | Befund |
|---|---|---|---|
| `net` (14. das Netz) | **75 / 0** | — (nicht nötig) | Im Parallel-Lauf rot durch die Netzsperre unter Last. Allein grün. |
| `multiuser` (29.) | 90 / **1** | 90 / **1** | Dieselbe Zusage, dieselben Zahlen: „das Verhältnis stimmt nicht: 24957 µs zu 612973 µs" (Basis: 24952 zu 601272). 1024 gegen 4096 PBKDF2-Runden sollen 3–5× kosten, kosten hier 24×. Das Skript selbst beschreibt den Grund (KVM legt bei Läufen über ~200 ms einen festen Aufschlag drauf). Wirtsabhängig, kein Befund dieser Runde. |
| `init` (29. der erste Prozess) | 39 / **39** | 39 / **39** | ZWEI Ursachen, beide vorbestehend, siehe unten. |
| `bridge` (38. JARVIS-Helfer) | 111 / **1** | 111 / **1** | „foto mit Schein: … dieser Kern hat SYS_OSUM_SHOT": der Helfer fragt 1840, in merge6 ist 1840 `CPUSTAT` — genau der Fehler, den MERGE-7 mit `SYS_OSUM_SHOT = 1841` behoben hat (Kommentar in `lib/libc/kcall.fi` auf merge7). Auf merge6 rot, mit merge7 erledigt. |

Zweig und Basis sind auf allen dreien roten Abschnitten ZEILENGLEICH rot. Kein
Abschnitt ist durch diese Runde rot geworden.

### `init`: was die 39 roten Zusagen wirklich sind

Der Hauptlauf (neun Dienste, ein Absturz, ein Ziel, 240 s Frist) kommt nicht
über ACPI herunter — rc 124 —, und die 28 Zusagen dahinter lesen einen
Mitschnitt, der nicht da ist. Der Mitschnitt, der da ist, sagt zweierlei:

1. **`panic: integer overflow casting 'u64 as u8' at kernel/sched.fi:1060`** —
   die Ablaufspur schreibt die Prozessnummer als ein Oktett, und die
   Respawn-Schleife des Tests treibt die Nummern über 255. Auf der Basis
   dieselbe Zeile (`/tmp/tmp.MjsBdeL6pt/dienste.txt`). **Behoben in 85cc8b8**
   (`(v & 0xFF) as u8`); mit dem Fix: keine Panik mehr, auf Zweig UND Basis
   (der Fix wurde für den Vergleich vorübergehend in den Basis-Baum gelegt und
   danach zurückgenommen).
2. **Und dann steht die Maschine trotzdem**: nach `==BEGIN==` druckt das erste
   `svc status` keine Tafel, nach `--SPAETER--` bleibt das zweite `svc status`
   (`elf: start 26`) das Letzte im Mitschnitt — keine Panik, kein Halt, bis die
   Frist zuschlägt. **Zweig und Basis (jeweils mit dem sched-Fix) identisch.**
   Die Ursache ist offen und gehört zur Runde INIT/SVC; sie hat mit dieser Runde
   nichts zu tun: der einzige Kern-Haken dieser Runde (`sperre_wache`) kehrt
   ohne stehende Sperre sofort zurück und wird nur aus dem Fensterserver-Pfad
   gerufen (`kgui.fi` 1941/2952) — der init-Lauf hat keinen Fensterserver.

Auf `merge7` war `init` in EINEM Lauf grün; ob das der geänderte `proc.fi`
(einzige Kern-Differenz auf diesem Pfad) oder Glück im Rennen war, ist nicht
gemessen.

### `ota`, allein — und der Fehler, den erst der Einzellauf gezeigt hat

Der erste Einzellauf (altes Abbild, 15:16–17:10) war bis 16:40 wirklich allein
(Load 2–4, keine fremden QEMUs): **Abschnitte 1–3: 92 grün, 0 rot; (d) „das
Update, das nicht hochkommt": Durchläufe 1–6 grün.** Ab 16:40 kamen 11–19
fremde QEMU-Instanzen dazu (tools/glyphe in `/root/osum-merge7`, Load bis 22).
Durchlauf 7 fiel — und der Mitschnitt `d7-s1.txt` sagt warum:

    panic: integer overflow in 'u64 - u64' at kernel/arch/x86_64/apic.fi:452:22

`vergangen = (a - a0) & maske` — die Umlaufrechnung des ACPI-Zeitgebers, aber
Firn prüft die Differenz VOR der Maske. Der 24-Bit-Zeitgeber läuft alle 4,69 s
um; ein 100-ms-Fenster trifft den Umlauf in 2,1 % aller Starts. **Gemessen: 2
von 53 Starts** (d7-s1, d9-ein) — genau die Rate. Vorbestehend seit BLECHVIER
(67c6047), auf merge6 und merge7 dieselbe Zeile. **Behoben in de19bcb**
(`(a + (maske + 1) - a0) & maske`). Das erklärt, warum jeder Test mit vielen
Starts (ota, update, betrieb, die Stromausfall-Schüsse) auf jedem Zweig ab und
zu grundlos rot war. Der Lauf wurde bei Durchlauf 9 abgebrochen, weil er nur
noch diesen bekannten Fehler gemessen hätte; Mitschnitt und die zwei
Panik-Dateien liegen unter `.test-work/ota-solo-altesabbild/`.

**Der zweite Einzellauf, mit beiden Fixes (apic.fi de19bcb, sched.fi 85cc8b8):**
20:40–23:59 am 07.09., 3 h 19 min, wirklich allein: 200 Proben im Minutentakt
(`.test-work/ota-solo-fix/last-sampler-ota2.txt`), keine einzige mit einer
fremden QEMU-Instanz, Load 0,33–3,48, nur die eigenen ein bis zwei Maschinen.
Vorher musste ein fremder Vollauf zu Ende gehen (`/root/osum-merge7`, 67
Abschnitte, 10 gleichzeitig, 19:18–20:29) — ein Wächter hat das Ende
abgewartet und erst dann gestartet.

    OTA: 107 grün, 0 rot        (rc 0)

| Abschnitt | Ergebnis |
|---|---|
| 1–3: Bau, der gute Weg, die Ablehnungen (a, a2, g, b, b2, c, c2, f, Einstellungsseite) | 92 grün, 0 rot — dieselben 92 wie im ersten Einzellauf |
| 4 (d): das Update, das nicht hochkommt | **10 von 10** Durchläufen hat sich das Gerät selbst gerettet; Gegenprobe (das gute Update läuft) grün |
| 4: der Wachhund | Erprobung erkannt, Neustart ausgelöst, ohne Erprobung nichts — 3 von 3 |
| 5 (e): der Stromausfall, 30 Schüsse | grün; gemessen: Netz 10 605 ms, Paket geprüft 15 148 ms, geschrieben 26 482 ms, bereit 26 593 ms |
| 6: die Messungen | Update auf der Leitung 38 838 Oktett (übertragen 34 710); `ota suchen` bis Antwort 86,9 s; `ota einspielen` bis „bereit zum Neustart" 213,8 s Wanduhr; Rückfall 55,8 s |

**126 Starts, 0 Paniken** (jeder Mitschnitt liegt unter
`.test-work/ota-solo-fix/`). Zum Vergleich der Kern OHNE den apic.fi-Fix, am
selben Tag, im selben Test: der erste Einzellauf dieser Runde 2 Paniken in 53
Starts; merge7s eigener Vollauf (`/tmp/m7-testsh4.log`, `ota` dort 19:40–20:29)
**1 Panik in 126 Starts** — dieselbe Zeile `apic.fi:452:22`, in `d2-ein.txt`
(gesichert unter `.test-work/merge7-fremd-ota/`), und deshalb dort „(d)
Durchlauf 2" rot und „selbst gerettet: 9, erwartet 10". Bei 2,1 % je Start
wären 126 Starts ohne Panik mit dem alten Kern ein Zufall von rund 7 %;
zusammen mit der Rechnung an der Zeile selbst reicht das: der Umlauf ist zu.

Was NICHT gemessen wurde: `ota` allein auf der Basis (merge6). Das wären
weitere 3 h 20 min gewesen, um den bekannten apic.fi-Fehler noch einmal zu
treffen — genau das, was der erste Einzellauf mit dem alten Abbild schon getan
hat (Abschnitte 1–3 92/0, Durchläufe 1–6 grün, Durchlauf 7 die Panik). Die
Parallel-Zahlen (Zweig 40 rote Zusagen, Basis 44) sind kein Vergleich, siehe
oben: beide Läufe schrieben in dasselbe `/tmp/ota-run`.

### Stand der übrigen Abschnitte — gegen `merge7`s eigene Läufe gehalten

Im Parallel-Lauf vom 06.09. waren auf dem Zweig 23 Abschnitte rot
(`.test-work/parallel/.rc.*`), auf der Basis 26. Ohne die vier oben bleiben
auf dem Zweig 19:

    gfx k15 k18 display theme paint netview powermon server
    update usbimg umlaut softui ota blech modul stick werkzeug glyphe

Jeder dieser 19 ist im selben Parallel-Lauf auch auf der Basis (merge6) rot.
Die Basis hat vier weitere (`k16 hwnet themestore vielkern`); der Zweig hat
keinen, den die Basis nicht hat — außer `net`, und das ist allein 75/0 (oben).
Für `blech`, `modul` und `stick` sind Zahlen und rote Zeilen auf Zweig und
Basis dieselben (69/1 „DER ALTE KERN haengt nichts ein", 72/2 „der verdorbene
Programmtext hat nichts ausgeloest", 20/22).

`merge7` hat am 07.09. zwei eigene Vollläufe gemacht (anderer Baum,
`/root/osum-merge7`, nicht diese Runde; `/tmp/m7-testsh3.log` und
`/tmp/m7-testsh4.log`), und die zwei zusammen sagen mehr als jeder für sich:

| merge7-Lauf | gleichzeitig | rot | welche |
|---|---|---|---|
| testsh3 (bis 19:05) | 2 | **14** | `async gfx k16 k15 k18 display theme paint netview powermon server usbimg umlaut softui` |
| testsh4 (19:18–20:29) | 10 | **23** | dieselben ohne `async k16`, dazu `pci init ota blech hid modul stick vielkern werkzeug glyphe systembus` |

Derselbe Baum, dieselbe Stunde: **elf Abschnitte werden allein durch die
Gleichzeitigkeit rot** — darunter `init`, `ota`, `blech`, `modul`, `stick`,
`werkzeug`, `glyphe`. Und zwar mit den Zahlen des Parallel-Laufs dieser
Runde: BLECH 69/1, MODUL 72/2, STICK 20/22 auf merge7 unter Last — dieselben
wie auf Zweig und Basis unter Last. Was da rot wird, misst die Maschine.

Damit teilen sich die 19 so auf:

1. **12 überall rot** — auf Zweig, Basis und in beiden merge7-Läufen: `gfx k15
   k18 display theme paint netview powermon server usbimg umlaut softui`.
   Vorbestehend, nicht Sache dieser Runde, nicht einzeln nachgefahren. Ein
   Detail dazu: `gfx` ist auf dem Zweig inzwischen **76/0** („Drei Fehler",
   Nr. 2), und merge7s einzige rote gfx-Zusage ist genau diese („die Zeile
   der Shell steht bildpunktgenau auf dem Schirm — 'OSUM SHELL ON SCREEN'
   steht nicht auf dem nachgebildeten Bildschirm", 75/1 in beiden
   merge7-Läufen) — die Änderung an `tools/gfx/run.sh` käme mit dem Merge
   mit.
2. **7 nur unter Last rot** — auf Zweig und Basis im Parallel-Lauf, auf
   merge7 bei 10 gleichzeitig, aber grün bei 2 gleichzeitig: `ota update
   blech modul stick werkzeug glyphe` (`update` war in beiden merge7-Läufen
   grün und im Parallel-Lauf dieser Runde auf Zweig und Basis mit
   VERSCHIEDENEN Zeilen rot — zwei Läufe schrieben in dasselbe
   `/tmp/update-run`). Genau diese sieben wurden auf dem Zweig ALLEIN
   nachgemessen — `ota` oben, die anderen sechs hier, seriell
   (`OSUM_JOBS=1 OSUM_NUR='^(update|blech|modul|stick|werkzeug|glyphe)$'`):

| Abschnitt | Zweig, allein | Basis merge6, allein | Befund |
|---|---|---|---|
| `update` (30.) | **49 / 0**, 1617 s | **49 / 0**, 1622 s | Im Parallel-Lauf auf beiden rot, mit verschiedenen Zeilen — beide Läufe schrieben in dasselbe `/tmp/update-run`. Allein grün. |
| `blech` (35.) | 69 / **1**, 113 s | 69 / **1**, 112 s | zeilengleich: „DER ALTE KERN haengt nichts ein". merge7: grün bei 2 gleichzeitig, 69/1 bei 10. |
| `modul` (37.) | 72 / **2**, 134 s | 72 / **2**, 136 s | zeilengleich: „rc=21: der verdorbene Programmtext hat nichts ausgeloest", „kein Ausnahmebericht". merge7: grün bei 2, 72/2 bei 10. |
| `stick` (39.) | 20 / **22**, 368 s | 20 / **22**, 372 s | dieselben Zahlen; merge7: grün bei 2, 20/22 bei 10. |
| `werkzeug` (41.) | 26 / **8**, 104 s | 22 / **12**, 100 s | Die 8 des Zweigs sind eine TEILMENGE der 12 der Basis: der Sortier-Klick in die Kopfzeile (2), SYS_KILL (2), die vier `qs`-Zusagen. Die Basis hat dazu Startmenü, `wahl pid`, `frage pid`, Helligkeitsregler. merge7: 34/0 bei 2, 30/4 bei 10 (Beschriftungen, `frage pid`, SYS_KILL ×2). |
| `glyphe` (42.) | 26 / **3**, 2291 s | 27 / **2**, 2178 s | Zweig: die zwei Gegenproben „ohne die Tafelsperre passiert NICHTS" und „mit EINER Buehne passiert nichts" (LAEUFE=20; beide auch auf merge7 bei 10 gleichzeitig — sie brauchen ein Rennen, das auf 20 Wirtskernen nicht immer kommt) — und **1 von 20 Läufen mit `-smp 8` mit Panik oder Ausnahme**. Basis: dieselben zwei Gegenproben, **0 von 20** mit `-smp 8` (Zweig parallel am 06.09.: 0 von 20; merge7: 0 von 20 in beiden Läufen). |

Der Sortier-Klick im Aufgabenverwalter war der eine Punkt, der nach ALLTAG
aussah: `taskmgr.fi` und `tools/werkzeug/run.sh` sind auf Zweig und Basis
identisch, `wlib` rundet seit dieser Runde Ecken und Höhen aufs
Vierer-Raster — ein Klick, der die Kopfzeile verfehlt, wäre genau das
gewesen. Die Basis allein verfehlt sie genauso (und vier Zusagen mehr).

**Die Panik in der `-smp 8`-Serie** ist die einzige Zeile dieser sechs, die
der Zweig hat und die weder im Parallel-Lauf des Zweigs noch bei merge7
(0 von 20, beide Läufe) auftrat. Der Läufer räumt sein Verzeichnis ab, der
Text der Panik war weg. Darum lief `glyphe` auf dem Zweig noch einmal mit
aufgehobenen Mitschnitten (`/tmp/glyphe-keep`, Kopie des Läufers ohne `trap`):
**0 von 20** mit `-smp 8` und 0 von 20 mit `-smp 4` (03:00, allein, Load 8–12 aus den eigenen acht Maschinen). Damit steht sie 1-mal in 40 Läufen des Zweigs mit `-smp 8` und 0-mal in 20 der Basis, 0-mal in 40 von merge7 — zu selten, um sie in dieser Runde zu fassen, und der Text fehlt. Sie bleibt der EINE offene Punkt dieser Nachmessung: in der Merge-Runde `glyphe` mit aufgehobenen Mitschnitten fahren, bis sie wieder auftritt (der Läufer räumt sein Verzeichnis sonst ab; das Rezept ist ein `sed` auf
`tools/glyphe/run.sh`: `TMPD=$(mktemp -d)` durch einen festen Ordner ersetzen,
die `trap`-Zeile streichen). Das Rennen würde im Fensterserver liegen — dort sitzt `sperre_wache`, der einzige Kern-Haken dieser Runde.

Nebenbefund an `test.sh`, keine Änderung in dieser Runde: bei `update` steht
„(davon 1442,242 s Warten auf die Netzsperre)" in der Zeitzeile, obwohl die
Maschine frei war — `abschnitt_ausfuehren` löscht ein altes `.netto.$i` vor
einem Nicht-Netz-Abschnitt nicht, und mit `OSUM_NUR` bekommen andere
Abschnitte dieselben Indizes (hier `.netto.0` vom `net`-Lauf um 17:15).
Ein `rm -f "$WORK/.netto.$i"` am Anfang der Funktion behebt das; `test.sh`
ist ein Merge-Brennpunkt, das gehört in die Merge-Runde.

### Ein Erbe von `merge6`, das nicht dieser Runde gehört: die langsame Rechenarbeit in Ring 3

Beim Nachfahren fiel auf, dass die A/B-Update-Tests hier ein Vielfaches der
merge7-Zeiten brauchen — und die Zahlen dazu stehen längst im
`multiuser`-Abschnitt, alle unter KVM (`/dev/kvm ist da`):

| | Zweig, allein | Basis, allein | merge7 (10 gleichzeitig) |
|---|---|---|---|
| PBKDF2-Runden je Sekunde in Ring 3 | 6 614 | 6 329 | **37 294** |
| EINE Prüfung mit 8192 Runden | 1,24 s | 1,29 s | **0,22 s** |
| 1024 Runden (kurz) | 25 ms | 25 ms | — |
| `ota`: von `ota suchen` bis zur Antwort (ganzer Start) | 86,9 s | — | **12,3 s** |
| `ota`: `einspielen` → „bereit zum Neustart", Wanduhr | 213,8 s | — | **17,4 s** |
| `ota`: dasselbe nach der Uhr des Gastes | 26,6 s | — | 18,6 s |
| `ota`, der ganze Lauf | 3 h 19 min | — | **49 min** |
| `update` | 1617 s | 1622 s | **757 s** |
| `blech` / `modul` / `stick` / `werkzeug` | 113 / 134 / 368 / 104 s | 112 / 136 / 372 / 100 s | 112 / 143 / 374 / 94 s |

Kurze Rechenläufe sind gleich schnell, lange (über ~200 ms am Stück:
PBKDF2, RSA/ECDSA im TLS-Handschlag, Ed25519 in `update`) sind auf
`merge6` fünf- bis sechsmal langsamer als auf `merge7`, und die Uhr des
Gastes und die Wanduhr gehen dabei um das Achtfache auseinander, was sie auf
merge7 nicht tun. Abschnitte ohne lange Rechenläufe sind zeitgleich. Zweig
und Basis sind darin gleich — das ist nicht ALLTAG, es liegt zwischen
`merge6` und `merge7`, und die Ursache wurde hier nicht gesucht. Der
`multiuser`-Text schreibt es einem festen KVM-Aufschlag zu; merge7 zeigt,
dass es keiner ist. Nach dem Merge auf `merge7` gehört `multiuser` einmal
nachgemessen — und die 3 h 19 min für `ota` sollten dann Vergangenheit sein.

Die Zahlen des Zweigs, die zählen, stehen damit alle allein gemessen da:
`tools/alltag` 45/0, `themestore` 81/0, `gfx` 76/0, `net` 75/0, dazu `ota`
und die sechs. Kein Abschnitt ist auf dem Zweig rot, der nicht auch auf
`merge6` rot ist — und was auf dem Zweig allein rot bleibt, ist es auch auf
der Basis allein: zeilengleich (`init`, `bridge`, `multiuser`, `blech`,
`modul`, `stick`), als Teilmenge (`werkzeug`) — bis auf die eine
`glyphe`-Panik in 40 Läufen, die oben steht.

## Probe-Merge auf `merge7` (8c31a08) — gemessen, nicht gemergt

`merge7` liegt inzwischen auf GitHub (Zweig `merge7`, 8c31a08); `alltag` kommt
DANACH obendrauf. Ob das passt, wurde in einem Wegwerf-Arbeitsbaum ausprobiert
(`git worktree add --detach /root/osum-probe7 origin/merge7`, dort
`git merge --no-commit --no-ff alltag`). Nichts davon ist gemergt oder gepusht.

**Ausgangslage.** `git merge-base alltag origin/merge7` = a92fa00, das ist genau
die Spitze von `merge6` — `alltag` hat keinen anderen Vorfahren. Zwischen
`merge6` und `merge7` liegen 55 Commits (die Runden DESIGN-2, BLECH-2, BRIDGE-2,
SYSTEMBUS, PROTOKOLL, TON, CERTUS-2), 152 Dateien.

**Was git meldet.** 95 Dateien gehen automatisch, 6 Dateien mit 13
Konfliktstellen:

| Datei | Stellen | Auflösung |
|---|---|---|
| `kernel/proc.fi` | 1 | merge7-Seite: die Arena ist dort 192 MiB (`PRIV_SLOTS` 99, `BIG_TOP` 0x4C600000, Runde CERTUS). ALLTAG hatte sie für den Bildbetrachter von 6 auf 10 MiB gehoben — 192 deckt das mit. |
| `kernel/sys.fi` | 3 | Exportliste: Vereinigung. Konstante: beide. Dispatcher: beide Zweige hintereinander, die schließende Klammer der merge7-Seite dazwischen. |
| `lib/libc/kcall.fi` | 2 | Exportliste: Vereinigung. Konstante: beide. |
| `kernel/user/wlib.fi` | 6 | Exportlisten (3×): Vereinigung. `say_rects` neben den DESIGN-2-Wörtern: beide. Maus-runter/Maus-hoch: beide — **und die schließende Klammer der merge7-Seite zurück** (`if k == K_LEINWAND { … return }` bzw. `LE_UP`). Ohne sie: `'fn' is only allowed at top level` bei `on_up`/`on_move` — gemessen beim ersten Probe-Bau. |
| `tools/laden/apps.tab` | 1 | beide (certus + die sechs Zeilen dieser Runde). |
| `tools/laden/build.sh` | 1 | GUI-Liste von merge7 (mit `taskmgr`) + `rechner papierkorb viewer snip lock`; CLI + `zip`. |

**Was git NICHT meldet — zwei Nummern, die doppelt vergeben sind.** Beide
stehen in verschiedenen Zeilen, der Textverschmelzer sieht sie nicht; beide
wären nach dem Merge stille Fehlweichen:

1. **`SYS_OSUM_SPERRE = 1850`** (ALLTAG) gegen **`SYS_OSUM_AUDGET = 1850`**
   (Runde TON, merge7). Der Sperrbildschirm hätte den Ton gefragt. Die Dekaden
   auf merge7: 1810 DISP, 1820 TILE, 1830 PMON, 1840/41 CPUSTAT/SHOT, 1850–54
   AUD, 1860/61 KLOG/KRACH, 1900–03 FTYPE…, 1950/51 WG, 1960 BUS. **Frei: 1870.**
   Drei Stellen: `kernel/sys.fi`, `lib/libc/kcall.fi`, `kernel/user/lock.fi`
   (`SYS_SPERRE`). `tools/posix/run.sh` Abschnitt 1 hält Kern und libc danach
   wieder nebeneinander (auf dem aufgelösten Baum: 160 Namen im Kern, 158 in
   der libc, kein `OSUM_*` nur auf einer Seite — die zwei Kern-eigenen sind
   `SYS_MARK`/`SYS_LEAVE`, vorbestehend).
2. **`K_BILD = 15`** (ALLTAG, die Bildfläche) gegen **`K_LEINWAND = 15`**
   (CERTUS-AUF-OSUM, die Leinwand des Browsers). Zwei Widget-Arten mit einer
   Nummer: der Maler hätte die Bildfläche als Leinwand gemalt. **Neu: `K_BILD`
   16, `K_SLIDER` 17** — nur in `wlib.fi`; `viewer.fi`/`snip.fi` benutzen die
   Namen, `shotcheck.py` liest Arten nicht nach Zahl.

**Was NICHT kollidiert (gegengeprüft, nicht angenommen).**

- `KEY_SDEL = 0x10A` (Umschalt+Entf): merge7 endet bei `KEY_DEL = 0x109`.
- Die Sperre im Tastaturblock (`kstate`, `K11_OFF` + `SP_ON`…`SP_SLOT` =
  0x100…0x138): merge7 belegt dort 0x00–0xB0 (`KB_*`, `HK_*`), `KB_HOT` 0xC0
  bis 0xE0 und `ENV_BUF` ab 0x200 — die Lücke 0x100–0x1FF ist auf merge7
  genauso frei wie auf merge6.
- **kdata:** ALLTAG legt KEINEN Bereich an. `tools/kernel/memmap.py` auf dem
  verschmolzenen Baum: **104 Bereiche in 0x100000 Oktetten, 11 Vektoren, 173
  Modusnamen, 0 Kollisionen** — dieselbe Zahl wie merge7 allein (alltag allein:
  93 Bereiche in 0xC0000, 0 Kollisionen, wie merge6). MERGE-7s neue Aufteilung
  (BUS 0xC0000, LOG 0xC8000, AUD/HDA/MIX 0xD8000…, BLK 0xDF000…) berührt nichts
  von dieser Runde.
- Win+L (ALLTAG, `kbd.fi`) und Super+P (FEEDBACK/BRIDGE-2, das Bildschirmfoto):
  die Sperre greift im Super-Zweig nur bei `l`/`L` und kehrt dort zurück; jeder
  andere Buchstabe geht wie vorher in die Klinke (`HK_KEY`/`HK_SEQ`), aus der
  `kernel/shot.fi` das Super+P liest. Automatisch zusammengeführt, gegengelesen.

**Der Bau des aufgelösten Baums** (`tools/alltag/build.sh`, Compiler-Pin
a751b3d ist auf beiden Zweigen derselbe): **0 Fehler**, 21 Programme gelinkt —
darunter `viewer snip lock papierkorb rechner zip` gegen die verschmolzene
`wlib` und merge7s `taskmgr` —, das Abbild bootet, `wm: selftest 30 / 30`,
`desk: start /bin/launcher`, `taskbar: round=201 … px=71680 soll=71680 null=0`
(aus dem seriellen Protokoll des Bau-Starts; `desktop.png` liegt daneben). `korb.fi` und `qs.fi` sind Bibliotheken
ohne `u_start` und gehören nicht in die Programmliste (das war ein
Listenfehler beim Probieren, kein Merge-Befund). Nicht gebaut: `certus` (kommt
aus `/root/certus-sammeln` über `kernel/user/certus/build.sh`, hängt nur an der
gebauten `wlib`). **Nicht gelaufen:** `tools/alltag/run.sh` auf dem
verschmolzenen Baum — das wäre QEMU-Last während der `ota`-Einzelmessung
gewesen und ist Pflicht für die Merge-Runde.

**Werkzeug.** `tools/alltag/probe7-aufloesung.py <wegwerf-worktree>` führt die
Tabelle oben mechanisch aus (Vereinigung, beide, merge7-Seite, Umnummerierung
1850→1870 und 15/16→16/17); die zwei Klammern in `wlib.fi` setzt es nicht —
sie stehen im Kopf des Skripts. Wegwerf-Werkzeug, kein Teil der Abnahme.

**Fazit:** `alltag` passt NICHT konfliktfrei auf `merge7` — 6 Dateien
textlich, dazu zwei stille Nummernkollisionen (1850, 15). Mit den Auflösungen
oben baut und bootet der verschmolzene Baum. Der Wegwerf-Baum
`/root/osum-probe7` bleibt zum Nachsehen stehen (nichts committet).
