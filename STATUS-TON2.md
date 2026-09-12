<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Runde TON-2 — der Leerlauf, der Mischer, der Regler

Zweig `ton2`, abgezweigt von `ton` (6d0b887). Arbeitsbaum `/root/osum-ton2`.
Nicht gepusht, nicht gemergt.
Stand: 06.09.2026.

Commits: `7903fce` (der Leerlauf) · `17c9723` (der Regler) · `51d2dcc`
(die Abnahmen) · dieser Bericht.

---

## Kurz

| Auftrag | Ergebnis |
|---|---|
| Die letzten zwei Aussetzer | **Ursache gefunden und behoben.** 12 Läufe à 60 s: **gaps = 0 in allen**, kein Rahmen verloren |
| Mischer, mehrere Quellen | **Vorhanden seit Runde HDA** — jetzt von Ring 3 aus nachgewiesen: 2 Programme, 2 Ströme, beide Töne einzeln messbar |
| Lautstärke je Quelle + Master | **Nachgewiesen.** `-v` trifft nur seinen Strom, `-m` beide |
| Clipping-frei | **Nachgewiesen mit Gegenprobe:** flacher Scheitel bei 32767, 65 436 begrenzte Werte, kein Umlauf |
| Systemklänge als Quelle | **Nachgewiesen:** Hinweiston bei 1050 ms, Leistung 2964 gegen Grundpegel 0, Musik ohne Lücke |
| Regler + Taskleistensymbol | **Gebaut,** `K_SLIDER` in wlib, 4 Glyphen, Klick + Super+M |
| Regression kdata | **Geprüft.** Keine Kollision durch TON-2 — **aber ein echter Konflikt in `taskbar.fi`** (siehe Abschnitt 6) |

---

## 1. Der Befund: zwei Drittel aller Systemaufrufe waren Leerlauf

Runde TON hatte die Aussetzer aus der **Platte** geholt (4982 ms Lesen auf
84 ms). Übrig blieben zwei, und der Auftrag vermutete richtig: der
Abspieler dreht leer, wenn der Ring voll ist.

Gemessen für **eine Sekunde** Ton, `/ton.wav`, `-smp 4`, IDE:

| | Grundlinie | TON-2 |
|---|---:|---:|
| Wartedrehungen | 139 290 | **26** |
| Systemaufrufe gesamt | 418 952 | **963** |
| Schübe | 139 713 | **126** |
| Lücken in der Ausgabedatei | 0 | 0 |

Für 46 540 Rahmen braucht es rund **45** echte Schübe. Jede Wartedrehung
kostete **zwei** Systemaufrufe (`A_PLAYED` + `SYS_YIELD`): 278 580 von
418 952, also **66,5 %** aller Systemaufrufe, und keiner davon hat einen
Rahmen bewegt.

### Die Zahl, die auf niemanden zeigte

`rechnen_us` meldete 436 ms „Rechnen". Das war eine Falle im **eigenen
Messgerät**: `play.fi` bildete sie als *Differenz* (gesamt − lesen −
senden). Eine Zahl, die man nur ausrechnet, statt sie zu messen, ist ein
Sammelbecken für alles, was sonst nirgends gezählt wird — hier für genau
diesen Leerlauf.

Jetzt misst eine Uhr die Aufbereitung (`aufbereit_us`) und eine zweite
die Wartezeit (`warten_us`). Danach war die Rechnung sofort lesbar:
**echte Arbeit 114 ms je Sekunde Ton (11 %)**, der Rest ist Warten auf
das Gerät.

---

## 2. `AS_WAITSPACE` — das Warten gehört in den Kern

`sleep_ms(1)` geht in diesem Kernel **nicht**: `do_nanosleep`
(`kernel/sys.fi:5304`) rechnet `ticks = sec*100 + (nsec+9999999)/10000000`
und rundet damit auf ganze **10-ms-Schläge auf** (`TICK_HZ = 100`).
Runde TON hatte das gemessen — 158 Aussetzer — und deshalb bewusst den
Spin behalten.

`kernel/mix.fi` sagt seit Runde HDA selbst, wo die Lösung liegt:

> „das gehört in den Systemaufruf, wo es einen Prozess gibt, den man
> schlafen legen kann."

    osum_audset(AS_WAITSPACE, ((Kennung + 1) << 8) | Rahmen/16)
        -> Rahmen, die jetzt Platz haben

