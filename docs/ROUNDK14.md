# Runde K14 — VFS und fremde Dateisysteme

**Stand:** 26.08.2026 · Branch `k14-vfs`, abgezweigt von `main` (`7a53ac3`)
· Abnahme: `bash tools/k14/run.sh` → **146 Zusagen, 0 Fehler**
· Vollabnahme: `./test.sh` → Abschnitt 20 dazu, keine bestehende Zusage
verloren.

---

## 1. Das Problem, mit dem diese Runde anfing

Osum kannte **genau ein** Dateisystem: sein eigenes, OFS
(`kernel/fs.fi`). `mount` gab es als Kernelfunktion und als Befehl, aber
es hatte **kein Ziel** — es hiess „die eine Platte ist da" und setzte
eine Eins in `kstate.FS_READY`. Der Kommentar in `kernel/sys.fi` sagte es
selbst:

> `mount(op, 0, 0)`: 0 fragt nach (1 = eingehaengt), 1 haengt ein […]
> Dateisystem auf EINER Platte, und ein `mount` mit Geraetenamen und
> Ziel waere eine eigene Runde.

Drei Folgen, und alle drei waren im Baum sichtbar:

* **Kein `/proc`.** `ps` und `top` fragten stattdessen über einen
  Sonderaufruf (`SYS_OSUM_PSTAT`, Nummer 1003, Runde K6) — eine eigene
  ABI für eine Frage, die jedes Unix über das Dateisystem beantwortet.
* **Kein `/dev` als Verzeichnis.** Runde K7 brauchte den Rahmenpuffer in
  Ring 3 und fing dafür in `sys.do_open` den Namen `/dev/fb` ab, *bevor*
  irgendetwas nachgeschlagen wurde. Der Kommentar dort war ehrlich: „Ein
  Osum mit einem echten Geraeteverzeichnis waere eine eigene Runde."
* **Jede fremde Platte war leer.** Osum sah in Block 0 nach einem
  OFS-Superblock. Auf jeder Platte, die Linux oder Windows beschrieben
  hat, steht dort eine *Partitionstafel*.

---

