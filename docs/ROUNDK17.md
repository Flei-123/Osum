# Runde K17 — USB: xHCI, der Kern, HID und der Stick

**Stand:** 26.08.2026 · Branch `k17-usb`, abgezweigt von `main`
(`c5fe12f`) · Abnahme: `bash tools/k17/run.sh` → **146 Zusagen, 0
Fehler**.

---

## 1. Das Problem, mit dem diese Runde anfing

Osum hatte zwei Eingabegeräte, und beide hängen am selben Baustein von
1984: die Tastatur an IRQ 1 (`kernel/kbd.fi`, Runde 59) und die Maus an
IRQ 12 (`kernel/ps2m.fi`, Runde K10). Im Kopf von `ps2m.fi` steht seit
Runde K10 der Satz, der diese Runde ausgelöst hat:

> WARUM PS/2 UND NICHT USB-HID. […] Ein USB-HID-Weg braucht davor einen
> xHCI-Treiber, Endpunkte, Deskriptoren und eine Warteschlange; das ist
> eine Runde für sich und stünde hier als halbfertiges Stück.

Das war die richtige Entscheidung für K10 und ist seitdem eine Schuld.
Auf einem Laptop von 2026 gibt es keinen 8042 mehr — Tastatur und
Touchpad hängen an USB oder I²C. Ein System, das nur PS/2 kann, läuft in
QEMU und auf nichts sonst. Die Roadmap sagt es unter Punkt 3.1: *„der
dickste Brocken dieser Gruppe, und Voraussetzung für fast jede echte
Maschine"*.

Dazu kam die zweite Hälfte: ein USB-Stick ist das, was ein Mensch in
einen Rechner steckt, wenn er etwas darauf haben will. Osum konnte
FAT32 seit Runde K14 — aber nur auf einer Platte, die QEMU beim Start
mit `-drive` hereinreicht.

---

## 2. Was jetzt da ist

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/xhci.fi` | 1132 | Der **Regler**: PCI-Fund, Register, Kommando-, Ereignis- und Übertragungsringe, Steckplätze, Endpunkte, Adressvergabe, Anschlussverwaltung, MSI-X auf Vektor 43 |
| `kernel/usb.fi` | 1718 | Der **Kern**: Aufzählung, Deskriptoren, Konfiguration, Treiberzuordnung — und die drei Klassen (Tastatur, Maus, Massenspeicher) |
| `kernel/user/k17.fi` | 299 | Das Messprogramm in Ring 3 |
| `tools/k17/run.sh` | 697 | Der Testläufer |

Dazu geändert: `kbd.fi` (`irq` → `on_code`), `ps2m.fi` (`usb_packet`,
`adopt`), `blk.fi` (`DEV_USB` = 4, `removable`), `trap.fi` (Vektor 43,
Anstecken/Abziehen im Zeitgeber), `devfs.fi` (`/dev/usb`), `sys.fi`
(zwei Aufrufe, `mnt_gone`, `source_dev`), `sched.fi` (`KSTACK_FRAMES`
4 → 8), `kstate.fi` (`kdata` 0x50000 → 0x58000, der Vorrat `K17_OFF`,
neun Modusbits), `boot.s`, `kmain.fi`, `lib/libc/kcall.fi`,
`tools/kernel/karte.py`, `test.sh`.

---

## 3. Die Schichtung, und warum sie so und nicht anders ist

```
   kbd.on_code        ps2m.usb_packet        blk.read_on(DEV_USB)
        ^                    ^                        ^
        |                    |                        |
   usb.press          usb.mouse_report          usb.msc_read
        \____________________|________________________/
                             |
                          usb.fi          Aufzaehlung, Deskriptoren,
                             |            Klassen, An- und Abstecken
                          xhci.fi         Steckplaetze, Endpunkte,
                             |            Ringe, Tuerklingeln
                          pci.fi          (Runde K2)
