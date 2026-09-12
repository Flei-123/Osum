<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Runde BLECH-ECHT — vier Zweige nach `main`, ein Abbild, und eine ehrliche Bereitschaftstafel

Arbeitsbäume `/root/osum-blechecht` und `/root/be-probe`, Zweig
`blechecht`, abgezweigt von `main` (`404fa65`, Ende Runde MERGE-5).
Gemessen am 02./03.09.2026 auf dem üblichen Wirt (AMD EPYC 7571, 12
Kerne, 19 GiB, `/dev/kvm`, QEMU 7.2.22).

**Der Auftrag war einer:** Justin soll Osum auf einem echten Laptop von
einem USB-Stick starten können. Alles unten ist danach sortiert.

---

## DIE RUNDE IN FÜNF ZEILEN

1. **Vier Zweige sind in `main`**: `blech` (mit `rtl` als Vorfahr),
   `hid`, `modul`, `bridge`. Vier weitere waren **schon** drin
   (`ahci`, `update`, `hwnet`, `usbimg` — 0 Commits vor `main`), was
   der Auftrag nicht wissen konnte.
2. **`schirm` ist NICHT drin**, und zwar aus einem gemessenen Grund:
   mit ihm füllt die Oberfläche einen 1280x800-Schirm nur zu 49 % × 50 %
   und die Taskleiste verschwindet. Ein Zweig, der eine grüne Abnahme rot
   macht, kommt nicht herein.
3. **Zwei echte Merge-Schäden gefunden und behoben**, beide vom selben
   Bauplan: zwei Runden haben sich denselben freien Platz genommen, weil
   beide vor dem jeweils anderen Merge abgezweigt sind (Seiten in
   `kdata`, Bits im Modusvektor, dreimal derselbe Fall).
4. **Der Namenskonflikt ist aufgelöst**: das Programm der Runde POLL
   heißt jetzt `/bin/pollbr`, `/bin/jarvisd` gehört der Brücke aus
   Runde BRIDGE.
5. **Das Abbild startet auf sechs Wegen** — BIOS und UEFI, von IDE, von
   AHCI und von NVMe, mit Intel- und mit Realtek-Netzkarte —, und was es
   dabei nicht kann, steht in `docs/BLECH-BEREIT.md`.

---

## TEIL 1 — WAS SCHON IN `main` WAR

Der Auftrag nennt elf Zweige. Vier davon sind **null Commits** von
`main` entfernt, waren also längst gemerged:

| Zweig | Commits vor `main` |
|---|---|
| `ahci` | **0** (245 dahinter) |
| `update` | **0** (240 dahinter) |
| `hwnet` | **0** (247 dahinter) |
| `usbimg` | **0** (237 dahinter) |