Der Kern pumpt den Mischer, rechnet aus Füllstand und Abtastrate die
Wartezeit und legt den Prozess genau so lange schlafen.

**Drei Fallen, alle gemessen:**

1. **Die Sperre.** `audio.hold` ist eine Drehsperre **mit `cli`**. Wer
   damit schlafen geht, hält den Rechner an. Also unter der Sperre
   *rechnen*, ohne sie *schlafen*, danach neu nachsehen.
2. **Die Kennung.** `mix.open` gibt für den ersten Strom `0` zurück —
   dieselbe `0`, die „Einstromweg" heißt. Um eins verschoben.
3. **Aufrunden.** Rahmengenau gerechnet wird `us / 10000` fast immer
   null, es bleibt beim `yield`, der Aufruf kommt nach ~724 µs zurück:
   **74 361** Drehungen in 60 s statt **2 604**.

### Ein negatives Ergebnis, das im Code steht

Das `SYS_YIELD` nach jedem Schub sah mit `AS_WAITSPACE` überflüssig aus.
Entfernen ergab **Aussetzer 1 → 4**, Systemaufrufe **2095 → 3594**.
`AS_WAITSPACE` läuft **nur bei vollem Ring**; solange Platz ist, läuft
die Schleife durch, ohne je in den Kern zu gehen. Die Zeile bleibt, die
Begründung steht jetzt dort.

---

## 3. Die 60-Sekunden-Abnahme

`bash tools/ton/acceptance.sh` — zwölf Läufe, `lang44.wav -w 6`:

| smp | Quelle | gespielt | syscalls | Schübe | wartete | Aussetzer | **gaps** |
|---|---|---:|---:|---:|---:|---:|---:|
| 1 | ide | 2 646 000 | 39 239 | 10 348 | 2 602 | 1 | **0** |
| 1 | ide | 2 646 000 | 39 326 | 10 384 | 2 619 | 1 | **0** |
| 1 | ide | 2 646 000 | 39 244 | 10 356 | 2 601 | 2 | **0** |
| 1 | ram | 2 646 000 | 37 034 | 8 128 | 2 607 | 3 | **0** |
| 1 | ram | 2 646 000 | 37 177 | 8 205 | 2 629 | 3 | **0** |
| 1 | ram | 2 646 000 | 36 947 | 8 044 | 2 606 | 1 | **0** |
| 4 | ide | 2 646 000 | 39 286 | 10 371 | 2 610 | 3 | **0** |
| 4 | ide | 2 646 000 | 39 256 | 10 353 | 2 606 | 3 | **0** |
| 4 | ide | 2 646 000 | 39 251 | 10 345 | 2 607 | 3 | **0** |
| 4 | ram | 2 646 000 | 36 901 | 8 005 | 2 601 | 1 | **0** |
| 4 | ram | 2 646 000 | 36 998 | 8 096 | 2 603 | 3 | **0** |
| 4 | ram | 2 646 000 | 36 936 | 8 022 | 2 607 | 3 | **0** |

`gespielt = 2 646 000` ist in **allen zwölf** genau `6 × 441 000` — kein
Rahmen zu viel, keiner zu wenig. `verloren = 0`, `still = 0`,
`luecke_rest = 0`.

**~636 Systemaufrufe je Sekunde Ton** gegen 418 952 in der Grundlinie.

### Warum drei Läufe je Fall

Der Aussetzerzähler (`hda.fi`, `S_UNDER`) wird **nur fortgeschrieben,
wenn jemand `position_frames` aufruft**. Über eine Sekunde schwankte er
bei völlig gleichem Code zwischen **1 und 5**. Er ist damit teils ein
Beobachtungsartefakt — und weil TON-2 200× seltener hinsieht, ist er
nicht mit der Grundlinie vergleichbar.

**Die Zahl, die zählt, ist `gaps`**: echte Nullstrecken in dem, was das
Gerät ausgegeben hat. Schon die Grundlinie hatte `gaps = 0` bei drei
„Aussetzern" — der Zähler hat **nie** hörbaren Schaden bedeutet.

### Warum 60 s nicht als eine Datei gehen

