# RUNDE TESTFAST -- Stand

Zweig `testfast`, abgezweigt von `mergeline` (e9fcc1c).
Arbeitsbaum: `/root/tf-osum`.

> **Warum nicht `/root/mg-osum`?** Dort ist der Zweig `kvmfix` ausgecheckt
> und es lief beim Start dieser Runde eine volle Abnahme
> (`/tmp/base-tcg.log`). Ein `git checkout` dort haette diesen Lauf
> zerrissen. `git worktree add /root/tf-osum -b testfast mergeline` gibt
> denselben Zweigstand ohne die fremde Runde anzufassen. `mergeline` und
> `main` sind unberuehrt.

---

## Was gebaut ist

### 1. Zentrale Accel-Wahl -- `tools/lib/qemu.sh`

Liefert beim Einbinden zwei Dinge:

| Name | Inhalt |
|---|---|
| `$OSUM_QEMU_ACCEL` | `kvm` oder `tcg` |
| `$QEMU_X86` | `qemu-system-x86_64 -accel <accel>` |

Reihenfolge der Entscheidung:

1. `OSUM_ACCEL=tcg\|kvm` -- ausdruecklicher Wunsch, schlaegt alles.
2. `tools/lib/accel-ausnahmen.txt` -- Abschnitte, die unter KVM fallen.
   Abschaltbar mit `OSUM_ACCEL_FORCE=1` (nur zum Messen).
3. Sonst `kvm`, wenn `/dev/kvm` les- und schreibbar ist **und** die
   QEMU-Binaerdatei `kvm` kennt; andernfalls `tcg`.

Jeder Laeuferlog beginnt jetzt mit einer Zeile
`accel: kvm (/dev/kvm ist da)` -- ohne die ist eine Zeitangabe wertlos.

`$QEMU_X86` ist eine **Variable und keine Shell-Funktion**, weil fast
jeder Aufruf hinter `timeout` steht und `timeout` als externes Programm
keine Shell-Funktion ausfuehren kann.

**Umgestellt: 69 qemu-Starts** -- 56 in den 35 Abnahme-Laeufern,
13 in Hilfsskripten (`speicher`, `ofs3`, `mem`, `desktop`, `i18n`,
`install/oneshot`, `k15/oneshot`, `tresor/gui`, `netview/smoke`; die
stehen nicht in `test.sh` und sind in dieser Runde **nicht gemessen**).

**Nicht angefasst, mit Begruendung im Quelltext:**

| Datei | Warum TCG |
|---|---|
| `tools/hv/run.sh` | testet den eigenen Hypervisor mit `-cpu qemu64,+vmx/+svm`, setzt `-accel tcg` selbst; misst ausdruecklich, dass TCG kein VT-x anbietet |
| `tools/smp/run.sh` | `-accel tcg,thread=single\|multi` **ist** die Messung dieses Abschnitts |
| `tools/arm/run.sh` | `qemu-system-aarch64` auf x86 -- KVM ist dort unmoeglich |

Gegenprobe nach dem Umbau: `grep` findet **keinen** x86-Start mehr ohne
`-accel`, ausser in diesen drei Dateien.

### 2. `test.sh` laeuft parallel

* `OSUM_JOBS` -- wieviele Abschnitte gleichzeitig, Standard `nproc/2` (= 6).
* `OSUM_JOBS=1` -- der alte, streng serielle Weg durch denselben Code.
* `OSUM_ZEIT=0` -- schaltet die Zeitangabe je Abschnitt ab.

Drei Dinge, die dabei schiefgehen konnten, und was dagegen getan ist:

1. **Arbeitsverzeichnisse** -- nachgesehen: alle 34 Laeufer holen sich ihr
   Verzeichnis mit `mktemp -d`, jeder Monitor-Socket liegt darin
   (`$TMPD/mon*.sock`). Kein fester Pfad, um den sich zwei streiten.
