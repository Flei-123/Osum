# OFS-JOURNAL.md -- was einen Stromausfall ueberlebt, und was nicht

*Runde FSROBUST, Abschnitt 2 und 3. 28.08.2026. Die Zahlen in § 5 kommen
aus `tools/fsrobust/run.sh`, Abschnitt "Stromausfall"; jede einzelne ist
ein Lauf, in dem QEMU mit SIGKILL abgeschossen wurde.*

---

## 1. Die Entscheidung: Journal, nicht Copy-on-Write

Der Auftrag laesst die Wahl. Sie faellt auf das Journal, und zwar aus
drei Gruenden, die alle in `kernel/fs.fi` stehen und nicht in einer
Vorliebe.

### 1.1 In OFS *ist* die Inodenummer die Stelle auf der Platte

```
inode_block_of(ino) = itable + (ino - 1) / inodes_per_block
```

Das ist keine Tabelle und keine Abbildung -- die Nummer IST die Adresse.
`kernel/ofs.fi` gibt der VFS-Schicht genau diese Nummer als **Knoten**
heraus, und der Kopf jener Datei sagt es ausdruecklich: *"DER KNOTEN VON
OFS IST DIE INODENUMMER."*

Copy-on-Write heisst: ein geaenderter Inode landet **woanders**. Dann
gibt es zwei Wege, und beide sind teuer:

* **Eine Umleitungstafel** (wie ZFS' Object Set oder btrfs' Root Tree).
  Das ist eine zweite Datenstruktur, die selbst atomar geschrieben werden
  muss -- also braucht man doch wieder einen atomaren Wurzelwechsel, nur
  fuer eine Tafel, die es vorher nicht gab. Ein halbes Dateisystem mehr.
* **Eine neue Inodenummer je Schreiben.** Das bricht `stat` (die
  Inodenummer ist die Identitaet einer Datei), den Namensindex aus Runde
  K15, den harten Verweis (zwei Namen, EINE Nummer) und die Zusage aus
  Runde OFS3, die die Inodenummer VOR und NACH `rename` vergleicht und
  Gleichheit verlangt.

### 1.2 CoW braucht mehr als ein Bit je Block

Solange die alte und die neue Wurzel gleichzeitig gelten, gehoert ein
Block **beiden**. Die Karte von OFS hat ein Bit je Block. Sie muesste ein
Zaehler werden -- und damit aendert sich das Format fuer JEDE bestehende
Platte, auch fuer die, die nie CoW benutzen wird.

Das Journal aendert am Format **zwei Woerter im Superblock**, die vorher
null waren. Und eine Null heisst dort seit Runde K13 "wie vorher".

### 1.3 Der Auftrag beschreibt das Journal woertlich

> "erst Absicht protokollieren, dann ausfuehren, dann Eintrag loeschen"

Das sind genau die Schritte 2, 5 und 6 in § 2.

### 1.4 Was CoW besser koennte -- und das gehoert dazu

**CoW schreibt jeden Block einmal, das Journal schreibt ihn zweimal.**
Der Preis ist gemessen und steht in § 6. CoW haette ausserdem
Schnappschuesse fast geschenkt (Runde TRESOR baut sie heute in Ring 3
nach). Wer OFS eines Tages auf CoW umbaut, faengt bei § 1.1 an und
braucht eine Umleitungstafel; diese Runde hat das nicht getan, weil der
Gewinn -- ein Schreibvorgang statt zwei -- den Umbau von `stat`, `link`
und `rename` nicht aufwiegt.

---

## 2. Das Verfahren

Ein **Redo-Journal mit sofortigem Nachtragen** -- ext3 nennt diese
Betriebsart `data=journal`, und die Wahl fuer die volle Fassung statt
`data=ordered` ist der Kern von § 4.

Der ganze Code steht in `kernel/ofsj.fi`, 380 Zeilen. Eine Umschreibung
laeuft so:

```
  1. ABSICHT        jeder Block, den fs.fi schreiben will, geht ZUERST
                    in den Journalbereich, an einen Platz. Der Platz
                    merkt sich, WOHIN der Block gehoert, und einen
                    Streuwert ueber seinen Inhalt.
  2. BESTAETIGEN    Zieltafel und Kopfblock hin, dann FLUSH CACHE, dann
                    -- als LETZTES und in EINEM Sektor -- der
                    Bestaetigungsblock mit Folgenummer und Pruefsumme,
                    dann noch einmal FLUSH CACHE.
  3. NACHTRAGEN     jeder Platz an sein Ziel. Das ist die eigentliche
                    Aenderung der Platte.
  4. LOESCHEN       der Bestaetigungsblock wird genullt.
```

**Der Bestaetigungssektor ist der Kippschalter.** Davor gilt der alte
Zustand, danach der neue. Er ist EIN Sektor, weil ein Sektor die
kleinste Einheit ist, ueber die eine Platte ueberhaupt eine Aussage
macht.

### Die Lage auf der Platte

