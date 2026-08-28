# OFS-LIMITS.md -- wie gross OFS wirklich darf

*Runde FSROBUST, Abschnitt 1. 28.08.2026. Jede Zahl hier ist GEMESSEN --
entweder von `kernel/user/fsrlim.fi` in Ring 3, oder auf dem Wirt aus dem
Abbild gelesen. Wo eine Zahl gerechnet und nicht gemessen ist, steht es
dabei.*

---

## 0. Warum diese Datei

`docs/BACKUP-UI.md` und der Kopf von `kernel/fs.fi` nannten fuer OFS eine
Decke von **2 MiB je Datentraeger**. Runde OFS3 hat sie aufgehoben, und
das Rundenprotokoll dazu sagt "mehrere Gigaoktett". Das ist keine Zahl.

Der Auftrag dieser Runde faengt deshalb mit einer Nachmessung an: nicht
"ist es behoben", sondern **wo liegt die Grenze jetzt**. Die Antwort auf
die erste Frage ist ja -- die auf die zweite steht unten, und sie ist an
zwei Stellen eine ganz andere, als die Rechnung aus den Konstanten
ergeben haette.

---

## 1. Die Zahlen auf einen Blick

| | Wert | woher |
|---|---:|---|
| Block | 512 Oktette | Superblock, `I_BSIZE` |
| **groesste Datei** | **136.351.744 Oktette** (266.312 Bloecke) | gemessen, binaere Suche |
| **groesster Datentraeger** | **137.438.953.472 Oktette** (268.435.456 Bloecke, 128 GiB) | gemessen, gebootet und beschrieben |
| groesstes einzelnes `write` | 4.096 Oktette | `kernel/sys.fi::MAX_IO` |
| Inodes je Datentraeger | was der Superblock sagt, minus eine | gemessen |
| **Eintraege je Verzeichnis, baulich** | **516.483** | gerechnet aus zwei gemessenen Zahlen |
| Eintraege je Verzeichnis, praktisch | siehe § 5 -- der Preis ist quadratisch | gemessen |
| laengster Name | 255 Zeichen | Runde OFS3 |
| Journalbereich | 522 Bloecke (267.264 Oktette), fest | Runde FSROBUST |

---

## 2. Die groesste Datei: 136.351.744 Oktette

**Gemessen, nicht gerechnet.** `kernel/user/fsrlim.fi` sucht die Grenze
BINAER: an Stelle `i * 512` ein Oktett schreiben und sehen, ob es
hineingeht. Dreissig Versuche, und die Antwort ist der letzte Index, an
dem es gelingt.

```
fsrlim: maxidx  = 266311        der letzte Block, in den etwas geht
fsrlim: maxfile = 136351744     (266311 + 1) * 512
fsrlim: ueber   = 0             EIN Block weiter geht es NICHT
```

Die letzte Zeile ist die wichtige. Eine Suche, die nur den letzten Erfolg
meldet, hat nichts gemessen -- erst die Gegenprobe, dass es einen Block
weiter scheitert, macht daraus eine Grenze.

Woher die Zahl kommt: acht direkte Blockzeiger, 64 durch den einfach,
4.096 durch den doppelt und 262.144 durch den dreifach indirekten
Zeiger. 266.312 Bloecke zu 512 Oktetten. Die Rechnung steht in
`kernel/fs.fi::max_file` -- aber die Rechnung ist hier die BESTAETIGUNG
der Messung und nicht ihre Quelle. Ein Zeigerbaum, dem eine Stufe fehlt,
faellt der Messung auf und der Rechnung nicht.

---

## 3. Der groesste Datentraeger: 128 GiB, und die Grenze ist NICHT OFS

Drei Abbilder wurden gebaut, gebootet und beschrieben. Sie sind duenn
(`sparse`), ein Abbild von 128 GiB kostet 65 MiB auf der Wirtsplatte.

| Abbild | was der Kern meldet | eingehaengt | beschrieben |
|---|---:|:--:|:--:|
| 4 GiB (8.388.608 Bloecke) | 8.388.608 | ja | ja |
| **128 GiB (268.435.456)** | **268.435.456** | **ja** | **ja** |
| 256 GiB (536.870.912) | **268.435.456** | ja | ja |

**Bei 256 GiB meldet der Kern nur 128 GiB, und das ist ehrlich.** Die
Grenze steht nicht in OFS, sondern in `kernel/blk.fi::identify`: dieser
ATA-Treiber legt die Blocknummer in die vier unteren Bits des
Laufwerksregisters, das ist LBA28, das sind 2^28 Sektoren. Was darueber
hinausgeht, kann er nicht ansprechen, also schneidet er die gemeldete
Zahl dort ab, statt eine Platte zu behaupten, die er nicht lesen kann.
Die Karte von OFS koennte weiter -- ihre Felder sind 64 Bit breit.