2. **Das Netz** -- `net`, `netmon`, `netview` und `tunnel` bauen sich
   Namensraeume und veth-Paare:
   * `net` und `netview` nennen das ferne Ende **beide `v1`**, und
     zwischen `ip link add ... peer name v1` und
     `ip link set v1 netns <ns>` existiert dieser Name **global**.
   * `netmon` und `netview` rechnen ihren Anschluss **beide** als
     `5800 + ($$ % 90) * 2` aus.

   Diese vier laufen untereinander **seriell** ueber `flock`. Die Sperre
   liegt unter `/tmp/osum-netz.lock` und nicht im Arbeitsbaum, weil
   `ip netns` dem **Wirt** gehoert und auf diesem Rechner ueber sechzig
   Arbeitsbaeume desselben Repos stehen. Zu allem anderen laufen die vier
   weiter gleichzeitig. **Entschaerft wird nichts** -- jeder der vier tut
   genau das, was er vorher tat.
3. **Die Ausgabe** -- jeder schreibt in sein eigenes Protokoll; ausgegeben
   wird am Stueck und in der **Reihenfolge des Skripts**. Abschnitt 5
   erscheint vor Abschnitt 6, auch wenn 6 frueher fertig war.

Keine der 35 `lauf "..."`-Zeilen wurde angefasst -- nur die Maschinerie
darum herum. Damit fuehrt sich die Runde `kvmfix` (die genau eine neue
`lauf`-Zeile fuer `tools/kvm/run.sh` einhaengt) konfliktfrei zusammen.

#### Der Scheduler ist mit Stubs geprueft

Sieben Stub-Abschnitte mit bekannten Schlafzeiten (Summe 13 s), einer
faellt absichtlich durch, zwei sind als "Netz" markiert:

| | seriell (`OSUM_JOBS=1`) | parallel (`OSUM_JOBS=4`) |
|---|---|---|
| Gesamtzeit | 13 173 ms | **4 164 ms** |
| Bilanz | `PASS=6 FAIL=1 ZUSAGEN=45` | `PASS=6 FAIL=1 ZUSAGEN=45` |
| Ausgabereihenfolge | 1..7 | **identisch** |
| net/netmon gleichzeitig | -- | **nie** (Zeitspur nachgerechnet) |

---

## Messungen

Wirt: AMD EPYC 7571, `nproc` = 12, 19 GB RAM, `/dev/kvm` 0666.

### Vorprobe (vor dem Umbau, aus dem Auftrag)

Kernelboot, `build-kernel.sh` Stufe 0, `-m 512`, `osum nopwr`, je 3 Laeufe:

| accel | Mittel |
|---|---|
| tcg | 4319 ms |
| kvm | **941 ms** |

### Erste eigene Gegenprobe: `tools/freestanding/run.sh`

| accel | Zeit | Ergebnis |
|---|---|---|
| tcg | 40 407 ms | 41 passed, 0 failed |
| kvm | 40 478 ms | 41 passed, 0 failed |

**Kein Unterschied** -- und das ist kein Widerspruch, sondern die erste
echte Erkenntnis dieser Runde: dieser Abschnitt uebersetzt fast nur
(auf dem Wirt, mit `firnc`) und startet QEMU nur kurz. Wo der Uebersetzer
die Zeit frisst, hilft KVM nichts. Der Hebel wirkt nur dort, wo QEMU
wirklich rechnet. Genau deshalb wird jeder Abschnitt einzeln gemessen
und nicht hochgerechnet.

### Volle Abnahmen

| Lauf | accel | jobs | Zustand |
|---|---|---|---|
| A | tcg | 1 | steht aus |
| B | kvm | 1 | **laeuft** |
| C | kvm | 6 | steht aus |

Die Tabelle Abschnitt fuer Abschnitt (TCG-Zeit, KVM-Zeit, TCG-Ergebnis,
KVM-Ergebnis) kommt aus A und B; C ist die Schlusszahl.

---

## Ausnahmeliste

`tools/lib/accel-ausnahmen.txt` ist **noch leer**. Sie wird aus Lauf B
gefuellt: jeder Abschnitt, der unter KVM rot wird, kommt mit
Begruendung hinein und laeuft vorerst auf TCG.

Parallel laeuft die Runde `kvmfix`, die zwei bekannte KVM-Abstuerze im
Kernel behebt (ein `rdmsr` auf ein Intel-MSR unter AMD; ein
Selektorfehler im `sysret`-Rueckweg). Diese Runde fasst `kernel/` nicht
an -- faellt ein Abschnitt daran, wird er notiert und auf TCG gehalten.

