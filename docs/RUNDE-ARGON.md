# Runde ARGON (K-021) — Argon2 über die vier Spuren, und SHA-NI

Zweig `argon`, Grundlage `main` = `d5583ee`. Worktree `/root/osum-w-argon`.

Ziel: das Aufsperren. Runde AESNI (K-020) hat Lesen und Schreiben erledigt
(188 MiB/s statt 0,58), das Entsperren ausdrücklich nicht — es hängt an
Argon2, und Argon2 rechnete seine vier Spuren nacheinander.

**Abnahme: `bash tools/argon/run.sh` → 33 bestanden, 0 gescheitert.**
Daneben unverändert: `tools/krypto/run.sh` → **61/0**,
`tools/aesni/run.sh` → **31/0**, `tools/check-ui.sh` → **PASSED**.

---

## 1. Die Vorabmessung — und die erste Zahl des Auftrags stimmt nicht

Der Auftrag nennt als Ausgangslage **5,2 s** Entsperrzeit und vermutet als
Hauptposten, dass `unlock` **alle acht Schlüsselplätze** durchrechnet. Beides
wurde nachgemessen, bevor eine Zeile geschrieben wurde. Beides ist so nicht
haltbar.

### 1.1 Das Entsperren kostet 790 ms, nicht 5,2 s

Gemessen auf dem Wirt (AMD EPYC, QEMU mit KVM, `-m 512`), je drei Läufe,
Streuung unter 25 ms:

| Lauf | Zeit |
|---|---|
| Hochlauf **mit** `kryptoauf` (Vorgabe t=2, m=32 MiB, p=4) | 3581 / 3563 / 3572 ms |
| Hochlauf **ohne** Entsperren (`kryptoroh`) | 2786 / 2792 / 2760 ms |
| **Differenz = das Entsperren** | **rund 790 ms** |

Der Rest ist gewöhnlicher Hochlauf und hat mit Krypto nichts zu tun. Die 5,2 s
der Vorrunde sind eine **Hochlauf-Gesamtzeit**, keine Entsperrzeit; der Bericht
K-019 sagt in seiner Tabelle auch „samt Hochlauf“. Wer daraus eine Entsperrzeit
macht, misst zu vier Fünfteln den Hochlauf.

Der Argon2-Anteil skaliert sauber linear in `m` (Gesamtzeit minus 2780 ms
Grundlast):

| m | 8 MiB | 16 MiB | 32 MiB | 64 MiB |
|---|---|---|---|---|
| Argon2-Anteil | 333 ms | 482 ms | 781 ms | 1403 ms |

### 1.2 Die acht Plätze kosten NICHT achtmal

`kernel/krypto.fi`, `slot_open`, Zeile 531:

```
let sl: u64 = slot_at(state, i)
if le32(sl, S_USED) == 0 {
    return false
}
```

Ein **unbelegter** Platz kehrt sofort zurück — Argon2 läuft dort nie. Bei einem
belegten Platz ist `unlock` also **ein** Argon2-Lauf und nicht acht. Gemessen:

| belegte Plätze | Hochlauf mit Entsperren |
|---|---|
| 1 | 3401 ms |
| 2 | 4064 ms |

Jeder **belegte** Platz kostet rund 660 ms, jeder leere nichts.

**Das ist zugleich ein roter Punkt** (siehe 7.1): der Kommentar über `unlock`
begründet ausführlich, warum alle acht Plätze durchgerechnet werden — „ein
Abbruch beim ersten Fehlschlag verriete, wie viele belegt sind“. Genau das
verrät die Laufzeit heute, weil der Kurzschluss eine Ebene tiefer sitzt. Die
Absicht ist richtig, die Umsetzung löst sie nicht ein.

### 1.3 Wo die Zeit innerhalb von Argon2 liegt

Auf dem Wirt, über `tools/krypto/orakel.fi` (dieselben `lib/crypto`-Dateien wie
im Kern):

| Parameter | Zeit |
|---|---|
| t=2, m=32 MiB, p=4 (Vorgabe) | 560 ms |
| t=3, m=64 MiB, p=4 (RFC 9106 Abschnitt 4) | 1738 ms |