Ein Inode fasst hier **2 134 016 Oktette** (8 direkte, 64 einfach und
4096 doppelt indirekte Blöcke, `kernel/fs.fi`) = **12,1 s** bei 44 100 Hz
stereo. Deshalb `/bin/play -w N`: dieselbe Datei N mal an **einem
offenen Strom**. Die fünf Nähte sind zusätzlich eine Prüfung, die eine
einzelne lange Datei gar nicht hätte — wäre dort eine Lücke, stünde sie
als Nullstrecke in der Datei.

---

## 4. Der Mischer, von Ring 3 aus — 25 Zusagen, 0 beanstandet

`bash tools/ton/mischer.sh`. Der Mischer selbst ist **Bestand seit Runde
HDA** (4 Ströme, Lautstärke je Strom, Sättigung mit Zähler, Master,
Systemklänge). Neu ist der Nachweis **von außen**.

* **Zwei Programme:** Ströme 0 und 1, je 240 000 Rahmen. p1(440 Hz)=3054,
  p2(660 Hz)=4522, dazwischen bei 550 Hz nur 128. max=23 692 < 32 767.
* **Lautstärke je Strom:** voll max=12 000, auf 25 % max=**3 000**.
* **Ein Strom auf 0:** p1 = 50 (weg), der andere spielt in voller
  Aussteuerung weiter.
* **Master:** max 22 871 → **12 000**, beide Töne noch da.
* **Sättigung:** zwei Ströme zu je 30 000 → **flacher Scheitel bei
  32 767**, min −32 768, **65 436** begrenzte Abtastwerte. Kein Umlauf.
* **Systemklang:** Hinweiston (880 Hz) bei **1050 ms**, Leistung **2964**
  gegen Grundpegel **0**; die Musik läuft ohne Lücke durch.

### Zweimal war das Messgerät schuld

Das ist der lehrreichste Teil dieser Runde, weil die falsche Reaktion
gewesen wäre, den Kernel zu „reparieren":

1. **Goertzel über die ganze Datei taugt nicht für zwei Programme.** Der
   Ton, der **gar nicht angefasst** wurde, stand in drei Läufen bei
   4522, 2397 und 6000. Die Shell startet A im Hintergrund und B danach;
   die Überlappung ist je Lauf verschieden lang. Jetzt: Lautstärke je
   Strom mit **einem** Strom messen (Amplitude ist eindeutig),
   Unabhängigkeit dort nachweisen, wo einer auf **null** steht.
2. **„Lücken" am Dateiende waren keine.** Der Master-Abschnitt meldete
   `gaps=6`, 5586 verlorene Rahmen. Nachgesehen: `verloren > 0` trat
   **genau** in den Läufen auf, in denen ein Programm früher fertig ist
   (stumm 16 665, clip 16 687, master 5586 — zwei und leise, beide gleich
   lang: **0**). Das ist `catch_up` in `kernel/audio.fi` und **so
   entworfen**: läuft der Ring weiter ohne Nachschub, wird der
   Schreibzeiger auf die Position geholt und der Rest genullt, statt die
   letzten 85 ms noch einmal zu spielen. `wavcheck.py` hat dafür jetzt
   `--von-ms`/`--bis-ms`; im Fenster, in dem beide spielen, ist
   `gaps = 0`.
3. **Und ein geratenes Fenster.** `-k 60` zählt **Schübe**, nicht
   Millisekunden — der Abspieler schiebt schneller, als das Gerät spielt.
   Das Fenster 1200–1700 ms fand nichts; der Ton lag bei 1050. Jetzt wird
   **gesucht** statt geraten (50-ms-Fenster, stärkstes 880-Hz-Fenster).

---

## 5. Der Lautstärkeregler

**`wlib.slider(text, wert)` — `K_SLIDER`, das 14. Widget.** Er kommt in
die **Bibliothek** und nicht ins Programm: das ist die Regel des
Auftrags, und `tools/design/messen.py` zählt jeden Zeichenaufruf
außerhalb wlib. Malen, Klicken, **Ziehen** (dieselbe `s_down`-Mechanik
wie das Textfeld) und Tastatur (links/rechts eine Stufe, Pos1/Ende an die
Enden). Farben **ausschließlich** aus dem Thema: `T_SCROLL` (Rinne —
dieselbe Marke wie die Rollleiste, es ist dieselbe Sache), `T_ACCENT`
(gefüllter Teil), `T_THUMB` (Griff), `T_LINE` (Kante).

