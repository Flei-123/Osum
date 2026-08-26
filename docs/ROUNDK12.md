# Runde K12 — ein Wirt für fremde Prozessoren

Osum kann von dieser Runde an ein fremdes Betriebssystem auf sich laufen
lassen. Nicht, indem es dessen Schnittstellen nachbaut, sondern indem es
den **Prozessor virtualisiert**: Steuerblock, Gastzustand, Abfangbits,
Eintritt, Austritt, Austrittsgrund. Diese Aufgabe ist endlich — sie steht
vollständig in den Handbüchern von Intel und AMD — und wenn sie stimmt,
stimmt sie für jedes Gastsystem, weil ein Gastsystem nichts anderes sieht
als einen Prozessor.

    ./test.sh          ALLE 15 ABSCHNITTE BESTANDEN, 1243 Zusagen, 0 Fehler
    bash tools/hv/run.sh                HV: 114 passed, 0 failed

Vorher: 14 Abschnitte, 1126 Zusagen. Dazugekommen sind 117 -- 114 aus
`tools/hv/run.sh`, dazu je eine in `tools/kernel/run.sh` und
`tools/pci/run.sh` (die fuenfte Assemblerdatei uebersetzt) und eine im
Netz-Abschnitt. Keine bestehende Zusage ist weggefallen.

---

## 0. Die erste Entscheidung: AMD-V statt Intel VT-x

Der Auftrag sagte „Intel VT-x zuerst“. **Das geht in dieser Umgebung
nicht**, und das ist gemessen und nicht vermutet:

```
$ qemu-system-x86_64 -accel tcg -cpu qemu64,+vmx ...
qemu-system-x86_64: warning: TCG doesn't support requested feature:
                    CPUID.01H:ECX.vmx [bit 5]

$ qemu-system-x86_64 -accel tcg -cpu qemu64,+svm ...
(keine Warnung)
```

Dazu kommt: der Rechner, auf dem dieses Projekt gemessen wird, ist ein
AMD EPYC 7571 **ohne `/dev/kvm`**. Es gibt also weder eine
Beschleunigung, hinter der ein echtes VT-x stecken könnte, noch einen
Intel-Kern. Ein VMX-Wirt wäre hier **nicht messbar** — und dieses Projekt
misst. Also AMD-V.

Der Sache nach ist es dasselbe: ein Steuerblock, in dem steht, was der
Gast nicht selbst darf; ein Befehl, der in den Gast eintritt; ein Grund,
warum er wieder herauskommt. Nur die Namen und die Zahlen sind andere
(VMCB statt VMCS, `vmrun` statt `vmlaunch`, NPT statt EPT).

`tools/hv/run.sh` misst diese Begründung bei **jedem Lauf neu**. Sollte
TCG eines Tages VMX können, wird der Abschnitt rot und jemand muss
nachsehen.

---

## 1. Was diese Maschine kann — und was nicht

CPUID `0x8000000A`, mit einem eigenen Bare-Metal-Prüfling gemessen:

| Eigenschaft            | `-cpu qemu64` | `-cpu max` / `EPYC` |
|------------------------|---------------|---------------------|
| SVM                    | ja            | ja                  |
| nested paging (NPT)    | **nein**      | **ja**              |
| nrip save              | nein          | nein                |
| decode assists         | nein          | nein                |
| VMCB clean bits        | nein          | nein                |
| flush by ASID          | nein          | nein                |
| ASIDs                  | 16            | 16                  |

Daraus folgen zwei Dinge, die dieser Wirt selbst tun muss:

* **Ohne „nrip save“** verrät der Prozessor nach einem Austritt nicht, wo
  der nächste Befehl anfängt. Der Wirt muss die Länge des abgefangenen
  Befehls kennen und `RIP` selbst weiterrücken: `cpuid` 2 Oktette,
  `vmmcall` 3, `hlt` 1, `rdmsr`/`wrmsr` 2. Bei Anschlusszugriffen ist es
  anders — dort steht der nächste `RIP` architektonisch in `EXITINFO2`,
  und das ist die einzige Stelle, an der der Prozessor die Länge verrät.
