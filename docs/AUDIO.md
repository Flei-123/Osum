<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Ton in Osum — die Grenze, der Treiber, der Mischer

Stand: Runde HDA, 30.08.2026 — ergänzt um Runde TON-2, 06.09.2026 (Abschnitt 5b).
Treiber: `kernel/hda.fi` (Intel HD-Audio) · `kernel/ac97.fi` (AC97)
Schicht: `kernel/audio.fi` · Mischer: `kernel/mix.fi`
Aufrufe: `kernel/sys.fi` 1850–1854 (Runde TON: umnummeriert, 1840 ist seit Runde WERKZEUGE `SYS_OSUM_CPUSTAT`) · Ring 3: `kernel/user/play.fi`
Abnahme: `tools/hda/run.sh`

Diese Datei löst die gleichnamige aus Runde MEDIA1 ab. Was dort stand, gilt
weiter; was diese Runde daran geändert hat, steht in Abschnitt 1.

---

## 0. Die Probe auf die Rechnung von MEDIA1

Runde MEDIA1 hat eine Grenze gezogen und behauptet:

> „der HDA-Treiber der späteren Runde bedient GENAU diese Schnittstelle und
> KEINE Zeile darüber ändert sich.“

Diese Runde hat den Treiber gebaut. **Die Behauptung stimmt zu zwölf
Zwölfteln, und eine dreizehnte Funktion ist dazugekommen.** Das ist ein
gutes Ergebnis für eine Grenze, die ohne den zweiten Treiber entworfen
wurde — und die eine Ausnahme hat einen handfesten Grund, keinen
Entwurfsfehler:

| | AC97 | Intel HD-Audio |
|---|---|---|
| Der DMA am Ende der Daten | **hält an** (CIV erreicht LVI) | **läuft im Kreis weiter** |
| „Das Stück ist zu Ende“ | ein Zustand der Hardware | eine **Information**, die nur der Aufrufer hat |

Deshalb `hw_drain_mark()`. Ohne sie zählt der Aussetzerzähler nach dem
letzten Rahmen jedes Stücks weiter, und „Aussetzer je Minute“ wäre eine
Zahl über die Zahl der abgespielten Dateien.

---

## 1. Die Grenze: dreizehn Funktionen, ein Block, eine Datei

In `kernel/audio.fi` steht **ein einziger Block**, der unter die Grenze
greift:

| Funktion | Was sie liefert | AC97 | HD-Audio |
|---|---|---|---|
| `hw_ready` | gibt es das Gerät | `S_READY` | `S_READY` |
| `hw_ring` | Adresse des DMA-Ringpuffers | 4 Rahmen aus `mem.frame_run` | dieselben |
| `hw_ring_frames` / `hw_entries` / `hw_entry_frames` | die Geometrie | 32 × 128 | 32 × 128 |
| `hw_submit` | einen vollen Eintrag übergeben | BDL schreiben, **LVI nachziehen** | nur Buch führen (die Liste steht schon) |
| `hw_start` / `hw_stop` | Lauf an, Lauf aus | `PO_CR` Bit 0 | `SDnCTL` RUN |
| `hw_position` | **abgespielte Rahmen, monoton** | `CIV`·128 + (128−`PICB`/2) | **DMA-Positionspuffer**, LPIB als Rückfall |
| `hw_volume` | Lautstärke in Prozent | Register 0x02/0x18 | `SET_AMP_GAIN_MUTE` am Wandler |
| `hw_running` | läuft der DMA | `S_RUNNING` | `SDnCTL` RUN |
| `hw_rate` / `hw_set_rate` | Abtastrate | VRA (Register 0x2C) | `SDnFMT` Bit 14 |
| **`hw_drain_mark`** | „ab hier kommt nichts mehr“ | tut nichts | hört auf, Aussetzer zu zählen |

**Alles andere steht über der Grenze und wird nicht zweimal gebaut:**
Format, Ringbuchführung, Auffüllen mit Stille, **Vorausnullen**,
**Aufholen nach einem Aussetzer**, Aussetzerzählung, Lautstärkepolitik,
Tonerzeugung, Systemklänge, der Mischer, die fünf Systemaufrufe.

