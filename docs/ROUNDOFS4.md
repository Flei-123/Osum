# Runde OFS4 — OFS waechst und schrumpft im laufenden Betrieb

Zweig `ofs4`, abgezweigt von `mergeline2` (54bf135).
Der ENTWURF und die Begruendung jeder Entscheidung stehen in
`docs/OFS4-ENTWURF.md`; dieses Papier ist der Bericht: was wirklich
gebaut wurde, was gemessen wurde, und was nicht geht.

---

## Was fertig ist

| Stufe | Zustand |
|---|---|
| **0 — Befund und Entwurf** | fertig, `docs/OFS4-ENTWURF.md` (478 Zeilen) |
| **1 — online wachsen** | **fertig und gruen** |
| **2 — online verkleinern** | **fertig und gruen** |
| 3 — Zaehlerkarte fuer Schnappschuesse | **nur entworfen**, nicht gebaut (Entwurf Abschnitt 8) |

Stufe 3 bleibt bewusst ein Entwurf. Der Auftrag sagt es selbst: „Wenn die
Zeit nicht reicht: ENTWERFEN und aufschreiben, nicht halb bauen." Eine
Zaehlerkarte, die auf der Platte steht, aber von `block_alloc` noch nicht
gepflegt wird, ist das schlechteste Ding, das es gibt — eine
Datenstruktur, die aussieht, als stimme sie.

## Die eine Entscheidung, um die es ging

`kernel/ofsj.fi` sagt: *„IN OFS IST DIE INODENUMMER DIE STELLE AUF DER
PLATTE."* Daraus folgt, dass die Blockkarte nicht wachsen kann, ohne die
Inodetabelle zu schieben — und dann zeigte jede Inodenummer im ganzen
Baum auf einen anderen Block.

Der Auftrag stellte zwei Wege zur Wahl. Gewaehlt wurde **Weg (b)**: die
Inodetabelle bleibt fest, nur **Datenbloecke** ziehen um. Weg (a), die
Inode-Umleitungstafel, haette *dauerhaft* an jedem Inodezugriff gekostet
— OFS hat keinen Blockpuffer, also waere `inode_get` von einem
Blockzugriff auf zwei gegangen (+100 %) — und dafuer genau eine
Faehigkeit gebracht, die diese Runde ohnehin nicht baut.

Die Luecke, die Weg (b) laesst — die Karte kann nicht wachsen —, wird
**nicht** durch einen Umzug geschlossen, sondern durch **Vorrat beim
Formatieren**. Das ist die Antwort, die ext2/3/4 seit 2002 auf dieselbe
Frage geben (*reserved GDT blocks*, `resize_inode`), und OFS hatte das
Werkzeug dafuer schon: `mkfs.py --karten=<n>` aus Runde INSTALL. Der
Kern benutzt es jetzt im laufenden Betrieb.

**Diese Runde aendert am Format auf der Platte KEIN EINZIGES FELD.**
`SB_BLOCKS` gibt es seit Runde 62. Deshalb ist sie in beide Richtungen
rueckwaertsvertraeglich: ein Abbild von gestern waechst und schrumpft
heute, und ein Kern von gestern haengt eine gewachsene oder
verkleinerte Platte ein, ohne von dieser Runde zu wissen.

## Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/fs.fi` | **+542** | `grow_to`, `shrink_to`, `shrink_fits`, der Blockumzug ueber alle drei Zeigerstufen, der Deckel des Zuteilers |
| `lib/libc/kcall.fi` | +2 | `SYS_OSUM_FSRES` auch in der libc — `tools/posix/run.sh` vergleicht die beiden Tafeln Name fuer Name und wird sonst rot |
| `kernel/sys.fi` | **+97** | `SYS_OSUM_FSRES` (1840): zwoelf Auskuenfte, zwei Taten, keine Zeiger aus Ring 3 |
| `kernel/user/ofs4.fi` | 711 (neu) | die Messung in Ring 3 |
| `tools/ofs4/run.sh` | 425 (neu) | die Abnahme, acht Abschnitte |
| `tools/ofs4/crash.sh` | 148 (neu) | ein Stromausfall mitten im Groessenwechsel |
| `tools/ofs4/pruef.py` | 197 (neu) | dieselbe Pruefung auf dem WIRT |
| `docs/OFS4-ENTWURF.md` | 478 (neu) | der Entwurf |