Der Journalbereich liegt **zwischen Inodetabelle und Datenbereich**. Das
ist die billigste Stelle, die es gibt: die Karte traegt seit Runde 62
alles vor `data_start` als belegt ein, also braucht es keine
Sonderbehandlung im Zuteiler, keine in `df` und keine in `fsck`.

```
  jstart + 0        Kopf:          Kennung, Folgenummer, Anzahl
  jstart + 1..8     Zieltafel:     512 Blocknummern zu acht Oktetten
  jstart + 9..520   Nutzlast:      512 Bloecke
  jstart + 521      Bestaetigung:  Kennung, Folgenummer, Anzahl, Summe
                                   -------- 522 Bloecke
```

### Lesen waehrend einer Umschreibung

`fs.fi` liest und schreibt denselben Block mehrfach in einer Umschreibung
-- `block_alloc` liest die Karte, setzt ein Bit, schreibt sie; der
naechste `block_alloc` liest sie wieder. **Wuerde er die alte Fassung
sehen, gaebe er denselben Block zweimal her.** `ofsj.read` liefert
deshalb den Block AUS DEM JOURNAL zurueck, wenn er in der laufenden
Umschreibung liegt.

### Wo es eingehaengt ist

An **`fs.enter` und `fs.leave`** -- an dem Paar, das seit Runde 62 ohnehin
jede kritische Stelle dieser Datei klammert. Eine Liste von Aufrufstellen
waere eine Liste, die jemand vergessen kann; ein Paar, an dem alles
vorbeikommt, ist keine. Und weil `enter`/`leave` schon
wiedereintrittsfaehig sind, ist "eine Datei anlegen" von selbst EINE
Umschreibung und nicht drei: `create_path` ruft `dir_add` ruft
`write_at`, und bestaetigt wird erst, wenn der aeusserste herauskommt.

---

## 3. Was nach einem Stromausfall passiert -- alle Faelle

| Strom weg ... | gueltige Bestaetigung? | was `mount` tut | Ergebnis |
|---|:--:|---|---|
| in Schritt 1 (Absicht) | nein | nichts | der **alte** Zustand, und er ist stimmig -- die Platte wurde noch nicht angefasst |
| beim Schreiben des Bestaetigungssektors | Kennung ja, Summe nein | verwirft | der **alte** Zustand |
| in Schritt 3 (Nachtragen) | ja | traegt ALLES nach | der **neue** Zustand |
| in Schritt 4 (Loeschen) | ja | traegt noch einmal nach | der **neue** Zustand |

Das Nachtragen ist **wiederholbar**: denselben Block noch einmal mit
demselben Inhalt zu ueberschreiben aendert nichts. Deshalb ist der dritte
und der vierte Fall derselbe.

### Die Pruefsumme ist kein Schmuck

Ein halb geschriebener Bestaetigungssektor koennte die Kennung schon
tragen und die Zahlen noch nicht. Ohne Pruefsumme wuerde er als gueltig
gelesen und Muell nachgetragen -- also genau der Schaden entstehen, gegen
den das Ganze gebaut ist.

**Gemessen:** `tools/fsrobust/kaputt.py jmuell` legt einen
Bestaetigungsblock mit richtiger Kennung, plausibler Anzahl und
FALSCHER Summe an. Der Kern haengt das Abbild ein und traegt nichts nach:

```
osum: mount=1
fsck: joffen = 0        (die Bestaetigung ist nach dem Einhaengen weg)
fsck: fehler = 0        (das Dateisystem ist unversehrt)
```

### Und ein zweiter Fall, der aelter ist als diese Runde

`fs.format_as` schrieb den Superblock als **ERSTES**. Ein Formatieren,
dem der Strom ausging, hinterliess damit eine gueltige Kennung ueber
einer Karte und einer Inodetabelle, die es noch gar nicht gab -- und
`mount` glaubte ihr und las Muell als Inodes. Seit dieser Runde geht der
Superblock als **LETZTES** hin. Ein abgebrochenes Formatieren ist damit
"keine Platte dieser Art", und das ist die Wahrheit ueber sie.

---

## 4. Warum die DATEN mitgesichert werden und nicht nur die Verwaltung

ext3 und ext4 sichern in ihrer Standardbetriebsart (`data=ordered`) nur
die Verwaltung: Daten gehen an ihren Platz, danach die Metadaten. Das
haelt das Dateisystem heil, aber es hat eine Luecke, und die ist genau
der Fall, um den es hier geht:

> **Eine Datei an DERSELBEN Stelle zu ueberschreiben.**

Die Metadaten aendern sich dabei nicht (Groesse gleich, Bloecke gleich),
also gibt es nichts zu protokollieren -- und die Datei ist nach einem
Stromausfall vorne neu und hinten alt.

