# Runde VIELKERN — Ring 3 auf allen Kernen, und drei Messgeräte, die gelogen haben

*05.09.2026 · Repo `/root/osum-blechhid` · Grundlage Commit `a53cb1d`*

---

## 1. `KSTACK_CUR` je Kern — der Preis der Vorrunde ist zurückgezahlt

Runde BLECHKERN musste Ring 3 an Kern 0 binden, weil `syscall_entry` in
`isr.s` den Kernstapel aus **einem** Wort für die ganze Maschine holte
(`kdata + KSTACK_CUR`) und `sched.set_kernel_stack` es nur auf Kern 0
schrieb. Damit lief die ganze Oberfläche einkernig.

### Die Entscheidung: GS-Basis, aber **ohne** `swapgs`

Es gibt zwei übliche Wege, und einen dritten, der hier der richtige ist.

**Nicht genommen: ein Feld über die LAPIC-Kennung.** Der Einsprung hat
kein freies Register — `rsp` zeigt noch auf den Benutzerstapel, alle
anderen tragen Benutzerzustand. Um die Kennung zu lesen, bräuchte es
erst einen Ablageplatz im Speicher, und der müsste selbst schon je Kern
sein. Henne und Ei; genau dafür gibt es die Segmentbasis.

**Nicht genommen: `swapgs`.** Der Lehrbuchweg, und er kostet
Paarungsdisziplin in **jedem** der 48 Unterbrechungsstümpfe: jeder
müsste prüfen, ob er aus Ring 3 kam, und nur dann tauschen. Eine
verlorene Hälfte dieser Paarung ist ein Fehler, den man nicht sieht,
sondern erst Wochen später als Absturz. Dazu kommt ein zweiter,
feinerer: `swapgs` bindet die Basis an den *Ablauf*, nicht an den Kern —
wandert eine Aufgabe mitten im Systemaufruf auf einen anderen Kern,
tauscht sie beim Austritt die Basis eines fremden Kerns.

**Genommen: `IA32_GS_BASE` fest auf den `cpu`-Satz dieses Kerns.**
Ring 3 benutzt GS in diesem System **nicht** — nachgezählt am fertigen
Abbild:

    objdump -d kernel.img.elf | grep -c '%gs:'   ->  3   (alle in syscall_entry)

Also darf die Basis stehen bleiben. Sie ist damit eine Eigenschaft des
**Kerns**, nicht der Aufgabe, und überlebt jede Wanderung. Der Tag für
`swapgs` ist der Tag, an dem dieses System TLS in Ring 3 bekommt — und
nicht früher.

### Was geändert wurde

| Stelle | vorher | jetzt |
|---|---|---|
| `isr.s` | `movq %rsp, sys_rsp(%rip)` · `movq kdata+KSTACK_CUR(%rip), %rsp` | `movq %rsp, %gs:0x88` · `movq %gs:0x90, %rsp` |
| `cpu.fi` | — | `C_SYSRSP 136`, `C_KSTACK 144`, `C_TSSADDR 152` |
| `user.fi` | `setup` einmal, auf Kern 0 | `setup_here(state, cpubase)` je Kern: STAR, LSTAR, SFMASK, **EFER.SCE** und GS-Basis |
| `smp.ap_main` | — | ruft `setup_here` **vor** `C_ONLINE = 1` und meldet die Gegenprobe |
| `smp.tables` | TSS installiert, Adresse vergessen | `C_TSSADDR` wird eingetragen |
| `sched.set_kernel_stack` | nur Kern 0 | `C_KSTACK` **und** `RSP0` im TSS **dieses** Kerns |
| `sched.create` | `TC_AFF = 0` für `K_USER` | wieder `ANY_CPU` |
| `sched.darf_ring3` | „nur Kern 0“ | „nur ein Kern mit **geprüfter** GS-Basis“ |

`EFER.SCE` je Kern ist kein Detail: ohne dieses Bit ist `syscall` auf
einem Anwendungskern ein `#UD` — dieselbe Ausnahme wie auf Justins Foto,
nur aus einem anderen Grund.

### Der Beweis

Dieselbe Datei, nur `-smp` verschieden, Limine/UEFI, `-accel kvm -cpu
host`, 3440×1440:

| | `-smp 1` | `-smp 4` | `-smp 8` |
|---|---|---|---|
| Protokollzeilen | 1295 | 1345 | 1352 |
| Ausnahmen | **0** | **0** | **0** |
| `R3K` (Kerne, auf denen Ring 3 lief) | **1** | **4** | **7** |
| `R3W` (Kern ohne eigene GS-Basis) | 0 | 0 | 0 |
| `WA` (Wächterbruch) | 0 | 0 | 0 |

`R3K 4` und `R3K 7` sind die Zahl, um die es geht: vor dieser Runde war
sie unter allen Umständen 1.

---

## 2. Die Messtafel hat abgeschnitten, ohne es zu sagen

Am Ende der Vorrunde stand mein eigener Satz: *„Nach dem Brennen:
Tafelzeile 12. Dort muss `WA 0` **und `R3F 0`** stehen.“*

Zeile 12 war **70 Zeichen** lang. Die Tafel ist **48** breit. Auf dem
Schirm stand:

    12 STUFE ST 38 MAX 38 RND 12970 LOOP 1362 TB 1 W

`WA`, `T`, `KS` und `R3F` waren **abgeschnitten**. Ich habe Justin
gebeten, etwas nachzusehen, das er nicht sehen konnte.

Behoben in drei Schritten:

1. **`tafel_merken` zählt jede zu lange Zeile** — als Bitmaske, damit
   dort nicht die Zahl der Anstriche steht, sondern die Zahl der
   *verschiedenen* betroffenen Zeilen, dazu die schlimmste Länge.
2. Die Sicherheitszahlen bekommen eine **eigene Zeile 23**:

       23 SICHER WA 0 KS 47360 R3W 0 R3K 4 LG 0

3. Die vier gefundenen Überlängen (Zeilen 8, 12, 18, 19) sind gekürzt.
   Am Ende steht `LG 0`.

`LG` ist damit das Messgerät für das Messgerät. Steht dort etwas anderes
als 0, fehlt auf dem Schirm etwas — und dann ist keine Zahl der Tafel
mehr vollständig.

---

## 3. `ROH` war nie kaputt — die Frage war falsch gestellt

`ROH` las den DMA-Puffer, also das, was die Karte **zuletzt**
hineingeschrieben hat. Eine USB-Tastatur im Boot-Protokoll schickt beim
**Loslassen** einen Bericht aus acht Nullen. Nach jedem normalen
Tastendruck steht dort also `0000000000000000` — die Tafel zeigte
getreulich den Zustand „gerade wird keine Taste gehalten“.

Deshalb lautete die Anleitung dazu auch: *„eine Taste drücken und
HALTEN, dann fotografieren“*. Ein Messgerät, das eine dritte Hand
braucht, ist keins.

Jetzt wird der letzte Bericht gemerkt, der **nicht** leer war
(`usb.D_ROHW`), dazu ihre Anzahl (`D_ROHN`). Gemessen, vier normale
Tastendrücke, ohne Halten:

    18 TAST D 1 BER 10 ARM 11 CC 1 RK 001B0000 N 6

`RK 001B0000` = Umschalttasten 00, erster Tastencode **0x1B** — das ist
`x`, die zuletzt gedrückte Taste. `N 6` sind sechs nicht-leere Berichte.

Vier statt acht Oktett, weil acht Oktett 51 Zeichen ergäben und die
Tafel 48 breit ist — derselbe Fehler wie bei Zeile 12, diesmal vorher
bemerkt.

**So liest man es jetzt:** `N` steigt und `TAS` bleibt 0 → der Bericht
kommt an, der **Zerleger** ist schuld. `N` bleibt 0 und `BER` steigt →
es kommen nur Leermeldungen, dann ist es der **Endpunkt**.

---

## 4. Blit-Versatz bei 3440 — der Verdacht ist **widerlegt**

Die Vermutung lautete: eine Stride-Rechnung bricht bei 3440
Bildpunkten, weil 3440 kein Vielfaches von 8 oder 16 sei. **Das stimmt
schon rechnerisch nicht:** 3440 = 16 · 215, also durch 8 und 16 teilbar.

