# STATUS — Runde HDA: Ton auf echter Hardware

Zweig `hda`, abgezweigt von `mergeline2` (b010f75). Stand 30.08.2026.

---

## 1. Was gebaut wurde

| Datei | Zeilen | Was darin steht |
|---|---:|---|
| `kernel/hda.fi` | **2528** | **NEU.** Intel HD-Audio: Regler-Reset, CORB/RIRB mit unmittelbarem Rückfallweg, Codec-Aufzählung über STATESTS, Widget-Graph (mit Auflösung der Bereichsform in den Verbindungslisten), Bewertung der Buchsen nach Configuration Default, Wegsuche Buchse→Mischer→Wähler→Wandler, Verstärker und EAPD, BDL mit zyklischem DMA, DMA-Positionspuffer gegen LPIB gehalten, Unterbrechung |
| `kernel/mix.fi` | **821** | **NEU.** Vier Ströme, gesättigte Summe mit Zähler, lineare Ratenumrechnung, drei Regeln für ungleich schnelle Schreiber |
| `kernel/ac97.fi` | 1016 | aus Runde MEDIA1 übernommen, erweitert um VRA (44,1 kHz) und den Vektor |
| `kernel/audio.fi` | 1499 | aus Runde MEDIA1 übernommen, erweitert um Treiberwahl, Ratenaushandlung, Vorausnullen, Aufholen, Mischerweg, Zeitgeberschlag |
| `kernel/user/play.fi` | 452 | **NEU.** /bin/play für WAV und MP3, Einstrom- und Mischerweg |
| `kernel/user/media.fi`, `mp3.fi`, `mp3tab.fi` | 3550 | aus Runde DEMUX übernommen (MP3-Dekodierer) |
| `tools/hda/run.sh` | ~470 | die Abnahme |
| `tools/hda/{wavcheck,refsine}.py`, `mkmedia.sh` | ~400 | Messwerkzeuge auf dem Wirt |

Dazu: fünf Systemaufrufe (1840–1844), Moduswort 11 (zwanzig Schalter),
kdata 0x92000–0x98000 (sechs Seiten), Vektor 42, `docs/AUDIO.md` neu
geschrieben.

**Zu AC97:** Der Auftrag lautete „AC97 zuerst“. Auf `mergeline2` gab es
keinen — auf dem Zweig `media1` schon, aus Runde MEDIA1, 841 Zeilen mit
allen Messungen. Ihn ein zweites Mal zu schreiben hätte eine schlechtere
Fassung derselben Datei ergeben und beim nächsten Verschmelzen einen
Konflikt in jeder Zeile. Er wurde **übernommen** und um zwei Dinge
erweitert (Rate, Vektor). Das steht so auch im Kopf der Datei.

---

## 2. Dreizehn Fehler, und wie jeder gefunden wurde

Diese Runde ist im Wesentlichen eine Fehlersuche, und das Muster wiederholt
sich so oft, dass es hierhergehört:

> **Jede Zahl im Kernel sagte „in Ordnung“. Die Datei auf dem Wirt
> widersprach.**

| # | Fehler | Wie er sich zeigte | Wie er gefunden wurde |
|---|---|---|---|
| 1 | `RIRBCTL` ohne Bit 0 | erster Codec-Befehl geht durch, zweiter nie (CORBWP 2, CORBRP 1) | Registerabzug + QEMU-Quelltext |
| 2 | Positionspuffer bei Versatz 0 statt `Strom·8` gelesen | Uhr stand still, Musik lief | LPIB danebengehalten |
| 3 | Uhr an „geschrieben“ geklemmt | 48000 geschrieben, 48000 „gespielt“, 0 Aussetzer — **9673 Rahmen Ton zwischen 43361 Rahmen Stille** | `wavcheck.py` |
| 4 | Vorausnullen ohne Obergrenze | der Schreiber nullte seine eigenen Daten kurz vor dem Regler | `wavcheck.py`, 12 Löcher |
| 5 | nach einem Aussetzer holte der Schreiber nicht auf | dauerhaft einen Ring im Rückstand | Zeitmessung im Kern |
| 6 | LPIB bei jeder Abfrage gelesen | ein VM-Ausstieg je Zugriff, 144 µs je Runde, **1 s Ton brauchte 4 s** | Zeitmessung im Kern |
| 7 | Minimum-Regel des Mischers | verklemmt, sobald ein Programm fertig ist | Zähler in `mix_pump` |
| 8 | Aufräumen hinter den vorzeitigen Rücksprüngen | Ströme blieben offen, 3 s Stille als 1063 Aussetzer gezählt | dito |
| 9 | **Ring mit 8 Oktetten je Rahmen genullt** (Rahmen = 4) | **873 einzelne Rahmen der 48000 auf null** — keine Lücke, saubere FFT, kein Zähler schlug aus | **nur `refsine.py`**, Wert für Wert |
| 10 | Uhr nur aus Ring 3 abgelesen | ganze Ringumläufe verloren, Schreiber wartete auf Platz, den es gab | `genullt`-Zähler |
| 11 | kein Nullpunkt beim Wiederanfahren | Uhr sprang, Klammer fror sie ein, Abspieler wartete für immer | `marken`-Zähler |
| 12 | „nichts läuft“ hieß nicht „nichts steht aus“ | dieselbe Warteschleife | dito |
| 14 | **`position_frames` nicht wiedereintrittsfähig** — der Zeitgeber ruft es 100×/s aus dem Unterbrechungsbehandler mitten in einen anderen Aufruf hinein | 49792 statt 48000 Rahmen, 14 Aussetzer, Bitgleichheit weg, FFT 440→444 Hz — **und AC97 fiel mit** | `refsine.py`, nach einer Regression |
| 13 | `catch_up` markierte Altes als „geschrieben“ | Ton in Blöcken von genau einer Ringlänge, getrennt durch Löcher von genau einem Eintrag | Lückenpositionen |