Deshalb misst diese Runde genau das: `kernel/user/fsrw.fi` haelt zwei
Dateien von je 4.096 Oktetten offen und ueberschreibt sie in jeder Runde
vollstaendig. Die ersten acht Oktette tragen die Rundennummer, die
restlichen 4.088 ein Muster, das AUS IHR ausgerechnet ist. Eine
gemischte Datei faellt damit auf, statt wie eine gueltige auszusehen.

**Und die Gegenprobe zeigt, dass die Messung wirklich misst:** mit dem
Wort `nojournal` -- derselbe Kern, dieselbe Platte, ein Wort Unterschied
-- treten genau diese gemischten Dateien auf. Die Zahlen stehen in § 5.

---

## 5. Der Beweis: SIGKILL mitten im Schreiben

ERGEBNIS-STROMAUSFALL

---

## 6. Was es kostet

KOSTEN-JOURNAL

---

## 7. Wovor das NICHT schuetzt

Diese Liste ist der wichtigste Abschnitt der Datei. Alles, was oben
steht, gilt unter genau den Annahmen, die hier stehen -- und wer sie
nicht kennt, haelt die Absicherung fuer mehr, als sie ist.

1. **Vor einer Platte, die luegt.** Das ganze Verfahren beruht darauf,
   dass ein `blk.write`, das zurueckkommt, wirklich auf dem Medium ist.
   Eine Platte mit Schreibpuffer, die FLUSH CACHE ignoriert (es gibt
   solche), kann die Bestaetigung VOR der Nutzlast ablegen. Dann traegt
   die Wiederherstellung Muell nach. `ofsj.commit` schickt zweimal FLUSH
   CACHE; mehr kann eine Software nicht tun.
2. **Vor einem zerlegten Sektor ausserhalb der Bestaetigung.** Die
   Pruefsumme deckt den Bestaetigungssektor und die Nutzlast im Journal.
   Ein Datenblock, den die Platte selbst halb beschrieben zurueckgibt,
   wird nicht erkannt -- dafuer braeuchte jeder Block eine Pruefsumme,
   und das ist ein anderes Format.
3. **Vor Bitfaeule.** Ein Oktett, das auf der Platte von selbst kippt,
   faellt niemandem auf. `fsck` findet daraus nur, was die Struktur
   verletzt.
4. **Vor zwei Kernen gleichzeitig.** Der Zustand der Umschreibung liegt
   EINMAL in `kdata` (`kstate.JR_OFF`), geschuetzt durch `atomic.L_FS`
   wie der Rest von `fs.fi`. Zwei Kerne, die gleichzeitig schreiben,
   laufen nacheinander durch -- das ist richtig, aber es ist auch die
   Grenze: eine zweite gleichzeitige Umschreibung gibt es nicht.
5. **Vor `/dev/hda`.** Wer roh auf das Blockgeraet schreibt (`devfs`),
   geht am Journal vorbei. Das ist in jedem Unix so und trotzdem eine
   Luecke.
6. **Vor einem Schreiben, das groesser ist als eine Umschreibung.** Ueber
   512 Bloecke hinaus wird zerlegt (§ 2); jedes Stueck ist fuer sich
   unteilbar, die Folge nicht. Aus Ring 3 kann das heute nicht vorkommen
   (`MAX_IO` = 4.096), aber ein Aufrufer im Kern koennte es ausloesen.
7. **Vor `create` und `write` als ZWEI Systemaufrufen.** Eine frisch
   angelegte, noch nicht beschriebene Datei ueberlebt einen Stromausfall
   mit NULL Oktetten. Das ist kein Schaden am Dateisystem -- es ist die
   Wahrheit ueber zwei Aufrufe -- aber wer "die Datei ist entweder da
   oder nicht" braucht, muss in eine Nebendatei schreiben und
   umbenennen. `rename` ist EINE Umschreibung und damit unteilbar.
8. **Vor FAT.** `kernel/fat.fi` hat nichts davon und bekommt auch nichts.
   Ein Server legt seine Daten nicht auf FAT.
9. **Vor einem Formatieren, dem der Strom ausgeht -- bis auf die
   Kennung.** Es bleibt eine Platte zurueck, die sich nicht einhaengen
   laesst. Das ist besser als eine, die sich falsch einhaengen laesst,
   aber die Daten von vorher sind trotzdem fort.

---

## 8. Wie man es einschaltet

| | |
|---|---|
| Abbild auf dem Wirt | `mkfs.py build <abbild> <bloecke> --v3 --journal ...` |
| Formatieren im Kern | Wort `jrnlfmt` auf der Befehlszeile |
| Abschalten (Gegenprobe) | Wort `nojournal` |
| Nachsehen | `/bin/fsck /dev/hda` meldet `journal = <bloecke>` und `joffen = 0/1` |

Ohne Journalbereich verhaelt sich alles wie vor dieser Runde -- eine
Null in `SB_JSTART` heisst "kein Journal", und ein Kern von gestern
liest eine Platte MIT Journal, ohne davon zu wissen: er sieht nur einen
Datenbereich, der etwas spaeter anfaengt.
