# Runde OFS3 — den Zwei-Megaoktett-Deckel aufbrechen

**Stand:** 27.08.2026 · Branch `ofs3`, abgezweigt von `main` (`3389fbd`) ·
Abnahme: `bash tools/ofs3/run.sh` → **75 Zusagen, 0 Fehler**, Laufzeit 65 s ·
Nummernvorrat: kdata `0x5A000..0x5C000` (OFS3) und `0x60000..0x64000`
(uio, umgezogen), Systemaufrufe 6 / 88 / 89 / 280, Modusbits in einem
**eigenen** Wort (`kstate.OFS3_MODE`) · `tools/kernel/memmap.py`: **52
Bereiche, 0 Kollisionen**

---

## 1. Der Satz, um den es geht

**Osum konnte pro Platte zwei Megaoktett verwalten. Jetzt vier
Gibioktett — gemessen, nicht behauptet: ein Abbild von 8.388.608 Blöcken
wird gebaut, gebootet, und `df` im Gastsystem sagt
`blocks total=8388608 free=8385271`.**

Der Deckel stand seit Runde 62 im Quelltext und in keiner Roadmap. Er
hatte zwei Hälften, und die zweite war die unangenehmere:

1. **Die Blockkarte war ein Block.** 512 Oktette sind 4096 Bits, also
   4096 Blöcke, also 2 MiB. `kernel/fs.fi` sagte es selbst, in einem
   Nachsatz: *„4096 Blöcke, also zwei Megaoktett je Abbild. Wer mehr
   will, braucht eine mehrblockige Karte — das ist eine andere Runde."*
2. **Der Kern hat die Platte nie gefragt, wie groß sie ist.**
   `kernel/kmain.fi` meldete die Wurzelplatte mit der Konstanten
   `OSUM_BLOCKS = 4096` an — ganz gleich, was wirklich dran hing. Eine
   Platte von 32 MiB lief nach 2 MiB voll und meldete ENOSPC, während
   30 MiB unberührt dalagen. **Die mehrblockige Karte allein hätte gar
   nichts gebracht.** Das ist im ersten Rauchtest dieser Runde
   aufgefallen und nicht in der Planung.

---

## 2. Was Fassung 3 ändert, in Zahlen

Alle vier Zahlen kommen jetzt **aus dem Superblock** und nicht mehr aus
einer Konstanten des Übersetzers. Genau das macht die Gegenprobe
möglich: derselbe Kern, ein anderes Abbild, andere Grenzen.

| | Fassung 2 | Fassung 3 |
|---|---|---|
| Blockkarte | 1 Block, 4096 Blöcke | `SB_BMBLOCKS` Blöcke, je 4096 Bits |
| größte Platte | 2 MiB | so viel wie die Karte trägt (gemessen: 4 GiB) |
| Inode | 128 Oktette | 256 Oktette |
| Zeitstempel | keine | drei (erzeugt, geändert, zugegriffen) |
| indirekte Stufen | einfach, doppelt | zusätzlich **dreifach** |
| größte Datei | **2.134.016** Oktette | **136.351.744** Oktette |
| Verzeichniseintrag | 32 Oktette | 264 Oktette |
| längster Name | 23 Zeichen | **255 Zeichen** |
| Inodearten | `T_FREE`, `T_FILE`, `T_DIR` | zusätzlich **`T_LINK`** |
| `rename` | gibt es nicht | echte Verrichtung, ein Inode bleibt ein Inode |

Wörtlich aus `tools/osum/mkfs.py`, drei Läufe:

```
mkfs: v1.img  blocks=4096   free=3737   inodes=4/128   data=34   version=1 bmblocks=1    isize=128 dirent=32  namelen=24  maxfile=2135552
mkfs: v2.img  blocks=4096   free=2912   inodes=16/128  data=34   version=2 bmblocks=1    isize=128 dirent=32  namelen=24  maxfile=2134016
mkfs: v3.img  blocks=131072 free=129367 inodes=16/1024 data=545  version=3 bmblocks=32   isize=256 dirent=264 namelen=256 maxfile=136351744
mkfs: 4g.img  blocks=8388608 free=8385271 inodes=16/256 data=2177 version=3 bmblocks=2048 isize=256 dirent=264 namelen=256 maxfile=136351744
```

