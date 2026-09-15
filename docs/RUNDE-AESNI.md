# Runde AESNI (K-020) — AES auf den Befehlen der Maschine

Zweig `aesni`, Grundlage `main` = `0a1d067`. Worktree `/root/osum-w-aesni`.

Ziel: die Plattenverschlüsselung aus Runde KRYPTO (K-019) ist gebaut und
richtig, aber mit **0,41 MiB/s** unbenutzbar. Das ist der einzige Grund,
warum K-019 heute nur im Prüfstand taugt.

**Abnahme: `bash tools/aesni/run.sh`.**

---

## 1. Die drei Machbarkeitsfragen — beantwortet, BEVOR gebaut wurde

Der Auftrag verlangt diese Tabelle vor der ersten Zeile Code. Sie steht
hier, und jede Antwort ist gemessen und nicht nachgeschlagen.

| # | Frage | Antwort | Beleg |
|---|---|---|---|
| 1 | Kann Firn SSE/AES-NI erzeugen? | **Ja, direkt.** `asm("aesenc xmm0,xmm1", …)` übersetzt ohne weiteres. Kein Assemblerumweg, keine Hand-Kodierung. | `/tmp/probe_aesni.fi`, siehe 1.1 |
| 2 | Wird CPUID abgefragt? | **Ja, das Muster lag schon im Baum.** `fpu.cpuid_c`, `rand.has_rdseed`, `guard.leaf7_ebx`. AES-NI ist Blatt 1 ECX Bit 25, PCLMULQDQ Bit 1. | `kernel/rand.fi:111`, `fpu.fi:262` |
| 3 | Sind die XMM-Register nutzbar und **gesichert**? | **Ja, beides — und zwar seit Runde AVX.** CR4.OSFXSR/OSXMMEXCPT/OSXSAVE werden gesetzt, und der Kontextwechsel sichert *eager* je Aufgabe. | `fpu.fi`, `docs/RUNDE-AVX.md`, siehe 1.4 |

### 1.1 Frage 1: Firn kann es, und zwar richtig

Firn hat ein eingebautes `asm` mit Operandenbindung
(`in("rdi") x`, `out("rax")`, `clobber("memory")`). Im Baum stand es
schon für `movdqu`, `paddq`, `cpuid`, `rdtsc` und sogar `vmovdqu64`
(AVX-512) — `kernel/uprog.fi`, `kernel/fb.fi`, `kernel/arch/x86_64/fpu.fi`.

Gemessen wurde trotzdem, denn „der Übersetzer frisst es" und „die
Maschine rechnet das Richtige" sind zwei verschiedene Aussagen. Eine
Probe hat `AESENC` und `PCLMULQDQ` je einmal ausgeführt und das
Ergebnis gegen eine **unabhängige Nachbildung in Python** gehalten
(S-Box aus der Körperinversion gerechnet, ShiftRows → SubBytes →
MixColumns → XOR; PCLMULQDQ als trägerlose Multiplikation):

```
AESENC  erwartet  6a695a4c20622144a8c2434003bb0b71
AESENC  gemessen  6a695a4c20622144a8c2434003bb0b71   stimmt
PCLMUL  erwartet  0000030000181b282038530800006b00
PCLMUL  gemessen  0000030000181b282038530800006b00   stimmt
```

**Damit fällt der Umweg weg.** Der Auftrag nennt als Ausweichwege (a)
eine Assemblerdatei nach dem Vorbild von `boot.s` und (b) die Oktette
von Hand über den geprüften x86-Kodierer. Keiner von beiden wird
gebraucht, und der billigste Weg ist der, den man nicht baut.

### 1.2 Frage 2: CPUID — und warum sie kein Schmuck ist

`cpuid` Blatt 1, ECX Bit 25 (AES-NI) und Bit 1 (PCLMULQDQ). `rbx` trägt
in Firn den Rahmen und wird um jedes `cpuid` herum gerettet — derselbe
Griff wie in `rand.has_rdseed`.

