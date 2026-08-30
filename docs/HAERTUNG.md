# Runde HAERTUNG — W^X im Kern, Wachseiten, ASLR, IOMMU

Zweig `haertung`, abgezweigt von `mergeline2` bei `b010f75`.
Nachgemessen von `tools/haertung/run.sh`.

---

## 1. Was schon da war — Korrektur zur Roadmap-Zeile A12

Der Auftrag dieser Runde ging von einer Lücke aus, die so nicht bestand.
Nachgeprüft auf `mergeline2`, bevor eine Zeile geschrieben wurde:

| Behauptet | Wirklich |
|---|---|
| „SMEP wird an 4 Stellen erwähnt" | **SMEP/SMAP sind fertig gebaut.** `kernel/arch/x86_64/guard.fi`, 39 bzw. 49 Vorkommen allein dort. CR4-Bits, `stac`/`clac`-Fenster mit Zähler, CPUID-Abfrage, Nachziehen auf jedem weiteren Kern. Gegenproben `nosmep`, `nosmap`, `smapraw`, `smepraw`. `tools/guard/run.sh` läuft komplett grün — bis hin zu „#PF mit Bit 4 gesetzt — es war ein INSTRUKTIONSABRUF" und „das SMAP-Fenster wurde 312x geöffnet". Die Zahl 4 war eine **Datei**zählung, keine Vorkommenszählung. |
| „ASLR: 0 Treffer" | stimmt |
| „IOMMU: 0 Treffer" | stimmt |
| „Syscall-Argumentprüfung hinkt hinterher" | **`proc.user_ok` gibt es seit Runde 62** und wird an rund 30 Stellen aufgerufen: Bereichsgrenze, Überlaufprüfung, und ein Tabellenlauf, der auf jeder Ebene das Benutzerbit verlangt. `peek`/`poke`/`copy_in`/`copy_out` gehen alle darüber. |
| „W^X … die Laufzeit hinkt hinterher" | **halb richtig.** Für Ring 3 stand W^X seit Runde K1 (NX-Bit, `proc.nx`, getrennte Segmente in `kernel/user/user.ld`). **Für den Kern selbst stand es nicht** — und das war die eigentliche Lücke, siehe Abschnitt 2. |

**A12 sollte also lauten:** ASLR und IOMMU fehlen; SMEP/SMAP/NX/Zeigerprüfung stehen;
W^X galt für Ring 3, nicht für Ring 0.

---

## 2. W^X für den Kern — die eigentliche Lücke

### Der Befund

Die Identitätsabbildung des Kerns wird in `boot.s`/`start.s` aus 2-MiB-Kacheln
mit den Bits **`0x83`** gebaut: *vorhanden | schreibbar | grosse Seite*. Kein
NX. `mem.idmap_grow` setzt für jedes weitere Gibioktett dasselbe (`PDE_HUGE`).

Damit war **jede Seite des Kerns gleichzeitig schreibbar und ausführbar**:

* sein eigener Code liess sich überschreiben,
* sein Stapel, seine Halde und jeder freie Rahmen liessen sich anspringen,
* die Tabelle `vectors` — eine Liste von Einsprungadressen — lag beschreibbar da.

**SMEP hilft dagegen nicht.** SMEP verbietet Ring 0 den Befehlsabruf aus Seiten
mit *Benutzerbit*. Keine dieser Seiten hat eins. SMEP und W^X-im-Kern sind zwei
verschiedene Löcher; das erste war gestopft, das zweite nicht.

Gemessen mit `wx_verify`, das die Tabellen wirklich abläuft:

```
ohne den Durchgang (nowx):   1511 Seiten sind W und X zugleich
mit dem Durchgang:              0
```

### Der Durchgang

`kernel/hard.fi`, `wx_apply`. Er **setzt keine Adressen** — er liest jeden
Eintrag, lässt Adresse und Benutzerbit stehen und verändert genau zwei Bits,
W und NX. Deshalb muss er *nach* `proc.map_programs` laufen: das setzt die
Benutzerbits auf `.utext`, und wer danach Adressen neu schriebe, machte sie
zunichte.

