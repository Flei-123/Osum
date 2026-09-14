# Runde DUALBOOT — OrientOS neben ein vorhandenes System

Zweig `dualboot`, abgezweigt von `main` (`e3e724a`).
Gemessen mit `bash tools/dual/abnahme-cli.sh`, `tools/dual/startprobe.sh`
und `tools/dual/kettenprobe.sh`.

Diese Runde greift den Rest von **`P-012`** an und den Satz, mit dem
`docs/RUNDE-INSTALLER.md` endet:

> **Kein Formatieren, kein Auswählen einer Partition** — die Platte wird
> ganz genommen.

Bis hierher brauchte, wer OrientOS neben Windows wollte, eine **zweite
Platte**. Jetzt nicht mehr.

---

## 1. Die Antwort auf Justins Frage

**Ja — mit einer Einschränkung, und sie liegt nicht in dieser Runde.**

Gemessen ist die ganze Kette: eine Platte, auf der ein fremdes System
liegt, bekommt eine dritte Partition dazu, ohne dass sich an den beiden
vorhandenen **ein einziges Oktett** ändert; das Bootmenü bietet danach
beide Systeme an, und **beide starten wirklich**.

Die Einschränkung: der Kern kennt die Größe der **zweiten** Platte nicht
(Abschnitt 4.1). Auf einem echten Rechner mit **einer** Platte, in der
Windows und der freie Platz liegen, trifft das nicht zu — dort ist die
Zielplatte die erste, und deren Größe kommt aus IDENTIFY. Gemessen ist
dieser Fall hier trotzdem nicht, weil der Messaufbau die Wurzel auf
einer Platte braucht und das Ziel auf einer anderen.

Was ebenfalls **nicht** geht und mit Absicht nicht geht: eine vorhandene
Partition **verkleinern**. Wer keinen freien Platz hat, muss ihn vorher
in seinem eigenen System freimachen. Das Fenster sagt das im Klartext,
statt es zu versuchen.

---

## 2. Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/user/dualkern.fi` | ~870 | die Maschine: eine **vorhandene** GPT lesen, eine Lücke finden, **einen** Eintrag ergänzen |
| `kernel/user/installer.fi` | +~450 | zwei Reiter, die Partitionsansicht, der zweite Weg |
| `kernel/user/dualcli.fi` | ~370 | derselbe Weg ohne Fensterserver — damit die Zusage messbar bleibt |
| `kernel/user/instkern.fi` | +30 | `wurzel_kopieren_ab`: dieselbe Schleife, freier Anfangssektor |
| `tools/dual/fremdplatte.sh` | ~190 | eine Platte, auf der schon jemand wohnt — gebaut mit `sgdisk` |
| `tools/dual/tafelpruef.py` | ~200 | die Tafel mit **fremden Augen** lesen, beide CRC32 selbst rechnen |
| `tools/dual/beweis.c` | ~80 | eine echte UEFI-Anwendung, die sich selbst zu erkennen gibt |
| `tools/dual/abnahme-cli.sh` | ~280 | die Abnahmekette mit Prüfsummen |
| `tools/dual/startprobe.sh` | ~130 | startet die Platte wirklich? |
| `tools/dual/kettenprobe.sh` | ~150 | startet der **zweite** Eintrag wirklich? |
| `locale/de,en/messages` | +32 je | die Texte |

### Die Entscheidung: eine zweite Datei, nicht eine zweite Rechnung

`instkern.gpt_schreiben` **schreibt** eine Tafel. `dualkern.neben_schreiben`
**ändert** eine vorhandene. Das ist ein anderer Beruf:

> Eine vorhandene Tafel zu ändern heißt, Oktette anzufassen, die jemand
> anderes geschrieben hat. Jeder Fehler dabei kostet nicht „die
> Installation", sondern **die Daten des Benutzers**.

Deshalb liegt das getrennt. Die Regel der Datei, ohne Ausnahme: **es
wird nur geschrieben, was neu ist** — genau ein bisher leerer Eintrag,
die beiden CRC32, die beiden Köpfe, die Sicherung am Plattenende. Kein
vorhandener Eintrag wird verschoben, verkleinert, umsortiert oder
gelöscht.

Zwei Vorprüfungen tragen die ganze Zusage:

1. **Überschneidet sich der Bereich mit irgendeiner vorhandenen
   Partition?** Ein Eintrag über einer fremden Partition zerstört deren
   Daten in dem Augenblick, in dem OrientOS dorthin schreibt — und die
   Tafel sähe dabei vollkommen gesund aus.
2. **Ist der gewählte Tafeleintrag wirklich leer?** Wäre er es nicht,
   verschwände eine fremde Partition aus der Tafel; ihre Daten lägen noch
   da, aber kein System fände sie wieder.

### Die fremde EFI-Partition wird **mitbenutzt**

Das ist der Punkt, an dem ein schlechtes Installationsprogramm fremde
Bootlader löscht: es legt eine neue ESP an, und was vorher dort lag, ist
weg. Hier wird die vorhandene eingehängt, und OrientOS legt seine
Dateien in ein **eigenes Unterverzeichnis**:

```
  /EFI/orientos/osum.mb        der Kern
  /EFI/orientos/BOOTX64.EFI    der Bootlader
```

Außerhalb davon werden **genau zwei** Dateien angefasst: `/limine.conf`
(sie *ist* das Menü, das beide Systeme anbieten soll) und
`/EFI/BOOT/BOOTX64.EFI` (dort sucht die Firmware ohne Eintrag in ihrer
Reihenfolge). `\EFI\Microsoft\Boot\bootmgfw.efi` wird **gelesen und nie
geschrieben**.

---

## 3. Das Bootmenü: Kettenstart, nicht NVRAM

Der Auftrag ließ die Wahl zwischen einem Kettenstart und der
UEFI-Bootreihenfolge. Genommen ist der **Kettenstart**, und zwar
begründet:

* Der mitgelieferte Lader ist **Limine 9.6.7**, und der kann es:
  `strings` auf `BOOTX64.EFI` nennt `chainload` und `efi_chainload`
  neben `multiboot1`.
* Die UEFI-Bootreihenfolge liegt im **NVRAM der Hauptplatine**. Sie
  braucht einen Dienst, den dieses System nicht hat, und sie überlebt
  kein Zurücksetzen des BIOS. Eine Datei auf der Platte überlebt es.

Die Startdatei bekommt den zweiten Eintrag **nur dann**, wenn
`bootmgfw.efi` wirklich da ist. Ein Menüeintrag, der ins Leere führt,
ist schlimmer als keiner — er sieht aus wie ein Weg zurück ins alte
System und endet in einer Fehlermeldung des Bootladers.

```
timeout: 10

/OrientOS
    protocol: multiboot1
    path: boot():/EFI/orientos/osum.mb
    cmdline: osum vfs gfx wm wig desk wmshell wmdauer herz tz=120 nosched noproc nofs

/Windows Boot Manager
    protocol: efi_chainload
    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
```

---

## 4. Die Funde

### 4.1 Der Kern kennt die Größe der zweiten Platte nicht — der größte Fund

In `kernel/kmain.fi:176` steht:

```firn
const DISK2_BLOCKS: u64 = 163840
```

Und genau diese Zahl bekommt `blk.probe_ata1` (kmain.fi:2884). ATA PIO
meldet die Größe des Sklaven nicht von selbst, ein IDENTIFY dafür gibt
es nicht — also ist sie **fest verdrahtet auf 80 MiB**.

**Die Folge ist heimtückisch.** `blk.write_on` weist jeden
Schreibzugriff hinter `blocks_on()` ab, und zwar **still**
(`blk.fi:988/1012`). Auf einer größeren zweiten Platte landet die
primäre GPT-Tafel (Sektor 2) richtig, die **Sicherungstafel am
Plattenende aber nirgends**. Das Ergebnis sieht wie ein Erfolg aus.

Gefunden hat es **nicht** `sgdisk` — der sagt nur „Main and backup
partition tables differ" —, sondern der eigene, unabhängige Prüfer mit
dem Satz:

```
   FEHLER:
     - die beiden Koepfe nennen verschiedene Tafelsummen
```

Genau dafür wurde `tools/dual/tafelpruef.py` gebaut: er rechnet alle
vier Summen einzeln und sagt, **welche** nicht stimmt. Er hat sich beim
ersten Lauf bezahlt gemacht.

