# RUNDE BLECHZWEI — die Stufenmarke, und zwei Fehler aus einem Foto

Vier Fotos von Justins Blech, Menueeintrag **„Schreibtisch (Rahmenpuffer
uncached, Test)"**. Zum ersten Mal steht die Messtafel auf echtem Blech
— und sie aktualisiert sich.

## Was die Fotos sagen

```
Foto A:  8 TAKT IRQ 130 MAL 13 LOOP 0 PRE 1
Foto B:  8 TAKT IRQ 320 MAL 32 LOOP 0 PRE 1
Foto D:  8 TAKT IRQ 610 MAL 61 LOOP 0 PRE 1
         9 KABEL LSR FF SCR FF VERW 0 AUS 1 FB UC
        10 HERZ  HZ 500 TOT 0 LED 0 HELL 3
        11 USB   DEV 2 FUND 5 HUB 0 KBD 0 FAIL 0
```

**Der Zeitgeber lebt.** `IRQ` steigt linear, `MAL` im Verhaeltnis 1:10.
Die Theorie „der oertliche Zeitgeber feuert nicht periodisch" ist damit
**widerlegt** und wird nicht weiterverfolgt.

**Der Rahmenpuffer-Verdacht ist bestaetigt.** Mit `fbuc` erscheint die
Tafel; mit dem Standardeintrag kam sie in drei Runden nie. Das ist die
A/B-Gegenprobe.

**Es gibt keinen UART.** `LSR FF SCR FF` heisst offener Bus, kein
Baustein an 0x3F8; `AUS 1` heisst, die Selbstabschaltung der Runde KABEL
hat gegriffen. Jede serielle Diagnose ist bei Justin wertlos — die
Auflage „alles auf den Schirm" ist damit gemessen begruendet.

## Die Rechnung, die diese Runde erzwungen hat

Zwischen Foto A und Foto B liegt rund **eine Minute**, und der
Markenzaehler steigt um **190**. Das sind **drei Marken je Sekunde statt
hundert** — 97 % der Zeitgeberschlaege gehen verloren, weil der
Behandler noch mit dem vorigen Anstrich beschaeftigt ist.

Denn die Messtafel uebertrug bis zu dieser Runde **582 volle
Bildzeilen**: 582 × 3440 × 4 = **8,0 MB**, zehnmal je Sekunde, aus dem
Zeitgeberbehandler, mit abgeschalteten Unterbrechungen.

**Gemessen**, Vollbild-Blit, derselbe Kern, drei Betriebsarten
nacheinander, Seitentafeleintrag jeweils zurueckgelesen:

| Betriebsart | `flush` Vollbild | PDE | PAT-Stelle 4 |
|---|---|---|---|
| **write-combining** (Vorgabe) | **1 751 µs** | `10E3` | `01` |
| write-back (`fbwb`) | 3 402 µs | `00E3` | `06` |
| uncached (`fbuc`) | **396 531 µs** | `00FB` | `06` |

**UC ist 226-mal langsamer als WC.** Und QEMU hat gar keine
Zwischenspeicher-Semantik — auf echtem Blech ist jeder Vierbyte-Wert
eine eigene Bustransaktion, der Abstand ist also eher groesser. Damit
ist `LOOP 0` im UC-Eintrag kein Raetsel mehr, sondern eine Folge: der
Rechner verbringt seine Zeit damit, sein eigenes Messgeraet zu malen.

## Zwei echte Fehler, beide aus den Fotos

### 1. `fb.flush()` hatte im einfachen Pfad kein `sfence`

Die Vorrunde hat den Zaun an `flush_stripe` gehaengt und **diesen Pfad
uebersehen**. WC-Schreibzugriffe sind schwach geordnet; ohne Zaun steht
eine kleine Aenderung erst dann auf dem Schirm, wenn zufaellig genug
nachkommt.

Justins Brett faehrt im **Streifenbetrieb** (19,8 MB Puffer gegen ein
Fenster von 8 × 2 MiB), bei ihm lief also der andere Pfad. Auf
1920×1080 ist es genau dieser.

### 2. Ein Fenster, zwei Schreiber — Justins Doppelbild

`flush_stripe` biegt **ein** Fenster von 2 MiB nacheinander auf jeden
Block des Rahmenpuffers um. Die Messtafel laeuft seit der Runde HAENGER
**aus dem Zeitgeberbehandler** und ruft denselben Weg.

Trifft die Unterbrechung eine Aufgabe **zwischen `slot_remap` und
`copy_words`**, biegt sie das Fenster auf einen anderen Block — und die
Aufgabe schreibt ihren Streifen danach **an die falsche Stelle im
Bildspeicher**. Genau so sieht das aus: Bruchstuecke einer alten Zeile
mitten in einer neuen.

Umbiegen und Kopieren stehen jetzt zusammen unter `arch.irq_save`.

## Die Stufenmarke — die Antwort auf `LOOP 0`

`tafel_loop` wird an genau einer Stelle erhoeht (`kopf_malen`), und
`kopf_malen` wird an genau einer Stelle gerufen (im Rumpf von
`wait_wm`). Die erste Erhoehung passiert schon beim **ersten** Aufruf.
`LOOP 0` heisst deshalb hart: **diese Zeile wurde nie erreicht.**