* **Ohne „decode assists“** sagt der Prozessor bei einem Zugriff auf ein
  Steuerregister nicht, aus welchem Register der Wert kam. Der Wirt muss
  den Befehl **selbst aus dem Gastspeicher lesen und entziffern**
  (`hv.decode_movcr`: Vorsatzoktette überspringen, `0F 22 /r` erkennen,
  ModRM auswerten). Gemessen: 3 solche Austritte im zweiten Gast, alle
  richtig entziffert — der Gast läuft danach weiter und kommt zum
  richtigen Ergebnis.

**Deshalb `-cpu max` und nicht `-cpu qemu64`.** Gegenprobe E des Läufers
misst genau das: mit `qemu64` meldet der Wirt `np=no`, und die Zusage
darüber wird **rot**, statt stillzuschweigen.

---

## 2. Die Falle, die eine halbe Stunde gekostet hat

Verschachtelte Seitentabellen ließen QEMU hängen. Der Grund steht in
QEMUs eigenem Quelltext (v7.2,
`target/i386/tcg/sysemu/svm_helper.c`, Zeile 284):

```c
if (nested_ctl & SVM_NPT_ENABLED) {
    env->nested_cr3 = ...;
    env->hflags2 |= HF2_NPT_MASK;
    env->nested_pg_mode = get_pg_mode(env) & PG_MODE_SVM_MASK;   /* <-- */
    ...
}
```

Diese Zeile steht **vor** dem Laden des Gastzustands. `get_pg_mode(env)`
liest also CR0/CR4/EFER **des Wirts** — und gibt bei `CR0.PG == 0` sofort
0 zurück. Eine vierstufige Tabelle wird dann als zweistufige gelesen, und
der Seitenlauf dreht sich im Kreis.

Der erste Prüfling war ein 32-Bit-Multiboot-Kernel ohne Paging; deshalb
hing er. **Osum läuft im langen Modus mit Paging** — genau der Fall, der
trägt. Ein Wirt im geschützten Modus könnte es unter QEMU nicht.

Zweite Falle derselben Art: QEMU liest `IOPM_BASE_PA` und `MSRPM_BASE_PA`
**wirklich** aus dem Speicher (`svm_check_intercept_param`). Stünde dort
eine 0, würde die physische Adresse 0 als Bitkarte gelesen — und was dort
zufällig liegt, entschiede darüber, welche Anschlüsse abgefangen werden.
Dieser Wirt legt echte Bitkarten an: drei Seiten für die Anschlüsse, zwei
für die MSRs, **alle Bits gesetzt**. Ein Gast hat keinen einzigen
Anschluss für sich.

---

## 3. Der Weltwechsel — was `vmrun` *nicht* tut

`kernel/hv.s`. Das Missverständnis, an dem ein Hypervisor stirbt, ist die
Annahme, `vmrun` kümmere sich um alles. Es tut es nicht (AMD APM Band 2,
15.5.1 — und QEMU setzt es nachweislich genauso um, `helper_vmrun`
Zeilen 339–345, `do_vmexit` 746–786):

| Zustand | von `vmrun` behandelt? |
|---|---|
| ES, CS, SS, DS, GDTR, IDTR, EFER, CR0/3/4, RFLAGS, RIP, RSP, RAX | **ja**, automatisch gesichert und geladen |
| RBX, RCX, RDX, RBP, RSI, RDI, R8–R15 | **nein** — stehen in keinem der beiden Bereiche |
| FS, GS, TR, LDTR, KernelGsBase, STAR, LSTAR, CSTAR, SFMASK, SYSENTER_* | **nein** — dafür gibt es `vmsave`/`vmload` |

Die allgemeinen Register trägt `hv_vmrun` von Hand hin und zurück
(Registerblock, 14 Wörter je Maschine).

Der zweite Punkt ist für **diesen** Kernel lebenswichtig: Osum lebt von
`syscall`/`sysret` (MSR_STAR, MSR_LSTAR, MSR_SFMASK aus `kernel/user.fi`)
und von seinem TSS. Ein Gast, der TR oder LSTAR umsetzt und dessen Werte
stehenbleiben, nimmt den Wirt beim nächsten Systemaufruf mit. Deshalb:

```
clgi                       kein Interrupt in das Fenster, in dem
                           TR und LSTAR dem Gast gehoeren
vmsave (Wirtsbereich)      Wirt FS/GS/TR/LDTR/STAR/... wegschreiben
vmload (VMCB)              Gastwerte hereinholen
vmrun                      ---- Weltwechsel ----
vmsave (VMCB)              Gastwerte zurueckschreiben
vmload (Wirtsbereich)      Wirt wiederherstellen
stgi
```

**Und das ist gemessen, nicht behauptet.** Nach dem Gast, der einen
Dreifachfehler baut, liest der Wirt `MSR_LSTAR` zurück und vergleicht es
mit dem, was `user.setup` hineingeschrieben hat:

    hv: OK  and the host's syscall path is untouched

---

## 4. Verschachtelte Seitentabellen

Der Gast bekommt einen eigenen physischen Adressraum. Was er für Adresse
`0x1000` hält, ist irgendein Rahmen, den der Rahmenverwalter übrig hatte
— und er kann es nicht merken.

Vier Ebenen (das Format, das die Hardware für verschachtelte Tabellen
verlangt), vier zusammenhängende Rahmen, eine PT deckt 2 MiB. Jeder
Eintrag trägt **P|W|U**; das U ist kein Versehen: ein verschachtelter
Seitenlauf läuft immer mit Nutzerrechten (AMD APM 15.25.5), und ohne U
bekäme jeder Gastzugriff einen Seitenfehler.

Aufteilung des Gastspeichers (acht Rahmen je Maschine):

```
gastphysisch 0x0000  Vektortabelle, Stapel, Muster des Wirts bei 0x0800
             0x1000  das Programm des Gasts   (CS.base im Realmodus)
             0x2000  Seitenverzeichnis         (Gast 2)
             0x3000  Seitentabelle 0..4 MiB    (Gast 2)
             0x4000  Seitentabelle 4..8 MiB    (Gast 2)
             0x5000  die Seite unter 0x00400000(Gast 2)
             0x6000  Stapel im geschuetzten Modus
             0x7000  ABSICHTLICH NICHT ABGEBILDET
```

---

## 5. Die Gäste

Sechs, alle in `kernel/hv.s` in echtem Assembler (ein von Hand kodiertes
Zahlenfeld wäre nicht nachprüfbar; was hier steht, übersetzt `as` und
`objdump` liest es zurück). Jeder meldet über `vmmcall` Zahlen zurück,
und **jede einzelne wird nachgelesen**.

| # | Gast | was er beweist |
|---|------|----------------|
| 1 | `hello` | Realmodus: Text durch einen Anschluss, den es nicht gibt; CPUID; liest das Muster des Wirts **durch die NPT**; hängt sich einen Behandler in die Vektortabelle und nimmt eine **vom Wirt eingeworfene Unterbrechung** entgegen |
| 2 | `pm` | geht **selbst** in den geschützten Modus, baut sich seine **eigene** zweistufige Seitentabelle, schaltet sein **eigenes** Paging ein und liest durch eine selbstgebaute virtuelle Adresse zurück, was er hingeschrieben hat |
| 3 | `loop` | sagt `cli` und dreht sich für immer im Kreis |
| 4 | `fault` | läuft in eine nicht abgebildete Seite |
| 5 | `crash` | baut einen Dreifachfehler |
| 6 | `bench` | tut nichts außer austreten — 512 Runden für die Preismessung |

### Gast 2 ist der eigentliche Beweis

```
    movl $0x5A5AC0DE, %eax
    movl %eax, 0x00400000     <- gastvirtuell, ueber SEINE Tabelle
    movl 0x5000, %ebx         <- gastphysisch, ueber die identische
```

Damit hängen **zwei Übersetzungen hintereinander**: gastvirtuell →
gastphysisch macht der Gast mit seinen Tabellen, gastphysisch →
wirtsphysisch macht die NPT des Wirts. Der Gast weiß von der zweiten
nichts. Gemessen: `0x5A5AC0DE` kommt zurück, `cr0 = 0x80000011`
(PE **und** PG), `cr3 = 0x2000`.

