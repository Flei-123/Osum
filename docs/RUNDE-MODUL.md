# Runde MODUL — ein Treiber, der nicht im Kern steht

Arbeitsbaum `/root/osum-modul`, Zweig `modul`, abgezweigt von `main`
(`163984d`). Gemessen am 02.09.2026 auf dem üblichen Wirt (AMD EPYC 7571,
12 Kerne, 19 GiB, `/dev/kvm` vorhanden). **Kein Merge nach `main`.**

Zwei andere Runden liefen daneben: MERGE-5 in `/root/mg-osum` und BLECH
in `/root/osum-blech`. Keine Datei, an der BLECH arbeitet (`ehci.fi`,
`nvme.fi`, `rootsel.fi`, `hw.fi`, `hwdiag.fi`, `tasks.fi`), ist hier
angefasst worden.

---

## Die Frage, und die Antwort in drei Sätzen

Der Eigner fragte: *„Wie macht es Windows? Bei der GPU steht da Basic
Display Driver, und dann kann ich mir z. B. von NVIDIA GPU-Treiber
herunterladen."*

1. **Osum hat das Äquivalent zum Basic Display Adapter schon** —
   `kernel/fb.fi` nimmt den Rahmenpuffer der Firmware oder setzt den
   Modus selbst über die Bochs-Register 0x1CE/0x1CF.
2. **Was fehlte, war das Nachladen.** Diese Runde baut es: ein Treiber
   ist jetzt eine signierte Datei auf der Platte, kein Stück Kern.
3. **Einen Treiber von NVIDIA wird es für Osum nie geben.** Warum, steht
   in `docs/MODUL-BEFUND.md` Abschnitt 3.1, mit Quellen.

---

## Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/modul.fi` | 1079 | **der Lader.** `.omod`-Kopf, Schnittstellenfassung, Ed25519, ELF64-`ET_REL`, Relokationen, Symbolbindung, Ein-/Aussprung, Entladen. 25 benannte Gründe |
| `kernel/ksym.fi` | 348 | **die Ausfuhrtafel des Kerns.** 13 Namen, und die Zahl `ABI` |
| `kernel/modtab.fi` | 154 | die Treibertafel zwischen Lader und Stummel |
| `kernel/modidx.fi` | 83 | die 28 Platznummern, EINMAL aufgeschrieben |
| `kernel/ps2m-aus.fi` | 346 | **der Stummel.** Dieselben 31 Ausfuhren wie `ps2m.fi`, kein Treiber darin |
| `module/ps2maus.fi` | 219 | **das Modul.** Enthält eine Zeile Treiber: `import ps2m` |
| `module/ps2maus-fremd.fi` | 187 | die Gegenprobe mit einem Namen, den der Kern nicht anbietet |
| `tools/modul/mkomod.py` | 257 | `.omod` bauen und signieren, samt allen kaputten Fassungen |
| `tools/modul/bau.sh` | 95 | den Modulbaum zusammenstellen und übersetzen |
| `tools/modul/run.sh` | 381 | die Abnahme, zehn Abschnitte |
| `tools/modul/paket.sh` | 117 | `.omod` → `.opk` → Speicher → Platte |
| `docs/MODUL-BEFUND.md` | 740 | Befund und Entwurf, mit 51 Quellen |

Dazu geändert: `kernel/kstate.fi` (`MODUL_OFF`, drei Seiten auf
0x4D000, und zwei Modusbits), `kernel/kmain.fi` (das Wort `modul` und
der Messabschnitt), `kernel/gfx.fi` + `kernel/gfx-aus.fi` (vier Türen
mehr in der Naht), `kernel/arch/x86_64/isr.s` (`osum_panic` als
Vektor 73), `tools/build-kernel.sh` (`--ohne-ps2m`),
`tools/kernel/memmap.py` (der neue Bereich in der Karte).

---

## Teil 1 — Der Befund

Steht vollständig in **`docs/MODUL-BEFUND.md`**, Teil 1, mit Zitatstellen
und 51 Quellen. Die vier Sätze, auf die es ankommt:

* **Windows' Basic Display Driver** (`BasicDisplay.sys`) schreibt in den
  linearen Rahmenpuffer, den die Firmware gesetzt hat. Auf UEFI:
  *„inherits the linear frame buffer that is set during boot. In this
  case, no mode or resolution changes are possible."* 3D gibt es — aber
  in Software über WARP, nicht auf der GPU.