Der ernstzunehmende Fall ist ein anderer und steht in der eigenen
Startzeile des Kerns:

    fb: 3440x1440x32  pitch=13760        13760 = 3440 * 4

Unter QEMU ist die Zeilenbreite **genau** Breite mal vier. Auf echter
Firmware ist sie das oft nicht — eine GOP meldet für 3440 gern 3456 je
Zeile. Jede Rechnung, die `breite * 4` schreibt, wo `zeilenbreite`
stehen müsste, wäre im Prüfstand richtig und auf Justins Brett falsch.

Dafür gibt es jetzt **`fbpad=<n>`**: die gemeldete Breite wird um n
Bildpunkte verkleinert, die Zeilenbreite bleibt. Kein Oktett außerhalb
des echten Rahmenpuffers.

    ohne:  fb: 3440x1440x32  pitch=13760
    mit:   fb: 3424x1440x32  pitch=13760      <- genau Justins Fall

Gemessen am Bildschirmfoto beider Läufe:

| | `fbpad=0` | `fbpad=16` |
|---|---|---|
| Oberkante der Leiste, 17 Spalten von 0 bis 3400 | alle **y=1360** | alle **y=1360** |
| verschiedene Bildpunkte im Bereich 0…3424 | — | **0,39 %** (Uhr und Zähler) |

Kein Versatz, kein Schrägzug, keine verschobene Zeile. **Der Zeichenweg
rechnet mit der Zeilenbreite, nicht mit der Breite.**

### Was dann?

Zeichen können links noch auf einem zweiten Weg verschwinden: durch das
**Schnittfenster**. `wm.fb_glyph` lässt jeden Bildpunkt mit `pxx < ax0`
aus. Liegt `ax0` rechts vom Titelanfang, fehlt genau der linke Teil des
Textes — und der Rahmen bleibt heil, weil er in einem anderen Aufruf mit
einem anderen Schnitt gemalt wird. Das passt auf Justins Beobachtung
(`inal -- sh` statt `Terminal -- sh`) genauer als jede Stride-Theorie.

Das ist jetzt keine Vermutung mehr, sondern eine **Zahl**: `TK` auf
Tafelzeile 7 zählt, wie oft der Titel links beschnitten wurde. Ein
einziges Foto entscheidet.

---

## 5. Der Fehler, den die Regression gefangen hat

Nach dem Umbau fiel `tools/einsprung/run.sh` von **12 auf 7 von 14**,
mit einem Dreifachfehler:

    *** EXCEPTION 8 #DF  rip=0x1002c3  rsp=0x0

`0x1002c3` ist das dritte der drei neuen Befehle — `push %gs:0x88` —
und `rsp=0x0` heißt: `%gs:CPU_KSTACK` war **null**.

Die Ursache steht in `cpu.register`:

```
    while i < kstate.CPU_BYTES / 8 {
        __mmio_write64((record(state, n) + i * 8) as *mut u64, 0)
```

Der ganze Satz wird genullt. Das ist richtig, wenn ein Satz **angelegt**
wird — und `register` läuft in `smp.probe`, also **nach** `sched.init`
und **nach** `user.setup`. Für Satz 0 war es kein Anlegen, sondern ein
Überschreiben von etwas, das schon in Benutzung war: `C_KSTACK` stand
auf `syscall_stack_top` und war danach 0.

Behoben auf zwei Ebenen: `register` rettet `C_SYSRSP`, `C_KSTACK` und
`C_TSSADDR` über das Nullen hinweg, und `kmain` trägt nach `smp.stage`
beides noch einmal ein (`sched.kstack_wieder`) — für den Fall, dass der
Startkern dort eine andere Satznummer als 0 bekommt.

Dazu eine Zeile, die es beim nächsten Mal sofort sagt, statt es als
Dreifachfehler zu zeigen:

    user: gs-basis 0x593000  kstack 0x570000

Danach wieder **12 von 14**, mit denselben zwei Fehlern wie in den
beiden Runden davor (`wm: hold` braucht länger als die 240 s des
Prüfskripts; ein Erwartungstext aus einer Vorrunde). Keine Regression.

---

## 6. Und der zweite Fehler, den die Abnahme gefangen hat

