# MERGE-9 -- vier Zweige auf merge8

Basis: `merge8` e386da8. Arbeitsbaum `/root/osum-merge9`, Zweig `merge9`.

## 1. Was hineingekommen ist

| # | Zweig | HEAD | Dateien | Reihenfolge nach Konfliktrisiko |
|---|-------|------|---------|-------------------------------|
| 1 | `schnellbild` | f5b29d0 | 6 | SSE2-Alpha, Dirty-Rects |
| 2 | `laufzeit` | 4de8bc9 | 13 | 7 Syscalls, TLS fs-Register, fremdtrace |
| 3 | `fremdland` | 511179b | 33 | busybox, fork/Faeden, Sperren |
| 4 | `tuerschloss` | 40c05a1 | 286 | SYS_SPAWN, Shell, Alt+Tab, xhci, Compiler auf Stick |

**Alle vier ohne einen einzigen Konflikt.** Alle zweigen von derselben
Basis c0f7151 ab. `tuerschloss` hatte 16 Commits, nicht 7.

`schleuse2` (SCHLEUSE-3) ist NICHT dabei: die Pruefung
`tools/wasm2firn/pruefung/run.sh` lief noch, als diese Runde schloss.
Nichts dort angefasst -- SCHLEUSE-3 wird ein eigener Merge.

### Die Syscall-Frage, die keine war
`laufzeit` und `fremdland` vergeben BEIDE `SYS_ARCH_PRCTL=158`,
`READV=19`, `WRITEV=20`, `SET_TID_ADDRESS=218`, `PREAD64=17`,
`PWRITE64=18`, `FCNTL=72`. Das sind die Linux-Standardnummern, also
dieselbe Zahl fuer dieselbe Sache -- eine Textkollision, kein
Sachkonflikt. Nach dem Merge steht jede Nummer genau einmal:
158 -> 165 -> 168 Syscalls, keine Doppelbelegung, kdata 0 Kollisionen.

## 2. Das Wurzelabbild: 20 -> 32 MiB (Commit 33001a5)

`FS_BLOCKS` 40960 -> 65536. GEMESSEN am Abbild der Runde MERGE-8: bei
40960 blieben `free=8945`, also 4,4 MiB. Certus ist 6 493 760 Oktette
(6,19 MiB) und passte nicht.

WARUM DAS SICHER IST: seit OFS v3 ist die Blockkarte mehrblockig
(`SB_BMBLOCKS`). `FS_KARTEN=128` traegt 128*4096 = 524 288 Bloecke =
256 MiB; 65536 brauchen davon 16. Der Satz in STATUS-FREMDLAND.md
("4096 Bloecke = 2 MB je Platte") und der Kommentar in
`kernel/fs.fi:236` stammen aus der Zeit VOR OFS v3 -- das gebaute
Abbild meldet `bmblocks=128`.

Neu sind `CERTUS=`, `BUSYBOX=`, `LUA=`, `SQLITE=`: wer ein fertiges
Programm hat, gibt den Pfad an, es landet unter `/bin/`. Fehlt es,
bleibt es weg und der Bau laeuft weiter -- derselbe Weg, den `firnc`
schon geht. GEMESSEN: `blocks=65536 free=19225` (9,4 MiB frei),
`/bin/certus` 6 493 760, `/bin/busybox` 326 336, `/bin/lua` 380 488,
dazu `/bin/firnc` und `/bin/fas`. sqlite3 liegt nur als Quelle vor
(tools/fremd/), nicht als Binary -- der Platz dafuer ist da.

## 3. Der volle Lauf und die Endtafel

`test.sh`, OSUM_JOBS=4: **49 von 74 gruen, 25 rot, 5162 Zusagen.**

DIESE ZAHL IST NICHT DIE WAHRHEIT. Der Lauf stand unter Lastmittel
25-36: der eigene Lauf, SCHLEUSE-3 mit bis zu 7 QEMUs und der
Android-Emulator gleichzeitig. Elf Abschnitte hatten GENAU EINEN
Fehler mehr als merge8 -- das Muster von Zeitschranken, die reissen.
Deshalb ist jeder rote Abschnitt einzeln nachgefahren worden, seriell.