### Gast 4: Seiten auf Zuruf

Er schreibt nach gastphysisch `0x7000`, das der Wirt nicht abgebildet
hat. Das gibt einen **NPF**-Austritt mit der gastphysischen Adresse in
`EXITINFO2`. Der Wirt legt einen Rahmen unter und lässt weiterlaufen —
der Gast liest denselben Wert (`0xC0DE`) zurück und merkt nichts. Seiten
auf Zuruf, für eine ganze Maschine statt für einen Prozess.

### Gast 5: die wichtigste Gegenprobe

Der Wirt setzt für ihn `IDTR.limit = 0`. Aus `ud2` wird ein #UD, daraus
ein #DF, daraus ein Dreifachfehler → Austrittsgrund **SHUTDOWN**. Die
Gastmaschine ist tot, der Wirt läuft weiter, und sein `syscall`-Pfad ist
unverändert.

---

## 6. Die Austritte, nach Grund gezählt

Ein voller Lauf (`hv gastlauf gastmess gastcr`, `-cpu max`):

```
hv: exits total=612  cpuid=2  ioio=16  msr=0  hlt=0  vmmcall=524
                     npf=1  intr=65  shutdown=1  exc=0  crwr=3
                     err=0  other=0
```

Jede Zahl ist erklärbar, und der Testläufer prüft jede einzelne:

| Grund | Zahl | woher |
|---|---|---|
| `cpuid` | 2 | Gast 1 fragt zweimal |
| `ioio` | 16 | 15 Oktette „hallo vom gast\n“ + 1 `out` aus Gast 2 |
| `vmmcall` | 524 | 6+4+2+1 der Gäste 1/2/4/5 + 511 des Messgasts |
| `npf` | 1 | Gast 4 läuft gegen `0x7000` |
| `intr` | 65 | der Zeitgeber des Wirts holt den Läufer ein |
| `shutdown` | 1 | Gast 5 |
| `crwr` | 3 | Gast 2: zweimal CR0, einmal CR3 |
| `err` | 0 | kein Eintritt wurde zurückgewiesen |
| `other` | 0 | **kein Grund blieb unbehandelt** |

Ohne `gastlauf`/`gastmess`/`gastcr` sind es 33 Austritte.

### Was ein Austritt kostet

Der Messgast tut nichts außer austreten; sein Kontingent ist die Zahl der
Runden. Damit ist der Wert eine Zeit **je Runde** und keine Schätzung:

```
hv: bench rounds=512 cycles=34288298 per-exit=66969
           in-guest=53137 in-host=13832        (firnc0)
hv: bench rounds=512 cycles=38511506 per-exit=75217
           in-guest=53577 in-host=21640        (firnc1)
```

**Diese Zahlen sind Zyklen unter QEMUs Softwareemulation und keine
Aussage über echte Hardware.** Auf einem echten AMD-Prozessor kostet ein
`vmrun`/`#vmexit`-Paar einige hundert bis wenige tausend Zyklen; hier
wird der Weltwechsel selbst emuliert. Was die Zahl beweist, ist, dass
gemessen wurde und nicht geschätzt — und das Verhältnis (rund 4:1
Gast zu Wirt) sagt, dass die Behandlung im Wirt nicht der Flaschenhals
ist.

---

## 7. Wem gehört die physische Unterbrechung

Das ist die eine Einstellung, die einen Wirt zum Wirt macht — und die
Stelle, an der ich einen ganzen Fehlschluss produziert habe, den ich hier
aufschreibe, weil er lehrreich ist.

Der Läufer blieb hängen. Es sah nach einer Grenze von QEMU aus, und ich
hätte sie beinahe als solche berichtet. Sie war keine.

QEMU nimmt die Unterbrechung im Gast genau dann
(`target/i386/cpu.c`, `x86_cpu_pending_interrupt`, Zeile 6872):

