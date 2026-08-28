# RUNDE TESTFAST -- Stand 28.08.2026, 11:50

Zweig `testfast`. Abgezweigt von `mergeline` bei `e9fcc1c`, seit 11:44 mit
dem aktuellen `mergeline` (`4f844b5`, enthaelt die Runde `kvmfix`)
zusammengefuehrt -- **konfliktfrei**, siehe unten.
Arbeitsbaeume: `/root/tf-osum` (Hauptbaum), `/root/tf-osum-a` (zweiter
Messbaum), `/root/tf-vor` (Gegenprobe auf reinem `mergeline`).

`main` und `mergeline` sind unberuehrt. Nichts gepusht ausser `testfast`.

---

## DAS WICHTIGSTE IN DREI SAETZEN

1. Die Parallelisierung von `test.sh` steht, ist mit einer eigenen
   Pruefung im Repo belegt (`tools/lib/sched-pruef.sh`, alles gruen) und
   ist der Hebel, der immer wirkt.
2. KVM hat auf dem Kernelstand `e9fcc1c` **zwanzig von dreissig
   Abschnitten rot gemacht** und die Abnahme dabei sogar VERLANGSAMT
   (5449 s gegen 5186 s) -- weil abstuerzende Kernel in ihre Zeitgrenzen
   laufen. Ursache waren genau zwei Kernelfehler, hier unabhaengig mit
   Registern belegt.
3. Diese zwei Fehler hat die Runde `kvmfix` behoben; ihr Ergebnis steht
   seit `60d3509` in `mergeline`. Nach dem Hereinholen laeuft derselbe
   Kernel unter KVM wieder sauber durch (`exit 21`, `kernel: done`) und
   ist dabei **2,2x schneller** als unter TCG. Die Ausnahmeliste ist
   damit von fuenfundzwanzig Eintraegen auf **null** geschrumpft.

---

## Was gebaut ist

### 1. Zentrale Accel-Wahl -- `tools/lib/qemu.sh`

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

Jeder Laeuferlog beginnt mit `accel: kvm (/dev/kvm ist da)` -- ohne diese
Zeile ist eine Zeitangabe wertlos, und die Messtabelle liest sie aus.

`$QEMU_X86` ist eine **Variable und keine Shell-Funktion**, weil fast
jeder Aufruf hinter `timeout` steht und `timeout` als externes Programm
keine Shell-Funktion ausfuehren kann.

**Umgestellt: 69 qemu-Starts** -- 56 in den Abnahme-Laeufern, 13 in
Hilfsskripten, die nicht in `test.sh` stehen und darum in dieser Runde
auch nicht gemessen sind.

**Nicht angefasst, mit Begruendung im Quelltext:**

| Datei | Warum |
|---|---|
| `tools/hv/run.sh` | testet den eigenen Hypervisor mit `-cpu qemu64,+vmx/+svm`, setzt `-accel tcg` selbst |
| `tools/smp/run.sh` | `-accel tcg,thread=single\|multi` **ist** die Messung dieses Abschnitts |
| `tools/arm/run.sh` | `qemu-system-aarch64` auf x86 -- KVM dort unmoeglich |
| `tools/kvm/run.sh` | kam mit `kvmfix` herein und waehlt sein `-accel` selbst; dieser Abschnitt IST der Vergleich |

Gegenprobe: `grep` findet **keinen** x86-Start mehr ohne `-accel` ausser
in diesen vier Dateien.

### 2. `test.sh` laeuft parallel

* `OSUM_JOBS` -- wieviele Abschnitte gleichzeitig, Standard `nproc/2`.
* `OSUM_JOBS=1` -- der alte, streng serielle Weg durch denselben Code,
  inklusive der Ueberschrift **vor** dem Lauf (siehe "behobene Regresse").
* `OSUM_ZEIT=0` -- schaltet die Zeitangabe je Abschnitt ab.
* `OSUM_NUR='<regex>'` -- nur passende Abschnitte, zum Nachmessen
  einzelner Faelle. Die Schlussbilanz sagt dann ausdruecklich, dass sie
  **nicht als Abnahme gilt** und wieviele Abschnitte fehlen.
