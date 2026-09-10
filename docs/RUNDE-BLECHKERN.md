# Runde BLECHKERN — der #UD auf Justins Blech, und warum der Prüfstand ihn nie sah

*05.09.2026 · Repo `/root/osum-blechhid` · Grundlage Commit `83f7dd8`
(das ausgelieferte Abbild `b2addaf7…`)*

---

## 0. Die kürzeste Fassung

Ein Anwendungskern durfte einen **Ring-3-Prozess** übernehmen. Er darf es
nicht — und dass er es nicht darf, stand seit Runde K5 wörtlich im
Quelltext, als ausdrückliche Bedingung, mit Begründung. **Durchgesetzt
wurde die Bedingung nie.** Jeder Prozess bekam beim Anlegen `ANY_CPU`.

Meine Abnahme lief mit **einem** vCPU. Justins Brett hat mehrere. Das ist
der ganze Unterschied zwischen „164 Anstriche, null Ausnahmen“ und
„nichts geht mehr, nicht mal die Maus“.

---

## 1. Justins Zahlen, und was sie wirklich sagen

    *** ABSTURZ ***  VEK 6  #UD
    RIP  0000000000000080
    CR2  000000004007D7A8   (ALT, gilt nur bei PF)
    ERR  00000000   CS 0008
    RSP  0000000000990C00
    STUFE ST 22 MAX 22 RND 0
    AUF 4 PID 5 ART 1 PRG  BAD 0
    KERN 2 HAELT AN -- BITTE FOTO  NR 2

Punkt für Punkt, gegen Justins eigene Deutung geprüft:

| seine Deutung | Befund |
|---|---|
| 1. Vektor 6 ist #UD, ein anderer Fehler als letzte Runde | **richtig** |
| 2. `RIP 0x80` = Sprung über einen Müllzeiger, Feldabstand 0x80 | **halb richtig.** Es ist ein Sprung über eine kaputte Adresse — aber kein Feldabstand einer Struktur, sondern der Rest einer **überschriebenen Rücksprungkette**. Das Muster ist dasselbe wie `rip=0xd70` in Runde LEISTE: bei jedem Lauf eine andere Zahl. |
| 3. `CS 0008` = Ring 0, der Kern springt selbst ins Nirwana | **richtig, und es ist der entscheidende Hinweis** |
| 4. `RSP 0x990C00` sieht nach gesundem Kernstapel aus, also kein Überlauf | **richtig — und trotzdem war es ein Stapelproblem.** Nicht *über*gelaufen, sondern **von zwei Kernen gleichzeitig benutzt**. Dabei bleibt `rsp` plausibel; zerstört wird der *Inhalt*. |
| 5. „PRG BAD“ — ist der Programmname Müll? | **nein.** `PRG` und `BAD` sind zwei Felder: `PRG <name>` (hier leer, weil eine Kernaufgabe keinen Prozessnamen hat) und `BAD <n>` = `proc.badentry_zahl()`, die Zahl der abgelehnten Einsprünge, hier 0. `AUF 4` = Platz 4 der Aufgabentabelle, `PID 5`, **`ART 1` = `K_IDLE`** — die Leerlaufaufgabe. |
| 6. Es müssten ALLE Kerne angehalten werden | **richtig, war nicht so, ist jetzt so** (Abschnitt 5) |

`ART 1` und `KERN 2` zusammen sagen: es starb die **Leerlaufaufgabe des
Anwendungskerns 2**. `STUFE ST 22` sagt, wo Kern 0 in derselben Sekunde
stand: in `desk_start` — beim Starten der Ring-3-Programme.

---

## 2. Der Mechanismus

`kernel/arch/x86_64/isr.s`, Einsprung eines Systemaufrufs:

```asm
    movq %rsp, sys_rsp(%rip)
    movq kdata + KSTACK_CUR(%rip), %rsp
```

**Ein** Wort für die ganze Maschine. Und `sched.set_kernel_stack`:

```
fn set_kernel_stack(state: u64, ktop: u64) {
    if cpu.here(state) != 0 {
        return
    }
```

Nur Kern 0 schreibt es. Das ist kein Versehen — daneben steht der Satz,
worum es geht:

> *A core that wrote its kernel task's stack into that word would send
> the next system call of a ring 3 process onto a stack somebody else is
> standing on.*

Und `kernel/arch/x86_64/smp.fi` sagt, welche Bedingung daraus folgt:

> *WHAT THIS ROUND DELIBERATELY DOES NOT DO. **Ring 3 stays on the boot
> processor.** … Until then the application processors run kernel tasks.*

`sched.create` setzte aber für **jede** Gattung:

```
    tc_set(state, slot, TC_AFF, ANY_CPU)
```

Damit nahm Kern 2 den Starter, die Leiste oder den Schreibtisch. Deren
nächster `syscall` landete auf dem Kernstapel der Aufgabe, die gerade auf
**Kern 0** lief. Zwei Kerne, ein Stapel. Zusätzlich zeigt die TSS eines
gestarteten Kerns (`RSP0`) auf dessen **eigenen** Startstapel — also
genau dorthin, wo seine übernommene Leerlaufaufgabe steht. Eine
Unterbrechung aus Ring 3 auf Kern 2 schreibt ihren Rahmen mitten in
deren gesicherten Zusammenhang. Beim nächsten Wechsel zurück holt sich
die Leerlaufaufgabe ihre Rücksprungadresse — und die ist jetzt `0x80`.

**Deshalb `ART 1` auf `KERN 2`.** Der Sterbende ist nicht der Täter,
sondern das Opfer.

---

## 3. Der Beweis: dieselbe Datei, nur die Kernzahl verschieden

Das **ausgelieferte** Abbild `b2addaf7…`, unverändert, über Limine unter
UEFI, `-accel kvm -cpu host`, 3440×1440, xHCI, e1000. Einziger
Unterschied: `-smp`.

| Lauf | Protokollzeilen | Ausnahmen | Ausgang |
|---|---|---|---|
| **`-smp 1`** | 791 | **0** | Leiste läuft, sauber |
| **`-smp 4`** | 291 | `#DB rip=0x100453`, `#GP`, `#UD` | tot |
| **`-smp 8`** | 284 | `#DF`, `user fault err=0xf`, `#DB`, `lock: stuck id=0 owner=6` | tot |

Der `-smp 8`-Lauf bricht an **derselben Stelle** ab wie Justins Foto:

    taskbar: shape file= name= id=0 keys=0 ctrl_h=26
    taskbar: ready ascent=12
    user fault: pid=20  vector=14  err=0xf  cr2=0x4007a0e8  rip=0x4011f77c

`err=0xf` hat das RESERVED-Bit gesetzt: die Seitentafeln selbst waren
schon beschrieben.

**Warum es die letzte Abnahme nicht fand:** sie lief ohne `-smp`, also
mit einem vCPU. Ein Prüfstand, der die Maschine nicht baut, die geprüft
werden soll, prüft nichts. Ab dieser Runde läuft die Abnahme mit vier
Kernen.

---

## 4. Der Eingriff

### 4.1 `sched.create` — Ring 3 bleibt auf Kern 0

```
    if kind == K_USER {
        tc_set(state, slot, TC_AFF, 0)
    } else {
        tc_set(state, slot, TC_AFF, ANY_CPU)
    }
```

Kernaufgaben (`K_WORKER`, `K_GRIND`, `K_NETD`, `K_AIO`, `K_VEC`) bleiben
auf allen Kernen — sie verlassen Ring 0 nie und haben mit `KSTACK_CUR`
nichts zu tun. Der SMP-Nutzen bleibt also, verloren geht nur die
Wanderung von Benutzerprozessen, und die war nie zugesagt.

### 4.2 `sched.pick` — der Riegel, der nicht in fremdem Speicher steht

Die Bindung steht in einer Nebentabelle, also in Speicher, den ein
Überlauf umschreiben kann — und davon handelt diese Runde. Deshalb
dieselbe Bedingung noch einmal aus der **Gattung** hergeleitet:

```
fn darf_ring3(state: u64, i: u64, me: u64) -> bool {
    return me == 0 || tget(state, i, T_KIND) != K_USER
}
```

### 4.3 `R3F` auf der Messtafel, Zeile 12

```
tafel: 12 STUFE ST 38 MAX 38 RND … WA 0 T 0 KS 39336 R3F 0
```

`R3F` = Ring-3-Prozesse, die zuletzt auf einem Kern ≠ 0 gelaufen sind.
**Muss null bleiben, genau wie `WA`.** Steht dort etwas anderes, ist die
Bindung durchbrochen und jede andere Zahl auf der Tafel ist eine
Vermutung. Die Zeile färbt sich dann rot.

