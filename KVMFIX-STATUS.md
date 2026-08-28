# RUNDE KVMFIX — Zwischenstand

**Zweig:** `kvmfix`, abgezweigt von `mergeline`.
**Wirt der Messung:** AMD EPYC 7571 (`AuthenticAMD`), 12 Kerne, 19 GiB RAM,
QEMU 7.2.22 (Debian), `/dev/kvm` mit Modus 0666 durchgereicht,
`kvm.ignore_msrs=N`, `kvm.report_ignored_msrs=Y`.
**Kernel gebaut mit:** `bash tools/build-kernel.sh <aus> --stufe 0` (firnc0),
Gegenprobe mit `--stufe 1` (firnc1).

Alles unten sind **gemessene Zahlen**. Wo etwas nicht gemessen wurde,
steht das dabei.

---

## 1. Die Grundlinie: was VORHER passiert ist

Kernel: `mergeline` (Commit `e9fcc1c`), unverändert.

| Lauf | Befehlszeile | `-accel tcg` | `-accel kvm` |
|---|---|---|---|
| A | `osum nokbd nosched noproc nofs noring3`, `-m 128` | **rc=21**, 76 Zeilen, `kernel: done` | **rc=63**, 40 Zeilen, `*** EXCEPTION 13 #GP err=0x0` |
| B | `osum nopwr`, `-m 512` | **rc=21**, 166 Zeilen, `kernel: done` | **rc=63**, 98 Zeilen, `*** EXCEPTION 13 #GP err=0x20` |
| C | `osum`, `-m 512` | **rc=21**, 133 Zeilen, `kernel: done` | (stirbt wie A) |

---

## 2. Absturz 1 — bewiesen: ein INTEL-Register auf einer AMD-CPU

Der Ausnahmebericht des Kernels selbst:

```
*** EXCEPTION 13 #GP  err=0x0
  rip=0x131ef5  cs=0x8  rflags=0x10246
  rax=0x1a2  rcx=0x1a2  rdi=0x1a2
```

**Beweis, Schritt für Schritt:**

1. `objdump -d --start-address=0x131ec0 /tmp/k0.mb.elf` zeigt an
   **genau `0x131ef5`** den Befehl `rdmsr` — nicht in der Nähe, sondern
   dort.
2. Bei `rdmsr` ist `rcx` der Registerindex. `rcx = 0x1A2` =
   `IA32_TEMPERATURE_TARGET`, definiert in `kernel/pwr.fi:197`, gelesen
   in `probe()` (vormals Zeile 437) **ohne jede Vorprüfung**.
3. Der Wirt ist `AuthenticAMD`. Das Register ist Intel-eigen; KVM bildet
   es nicht nach und läuft mit `ignore_msrs=N` → `#GP`.
4. Gegenprobe mit `tools/k18/msrprobe.s` (dem Prüfprogramm der Runde K18
   selbst), einmal je Beschleuniger, `-cpu host`:

   | Register | `-accel tcg` | `-accel kvm` |
   |---|---|---|
   | `IA32_PERF_CTL` 0x199 | `r=0` gp=0 | `r=0` gp=0 |
   | `IA32_PERF_STATUS` 0x198 | `r=0x400000003e8` gp=0 | `r=0x400000003e8` gp=0 |
   | `IA32_MISC_ENABLE` 0x1A0 | `r=1` gp=0 | `r=1` gp=0 |
   | `IA32_THERM_STATUS` 0x19C | `r=0` gp=0 | **Zugriff bricht ab** |
   | `CPUID.06H:EAX` | `0x00000000` | `0x00000004` |

   (Das Prüfprogramm der Runde K18 hat einen 32-Bit-Wiederaufsetzpfad,
   der unter KVM selbst zusammenbricht — es endet an 0x19C mit
   „KVM internal error / emulation failure“. Als Nachweis, **DASS** die
   Register hier anders antworten, reicht das; die belastbare Zahl
   liefert der Kernel selbst, siehe `pwr: msr-gp=` unten.)

**Warum der Kernel unter TCG bis dahin durchlief:** QEMU nimmt jeden
`rdmsr` an und gibt eine Null zurück. Der Kommentar in `kernel/pwr.fi`
sagte das sogar wörtlich („auf diesem Wirt löst KEINES dieser Register
eine Schutzverletzung aus“) — die Messung stimmte, der Schluss daraus
nicht.

### Die Lösung: eine Fixup-Tabelle, kein Herstellervergleich

Gewählt wurde der **Fängerpfad** (`rdmsr_safe`/`wrmsr_safe` nach Art der
Linux-Exception-Table), nicht die CPUID-Herstellerprüfung. Begründung:

* Auch **Intel**-Maschinen fehlt einzeln ein Register:
  `MSR_PLATFORM_INFO` (0xCE) erst ab Nehalem, `MSR_TURBO_RATIO_LIMIT`
  (0x1AD) nur mit Turbo, `IA32_TEMPERATURE_TARGET` (0x1A2) nicht auf
  jedem Modell. Für keines gibt es ein eigenes CPUID-Bit.
* Ein **Wirt** entscheidet selbst, was er nachbildet — unabhängig davon,
  was CPUID dem Gast erzählt (`ignore_msrs=N` auf diesem Rechner).
* Eine Herstellerprüfung muss an **jeder** Zugriffsstelle richtig sein,
  ein Fängerpfad an **einer**.

Die CPUID-Prüfungen, die es schon gibt (`C_HWP`, `C_DTS`,
`cpu_has_svm()`), bleiben als erste Frage stehen. Der Fänger ist die
zweite.

**Wo es steht:**

| Datei | was |
|---|---|
| `kernel/arch/x86_64/isr.s` | `msr_read_safe` / `msr_write_safe` (Assembler, weil der Fänger eine Befehlsadresse braucht) und die Tabelle `msr_fixups` (Paare aus Fehleradresse und Fängeradresse, Nullpaar am Ende) |
| `kernel/arch/x86_64/isr.s` | drei neue Plätze in `vectors`: 70 = Tabelle, 71 = Lesen, 72 = Schreiben |
| `kernel/msr.fi` (neu, 131 Zeilen) | das Fenster dorthin: `rd`, `wr`, `rd0`, `catch_rip` |
| `kernel/arch/x86_64/trap.fi` | im `#GP`-Zweig, **nur aus Ring 0**, `catch_rip` fragen und `rip` im Rahmen ersetzen. Trifft nichts zu, hält die Maschine an wie seit Runde 59. |

Die Abmachung der beiden Assemblerfunktionen ist **strenger als System V**:
außer `rax` ändert sich kein Register (`rcx`/`rdx` gerettet, Flaggen über
`pushfq`/`popfq`) — der Aufrufer ist ein `asm("call rax", …)` aus Firn,
und was der über zerstörte Register weiß, steht nur in seinen
`clobber`-Klauseln.

---

## 3. Absturz 2 — bewiesen: `sysret` setzt SS.RPL auf AMD nicht auf 3

Der Ausnahmebericht:

```
*** EXCEPTION 13 #GP  err=0x20
  rip=0x1002af  cs=0x8  rflags=0x10006  rsp=0x5acfd8
  rcx=0x4000db  r11=0x206
```

**Beweis, Schritt für Schritt:**

1. `objdump` an `0x1002af`: dort steht **`iretq`**, das letzte Wort von
   `isr_common` in `isr.s` — *nicht* `sysretq`. Die Vermutung im Auftrag
   („der Rückweg des Systemaufrufs“) war also nur halb richtig: es ist
   der Rückweg aus einer **Unterbrechung**.
2. Fehlercode `0x20` = Selektorindex 4, TI=0 → GDT-Eintrag 4.
3. GDT-Eintrag 4 in `boot.s` ist `0x00CFF2000000FFFF`. Zugriffsbyte
   `0xF2` = P=1, DPL=3, S=1, Typ=2 (Daten, schreibbar). Der Eintrag ist
   **korrekt** — hier war der Fehler nicht.
4. **Die entscheidende Messung.** In `trap.fi` wurde vorübergehend eine
   Zeile eingezogen, die bei jedem Trap aus Ring 3 CS und SS aus dem
   Rahmen ausgibt. Derselbe Kernel, dieselbe Befehlszeile, nur ein
   anderer Beschleuniger:

   ```
   -accel tcg  ->  r3trap cs=0x2b  ss=0x23  vec=32     ->  rc=21, "kernel: done"
   -accel kvm  ->  r3trap cs=0x2b  ss=0x20  vec=32     ->  rc=63, #GP err=0x20
   ```

   **`ss=0x20` gegen `ss=0x23`.** Das ist der ganze Unterschied, und er
   ist damit nicht mehr Vermutung, sondern abgelesen.
