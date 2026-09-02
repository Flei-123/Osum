# Einen Treiber zu Osum hinzufügen

Stand: Runde STRUKTUR. Diese Datei beschreibt den **heutigen** Baum, nicht
die Absicht. Jede Zeile Beispielcode darin ist aus einem Treiber
abgeschrieben, der im Repo liegt und läuft.

---

## 1. Wo die Treiber liegen

```
kernel/                     DER KERN. Speicher, Fäden, Zeit, Systemaufrufe,
                            Dateisysteme, Netzstapel, Fensterserver.
                            Kennt KEINEN Treiber beim Namen — nur die
                            Schnittstellendateien unten.
kernel/drivers/
  bus/    pci.fi acpi.fi         der Bus. Hier entsteht jede Treiberwahl.
  net/    netdev.fi              SCHNITTSTELLE: Tabelle PCI-Nummer → Treiber
          virtio.fi e1000.fi     je Chip eine Datei
  blk/    blk.fi                 SCHNITTSTELLE: Gerätenummer → Treiber
          nvme.fi ahci.fi        je Chip eine Datei
  usb/    usb.fi                 SCHNITTSTELLE: der Kern über dem Regler
          xhci.fi                je Regler eine Datei
  input/  kbd.fi ps2m.fi         Tastatur, Zeigegerät
  gfx/    gfx.fi                 SCHNITTSTELLE (die Naht zur Grafik)
          gfx-aus.fi             ihre Leerfassung für `--gui off`
          fb.fi vmode.fi font.fi der Rahmenpuffer und die Bildmodi
  snd/    (leer)                 siehe Abschnitt 6
```

**Was ein Treiber ist**, und die Regel ist eng gemeint: *was mit dem Gerät
redet* — Register, Portadressen, Ringe, Unterbrechungen. `fb.fi` schreibt
in einen Rahmenpuffer und ist einer. `wm.fi` kennt keine einzige
Hardwareadresse, sondern Fenster, und ist keiner; er liegt weiter in
`kernel/`. Ebenso `ttf.fi` (ein Schriftrasterer), `tile.fi` (ein
Fensterbaum), `ansi.fi` (eine Terminalemulation). Ohne diese Grenze hieße
`drivers/` nach zwei Runden nur noch „alles, was mit Bildschirm zu tun
hat".

---

## 2. Wie `import` einen Treiber findet

Der Übersetzer sucht ein `import` in dieser Reihenfolge
(`compiler/src/modules.rs` im Firn-Repo):

1. **neben der importierenden Datei**
2. **neben der Wurzeldatei** — das ist `kernel/kmain.fi`, also `kernel/`
3. `$FIRNLIB`, dann `<firnc>/../lib`

Drei Folgerungen, die man beim Schreiben eines Treibers braucht:

* Ein Treiber erreicht den Kern **unverändert**: `import kstate`,
  `import serial`, `import mem` funktionieren aus jedem Unterverzeichnis,
  weil Regel 2 greift.
* Treiber **derselben Klasse** erreichen einander mit dem nackten Namen:
  `netdev.fi` schreibt `import virtio`, weil beide in `drivers/net/` liegen.
* Von **außerhalb** der Klasse braucht es den Pfad: `import drivers.net.netdev`.

**Der Modulname ist der Dateiname, nicht der Pfad.** Nach
`import drivers.blk.blk` heißt der Aufruf weiter `blk.read(state, ...)` —
ein Modul wird unter dem *letzten* Pfadteil angesprochen. Deshalb ändert
ein Umzug keine Aufrufstelle und kein Linkersymbol
(`_F0.virtio__tx_frame` bleibt, was es war).

> **Achtung, die eine Falle:** Dateinamen müssen im ganzen Kernbaum
> eindeutig bleiben. Zwei Dateien namens `net.fi` in verschiedenen
> Verzeichnissen ergäben zweimal das Modul `net` und damit doppelte
> Symbole.

---

## 3. Eine Netzkarte hinzufügen (der ausführliche Fall)

`kernel/drivers/net/netdev.fi` ist die Schnittstelle: eine Tabelle bildet
die PCI-Hersteller-/Gerätenummer auf einen Treiber ab, und jeder Treiber
liefert dieselben Namen. Vier Schritte.

