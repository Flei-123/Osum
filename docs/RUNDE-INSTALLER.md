# Runde INSTALLER — der Weg vom Stick auf die Platte

Zweig `installer`, abgezweigt von `main` (`ae381a3`).
Gemessen mit `bash tools/install/abnahme.sh`.

Diese Runde greift **`P-001`** an, den Punkt mit Priorität 1 in
`/root/osum-roadmap/OFFEN.md`:

> **Installation auf Platte** — der Stick läuft aus dem RAM, nichts
> überlebt den Neustart. `install.fi` schreibt GPT/EFI, aber es gibt
> **keinen bedienbaren Installationsweg** aus der Oberfläche.

Der Befund war genau richtig, und er sagt auch, was zu tun war: die
**Maschine** gab es seit Runde INSTALL (70 Zusagen,
`docs/ROUNDINSTALL.md`), es fehlte die **Tür**.

---

## 1. Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/user/instkern.fi` | 805 | die Maschine: Schutz-MBR, GPT mit beiden CRC32, FAT32, Umzug der Wurzel, Wachsen, Kopieren |
| `kernel/user/installer.fi` | ~700 | das Fenster: Platten zeigen, zweistufig fragen, installieren, Fortschritt |
| `kernel/user/install.fi` | 934 → 349 | die Kommandozeile davor, unverändert in dem, **was** sie tut |
| `assets/apps/installer.osp/` | — | das Bündel: INFO, start, symbol, data |
| `tools/install/abnahme.sh` | 330 | die Abnahmekette mit Bildern |
| `tools/install/shot-gui.sh` | 100 | ein Foto vom Fenster |
| `locale/de,en/messages` | +24 je | die Texte |

### Die Entscheidung: geteilt, nicht nachgebaut

Der bequeme Weg wäre gewesen, ein Fenster danebenzustellen und die
Schreibarbeit ein zweites Mal zu tippen. Dann gäbe es **zwei** Stellen,
an denen eine GPT-Prüfsumme gerechnet wird, und die zweite wäre die, die
beim nächsten Formatwechsel vergessen wird — dasselbe, was
`tools/check-ui.sh` für Bedienelemente verbietet, nur eine Etage tiefer.

Deshalb steht die Maschine in `instkern.fi` und hat **genau zwei**
Aufrufer. Was dort neu ist gegenüber der Vorlage:

* sie **sagt, wo sie steht** (`schritt_nr()`, `fortschritt()` in
  Promille) — das Kopieren dauert Minuten, und ein Fenster, das
  minutenlang nichts sagt, ist von einem abgestürzten nicht zu
  unterscheiden;
* sie meldet einen Fehlergrund als **Zahl**, nicht als deutschen Satz.
  Eine Bibliothek, die selbst auf die Leitung schreibt, nimmt dem
  Aufrufer die Entscheidung ab, ob und wie er es sagen will.

`check-ui.sh` bleibt grün: das Fenster malt nichts selbst.

---

## 2. Die Abnahmekette

Ein Installationsprogramm ist nicht fertig, wenn es „fertig" meldet. Es
ist fertig, wenn die Maschine **ohne das Installationsmedium** startet
und das Angelegte einen Neustart überlebt.

```
  vom Stick starten
    -> das Fenster steht, die Platte ist gelistet
    -> installieren
    -> Maschine AUS
    -> Medium WEG  (kein -kernel, kein -initrd, nur OVMF)
    -> von der PLATTE starten
    -> eine Datei anlegen
    -> NEU STARTEN
    -> die Datei ist noch da
```

Dazu die Gegenprobe: ein gekipptes Oktett im **Superblock** der
Wurzelpartition, und der Kern darf sie dann **nicht** einhängen. (Nicht
die GPT-Tafel: einen kaputten primären GPT-Kopf repariert OVMF aus der
Sicherung, bevor ein Betriebssystem ihn sieht — das hat schon Runde
INSTALL gemessen. Wer dort misst, prüft die Firmware und nicht sich
selbst.)

**Ergebnis: 27 Zusagen, 0 Fehler.** Das ganze Protokoll liegt unter
`docs/bilder/installer/abnahme.log`.

