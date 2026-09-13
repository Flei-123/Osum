# Runde HOTPLUG — der Wechseldatenträger

Zweig `hotplug`, abgezweigt von `main` (ae381a3), Arbeitsbaum
`/root/os-hotplug`. Nicht gemergt.

Auftrag: Punkte **P-005** (kein Geräte-/Hotplug-Manager) und **P-006**
(kein Weg, einen USB-Stick zur Laufzeit einzubinden) der Offenliste,
beide Priorität 1.

---

## Zuerst: die Offenliste war veraltet

Der Auftrag sagte, es gebe „keinen Hotplug-Manager“ und „0 Treffer für
mount im Explorer“. Die Bestandsaufnahme hat etwas anderes ergeben, und
das gehört an den Anfang, weil es den Zuschnitt dieser Runde bestimmt:

| Was der Auftrag vermutete | Was wirklich dastand |
|---|---|
| kein Hotplug-Manager | `usb.port_watch` (im Zeitgeber) + `usb.hotplug_work` (in der Schreibtischschleife) seit Runde BLECHEINGABE — **fertig** |
| kein USB-Massenspeicher | `usb.fi`, 3456 Zeilen, volles Bulk-Only-Transport: CBW/CSW, INQUIRY, TEST UNIT READY, READ(10)/WRITE(10), STALL-Behandlung — **fertig** |
| keine Partitionserkennung | `part.fi`, MBR **und** GPT samt CRC-Prüfung — **fertig** |
| kein Einhängen | `vfs.mount_at` / `umount_index`, Einhängetafel `mnt.fi` mit `M_OPENS` — **fertig** |
| Explorer kennt keine Datenträger | `exporte.carrier_read()` liest sie **live** aus `SYS_MNTSTAT` — **fertig** |

**Die wirkliche Lücke war genau eine Stelle:** `kmain.usb_mount` hängte
den Stick **einmal beim Start** ein, und nur unter dem Kommandozeilenwort
`usbstick`. Ein Stick, der zur Laufzeit kam, wurde aufgezählt — und dann
vergessen. Es fehlte nicht der Treiber und nicht das Dateisystem,
sondern die **Naht dazwischen**.

---

## Was gebaut wurde

### `kernel/wechsel.fi` (neu, ~560 Zeilen)

Die Naht zwischen zwei Schichten, die einander nicht kennen dürfen:
`usb.fi` darf nichts von Dateisystemen wissen (Zusage der Runde K17,
gemessen in `tools/k17/run.sh` Abschnitt 1), `vfs.fi` nichts von USB.

* `kommt(dev)` — Partitionstafel lesen, Dateisystem **am Inhalt**
  erkennen, unter `/medien/usbN` einhängen, Ereignis auf den Systembus.
* `geht(dev)` — der Notfall. Räumt die Tafel, **ohne zu schreiben**.
* `auswerfen(i)` — der geordnete Weg. Schreibt zuerst, sagt E_BUSY, wenn
  noch etwas offen ist.
* Acht Plätze, jeder mit eigener Gerätenummer, eigenem Pfad, eigenem
  Dateisystemtyp.

### Die Flanken statt eines Rückrufs

`usb.fi` zählt zwei neue Zahlen: `S_MSCGEN` (+1, sobald ein
Massenspeicher **bereit** ist — nach INQUIRY und TEST UNIT READY, nicht
vorher) und `S_MSCWEG` (+1 in `gone`, also auch über die Gegenprobe
`unplug_now`). Wer sie liest, vergleicht sie mit seinem letzten Stand.

Ein Funktionszeiger aus `usb.fi` in die Schicht darüber wäre derselbe
Kreis im Modulgraphen, nur verschleiert. **Eine Zahl kennt niemanden.**

### Aufruf 1704 und `/bin/auswerfen`

Ein Feld je Aufruf, kein Zeiger in den Kern — dieselbe Bauart wie
`SYS_MNTSTAT` (1700). `WX_EJECT` gibt den **positiven** errno zurück,
damit die Oberfläche `E_BUSY` benennen kann statt nur „ging nicht“.

`auswerfen` ohne Argument zeigt, was steckt — samt der Zahl der offenen
Deskriptoren. Die Zahl, wegen der der Knopf gleich nein sagen wird,
gehört auf den Schirm, **bevor** jemand drückt.