Mit Ring 3 auf allen Kernen startet der **volle Schreibtisch** nicht
mehr vollständig:

    desk: start /bin/desktop  pid=6
    desk: start /bin/taskbar  pid=0      <- kein Prozess
    desk: start /bin/launcher pid=7

`pid=0` heißt: `elf.spawn` hat gar nicht erst angelegt — es gibt keine
`elf: start`-Zeile davor, keinen `user fault`, keine Ausnahme. Zweimal
von zwei Läufen, also kein Zufall. Danach ist die Leiste weg
(`7 LEISTE KEIN`), und damit ist genau das kaputt, worum es Justin
geht.

Der Kern-Unterbau ist davon **nicht** betroffen: dieselben Kerne, die
hier den Schreibtisch nicht hochbringen, fahren den kleineren Aufbau
(`kurz.sh`, Leiste + Uhr + Eingabe) mit `R3K 4` und **null** Ausnahmen
durch. Der Fehler sitzt oberhalb — im Anlegen eines Prozesses aus einem
Prozess heraus, auf einem anderen Kern als dem, der `desk` gerade
ausführt. Gefunden ist er nicht.

**Also fährt das ausgelieferte Abbild wie das der Runde BLECHKERN:
Ring 3 auf Kern 0.** Das neue Wort **`r3alle`** auf der
Kernel-Befehlszeile gibt alle Kerne frei — für den nächsten, der die
Ursache sucht, und ohne dass dafür ein zweiter Kernel gebaut werden
muss. `R3K` auf Tafelzeile 23 sagt jederzeit, was gerade gilt: `1` ohne
das Wort, `4` bzw. `7` mit ihm.

Das ist kein schöner Abschluss, aber es ist der ehrliche: der Unterbau
ist gebaut und belegt, und er wird erst scharf geschaltet, wenn der
Schreibtisch darauf steht.

---

## 7. Die Abnahme

Am **fertigen Abbild**, Limine, UEFI, `-accel kvm -cpu host`,
**`-smp 4`**, 3440×1440, xHCI-Tastatur + USB-Maus, e1000 mit DHCP.

| gemessen | Zahl |
|---|---|
| Anstriche der Leiste | **180** |
| Uhr-Anstriche / davon **verschiedene** | 179 / **177** |
| erste → letzte Uhr | `13:34:45` → `13:37:41` = **176 s durchgehend** |
| `EXCEPTION` · `user fault` · `UEBERGELAUFEN` · `lock: stuck` | **0 · 0 · 0 · 0** |
| Tafelzeile 23 | `WA 0  KS 50896  R3W 0  R3K 1  LG 0` |
| Tafelzeile 18 | `TAST D 1 BER 16 ARM 17 CC 1 RK 08000000 N 10` |
| Tafelzeile 7 | `LEISTE id9 y1400 MAL 145 fl2 ZU 1 **TK 0**` |
| Netz | `22 NETZ K2 BDF 0020 L 1 ABL 0 IP 10.0.2.15` |
| Klicks / davon auf den Startknopf | 7 / **4** |
| Startmenü | `launcher pid=25` |
| `tools/einsprung/run.sh` | **12 von 14** — dieselben zwei wie in den beiden Runden davor |

`LG 0` ist neu und wichtig: **keine** Tafelzeile wird mehr
abgeschnitten. Was auf dem Schirm steht, ist vollständig.

`KS 50896` von 65536 — 78 %. Der höchste bisher gemessene Wert; die
Wächterseite steht, aber die Zahl ist im Auge zu behalten.

---

## 8. Ehrlich offen

**Nicht gebaut in dieser Runde:** Startmenü Stufe 2, Ausbau des
Kontrollzentrums, App-Store mit echtem Inhalt, jarvisd-Ausbau. Für den
App-Store liegt die Werkzeugkette bereit
(`tools/ota/veroeffentlichen.py`, `verzeichnis.py`, `opk.py`), und
`jarvisd` hat den Bildschirmfoto-Auftrag (`jarvisd -f <pfad>`, PPM) und
die Startdiagnose (`jarvisd -d`) schon aus der Vorrunde. Beides ist
begonnene Arbeit, nicht fehlende.