| Bereich | Rechte | warum |
|---|---|---|
| `0` … `0x8000` | RW, NX | BIOS-Daten, Bildschirmspeicher |
| `0x8000` … `0xA000` | RW→**RX** | das AP-Trampolin. Bis `smp.stage` schreibbar, danach `tramp_seal` |
| `0x100000` … `__user_begin` | **R X** | Kerncode |
| `__user_begin` … `__user_end` | **R X** + Benutzerbit | `.utext`, der Code für Ring 3 |
| `__user_end` … `__data_begin` | **R**, NX | `.rodata`, darin `vectors` |
| `__data_begin` … Kachelgrenze | RW, NX | `.data`, `.bss`, Seitentabellen |
| darüber | RW, NX | Halde, Rahmen, Kernstapel — als ganze Kacheln |

Drei Kacheln des Abbilds werden dafür in 4-KiB-Seiten aufgelöst (ein Rahmen je
Kachel). Alles oberhalb bleibt eine Kachel und bekommt NX am Stück.

### Ohne `CR0.WP` wäre das alles Zierde

Steht CR0 Bit 16 auf 0, darf Ring 0 **in jede vorhandene Seite schreiben**, auch
in eine als nur-lesend eingetragene — das Bit gilt dann nur für Ring 3. `boot.s`
setzte `CR0.PG|PE` und sonst nichts.

Gemessen: die erste Fassung machte den Kerncode nur-lesend, und die Gegenprobe
`wxwrite` schrieb trotzdem anstandslos hinein (Beendigungscode 21 statt 63).
Erst mit `wp_on` ist es ein `#PF err=0x3`. CR0 ist **pro Kern** — `smp.ap_main`
setzt es ebenfalls.

### Der ELF-Lader

`kernel/user/user.ld` sagt seit Runde K1, es mache W^X „nachprüfbar", und hält
sich daran. Nur **prüfte es niemand**: `elf.segment` las `PF_W` und `PF_X` und
reichte beide an `proc.map_page` durch. Eine Datei mit einem RWX-Segment bekam
eine Seite, die schreibbar und ausführbar war. Jetzt: `R_WX`, gezählt in
`ELF_WX_REFUSED`.

---

## 3. Zwei latente Fehler, die diese Runde ausgelöst hat

Beide lagen schon vorher im Baum und waren nur nie erreichbar.

### `EFER.NXE` fehlte auf jedem weiteren Prozessor

Das Trampolin in `smp.s` setzt `EFER.LME` und sonst nichts. Der Startprozessor
schaltet `NXE` in `user.setup`; die weiteren nicht.

Solange in der Identitätsabbildung **kein einziges Bit 63 gesetzt war**, fiel
das nicht auf. Seit dem W^X-Durchgang ist es fast überall gesetzt — und bei
`NXE=0` ist Bit 63 kein „nicht ausführbar", sondern ein **reserviertes** Bit.
Ein reserviertes Bit macht *jeden* Zugriff auf diesen Eintrag zum Seitenfehler.

Befund: mit `-smp 4` kam der Kern bis `smp: apic=0 1 2 3` und blieb stehen. Die
weiteren Kerne fielen über die Bits, die sie schützen sollten. Behoben in
`smp.s` — mit CPUID-Abfrage davor, denn auf einer Maschine ohne NX wäre das
`wrmsr` ein `#GP`.

### `map_user_pt` setzte das Benutzerbit auf Ebene 2 nur in einem Zweig

`user.map_user_pt` sagt selbst, das Benutzerbit müsse auf *jeder* Ebene stehen,
und setzt es auf Ebene 4 und 3 — und auf Ebene 2 **nur im Teilungszweig**. Wer
eine schon aufgelöste Kachel vorfand, landete im `else` und bekam es nicht.

Das war nie erreichbar, weil bis zu dieser Runde **niemand sonst Kacheln
auflöste**. Seit die Wachseiten es tun, kann `map_programs` eine aufgelöste
Kachel vorfinden.

Befund: Verzeichniseintrag `0x5db023` statt `0x4f7027` — es fehlte Bit 2 —, und
Ring 3 fiel beim ersten Befehlsabruf auf `0x400000` mit `err=0x15` (vorhanden,
Nutzerzugriff, Instruktionsabruf).

---

## 4. Wachseiten

Ein Kernstapel war acht Rahmen am Stück. Lief er über, schrieb er in den Rahmen
darunter — kein Absturz, keine Meldung, nur ein Nachbar mit falschen Werten.

* **Je Aufgabe:** ein Rahmen mehr, der unterste wird aus der Abbildung genommen.
  Er bleibt dem Rahmenverwalter entzogen, aber es gibt keine Abbildung mehr auf
  ihn. `free_stack` gibt ihn beim Abräumen wieder her.