Der Preis der Karte ist der Rede kaum wert: **2048 Blöcke = 1 MiB für
4 GiB Platte, also 0,02 %.** Der Preis des längeren Namens ist echt und
steht in Abschnitt 8.

---

## 3. Die zweite Hälfte: ATA IDENTIFY

`kernel/blk.fi` hat jetzt `capacity(state)`. Es stellt den Befehl 0xEC
und liest die Sektorzahl aus den Wörtern 60/61 (LBA28) bzw. 100..103
(LBA48). `kmain.fi` benutzt sie über `root_blocks(state)`; antwortet die
Platte nicht, bleibt es bei `OSUM_BLOCKS`, und **kein Lauf, der vorher
funktioniert hat, fällt dadurch aus**.

Die Obergrenze ist ehrlich gedeckelt: dieser Treiber legt die
Blocknummer in die vier unteren Bits des Laufwerksregisters — das ist
LBA28, 268.435.456 Sektoren, 128 GiB. Was darüber liegt, kann er nicht
lesen, also behauptet er es auch nicht.

Der Unterschied, gemessen an derselben Platte von 32 MiB:

```
vorher:  blocks total=4096    free=2741  used=1355
nachher: blocks total=65536   free=64247
```

---

## 4. Die Zusagen, in Ring 3 gemessen

`kernel/user/ofs3.fi` ist ein gewöhnliches Ring-3-Programm. Es geht
durch dieselben Systemaufrufe wie jedes andere — `open`, `write`,
`stat`, `lstat`, `symlink`, `readlink`, `rename`, `getdents` — und
schreibt Zahlen, keine Sätze. Wörtlich von der seriellen Leitung:

```
ofs3: grossdatei = 2396160      (die alte Grenze war 2134016)
ofs3: lesen1 = 512              (512 von 512 Oktetten richtig, am Anfang)
ofs3: lesen2 = 512              (512 von 512, HINTER der alten Grenze)
ofs3: lesen3 = 512              (512 von 512, ganz am Ende)
ofs3: namelen = 255
ofs3: nameok = 1
ofs3: dentlen = 255             (über getdents in voller Länge zurück)
ofs3: ctime = 1787812980
ofs3: mtime0 = 1787812980
ofs3: mtime1 = 1787812982       (nach zwei Sekunden und einem Schreiben)
ofs3: linkok = 1
ofs3: linklen = 9               ("/tmp/zeit")
ofs3: linklstat = 1             (lstat sieht den Verweis)
ofs3: linkstat = 1              (stat sieht die Datei dahinter)
ofs3: linkread = 1
ofs3: rename = 0
ofs3: ino1 = 21
ofs3: ino2 = 21                 (DIESELBE Inode -- umbenannt, nicht kopiert)
ofs3: viele = 120
ofs3: ende = 1
```

Der Sollwert jeder zurückgelesenen Stelle ist **aus der Stelle
ausgerechnet** (`(pos * 2654435761) % 251`), nicht gemerkt. Ein
Dateisystem, das den falschen Block liefert, fällt damit auf, statt eine
Null zu liefern, die wie eine Null aussieht.

---

## 5. Die Gegenproben

Eine Eigenschaft ohne Gegenprobe ist eine Behauptung. Jede hier fällt,
und das Fallen ist die Messung.

**Dasselbe Programm auf einer Platte der Fassung 2** (derselbe Kern,
dasselbe Abbild bis auf den Superblock):

```
ofs3: nameok = 0        der 255-Zeichen-Name geht dort nicht
ofs3: ctime = 0         die Zeitstempel sind null
ofs3: mtime0 = 0
```

**`ls -l` derselben Datei, einmal je Fassung:**

```
Fassung 3:  -        0 2026-08-27 06:43 marke
Fassung 2:  -        0 1970-01-01 00:00 marke
```

**`nolinks`** auf der Befehlszeile: derselbe Kern folgt keinem
symbolischen Verweis mehr, `cat /zeiger` bringt nichts zurück.

**`ofs3fmt`**: `fs.format` baut Fassung 3 statt Fassung 2 — ein Wort
Unterschied, und die größte Platte steigt von zwei Megaoktett auf
Gigaoktette. Wären die Grenzen im Übersetzer statt im Superblock,
könnte dieser Unterschied gar nicht entstehen.

**`noatime`**: die Zugriffszeit wird beim Öffnen nicht nachgeführt.

---

