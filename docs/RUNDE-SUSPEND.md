# Runde SUSPEND (K-018) — Suspend und Ruhezustand

**Stand:** 15.09.2026 · Zweig `suspend`, abgezweigt von `main` (`fd33f0f`) ·
Abnahme: `bash tools/suspend/run.sh` · Nummernvorrat: kdata
`0x110000..0x113000` (**vorher zugeteilt**), Modusbits 990/991 (Wort 15,
Bit 30/31), Kommandozeilenwörter `suspmess` und `suspend`.

---

## 1. Der Satz, um den es geht

**Ein definierter Zustand geht auf die Platte, kommt zurück und ist
byteweise identisch — zweimal hintereinander, ohne einen einzigen
verlorenen Seitenrahmen. Und ein absichtlich beschädigtes Abbild wird
abgewiesen statt eingespielt.**

Was dabei **nicht** behauptet wird, steht hier und nicht in einer
Fußnote: **die Maschine schläft noch nicht wirklich.** Gebaut und
gemessen ist der **Träger** — Abbild, Prüfsumme, Wiedererkennung,
Gegenprobe. Die Sicherung der CPU-Register, des FPU/XSAVE-Bereichs, der
Seitentabellen und der Gerätezustände ist **nicht gebaut**. Sie steht
einzeln in Abschnitt 7 als roter Punkt.

---

## 2. Die Vorabmessung: was war da, was hat gefehlt

Der Auftrag verlangt: zuerst messen, dann bauen. Gemessen wurde mit
`osum suspmess` im laufenden Kern (`kernel/susp.fi`), auf QEMU 7.2.22
(SeaBIOS, `-machine pc`, `-m 512`).

| Baustein | Zustand vorher | Fundstelle |
|---|---|---|
| FADT wird gelesen | **da** | `power.acpi_off` (K13), `acpiev.stage` |
| PM1a/PM1b_CNT bekannt | **da** | FADT-Versatz 64/68, `power.fi` schreibt dort schon |
| PM1a/PM1b_EVT, PM1_EVT_LEN, GPE0/GPE1, SCI_INT | **da** | `acpiev.fi` |
| SMI_CMD / ACPI_ENABLE (ACPI-Modus einschalten) | **da** | `acpiev.acpi_mode_on` |
| AML-Namensraum mit Methodenausführung | **da** | `aml.ns_hold`, `aml.eval_node` |
| Rahmenverwalter mit Zählung | **da** | `mem.frames_free` / `frames_total` |
| Blockweg zum Schreiben | **da** | `blk.write_on` / `blk.flush` |
| **`\_S3` / `\_S4`** | **FEHLT** | kein einziger Treffer im Baum |
| **FACS** (Platz für den Aufwachvektor) | **FEHLT** | kein Treffer im Baum |
| **Zustandssicherung** (Register, FPU, Seitentabellen, Geräte) | **FEHLT** | — |

Nur `_S5_` wurde gesucht, und zwar **von Hand als Oktettmuster** in
`power.s5_values` — nicht über den Deuter.

### Was die Maschine wirklich anbietet (gemessene Zeilen)

```
susp: vorabmessung -- fadt=0x1ffe198c facs=0x1ffe0000 flen=64 hwsig=0x0 wake=0x0
susp: vorabmessung -- pm1a=0x604 pm1b=0x0 s3=1,1 s4=2,2
susp: vorabmessung -- disk=1 bloecke=131072 why=ok
```

Eine FACS ist also **da** (64 Oktette, Aufwachvektor steht auf 0), und
`\_S3` ist **da**. Die Empfehlung aus K-004, S3 sei mangels
Firmware-Zusammenspiel unbrauchbar, ist auf dieser Maschine **so nicht
haltbar** — siehe Abschnitt 3.

### Die Gegenprobe, die einen echten Fehler gefunden hat

Die erste Fassung meldete **`s3=NEIN s4=NEIN`**. Das hätte als
„die Firmware kann kein S3" in den Bericht gehen können. Stattdessen
wurde gegen eine **zweite, unabhängige Quelle** gemessen: ein Abzug des
ACPI-Bereichs (`pmemsave 0x1ff00000`) durch `iasl -d`:

```
Scope (\)
{
    Name (_S3, Package (0x04) { One, One, Zero, Zero })
    Name (_S4, Package (0x04) { 0x02, 0x02, Zero, Zero })
    Name (_S5, Package (0x04) { Zero, Zero, Zero, Zero })
}
```