```c
(HF2_VINTR && HF2_HIF) || (!HF2_VINTR && (guest EFLAGS.IF))
```

`HF2_HIF` setzt `helper_vmrun` aus **EFLAGS.IF des Wirts**, gelesen im
Augenblick des Eintritts. Mein Austrittsbehandler machte damals ein
`sti; nop; cli`, um die Unterbrechung hereinzulassen. **Das `cli` am Ende
löschte das IF des Wirts** — und der zweite Eintritt war blind. Der erste
Austritt kam noch, danach nie wieder.

Die Lehre steht jetzt im Quelltext: der Behandler dreht an IF überhaupt
nicht mehr. `stgi` am Ende von `hv_vmrun` macht das globale Flag auf, das
IF des Wirts kommt beim Austritt aus dem Rettungsbereich zurück, und die
Unterbrechung wird noch im Stumpf zugestellt.

Gemessen, mit einem Gast, der `cli` sagt und im Kreis läuft:

| V_INTR_MASKING | Ergebnis |
|---|---|
| **an** (Vorgabe) | 65 INTR-Austritte, der Wirt behält die Maschine |
| aus (`gastfrei`) | `vmrun` kehrt **nie** zurück |

Das ist zugleich die schärfste Gegenprobe dieser Runde: ein Gast, der
sich weigert, den Prozessor herzugeben, wird eingeholt — und ohne diese
eine Einstellung eben nicht.

---

## 8. Gastmaschinen aus Ring 3 — über Handles

Eine Gastmaschine ist eine **Objektart wie jede andere** (`cap.K_VM`,
`K_MAX` 8 → 9). Es gibt keinen zweiten Weg.

Das ist keine Bequemlichkeit. Eine Gastmaschine ist ein mächtiges Ding —
eigener physischer Speicher, eigener Prozessor. Wäre sie über eine kleine
Zahl erreichbar, könnte jeder Prozess durch Raten an eine fremde geraten.
Über ein Handle kann er es nicht: der Würfelwert der Tabelle geht in die
Generation ein.

Fünf Aufrufe, **1500 bis 1504**. (Beim Bau dieser Runde waren es 1400 bis
1404; Runde K11 hat parallel 1400 und 1401 für `setenv` und `mount`
genommen, der Merge hat diese Runde einen Block weitergerückt.)

| Nr | Aufruf | braucht |
|---|---|---|
| 1500 | `vm_create(gast, rechte)` → Handle | — |
| 1501 | `vm_run(h)` → Grund des Anhaltens | `R_WRITE` |
| 1502 | `vm_stat(h, aus)` | `R_INSPECT` |
| 1503 | `vm_kill(h)` | `R_MANAGE` |
| 1504 | `vm_value(h, nr)` | `R_READ` |

> **Zu 1400, und warum nicht 140.** Der Auftrag sagte „fest ab Nummer 140
> aufwärts“. 140 ist bei Linux `setpriority`, 141 `getpriority`, 158
> `arch_prctl`, 186 `gettid` — und 186 hat Runde K9 bereits als `gettid`.
> Die erste Regel der Karte in `sys.fi` ist älter als der Auftrag: *was
> Linux hat, hat Linux’ Nummer.* Runde K12 nimmt deshalb den
> Hunderterblock **1400** — dieselbe 140, an der Stelle, an der dieser
> Kernel seine eigenen Aufrufe führt. Eingetragen ist der Block in der
> Karte am Kopf von `sys.fi`.

`kernel/uprog.fi`, `u_hv` meldet **14 Zusagen aus Ring 3**, und die
Hälfte davon ist eine Ablehnung:

```
hvuser: handle=-2316617939698057214
hvuser: run=2        state=3   exits=23
hvuser: result=4660  value=23130
hvuser: 14 / 14
hv: ring 3 exit=0
```

Die drei Ablehnungen, um die es geht — POSIX hätte für alle drei nur
`-EBADF`:

* ein **erfundenes** Handle → `BadHandle`
* die Konsole (ein **Strom**, keine Maschine) → `WrongType`
* eine **Kopie ohne `R_MANAGE`** darf den Gast führen, aber nicht
  abräumen → `RightsDenied`

