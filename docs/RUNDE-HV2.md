# Runde HV2 — vom Wirt zum Rechner

Die Runde K12 hat einen **Wirt** gebaut: Steuerblock, Weltwechsel,
Austrittsgrund, zwei Übersetzungsebenen. Was sie nicht hatte, war ein
**Rechner** — etwas, das ein fremdes Betriebssystem für eine Maschine
halten könnte. Ein Gast im Realmodus, acht Rahmen Speicher und eine
serielle Schnittstelle, die nur in eine Richtung geht, sind kein
Rechner.

Diese Runde baut die drei Stufen, die aus dem Wirt einen Rechner machen,
und sie baut sie **fertig und gemessen** statt alle fünf halb.

    bash tools/hv/run.sh          HV: 162 passed, 0 failed
    (vorher, Runde K12)           HV: 114 passed, 0 failed

Dazugekommen sind **48 Zusagen**. Keine bestehende ist weggefallen, und
keine bestehende Zahl hat sich ohne Grund geändert.

---

## 0. Was fertig ist und was nicht — zuerst, damit es niemand sucht

Der Auftrag nennt fünf Stufen. **Drei sind fertig, zwei nicht**, und das
steht hier oben statt unten:

| # | Stufe | Stand |
|---|---|---|
| 1 | **Der lange Modus im Gast** | **fertig, gemessen** |
| 2 | **Gastspeicher, der mitwächst (2 MiB)** | **fertig, gemessen** |
| 3 | **Virtuelle Geräte: Verteiler, Zeitgeber, serielle Schnittstelle** | **fertig, gemessen** |
| 3b | `virtio-blk` / `virtio-net` als **Gerät** | **nicht gebaut** |
| 4 | **Der Ladeweg** (`bzImage`, `boot_params`) | **nicht gebaut** |
| 5 | **Der Entzifferer mit Gast-Paging** | **nicht gebaut** |

**Ein Linux ist in dieser Runde nicht gestartet.** Der Auftrag sagt, in
diesem Fall seien drei fertige Stufen besser als fünf halbe — das ist
die Entscheidung, die hier getroffen wurde, und Abschnitt 8 sagt genau,
woran es liegt und was gemessen wurde, statt es zu vermuten.

---

## 1. Stufe 1 — der lange Modus, und warum `LMA` der Beweis ist

Die Gäste der Runde K12 laufen im Real- und im geschützten Modus.
`EFER.LME`/`LMA` wurden durchgereicht, aber **nie gemessen** — das sagt
der Bericht jener Runde selbst.

Der siebte Gast (`kernel/arch/x86_64/hv.s`, `g_lm_start`) geht den
ganzen Weg **selbst**, so wie jeder x86-Kern ihn geht:

```
Realmodus → eigene GDT → geschützter Modus → vierstufige Tabelle
mit 2-MiB-Seiten → CR4.PAE → EFER.LME → CR0.PG → weiter Sprung
in ein Segment mit L=1 → 64 Bit
```

### Warum `EFER.LMA` und nicht `EFER.LME` die Zusage ist

Das ist der Kern der Messung. `LME` (Bit 8) **schreibt der Gast selbst** —
eine Zusage darüber wäre eine Zusage über den Gast, nicht über den Wirt.
`LMA` (Bit 10) ist ein **Nur-Lese-Bit**: es setzt **der Prozessor**, und
zwar genau in dem Augenblick, in dem bei gesetztem `LME` das Paging
dazukommt. Der Gast kann es nicht fälschen.

Gemessen (`value 10`, vom Gast im langen Modus per `rdmsr` gelesen):

```
hv: OK  guest 7 reached LONG MODE: efer.lme and lma      efer & 0x500 == 0x500
hv: OK  guest 7 runs with pe and paging on cr0           cr0 & 0x80000001
hv: OK  guest 7 turned on pae -- without it no           cr4 & 0x20
hv: OK  guest 7 really has 64 bit wide registers         0x12345678
hv: OK  guest 7 wrote through a 2 MiB page and read      0xC0FFEE64
hv: OK  and the host really took the efer.lme write
```

Die vierte Zeile ist die, die man nicht umgehen kann: der Gast bildet
`0x1234567800000000`, schiebt 32 Bit nach rechts und meldet das Ergebnis.
**Ein Gast im geschützten Modus könnte diesen Wert gar nicht erst
bilden** — es gibt kein 32-Bit-Register, in das er passt.