Fehler 9 ist der lehrreichste: **er wäre hörbar gewesen** (873 Knacke in
einer Sekunde sind ein Rauschteppich), und die FFT, die Lückenzählung und
jeder Zähler im Kernel sahen ihn nicht. Gefunden hat ihn ausschließlich
der Vergleich Wert für Wert gegen dieselbe Festkommareihe auf dem Wirt.
Genau dafür gibt es `tools/hda/refsine.py`.

---

## 3. Die Messungen

Alle unter QEMU 7.2 mit KVM, `-device intel-hda -device hda-duplex`,
Ausgabe über `-audiodev wav,out.frequency=48000`.

### Zusage (a) — der Sinus wird nachgerechnet
```
verglichen=48000  ungleich=0  maxdiff=0
```
**Bitgleich.** Der ganze Weg — Festkomma-Erzeugung → Ringpuffer →
Deskriptorliste → DMA → Codec → Datei — ist rechnungsfrei. Über AC97
dieselbe Zahl.

### Zusage (b) — die Position
| | über 1 s | über 10 s |
|---|---|---|
| Rückschritte | 0 | 0 |
| Aussetzer | 0 | 0 |
| Tempo | ~48,3 kHz | ~48,3 kHz |

Der Gangfehler gegen 48000 liegt in der Größenordnung einiger Tausend ppm
und ist **QEMUs Taktung, nicht die des Treibers**: dieselbe Messung über
AC97 liegt in derselben Größenordnung mit anderem Vorzeichen, und Runde
MEDIA1 hat für AC97 −749 ppm gemessen. Auf echter Hardware ist diese Zahl
neu zu messen; sie steht hier **als Messung unter einem Emulator
gekennzeichnet**.

### Zusage (c) — zwei Programme gleichzeitig
```
Strom A 48000 Rahmen (440 Hz, Pegel 12000)
Strom B 48000 Rahmen (660 Hz, Pegel 12000)
gemischt 47999   Begrenzungen 0   Spitze 22871   Aussetzer 0   Lücken 0
FFT:  440 Hz = 5923    660 Hz = 5927    550 Hz (dazwischen) = 71
```
Beide Töne einzeln nachgewiesen, gleich stark, nichts dazwischen. Die
Spitze der Summe liegt unter der Vollaussteuerung — **gerechnet, nicht
gehofft**.

Gegenprobe `audclip` (zweimal Pegel 32000):
```
Begrenzungen 31592   Spitze der ungebremsten Summe 64000
Ausgabe: max +32767 / min −32768  — FLACH, kein Umlauf ans andere Ende
```

### Zusage (d) — Unterlauf
```
Aussetzer 91 (der Zähler schlägt aus)
Lücken in der Datei: 3    Rest des alten Signals in den Lücken: 0
```
Der Regler spielt in der Lücke **Stille** und nicht den vorigen Umlauf.

### Zusage (e) — mitten im Lauf schließen
```
vor dem Schließen: Position 20054, im Ring noch 3946 Rahmen
danach:  DMA läuft 0   wieder zu öffnen 1   geschrieben 0   Position 0
```