---

## 2. Was HD-Audio anders macht — die vier Fallen

### 2.1 Der Befehlsring braucht BEIDE Bits in RIRBCTL

`RIRBCTL` Bit 1 ist der DMA des Antwortrings, **Bit 0 („Response
Interrupt Control“) entscheidet, ob das Zustandsbit `RIRBSTS.RINTFL`
überhaupt gesetzt wird** — und über dieses Bit läuft die Freigabe des
Befehlsrings. Ohne Bit 0: der erste Befehl geht durch, der zweite nie
(gemessen: CORBWP 2, CORBRP 1).

### 2.2 Der Positionspuffer wird JE STROM geschrieben

`DPLBASE`/`DPUBASE` zeigen auf einen Block; die Position **dieses**
Stroms steht bei `Stromnummer · 8`. Der erste Ausgabestrom hat die
Nummer `ISS` (alle Eingabeströme liegen davor) — bei QEMU 4, also
Versatz 32. Wer bei 0 liest, liest den Eingabestrom, und der läuft nicht.

### 2.3 Die Uhr darf NICHT an „geschrieben“ geklemmt werden

Bei AC97 kann der Regler den Schreibzeiger nicht überholen. Bei HD-Audio
kann er. Klemmt man `gespielt` an `geschrieben`, rechnet die Schicht
ihren freien Platz falsch und schreibt **hinter** den Lesezeiger des
Reglers. Gemessen: 48000 Rahmen geschrieben, 48000 „gespielt“, null
Aussetzer gemeldet — und 9673 Rahmen Ton zwischen 43361 Rahmen Stille in
der Datei.

### 2.4 Der Ring muss ausgenullt werden — an drei Stellen

| wann | Funktion | warum |
|---|---|---|
| nach jedem Schreiben | `zero_ahead` | ein Unterlauf soll STILLE sein und nicht der vorige Umlauf |
| nach einem Aussetzer | `catch_up` → `zero_all` | der Schreibzeiger springt vor und markiert Altes als „geschrieben“ |
| beim Schließen | `close` → `zero_all` | zwischen dem letzten Rahmen und dem `stop` liegen Zeitscheiben |

---

## 3. Der Weg zum Lautsprecher

```
Wurzelknoten 0 ──Param 0x04──▶ Funktionsgruppen
                 Param 0x05──▶ Typ 1 = Audio Function Group
      AFG ───────Param 0x04──▶ Knoten (bei QEMU 2, bei einem ALC892 36)
  je Knoten ─────Param 0x09──▶ Art (Wandler / Mischer / Wähler / Buchse)
                 Param 0x0C──▶ Buchsen-Fähigkeiten
                 Verb 0xF1C──▶ BUCHSENBELEGUNG  ← hier steht, was hörbar ist
                 Verb 0xF02──▶ Verbindungsliste (mit Bereichen!)
```

Die Bewertung der Buchsen (`hda.pin_score`):

* Anschluss „nicht vorhanden“ (Bits 30–31 = 1) → **ausgeschlossen**
* digitale Knoten (AWCAP Bit 9) → **übersprungen** (kein HDMI in dieser Runde)
* Line Out (400) > Lautsprecher (380) > Kopfhörer (360) > alles andere (1)
* bei gleicher Art gewinnt die kleinere Sequenznummer

Danach: bounded DFS über höchstens vier Knoten (Buchse → Mischer → Wähler
→ Wandler). **Reicht die beste Buchse nicht an einen Wandler, wird die
nächstbeste genommen** — ein Treiber, der nur die beste probiert, ist auf
jedem zweiten Brett still.

Eingeschaltet wird dann: Power D0 je Knoten · Ausgangsverstärker auf den
**Nullpunkt** (0 dB, nicht auf das Maximum) · Eingangsverstärker der
Mischer **nur am benutzten Index**, alle anderen stumm · Pin-Control
OUT (+ HP-Treiber, wenn die Buchse ihn hat) · **EAPD** — das eine Bit,
an dem „unter Linux kein Ton auf dem Laptop“ meistens hängt.

