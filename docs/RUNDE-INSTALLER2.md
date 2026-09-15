# RUNDE INSTALLER2 -- P-001: der Installer bekommt sein Fenster auf

Zweig `installer2`, Basis `main` (55ac7d9). Worktree `/root/osum-w-inst`.

**Ergebnis: `tools/install/abnahme.sh` -- 35 gruen, 0 rot, einschliesslich
Abschnitt 7b.** P-001 traegt, und O-009 ist damit auch auf dem ECHTEN Weg
gemessen (installierte Platte statt RAM-Wurzel).

---

## 1. DIE URSACHE -- UND WARUM DIE AUFTRAGSPRAEMISSEN ALLE FALSCH WAREN

Der Auftrag nannte fuenf Kandidaten: `wigapp` wird nicht gefunden, das
Programm startet und stirbt sofort, der Fensterserver ist noch nicht
bereit, eine Bedingung im Startpfad schlaegt fehl, eine Zeitschranke
greift. **Keiner davon war es.** Zuerst nachgesehen, dann repariert:

| Vermutung | nachgemessen |
|---|---|
| `/bin/installer` fehlt im Abbild | **liegt drin**, 1183360 Oktette (`mkfs.py list`) |
| `sofort` kommt nicht an | **kommt an**: `installer: argc=2 installer sofort` |
| `wigapp=` wird falsch zerlegt | `wigapp_zerlegen` ist korrekt, jedes Komma wird zur Null |
| Programm stirbt sofort | es wurde **nie gestartet** -- `k15: start` stand nirgends |
| Fensterserver nicht bereit | er wurde **nie erreicht** |

### Was wirklich passiert ist

Der Fehler ist eine **Reihenfolge in `kernel/kmain.fi`**:

    osum(state)              Zeile 796
    gfx.stage_surface(state) Zeile 934

`gfx.stage_surface` ist der Weg zur Oberflaeche: ueber `kgui.surface` zu
`k15_start`, und das ist die Stelle, die das Programm aus `wigapp=`
startet. `osum(state)` steht **davor** -- und startet den ERSTEN PROZESS
`/bin/init`. Es kehrt erst zurueck, wenn der fertig ist (`wait_long`).

`init` liest `/etc/ziel`; im Abbild steht dort `grafik`. Die `inittab`
des Sticks fuehrt genau eine Zeile, `sh:konsole:ctrl`. Im Ziel `grafik`
will damit **kein einziger Dienst** laufen. `init` hat nichts zu tun,
dreht seine Leerlaufschleife

    while going == 1 && idle < 4000        // 4000 * 25 ms, rund 100 s

leer, faellt heraus und ruft `shutdown()`. Gemessen, woertlich:

    osum: pid1 init
    init: wurzel=1
    init: ziel=grafik
    init: mounts=0
    init: dienste=1
    init: herunterfahren
    init: orphans=0

Danach ist die Maschine aus. `gfx.stage_surface` wird nie erreicht,
`k15_start` nie gerufen, das Fenster kommt nie. **Das ist der ganze
Fehler.**

### Der Schalter, den es schon gab

`osum()` begann mit

    if wm_owns_shell(state) { return }

und `wm_owns_shell` fragte **nur** nach `M_WMSHELL` -- dem Wort fuer die
Shell IM TERMINALFENSTER. Die Abnahme faehrt mit `wig`. Also war die
Antwort "nein", und `osum` startete init.

### Die Falle, in die der erste Anlauf lief

`wmshell` einfach mitzugeben, repariert das Fenster -- und bricht die
Platte. `osum()` macht naemlich **zweierlei**:

1. die Platte aufbauen: `blk.probe_ata0`, `blk.use_ata`, `fs.mount`,
   `k14_setup`, `/dev`;
2. den ersten Prozess starten.

Die alte Rueckkehr im Kopf der Funktion uebersprang **beides**. Gemessen:
das Fenster stand, aber

    installer: ready n=0

-- keine einzige Platte, obwohl eine daran hing.

---

## 2. WAS GEAENDERT WURDE