Dass die Prüfung nötig ist, ist **gemessen und nicht angenommen**:
dieselbe Probe unter `qemu-x86_64 -cpu qemu64` (eine CPU ohne AES-NI)
meldet korrekt `AESNI-Bit(25)=nein` — und stirbt anschließend am
*ungesicherten* `aesenc` mit

```
qemu: uncaught target signal 4 (Illegal instruction) - core dumped
```

Das ist genau der `#UD`, vor dem der Auftrag warnt. In Ring 3 ist er ein
toter Prozess, in Ring 0 ein toter Kern.

### 1.3 Frage 3: die gefährlichste — und sie war schon beantwortet

Der Auftrag nennt das richtig als den gefährlichsten Teil: *„Wenn der
Kern XMM im Kontextwechsel NICHT sichert und du sie im Kern benutzt,
zerstörst du still die Register laufender Ring-3-Prozesse."*

Diese Runde musste das **nicht bauen**, weil Runde AVX es gebaut hat,
und zwar aus genau diesem Anlass (`/bin/fetch` starb auf `-cpu max` mit
`user fault: vector=6`). Nachgesehen und bestätigt:

* `fpu.apply` setzt CR4 Bit 9 (OSFXSR), 10 (OSXMMEXCPT) und 18
  (OSXSAVE), letzteres nur wenn `cpuid` XSAVE anbietet.
* Gesichert wird **eager**, ein Rahmen (4096 Oktette) je Aufgabe aus
  `mem.frame_alloc`, mit FXSAVE/XSAVE/XSAVEOPT je nach Maschine.
* Die Gegenprobe existiert: `nofpuswitch` schaltet frei und sichert
  *nicht* — dann **muss** `vec: clean=0` werden. Erst dadurch misst der
  Test überhaupt etwas.

Im Lauf dieser Runde bestätigt (`-cpu max`):

```
fpu: mode=3  cr4=0x340620  xcr0=0x7  size=832  lazy=0
aesni: have=1  pclmul=1  used=1  fpu=1
```

`mode=3` ist XSAVEOPT, `cr4` hat Bit 9, 10 und 18 gesetzt.

**Was daraus folgt und im Kern so verdrahtet ist:** der schnelle Weg
hängt an `fpu.enabled(state)`. Wer die Vektoreinheit abschaltet
(`nofpu`), schaltet AES-NI mit ab — nicht weil es technisch müsste,
sondern weil das Gegenteil ein stiller Datenverlust in fremden
Prozessen wäre.

---

## 2. Der gewählte Weg, mit Begründung

**Firn direkt, über `asm`.** Begründung: Frage 1 ist mit Ja beantwortet
und byteweise belegt. Ein Assemblerfile oder eine Hand-Kodierung wäre
Arbeit ohne Gegenwert und eine zweite Stelle, an der etwas falsch sein
kann.

Aufgeteilt wurde in zwei Dateien, und die Grenze ist Absicht:

| Datei | Was | Kennt `kstate`? |
|---|---|---|
| `lib/crypto/aesni.fi` | die Rechnung: Schlüsselpläne, ein Block, acht Blöcke, XTS | **nein** — läuft auch im Orakel auf dem Wirt |
| `kernel/kaesni.fi` | die Naht: `cpuid` fragen, `fpu` prüfen, Schalter stellen, berichten, prüfen, messen | ja |

`kaesni` statt `aesni`: Kern und `lib` teilen **einen** Namensraum. Zwei
Module gleichen Namens sind dort eines, und der Übersetzer meldet dann
`module 'aesni' has no element 'Enc'` — in `xts.fi`, das mit dem Kern
nichts zu tun hat. Der Vorsatz `k` ist dieselbe Lösung wie bei `kjson`,
`kutil`, `kgui`.

### Was NICHT angefasst wurde

`lib/crypto/aes.fi` bleibt **Zeile für Zeile stehen**. Drei Gründe:

1. Nicht jede Maschine hat die Befehle — der Rückfallweg ist auf allem
   vor Westmere (2010) der Normalfall, nicht das Zugeständnis.