| Abschnitt | merge8 | Volllauf | seriell nachgefahren | Urteil |
|-----------|--------|----------|----------------------|--------|
| `kernel` | 176/0 | 175/1 | **176/0** | Lastflake |
| `net` | 75/0 | 74/1 | **75/0** | Lastflake |
| `init` | 78/0 | 77/1 | **78/0** | Lastflake |
| `multiuser` | 91/0 | 90/1 | **91/0** | Lastflake |
| `arm` | 48/0 | 47/2 | **gruen** (order.sh) | Lastflake |
| `smp` | 59/0 | 58/1 | 59/0 bzw. 58/1 | instabile Gegenprobe |
| `ahci` | 62/0 | 58/4 | 58/4 -- **merge8 heute auch 58/4** | vorbestehend/Umgebung |
| `tiling` | 68/0 | 67/1 | **68/0 nach Fix** | REGRESSION, behoben |
| `paint` | 32/1 | 30/3 | **32/1 nach Fix** | REGRESSION, behoben |
| `glyphe` | 28/1 | 27/2 | -- | = merge7/merge8-Solo (27/2) |
| `vielkern` | 38/2 | 37/3 | -- | beide rot, merge8 schlechter (133 vs 94) |
| `werkzeug` | 23/11 | **32/2** | -- | BESSER als merge8 |
| `usbimg` | 37/11 | **46/2** | -- | BESSER (das groessere Abbild) |
| `icons` | 25/2 | **25/0** | -- | BESSER |

Dreizehn weitere rote Abschnitte sind Zahl fuer Zahl dieselben wie in
merge8 (k15 20, display 3, theme 1, netview 13, powermon 2, server 2,
umlaut 5, softui 3, hid 1, modul 2, stick 22, systembus 1) --
vorbestehend, keine Regression.

`smp`: die Zusage "WITHOUT the lock: the same frame in two cores'
hands >= 1" will ein Rennen SEHEN. Gemessen ueber vier Laeufe: merge8
solo 5, merge9 Volllauf 0, merge9 solo 6, merge9 seriell 0. Die
Gegenprobe ist selbst unzuverlaessig, und zwar auf beiden Staenden.

## 4. Die zwei echten Regressionen (Commit 014f659)

**1. `kernel/wm.fi`: zwei Skalare auf einer Adresse.**
`S_PXSUM` lag auf `0x1130` -- dort steht seit Runde GLYPHE `S_LESER`
(wm.fi:554). Auf dem Zweig SCHNELLBILD war die Stelle frei;
zusammengefuehrt schrieben beide dasselbe Wort. Der Ableser haette die
Pixelsumme als "laeuft/laeuft nicht" gelesen, die Summe waere bei
jedem Anstrich ueberschrieben worden. Gefunden von
`tools/paint/run.sh` ("Skalare ueberschneiden sich"). `S_PXSUM` steht
jetzt auf `0x11C8`, dem ersten freien Wort hinter `S_VERWORF`.
Danach paint 32/1 -- FAIL-Menge identisch mit merge8.

**2. `tools/tiling/run.sh`: eine Zahl, die im Test stand.**
Runde TUERSCHLOSS hat `bind mod+tab next-window` (Alt+Tab) nach
`assets/tiling.conf` gelegt -- 21 Eintraege wurden 22. Abschnitt 9
verglich gegen die fest getippte 21 und wurde rot, obwohl Kern und
Ring 3 einig waren (beide 22). Abschnitt 8 rechnet `soll` schon aus
der Datei aus; Abschnitt 9 benutzt jetzt dieselbe Zahl. Danach 68/0.

## 5. Durchklick (pruef/durchklick3.py, pruef/appprobe.py)

**27 von 48 GEHT** bei 1280x800; Referenz aus BEFUND-DURCHKLICK-2 war
**29 von 48**. Genau ZWEI Punkte kippten: **3.4 (Editor starten)** und
**3.9 (Einstellungen starten)**.

Beide gehoeren zu der Gruppe, die BEFUND-DURCHKLICK-2 Abschnitt
"Maengel des Messaufbaus, nicht des Systems" schon benennt (3.4, 3.5,
3.9, 3.14, 3.15). Der Gegenbeleg kommt aus `pruef/appprobe.py`, dem
GLEICHEN Abbild und derselben Nacht:

    Eintrag 1 @(80,566): start=[]                                ready=['edit']
    Eintrag 2 @(80,586): start=[('/apps/settings.osp/start','21')] ready=['settings']

`settings` startet mit pid=21, `edit` meldet `ready`. Die Programme
laufen; der Durchklick trifft den Menueeintrag nicht zuverlaessig.
Alt+Tab wirkt: `wm: fokus 13 -> 15 -> 7`, vier umschaltbare Fenster.

## 6. Das Abbild

    orientos-usb-20260909-014f659.img   136 314 880 Oktette (130 MiB)
    sha256 46c77d36237ee094d10bb04f1957fda11418f7a29178a38837f4d1f8af025854

Gebaut mit `JARVIS_CONF=assets/jarvis/rechte-justin.conf`, dazu
CERTUS/BUSYBOX/LUA. Liegt in `/root/abbilder/` und
`/srv/store/abbilder/`, beide mit `.sha256`; die Kopie ist mit
`sha256sum -c` geprueft.