### `kernel/kmain.fi` (Commit 412d6d6)

**(a) `wm_owns_shell` fragt nach allen Woertern**, mit denen der
Fensterserver sein Programm selbst startet: `wmshell`, `desk`,
`tileshot`, `wig`, `wigfiles`, `wigstart`. Die Frage heisst "besitzt der
Fensterserver die Sitzung", und das tut er bei `wig` genauso wie bei
`desk` -- `kgui.surface` waehlt zwischen `desk_start` und `k15_start`.

**(b) Die fruehe Rueckkehr steht nicht mehr im Kopf von `osum`**, sondern
genau **vor dem Block RUNDE K13**, also vor dem ersten Prozess (hinter
`usb_hold`/`list_dir`). Damit gilt beides: die Wurzel wird immer
eingehaengt und `/dev` steht -- und wer die Shell besitzt, startet
trotzdem kein zweites init.

### Warum `wmshell` NICHT in die Kommandozeile der Abnahme kam

Ausprobiert und **gemessen verworfen**. Das Wort startet zusaetzlich
`/bin/sh` im Terminalfenster. Unter `nokbd` kehrt deren `read` sofort
mit null zurueck, die Shell endet, und `wait_wm` startet sie im
Sekundentakt neu:

| Lauf | `sh: ready` | Kopiertempo der Wurzel |
|---|---|---|
| mit `wmshell` (Sturm) | **361** | **43 Bloecke/min** |
| mit `wmshell`, frueh | 44 | 940 Bloecke/min |
| ohne `wmshell` (Fix) | **0** | **1878 Bloecke/min** |

Der Installer verhungerte neben seinem eigenen Terminal. Die
Kommandozeile in `tools/install/abnahme.sh` ist deshalb **unveraendert**;
dort steht nur die Begruendung, warum `wmshell` nicht dazugehoert.

### `tools/install/abnahme.sh` (Commit 3e54309) -- drei Fehler IN DER PROBE

Nachdem Glied 1-5 trugen, kam Glied 6/7 an die Reihe. Dort steckten drei
Fehler, alle drei in der Abnahme und nicht im System; zwei haben sich
gegenseitig verdeckt.

**(1) Das Skript lief nie.** `platte_lauf` schreibt eine `limine.conf`
mit `script=...`. Seit der Installer eine VOLLSTAENDIGE Wurzel schreibt,
liegt auf der Platte auch `/bin/init` -- und `osum` startet dann init
statt `/bin/sh`. Das Skript liest laut Kommentar bei `wm_owns_shell`
"der, der zuerst danach greift"; init greift gar nicht danach, findet im
Ziel `grafik` keinen Dienst und schaltet ab. Auf der Leitung stand
**kein** `sh: ready`, `/beweis.txt` wurde nie angelegt. Glied 7 meldete
zu Recht "die Datei ist nach dem Neustart weg" -- sie war nie da.
BEHOBEN: `initsh` in die cmdline der Skriptlaeufe (der dafuer
vorgesehene Notweg, `kmain.fi`, `M_INITSH`).

**(2) Der gruene Haken auf die eigene Frage.** `grep
hallo-von-der-platte schreib.txt` traf die Zeile

    mb: flags=... cmd=... script=echo hallo-von-der-platte >/beweis.txt

also die KOMMANDOZEILE, die der Kern beim Start ausgibt. Das Wort stand
genau einmal in der Datei, in Zeile 7, und das war die `mb:`-Zeile. Der
Test war gruen, waehrend das Skript nie lief -- **er verdeckte (1)**.
BEHOBEN: `grep -va '^mb: '` an beiden Stellen, dazu eine eigene Zusage,
dass ueberhaupt eine Shell gelaufen ist.

**(3) Der Beendigungscode 21 war zu eng.** `kernel/power.fi` sagt es
woertlich: "eine ACPI-Abschaltung ergibt 0, `isa-debug-exit` ergibt 21".
Seit auf der Platte ein vollstaendiges System liegt, endet der Lauf ueber
ACPI (`power: init sagt ab`) und damit mit 0. Auf 21 zu bestehen hiesse,
den SCHLECHTEREN der beiden Wege zu verlangen. BEHOBEN: 21 ODER 0 gelten;
124 (Zeitablauf) und Abstuerze weiterhin nicht.