* `OSUM_WORK=<pfad>` -- wohin die Protokolle je Abschnitt gehen.

Drei Dinge, die schiefgehen konnten, und was dagegen getan ist:

1. **Arbeitsverzeichnisse** -- nachgesehen: alle Laeufer holen sich ihr
   Verzeichnis mit `mktemp -d`, jeder Monitor-Socket liegt darin. Kein
   fester Pfad, um den sich zwei streiten koennten.
2. **Das Netz** -- `net`, `netmon`, `netview` und `tunnel` bauen sich
   Namensraeume und veth-Paare:
   * `net` und `netview` nennen das ferne Ende **beide `v1`**, und
     zwischen `ip link add ... peer name v1` und
     `ip link set v1 netns <ns>` existiert dieser Name **global**.
   * `netmon` und `netview` rechnen ihren Anschluss **beide** als
     `5800 + ($$ % 90) * 2` aus.

   Diese vier laufen untereinander **seriell** ueber `flock`. Die Sperre
   liegt unter `/tmp/osum-netz.lock` und **nicht** im Arbeitsbaum, weil
   `ip netns` dem Wirt gehoert und auf diesem Rechner ueber sechzig
   Arbeitsbaeume desselben Repos stehen. Waehrend der Messungen liefen
   zeitweise vier Abnahmen aus vier Baeumen gleichzeitig -- die Sperre
   hat sichtbar gehalten. **Entschaerft wird nichts.**
3. **Die Ausgabe** -- jeder schreibt in sein eigenes Protokoll; ausgegeben
   wird am Stueck und in der **Reihenfolge des Skripts**.

Keine der `lauf "..."`-Zeilen wurde angefasst -- nur die Maschinerie
darum herum. **Das hat sich ausgezahlt:** der Merge von `mergeline`
(inklusive der neuen `lauf`-Zeile fuer `tools/kvm/run.sh`) lief
**konfliktfrei** durch, `test.sh` bekam genau `+1` Zeile.

### 3. Die Parallelmaschinerie ist gepruefft -- `tools/lib/sched-pruef.sh`

Sieben Stub-Laeufer mit bekannten Schlafzeiten, einer faellt absichtlich
durch, zwei liegen unter `tools/net/` und `tools/netmon/`. Die Pruefung
**schneidet die Maschinerie aus `test.sh` heraus** statt sie zu kopieren
-- faellt sie durch, ist `test.sh` kaputt und nicht die Pruefung.

```
  seriell (OSUM_JOBS=1): 13201 ms
  parallel (OSUM_JOBS=4):  4198 ms
  OK    parallel ist schneller als seriell
  OK    beide Wege liefern dieselbe Bilanz (PASS=6 FAIL=1 ZUSAGEN=45)
  OK    die Ausgabereihenfolge ist identisch
  OK    die zwei Netz-Abschnitte ueberschnitten sich nie (Zeitspur nachgerechnet)
  OK    der absichtlich rote Stub ist in beiden rot
SCHED: alles gruen
```

Beim ersten Lauf war sie **rot** -- die Netz-Stubs hiessen `tools/nets3/`
und trafen das Sperrmuster `^tools/(net|netmon|netview|tunnel)/` nicht.
Ein Fehler in der Pruefung, nicht in `test.sh`, aber er zeigt, dass die
Pruefung wirklich prueft.

---

## DIE ZWEI KVM-FEHLER -- unabhaengig reproduziert

Derselbe Kernel (`build-kernel.sh` Stufe 0), dieselbe Kommandozeile,
**nur `-accel` anders**. Protokolle unter `.mess/diag-*.txt`.

### Fehler 1 -- `rdmsr` auf ein Intel-MSR

```
*** EXCEPTION 13 #GP  err=0x0
  rip=0x131ef5  cs=0x8  rflags=0x10246  rsp=0x4ccd60
  rax=0x1a2   rcx=0x1a2   rdx=0x0
```