Die Testplatte ist deshalb 80 MiB groß. **Wer größere fremde Platten
messen will, muss zuerst `DISK2_BLOCKS` beheben — das ist eine eigene
Runde.**

### 4.2 Eine zweite Kopie von Limine taugt nicht als Beweis

Der erste Versuch, den Kettenstart zu messen, legte eine zweite
Limine-Binärdatei an die Stelle von `bootmgfw.efi`. Ergebnis: der Schirm
blieb **schwarz**, und das sah wie ein Fehlschlag aus.

Es war keiner. Die zweite Kopie sucht **dieselbe** `limine.conf` wie die
erste und ist von ihr nicht zu unterscheiden. Das Ziel eines
Kettenstarts muss sich **selbst zu erkennen geben** — deshalb liegt dort
jetzt `tools/dual/beweis.c`: eine echte UEFI-Anwendung (gebaut mit
`x86_64-w64-mingw32-gcc -Wl,--subsystem,10`), die auf COM1 **und** auf
den EFI-Schirm einen Satz schreibt, den sonst niemand schreibt.

### 4.3 Die Oberfläche ließ sich auf diesem Wirt nicht messen

Jeder Lauf mit `wigapp=/bin/installer` endet auf diesem Rechner bei

```
init: wurzel=1
init: ziel=grafik
init: mounts=0
init: dienste=1
init: herunterfahren
```

— keine einzige `wm:`-, `wig:`- oder `installer:`-Zeile, obwohl der
Framebuffer steht (`fb: selftest 13 / 13 failed=0x0`) und
`/bin/installer` im Wurzelabbild liegt.

**Das ist nicht in dieser Runde entstanden.** Die Gegenprobe:
`bash tools/install/abnahme.sh` — die Abnahme der vorigen Runde, die
laut `docs/RUNDE-INSTALLER.md` mit **27 Zusagen grün** ist — hängt in
derselben Umgebung an derselben Stelle und meldet danach „keine
EFI-Partition / kein BOOTX64.EFI / keine limine.conf". Ausgeschlossen
wurden: der Beschleuniger (TCG wie KVM), die Plattengröße (320 MiB wie
512 MiB) und die Kommandozeile (Wort für Wort die aus
`tools/install/abnahme.sh:180`).

Deshalb **`dualcli.fi`**: derselbe Weg über die Kommandozeile. Das ist
keine zweite Umsetzung — jede Zeile, die schreibt, steht in `dualkern`
und `instkern`, und `dualcli` ruft sie in derselben Reihenfolge wie das
Fenster. Eine Zusage, die nur über die Oberfläche prüfbar ist, fällt
genau dann aus, wenn man sie am dringendsten braucht.

Was daraus folgt, ehrlich gesagt: **die neue Oberfläche ist übersetzt,
`check-ui.sh` ist grün, aber sie ist nicht im Bild gemessen.** Die
Maschine dahinter ist es.

### 4.4 `script=` kommt nur an, wenn init nicht ins Ziel `grafik` startet

Auch ohne `modfs` liest `init` seine Wurzel von der Platte, und dort
steht `/etc/ziel` auf `grafik`. Dann startet `kgui` die Oberfläche und
`script=` kommt nie an. Der Messaufbau schreibt deshalb in der **Kopie**
des Wurzelabbilds das Wort um (`mkfs.py where` nennt den Block) — und
der neue Text darf nicht länger sein als `grafik\n`, weil die Länge in
der Inode steht und dort nicht angefasst wird. `init` fällt bei einem
unbekannten Wort ausdrücklich auf die Konsole zurück.

---

## 5. Die Abnahme

### 5.1 Die Platte, auf der schon jemand wohnt

Gebaut mit **`sgdisk`**, also einem fremden Werkzeug — sonst misst der
Lauf, ob OrientOS seine eigene Schreibweise wiederfindet, und nicht, ob
es eine fremde Tafel versteht.

| | Sektoren | Inhalt |
|---|---|---|
| Partition 1 | 2048..71679 (34 MiB) | ESP, FAT32, darin `\EFI\Microsoft\Boot\bootmgfw.efi` und `BCD` |
| Partition 2 | 71680..92159 (10 MiB) | „Microsoft basic data", FAT16, `WICHTIG.TXT` |
| **frei** | 92160..163806 (34 MiB) | **hier soll OrientOS hin** |

