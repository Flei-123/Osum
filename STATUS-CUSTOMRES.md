# STATUS -- Runde CUSTOMRES

Zweig `customres`, abgezweigt von `mergeline` (adaa9c7). **NICHT nach
`main` gemergt.** Worktree `/root/osum-customres`.

Justins Frage: *"Kann man auch benutzerdefinierte Auflösungen erstellen
wie im NVIDIA-Control-Panel?"*

Antwort in einem Satz: **ja, unter QEMU -- mit drei Schranken, die jede
ihre Zahl nennt, einer Frist, die jetzt wirklich von selbst abläuft, und
einem gespeicherten Modus, den ein Zähler nach drei unbestätigten Starts
wieder los wird. Auf echtem Blech: nein, und warum, steht in
docs/DISPLAY.md A4.**

---

## Ausgangslage (selbst nachgemessen, nicht übernommen)

| | |
| --- | --- |
| `bash tools/display/run.sh` auf `mergeline` | **145 passed, 0 failed** |
| Modi, die die Karte hergibt (QEMU 7.2.22, `-vga std`) | 18 von 22 Kandidaten |
| Bildspeicher | 16 777 216 Oktette |
| Kachelgrenze (`maplimit`) | 12 582 912 Oktette |
| `set_mode(777, 333, 32)` | `E_NOMODE` -- was nicht in der Liste steht, geht nicht |
| Fensterplätze | `alle=8  frei=5  belegt=3  fb=2  laufmax=6` |

---

## Was gebaut wurde

| Datei | was |
| --- | --- |
| `kernel/vmode.fi` | `set_mode` -> `switch_to` + Listenprüfung · `check_custom`/`set_custom` mit drei Schranken · sortiertes Einschieben · `poll` mit Riegel · 9 eigene Zusagen |
| `kernel/dispsave.fi` (neu) | `/system/BILDMODUS`, 31 Oktette feste Breite, Erprobungszähler wie beim A/B-Boot |
| `kernel/tasks.fi` | die Leerlaufaufgabe ruft `vmode.poll` -- **das** lässt die Frist wirklich ablaufen |
| `kernel/sys.fi` | `DS_CUSTOM`, `DS_CHECK`, `DS_SAVE`; `DS_CONFIRM` speichert jetzt auch; `DG_CUSTWHY`/`DG_CUSTNUM` + 7 Felder zum gespeicherten Modus. **Keine neue Aufrufnummer.** |
| `kernel/kmain.fi` | Wörter `dispeigen`, `dispeigenbad`, `dispeigenfrist`; der Startvorgang; `disp: kacheln` |
| `kernel/user/dispctl.fi` | `eigen`, `pruefen`, `speichern`, `testc` -- und der Grund als **Satz** |
| `kernel/user/einstellungen.fi` | drei Eingabefelder, zwei Knöpfe, die Zeile mit Schranke und Zahl |
| `tools/customres/run.sh` (neu) | die Abnahme, neun Abschnitte, mit Bildschirmfotos |
| `docs/CUSTOMRES.md` (neu), `docs/DISPLAY.md` (Nachtrag A1-A4) | die Zahlen und der ehrliche Befund zur 16-MiB-Grenze |

---

## Die Zahlen

### Eine eigene Auflösung

```
disp: eigen 1400x1050x 32  rc=0  why=0  num=5880000  custom=1
     panel=1400x1050  us=13897
```

Bildschirmfoto: **1400 x 1050**, Prüfbild bildpunktgenau gegen den
Zeichensatz. 1400x1050 steht in **keiner** Kandidatenliste -- der Läufer
sieht das im Quelltext nach, sonst misst der Abschnitt nichts.

### Die drei Schranken, jede mit ihrer Zahl

```
2560x1440x32  rc=8  why=3  num=14745600   maplimit=12582912  vram=16777216
1366x768x32   rc=4  why=1  num=1360       (QEMU machte aus 1366 -> 1360)
1400x1050x16  rc=6  why=4  num=16
```

Und **dieselbe Zahl an eine kleinere Karte** (`vgamem_mb=8`):

```
2560x1440x32  rc=7  why=2  num=14745600   vram=8388608
```

Grund 3 -> Grund 2, ohne dass ein Wort der Meldung zweimal geschrieben
wäre. Eine Begründung, die sich mit der Maschine ändert, ist eine
Messung.

### Die Frist läuft ohne jedes Zutun ab

Ein Programm in Ring 3 schaltet um und legt sich schlafen:

```
script=dispctl eigen 1400 1050;sleep 22;dispctl raw
   panelw=1400  pending=1                 direkt nach dem Wechsel
   panelw=800   pending=0  reverts=1      nach 22 Sekunden Schlaf
   switches=2   confirms=0
```

Dazwischen lief nur `/bin/sleep`, und das ruft keinen Bildschirmaufruf.
Zurückgeschaltet hat die Leerlaufaufgabe -- oder niemand.