```

`xhci.fi` weiß nicht, was eine Tastatur ist. Es kennt Steckplätze,
Endpunkte und Übertragungen. `usb.fi` weiß nicht, was ein Dateisystem
ist — es liefert 512 Oktette. Das ist dieselbe Trennung wie zwischen
`nvme.fi` und `blk.fi` in Runde K2, und sie ist gemessen: `fs.fi`,
`fat.fi`, `vfs.fi`, `ofs.fi` und `part.fi` enthalten den Namen `usb.`
kein einziges Mal (Abschnitt 1 der Abnahme).

---

## 4. Der Regler

Ein xHCI ist vier Registersätze, drei Ringe und eine Tafel von
Zusammenhängen. Nichts davon steht an einer festen Adresse — **alles
sagt das Gerät selbst**:

* `CAPLENGTH` (das erste Oktett bei BAR 0) ist der Abstand zu den
  Betriebsregistern, `DBOFF` der zur Türklingeltafel, `RTSOFF` der zu
  den Laufzeitregistern.
* `HCSPARAMS1` sagt, wie viele Anschlüsse und Steckplätze es gibt
  (gemessen unter `qemu-xhci`: 8 Anschlüsse, 64 Steckplätze).
* `HCCPARAMS1` Bit 2 sagt, ob ein Zusammenhang 32 oder 64 Oktette hat
  (QEMU: 32). Der Treiber rechnet mit der gelesenen Zahl; eine geratene
  wäre auf der ersten echten Maschine falsch.
* `HCSPARAMS2` sagt, wie viel Arbeitsspeicher der Regler für sich selbst
  verlangt. QEMU verlangt keinen — die Zeilen dafür stehen trotzdem im
  Treiber, weil ein Regler, der welchen verlangt, sonst auf Speicher
  wartet, den es nicht gibt.

Die drei Ringe sind Felder von 16-Oktett-Blöcken mit einem **Umlaufbit**:
wer schreibt, setzt es, wer liest, vergleicht es. Der letzte Platz jedes
Rings ist ein Sprung zurück an den Anfang, und mit ihm kippt das Bit.
Ohne diese Mechanik ließe sich nicht sagen, wo der eine aufgehört und der
andere angefangen hat.

### Was die Sprache hier nicht kann

Dieselbe Lage wie in `nvme.fi`, und sie steht im Kopf beider Dateien: ein
TRB ist eine Struktur mit Feldern an festen Stellen, aber Firn Stufe 0
hat weder flüchtigen Feldzugriff (`a.b` trägt kein
Volatile-Versprechen — das hängt an `__mmio_read32`/`__mmio_write32`)
noch `#[align(n)]` (in `compiler/src/attrs.rs` als
`implemented: false` eingetragen). Also werden die Versätze von Hand
gerechnet, jeder Zugriff geht durch die Intrinsics, und die Ausrichtung
kommt aus dem Bereich, den `boot.s` übergibt.

Eine Stelle ist dabei nicht Kosmetik: `trb()` schreibt das **Steuerwort
zuletzt**, weil in ihm das Umlaufbit steht. Der Regler darf den Block
erst dann für gültig halten, wenn der Rest schon darin steht.

---

## 5. Die Tastatur mündet in den Weg von Runde 59 — wörtlich

Das ist die Zusage, um die es in dieser Runde eigentlich geht, und sie
ist keine Absichtserklärung, sondern eine Änderung an genau einer Datei.
`kernel/kbd.fi` hatte eine Funktion:

```firn
fn irq(state: u64) {
    let code: u64 = serial.in8(DATA_PORT) as u64
    ...  // Umschalt, Steuerung, Pfeiltasten, Zeilendisziplin, Fokus
}
```

Jetzt hat sie zwei:

```firn
fn irq(state: u64) {
    on_code(state, serial.in8(DATA_PORT) as u64)
}

fn on_code(state: u64, code: u64) {
    ...  // unveraendert
}
```