Und der Beleg für den roten Punkt 3 der Vorrunde, in einer Zeile:

| p | 1 | 2 | 4 | 8 |
|---|---|---|---|---|
| Zeit (t=2, m=32 MiB) | 600 ms | 622 ms | 638 ms | 609 ms |

**`p` ändert die Laufzeit nicht.** Die Arbeit ist dieselbe (p teilt den
Speicher, es vergrößert ihn nicht), und sie wird nacheinander erledigt.

---

## 2. Was der Kern an Nebenläufigkeit wirklich anbietet

Der Auftrag verlangt diese Feststellung **vor** dem Bauen. Sie steht hier, und
sie hat sich im Lauf der Runde einmal als falsch erwiesen — das gehört dazu.

### 2.1 Was vorhanden ist

| Frage | Antwort | Beleg |
|---|---|---|
| Laufen die anderen Kerne? | **Ja.** INIT+SIPI, eigener Stapel, eigene GDT, eigenes TSS, Meldung über `C_ONLINE` | `kernel/arch/x86_64/smp.fi`, `start`/`ap_main` |
| Gibt es Sperren und Barrieren? | **Ja.** `cas`, `fetch_add`, `barrier`, `pause`, acht benannte Sperren | `kernel/atomic.fi` |
| Nehmen Kernaufgaben auf mehreren Kernen Arbeit an? | **Ja**, und es ist gemessen: `smp: sched tasks=8 done=8 cores_used=4` | `smp.schedule_demo` |

### 2.2 Der Irrtum, der erst die Messung fand

Aus den Zeilennummern in `kmain.fi` — `smp.stage` in Zeile 836,
`krypto_stufe` in Zeile 3424 — habe ich zunächst geschlossen, SMP laufe vor dem
Entsperren. **Das war falsch.** 3424 ist die Stelle, an der `krypto_stufe`
*definiert* wird; gerufen wird es aus `fn osum(state)`, und `osum(state)` steht
in Zeile **785** — also **vor** `smp.stage`.

Das Startprotokoll sagt es unmissverständlich:

```
185  krypto: auf=1 fehler=0 platz=0
194  smp: cpus=4  acpi=1  rev=0  apic=0 1 2 3
195  smp: online=4 of 4  failed=0
```

Die Entsperrung lief auf **einem einzigen Kern**; die anderen waren noch nicht
gestartet. Die erste Fassung dieser Runde meldete deshalb folgerichtig
`argon: par=0 kerne=0` — bei jedem `-smp`.

**Lehre, und sie steht hier, damit die nächste Runde sie nicht wiederholt:**
Aufrufreihenfolge im Kern am Startprotokoll messen, nie aus Zeilennummern von
Definitionen ableiten.

### 2.3 Was daraus folgte

Zwei Wege standen offen:

**Nicht genommen: die Phasen-Barriere von `smp.fi`** (`S_PHASE`/`S_DONE`,
`PH_BENCH` … `PH_GRACE`). Sie ist zur Entsperrzeit tot: `smp.stage` schickt die
Kerne zuletzt in `PH_SCHED`, und aus dieser Phase kommt ein Kern **nie zurück**
— er wird Leerlaufaufgabe des Ablaufplaners. Eine neue Phase dort einzuhängen
wäre wirkungslos gewesen.

**Genommen: Kernaufgaben, und die Kerne früher starten.**
`smp.frueh_start` holt aus `stage` genau zwei Schritte vor — die Prozessoren
finden (`probe`) und starten (`start`) — und schickt sie in `PH_SCHED`, damit
sie Arbeit aus der Laufschlange annehmen. Die Messungen von Runde K5 bleiben,
wo sie sind. Gerufen wird es **nur**, wenn wirklich eine Ableitung ansteht:
nicht bei `kryptoroh`, nicht bei `noargonpar`. Ein Lauf ohne `kryptoauf` sieht
diese Funktion nie und verhält sich Zeile für Zeile wie vorher.

---

## 3. Was gebaut wurde