### Der Knopf im Explorer

Neben „Aktualisieren“ und nicht in einem Menü: Auswerfen ist der einzige
Weg, einen Stick ohne Datenverlust loszuwerden, und einen Knopf, den man
suchen muss, drückt niemand — dann zieht der Mensch einfach. Vier
Antworten in der Statuszeile, `E_BUSY` mit eigenem Satz („noch etwas
geöffnet“), weil das keine Störung ist, sondern eine Bitte.

Oberfläche über `wlib`/fUi, `tools/check-ui.sh` bleibt grün.

---

## Datenverlust: zwei Wege hinaus, und sie sind verschieden

Das ist der Kern der Runde und der Grund, warum `geht` nicht über
`vfs.umount_index` läuft:

**Auswerfen** ist der geordnete Weg. `vfs.umount_index` ruft `fat.sync`
**vor** `fat.release` — aber nur, wenn die Prüfung auf offene
Deskriptoren (`mnt.opens != 0` → E_BUSY) vorher durchging. Ein
Auswerfen, das die Daten schreibt und dann E_BUSY meldet, hätte die
Datei eines anderen Prozesses halb geschrieben.

**Abziehen** ist der Notfall. Das Gerät ist schon weg; hier ist nichts
mehr zu retten und auch nichts mehr zu schreiben. **Wer jetzt noch
`fat.sync` riefe, schriebe in ein Loch.** Die Einhängung wird roh aus
der Tafel genommen. Ein Datenverlust ist das nicht — die Daten waren in
dem Augenblick verloren, in dem die Hand am Stecker zog. Was dieser
Zweig verhindert, ist der **zweite** Schaden: ein Kern, der auf ein
totes Gerät schreibt und dabei stirbt.

## Das Dateisystem wird am Inhalt erkannt, nicht am Typoktett

Das Typoktett einer MBR-Tafel (0x0B, 0x0C) ist eine **Behauptung** des
Formatierers. Sie stimmt meistens und ist deshalb gefährlich: wer ihr
glaubt, hängt irgendwann ein NTFS als FAT32 ein und schreibt in eine
Struktur, die er nicht versteht.

`fs_erkennen` liest den Bootsektor: Signatur 0x55AA, Oktette je Sektor
als Zweierpotenz zwischen 512 und 4096, „FAT32“ ab Oktett 82. Ein FAT16
(Kennung bei Oktett 54) wird **ausdrücklich abgelehnt** statt eingehängt
und beim ersten Verzeichnis fallengelassen.

---

## Die Abnahme

`bash tools/hotplug/run.sh` — **33 Zusagen, 0 rot.**

Gemessen wird mit `device_add usb-storage` / `device_del` über den
QEMU-Monitor: dieselbe Hardwareänderung, die eine Hand am Stecker macht.
`tools/k17/run.sh` misst einen Stick, der **beim Start schon steckt** —
das misst das Aufzählen, und beim Start ist das Dateisystem noch nicht da.

| Abschnitt | was |
|---|---|
| 2 | Anstecken im Betrieb: `wechsel: kommt … fs=4 mount=1`, `fat: spc=1 clusters=92726`, `hotplugs=1` |
| 3 | `ls` sieht die Datei des Wirts, `cat` liest sie, Osum schreibt eine eigene, `auswerfen` → rc=0 |
| 4 | Abziehen **ohne** Auswerfen: `wechsel: geht`, kein panic, kein EXCEPTION, Kern beendet sich mit 21 |
| 5 | zwei Sticks — die Grenze, ehrlich gemessen (siehe unten) |
| 6 | FAT16: aufgezählt, **nicht** eingehängt, kein Absturz |

**Die Zusage, auf die es ankommt, ist nicht „kein Fehler gemeldet“:**
nach dem Auswerfen liest **der Wirt** mit `mtools` nach — `osum.txt`,
14 Oktette, Inhalt `osum-war-hier`, und `fsck.fat` findet keinen Schaden.
Das ist Punkt 4 aus K17, auf das Auswerfen angewandt.

---

## Was dabei aufgefallen ist

Vier Befunde, die nur ein echter Lauf zutage fördert:

**1. `usb_hold` stand vor dem Dateisystem.** Der Haltepunkt der
Kernläufe lag in `usb_stage`, also vor `k14_setup`. Ein Stick, der
während des Haltens kam, konnte gar nicht eingehängt werden:
`vfs.ready` war noch falsch. Gemessen: `hotplugs=1 devices=1` (das
Gerät war da, 98304 Blöcke), und keine einzige `wechsel:`-Zeile.

**2. Zwei Warteschleifen arbeiteten nicht.** `usb_hold` rief
`hotplug_work` überhaupt nicht; `hold_a_moment` und die
`wighalt`-Schleife in `kgui.fi` warteten leer bzw. nur mit `wm.poll`.
`port_watch` legt den Anschlusswechsel im Zeitgeber ab, und niemand
holte ihn wieder: `events=1`, `hotplugs=0`, und zwei Bildschirmfotos,
die sich Oktett für Oktett glichen.

**3. `vfs.ready` ist im grafischen Lauf falsch.** Mit `wigfiles` hängt
der Fensterserver die Wurzel selbst über `fs.fi` ein (`wm: mount=1`),
und die VFS-Schicht darüber bleibt unberührt. Gemessen: `kgui: wechsel
gen=1 weg=1 vfs=0` — der Stick war da, die Flanke kam an, und es gab
keine Tafel, in die er gepasst hätte. `wechsel.kommt` zieht sie jetzt
nach.

**4. `/medien/usbN` muss es geben, bevor eingehängt wird.** `/medien`
legt `k14_setup` an (und `wechsel.kommt` notfalls selbst); den
Unterordner kann dort niemand anlegen, weil niemand weiß, wie viele
Sticks kommen.

### Ein bestehender Fehler, der nicht dieser Runde gehört

Der **Dateimanager stirbt** beim Aufbau der Seitenleiste, wenn das
Abbild die Orte unter `/data` nicht als Ordner trägt:

```
k15: start /bin/explorer  pid=2
user fault: pid=3  vector=14  err=0x5  cr2=0x0  -- process killed
```

Ein Lesezugriff auf Adresse 0, im Rückverfolger `ulib__strncpy`, gerufen
aus `exporte.entry` → `kuerzen`. **Die Gegenprobe mit dem unveränderten
`explorer.fi` aus `main` (ae381a3) stirbt genauso** — der Fehler ist
älter als diese Runde und wird hier nur benannt, nicht behoben.
`tools/k15/run.sh` fällt er nicht auf, weil es mit `tools/k15/tree.py`
einen vollständigen `/data`-Baum anlegt.

Wer das aufnimmt: `exporte.entry` kopiert den Pfad (`kuerzen` →
`strncpy`), **bevor** es mit `nurwenn_da` prüft, ob es ihn gibt; und
`trash.korb_von` liefert einen Pfad, dessen Wurzel es nicht geben muss.
Richtig wäre, den Zeiger auf 0 zu prüfen, bevor kopiert wird.

---

## Die Grenze, die bleibt: zwei Sticks

Zwei Sticks werden **beide aufgezählt** (`devices=2`, `hotplugs=2` — der
USB-Baum kann es), aber nur **einer** wird eingehängt.

Der Grund liegt unter dieser Runde: `usb.fi` hält den Massenspeicher in
**einer** Zelle (`S_MSC`), `usb.msc_read`/`msc_write` nehmen **keine**
Gerätenummer entgegen, und `blk.fi` hat genau ein `DEV_USB`. Der zweite
Stick wäre derselbe `DEV_USB` — die Naht lehnt ihn deshalb ausdrücklich
ab („dev schon in der Tafel“). Die Alternative wäre ein zweiter Eintrag,
der auf die Blöcke des **ersten** zeigt: eine Attrappe in der
Seitenleiste, die beim ersten Klick die falschen Daten zeigt.

**Lieber ein Träger weniger als ein falscher.**

Was fehlt, damit es geht: eine Gerätenummer je Massenspeicher in
`usb.fi` (`S_MSC` als Tafel statt als Zelle), `msc_read(state, dev, lba,
dst)` und `DEV_USB0..DEV_USBn` in `blk.fi`. Das ist eine eigene Runde
und berührt drei Schichten.