### Der Wirt musste dafür etwas lernen: `wrmsr` wirklich annehmen

Bis zu dieser Runde **schluckte** der Wirt jedes Schreiben auf ein MSR
(`do_msr`: `if write { return }`). Für die Gäste der Runde K12 war das
richtig — keiner brauchte eines. Ein Gast, der in den langen Modus will,
braucht **genau eines**.

Der Wirt übernimmt jetzt `LME`, `NXE` und `SCE` in das Gast-EFER. Was er
**nicht** übernimmt, ist `SVME`: das Bit muss im Gast-EFER stehen (AMD
APM Band 2, 15.5.1), aber es gehört nicht dem Gast — ein Gast, der es
löschte, machte seinen eigenen Zustand ungültig. `LMA` steht
ausdrücklich **nicht** in der Maske; es ist das Bit, das der Prozessor
setzt.

---

## 2. Die Falle, die diese Stufe wirklich gekostet hat: `LMA` beim abgefangenen `mov cr0`

Das ist der lehrreichste Fehler der Runde, und er sah aus wie ein Fehler
des Gasts.

Mit `gastcr` fängt der Wirt Schreibzugriffe auf CR0/CR3/CR4 ab, liest
den Befehl selbst und **schreibt den Wert in das VMCB-Feld**. Der
Gast im langen Modus starb dann — `shutdown=2` statt 1, und zwar
zuverlässig.

Der Grund ist architektonisch und steht in keinem Fehlerbild:

> Führt **der Gast** `mov reg, cr0` mit PG aus und steht `EFER.LME`,
> dann setzt **der Prozessor** `EFER.LMA` dazu. Fängt **der Wirt** den
> Befehl ab und schreibt den Wert selbst in das Feld, geschieht das
> **nicht** — er hat nur ein Feld beschrieben, und kein Prozessor hat
> etwas ausgeführt.

Beim nächsten Eintritt steht dann `CR0.PG=1`, `CR4.PAE=1`, `LME=1` und
`LMA=0`. Das ist ein **ungültiger Gastzustand**, und der Gast stirbt.

Die Abhilfe steht jetzt in `decode_movcr` und ist fünf Zeilen: wer CR0
für den Gast schreibt, zieht `LMA` nach — und nimmt es wieder weg, wenn
das Paging fällt. **Hier trennt sich ein Wirt, der Steuerregister
abfängt, von einem, der es nur vorhat.**

---

## 3. Stufe 2 — eine Tabelle, die mitwächst

Die NPT der Runde K12 hat **eine** Seitentabelle und deckt damit 2 MiB.
Für sechs Gäste von je acht Seiten reicht das; für irgendetwas Echtes
nicht.

`npt_build_big` baut die Tabelle aus **2-MiB-Seiten** (PML4 → PDP → PD,
und im PD steht mit dem Bit `PS` unmittelbar der Speicher). Das spart
nicht nur Platz, sondern vor allem **Zeit**: 64 MiB in Seiten zu 4 KiB
wären 16384 Einträge in 32 Tabellen — in Seiten zu 2 MiB sind es 32
Einträge in **einer**.

Gemessen, der Gast im langen Modus auf einer Maschine mit 8 MiB:

```
hv: guest lm slot=4 exits=14 out=2 result=0x6464 state=3  big2m=4  pages=2048
hv: OK  and its npt is built from 2 MiB pages, not 4K
```

`big2m=4` sind vier große Seiten, `pages=2048` sind 2048 Rahmen — 8 MiB.
Der Schreibzugriff des Gasts auf `0x00200000` liegt in der **zweiten**
großen Seite und kann nur ankommen, wenn wirklich mit 2-MiB-Einträgen
übersetzt wird.

### Die Ausrichtung ist der ganze Punkt

Ein Eintrag mit `PS` verlangt, dass die Adresse auf 2 MiB ausgerichtet
ist. `frame_run` gibt zusammenhängende Rahmen, **verspricht aber keine
Ausrichtung**. Also fordert `vm_create_big` eine große Seite mehr an,
als es braucht, und fängt beim nächsten Vielfachen an.

