<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Ton in Osum — die Schicht, die HDA unverändert bedienen muss

Stand: Runde MEDIA1, 28.08.2026.
Treiber: `kernel/ac97.fi` · Schicht: `kernel/audio.fi` · Aufrufe: `kernel/sys.fi` 1840–1842
Abnahme: `tools/media1/run.sh`

---

## 0. Warum dieses Dokument die wichtigste Datei der Runde ist

Der Fahrplan (Block F) sagt: AC97 zuerst, **Intel HDA danach**. AC97 lebt nur noch in
QEMU, VirtualBox und Bochs; auf echten PCs ist es seit ~2006 verschwunden. HDA sitzt
dagegen auf praktisch jedem x86-Rechner seit 2005 — und kostet 1000–2000 Zeilen statt
300–600, weil die **Codec-Topologie** je Hersteller anders aussieht (Linux hat dafür
tausende Zeilen Quirk-Tabellen; eine generische Heuristik trifft 70–85 % der Maschinen).

Die Runde MEDIA1 ist deshalb nicht „Osum kann piepen“. Sie ist:
**die Grenze zu ziehen, an der der HDA-Treiber später eingesetzt wird, ohne dass eine
Zeile darüber sich ändert.** Alles andere wäre in zwei Monaten noch einmal zu schreiben.

---

## 1. Die Grenze: neun Funktionen, ein Block, eine Datei

In `kernel/audio.fi` steht **ein einziger Block**, der unter die Grenze greift. Er ist
im Quelltext als solcher überschrieben, und `tools/media1/run.sh` zählt nach, dass es
nicht mehr als zwölf Funktionen sind:

| Funktion | Was sie liefert |
|---|---|
| `hw_ready(state)` | gibt es das Gerät, ist es aufgesetzt |
| `hw_ring(state)` | Adresse des DMA-Ringpuffers |
| `hw_ring_frames(state)` | wie viele Rahmen er fasst |
| `hw_entry_frames(state)` | wie viele Rahmen ein Deskriptor-Eintrag fasst |
| `hw_entries(state)` | wie viele Einträge es gibt |
| `hw_submit(state)` | einen **vollen** Eintrag übergeben, LVI nachziehen |
| `hw_start` / `hw_stop` | Lauf an, Lauf aus |
| `hw_position(state)` | **abgespielte Rahmen, monoton** — die Leituhr |
| `hw_volume(state, pct)` | Lautstärke in Prozent |
| `hw_running(state)` | läuft der DMA gerade |

**Alles andere steht über der Grenze und wird nicht zweimal gebaut:** Format,
Ringbuchführung, Auffüllen mit Stille, Aussetzerzählung, Lautstärkepolitik,
Tonerzeugung (Sinus in Festkomma), Systemklänge, die drei Systemaufrufe.

### Was HDA konkret tun muss

HDA hat dieselben Bausteine unter anderem Namen — deshalb passt die Grenze:

| Osum | AC97 | Intel HDA |
|---|---|---|
| Ring + Deskriptorliste | BDL, 32 Einträge, `PO_BDBAR` | BDL, `SDnBDPL/U`, `SDnCBL` |
| „letzter gültiger Eintrag“ | `PO_LVI` | `SDnLVI` |
| Lauf an | `PO_CR` Bit 0 | `SDnCTL` RUN |
| Format | fest 48/16/2 | `SDnFMT` = 0x0011 |
| **Abspielposition** | `PO_CIV` + `PO_PICB` | `SDnLPIB` — **besser: DMA Position Buffer** (`DPLBASE`/`DPUBASE`), weil LPIB auf manchen Reglern nachhinkt |
| Lautstärke | Mischer-Register 0x02/0x18 | `SET_AMP_GAIN_MUTE` je Widget |

Der teure Teil von HDA liegt **komplett unter der Grenze**: Controller-Reset, `STATESTS`,
CORB/RIRB oder Immediate Command Register, Widget-Baum, Pfad vom Audio Output Converter
zu einem Pin Complex, Amp-Gains. Nichts davon fasst `audio.fi` an.

---

## 2. Die Uhr — und warum sie der Ton ist und nicht der Prozessor

```
t_audio_us = samples_played * 1_000_000 / 48000
```

Der Quarz eines Tonchips läuft nominell mit 48 000 Hz und real mit ±100 ppm. Über eine
Stunde sind das **360 ms**. Wer das Bild an den Prozessortakt hängt und den Ton an den
Chip, hat garantiert Versatz; wer das Bild an `samples_played` hängt, hat ihn per
Konstruktion nicht. Deshalb ist `samples_played` die **Leituhr** für die spätere
Videorunde.

### Gemessen in dieser Runde

`tools/media1/run.sh`, Abschnitt 5, misst dieselbe Strecke mit **drei** Uhren — einmal
über 1 s und einmal über 5 s. Aus zwei Längen lassen sich **fester Versatz** und
**Gangfehler** trennen; eine einzelne Messung kann das nicht (ein fester Versatz von
9 ms sieht über eine Sekunde aus wie 9000 ppm Gangfehler und über fünf wie 1800).