### 4.4 Der Stapel eines Anwendungskerns: 16 KiB → 64 KiB, mit Wache

`AP_STACK_FRAMES` stand auf 4 mit dem Kommentar *„16 KiB, as a task
gets“*. Das stimmte, bis Runde LEISTE die Aufgabenstapel auf 16 Rahmen
setzte (gemessener Höchststand damals `KS 46688`). Der Kommentar blieb
und war ab da falsch — der Anwendungskern fuhr mit einem Drittel dessen,
was derselbe Ablaufplaner auf Kern 0 braucht. Und dieser Stapel hat
keine Wache: er gehört einer Aufgabe aus `sched.adopt`, die `T_KSTACK = 0`
trägt, und `guard_check` sieht sie deshalb nicht an. Jetzt 16 Rahmen
plus ein bemalter Wachrahmen darunter (`smp.wache_brueche`).

---

## 5. Die Absturzanzeige sagt jetzt drei Dinge mehr

### 5.1 Woher der Sprung kam — Zeile `SPUR`

`spur_sagen` aus Runde LEISTE liest über `proc.translate` und sucht im
Bereich der **Benutzerprogramme**. Ein Absturz in Ring 0 — und Justins
war einer, `CS 0008` — fiel komplett durch. Neu: `trap.kspur_bauen` liest
den **Kernstapel** unmittelbar und sucht Zahlen zwischen `0x100000` und
`_etext`.

`_etext` ist neu (`kernel/kernel.ld`, erreichbar als Nummer 74 der
Tabelle aus `isr.s`) und der Unterschied ist messbar. Mit `KERNEL_END`
als oberer Schranke:

    SPUR 00578000 001430BC 0055FC00 0055FBC0     ← 1 von 4 ist Code

Mit `_etext`:

    SPUR 00143195 0018C641 002808CC 0028C1A4     ← 4 von 4 sind Code

    0x143195  sched.irq_restore   sched.fi:715
    0x18c641  elf.build           elf.fi:974
    0x2808cc  wm.gs               wm.fi:683
    0x28c1a4  wm.raise_win        wm.fi:2468

### 5.2 Und sie steht auf dem SCHIRM, nicht nur auf der Leitung

Justins Brett hat keine serielle Leitung. `SPUR` ist deshalb Zeile **8**
der Absturzanzeige. Zeile **9** sagt, was mit den anderen Kernen
geschieht. Umgekehrt geht jede Zeile der Anzeige jetzt auch auf die
Leitung (`absturz: <nr> <text>`) — damit der Prüfstand nachlesen kann,
was auf dem Schirm steht, statt es zu fotografieren und mit dem Auge zu
vergleichen.

### 5.3 Alle Kerne halten an

`power.halt_forever` ist `cli; hlt` und hält **den Kern an, auf dem es
läuft**. Neu: der sterbende Kern schickt einen **NMI an alle anderen**
(ICR `0xC4400`: Zustellart NMI, Kurzform „alle außer sich selbst“), und
der erste Befehl des Fangnetzes ist der Riegel dagegen:

```
fn entry(frame: u64, state: u64) {
    if halt_alle != 0 {
        power.halt_forever()
    }
```

Reihenfolge mit Absicht: **erst das Bild, dann die Maschine stilllegen.**
Ein Kern, den ein NMI mitten in einer Sperre des Fensterservers trifft,
gibt sie nicht mehr her.

Gemessen, Absturz auf Bestellung (`knall`), `-smp 4`:

    absturz:  0 *** ABSTURZ *** VEK 14 #PF
    absturz:  1 RIP 00000000002C6AC5
    absturz:  2 CR2 00007FFFFFFF0000
    absturz:  3 ERR 00000002  CS 0008
    absturz:  4 RSP 000000000055FB90
    absturz:  5 STUFE ST 37 MAX 37 RND 0
    absturz:  6 AUF 0 PID 1 ART 0 PRG  BAD 0
    absturz:  7 KERN 0 HAELT AN -- BITTE FOTO  NR 1
    absturz:  8 SPUR 00143195 0018C641 002808CC 0028C1A4
    absturz:  9 ANDERE KERNE: 3 NMI, MASCHINE STEHT

Und nach `*** kernel halted` kommt **keine Zeile mehr**. Vorher lief der
Rest der Maschine weiter und übermalte die Anzeige — genau das, was
Justin am 04.09. gesehen hat.

---

## 6. Offene Kante, ausdrücklich benannt