Also 31 Marken: durch die ganze Startfolge und durch **jeden Schritt**
des `wait_wm`-Rumpfs. Zeile 12 der Tafel zeigt sie:

```
12 STUFE ST 38 MAX 38 RND 4967 LOOP 511
```

| Stufe | wo der Kern steht |
|---|---|
| 10 / 18 / 19 | erstes Standbild / vor und nach dem USB-Bericht |
| 20 / 21 / 22 | zweites Standbild / `i18n_bench` / `desk_start` |
| 24 / 25 / 26 | vor `shell_start` / danach / vor `wait_wm` |
| 30 | vor der Schleife |
| **32 / 33** | `usb.poll` / `usb.hotplug_work` |
| **34 / 35** | `wm.poll` / **`wm.compose`** |
| 36 / 37 / 38 | `kopf_malen` / der Puls / `sleep_ticks` |
| 40 | `wait_wm` ist zurueckgekehrt |

`ST` ist der zuletzt erreichte Schritt, `MAX` der hoechste ueberhaupt
erreichte, `RND` die Rundenzahl der Schleife. Stehen `ST` und `MAX` auf
derselben Zahl und `RND` bleibt null, **haengt es genau an dieser
Zeile**. Das ist der Unterschied zwischen einer Vermutung und einer
Adresse.

## Zeile 13: die Abbildung, aus der Seitentafel gelesen

Bis zu dieser Runde stand `FB WC` auf der Tafel — und das war eine
**Absicht** (`S_WC`), keine Messung. Jetzt wird der echte
Seitentafeleintrag zurueckgelesen:

```
13 ABBILD PDE 10E3 PAT 01 KCH 1
```

* `PDE 00E3` → **write-back**, der stille Fall
* `PDE 10E3` → **write-combining** (Bit 12, die PAT-Stelle)
* `PDE 00FB` → **uncached** (Bit 3 PWT und Bit 4 PCD)
* `PAT` ist Oktett 4 des MSR 0x277 und **muss 01 sein**, sonst ist das
  PAT-Bit oben wirkungslos
* `KCH` sind die 2-MiB-Kacheln; mehr als acht heisst Streifenbetrieb

Die Zeile ist gruen, wenn die Seitentafel wirklich WC oder UC sagt, und
**rot bei write-back**.

## Die Tafel kostet jetzt ein Fuenfzigstel

* `fb.flush_rect` uebertraegt nur das **Textrechteck** (780 × 48) statt
  voller Bildzeilen (3440 × 582).
* Die Tafel malt nur noch Zeilen, die sich **wirklich geaendert** haben.
* **Aber**: hat der Fensterserver seit dem letzten Anstrich
  zusammengesetzt, wird alles neu gemalt. Das war noetig und ist
  gemessen — im ersten Lauf standen nur die halben Zeilen da (`y=5` und
  `y=400` schwarz mit Schrift, `y=100` und `y=200` Schreibtischgrund),
  weil `compose` seinen Grund darueber malt. Nach der Korrektur: **11
  von 11 Zeilen bedeckt.**
* `wm.messzeile` loescht ihr eigenes Feld unmittelbar vor dem Malen —
  gegen das Doppelbild.

## KBD und LED: zwei Zaehler, ein Wort

Die Tafel sagte `KBD 0`, die USB-Diagnose `kbd=1 drv=1`. **Beide hatten
recht**: `KBD` zaehlte die *Tastenereignisse*, die Diagnose meinte das
*Geraet*. Jetzt getrennt:

```
11 USB   DEV 2 FUND 2 HUB 0 KBD 1 TAS 0 FAIL 0
10 HERZ  HZ 7000 TOT 0 LED 139/139/0 HELL 140
```

`KBD` = das Geraet (Platz + 1, 0 = keines), `TAS` = angekommene Tasten,
`LED ok/Versuche/Fehler`. `LED 0` allein war zweideutig — keine
Tastatur, oder Tastatur da und der Steuertransfer scheitert. Mit drei
Zahlen ist es eindeutig.

Dazu: `SET_REPORT` laeuft nicht mehr zweimal gleichzeitig auf dem
Steuerungsring desselben Steckplatzes (`S_LEDBUSY`) — `herz_leds` kommt
aus dem Zeitgeber, `led_service` aus der Meldung des Geraets.

## Was ich NICHT behaupte

* Ob Write-Combining auf **Justins** Brett wirklich greift, ist
  ungemessen. In QEMU steht `PDE 10E3 PAT 01`; auf seinem Brett hat es
  noch nie ein Foto gegeben, weil die Tafel im WC-Eintrag nie kam.
  **Zeile 13 beantwortet das jetzt mit einem Foto.**
* Ob `LOOP 0` allein an den Kosten des UC-Anstrichs lag, ist ungemessen.
  Die Rechnung passt (drei Marken je Sekunde statt hundert), aber
  **Stufe 12 sagt es genau**, statt dass ich es herleite.