---

## 4. Der Mischer

Vier Ströme zu je 64 KiB (341 ms bei 48 kHz), Summe mit **Sättigung**
(nicht mit Division durch die Zahl der Ströme — das ließe die Lautstärke
springen, sobald ein Systemklang anfängt), Zwischenpuffer mit **64 Bit je
Abtastwert** (vier Ströme zu 32768 sind 131072 und passen in 16 Bit
nicht), **ein** Begrenzungsschritt am Ende, Begrenzungen werden **gezählt**.

Drei Regeln, jede mit einer Messung dahinter:

1. **Im Regelfall das Minimum** über alle Ströme — wer nichts hat, hält
   die anderen kurz auf.
2. **In der Notlage das Maximum** (Ringvorrat < 8 Einträge = 21 ms) —
   dann bekommt der Langsame eine Lücke und die anderen laufen weiter.
3. **Aufhalten darf nur, wer in den letzten 5 ms geschrieben hat.** Ohne
   diese Regel verklemmt sich (1), sobald ein Programm fertig ist.

Die Ratenumrechnung ist **linear** und greift nur, wenn ein Strom eine
andere Rate hat als das Gerät (der erste Strom setzt die Gerätrate). Für
44100 gegen 48000 liegt der Fehler bei rund −30 dB in den oberen Oktaven.
Ein anständiger Filter wäre eine eigene Runde; das steht hier, statt es
zu verschweigen.

---

## 5. Die Puffer und die Verzögerung

| Stufe | Größe | Zeit bei 48 kHz | Begründung |
|---|---|---|---|
| Eintrag der Deskriptorliste | 128 Rahmen | 2,67 ms | feiner als der Zeitgeber (10 ms) schlägt |
| Geräte-Ring | 32 Einträge = 4096 Rahmen | **85,3 ms** | > 2 Zeitgebermarken, > QEMUs Mischerpuffer (46 ms), < hörbare Verzögerung |
| Vorlauf vor dem Anfahren | 24 Einträge = 3072 | 64 ms | **muss über der Ausgabepufferung der Hardware liegen** — gemessen in MEDIA1: mit 8 Einträgen 24 Aussetzer bei 24 Schreibvorgängen |
| Strompuffer je Programm (Mischerweg) | 16384 Rahmen | **341 ms** | die Zeit, die ein Prozess wegbleiben darf |
| Mischschub | 256 Rahmen | 5,33 ms | vom Platz im Zwischenpuffer bestimmt |

**Ausgabelatenz Einstromweg:** 85,3 ms (nur der Ring).
**Ausgabelatenz Mischerweg:** bis zu 426 ms, wenn das Programm seinen
Puffer vollschreibt. Wer weniger will, nimmt den Einstromweg
(`/bin/play -1`) — deshalb gibt es ihn.

---

## 5b. Runde TON-2: der Leerlauf, der Mischer von aussen, der Regler

Stand: 06.09.2026, Zweig `ton2`.

### Der Abspieler drehte leer

Runde TON hat die Aussetzer aus der **Platte** geholt (4982 ms Lesen auf
84 ms, siehe `kernel/blk.fi`). Übrig blieben zwei, und die kamen aus dem
Abspieler selbst.

Gemessen für **eine Sekunde** Ton (`/ton.wav`, `-smp 4`, IDE):

| | vorher | nachher |
|---|---:|---:|
| Wartedrehungen | 139 290 | **26** |
| Systemaufrufe gesamt | 418 952 | **963** |
| Schübe | 139 713 | **126** |
| Lücken in der Ausgabedatei | 0 | **0** |

Für 46 540 Rahmen braucht es rund **45** echte Schübe. Gezählt wurden
139 290 Wartedrehungen zu je **zwei** Systemaufrufen (`A_PLAYED` +
`SYS_YIELD`) — 278 580 von 418 952 Aufrufen, also **zwei Drittel aller
Systemaufrufe**, und keiner davon hat einen Rahmen bewegt.

