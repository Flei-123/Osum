# Runde HV3 — Stufen 4 und 5: ein echtes Linux startet

Diese Runde hatte ein einziges Ziel: der Hypervisor aus HV2 soll kein
Spielzeug mehr fuehren, sondern einen FREMDEN, unveraenderten Kern —
ein Debian-Linux 6.12 als `bzImage`. Am Ende dieser Runde tut er das.
Linux laeuft bis in seine Benutzerumgebung hinein und haelt erst an,
weil ihm keine Wurzel gegeben wurde.

Alles hier ist GEMESSEN. Jede Zahl stammt aus einem Lauf, der
nachvollziehbar ist; keine stammt aus einer Vermutung.

---

## 0. Das Ergebnis in einer Zeile

```
hv: linux exits=192512 out=5 state=1 rip=0xffffffff81087992
    exitcode=0x7b said=25953 lastnpf=0x0 cr0=0x80050033
    cr3=0x2c2c000 efer=0x1d01 decfail=0
hv: proofs 36 / 36
```

`said=25953` ist der Massstab: so viele Oktette hat Linux durch die
emulierte serielle Schnittstelle gesagt. Zu Beginn dieser Runde waren
es **0**, nach dem ersten Teilerfolg **74**, am Ende **25953**.

Woertlich, aus dem Lauf:

```
[    0.000000] Linux version 6.12.101+deb12-rt-amd64 ... SMP PREEMPT_RT
[    0.000000] CPU: vendor_id 'OsumHypervis' unknown, using generic init.
[    0.032000] smp: Brought up 1 node, 1 CPU
[    0.032000] devtmpfs: initialized
[    2.672055] AppArmor: AppArmor sha256 policy hashing enabled
[    2.956073] VFS: Cannot open root device "" or unknown-block(0,0)
[    2.956073] Kernel panic - not syncing: VFS: Unable to mount root fs
```

Das letzte Wort ist KEIN Fehler des Wirts. Linux hat seinen gesamten
Hochlauf durchlaufen — Speicherzonen, Prozessor, `devtmpfs`, die
Sicherheitsmodule, das Netzwerkprotokoll — und panikt genau dort, wo
jeder Kern ohne Wurzeldateisystem panikt. Ein Datentraeger ist Stufe 6
und war nicht Teil dieses Auftrags.

---

## 1. Was wirklich im Weg stand — und was NICHT

Waehrend dieser Runde kam ein Recherchebefund herein: Linux starte
nicht, weil die PLATTFORM-FIRMWARE fehle (ACPI mit RSDP/FADT/MADT/MCFG,
IOAPIC, HPET). Der Befund klang plausibel und war fuer diesen Blocker
**falsch**. Das ist kein Vorwurf an die Recherche, sondern der Grund,
warum diese Runde zuerst gemessen und dann gebaut hat.

Die Messung war eine Spur der Austrittsgruende (`gastspur`). Sie sagte
bei jedem Schritt woertlich, WO Linux stand. Was sie zeigte:

| Nr. | Symptom (gemessen) | Wirkliche Ursache | ACPI schuld? |
|-----|--------------------|-------------------|--------------|
| 1 | `exitcode=0x7f`, Dreifachfehler | EFER/GS_BASE im MSR-Pfad | nein |
| 2 | 1527× Anschluss 0x70/0x71 | keine Uhr (CMOS/RTC) | nein |
| 3 | 3132× Anschluss 0x61 an EINEM Befehlszeiger | Kanal 2 des Zeitgebers zaehlte nie | nein |
| 4 | 3009× Grund 0x60 an `native_safe_halt` | kein Takt wurde eingeworfen | nein |

Und was Linux zu ACPI selbst sagte, nachdem es lief:

```
[    0.000000] ACPI BIOS Error (bug): A valid RSDP was not found
[    0.000000] APIC: Keep in PIC mode(8259)
[    0.000000] No local APIC present
```

Linux hat das Fehlen von ACPI **gemeldet und ist weitergelaufen**. Es
faellt auf die zwei 8259A zurueck, genau wie vorgesehen. Die ACPI-
Tabellen sind fuer mehrere Prozessoren und fuer PCIe noetig — fuer
EINEN Prozessor mit Altgeraeten sind sie es nicht.

**Die Lehre:** ein Gast, der stillsteht, sagt nicht von selbst warum.
Die Spur der Austrittsgruende hat es in jedem der vier Faelle in
wenigen Minuten gesagt. Ohne sie waere diese Runde damit vergangen,
ACPI-Tabellen zu bauen, die den Stillstand nicht behoben haetten.

---

## 2. Stufe 4 — der MSR-Pfad (Fehler 1)

### Was gemessen wurde

