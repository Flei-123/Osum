# STATUS -- Runde UHRWERK

Zweig `uhrwerk`, abgezweigt von `hidweg` (1493451). **NICHT gepusht,
NICHT nach main/hidweg gemergt.** Arbeitsbaum `/root/osum-blechhid`.
Commit **9ccf87e**.

Justins Befund, auf echtem Blech fotografiert (Ryzen, 3440x1440,
UEFI/Limine): *die Uhr in der Taskleiste steht. Faehrt die Maus ueber
die Ziffern, springt sie auf die richtige Zeit. Maus woanders bewegen
reicht nicht.*

Antwort in einem Satz: **es war ein Zeichenfehler und kein
Ablaufplaner-Fehler -- die Leiste schob ein Band von 80 Bildzeilen
durch eine Zeichenflaeche, die auf 3440 Bildpunkten Breite nur 76
traegt, und verlor dabei JEDEN EINZELNEN Anstrich vollstaendig.**

---

## 1. Zuerst gemessen -- und die Vermutung fiel

Der Auftrag nannte drei Verdaechtige: der Zeitgeber schlaegt nicht, die
Taskleiste wird nie geweckt, oder `wm.compose` kommt ohne Eingabe nicht
durch. **Keiner davon war es.** Ein Lauf von 90 Sekunden ohne jede
Eingabe (QEMU/KVM, `-cpu host -smp 4`, echte 3440x1440 ueber `fbres=`):

| | gemessen | Soll | |
| --- | --- | --- | --- |
| `PREEMPT` | **1** | 1 | Verdraengung ist an |
| `HZ` | **100** | 100 | der Zeitgeber schlaegt |
| `TICKS` | **+100/s** | 100/s | die Uhr des Kerns laeuft |
| `LOOP` | **+699** | >0 | die Schreibtischschleife dreht |
| `wm.composites` | **+294 (4,32/s)** | >0 | **compose laeuft OHNE Eingabe** |
| `taskbar round` | **+2600 (88/s)** | ~40/s | die Leiste wird geweckt |
| `status_build` true | **+100** | ~1/s | sie merkt den Sekundenwechsel |

Und die Leiste zaehlte in ihrem eigenen Puffer korrekt hoch:

    taskbar: text clock x=3151 ... t=21:54:18 05.09.26
    taskbar: text clock x=3151 ... t=21:54:19 05.09.26
    taskbar: text clock x=3151 ... t=21:54:20 05.09.26

Alles gruen. Und das Bild stand trotzdem still. Der Fehler sitzt hinter
all dem.

### Die Zahl, die ihn zeigt

`wig.blit` GIBT ZURUECK, wie viele Bildpunkte es hinuebergebracht hat.
Bis zu dieser Runde hat das niemand angesehen (`let _p: u64 = ...`).
Angesehen sagt es:

| | vorher | nachher |
| --- | --- | --- |
| `px` (wirklich hinueber) | **0** | 27 244 800 |
| `soll` (haette hinueber sollen) | 28 070 400 | 27 795 200 |
| `null` (Pushs, die NICHTS brachten) | **102** | **0** |

**Jeder einzelne Push brachte null Bildpunkte hinueber.**

### Wo genau das Bild aufhoert

Ueber fuenf Bildschirmfotos ohne Eingabe, Zeile fuer Zeile verglichen:

    letzte Bildzeile, die sich je aendert:  1339
    die Taskleiste faengt an bei:           1360

Zwischen 1340 und 1439 bewegte sich in keinem Bild ein einziger
Bildpunkt. Die Leiste war auf dem Schirm -- sie war nur die vom
allerersten Anstrich.

---

## 2. Die Ursache

Die Zeichenflaeche von wlib ist ein **Streifen mit festem Platzbedarf**
(`SURF_BUDGET` = 1 MiB, `kernel/user/wlibc.fi`). Sie ist so breit wie
der Schirm; wie viele BILDZEILEN sie traegt, faellt aus der Breite:

| Schirmbreite | 1920 | 2560 | **3440** | 3840 |
| --- | --- | --- | --- | --- |
| `surf_rows` | 136 | 102 | **76** | 68 |

Die Taskleiste malte in einem Band von **fest verdrahteten `BAND` = 80**
Zeilen (`height=40` bei Skala 2). Bis 2560 passt das. Auf 3440 nicht.

Die Kette, Glied fuer Glied:

1. `taskbar.paint` schiebt ein Band von 80 Zeilen: `wlibc.push(..., 80)`.
2. `wlibc.push` rechnet die Quelladresse aus und ruft `WIG_BLIT` --
   **mit der Hoehe 80**, obwohl nur 76 Zeilen abgebildet sind.
3. `wig.blit` liest zeilenweise ueber `fetch`.
4. `fetch` fragt `proc.user_ok(src, len)`. Die vier Zeilen hinter der
   Abbildung gehoeren dem Prozess **nicht**.
5. `fetch` gibt `false`, `blit` bricht ab und liefert **0**.
6. Das `wm.damage(...)` **am Ende von `blit`** wird damit **nie
   erreicht**.

Ohne `damage` wird die Stelle nie schmutzig gemeldet, ohne schmutzige
Stelle setzt `compose` sie nie neu zusammen -- und auf dem Schirm bleibt
der erste Anstrich stehen.

**Warum die Maus half:** bewegt sich der Zeiger ueber die Leiste, malt
der FENSTERSERVER den Bereich aus dem Eingabepfad neu (Zeiger, eigenes
Damage) und schiebt dabei den Fensterpuffer mit -- in dem die neue
Uhrzeit laengst steht. Deshalb sprang die Uhr genau dort und nur dort.

### Warum es 25 Runden lang niemand gesehen hat

Der Fehler braucht einen Schirm ab etwa **2600 Bildpunkten Breite**. Die
Testlaeufe fahren 1280x800. Gegenprobe mit **demselben alten Abbild**:

| altes Abbild auf | `null` | `px` | Uhr |
| --- | --- | --- | --- |
| 1920x1080 | 0 | 1 152 000 = `soll` | **laeuft** |
| 3440x1440 | 16 | **0** | **steht** |

---

## 3. Was geaendert wurde

Zwei Stellen, **beide in Ring 3**. Am Kern aendert sich keine Zeile --
das Abbild ist Oktett fuer Oktett so gross wie vorher (4 127 516).

| Datei:Zeile | was |
| --- | --- |
| `kernel/user/taskbar.fi:3052` | `paint` nimmt die Bandhoehe als `min(BAND, wlibc.surf_rows())` statt fest 80. Auf 3440 sind das **zwei** Baender (76+4), auf 2560 und darunter unveraendert **eines** -- dort ist `surf_rows` groesser als 80. |
| `kernel/user/wlibc.fi:1352` | `push` klemmt die Hoehe zusaetzlich auf `s_srows` und liest damit **nie** ueber die Abbildung hinaus. Der Riegel fuer jede kuenftige Anwendung, die dasselbe falsch macht: ein stiller Totalverlust darf nicht wieder moeglich sein. |

Dazu die Zaehler, die den Befund messbar halten (`ub_px`, `ub_soll`,
`ub_null`, `ub_sb`, `ub_sbt`, `ub_round`), gemeldet **im Pulstakt** alle
200 Runden -- nicht in jeder Runde, siehe der bekannte Flut-Fehler.

**Andere Anwendungen geprueft:** `wlib.fi` und `desktop.fi` rechnen
bereits mit `surf_rows()`. `qs.fi` hat `BAND = 64` und eine feste
Breite -- passt auf jeder Aufloesung. Die Taskleiste war die einzige
Stelle mit der fest verdrahteten Zahl.

---

## 4. Abnahme

Alles ohne jede Eingabe gemessen (`tools/uhrwerk/`).

| Zusage | Zahl |
| --- | --- |
| Uhrstreifen aendert sich (3440x1440) | **4 von 4** Abstaenden (vorher **0 von 5**) |
| letzte Zeile, die sich bewegt | **1410** (vorher 1339 -- ueber der Leiste) |
| Pushs verloren | **0** (vorher 102) |
| `px == soll` | ja, in allen Laeufen |
| `-smp 1`, 5 Laeufe | 0 Panics, `null=0`, `px==soll` ueberall |
| `-smp 4`, 5 Laeufe | 0 Panics, `null=0`, `px==soll` ueberall |
| Eingabe lebt noch | `bew=8 kl=1 ta=2`, und mit Eingabe `null=0` |
| Kosten | 580 665 Bildpunkte/s = **0,117 Vollbilder/s**; je Bildpaar 0,27--0,31 % des Schirms -- **kein** Vollbild-Neuanstrich |
| 1920x1080 | `null=0`, Uhr laeuft |
| 2560x1440 | `null=0`, Uhr laeuft |
| 3840x2160 (68 Zeilen, haertester Fall) | `null=0`, Uhr laeuft, 3 von 3 |