## 6. Der weite Block

Die Zahl im Superblock ist noch kein Beweis. `mkfs.py --reserve=<n>`
markiert die ersten *n* Datenblöcke als belegt, ohne sie irgendeiner
Datei zu geben; die Datei landet dann dort, wo man sie haben will.

```
where /weit.txt ino=16 size=27 blocks=1 first=201252 last=201252
```

Block **201252** — dafür gab es in Fassung 2 kein Bit. Der Kern liest
die Datei, schreibt sie neu, und der **Wirt** liest zurück, was der Kern
hingelegt hat (`mkfs.py cat` auf das Abbild nach dem Lauf). Danach liegt
sie immer noch bei 201252.

---

## 7. Die Zeit überlebt den Neustart

Zwei QEMU-Läufe auf **derselben** Plattendatei, nichts wird dazwischen
neu gebaut:

```
ls -l nach dem Anlegen:  -        0 2026-08-27 06:43 marke
ls -l nach dem Neustart: -        0 2026-08-27 06:43 marke
```

Zeichen für Zeichen gleich. Und die Programme benutzen die Zeit
wirklich:

* `ls -l` zeigt sie als Datum (`sag_zeit` rechnet Sekunden seit 1970 in
  Jahr/Monat/Tag/Stunde/Minute um, mit Schaltjahren).
* `tar` schreibt sie ins mtime-Feld bei Versatz 136 — gemessen:
  **1787813168**, aus dem Archiv auf dem Wirt oktal zurückgelesen.
  Vorher stand dort eine Null.
* `find -newer DATEI` und `find -mtime ±N` gibt es überhaupt erst seit
  dieser Runde. Gemessen: `touch /tmp/alt; sleep 2; touch /tmp/neu;
  find /tmp -newer /tmp/alt` findet `/tmp/neu` und **nicht** `/tmp/alt`.
* Der Datei-Explorer hat eine Spalte „Zeit", die nicht mehr leer ist.

---

## 8. Was es kostet

* **Ein Verzeichniseintrag ist von 32 auf 264 Oktette gewachsen.** Ein
  Verzeichnis mit viertausend kurzen Namen wächst von 128 KiB auf
  1,06 MiB. Das ist der Preis für 255 Zeichen, und er ist bezahlt
  worden, weil ein Dateisystem mit 23-Zeichen-Namen kein Alltagssystem
  trägt (die Paketverwaltung musste SHA-256 auf 20 Hexziffern kürzen).
* **Die Inodetabelle ist doppelt so groß.** 128 Inodes zu 256 Oktetten
  sind 64 Blöcke statt 32. Deshalb steht `data=545` bei einem Abbild mit
  1024 Inodes.
* **`fs.format` im Kern baut weiter Fassung 2.** Der erste Entwurf hat
  es andersherum gemacht, und `tools/kernel/run.sh` ist daran gefallen:
  1980 statt 2018 freie Blöcke nach dem Formatieren einer RAM-Platte von
  2048 Blöcken. Diese Zusage ist älter als die Runde und misst etwas
  Richtiges. Der Wirt (`mkfs.py`) hält es genauso: ohne `--v3`
  Fassung 2.

---

## 9. Aufwärtskompatibilität

Die Fassungsnummer steht seit Runde K13 im Superblock bei Versatz 64,
und eine Null dort heißt „Fassung 1". Genauso heißt eine Null in **jedem
der vier neuen Felder** „so wie vorher": Karte = ein Block, Inode = 128,
Eintrag = 32, Name = 24. Ein Abbild aus Runde 62 sagt damit von selbst
das Richtige, ohne dass jemand es anfasst.

Gemessen, beide mit demselben Kern:

```
Fassung 1:  osum: mount=1   sh: ready, osum   k13: ofsver=1
Fassung 2:  osum: mount=1   sh: ready, osum   k13: ofsver=2
```

Und die Vorgabe hat sich nicht verschoben: ohne `--v3` baut `mkfs.py`
weiter `version=2 bmblocks=1 isize=128 dirent=32 namelen=24` mit
`data=34`, und zwei Läufe geben Oktett für Oktett dasselbe Abbild.

---

## 10. Was NICHT bewiesen ist

Das ist der wichtigste Abschnitt dieses Logbuchs.