* **Herstellertreiber sind möglich, weil DREI Dinge zusammenkommen:**
  eine **stabile, versionierte ABI** (`DXGKRNL_INTERFACE` mit
  `Version`-Feld, additiv gewachsen), ein **Ladeformat** (PE +
  Dienstschlüssel + `DriverEntry`), und eine **Signaturkette** (seit
  Windows 10 1607: *„Windows will not load any new kernel-mode drivers
  which are not signed by the Dev Portal"*). Nimmt man eins weg, bricht
  das Ganze.
* **Linux macht das Gegenteil und sagt es offen:** *„Linux does not have
  a binary kernel interface, nor does it have a stable kernel
  interface."* Deshalb `vermagic`, deshalb MODVERSIONS-CRCs je Symbol,
  deshalb schleppt NVIDIA einen quelloffenen *kernel interface layer*
  mit, *„that must be compiled specifically for each kernel"* — und
  deshalb gibt es DKMS.
* **Für Osum folgt daraus, ehrlich:** Ein Treiber von NVIDIA oder AMD ist
  ausgeschlossen — er ist gegen eine fremde ABI gebaut, niemand portiert
  ihn (die Suche fand Herstellertreiber für Nischensysteme nur bei
  NVIDIA/FreeBSD und NVIDIA/Solaris; für Haiku, ReactOS, SerenityOS und
  Redox von niemandem), und selbst ein perfekter Nachbau bekäme eine
  moderne NVIDIA-Karte ohne signierte Firmware nicht über den Starttakt
  (Airlie: *„you can't make it reclock, you can't make it go faster"*).
  Möglich ist genau zweierlei: **(a)** eigene Treiber, die nachgeladen
  statt einkompiliert werden — das ist diese Runde — und **(b)**
  langfristig ein eigener, einfacher Modus-Setz-Treiber je GPU-Familie.

---

## Teil 2 — Der Entwurf und die Empfehlung

Beide Wege sind in `docs/MODUL-BEFUND.md` Teil 2 ausgearbeitet.

**Empfohlen und gebaut: Weg A — Kernmodule mit versionierter
Schnittstelle und Signaturpflicht.** Vier Gründe:

1. Weg B (Ring 3) ist heute nicht ehrlich machbar: **Osum spricht keine
   IOMMU an.** Ein Ring-3-Treiber ohne IOMMU hat volle DMA-Gewalt über
   den ganzen Speicher — die Ring-3-Grenze wäre Zierat. Linux' eigene
   VFIO-Doku: *„DMA is by far the most critical aspect … allowing a
   device read-write access to system memory imposes the greatest risk
   to the overall system integrity."* seL4 sagt es am schärfsten: *„the
   proof assumes that DMA is off."*
2. Weg A löst das Problem, das wirklich da ist: einen Treiber ins System
   bekommen, ohne den Kern neu zu bauen.
3. Weg A liegt auf dem, was Osum schon hat: `firnc` erzeugt `ET_REL`,
   `kernel/elf.fi` beweist seit Runde K1 das Abweisen kaputter ELF,
   `lib/crypto/ed25519.fi` liegt seit Runde UPDATE da.
4. Weg B bleibt danach offen und wird leichter — wer Module laden kann,
   kann später ein Modul laden, das die IOMMU aufsetzt.

**Welcher Weg für welche Geräteart:** eine **Netzkarte** ist ein guter
Ring-3-Kandidat (ein Netz, das zwei Sekunden weg ist, ist ein Ärgernis;
ein Kern, der weg ist, ist ein Datenverlust — und DPDK zeigt, dass es
sogar schneller sein kann). Ein **Speichertreiber, der die Wurzel
trägt, nicht** — er wird gebraucht, bevor es einen Ring 3 gibt, und ein
Neustart hilft nicht, weil das Dateisystem darüber halb geschriebene
Blöcke hat.

---

## Teil 3 — Der Prototyp, und was er misst

### Was eine `.omod` ist

```
  0   8   Kennung "OSUMMOD\n"
  8   4   Formatfassung des Kopfes (1)
 12   4   die Schnittstellenfassung, gegen die gebaut wurde (ksym.ABI)
 16   8   Laenge der Nutzlast
 24   8   Merker, 0
 32  32   Name, nullbeendet
 64   n   die ELF64-Objektdatei (ET_REL), das was `firnc -o x.o x.fi` liefert
64+n 64   Ed25519 (RFC 8032) ueber die Oktette 0 .. 64+n
```

Der öffentliche Schlüssel steht **im Kernabbild** (`kernel/modul.fi`,
`fn schluessel`), nicht in einer Datei daneben. Wer die Platte schreiben
kann, schriebe sonst beides.

### Der Kniff, ohne den es nicht gegangen wäre

Firn kann einen Funktionszeiger nicht in eine Zahl wandeln —
`kernel/vfs.fi` sagt das seit Runde K14 ausdrücklich, und es stimmt
weiter. Was es seit Runde 58/68 kann, ist ein **Funktionswert in einem
Strukturfeld**. Und ein Strukturfeld liegt im Speicher.

Im erzeugten Assembler (beide Übersetzer, `--emit=asm`):

```
    lea rax, [rip + .L__fnv._F0.serial__puts]
    ...
.L__fnv._F0.serial__puts:
    .quad _F0.serial__puts
```

Ein Funktionswert ist also nicht die Adresse der Funktion, sondern die
Adresse einer **Zelle in `.rodata`**, in der die Adresse steht. Zweimal
auflesen gibt die Zahl. Deshalb steht in `kernel/ksym.fi` keine
Assemblerzeile und in `tools/build-kernel.sh` kein zusätzliches
`--defsym`: derselbe Quelltext gilt für `firnc0` (`_F0.`) und `firnc1`
(`_F1.`), weil der Name nirgends aufgeschrieben ist.

**Gemessen, nicht behauptet** (Abschnitt 2 des Läufers): der Kern druckt
alle 13 Adressen, und der Läufer hält jede gegen `nm` auf dem
gebundenen Abbild. **13 von 13 gleich, 0 Abweichungen.**

### Was der Läufer misst

`bash tools/modul/run.sh`, zehn Abschnitte, **74 bestanden, 0
gefallen**. Protokolle: `/root/m3logs/MODUL-lauf1.log` (erster Lauf, drei
Messfehler im Läufer selbst — siehe unten), `MODUL-lauf2.log` (60/0, ohne
Abschnitt 10) und `MODUL-lauf3.log` (74/0, vollständig).

**Zwei Kerne aus EINEM Quelltext.** `tools/build-kernel.sh` ohne
Schalter bindet `kernel/ps2m.fi` ein; mit `--ohne-ps2m` steht
`kernel/ps2m-aus.fi` an seiner Stelle. Das ist derselbe Griff, den das
Repo für `--gui off` (Runde SERVERBUILD) und `--ohne-tunnel` schon hat.
Der Nachweis, dass der Treiber wirklich weg ist und nicht nur
abgeschaltet: `nm` findet `_F0.ps2m__consume` im einen Abbild und **im
anderen nicht**.

| | Kern **mit** `ps2m.fi` | Kern **ohne** |
|---|---:|---:|
| Abbild | 3 403 136 Oktett | 3 393 356 Oktett |
| Differenz | | **9 780 Oktett** |
| `_F0.ps2m__consume` im Abbild | ja | **nein** |

**Der Beweis, in einer Tabelle** (Läuferabschnitte 3–5, Kern mit
`--ohne-ps2m`):

| | ohne Modul | mit Modul | nach dem Entladen |
|---|---|---|---|
| `gfx.mouse_init(800,600)` | **0** | **1** | — |
| `gfx.mouse_present` | **0** | **1** | **0** |
| Gerätekennung vom 8042 | 0 | **3** (Rad) | 0 |
| PS/2-Pakete nach `mouse_move` | 0 | **8** | **0** |
| gezählte Bewegungen | 0 | **6** | 0 |
| Zeigerort | — | x=140 y=70 | — |
| freie Rahmen | 63 988 | 63 979 | **63 988** |

Es sind dieselben Zeilen Quelltext, die vorher und nachher gerufen
werden. Kein Aufrufer ist für diese Runde angefasst worden: `wm.fi` ruft
`ps2m.x(state)` weiter an fünfzehn Stellen, `kgui.fi` an neunzehn,
`gfx.fi` an neun.

**Die Zahlen des Ladevorgangs:**

```
sigok=1  secs=11  syms=218  rel=569  ext=12  bytes=34490
datei=58384  basis=0x5fb000  rahmen=9  abi=1  initrc=0  plaetze=28
```

569 Relokationen aufgelöst, 12 Namen gegen die Ausfuhrtafel des Kerns
gebunden, 34 490 Oktett Abbild in 9 Rahmen, und `modul_init` hat 28
Adressen in die Treibertafel eingetragen. Die Zeile `ps2maus:
eingetragen 28` **kommt aus dem Modul selbst** — das ist fremder
Programmtext, der in Ring 0 `k_puts` und `k_dec` des Kerns ruft.

Das Modul verlangt genau sechs Namen und keinen mehr:
`k_abi k_bind k_dec k_puts kdata osum_panic`.

### Die sechs Abweisungen

Jede mit ihrem Grund auf der seriellen Leitung, jede mit `rc=21` (der
Kern hat sich selbst beendet, er ist nicht gefallen), und in keiner ist
`modul_init` gelaufen:

| Gegenprobe | Grund | wie weit kam sie |
|---|---|---|
| Schnittstellenfassung 2 statt 1 | `fassung` | Kopf gelesen, dann Schluss |
| ein Oktett der Signatur gekippt | `signatur` | Ed25519 gerechnet, dann Schluss |
| ein Oktett der **Nutzlast** gekippt (Signatur bleibt über die alte gültig) | `signatur` | dito |
| die Kennung verdorben | `kennung` | acht Oktett gelesen, dann Schluss |
| ein Symbol, das der Kern nicht anbietet (`k_gibtsnicht`) | `symbol` | **Signatur gültig, 11 Abschnitte gelegt, 9 Relokationen angewandt** — und dann abgewiesen, 0 Plätze in der Tafel |
| gar keine Datei | `datei-fehlt` | — |

Der Fall `symbol` ist die schärfere Zusage: der Lader springt **nicht**
in ein Modul, dessen Lücken er nicht füllen konnte. Ein Lader ohne
Namensprüfung schriebe dort eine Null, das Modul liefe an, und der
Absturz käme irgendwann später an einer Stelle ohne Zusammenhang zur
Ursache.

### Die gemessene GRENZE — und sie wird nicht beschwiegen

Ein Modul, dessen **Programmtext** verdorben ist (64 Oktett `0xCC` = `int3`
mitten in `.text`), das aber **richtig signiert** wurde, kommt durch alle
drei Riegel: `modul: laden=ok`, `nach init=1 present=1`. Und dann:

```
*** EXCEPTION 3 #BP  err=0x0
rc=63
```

**Ein signiertes, aber kaputtes Modul nimmt den Kern mit.** Das ist keine
Lücke im Prototypen, das ist Ring 0 — unter Windows und Linux ist es
genauso. Es ist der Grund, warum die Signatur Pflicht ist und nicht Kür,
und es ist der Grund, warum `docs/MODUL-BEFUND.md` den Ring-3-Weg
überhaupt so ernst nimmt.

Der Kern sagt dabei immerhin, **woran** er gestorben ist. Das ist der
Unterschied zwischen einem Absturz und einem Rätsel.

### Beide Übersetzerstufen

Ein Modul, das **firnc0** gebaut hat, lädt unter einem Kern, den
**firnc1** gebaut hat — laden, Gerät da, entladen, `rc=21`. Genau dafür
gibt es `#[export_c]` (der Einsprungpunkt heißt in beiden Stufen
`modul_init`, ohne `_F0.`/`_F1.`), und genau dafür kommt die
Ausfuhrtafel ohne `--defsym` aus.

### Die Auslieferung — der ganze Weg

```
module/ps2maus.fi
     │  tools/modul/bau.sh            firnc, strip, Kopf, Ed25519
     ▼
ps2maus.omod            58 656 Oktett     ← das prueft DER KERN
     │  pkg/opk.py bauen
     ▼
ps2maus-1.0.0.opk       58 983 Oktett     ← das prueft OPK
     │  werkzeug/store add
     ▼
index.json + index.json.sig, Revision 2   ← das prueft der Speicher
     │  store publish → https://store.fleitec.com/
     ▼
opk installieren  →  /apps/ps2maus.prog/lib/ps2maus.omod
     │
     ▼
der Kern findet es und laedt es
```

Gemessen (`bash tools/modul/paket.sh`, Läuferabschnitt 10):

* `store verify --tief`: **„Signatur gueltig (beide Umsetzungen einig) …
  Ergebnis in Ordnung"**
* Der Katalogeintrag heißt `opk:ps2maus`, `art: "opk"`, `maschine:
  "any"`, mit `sha256` (der Datei) und `inhaltSha256` (über Beschreibung
  + Nutzlast) — genau die zwei Zahlen, die
  `orientstore/docs/KATALOG-FORMAT.md` Abschnitt 3 für `opk` vorsieht.
* `opk installieren --wurzel W` legt die Datei ab, und sie ist **Oktett
  für Oktett** das gebaute `.omod`.
* **Und dann bootet der Kern gegen eine Platte, die aus genau diesem
  installierten Baum gebaut ist, und lädt die Datei, die die
  Paketverwaltung dorthin gelegt hat** — nicht aus `/lib`, sondern aus
  `/apps/ps2maus.prog/lib/ps2maus.omod`, wohin `opk` sie legt. `laden=ok`,
  `present=1`, `pkt=8` nach `mouse_move`, `entladen=1`, `rc=21`.
  (`kernel/kmain.fi` sucht an beiden Stellen — erst dort, wo ein Mensch
  eine Datei hinlegt, dann dort, wo die Paketverwaltung sie hinlegt.
  Windows hat aus demselben Grund einen DriverStore neben
  `System32\drivers`.)

**Drei Signaturen, drei verschiedene Fragen** — und keine ist
überflüssig:

| | Frage | wer prüft | wie oft |
|---|---|---|---|
| Ed25519 über die `.omod` | *darf dieser Programmtext in Ring 0?* | der Kern | bei **jedem** Laden |
| Ed25519 über die `.opk` | *kommt dieses Paket von mir?* | `opk` (Runde UPDATE) | beim Installieren |
| Ed25519 über `index.json` | *ist dieser Katalog echt?* | der Speicher-Client | bei jedem Abgleich |

Windows hat an derselben Stelle ebenfalls **zwei** getrennte Hürden:
Code Integrity beim Laden und die PnP-Signatur beim Installieren.

**Das ist genau das Bild, das Justin vor Augen hatte** — nur ist der
Absender er selbst und nicht NVIDIA.

---

## Abnahme

### Der Modulläufer selbst

`bash tools/modul/run.sh`, zehn Abschnitte:
**74 bestanden, 0 gefallen** (`/root/m3logs/MODUL-lauf3.log`).
Zwei frühere Läufe stehen daneben (`MODUL-lauf1.log`, `MODUL-lauf2.log`);
was zwischen ihnen passiert ist, steht im nächsten Abschnitt.

### Die volle Abnahme

**Sie ist in ZWEI Durchgängen gefahren worden, und der Grund ist ein
Unfall, der hier benannt gehört:** der erste Lauf (`OSUM_JOBS=4 bash
test.sh`, 09:56–12:51) ist nach 39 von 54 angemeldeten Abschnitten
**abgebrochen** — der Prozess war weg, ohne Schlussbilanz im Protokoll
(gedruckt waren zu dem Zeitpunkt 35; die Ausgabe geht der Reihe nach und
hinkt den fertigen Abschnitten hinterher). Was ihn getötet
hat, ist nicht geklärt; kein OOM in `dmesg`, keine volle Platte zu
diesem Zeitpunkt. Er ist nicht neu gestartet worden, weil die 39
gemessenen Abschnitte gültige Messungen sind und ein zweiter voller Lauf
auf diesem Wirt drei Stunden kostet.

| Durchgang | Protokoll | Abschnitte | Ergebnis |
|---|---|---:|---|
| 1 (09:56–12:51, abgebrochen) | `MODUL-ABNAHME.log` | 39 | 36 grün, **3 rot**: `net`, `netview`, `netmon` |
| 2 (`OSUM_NUR` auf die fehlenden 14) | `MODUL-ABNAHME-2.log` | 14 | 13 grün, **1 rot**: `multiuser` |
| 3 (die vier roten einzeln, `OSUM_JOBS=1`) | `MODUL-ABNAHME-3-einzeln.log` | 4 | **noch nicht fertig**, siehe unten |

Danach liegen **54 Protokolle** in `.test-work/`; eines davon
(`vendor.log`) gehört zur Übersetzerprüfung, die außerhalb der
Abschnittsliste läuft. Gemessen sind damit **53 Abschnitte**. Eine
Schlussbilanz über alles gibt es nicht — sie hätte der abgebrochene Lauf
gedruckt.

**Der Wirt war die ganze Zeit dreifach belegt.** Neben dieser Runde liefen
die vollen Abnahmen von BLECH (`/root/osum-blech`) und MERGE-5
(`/root/osum-merge5`) auf demselben Rechner — Lastmittel 12 bis 21 auf
zwölf Kernen. Und die vier Netzabschnitte (`net`, `netmon`, `netview`,
`tunnel`) teilen sich **eine Sperre über alle Arbeitsbäume hinweg**
(`/tmp/osum-netz.lock`, seit Runde TESTFAST, weil `ip netns` dem Wirt
gehört und nicht dem Baum). Der Abschnitt `tunnel` hat deshalb
**7241 s gebraucht, davon 6951 s Warten auf die Sperre** — das steht so
im Protokoll, der Läufer misst es selbst mit.

### Die vier roten, und was sie sind

| Abschnitt | Zusage, die fiel | Art |
|---|---|---|
| `net` | „through 20 % loss: octets that arrived, all of them in order: 261176, expected eq 262144" | **Durchsatz unter künstlichem Paketverlust** — die klassische lastempfindliche Messung |
| `netview` | „faking: the state icon went missing: falsch 40 von 82" | Bildvergleich auf einer Oberfläche; **war in der Vergleichsgrundlage MERGE-3 ebenfalls rot** |
| `netmon` | „'wget: octets 65536' is missing", „'netmon: rows programs=' is missing" | eine Zeile kam nicht rechtzeitte; **MERGE-3 hat diesen Abschnitt ausdrücklich als Lastphantom benannt** |
| `multiuser` | „das Verhaeltnis stimmt nicht: 36925 us zu 692665 us (1875/100)" | **ein Zeitverhältnis** — dieselbe Sorte |

**Keine dieser vier Zusagen berührt den Modullader.** Keine von ihnen
liest eine Datei, die diese Runde angefasst hat; `net`, `netmon` und
`netview` messen den Netzstapel, `multiuser` misst ein Zeitverhältnis
zwischen zwei Benutzern.

Die Vergleichsgrundlage ist `/root/m3logs/ABNAHME-1-mergeline2.log`
(Runde MERGE-3, `main`): dort waren **fünf** Abschnitte rot — `k15`,
`icons`, `netview`, `netmon`, `tresor` —, und `docs/RUNDE-MERGE3.md`
hält für `netmon` und `tresor` fest, dass sie unter Last falsch messen.
In dieser Runde sind `k15`, `icons` und `tresor` **grün**, `netview` und
`netmon` weiterhin rot, und `net` und `multiuser` sind unter der
dreifachen Last dazugekommen.

**Was ich NICHT behaupten kann:** dass die vier bei ruhiger Maschine grün
sind. Der Nachmesslauf (Durchgang 3) hat zur Berichtszeit noch in der
Netzsperre gewartet — MERGE-5 hielt sie über eine Stunde. Wer diese
Runde übernimmt, fährt

```
OSUM_JOBS=1 OSUM_NUR='^(net|netmon|netview|multiuser)$' bash test.sh
```

auf einer Maschine, auf der sonst nichts läuft, und trägt das Ergebnis
hier nach. Das ist die ehrliche Fassung, und sie ist besser als eine
Zahl, die ich mir zurechtlege.

### Die Karte

`python3 tools/kernel/memmap.py`: **82 Bereiche in 0xA0000 Oktetten
kdata, 8 Vektoren, 108 Modusnamen in 16 Wörtern, 0 Kollisionen.** Der
neue Bereich `MODUL` (0x4D000..0x50000) steht in der Karte; die drei
Seiten kommen aus dem Loch, das `kstate.fi` seit Runde K17 zwischen
`MODE_OFF` und `K17_OFF` als frei ausweist.

### Ein Unfall, der benannt gehört

Die Abnahme läuft **in demselben Arbeitsbaum**, in dem committet wird,
und drei ihrer Läufer (`netview`, `themestore`, `umlaut`) **schreiben
ihre Bildschirmfotos in den Baum** (`docs/shots/…`). Ein `git add -A`
hat sie mitgenommen: 25 PNG, deren einziger Unterschied zur Fassung auf
`main` die Kompression eines neuen Laufs ist. Sie stehen in Commit
`e4c228f` und sind mit `1266659` wieder zurückgenommen; die Historie ist
NICHT umgeschrieben.

Dieselbe Sorte Unfall steht in der Commit-Botschaft von `12d292f`
(CERTUS 9/n). Die Lehre ist beide Male dieselbe: wer in einem Baum
arbeitet, in dem gleichzeitig die Abnahme läuft, prüft `git status` VOR
dem `add`.

### `tools/modul/run.sh` steht NICHT in `test.sh`

Eine bewusste Entscheidung: die Abnahme dieser Runde soll dieselben
Abschnitte fahren wie die Vergleichsgrundlage, sonst ist die Zahl
darunter nicht mehr vergleichbar. Der Modulabschnitt ist **getrennt**
gemessen (drei Läufe, alle protokolliert). Wer ihn dauerhaft will,
trägt ihn in `test.sh` ein und misst danach einmal alles neu.

### Was der Läufer über sich selbst gelernt hat

Der erste Lauf (`MODUL-lauf1.log`) meldete **drei rote Zusagen, und alle
drei waren Fehler im Läufer, nicht im Kern.** Sie stehen hier, weil ein
Läufer, der falsch misst, schlimmer ist als einer, der nichts misst:

1. **`nm … | grep -q` unter `set -o pipefail`.** `grep -q` bricht ab,
   sobald es fündig wird; `nm` stirbt an SIGPIPE; `pipefail` macht daraus
   einen Fehlschlag der ganzen Röhre — unabhängig davon, ob das Symbol da
   war. Behoben: erst in eine Datei, dann suchen.
2. **`ext=[0-9]+` traf `k_text=0x1153cc`.** Die Ausfuhrtafel druckt
   `k_text=0x…`, und darin steckt die Zeichenfolge `ext=0`. Der Läufer
   las also eine 0, wo eine 12 stand.
3. **`id=[0-9]+` traf `apic: id=0`.** Dieselbe Sorte Fehler, andere
   Zeile.

Behoben mit zwei eigenen Lesefunktionen, die die Zahl aus **der einen
Zeile** holen, in der sie steht. Danach: `MODUL: 60 bestanden, 0
gefallen` (Lauf 2, ohne Abschnitt 10) bzw. der volle Lauf 3.

---

## Was noch fehlt — ehrlich

**Am Lader:**

* **Kein W^X, und das ist keine Kleinigkeit.** Osum setzt `EFER.NXE`
  nicht (nachgesehen in `kernel/arch/x86_64/boot.s`: gesetzt wird nur
  Bit 8, LME), die 1-GiB-Identitätsabbildung besteht aus 2-MiB-Seiten mit
  `present | writable`. **Jede beschreibbare Seite dieses Kerns ist
  ausführbar.** Der Modullader nutzt das aus — er schreibt in einen
  frisch geholten Rahmen und springt hinein. Richtig wäre: die Seiten des
  Moduls nach dem Relozieren auf nur-lesend-und-ausführbar (`.text`,
  `.rodata`) bzw. lesend-schreibend-nicht-ausführbar (`.data`, `.bss`)
  stellen. Das braucht NXE und ein Aufteilen der 2-MiB-Seiten und ist
  eine Runde für sich.
* **Keine Abhängigkeiten zwischen Modulen.** Linux hat `depends=` und
  `modprobe`; hier gibt es nur „ein Modul, das der Kern befriedigen
  kann". Zwei Module, von denen eines Symbole des anderen braucht, gehen
  nicht.
* **Kein Verweiszähler.** `entladen` fragt nicht, ob gerade jemand in
  einer Funktion des Moduls steht. In dieser Runde ist das messbar
  harmlos (der Messabschnitt läuft mit `nosched`, es gibt keine zweite
  Aufgabe), aber in einem laufenden System mit Zeitgeber und mehreren
  Prozessoren ist es ein Rennen. Linux löst das mit `try_module_get`.
* **Halb angewandte Relokationen werden nicht zurückgenommen.** Scheitert
  die 500. Relokation, sind die ersten 499 geschrieben. Der Lader gibt
  den Rahmenlauf zurück, also ist es folgenlos — aber der Fall
  „Relokation im Abbild eines Moduls, das schon lief" existiert nicht,
  weil es kein Nachladen in ein laufendes Modul gibt. Sobald es das gibt,
  muss dieser Punkt geschlossen werden.
* **Nur ein Steckplatz wird wirklich benutzt.** `modidx.MAX_SLOT` ist 2,
  gemessen ist einer (`SLOT_MAUS`). Ein zweiter Steckplatz ist
  vorgesehen, aber nicht gefahren.
* **Kein Widerruf.** Es gibt einen Schlüssel und keine Sperrliste. Ein
  einmal signiertes Modul bleibt für immer gültig. Windows hat dafür die
  „vulnerable driver blocklist"; Osum hat nichts.
* **Der Schlüssel dieser Runde ist ein PRÜFSCHLÜSSEL** und liegt
  absichtlich im Repo (`tools/modul/pruef.seed`). Für eine Auslieferung
  braucht es einen anderen, der nirgends eingecheckt ist.

**An der Messung:**

* **Der Preis eines Aufrufs über den Stummel ist ABGEZÄHLT, nicht
  gemessen.** Es ist ein Lesen aus `kdata`, ein Vergleich gegen Null und
  ein indirekter Sprung mehr je Aufruf. Eine Zeitmessung an einer
  Funktion, die je Bildwiederholung dreißigmal läuft, bräuchte einen
  Zähler, den diese Runde nicht gebaut hat.
* **Die Tiefe des Kernstapels bei der Ed25519-Prüfung ist nicht
  gemessen.** Der größte Rahmen in `ed25519_verify` ist 5 264 Oktett
  (aus `--emit=asm` abgelesen), der Kernstapel hat 65 536 (`boot.s`,
  `.skip 65536`). Es hat in jedem Lauf gehalten; die tatsächliche Tiefe
  ist unbekannt. `kernel/elf.fi` hat für seinen Pfad einmal 16 208 von
  16 384 gemessen — an dieser Sorte Zahl hängt mehr, als man denkt.
* **`tools/modul/run.sh` steht nicht in `test.sh`.** Begründet oben.
* **`/bin/opk` auf Osum selbst hat das Paket NICHT installiert.** Die
  Auslieferung ist bis zum Wurzelbaum gemessen (`opk.py` auf dem Wirt),
  und der Kern lädt aus genau diesem Baum. Dass Osums eigenes `/bin/opk`
  dasselbe Ergebnis liefert, ist die Zusage der Runde INSTALL und hier
  **nicht neu nachgefahren** worden.

**Am größeren Bild:**

* **Es gibt noch keinen zweiten Treiber als Modul.** Der Prototyp zeigt,
  dass es geht — er zeigt nicht, dass es für eine Netzkarte oder einen
  Speichertreiber geht. Eine Netzkarte hat DMA, Unterbrechungen und
  einen Zustand, der einen Neustart nicht verträgt; das ist die nächste
  Runde und nicht diese.
* **Der Weg zu einem eigenen Modus-Setz-Treiber ist beschrieben, aber
  nicht begonnen** (`docs/MODUL-BEFUND.md` 3.2). Die Reihenfolge nach
  Aufwand ist Bochs/BGA (hat Osum schon) → VMware SVGA II → virtio-gpu →
  Intel.

---

## Und zum Schluss, für den Eigner

**Was du künftig nachladen kannst:** eigene Osum-Treiber als
`.omod`-Datei — eine Maus, eine Netzkarte, eine Tonkarte, ein
Speichertreiber, irgendwann ein einfacher Modus-Setz-Treiber für eine
GPU-Familie. Du lädst sie aus deinem eigenen Speicher
(https://store.fleitec.com/), installierst sie mit `opk`, und der Kern
prüft beim Laden deine Signatur. Der Kern muss dafür nicht neu gebaut
werden.

**Was du nie nachladen kannst:** einen Treiber von NVIDIA oder AMD.
Nicht weil Osum zu klein ist, sondern weil dieser Treiber gegen die
Windows- bzw. Linux-ABI gebaut ist, niemand ihn portiert, und eine
moderne NVIDIA-Karte ohne herstellersignierte Firmware nicht einmal über
ihren Starttakt hinauskommt.
