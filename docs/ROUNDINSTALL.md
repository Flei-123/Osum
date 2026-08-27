# Runde INSTALL — das System auf eine echte Platte, und der Weg zurueck

Zweig `install`. Gemessen mit `bash tools/install/run.sh`, ein Lauf,
sieben Teile: **70 Zusagen, 0 Fehler.**

Was diese Runde angreift, steht in OrientOS' `ROADMAP.md`:

* **9.4** — „kein Programm schreibt ein Wurzeldateisystem auf eine
  Platte […] Aenderungen ueberleben den Lauf nicht."
* **6.1** — „`opk` laeuft auf dem Wirt, nicht auf Osum — das gebootete
  System liest den Store und startet Pakete, installiert aber nicht."
* **6.2** — der oeffentliche Schluessel entsteht bei jedem Bau neu.

Zwei davon sind jetzt eingeloest, einer nur zur Haelfte. Was NICHT
bewiesen ist, steht am Ende, und es ist der laengste Abschnitt.

---

## Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/user/install.fi` | 933 | `/bin/install` — GPT schreiben, EFI-Partition formatieren, Wurzeldateisystem kopieren, Bootlader eintragen |
| `kernel/user/opk.fi` | 1314 | `/bin/opk` — installieren, entfernen, liste, aktualisieren, generationen, zurueck, richten, pruefen |
| `kernel/user/sha.fi` | 260 | SHA-256 fuer beliebige Laengen, in Ring 3 |
| `tools/install/run.sh` | 435 | der Laeufer, sieben Teile mit Gegenproben |
| `tools/install/oneshot.sh` | 112 | EIN QEMU-Lauf, drei Startarten: `iso`, `platte`, `roh` |
| `tools/install/build.sh` | 119 | Kern, 34 Programme, zwei signierte Quellen, leere Zielplatte |

`/bin/install` braucht **keinen einzigen neuen Systemaufruf**: `/dev/hda`
ist seit K14 eine echte Datei mit `lseek`/`read`/`write`, und damit ist
Partitionieren dasselbe, was `fdisk` auf jedem Unix tut. Neu sind nur
zwei Aufrufe, die dem Paketweg fehlten: **`SYS_LINK` (86)** und
**`SYS_SYNC` (162)**.

**Modusbits wurden KEINE zugeteilt.** Der u64-Modusraum steht
unveraendert bei vier freien Bits (38, 61, 62, 63). `tools/kernel/memmap.py`
vor und nach der Runde: *51 Bereiche in 0x60000 Oktetten kdata,
6 Vektoren, **0 Kollisionen***.

---

## 1. Die Karte, und das Format, das sich nicht geaendert haben darf

Die Blockkarte ist in dieser Runde **mehrblockig** geworden — ohne das
haette ein Wurzeldateisystem nie ueber 4096 Bloecke hinauswachsen
koennen. Eine Formataenderung, die sich „nur ein bisschen" aendert, ist
ein anderes Format, also wird sie gegen `main` gehalten:

* ein Abbild ohne `--karten` ist **Oktett fuer Oktett** das von `main`
  (2 097 152 Oktette),
* mit `--karten=8` ein **anderes** Abbild (sonst haette der Vorrat
  nichts getan),
* Superblock mit Vorrat (karten / itab / data): **8 9 41**.

## 2. Die Installation — und was der WIRT auf der Platte findet

Ein Lauf mit dem Wurzeldateisystem als Multiboot-Modul (die Lage eines
ISO) schreibt auf eine **leere 256-MiB-Platte**. Danach liest der Wirt
mit seinen eigenen Werkzeugen nach; einem Installationsprogramm, dem nur
sein eigenes Betriebssystem glaubt, glaubt hier niemand.