### 3.1 Argon2 parallel — und warum die Rechnung nur einmal dasteht

Die Aufteilung folgt RFC 9106: **innerhalb einer Scheibe sind die p Spuren
unabhängig, synchronisiert wird an der Scheibengrenze.** Das ist keine
Auslegung — `index_alpha` belegt es selbst: greift ein Block auf eine *fremde*
Spur zu, reicht die erlaubte Fläche nur über die **abgeschlossenen** Scheiben,
nie in die laufende hinein.

Der Rumpf einer Spur steht **genau einmal** im Baum, als
`argon2.fill_segment`. Der serielle Weg ruft ihn, die Spuraufgabe ruft ihn.
`argon2_any` ist dafür in drei Teile zerlegt:

| Teil | Was |
|---|---|
| `prepare` | Prüfungen, Geometrie, H0, die ersten zwei Blöcke je Spur |
| `passes` | die Schleife (seriell) — ruft `fill_segment` |
| `finish` | letzte Blöcke aller Spuren gexort, H' darüber |

`kargon.argon2id_par` ruft dieselben drei Teile in derselben Reihenfolge und
ersetzt nur die mittlere Schleife. **Eine parallele Umsetzung, die den Rumpf
nachbaut, wäre die Stelle, an der beide Wege auseinanderlaufen** — und das
Ergebnis wäre eine Platte, die niemand mehr aufbekommt.

`zp`/`ip` (die Adressblöcke für Argon2i/id) sind **je Spur eigene**. Ein
geteilter Adressblock wäre ein Datenrennen mit falschem Ergebnis — und zwar
eines, das bei p=1 nie auffällt.

Fällt irgendwo etwas aus — kein Rahmen, keine Aufgabe, eine Spur nicht fertig
—, rechnet `parallel_slice` `false` zurück und der Aufrufer macht die Scheibe
**seriell**. Das ist kein Notnagel, sondern der Normalfall auf einem Rechner
mit einem Kern.

### 3.2 SHA-NI

Dieselbe Aufteilung wie bei AES-NI, und aus demselben Grund:
`lib/crypto/shani.fi` (die Rechnung, kennt `kstate` nicht, läuft auch im
Orakel) und `kernel/kshani.fi` (die Naht: `cpuid`, `fpu.enabled`, Schalter,
Bericht, Kreisprobe). Vorsatz `k`, weil Kern und `lib` einen Namensraum teilen.

`lib/crypto/sha256.fi` bleibt als Rückfallweg **vollständig stehen**.

---

## 4. Die drei Fallen von SHA-NI — gemessen, nicht nachgeschlagen

Sie stehen hier, weil jede davon ein stabiles, reproduzierbares **falsches**
Ergebnis liefert.

1. **`xmm0` ist ein impliziter Operand von `SHA256RNDS2`** — es trägt W+K der
   beiden Runden. Wer dort den Zustand hält, rechnet Müll. Der Zustand gehört
   in andere Register (hier `xmm8`/`xmm9`).

2. **Die Registerrollen tauschen bei jedem `SHA256RNDS2`.** Mit einer
   Einzelbefehl-Probe gemessen: `sha256rnds2 dst, src` liest `dst = {H,G,D,C}`
   (dword0 = H) und `src = {F,E,B,A}` (dword0 = F) und schreibt das **neue**
   `{F,E,B,A}` nach `dst`. Deshalb wechseln sich `sha256rnds2 xmm8,xmm9` und
   `sha256rnds2 xmm9,xmm8` ab; nach zwei Befehlen sind die Rollen wieder wie
   am Anfang.

3. **Die Rotation des Nachrichtenplans.** Richtig ist je Schritt j (Register
   r[0..3] = `xmm3`..`xmm6`, je vier W-Wörter):
   `sha256msg1(r[j], r[j+1])`; `palignr(r[j+3], r[j+2], 4)` liefert W[i-7];
   `paddd` auf r[j]; `sha256msg2(r[j], r[j+3])`.
   Das wurde im Modell über **alle zwölf Schritte** (W16…W63) gegen die
   Referenz geprüft, **bevor** es ins `asm` ging. Mein erster Versuch hatte die
   `palignr`-Operanden vertauscht.