2. WLAN und SSH hängen an derselben Datei (CCM, CMAC, Key Wrap). Die
   WLAN-Abnahme ist **185 Zusagen mit einem echten WPA2-Mitschnitt**.
3. Die Tabellenfassung ist die Gegenprobe. Zwei unabhängige Wege, die
   Oktett für Oktett dasselbe liefern müssen, sind mehr wert als einer,
   dem man glauben muss.

### Drei Entwurfsentscheidungen, die Messungen erzwungen haben

**Der Schlüsselplan kommt aus `aes.key_set`.** AES-NI kann ihn mit
`AESKEYGENASSIST` selbst rechnen — aber AES-192 entsteht dabei in
Sechser-Wörtern über zwei Register, und genau dort verrechnet man sich.
`aesni.enc_from` nimmt deshalb die 240 Oktette, die `key_set` schon
gebaut und die FIPS 197 schon abgenommen hat. Damit ist der Plan **per
Konstruktion** derselbe wie in der Tabellenfassung, für alle drei
Längen, und die Kreisprobe prüft nur noch die Rechnung.

**Die Schleife steht IM asm-Block.** `kernel/fb.fi` hat das für SSE2
schon gemessen: ein `asm` je Bläschen mit der Schleife in Firn darum
brachte Faktor 1,9 statt der erwarteten 4 bis 8, weil der Rahmen um den
Block mehr kostete als die Rechnung darin. `xts_enc8` trägt sein
`dec r8 / jnz` deshalb selbst.

**Acht Blöcke nebeneinander.** `AESENC` hat auf heutigen Maschinen eine
Latenz von rund vier Takten, aber einen Durchsatz von einem je Takt.
Eine einzelne Kette lässt die Rechenwerke zu drei Vierteln leer stehen.
XTS ist aber eine Kette — Block j+1 braucht den Tweak von Block j.
Gelöst, indem die acht Tweaks **vorher** ausgerechnet in ein Feld gelegt
werden; dann sind die acht AES-Rechnungen unabhängig.

**PCLMULQDQ ist geprüft und NICHT benutzt.** Die Tweak-Multiplikation
ist eine Verschiebung um *ein* Bit; skalar über zwei `u64` kostet das so
wenig, dass keine Messung einen Unterschied zeigte. `pclmul_usable()`
steht trotzdem da und wird berichtet, damit niemand die Abwesenheit für
ein Versehen hält.

---

## 3. Die Kreisprobe — die härteste Auflage

*„Die Richtigkeit darf nicht wackeln."* Deshalb zuerst und in vier
unabhängigen Formen.

| Probe | Umfang | Ergebnis |
|---|---|---|
| FIPS 197 Anhang C.1/C.2/C.3 | AES-128/192/256, die veröffentlichten Vektoren | `69c4e0d8…`, `dda97ca4…`, `8ea2b7ca…` — **alle drei exakt** |
| Tabelle gegen AES-NI, Blöcke | 6000 Zufallsblöcke, 3 Schlüssellängen, hin und zurück | **0 ungleich** |
| Gegen OpenSSL, XTS | 300 Sektoren, Längen 16/32/512/4096, Zufallsschlüssel | **0 Abweichungen** |
| Gegen OpenSSL, Rückrichtung | 200 Sektoren, von OpenSSL erzeugter Geheimtext | **0 Abweichungen** |
| Wechselnde Schlüssel | 400 Sektoren, 4 Schlüssel im Wechsel | **0 Abweichungen** |
| Beide Wege, dieselbe Maschine | 300 Sektoren, `noaesni` gegen normal | **byteidentisch** |
| Im Kern, Ring 0 | `aestest` auf `-cpu max` | `gleich=385 ungleich=0` |

Die Zeile *wechselnde Schlüssel* ist keine Zugabe: sie prüft die
Ungültigmachung des Schlüsselspeichers aus Abschnitt 4. Ein Speicher,
der den alten Plan behält, fällt genau dort auf und sonst nirgends.

---

## 4. Das Tempo — und die Überraschung dieser Runde

### Die Ausgangslage, selbst nachgemessen