`rechnen_us` (436 ms) war dabei eine **Falle im eigenen Messgerät**: es
wurde in `play.fi` als *Differenz* gebildet (gesamt − lesen − senden) und
war damit kein Maß für Rechenzeit, sondern ein Sammelbecken für alles,
was sonst nirgends gezählt wurde — also für genau diesen Leerlauf. Jetzt
misst eine Uhr die Aufbereitung (`aufbereit_us`) und eine zweite die
Wartezeit (`warten_us`); zusammen erklären sie `ring3_us` **ohne
Restgröße**.

### `AS_WAITSPACE` (audset 15)

Der Ausweg `sleep_ms(1)` geht in diesem Kernel **nicht**: `do_nanosleep`
rechnet in ganzen Zeitgeberschlägen und rundet **auf** (`TICK_HZ = 100`),
die kürzeste Bitte schläft also volle 10 ms. Runde TON hat das gemessen
(158 Aussetzer) und deshalb bewusst den Spin behalten.

Also wandert das Warten dahin, wo es hingehört — `mix.fi` sagt es selbst
seit Runde HDA: *„das gehört in den Systemaufruf, wo es einen Prozess
gibt, den man schlafen legen kann.“*

    osum_audset(AS_WAITSPACE, ((Kennung + 1) << 8) | Rahmen/16)
        -> Rahmen, die jetzt Platz haben

Der Kern pumpt den Mischer, rechnet aus Füllstand und Abtastrate die
Wartezeit und legt den Prozess genau so lange schlafen.

**Drei Fallen, alle gemessen:**

1. **Die Sperre.** `audio.hold` ist eine Drehsperre **mit
   abgeschalteten Unterbrechungen**. Wer damit schlafen geht, hält den
   Rechner an. Also: unter der Sperre *rechnen*, ohne sie *schlafen*,
   danach neu nachsehen.
2. **Die Kennung.** `mix.open` gibt für den ersten Strom die `0` zurück
   — dieselbe `0`, die „Einstromweg“ heißt. Deshalb um eins verschoben.
3. **Auf einen ganzen Schlag aufrunden**, sobald überhaupt gewartet
   wird. Rahmengenau gerechnet wird `us / 10000` fast immer null, es
   bleibt beim `yield`, und der Aufruf kommt nach ~724 µs zurück:
   74 361 Drehungen in 60 s statt 2 604.

**Ein negatives Ergebnis, das im Code steht:** das `SYS_YIELD` nach jedem
Schub sieht mit `AS_WAITSPACE` überflüssig aus. Entfernen ergab
Aussetzer 1 → 4 und Systemaufrufe 2095 → 3594. `AS_WAITSPACE` läuft
**nur bei vollem Ring**; solange Platz ist, läuft die Schleife durch,
ohne je in den Kern zu gehen. Die Zeile bleibt.

### Die 60-Sekunden-Abnahme

`bash tools/audio/acceptance.sh` — zwölf Läufe: `-smp 1` und `-smp 4`, Quelle
`ide` und `ram`, je **drei** Mal. Drei und nicht einer, weil der
Aussetzerzähler (`hda.fi`, `S_UNDER`) nur fortgeschrieben wird, wenn
jemand die Position abfragt, und über eine Sekunde bei gleichem Code
zwischen 1 und 5 schwankte. **Die Zahl, die zählt, ist `gaps`** — echte
Nullstrecken in dem, was das Gerät ausgegeben hat.

Sechzig Sekunden gehen **nicht als eine Datei**: ein Inode fasst hier
2 134 016 Oktette (8 direkte, 64 einfach und 4096 doppelt indirekte
Blöcke, `kernel/fs.fi`) = **12,1 s** bei 44 100 Hz stereo. Deshalb
`/bin/play -w N` — dieselbe Datei N mal an **einem offenen Strom**; die
Nähte dazwischen sind zusätzlich eine Prüfung, die eine lange Datei gar
nicht hätte.

### Der Mischer, von Ring 3 aus