| Was | Gemessen |
|---|---|
| Kern | 1 713 708 Oktette |
| Programme im Userland | 34 |
| Quellabbild | 5 242 880 Oktette |
| Probelauf ohne `--ja` | Platte **Oktett fuer Oktett unberuehrt** |
| Kopierte Sektoren | **10 240** |
| Wurzeldateisystem gewachsen auf | **452 207** Bloecke |
| `IDENTIFY` meldet | **524 288** Sektoren |
| Schutz-MBR | 0x55AA, Typ **0xEE** |
| GPT-Kopf | `EFI PART`, CRC32 mit **zlib** nachgerechnet |
| Eintragstafel | CRC32 mit **zlib** nachgerechnet |
| Sicherung am Plattenende | Block **524 287**, Kopf-CRC stimmt, Tafel **Oktett fuer Oktett** die primaere |
| Partition 0 | 2048–72047, **EFI**-Kennung |
| Partition 1 | 72048–524254, **OSUM**-Kennung |
| `fsck.fat` auf der EFI-Partition | **0** (6 Dateien, 3848/68882 Cluster) |
| Kern auf der EFI-Partition | **Oktett fuer Oktett** der gebaute (1 713 708) |
| Bootlader | **Oktett fuer Oktett** der gebaute (253 952) |
| Superblock der Partition | nennt die gewachsene Groesse **452 207** |

## 3. Der Start VON DER PLATTE — ohne ISO, ohne Modul

QEMU bekommt **kein** `-kernel` und **kein** `-cdrom`, nur die Platte und
OVMF. Die Kommandozeile steht in der `limine.conf` **auf der Platte**,
die der Installer dorthin geschrieben hat; ein `-append` waere
geschummelt gewesen.

* Beendigungscode **21** (der vereinbarte Erfolgscode),
* `osum: rootpart=1  first=72048  blocks=452207`,
* eingehaengt, das Userland liegt darauf,
* **`osum: from module` kommt NICHT vor** — es war kein Boot-Modul im
  Spiel.

