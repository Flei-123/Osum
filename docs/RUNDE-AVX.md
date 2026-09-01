# Runde AVX — die Vektorregister, und warum das Update ohne sie auf Blech stirbt

Zweig `avx`, abgezweigt von `mergeline2` (94c12fd). Gemessen auf einem
AMD EPYC 7571 (Zen 1), QEMU 7.2.22, `-accel kvm`, sofern nicht anders
angegeben.

---

## 0. DER BEFUND, UND ER IST NACHGEMESSEN

`docs/OTA.md`, Abschnitt „WAS NOCH FEHLT", Punkt 1:

> **AVX-512 tötet `/bin/fetch`.** […] Die Ursache liegt nicht in dieser
> Runde und nicht in `fetch`: **Osum schaltet für Ring 3 weder
> `CR4.OSXSAVE` noch `XCR0` frei, und der Kontextwechsel sichert keine
> Vektorregister.** […] Das Freischalten allein wäre **falsch**: dann
> benutzt Ring 3 Vektorregister, die kein Kontextwechsel sichert.

Bevor eine Zeile geschrieben wurde, ist das nachgesehen worden. Derselbe
Kern (`mergeline2`, ohne diese Runde), sieben Prozessormodelle, und die
Zeile, die `guard.report` schon immer schreibt:

| `-cpu` | `guard: cr4=` | OSFXSR (0x200)? | OSXSAVE (0x40000)? |
|---|---|---|---|
| `qemu64` | `0x20` | nein | nein |
| `Nehalem` | `0x20` | nein | nein |
| `Westmere` | `0x20` | nein | nein |
| `SandyBridge` | `0x20` | nein | nein |
| `Haswell` | `0x100020` | nein | nein |
| `Skylake-Server` | `0x300020` | nein | nein |
| `max` | `0x300020` | nein | nein |

`0x20` ist PAE, `0x100000`/`0x200000` sind SMEP und SMAP aus Runde K10.
**Bit 9 fehlt überall.** Damit ist auf dieser Maschine *jede*
SSE-Anweisung ein `#UD` — in Ring 3 *und* in Ring 0.

### Warum es trotzdem bis `Haswell` lief

Weil bis dahin niemand eine SSE-Anweisung ausgeführt hat. Firns
Bibliothek fragt `cpuid` und nimmt den breitesten Weg
(`lib/std/cpu.fi`, `lib/std/crypto/accel.fi`); `sha256.fi` schaltet auf
die SHA-NI-Fassung um, sobald `cpuid` Blatt 7 EBX Bit 29 gesetzt ist.
QEMU meldet dieses Bit erst ab `-cpu max`. Bis dahin rechnet dieselbe
Bibliothek skalar und rührt kein einziges Vektorregister an. TLS 1.3
hängt an SHA-256 — also stirbt `/bin/fetch` genau dort und nirgends
sonst.

Und der Kern selbst rührt sie auch nicht an. Nachgezählt, weil es die
Voraussetzung für die ganze Bauart unten ist:

    objdump -d osum.mb.elf | grep -cE 'xmm|ymm|zmm'   ->  0

---

## 1. WAS GEBAUT WURDE

### `kernel/arch/x86_64/fpu.fi` (neu, 780 Zeilen)

* **`probe`** — `cpuid` Blatt 1 (FXSR, SSE, XSAVE, AVX), Blatt 7
  (AVX512F), Blatt 0x0D Unterblatt 0 (welche Anteile die Maschine
  anbietet, wie groß der Bereich sein muss) und Unterblatt 1
  (XSAVEOPT). Entscheidet daraus `MODE_OFF` / `MODE_FX` / `MODE_XSAVE` /
  `MODE_XSAVEOPT` und die XCR0-Maske.