`bash tools/audio/mischer.sh`. `tools/hda/run.sh` Abschnitt 5 prüft den
Mischer **von innen** (Kernel-Prüfpfad `audmix`, zwei erfundene Ströme);
das ist eine Aussage über die Additionsschleife und keine darüber, ob
zwei **Programme** nebeneinander spielen. Diese Abnahme fragt es von
außen: zweimal `/bin/play` durch die Shell, jeder Ton einzeln per
Goertzel nachgewiesen.

Neue Optionen: `/bin/play -v <0..100>` (Lautstärke **dieses** Stroms,
`AS_SVOL`), `-m <0..100>` (Master, `AS_VOLUME`), `-w <N>` (Wiederholungen).

**Eine Korrektur am Messgerät, die hierher gehört:** der erste Anlauf
stellte einen von *zwei gleichzeitigen* Strömen leiser und verglich beide
Leistungen mit dem Lauf davor. Das war falsch — der Ton, der **gar nicht
angefasst** wurde, stand in drei Läufen bei 4522, 2397 und 6000. Grund:
die Shell startet A im Hintergrund und B danach, die beiden überlappen
sich je Lauf verschieden lang, und eine Goertzel-Auswertung über die
ganze Datei misst dann die **Überlappung** und nicht die Lautstärke. Die
Lautstärke je Strom wird jetzt mit **einem** Strom gemessen, wo die
Amplitude eindeutig ist; die Unabhängigkeit zweier Ströme weist der
Abschnitt mit `-v 0` nach, wo ein Ton **ganz** fehlt.

### Der Lautstärkeregler

* `wlib.slider(text, wert)` — **K_SLIDER**, 0..100, mit Ziehen und
  Tastatur (links/rechts, Pos1/Ende). Er kommt in die **Bibliothek**,
  nicht ins Programm: ein Regler, den ein Programm selbst malt, ist ein
  Programm, das an wlib vorbeizeichnet, und genau das zählt
  `tools/design/messen.py` als Fehler.
* `/bin/qs` bekommt die Lautstärke als zweite Reglerzeile — gebaut wie
  die Helligkeit darüber, aus denselben Themenmarken (`T_SCROLL`,
  `T_ACCENT`, `T_BTN`, `T_LINE`). **Kein fester Farbwert.**
* Vier neue Glyphen (`icon.volume.high/low/zero/muted`, Block
  E010..E01F) über `assets/icons/icons.map` erzeugt — kein Codepunkt
  steht im Zeichencode.
* Bedient wird es auf vier Wegen: Klick in die Rinne, Klick auf die
  Beschriftung (stumm), Klick auf das Symbol in der Leiste (öffnet das
  Panel), **Super+M**. `m` und keine Multimediataste, weil
  `kernel/kbd.fi` Buchstaben liefert und keine erweiterten Abtastcodes.
* **Keine Karte, kein Feld** — dieselbe Regel wie beim Akku und beim
  Netz. `A_READY` sagt es. Ein Bildschirmfoto ohne `-device intel-hda`
  zeigt den Regler deshalb **absichtlich** nicht;
  `tools/design/capture.sh ton=ja` hängt eine Karte an.

---

## 6. Was fehlt (Stand dieser Runde)

* **Keine Aufnahme.** Eingabeströme und ADC-Knoten werden aufgezählt und
  nicht angefasst.
* **Kein HDMI/DisplayPort-Ton.** Digitale Buchsen werden übersprungen.
* **Keine Buchsenerkennung im Betrieb.** Der Weg wird EINMAL beim
  Aufsetzen gewählt; ein später eingesteckter Kopfhörer schaltet nicht um.
  Das braucht unaufgeforderte Antworten (`SET_UNSOLICITED_ENABLE`) und
  eine Stelle, die sie behandelt.
* **Nur ein Ausgabestrom in der Hardware.** Mehrere Programme löst der
  Software-Mischer.
* **Keine Herstellertabellen.** Keine Kennung ist fest verdrahtet.
* **`/bin/play` hat aus Ring 3 noch Aussetzer.** Siehe STATUS-HDA.md,
  Abschnitt „Der rote Punkt“. Der Weg IM KERN hat null.
