# Runde K10 — die zwei Schutzbits und das Boot-Modul

**Stand: 26.08.2026.** Diese Runde hat nichts erfunden. Sie holt die
letzten zwei Fähigkeiten aus OrientOS' Rust-Kernel herüber, die Osum noch
nicht hatte, und misst sie nach.

| Aus OrientOS (Rust) | Nach Osum (Firn) | Zeilen |
|---|---|---:|
| `kernel/src/arch/x86_64/user.rs` — SMEP/SMAP in CR4, `stac`/`clac` | `kernel/guard.fi` | 328 |
| `kernel/src/kcore/initramfs.rs` — Boot-Modul + CRC32 | `kernel/bootmod.fi` | 251 |

Beide standen in OrientOS' `KERNELWECHSEL.md` § 4 als **offen**. Sie
waren die letzten zwei Punkte, an denen der Rust-Kernel noch etwas
konnte, was dieser hier nicht konnte.

Abnahme: `bash tools/guard/run.sh` → **55 Zusagen, 0 Fehler**;
`./test.sh` Abschnitt 15.

---

## 1. Warum das nicht zwei Runden sind

Beide sind klein, beide hängen an derselben Frage — *was nimmt ein
Kernel von außen entgegen, und was davon darf er anfassen?* — und beide
brauchen dieselbe Art Gegenprobe: einmal **mit** und einmal **ohne** die
Sache selbst, sonst misst der Nachweis nichts.

---

## 2. SMEP und SMAP

### Was die beiden Bits tun, und warum NX sie nicht ersetzt

**SMEP** (CR4 Bit 20). Ring 0 darf keinen Befehl mehr aus einer Seite
holen, deren Benutzerbit gesetzt ist. Das ist die Abwehr gegen die
älteste Rechteausweitung überhaupt: ein Kernelzeiger wird verbogen,
zeigt auf Code, den das unprivilegierte Programm selbst geschrieben hat,
und dieser Code läuft dann in Ring 0. **NX hilft dagegen nicht** — die
Seite des Programms ist ja *absichtlich* ausführbar, nur eben für Ring 3.

**SMAP** (CR4 Bit 21). Ring 0 darf unprivilegierte Daten nur noch in
einem ausdrücklich geöffneten **Fenster** lesen und schreiben (`stac`
auf, `clac` zu — das Fenster ist das AC-Bit in den Flags). Damit wird aus
„der Kernel hat aus Versehen einen Nutzerzeiger dereferenziert" ein
sofortiger, lokalisierbarer `#PF` statt eines stillen Datenlecks.

### Wo das Fenster steht

Genau **vier Stellen** in diesem Kernel greifen auf Speicher zu, den
Ring 3 sehen darf, und alle vier gehen über `proc.translate` und die
Identitätsabbildung:

* `sys.peek`, `sys.poke` — ein Oktett aus dem Adressraum des Prozesses,
* `sys.copy_in`, `sys.copy_out` — seitenweise hin und her.

Dazu die eine Stelle, an der ein Signalrahmen auf den **Nutzerstapel**
gelegt wird: `signal.poke64` / `signal.peek64`.

Das Fenster steht dabei um die **Seite**, nicht um das einzelne Oktett:
`stac`/`clac` je Oktett wären zwei Befehle auf jeden kopierten Wert, und
ein Fenster, das eine Seite lang offen ist, ist immer noch ein Fenster.

### CR4 ist pro Prozessor

Ein zweiter Prozessor, der über `smp.s` hochkommt, hat die Bits nicht —
sein Trampolin setzt PAE und sonst nichts. `guard.apply_here` zieht sie
in `smp.ap_main` nach und **liest CR4 danach zurück**; gezählt wird nur,
wer sie wirklich stehen hat. Unter `-smp 4`: `guard: aps=3`.

Ein Kernel, der nur auf einem von vier Kernen geschützt ist, ist nicht
geschützt.

### Die Gegenproben

| Kommandozeile | Erwartet | Gemessen |
|---|---|---|
| `-cpu max` | CR4 = `0x300020`, `smep=1 smap=1` | ✔ |
| QEMU-Vorgabe (`qemu64`) | CR4 = `0x20`, `smep=0 smap=0`, Lauf endet trotzdem mit 21 | ✔ |
| `smapraw` mit SMAP | `#PF err=0x1`, Beendigungscode **63** | ✔ |
| `smapraw nosmap` | kommt zurück, liest `got=0x5a`, Code **21** | ✔ |
| `smepraw` mit SMEP | `#PF err=0x11` (Bit 4 = **Instruktionsabruf**), Code **63** | ✔ |
| `smepraw nosmep` | `smep: came back (!)`, Code **21** | ✔ |
| `caps` mit SMAP | `windows=312`, 2× `caps: 18/18 proofs` | ✔ |
| `caps nosmap` | `windows=0`, trotzdem 2× `18/18` | ✔ |

Der Unterschied zwischen dem Lauf, der stehenbleibt, und dem, der
durchläuft, ist **ein Bit in CR4**. Das ist der ganze Nachweis.

**`windows=` ist keine Kosmetik.** Eine Zusage „SMAP ist an" wäre
wertlos, solange niemand nachweist, dass der Kernel das Fenster
überhaupt benutzt — ein Kernel, der Ring-3-Speicher nie anfasst, hätte
dieselbe Zusage und könnte keine Systemaufrufe.

### Was auf einem Prozessor ohne die Bits passiert

Nichts. `guard.stac`/`guard.clac` sind dann ein Vergleich und ein Sprung;
`stac` ohne CR4.SMAP wäre ein `#UD` im Kernel, deshalb steht die Abfrage
davor und nicht daneben. Die vierzehn übrigen Abschnitte von `./test.sh`
laufen ohne `-cpu max` und messen deshalb genau das, was sie vorher
gemessen haben — **Zeile für Zeile dieselben Zahlen**.