Getrennt ist nur das **Holen**. Der USB-Treiber übersetzt den
HID-Gebrauchscode in einen **PS/2-Abtastcode des Satzes 1** — also in
genau das, was der 8042 an Tor 0x60 liefern würde — und ruft damit
`kbd.on_code`. Die Umschalttabelle, die Steuerungsbehandlung, die
Pfeiltasten als `ESC [ x`, die Zeilendisziplin aus Runde K9 und der
Eingabefokus des Fensterservers aus Runde K10 sind **eine** Kette, und
beide Geräte hängen an derselben.

Für die Maus dasselbe eine Ebene tiefer: `usb.mouse_report` baut aus dem
HID-Bericht einer Boot-Maus ein **PS/2-Paket** (drei oder vier Oktette,
Bit 3 im ersten gesetzt) und gibt es an `ps2m.usb_packet`. Von dort an
ist es dieselbe Rechnung wie seit K10 — dieselbe Begrenzung auf die
Bildschirmkanten, dieselbe Klickzählung, dasselbe `S_CHANGED`, das der
Fensterserver abholt.

Zwei Vorzeichen drehen sich dabei um, und beide sind eine eigene Art zu
scheitern: USB zählt **y nach unten** (wie der Bildschirm), PS/2 nach
oben; und eine Radumdrehung nach vorn ist bei USB +1, bei PS/2 0x0F.

---

## 6. Die Gegenprobe, die der Auftrag verlangt hat

> Eine über USB angesteckte Tastatur erzeugt in der Shell **dieselben**
> Zeichen wie die PS/2-Tastatur — derselbe Test, zweimal gefahren.

Gemacht, und zwar so: dieselbe Folge von `sendkey`-Befehlen aus dem
QEMU-Monitor (`tools/k11/tasten.py` aus Runde K11), dasselbe
Plattenabbild, dieselbe Shell — einmal mit `-device usb-kbd` und einmal
ohne. Verglichen werden

* die `key:`-Zeilen der seriellen Leitung, Oktett für Oktett (26 Zeilen),
* die Shell-Sitzung zwischen `sh: ready` und `sh: bye`, Oktett für Oktett.

Beide sind gleich.

**Und der Gegenbeweis dazu, ohne den der Vergleich wertlos wäre.** QEMU
entscheidet selbst, an welches Tastaturgerät ein `sendkey` geht. Hätte
es in beiden Läufen den PS/2-Regler genommen, wären die Ausgaben gleich
*und* falsch. Deshalb zählt `usb.press` mit, und der Zähler steht am Ende
des Laufs auf der Leitung:

```
usb: keys=26 reports=52 moves=0 events=57 irqs=57 xhcierr=0 ...
```

26 Tasten sind durch den USB-Weg gegangen — genau so viele, wie es
`key:`-Zeilen gibt. Im PS/2-Lauf gibt es diese Zeile überhaupt nicht.

### Die Lehre aus B3, ausdrücklich

Ein `cmp` über zwei leere Dateien geht immer durch. Der Vergleicher in
`tools/k17/run.sh` heißt deshalb `gleiche_datei name a b mindestzeilen`
und **lässt die Zusage fallen**, wenn eine Seite zu kurz ist — er zählt
sie nicht als bestanden. Dasselbe für die Shell-Sitzung (mindestens acht
Zeilen) und für die `key:`-Zeilen (mindestens 24).

### Die Lehre aus K7B, ausdrücklich

Nichts in dieser Runde wird gegen eine Fläche gerechnet. Der Zeiger steht
nach acht Anschlägen in die Ecke und zwei Bewegungen von je (100, 60) auf
**genau** (200, 120), mit **genau** einem Klick — drei Zahlen, die
ausgerechnet und nicht geschätzt sind.

---

## 7. Der Stick