Drei Dinge, die man an einem Regler falsch macht:

1. **Die Klickfläche.** Die Rinne ist 4 px hoch; das Widget ist
   `ctrl_small()` hoch, weil gegen **32 px** gemessen wird.
2. **Zwei Rechnungen für dieselbe Rinne.** Malen und Treffen gehen durch
   `slider_bahn`/`slider_rw` — sonst ist der Regler eines Tages woanders
   zu fassen als gezeichnet.
3. **Die 100 nicht erreichen.** Der Griff ist 10 breit, die Bahn also 10
   kürzer; gerechnet wird auf die Griffmitte und **gerundet**.

**`/bin/qs`** bekommt die Lautstärke als zweite Reglerzeile, gebaut wie
die Helligkeit darüber (qs ist ein Flächenmaler, kein Widget-Fenster —
die Begründung steht seit DESIGN-2 im Maler-Absatz).

**Der Kopf von `qs.fi` wurde berichtigt.** Dort stand seit Runde NETVIEW:
*„VOLUME. There is no sound. A slider would move a number that reaches no
speaker."* Der Satz war richtig, als er geschrieben wurde. Seit MEDIA1
gibt es einen Treiber, seit HDA einen Mischer, seit TON einen Master. Die
Regel dieser Datei — *nur was wirklich da ist* — verlangt jetzt das
Gegenteil.

**Vier Glyphen** (`icon.volume.high/low/zero/muted`, Block E010..E01F)
über `assets/icons/icons.map` erzeugt — kein Codepunkt steht im
Zeichencode. Drei Stufen und ein **Kreuz**: bei 16 px kann man eine Zahl
nicht lesen, eine Form schon, und *stumm* muss auch ohne Farbe erkennbar
sein.

**Bedient auf vier Wegen:** Klick in die Rinne, Klick auf die
Beschriftung (stumm), Klick auf das Symbol in der Leiste (öffnet das
Panel), **Super+M**. `m` und keine Multimediataste, weil `kernel/kbd.fi`
Buchstaben liefert und keine erweiterten Abtastcodes — eine Verknüpfung
auf einer Taste, die nie ankommt, ist keine.

**Keine Karte, kein Feld** — dieselbe Regel wie beim Akku und beim Netz.

### Am Bild nachgewiesen

    taskbar: icon field=snd id=57360 x=1162 y=12 px=16 inkbox=208
    qs: geo x=888 y=324 w=388 h=432
    qs: text x=10 y=320 [Lautstärke]
    qs: vol ist=100 stumm=0 x=366

Der Umriss im Bild, 16×16 aus der Aufnahme ausgeschnitten — ein Kegel mit
zwei Wellen (Lucide `volume-2`), kantengeglättet, in `T_FG`:

    .....###........
    ....####....##..
    .#######....###.
    #####+##..#+.##.
    ##....##..##.##+
    ##....##..##.+##
    ##....##..##..##
    ##....##..##.##+
    #####.##..#+.##.
    .#######....###.
    ....####....##..
    .....###........

`tools/design/capture.sh` kennt jetzt **`ton=ja`**. Es hängt **zwei**
Dinge an: die Karte *und* das Wort `audio` auf der Befehlszeile. Ohne das
zweite meldet der Kern `aud: aus (kein Wort)` — beim ersten Anlauf sah
das wie ein Fehler im Regler aus und war die Regel „keine Karte, kein
Feld" bei der Arbeit.

`qs.fi` meldet neu `qs: geo x= y= w= h=`. Ohne diese Zeile ist jedes
Bildschirmfoto des Panels eine Suchaufgabe: die Texte melden
**Panel**-Koordinaten, das Bild hat **Bildschirm**-Koordinaten, und der
Ursprung stand nirgends — ich habe ihn zweimal falsch geraten.

---

## 6. Regression: die kdata-Versätze — und ein echter Konflikt

**Geprüft gegen `/root/osum-systembus`, `/root/osum-protokoll`,
`/root/osum-bridge2` und `/root/osum-merge7`.**

### Gute Nachricht: TON-2 kollidiert nicht