### Schritt 1 — die Datei

`kernel/drivers/net/r8169.fi`. Der Kopf sagt, **welcher Chip** und **warum
er messbar ist** (steht er in QEMU? sonst ist keine Zusage prüfbar).

### Schritt 2 — die 24 Pflichtfunktionen

Jede trägt das Suffix `_on` und nimmt die Kartennummer *innerhalb dieses
Treibers* als zweites Argument. Abgeschrieben aus `virtio.fi`:

```firn
fn init_on(state: u64, c: u64, use_msix: bool, armed: bool) -> bool
fn present_on(state: u64, c: u64) -> bool
fn ready_on(state: u64, c: u64) -> bool
fn up_on(state: u64, c: u64) -> bool
fn bdf_on(state: u64, c: u64) -> u64
fn idx_on(state: u64, c: u64) -> u64
fn mac_at_on(state: u64, c: u64, i: u64) -> u64
fn link_up_on(state: u64, c: u64) -> bool
fn shut_down_on(state: u64, c: u64)

fn tx_frame_on(state: u64, c: u64, src: u64, n: u64) -> bool
fn tx_room_on(state: u64, c: u64) -> u64
fn rx_take_on(state: u64, c: u64, frame: *mut u64, slot: *mut u64) -> u64
fn rx_recycle_on(state: u64, c: u64, id: u64)

fn irq_on(state: u64, c: u64)
fn poll_on(state: u64, c: u64) -> bool

// Zähler — sie speisen `netmon`, `netview` und /proc:
fn irqs_on(state, c) -> u64          fn rx_frames_on(state, c) -> u64
fn tx_frames_on(state, c) -> u64     fn tx_drops_on(state, c) -> u64
fn rx_octets_on(state, c) -> u64     fn tx_octets_on(state, c) -> u64
fn features_on(state, c) -> u64      fn queue_size_on(state, c) -> u64
fn msix_on(state, c) -> bool         fn notified_on(state, c) -> u64
```

Dazu **`fn supports(dev: u64) -> bool`**, wenn der Treiber eine ganze
Familie trägt (`e1000.fi` macht das für die 8254x/82574-Reihe) — dann
steht die Geräteliste im Treiber und nicht in der Tabelle.

Und die Speichergrenze des Treibers als **`const MAX_UNITS`** bzw.
`MAX_CARDS`: `netdev.probe` fragt sie ab und nimmt keine Karte an, für
die der Treiber keinen Platz mehr hat. Die Grenzen heute:

| Grenze | Wert | woher |
|---|---|---|
| `netdev.MAX_CARDS` | 7 | so viele Vektoren gibt es (45 + 37–42) |
| `e1000.MAX_UNITS` | 6 | `(0x1000 − 0x400) / 0x200`, der Platz in der Seite |
| `virtio.MAX_CARDS` | 2 | Karte 1 liegt in `pci.K2_SCALARS+0x1600`, die Seite endet auf 0x2000 |

`init_on` bekommt den Vektor als **Argument** — er wird nicht im Treiber
ausgerechnet.

### Schritt 3 — Konstante und Tabelleneintrag

In `netdev.fi`:

```firn
import r8169                              // gleiches Verzeichnis, nackter Name

const KIND_R8169: u64 = 3                 // KIND_NONE=0, VIRTIO=1, E1000=2

// in fn probe(), im Zweig für Klasse 02:00:
if ven == r8169.VENDOR_REALTEK {
    if r8169.supports(dev) { k = KIND_R8169; unit = r8169_units }
}
```

…und derselbe `KIND_R8169`-Zweig in **jeder** Weiterleitung
(`init_on`, `tx_frame_on`, …) sowie in `print_kind`, damit die serielle
Leitung den Namen sagt statt einer Zahl.

### Schritt 4 — Speicher anmelden

Der Treiberzustand liegt in `kdata`, nicht auf dem Stapel. Trage dir ein
Stück ein und **melde es in `tools/kernel/memmap.py` an** — das Werkzeug
rechnet nach, dass sich nichts überschneidet. Das Netzstück liegt bei
`kstate.NETDEV_OFF` (0x7A000, eine Seite):

