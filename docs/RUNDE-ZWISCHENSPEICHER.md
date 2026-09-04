# RUNDE ZWISCHENSPEICHER — der Rahmenpuffer war write-back abgebildet

Justins Rechner hat **keine eingebaute Grafik**. Der Rahmenpuffer ist ein
PCIe-Fenster der RTX 3060, kein Systemspeicher. Und er war bis zu dieser
Runde **write-back** abgebildet.

## Der Befund, Zeile fuer Zeile

1. `kernel/fb.fi` `map_run` und `slot_remap`: die Seitenbits waren
   `PAGE_PRESENT | PAGE_WRITE | PAGE_HUGE`. `PAGE_PCD | PAGE_PWT` kamen
   **nur** dazu, wenn `uncached` gilt — und das haengt an `M_UC`, dem
   Wort `fbuc`.
2. `grep fbuc tools/usbimg/build.sh` → **0 Treffer**. Auf keinem
   Menueeintrag stand `fbuc`.
3. `grep '0x277\|wbinvd\|clflush'` ueber `kernel/` → **nichts**. Das
   PAT-MSR wurde nie programmiert, es gab kein `wbinvd`, kein `clflush`.
4. `fb.flush_stripe` kopierte mit `copy_words` und machte danach
   **weder** einen Zwischenspeicher-Flush **noch** ein `sfence`.

**Alle vier bestaetigt.**

## Warum das Justins Foto genau erklaert

Ein Schreibzugriff in einen WB-abgebildeten MMIO-Bereich landet in der
Zwischenspeicherhierarchie der CPU und geht erst dann ueber PCIe zur
Karte, wenn die Zeile **verdraengt** wird. Niemand erzwingt das.

* Das **erste Vollbild** ist 3440·1440·4 = **19,8 MB** — groesser als
  jeder L3. Es verdraengt sich selbst und wird sichtbar. Genau das sieht
  Justin: blauer Grund, Mauszeiger.
* Jede **spaetere Aenderung** ist klein (Taskleiste, Messtafel, ein
  Terminalfenster, der Zeiger). Sie passt bequem in den
  Zwischenspeicher, wird nie verdraengt — und erscheint **nie**.
* Der Kern laeuft dabei voellig gesund weiter. Deshalb meldet die
  Taskleiste `rc=0`, deshalb liefen die 453 Anstriche der Vorrunde
  wirklich, und deshalb war trotzdem keiner zu sehen.
* In QEMU faellt es nie auf: dort ist der Rahmenpuffer gewoehnlicher
  Systemspeicher.

## Was gebaut wurde

### Write-Combining als Vorgabe (B)

`fb.pat_setup` programmiert **IA32_PAT (MSR 0x277), Stelle PA4, auf
WC (0x01)** und **liest zurueck** — die Stellen 0 bis 3 bleiben
unveraendert, damit jede bestehende Abbildung ihre Bedeutung behaelt.
Bei 2-MiB-Seiten ist die PAT-Stelle **Bit 12** (`PAGE_PAT_HUGE`), also
PAT=1, PCD=0, PWT=0 → Index 4.

Die Seitenbits stehen jetzt an **einer** Stelle (`fb_bits`) statt
doppelt in `map_run` und `slot_remap` — genau so eine Verdopplung ist
der Grund, warum eine Betriebsart an einer Stelle greift und an der
anderen nicht.

`fb.flush_stripe` endet mit `arch.barrier_write()` (`sfence`).
WC-Schreibzugriffe sind schwach geordnet und sammeln sich in den
Schreibpuffern; ohne das steht ein Streifen erst auf dem Schirm, wenn
zufaellig genug nachkommt.

Klappt das Umprogrammieren nicht, bleibt es beim alten Verhalten, und
`wc=0` steht in der `fb:`-Zeile und auf der Tafel.

**Ehrlich gesagt:** das Handbuch verlangt fuer eine PAT-Aenderung im
Betrieb eine laengere Folge (Zwischenspeicher aus, spuelen, TLB leeren).
Hier steht sie vor der ersten Abbildung des Rahmenpuffers und vor jedem
Bild, danach wird CR3 neu geladen. Auf mehreren Kernen muesste jeder
Kern sie ausfuehren; dieser Kern malt nur auf dem Startprozessor.

