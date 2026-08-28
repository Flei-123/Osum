# STATUS — Runde FSROBUST

Zweig `fsrobust`, abgezweigt von `mergeline` (4f844b5). **Nicht nach
`main` mergen.**

Alle Zahlen hier sind gemessen. Wo etwas gerechnet ist, steht es dabei.
Die Langfassungen stehen in `docs/OFS-LIMITS.md` und
`docs/OFS-JOURNAL.md`.

---

## 0. Der Befund am Anfang — nachgemessen statt geglaubt

Der Auftrag sagt: *„OFS hatte laut docs/BACKUP-UI.md eine Grenze von
2 MiB pro Datenträger; eine Runde OFS3 sollte sie aufheben. PRÜFE ZUERST
SELBST."*

**Sie ist aufgehoben.** Gemessen, nicht nachgelesen:

| | vorher (Fassung 2) | jetzt (Fassung 3), gemessen |
|---|---:|---:|
| Datenträger | 2 MiB | **128 GiB** — und die Grenze ist der ATA-Treiber, nicht OFS |
| Datei | 2.134.016 Oktette | **136.351.744 Oktette** |
| Name | 23 Zeichen | 255 Zeichen |

Die 128 GiB sind gebootet und beschrieben worden, nicht ausgerechnet:
auf einem Abbild dieser Größe wurde eine Datei an **Block 268.431.360**
angelegt (128,0 GiB in die Platte hinein), und der Wirt hat ihren Inhalt
danach aus dem Abbild gelesen und verglichen.

---

## 1. Was gebaut wurde

| Datei | was |
|---|---|
| `kernel/ofsj.fi` | das Journal: Absicht → Bestätigung → Nachtragen → Löschen |
| `kernel/fs.fi` | jeder Schreib-/Lesezugriff geht durch `ofsj`; Superblock zuletzt |
| `kernel/user/fsck.fi` | `/bin/fsck`, roh über `/dev/hda`, in Ring 3 |
| `kernel/user/fsrlim.fi` | die Grenzen, in Ring 3 gemessen |
| `kernel/user/fsrw.fi` | das Programm, dem der Strom ausgeht |
| `kernel/user/fsrv.fi` | was danach dasteht |
| `tools/fsrobust/crash.sh` | ein Stromausfall (SIGKILL), zwei Starts |
| `tools/fsrobust/pruef.py` | dieselbe Prüfung auf dem Wirt — zweite Umsetzung |
| `tools/fsrobust/kaputt.py` | dreizehn mit Absicht zerstörte Abbilder |
| `tools/fsrobust/run.sh` | der Abnahmeabschnitt (Abschnitt 29 in `test.sh`) |
| `docs/OFS-LIMITS.md` | die Grenzen |
| `docs/OFS-JOURNAL.md` | die Entscheidung, das Verfahren, der Beweis, die Lücken |

---

## 2. Journal statt Copy-on-Write — die Begründung in einem Satz

**In OFS *ist* die Inodenummer die Stelle auf der Platte**
(`inode_block_of(ino) = itable + (ino-1)/ipb`), und `kernel/ofs.fi` gibt
genau diese Nummer als VFS-Knoten heraus. Copy-on-Write müsste sie
beweglich machen — das bricht `stat`, den harten Verweis, den
Namensindex aus K15 und die Zusage aus OFS3, dass `rename` die
Inodenummer nicht ändert. Dazu käme, dass CoW mehr als ein Bit je Block
braucht, solange zwei Wurzeln gleichzeitig gelten; die Karte von OFS hat
eines.

Das Journal kostet dagegen **zwei Wörter im Superblock**, die vorher
null waren — und eine Null heißt dort seit Runde K13 „wie vorher".

Ausführlich: `docs/OFS-JOURNAL.md` § 1, samt dem, was CoW **besser**
könnte.

---

## 3. Der Beweis

| | mit Journal | mit `nojournal` (Gegenprobe) |
|---|---:|---:|
| Abschüsse mit SIGKILL | **60** | 60 |
| **Läufe mit Schaden** | **0** | 4 |
| Läufe, die danach nicht mehr hochkamen | 0 | 0 |
| Läufe, in denen das Journal wirklich nachgetragen hat | **11** | — |

Dazu ein zweiter Lauf derselben Anordnung: 60 mit Journal, **0** Läufe
mit Schaden; 60 mit `nojournal`, 7 Läufe mit Schaden.

**Zusammen 120 Abschüsse mit Journal, 0 beschädigte Fälle — gegen
11 von 120 ohne.**

Geprüft wird jeder Lauf dreimal und von drei verschiedenen Stellen:
`fsrv` in Ring 3 (durch dieselben Systemaufrufe wie jedes andere
Programm), `/bin/fsck` roh über `/dev/hda`, und `tools/fsrobust/pruef.py`
auf dem Wirt aus dem Abbild. Die Langfassung mit der Aufteilung der
Schäden steht in `docs/OFS-JOURNAL.md` § 5.


---

## 4. `/bin/fsck`

Läuft in Ring 3, liest `/dev/hda` **roh** (nicht durch das Dateisystem,
das es prüfen soll). Prüft Superblock, Journalzustand, jede Inode samt
Zeigerbaum auf Bereich und Doppelbelegung, die Karte gegen die
Wirklichkeit und den Verzeichnisbaum. Mit `-r` behebt es, was eindeutig
ist: verlorene Blöcke freigeben, benutzte in der Karte nachtragen.