Der Bericht der Vorrunde nennt 0,41 MiB/s (in QEMU gemessen). Auf dem
Wirt, mit demselben Quelltext im Orakel:

```
XTS 512 Oktette    897,87 us/Sektor     0,544 MiB/s
XTS 4096 Oktette  6893,19 us            0,567 MiB/s
AES-256, ein Block  25,37 us
AES-128, ein Block  15,89 us
```

Dieselbe Größenordnung, bestätigt. Und die Zahlen sagen auch gleich,
**wo** es liegt: 32 Blöcke × 25,37 µs = 812 µs von 898 µs sind die
Chiffre selbst. Die XTS-Schicht ist unschuldig, genau wie der Auftrag
sagt.

### Die Überraschung: nach den Befehlen war der SCHLÜSSELPLAN der Engpass

Nach dem Einbau von AES-NI kostete ein Sektor immer noch **16 µs**, bei
einer reinen Rechenzeit von 1,9 µs. Aufgeschlüsselt (alles gemessen, je
20 000 Durchgänge):

| Teil | Kosten | Bemerkung |
|---|---|---|
| `aes.key_set` (Tabelle) | **6218 ns** | und `sector_encrypt` rief sie **zweimal** je Sektor, für k1 und k2 |
| `aesni.enc_from` | 728 ns | 240 Oktette kopieren |
| `aesni.dec_from` | 1434 ns | dazu 13 × `AESIMC` |
| `usable()` / `cpuid` | 118 ns | |
| **die XTS-Rechnung selbst** | **1943 ns** | das, worum es eigentlich ging |

Über 12 µs von 16 µs waren Schlüsselplan für einen Schlüssel, der sich
nie ändert. Eine Platte liest Sektor um Sektor mit **demselben**
Schlüssel — das war reine Arbeit für den Papierkorb.

Behoben mit einem Schlüsselspeicher in `xts.fi`, der die fertigen Pläne
des zuletzt benutzten Schlüssels hält. Der Vergleich läuft über alle 64
Oktette und bricht nicht früh ab (ein früher Abbruch wäre ein Zeitkanal
über den Schlüssel — dieselbe Regel wie in `halves_equal`).

### Die Zahlen, vorher und nachher

Auf dem Wirt (AMD EPYC 7571), **dieselbe Binärdatei, derselbe Lauf**,
umgeschaltet mit dem Orakelbefehl `noaesni`:

| Länge | AES-NI | Tabelle | Faktor |
|---|---|---|---|
| 512 Oktette (ein Sektor) | **3,08 µs — 158,79 MiB/s** | 849,00 µs — 0,58 MiB/s | **276×** |
| 4096 Oktette | **18,86 µs — 207,15 MiB/s** | 6576,45 µs — 0,59 MiB/s | **349×** |

Bester gemessener Einzelwert nach dem Schlüsselspeicher: **2,60 µs je
Sektor = 187,80 MiB/s**.

Im **Kern** (QEMU mit KVM, `rdtsc`-Takte je 512-Oktett-Sektor — in
Takten, weil `TIME_KHZ` an dieser Stelle des Hochlaufs noch null ist und
die erste Fassung dieser Messung darum treu `ns512=0` meldete):

| Lauf | Takte je Sektor | |
|---|---|---|
| `-cpu max` | **12 514** | `have=1 pclmul=1 used=1 fpu=1` |
| `-cpu max noaesni` | 1 669 719 | Gegenprobe auf derselben Maschine → **Faktor 133** |
| `-cpu qemu64,-aes` | 1 713 842 | `have=0 used=0`, Rückfall greift |

Der Unterschied zwischen 276× (Wirt) und 133× (Kern) ist kein
Widerspruch: im Kern misst `bench` den ganzen Weg durch
`xts.sector_encrypt` inklusive der Prüfungen, und der Tabellenlauf dort
läuft mit 20 statt 2000 Runden.

### Ein Megaoktett, zum Vergleich

| | vorher | nachher |
|---|---|---|
| 1 MiB | rund **2,5 s** | rund **6 ms** |

### Was Argon2 jetzt kostet