## 2. Was jetzt da ist

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/vfsops.fi` | 138 | Die **Form**, in der sich ein Dateisystem anmeldet: neun Funktionszeiger plus eine Bitmaske |
| `kernel/mnt.fi` | 327 | Die **Einhängetafel**: 8 Einträge zu 128 Oktetten |
| `kernel/vfs.fi` | 530 | Der **Namensraum**: Auflösung über Grenzen, Ein- und Aushängen, die neun Verrichtungen |
| `kernel/ofs.fi` | 178 | OFS als **Treiber** dieser Schicht |
| `kernel/procfs.fi` | 1226 | `/proc`, im Speicher erzeugt |
| `kernel/devfs.fi` | 444 | `/dev` als echtes Dateisystem |
| `kernel/part.fi` | 498 | MBR und GPT, mit **beiden** CRC32-Prüfsummen |
| `kernel/fat.fi` | 1802 | FAT32, lesend **und** schreibend, mit langen Namen |
| `kernel/user/k14.fi` | 701 | Das Messprogramm in Ring 3 |
| `tools/k14/run.sh` | 612 | Der Testläufer |

Dazu geändert: `blk.fi` (zweite Platte, gerätebezogenes Lesen/Schreiben),
`file.fi` (`K_VFILE`=12, `K_VDIR`=13, Feld `OF_MNT`), `fs.fi`
(`rename_path`), `bootmod.fi` (CRC32 fortschreibbar), `atomic.fi`
(`L_PROC`), `kstate.fi`, `sys.fi`, `kmain.fi`, `kernel/user/mount.fi`,
`kernel/user/umount.fi`, `ulib.fi`, `lib/libc/kcall.fi`,
`tools/kernel/karte.py`, `test.sh`.

---

## 3. Die Tafel der Verrichtungen — und warum sie echte Zeiger sind

Ein Dateisystem meldet sich mit **neun Funktionen** an:

```
lookup · readdir · attr · read · write · create · unlink · rename · trunc
```

Dazu eine Bitmaske `mask`, die sagt, welche davon es *wirklich* kann.
`vfs.fi` prüft das Bit, **bevor** es den Zeiger benutzt: `/proc` trägt
nur die vier lesenden Bits, `/dev` keine zum Anlegen, ein mit `fatro`
eingehängtes FAT32 keine schreibenden.

**Das sind echte indirekte Aufrufe, und das ist nachgerechnet.** Firn
Stufe 0 kann einen Funktionszeiger weder in eine Zahl wandeln
(`conversion from fn(u64, u64) -> u64 to u64 is not allowed`) noch aus
einem Feld einer Tafel heraus aufrufen (`only direct function names can
be called (pointer calls are not supported in stage 0)`). Ein **Feld
einer Struktur** aufzurufen kann es — und das erzeugt `call *%rax`.

Gemessen (`tools/k14/run.sh`, Abschnitt 3):

```
indirekte Aufrufe im Kern (firnc0): 18
indirekte Aufrufe im Kern (firnc1): 18
vfs.node_for / v_readdir / v_attr / v_read / v_write /
v_create / v_unlink / v_rename / v_trunc     je genau 1
Aufrufe von fs.* (OFS) in kernel/vfs.fi:      0
Verrichtungen in der Tafel von vfsops.fi:     9
```

Die Null in der vorletzten Zeile ist die eigentliche Zusage: **`vfs.fi`
nennt OFS nicht beim Namen.** Der einzige Ort, an dem ein Dateisystem
genannt wird, ist `vfs.ops_of` — die Anmeldestelle, vier Zeilen lang.

Zweitens ein Beweis *im Lauf*: `VFS_OPS` zählt die Schicht, wenn sie eine
Verrichtung **anstösst**; `VFS_INDIRECT` zählt der **Treiber**, wenn sie
bei ihm **ankommt**. Zwei Zähler an zwei Stellen in zwei Dateien. Im
Regellauf: `ops=140 indirect=140`. Wären beide an derselben Stelle, wäre
ihre Gleichheit eine Tautologie.

---

## 4. OFS ist der erste Nutzer, kein Sonderfall daneben

Der Auftrag verlangte beides: OFS soll durch die Schicht gehen — und es
darf **keine** der 1486 bestehenden Zusagen verlieren. Der Weg dahin:

* OFS ist Eintrag **0** der Einhängetafel, mit einer Ops-Tafel wie jeder
  andere Treiber (`kernel/ofs.fi`, 178 Zeilen — dünn, und das *ist* der
  Beweis, dass die Form stimmt).
* Für die **Wurzel** benutzt `sys.fi` weiterhin den geraden Weg von Runde
  62, solange nicht `vfsall` auf der Kommandozeile steht. Das ist die
  Vorsicht, die der Auftrag verlangt („Nichts löschen, bevor der Ersatz
  läuft").
* Mit `vfsall` geht **auch** die Wurzel durch die Ops-Tafel. Derselbe
  Kernel, dieselbe Arbeit (`ls /bin`, `mkdir`, `echo >`, `cat`, `cp`,
  `rm`, `wc`, `grep` — 31 Zeilen Ausgabe), zweimal, und die beiden
  Mitschnitte werden **Oktett für Oktett** verglichen. Ebenso die
  Wurzelplatte danach.

Gemessen:

```
dieselbe Arbeit auf OFS, beide Wege, Oktett fuer Oktett     gleich
und die Wurzelplatte danach, Oktett fuer Oktett             gleich
mit vfsall gehen mehr Verrichtungen ueber die Tafel:  6 -> 155
```

Die letzte Zeile ist die Gegenprobe zur Gleichheit: hätte `vfsall` nichts
geändert, wären die beiden Läufe trivialerweise gleich gewesen.

---

## 5. Pfadauflösung über Einhängegrenzen

`vfs.mount_for` sucht den **längsten** passenden Einhängepfad — nicht den
ersten. Mit `/` und `/mnt` in der Tafel würde der erste jeden Pfad auf
der Wurzel enden lassen.

Und „passend" heisst **an einer Namensgrenze**. `/mnttest` fängt mit
`/mnt` an, Oktett für Oktett; ein Präfixvergleich ohne Grenze würde die
Datei auf dem FAT32 suchen. Das ist die eine Zeile, an der eine
Einhängeschicht falsch wird (`mnt.path_eq_prefix`), und sie wird gemessen:

```
mnttest_is_err = 2      (-ENOENT, nicht der Inhalt von /mnt)
```

**Kein Zwischenpuffer.** Der Rest eines Pfades ist ein Stück *desselben*
Textes (`path + used`), weil der Einhängepfad ein Anfang davon ist. Nur
wenn der Pfad genau der Einhängepunkt ist, bleibt nichts übrig — dann
wird ein `"/"` vom Stapel des Aufrufers gereicht. Ein globaler Puffer
wäre auf einer Maschine mit acht Kernen eine Stelle, an der sich zwei
Auflösungen ins Gehege kommen.

**Ein Einhängepunkt muss ein Verzeichnis sein, das es gibt** — wie auf
jedem Unix. Das ist keine Strenge um ihrer selbst willen: dadurch ändert
sich an einem bestehenden Plattenabbild *nichts*. Wo kein `/proc` liegt,
wird auch keines eingehängt, und die Abbilder der Runden 59 bis K12
messen weiter genau das, was sie gemessen haben.

**Aushängen prüft offene Deskriptoren.** `mnt.opens` geht in
`sys.open_vfs` hoch und in `sys.unref_of` herunter — und nur dann, wenn
der *letzte* Deskriptor auf diesen Eintrag geht (`dup2` und `fork` machen
zwei Deskriptoren aus einer offenen Datei). Gemessen:

```
opens_before = 0 · opens_open = 1 · umount_busy = 16 (-EBUSY)
opens_after  = 0 · umount_ok   = 0 · gone_is_err = 2 (wirklich weg)
mount_ok     = 0 · back_is_err = 0 (und wieder da)
```

---

## 6. `/proc`

Ein Dateisystem, dessen Dateien **beim Lesen entstehen**. Sie liegen
nirgends; sie werden auf einer Seite (`kstate.PROCFS_OFF`, mit
`atomic.L_PROC` darum) geschrieben und sind wieder weg, sobald das `read`
zurück ist.

Global: `meminfo`, `cpuinfo`, `uptime`, `mounts`, `stat`, `version`.
Je Prozess: `status`, `stat`, `cmdline`, `maps`, `fd/`.

Zwei Stellen, an denen `/proc` mehr ist als eine formatierte Konstante:

* **`cmdline` liest den Adressraum des fremden Prozesses.**
  `elf.write_args` legt `argc`, die Zeiger und die Zeichenketten auf
  `proc.ARGS_BASE`; `procfs.make_cmdline` liest genau dort, über
  `proc.translate`, also durch die Seitentabelle *jenes* Prozesses. Eine
  Kopie im Kernel wäre veraltet, sobald `execve` lief.
* **`maps` läuft die Seitentabelle ab.** Keine Liste von Konstanten:
  `proc.translate` und `proc.page_exec` werden Seite für Seite gefragt
  (`USER_DATA` bis `USER_DATA + USER_SPAN`), und was zusammenhängt, wird
  zu einer Zeile. Gemessen wird das mit der einzigen Metrik, die nicht
  durch Nichtstun zu bestehen ist: das Programm nimmt sich per `mmap`
  vier Seiten und die Datei **muss danach mehr Zeilen haben**.

```
maps_lines = 3 → maps_after_map = 4 → maps_grew = 1
```

Ein Fehler, den diese Runde dabei selbst gemacht und gemessen hat: die
erste Fassung lief nur bis `proc.USER_TOP` (0x40009000) — das ist die
Oberkante des *Stapels*, nicht das Ende des Adressraums. Sie meldete für
jeden Prozess genau eine Zeile, obwohl das Abbild bei 0x40100000 liegt.

Ein zweiter, ebenso lehrreich: `file.fd_of` gibt den Platz in der Tafel
der offenen Dateien zurück und `MAX_OPEN`, wenn der Deskriptor
geschlossen ist — **nicht** null, denn null ist ein gültiger Platz
(die Konsole auf Deskriptor 0). Die erste Fassung prüfte `!= 0` und zählte
damit genau das Gegenteil auf: Deskriptor 0 fehlte, und jeder
geschlossene stand in der Liste.

**Der Sonderaufruf von Runde K6 bleibt.** `tools/k14/run.sh` Abschnitt 10
hält `ps` (über `SYS_OSUM_PSTAT`) gegen `cat /proc/<pid>/stat` (über das
Dateisystem), Pid und Eltern-Pid für die Aufgaben 1 und 2. Solange das
nicht in beide Richtungen gemessen ist, wird nichts entfernt.

---

## 7. `/dev`

`null`, `zero`, `random`, `urandom`, `tty`, `console`, `fb`, `hda`,
`hdb`, `ram0`, `nvme0`. Kein Zustand im Speicher: der Knoten *ist* die
Gerätenummer, und ein Gerät mehr ist eine Zeile.

Zwei Geräte sind mit Absicht anders: ein Knoten, der ein **Terminal** oder
der **Rahmenpuffer** ist, wird in `sys.open_vfs` zu genau dem Deskriptor,
den Runde K9 und Runde K7 dafür gebaut haben (`K_TTY`, `K_FB`). Ein
zweiter Weg auf dasselbe Gerät wäre eine zweite Stelle, an der die
Zeilendisziplin steht — und die zweite wäre irgendwann die falsche. Alle
Messungen der Runden K7 und K9 laufen unverändert weiter.

`/dev/hda`, `/dev/hdb`, `/dev/ram0`, `/dev/nvme0` sind **Blockgeräte** mit
oktettweisem Zugriff (Teilsektoren werden gelesen, bevor sie geschrieben
werden). Sie sind die einzigen Dateien hier, deren Oktette wirklich auf
einem Träger liegen — und damit die, an denen sich prüfen lässt, dass
hier keine Attrappe steht:

```
hdb_boot_ok = 1        der erste Sektor endet auf 0x55 0xAA
                       (dort, weil `sfdisk` auf dem WIRT es schrieb)