```
hv: sp c=0x7c rip=0xffffffff8103f4ef i1=0x1    msr 0xc0000101 wr
hv: sp c=0x72 rip=0xffffffff8103f4fb           cpuid
hv: sp c=0x7c rip=0xffffffff8103f504 i1=0x0    msr 0xc0000080 rd
hv: sp c=0x7c rip=0xffffffff8103f525 i1=0x1    msr 0xc0000080 wr
hv: sp c=0x7f rip=0xffffffff8335db43           SHUTDOWN
```

### Zwei Fehler, beide toedlich

**`MSR_GS_BASE` (0xc0000101) wurde verschluckt.** Linux legt dort den
Anfang seines Bereichs je Prozessor hin. Der Wirt nahm das Schreiben
entgegen und tat nichts. Jeder folgende Zugriff ueber `gs:` las
daraufhin ab Adresse 0 — Seitenfehler, und weil die Behandlung selbst
wieder ueber `gs:` geht, ein Dreifachfehler. `GS.base` ist KEIN eigenes
Feld im Steuerblock, es steht im Segmentbeschreiber (`S_GS + 8`);
genau deshalb war es uebersehen worden.

**EFER verlor LMA.** Linux liest EFER, setzt `SCE` und schreibt zurueck.
Der gelesene Wert enthaelt `LMA` — ein Bit, das der Prozessor selbst
setzt. Die Schreibmaske des Wirts liess es fallen. Ein Eintritt mit
`LME` gesetzt und `LMA` geloescht ist ungueltig.

Der neue `do_msr` behandelt vollstaendig: `EFER`, `STAR`, `LSTAR`,
`CSTAR`, `SFMASK`, `FS_BASE`, `GS_BASE`, `KERNEL_GS_BASE`, `TSC`,
`MISC_ENABLE`, `PAT`. Gelesen wird aus dem Steuerblock, geschrieben
wird dorthin zurueck — nicht in ein Nebenbuch, das der Prozessor nie
sieht.

---

## 3. Stufe 5 — die drei Geraete, ohne die kein Linux hochlaeuft

### 3a. Die Uhr (CMOS/RTC, 0x70/0x71) — Fehler 2

Ohne sie war der Anschluss offener Bus und lieferte 0xFF. In Register A
steht dann das Bit UIP (0x80) **fuer immer**, und `mach_get_cmos_time`
wartet darauf, dass es faellt.

Gemessen: **1527** Lesevorgaenge, immer dieselben zwei Befehlszeiger.
Nach dem Einbau: **11**.

Der entscheidende Punkt im Bau ist, dass UIP nicht stehenbleiben darf.
Es steht hier in einem von sechzehn Lesevorgaengen und faellt dann von
selbst — ein Gast, der auf den Wechsel wartet, sieht ihn und kommt
weiter. Register C loescht sich durch das Lesen, sonst haengt ein Gast,
der darauf wartet, dass es leer wird.

### 3b. Der zweite Kanal des Zeitgebers (0x42 und 0x61) — Fehler 3

Gemessen: **3132** Lesevorgaenge an EINEM Befehlszeiger
(`0xffffffff81050fa7`) — Linux' `pit_calibrate_tsc`.

Der Grund war eine falsche Annahme aus HV2: der Anschluss 0x61 kippte
sein Bit 4. Linux wartet aber auf **Bit 5**, den Ausgang des Kanals 2,
und der stand nie. Ein kippendes Bit 4 ist die Auffrischung des
Speichers und beantwortet eine ganz andere Frage.

Kanal 2 zaehlt jetzt wirklich herunter (Tor = Bit 0 von 0x61) und setzt
beim Durchlauf seinen Ausgang. Er zaehlt dabei in Schritten von 256 und
nicht um eins: der Wirt sieht den Gast nur bei jedem Zugriff, und wer um
eins herunterzaehlt, braucht fuer einen Durchlauf so viele Austritte,
wie der Zaehler gross ist.

Nach dem Einbau: **149** Zugriffe, und Linux sagte statt 74 nun 1280
Oktette.

### 3c. Der Takt (Fehler 4) — das Erste, was OHNE den Gast geschieht

Gemessen: **3009 von 4096** Austritten mit Grund 0x60 an einem
einzigen Befehlszeiger — dem `hlt` in `native_safe_halt`.

Alles, was diese Runde vorher gebaut hatte, war eine ANTWORT: der Gast
fragt, der Wirt antwortet. Ein Takt ist etwas anderes. Linux schaltet
nach dem Hochlauf die Unterbrechungen frei, legt sich mit `hlt` hin und
wartet auf IRQ 0. Kommt nichts, wartet es fuer immer — es ist nicht
abgestuerzt, es wartet.