```
+0x000  netdev.fi: 0x40 je Karte (Treiberart, Einheit, PCI-Platz)
+0x300  netdev.fi: die Karten OHNE Treiber, mit ihren Nummern
+0x400  e1000.fi:  0x200 je Einheit
```

### Schritt 5 — die Unterbrechung

**Das ist die Stelle, an der es schiefgeht.** Ein Vektor ist nur
benutzbar, wenn `kernel/arch/x86_64/isr.s` einen Stummel dafür hat
(`isr_plain N`) *und* `trap.fi` einen Zweig. Vorhanden sind `isr0..isr47`;
ab 48 stehen in der Tabelle `vectors` andere Einträge
(`syscall_entry`, `user_entry`, …) — **48 aufwärts ist kein freier
IRQ-Vektor.**

Belegung in 32..47 (Stand Runde STRUKTUR):

| Vektor | wofür |
|---|---|
| 32 | Zeitgeber |
| 33 | Tastatur (GSI 1) |
| 34, 35 | **frei** |
| 36 | seriell COM1/COM2 (GSI 4/3) |
| 37–42 | Netzkarten 1–6 (`VEC_NET_MORE`) |
| 43 | xHCI |
| 44 | NVMe |
| 45 | Netzkarte 0 (`VEC_NET`) |
| 46 | PS/2-Maus (GSI 12) |
| 47 | spurious |

Wer einen Vektor nimmt, trägt ihn als **`const VEC_…`** ein — dann findet
`tools/kernel/memmap.py` eine Kollision. Wer einen *Block* nimmt, trägt
ihn zusätzlich in `BEREICHS_VEKTOREN` in memmap.py ein.

> **Warum das wichtig ist, mit einem echten Fall.** Bis Runde STRUKTUR
> bekam die zweite Netzkarte `VEC_NET + 1`. Das ist 46 — der Vektor der
> PS/2-Maus. Weil der Mauszweig in `trap.fi` vor dem Netzzweig steht, hat
> die zweite Karte nie eine Unterbrechung gesehen. Der Kartenprüfer hat
> geschwiegen, weil er `const VEC_*` liest und `VEC_NET + 1` eine
> *Rechnung* ist. **Rechne einen Vektor nicht aus — vergib ihn.** Seit
> dieser Runde tut das `netdev.vec_of(c)` an einer Stelle, und die
> Treiber bekommen ihn als Argument.

---

## 4. Eine Platte hinzufügen

`kernel/drivers/blk/blk.fi` ist die Schnittstelle. Sie ist **noch keine
Tabelle wie `netdev`**, sondern eine Kette von `if dev == DEV_x` in
`read_on`, `write_on`, `blocks_on`, `present_on` — das ist der offene
Punkt dieser Klasse (Abschnitt 7).

Ein Blocktreiber liefert:

```firn
fn present(state: u64) -> bool          // ist der Regler da?
fn init(state: u64) -> bool             // hochziehen
fn ready(state: u64) -> bool
fn identify(state: u64) -> bool         // Größe/Blockformat erfragen
fn blocks(state: u64) -> u64            // wie viele 512er-Blöcke
fn read_block(state: u64, lba: u64, dst: u64) -> bool
fn write_block(state: u64, lba: u64, src: u64) -> bool
fn flush(state: u64) -> bool
```

`read_many`/`write_many` sind freiwillig und lohnen (AHCI und NVMe haben
sie). Dann in `blk.fi`: eine `const DEV_x`, ein Zweig in den vier
`*_on`-Funktionen, ein `use_x` — und **kein einziges Wort in `fs.fi` oder
`fat.fi`**. Dass das viermal in Folge gehalten hat (NVMe, ATA1, USB,
AHCI), ist die Zusage dieser Schnittstelle.

**Welches Gerät die Wurzel trägt**, entscheidet seit Runde BLECH
`kernel/rootsel.fi` (Reihenfolge NVMe → AHCI → USB → IDE, und es gewinnt
der erste, dessen Wurzel sich wirklich einhängen lässt) — nicht mehr die
Kommandozeile. Ein neuer Blocktreiber will dort einen Bewerbereintrag.

---

## 5. Eingabe, Grafik, Bus