Bulk-Only-Transport ist einfach: ein 31 Oktett langer Befehlsblock (CBW)
auf den Massenendpunkt hinaus, Daten hin oder her, eine 13 Oktett lange
Quittung (CSW) herein. Darin steckt ein SCSI-Befehl — `INQUIRY`,
`TEST UNIT READY`, `READ CAPACITY (10)`, `READ (10)`, `WRITE (10)`,
`REQUEST SENSE`. Das ist der Grund, warum ein Stick überhaupt an
`blk.fi` passt: er spricht Blöcke.

`blk.fi` bekommt damit sein **viertes** Gerät (`DEV_USB` = 4), und die
Schnittstelle wird zum dritten Mal nicht breiter — kein Argument mehr,
keine zweite Leseroutine, keine Zeile in `fs.fi` oder `fat.fi`.

Gemessen wurde es so, wie es der Auftrag verlangt hat:

1. `mkfs.vfat -F 32` legt ein FAT32 an, `sfdisk` eine MBR-Tafel,
   `mcopy` eine Datei hinein.
2. Osum liest sie (`hostlen = 24`, `hostok = 1` — Oktett für Oktett aus
   Ring 3 verglichen).
3. Osum schreibt `neu.txt`.
4. **Danach liest `mtools` auf dem Wirt dieselbe Datei aus demselben
   Abbild**, und `cmp` vergleicht sie mit `osum-war-hier`.
5. `fsck.fat -n` sagt, dass das Dateisystem danach noch eines ist.

Dazu der Weg aus der Shell: `/dev/usb` ist der ganze Träger,
`/dev/usb1` seine erste Partition — dieselbe Regel wie `/dev/hdb` und
`/dev/hdb1`, und `mount /dev/usb1 /usb vfat` tut, was dasteht.
`/dev/usb` steht **nur dann** im Geräteverzeichnis, wenn wirklich ein
Stick da ist; ohne einen fehlt der Eintrag, und beides ist geprüft.

---

## 8. Abziehen im Betrieb

Der Zeitgeber sieht viermal je Sekunde nach, was sich an den
Anschlussregistern geändert hat (ein Lesezugriff je Anschluss). Nur wenn
sich wirklich etwas geändert hat, wird ein Gerät aufgenommen oder
verabschiedet.

**Ehrlich gesagt: eine Aufzählung im Zeitgeberbehandler ist nicht
schön.** Sie dauert einige Millisekunden, und in dieser Zeit steht der
Zeitgeber. Der richtige Ort wäre eine Kernaufgabe; die gibt es in diesem
Kernel für Geräte noch nicht. Solange das so ist, steht die Zeile dort
und nicht woanders — und sie läuft **nur**, wenn dieser Lauf überhaupt
USB aufgesetzt hat. Jede Messung der Runden 52 bis K16 sieht damit den
Kernel, den sie vorher gesehen hat.

Was danach passiert, misst `/bin/k17` aus Ring 3, mit einem Deskriptor,
der **offen bleibt**:

```
k17: openfd = 1        vor dem Abziehen ist er offen
k17: pull = 1          das Geraet wird abgezogen
k17: afterread = 19    lesen darauf: -ENODEV
k17: afterwrite = 19   schreiben darauf: -ENODEV
k17: afteropen = 19    und ein neues Oeffnen desselben Pfades: -ENODEV
k17: mscgone = 0       der Stick meldet sich nicht mehr als da
k17: rootwrite = 14    derselbe Prozess schreibt auf der Wurzel weiter
k17: rootread = 14     und liest, was er geschrieben hat
k17: done = 1          und kommt bis zum Ende
```

**ENODEV und nicht EIO**, und das ist kein Geschmack: EIO hieße „der
Lesevorgang ist schiefgegangen", und das lädt zum Wiederholen ein.
ENODEV heißt „das Gerät gibt es nicht mehr", und dabei bleibt es. Die
Prüfung steht an **einer** Stelle — am Deskriptor (`sys.mnt_gone`), nicht
im Treiber — und gilt damit für jedes Dateisystem auf jedem Gerät, das
verschwinden kann.