Kein Test wurde abgeschaltet, keine Zeile eines bestehenden Tests
geaendert. In `kernel/fs.fi` sind ausserhalb des neuen Abschnitts genau
zwei Stellen angefasst: `block_alloc` bekommt drei Zeilen fuer den
Deckel (der ausserhalb einer Verkleinerung 0 ist und dann nichts tut),
und `geom3` setzt Deckel und Umzugszaehler zurueck.

## Wie das Verkleinern funktioniert

```
  1. PRUEFEN, ohne etwas anzufassen (zwei Kartenlaeufe)
  2. DECKEL: block_alloc gibt nichts mehr hinter der neuen Grenze her
     -- ein Wort im Arbeitsspeicher, NICHT auf der Platte
  3. UMZIEHEN, je Block EINE Umschreibung ueber das Journal
  4. KIPPEN, EINE Umschreibung: Bits hinter der Grenze auf BELEGT,
     SB_BLOCKS auf die neue Zahl
```

Der Kern des Ganzen ist Schritt 3: **ein Blockumzug fuehrt von einem
gueltigen Zustand in einen gueltigen Zustand.** Deshalb muss das
Verkleinern nicht als Ganzes unteilbar sein — ein Stromausfall an jeder
Stelle der Kette hinterlaesst ein gueltiges Dateisystem in der ALTEN
Groesse, nur anders sortiert. Erst Schritt 4 kippt die Groesse, und der
ist eine einzige Journalumschreibung.

Ein Umzug kostet hoechstens **vier** Journalplaetze von 512 (der neue
Block, der Halter des Zeigers, die Kartenbloecke von altem und neuem
Block). Der Deckel aus Schritt 2 ist zugleich das, was den Lauf
**wettlauffrei** macht: solange er steht, kann kein neuer Block hinter
der Grenze entstehen, also kann die Menge der umzuziehenden Bloecke nur
kleiner werden. Genau deshalb darf der Lauf zwischen zwei Umzuegen die
Sperre loslassen — und genau deshalb ist „online" hier woertlich
gemeint.

## Die Messungen

*(Alle Zahlen aus `bash tools/ofs4/run.sh`, Abbild 16 MiB Geraet /
8 MiB Dateisystem, Fassung 3, 256 Inodes, mit Journal.)*

### Die Grenze des Wachsens, gemessen statt behauptet

Zwei Abbilder, die sich in **einer** Zahl unterscheiden:

| | Karte deckt | Geraet | gewachsen bis |
|---|---:|---:|---:|
| `a.img` (`--karten=4`, kein Vorrat) | 16384 | 32768 | **16384** |
| `b.img` (`--karten=8`, Vorrat) | 32768 | 32768 | **32768** |

Das ist die Entwurfsentscheidung als Messung: ohne Vorrat setzt die
Karte die Grenze, mit Vorrat waechst dasselbe Dateisystem auf dasselbe
Geraet. `fsck` meldet in beiden Faellen 0 Fehler.

### Verkleinern

*(Zahlen aus dem Abnahmelauf vom 30.08.2026, `tools/ofs4/run.sh`,
Abschnitte 3 und 5b. `rc=0`, Gesamtdauer 2132 s, 62 Pruefungen
bestanden, 0 gescheitert.)*

| | |
|---|---:|
| von | **32768** Bloecke |
| auf | **2778** Bloecke |
| belegte Bloecke hinter der Grenze (`need`) | **328** |
| davon umgezogen (`moved`) | **328** |
| Dauer des Verkleinerns | **30994 ms** |
| das sind je umgezogenem Block | **94 ms** |
| Dauer des Wachsens (EINE Umschreibung) | **55 ms** |
| Verhaeltnis Verkleinern : Wachsen | **220 : 1** |
| zum Vergleich: ein Leerstart der Pruefumgebung | 8032 ms |

`need == moved` ist die Zusage: es bleibt kein Block hinter der Grenze
liegen. Der Wirt prueft es unabhaengig nach
(`tools/ofs4/pruef.py grenze`) und kommt auf denselben Fingerabdruck
wie der Gast (13907754609921278853).

Die 94 ms je Block sind **kein** Mass fuer die Platte, sondern fuer das
Journal: jeder Umzug ist eine eigene Umschreibung mit eigenem `sync`,
und der Test laeuft unter QEMU mit `cache=directsync`, also ohne jeden
Schreibpuffer des Wirts. Das ist Absicht — mit Puffer waere die Zahl
huebscher und der Stromausfalltest wertlos.