| Größe | Wert (28.08.2026, KVM, QEMU 7.2) |
|---|---|
| Gangfehler Ton gegen Zyklenzähler | **−749 ppm** |
| fester Versatz | **+9 ms** |
| Ton gegen Zeitgeber (100 Hz, unabhängig) | **+374 ppm**, Körnung einer Marke = 2037 ppm |
| Rückschritte der Position (`backsteps`) | **0** in jedem Lauf |

**Der Versatz von 9 ms ist kein Fehler, sondern eine Eigenschaft der Hardware**, und die
Recherche hat ihn vorhergesagt: *„Deine Audio-Hardware hat eine feste Ausgabelatenz
(Puffer + Codec-Pipeline, typisch 5–30 ms). Das ist ein konstanter Offset, kein Drift —
einmalig messen und als Konstante abziehen.“*
`CIV`/`PICB` zählen, was der **Regler geholt** hat, nicht was der Lautsprecher schon
gesagt hat. Zwischen beiden liegt der FIFO (echte Hardware) bzw. der Mischerpuffer
(QEMU). Für Lippensynchronität heißt das: der Videopfad zieht diesen einen konstanten
Wert ab, und dann stimmt es.

**Bedingung, unter der die Uhr gilt:** sie muss **mindestens einmal je Ringumlauf**
(85,3 ms) abgefragt werden, sonst geht ein Umlauf verloren. Der Schreibpfad tut das von
selbst; wer nur zusieht, muss pollen. Eine Unterbrechung, die das erledigt, gibt es in
dieser Runde nicht — siehe „Was fehlt“.

---

## 3. Die Geometrie und die Verzögerung

| Größe | Wert |
|---|---|
| Format | 48 000 Hz, 16 Bit, 2 Kanäle (fest) |
| ein Eintrag | 128 Rahmen = 512 Oktette = **2,666 ms** |
| Einträge | **32** (= der Zählbereich der Hardware, siehe unten) |
| Ring | 4096 Rahmen = 16 384 Oktette = **85,333 ms** |
| Vorlauf vor dem Anfahren | 24 Einträge = 3072 Rahmen = **64 ms** |
| Stille am Dateiende (Auffüllen) | höchstens 127 Rahmen = **2,64 ms** |

**Warum 32 Einträge und nicht 8** — eine Falle, in die diese Runde einmal gelaufen ist:
Der laufende Index `CIV` zählt bei AC97 **immer bis 32**, nicht bis zur Zahl der
Einträge, die der Treiber benutzt. Die erste Fassung hatte 8 Einträge zu 512 Rahmen und
rechnete `CIV % 8`. Der Regler lief durch 24 nie beschriebene Einträge mit Länge null,
die Position sprang, die Umlaufzählung explodierte, der Schreiber hielt den Ring für
leer. **Gemessen: 48128 Rahmen geschrieben, 12288 in der Datei.**

**Warum 64 ms Vorlauf und nicht 21 ms** — die zweite Falle:
Der Regler holt sich die Oktette **im Voraus**, nicht im Takt der Lautsprecher (FIFO
bzw. QEMU-Mischerpuffer, dort 46 ms). Steht weniger im Ring, als in seinen Puffer passt,
ist der Ring nach einem Wimpernschlag leer. **Gemessen: mit 21 ms Vorlauf 24 Aussetzer
bei 24 Schreibvorgängen; mit 64 ms 0 bis 5, und die 5 sind Last auf dem Bauserver.**

---

## 4. Die Systemaufrufe (Vorrat 1840–1849)

```
1840  osum_audget(feld)             -> Wert
1841  osum_audset(feld, wert)       -> 0 oder -errno
1842  osum_audwrite(zeiger, rahmen) -> angenommene Rahmen oder -errno
```

`osum_audwrite` **blockiert nicht.** Es nimmt, was in den Ring passt, und sagt wie viel.
Das ist Absicht: ein Abspieler, der später auch Bilder dekodiert, darf nicht im Ton
hängen — und Fäden gibt es in diesem System noch nicht (Block A1). Damit gilt die Regel
aus der Recherche unmittelbar:

> **Ton hat Vorrang. Ein leergelaufener Tonpuffer ist ein hörbarer Knacks, ein
> ausgelassenes Bild sieht niemand.**

Felder von `osum_audget`: `A_READY`, `A_RATE`, `A_CHANNELS`, `A_BITS`, `A_VOLUME`,
`A_PLAYED`, `A_WRITTEN`, `A_UNDERRUNS`, `A_LATENCY`, `A_ENTRYUS`, `A_RINGFRAMES`,
`A_ENTRYFRAMES`, `A_ENTRIES`, `A_RUNNING`, `A_OPEN`, `A_BACKEND`, `A_WHY`, `A_IRQS`,
`A_SUBMITS`, `A_SOUNDS`, `A_BEEPS`, `A_MUTED`, `A_STARTS`, `A_DCH`, `A_CODEC`,
`A_REMAIN`, `A_WRITES`, `A_MASTERREG`, `A_PCMREG`, `A_BACKSTEPS`.
Felder von `osum_audset`: `AS_VOLUME`, `AS_OPEN`, `AS_MUTE`, `AS_DRAIN`, `AS_STOP`,
`AS_SOUNDS`, `AS_BEEP`.