* **Vier Gibioktett sind gemessen, mehr nicht.** Das Format kann mehr
  (`bmblocks` ist ein 64-Bit-Wort), und der ATA-Treiber kann bis 128 GiB
  (LBA28). Zwischen 4 GiB und 128 GiB ist **nichts gemessen**. Wer eine
  Zahl dazwischen braucht, muss sie messen.
* **Die 4-GiB-Platte ist ein Loch.** Der Wirt legt sie als Sparse-Datei
  an (4,0 GiB angemeldet, 2,2 MiB belegt). Der Kern hat davon die
  Superblock-, Karten- und Inodeblöcke und ein paar Datenblöcke wirklich
  angefasst. **Eine volle 4-GiB-Platte ist nicht geschrieben worden.**
* **Die größte Datei ist rechnerisch 136.351.744 Oktette; geschrieben
  wurden 2.396.160.** Der dreifach indirekte Zeiger ist im Format da und
  in `mkfs.py` und `fs.fi` umgesetzt, aber eine Datei, die ihn wirklich
  braucht (über 2.135.552 Oktette hinaus in die dritte Stufe), ist nicht
  gemessen worden — bei ATA-PIO in QEMU wäre das ein Lauf von vielen
  Minuten.
* **`free_blocks` ist linear in der Plattengröße.** Bei 8.388.608
  Blöcken liest `df` 2048 Kartenblöcke. Das ist in QEMU schnell genug
  gewesen; auf einer echten Platte mit echter Latenz ist es nicht
  gemessen.
* **Es gibt keinen harten Verweis aus Ring 3.** `link(2)` gibt es in
  diesem Kern nicht. `ln` ohne `-s` legt deshalb einen SYMBOLISCHEN
  Verweis an und sagt es auf die Fehlerausgabe. `mkfs.py` kann harte
  Verweise auf dem Wirt (`<neu>@<vorhanden>`), das Gastsystem nicht.
* **Verweisketten sind auf acht begrenzt.** Neun hintereinander laufen
  ins Leere. Eine Schleife von zwei Verweisen aufeinander ist nicht
  eigens gemessen.
* **`rename` über Einhängegrenzen hinweg gibt `-EXDEV`.** Das ist
  richtig so, aber die einzige Umsetzung ist die Prüfung in `vfs.fi`;
  ein Umbenennen von OFS nach FAT32 ist nicht gemessen.
* **`rename` überschreibt nicht.** Ein vorhandenes Ziel gibt `-EEXIST`.
  POSIX verlangt, dass es still ersetzt wird. Das ist eine bewusste
  Abweichung und keine Nachlässigkeit — aber sie ist eine Abweichung.
* **`rename` braucht `vfs` auf der Befehlszeile.** Ohne die Schicht aus
  Runde K14 gibt der Systemaufruf `-ENOSYS` zurück. Das ist die
  bestehende Bauart des Systems, hier nur festgehalten, damit niemand
  glaubt, `mv` benenne in jedem Lauf um.
* **Der Zeitstempel kommt aus `time.fi`.** Wie genau die Uhr geht, ist
  Sache jener Runde und hier nicht nachgemessen worden. Gemessen ist
  nur: die Zahl ist nicht null, sie steigt beim Schreiben, und sie
  überlebt einen Neustart.
* **`tools/k16/run.sh` und drei Zusagen in `tools/k13`/`tools/k14`
  bleiben rot** — sie sind es auf `main` (3389fbd) genauso, mit einem
  eigenen Arbeitsbaum nachgemessen. Siehe Abschnitt 11.

---

## 11. Was nebenbei aufgefallen ist

Zwei Fehler, die **älter sind als diese Runde**, hat sie ans Licht
gebracht, weil die alten Abnahmen noch einmal liefen. Beide fallen auf
`main` (3389fbd) genauso; das ist mit einem eigenen Arbeitsbaum an
derselben Stelle nachgemessen worden, damit nicht diese Runde die Schuld
bekommt. Sie stehen in einem **eigenen Commit**.

**1. `sched.T_BIG` lag auf demselben Versatz wie `sched.T_UID` (392).**
`do_exec` setzt `T_BIG` auf 0, wenn ein neues Abbild anfängt — und hat
damit die **echte Benutzerkennung bei jedem `execve` auf 0
zurückgesetzt**. Das ist keine Schönheitsfrage: `su` fragt nur dann nach
einem Passwort, wenn die echte Kennung nicht 0 ist. Nach `su justin` kam
jedes weitere `su root` **ohne Passwort** durch. `tools/k13/run.sh`
sagte auf `main` genau das:

```
FAIL  justin: die eigene Kennung nach su: '0', erwartet '1000'
FAIL  su lehnt ein falsches Passwort ab -- 'su: falsches Passwort' fehlt
```

`T_BIG` liegt jetzt auf 448. Ein Datensatz ist 512 Oktette groß, das
letzte belegte Feld war `T_UMASK` bei 440. **k13 fällt damit von 12 auf
3 Fehler.**

**2. Die Ausnahmeliste in `tools/k16/run.sh` war stehengeblieben.** Sie
kannte `flate`, `tools` und `ulib` als Bibliotheken ohne `u_start` —
aber nicht `appdir`, `nidx`, `pw`, `wlib` und `wlibc`, die seit den
Runden K15/K16 dazugekommen sind und in ihrer ersten Zeile selbst
sagen, was sie sind. Der Binder bekam sie als Programme und scheiterte
an `_F1.u_start`. Auf `main`: „70, erwartet eq 75". **k16 fällt von 6
auf 4 Fehler.**

Der Stand der alten Abnahmen, jede Zahl aus einem Lauf:

| Abnahme | `main` (3389fbd) | Zweig `ofs3` |
|---|---|---|
| `tools/k13/run.sh` | 12 Fehler | **3** (dieselben drei auch auf `main`) |
| `tools/k14/run.sh` | 8 Fehler | **8** (dieselben acht) |
| `tools/k15/run.sh` | 0 Fehler | **0** (825 s Laufzeit) |
| `tools/k16/run.sh` | 6 Fehler | **4** (Teilmenge von `main`) |
| `tools/k18/run.sh` | 0 Fehler | **0** (170 Zusagen) |
| `tools/kernel/run.sh` | — | **0** (176 Zusagen) |
| `tools/osum/run.sh` | — | **0** (130 Zusagen) |
| `tools/posix/run.sh` | — | **0** |
| `tools/wm/run.sh` | — | **0** |
| `tools/ofs3/run.sh` | — | **0** (75 Zusagen) |
| `tools/mem/run.sh` | — | **0** (50 Zusagen) |

**Keine einzige Zusage ist durch diese Runde rot geworden.** Was rot
bleibt, war es vorher schon.

**EINE MESSFALLE, DIE HIER STEHEN MUSS:** diese Zahlen gelten nur, wenn
die Abnahmen EINZELN laufen. Sechs Laeufer gleichzeitig auf zwoelf
Kernen unter QEMU/TCG erzeugt Fehlalarme in Serie -- `tools/ofs3/run.sh`
hat parallel 29 Fehler gemeldet und allein null, `tools/k14/run.sh`
schwankte zwischen 7 und 17. Die Ursache ist Zeit und nicht Code: die
Laeufer haben Zeitlimits, und ein Gastsystem, das sich seine Sekunde
teilen muss, schaltet sich anders ab. Wer diese Runde nachmisst, faehrt
die Laeufer nacheinander.

---

## 12. Wie man es nachmisst

```
bash tools/ofs3/run.sh          # 75 Zusagen, ~65 s
python3 tools/kernel/memmap.py   # 52 Bereiche, 0 Kollisionen

# eine Platte von vier Gibioktett von Hand
python3 tools/osum/mkfs.py build /tmp/4g.img 8388608 --v3 --inodes=256 \
    --time=$(date +%s) /bin/ /bin/sh=... /bin/df=...
qemu-system-x86_64 -kernel osum.mb -m 512 -append "osum vfs script=df;exit" \
    -drive file=/tmp/4g.img,format=raw,if=ide,index=0 ...
```

Neue Befehle von `mkfs.py`:

```
mkfs.py build <abbild> <bloecke> [--v1] [--v3] [--inodes=n] [--time=t] [--reserve=n]
mkfs.py where <abbild> <pfad>     # an welchen Bloecken die Datei liegt
mkfs.py times <abbild> <pfad>     # Art und die drei Zeiten aus dem Inode
```

`<pfad>-><ziel>` in der Bauliste legt einen symbolischen Verweis an.

Neue Wörter auf der Befehlszeile des Kerns: `ofs3run`, `ofs3fmt`,
`noatime`, `nolinks`.