Nebenbefunde zum Übersetzer: Firn nimmt die Befehle direkt (`asm` mit
`\n`-getrennten Zeilen, numerische Marken `1:`/`1b` wie in `aesni.fi`). Eine
Skalierung `[r8+r11*64]` geht **nicht** (x86 kann höchstens `*8`) — ein
laufender Zeiger löst das.

---

## 5. Die Messwerte

### 5.1 Die Richtigkeit — zuerst, weil sie nicht wackeln darf

| Probe | Umfang | Ergebnis |
|---|---|---|
| **RFC 9106, t=3/m=32/p=4** | der Vektor, der die Spur-Zusammensetzung prüft | **stimmt** |
| Argon2id/i/d gegen `argon2-cffi` | 3 Spielarten × t=1..3 × m=8..256 × p=1..8 | **162/162** |
| Die ganze Kryptokette | BLAKE2b, Argon2, XTS, negative Hälfte | **168/168** |
| Umbau `fill_segment` gegen den Urzustand | 55 Parametersätze | **0 ungleich** |
| Umbau `prepare`/`passes`/`finish` | 162 Parametersätze | **0 ungleich** |
| SHA-256: beide Wege, auf dem Wirt | Längen 0…600 und 1000…4096 | **3698 Fälle, 0 ungleich** |
| SHA-256: beide Wege, in Ring 0 | Längen 0…300 und 512…1024 | **814 Fälle, 0 ungleich** |
| FIPS 180-4 „abc“ über den schnellen Weg | `ba7816bf…15ad` | **stimmt** |

### 5.2 Eine bestehende Platte — die Zusage, die zählt

| Schritt | Ergebnis |
|---|---|
| Träger mit dem **seriellen** Weg angelegt (`noargonpar`, ein Kern) | `neu=1` |
| … mit dem **parallelen** Weg aufgesperrt | **`auf=1`**, `mount=1` |
| Gegenrichtung: parallel angelegt, seriell aufgesperrt | **`auf=1`** |
| falsche Passphrase | `auf=0` — weiter abgewiesen |

### 5.3 Das Tempo

Argon2 allein, in `rdtsc`-Takten um den Lauf im Kern gemessen (in Takten, weil
`TIME_KHZ` an dieser Stelle des Hochlaufs noch null ist — dieselbe
Einschränkung, die `kaesni.bench` nennt). Vorgabeparameter t=2, m=32 MiB, p=4:

| Lauf | Takte | Faktor |
|---|---|---|
| `-smp 4 noargonpar` (seriell, **der ehrliche Vorher-Wert**) | 1 389 515 160 | — |
| `-smp 1` (seriell, nur ein Kern da) | 1 497 790 536 | |
| `-smp 2` parallel (`kerne=2`) | 863 897 716 | **1,61** |
| `-smp 4` parallel (`kerne=4`) | 640 527 492 | **2,17** |
| `-smp 8` parallel (`kerne=4`) | 673 467 036 | 2,06 |

Der Abnahmelauf misst dasselbe noch einmal selbst und kam auf
1 386 701 580 gegen 515 432 390 Takte = **Faktor 2,69**. Die Streuung zwischen
den Läufen liegt daran, dass der Wirt nebenher anderes tut; die Größenordnung
ist in jedem Lauf dieselbe.

**Faktor 2,2 bis 2,7 bei vier Kernen — nicht 4.** Ehrlich hingeschrieben, und
die Gründe sind bekannt:

* `p=4` deckelt auf vier Spuren. `-smp 8` bringt nichts mehr, und das ist
  keine Schwäche der Umsetzung, sondern die Norm: mehr Kerne als Spuren haben
  nichts zu tun.
* **Die Scheibengrenze ist eine echte Barriere.** Bei t=2 sind das acht
  Synchronisationspunkte, an denen der schnellste Kern auf den langsamsten
  wartet.
* Je Segment kosten Anlegen, Einplanen und Abräumen der Aufgaben.