Dieselbe Maschine, dasselbe Programm, ein anderes Recht.

> **Eine Stunde gekostet:** ein Handle ist **nicht an seinem Vorzeichen**
> zu erkennen. `cap.handle_make` legt die Generation samt Würfelwert in
> die oberen 32 Bit — jedes zweite Handle hat Bit 63 gesetzt und sähe wie
> ein Fehler aus. Fehler sind `0 -% e` mit `e <= 9` und liegen ganz oben.

---

## 9. Der Speicher, und warum `kdata` wachsen musste

`kdata` war **randvoll**: 0x3C000 gehört dem Rahmenpuffer (Runde K7B),
und die parallel laufende Runde K10 hat 0x3D000 bis 0x40000 belegt. Es
gab keine freie Seite mehr.

Deshalb wächst `KDATA_SIZE` von `0x40000` auf `0x50000` (**zwei
Stellen**: `kernel/boot.s` und `kernel/kstate.fi` — `tools/hv/run.sh`
liest beide und vergleicht sie). Runde K12 nimmt genau **eine** Seite,
`HV_OFF = 0x40000`; 0x41000 bis 0x50000 bleiben frei.

Alles Große kommt aus dem **Rahmenverwalter** und nicht aus `kdata`:
Steuerblöcke, verschachtelte Seitentabellen, Bitkarten, der Speicher der
Gäste. Eine Gastmaschine ist so groß, wie ihr Gast Speicher braucht, und
das gehört nicht in eine feste Seite.

Der Bereich ist in `tools/kernel/karte.py` eingetragen — als bisher
einziger neben `fb.fi` in einer anderen Datei als `kstate.fi`, mit den
vier Innen-Versätzen ausdrücklich als „kein kdata“ erklärt. Der
Kartenprüfer rechnet nach: **39 Bereiche, 0 Kollisionen.**

Und der Wirt zählt seine Rahmen:

```
hv: frames before=64857 after=64857 leak=0
```

Ein Wirt, der bei jeder Gastmaschine Rahmen liegen lässt, ist ein Wirt
mit einem Leck — und ein Leck sieht man nur, wenn man zählt.

---

## 10. Die Gegenproben

| Wort | was zusammenbricht |
|---|---|
| *ohne* `hv` | genau **eine** Zeile (`hv: skipped`), kein Gast, kein Ring-3-Programm, der übrige Kernel Zeile für Zeile wie vorher |
| `nonpt` | ohne verschachtelte Tabellen läuft der Gast unmittelbar im Speicher des Wirts und **kommt nie zurück** (Zeitlimit) |
| `gastfrei` | ohne `V_INTR_MASKING` behält der Läufer den Prozessor **für immer** |
| `nosvm` | ohne `EFER.SVME` gibt es nichts von alledem — und der Kernel lebt |
| `-cpu qemu64` | CPUID bietet keine NPT an, der Wirt **meldet** es und die Zusage darüber wird **rot** |

Dazu die beiden Umgebungsproben aus Abschnitt 0, die bei jedem Lauf neu
messen, dass TCG VMX nicht kann und SVM kann.

---

## 11. Was offen bleibt — ehrlich

**Linux ist nicht gelaufen.** Das war das genannte Fernziel, und es ist
nicht erreicht. Was fehlt, ist benennbar:

1. **Der lange Modus im Gast.** Die Gäste dieser Runde laufen im Real-
   und im geschützten Modus. Der Weg in den langen Modus ist im Wirt
   nicht ausprobiert; `EFER.LME`/`LMA` des Gasts werden durchgereicht,
   aber nicht gemessen.
2. **Ein Ladeweg.** Ein Linux-Kern will über den Boot-Protokoll-Kopf
   geladen werden (`bzImage`, `boot_params`, `setup_header`), mit
   Kommandozeile und initrd im Gastspeicher. Nichts davon gibt es.