---

## 3. GEMESSEN

### `tools/install/abnahme.sh` -- **35 gruen, 0 rot**

Glied 1-3, die vorher rot waren:

    [ ok ] das Installationsfenster steht (Bild: 41 % Tinte)     Schranke 5 %
    [ ok ] das Fenster meldet 7 Bedienelemente                   Schranke 5
    [ ok ] die Platte wurde gefunden und aufgelistet

Die Bedienelemente sind **maschinell gezaehlt** (`grep -c 'installer:
rect'`), nicht "es kam ein Bild". Das Programm meldet jedes Rechteck
selbst mit Nummer, Art und Lage:

    installer: rect id=0 kind=1 x=16  y=16  w=688 h=20
    installer: rect id=1 kind=6 x=16  y=44  w=688 h=160
    installer: rect id=2 kind=7 x=16  y=212 w=688 h=32
    installer: rect id=6 kind=1 x=16  y=456 w=688 h=20
    installer: rect id=7 kind=1 x=16  y=484 w=688 h=20
    installer: rect id=8 kind=2 x=484 y=512 w=132 h=32
    installer: rect id=9 kind=2 x=624 y=512 w=80  h=32

Der Start selbst:

    osum: ata0 sectors=655360
    osum: mount=1                       (kein "osum: pid1 init" mehr)
    k15: start /bin/installer  pid=2
    installer: argc=2 installer sofort
    installer: disk /dev/hda 655360
    installer: ready n=1                (vorher n=0)
    installer: start
    installer: step=1 0 ... step=3 0
    installer: step=4 1000
    installer: step=5 1000
    installer: esp=/dev/hda1
    installer: fertig

### Die Platte, vom WIRT nachgelesen

Nicht vom Installer behauptet, sondern mit fremden Werkzeugen gelesen:

    GPT-Signatur      b'EFI PART'
    Partition 1       LBA 2048-72047     34 MiB   "EFI"
    Partition 2       LBA 72048-655326   284 MiB  "OSUM"
    EFI-Dateisystem   FAT32, OEM "MSWIN4.1"
    OSUM-Superblock   "SFO-MUSO"

`mdir` auf der EFI-Partition:

    /osum.mb                 6077024 Oktette
    /limine.conf                 159 Oktette
    /EFI/BOOT/BOOTX64.EFI     253952 Oktette

### Glied 5 -- der Punkt, an dem sich alles entscheidet

QEMU ohne `-kernel`, ohne `-initrd`, ohne `-cdrom`. Nur die Platte und
OVMF:

    [ ok ] die Platte startet und laeuft
    [ ok ] BILD: der Schreibtisch von der Platte (69 % Tinte)
    [ ok ] rootpart=1  first=72048  blocks=583279
    [ ok ] die Wurzel ist eingehaengt
    [ ok ] der Schreibtisch startet von der Platte
    [ ok ] GEGENPROBE: 'from module' kommt nicht vor -- kein Stick im Spiel

### Abschnitt 7b -- O-009 auf dem ECHTEN Weg

**Laeuft durch, sechs Zusagen, alle gruen:**

    [ ok ] Lauf 1: Ed25519-Paar angelegt (pub 45ab2f12284e49ef...)
    [ ok ] O-009: NACH DEM NEUSTART DERSELBE oeffentliche Teil
    [ ok ] O-009: eine Unterschrift VON VOR dem Neustart verifiziert weiterhin
    [ ok ] O-009: fremdes Werkzeug (python-cryptography) rechnet sie nach
    [ ok ] GEGENPROBE: ueber eine andere Nachricht faellt sie durch
    [ ok ] GEGENPROBE: nach dem Zuruecksetzen ist er WEG und ein neuer
           entsteht (pub 8b71a1d75a8b3a4d...)