---

## 3. Das Boot-Modul

### Warum das fehlte

Osum hat drei Blockgeräte (`blk.fi`): RAM-Platte, ATA, NVMe. Sein
Userland liegt in einem OFS-Dateisystem auf einer Platte, die QEMU mit
`-drive` hereinreicht. **Ein ISO hat keine solche Platte.** Was ein Lader
dort weiterreichen kann, ist ein *Modul*. Ohne Modulunterstützung kann
ein ISO nur einen Kern tragen, kein Userland — genau der Unterschied, den
OrientOS' `KERNELWECHSEL.md` § 4.4 benannt hat.

### Was ein Modul ist

Multiboot 1, Spezifikation 3.3: Flag-Bit 3 sagt, dass `mods_count`
(Offset 20) und `mods_addr` (Offset 24) gelten. Dahinter eine Tabelle von
je 16 Oktetten: Anfang, Ende, Zeichenkette, reserviert. Mehr nicht. Der
Lader legt die Datei irgendwo in nutzbaren Speicher und nennt die beiden
Adressen — er sagt nicht, was drin ist, und er prüft nichts.

Für `fs.fi` ändert sich dabei **nichts**: es sind dieselben 512 Oktette
je Block, nur aus einem anderen Gerät. Genau dafür gibt es die
Schnittstelle in `blk.fi`.

### Die Prüfsumme

Der Weg vom Bauplatz zum Kern geht über ein Abbildformat, ein Bootmedium,
eine Firmware und einen Lader. Ein einzelnes gekipptes Oktett im
Programmtext fällt sonst erst als unerklärlicher Absturz im
unprivilegierten Programm auf — der Fehler ist dann vier Schichten von
seiner Ursache entfernt.

`crc32` (IEEE, reflektiert, tabellenlos, dasselbe Polynom wie in
OrientOS' `initramfs.rs`) läuft über das **ganze** Modul, **bevor** der
erste Block davon gelesen wird, und wird gegen `modcrc=<8 Hexziffern>`
gehalten. Passt es nicht, wird das Modul **nicht** benutzt — und das
steht im Protokoll, statt still zu passieren.

Ohne Vorgabe ist die Summe eine **Angabe**, mit Vorgabe eine
**Bedingung**.

### Ein Modul, das niemand angefordert hat, wird nicht zur Wurzel

`bootmod.ready` sagt nur dann ja, wenn **alle drei** zutreffen: es gibt
ein Modul, seine Summe stimmt, und die Kommandozeile enthält `modfs`.

### Der Bereich gehört dem Modul

Der Lader legt das Modul in Speicher, den die Speicherkarte als
**nutzbar** führt — und `mem.scan` gibt genau diese Rahmen an den
Rahmenverwalter. Ohne ein `reserve` bekommt der nächste Anforderer das
Userland-Abbild und schreibt darüber; der Fehler zeigt sich erst viel
später, in einem Programm, das nicht mehr lädt.

`mem.scan` nimmt deshalb den Bereich jedes Moduls und die Modultabelle
selbst zurück. **Die Gegenprobe dazu ist `bootmod.recheck`:** am Ende
eines Laufs, in dem Prozesse gestartet, Seiten abgebildet und die Halde
benutzt wurden, wird die Summe **noch einmal** gerechnet.

```
mod: base=0x227000  bytes=2097152  blocks=4096  crc=0x855e7b04  want=0x855e7b04  ok=1
osum: from module 0x227000  blocks=4096
osum: mount=1
sh: ready, osum
osum$ ls /bin
./ ../ sh ls cat echo wc grep uname true false
osum: sh exit=0
osum: frames_free=129909 of 129909
guard: aps=0  windows=109
mod: recheck crc=0x855e7b04  same=1
```

Dieselbe Shell, dieselben Werkzeuge, dieselben Systemaufrufe — nur liegt
die Wurzel jetzt in einer Datei, die der Lader danebengelegt hat. Und das
alles mit **SMEP und SMAP an**.

---

## 4. Was diese Runde NICHT gemacht hat

* **Mehr als ein Modul.** `mods_count` wird gelesen und jedes Modul im
  Rahmenverwalter reserviert, aber nur Modul 0 wird zur Platte. Ein
  zweites hätte im Augenblick keinen Zweck.
* **Ein Archivformat.** OrientOS' `IRFS0002` hatte eine Prüfsumme *je
  Eintrag*; hier steht **ein** OFS-Abbild im Modul und **eine** Summe
  darüber. Das ist weniger fein und dafür dasselbe Dateisystem, das der
  Kernel ohnehin hat — kein zweiter Leser, kein zweites Format.
* **Ein Modul, das beschrieben wird.** Das Dateisystem im Modul ist
  schreibbar wie jede RAM-Platte, aber die Änderungen überleben den Lauf
  nicht. Für eine Wurzel, die überlebt, gibt es die ATA- und die
  NVMe-Platte.
* **Die arch-Grenze.** OrientOS' `kcore/arch_iface.rs` — die
  Architekturgrenze als Traits — ist **nicht** portiert. Das ist eine
  Umbauarbeit an jedem Modul dieses Kernels, keine Portierung. Sie bleibt
  offen und steht in `README.md` unter „Was er nicht kann".
* **Kanäle, Ports, Namensräume.** Die nativen Aufrufe dafür existieren
  in `sys.fi` und antworten `NotSupported` (−9). Das Handle-Modell
  darunter ist portiert (`cap.fi`); die Objekte, die daran hängen, sind
  es nicht.