Und damit das kein Leck wird, merkt sich die Maschine **beides**:
`V_RUNBASE`/`V_RUNLEN` (was `frame_run` herausgab) und `V_RAM` (wo der
Gast anfängt). Zurückgegeben wird der **Lauf**, nicht der ausgerichtete
Anfang. Wer nur ab `V_RAM` freigibt, lässt bei jedem großen Gast die
Rahmen davor liegen:

```
hv: frames before=62770 after=62770 leak=0
```

---

## 4. Stufe 3 — Geräte, nicht Treiber

Der Bericht der Runde K12 sagt es selbst: *„Osum hat beide Treiber
bereits für sich selbst, aber ein Treiber ist nicht ein Gerät."* Diese
Stufe baut die andere Seite — `kernel/arch/x86_64/vdev.fi`, 
**neu**.

Der Unterschied ist nicht akademisch. Bis hierher hatte ein Gast **eine
Richtung**: Schreiben auf 0x3F8 wurde weitergereicht, jedes Lesen
lieferte `0xFF` (den offenen Bus). Das reicht für einen Gast, der reden
will. Ein Betriebssystem **prüft aber erst und benutzt dann**.

### Drei Geräte, und warum genau diese

| Gerät | Anschlüsse | ohne es |
|---|---|---|
| **16550A**, serielle Schnittstelle | 0x3F8–0x3FF, **alle acht Register, beide Richtungen** | man sieht nicht, wie weit ein Gast gekommen ist |
| **8259A ×2**, Unterbrechungsverteiler | 0x20/0x21, 0xA0/0xA1 | kein Gast bekommt je eine Unterbrechung zugestellt |
| **8254**, Zeitgeber | 0x40–0x43, 0x61 | keine Systemuhr, keine Kalibrierung |

### `LSR = 0xFF` ist tödlich — und genau das lieferte die Runde K12