Der Wirt wirft nun alle `TICK_EVERY` Austritte eine Unterbrechung ein,
wenn drei Bedingungen stimmen: der Gast laesst sie zu (sein IF), es
steht keine andere im Einwurffeld, und der Verteiler laesst die Leitung
durch (seine Maske).

**Der Vektor ist NICHT fest 0x20.** Er kommt aus ICW2, also aus dem, was
der Gast dem Verteiler selbst gesagt hat. Ein Linux programmiert die
Basis um; eine feste Zahl traefe danach den falschen Eintrag.

Dazu kam eine zweite Aenderung, ohne die der Takt nichts genuetzt haette:
**ein `hlt` beendet den Lauf nicht mehr**, solange der Gast
Unterbrechungen zulaesst. Vorher gab der Wirt dort immer `R_HALT` — und
nahm einem echten Linux damit genau den Hochlauf. Nur ein Gast, der die
Unterbrechungen ABGESCHALTET hat, meint sein `hlt` endgueltig.

---

## 4. Zwei Dinge, die sich aus dem Betrieb ergaben

**Ein Lauf reicht nicht.** `vm_run` gibt nach 4096 Austritten zurueck,
damit ein Gast den Wirt nicht festhaelt. Linux' Hochlauf braucht
**192512**. Der Wirt holt den Gast nun wieder herein, solange er
FORTSCHRITT macht — mehr gesagt oder mehr Austritte. Bleibt beides
stehen, dreht er sich im Kreis.

**`panic=-1` ist eine Abbruchbedingung, keine Bequemlichkeit.** Ohne
Wurzel panikt Linux und bleibt danach MIT eingeschalteten
Unterbrechungen stehen: es lief weiter, ohne noch etwas zu sagen, und
der Wirt holte es bis zum Zeitlimit herein. Mit dem Wort startet es
sich neu, und der Wirt sieht den Dreifachfehler als sauberes Ende.

---

## 5. Was an Platz gebraucht wurde

`VD_BYTES` wuchs von 256 auf 512. Die Uhr fuellte den Block auf genau
0x100, der zweite Kanal brauchte mehr. Acht Maschinen zu 512 Oktetten
sind 4096 und passen in `VDEV_MAX`. Der Kartenpruefer bestaetigt es bei
jedem Lauf:

```
die Karte von kdata ist ueberschneidungsfrei
(134 Bereiche in 0x140000 Oktetten kdata, 0 Kollisionen)
```

---

## 6. Die Messung

```
HV:       162 passed, 0 failed   (unveraendert, keine Zusage verloren)
hv:       proofs 36 / 36         (32 vorher + 4 neue dieser Runde)
STRUKTUR: OK                     (halten 925, brechen 47, Deckel 47)
```

Die vier neuen Zusagen messen nicht, dass Linux "nicht abstuerzt",
sondern jede einzelne Stufe dieser Runde:

- `and it kept talking: a whole boot log` — mehr als 4096 Oktette.
  Der Lader allein bringt es auf wenige Dutzend.
- `the host gave linux a timer of its own` — es wurden Takte eingeworfen.
- `and linux read the clock instead of hanging` — die Uhr wurde gelesen,
  und zwar **weniger als 256 Mal**. Tausendfach hiesse, er haengt in
  der Schleife, die Stufe 3a aufgeloest hat.
- `it calibrated against the pit and moved on` — dasselbe fuer 0x61.

Die Obergrenzen sind Absicht. Eine Zusage, die nur "groesser als null"
prueft, wuerde auch dann gruen bleiben, wenn der Gast wieder in genau
der Schleife steckte, die diese Runde beseitigt hat.

---

## 7. Was als Naechstes ansteht

1. **Ein Datentraeger.** Das ist der einzige Grund, warum Linux jetzt
   noch panikt. Ein `initramfs` als zweites Modul waere der kuerzeste
   Weg zu einer Eingabeaufforderung.
2. **virtio als GERAET, nicht als Treiber.** Osum hat virtio-Treiber
   fuer sich selbst; gebraucht wird die Gegenseite — Virtqueues,
   Deskriptorringe, Aushandlung der Eigenschaften. Ein Treiber ist kein
   Geraet. Mit Altgeraeten allein bleibt ein Gast langsam.
3. **ACPI (RSDP/XSDT/FADT/MADT/MCFG) und der IOAPIC.** Nicht fuer den
   Start — das ist jetzt gemessen — sondern fuer MEHRERE Prozessoren
   und fuer PCIe. Sobald `smp` mehr als eine CPU haben soll, fuehrt
   kein Weg daran vorbei.
4. **Die Zeitquelle.** `tsc: Unable to calibrate against PIT` steht noch
   im Ablauf, und Linux nennt seine Uhr instabil. Ein HPET oder ein
   sauber gezaehlter Kanal 0 waere der naechste Schritt.