**Unverändert** — diese Runde hat Argon2 nicht angefasst. Aus der
Vorrunde: t=3/m=64 MiB/p=4 in **2,7 s** (von 13,1 s), Vorgabeparameter
**5,2 s**, der Abnahmelauf rechnet mit t=1/m=64 KiB. Argon2 ruft kein
AES; es hängt an BLAKE2b. Die Entsperrzeit beim Hochlauf wird deshalb
weiter von Argon2 beherrscht und **nicht** von XTS — was diese Runde
gewinnt, gewinnt sie beim *Lesen und Schreiben*, nicht beim Aufsperren.

---

## 5. Der Rückfallweg — echt gefahren, nicht behauptet

Der Auftrag verlangt ausdrücklich: *„Prüf das echt, nicht durch
Behauptung."* Drei unabhängige Belege:

1. **Auf dem Wirt, Ring 3.** Dieselbe Orakel-Binärdatei unter
   `qemu-x86_64 -cpu qemu64` (kein AES-NI): läuft durch, kein `#UD`,
   und liefert über 300 Sektoren **Oktett für Oktett dasselbe** wie der
   AES-NI-Lauf. Beide Wege lesen dieselbe Platte.
2. **Im Kern, CPU ohne die Befehle.** `-cpu qemu64,-aes`:
   `aesni: have=0 pclmul=0 used=0 fpu=1`, Rückfall auf die Tabelle,
   und der Kern läuft bis `kernel: done` durch.
3. **Im Kern, Befehle da, Weg von Hand heraus.** `noaesni` auf
   `-cpu max`: `have=1 … used=0`. Das ist der Schalter, der den Faktor
   oben überhaupt messbar macht — ohne ihn wäre „die Tabelle rechnet
   dasselbe" eine Aussage, die nur auf altem Blech prüfbar wäre.

Dazu die Gegenprobe zur Gegenprobe aus 1.2: **ohne** die `cpuid`-Abfrage
stirbt dasselbe `aesenc` auf `qemu64` wirklich mit `SIGILL`.

---

## 6. Was wo steht

| Datei | Was | neu? |
|---|---|---|
| `lib/crypto/aesni.fi` | die Rechnung: `usable`, `enc_from`/`dec_from`, ein Block, `xts_enc8`/`xts_dec8`, XTS je Sektor | **neu** |
| `kernel/kaesni.fi` | die Naht: `apply`, `report`, `selftest`, `bench` | **neu** |
| `lib/crypto/xts.fi` | schneller Weg in `sector_encrypt`/`sector_decrypt`, Schlüsselspeicher, `use_aesni`/`aesni_on`/`forget` | geändert |
| `lib/crypto/aes.fi` | — | **unverändert** |
| `kernel/krypto.fi` | `lock_down` ruft `xts.forget()` | geändert |
| `kernel/kstate.fi` | `AESNI_OFF` 0x120000, `AESNI_MAX` 0x1000, `M_NOAESNI`/`M_AESTEST`/`M_AESBENCH` = 1010/1011/1012 | geändert |
| `kernel/kmain.fi` | die drei Modusworte, `kaesni.apply`/`report`/`selftest`/`bench` | geändert |
| `tools/kernel/memmap.py` | der Eintrag `AESNI` | geändert |
| `tools/krypto/orakel.fi` | `xtsbench`, `aesbench`, `noaesni`, `aesni` | geändert |
| `tools/aesni/kreis.fi` | die Kreisprobe auf dem Wirt | **neu** |
| `tools/aesni/run.sh` | die Abnahme | **neu** |

Modusworte: `noaesni` (die Gegenprobe), `aestest` (Kreisprobe in Ring 0),
`aesbench` (Tempo in Ring 0).

Speicher: kdata **0x120000 bis ausschließlich 0x121000**, eine Seite.
Modusindizes **1010 bis 1012** von den zugeteilten 1010–1019. Beides
genau wie vorher zugeteilt, keine Seite und kein Index außerhalb.
`python3 tools/kernel/memmap.py` meldet **126 Bereiche, 227 Modusnamen,
0 Kollisionen**.