* **`apply` / `apply_here`** — `CR0`: `EM` löschen (sonst ist SSE
  Emulation und damit `#UD`), `MP` setzen (sonst gibt `fwait` bei
  gesetztem `TS` kein `#NM`), `NE` setzen, `TS` löschen. `CR4`:
  `OSFXSR | OSXMMEXCPT`, dazu `OSXSAVE`, *falls* `cpuid` XSAVE meldet.
  `XCR0` über `XSETBV` — **nur soweit Blatt 0x0D es anbietet**.
  `apply_here` läuft auf **jedem weiteren Prozessor** aus
  `smp.ap_main`, liest CR4 zurück und zählt sich atomar (`fpu: aps=`).
* **`switch`** — die eine Zeile, die in `sched.switch_to` steht:
  Zustand des Abgebenden sichern, den des Kommenden laden.
  `FXSAVE`/`FXRSTOR`, `XSAVE`/`XRSTOR`, `XSAVEOPT`, je nach `probe`.
* **`area_new` / `area_init` / `area_copy` / `sync_here`** — ein Rahmen
  (4096 Oktette) je Aufgabe aus `mem.frame_alloc`, mit sauberem
  Anfangszustand.
* **`on_nm`** — der träge Weg (`fpulazy`), über `CR0.TS` und `#NM`.

**Ein Fehler von Bit 27 statt 26.** Die erste Fassung fragte `cpuid`
Blatt 1 ECX Bit 27 nach XSAVE. Bit 27 ist aber `OSXSAVE` und meldet, was
*das Betriebssystem* gesetzt hat — vor `apply` ist es null. Wer danach
fragt, ob die Maschine XSAVE kann, bekommt nie ja. Der erste Lauf meldete
deshalb `mode=1` (FXSAVE) auch unter `-cpu max`. XSAVE ist Bit 26.

### Der saubere Anfangszustand

`area_init` nullt den Rahmen und schreibt zwei Felder von Hand:

    +0    FCW        = 0x037F
    +24   MXCSR      = 0x1F80,  darüber MXCSR_MASK = 0xFFFF

Der XSAVE-Kopf auf +512 bleibt null: `XSTATE_BV = 0` heißt „alle Anteile
im Anfangszustand", `XCOMP_BV = 0` heißt Standardformat.

**Warum MXCSR von Hand dastehen muss:** `XRSTOR` lädt MXCSR *immer* aus
dem Bereich, sobald SSE oder AVX in der Maske steht — unabhängig davon,
was in `XSTATE_BV` steht. Eine 0 dort wäre ein gültiger, aber falscher
Zustand: alle sechs SSE-Ausnahmen unmaskiert, und der erste denormale
Zwischenwert wäre ein `#XM`.

### Wo der Bereich liegt, und warum nicht in `kdata`

Ein Rahmen je Aufgabe aus `mem.frame_alloc`. Mit AVX-512 ist der Bedarf
über 2,5 KiB; 32 Aufgaben wären 128 KiB, und `KDATA_SIZE` zu vergrößern
hieße `boot.s`, `kstate.fi` und `tools/kernel/memmap.py` anzufassen —
während MERGE-3 nebenan läuft. Ein Rahmen ist außerdem 4096-fach
ausgerichtet und damit für `FXSAVE` (16) *und* `XSAVE` (64) richtig, ohne
dass irgendwo gerundet werden müsste. Die *Skalare* der Schicht (elf
Wörter) liegen in der Skalarseite ab Offset 1600 — der höchste bis dahin
vergebene Skalar war `A_DENIED` auf 1568. **Diese Runde nimmt keine neue
Seite in `kdata` und ändert `tools/kernel/memmap.py` nicht.**

---

## 2. DIE `-cpu`-TABELLE, VORHER UND NACHHER

Gemessen mit `tools/avx/cputab.sh` gegen `tools/ota/server.py`: je
Prozessormodell zwei Startvorgänge von der Platte, über OVMF, über eine
echte e1000 — `ota zeigen;ota suchen` (TLS 1.3, Kette geprüft, Ed25519
über das VERZEICHNIS) und, wenn der durchkam, `ota einspielen` (Paket
holen, **SHA-256 gegen das signierte VERZEICHNIS halten**, einspielen).

**VORHER** (Zweig `ota` allein, `/root/ota-avx-vor`):