Linux' `serial8250_do_startup` hat eine ausdrückliche Sicherheitsprüfung:
liest es im Zeilenzustandsregister `0xFF`, hält es den Anschluss für
defekt und gibt ihn auf (*„LSR safety check engaged!"*). Der offene Bus
der Runde K12 lieferte genau das. **Ein Gast hätte geredet und Linux
hätte geschwiegen** — und niemand hätte gesehen, warum.

Der Ruhewert ist jetzt `0x60` (`THRE|TEMT`, „ich kann senden"), weil
dieser Wirt jedes Oktett sofort weitergibt.

### Der achte Gast prüft die Geräte, statt sie zu benutzen

`g_dev_start` macht die Proben, die ein Treiber macht:

```
hv: OK  the uart scratch register really holds 0x5A     (0x3FF: reiner Speicher)
hv: OK  the uart says thre and temt: it can send        (LSR == 0x60)
hv: OK  and the lsr is NOT 0xFF -- linux would give up
hv: OK  behind dlab lies the divisor, not the data      (DLAB-Umschaltung)
hv: OK  the pic took the full icw1..icw4 sequence       (Maske 0xFD zurück)
hv: OK  and its vector base is the guest's 0x30, not    (aus ICW2, nicht fest)
hv: OK  the timer joined both halves into 0x2E9C        (zweiteiliges Schreiben)
hv: OK  and the pic is fully initialised, step 0
gast| geraete geprueft
```

Zwei davon sind die, an denen Emulationen üblicherweise scheitern:

* **Die Vektorbasis darf nicht fest verdrahtet sein.** Die Lehrbücher
  sagen 0x20/0x28; ein heutiger Linux nimmt **0x30/0x38**
  (`ISA_IRQ_VECTOR`). Der Verteiler nimmt sie deshalb immer aus dem,
  was der Gast in ICW2 geschrieben hat.
* **Das zweiteilige Schreiben des Zeitgebers.** Ein Treiber schreibt
  zwei Oktette nacheinander in denselben Anschluss. Wer beide als
  ganzen Wert nimmt, bekommt eine Uhr, die um den Faktor 256
  danebenliegt. Gemessen: `0x2E9C` und nicht `0x2E` oder `0x9C`.

---

## 5. Zwei Fehler, die die Messung gefunden hat — und die still gewesen wären

Beide sind wertvoller als die Stufen selbst, weil sie zeigen, wofür das
Messen da ist.

### (a) Ein neuer Gast an der falschen Stelle in der Tabelle

`hv.fi` findet das Abbild eines Gasts über `HV_G_FIRST + Nummer * 2`.
Der neue Gast stand zuerst auf Platz **16**, hinter den Hilfsfunktionen.
Die Formel las Platz **13**, fand dort `hv_guest_save` — und **kopierte
eine Funktion des Wirts als Gastabbild in den Gastspeicher**.

Das Fehlerbild war irreführend: `rip=0xFFF`, ein NPF weit außerhalb, ein
Gast, der nach zwei Austritten starb. Es sah aus wie ein Speicherfehler
und war ein Tabellenfehler. **Die Gäste müssen lückenlos stehen**; das
steht jetzt als Kommentar an der Tabelle.

### (b) Der Briefkasten war zu klein

Der Geräte-Gast meldete die Werte 40–45. `value_put` hat eine Grenze:

```
if n >= VAL_MAX { return }        // VAL_MAX war 32
```

**Alles ab 32 wurde still weggeworfen.** Die Geräte lieferten dabei die
ganze Zeit die richtigen Werte — im Protokoll nachgesehen: `0x5A`,
`0x60`, `0x0C`, `0xFD` —, und die Zusagen darüber blieben trotzdem rot.
Eine Stunde Suche am falschen Ende.

`VAL_MAX` ist jetzt 64, und die Maske ist zu den Skalaren gezogen
(`S_VALMASK`), weil die Werte sonst in sie hineingelaufen wären — was
beim Hinschreiben auffiel und nicht erst beim Messen.

### (c) Der Geräteblock war kleiner als seine Felder

`VD_BYTES` war 128, die Felder reichen bis `0xE0`. Der Zeitgeber einer
Maschine lag damit im Block der nächsten. Jetzt 256.

---

## 6. Wo der Zustand liegt — und ein Befund über `kdata`

Die Geräte brauchen eine eigene Seite. Der Bericht der Runde K12 sagt,
`0x41000` bis `0x50000` sei frei. **Das stimmte damals und stimmt heute
nicht mehr**: seither haben K13, K14, WIG, K16, MODE, EHCI, K17, K18,
OFS3, DISP und JRNL den ganzen Bereich bis `0x60000` belegt.

`tools/kernel/memmap.py` hat die Kollision **dreimal hintereinander**
gemeldet, statt sie durchgehen zu lassen — `0x41000` (K13), `0x84000`
(HNON/HCNT), `0x88000` (TASK). Genau dafür gibt es den Kartenprüfer.

Die Geräte liegen jetzt auf **`0x13C000`**, den letzten 16 KiB von
`kdata`. **Das ist der letzte zusammenhängende freie Block.** Wer nach
dieser Runde eine Seite braucht, muss `KDATA_SIZE` wachsen lassen —
das ist ein Befund für die nächste Runde und keine Nebenbemerkung.

```
134 Bereiche in 0x140000 Oktetten kdata, 0 Kollisionen
```

Innerhalb der Seite des Wirts musste außerdem der Registerblock weichen:
die Maschinen wurden von 128 auf 192 Oktette länger (`V_RUNBASE`,
`V_RUNLEN`, `V_BIG`), also von `0x400..0x7FF` auf `0x400..0x9FF`.
`GPR_OFF` liegt deshalb jetzt bei `0xA00` statt `0x800`. Ohne das hätte
die Maschine 5 die Register der Maschine 0 als ihren Zustand gelesen —
ein Fehler, den man nicht sieht.

---

## 7. Die Austritte, nach Grund gezählt

Ein voller Lauf (`hv gastlauf gastmess gastcr gastlang gastgeraet`):

```
hv: exits total=668  cpuid=2  ioio=52  msr=3  hlt=0  vmmcall=538
                     npf=1  intr=64  shutdown=1  exc=0  crwr=7
                     err=0  other=0
```

Jede Zahl ist erklärbar, und der Läufer prüft jede:

| Grund | K12 | HV2 | woher die Differenz |
|---|---|---|---|
| `ioio` | 16 | **52** | +1 langer Modus (`L`), +35 Geräte-Gast (5 Proben mit Rücklesen, 17 Oktette Text) |
| `crwr` | 3 | **7** | +4 langer Modus (CR4, CR3, CR0 zweimal) |
| `msr` | 0 | **3** | der lange Modus liest und schreibt `EFER` |
| `shutdown` | 1 | **1** | **unverändert** — der Gast im langen Modus stirbt *nicht* mehr |
| `err`, `other` | 0 | **0** | kein zurückgewiesener Eintritt, kein unbehandelter Grund |

Was ein Austritt kostet, unverändert gemessen (QEMU-Emulation, keine
Aussage über echte Hardware):

```
hv: bench rounds=512 cycles=36596846 per-exit=71478
           in-guest=56202 in-host=15275
```

---

## 8. Warum kein Linux gestartet ist — gemessen, nicht vermutet

Der Ladeweg ist **nicht gebaut**, und der Grund ist eine Zahl. Aus dem
Kopf des bzImage, das auf dieser Maschine liegt
(`/boot/vmlinuz-6.12.101+deb12-rt-amd64`), ausgelesen:

```
boot_flag  0x1FE = 0xAA55          header 0x202 = "HdrS"
version    0x206 = 0x020F          xloadflags 0x236 = 0x7F  (XLF_KERNEL_64 gesetzt)
setup_sects 0x1F1 = 39             -> der zu ladende Teil fängt bei 0x5000 an
pm_size                            = 11 974 592 Oktette  (11 MiB)
init_size  0x260 = 0x37EC000       = 58 966 016 Oktette  (56 MiB)
pref_address 0x258 = 0x1000000     kernel_alignment 0x230 = 0x200000
```

`init_size` ist die Zahl, die entscheidet: **56 MiB müssen identisch
abgebildet sein**, bevor der Kern den ersten Befehl ausführt. Dazu die
Zero-Page, die Kommandozeile und ein initrd.

Das ist mit Stufe 2 grundsätzlich erreichbar — `vm_create_big` legt
2-MiB-Seiten an, und 56 MiB sind 28 davon. Was **fehlt**, ist der Weg
dorthin, und zwar vollständig:

1. **Das Abbild muss in den Gast.** Osum müsste ein bzImage von einer
   Platte lesen und 11 MiB in den Gastspeicher kopieren. Der Läufer
   dieser Runde startet den Kernel über Multiboot **ohne Dateisystem**
   (`nofs`) — es gibt in dieser Prüfumgebung keine Platte, von der
   gelesen werden könnte.
2. **Die Zero-Page.** 4 KiB, genullt, mit dem Setup-Kopf aus dem Abbild
   (`0x1F1` bis `0x202 + Oktett bei 0x201`), `type_of_loader = 0xFF`,
   `cmd_line_ptr`, und **mindestens einem E820-Eintrag** (20 Oktette:
   Adresse, Größe, Typ 1) samt `e820_entries` bei `0x1E8`.
3. **Der Einsprungzustand.** Der 64-Bit-Einsprung liegt bei
   `Ladeadresse + 0x200` und verlangt wörtlich (boot.rst): *„the CPU
   must be in 64-bit mode with paging enabled … a GDT must be loaded
   with the descriptors for selectors `__BOOT_CS(0x10)` and
   `__BOOT_DS(0x18)` … interrupts must be disabled; `%rsi` must hold
   the base address of the struct boot_params."* Der Wirt müsste den
   Gast also **fertig im langen Modus starten**, statt ihn selbst
   hineinlaufen zu lassen — das ist neu, aber nach Stufe 1 gerade der
   Teil, der gebaut ist.
4. **Der Entzifferer** (Stufe 5) kann nur `0F 22 /r` und nur ohne
   Gast-Paging. Ein Linux schaltet sein Paging sofort ein; von da an
   müsste der Wirt die Tabellen **des Gasts** selbst laufen, um an die
   Befehlsoktette zu kommen.

**Und für Windows** — das ist ausdrücklich **nicht** das Ziel dieser
Runde und auch nicht das der nächsten. Darüber hinaus bräuchte es
**ACPI-Tabellen** (RSDP, RSDT/XSDT, FADT, MADT — Windows startet ohne
sie nicht), einen **UEFI- oder BIOS-Weg** statt eines Boot-Protokolls,
einen **LAPIC/IO-APIC** statt der beiden 8259, einen **PCI-Konfigurations-
raum**, eine **Platte, die es kennt** (AHCI oder virtio mit Treiber im
Installationsabbild) und eine **Grafikausgabe**. Das ist das Ziel
*danach*, nicht dieses.

---

## 9. Die Gegenproben

Jede neue Stufe hat eine Probe, in der sie **zusammenbricht**. Ohne sie
wäre jede Zusage nur eine Behauptung über einen Lauf, der zufällig
gutging.

| Wort | was zusammenbricht |
|---|---|
| `ohnelme` | der Wirt schluckt das Schreiben auf `EFER.LME` wie in K12 — der Gast bleibt 32 Bit und **stirbt in einem Dreifachfehler**; die Zusage über den langen Modus wird **rot** |
| *ohne* `gastlang` | kein Gast im langen Modus, und die Gäste der Runde K12 laufen **unverändert** |
| *ohne* `gastgeraet` | kein Geräte-Gast |
| Geräte-Probe | das Kratzregister gibt zurück, was hineingeschrieben wurde, und der Zeilenzustand ist **nicht** `0xFF` |

Dazu alle sechs Gegenproben der Runde K12 (`ohne hv`, `nonpt`,
`gastfrei`, `nosvm`, `-cpu qemu64`, das Wort-als-Wort) — **unverändert
grün**.

---

## 10. Die Dateien

| Datei | Zeilen | was diese Runde daran tat |
|---|---|---|
| `kernel/arch/x86_64/vdev.fi` | ~560 | **neu** — die drei Geräte |
| `kernel/arch/x86_64/hv.s` | +240 | zwei neue Gäste (langer Modus, Geräte), Tabelle umsortiert |
| `kernel/arch/x86_64/hv.fi` | +380 | `EFER`-Übernahme, `LMA` beim abgefangenen `mov cr0`, `npt_build_big`, `vm_create_big`, Geräte-Anbindung, größerer Briefkasten |
| `kernel/arch/x86_64/vmcb.fi` | +50 | die Konstanten des langen Modus (`ATTR_CODE64`, `EFER_LME/LMA`, `CR4_PAE`, `PT_PS`) |
| `tools/hv/run.sh` | +90 | 18 neue Zusagen, 3 neue Gegenproben, angepasste Zahlen |
| `tools/kernel/memmap.py` | +6 | der Bereich `VDEV` |
| `tools/struktur/ablage.txt`, `schichten.txt` | +2 | `vdev` eingetragen |

---

## 11. Was offen bleibt — ehrlich

1. **Der Ladeweg** (Stufe 4). Abschnitt 8 sagt mit Zahlen, was fehlt.
   Der nächste sinnvolle Schritt ist **nicht** der ganze Weg, sondern
   die Zero-Page: sie lässt sich bauen und prüfen, ohne dass ein
   einziges Oktett Linux vorhanden sein muss.
2. **Der Entzifferer mit Gast-Paging** (Stufe 5). Unverändert die
   Grenze aus K12 — und jetzt die schärfste, weil jedes echte
   Gastsystem sein Paging sofort einschaltet.
3. **`virtio-blk` und `virtio-net` als Gerät.** Sie brauchen einen
   PCI-Konfigurationsraum, in dem ein Gast sie überhaupt finden kann.
   Dieser Wirt hat keinen.
4. **Die Unterbrechung des Verteilers wird nicht zugestellt.** Der
   8259 führt Maske, Anforderung und Bedienung und sagt auf Verlangen
   den Vektor (`pic_pending`) — aber nichts ruft das im Lauf auf. Ein
   Zeitgeber, der wirklich tickt, fehlt damit.
5. **Ein Kern, mehrere Gäste gleichzeitig.** Unverändert offen.
6. **`kdata` ist voll.** `0x13C000` war der letzte freie Block. Die
   nächste Runde, die eine Seite braucht, muss `KDATA_SIZE` wachsen
   lassen (zwei Stellen: `kernel/arch/x86_64/boot.s` und
   `kernel/lib/kstate.fi` — der Läufer vergleicht beide).

Was **steht**, ist der Unterschied zwischen einem Wirt und einem
Rechner: ein Gast kann jetzt 64 Bit laufen, bekommt so viel Speicher,
wie er braucht, und findet Geräte vor, die auf Fragen antworten statt
zu schweigen.