### Und der hintere Teil wird wirklich erreicht

Eine Decke zu melden ist das eine; sie zu benutzen das andere. Auf dem
128-GiB-Abbild wurden deshalb auf dem WIRT alle Bits bis Block
268.431.359 als belegt eingetragen, und dann hat der Kern eine Datei
angelegt. Der Wirt hat danach nachgesehen, wo sie liegt:

```
erster Datenblock = 268431360   (= Oktett 137.436.856.320, 128,0 GiB hinein)
Inhalt stimmt: True
Bit in der Karte gesetzt: 1
```

Der Lauf dauerte 88 Sekunden. Das ist der zweite Teil der Wahrheit ueber
grosse Platten: **`free_blocks` und der Blockzuteiler lesen die Karte
Block fuer Block.** Bei 128 GiB sind das 65.536 Kartenbloecke, und `df`
liest sie alle. Auf einer leeren Platte derselben Groesse dauerte
derselbe Lauf 26 Sekunden.

### Was das an Verwaltung kostet

| Platte | Kartenbloecke | Karte | Anteil |
|---|---:|---:|---:|
| 4 GiB | 2.048 | 1 MiB | 0,024 % |
| 128 GiB | 65.536 | 32 MiB | 0,024 % |

---

## 4. Inodes: was der Superblock sagt, minus eine

Die Zahl steht im Superblock (`SB_INODES`) und wird beim Formatieren
gewaehlt. Gemessen auf einem Abbild mit 256:

```
fsrlim: inodes = 256      was der Superblock sagt
fsrlim: iused  = 12       schon belegt (Wurzel, vier Verzeichnisse, Programme)
fsrlim: files  = 243      so viele liessen sich noch anlegen
fsrlim: ferr   = 1        und dann kam Fehler 1
```

12 + 243 = 255 = `SB_INODES - 1`. Die Null ist keine Inode; die Tabelle
faengt bei EINS an (`kernel/fs.fi::inode_block_of` rechnet `ino - 1`).

**EIN BEFUND, UND ER IST NICHT BEHOBEN:** der Fehler beim Aufbrauchen
der Inodetabelle ist **1 (EPERM)** und nicht 28 (ENOSPC). Ein Programm,
das `errno` liest, erfaehrt damit "darfst du nicht" statt "kein Platz
mehr". Das gehoert berichtigt; diese Runde hat es nicht getan, weil die
Fehlernummer durch die Rechteschicht laeuft und bestehende Zusagen
daranhaengen koennten. Es steht hier, damit es nicht vergessen wird.

---

## 5. Eintraege je Verzeichnis: 516.483 baulich, viel weniger praktisch

### Die bauliche Decke

Ein Verzeichnis IST eine Datei -- das ist der Satz, auf dem OFS steht,
und deshalb ist seine Decke die der Datei:

```
516.483 = floor(136.351.744 / 264)
```

Beide Zahlen sind gemessen (§ 2 und der Superblock), die Division ist
gerechnet. **Dass die Rechnung gilt, ist gemessen worden**, und zwar so:
auf dem Wirt wurde ein Verzeichnis mit 12.002 Eintraegen gebaut -- 3.168.528
Oktette, also WEIT hinter der doppelt indirekten Stufe, die bei 2.134.016
Oktetten endet. Der Kern hat es gelesen:

```
fsrlim: dents = 12002     alle Eintraege kamen ueber getdents zurueck
fsrlim: dlast = 1         und der LETZTE Name liess sich oeffnen
```

Ein Verzeichnis benutzt also wirklich den dreifach indirekten Zeiger wie
jede andere Datei auch.

### Die praktische Decke ist eine andere, und sie ist quadratisch

Ein Verzeichnis mit einer halben Million Eintraegen laesst sich LESEN.
Es laesst sich nicht in vertretbarer Zeit FUELLEN, und der Grund steht in
zwei Funktionen:

* `kernel/fs.fi::dir_find` geht das Verzeichnis Eintrag fuer Eintrag
  durch -- fuer JEDEN Namen, den jemand sucht.
* `kernel/fs.fi::inode_alloc` faengt bei Inode 1 an und liest je Inode
  einen Block, bis eine freie kommt -- fuer JEDE neue Datei.