### 5.4 Die Entsperrzeit beim Hochlauf — die Zahl, die zählt

| | seriell | parallel |
|---|---|---|
| Hochlauf gesamt (`-smp 4`, Vorgabeparameter) | 3725 ms | 3361 ms |
| Grundlast ohne Entsperren (`kryptoroh`, `-smp 4`) | 2900 ms | 2900 ms |
| **Das Entsperren allein** | **rund 825 ms** | **rund 461 ms** |

### 5.5 SHA-NI im Kern, auf drei Maschinen

| Lauf | Befund | Kreisprobe | Platte |
|---|---|---|---|
| `-cpu host` | `have=1 used=1 fpu=1` | 814, **0 ungleich** | `auf=1`, `kernel: done` |
| `-cpu host noshani` | `have=1 used=0` (Gegenprobe von Hand) | 814, **0 ungleich** | `auf=1`, `kernel: done` |
| `-cpu qemu64` | `have=0 used=0` (**echter Rückfall**) | 814, **0 ungleich** | `auf=1`, `kernel: done` |

Der Rückfallweg ist damit **gefahren und nicht behauptet**: `-cpu qemu64` hat
kein SHA-NI, es gibt kein `#UD`, und die Platte geht dort genauso auf.

### 5.6 Die Nachbarn

| Abnahme | Ergebnis |
|---|---|
| `tools/krypto/run.sh` | **61 bestanden, 0 gescheitert** |
| `tools/aesni/run.sh` | **31 bestanden, 0 gescheitert** (XTS weiter 174 MiB/s, Faktor 135 im Kern) |
| `tools/check-ui.sh` | **PASSED** |
| `python3 tools/kernel/memmap.py` | 128 Bereiche, 239 Modusnamen, **0 Kollisionen** |

---

## 6. Zwei echte Fehler, die erst die Messung gefunden hat

Beide entstanden dadurch, dass die Kerne nun **früher** starten, und beide
hätten in einem Selbsttest nie auffallen können.

1. **`probe` registriert die Prozessoren.** Ein zweiter Aufruf aus `stage`
   nach `frueh_start` hängte sie ein zweites Mal an die Tafel: ein Lauf mit
   `-smp 2` meldete `apic=0 1 0 1` und rechnete mit vier Kernen, von denen es
   zwei nicht gibt. Behoben mit `S_PROBED`; `stage` liest die Tafel dann nur
   noch.

2. **Aus `PH_SCHED` kommt kein Kern zurück.** Die Messungen von Runde K5
   (`bench`, `stress`, `frames`, …) laufen über `run_phase`, und das wartet,
   bis `S_DONE` die Zahl der laufenden Kerne erreicht — hochgezählt von den
   Kernen in `phases`. Hat `frueh_start` sie vorher in ihre Leerlaufaufgabe
   geschickt, wartet `run_phase` auf ein Merkzeichen, das niemand mehr setzt:
   vier Milliarden Umdrehungen, und der Hochlauf steht. Gemessen — ein Lauf
   mit `-smp 2` und `kryptoauf` blieb nach `smp: online=2 of 2` hängen.
   Behoben mit `S_SCHEDPH`: die Messungen werden übersprungen, wenn die Kerne
   schon planen. **Das betrifft nur Läufe mit `kryptoauf`** —
   `tools/smp/run.sh` entsperrt keine Platte und misst unverändert.

Dazu ein Schönheitsfehler, der ebenfalls behoben ist: `smp.frueh_start` stand
zunächst *hinter* dem ersten `serial.puts` der Krypto-Stufe, worauf sich die
Zeilen im Protokoll verschränkten (`krypto:smp: frueh online=4 of 4`).

---

## 7. Die roten Punkte

Einzeln benannt, nicht versteckt.