**Die Gegenprobe, und was sie gekostet hat.** Ein einziges gekipptes
Oktett in der GPT-Eintragstafel (Eintrag 1, Feld „erster Block"), auf dem
Wirt mit `zlib` nachgerechnet: `arr_crc_kaputt True`. Ueber OVMF startet
dieselbe kaputte Platte **trotzdem** — und das ist keine Schwaeche des
Kerns, sondern eine Eigenschaft von UEFI: die Firmware stellt den
primaeren GPT-Kopf aus der Sicherung wieder her, bevor irgendein
Betriebssystem ihn zu Gesicht bekommt. Wer hier misst, prueft die
Firmware und nicht sich selbst.

Deshalb gibt es jetzt eine dritte Startart, `roh`: der Kern kommt ueber
`-kernel`, es gibt **keine Firmware und kein Modul**, und niemand ausser
ihm sieht die Partitionstafel an. Erst der positive Fall auf diesem Weg
(`osum: rootpart=1`, Code 21) — ohne ihn waere die Gegenprobe auch dann
gruen, wenn der Startweg gar nicht funktioniert. Dann die Gegenprobe:

```
part: gpt crc mismatch
part: mbr=2  gpt=1  parts=0
osum: no ofs partition
osum: mount=0
```

Und der Befund ueber UEFI steht als eigene, gruene Zusage daneben,
gemessen und nicht behauptet.

## 4. Dass Schreiben den Lauf ueberlebt

Der Satz aus 9.4, der bis heute galt, gilt nicht mehr: Datei anlegen,
herunterfahren, neu starten, wieder lesen — **und der Wirt liest sie
danach aus der Abbilddatei**. Vier Zusagen, alle gruen.

## 5. Der Paketweg auf dem Geraet

`/bin/opk` installiert ein Paket, das der **Wirt** gebaut hat und das
Osum nie gesehen hat. Store, PLAN-Dateien und `/system/AKTUELL` genau
wie in `PAKETE.md` — kein zweites Format.

| Schritt | Gemessen |
|---|---|
| hallo 1.0.0 | `b7ee223324e20b36` |
| hallo 2.0.0 | `cec208d4dc40c2f4` |
| installieren | Code 21, `opk: installiert hallo` |
| das Paket **laeuft** aus `/apps` | ja |
| `opk liste` | nennt **genau** den Hash, den der Wirt gerechnet hat |
| aktualisieren aus der Quelle | nimmt die neue Fassung, Hash aus dem INDEX |
| nach dem **Neustart** | die neue Fassung laeuft |
| Generationen | **zwei** |
| `opk zurueck` | die **alte** Fassung laeuft wieder, Liste nennt den alten Hash |

Gegenproben: ein Paket mit einem gekippten Oktett wird abgelehnt
(`opk: Pruefsumme falsch`) — und das **unversehrte** wird im selben Lauf
angenommen. Eine Gegenprobe ohne diese zweite Haelfte beweist nur, dass
das Programm ueberhaupt nein sagen kann.

## 6. Der Stromausfall

QEMU wird mit **SIGKILL** beendet, waehrend die Aktualisierung schreibt —
an sechs verschiedenen Stellen. Danach muss die Platte starten, `opk liste`
**genau einen** der beiden Hashes nennen und das Paket laufen.

| Abbruch nach | Startet | Liste | Laeuft |
|---:|---|---|---|
| 300 ms | ja | alt | Fassung 1 |
| 700 ms | ja | alt | Fassung 1 |
| 1200 ms | ja | alt | Fassung 1 |
| 1800 ms | ja | alt | Fassung 1 |
| 2600 ms | ja | alt | Fassung 1 |
| 3600 ms | ja | **neu** | **Fassung 2** |

**6 von 6 ueberlebt, nie ein Zustand dazwischen.** Der Umschlag hat
genau einen Punkt: `/system/AKTUELL` ist eine Datei, deren **Laenge sich
nicht aendert**, wird also in genau einen Datenblock geschrieben, und ein
Sektor erreicht die Platte ganz oder gar nicht. Alles davor (Store-Eintrag
unter `/store/.teil`, dann EIN `rename`; die neue Generation als
Verzeichnis) ist noch niemandes Wahrheit; alles danach (`/apps`) ist
abgeleiteter Zustand, den `opk` bei jedem Aufruf nachbaut.

Dass SIGKILL das richtige Werkzeug ist, ist kein Geschmack: QEMU schreibt
mit `cache=writeback` in den Seitenspeicher des Wirts, was der Gast
geschrieben hat, ueberlebt also das Ende des QEMU-Prozesses. Der Abbruch
trifft **den Gast** und nicht die Abbilddatei. Ein Wirtsabsturz waere
eine andere Frage — und die stellt dieser Lauf nicht.

---

## Zwei Fehler, die aelter sind als diese Runde

### FLUSH CACHE an ein besetztes Laufwerk

In `ata_write_on` stand `out8(ATA_CMD, ATA_FLUSH)` **unmittelbar** hinter
dem letzten Datenwort. Nach ATA/ATAPI-7 (6.20) darf ein Befehl nur an ein
Laufwerk gehen, das nicht beschaeftigt ist; nach dem letzten Wort eines
WRITE SECTORS setzt das Laufwerk BSY und schreibt. QEMU macht daraus je
nach Zeitpunkt einen abgebrochenen Befehl mit gesetztem ERR — und
`blk.write` meldete einen Fehler fuer einen Sektor, der in Wirklichkeit
auf der Platte stand.

Aufgefallen ist es erst hier, weil erst diese Runde **tausende** Sektoren
hintereinander schreibt: derselbe Lauf brach einmal beim 1032. Sektor ab
und einmal gar nicht. Gespuelt wird jetzt dort, wo es hingehoert —
`blk.flush` einmal, gerufen von `sync`.

### Lesen wurde nicht wiederholt, Schreiben schon

Der teurere Fund, und der Grund, warum die letzte Zusage lange rot blieb.
`blk.write` ging ueber `ata_write_twice`: zwei Versuche, dazwischen ein
`ata_recover`. `blk.read` ging ueber `ata_read` — **ein einziger Versuch,
ohne Ruecksetzen**. Zwei Umsetzungen desselben Weges, und nur eine davon
war repariert worden.

Ein Lesefehler ohne `ata_recover` laesst das Laufwerk in dem Zustand
stehen, in dem es gestolpert ist. Deshalb war nicht ein Block verloren,
sondern **alle folgenden**: erst `opk: das Umbenennen scheiterte`, dann
`sh: cannot run opk -> -2`, und das Dateisystem war fuer den Rest des
Laufes hin.

**Wie es festgenagelt wurde** — der Fehler sah nach Zufall aus, war aber
keiner:

| Lage | Ergebnis |
|---|---|
| unmittelbar nach der Installation gestartet | **2 von 2 Fehler** |
| derselbe Platteninhalt ueber eine Kopie | **10 von 10 gut** |
| `cmp` zwischen beiden Abbildern | **Oktett fuer Oktett gleich** |
| direkt nach der Installation, **nach dem Fix** | **5 von 5 gut** |

Der Unterschied war allein die Zugriffszeit des Wirtes: eine frisch
beschriebene 256-MiB-Datei antwortet langsamer als eine, die gerade
kopiert wurde. `cmp` schliesst den Platteninhalt als Ursache aus — das
ist der Messwert, der aus „mal so, mal so" einen Befund macht.
`read` nimmt jetzt denselben Weg wie `write`, und beide kennen auch die
zweite Platte (`DEV_ATA1`). Die toten Zwillinge `ata_read`, `ata_write`
und `ata_select` sind geloescht: ein Weg, nicht zwei.

---

## Was NICHT bewiesen ist

* **Echte Hardware ist nicht angefasst worden.** Alles laeuft unter QEMU
  mit einem IDE-Laufwerk und OVMF. Ein echtes BIOS, ein echtes SATA-
  Laufwerk, eine echte NVMe: nicht gemessen.
* **Der Installationsweg kennt nur ATA.** `blk.fi` hat einen NVMe-Pfad,
  aber `/bin/install` ist nur gegen `/dev/hda` gelaufen. Ob er auf NVMe
  arbeitet, ist unbekannt — nicht „geht wahrscheinlich".
* **`/bin/opk` prueft die Ed25519-Signatur NICHT.** Geprueft wird, dass
  das Paket genau den Hash hat, den der INDEX ihm zuschreibt — ein echtes
  Glied der Kette, es faengt ein ausgetauschtes **Paket**. Einen
  ausgetauschten **INDEX** faengt es nicht. Wer die Kette ganz will,
  prueft die Quelle heute auf dem Wirt (`opk.py quelle`). Damit bleibt
  **ROADMAP 6.2 offen**, und der oeffentliche Schluessel entsteht
  weiterhin bei jedem Bau neu — er ist ein Verfahren, keine Herkunft.
* **Der Stromausfall ist an sechs Zeitpunkten gemessen, nicht
  erschoepfend.** Sechs von sechs ist ein Befund, kein Beweis. Ein
  Fenster von wenigen Mikrosekunden, das keiner der sechs Abbrueche
  getroffen hat, waere von diesem Lauf nicht zu sehen.
* **Nur der Gast wurde abgeschossen, nicht der Wirt.** Was passiert, wenn
  dem Rechner unter dem laufenden QEMU der Strom ausgeht (also der
  Seitenspeicher des Wirts verlorengeht), stellt dieser Lauf nicht.
* **Eine Plattengroesse, ein Layout.** 256 MiB, eine EFI-Partition, eine
  Wurzelpartition. Kleinere Platten, vorhandene Partitionen, mehrere
  Betriebssysteme nebeneinander: nicht gemessen. Und eine harte Grenze,
  die dieser Lauf nicht anfasst: `ata_select_on` legt die LBA in vier
  Register (`(lba >> 24) & 0x0F`) — das ist **LBA28**, also
  2^28 Sektoren = **128 GiB**. Groessere Platten braucht LBA48, und das
  ist eine eigene Runde.
* **Kein Aktualisieren des KERNS.** Aktualisiert wurde ein Paket. Ein
  neuer Kern auf der EFI-Partition, mit Rueckfallmoeglichkeit, ist nicht
  gebaut und nicht gemessen.
* **`firnc` liegt weiterhin nicht im Produkt** (ROADMAP 6.4a). Das
  installierte System kann `.s` assemblieren, aber keine `.fi`
  uebersetzen.