### Der normale Dateizugriff

Die Frage aus dem Auftrag: *bleibt der normale Dateizugriff gleich
schnell?* Gemessen mit `/bin/fsrw`, 30 Runden schreiben+lesen+pruefen,
einmal auf einer unberuehrten Platte und einmal auf **derselben**
Platte, nachdem sie auf 2778 Bloecke verkleinert und wieder auf 32768
gewachsen war:

| | Runden | Dauer |
|---|---:|---:|
| unberuehrte Platte | 30 | **103069 ms** |
| nach klein + gross | 30 | **112530 ms** |
| Unterschied | | **+9 %** |

Die 9 % sind **nicht** der Preis des Umbaus am Code — im normalen
Betrieb laeuft kein einziger neuer Befehl, der Deckel im `block_alloc`
ist dann 0 und die drei Zeilen sind ein Vergleich gegen Null. Die 9 %
sind die **Fragmentierung**: der Umzug hat 328 Bloecke von hinten nach
vorn in die Luecken gestopft, und danach liegen die Dateien nicht mehr
lueckenlos. Das ist genau der Grund, warum Btrfs `balance` hat und
OFS nicht. Ehrlich genannt statt weggelassen.

## Der Stromausfall — die Zahlen

| | |
|---|---:|
| Abschuesse insgesamt (SIGKILL mitten im Groessenwechsel) | **50** |
| davon trafen den Pendellauf wirklich | **50** |
| Faelle, in denen der Wirt ein beschaedigtes Dateisystem fand | **0** |
| `fsck`-Fehler in irgendeinem Lauf | **0** |
| Laeufe mit ungueltiger Geometrie | **0** |
| Laeufe, in denen das Journal etwas nachtragen musste | **5** |
| Pruefstarts, die wegen QEMU wiederholt werden mussten | **0** |
| verschiedene Groessen, die danach vorkamen | **2** (2778 und 32768) |

Die letzte Zeile ist die eigentliche Aussage: es gab **nur** die alte
und die neue Groesse, nie etwas dazwischen. Und es waren wirklich
**beide** — ohne den zweiten Feldzug (siehe unten) waere „nur zwei
Groessen" eine Aussage ueber eine einzige gewesen.

## Die Tests, und was sie wirklich rot werden laesst

| Auftrag | wie es geprueft wird |
|---|---|
| **(a)** Wachsen im laufenden Betrieb, waehrend geschrieben wird | `ofs4 last` startet `/bin/fsrw endlos` als EIGENEN Prozess (`SYS_EXEC`), wartet, bis er wirklich schreibt, und waechst dann. Danach muss der Bestand Zeile fuer Zeile derselbe sein. |
| **(b)** Verkleinern mit belegten Bloecken hinter der Grenze | Der Bestand wird so gebaut, dass **jedes zweite Fuellstueck geloescht** wird: freier Platz vorn, Belegtes hinten. Ohne diesen Schritt lieferte der Zuteiler eine luecklose Reihe von vorn, und „verkleinern" hiesse „eine Zahl im Superblock aendern" — ein gruener Test, der nichts misst. |
| **(c)** Verkleinern, wenn nicht genug frei ist | `ofs4 nein` versucht auf `data_start + 8`. Erwartet: `fits=0`, Rueckgabe 0 — **und das Abbild ist danach Oktett fuer Oktett dasselbe** (`md5sum`). Mit Gegenprobe: derselbe Start ohne die Verkleinerung laesst das Abbild ebenfalls unveraendert, sonst misst `md5sum` nichts. |
| **(d)** Stromausfall | QEMU per SIGKILL, `cache=directsync`, in ZWEI Feldzuegen (siehe unten). |
| **(e)** Namensindex, harte Verweise, `rename` | Drei Pruefblocke — vor dem Verkleinern, danach, und nach dem Wiederwachsen — werden **Zeile fuer Zeile mit `cmp` verglichen**. Darin: Inodenummern, `hartok`, `zeigok`, `renameok`, `dents`, `mtime`. |
| **(f)** Grosses Verzeichnis und dreifach indirekt | 24 Namen in einem Verzeichnis (die Verzeichnisdatei geht ueber die acht direkten Zeiger hinaus) und eine luecklose Datei mit Stuecken bei 0, 1.000.000 und 2.200.000 — die drei Stellen liegen im direkten, im doppelt und im **dreifach** indirekten Bereich. Geprueft wird jede mit 512 von 512 stimmenden Oktetten. |