`KSTACK_CUR` **je Kern** ist nicht gebaut. Solange es das nicht gibt,
laufen Benutzerprozesse nur auf Kern 0 — auf einem Rechner mit acht
Kernen also die ganze Oberfläche auf einem. Der Weg dahin steht seit
Runde K5 fest (GS-Basis oder ein zweiter Tabellenzugriff im
Systemaufruf-Einsprung, in Assembler, vor dem ersten Stapel), und dazu
gehört, dass `switch_to` die `RSP0` der TSS **des jeweiligen Kerns**
nachführt. Das ist eine eigene Runde.

Diese Runde macht das System **richtig statt schnell**. In dieser
Reihenfolge.

---

## 7. Noch ein Fund: der Startknopf hat nie ein Programm gestartet

Zum ersten Mal hat ein Lauf den 30 Bildpunkte breiten Knopf wirklich
getroffen (`taskbar: click x=20 y=21 hits=start`) — und dahinter stand:

    taskbar: launcher pid=-22

`-22` ist `EINVAL`. `taskbar.startmenue_um` rief `SYS_SPAWN` (1000) mit
dem **Pfad** `/bin/launcher`. `SYS_SPAWN` nimmt aber keine Anschrift,
sondern eine Nummer aus `uprog.fi`:

```
fn do_spawn(state, me, prog, arg) {
    if prog == 0 || prog > 16 { return neg(errno.E_INVAL) }
```

Ein Zeiger ist immer größer als 16. Der Aufruf konnte also **nie**
gelingen. Richtig ist `SYS_EXEC` (1001), so wie `explorer`, `firun` und
`launcher` ihn längst benutzen. Danach:

    taskbar: click x=20 y=21 hits=start
    taskbar: launcher pid=21

Warum es so lange unentdeckt blieb: Runde LEISTE hat ausdrücklich
notiert, dass sie den Knopf im Prüfstand nicht getroffen hat („QEMUs
`mouse_move` ist im Monitor relativ“). Ein Knopf, den kein Lauf drückt,
ist ein Knopf, dessen Wirkung niemand misst. Diese Runde drückt ihn —
mit einer **echten relativen USB-Maus** (`-device usb-mouse`) statt
einem Tablett, weil Justin auch eine hat.

---

## 8. Die Abnahme

Am **fertigen Abbild**, über Limine, unter **UEFI**, `-accel kvm
-cpu host`, **`-smp 4`**, 3440×1440, xHCI-Tastatur + USB-Maus, e1000
mit DHCP.

| gemessen | Zahl |
|---|---|
| Anstriche der Leiste | **179** |
| Uhr-Anstriche / davon **verschiedene** | 178 / **177** |
| erste → letzte Uhr | `11:25:45` → `11:28:41` = **176 s durchgehend** |
| `EXCEPTION` · `user fault` · `UEBERGELAUFEN` · `lock: stuck` | **0 · 0 · 0 · 0** |
| `WA` (Wächter) über den ganzen Lauf | nur **`WA 0`** |
| `R3F` (Ring 3 auf fremdem Kern) über den ganzen Lauf | nur **`R3F 0`** |
| höchster Kernstapelstand `KS` | 47 360 von 65 536 |
| Kerne | `smp: online=4 of 4  failed=0` |
| Netz | `22 NETZ K2 BDF 0020 L 1 ABL 0 IP 10.0.2.15` |
| Klicks / davon auf den Startknopf | 7 / **4**, alle `hits=start` |
| Startmenü | `taskbar: launcher pid=21` (vorher `-22`) |
| Tastatur | `TAS 6`, `BER 16 ARM 17 CC 1`, `hk: super+a` → Kontrollzentrum offen |

**177 verschiedene Uhrzeiten in 176 Sekunden** heißt: die Leiste malt
genau einmal je Sekunde, fast drei Minuten lang, ohne Wiederholung —
**mit vier Kernen**, also unter genau der Bedingung, unter der das
ausgelieferte Abbild nach wenigen Sekunden gestorben ist.

### Gegenprobe, dieselbe Datei, nur `-smp` verschieden

| Abbild | `-smp 1` | `-smp 4` | `-smp 8` |
|---|---|---|---|
| `b2addaf7` (ausgeliefert) | 791 Zeilen, 0 Ausnahmen | **Absturz** | **Absturz** |
| diese Runde | 989 Zeilen, 0 Ausnahmen | 897 Zeilen, **0** | 981 Zeilen, **0** |