Beides zusammen macht "N Dateien anlegen" zu einem Vorgang, der mit N
quadratisch waechst. Gemessen (`fsrlim viele`, Abbild mit 4.096 Inodes):

| Dateien | Wanduhr | abzueglich Leerlauf | je Datei | Faktor gegenueber der Haelfte |
|---:|---:|---:|---:|---:|
| 125 | 24,6 s | **21,0 s** | 168 ms | -- |
| 250 | 81,6 s | **78,0 s** | 312 ms | **3,7x** |
| 500 | 345,1 s | **340,9 s** | 682 ms | **4,4x** |

Doppelt so viele Dateien kosten fast VIERMAL so viel Zeit. Das ist die
Signatur von N-Quadrat, und sie ist gemessen und nicht abgeleitet: der
Leerlauf (booten und beenden, 3,5 bis 4,2 s) ist abgezogen, alle drei
Laeufe liefen nacheinander auf derselben Maschine.

Damit ist die praktische Decke keine Zahl, sondern eine Geduldsfrage:
zweitausend Dateien in EINEM Verzeichnis anzulegen dauert in dieser
Umgebung ueber eine Stunde, waehrend dasselbe Verzeichnis mit
zwoelftausend Eintraegen (auf dem Wirt gebaut) in 36 Sekunden vollstaendig
GELESEN wird. Lesen ist linear, Anlegen ist es nicht.

Das ist keine Grenze des FORMATS, sondern eine des Zuteilers und der
Suche. Ein Namensindex fuer Verzeichnisse (`kernel/nidx.fi` gibt es
schon, aber `dir_find` benutzt ihn nicht) und ein Merker im
Inodezuteiler wie der in `block_alloc` (`G_HINT`) wuerden beides linear
machen. Das ist eine eigene Runde und keine Zeile in dieser.

---

## 6. Das groesste einzelne `write`: 4.096 Oktette

`kernel/sys.fi::MAX_IO` ist 4096. Ein `write` mit mehr Oktetten schreibt
4.096 und meldet 4.096; `libc`s `write_all` ruft dann noch einmal.

**Diese Zahl ist fuer Runde FSROBUST wichtiger, als sie aussieht.** Das
Journal traegt 512 Bloecke je Umschreibung, also 262.144 Oktette
Nutzlast. Ein einzelnes `write` aus Ring 3 kann also NIE gross genug
sein, um eine Umschreibung zu sprengen -- der Zerlegemechanismus in
`fs.write_at` (siehe docs/OFS-JOURNAL.md § 6) kommt aus Ring 3 gar nicht
zum Tragen. Er ist fuer den Tag da, an dem `MAX_IO` waechst, und fuer
Aufrufer im Kern.

---

## 7. Was das Journal kostet

| | |
|---|---:|
| Journalbereich | 522 Bloecke = 267.264 Oktette |
| davon Kopf | 1 Block |
| davon Zieltafel | 8 Bloecke (512 Zahlen) |
| davon Nutzlast | 512 Bloecke |
| davon Bestaetigung | 1 Block |

Die Zahl ist FEST und haengt nicht an der Groesse der Platte. Auf einer
Platte von 32 MiB sind das 0,8 %, auf einer von 128 GiB 0,0002 %.

Ohne das Wort `--journal` (mkfs) bzw. `jrnlfmt` (Kern) gibt es den
Bereich nicht, und das Abbild ist Oktett fuer Oktett eines von vor dieser
Runde. Gegengeprueft: `mkfs.py build` auf Fassung 2 liefert vor und nach
dieser Runde dieselbe Datei (`cmp` ohne Unterschied).

---

## 8. Was NICHT gemessen wurde

Damit niemand mehr hineinliest, als dasteht:

* **Keine Platte ueber 128 GiB.** Ob OFS auf 1 TiB laeuft, ist unbekannt
  -- der Treiber kommt nicht so weit. Mit LBA48 in `blk.fi` waere es eine
  Messung wert.
* **Keine echte Platte.** Alles hier ist QEMU mit `if=ide`. Runde REALHW
  hat den Kern auf echter Hardware gebootet, aber nicht mit diesen
  Groessen.
* **Kein Verzeichnis mit 516.483 Eintraegen.** Gemessen wurden 12.002.
  Die Decke folgt aus § 2 und der Eintragsgroesse; dass die Adressierung
  bis in die dritte Stufe traegt, ist gemessen, die letzten
  Hunderttausend sind gerechnet.
* **Keine 136-MiB-Datei am Stueck.** Die Grenze wurde punktuell
  angefahren (ein Oktett an der hoechsten erreichbaren Stelle), nicht
  vollgeschrieben.