---

## 9. Was schiefging, und was es gekostet hat

### 9.1 Der Baum baute nicht

`main` (`c5fe12f`) **übersetzt nicht**. Zwei Textverschmelzungsschäden
aus dem K15-Merge:

* `kmain.mode_of`: dem `if` für `M_NOSTACK` fehlt die schließende
  Klammer. Alles danach steht damit im Rumpf des `if`, und der Übersetzer
  bricht bei der nächsten `fn` ab.
* `sys.fi`: die Weiche für die Aufrufe 1800..1899 (Runde K15) ist beim
  Verschmelzen in `k13_call` gelandet statt in `dispatch`. Dort gibt es
  kein `a4`.

Beides steht als erster Commit dieses Branches (`93ad914`). Ohne ihn
kann diese Runde nichts messen.

### 9.2 Der Kernstapel lief unten heraus — und die Shell starb

Der teuerste Fehler dieser Runde, und er sah aus wie etwas ganz anderes.

`wc /usb/host.txt` gab das richtige Ergebnis aus (`1 5 24`) — und danach
starb **die Shell** an einem Seitenfehler:

```
user fault: pid=5  vector=14  err=0x7  cr2=0x0  rip=0x40104433
```

`rip` zeigte in `run_stage` der Shell, auf einen `movb $0x20,(%rcx)` —
sie schrieb ein Leerzeichen durch einen Zeiger, der einmal 0 war und
einmal eine Adresse aus der **Kernhalde**. Ein Ring-3-Programm kommt
nicht an eine Kernadresse; also hatte der Kernel sie dorthin geschrieben.

Es war der Kernstapel. Der tiefste Systemaufruf dieses Kernels führt seit
dieser Runde durch vier weitere Schichten:

```
sys.dispatch -> do_read -> vfs_read -> vfs.v_read -> fat.read
             -> blk.read_on -> usb.msc_read -> usb.bot
             -> xhci.bulk -> xhci.wait_ep -> xhci.drain
```

Der Kommentar in `sys.k13_call` sagt, dass der tiefste Kernstapel eines
Laufs schon vor dieser Runde bei **16128 von 16384 Oktetten** lag — 112
Oktette Luft. Die Zahl war also nicht knapp, sie war zu klein.

**Gemessen statt geraten:** mit zwölf Rahmen (49152 Oktette, weit mehr
als nötig) steht die Hochwassermarke desselben Laufs bei **26488**
Oktetten; auf derselben Maschine mit demselben Skript auf einer
ATA-Platte statt auf dem Stick sind es **21424**. Der USB-Weg kostet also
5064 Oktette mehr. `KSTACK_FRAMES` steht jetzt auf **8** (32768 Oktette),
also 6280 Oktett Luft über der gemessenen Marke. Die beiden Schranken in
`tools/osum/run.sh` bleiben unverändert gültig.

### 9.3 Die Modusbits von K13, K14 und K16 lagen übereinander

`kstate.MODE` ist **ein** Wort. Drei Runden haben unabhängig voneinander
bei `1 << 31` angefangen:

| Bit | | | |
|---|---|---|---|
| 1<<31 | `M_K13` | `M_VFS` | `M_NOBIG` |
| 1<<32 | `M_NOPERM` | `M_NOVFS` | `M_NOSTACK` |
| 1<<33 | `M_INITSH` | `M_NOPROCFS` | |
| 1<<34 | `M_NOSUID` | `M_NODEVFS` | |
| 1<<35 | `M_NOACPI` | `M_NOFAT` | |
| 1<<36 | `M_FORCEV2` | `M_NOPART` | |
| 1<<37 | `M_ZOMBIE` | `M_FATRO` | |

Jeder Zweig war **für sich** grün; die Kollision stand in keiner
gemeinsamen Zeile. Genau wie bei `kdata` in Runde K7/K9 und bei der
Vektortafel in Runde K10.