**Serielle Ausgabe verschränkt sich jetzt.** Mit Ring 3 auf allen Kernen
schreiben mehrere Kerne gleichzeitig auf dieselbe Leitung, und
`serial.puts` nimmt keine Sperre (`atomic.L_CONSOLE` ist definiert und
wird von niemandem genommen). Eine Sperre dort wäre eine Sperre im
Unterbrechungspfad und kann sich mit sich selbst verklemmen — das ist
eine eigene Runde. Für Justin ändert sich nichts: sein Brett hat keine
serielle Leitung (`LSR FF`). Für den Prüfstand heißt es, dass einzelne
Protokollzeilen ineinanderlaufen können.

---
---

# Runde VIELKERN 3 — scharf geschaltet, und der Riegel wird gebrochen

*05.09.2026 · Arbeitsbaum `/root/osum-vielkern`, Zweig `vielkern3`,
abgezweigt von `hidweg` @ 1493451*

Die Vorrunde endete mit einem ehrlichen Satz und einem offenen Fehler:

> **Also fährt das ausgelieferte Abbild wie das der Runde BLECHKERN:
> Ring 3 auf Kern 0.** […] `/bin/taskbar` bekommt beim Start `pid=0`,
> zweimal von zwei Läufen — der Prozess wird gar nicht erst angelegt,
> und die Leiste fehlt. Warum, ist nicht gefunden.

Diese Runde findet es, behebt es, misst es und schaltet scharf.

---

## 1. Ein Fehlschlag, der nichts sagt, ist keine Messung

Vor `pid=0` stand nichts: keine `elf: start`-Zeile, keine Ausnahme,
kein Grund. Dabei legt `elf.build` seinen Grund seit jeher in
`kstate.ELF_ERR` ab, und `sys.do_exec` liest ihn auch aus — nur der Weg
**aus dem Kern heraus** (`kgui.desk_spawn_n`) tat es nicht.

Drei Zeilen dazu, und der erste Lauf sagte, wo es sitzt:

    desk: start /bin/taskbar   pid=0  kern=0
    elf: refused, reason 1  no such file
    desk: start /bin/launcher  pid=0  kern=0
    elf: refused, reason 2  not a plain file

`/bin/launcher` **ist** eine gewöhnliche Datei. Und weil ein Treiber,
der stumm scheitert, aus einem Plattenfehler einen Dateisystemfehler
macht, zählt `blk.fi` seither jeden ATA-Fehlschlag und nennt die ersten
acht mit Block und Statusregister. **Es kam keine einzige solche
Zeile.** Die Platte war es nicht.

## 2. Die Ursache: das zweite `KSTACK_CUR`

```
fn inode_get(state, ino, field) -> u64 {
    ofsj.read(state, inode_block_of(state, ino), buf_in(state))   // EIN Puffer
    return get64(buf_in(state) + inode_off(state, ino) + field)   // fuer die
}                                                                 // ganze Maschine
```

`buf_in` ist **ein** Block von 512 Oktetten in der Datenseite. Zwischen
dem Lesen und dem Herausholen liegt nichts — solange nur **ein** Kern im
Dateisystem ist. Genau das war bis zur Vorrunde der Fall: Ring 3 lief auf
Kern 0, und die Arbeit des Kerns auch. Mit `r3alle` liest Kern 0 den
Inode von A hinein, Kern 2 überschreibt ihn mit dem von B, und Kern 0
liest die **Art** von B aus dem Feld von A. Daher `not a plain file` für
eine gewöhnliche Datei.

**Dieselbe Fehlerform wie `KSTACK_CUR`, ein Stockwerk tiefer**: ein Wort
für die ganze Maschine, das nur hielt, weil nie zwei Kerne gleichzeitig
hinsahen. Der Riegel dafür war die ganze Zeit da (`atomic.L_FS` über
`fs.enter`/`leave`, **je Kern wiedereintrittsfähig**) — er lag nur nicht
um diese Zugriffe.

Unter die Sperre kommen jetzt alle Wege, die einen Block in einen
geteilten Puffer holen: `inode_get`, `inode_set`, `inode_init`,
`used_inodes`, `free_blocks`, `file_truncate` (`buf_ib`/`buf_i2`/
`buf_dt`), `entry_at` (die **ganze** Aufzählung, nicht je Eintrag) und
`symlink_path` (`OP_TMP`).