* **Die vier festen Stapel** aus `boot.s` (`kernel_stack` 64 KiB, `df_stack`,
  `syscall_stack`, `irq_stack` je 16 KiB) lagen auf 16 ausgerichtet
  hintereinander in `.bss`. Ein Überlauf schrieb in den nächsten — oder in
  `kdata`, die Zustandsregion des ganzen Kerns. Jetzt hat jeder eine
  4096-ausgerichtete Wachseite unter sich. Preis: vier Seiten `.bss`.
* Der Trap-Melder **benennt** den Treffer: `WACHSEITE -- Stapel uebergelaufen`.
  Ohne das stünde dort eine Adresse, die niemand einordnen kann.

Gemessen: 19 Wachseiten (ein Prozessor), 27 (vier).

**Was das nicht fängt**, ausdrücklich: einen Rahmen, der die Wache
*überspringt*. Ein einziger Zugriff mehr als 4096 Oktette unterhalb des
Stapelzeigers landet dahinter. Dagegen hilft nur ein Wachwert je Funktionsrahmen
(`-fstack-protector`), und den müsste der Firn-Übersetzer legen. Er kann es
heute nicht — siehe Abschnitt 7.

---

## 5. ASLR — und was sie bei statischem Linken wirklich bringt

Osum wird **statisch gelinkt, ohne PIE** (Roadmap A9). Die Adresse jeder
Funktion steht damit fest im Abbild. Daran ändert kein Verwürfeln etwas.

Verwürfelt werden deshalb nur die **Stapel**: Kernstapel je Aufgabe und
Nutzerstapel, jeweils um einen auf 16 ausgerichteten Betrag innerhalb einer
Seite. 4096/16 = 256 Plätze = **8 Bit** nach Bauart.

### Gemessen, 100 Starts

| | Nutzerstapel | Kernstapel |
|---|---|---|
| verschiedene Werte | 81 von 100 | 80 von 100 |
| kleinster / grösster | `0x60` / `0xff0` | `0x20` / `0xf40` |
| Ausrichtung | alle ≡ 0 (mod 16) | alle ≡ 0 (mod 16) |
| **Shannon-Entropie** | **6,26 Bit** | **6,20 Bit** |
| theoretisch | 8,00 Bit | 8,00 Bit |

Bei 100 Proben ist die *beobachtete* Entropie nach oben durch log₂(100) = 6,64
Bit begrenzt — mehr lässt sich aus so wenigen Starts nicht sehen. Die Messung
ist mit den 8 Bit der Bauart verträglich, belegt sie aber nicht; dafür bräuchte
es einige tausend Starts.

### Wogegen das hilft — und wogegen nicht

**Hilft** gegen alles, was eine *abgelegte* Adresse braucht: Rücksprungadressen
auf dem Stapel, Zeiger in Stapelrahmen, Angriffe, die einen Stapelinhalt an
einer vorher bekannten Stelle erwarten.

**Hilft nicht** gegen ROP auf feste Code-Adressen. Bei statischem Linken ohne
PIE liegt jedes Gadget bei jedem Start an derselben Stelle. 8 Bit Stapel-ASLR
sind gegen einen Angreifer, der nur Code-Adressen braucht, wirkungslos.
Wer das ändern will, braucht PIE — eine eigene, grosse Runde.

**Nicht verwürfelt:** der Stapel von Programmen **von der Platte**. Deren
Stapelzeiger zeigt auf den Argumentblock (`elf.fi`, `T_USTACK = ARGS_BASE`), und
dessen Seite hat ein festes Layout — `argc` bei 0, die Zeiger ab 8, die
Zeichenketten ab 80, die Umgebung ab `ENV_OFF`. Das ist Teil der
Startvereinbarung jedes Programms; es zu verschieben ist kein Einzeiler,
sondern ein Umbau. Offene Kante.

---

## 6. IOMMU — gelesen, nicht gebaut

`iommu_scan` sucht **DMAR** (Intel VT-d) und **IVRS** (AMD-Vi), wertet den Kopf
aus, zählt die Einheiten, meldet die Registerbasis der ersten — und hört auf.
Keine Domänen, keine Wurzeltabellen, keine Adressübersetzung.

Gemessen in QEMU:

```
-machine q35 -device intel-iommu   ->  hard: iommu=vt-d   units=1  base=0xfed90000
-machine q35 (ohne)                ->  hard: iommu=keine  units=0  base=0x0
```