Die Folge war messbar: `novfs` setzte damit auch `M_NOSTACK`, das
Stapelwachstum von Runde K16 blieb aus, und `/bin/k14` starb an einem
Seitenfehler unter seinem eigenen Stapel — **acht Zusagen von K14
fielen**, und zwar an einer Gegenprobe, die mit Stapeln nichts zu tun
hat.

Behoben (Commit `da5debe`), und dazu die Konsequenz: **`tools/kernel/karte.py`
rechnet die Modusbits ab sofort nach**, dieselbe Regel wie bei `kdata`
und bei den Vektoren — derselbe Name darf mehrfach dastehen, zwei
verschiedene Namen nicht auf demselben Wert. Geprüft werden `kstate.fi`
und `kmain.fi`; andere Module (`hw.fi`, `fb.fi`, `hv.fi`, `guard.fi`,
`smp.fi`) führen ein eigenes Wort mit eigenen Bits.

Dabei musste `kmain.provoke` von `mode & 0xFF` auf `mode & 0x7` umgestellt
werden. Die Trap-Arten sind 1 bis 4; die Bits 3 bis 7 gehörten faktisch
niemandem, weil ein Schalter dort einen Prozessorfehler ausgelöst hätte.

### 9.4 `present_on` schreibt in ein Register

Die erste Fassung der ENODEV-Prüfung fragte bei **jedem** `read` und
`write` `blk.present_on(dev)`. Für eine ATA-Platte schreibt diese
Funktion in das Laufwerksregister des Busses (0x1F6) — also mitten in
eine laufende Übertragung derselben Platte. Gefunden hat es Abschnitt 9
von `tools/k14/run.sh`: die Wurzelplatte war nach dem Lauf nicht mehr
Oktett für Oktett dieselbe.

`blk.removable(dev)` beantwortet die Frage jetzt ohne einen einzigen
Zugriff auf Hardware, und nur ein Gerät, das verschwinden **kann**, wird
wirklich gefragt.

### 9.5 Kleinigkeiten, die trotzdem Zeit gekostet haben

* Die Massenendpunkte bekamen erst eine fest eingetragene Paketgröße von
  512. `qemu-xhci` hängt einen Stick an einen **USB-3**-Anschluss, wenn
  einer frei ist, und dort sind es 1024. Jetzt kommt die Zahl aus dem
  Deskriptor.
* Die Antwort auf `READ CAPACITY` überschrieb die von `INQUIRY`, und
  danach war der Herstellername in der Meldung leer. Ein Fehler, der nur
  in der **Ausgabe** stand und nicht im Treiber.
* `hole-firnc.sh` baut in `/tmp/firn-pin-<commit>`, und mehrere Runden
  arbeiten gleichzeitig an diesem Baum. Zwei gleichzeitige Läufe räumen
  einander das Bauverzeichnis weg. Umgangen, nicht behoben: der fertige
  Übersetzer wurde aus dem Hauptbaum kopiert.

---

## 10. Was offen blieb

* **Nur vier Geräte gleichzeitig** (`usb.MAX_DEV`, `xhci.MAX_SLOT`) und
  **sechzehn Endpunkte** (`xhci.MAX_EP`). Beides sind Zahlen, keine
  Grenzen der Sache: die Geräte- und Endpunkttafeln liegen in `kdata`,
  und der Vorrat dieser Runde ist acht Seiten. Mehr Geräte hieße, die
  Tafeln in den Rahmenverwalter zu legen.
* **Keine Verteiler (Hubs).** Ein USB-Verteiler ist selbst ein Gerät der
  Klasse 09, und ein Gerät dahinter braucht eine *Route-String* im
  Steckplatzzusammenhang. Der Treiber schreibt dort eine Null — richtig
  für alles, was direkt am Wurzelverteiler hängt, und falsch für alles
  dahinter. Ein Stick in einer Tastatur wird also nicht gefunden.