| Glied | Gemessen |
|---|---|
| Fenster steht | 63,9 % Tinte im Fensterbereich, 6 Bedienelemente gemeldet |
| Platte erkannt | `/dev/hda`, 655360 Sektoren, als leer erkannt |
| Installation | alle fünf Schritte auf der Leitung (1 2 3 4 5), `installer: fertig` |
| Wirt liest nach | GPT: Partition 1 EFI (`EF00`), Partition 2 `OSUM`; ESP trägt `BOOTX64.EFI` (253 952), `osum.mb` (5 060 040), `limine.conf` |
| **Start von der Platte** | **ohne `-kernel`, ohne `-initrd`, nur OVMF:** `wm: rootpart=1 first=72048 blocks=583279`, `wm: mount=1` |
| Gegenprobe | `from module` kommt **nicht** vor — es war kein Stick im Spiel |
| **Schreibtisch** | `desk: start /bin/desktop` — und ein **Bild** davon, 65 % Tinte |
| Datei anlegen | `/beweis.txt` geschrieben und gelesen |
| **Neustart** | **die Datei ist noch da, mit Inhalt** |
| Gegenprobe | gekippter Superblock ⇒ die Wurzel wird **nicht** eingehängt |

Bilder:

| Datei | Was |
|---|---|
| `20-fenster.png` | das Installationsfenster, vom Stick gestartet |
| `30-fertig.png` | nach der Installation |
| `40-von-der-platte.png` | **der Schreibtisch, von der Platte, ohne Stick** |

---

## 3. Die Fehler, die dabei gefunden wurden

Fünf davon waren im Quelltext nicht zu sehen. Sie stehen hier, weil sie
die eigentliche Arbeit dieser Runde sind.

### 3.1 Ein Fenster, in dem nichts stand

Die erste Fassung setzte vier Schachteln mit selbst ausgerechneten
Y-Werten nebeneinander. Ergebnis: **94,6 % einfarbige Fläche**, gemessen
mit `pruef/bildpruef.py` — nur der Titelbalken war da.

Richtig ist das Muster des Aufgabenverwalters: **ein** `box_v` über das
ganze Fenster, die Widgets der Reihe nach hinein, die Knopfreihe als
`box_h` rechts unten. Danach 58,0 % Tinte und Inhalt in jedem Achtel.

### 3.2 Eine Tabelle ohne Kopfzeile ist ein Absturz

```
user fault: pid=4 vector=14 err=0x5 cr2=0x0
            rip=0x4012a925          (= wlib.row_len)
```

`paint_table` liest Zeile 0 des Textblocks als Beschriftung
(`row_at(text, 0)`). Fehlt sie, kommt 0 zurück, `row_len(0)` liest an
Adresse null, und der Prozess stirbt. **Im Bild sieht man davon nichts**:
der Fensterserver malt den Rahmen weiter, das Programm dahinter ist schon
tot. Nur Foto *und* serielle Leitung zusammen zeigen so etwas.

### 3.3 Der Schalter, der nie ankam

In **jedem** Programm dieses Baums mit `profile app` steht

```firn
fn main() -> i32 { return u_start(0) as i32 }
```

darüber der Satz „das `main`, das nie läuft — `user.ld` springt nach
`u_start`". **Der Satz stimmt für `profile kernel` und nicht für
`profile app`.** Nachgemessen an der fertigen Datei:

```
401000eb: mov  %rsp,%rdi      <- der Argumentblock
401000f2: call 0x40102d4a     <- und das ist `main`, nicht u_start
```

Unter `app` bindet der Übersetzer sein eigenes `_start` ein (es liegt kein
`crt.o` daneben), und das ruft `main`. Die Null in dieser Zeile hat den
Argumentblock weggeworfen: `installer: argc=0`, obwohl der Kern ihn gebaut
und übergeben hatte. Mit `proc.ARGS_BASE` statt der Null: `argc=2`.

**Das betrifft nicht nur diese Datei.** Dieselben drei Zeilen stehen in
`desktop`, `taskbar`, `settings`, `launcher`, `explorer`, `widgetdemo`,
`taskmgr`, `calc`, `certus`, `speicher`. Deren Gegenproben (`nohit`,
`noclip`, `nokeys`, `noidx`) haben **nie gewirkt** — die Testläufer sind
grün, ohne dass der Schalter je etwas getan hätte. Hier ist es **nur für
`installer.fi`** repariert; der Rest gehört in eine eigene Runde, weil
jede dieser Gegenproben einzeln nachgemessen werden muss.

### 3.4 Eine Platte, die es nicht gibt