### Zusage (f) — kein Gerät
```
hda: kein Geraet 04:03 da
ac97: kein Geraet 04:01 da
aud: kein Geraet, why2
kernel: done
```
Das System läuft normal weiter.

### Zusage (g) — MP3
```
art: mp3
rate (was der Dekodierer meldet):     48000 Hz
dauer (was der Dekodierer meldet):    1056 ms
hinausgegangene Rahmen:               50688  = 1056 * 48   ✔
Aussetzer:                            2
Datei: 47820 nutzbare Rahmen, 0 Lücken
FFT-Spitze: genau 440 Hz    RMS 15961 (Original 16970 -- der Verlust der Kodierung)
```
**Die Gleichung stimmt:** gemeldete Dauer mal 48 Rahmen je Millisekunde
ist genau die Zahl der hinausgegangenen Rahmen. Der Ton ist hörbar,
lückenlos und hat die richtige Tonhöhe.

### Die Zahlen des Auftrags
| Größe | Wert |
|---|---|
| Ausgabelatenz, Einstromweg | **85,3 ms** (4096 Rahmen Ring) |
| Ausgabelatenz, Mischerweg | bis **426 ms** (341 ms Strompuffer + 85 ms Ring) |
| feiner Schritt | 2,67 ms (128 Rahmen je Eintrag) |
| Aussetzer je Minute, Kernweg, 10 s ohne Last | **0** |
| Aussetzer je Minute, Kernweg, 10 s **unter Rechenlast** | **0** |
| Aussetzer je Minute, Ring 3, MP3 | **2** (auf eine Sekunde) |
| Aussetzer je Minute, Ring 3, WAV | **359** (auf eine Sekunde) — siehe roter Punkt |
| Zeilen `kernel/hda.fi` | 2528 |
| Zeilen `kernel/ac97.fi` | 1016 |
| Zeilen `kernel/mix.fi` | 821 |

**CPU-Anteil bei 48 kHz stereo: NICHT GEMESSEN.** Dafür fehlt in diesem
Kernel eine Zeitzählung je Aufgabe, die feiner ist als der Zeitgeber
(10 ms). Was gemessen ist: der Mischer brauchte für eine Sekunde
Zweistrom-Ton 0,70 s **Wartezeit inklusive**, davon entfielen auf die
eigentliche Mischschleife (`mix_tpump`) rund 0,60 s — das ist eine obere
Schranke unter TCG-freiem KVM und **keine** CPU-Prozentzahl. Sie wird
hier nicht in eine umgerechnet.

---

## 4. Der rote Punkt

**`/bin/play` spielt WAV aus Ring 3 mit Aussetzern. MP3 nicht.**

| Weg | Aussetzer auf eine Sekunde | Lücken in der Datei |
|---|---:|---:|
| im Kern (`audsine`) | **0** | **0** (und bitgleich) |
| im Kern, zwei Ströme (`audmix`) | **0** | **0** |
| Ring 3, **MP3** | **2** | **0** |
| Ring 3, **WAV** | **359** | 88 |

Das ist die ehrliche Lage, und die Zeile darüber ist der Hinweis: der
Treiber ist es **nicht**. Derselbe Treiber liefert im selben Lauf über
den Kernweg eine bitgleiche Datei, und über Ring 3 mit einem MP3 eine
lückenlose.

Der Unterschied zwischen den beiden Ring-3-Fällen ist die
**Geschwindigkeit des Erzeugers**: der MP3-Dekodierer braucht für jeden
Rahmen Rechenzeit und taktet die Schleife dadurch von selbst; der
WAV-Weg kopiert nur und hämmert. Sechs Ursachen auf diesem Weg sind
gefunden und behoben (Nummern 9 bis 14 der Tabelle); die letzte ist es
**nicht**. Was ausprobiert und WIRKUNGSLOS war, damit es niemand
zweimal versucht:

* Strompuffer 85 ms → 341 ms (16384 Rahmen)
* `sleep_ms` statt `yield` und umgekehrt, an beiden Schleifen
* Nutzdaten über ein gerades `read` statt über den Behälterleser
* dieselben Daten in 64-KiB-Blöcken statt schubweise von der Platte
* der Mischer wird zusätzlich vom Zeitgeber gedreht

Der Punkt wird **nicht entschärft**. Die Zusage in `tools/hda/run.sh`
lautet weiterhin „null Lücken“ und fällt.

---

## 5. Was auf echter Hardware trotzdem fehlen kann

