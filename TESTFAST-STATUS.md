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