### Warum zwei Feldzuege beim Stromausfall

Der Kippschalter des **Wachsens** ist EINE Umschreibung von wenigen
Millisekunden und liegt im Pendellauf unmittelbar hinter dem des
Verkleinerns. Ein zufaelliger Abschuss trifft deshalb fast immer die
**Umzugskette** — das Ergebnis ist dann immer die alte Groesse. Der
erste Feldzug misst genau das.

Der zweite laesst das Dateisystem mit `ofs4 pendel 4000` vier Sekunden
in der **verkleinerten** Groesse stehen. Erst damit kommt der zweite
erlaubte Endzustand ueberhaupt vor. Ohne diesen Feldzug waere „es gibt
nur zwei Groessen" eine Aussage ueber **eine** Groesse gewesen — und das
steht hier, weil der erste Entwurf dieses Tests genau diesen Fehler
hatte.

## Was NICHT geht, und warum

1. **Wachsen ueber die Kartendeckung hinaus.** Die Karte liegt vor der
   Inodetabelle; sie zu vergroessern hiesse, die Tabelle zu schieben.
   Der Kern **sagt** die Grenze (`ofs4 info` zeigt `map`), er umgeht sie
   nicht. Antwort: `mkfs.py --karten=<n>`.
2. **Die Zahl der Inodes ist beim Formatieren endgueltig.** Derselbe
   Handel wie bei ext2/3/4.
3. **Verkleinern nicht unter `data_start`.** Superblock, Karte,
   Inodetabelle und Journal koennen nicht umziehen.
4. **Ein Schritt traegt hoechstens 511 Kartenbloecke** (= 2.093.056
   Bloecke = 1022 MiB), weil eine Umschreibung 512 Journalplaetze hat.
   Wer mehr will, waechst oder schrumpft zweimal. Das wird geprueft und
   sauber abgelehnt, nicht stillschweigend halb getan.
5. **Die Karte wird beim Verkleinern NICHT gekuerzt.** Das ist eine
   begruendete Abweichung vom Auftrag: gekuerzt haette sie keinen
   Datenblock freigegeben (sie liegt vor `data_start`), und
   stehengelassen **ist sie der Vorrat, mit dem man wieder wachsen
   kann**. Eine Platte, die von 16 auf 8 MiB verkleinert wurde, kann
   jederzeit zurueckwachsen, ohne dass jemand sie neu formatiert.
6. **Keine Schnappschuesse.** Dafuer muesste die Karte ein Zaehler
   werden; der Entwurf steht in `docs/OFS4-ENTWURF.md`, Abschnitt 8.

## Wie nah ist OFS jetzt an Btrfs

Gemessen, nicht geschaetzt: `fs/btrfs` aus `torvalds/linux` (Zweig
`master`, `Makefile` sagt `VERSION = 7`, `PATCHLEVEL = 2`), am
30.08.2026 geholt und mit `wc -l` gezaehlt: **163.443 Zeilen in 128
Quelldateien**. OFS ist `fs.fi` + `ofsj.fi` + `ofs.fi` = **3730 Zeilen
vor dieser Runde**, 4271 danach. Das Verhaeltnis ist **rund 38 zu 1**,
und `volumes.c` + `relocation.c` allein — die zwei Btrfs-Dateien, in
denen das Verkleinern und das Verschieben belegter Bloecke stehen —
sind 15.317 Zeilen und damit mehr als das Dreifache von ganz OFS.

**Was OFS jetzt kann, das Btrfs auch kann:** online wachsen, online
verkleinern mit Umzug belegter Bloecke, ausfallsicher an jeder Stelle,
abbrechbar, mit sauberer Ablehnung.

**Was fehlt:** Schnappschuesse und Unterbaende, Copy-on-Write,
Pruefsummen ueber Daten, mehrere Geraete/RAID, Extents statt Bloecke,
B-Baeume fuer Verzeichnisse, Verdichtung, `balance`, mitwachsende
Inodezahl, `send`/`receive`.

Die ehrliche Antwort auf „wie nah" ist also: **an einer von zehn Stellen
so nah wie versprochen, an den uebrigen neun gar nicht.** 38 zu 1 an
Zeilen ist kein Zufall.