`rcx` ist bei `rdmsr` der MSR-Index, `0x1A2` ist
`IA32_TEMPERATURE_TARGET` -- ein Register, das es **nur bei Intel** gibt.
Der Wirt ist ein **AMD EPYC 7571**. TCG reicht unbekannte MSRs gutmuetig
durch, KVM tut, was echte Hardware tut: `#GP`.

### Fehler 2 -- der Selektor im `sysret`-Rueckweg

```
qemu ... -append "osum nokbd nopwr"
*** EXCEPTION 13 #GP  err=0x20
  rip=0x1002af  cs=0x8  rflags=0x10006
  rbx=0x40006474  rsi=0x40006211  rbp=0x40006178
```

Der Fehlercode eines `#GP` ist bei einem Selektorfehler der Selektor
selbst: `0x20` = GDT, Eintrag 4. `rbx`/`rsi`/`rbp` zeigen auf
`0x4000xxxx`, also Ring-3-Adressen -- der Kernel ist auf dem **Rueckweg
nach Ring 3**.

Beides ohne eine Zeile in `kernel/` zu aendern. Es sind genau die zwei
Fehler, die `kvmfix` angekuendigt und behoben hat.

---

## MESSTABELLE 1 -- VOR `kvmfix` (Kernelstand `e9fcc1c`)

Wirt: AMD EPYC 7571, `nproc` = 12, 19 GB RAM, `/dev/kvm` 0666.
Beide Laeufe seriell (`OSUM_JOBS=1`), in getrennten Arbeitsbaeumen,
gleichzeitig -- die Zeiten sind daher gegeneinander fair, aber
gegenueber einem ruhigen Wirt ueberhoeht.

Die vollstaendige Tabelle mit allen 36 Abschnitten steht in
`.mess/tabelle-vor-kvmfix.md`. Das Ergebnis in Zahlen:

| | TCG (Lauf A) | KVM (Lauf B) |
|---|---:|---:|
| Summe der Abschnittszeiten | **5186 s** | **5449 s** |
| unter KVM rot geworden | -- | **20 von 30** |

**KVM war LANGSAMER.** Nicht, weil KVM langsam waere, sondern weil ein
Kernel, der an einer Ausnahme stehenbleibt, seinen Test in die
Zeitgrenze laufen laesst. Die deutlichsten Faelle:

| Abschnitt | TCG | KVM | |
|---|---:|---:|---|
| `k11` | 168,8 s | 602,7 s | 3,6x **langsamer**, rot |
| `wm` | 129,1 s | 409,6 s | 3,2x **langsamer**, rot |
| `netview` | 652,1 s | 1285,0 s | 2,0x **langsamer**, rot |
| `k17` | 134,5 s | 290,9 s | 2,2x **langsamer**, rot |

Und die Gegenrichtung, ebenso lehrreich:

| Abschnitt | TCG | KVM | |
|---|---:|---:|---|
| `freestanding` | 40,463 s | 40,470 s | **auf 7 ms gleich** |
| `core` | 62,570 s | 62,547 s | **auf 23 ms gleich** |

Diese beiden verbringen ihre Zeit im **Firn-Uebersetzer auf dem Wirt**,
nicht in QEMU. Wo der Uebersetzer die Zeit frisst, hilft KVM nichts --
die Parallelisierung dagegen schon. Genau deshalb wird hier abschnitts-
weise gemessen und nicht aus einem einzelnen Kernelboot hochgerechnet.

### Vorschaeden auf `mergeline`, nicht von dieser Runde

Unter TCG waren schon vor dieser Runde rot, in **zwei unabhaengigen
Arbeitsbaeumen zeichengleich**:

| Abschnitt | erste Fehlerzeile |
|---|---|
| `icons` | `lib/icons.fi does not match the map -- run the builder` |
| `k16` | `fas scheitert an: ... 'F1.u_start'` |
| `k14` | `und die Wurzelplatte danach, Oktett fuer Oktett` |
| `tunnelpakete` | `/apps/vpn.osp/start fehlt nach der Installation` |