Die Firmware kann es. Der Fehler lag im Kern:
**`amlns.node_at(state, 0)` liefert eine ADRESSE, `amlns.child()`
erwartet einen INDEX** — die Wurzel ist schlicht Index `0`. Nach der
Berichtigung sagt der Kern `s3=1,1 s4=2,2`, **Wert für Wert dasselbe wie
iasl**. Dieser Abgleich steht dauerhaft in der Abnahme (Abschnitt 3b von
`tools/suspend/run.sh`) und nicht nur in diesem Bericht.

Ein zweiter Fehler kam aus derselben Haltung: die Plattenmessung fragte
`blkdev.fi` — das ist die **PCI-Aufzählung**, und ihre Liste füllt
`probe`, das in diesem Kern **niemand ruft**. Gemeldet wurde „keine
Platte", während dieselbe Maschine wenige Zeilen später
`osum: ata0 sectors=131072` druckte. Richtig ist `blk.fi` (dieselbe
Schnittstelle, die das Dateisystem benutzt), und die Plattenmessung
braucht einen **späteren Zeitpunkt** als die ACPI-Messung: `blk.use_ata`
läuft erst in `kmain.osum`, während `susp.stage` hinter `acpiev.stage`
hängt. Deshalb zwei Stufen — `susp.stage` (früh, ACPI) und `susp.late`
(spät, Platte).

---

## 3. Die Entscheidung: S4 gebaut, S3 gemessen

`docs/` empfiehlt (K-004) den Ruhezustand auf Platte, weil er ohne
funktionierendes S3-Firmware-Zusammenspiel auskommt. Die Empfehlung
wurde **nicht geglaubt, sondern nachgemessen** — mit diesem Ergebnis:

**Die Begründung für S4 ist eine andere als die in K-004 vermutete.**
Nicht „S3 gibt es hier nicht" (es gibt es: `_S3 = {1,1}`, FACS
vorhanden), sondern:

1. **Der Rückweg aus S3 beginnt im Realmodus.** Die Firmware springt den
   `FIRMWARE_WAKING_VECTOR` aus der FACS an — eine Adresse unter 1 MiB,
   16-Bit. Dieser Kern läuft im langen Modus mit eigener Seitentabelle;
   zurück braucht es ein Trampolin 16 → 32 → 64 Bit. Den Code hat `smp`
   für die Nebenkerne, aber er startet dort aus einem **definierten**
   Zustand, während S3 aus einem zurückkommt, in dem die Firmware den
   Speicher unter 1 MiB angefasst haben kann.
2. **S4 hängt an keiner dieser Unbekannten.** Das Abbild liegt auf der
   Platte, der Rückweg ist ein normaler Kaltstart mit einer Prüfung beim
   Hochlauf. Alles, was S4 braucht, hat dieser Kern vollständig:
   Blockweg, Rahmenverwalter, eine erprobte Prüfsumme.
3. **S4 ist prüfbar, ohne die Maschine auszuschalten.** Genau das
   verlangt die Abnahme: zwei Zyklen, byteweiser Vergleich, eine
   Gegenprobe, die fehlschlagen muss. Ein S3-Zyklus unter QEMU wäre ein
   einzelner Ja/Nein-Befund gewesen.

**Gebaut:** S4 (Träger). **Gemessen und für die nächste Runde
festgehalten:** `\_S3 = {1,1}`, `\_S4 = {2,2}`, `PM1a_CNT = 0x604`,
FACS bei `0x1ffe0000` mit 64 Oktetten. Der Schlafwert kommt jetzt aus dem
**Deuter** (`aml.eval_node` auf den Namensraum) und nicht mehr aus einer
Oktettsuche — damit findet dieser Weg auch ein Paket, das hinter einer
Methode steht, und `power.s5_values` bleibt davon unberührt.

---

## 4. Was gebaut wurde