**Nachgezählt statt behauptet**, und zwar an der Quelle: von den 112
Funktionen in `fs.fi` fassen 10 Blöcke direkt an, und **jeder** ihrer
Wege nach draußen geht durch `enter`. Das ist Abschnitt 3 von
`tools/vielkern/run.sh` und läuft bei jeder Abnahme mit.

| voller Schreibtisch, `-smp 8 r3alle einst` | vorher | nachher |
|---|---|---|
| `/bin/desktop` | pid≠0 | pid≠0 |
| `/bin/taskbar` | **pid=0**, `reason 1` | pid≠0 |
| `/bin/launcher` | **pid=0**, `reason 2` | pid≠0 |
| `/bin/settings` | **pid=0**, `reason 2` | pid≠0 |
| Tafelzeile 23 | — | `WA 0 R3W 0 R3K 7 LG 0` |

## 3. Die Messung: welcher Prozess auf welchem Kern

`R3K` allein ist eine Zahl ohne Auflösung dahinter. Jetzt steht da, wer
wo war — alle fünf Sekunden, mit der Tafel:

    r3: pid=18  kern=6  maske=0xdb  n=6  runs=67
    r3: pid=19  kern=0  maske=0xcf  n=6  runs=48
    r3: prozesse=4  kerne=0xdb  n=6  fremd=4  alle=1
    r3: syscalls  c0=52 c1=26 c2=0 c3=261 c4=50 c5=0 c6=11 c7=0  summe=400  abw=0

`maske` ist `TC_MASK`, ein Bit je Kern, auf dem die Aufgabe **je** lief;
`kern` ist `TC_CPU`, der letzte.

**Die letzte Zeile ist der eigentliche Beweis.** Gezählt wird in
`syscall_entry` mit **einem** Befehl:

    incq %gs:CPU_SYSCALLS

— im selben `cpu`-Satz und über **dieselbe GS-Basis**, aus der eine
Zeile darüber der Kernstapel kommt. Zählt ein Kern hier hoch, dann hat
sein `%gs:CPU_KSTACK` funktioniert: er steht ja schon darauf. Hätte ein
Kern eine falsche Basis, zählte er in einen fremden Satz — und `abw`
(Summe der Zähler gegen `kstate.SYSCALLS`) wäre nicht null. Das kostet
einen Befehl und **kein** `cpu.here` je Systemaufruf.

`abw` war in **jedem** gemessenen Lauf 0.

| voller Schreibtisch, vier Ring-3-Programme | Kerne mit Ring 3 | Systemaufrufe je Kern |
|---|---|---|
| `-smp 4 r3eins` | **1** | `c0=590 c1=0 c2=0 c3=0` |
| `-smp 4` (Vorgabe) | **4** | `c0=328 c1=107878 c2=2594 c3=558` |
| `-smp 8` (Vorgabe) | **5…8** | über fünf bis acht Kerne verteilt |

## 4. Eine Zeile bleibt eine Zeile

Der erste Lauf der neuen Messung sah so aus:

    r3: pid=16  kern=2  maske=0x4  n=1  rulnsau=n1c

Das ist `runs=1` und `launc…` ineinander — mehrere Kerne auf einer
seriellen Leitung, `serial.puts` schreibt Zeichen für Zeichen. Für einen
Menschen häßlich, für einen Prüfstand das Ende der Messung.