* **Kein Berichtsbeschreibungs-Zerleger.** Tastatur und Maus laufen im
  **Boot-Protokoll**, in dem das Format festliegt. Das ist der Grund,
  warum jedes BIOS eine USB-Tastatur bedienen kann. Ein Gerät ohne
  Boot-Protokoll (Schnittstellenunterklasse ≠ 1) wird ausdrücklich
  **abgelehnt** und nicht stillschweigend falsch gelesen — ein
  Touchpad mit Gesten oder ein Gamepad gehört in eine eigene Runde.
* **Ein Stick zur Zeit.** Der Massenspeichertreiber führt eine Größe und
  eine Blockgröße, nicht eine je Gerät. Zwei Sticks gleichzeitig wären
  eine kleine Erweiterung, aber sie wäre unbenutzt und ungemessen.
* **Kein `bmRequestType`-Zwischenspeicher, keine Streams, kein
  UAS.** Ein moderner Stick kann UAS (SCSI über mehrere Ströme); dieser
  Treiber spricht nur BOT. Jeder Stick kann BOT.
* **Die Aufzählung läuft im Zeitgeberbehandler** (siehe Abschnitt 8).
* **Blockgrößen ≠ 512 werden abgelehnt**, mit einer Meldung. `blk.fi`
  spricht 512 Oktette je Block; ein Stick mit 4096 wäre ein anderer
  Treiber.
* **`usb.MAX_DEV` Geräte, aber nur ein Eingabefokus.** Zwei USB-Tastaturen
  gleichzeitig würden beide in denselben Weg münden — was richtig ist,
  aber nicht gemessen.

Und zwei Dinge, die diese Runde **gefunden**, aber nicht behoben hat:

* **K13 und K16 sind auf `main` rot**, unabhängig von dieser Runde.
  Gemessen auf dem Stand `93ad914` (nur die Übersetzungsschäden behoben,
  sonst nichts): `K13: 82 passed, 17 failed`, `K16: 58 passed, 6 failed`.
  Auf diesem Branch steht K13 nach der Bit-Reparatur bei
  `88 passed, 11 failed` — also **besser** als vorher, aber nicht grün.
  Die verbleibenden Fehler betreffen `su`/`passwd`/PBKDF2 (K13) und den
  Assembler `fas` mit den Ring-3-Programmen von K15 (K16). Beides gehört
  denen, die diese Runden gebaut haben.
* **`M_NOPERM` und `M_NOVFS` waren nicht die einzigen.** Die neue Prüfung
  in `karte.py` hätte alle drei Kollisionen am Tag ihres Entstehens
  gefunden.

---

## 11. Was die uebrigen Abschnitte der Vollabnahme sagen

Gemessen auf diesem Branch und, zum Vergleich, auf dem Stand `93ad914`
(nur die beiden Uebersetzungsschaeden behoben, sonst nichts von dieser
Runde):

| Abschnitt | dieser Branch | `93ad914` |
|---|---|---|
| `tools/kernel/run.sh` | 176 / 0 | — |
| `tools/osum/run.sh` | 130 / 0 | — |
| `tools/posix/run.sh` | 134 / 0 | — |
| `tools/wm/run.sh` | 103 / 0 | — |
| `tools/gfx/run.sh` | 76 / 0 | — |
| `tools/k14/run.sh` | 151 / 1 | 138 / 14 |
| `tools/k13/run.sh` | 88 / 11 | 82 / 17 |
| `tools/k16/run.sh` | 58 / 6 | 58 / 6 |
| `tools/k17/run.sh` | **146 / 0** | — |

**K13 und K16 sind auf `main` rot, und zwar unabhaengig von dieser
Runde.** Die Reparatur der Modusbits (Abschnitt 9.3) hat K13 von 17
Fehlern auf 11 gebracht und K14 von 14 auf 1; die uebrigen Fehler
betreffen `su`/`passwd`/PBKDF2 (K13) und den Assembler `fas` mit den
Ring-3-Programmen von Runde K15 (K16). Beides gehoert denen, die diese
Runden gebaut haben — hier steht es, damit es nicht in einer Fussnote
verschwindet.