---

## 5. Die Lautstärke — und eine Ehrlichkeit über QEMU

Prozent 0…100. 100 schreibt **0** in beide Mischerregister.

* **Master (0x02)**: sechs Bit Dämpfung je Kanal, 1,5 dB je Schritt, 0 = am lautesten.
  Osum rechnet `att = 63 * (100 - pct) / 100`. QEMU macht daraus einen **linearen**
  Faktor `(255 − 255·att/63)/255`, echte Hardware eine **logarithmische** Kurve. Die
  Abnahme prüft den QEMU-Wert: bei 50 % erwartet `0,509804`, gemessen `0,509803`.
* **PCM-Ausgang (0x18)**: Osum schreibt **0**. Auf echter AC97-Hardware ist `0x08` die
  Einheitsverstärkung und `0x00` sind **+12 dB**; QEMU kennt diese Verstärkung nicht und
  behandelt 0 als Einheit. Osum schreibt 0, weil nur dann der Weg vom Programm bis zur
  Datei **rechnungsfrei** ist — und genau das misst die Abnahme mit dem Bitvergleich.
  **Für echte AC97-Hardware gehört hier `0x0808` hin.** Steht in der Restliste.

---

## 6. Die Einstellung: `/etc/audio.conf`

Drei Zeilen, `wort zahl`:

```
lautstaerke 40
stumm 0
klaenge 1
```

Geschrieben von `/bin/vol` **und** vom Reiter „Ton“ in `/bin/einstellungen`. Beide
schreiben die **ganze** Datei, also kann kein halber Stand entstehen. Gelesen wird sie
mit `vol laden`.

**Es gibt eine Lautstärke für die ganze Maschine, keine je Programm.** Ein Regler je
Programm braucht einen Mischer, ein Mischer braucht den Systembus mit Rechten
(Block A3). Das ist keine Auslassung, sondern eine Reihenfolge.

---

## 7. Systemklänge

Ein kurzer Ton (880 Hz, 90 ms, −15 dBFS) bei **jeder** Fehlermeldung. Er hängt in
`ulib.esay_line` — der **einen** Stelle, durch die alle 120 Programme dieses Systems
ihre Fehler schreiben. Was er kostet, gezählt statt geschätzt: **ein Systemaufruf je
Prozess**, der überhaupt eine Fehlermeldung schreibt, und keiner für die anderen
(`snd_state` merkt sich die Antwort).

Abschaltbar im Kern (`/bin/vol klang aus`, Reiter „Ton“), gemerkt in `/etc/audio.conf`.
Er unterbricht **niemals** eine laufende Wiedergabe: solange jemand das Gerät geöffnet
hat, wird der Klang gezählt und verworfen. Ein zweiter Strom bräuchte einen Mischer.

---

## 8. Was fehlt — ehrlich und nummeriert

1. **Kein Unterbrechungsbetrieb.** Der Treiber arbeitet abfragend; `IOCE`/`LVBIE` bleiben
   aus, weil kein Vektor auf der Leitung liegt und eine pegelgesteuerte PCI-Leitung, die
   niemand quittiert, auf einer geteilten Leitung ein Sturm im Nachbargerät wäre.
   Folge: Wiedergabe braucht einen laufenden Prozess. Für Hintergrundmusik ohne Last
   fehlt der Vektor. `ac97.irq` ist geschrieben und wartet darauf.
2. **Kein Mischer.** Ein Strom zur Zeit. Braucht A3 (Systembus mit Rechten).
3. **Keine Aufnahme.** Die beiden Eingangskanäle des Chips bleiben unberührt.
4. **Nur 48 kHz / 16 Bit / Stereo im Kern.** Umgerechnet wird in Ring 3 (`/bin/play`,
   linear, Festkomma Q16) — kein Umrechner mit Fenster (Sinc), also bleiben
   Spiegelfrequenzen bei krummen Verhältnissen wie 44 100 → 48 000.
5. **Intel HDA fehlt** — das ist die nächste Tonrunde und der Grund für dieses Dokument.
6. **AC97 auf echter Hardware:** dort gehört `0x0808` statt `0x0000` in das PCM-Register
   (siehe Abschnitt 5), und die Kaltstart-Warterei müsste gegen echte Codecs geprüft
   werden. Beides ist in QEMU nicht messbar.
7. **Keine Sprungmarken.** Spulen in einer Datei gibt es nicht; dafür braucht der
   Behälter seine Sprungtafel (`docs/CONTAINER.md`).