hdb_size    = 83886080 lseek(fd, 0, SEEK_END) auf einer 80-MiB-Platte
hdb_mode    = 1        S_IFBLK
null_mode   = 1        S_IFCHR
```

`/dev/random` und `/dev/urandom` sind **derselbe** Topf
(`kernel/rand.fi`, Runde K9). Zwei Namen für zwei Töpfe zu behaupten wäre
eine Lüge über die Qualität des einen.

---

## 8. Partitionstafeln: MBR und GPT

`kernel/part.fi` liest beide. Der MBR: Signatur 0x55 0xAA, vier Einträge
zu 16 Oktetten ab 446, Typoktett übersetzt (0x0B/0x0C = FAT32, 0xEF =
EFI, 0x83 = Linux). Ein Eintrag mit dem Typ 0xEE ist der **Schutz-MBR**
einer GPT.

Die GPT: Kopf in Block 1, Signatur „EFI PART", und **beide** Prüfsummen
werden gerechnet — die über den Kopf (mit dem CRC-Feld auf null gesetzt,
so schreibt es die Vorschrift vor) und die über die ganze Eintragstafel.
Letztere wird **fortgeschrieben** statt gesammelt: die Tafel ist bis zu
16 KiB gross, die Platte gibt sie in Sektoren her, und der ganze
Datenbereich dieser Runde sind drei Seiten. Dafür wurde `bootmod.crc32`
in `crc32_start` / `crc32_feed` / `crc32_end` zerlegt — ohne eine Zahl
daran zu ändern; Abschnitt 15 (`guard`) misst sie weiter.

Der Partitions-GUID wird **Oktett für Oktett** verglichen und nicht als
Zahl: ein GUID steht auf der Platte mit den ersten drei Feldern
kleinendig und den letzten beiden grossendig.

Gemessen gegen `sfdisk` und `sgdisk`:

```
MBR:  part: mbr=1  gpt=0  parts=1     FAT32 gefunden, Datei lesbar
GPT:  part: mbr=2  gpt=1  parts=1     dito, beide Pruefsummen stimmen
```

**Gegenprobe:** ein einziges umgedrehtes Bit im GPT-Kopf
(`first_usable_lba`, Oktett 512+40) — der Kernel meldet
`part: gpt crc mismatch` und liest die Platte **nicht** mehr.

**Gegenprobe `nopart`:** ohne Partitionstafel wird das Dateisystem bei
Block 0 gesucht, wo die Tafel steht. Es wird keines gefunden; es bleiben
drei Einhängungen statt vier.

---

## 9. FAT32 — gegen die echten Werkzeuge

Das ist das erste Dateisystem dieses Kernels, das er **nicht selbst
erfunden hat**. OFS schreibt der Kernel und liest der Kernel; machen beide
Seiten denselben Fehler, fällt es nie auf. FAT32 steht seit 1996 fest.

**Gelesen** wird: kurze Namen (mit den beiden Kleinschreibbits im Oktett
12, die `mcopy` setzt), **lange Namen** (VFAT, dreizehn UTF-16-Zeichen je
Stück, rückwärts vor dem Eintrag, mit Prüfsumme des kurzen Namens),
Unterverzeichnisse, Ketten über beliebig viele Verbände.

**Geschrieben** wird: in bestehende Dateien, verlängernd mit neuen
Verbänden, Anlegen von Dateien und Verzeichnissen (mit `.` und `..`,
und `..` zeigt bei einem Kind der Wurzel auf **null**, wie die
Beschreibung es verlangt), Löschen (Kurzeintrag *und* die Namensstücke
davor — sonst meldet `fsck.fat` „orphaned long filename"), Umbenennen,
Kürzen. Jede Änderung geht in **alle** Zuordnungstafeln.

### Die Messung

Das Abbild kommt von `mkfs.vfat -F 32 -s 1` (64 MiB), die Dateien von
`mcopy`/`mmd`, die Tafeln von `sfdisk`/`sgdisk`.

**Lesen** — Osum kopiert die Dateien der fremden Platte auf *seine*
eigene, und der Wirt holt sie dort mit `mkfs.py cat` heraus:

| Datei | Ergebnis |
|---|---|
| `hello.txt` (16 Oktette) | Oktett für Oktett gleich |
| `blob.bin` (5000 Oktette Zufall) | Oktett für Oktett gleich |
| `unter/tief.txt` (zwei Ebenen tief) | Oktett für Oktett gleich |
| `einsehrlangername.txt` | Oktett für Oktett gleich — und der **lange** Name steht in `ls`, nicht `EINSEH~1` |

**Schreiben** — was Osum schreibt, holt `mcopy` wieder heraus:

| Prüfung | Ergebnis |
|---|---|
| `mdir` sieht `neu.txt`, `kopie.bin`, `neuverz` | ja |
| `mtype ::neu.txt` | `osum-war-hier` |
| `mcopy ::kopie.bin` vs. das Original (5000 Oktette) | identisch |
| die von Osum gelöschte Datei | weg |
| die Datumsfelder | gültig (nicht `1980-00-00`) |
| **`fsck.fat -n`** | **Rückgabe 0, keine Anmerkung** |

Das Datum war ein echter Fehler dieser Runde: die erste Fassung liess die
Felder null, und `mdir` zeigte `1980-00-00` — Monat 0 und Tag 0 gibt es
nicht. Jetzt kommt die Zeit aus der CMOS-Uhr (`time.rtc_field`); sagt die
Uhr Unsinn, wird der erste Tag geschrieben, den FAT kennt, statt Unsinn.

Die FSInfo-Seite (die Zahl der freien Verbände) wird bei jeder Zuteilung
auf **0xFFFFFFFF = unbekannt** gesetzt — das ist der von Microsoft
vorgesehene Wert. Beim **Aushängen** wird sie einmal wirklich gerechnet
(`fat.sync`, 129022 Einträge). Das ist gemessen, in beide Richtungen:

```
mit `umount /mnt`:   fsck.fat -n → Rueckgabe 0, keine Anmerkung
ohne `umount`:       fsck.fat sagt "Free cluster summary uninitialized"
```

---

## 10. Die Zweite Platte

Ohne ein zweites Gerät wäre jede Messung dieser Runde ein Selbstgespräch.
`blk.fi` bekam den **ATA-Sklaven** am ersten Bus: dieselben Ports,
dieselben Register, ein einziges Bit anders (Bit 4 des
Laufwerksregisters, 0xF0 statt 0xE0). Dazu eine gerätebezogene
Schnittstelle: `blk.read_on(state, dev, lba, dst)` statt der globalen
Zahl `kstate.DISK_DEV`. `read` und `write` bleiben genau, was sie waren —
sie reichen die globale Zahl durch, und `fs.fi` ändert dafür keine Zeile.
Dieselbe Regel wie bei DEV_NVME in Runde K2.

`blk.probe_ata1` **liest den ersten Block**, bevor es „ja" sagt: ein
Statusregister, das nicht 0xFF liest, ist noch keine Platte — QEMU lässt
den Sklaven auch dann antworten, wenn gar kein `-drive` daran hängt.

---

## 11. Die Zahlenvorräte dieser Runde

Der Auftrag hat sie zugeteilt, weil weitere Runden **gleichzeitig** an
diesem Baum arbeiten. Genau diese Lage hat dem Projekt viermal dieselbe
kdata-Kollision beschert (siehe den Kopf von `tools/kernel/karte.py`).

| Vorrat | genommen |
|---|---|
| kdata 0x43000..0x46000 | `K14_OFF` 0x43000, `FAT_OFF` 0x44000, `PROCFS_OFF` 0x45000 |
| Aufrufnummern 1700..1799 | `SYS_OSUM_MNTSTAT` = 1700 |
| Deskriptorarten 12, 13 | `K_VFILE` = 12, `K_VDIR` = 13 |
| Abschnitt 20 in `test.sh` | belegt |
| `docs/ROUNDK14.md`, `tools/k14/` | diese Datei, dieser Läufer |

`mount`, `umount2` und `rename` haben **Linux' Nummern** (165, 166, 82),
weil Linux die Aufrufe hat — Regel 1 der Karte in `kernel/sys.fi` ist
älter als der Auftrag: eine abweichende Nummer wäre eine
Übersetzungstabelle, die jemand pflegen muss.

Die drei kdata-Seiten stehen in `tools/kernel/karte.py`
(BEREICHE + `dateien` + KEINE_KDATA), und der Prüfer rechnet nach:
**46 Bereiche in 0x50000 Oktetten kdata, 0 Kollisionen.**
Gegenprobe: `PROCFS_OFF` versuchsweise auf `FB_OFF` (0x3C000) gelegt —
der Prüfer schlägt an.

**Die Programmnummern 18 und 19 (`P_*` in `uprog.fi`) wurden nicht
gebraucht** und bleiben frei. Das Messprogramm dieser Runde liegt als ELF
auf der Platte (`kernel/user/k14.fi`, `/bin/k14`), wie in den Runden K4,
K6 und K9 — dort kann es `mount`, `umount2` und `getdents64` wirklich
rufen, was ein Programm in `uprog.fi` (das nichts importieren darf) nur
mit einer zweiten Kopie aller Nummern könnte.

---

## 12. Die Gegenproben

Jede Zusage dieser Runde hat eine, und jede bricht wirklich zusammen:

| Wort | Wirkung | gemessen |
|---|---|---|
| `novfs` | nur die Wurzel, kein weiteres Einhängen | `mount_count` 4→**1**, `proc_type`/`dev_type`/`fat_type` → 0, `hdb_boot_ok` → 0 — **und OFS trägt weiter das Userland** |
| `noprocfs` | kein `/proc` | 4 → 3 Einhängungen |
| `nodevfs` | kein `/dev` | 4 → 3 Einhängungen |
| `nofat` | die zweite Platte wird nicht angefasst | 4 → 3 Einhängungen |
| `nopart` | Dateisystem bei Block 0 gesucht | kein FAT32 gefunden |
| `fatro` | nur lesend eingehängt | nichts entsteht, Platte **Oktett für Oktett unverändert** |
| GPT-Bit umgedreht | Kopfprüfsumme | `gpt crc mismatch`, Platte wird nicht gelesen |
| kein zweites Laufwerk | — | Kernel läuft weiter (21), drei Einhängungen |
| `vfsall` | Wurzel durch die Ops-Tafel | 6 → 155 Verrichtungen, Ausgabe **identisch** |
| kdata-Karte | `PROCFS_OFF` auf `FB_OFF` | Prüfer schlägt an |
| ohne `umount` | FSInfo nicht nachgeführt | `fsck.fat` meldet es |

---

## 13. Was NICHT geht — benannte Grenzen

Nichts davon ist geschönt.

1. **OFS lässt sich nur als Wurzel einhängen.** `kernel/ofs.fi` sieht
   `mnt.dev` und `mnt.first` nicht an: `fs.fi` liest über `blk.read`,
   also über die eine Platte, die `kstate.DISK_DEV` nennt, und diese
   Runde hat daran keine Zeile geändert — 1486 Zusagen hängen daran. Die
   Felder stehen in der Einhängetafel, FAT32 benutzt sie, und der Tag, an
   dem OFS auf einer Partition liegen soll, ändert genau die drei Zeilen
   in `ofs.fi`, in denen jetzt `fs.` steht.
2. **`/proc/self` gibt es nicht.** Die neun Verrichtungen bekommen
   `state` und die Nummer der Einhängung, aber nicht die des rufenden
   Prozesses. Ein Programm braucht `getpid()` und baut den Pfad selbst.
3. **`/proc/<pid>/fd/N` ist eine Datei, kein Verweis.** Linux macht
   daraus einen symbolischen Verweis; dieser Kernel hat keine. Der Inhalt
   sagt, was der Deskriptor ist (`file 12`, `pipe`, `tty 0`, `console`).
4. **`/proc` und `/dev` zeigen keine eigenen Einhängepunkte in `ls /`.**
   Ein Einhängepunkt muss ein Verzeichnis auf der Wurzel sein und wird
   dort ganz normal aufgelistet; es wird nichts in eine Auflistung
   *eingeschoben*. Das ist auch der Grund, warum diese Runde an
   bestehenden Abbildern nichts ändert.
5. **FAT32: nur 512 Oktette je Sektor.** Der Treiber lehnt alles andere
   beim Einhängen ab, statt zu raten. FAT12 und FAT16 werden nicht
   gelesen: die 16-Bit-Felder des BPB müssen null sein, sonst ist es
   kein FAT32 — ein FAT16 durchzulassen hiesse, seine Wurzel als
   Verband 2 zu lesen, wo dort die erste Datei liegt.
6. **FAT32: Namen bis 63 Zeichen, und ein NEUER Name nur in US-ASCII.**
   Gelesen werden auch andere Zeichen — aber jedes Oktett über 127 wird
   zu `?`. Eine halbe UTF-16-Wandlung wäre schlimmer als eine ehrliche
   Ersatzmarke: der Name wäre lesbar falsch statt sichtbar unbekannt.
7. **FAT32: höchstens 24 gleichzeitig geöffnete Knoten je Kernel**
   (`fat.MAX_NODES`). Ein Knoten wird wiederverwendet, wenn dieselbe
   Datei noch einmal geöffnet wird — sonst wäre die Tafel nach 24 `open`
   voll und `st_ino` wäre jedes Mal eine andere Zahl für dieselbe Datei.
8. **FAT32: kein `fsync`.** Geschrieben wird sofort und ohne Zwischenlage;
   die FSInfo-Seite wird beim Aushängen nachgeführt. Wer die Maschine vor
   dem `umount` ausschaltet, hat ein Dateisystem, über das `fsck.fat`
   „Free cluster summary uninitialized" sagt — sonst nichts.
9. **`rename` eines VERZEICHNISSES prüft keinen Ringschluss.** Ein
   Verzeichnis in einen seiner eigenen Nachfahren zu hängen würde einen
   Teilbaum abschneiden. POSIX verlangt dafür `-EINVAL`; dieser Kernel
   prüft es nicht, weil die Prüfung den ganzen Pfad nach oben laufen
   müsste und es hier keinen Weg von einer Inode zu ihrem Elternteil
   gibt ausser ihrem eigenen `..`.
10. **Acht Einhängungen, sechzehn Partitionen.** Feste Grössen im
    Datenbereich, keine dynamische Liste — Firn Stufe 0 hat im
    Kernelprofil keinen Allokator.
11. **`mount` kennt nur `MS_RDONLY` (Bit 0).** Jedes andere Bit in
    `flags` gibt `-EINVAL`, statt still überlesen zu werden.
12. **Die zweite Platte ist ATA PIO und ihre Grösse kommt von aussen**
    (`DISK2_BLOCKS` in `kmain.fi`, 163840 Blöcke = 80 MiB). ATA PIO sagt
    von sich aus nicht, wie gross ein Laufwerk ist; ein IDENTIFY dafür
    wäre ein zweites Protokoll für eine Zahl, die der Testläufer ohnehin
    kennt — er baut das Abbild.

---

## 14. Zwei Fehler, die diese Runde selbst gemacht und gemessen hat

* **`/proc/<pid>/maps` lief bis `proc.USER_TOP`.** Das ist die Oberkante
  des Stapels (0x40009000), nicht das Ende des Adressraums. Die Datei
  hatte für jeden Prozess genau eine Zeile. Gefunden nicht durch Lesen,
  sondern durch die Messung „drei Zeilen vor `mmap`, vier danach" — mit
  dem Fehler wären es eine und eine gewesen, und `maps_grew` wäre null.
* **`file.fd_of` gibt `MAX_OPEN` für „geschlossen" zurück, nicht null.**
  `/proc/<pid>/fd` prüfte `!= 0` und zählte damit genau das Gegenteil
  auf: Deskriptor 0 (die Konsole, Platz 0) fehlte, jeder geschlossene
  stand darin. Sichtbar wurde es als `0 1 2 4 5 … 15` statt `0 1 2`.

Beides steht als Kommentar an der jeweiligen Stelle im Quelltext — so wie
die vier kdata-Kollisionen in `kstate.fi` stehen.

---

## 15. Abnahme

```
bash tools/k14/run.sh
  1. die Nummern, die Karte von kdata und die Zahlenvorraete
  2. bauen: der Kern und der Werkzeugkasten, aus BEIDEN Uebersetzern
  3. die Tafel der Verrichtungen ist eine Tafel von ZEIGERN
  4. die Abbilder: FAT32 von mkfs.vfat, Partitionen von sfdisk/sgdisk
  5. der Regellauf: vier Dateisysteme nebeneinander (MBR)
  6. FAT32 gegen mkfs.vfat, mcopy, mdir und fsck.fat
  7. die Partitionstafel: MBR, GPT und ein umgedrehtes Bit
  8. die Gegenproben: ohne die Schicht bricht jede Zusage weg
  9. OFS ist ein NUTZER der Schicht, kein Sonderfall daneben
 10. /proc gegen SYS_OSUM_PSTAT: zwei Wege, dieselben Zahlen

K14: 146 passed, 0 failed
```

Der Läufer überspringt sich selbst (Rückgabe 0), wenn `qemu-system-x86_64`,
`mkfs.vfat`, `mcopy`, `mdir`, `mmd`, `mtype` oder `sfdisk` fehlen —
`sgdisk` und `fsck.fat` sind einzeln optional und lassen nur ihren
Abschnitt weg.