### 5.2 `tools/dual/abnahme-cli.sh` — **24 grün, 0 rot**

| Glied | Gemessen |
|---|---|
| Tafel lesen | `dual: part 1 2048 71679 1`, `part 2 71680 92159 2` — Lage **und** Art richtig |
| Lücke | `dual: frei 92160 163806` |
| fremde ESP | `dual: esp=1` |
| **Probelauf** | ohne `--ja`: **die Platte ist Oktett für Oktett unverändert** |
| Eintrag | `dual: neu p3 92160 163806` |
| **fremde Daten** | Prüfsumme vorher = nachher: `4377737cc738c7cf…` |
| **fremder Bootlader** | `bootmgfw.efi` (6678) und `BCD` (78) sind noch da |
| eigenes Verzeichnis | `/EFI/orientos/` trägt `osum.mb` (5 093 592) und `BOOTX64.EFI` (253 952) |
| **fremdes Werkzeug** | `sgdisk`: **No problems found** |
| **zweiter Prüfer** | „beide Köpfe und beide Tafelsummen sind in Ordnung" |
| Bootmenü | beide Einträge, `efi_chainload` auf `bootmgfw.efi` |
| **Gegenprobe** | zu wenig Platz ⇒ `dual: zu wenig`, **Platte unverändert**, nichts installiert |

### 5.3 `tools/dual/startprobe.sh` — **7 grün, 0 rot**

OVMF, **kein `-kernel`, kein `-initrd`, kein Installationsmedium**.

```
  [ ok ] OrientOS steht im Bootmenue AUF DEM SCHIRM
  [ ok ] DAS FREMDE SYSTEM STEHT IM BOOTMENUE AUF DEM SCHIRM
  [ ok ] der Bootlader laeuft VON DER PLATTE (kein Medium im Spiel)
  [ ok ] ORIENTOS STARTET VON DER PLATTE
  [ ok ] es findet seine Wurzel in der neuen Partition (rootpart=2  first=92160)
  [ ok ] der Schreibtisch startet
  [ ok ] die Wurzel kam NICHT als Boot-Modul
```

`first=92160` ist genau der Sektor, den `neben_schreiben` in die fremde
Tafel geschrieben hat.

### 5.4 `tools/dual/kettenprobe.sh` — **3 grün, 0 rot**

Der zweite Eintrag, mit der Pfeiltaste gewählt wie von einem Menschen:

```
  [ ok ] DER KETTENSTART LAEUFT -- der fremde Bootmanager meldet sich
  [ ok ] und er steht auch AUF DEM SCHIRM
  [ ok ] OrientOS wurde NICHT gestartet -- es war wirklich der zweite Eintrag
```

### 5.5 Bilder

| Datei | Was |
|---|---|
| `10-bootmenue.png` | das Menü mit **beiden** Systemen, von der Platte |
| `20-orientos-von-der-platte.png` | der Schreibtisch, aus der neuen Partition |
| `25-zweiter-eintrag-gewaehlt.png` | der zweite Eintrag ist gewählt |
| `30-kettenstart.png` | der fremde Bootmanager läuft |

---

## 6. Was offen bleibt

* **`DISK2_BLOCKS`** (4.1) — solange das steht, sind fremde Platten über
  80 MiB nicht messbar, und ein Schreibversuch dahinter schlägt **still**
  fehl. Das ist der nächste sinnvolle Schritt, und er ist wichtiger als
  alles andere auf dieser Liste.
* **Die neue Oberfläche ist nicht im Bild gemessen** (4.3). Sie
  übersetzt, `check-ui.sh` ist grün, die Maschine dahinter ist gemessen
  — das Fenster selbst nicht.
* **Kein NTFS.** Die Datenpartition der Testplatte ist FAT; ein echtes
  Windows hat NTFS. Für diese Runde ist das gleichgültig — die
  Partition wird nie angefasst, nur ihre Prüfsumme verglichen —, aber
  gemessen ist es nicht.
* **Kein Verkleinern.** Mit Absicht, siehe oben.
* **Die UEFI-Bootreihenfolge** bleibt unangetastet. Wer seinen Rechner
  so eingestellt hat, dass er direkt `bootmgfw.efi` startet, sieht das
  neue Menü nicht und muss einmal im BIOS umstellen.