**Warum nicht mehr.** Auf dem Papier ist die IOMMU die grösste Lücke: DMA geht
an der MMU vorbei, und ohne sie sind alle anderen Massnahmen Zierde. In der Lage
dieses Systems aber ist sie nachrangig: Osum ist ein **Monolith**, alle Treiber
laufen im Kern, es gibt **keine Treiber im Nutzerraum**, die einzusperren wären.
Der reale Angriff wäre ein bösartiges externes Gerät (Thunderbolt, PCIe-Hotplug)
— für die Zielhardware heute nachrangig.

Halb gebaut und stillschweigend unwirksam wäre das schlechteste Ergebnis: im
Bericht sähe es aus, als sei etwas geschützt. Sobald es Treiber im Nutzerraum
oder Thunderbolt gibt, wird die IOMMU zur Pflicht und bekommt eine eigene Runde.

**Plan für diese Runde:** Registerfenster (`base`) abbilden → `CAP`/`ECAP`
lesen → Wurzeltabelle und Kontexttabellen anlegen → je Gerät eine Domäne mit
eigener Seitentafel → `TE` in `GCMD` setzen → Gegenprobe: ein Gerät schreibt per
DMA ausserhalb seiner Domäne und wird geblockt (in QEMU mit `-device
intel-iommu` nachstellbar).

---

## 7. Was diese Runde NICHT abfängt

* **Wachwerte je Funktionsrahmen** (stack canary). Der Firn-Übersetzer legt
  keine. Damit bleibt ein Überlauf *innerhalb* eines Stapels unentdeckt, solange
  er die Wachseite nicht erreicht — und ein Sprung über die Wachseite hinweg
  bleibt unentdeckt.
* **ROP gegen feste Code-Adressen** — siehe Abschnitt 5.
* **DMA an der MMU vorbei** — siehe Abschnitt 6.
* **Andere Kerne sehen Tabellenänderungen verzögert.** `flush()` wirft nur den
  TLB des *eigenen* Kerns weg. Wachseiten, die eine Aufgabe auf Kern 0 legt,
  gelten für Kern 1 erst, wenn dessen TLB den alten Eintrag verdrängt. Ein
  richtiger TLB-Abgleich über alle Kerne (IPI) fehlt. Für den W^X-Durchgang
  spielt es keine Rolle — der läuft vor `smp.stage`.
* **`.text` ist 3 MiB gross**, weil `.utext` auf 2 MiB ausgerichtet ist. Der
  Durchgang macht die Füllung dazwischen mit lesbar und ausführbar. Das ist
  Nullen, kein Code, aber es ist mehr ausführbare Fläche als nötig.

---

## 8. Kosten

Die These „unter 1 Prozent" liess sich mit dem vorhandenen Werkzeug **nicht
auf 1 Prozent genau prüfen** — das ist ehrlich zu sagen, statt eine Zahl zu
erfinden.

**Bootzeit**, 15 Läufe je Seite, Wanduhr, auf einem Server, auf dem gleichzeitig
andere Runden bauen:

```
GRUNDLINIE  Median 5,9785 s   Min 5,5214 s
HAERTUNG    Median 5,7190 s   Min 5,4293 s
Unterschied im Median: -4,34 %
```

Der gehärtete Kern misst sich *schneller* als die Grundlinie. Das ist kein
Gewinn, das ist **Rauschen**: die Streuung innerhalb einer Seite (5,52 … 6,82 s)
ist ein Vielfaches des Unterschieds zwischen den Seiten. Eine Wanduhrmessung
unter Fremdlast kann Unterschiede unter etwa 5 Prozent nicht auflösen.

**Was sich dafür genau sagen lässt:**

* Der einmalige Preis des Durchgangs ist **1538 Seiteneinträge schreiben, 4
  Kacheln auflösen** (4 Rahmen) und ein `mov cr3`. Das sind einige zehntausend
  Takte, einmal je Start.
* Je Aufgabe: ein Rahmen mehr, ein Tabelleneintrag, ein `mov cr3`, ein Aufruf
  von `rand.bytes`.
* **Der Syscall-Pfad hat null zusätzliche Befehle.** `kernel/sys.fi` ist von
  dieser Runde **unverändert** (`git diff --stat -- kernel/sys.fi` ist leer).
  Es kam keine Prüfung, keine Verzweigung und kein Zähler in den heissen Pfad.
  Eine Syscall-Latenzmessung könnte hier nur Rauschen zeigen — es gibt nichts,
  was langsamer geworden sein könnte.