* **`kernel/susp.fi`** — die ganze Runde in einer Datei:
  * `measure` / `report` — die Vorabmessung (FADT, FACS, PM1a/b, `\_S3`,
    `\_S4` über den Deuter), Schalter `suspmess`.
  * `disk_measure` — die Platte, an einem **späteren** Punkt.
  * `save` — Nutzlast schreiben, fortlaufend prüfsummieren, **den Kopf
    zuletzt** (ein Stromausfall mitten in der Nutzlast hinterlässt kein
    halb gültiges Abbild).
  * `restore` — Kopf prüfen (MAGIC, Fassung), **die ganze Nutzlast lesen
    und prüfen, bevor irgendetwas gilt**, erst dann übernehmen.
  * `invalidate` — das Abbild nach dem Einspielen ungültig machen.
  * `corrupt` — ein Oktett kippen, nur für die Gegenprobe.
  * `selftest` — der Prüfstand: zwei Zyklen und die Gegenprobe.
* **`kernel/kstate.fi`** — `SUSP_OFF = 0x110000`, `SUSP_MAX = 0x3000`,
  Modusbits `M_SUSPMESS` (990) und `M_SUSPEND` (991).
* **`kernel/kmain.fi`** — `susp.stage` hinter `acpiev.stage`,
  `susp.late` hinter `fs.mount`, die zwei Kommandozeilenwörter.
* **`tools/kernel/memmap.py`** — der Bereich `SUSP` eingetragen.
* **`tools/suspend/run.sh`** — die Abnahme.

### Der Aufbau des Abbilds

Es liegt in den **letzten 64 Blöcken** der Platte, nicht am Anfang: dort
stehen Partitionstafel und Dateisystem, und ein Ruhezustand, der die
Wurzel überschreibt, ist kein Ruhezustand, sondern ein Datenverlust.

```
LBA n-64      der Kopf: MAGIC "OSUMHIB", Fassung, Zahl der Blöcke,
              Prüfsumme, der Prüfstandszustand, Hardware Signature
LBA n-63 ..   die Nutzlast, 512 Oktette je Block
```

### Die Prüfsumme

Die erste Fassung rechnete FNV-1a von Hand und fiel im ersten Lauf sofort
auf: `panic: integer overflow in 'u64 * u64' at susp.fi:557`. Firn prüft
Überläufe, und eine Hashmultiplikation läuft nun einmal über. Statt den
Überlauf zu erlauben (`*%`), nimmt die Datei die Summe, die der Baum
schon hat: **`bootmod.crc32`** (IEEE, reflektiert, fortschreibbar) —
dieselbe, mit der die Startmodule geprüft werden. Sie ist **keine
Kryptographie** und soll keine sein: sie muss ein umgekipptes Oktett
finden, nicht einen Angreifer abwehren.

---

## 5. Die Messwerte

Aus einem echten Lauf, wörtlich von der seriellen Leitung
(`osum suspend acpiev`):

```
susp: vorabmessung -- fadt=0x1ffe198c facs=0x1ffe0000 flen=64 hwsig=0x0 wake=0x0
susp: vorabmessung -- pm1a=0x604 pm1b=0x0 s3=1,1 s4=2,2
susp: vorabmessung -- disk=1 bloecke=131072 why=ok
susp: == zyklus 1
vorher zyklus=1 cnt=1007 pat=0xb6b6 frei=128628
susp: gesichert n=63 sum=0x3172595f
susp: eingespielt -- sum=0x3172595f soll=0x3172595f
nachher zyklus=1 cnt=1007 pat=0xb6b6 frei=128628
susp: gleich
susp: rahmen gleich
susp: == zyklus 2
vorher zyklus=2 cnt=1014 pat=0xc7c7 frei=128628
susp: gesichert n=63 sum=0xc31f168f
susp: eingespielt -- sum=0xc31f168f soll=0xc31f168f
nachher zyklus=2 cnt=1014 pat=0xc7c7 frei=128628
susp: gleich
susp: rahmen gleich
susp: == gegenprobe kaputt
susp: KALTSTART, sauber why=Pruefsumme falsch
```

| Messgröße | Wert |
|---|---|
| Zustand nach Zyklus 1 identisch | **ja** (`cnt`, `pat`, `zyklus` byteweise) |
| Zustand nach Zyklus 2 identisch | **ja** |
| Freie Rahmen vorher / nachher, Zyklus 1 | **128628 / 128628** |
| Freie Rahmen vorher / nachher, Zyklus 2 | **128628 / 128628** |
| Verlorene Rahmen | **0** |
| Prüfsumme Zyklus 1 / Zyklus 2 | `0x3172595f` / `0xc31f168f` — **verschieden** |
| Beschädigtes Abbild eingespielt | **nein**, `why=Pruefsumme falsch` |
| `\_S3` Kern vs. iasl | `1,1` vs. `1,1` |
| `\_S4` Kern vs. iasl | `2,2` vs. `2,2` |