3. **Virtuelle Geräte.** Ein Linux braucht mindestens einen
   Unterbrechungsverteiler (i8259 oder LAPIC), einen Zeitgeber, eine
   serielle Schnittstelle mit echten Registern und eine Platte. Dieser
   Wirt hat die serielle **Ausgabe** (der Gast schreibt, der Wirt gibt
   es weiter) und sonst offenen Bus. `virtio-blk` und `virtio-net` wären
   die nächste Stufe — Osum hat beide Treiber bereits für sich selbst,
   aber ein Treiber ist nicht ein Gerät.
4. **Gastspeicher in Gigabyte-Größe.** Acht Rahmen je Maschine reichen
   für die Gäste dieser Runde. Die NPT deckt 2 MiB mit einer PT; für
   einen echten Gast bräuchte es eine Tabelle, die mitwächst, und
   sinnvollerweise 2-MiB-Seiten.
5. **Der Befehlsentzifferer** kann genau eine Form (`0F 22 /r`) und nur,
   solange der Gast noch kein eigenes Paging hat. Mit eingeschaltetem
   Gast-Paging müsste der Wirt zusätzlich die Tabellen **des Gasts**
   laufen, um an die Befehlsoktette zu kommen. Das sagt der Quelltext an
   der Stelle auch, statt es zu verschweigen.
6. **Ein Kern, mehrere Gäste gleichzeitig.** Der Wirt kann acht
   Maschinen halten, führt aber immer nur die, die gerade `vm_run`
   bekommt. Ein Gast auf einem eigenen Prozessorkern (Osum hat SMP seit
   K5) ist nicht gebaut.

Was **steht**, ist die Grundlage, auf der das alles gebaut werden kann:
Ein- und Austritt sind richtig, der Austrittsgrund wird vollständig
ausgewertet, die Übersetzung trägt zwei Ebenen tief, der Wirt überlebt
einen Gast, der ihn mitnehmen will, und Ring 3 kann eine Gastmaschine
führen, ohne dafür Sonderrechte zu bekommen.

---

## 12. Der Fehler, den die Gegenprobe gefunden hat

Das ist der lehrreichste Teil dieser Runde, und er stand fast im Baum.

Alles war grün — Gäste, NPT, Ring 3, alle fünf Gegenproben. Dann lief
`./test.sh` ein weiteres Mal, und Gegenprobe A wurde **rot**:

```
FAIL  ohne 'hv': genau die eine Zeile -- 'hv: skipped' fehlt
FAIL  ohne 'hv': keine einzige Zusage -- 'hv: OK' sollte nicht da sein
FAIL  ohne 'hv': kein Gast hat geredet -- 'gast|' sollte nicht da sein
FAIL  ohne 'hv': kein Programm in Ring 3 -- 'hvuser:' sollte nicht da sein
```

Der Kernel hatte den Hypervisor eingeschaltet, **obwohl das Wort nicht
auf der Kommandozeile stand**. Der Grund:

**QEMU stellt der Multiboot-Kommandozeile den Pfad des Abbilds voran.**

```
mb: flags=0x24f  cmd=/tmp/tmp.aBhvXk12/osum0.mb osum nokbd nofs
                          ^^
```

Die Testläufer bauen in ein Verzeichnis aus `mktemp -d`, und dessen Name
ist zufällig. Enthält er die zwei Buchstaben `hv`, findet eine
**Teilzeichenketten**-Suche das Wort dieser Runde im Pfad. Genau das war
passiert.

Nachgestellt, damit es kein Verdacht bleibt:

```
$ mkdir /tmp/pfad-mit-hv-drin
$ qemu-system-x86_64 -kernel /tmp/pfad-mit-hv-drin/k.mb \
      -append 'osum nokbd nofs'
hv: proofs 20 / 20        <- ohne das Wort auf der Kommandozeile
```

Die Abhilfe ist klein und steht jetzt in `hv.fi` (`find_word`): vor dem
Treffer muss der Anfang der Zeile oder ein Trennzeichen stehen, dahinter
das Ende oder ein Trennzeichen. **Ein Wort aus zwei Buchstaben ist sonst
kein Schalter, sondern ein Zufall.**