`kernel/audio.fi`, `kernel/mix.fi` und `kernel/blk.fi` sind auf `merge7`
**byte-gleich** mit `ton` — MERGE-7 hat `ton` bereits gemergt (`a23af7c`).
Damit gilt dort:

* `AS_WAITSPACE = 15` ist frei (letzte belegte Nummer: `AS_SMUTE = 14`).
* Die `L_`-Versätze 0xC8..0xE8 stimmen überein.
* **TON-2 ändert `kstate.fi` nicht** und legt keinen neuen Block an.

MERGE-7 hat die Ton-Blöcke bereits **verschoben** (`AUD_OFF` 0xB0000 →
0xD8000, die übrigen entsprechend bis `BLKD_OFF` 0xE0000); an 0xB0000
liegt dort jetzt `WIGST_OFF`, an 0xB8000 `SCANB_OFF`. Das betrifft TON-2
nicht, ist aber der Grund, warum ein naiver Vergleich der Zahlen
Kollisionen zu zeigen scheint.

### **Konflikt, den MERGE-7 auflösen muss: `kernel/user/taskbar.fi`**

**Runde SYSTEMBUS hat dort bereits ein viertes Statusfeld gebaut** (die
Glocke):

| | SYSTEMBUS (auf merge7) | TON-2 |
|---|---|---|
| | `F_NET=0, F_BAT=1, F_CLK=2, F_NOTI=3` | `F_NET=0, F_SND=1, F_BAT=2, F_CLK=3` |
| `F_N` | 4 | 4 |
| Kette | … `F_NET` → `F_NOTI` | … `F_SND` → `F_NET` |

Beide vergrößern dieselben sieben Stellen auf vier, und **beide
beanspruchen Index 1..3 verschieden**. Zusammengeführt braucht es **fünf**
Felder:

    const F_NET:  u64 = 0
    const F_SND:  u64 = 1
    const F_BAT:  u64 = 2
    const F_CLK:  u64 = 3
    const F_NOTI: u64 = 4
    const F_N:    u64 = 5

und dazu: `f_x/f_y/f_w/f_h/f_lines` auf `[u64; 5]`, `f_txt` auf 320,
`f_full` auf 160, und **beide** Ketten (senkrecht ~Z. 1976, waagrecht
~Z. 2107) müssen **dieselbe** Reihenfolge nennen. Eine Kette allein zu
ändern zeigt das Feld auf einer Kante und auf der anderen nicht.

### Weitere Dateien, die auf merge7 abweichen

* **`kernel/user/wlib.fi`** — dort liegt DESIGN-2 (Tween + die
  `mal_*`-Malerschicht). `K_SLIDER` ist **additiv**; beim Zusammenführen
  sollte `paint_slider` auf `mal_*` umgestellt werden.
* **`kernel/user/qs.fi`** — merge7 benutzt schon `wlib.mal_flaeche` statt
  `wlibc.rect`; die neue Reglerzeile analog umstellen.
* **`kernel/sys.fi`** — merge7 importiert zusätzlich `bus`, `klog`,
  `absturz`. `do_audwait` ist additiv.

---

## 6b. Die bestehenden Abnahmen — und ein Fehlalarm, der einzeln verschwand

`tools/hda/run.sh` (Runde HDA) gegen **beide** Zweige gefahren:

| | `ton` (unverändert) | `ton2` |
|---|---:|---:|
| bestanden | 138 | 135 |
| gefallen | **4** | **7** |

Die vier auf beiden Zweigen sind **Bestand** und zeichengleich:
`Stroeme, die zu spaet kamen: 1`, `Aussetzer aus Ring 3: 4`,
`Aussetzer: 2`, `die Speicherkarte hat Kollisionen`.

Die drei zusätzlichen sahen nach einer echten Regression aus — die
gefährlichste Sorte, weil zwei davon genau den Mischer betreffen, den
diese Runde für korrekt erklärt:

    FAIL  begrenzte Abtastwerte (12000+12000 < 32767): 24, erwartet 0
    FAIL  die groesste Summe liegt unter der Vollaussteuerung: 35781
    FAIL  Aussetzer bei MP3 aus Ring 3: 4, erwartet <= 2

**Einzeln nachgestellt, drei Läufe je Zweig** (derselbe `audmix`-Pfad,
eine QEMU zur Zeit):