**Vorher (gemessen, vor der Berichtigung): `panelw=1400  reverts=0`.**
Die Frist war da, sie lief nur nicht.

### Der Neustart, fünf Starts auf derselben Platte

```
1  save none                            eigene Auflösung + "Behalten"
2  save on 1400x1050x 32  v=1           panelw=1400  saveapp=1
3  save on 1400x1050x 32  v=2           panelw=1400
4  save aufgebraucht  v=2  (Startmodus bleibt)   panelw=800
5  save none                            panelw=800  (keine Schleife)
```

Gegenprobe: nach dem Neustart `savetry=1`, nach `dispctl behalten`
`savetry=0`.

### Die Zusagen

| | |
| --- | --- |
| `disp: selftest` (Runde DISPLAY) | **15 / 15**, unverändert |
| `disp: custom selftest` (diese Runde) | **9 / 9** |
| `dispctl test` (Runde DISPLAY, Ring 3) | **12 / 12**, unverändert |
| `dispctl testc` (diese Runde, Ring 3) | **10 / 10** |
| `fb: selftest` / `selftest2` | **13 / 13** und **11 / 11**, unverändert |

---

## Die 16-MiB-Grenze -- geprüft, nicht angefangen

**Der Gewinn wäre echt.** Mit `-device VGA,vgamem_mb=64` nehmen QEMUs
Register 3840x2160 an; übrig bleibt genau eine Schranke, nämlich diese:

```
vgamem_mb=16   disp: out 3840x2160  reason=1   (die Karte lehnte ab)
vgamem_mb=64   disp: out 3840x2160  reason=3   (dieser Kernel kann es nicht)
```

**Der Eingriff wäre zu groß für diese Runde**, und der Grund ist nicht
Aufwand, sondern wo das Fenster liegt: in der **einen** Seitentafel, die
sich jeder Prozess mit dem Kern teilt (`proc.fi` kopiert genau `PDPT[0]`
und legt sein eigenes `PDPT[1]` daneben). Ein zweites Verzeichnis müsste
in jeden Prozess-PDPT kopiert werden und stieße mit `mem.idmap_grow`
zusammen, das `PDPT[1]`, `PDPT[2]`... mit der Identitätsabbildung des
Arbeitsspeichers füllt. Betroffen wären `boot.s`, `proc.fi`, `mem.fi`,
`apic.fi`, `fb.fi` und ein neuer `kdata`-Bereich für die Belegungsliste.

Vollständig aufgeschrieben in **docs/DISPLAY.md, Abschnitt A3** --
einschließlich der billigeren Hälfte (zwei Plätze mehr würden 2560x1440
bringen, aber nicht 4K) und der Altlast, die dabei zuerst zu bezahlen
wäre.

---

## Echte Hardware (Justins PC, 30.08.2026)

Gemessen an zwei Grafikgeräten, die nicht der Bochs-Aufsatz sind:

```
-vga cirrus                       fb: kein Rahmenpuffer
-vga none -device bochs-display   pci: 00:03.0 1234:1111 class=03:80:00
                                  fb: kein Rahmenpuffer
```

Das zweite ist das lehrreiche: **dieselbe PCI-Kennung, dieselben 16 MiB,
auf dem Bus gefunden -- und trotzdem kein Bildschirm**, weil es die
MMIO-Variante ohne das Torpaar 0x1CE/0x1CF ist.

| | auf echtem Blech? |
| --- | --- |
| überhaupt ein Bild | **ja** (Multiboot-Rahmenpuffer vom Lader, `SRC_MB`) |
| Modusliste, EDID, alle `disp:`-Zahlen | **nein** -- `vmode.ready` bleibt 0 |
| eigene Auflösungen (diese Runde) | **nein** |
| die Fünfzehn-Sekunden-Frist | **nein** -- es gibt nichts umzuschalten |
| `/system/BILDMODUS` und der Zähler | **nein** |
| Helligkeit/Gamma/Drehung/Skalierung | **nein -- und das ist ein Versehen**, siehe unten |

Die letzte Zeile ist der einzige Befund hier, mit dem man etwas tun
sollte: die sechs rechnen in `fb.present` auf der CPU und brauchen gar
keine Karte -- sie hängen nur am selben `vmode.ready`. **Diese Runde hat
es absichtlich nicht geändert**, weil Abschnitt 11 von
`tools/display/run.sh` zu Recht zusichert, dass ohne `disp` *jeder* dieser
Aufrufe `-ENODEV` sagt. Das Tor zu teilen ist eine kleine Änderung mit
einem Test daran und gehört der Runde, die das auf Blech startet.

---

## Abnahme

Der Zweig lag bis zuletzt auf `adaa9c7` -- dem Stand von `main`, von dem
die Grundlinie genommen wurde. `mergeline` war inzwischen siebzehn
Commits weiter (Runde TESTFAST: `test.sh` parallelisiert,
`tools/lib/qemu.sh` als **eine** Stelle für die Wahl zwischen kvm und
tcg). Der Merge lief konfliktfrei; danach wurde beides erneut gemessen,
und der Läufer dieser Runde hängt jetzt an der zentralen Accel-Wahl
statt an seiner eigenen zwei Zeilen langen Fassung.