## Was sonst offen bleibt

* **Der Auswurfknopf ist nicht fotografiert.** Er ist gebaut, übersetzt
  und gelinkt (`check-ui.sh` grün), aber der Dateimanager startet in
  diesem Baum nicht bis zum Fenster (siehe der bestehende Fehler oben).
  Fotografiert ist stattdessen derselbe Weg eine Schicht tiefer und auf
  demselben Schreibtisch — siehe „Die Bilder“.
* **Kamera, Drucker, Monitorwechsel** (die anderen Nutzer von P-006)
  sind nicht angefasst. Der Gerätemanager trägt jetzt Massenspeicher;
  eine Kamera ist eine eigene Geräteklasse.
* **Das Ereignis auf dem Bus wird von niemandem abonniert.** Der Kern
  schickt es (`bus.noti_post`, sichtbar in der Leiste); der Explorer
  baut seine Seitenleiste noch beim Aktualisieren neu auf, statt auf die
  Meldung zu hören.

---

## Die Bilder

`bash tools/hotplug/bild-term.sh` — drei Bildschirmfotos aus **einer**
laufenden Maschine, `docs/shots/hotplug/`:

| Bild | was darauf steht |
|---|---|
| `10-vorher.png` | `auswerfen` → „kein Wechseldatenträger da“ |
| `20-steckt.png` | nach `device_add`: `ls /medien/usb0` zeigt `host.txt`, `auswerfen` zeigt die Tafel: `0  /medien/usb0  96256  0` |
| `30-danach.png` | nach `auswerfen 0`: „ausgeworfen: /medien/usb0“, danach wieder „kein Wechseldatenträger da“ |

Fotografiert wird ein **Terminalfenster auf dem Schreibtisch**
(`wmshell`) und nicht der Dateimanager — der stirbt in diesem Baum aus
einem Grund, der älter ist als diese Runde. Es ist derselbe Weg:
dasselbe `/bin/auswerfen`, derselbe Aufruf 1704, dieselbe Tafel des
Kerns, die auch die Seitenleiste liest.

**Der Unterschied ist die Zusage, nicht das einzelne Bild.** In Zahlen,
gemessen mit `pruef/bildpruef.py` und einem Punktvergleich über den
Fensterinhalt (x 27..560, y 63..425):

```
10-vorher:  10767 helle Punkte (Text)
20-steckt:   8670
30-danach:   7422
Unterschied 10 gegen 20:  Rechteck (27,63)-(555,422)
Unterschied 20 gegen 30:  Rechteck (26,63)-(425,422)
```

Ein einzelnes Bild mit einer Zeile darauf könnte immer dagestanden
haben; drei verschiedene Bilder aus einem Lauf können es nicht.

---

## Dateien

| Datei | was |
|---|---|
| `kernel/wechsel.fi` | **neu** — die Naht, 8 Plätze, kommt/geht/auswerfen |
| `kernel/usb.fi` | zwei Flankenzähler, `msc_gen`/`msc_weg` |
| `kernel/kgui.fi` | `wechsel_schritt` in drei Schleifen |
| `kernel/kmain.fi` | `/medien`, `wechsel.init`, `usb_hold` verschoben |
| `kernel/sys.fi` | Aufruf 1704, `wechsel_call` |
| `kernel/kstate.fi` | `WECHSEL_OFF` 0xF1000 |
| `kernel/user/auswerfen.fi` | **neu** — `/bin/auswerfen` |
| `kernel/user/explorer.fi` | der Auswurfknopf |
| `kernel/user/ulib.fi` | `SYS_WECHSEL` und die Felder |
| `tools/hotplug/run.sh` | **neu** — die Abnahme, 33/0 |
| `tools/hotplug/monitor.py` | **neu** — `device_add`/`device_del` |
| `tools/hotplug/lauf.sh` | **neu** — ein Lauf mit Drehbuch |
| `tools/hotplug/bild-term.sh` | **neu** — die drei Bilder |
| `tools/hotplug/bilder.sh` | **neu** — der Versuch im Dateimanager |
| `tools/kernel/memmap.py` | `WECHSEL` in der Karte |
| `locale/{de,en}/messages` | die fünf Texte des Knopfes |