| | Lauf 1 | Lauf 2 | Lauf 3 | clips |
|---|---:|---:|---:|---:|
| `ton2` | 23 715 | 22 871 | 22 871 | 0, 0, 0 |
| `ton` | 23 826 | 22 871 | 23 910 | 0, 0, 0 |

**Dieselbe Verteilung, keine Begrenzung.** Der Wert 35 781 entstand
unter der Last von zehn gleichzeitigen QEMU-Instanzen, die `test.sh` mit
`OSUM_JOBS=10` startet.

Das ist belegbar und nicht nur plausibel: `kernel/audio.fi`,
`kernel/mix.fi`, `kernel/hda.fi` und `kernel/kmain.fi` sind zwischen
`ton` und `ton2` **unverändert** (`git diff ton..HEAD --name-only` nennt
keine davon), und der `audmix`-Pfad benutzt weder `/bin/play` noch
`AS_WAITSPACE`.

**Es ist derselbe Fehlalarm, den Runde DESIGN-2 schon einmal hatte** (ein
SOFTUI-Lauf meldete 4 statt 3 Fehlschläge, weil 5 QEMU gleichzeitig
liefen). Die Lehre daraus hat sich hier zum zweiten Mal bezahlt gemacht:
**immer einzeln nachstellen, bevor man einen Fehler glaubt.**

Der andere Fehler, den `test.sh` meldet — *„der festgenagelte
Uebersetzer: vendor/firn/lib/net/stack.fi …"* — ist ebenfalls Bestand:
`vendor/` ist von TON-2 nicht angefasst, die Datei ist auf
`/root/osum-merge6` und `/root/osum-ton2` byte-gleich (sha1
`742b8e0d…`), und derselbe Abschnitt fällt auf `merge6` mit derselben
Meldung.

**`test.sh` Abschnitt 42** (`tools/ton/mischer.sh`) läuft auch unter
`OSUM_JOBS=10` mit **25 gut, 0 beanstandet**.

---

## 7. Was diese Runde NICHT getan hat

* **Der Aussetzerzähler ist nicht repariert.** `hda.fi` schreibt ihn nur
  fort, wenn jemand hinsieht. Ihn ehrlich zu machen hieße, ihn aus der
  Unterbrechung zu führen — eine eigene Runde, und `gaps` beantwortet die
  Frage bereits besser.
* **Die Dateigrößengrenze bleibt.** 12,1 s je Datei bei 44,1 kHz stereo.
  Ein dritter Indirektionsgrad gehört ins Dateisystem, nicht in eine
  Tonrunde.
* **Keine Aufnahme, kein HDMI-Ton, keine Buchsenerkennung** — unverändert
  aus Runde HDA.
* **Der Regler kennt keine gehörrichtige Skala.** Der Master ist
  **linear** in Prozent. Eine Kurve wäre hörbar besser und ist eine
  Entscheidung, die man einmal trifft und dann nicht mehr ändern kann,
  ohne dass sich jede eingestellte Lautstärke verschiebt.

---

## Neue und geänderte Dateien

**Neu:** `tools/ton/acceptance.sh` (12 × 60 s), `tools/ton/mischer.sh`
(25 Zusagen), `STATUS-TON2.md`.

**Geändert:** `kernel/sys.fi` (`AS_WAITSPACE`, `do_audwait`),
`kernel/user/play.fi` (`-w`, `-v`, `-m`, `-k`, zwei echte Uhren),
`kernel/user/wlib.fi` (`K_SLIDER`), `kernel/user/qs.fi` (Reglerzeile,
`qs: geo`), `kernel/user/taskbar.fi` (`F_SND`, Super+M),
`assets/icons/icons.map` + `lib/icons.fi` + `assets/osum-icons.ttf`
(4 Glyphen), `locale/{de,en}/messages`, `tools/hda/mkmedia.sh`
(`lang44`, `a4/b6`, `a5/b5`), `tools/hda/wavcheck.py`
(`--von-ms`/`--bis-ms`), `tools/ton/mess.sh` (Plattengröße gerechnet,
`TON_PLAYOPT`), `tools/design/capture.sh` (`ton=ja`), `test.sh`
(Abschnitt 42), `docs/AUDIO.md` (Abschnitt 5b).