5. Ursache: `MSR_STAR = (0x18 << 48) | (0x08 << 32)`
   (`kernel/arch/x86_64/user.fi:104`). `sysretq` bildet daraus
   SS = 0x18+8 = **0x20** und CS = 0x18+16 = 0x28.
   * **Intel** ODERt beim `sysret` eine 3 in **beide** Selektoren
     (SDM: `SS.Selector ← (IA32_STAR[63:48]+8) OR 3`) — daher 0x23/0x2B.
     QEMUs TCG macht es genauso (`helper_sysret` in
     `target/i386/tcg/seg_helper.c`).
   * **AMD** tut es nur für CS (deshalb steht im Bericht trotzdem
     `cs=0x2b`). SS bekommt den Wert unverändert: RPL 0.
   * Ring 3 läuft damit weiter — ein Datensegment mit DPL 3 darf CPL 3
     lesen und schreiben. Es fällt erst beim nächsten `iretq` **zurück**
     nach Ring 3 auf, denn der verlangt `SS.RPL == CS.RPL`.
6. **Damit ist auch das „Merkwürdige“ erklärt:** die 13 Systemaufrufe
   davor gehen durch, weil ein `syscall`/`sysret`-Paar den kaputten
   SS-Selektor gar nicht anfasst. Es stirbt beim **ersten
   Zeitgeberschlag**, der einen Prozess in Ring 3 antrifft — welcher
   Systemaufruf gerade läuft, ist Zufall (in zwei Läufen war es einmal
   `k18: miscback0`, einmal `k18: hwpreq0`).

### Die Lösung: eine Zeile

`MSR_STAR` bekommt als `sysret`-Grundwert **0x1B** statt 0x18 — derselbe
GDT-Eintrag, aber **mit RPL 3**. Daraus werden SS = 0x23 und CS = 0x2B,
auf beiden Herstellern und auch unter TCG. Das sind genau die Selektoren,
die `kernel/signal.fi` seit Runde K9 in seine `iretq`-Rahmen schreibt
(`USER_CS = 0x2B`, `USER_SS = 0x23`) — der Kernel wusste die richtigen
Werte also schon, nur `sysret` bekam sie nicht. Linux schreibt aus
demselben Grund `__USER32_CS` (den Selektor **mit** RPL 3) in dieses Feld.

Ersetzen von `sysret` durch `iretq` war damit **nicht nötig** und wurde
nicht gemacht: `sysret` ist nicht kaputt, sein Eingabewert war es.

---

## 4. Der Durchgang durch ALLE MSR-Zugriffe im Baum

`grep -rn 'rdmsr\|wrmsr' kernel/` — vollständig, mit Urteil:

| Ort | Register | Stand |
|---|---|---|
| `pwr.fi` (14 Zugriffe) | 0xCE, 0x199, 0x19C, 0x1A0, 0x1A2, 0x1AD, 0x1B0, 0x770, 0x771, 0x774 | **umgestellt** auf den Fängerpfad |
| `hv.fi` | `MSR_VM_CR` 0xC0010114, `MSR_VM_HSAVE` 0xC0010117 (AMD-eigen, auf Intel `#GP`) | **umgestellt** auf den Fängerpfad; die CPUID-Frage `cpu_has_svm()` bleibt davor stehen |
| `hv.fi` | `MSR_EFER` 0xC0000080, `MSR_LSTAR` 0xC0000082 | architektonisch, im langen Modus immer da → bleibt |
| `user.fi` | `MSR_STAR/LSTAR/SFMASK/EFER` (0xC0000080..84) | architektonisch → bleibt (der Fehler war der **Wert**, nicht der Zugriff) |
| `apic.fi` | `MSR_APIC_BASE` 0x1B | architektonisch seit dem Pentium, und `present()` fragt vorher CPUID.01H:EDX Bit 9 → bleibt |
| `boot.s`, `start.s`, `smp.s` | `MSR_EFER` 0xC0000080 | architektonisch, und ohne ihn gäbe es keinen langen Modus → bleibt |
| `batt.fi`, `pmon.fi` | **keiner** | `grep` liefert null Treffer. `pmon.fi:89` ist ein Kommentar über die K18-Messung, kein Zugriff. |

Nach der Umstellung zählt der Kernel selbst, was zurückgewiesen wurde
(`PW_MSRGP`) und sagt es — **aber nur, wenn es etwas zu sagen gibt**:

```
-accel tcg  ->  keine Zeile           (kein Register verweigert)
-accel kvm  ->  pwr: msr-gp=1         (genau eines: 0x1A2)
```

Damit ändert sich an der Ausgabe unter TCG **kein Oktett**, und auf
echter Hardware steht die Zahl da. Eine Null aus einem Register und eine
Null, weil es das Register nicht gibt, sind zwei verschiedene Dinge.

---

## 5. Was NACHHER passiert (dieselben Läufe, gefixter Kernel)