Dass die zwei Zyklen **verschiedene** Prüfsummen schreiben, ist selbst
eine Zusage der Abnahme: sonst misst der zweite Zyklus ein
stehengebliebenes Abbild des ersten und meldet grün, ohne etwas getan zu
haben.

---

## 6. Was die Abnahme prüft

`bash tools/suspend/run.sh` — die Zahlen stehen in Abschnitt 8.

1. Speicherkarte: 0 Kollisionen, **und** `SUSP_OFF` liegt genau auf
   `0x110000` und endet spätestens auf `0x113000`.
2. Der Kern baut.
3. Die Vorabmessung läuft, findet alles (`why=ok`), kein Ausnahmefehler.
4. **3b:** dieselbe DSDT, gelesen von `iasl` statt vom Kern — `\_S3` und
   `\_S4` müssen übereinstimmen.
5. Zwei Zyklen, byteweiser Vergleich, Rahmenzählung, verschiedene
   Abbilder, Prüfsumme beim Einspielen == Prüfsumme im Kopf.
6. Die Gegenprobe: beschädigtes Abbild → sauberer Kaltstart, **und zwar
   wegen der Prüfsumme**.
7. `tools/check-ui.sh` PASSED, `tools/usbimg/build.sh` baut.

---

## 7. Die roten Punkte, einzeln benannt

1. **Die Maschine schläft nicht wirklich.** Es wird kein `SLP_TYP|SLP_EN`
   nach PM1a_CNT geschrieben und kein Strom weggenommen. Der Zustand
   wird verworfen und ausschließlich aus dem Abbild zurückgeholt. Was
   gemessen ist, ist der Träger — nicht ein echter Netzausfall.
2. **Die CPU-Register werden nicht gesichert.** Kein `rsp`/`rbp`/`rbx`,
   keine Rücksprungadresse, kein `cr3`.
3. **Der FPU/XSAVE-Bereich wird nicht gesichert.** `fpu:` im Startlauf
   zeigt 16 Bereiche; keiner davon geht ins Abbild.
4. **Die Seitentabellen werden nicht gesichert.** Das Abbild trägt 63
   Blöcke Nutzlast, nicht den Arbeitsspeicher der Prozesse.
5. **Kein Gerätezustand.** Zeitgeber, Tastatur und Grafik werden weder
   abgelegt noch wiederhergestellt.
6. **Keine Starterkennung.** `S_RESTORED` wird gesetzt, aber der
   Hochlauf fragt sie noch nicht ab — ein echter Kaltstart spielt das
   Abbild nicht von selbst ein.
7. **S3 ist gemessen, nicht gebaut.** Der Schlafwert und die FACS liegen
   vor; der Aufwachvektor wird nicht geschrieben und das Trampolin
   16 → 32 → 64 Bit gibt es nicht.
8. **Nur auf QEMU gemessen.** Auf Blech ist diese Runde nicht gelaufen.
   `hwsig=0x0` — QEMU führt keine Hardware Signature; auf einer echten
   Maschine wäre sie der richtige Weg, ein Abbild zu verwerfen, das zu
   einer anderen Hardware gehört. Der Kopf trägt das Feld bereits, aber
   `restore` vergleicht es noch nicht.

---

## 8. Die Zahlen der Abnahme

Siehe `tools/suspend/run.sh`. Der Stand bei Abschluss der Runde steht in
der Abschlussmeldung des Zweigs.

---

## 9. Der nächste Schritt

In dieser Reihenfolge, weil jeder Schritt auf dem vorigen steht:

1. **Starterkennung** — beim Hochlauf nachsehen, ob ein gültiges Abbild
   liegt, und `hwsig` vergleichen. Danach ist S4 ein echter
   Ruhezustand und kein Prüfstand mehr.
2. **Register und `cr3` sichern**, über denselben Weg, den `smp` für die
   Nebenkerne benutzt.
3. **Den Arbeitsspeicher der Prozesse ins Abbild**, Rahmen für Rahmen
   aus der Bitkarte — dann ist die Zahl der gesicherten Rahmen die
   Messgröße, die heute noch `63 Blöcke` lautet.
4. **S3**, mit dem Aufwachvektor in der FACS und dem Trampolin. Die
   Messwerte dafür liegen seit dieser Runde vor.