**Dass es fertig wird, ist gemessen.** `tools/fsrobust/kaputt.py` baut
dreizehn Abbilder, die mit Absicht kaputt sind; auf jedem einzelnen
schaltet der Kern selbst ab (exit 21) und `fsck` meldet eine Zahl:

| Abbild | was zerstört wurde | `fsck` sagt | fertig? |
|---|---|---|:--:|
| `kennung` | Superblock ohne OSUM-OFS-Kennung | `magic=0`, 1 Fehler | ja |
| `muell` | die ersten 64 Blöcke Zufallsoktette | `magic=0`, 1 Fehler | ja |
| `inodes` | Superblock behauptet 2^40 Inodes | `geom=0`, gedeckelt auf das, was passt | ja |
| `bloecke` | Superblock behauptet 2^50 Blöcke | `geom=0`, gedeckelt auf das Gerät | ja |
| `bereiche` | Datenbereich VOR der Inodetabelle | `geom=0`, 1.788 Fehler | ja |
| `zeigerkreis` | ein indirekter Zeiger zeigt auf sich selbst | `doppelt=1`, `totlinks=126` | ja |
| `verzkreis` | zwei Verzeichnisse enthalten einander | `kreise=1` | ja |
| `selbstverz` | ein Verzeichnis enthält sich selbst | `kreise=1` | ja |
| `doppelt` | zwei Inodes teilen einen Datenblock | `doppelt=1` | ja |
| `wildzeiger` | Blockzeiger hinter das Ende der Platte | `ausser=1` | ja |
| `totlink` | Verzeichniseintrag auf eine freie Inode | `totlinks=1` | ja |
| `leerkarte` | die Blockkarte genullt | `fehlend=1013` | ja |
| `jmuell` | Bestätigung mit richtiger Kennung, falscher Summe | `joffen=1`, sonst nichts | ja |

**Dreizehn von dreizehn: `fsck` wird fertig** (6 bis 20 Sekunden je
Abbild, der Kern schaltet selbst ab, exit 21). Keines hängt.

Und `-r` behebt, was eindeutig ist: auf `leerkarte` trägt es die 1.013
benutzten Blöcke wieder in die Karte ein, danach meldet ein zweiter Lauf
0 Fehler.


---

## 5. Runde MULTIUSER

Der Zweig `multiuser` ist zum Zeitpunkt dieser Runde **noch in Arbeit**
(unversionierte Änderungen an `perm.fi` und `sys.fi`, letzter Commit
wenige Minuten alt). Er wurde deshalb **nicht** gemergt — eine
Zusammenführung mit einem laufenden Zweig wäre eine Momentaufnahme,
die keiner von beiden gewollt hat. Die Vorschau ist konfliktfrei
(`git merge-tree`: 0 Konflikte).

**Die Rechte-Metadaten sind trotzdem schon abgesichert, und zwar ohne
eine Zeile dafür.** `mode`, `uid` und `gid` liegen seit Runde K13 im
INODE (Versatz 88, 96, 104), und `fs.set_mode`/`fs.set_owner`/
`fs.set_meta` gehen durch `fs.enter` und `fs.leave` — also durch das
Journal. Das ist der Vorteil davon, das Journal an das Klammerpaar zu
hängen statt an eine Liste von Aufrufstellen: was später dazukommt, ist
von selbst dabei.

Gemessen wird es auch: `fsrw` setzt den Modus jeder Datei auf
`0600 | (g % 8)`, **vor** dem Zähler; `fsrv` und `pruef.py` prüfen ihn
für jede Datei bis zum Zähler. Steht dort die Vorgabe 0644, ist eine
Inode-Änderung verloren gegangen, die der Zähler für erledigt erklärt
hat.

---

## 6. Was diese Runde NICHT tut

* **FAT bleibt, wie es ist.** `kernel/fat.fi` bekommt kein Journal. Ein
  Server legt seine Daten nicht auf FAT — das steht schon im Auftrag.
* **Kein Merge nach `main`.**
* **Die Fehlernummer beim Aufbrauchen der Inodetabelle bleibt falsch**
  (EPERM statt ENOSPC, `docs/OFS-LIMITS.md` § 4). Gemessen, gemeldet,
  nicht angefasst — sie läuft durch die Rechteschicht, und dort hängen
  bestehende Zusagen.
* **`dir_find` und `inode_alloc` bleiben linear.** Damit ist „N Dateien
  anlegen" quadratisch. Das ist keine Grenze des Formats und wäre eine
  eigene Runde.

---

## 7. Kein bestehender Test wurde entschärft

`tools/fsrobust/run.sh` ist **neu** und Abschnitt 29 in `test.sh`.
Angefasst wurden ausserdem `tools/osum/mkfs.py` (`--journal`, ein neues
Wort) und `tools/kernel/memmap.py` (der neue kdata-Bereich). Beide
Änderungen sind additiv; die Gegenprobe steht in `run.sh` § 7:

* zwei Läufe von `mkfs.py build` ohne `--journal` geben Oktett für
  Oktett dieselbe Datei,
* und ihre Kopfzeile ist unverändert
  `version=2 bmblocks=1 isize=128 dirent=32 namelen=24`.