**Abnahmelauf: 8 ok, 0 NEIN.**

Und mit den Dateien, die WIRKLICH auf dem Stick liegen (`osum.mb` +
`root.img` aus dem fertigen Abbild), bei 3440x1440: Uhr laeuft 4 von 4,
`null=0`, `px == soll`.

---

## 5. Das Abbild

    /tmp/uhr-stick/orientos-usb-20260905-9ccf87e.img
    123 731 968 Oktette (118 MiB), GPT, EFI 96 MiB + Wurzel 20 MiB
    sha256 e31e31ce4b15e4d92e2fcdc18295c6cb2682eda55c9beb53452f2df5ae214787

    sudo dd if=orientos-usb-20260905-9ccf87e.img of=/dev/sdX bs=4M conv=fsync status=progress

### Was Justin fotografieren soll

**Die Uhr rechts unten in der Taskleiste, zweimal im Abstand von etwa
einer Minute -- ohne die Maus anzufassen.** Das ist die ganze Probe: die
Minute muss weitergesprungen sein, ohne dass er den Zeiger bewegt hat.

Der Stick-Eintrag `clock_seconds=1` laesst sie sekuendlich ticken, also
reicht auch ein Abstand von ein paar Sekunden.

Zur Sicherheit dazu **Tafelzeile 8**:

    8 TAKT  IRQ <n> MAL <n> LOOP <n> PRE 1 HZ 100

`PRE 1` und `HZ 100` belegen, dass der Zeitgeber und die Verdraengung
laufen. Standen die schon vorher richtig -- diese Runde hat sie nicht
angefasst --, aber sie schliessen den Ablaufplaner als Ursache aus, falls
auf seinem Brett doch etwas anderes klemmt.

---

## 6. Werkzeuge

| Datei | was |
| --- | --- |
| `tools/uhrwerk/bauen.sh` | Kern + Wurzelabbild mit `clock_seconds=1` |
| `tools/uhrwerk/uhrprobe.sh` | fotografiert mehrmals **ohne Eingabe** und vergleicht den Uhrstreifen; sagt "DIE UHR STEHT" oder "LAEUFT" |
| `tools/uhrwerk/messen.sh` | die Zahlen aus der seriellen Leitung (composes, TICKS, LOOP, PRE, HZ, die Zaehler der Leiste) |
| `tools/uhrwerk/acceptance.sh` | 5 Laeufe je Kernzahl + Eingabe-Gegenprobe |

`UHR_W`/`UHR_H` in der Umgebung setzen die Aufloesung (Vorgabe
3440x1440).

---

## 7. Was NICHT gruen ist

`tools/desktop/run.sh` meldet Fehlschlaege -- **aber schon auf dem
unveraenderten Stand 1493451**, also nicht aus dieser Runde. Gemessen,
beide Laeufe nebeneinander, Abschnitt 3, Kante `bottom`:

| | Basis 1493451 | Zweig `uhrwerk` |
| --- | --- | --- |
| FAIL im Block `[bottom]` | **5** | **5** |

Dieselben fuenf, an denselben Stellen, mit demselben Wortlaut. Der
Laeufer rechnet mit 800x600 und bekommt 1280x800:

    the bar is at (0, 772, 1280, 28), expected (0, 572, 800, 28)

Daran haengen die uebrigen vier (der Text steht dann nicht dort, wo der
Laeufer nachsieht). Das ist ein eigener Befund -- vermutlich seit der
Runde, die die Vorgabeaufloesung der Laeufe von 800x600 auf 1280x800
gezogen hat -- und gehoert in eine eigene Runde. Diese Runde hat ihn
weder verursacht noch behoben.

Ausserdem offen, aber ausserhalb dieses Auftrags: das Bootmenue des
Sticks setzt unter OVMF die Aufloesung nicht durch (`resolution:
3840x2160` im Eintrag, gestartet wird trotzdem 1280x800, `src=mb`). Der
Fehler dieser Runde ist auf dem Stick trotzdem nachweislich weg -- mit
den Dateien AUS dem fertigen Abbild und `fbres=3440x1440` gemessen.