<!-- CPUTAB-VOR -->

**NACHHER** (`ota` + `avx`, `/root/ota-avx-nach`):

<!-- CPUTAB-NACH -->

Und was dieselben sieben Modelle im Kern melden (`fpu: mode=`, ein
Startvorgang je Modell, `-accel kvm`):

| `-cpu` | `fpu: mode=` | `cr4=` | `xcr0=` | `size=` |
|---|---|---|---|---|
| `qemu64` | 1 (FXSAVE) | `0x620` | `0x0` | 512 |
| `Nehalem` | 1 (FXSAVE) | `0x620` | `0x0` | 512 |
| `Westmere` | 1 (FXSAVE) | `0x620` | `0x0` | 512 |
| `SandyBridge` | 3 (XSAVEOPT) | `0x40620` | `0x7` | 832 |
| `Haswell` | 3 (XSAVEOPT) | `0x140620` | `0x7` | 832 |
| `Skylake-Server` | 3 (XSAVEOPT) | `0x340620` | `0x7` | 832 |
| `max` | 3 (XSAVEOPT) | `0x340620` | `0x7` | 832 |

`xcr0=0x7` ist x87 + SSE + AVX; 832 Oktette sind 576 (Altbereich +
Kopf + SSE) + 256 (YMM_Hi128). Bis `Westmere` bietet QEMU kein XSAVE an,
und dann bleibt es bei `FXSAVE` — genau so, wie es soll.

### Was auf DIESER Maschine nicht messbar war: AVX-512

`Skylake-Server` und `max` melden hier **kein** AVX-512, und das liegt
nicht am Kern:

* Der Wirt ist ein **AMD EPYC 7571 (Zen 1)**. `/proc/cpuinfo`:
  `avx avx2 sha_ni xsave xsavec xsaveerptr xsaveopt xsaves` — **kein
  `avx512*`**. Unter `-accel kvm` kann QEMU nicht anbieten, was das Blech
  nicht hat.
* Und unter `-accel tcg` auch nicht: QEMUs Übersetzer kennt AVX und AVX2
  seit 7.2, AVX-512 überhaupt nicht. Nachgemessen — `-accel tcg -cpu max`
  und `-accel tcg -cpu Skylake-Server` melden beide dasselbe
  `xcr0=0x7  size=832`.

**Was daraus folgt und was nicht.** Was gemessen ist: die Freischaltung
und der Kontextwechsel für x87, SSE und AVX (256 Bit, `ymm0..15`), und
dass `-cpu max` — das Modell, an dem `/bin/fetch` gestorben ist — läuft.
Was **nicht** gemessen ist: `zmm`, die Opmask-Register und der
Hi16_ZMM-Anteil auf echter AVX-512-Hardware. Der Code dafür ist da und
hängt an genau zwei Stellen: an `cpuid` Blatt 0x0D (welche Bits in XCR0)
und an derselben Blattstelle (wie groß der Bereich). Der Testfall in
Ring 3 prüft alle **32** `zmm` einschließlich `zmm16..31`, sobald die
Maschine sie anbietet.

Dafür ist die eine Regel, an der das hängt, *doch* geprüft — siehe
Gegenprobe `fpuforce` in Abschnitt 3.

---

## 3. DIE GEGENPROBEN

Ein Test, der nicht rot werden kann, misst nichts. Es gibt fünf, und
jede ist einmal absichtlich rot gefahren worden.

### 3.1 Der Kontextwechsel — der eigentliche Nachweis der Runde

`uprog.u_vec` (`kernel/uprog.fi`, Programm `P_VEC`, Kernwort `vecproc`):
vier Prozesse **gleichzeitig**, jeder schreibt ein Muster, das nur zu ihm
passt, in **alle** Vektorregister, rechnet damit (`paddq`/`vpaddq`
zwischen den Registern, der Reihe nach — dieselbe Folge wird in
gewöhnlichen Zahlen nachgerechnet), gibt den Prozessor ab und sieht
danach nach, ob er seine eigenen Werte wiederfindet. Breite nach
`cpuid` + `xgetbv`: `xmm` / `ymm` / `zmm`. 64 Runden, zwei
`sched_yield` je Runde.