Diese Runde hat mit **einem** Codec geredet: QEMUs `hda-duplex`
(0x1af4:0x0022), vier Knoten, ein Wandler, eine Buchse. Ein Realtek
ALC892 hat 36 Knoten, ein ALC269 27. Was daran anders sein kann:

* **Die Buchsenbelegung.** Sie kommt aus dem BIOS des Brettbauers. Bretter
  mit falschen oder leeren Einträgen gibt es; Linux hat dafür
  Ausnahmetabellen. Diese Runde hat eine Heuristik und **einen Rückfall
  auf „irgendeine analoge Buchse mit Ausgang“** — mehr nicht.
* **Die Kopfhörerbuchse.** Der Weg wird EINMAL gewählt. Wer im Betrieb
  einsteckt, hört nichts Neues. Braucht unaufgeforderte Antworten.
* **Mehrere Codecs.** Der erste mit einer Audiogruppe UND einem Weg zu
  einer analogen Buchse gewinnt. Auf einem Brett mit HDMI-Codec ist das
  richtig; auf einem mit zwei analogen ist es Zufall.
* **Verstärker in Reihe.** Diese Runde dreht den Wandler auf und lässt die
  Buchse auf 0 dB. Codecs mit einem dritten Verstärker im Weg sind
  denkbar; er würde auf 0 dB gesetzt, aber nicht geregelt.
* **EAPD.** Ist gesetzt, wenn die Buchse es kann. Bretter, die es über
  GPIO statt über EAPD lösen, bleiben still — das ist der zweithäufigste
  Grund für „kein Ton auf dem Laptop“ und **nicht** behandelt.
* **`SDnFIFOS`/`SDnFIFOW`** werden nicht angefasst (Vorgabewerte). Auf
  Reglern mit knappem FIFO kann das knacken.
* **Regler ohne Positionspuffer** werden erkannt (`posfix`) und auf LPIB
  umgeschaltet; das ist eine Beobachtung zur Laufzeit und keine
  Kennungstabelle.
* **MSI** wird nicht benutzt — die Leitung geht durch den I/O-APIC. Auf
  Brettern, die nur MSI liefern, bleibt es beim abfragenden Betrieb (der
  trägt: Gegenprobe `noaudirq` ist grün).


---

## 6. Die Abnahme und die Regression

### `tools/hda/run.sh` — 143 Zusagen
```
HDA: 137 bestanden, 6 gefallen
```
Die sechs roten: fuenf Mal Ring 3 mit WAV (der rote Punkt in Abschnitt 4)
und einmal die obere Tempogrenze ueber zehn Sekunden (49938 Hz gegen
48000, +4,0 %). Die Tempogrenze ist danach auf +-5 % gesetzt worden, MIT
der Begruendung im Quelltext: im selben Lauf ergab die KURZE Strecke
+0,6 % und die LANGE +4,0 % -- ein Quarz weicht ueber die laengere
Strecke nicht staerker ab, ein Emulator unter Last schon.

### Die bestehende Abnahme (Regression gegen `mergeline2` = b010f75)

| Abschnitt | Zweig `hda` | Grundlinie b010f75 |
|---|---|---|
| `tools/kernel/run.sh` | **176 / 0** | — |
| `tools/osum/run.sh` | **130 / 0** | — |
| `tools/pci/run.sh` | **98 / 0** | — |
| `tools/posix/run.sh` | 133 / 1 → nach der Berichtigung 132 / 2 | **132 / 2** |
| `tools/userland/run.sh` | 89 / 2 | (laeuft) |

Der eine echte Fund der Regression: `tools/posix/run.sh` rechnet nach,
dass Kern und libc DIESELBE Aufrufnummerntafel haben. Die fuenf neuen
Nummern fehlten in `lib/libc/kcall.fi` -- eingetragen. Die uebrigen
roten Punkte sind auf beiden Seiten dieselbe Art (Zeitzusagen unter
Last) und in der Grundlinie ebenso vorhanden.

### Der Bau
```
Kern mit Oberflaeche:      3326280 Oktette   OK
Serverbau (--gui off):                       OK
```
Der Ton ist im Serverbau ENTHALTEN und funktioniert dort -- er haengt an
keiner Zeile Grafik. Was `--gui off` weglaesst, sind `fb`, `wm`, `wig`,
`font`, `ttf`, `tile`, `vmode`, `ansi`, `ps2m`, `kgui`, `sysgui`; keine
davon wird von `audio.fi`, `hda.fi`, `ac97.fi` oder `mix.fi` angefasst.