* **input/** — `kbd.fi` und `ps2m.fi` haben *keine* gemeinsame
  Schnittstellendatei; beide werden direkt gerufen. Für ein zweites
  Zeigegerät (I2C-HID, USB-HID) wäre eine `input.fi` nach dem Muster von
  `netdev.fi` der richtige Schritt — auf dem Zweig `hid` liegt die Arbeit
  dafür schon (`hidrep.fi`, `hidin.fi`, `i2chid.fi`).
* **gfx/** — `gfx.fi` ist eine echte Naht mit 37 Symbolen und einer
  Leerfassung `gfx-aus.fi`. Beim Bau mit `--gui off` werden die
  Grafikdateien nicht übersetzt und `gfx-aus.fi` tritt an die Stelle von
  `gfx.fi`; die Liste steht in `tools/build-kernel.sh`. **Wer eine Datei
  zu `drivers/gfx/` hinzufügt, trägt sie dort ein** — sonst zieht der
  Serverbau Grafik ins Abbild, die nicht hineingehört.
* **bus/** — `pci.fi` füllt die Gerätetafel, aus der jede Treiberwahl
  liest. `acpi.fi` liefert die Firmware-Tafeln (MADT, Akku, Thermalzone).

---

## 6. Eine neue Klasse anfangen (`snd/`)

`kernel/drivers/snd/` ist **leer und mit Absicht angelegt**. Ein
AC97-Treiber (`ac97.fi`, 841 Zeilen) und eine Tonschicht (`audio.fi`)
existieren, liegen aber auf den Zweigen `media1`/`hda` und sind nicht in
`main`. Wer sie hereinholt, legt sie hierher und schreibt eine
`snd.fi`-Naht nach dem Muster von `netdev.fi`, bevor der zweite Treiber
(HDA) dazukommt — nicht danach.

---

## 7. Was an dieser Struktur noch offen ist

Ehrlich aufgeführt, damit niemand es für fertig hält:

1. **`blk.fi` ist keine Tabelle.** `read_on`/`write_on`/`blocks_on`/
   `present_on` sind vier parallele `if`-Ketten über `DEV_*`. Ein fünfter
   Treiber heißt: vier Ketten anfassen. `netdev` löst dasselbe Problem
   mit *einer* Tabelle und einheitlichen Namen; `blk` sollte
   nachziehen. Die automatische **Erkennung** fehlt nicht mehr — die
   macht `rootsel.fi` seit Runde BLECH.
2. **`input/` hat keine Naht** (siehe Abschnitt 5).
3. **`serial.fi` ist ein Treiber und liegt trotzdem in `kernel/`.** Ein
   16550-UART gehört nach `drivers/char/`. Er ist es nicht geworden, weil
   55 Dateien ihn importieren und er die Ausgabe des Kerns selbst ist —
   das ist ein eigener Schritt und keine Nebenbemerkung.
4. **`batt.fi`, `pwr.fi`** sprechen ACPI und MSRs an, sind also Treiber,
   und liegen noch flach. Eine Klasse `drivers/pwr/` wäre folgerichtig.
5. **`netdev.probe` ist ein `if`-Baum, keine Datentabelle.** Für zwei
   Treiber ist das lesbar; ab vier gehört die Zuordnung in ein Feld aus
   `(Hersteller, Gerät, KIND)`.

---

## 8. Die drei Proben, bevor etwas eingecheckt wird

```sh
./tools/build-kernel.sh /tmp/k.bin                 # baut es?
./tools/build-kernel.sh /tmp/k-off.bin --gui off   # auch ohne Grafik?
python3 tools/kernel/memmap.py                     # überschneidet sich nichts?
./test.sh                                          # die volle Abnahme
```

Ein neuer Treiber ohne einen Läufer unter `tools/`, der ihn **an einem
emulierten Gerät misst**, ist keine Zusage, sondern eine Behauptung. Wenn
QEMU den Chip nicht kennt, ist er in dieser Runde nicht messbar — dann
gehört genau dieser Satz in den Rundenbericht (Runde HWNET hat aus dem
Grund den Realtek nicht gebaut, Runde BLECH aus dem Grund kein igc/igb).