1. **Die Laufzeit verrät weiter, wie viele Schlüsselplätze belegt sind.**
   `unlock` rechnet zwar alle acht durch, aber `slot_open` kehrt bei einem
   unbelegten Platz sofort zurück, ohne Argon2 zu rechnen. Gemessen: ein Platz
   3401 ms, zwei Plätze 4064 ms. Die Absicht des Kommentars über `unlock` ist
   damit **nicht eingelöst**. Diese Runde hat das **nicht behoben** — die
   Gegenmaßnahme (immer acht Ableitungen rechnen, auch für leere Plätze) würde
   das Entsperren wieder verachtfachen und gehört mit dieser Abwägung in eine
   eigene Runde.

2. **Der Gewinn ist 2,2 bis 2,7 und nicht 4.** Siehe 5.3. Wer mehr will, muss
   an die Scheibengrenze — und die ist von der Norm vorgeschrieben.

3. **`p=8` bringt nichts.** Der Kopfsatz erlaubt p bis 8, der Auftragsblock
   trägt acht Spuren, aber die Vorgabe ist p=4. Mit p=8 und acht Kernen wäre
   mehr zu holen; gemessen ist das **nicht**, und ein Träger mit p=8 wurde
   nicht angelegt.

4. **Die Kerne starten früher, und das ist eine Verhaltensänderung.** Sie
   greift nur bei `kryptoneu`/`kryptoauf`/`kryptofalsch` und nicht bei
   `noargonpar`, aber sie ist real: ein Lauf mit verschlüsselter Platte hat ab
   jetzt vier laufende Kerne, wo vorher einer lief — und überspringt dafür die
   K5-Messungen. Welche Wechselwirkungen das mit Abschnitten hat, die *beides*
   tun (entsperren **und** SMP messen), ist **ungemessen**; im Baum gibt es
   heute keinen solchen Abschnitt.

5. **SHA-NI bringt für die Entsperrzeit fast nichts.** Argon2 kostet Hunderte
   Millionen Takte, die Kopfprüfsumme einige Zehntausend. Der zweite Teil
   dieser Runde ist der zweite Teil des Auftrags, keine Rettung der
   Entsperrzeit. Ein eigener Messwert für SHA-256 im Kern (Takte je Block, mit
   und ohne) ist **nicht** erhoben — die Kreisprobe misst Richtigkeit, nicht
   Tempo.

6. **Argon2 bleibt der Posten.** Auch nach dieser Runde sind rund 460 ms der
   Entsperrzeit Argon2. Wer deutlich darunter will, muss die Parameter senken
   — und das ist eine Sicherheitsentscheidung und keine technische.

7. **Der Rückfallweg von Argon2 ist gemessen, der von SHA-NI echt gefahren.**
   Für Argon2 gibt es keine CPU ohne „mehrere Kerne“, die sich abschalten
   ließe; `noargonpar` und `-smp 1` sind die Gegenproben, und beide liefern
   byteweise dasselbe. Ein echtes Einkern-Blech ist **nicht** getestet.

8. **Bei kleinen Parametern verteilt sich nichts — und das ist richtig
   so.** Mit den Abnahmeparametern (t=1, m=64 KiB) ist ein Segment VIER
   Blöcke groß. Der Startkern hat alle vier Spuren fertig, bevor der
   Ablaufplaner eine Aufgabe auf einen anderen Kern legt; gemessen, vier
   Läufe hintereinander, alle `kerne=1` bei rund 5,9 Mio Takten. Das ist
   kein Fehler, sondern die richtige Antwort auf eine Rechnung, die zu
   klein zum Verteilen ist — aber es heißt, dass der Gewinn dieser Runde
   **erst ab einer gewissen Größe** eintritt. Wo genau die Schwelle liegt,
   ist **nicht** vermessen; bei m=32 MiB sind es verlässlich vier Kerne
   (sechs Läufe hintereinander `kerne=4`).

   *Der erste Entwurf der Abnahme prüfte die Kernzahl am falschen Lauf
   (dem mit den kleinen Parametern) und schlug deshalb sporadisch fehl.
   Die Prüfung sitzt jetzt an den Vorgabeparametern.*

9. **Die Aufgaben leben genau ein Segment.** Bei t=2, p=4 sind das 32
   Aufgaben je Entsperrung (`seg=32` im Bericht). Ein Bestand langlebiger
   Aufgaben mit eigener Barriere wäre billiger; gemessen, ob es sich lohnt,
   ist das **nicht**.