`/dev/nvme0` meldet eine Größe, auch wenn auf der Leitung `nvme: skipped`
steht: `devfs` gibt `blk.blocks_on() * BS` zurück und nicht die Antwort
eines Geräts. Ein Geisterlaufwerk in der Liste eines
Installationsprogramms ist kein Schönheitsfehler — es ist anklickbar.
Jetzt wird der erste Sektor **gelesen**, bevor eine Platte in die Liste
kommt.

### 3.5 Die Startdatei, die kopiert wurde — der schlimmste Fund

`installer: bei=5` hat die Stelle benannt. Zwei Teile, der zweite wiegt
schwerer:

1. **Die Datei gibt es auf dem Stick gar nicht.** Die Vorlage kopiert
   `/boot/limine.conf` von der Quelle. `tools/usbimg/build.sh` legt unter
   `/boot/` aber nur `osum.mb` und `BOOTX64.EFI` ab; die `limine.conf`
   entsteht später und geht direkt in die EFI-Partition des **Sticks**.
   Die Kopie konnte nur fehlschlagen — und weil alles andere schon
   geschrieben war, lag die Installation vollständig auf der Platte und
   meldete trotzdem einen Fehler.

2. **Und selbst wenn sie da wäre, wäre sie die falsche.** Die Startdatei
   des Sticks trägt `module_path: boot():/root.img` und `modfs` in der
   Kommandozeile: die Wurzel kommt dort als Boot-Modul in den
   Arbeitsspeicher. Genau das soll nach der Installation nicht mehr
   passieren. Eine kopierte Startdatei hätte eine Platte ergeben, die
   **bootet und trotzdem nichts behält** — also genau den Zustand, gegen
   den diese Runde antritt, nur unsichtbar, weil er wie ein Erfolg
   aussieht.

Der Installer schreibt die Datei jetzt selbst, mit der Kommandozeile, die
zu dem passt, was er angelegt hat.

### 3.6 Zwei Fallen im Messaufbau

* **`wighalt` wirkt nur zusammen mit `wmhold`.** Die Halteschleife in
  `kernel/kgui.fi` steht hinter `if !mode_on(M_WMHOLD)`. Ohne `wmhold`
  liest `wighalt` niemand, auf der Leitung fehlt `wm: halt sek=`, und der
  Kern fährt herunter, sobald der Fensterserver seine Messreihe fertig
  hat — mitten in der Installation.
* **Unter `desk` erreicht die Ausgabe eines Ring-3-Programms die serielle
  Leitung nicht.** Zum Messen `gfx wm wig` **ohne** `desk` nehmen.

---

## 4. Was O-009 angeht

`O-009` sagt: der Geräteschlüssel `/etc/jarvis/geraet.key` entsteht beim
Koppeln in der **RAM-Wurzel**, also muss nach jedem Neustart neu
gekoppelt werden — „hängt an `P-001`".

Das ist mit dieser Runde **strukturell** gelöst und **noch nicht
gemessen**: Glied 6/7 der Abnahme weist nach, dass eine angelegte Datei
den Neustart übersteht, weil die Wurzel auf der Partition liegt. Für den
Schlüssel gilt derselbe Weg — aber „derselbe Weg" ist eine Behauptung,
solange niemand koppelt, neu startet und nachsieht. Das gehört in die
Runde, die `jarvisd` auf einer installierten Platte misst, und es steht
hier, damit niemand `O-009` für erledigt hält.

---

## 5. Was offen bleibt

* **Der Zielpfad der EFI-Partition ist `/dev/hda1` fest verdrahtet** —
  in der Vorlage wie hier. Eine Installation auf `/dev/hdb` schreibt GPT
  und Wurzel richtig und hängt danach die falsche EFI-Partition ein. Die
  Liste zeigt heute nur Platten, die lesbar sind; sie zeigt sie aber
  alle, und zwei davon sind auswählbar.
* **Die Fortschrittsanzeige steht still, während kopiert wird.** Die
  Installation läuft in einem Zug und nicht häppchenweise zwischen zwei
  Ereignissen — Absicht (eine halb geschriebene Partitionstafel ist ein
  kaputter Datenträger), aber der Balken bewegt sich dadurch nur zwischen
  den fünf Abschnitten.
* **`main`/`u_start` in den zehn anderen Programmen** (siehe 3.3).
* **Kein Formatieren, kein Auswählen einer Partition** — die Platte wird
  ganz genommen. `P-012` bleibt offen.