Der Einwand aus Abschnitt 8 der Vorrunde („eine Sperre dort liegt im
Unterbrechungspfad und kann sich mit sich selbst verklemmen") ist
richtig — und lösbar. `serial.zeile_an`/`zeile_aus` ist **je Kern
wiedereintrittsfähig** wie `fs.enter`: gehört die Sperre diesem Kern
schon, wird nicht gewartet, sondern geschrieben. Ein Behandler, der
einen schreibenden Kern unterbricht, wartet damit nie auf sich selbst.
Und sie ist **begrenzt**: wer 20 Mio. Runden wartet, schreibt trotzdem
(`zeile_verloren()` zählt es) — gerade die Ausgabe muß überleben, wenn
sonst nichts mehr geht. Sie liegt **nicht** in `put`/`puts`, sondern um
die Zeilen herum, deren Text gemessen wird.

## 5. Der Riegel wird gebrochen — `tools/vielkern/run.sh`

Runde BLECHKERN hat ihren Fehler nicht deshalb übersehen, weil er
schwer zu sehen war, sondern weil **niemand ihn herbeiführen konnte**.
Die Bedingung stand im Kommentar, die Abnahme war grün, und aufgefallen
ist es auf Justins Brett.

Zwei neue Wörter auf der Kernel-Befehlszeile machen ihn bestellbar:

| Wort | was es tut |
|---|---|
| `gsluege` | jeder Anwendungskern bekommt die GS-Basis von **Kern 0** (`smp.ap_main`, vor `gs_melden`) — der Zustand vom 05.09. |
| `r3blind` | `sched.darf_ring3` fragt nicht mehr nach der GS-Basis |

**Mit `gsluege` allein muß der Riegel halten** — gemessen:

    tafel: 23 SICHER WA 0 KS 42488 R3W 3 R3K 1 LG 0
    keine Ausnahme, nur Kern 0 bekommt Systemaufrufe

**Mit `gsluege r3blind` muß er brechen** — und er bricht mit genau der
Signatur von Justins Foto:

    absturz:  0 *** ABSTURZ *** VEK 6 #UD
    absturz:  1 RIP 0000000000000007
    absturz:  6 AUF 6 PID 15 ART 3 PRG taskbar BAD 0

Ohne die zweite Hälfte mißt die erste nichts: daß die Maschine dort
lebt, könnte auch Zufall sein.

Dazu drei **statische** Zusagen gegen die Klasse Fehler, die still
bleibt: die Feldabstände in `isr.s` gegen `cpu.fi`, `kstate.MAX_CPUS`
gegen die Größe von `sched.gs_gut`, und der Nachweis an der Quelle über
`fs.fi` aus Abschnitt 2.

Der Läufer ist als **Abschnitt 40** in `test.sh` angemeldet.

## 6. Scharf geschaltet

`sched.ring3_alle` steht ab dieser Runde auf **1**. Die Bedingung, die
sich die Vorrunde selbst gestellt hat („er wird erst scharf geschaltet,
wenn der Schreibtisch darauf steht"), ist erfüllt und gemessen.

**`r3eins`** holt den alten Zustand zurück — Ring 3 nur auf Kern 0,
Oktett für Oktett das Verhalten der Runde BLECHKERN. Es wird **nach**
`r3alle` gefragt und gewinnt, wenn jemand beides schreibt: die
vorsichtigere Angabe schlägt die kühnere. Auf dem Stick liegt es als
eigener Menüeintrag, dazu einer mit `gsluege` als Gegenprobe auf Blech.
`r3blind` gibt es auf dem Stick **nicht** — das ist der Eintrag, der die
Maschine mit Absicht umbringt, und der gehört in den Prüfstand.

## 7. Ehrlich offen

* **Auf echtem Blech ist das noch nicht gelaufen.** Alle Zahlen dieser
  Runde kommen aus QEMU/KVM. Der Stick trägt die zwei Einträge dafür
  (Schreibtisch mit der neuen Vorgabe, plus `r3eins` als
  Rückfallebene); was zu fotografieren ist, steht in
  `tools/usbimg/build.sh` beim Eintrag.
* **Fairness zwischen den Kernen ist nicht gemessen.** In mehreren
  Läufen bekamen zwei der vier Prozesse auffällig wenige Züge
  (`runs=67 / 48 / 1 / 1`), während ohne `r3alle` alle vier auf
  ähnliche Zahlen kommen (`136 / 116 / 92 / 89`). Ob das an der Weckung
  über Kerngrenzen liegt oder daran, daß die betroffenen Prozesse
  einfach auf Ereignisse warten, ist **offen**. Es ist keine
  Korrektheitsfrage — `abw` bleibt 0, es gibt keine Ausnahme —, aber es
  ist die nächste Runde: *die Weckung über Kerngrenzen, mit Zahlen.*
* **Die Zahl der Systemaufrufe je Lauf schwankt um Größenordnungen**
  (590 bis 111 358 in gleich langen Läufen), je nachdem, ob
  `/bin/launcher` gerade seinen Namensindex durchsucht. Sie taugt als
  Verteilungsmaß (auf wie vielen Kernen kommt etwas an) und **nicht**
  als Durchsatzmaß. Ein Durchsatzmaß für den Schreibtisch gibt es in
  diesem Repo noch nicht.
* **`kstate.KSTACK_CUR` wird weiter mitgeschrieben und von niemandem
  gelesen.** Das ist Absicht und steht so in `sched.set_kernel_stack`:
  es bleibt als Anzeige stehen, bis eine Runde die Datenseite aufräumt.

## 8. Vorgefunden, **nicht** von dieser Runde

Die Abnahme dieses Zweigs hat rote Abschnitte, die schon auf `hidweg`
rot waren. Sie stehen hier, weil ein roter Abschnitt, über den alle
hinwegsehen, genau das ist, wovor `tools/gfx/run.sh` in seinem eigenen
Kommentar warnt — und weil der nächste, der sie sieht, wissen soll, daß
sie nachgemessen sind.

| Abschnitt | dieser Zweig | Grundlinie | Befund |
|---|---|---|---|
| 1 — festgenagelter Übersetzer | rot | **rot** | `vendor/firn/.gebaut` hat zwei Felder (`<commit> <flicken>`), `test.sh` vergleicht gegen ein Feld; und `vendor/net/BLOBS` nennt für `net/stack.fi` `136851a0…`, im Baum liegt `723eaa12…`. **Beides Oktett für Oktett identisch im unberührten Basisbaum `/root/osum-blechhid`.** |
| gfx | 46 / 30 | **rot** | zwei Ursachen, beide alt |
| display | 126 / 19 | 145 / 0 (03.09.) | dieselbe zweite Ursache wie gfx |
| customres | 126 / 9 | — | dieselbe |
| k16 | 60 / 4 | 58 / 6 (03.09.) | **weniger** Fehler als vorher |
| k17 | 157 / 1 | 154 / 4 (03.09.) | **weniger** |
| k18 | 169 / 1 | 167 / 3 (03.09.) | **weniger** |
| arm | 47 / 1 | 47 / 1 (03.09.) | unverändert |

**Die zwei Ursachen in gfx**, beide nachgemessen:

1. **`kernel/fb.fi` enthält NUL-Oktette**, `grep` hält die Datei damit
   für binär. `tools/gfx/run.sh` liest `WIN_LIST` mit `grep -E` **ohne
   `-a`** und bekommt eine leere Zeichenkette. Zwei statische Zusagen
   fallen daran.
2. **`fb: hold` wird nicht mehr ausgegeben**, obwohl `fbhold` auf der
   Befehlszeile steht. `kgui.gfx_hold` kommt bis
   `if !fb.want(state, fb.M_HOLD) { return }` und kehrt dort um —
   `FB_OFF + S_MODE` trägt das Bit 32 nicht, während `M_GFX` aus
   derselben Zeile gesetzt ist. Damit wartet jeder Läufer, der ein
   Bildschirmfoto machen will, ins Leere, und alle folgenden Zusagen
   fallen mit `No such file or directory: …ppm`.

   **Nachgemessen mit zwei Kernen aus zwei Commits**, gleiche
   Befehlszeile, gleiche Maschine:

   | Kern | `fb: hold` |
   |---|---|
   | `vielkern3` (dieser Zweig) | **0** |
   | `1493451` (VIELKERN 2, die Grundlinie) | **0** |

   Es ist also **vor** dieser Runde entstanden — irgendwo zwischen dem
   grünen Lauf vom 03.09. und `1493451`, also in BLECHKERN oder
   VIELKERN 1/2. Behoben wird es hier nicht: das ist eine eigene Runde,
   und sie bekommt drei Abschnitte auf einmal zurück (gfx, display,
   customres).

**Grün geblieben sind die vier Läufer, die überhaupt mit mehr als einem
Kern starten** — und nur die konnte das Umschalten der Vorgabe treffen:

    tools/guard/run.sh   58 / 0
    tools/avx/run.sh     32 / 0
    tools/smp/run.sh     59 / 0
    tools/kvm/run.sh     31 / 0

und der neue Läufer selbst:

    tools/vielkern/run.sh   36 / 0