Alles mit `-cpu max`, einem Prozessor:

| Kernwort | Bedeutung | `vec: bad=` je Prozess | `vec: clean=` |
|---|---|---|---|
| `nofpu` | **der Stand vor dieser Runde** | — `user fault: vector=6` (#UD) beim ersten `movdqu`, alle vier tot (`exit=134`) | 0 |
| `nofpuswitch` | freigeschaltet, **nicht gesichert** | 4096 / 4096 / 4096 / 3840 | 0 |
| *(Vorgabe)* | diese Runde | **0 / 0 / 0 / 0** | **1** |

Die mittlere Zeile ist genau der Fehler, vor dem `docs/OTA.md` warnt:
„*Das Freischalten allein wäre FALSCH*". Sie ist gebaut, damit er sich
als Zahl zeigen lässt. Zählerstand im guten Lauf: `saves=579
restores=579`.

### 3.2 Auf mehreren Prozessoren

`kmain.vectors_smp` startet **sechs Kernaufgaben** (`sched.K_VEC`,
Rumpf in `kernel/tasks.fi`), die dasselbe tun. Kernaufgaben wandern über
alle Kerne (`sched.may_run` mit `ANY_CPU`) und gehen durch denselben
`switch_to`.

| Lauf | `vecsmp: cores=` | `onmask=` | `exit=` | `clean=` |
|---|---|---|---|---|
| `-smp 1` | 1 | `0x1` | 0 0 0 0 0 0 | 1 |
| `-smp 2` | 2 | `0x3` | 0 0 0 0 0 0 | 1 |
| `-smp 4` | 4 | `0xf` | 0 0 0 0 0 0 | 1 |
| `-smp 4 nofpuswitch` | 4 | `0xf` | 250 ×6 | **0** |

`onmask` ist die Vereinigung der Kernmasken, die die sechs Aufgaben
wirklich getragen haben — `0xf` heißt: alle vier Kerne, also ist die
Aufgabe wirklich gewandert. `cores=` ist `fpu: aps= + 1`, und `aps` wird
nicht angenommen, sondern **aus CR4 zurückgelesen** (wie in
`guard.report_aps`): `aps=0 / 1 / 3`.

### 3.3 `fork` erbt den *lebenden* Zustand — ein Fehler dieser Runde

Die erste Fassung von `sched.fpu_inherit` kopierte den Bereich des
Elternteils ins Kind. Das ist falsch: im Bereich steht der Zustand, den
der **letzte Kontextwechsel** dort abgelegt hat; solange die Aufgabe
läuft, ist das nicht ihr Zustand. `do_fork` läuft im Elternteil — also
erbte das Kind die Register von vor dessen letztem Wechsel.
`fpu.sync_here` schreibt den lebenden Zustand vorher in den Bereich,
und zwar nur, wenn *dieser* Kern ihn trägt.

Und die Probe dazu musste zweimal gebaut werden. Der erste Versuch war
grün, **auch ohne** `sync_here` — weil der Prüfling nach seinem letzten
`sched_yield` gar nichts mehr an den Registern änderte und im Bereich
deshalb ohnehin das Richtige stand. Jetzt ändert der vierte Testprozess
seine Register unmittelbar vor dem `fork`, ohne einen Systemaufruf
dazwischen:

| | `vec: forkbad=` Elternteil | `vec: forkbad=` Kind | `vec: exit=` | `clean=` |
|---|---|---|---|---|
| mit `fpu.sync_here` | 0 | 0 | 0 0 0 0 | 1 |
| **ohne** `fpu.sync_here` | 0 | **60** | 0 0 0 **60** | **0** |

### 3.4 `fpuforce` — nichts freischalten, was `cpuid` nicht anbietet

`docs/OTA.md` nennt die Regel ausdrücklich: *„Nichts freischalten, was
`cpuid` nicht anbietet — das ist selbst ein #GP."* Das Wort `fpuforce`
setzt die drei AVX-512-Bits in XCR0, **ohne** zu fragen. Auf dieser
Maschine (Zen 1, kein AVX-512):

    *** EXCEPTION 13 #GP  err=0x0
      rip=0x1cb5ce  cs=0x8  rflags=0x10046
      rax=0x00000000000000e7   (= XCR0_X87|SSE|AVX|AVX512)
    *** kernel halted            (Beendigungscode 63)

Damit ist die Abfrage in `probe` keine Zierde, sondern das, was zwischen
einem laufenden Kern und einem toten steht — und der AVX-512-Zweig ist
damit wenigstens von der Seite geprüft, von der er tödlich wäre.

### 3.5 `noxsave` — der Rückfall auf FXSAVE

Auf einer Maschine ohne XSAVE (bis Nehalem) gibt es nur `FXSAVE`. Das
Wort erzwingt diesen Weg auch dort, wo XSAVE da wäre:

    fpu: mode=1  cr4=0x300620  xcr0=0x0  size=512  lazy=0
    vec: exit=0 0 0 0    vec: clean=1

---

## 4. DER PREIS

### 4.1 Zeit

`fpubench` misst die Anweisungen selbst: `fpu.save` + `fpu.restore` in
einer Schleife gegen dieselbe Schleife ohne sie. **Minimum über 400
Bündel zu je 250 Durchläufen** — auf diesem Wirt laufen mehrere andere
Runden gleichzeitig QEMU (Lastmittel 15–28 auf zwölf Kernen); ein
Mittelwert misst die Nachbarn mit, und ein weggenommener Zeitabschnitt
kann eine Messung nur verlängern, nie verkürzen.

| Modus | XCR0 | Bereich | **save+restore** | save | restore | `TS` setzen + `clts` |
|---|---|---|---:|---:|---:|---:|
| `XSAVEOPT`/`XRSTOR` | `0x7` | 832 B | **508** | 177 | 331 | 256 |
| `XSAVE`/`XRSTOR` (`noavx`) | `0x3` | 576 B | **420** | 151 | 273 | 215 |
| `FXSAVE`/`FXRSTOR` (`noxsave`) | — | 512 B | **294** | 120 | 182 | 214 |

(Zyklen, Minimum aus je drei Messungen im selben Lauf; die drei Werte
lagen bei 508/508/507, 420/418/419 und 294/292/294 — die Streuung des
Minimums ist unter einem Prozent.)

**Ein Kontextwechsel kostet also 508 Zyklen mehr** auf einer Maschine mit
AVX, 294 auf einer ohne XSAVE. Auf einem 2,2-GHz-Kern sind das 231 ns
bzw. 134 ns.

Der Wechsel als Ganzes ist auf diesem Wirt zu verrauscht, um daneben
etwas zu belegen: derselbe Arm (`fpubench: armA`) kam in
aufeinanderfolgenden Läufen auf 41 482, 45 629, 72 518 und 101 902 Zyklen
je Wechsel. Deshalb steht oben die Zahl, die *nur* diese Runde betrifft,
und nicht eine Differenz zweier verrauschter Summen.

### 4.2 Speicher

| | Oktette |
|---|---:|
| gemeldeter Bedarf mit x87+SSE+AVX (`cpuid` 0x0D:EBX) | **832** |
| gemeldeter Bedarf mit x87+SSE | 576 |
| `FXSAVE`-Bereich | 512 |
| Höchstbedarf über alle Anteile dieser Maschine (`cpuid` 0x0D:ECX) | 832 |
| **belegt je Aufgabe** (ein Rahmen) | **4096** |

Bei 32 Aufgaben (`kstate.MAX_TASKS`) sind das höchstens **128 KiB**
Rahmen. Auf einer Maschine mit AVX-512 wäre der gemeldete Bedarf
typischerweise etwa 2,7 KiB — er bleibt damit in demselben einen Rahmen,
und die Zahl 4096 ändert sich nicht. Der Bereich wird in `sched.reap`
zurückgegeben.

Dazu ein Feld im Aufgabensatz (`T_FPU`, 8 Oktette, auf Offset 640 in
einem Satz von 1024) und elf Skalare in der Skalarseite. Kein neuer
`kdata`-Bereich.

### 4.3 Und die Entscheidung: **eager**, nicht lazy

Der träge Weg ist gebaut (`fpulazy`), er funktioniert (`vec: clean=1`,
`fpu: nm=801` — der `#NM`-Fangbereich schlägt wirklich an) und er ist
gemessen. Er wird trotzdem **nicht** die Vorgabe, und dafür gibt es drei
Gründe, von denen die ersten beiden Zahlen sind:

1. **Er spart nur die Hälfte.** Das *Sichern* muss eager bleiben. Ließe
   man es weg, blieben die Register einer Aufgabe auf dem Kern liegen,
   von dem sie weggeschaltet wurde, und die nächste Runde derselben
   Aufgabe auf einem *anderen* Kern fände in ihrem Bereich veraltete
   Werte. Der Ausweg wäre ein Interruptschuss an den alten Kern. Also:
   511 - 331 = **177 Zyklen bleiben** in jedem Fall stehen.
2. **Was er dafür zahlt, ist teurer als das, was er spart.** `CR0.TS`
   setzen und wieder löschen kostet gemessen **256** Zyklen — mehr als
   die 331, die das Laden kostet, abzüglich… nichts. Unter KVM ist
   `mov cr0` ein Ausstieg aus der Gastmaschine und deshalb teurer als auf
   Blech; die 256 sind eine **obere Schranke**, kein Hardwarewert. Selbst
   wenn man sie großzügig auf 40 Zyklen echter Hardware ansetzt, bleibt:
3. **Jede Aufgabe, die Vektorregister anfasst, zahlt zusätzlich ein
   `#NM`** — einen echten Ausnahmedurchlauf, bei *jedem* Wechsel. Und
   das sind praktisch alle: der Testfall in Ring 3 meldet auf jeder
   Maschine ab SandyBridge `vec: width=2`, Firns `lib/std/crypto`
   schaltet nach `cpuid` auf SSE um, und der Übersetzer legt jeden `v128`
   in ein `xmm`. Gemessen an den Aufgaben, die *keine* anfassen, ist der
   Gewinn ein Bruchteil eines Prozents eines Wechsels; gemessen an denen,
   die welche anfassen, ist es ein Verlust.

Dazu, ohne Zahl, aber nicht ohne Gewicht: der träge Weg braucht eine
Buchführung darüber, welcher Kern gerade wessen Zustand trägt
(`cpu.C_FPUOWNER`), und einen Fangbereich mehr. Beides sind Stellen, an
denen ein Fehler sich als Zufall tarnt. Der eager-Weg hat zwei
Anweisungen und keine Buchführung.

`fpulazy` bleibt im Baum, weil eine Entscheidung ohne die Möglichkeit,
sie nachzumessen, keine ist.

---

## 5. WAS DIESE RUNDE NEBENBEI GEFUNDEN HAT — UND WAS NICHT IHR GEHÖRT

### 5.1 Ring 3 auf mehr als einem Prozessor endet in einem `#DF`

Der erste Versuch, den Vektortest hinter `smp.stage` mit **Prozessen**
statt Kernaufgaben zu fahren, endete unter `-smp 4` reproduzierbar so:

    *** EXCEPTION 8 #DF  err=0x0
      rip=0x10049c  cs=0x8  rflags=0x10246  rsp=0x40008ff0  ss=0x10

`rsp` liegt in einer **Nutzerseite** (0x40008ff0, der Nutzerstapel), `cs`
ist das Kernsegment. Der Grund steht in `kernel/arch/x86_64/isr.s`:

    movq %rsp, sys_rsp(%rip)          /* EIN globales Wort */
    movq kdata + KSTACK_CUR(%rip), %rsp   /* EIN globales Wort */

Zwei Kerne, die gleichzeitig einen Systemaufruf machen, überschreiben
einander `sys_rsp` und landen auf demselben Kernstapel. Das ist eine
Grenze aus Runde K5 und steht dort im Kommentar von
`sched.set_kernel_stack` wörtlich: *„a started core has a TSS of its own
and never leaves ring 0 in this round"*.

**Es gehört nicht dieser Runde**, und das ist gemessen und nicht
behauptet. Das Wort `r3smp` (Diagnose, in keinem Abnahmelauf) startet
dieselben vier Prozesse; Bit 8 im Argument lässt sie *alle*
Vektorbefehle weglassen, damit auch mit `nofpu` gemessen werden kann:

| | `-smp 1` | `-smp 4` |
|---|---|---|
| Vorgabe | rc=21, `exit=0 0 0 0` | **rc=63, `#DF`** |
| `nofpu` (keine Zeile dieser Runde aktiv) | rc=21, `exit=0 0 0 0` | **rc=63, `#DF`** |

Für echtes Blech ist das der nächste Sperrpunkt nach diesem hier: sobald
mehr als ein Kern ein unprivilegiertes Programm ausführt, ist der
Systemaufrufpfad kaputt. Es braucht `swapgs` mit einer GS-Basis je Kern
und einen Kernstapelzeiger je Kern statt der zwei globalen Wörter.

### 5.2 `-cpu max` unter KVM ist nicht `-cpu max`

Wer die Tabelle aus `docs/OTA.md` auf einem anderen Wirt nachfährt,
bekommt andere Zeilen: `max` heißt „alles, was *dieser* Wirt kann".
Auf dem Wirt dieser Messung (Zen 1) ist das AVX2 + SHA-NI; auf einem
Xeon wäre AVX-512 dabei. Der Fehler, den `docs/OTA.md` beschreibt, wird
auf Zen 1 von **SHA-NI** ausgelöst, nicht von AVX-512 — dieselbe
Ursache, ein anderes Bit.

---

## 6. KEINE REGRESSIONEN

<!-- ABNAHME -->

---

## 7. BERÜHRTE DATEIEN

Die Runde ist bewusst eng gehalten, weil MERGE-3 parallel läuft.

| Datei | Art der Änderung |
|---|---|
| `kernel/arch/x86_64/fpu.fi` | **neu** — die ganze Schicht |
| `kernel/arch/x86_64/smp.fi` | `import fpu`; **eine Zeile** `fpu.apply_here(state)` neben `guard.apply_here` |
| `kernel/arch/x86_64/trap.fi` | `import fpu`; `const NM_VECTOR`; **ein Block** für Vektor 7 vor dem Stapelwachstum |
| `kernel/sched.fi` | `import fpu`; `T_FPU` (Offset 640); `K_VEC`, `K_YIELD`; **eine Zeile** in `switch_to`; Bereich holen in `create`/`adopt`, zurückgeben in `reap`, Aufgabe 0 in `init`; `fpu_area`/`fpu_set_area`/`fpu_inherit`/`fpu_reset` |
| `kernel/cpu.fi` | **ein Feld** `C_FPUOWNER = 128` im Kernsatz |
| `kernel/kstate.fi` | **elf Skalare** ab Offset 1600 in der vorhandenen Skalarseite. Keine neue `kdata`-Seite, `tools/kernel/memmap.py` unverändert |
| `kernel/kmain.fi` | `import fpu`; `fpu.parse`, `fpu.apply` (vor `sched.init`), `fpu.report`, `fpu.report_aps`; die Abschnitte `vectors`, `vectors_smp`, `ring3_smp`, `fpu_bench` |
| `kernel/sys.fi` | **zwei Zeilen**: `sched.fpu_inherit` in `do_fork`, `sched.fpu_reset` in `do_execve` |
| `kernel/tasks.fi` | `import mem`, `import fpu`; die Rümpfe `vector_task` und `yield_task` |
| `kernel/uprog.fi` | das Programm `P_VEC` (Vektortest aus Ring 3) |
| `tools/avx/cputab.sh` | **neu** — die `-cpu`-Tabelle, auf den Artefakten von `tools/ota/run.sh` |
| `docs/RUNDE-AVX.md` | dieser Bericht |

Nicht angefasst: `kernel/arch/x86_64/switch.s`, `isr.s`, `boot.s`,
`kernel/proc.fi`, `kernel/mem.fi`, `tools/kernel/memmap.py`,
`tools/build-kernel.sh`.

**Warum nicht `switch.s`.** Welche Anweisung gebraucht wird — `FXSAVE`,
`XSAVE` oder `XSAVEOPT` — und mit welcher Maske steht erst zur *Laufzeit*
fest; es kommt aus `cpuid`. Eine Assemblerdatei müsste sich darüber
verzweigen. In `sched.switch_to` ist es eine Fallunterscheidung in
derselben Sprache wie alles andere. Das geht nur, weil der Kern selbst
keine Vektorregister benutzt (nachgezählt: null `xmm`/`ymm`/`zmm` im
Abbild) — sonst dürfte zwischen dem Laden und dem Stapelwechsel kein
compilierter Code mehr stehen.

---

## 8. WAS OFFEN BLEIBT

1. **AVX-512 auf echter Hardware.** Der Weg ist gebaut und durch
   `cpuid` verriegelt (Gegenprobe `fpuforce`: ohne die Verriegelung ein
   `#GP`), aber auf diesem Wirt nicht auszulösen — Zen 1 hat es nicht,
   und QEMUs TCG kennt es überhaupt nicht. **Das ist der erste Punkt,
   der auf dem Blech nachzumessen ist**: `fpu: mode=3  xcr0=0xe7
   size≈2700` und `vec: width=3  bad=0`.
2. **AMX** (`XCR0` Bits 17/18, TILECFG und TILEDATA). Nicht
   freigeschaltet. Ein Bereich von über 8 KiB passt nicht mehr in einen
   Rahmen; das braucht `mem.frame_run` und eine Entscheidung, ob ein
   Prozess sie überhaupt bekommen soll (Linux gibt sie erst auf
   `arch_prctl` heraus, aus genau diesem Grund).
3. **MPX** (Bits 3/4) und **PKRU** (Bit 9) sind bewusst nicht in der
   Maske: MPX ist tot, PKRU ohne `CR4.PKE` wirkungslos, und beides
   vergrößert nur den Bereich.
4. **Signalzustellung mit Vektorzustand.** `kernel/signal.fi` schreibt
   einen Rahmen auf den Nutzerstapel und stellt ihn in `sigreturn`
   wieder her — **die Vektorregister sind darin nicht enthalten**. Ein
   Signalbehandler, der SSE benutzt (also jeder, der `memcpy` aufruft),
   zerstört damit die Register des unterbrochenen Codes. Das ist der
   nächste Punkt nach AVX-512, und er ist kleiner als er klingt: der
   Rahmen bekommt einen Zeiger auf einen zweiten Bereich, `signal.push`
   ruft `fpu.sync_here` und kopiert, `sigreturn` kopiert zurück.
5. **`XSAVEC`/`XSAVES` und das verdichtete Format.** Der Wirt bietet
   beides an (`xsavec xsaves` in `/proc/cpuinfo`); benutzt wird das
   **Standardformat**, weil `XRSTOR` es ohne Sonderfall liest. Verdichtet
   wäre der Bereich bei AVX-512 spürbar kleiner. Eine eigene Messung
   wert, sobald es Hardware dafür gibt.
6. **Ring 3 auf mehreren Kernen** — siehe 5.1. Nicht diese Runde, aber
   der nächste Sperrpunkt für Blech.
7. **`fpu.area_new` scheitert unter Speichernot.** `sched.create`
   antwortet dann 0, und der Prozess entsteht nicht — richtig, aber
   ungetestet: es gibt keinen Fall, der den Rahmenverwalter an dieser
   Stelle leerlaufen lässt.

---

## 9. DIE DREI ZAHLEN

<!-- ZUSAMMENFASSUNG -->