Damit ist O-009 nicht mehr nur auf der RAM-Wurzel gemessen, sondern auf
der **installierten Platte** -- genau die Frage, die in `OFFEN.md` an
P-001 hing.

### Die Gegenproben, die fehlschlagen MUESSEN

Eine Abnahme, die immer gruen ist, misst nichts. Diese fallen durch, und
das wird als OK gewertet:

* **Glied 8**, ein gekipptes Oktett im Superblock der Wurzelpartition:
  `[ ok ] GEGENPROBE: die kaputte Wurzel wird NICHT eingehaengt`.
* **7b, Zuruecksetzen**: nach `rm /etc/jarvis/geraet.key` entsteht ein
  ANDERER oeffentlicher Teil, und die alte Unterschrift passt nicht mehr.
* **7b, fremde Nachricht**: dieselbe Unterschrift ueber eine andere
  Nachricht verifiziert nicht.
* **Glied 5, `from module`**: kaeme das Wort vor, waere ueber ein
  Boot-Modul gestartet worden und nichts bewiesen.
* Die vom Auftrag verlangte **Wegwerfplatte** steht in
  `tools/geraetekey/run.sh` Abschnitt 5 (`GK_WEGWERF=1`): die Platte wird
  vor jedem Start frisch ueberschrieben, und dann MUSS O-009 melden, dass
  der Schluessel den Neustart nicht ueberlebt hat --
  `[ OK ] mit einer Wegwerfwurzel faellt O-009 durch`.

### Nichts anderes ist umgefallen

| Laeufer | Ergebnis |
|---|---|
| `tools/check-ui.sh` | **CHECK-UI PASSED** |
| `tools/build-kernel.sh` | baut, 6077024 Oktette, Stufe 0 |
| `tools/usbimg/build.sh` | erzeugt Kern, Wurzel und Abbild, 0 Pflichtpfade fehlen |
| `python3 tools/kernel/memmap.py` | 129 Bereiche, 12 Vektoren, 245 Modusnamen in 17 Woertern, **0 Kollisionen** |
| `tools/geraetekey/run.sh` | **12 bestanden, 0 gescheitert** |

---

## 4. SPEICHER

**Kein kdata gebraucht, kein Modusindex gebraucht.** Die Runde hat
weder eine Seite noch ein Modusbit angefasst: `wm_owns_shell` liest
vorhandene Modusbits, und die verschobene Rueckkehr ist Ablaufsteuerung.

Die Zuteilung **0x138000..0x13A000 / Modus 1085..1087 ist unberuehrt**,
`MODE_WORDS` bleibt **17** (245 Modusnamen in 17 Woertern, Grenze
17 * 64 = 1088).

---

## 5. ZUSTAND

**P-001 ist erledigt und gemessen.** Der Installer bekommt sein Fenster
auf, findet die Platte, installiert, und die Maschine startet danach ohne
Medium von der Platte. `tools/install/abnahme.sh` laeuft mit **35 gruen,
0 rot** durch, einschliesslich **7b**.

In `OFFEN.md` kann **O-009** von "gemessen, wartet auf P-001 fuer den
echten Weg" auf **gemessen** gehen -- der echte Weg ist jetzt gemessen.

### Was diese Runde NICHT behauptet

* Der Installer ist mit `sofort` gemessen, also **ohne Mausklick**. Dass
  ein Mensch die Platte in der Liste anklicken und den Knopf druecken
  kann, ist in dieser Runde nicht nachgemessen worden -- die Rechtecke
  stehen (`kind=2` sind die zwei Knoepfe), aber es hat niemand darauf
  geklickt.
* Gemessen wurde auf **einer IDE-Platte in QEMU**. NVMe, AHCI und echtes
  Blech sind nicht Teil dieser Runde.
* Der Lauf `zweiplatten.sh` (zwei Platten nebeneinander) ist **nicht**
  mitgelaufen.
* Das Kopieren der Wurzel dauert auf diesem Wirt rund **acht Minuten**
  (32768 Sektoren oktettweise durch den FAT32-Schreiber). Das ist langsam
  und war nicht Gegenstand dieser Runde.