---

## 8. Was wo steht

| Datei | Was | neu? |
|---|---|---|
| `lib/crypto/argon2.fi` | `fill_segment`, `prepare`, `passes`, `finish`, `geometrie_*` herausgezogen und exportiert | geändert |
| `lib/crypto/shani.fi` | SHA-256 auf `SHA256RNDS2`/`MSG1`/`MSG2`, `usable`, `hash_blocks` | **neu** |
| `lib/crypto/sha256.fi` | schneller Weg in `compress`, `use_shani`/`shani_on` | geändert |
| `kernel/kargon.fi` | die Naht: `init`, `parallel_slice`, `spur_body`, `argon2id_par`, `report` | **neu** |
| `kernel/kshani.fi` | die Naht: `apply`, `report`, `selftest` | **neu** |
| `kernel/krypto.fi` | `derive_wrap` ruft `kargon.argon2id_par` | geändert |
| `kernel/sched.fi` | `K_ARGON` (Gattung 9) | geändert |
| `kernel/tasks.fi` | `K_ARGON` → `kargon.spur_body` | geändert |
| `kernel/arch/x86_64/smp.fi` | `frueh_start`, `S_PROBED`, `S_SCHEDPH` | geändert |
| `kernel/kstate.fi` | `ARGON_OFF` 0x126000, der Auftragsblock, die Modusworte | geändert |
| `kernel/kmain.fi` | die fünf Modusworte, `kargon.init`/`report`, `kshani.*`, `smp.frueh_start` | geändert |
| `tools/kernel/memmap.py` | der Eintrag `ARGON` | geändert |
| `tools/argon/kreis.fi` | die SHA-Kreisprobe auf dem Wirt | **neu** |
| `tools/argon/run.sh` | die Abnahme, 33 Punkte | **neu** |

Modusworte: `noargonpar` (die Gegenprobe zur Parallelität), `argonbench`,
`noshani` (die Gegenprobe zu SHA-NI), `shatest`, `shabench`.

Speicher: kdata **0x126000 bis ausschließlich 0x127000**, eine Seite.
Modusindizes **1040 bis 1044** von den zugeteilten 1040–1049. Beides genau wie
zugeteilt, keine Seite und kein Index außerhalb. `MODE_WORDS` ist 17, der
Vektor trägt 1088 Bits — 1049 liegt nachweislich darunter.
`python3 tools/kernel/memmap.py` meldet **128 Bereiche, 239 Modusnamen,
0 Kollisionen**.

---

## 9. Was offen blieb

* Der Zeitkanal über die Zahl der belegten Schlüsselplätze (roter Punkt 1).
  Das ist die nächste Runde, wenn sie jemand will — mit der Abwägung, dass die
  saubere Lösung das Entsperren verachtfacht.
* `p=8` mit acht Kernen messen, und die Vorgabeparameter daraufhin neu wählen.
  Die Parameter stehen je Platz im Kopfsatz; ein Träger bekommt später einen
  Platz mit anderen, ohne dass ein Sektor neu verschlüsselt wird.
* Ein Tempowert für SHA-256 im Kern (Takte je Block, mit und ohne SHA-NI).
  `shabench` ist als Moduswort vergeben, aber **nicht gebaut**.
* Die anderen Aufrufer von `sha256.fi` (TLS, SSH, OFS, das Paketwesen) ziehen
  den schnellen Weg jetzt stillschweigend mit. Gemessen ist dort **nichts** —
  die Kreisprobe sagt nur, dass beide Wege dasselbe rechnen.
* Ein Bestand langlebiger Spuraufgaben statt 32 kurzer je Entsperrung.
* `/root/.krypto-venv` existierte auf diesem Wirt **nicht**, womit
  `tools/krypto/run.sh` seine Gegenproben stillschweigend übersprungen hätte.
  Angelegt mit `argon2-cffi` und `cryptography`. Ein Läufer, der beim Fehlen
  des fremden Werkzeugs grün meldet statt gelb, ist eine eigene kleine Gefahr.