---

## Auflagen

* Kein Test entschaerft, keiner uebersprungen.
* Nur `tools/`, `tests/` und `test.sh` angefasst -- **kein `kernel/`**.
* Nichts nach `main` gemerged, `mergeline` unberuehrt.

---

## ZWISCHENSTAND (Laeufe A und B unterwegs)

### Was sich schon klar zeigt

**1. KVM hilft bei diesem Kernelstand fast nirgends -- nicht weil es
langsam waere, sondern weil der Kernel darunter stehenbleibt.**

Von den ersten 15 Abschnitten unter KVM sind **11 rot**, und sie fallen
ALLE mit demselben Muster:

```
kernel     firnc0: QEMU exit code 63, expected 21
osum       QEMU exit code 63, expected 21
pci        plain machine: exit code 63, expected 21
posix      QEMU exit code 63, expected 21
userland   t1: QEMU exit code 63, expected 21
caps       firnc0: Beendigungscode 63, erwartet 21
boot       firnc0: -kernel endet mit 63, erwartet 21
gfx        der Kern beendet sich sauber: 63, erwartet eq 21
unix       QEMU-Beendigungscode 63, erwartet 21
```

63 heisst laut Kopf von `test.sh`: *der Kernel ist an einer Ausnahme
stehengeblieben*. Es ist **ein** Fehler und nicht neun -- die Ausgabe
bricht jeweils genau dort ab, wo Ring 3 anfaengt (`ring3: syscall ...`
fehlt in allen). Das passt auf den Selektorfehler im `sysret`-Rueckweg,
den die Runde `kvmfix` behebt. Diese Runde fasst `kernel/` nicht an.

**2. Die Zeiten der roten Abschnitte sind als Messwert wertlos.**
Ein Lauf, der nach zwei Sekunden an einer Ausnahme stirbt, ist "schnell";
ein Test, der auf eine Zeile wartet, die nie kommt, laeuft in sein
`timeout` von 180 s. Beides steht in der Tabelle, beides misst nicht die
Geschwindigkeit von KVM. `osum` ist unter KVM sogar **langsamer**
(90,8 s gegen 71,4 s) -- die Zeitgrenzen laufen voll.

**3. Wo KVM nichts bringt, obwohl alles gruen ist.**

| Abschnitt | TCG | KVM |
|---|---:|---:|
| `freestanding` | 40,5 s | 40,5 s |
| `core` | 62,6 s | 62,5 s |
| `boot` | 43,0 s | 42,5 s |

Auf die Millisekunde gleich. Diese Abschnitte verbringen ihre Zeit im
**Firn-Uebersetzer auf dem Wirt**, nicht in QEMU. Die 4,6x aus der
Vorprobe gelten fuer einen Kernelboot, nicht fuer einen Abschnitt.
Deshalb wird hier abschnittsweise gemessen und nicht hochgerechnet.

**Folgerung, die sich abzeichnet:** der grosse Hebel dieser Runde ist die
**Parallelisierung**, nicht KVM. Parallelisierung verkuerzt auch die
Uebersetzerzeit, KVM nicht.

### Noch offen

* Laeufe A (tcg/seriell) und B (kvm/seriell) laufen noch.
* Lauf C (kvm/parallel) danach, mit gefuellter Ausnahmeliste.
* **Gefunden und noch zu beheben:** bei `OSUM_JOBS=1` erscheint die
  Abschnitts-Ueberschrift jetzt NACH dem Lauf statt davor -- beim alten
  Code sah man beim Zusehen, wo man gerade ist. Wird nachgezogen,
  sobald die Messlaeufe test.sh freigeben.
* **Gefunden und schon geschrieben, noch nicht eingebaut:**
  `tools/lib/work-patch.py` -- zwei Abnahmen aus demselben Arbeitsbaum
  ueberschreiben sich gegenseitig `.test-work/<name>.log`. Deshalb laeuft
  Lauf A in einem zweiten Arbeitsbaum (`/root/tf-osum-a`). Mit
  `$OSUM_WORK` geht es kuenftig auch ohne.