### Der Gegenprobe-Eintrag (A)

`OrientOS -- Schreibtisch (Rahmenpuffer ohne Zwischenspeicher)` mit
`fbuc`. Das groebste Mittel: PCD|PWT, jeder Bildpunkt einzeln auf den
Bus. Langsam, aber es kann per Bauart nichts liegenbleiben.

Dazu `fbwb`, das WC ausdruecklich **nicht** einschaltet — damit laesst
sich der Unterschied messen statt behaupten.

### Die Messung (D)

`fbbench`, 3440x1440, gleicher Kern, gleiche Maschine:

| Betriebsart | `flush` (Vollbild-Blit) | `fill` | `line` | Schleifenrunden in 45 s |
|---|---|---|---|---|
| **WC** (neue Vorgabe) | **1 759 µs** | 1 926 µs | 555 µs | **123** |
| WB (bisher, `fbwb`) | 4 606 µs | 2 769 µs | 646 µs | 103 |
| UC (`fbuc`) | **200 148 µs** | 2 012 µs | 4 982 µs | **0** |

**WC ist 2,6-mal schneller als WB und 114-mal schneller als UC.**
UC schafft in 45 Sekunden **keine einzige** volle Schreibtischrunde.

**Was diese Zahlen NICHT sagen:** sie sind in QEMU gemessen, wo der
Rahmenpuffer emulierter Speicher ist. Die absoluten Werte gelten nicht
fuer ein PCIe-Fenster. Was uebertraegt, ist die Reihenfolge:
WC ≈ WB ≫ UC, und dass WC nichts kostet.

### `back=` (E)

Gemessen am veroeffentlichten Abbild unter OVMF:

```
fb: 3440x1440x32  pitch=13760  src=mb  phys=0x80000000  back=0x2900000  uc=0
```

**`back=` ist gesetzt**, nicht `none` — der Zweitpuffer existiert, das
war in einer frueheren Runde behoben. `uc=0` bestaetigt die
WB-Abbildung.

## Was jetzt auf der Tafel steht

```
8 TAKT   IRQ 4700 MAL 595 LOOP 123 PRE 1
9 KABEL  LSR 60 SCR A5 VERW 0 AUS 0 FB WC
```

`FB WB` bei `uc=0` heisst: kleine Aenderungen bleiben im
Zwischenspeicher. `FB WC` heisst, dass PAT steht — **zurueckgelesen**,
nicht beabsichtigt.

## Und die zwei Befunde davor

**PREEMPT — Justin hat recht, ich hatte unrecht.** Meine Erklaerung
„`nosched` schaltet die Verdraengung ab" war falsch. `nosched` setzt nur
`M_NOSCHED`, ausgewertet in `kmain.scheduler()` — dem Selbsttest mit den
drei `K_WORKER`n. `sched.init` steht in `kmain.fi:387`, im Hauptpfad,
und setzt `PREEMPT` auf 1. `M_NOPREEMPT` steht **hinter** dem
`nosched`-Return und wird nie erreicht.

**Gemessen, nicht gelesen:** `PRE 1` auf der Tafel. Die Verdraengung ist
eingeschaltet.

**Der UART bleibt behoben.** `serial.put` wartete unbegrenzt auf das
THR-Empty-Bit, und `gfx.echo` stand **dahinter** — der Bildschirm hing
am Kabel. Jetzt: `gfx.echo` **zuerst**, dann eine Zeitgrenze
(`PUT_GRENZE`), Selbstabschaltung nach 16 verworfenen Oktetten, und ein
Praesenztest ueber das Notizregister (`probe`, 0xA5 hin und zurueck).
Dazu der Schalter `noserial`.

In QEMU gemessen: `LSR 60 SCR A5 VERW 0 AUS 0` — dort sitzt ein
Baustein, wie erwartet. **Auf Justins Brett ist das offen**, und genau
dafuer steht die Zeile jetzt auf dem Schirm: `LSR 00` waere der Beweis,
`LSR 60` die Widerlegung.