Das Abbild wächst um 4652 Oktette (3 175 816 → 3 180 468) plus vier Seiten
`.bss` zur Laufzeit.

---

## 9. Die Zeigerprüfung der Systemaufrufe

`tools/haertung/zeiger.py` baut den Aufrufgraphen über alle Kernmodule und
verfolgt **jedes Argument jedes Systemaufruf-Behandlers** über Modulgrenzen und
Aufrufebenen hinweg, indem es die Argumentstelle mitführt.

Drei Ausgänge: *geprüft* (erreicht `proc.user_ok` oder eine der geprüften
Zugriffsfunktionen), *roh* (wird als Adresse benutzt, ohne dass geprüft wurde),
*skalar* (nie als Adresse benutzt — da ist nichts zu prüfen).

**Ergebnis:**

```
Systemaufrufe mit Behandler:            122
davon mit mindestens einem Zeiger:      105
   davon alle Zeiger geprueft:           41
   davon mit ROHEM Argument:             64
Systemaufrufe ohne jeden Zeiger:         17

ROHE ARGUMENTE MIT ZEIGERVERDAECHTIGEM NAMEN:  1
   PRUEFEN: SYS_OSUM_NETVALLOW   sys.do_netvallow   addr
```

Die Zahl 64 ist **kein** Befund über 64 Löcher. Sie zählt Systemaufrufe, bei
denen *mindestens ein* Argument irgendwo als Adresse gelesen wird, ohne dass auf
dem Weg geprüft wurde — und das trifft auch `do_read` und `do_write`, deren
Puffer sehr wohl über `proc.user_ok` gehen, deren `fd` aber gleich danach als
Index in eine Kerntabelle gelegt wird. Ein Dateizeiger ist kein Nutzerzeiger.

Deshalb filtert das Werkzeug am Ende auf Argumente, deren **Name** nach einem
Zeiger aussieht (`buf`, `ptr`, `addr`, `path`, `out`, `dst`, `src`, …). Übrig
bleibt **genau eines**, und das ist von Hand nachgesehen: `do_netvallow` bekommt
in `addr` eine **IPv4-Adresse als Wert**, keinen Zeiger — der Aufruf prüft
`addr == 0 && pp == 0` und reicht sie an `netview.allow_set` weiter.

Weitere Stichproben aus der 64er-Liste, ebenfalls von Hand: `do_spawn` prüft
`prog == 0 || prog > 16`, `do_vm_create` prüft `guest >= hv.G_MAX`, `do_chmod`
bekommt Modusbits, `do_pstat`/`do_mntstat`/`do_pmon` bekommen Indizes.

**Kein ungeprüfter Nutzerzeiger gefunden.** Die Abdeckung von `proc.user_ok`
ist für die zeigernehmenden Systemaufrufe vollständig.

Zwei Fassungen dieses Werkzeugs meldeten vorher zu gute Zahlen, und beide Male
lag es an zu grober Auflösung — erst wurden Funktionen gleichen Namens aus
verschiedenen Modulen verschmolzen (122 von 122 „geprüft"), dann galt
`kstate.get`/`set` als Zeigerzugriff, wodurch jeder Tabellenindex als roher
Zeiger zählte. Beides steht als Warnung im Kopf der Datei.

**Die Grenze, ausdrücklich:** das ist eine Erreichbarkeitsaussage über den
Aufrufgraphen, kein Beweis. Ein Behandler mit zwei Zeigern, von denen nur einer
geprüft wird, sähe grün aus. Das Werkzeug sagt, *wo man hinsehen muss*; der
Nachweis sind die Angriffsläufe.

---

## 10. Kommandozeile

| Wort | Wirkung |
|---|---|
| `nowx` | der W^X-Durchgang fällt aus (und `CR0.WP` bleibt aus) |
| `nonx` | NX wird nicht gesetzt, Nur-Lesen schon |
| `noguard` | keine Wachseiten |
| `noaslr` | die Stapel liegen wieder fest |
| `wxwrite` | Gegenprobe: der Kern schreibt in seinen eigenen Code |
| `wxexec` | Gegenprobe: der Kern springt in einen Datenrahmen |
| `kblow` | Gegenprobe: der Kern läuft seinen Stapel hinunter |

Alle Zähler stehen in `kstate` ab Versatz 1480 und werden von
`tools/haertung/run.sh` gelesen.