---

## 7. Die roten Punkte

Einzeln benannt, nicht versteckt.

1. **Nur `sector_encrypt`/`sector_decrypt` sind schnell.** `encrypt` und
   `decrypt` — die allgemeine Form mit Ciphertext Stealing — bleiben
   absichtlich auf der Tabelle. Sie tragen die krummen Längen, sie laufen
   nicht je Sektor, und der schnelle Weg bräuchte dort einen zweiten
   CTS-Zweig, den niemand benutzt. Wer sie mit glatter Länge ruft,
   bekommt dasselbe Ergebnis wie vorher, nur langsam.
2. **Der Schlüssel liegt jetzt an einer Stelle mehr im Speicher.** Der
   Schlüsselspeicher in `xts.fi` hält drei fertige Pläne. Das ist kein
   neues Leck — der Kern hält den Hauptschlüssel ohnehin in `kstate`,
   solange die Platte offen ist — aber es ist eine zusätzliche Kopie.
   `krypto.lock_down` ruft deshalb `xts.forget()`; ohne das wäre
   `lock_down` eine Lüge. **Nicht geprüft** ist, ob der Plan danach
   wirklich nirgends mehr steht (Registerreste, Stapel).
3. **Konstantzeitig nur auf dem schnellen Weg.** AES-NI hat keine
   Tabelle und damit keinen wertabhängigen Zwischenspeicherzugriff — der
   rote Punkt 2 aus `RUNDE-KRYPTO.md` ist damit auf diesem Weg behoben.
   Wer zurückfällt, rechnet weiter über die S-Box und ist es weiter
   nicht.
4. **`bench` im Kern misst in Takten, nicht in Sekunden.** `TIME_KHZ`
   ist an dieser Stelle des Hochlaufs null. Für den Faktor kürzt sich die
   Frequenz heraus, für eine Absolutangabe in MiB/s nicht — `mibs100`
   bleibt dort 0.
5. **Acht Blöcke sind nicht das Maximum.** Moderne Umsetzungen (OpenSSL)
   verschränken auch den Schlüsselplan und nutzen VAES (AVX-512, 4
   Blöcke je Register). Hier sind es acht über SSE-Register; was darüber
   ginge, ist ungemessen.
6. **Der Schlüsselspeicher hält genau EINEN Schlüssel.** Zwei
   verschlüsselte Träger nebeneinander würden ihn bei jedem Wechsel neu
   füllen (12 µs). Für die eine Wurzelplatte, die K-019 kennt, ist das
   der Normalfall; für die Gerätetafel aus dem roten Punkt 8 der
   Vorrunde wäre es einer zu wenig.
7. **PCLMULQDQ wird geprüft, gemeldet und nicht benutzt.** Siehe 2.
   Sollte die Tweak-Rechnung je ins Gewicht fallen, liegt der Befund
   schon bereit.
8. **Die Entsperrzeit beim Hochlauf ändert sich praktisch nicht.** Sie
   hängt an Argon2 (Sekunden), nicht an XTS (jetzt Millisekunden). Wer
   das Aufsperren schneller haben will, muss an Argon2 ran — und das ist
   eine eigene Runde, siehe 4.

---

## 8. Was offen blieb

* Die Betriebsarten in `aes.fi` (CCM, CMAC, Key Wrap) könnten die
  schnellen Blöcke benutzen. WLAN rechnet AES einmal je Rahmen, der
  Gewinn wäre klein, und die Runde WLAN hängt an der Datei — deshalb
  nicht in dieser Runde angefasst.
* SHA-NI für die Kopfprüfsumme und den Schlüsselplatz-MAC. Die
  Vorarbeit liegt da (`fpu.fi` erwähnt es, `cpuid` Blatt 7 Bit 29).
* Argon2 parallel über die vier Spuren (roter Punkt 3 der Vorrunde) —
  das ist der Hebel für die Entsperrzeit, nicht AES.
* Der Schlüsselspeicher als Tafel „Gerät → Plan" statt einem Platz,
  falls je ein zweiter verschlüsselter Träger dazukommt.