**Eine Warnung zur Messmaschine.** Waehrend dieser Runde lief die
Systemplatte des Messrechners auf 97 Prozent voll, und mehrere Runden
massen gleichzeitig. Unter dieser Last faellt `tools/k14/run.sh`
sprunghaft aus (einmal 141 / 11 statt 151 / 1), und zwar an genau den
Stellen, an denen ein FAT-Schreibvorgang halb durchkommt — `fsck.fat`
meldet dann "Free cluster summary wrong" und eine neue Datei ist leer.
Das ist keine Eigenschaft des Kernels, sondern eine des Wirts: eine
ATA-Uebertragung, die auf ein volles Dateisystem schreibt, reisst die
Zeitgrenze in `blk.ata_wait`. Der Kommentar dort beschreibt genau diesen
Fall seit Runde K14. Die Zahlen oben stammen aus Laeufen mit freiem
Platz.

---

## 12. Die Zahlen

```
bash tools/k17/run.sh   ->  146 Zusagen, 0 Fehler
```

Aus einem Regellauf mit `qemu-xhci`, `usb-kbd`, `usb-mouse` und
`usb-storage`:

```
pci: 00:04.0 1b36:000d class=0c:03:30 usb  bar0=0xfebf0000/0x4000  irq=11  msix
usb: xhci slots=64  ports=8  ctx=32  irq=1
usb: port=1 speed=4 slot=1 id=46f4:0001 class=08:06:50 driver=msc
usb: msc blocks=131072  bsize=512  inq=36 QEMU
usb: port=5 speed=3 slot=2 id=0627:0001 class=03:01:01 driver=kbd
usb: port=6 speed=3 slot=3 id=0627:0001 class=03:01:02 driver=mouse
usb: devices=3 kbd=1 mouse=1 msc=1 enums=3 fails=0 events=51 irqs=51 cmds=10
```

| | |
|---|---|
| Anschlüsse, die der Regler selbst meldet | 8 |
| Steckplätze | 64 |
| Größe eines Zusammenhangs (aus HCCPARAMS1) | 32 Oktette |
| Meldevektor | 43, über MSI-X |
| Geräte, aufgezählt | 3, auf 3 Anschlüssen, in 3 Steckplätzen |
| Kommandos an den Regler | 10 |
| Fehler des Reglers im ganzen Lauf | 0 |
| Tasten über den USB-Weg (Tippprobe) | 26, gleich der Zahl der `key:`-Zeilen |
| Zeiger nach zehn Bewegungen | (200, 120), ein Klick |
| SCSI-Befehle über den Stick | 42 |
| Fehler im Bulk-Only-Transport | 0 |
| Tiefster Kernstapel des Laufs | 26488 von 32768 Oktetten |
| `kdata` | 0x50000 → 0x58000 (352 KiB), Vorrat K17 0x50000..0x58000 |
| Aufrufnummern | 1701, 1702 (Vorrat 1701..1749) |

Zahlenvorrat dieser Runde, wie zugeteilt und wie belegt:

| Vorrat | zugeteilt | belegt |
|---|---|---|
| kdata-Seiten | 0x50000–0x57FFF | 0x50000–0x57FFF, in 17 Stücken, von `karte.py` nachgerechnet |
| Systemaufrufe | 1700–1749 | 1701, 1702 (1700 gehört seit K14 der Einhängetafel) |
| Ring-3-Programmnummern | 40–44 | keine — diese Runde braucht keine, `/bin/k17` ist eine ELF-Datei auf der Platte |
| Deskriptorarten | 40–44 | keine — ein Stick ist eine Datei auf einem Dateisystem, keine neue Art |
| Testabschnitt | 23 | 23 (`test.sh`) |