| Läufer | vor dem Merge | nach dem Merge |
| --- | --- | --- |
| `tools/customres/run.sh` | 135 passed, 0 failed | **135 passed, 0 failed** |
| `tools/display/run.sh` | 145 passed, 0 failed | **145 passed, 0 failed** |

`./test.sh` (voller Lauf, vor dem Merge, parallel): **30 Abschnitte
bestanden, 7 fehlgeschlagen, 3278 Zusagen**. Abschnitt 28 --
`tools/customres/run.sh` -- ist seit `CUSTOMRES 11/n` darin eingetragen.

### Die sieben roten Abschnitte, einzeln nachgemessen

Ein voller Lauf sagt nicht, WOHER ein rotes Feld kommt. Jeder der sieben
wurde deshalb einzeln gemessen, auf `mergeline` **und** auf diesem
Zweig, seriell statt parallel:

| Abschnitt | `mergeline` | dieser Zweig | Befund |
| --- | --- | --- | --- |
| K14 | 146 passed, 6 failed | 151 passed, 1 failed | vorbestehend, in `GRUNDLINIE.md` benannt |
| K16 | 58 passed, 6 failed | 58 passed, 6 failed | vorbestehend, in `GRUNDLINIE.md` benannt |
| THEME | 91 bestanden, 0 durchgefallen | **91 bestanden, 0 durchgefallen** | im Vollauf 89/7 -- Laststörung |
| icons | 24 ok, 1 failed | 24 ok, 1 failed | vorbestehend (`lib/icons.fi does not match the map`) |
| tunnelpakete | 15 bestanden, 3 fehlgeschlagen | 15 bestanden, 3 fehlgeschlagen | vorbestehend |
| netview | siehe unten | siehe unten | vorbestehend |
| ARM | 48 passed, 0 failed | **48 / 48 / 47** in drei Läufen | flattert, siehe unten |

Keiner der sieben liegt an dieser Runde. Der Diff dieses Zweiges gegen
`mergeline` fasst fünfzehn Dateien an, und **keine einzige davon** wird
von einem der sieben Läufer gebaut oder gelesen: `kernel/vmode.fi`,
`kernel/dispsave.fi`, `kernel/kmain.fi`, `kernel/sys.fi`,
`kernel/tasks.fi`, `kernel/user/dispctl.fi`,
`kernel/user/einstellungen.fi`, `test.sh`, `tools/customres/run.sh` und
sechs Dateien unter `docs/`.

### ARM: der Fehlschlag ist eine Messstörung, und das ist nachgerechnet

`tools/arm/run.sh` meldete im Vollauf `_F0.amain__kmain is missing`, in
einer Wiederholung `_F0.amain__kexception is missing` -- **zwei
verschiedene Symbole aus derselben Datei**. Das allein ist schon ein
Hinweis, dass nicht das Bild fehlerhaft ist, sondern die Messung. Drei
Zahlen dazu:

* **Der Build ist bit-identisch reproduzierbar.** Sechs Läufe von
  `tools/arm/build.sh` auf diesem Zweig: sechsmal dieselbe Prüfsumme
  (`b1cdbc69…`), sechsmal 121 Symbole mit dem Präfix `_F0.`, und
  sechsmal sind **beide** gesuchten Symbole im Bild.
* **Bei Ruhe schlägt die Prüfung nie fehl.** Dieselbe ELF-Datei,
  dreihundertmal `aarch64-linux-gnu-nm … | grep -q " _F0.amain__kmain$"`:
  **0 Fehlschläge von 300**.
* **Unter Last flattert sie.** Drei volle Läufe des Abschnitts auf
  diesem Zweig, während andere Abnahmen liefen: 48/0, 48/0, 47/1.

Der Läufer ruft `nm` viermal auf und prüft dessen Rückgabewert nicht;
scheitert der Aufruf unter Speicher- oder Prozessdruck, ist das für den
Test nicht von einem fehlenden Symbol zu unterscheiden. Das ist ein
echter Mangel -- aber ein Mangel des ARM-Läufers, nicht dieses Zweiges,
und er wird hier **nicht** angefasst: `nm` einmal aufrufen, Rückgabewert
und leere Ausgabe getrennt melden, ist eine Verschärfung und gehört in
die Runde, der der Läufer gehört. Hier steht die Zahl, mit der sie
anfangen kann.

Kein bestehender Test wurde entschärft. Die neun Zusagen des
Modustreibers und die zehn aus Ring 3 stehen in **eigenen** Zählern
(`selftest_custom`, `testc`) -- eine bestehende Zahl zu erhöhen, um eine
neue Zusage unterzubringen, wäre die bequeme Art, eine alte anzufassen.