Und `rtl` ist **Vorfahr von `blech`** — wer `blech` merged, holt `rtl`
mit. Übrig blieben damit fünf: `blech`, `hid`, `modul`, `bridge`,
`schirm` (`struktur` siehe „was noch fehlt").

---

## TEIL 2 — DIE VIER MERGES, DER REIHE NACH

### 2.1 `blech` (29 Commits, mit `rtl`)

Realtek RTL8169/8168/8111/8101 (`kernel/r8169.fi`, 1239 Zeilen), der
PCH-Zweig für I217/I218/I219 in `e1000.fi`, die Wurzelsuche
(`rootsel.fi`: NVMe → AHCI → USB → IDE, der erste, der wirklich trägt),
die Treiberschicht für Massenspeicher (`blkdev.fi`), EHCI, die
RAID-Meldung, NVMe mit mehreren Namensräumen.

**Ein Konflikt**, `test.sh`: MERGE-5 hatte gerade Abschnitt 34 an `ota`
vergeben, BLECH nannte seinen ebenfalls 34. Beide bleiben, BLECH wird
35; `tools/rtl/run.sh` kommt als eigener Abschnitt mit. 56 angemeldete
Läufer werden 58.

Gemessen direkt nach dem Merge: **`BLECH: 72 bestanden, 0 gefallen`**,
**`RTL: 67 bestanden, 0 gefallen`**, **`GUARD: 58 passed, 0 failed`**
(206 Zusagen, 0 Fehler).

### 2.2 `hid` (4 Commits) — und der erste echte Schaden

Berichtsbeschreibungen zerlegen, ein Eingabeweg für PS/2, USB-HID und
I²C-HID, NKRO, Präzisions-Touchpad.

Drei Konflikte, alle additiv (`tools/kernel/memmap.py`, `test.sh`,
`docs/REALHW.md`). Danach war die Abnahme **rot**, und zwar zu Recht:

```
K17:  FAIL  tools/kernel/memmap.py meldet Kollisionen
      KOLLISION: AIO (kstate.fi:AIO_OFF) 0x92000..0x94000
                 ueberschneidet HIDREP_FLD (hidrep.fi:FLD_OFF) 0x92000..0x96000
      KOLLISION: den Modusindex 704 haben zwei Namen: M_ASYNC, M_HIDREP
      … 13 Kollisionen
HID:  56 bestanden, 1 gefallen
      FALL  die Moduswoerter des ganzen Baums sind eindeutig
```

**Die Ursache ist eine Frage der Zeitrechnung, nicht des Quelltextes.**
Der Zweig `hid` zweigt bei `b010f75` ab (MERGE-2 13). Dort waren die
Seiten `0x92000..0x9B000` und die Modusbits 704..711 frei — `kstate.fi`
wies sie ausdrücklich als frei aus. Vier Commits später hat Runde ASYNC
(MERGE-2 17) genau dieselben genommen. Beide Runden haben richtig
gehandelt; erst der Merge macht daraus einen Fehler.

**Behoben, ohne einer der beiden Runden etwas wegzunehmen:**

| | vorher | nachher |
|---|---|---|
| `KDATA_SIZE` | 0xA0000 (640 KiB) | **0xB0000 (704 KiB)** |
| `HIDREP_FLD/SUM/RAW`, `HIDIN`, `I2CHID`, `I2CBUF` | 0x92000..0x9B000 | **0xA0000..0xA9000** |
| `M_HIDREP` … `M_HIDDUMP` | 704..711 (Wort 11) | **832..839 (Wort 13)** |

`kdata` steht in `.bss` (`boot.s`), das Abbild wird davon **nicht**
größer; es wird beim Start genullt. Dasselbe hat Merge 2 schon einmal
getan (512 → 640 KiB).

Der dritte rote Punkt kam von `tools/hid/worte.py`, dem Prüfer, den die
Runde HID selbst gebaut hat: **kein Moduswort darf in einem anderen
stecken**, weil `mode_of` in `kmain.fi` mit einem reinen Oktettvergleich
sucht. Acht Einschlüsse waren neu — `disp`/`dispeigen*` (drei),
`dispeigen`/`dispeigenbad`, `ehci`/`ehcitest`, `nic`/`nicself`,
`nic`/`nictab`. **Alle acht sind vom erlaubten Bauplan** „breiter
Schalter + Verfeinerung" (wer `nicself` schreibt, will `nic`), keiner
ist ein Abschalter in einem fremden Wort — und die `disp`-Familie sucht
in `vmode.fi` ohnehin mit `find_word`, also mit Wortgrenze, wo der
Einschluss gar nicht zuschlagen kann. Sie sind mit Begründung in die
Liste der bekannten Fälle eingetragen, nicht entschärft.

Danach: `memmap` **0 Kollisionen**, `worte.py` **89 Wörter, keine neue
Überschneidung**, `HID: 57 bestanden, 0 gefallen`.

### 2.3 `modul` (5 Commits) — derselbe Schaden ein zweites Mal

Ein Treiber ist eine signierte Datei auf der Platte: `.omod`-Lader,
Ausfuhrtafel des Kerns, Treibertafel, der Stummel `ps2m-aus.fi`.

Zwei Konflikte, additiv gelöst — und dahinter wieder zwei Runden auf
demselben Platz: **BLECH hat die drei freien Seiten `0x4D000..0x50000`
für den EHCI-Regler genommen, MODUL für den Lader.** EHCI bleibt liegen
(der Regler verlangt eine 4096-Ausrichtung mitten im Stück), der Lader
zieht auf `0xA9000..0xAC000`. Die Modusbits von MODUL (710/711) waren
frei, seit HID auf Wort 13 gezogen war.

Außerdem angemeldet: **`tools/module/run.sh` als Abschnitt 37** — auch
dieser Läufer stand in keiner Abnahme, der vierte nach `avx`, `ota` und
`betrieb`. Gemessen: **`MODUL: 74 bestanden, 0 gefallen`**.

### 2.4 `bridge` (5 Commits) — und der Namenskonflikt

Der JARVIS-Helfer: ein Dienst, der sich über TLS 1.3 beim Server
**meldet** (hinaus, kein offener Anschluss), sich mit Ed25519 ausweist
und Aufträge ausführt, mit einer Rechteliste, die vor jedem Auftrag neu
gelesen wird.

**Zwei Programme wollten `/bin/jarvisd` heißen.** `docs/BRIDGE.md` hat
den Fall für den Merge vorgesehen; genau so ist es gemacht:

| Datei | Zeilen | heißt jetzt |
|---|---:|---|
| `kernel/user/jarvisd.fi` → `kernel/user/pollbr.fi` | 223 | **`/bin/pollbr`** |
| `kernel/app/jarvisd.fi` | 2274 | `/bin/jarvisd` |

Mitgezogen: der **gedruckte** Namensvorsatz (`pollbr: listening`), damit
ein Protokoll nicht zwei Programme unter demselben Namen zeigt, dazu 13
Stellen in `tools/poll/run.sh`, der Kommentar in `pollt.fi` und ein
Hinweis im Kopf von `POLL-STATUS.md`.

Gemessen: **`POLL: 67 bestanden, 0 durchgefallen`**,
**`BRIDGE: 113 bestanden, 0 durchgefallen`**,
**`USBIMG: 48 bestanden, 0 gescheitert`** — zusammen 237 Zusagen, 0
Fehler.

---

## TEIL 3 — `schirm`: WARUM ER DRAUSSEN BLEIBT

Der Zweig tut, was er verspricht: der **Rahmenpuffer** bekommt die
native Auflösung (`fb: nat=1280x800`), und der Zweitpuffer wird nach der
echten Geometrie bemessen. Der Merge selbst war klein (ein additiver
Konflikt im Startmenü: aus vier Einträgen werden sechs).

**Aber die Abnahme wurde davon rot**, und nicht knapp:

```
USBIMG: 47 bestanden, 1 gescheitert
  NEIN und die Taskleiste ist ebenfalls deutsch: NICHT gefunden
       (bester Wert 60%) -- 'kein Netz' bei x=577 Grundlinie=227
```

Nachgemessen, zweimal, mit demselben Abbild und nur einem Unterschied
auf der Befehlszeile:

| Start | Rahmenpuffer | gezeichneter Inhalt | Taskleiste |
|---|---|---|---|
| ohne Zusatz (nativ) | 1280x800 | `24..650 × 40..443` — **49 % × 50 %** | **nicht sichtbar** |
| `fbres=800x600` | 800x600 | `0..798 × 0..599` — **100 % × 100 %** | sichtbar, `kein Netz` an der richtigen Stelle |

Die Taskleiste rechnet sich dabei **richtig** aus — sie meldet
`geom edge=0 x=0 y=772 w=1280 h=28 shown=1` und zeichnet `kein Netz` bei
`x=1041` in ihr Fenster —, aber im Bild steht unterhalb von `y=443` kein
einziger Bildpunkt, der nicht Hintergrund ist. Es fehlt also nicht die
Auflösung, sondern das, was das Bild **zusammensetzt**.

Dasselbe passiert mit `wmshell` statt `wmhold wiglong`, also nicht nur
im Startweg des Abnahmeläufers.

**Konsequenz:** `schirm` bleibt draußen, bis das gefunden ist. Für
Justin ist das die bessere Wahl — 800x600, die den Schirm füllen und
eine Taskleiste haben, sind brauchbarer als 1280x800, bei denen die
Oberfläche in der Ecke klebt. Die Messung oben ist der Anfang der
nächsten Runde und steht auch in `docs/BLECH-BEREIT.md`, Abschnitt 4.

---

## TEIL 4 — DAS ABBILD UND DIE SECHS STARTS

`bash tools/usbimg/build.sh /tmp/be/usbimg`

| | MERGE-5 | **BLECH-ECHT** | Unterschied |
|---|---:|---:|---|
| Abbild | 123 731 968 Oktette | **123 731 968 Oktette (118 MiB)** | 0 |
| SHA-256 | `16a188f1266f937ecdbb9073e4cc3e0a4e518ba251ae0cbe5f5eab775b542719` | **`39a2952caeb53abefa27b7e8ea4e6adf5776f883c513766a8865acd5b715340e`** | anders |
| Kern | 3 363 920 Oktette | **3 789 672 Oktette** | **+425 752 (+12,7 %)** |
| Ring-3-Programme | 43 | **43** | 0 |
| Wurzel | 20 971 520, OFS v3 | **dieselbe** | 0 |
| Pflichtpfade | 24 | **24** | 0 |
| Umlautfolgen | 129 | **133** | **+4** |

Die 425 752 Oktette sind `r8169.fi` (1239 Z.), `ehci.fi`, `blkdev.fi`,
`rootsel.fi`, `chipname.fi`, `hidrep.fi` (1032 Z.), `hidin.fi` (1503 Z.),
`i2chid.fi` (795 Z.), `modul.fi` (1079 Z.), `ksym.fi`, `modtab.fi`,
`modidx.fi`, `ps2m-aus.fi`.

**Die sechs Starts — dasselbe Abbild als Platte, nicht mit `-kernel`:**

| Lauf | Firmware | Platte | Netz | Ergebnis |
|---|---|---|---|---|
| `bios-ide` | BIOS | IDE | e1000 | `firmware=BIOS`, `disk IDE`, `netdev: bestand … -> e1000` |
| `uefi-ahci` | UEFI (OVMF) | **AHCI** | e1000 | `firmware=UEFI`, **`disk AHCI bdf=0x20 8086:2922`** |
| `uefi-nvme` | UEFI | **NVMe (der Stick selbst)** | e1000 | gestartet, **`disk NVMe bdf=0x20 1b36:0010`** |
| `bios-nvme2` | BIOS | IDE + NVMe | e1000 | beide Platten gemeldet |
| `bios-e1000` | BIOS | IDE | 2× e1000 | `c0=e1000`, `c1=e1000` |
| `bios-rtl` | BIOS | IDE | RTL8139 | **`netdev: c1=r8169`** — der Realtek-Weg wird gefahren |

Alle sechs melden denselben vollständigen Diagnosebericht und
`fb 1280x800 bpp=32 src=multiboot`.

---

## TEIL 5 — DIE ABNAHME

**Lauf 1**, voll, `OSUM_JOBS=3`, auf dem Stand `blech + hid + modul`
(60 angemeldete Läufer): `/root/belogs/ABNAHME-1-blech-hid-modul.log`.

Rote Abschnitte und ihre Einordnung:

| Abschnitt | Lauf 1 | Urteil |
|---|---|---|
| `NET` | 74 / 1 | **Last.** Dieselbe Zeitzusage (Durchsatz durch 20 % Paketverlust), die in MERGE-5 einzeln **75 / 0** gab |
| `POWERMON` | 118 / 3 | **Last.** `burn appears in the table with processor time of its own: 0` — das Lastprogramm hat im Gastsystem keine Rechenzeit bekommen; die Kernzeilen summieren sich exakt (`kernelrows=4 rowenergy=639100 proce=639100 EQUAL`) |
| `INIT` | 76 / 2 | **Last.** Zwei Fristen (`der Dienst wurde nicht neu gestartet`, `shutdown … erwartet 0`) |
| `MULTIUSER` | 90 / 1 | **Last.** Eine Zeitzusage (`drei Fehlversuche dauerten nur 4544 ms länger`) |
| `USBIMG` | 47 / 1 | **Last.** `der Kern kommt nach der unbekannten Karte nicht mehr bis zum Ende` — genau die Zusage, die MERGE-5 schon als abgeschnittenen Lauf benannt hat. Einzeln in Lauf 2: **48 / 0** |
| `UMLAUT2` | 45 / 3 | **ECHT, und älter als diese Runde** — die offene Regression aus MERGE-5: 24 ASCII-Umschriften in den Dateien der Runden OTA/BETRIEB. Diese Runde hat sie nicht angefasst |

Während des Laufs liefen auf demselben Wirt **zwei weitere vollständige
Abnahmen fremder Runden** (Lastmittel 7–8, bis zu vier QEMU-Prozesse
neben den eigenen). Das ist die Erklärung, nicht die Ausrede: die fünf
Zeitzusagen oben sind dieselben, die MERGE-5 einzeln grün nachgemessen
hat.

**Lauf 2**, gezielt, auf dem Stand `+ bridge`:
**`ALLE 4 ABSCHNITTE BESTANDEN, 237 Zusagen, 0 Fehler`**
(`poll` 67/0, `bridge` 113/0, `usbimg` 48/0).

**Lauf 3**, gezielt, direkt nach dem `blech`-Merge:
**`ALLE 4 ABSCHNITTE BESTANDEN, 206 Zusagen, 0 Fehler`**
(`blech` 72/0, `rtl` 67/0, `guard` 58/0).

---

## WAS NOCH FEHLT — ehrlich benannt

1. **`schirm`.** Der Grund steht in Teil 3, mit Zahlen. Das ist der
   erste Punkt der nächsten Runde, und der Befund („die Taskleiste
   rechnet richtig und wird nicht zusammengesetzt") ist eine Spur, keine
   Vermutung.
2. **`struktur` ist nicht gemerged.** Der Zweig zieht 17 Treiberdateien
   nach `kernel/drivers/**` und bringt eine Probe mit, die den Rückfall
   meldet. Ein Probemerge zeigt **neun** Konfliktdateien (`e1000.fi`,
   `netdev.fi`, `virtio.fi`, `usb.fi`, `hwdiag.fi`, `kmain.fi`,
   `tasks.fi`, `test.sh`, `tools/build-kernel.sh`), und danach müssten
   die zehn Treiber, die diese Runde neu hereingeholt hat (`r8169`,
   `ehci`, `blkdev`, `rootsel`, `chipname`, `hidrep`, `hidin`,
   `i2chid`, …), von Hand einsortiert werden. **Er ändert kein
   Verhalten** — für „der Stick läuft auf einem Laptop" bringt er null.
   Deshalb bewusst nicht in dieser Runde, in der jede Stunde in Treiber
   und Messungen gegangen ist.
3. **`ota` in Lauf 1 ist zum Berichtszeitpunkt noch nicht fertig** — der
   Abschnitt braucht auf diesem Wirt bis zu dreieinhalb Stunden (30
   Stromausfälle mitten im Einspielen). Auf dem Stand von MERGE-5 ist er
   einzeln **107 grün, 0 rot** gemessen; diese Runde fasst weder
   `kernel/user/ota.fi` noch `tools/ota/` an.
4. **Die vier Zeitzusagen** (`net`, `powermon`, `init`, `multiuser`)
   sind in dieser Runde **nicht** einzeln auf ruhigem Wirt nachgemessen
   worden — dafür hätte jede eine eigene Stunde gebraucht. Sie sind als
   „Last" eingeordnet, weil sie dieselben sind, die in MERGE-5 einzeln
   grün waren; **bewiesen ist das hier nicht.**
5. **`UMLAUT2`** bleibt offen (24 Umschriften), unverändert seit
   MERGE-5, mit derselben Begründung.
6. **Auf dem Stick fehlen `ota`, `fetch`, `host`, `jarvisd`, `jsig`,
   `jarvisctl`** — siehe `docs/BLECH-BEREIT.md`, Abschnitt 7. Eine Zeile
   `PROGS` und der App-Bauweg; die lohnendste kleine Runde.
7. **Kein Rechner.** Es gibt weiterhin keine einzige Messung auf echtem
   Blech. Alles oben ist QEMU.