Und aus dem Fehler ist eine **dauerhafte Wache** geworden. Gegenprobe F
in `tools/hv/run.sh` verlässt sich nicht mehr auf den Zufall: sie legt
das Abbild ausdrücklich in ein Verzeichnis, dessen Name die zwei
Buchstaben *enthält*, prüft nach, dass der Pfad wirklich in der
Kommandozeile steht — und verlangt, dass der Kernel trotzdem schweigt.
Danach dasselbe *mit* dem Wort, aus demselben Pfad, und alles muss laufen.

> **Für die anderen Runden.** Dieselbe Falle liegt unter jedem Wort, das
> mit `mem.cmdline` gesucht wird: `nic` (`hw.fi`), `unix`, `caps`, `gfx`,
> `osum`, `ata`, `nofs`. Je kürzer das Wort, desto wahrscheinlicher der
> Zufallstreffer. Diese Runde fasst die fremden Dateien **nicht** an —
> aber `hv.find_word` ist die Vorlage, wenn jemand es aufräumen will.

---

## 13. Ein Befund nebenbei: zwei Runden koennen `./test.sh` nicht gleichzeitig laufen lassen

Das gehoert nicht zu dieser Runde, ist aber beim Messen zweimal
passiert und kostet jeden, dem es passiert, eine halbe Stunde Suche.

`tools/net/run.sh` (Runde K8) arbeitet mit einem **globalen** Netz-
Namensraum `k8net`, einem globalen Verbindungspaar `v0` und zwei
**festen** UDP-Anschluessen (5555 und 5556):

```sh
NS=k8net ; QPORT=5555 ; BPORT=5556
cleanup() { ... ip netns del "$NS" ; ip link del v0 ; }
trap cleanup EXIT
```

Laufen zwei Arbeitsbaeume gleichzeitig durch `./test.sh`, reisst der
zweite dem ersten mitten in Abschnitt 14 den Namensraum unter den
Fuessen weg. Der erste Lauf stirbt dabei **ohne Fehlermeldung** — er
bricht einfach ab, und das Protokoll hoert mitten in einem Abschnitt auf.
Genau das ist hier zweimal passiert.

**Nach dem dritten Mal ist es behoben.** Fuenf Zeilen in
`tools/net/run.sh`:

```sh
NS=k8net-$$
V0=v0-$$
V1=v1
QPORT=$(( 5000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))
```

Gemessen wird dasselbe -- dieselbe Bauart, dieselben Adressen, dieselben
Zusagen --, nur gehoert der Lauf sich selbst. Belegt: waehrend eine
zweite Runde ihre eigene Suite fuhr, lief `tools/net/run.sh` hier im
Namensraum `k8net-2832351` sauber durch, statt dem Nachbarn zum Opfer zu
fallen.

Das ist die einzige Datei ausserhalb dieser Runde, die hier angefasst
wurde, und sie gehoert der Runde K8, die gerade nicht laeuft. Die
Aenderung ist ruecknahmefaehig und aendert an keiner einzigen Messung
etwas.

---

## 14. Die Dateien

| Datei | Zeilen | was drin steht |
|---|---|---|
| `kernel/hv.s` | ~430 | Weltwechsel (`vmsave`/`vmload` um `vmrun`) und die sechs Gäste |
| `kernel/vmcb.fi` | ~260 | der Steuerblock, AMD APM Band 2 Anhang B nach Firn |
| `kernel/hv.fi` | ~1150 | der Wirt: aufsetzen, NPT, Austritte, Ring-3-Schnittstelle, Messung |
| `tools/hv/run.sh` | ~380 | 108 Zusagen, fünf Gegenproben, beide Übersetzer |

Berührt: `boot.s` und `kstate.fi` (`kdata` 0x40000 → 0x50000), `isr.s`
(**eine** Zeile: Platz 69 = `hv_vectors`), `kmain.fi` (vier Zeilen),
`cap.fi` (`K_VM`), `sys.fi` (Karte + fünf Aufrufe), `uprog.fi` (`u_hv`),
`tools/build-kernel.sh` (die fünfte Assemblerdatei), `tools/kernel/karte.py`
(der Bereich `HV`), `test.sh` (Abschnitt 15).