`net` war unter TCG ebenfalls rot, aber **anders**: nur die beiden
`tc netem`-Verlusttests. Das ist lastabhaengig und eine Folge der
Messlast dieser Runde (bis zu vier Abnahmen gleichzeitig), nicht des
Codes.

---

## NACH `kvmfix` -- die Lage kippt

`kvmfix` ist seit `60d3509` in `mergeline`. Diese Runde hat es mit
`git merge mergeline` hereingeholt (Merge `548bceb`, **konfliktfrei**,
`test.sh` +1 Zeile) und danach **gemessen**, nicht geglaubt:

Kernel Stufe 0 aus `mergeline`, `-m 128`, `osum nokbd`, je 3 Laeufe:

| accel | Beendigungscode | letzte Zeile | Mittel |
|---|---|---|---:|
| tcg | 21 | `kernel: done` | 3871 ms |
| kvm | 21 | `kernel: done` | **1786 ms** |

**2,2x schneller, bei gleichem Ergebnis.** Vor dem Merge endete derselbe
Lauf unter KVM mit `exit 63` an einem `#GP`.

> Die 4,6x aus dem Auftrag verglichen einen vollstaendigen TCG-Lauf mit
> einem KVM-Lauf, der frueher **abgestuerzt** ist. Der ehrliche Faktor
> auf dem gefixten Kernel ist 2,2x.

Damit ist jeder der fuenfundzwanzig Eintraege der Ausnahmeliste
gegenstandslos. Die Liste ist **leer**, die alte Fassung liegt
vollstaendig unter `.mess/accel-ausnahmen-vor-kvmfix.txt` -- sie ist der
Beleg fuer den Zustand vorher und wird nicht geloescht.

---

## Behobene Regresse dieser Runde

| gefunden | behoben in |
|---|---|
| bei `OSUM_JOBS=1` erschien die Abschnitts-Ueberschrift NACH dem Lauf statt davor -- beim Zusehen sah man nicht mehr, woran es haengt | `d2a302c` |
| zwei Abnahmen aus demselben Arbeitsbaum ueberschrieben sich `.test-work/<name>.log` | `$OSUM_WORK`, `9d752a8` |
| die Wartezeit an der Netzsperre zaehlte als Laufzeit des Abschnitts (`tunnelkosten` stand mit 632 s in der Tabelle, davon ueber 600 s Warten) | `9d752a8`, die Ausgabe weist die Wartezeit jetzt getrennt aus |
| die Scheduler-Pruefung lag in `/tmp` und war nach einem Neustart des Wirts weg | liegt jetzt im Repo, `e4976fd` |

---

## Offen

* **Die beiden Endlaeufe auf dem gefixten Kernel:** vorher (TCG, seriell)
  gegen nachher (KVM, parallel), volle Abnahme, mit Gesamtzeit und Zahl
  gruener Zusagen. Sie stehen aus, weil auf dem Wirt gerade **drei fremde
  Vollabnahmen** laufen (`osum-basecheck`, `kvmfix-base`, `kvmfix-osum`,
  Last 7-10). Unter dieser Last gemessene Gesamtzeiten waeren wertlos.
  Sie werden gestartet, sobald der Wirt frei ist.
* Danach: was unter KVM dann noch faellt, kommt mit Messwert in die
  Ausnahmeliste zurueck.

---

## Auflagen -- Stand

* Kein Test entschaerft, keiner geloescht. `OSUM_NUR` laesst Abschnitte
  weg, sagt das aber in der Bilanz laut dazu.
* Nur `tools/`, `tests/` und `test.sh` angefasst -- **kein `kernel/`**.
  Was an `kernel/` steht, kam vollstaendig aus dem Merge von `mergeline`.
* Nichts nach `main` gemerged, `mergeline` unberuehrt, nur `testfast`.