| Lauf | `-accel tcg` | `-accel kvm` |
|---|---|---|
| A `osum nokbd nosched noproc nofs noring3` `-m 128` | rc=21, 76 Zeilen | **rc=21**, 77 Zeilen (die eine Zeile ist `pwr: msr-gp=1`), 0 Ausnahmen |
| B `osum nopwr` `-m 512` | rc=21, 166 Zeilen | **rc=21**, 166 Zeilen, 0 Ausnahmen |
| C `osum` `-m 512` | rc=21, 133 Zeilen | **rc=21**, 134 Zeilen, 0 Ausnahmen |
| D `osum` `-cpu host` | — | **rc=21**, 134 Zeilen, 0 Ausnahmen |
| E `osum smp` `-cpu host -smp 4` | — | **rc=21**, 141 Zeilen, `smp: online=4 of 4 failed=0` |
| F `osum smp hv` `-cpu host -smp 4` | — | **rc=21**, 184 Zeilen, `hv: OK the processor can do svm` |
| G Stufe 1 (firnc1), `osum nopwr` | — | **rc=21**, 166 Zeilen, 0 Ausnahmen |

Die TCG-Ausgabe ist gegenüber vorher zeilenweise gleich; die einzigen
Unterschiede sind der Pfad des Abbilds in `cmd=…` und die
zeitabhängigen Zahlen (`apic: hz=`, `spin: ticks=`, `smp: locks`), die
zwischen zwei Läufen desselben Kernels genauso schwanken.

---

## 6. Der neue Testabschnitt

`tools/kvm/run.sh` — **35 Zusagen, 0 Fehler, 76 s Laufzeit.**

* Ohne `/dev/kvm` oder ohne QEMU: `exit 0` mit einer Zeile
  „KVM: uebersprungen …“ — **skip, nicht fail**.
* Abschnitt 1: fünf Befehlszeilen unter KVM, je drei Zusagen
  (rc=21, `kernel: done`, kein `EXCEPTION`), dazu `smp: online=4`.
* Abschnitt 2: dieselben Zeilen unter TCG, damit nicht offenbleibt, ob
  KVM etwas repariert oder nur etwas anderes tut.
* Abschnitt 3: `pwr: msr-gp` muss unter TCG **fehlen** und darf unter KVM
  dastehen — die Messung des Herstellerunterschieds selbst.
* Abschnitt 4, die Gegenproben (jede baut den Kern mit **einer**
  verbogenen Zeile neu):
  * `GP_VECTOR` auf 133 → ohne Fängerpfad. Unter TCG läuft er durch,
    unter KVM stirbt er an `#GP` mit `rcx=0x1a2`. ✔ beides gemessen.
  * `MSR_STAR` zurück auf 0x18. Unter TCG läuft er durch, unter KVM
    stirbt er an `#GP err=0x20`. ✔ beides gemessen.
  * Beide Gegenproben laufen **nur dort, wo sie etwas beweisen können**:
    die erste nur, wenn dieser Wirt wirklich ein Register verweigert, die
    zweite nur auf `AuthenticAMD`. Auf einem Intel-Wirt sagt der Läufer
    das hin, statt eine Zusage zu erfinden, die dort nicht gelten kann.
  * Und der mit **firnc1** gebaute Kernel läuft unter KVM ebenfalls durch.

Eingehängt in `./test.sh` mit **einer** Zeile (Abschnitt 28), damit der
Zweig `testfast` daneben arbeiten kann.

---

## 7. Die volle Abnahme unter TCG, vorher gegen nachher

*(wird unten eingetragen, sobald beide Läufe durch sind)*

---

## 8. Was NICHT gemacht wurde, und warum

* **Kein Test entschärft.** Keine Zusage wurde gestrichen, gelockert oder
  in eine Bedingung gehängt, damit sie grün wird. Die einzigen
  Bedingungen sind die zwei Gegenproben in `tools/kvm/run.sh`, und die
  hängen an einer Eigenschaft des **Wirts** (AMD? verweigert er ein
  Register?), nicht am Ergebnis.
* **Kein `iretq` statt `sysret`.** Siehe Abschnitt 3: `sysret` war nicht
  der Fehler.
* **Kein allgemeiner Fängerpfad für Nutzerspeicher.** Der bräuchte mehr
  als eine ausgetauschte Rücksprungadresse (auch die Angabe, wie viel
  nicht kopiert wurde); diese Runde braucht ihn nicht.
* **`apic.fi` und die drei Assemblerdateien nicht umgestellt.** Begründung
  in Abschnitt 4 — sie fassen ausschließlich architektonische Register
  an, die es ohne langen Modus gar nicht gäbe.
* **`mergeline` und `main` nicht angefasst.**
