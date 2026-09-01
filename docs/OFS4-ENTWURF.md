# OFS 4 — Wachsen, Verkleinern, und die Frage nach der Wurzel

**Runde OFS4.** Zweig `ofs4`, abgezweigt von `mergeline2`.
Dieses Papier ist Stufe 0 des Auftrags: der Befund und der Entwurf, und
zwar *vor* der ersten Zeile Code. Was danach wirklich gebaut wurde, steht
am Ende unter „Was gebaut wurde" und in `docs/ROUNDOFS4.md`.

---

## 1. Der Befund: was OFS heute ist, nachgezaehlt

Der Auftrag nennt `kernel/fs.fi` mit 2705 Zeilen. Auf `mergeline2` sind es
**2905**; die Zahl aus dem Auftrag stammt von einem aelteren Zweig. Der
Vollstaendigkeit halber, alles auf `mergeline2` gemessen (`wc -l`):

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/fs.fi` | 2905 | OFS selbst, vom Block aufwaerts |
| `kernel/ofsj.fi` | 609 | das Journal aus Runde FSROBUST |
| `kernel/ofs.fi` | 216 | der VFS-Treiber davor |
| `kernel/user/fsck.fi` | 786 | das Pruefprogramm, Ring 3, roh auf `/dev/hda` |
| `kernel/user/install.fi` | 934 | darin `wachsen`, offline, 51 Zeilen |
| `tools/osum/mkfs.py` | 996 | die zweite Umsetzung des Formats, auf dem Wirt |
| **Summe Dateisystem** | **3730** | `fs.fi` + `ofsj.fi` + `ofs.fi` |

## 2. Wie viel Code ist Btrfs wirklich

Gemessen, nicht geschaetzt. Am 30.08.2026 wurde `fs/btrfs` aus
`torvalds/linux` (Zweig `master`, `Makefile` sagt `VERSION = 7`,
`PATCHLEVEL = 2`) ueber die GitHub-API geholt und mit `wc -l` gezaehlt:

* **163.443 Zeilen** in **128** Quelldateien (`.c` und `.h`),
  davon 150.577 Zeilen in 65 `.c`-Dateien und 12.866 in 63 `.h`-Dateien.
  Das Verzeichnis hat 131 Eintraege; `Kconfig`, `Makefile` und
  `.editorconfig` sind nicht mitgezaehlt.

Die groessten Brocken:

| Datei | Zeilen |
|---|---:|
| `inode.c` | 10.862 |
| `volumes.c` | 9.034 |
| `send.c` | 8.297 |
| `tree-log.c` | 8.201 |
| `extent-tree.c` | 6.938 |
| `relocation.c` | 6.283 |
| `ioctl.c` | 5.704 |
| `extent_io.c` | 5.124 |
| `disk-io.c` | 5.097 |
| `ctree.c` | 5.091 |
| `block-group.c` | 5.027 |

**Das Verhaeltnis, damit die Groessenordnung ehrlich dasteht:**
163.443 zu 3730 ist **rund 44 zu 1**. Und das ist noch geschmeichelt: die
Zahl fuer Btrfs enthaelt weder `fs/btrfs`s Anteil an der generischen
VFS-Schicht noch `btrfs-progs` (mkfs, check, balance — noch einmal eine
sechsstellige Zeilenzahl in einem eigenen Baum). Allein
`volumes.c` + `relocation.c` — die zwei Dateien, in denen bei Btrfs das
Verkleinern und das Verschieben belegter Bloecke stehen — sind **15.317
Zeilen** und damit **das Vierfache von ganz OFS**.

Wer also sagt „OFS soll koennen, was Btrfs kann", sagt einen Satz, den
diese Runde nicht einloesen kann und nicht einloesen will. Was diese
Runde einloesen kann, ist eine *Teilmenge*: online wachsen, online
verkleinern, und ein ehrlicher Entwurf fuer die Buchhaltung, die
Schnappschuesse braucht. Was danach immer noch fehlt, steht in
Abschnitt 9.

## 3. Die Kernfrage: die Kopplung Inodenummer = Blockadresse

`kernel/ofsj.fi` sagt es woertlich, und es stimmt:

> IN OFS *IST* DIE INODENUMMER DIE STELLE AUF DER PLATTE.
> `inode_block_of` rechnet `itable + ino / ipb`.

Nachgesehen, `fs.fi`:

```
fn inode_block_of(state: u64, ino: u64) -> u64 {
    return itable(state) + (ino - 1) / inodes_per_block(state)
}
```

Daraus folgt dreierlei, und nur das dritte ist wirklich im Weg:

1. **Ein Inode kann nicht umziehen**, ohne seine Nummer zu aendern.
2. **Die Inodetabelle kann nicht umziehen**, ohne dass *jede* Nummer im
   Baum auf einen anderen Block zeigt.
3. Und weil die Karte **vor** der Inodetabelle liegt
   (`itable = bm_start + bm_blocks`, in `format_as` und in `mkfs.py`
   gleichlautend), **kann die Karte nicht wachsen, ohne die Inodetabelle
   zu schieben**. Genau daran scheitert `install.fi::wachsen` heute, und
   genau das meldet es als „zu wenig Kartenblöcke".

### Weg (a): eine Inode-Umleitungstafel

Eine eigene Tafel `ino -> Block`, atomar geschrieben, wie Btrfs sie mit
seinem Baum hat. Damit duerfte ein Inode umziehen, die Inodetabelle
duerfte wandern, und Copy-on-Write auf Inodes waere ueberhaupt erst
moeglich.

**Was der zusaetzliche Zugriff kostet, begruendet geschaetzt.** OFS hat
*keinen* Blockpuffer: `inode_get` liest bei jedem Aufruf genau einen
Block (`ofsj.read` auf `inode_block_of`) und `inode_set` liest und
schreibt genau einen. Eine Umleitungstafel legt davor **einen weiteren
Blockzugriff** — die Tafel selbst ist eine Reihe von 64 Zahlen je Block,
also ein Block je 64 Inodes. Ohne Puffer heisst das:

* `inode_get`: 1 Lesevorgang → 2. **+100 %.**
* `inode_set`: 1 Lesen + 1 Schreiben → 2 Lesen + 1 Schreiben. **+50 %.**
* `fs.path` auf `/a/b/c` macht heute je Bestandteil mindestens einen
  `inode_get` (Art) plus die Verzeichnissuche; jeder davon wird teurer.
* `fs.scan` (Runde K15, der Namensindex) laeuft ueber die *ganze*
  Inodetabelle. Mit Tafel wird aus einem sequentiellen Lauf ueber `n/2`
  Bloecke ein Lauf ueber `n/2 + n/64` Bloecke *und* ein Sprung je Inode —
  die Tafel steht woanders als die Tabelle. Der Lauf ist heute mit 0,8 s
  je Hochfahren gemessen (`docs/ROUNDSPEICHER.md`); er wuerde nicht um
  1,5 %, sondern um die Sprungkosten teurer, und die sind auf einer
  drehenden Platte etwas anderes als auf einem Zaehler.

Ein Puffer wuerde das meiste davon auffangen. **OFS hat keinen**, und
einen zu bauen ist eine eigene Runde — nicht ein Nebeneffekt dieser.

Dazu kommt: die Tafel ist eine **zweite Datenstruktur, die stimmen muss**.
Sie muss selbst atomar geschrieben werden, sie muss selbst wachsen, sie
muss selbst in `fsck` geprueft werden, und wenn sie und die Tabelle
auseinanderlaufen, ist das Dateisystem still kaputt. Das ist genau der
Satz, den `ofsj.fi` mit „ein halbes Dateisystem mehr" meint.

### Weg (b): die Inodetabelle bleibt fest, nur DATENbloecke ziehen um

Kostet **null** im laufenden Betrieb: kein zusaetzlicher Zugriff, keine
zweite Struktur, keine Formataenderung. Erlaubt das Verkleinern des
Datenbereichs vollstaendig — denn *jeder* Verweis auf einen Datenblock
steht in genau zwei Sorten von Blocknummer-Feldern, und beide sind
erreichbar:

* im Inode: `I_DIRECT[0..8)`, `I_INDIRECT`, `I_DINDIRECT`, `I_TINDIRECT`
* in einem Zeigerblock: 64 Woerter, eine, zwei oder drei Stufen tief

Verzeichnisse sind Dateien, ihre Bloecke sind Datenbloecke, also sind sie
mit erfasst. Ausserhalb dieser beiden Sorten zeigt **nichts** in OFS auf
einen Datenblock — der Superblock zeigt nur auf Karte, Inodetabelle,
Journal und Datenanfang, und die liegen alle vor `data_start`.

**WAS WEG (b) NICHT KANN, und das steht hier, bevor er gewaehlt wird:**

1. **Keine Schnappschuesse.** Ein Schnappschuss braucht zwei gleichzeitig
   gueltige Wurzeln; in OFS ist die Wurzel die Inodetabelle an einer
   festen Stelle. Zwei davon gaebe es nur mit einer Umleitungstafel
   (Weg a) oder mit einer zweiten Tabelle und damit zwei Nummernraeumen.
2. **Kein Copy-on-Write auf Inodes.** Ein geaenderter Inode wird
   weiterhin an Ort und Stelle ueberschrieben — abgesichert durch das
   Journal, nicht durch CoW.
3. **Die Inodetabelle kann nicht wandern.** Also ist die **Zahl der
   Inodes beim Formatieren endgueltig**. Ein Dateisystem, das auf das
   Zehnfache waechst, hat danach immer noch dieselbe Zahl von Dateien —
   das ist derselbe Handel, den ext2/3/4 mit ihrer festen
   Inodezahl machen, und es ist der bekannteste Nachteil dieser
   Familie.
4. **Alles vor `data_start` kann nicht umziehen**: Superblock, Karte,
   Inodetabelle, Journal. Verkleinern kann also nie unter
   `data_start` gehen.
5. **Der Datenbereich kann nicht nach vorn wachsen**, nur nach hinten.

### Der dritte Punkt, den die Aufgabenstellung nicht nennt

Weg (b) scheint an Punkt 3 zu scheitern, sobald man *wachsen* will: eine
groessere Platte braucht eine groessere Karte, und die schoebe die
Inodetabelle. Der Ausweg ist **nicht**, die Karte zu verschieben, sondern
sie **beim Formatieren gross genug zu machen**.

Genau so loest es ext2/3/4 seit 2002, und es hat dort einen Namen:
*reserved GDT blocks* (`resize_inode`). `mke2fs` legt Platz fuer eine
groessere Gruppendeskriptortafel an, damit `resize2fs` spaeter wachsen
kann, **ohne etwas zu verschieben**. Ohne diese Reserve sagt ext4
schlicht „Filesystem does not support online resizing" — es baut sich
nicht heimlich um.

**Und OFS hat das schon.** Runde INSTALL hat `mkfs.py --karten=<n>`
gebaut, samt Begruendung im Quelltext:

> RUNDE INSTALL: VORRAT AN KARTENBLOECKEN. `--karten=n` legt MEHR
> Kartenbloecke an, als die Platte braucht; die Bits dahinter stehen auf
> BELEGT. Genau das braucht ein Installationsprogramm, das dasselbe
> Dateisystem spaeter auf einer groesseren Partition WACHSEN lassen will.
> Ohne Vorrat muesste dabei die Inodetabelle wandern, und das ist kein
> Wachsen mehr, sondern ein Neubau.

`mount` nimmt eine zu grosse Karte an (es prueft nur, dass sie nicht zu
**klein** ist), `fsck` ebenso (`if bmb * 4096 < total`). Es ist also
**kein Formatwechsel** noetig — nur ein Kern, der die Reserve *im
laufenden Betrieb* benutzt.

### Die Wahl

**Weg (b), mit der Vorratskarte als Antwort auf das Wachsen.**

Begruendung in einem Satz: Weg (a) kostet *dauerhaft* an jedem
Inodezugriff (+50 bis +100 % ohne Blockpuffer) und bringt genau eine
Faehigkeit, die diese Runde ohnehin nicht baut (Schnappschuesse);
Weg (b) kostet im laufenden Betrieb **nichts**, loest den eigentlichen
Auftrag (wachsen und verkleinern) vollstaendig, und die Luecke, die er
laesst, ist an derselben Stelle wie bei ext4 — und wird an derselben
Stelle mit derselben Antwort geschlossen.

Was das ausdruecklich heisst: **eine Platte, die ohne Vorratskarte
formatiert wurde, kann nur bis zur Kartendeckung wachsen.** Das ist die
heutige Grenze, und diese Runde behaelt sie bei, statt heimlich die
Inodetabelle zu schieben. Der Kern **sagt** die Grenze (`ofs4 karte`), er
umgeht sie nicht.

## 4. Wie sich das mit dem Journal aus FSROBUST vertraegt

Journal und Umzug koennen nicht nur koexistieren — der Umzug *braucht*
das Journal, und zwar an genau zwei Stellen.

**Die Reihenfolge innerhalb einer Umschreibung.** `ofsj` gibt sie vor und
diese Runde folgt ihr ohne Ausnahme: `begin` → alle `write` → `commit`.
`commit` schreibt Zieltafel und Kopf, spuelt, setzt dann in **einem
Sektor** die Bestaetigung, spuelt wieder, und traegt erst danach nach.
Der Bestaetigungssektor ist der Kippschalter. Das heisst fuer den Umzug
eines Blockes von X nach Y:

```
  enter()                       -- ofsj.begin
  Y = block_alloc()             -- setzt Bit(Y) [Kartenblock], nullt Y
  lies X, schreib Y             -- Nutzlast, derselbe Platz wie das Nullen
  schreib Halter[off] = Y       -- Inodeblock ODER Zeigerblock
  block_free(X)                 -- loescht Bit(X) [Kartenblock]
  leave()                       -- ofsj.commit
```

Das sind **hoechstens vier** Journalplaetze (Y, Halter, Kartenblock von
Y, Kartenblock von X; die beiden Kartenbloecke fallen oft zusammen, dann
sind es drei). `MAX_SLOTS` ist 512 — ein Umzug passt mit sehr grossem
Abstand in *eine* unteilbare Umschreibung.

**Und das ist der Punkt, an dem der Entwurf steht oder faellt:** ein
Blockumzug ist eine Aenderung, die das Dateisystem **von einem gueltigen
Zustand in einen anderen gueltigen Zustand** bringt. Vorher: der Block
liegt bei X, der Verweis zeigt auf X, Bit(X) gesetzt, Bit(Y) frei.
Nachher: der Block liegt bei Y, der Verweis zeigt auf Y, Bit(Y) gesetzt,
Bit(X) frei. Beide Zustaende sind vollstaendig stimmig, und die
Dateiinhalte sind in beiden Oktett fuer Oktett dieselben.

Daraus folgt das Entscheidende fuer die Abbrechbarkeit: das Verkleinern
**muss nicht als Ganzes unteilbar sein**. Es ist eine Kette von
unteilbaren Schritten, und ein Stromausfall an *jeder* Stelle der Kette
hinterlaesst ein gueltiges Dateisystem in der **alten** Groesse — mit ein
paar Bloecken, die schon umgezogen sind. Das ist kein Zwischenzustand,
das ist ein gueltiger Zustand, der zufaellig anders aussortiert ist.

Erst der **letzte** Schritt ist der Kippschalter: eine einzige
Umschreibung, die die Bits hinter der neuen Grenze auf *belegt* setzt und
`SB_BLOCKS` schreibt. Davor gilt die alte Groesse, danach die neue, und
nie etwas dazwischen.

**Warum die Bits hinter der Grenze auf BELEGT und nicht auf frei:** genau
so macht es `format_as` seit Runde OFS3 fuer den Bereich hinter dem Ende
der Platte („WAS HINTER DER PLATTE LIEGT, GILT ALS BELEGT"). Es ist
dieselbe Lage und deshalb dieselbe Antwort — und es sorgt dafuer, dass
ein Kern *ohne* diese Runde, der so eine Platte einhaengt, die Bloecke
hinter der Grenze nicht vergibt.

**Warum der Zuteiler waehrend des Umzugs gedeckelt wird und die Deckelung
NICHT auf der Platte steht:** waehrend des Umzugs darf `block_alloc`
keinen Block hinter der neuen Grenze mehr hergeben, sonst zieht der Umzug
Bloecke nach vorn, waehrend nebenher neue nach hinten wandern. Der Deckel
ist ein Wort im Arbeitsspeicher (`G_CAP`). Er *muss* keinen Stromausfall
ueberleben: geht der Strom aus, ist die Verkleinerung abgebrochen, das
Dateisystem hat die alte Groesse, und ein Block hinter der Grenze ist
dann voellig zu Recht benutzbar. Ein Deckel auf der Platte waere ein
Zustand, den jemand aufraeumen muesste.

**Die andere Reihenfolge, die stimmen muss: Nachtragen vor Geometrie.**
`mount` traegt das Journal nach, *bevor* es die Geometrie aus dem
Superblock liest — das steht seit FSROBUST so da und ist die Bedingung
dafuer, dass ein nachgetragener Superblock (also eine nachgetragene
*Groesse*) auch gilt. Diese Runde aendert daran nichts und haengt sich
genau dahinter.

## 5. Was bricht — jede Zusage einzeln durchgegangen

| Zusage | woran sie haengt | bricht Weg (b)? |
|---|---|---|
| **Namensindex (K15/`nidx.fi`)** | ein Ring im Arbeitsspeicher aus `dir_add`/`dir_remove`; der Index wird beim Start aus `fs.scan` ueber die *Inodetabelle* gebaut | **nein.** Der Umzug legt keinen Verzeichniseintrag an und loescht keinen, ruft also weder `dir_add` noch `dir_remove`. Die Inodetabelle steht Oktett fuer Oktett an derselben Stelle; nur *Blockzeiger innerhalb* der Inodes aendern sich, und die liest `scan` nicht. |
| **Harte Verweise** | zwei Verzeichniseintraege mit derselben Inodenummer (`link_path`) | **nein.** Inodenummern bleiben unveraendert. Ein Block, der zu einer Inode gehoert, die zwei Namen hat, zieht *einmal* um — der zweite Name zeigt auf dieselbe Inode und sieht die Aenderung von selbst. |
| **`stat`** | `st_ino` aus der Inodenummer, Groesse/Rechte/Zeiten aus dem Inode | **nein** — mit einer Auflage: der Umzug darf **`touch_mtime` nicht rufen**. Einen Block zu verschieben ist keine Aenderung des Inhalts, und eine Datei, deren Aenderungszeit sich beim Verkleinern des Dateisystems bewegt, wuerde `find -newer`, `tar` und jedes Sicherungsprogramm anluegen. Der Umzug schreibt deshalb *nur* das Zeigerfeld. |
| **`rename` ohne Kopie (OFS3)** | `rename_path` haengt einen Verzeichniseintrag um, die Inodenummer bleibt | **nein.** Unberuehrt. |
| **Der dreifach indirekte Zeiger** | drei Stufen Zeigerbloecke | **nein**, aber er ist die Stelle, an der der Umzug schwierig wird: die Zeigerbloecke sind selbst Datenbloecke und koennen selbst hinter der Grenze liegen. Der Umzug zieht deshalb **erst den Zeigerblock selbst** nach und steigt **dann** hinein. |
| **Symbolische Verweise (`T_LINK`)** | der Inhalt *ist* der Pfad, in gewoehnlichen Datenbloecken | **nein.** Wie jede andere Datei. |
| **Alte Abbilder (v1/v2)** | Nullen im Superblock heissen „wie vorher" | **nein.** Diese Runde fuegt dem Format **kein einziges Feld** hinzu. `SB_BLOCKS` gab es seit Runde 62. |
| **Ein Kern von gestern liest eine gewachsene/verkleinerte Platte** | er liest `SB_BLOCKS` und die Karte | **nein.** Er sieht schlicht ein Dateisystem anderer Groesse. Deshalb ist diese Runde rueckwaertsvertraeglich in *beide* Richtungen — das ist selten und es ist der Lohn dafuer, das Format nicht angefasst zu haben. |

Was Weg (a) an derselben Tabelle gebrochen haette: nichts davon
zwangslaeufig — aber jedes „nein" oben waere ein „nur, wenn die Tafel
stimmt" geworden.

## 6. Stufe 1 — online wachsen

`install.fi::wachsen` (51 Zeilen, offline, roh auf `/dev/hda`) wandert als
`fs.grow_to` in den Kern und wird dabei drei Dinge, die es vorher nicht
war: **online**, **journalgesichert** und **eine einzige Umschreibung**.

```
grow_to(neu):
    ziel = min(neu, Geraetegroesse, Kartendeckung)
    wenn ziel <= alt: nichts zu tun
    wenn (betroffene Kartenbloecke + 1) > MAX_SLOTS: ablehnen  (stufenweise)
    enter()                                  -- eine Umschreibung
      fuer jeden Kartenblock von alt bis ziel:
          Bits [alt, ziel) auf FREI
      Superblock: SB_BLOCKS = ziel
    leave()                                  -- der Kippschalter
    Geometrie im Speicher nachziehen
```

Ein Stromausfall mittendrin: entweder die Bestaetigung steht (dann gilt
die neue Groesse *mit* den freigegebenen Bits) oder sie steht nicht (dann
gilt die alte Groesse *ohne* sie). Nie das eine ohne das andere — das
war der Fehler, den `install.fi` machen *konnte*: es schrieb den
Superblock **zuerst** und die Bits danach, und ein Abbruch dazwischen
hinterliess ein Dateisystem, das Bloecke fuer belegt hielt, die es
gerade dazubekommen hatte. (Kein Schaden — aber verlorener Platz, den nur
`fsck -r` zurueckholt.)

**Die Grenze `MAX_SLOTS`.** Ein Kartenblock deckt 4096 Bloecke = 2 MiB.
512 Journalplaetze minus einer fuer den Superblock sind 511 Kartenbloecke
= **2.093.056 Bloecke = 1022 MiB** Zuwachs je unteilbarem Schritt. Wer
mehr will, waechst zweimal. Das ist eine Zahl und keine Ausrede: sie
steht im Quelltext, sie wird geprueft, und `ofs4 wachsen` sagt es.

**Der Fall, den `install.fi` heute ablehnt** (Karte zu klein), bleibt
abgelehnt — aber jetzt mit einem Weg daneben: `mkfs.py --karten=<n>`
legt die Reserve an, und danach geht das Wachsen bis `n * 4096` Bloecke
im laufenden Betrieb. Das ist Abschnitt 3, „Der dritte Punkt".

## 7. Stufe 2 — online verkleinern

```
shrink_to(neu):
  1. PRUEFEN, ohne etwas anzufassen
       neu >= data_start + 8 ?
       neu < alt ?
       belegte Bloecke in [neu, alt)  =  U      (Kartenlauf)
       freie Bloecke in [data_start, neu) = F   (Kartenlauf)
       F >= U ?           sonst: ABLEHNEN, nichts angefasst
       (betroffene Kartenbloecke + 1) <= MAX_SLOTS ?
  2. DECKEL: block_alloc gibt ab jetzt nichts mehr ueber `neu` heraus
       (ein Wort im Arbeitsspeicher, nicht auf der Platte)
  3. UMZIEHEN, je Block EINE Umschreibung:
       fuer jede Inode 1..inode_count:
         Art == frei?  weiter
         die acht direkten Zeiger
         I_INDIRECT   -- erst den Zeigerblock selbst, dann seine 64
         I_DINDIRECT  -- erst den Block, dann 64 Bloecke zu je 64
         I_TINDIRECT  -- drei Stufen, gleiche Regel
  4. KIPPEN, EINE Umschreibung:
       Bits [neu, alt) auf BELEGT
       Superblock: SB_BLOCKS = neu
  5. Deckel weg, Geometrie im Speicher nachziehen
```

**Warum Schritt 1 vor Schritt 2 steht und nicht mitten drin:** eine
Ablehnung nach dem halben Umzug waere kein Fehlschlag, sondern ein
Dateisystem, das jemand umsortiert hat, ohne dass es jemand wollte.
Nachweisbar unschaedlich ist das trotzdem (Abschnitt 4), aber
„nichts angefasst" ist eine staerkere Zusage, und der Kartenlauf, der sie
einloest, kostet zwei Durchlaeufe ueber die Karte — bei 32 MiB sind das
16 Bloecke lesen.

**Der Fall „ein Inode liegt hinter der Grenze":** kann in OFS gar nicht
eintreten. Die Inodetabelle liegt *vor* `data_start`, und `neu` ist
mindestens `data_start + 8`. Die Entscheidung aus Stufe 0 greift hier
also nicht als Sonderfall, sondern als Bauform: weil kein Inode je
hinter der Grenze liegen *kann*, braucht Weg (b) den Fall nicht.

**Warum die Karte NICHT gekuerzt wird.** Der Auftrag nennt „Blockkarte
kuerzen" als Schritt 3. Das waere hier falsch, und zwar aus zwei Gruenden:

1. Die Karte liegt **vor** der Inodetabelle. Kuerzen wuerde also keinen
   Datenblock freigeben, sondern ein Loch zwischen Karte und Tabelle
   hinterlassen — Platz, den niemand benutzen kann, weil `data_start`
   sich nicht bewegen darf.
2. Die stehengebliebene Karte **ist die Reserve, mit der man wieder
   wachsen kann.** Eine Platte, die von 64 auf 32 MiB verkleinert wurde,
   behaelt damit eine Karte fuer 64 MiB — und kann jederzeit
   zurueckwachsen, ohne dass jemand sie neu formatiert. Das ist genau
   die ext4-Antwort aus Abschnitt 3, nur diesmal geschenkt.

Gekuerzt wird also `SB_BLOCKS` und nicht `SB_BMBLOCKS`. Das steht hier,
weil es eine Abweichung vom Auftrag ist und eine begruendete sein muss.

**Abbrechbarkeit, noch einmal ausgeschrieben.** Ein SIGKILL

* in Schritt 1: nichts geschrieben.
* in Schritt 2: nichts geschrieben (nur ein Wort im RAM).
* in Schritt 3, zwischen zwei Umzuegen: gueltiges Dateisystem, alte
  Groesse, `k` Bloecke schon vorn.
* in Schritt 3, *innerhalb* eines Umzugs: das Journal entscheidet — vor
  der Bestaetigung gilt der alte Block, danach der neue. Beides gueltig.
* in Schritt 4: das Journal entscheidet — alte Groesse oder neue Groesse.

In **keinem** Fall gibt es einen Zustand „halb verkleinert". Es gibt nur
„alte Groesse, teilweise umsortiert" und „neue Groesse".

## 8. Stufe 3 — die Buchhaltung fuer Schnappschuesse (Entwurf)

`ofsj.fi` nennt das Hindernis genau: *„Solange die alte und die neue
Wurzel gleichzeitig gelten, gehoert ein Block beiden. Die Karte von OFS
hat EIN Bit je Block; sie muesste ein Zaehler werden, und damit aendert
sich das Format fuer JEDE bestehende Platte."*

Der Entwurf, **nicht gebaut** (Begruendung unten):

* Eine **zweite Karte**, die *Zaehlerkarte*, mit vier Bits je Block
  (Zaehler 0..15, 15 = „viele", dann wird ein Ueberlaufbaum noetig — oder
  schlicht: 15 heisst „diesen Block nie freigeben"). 4 Bits je Block sind
  128 Bloecke Karte je Gigaoktett, also 0,006 % der Platte.
* Die **alte Bitkarte bleibt**, und sie behaelt ihre Bedeutung: „belegt".
  Sie ist damit die Ableitung `Zaehler > 0`. Warum beides und nicht nur
  die Zaehlerkarte: weil `block_alloc`, `free_blocks` und `df` die
  Bitkarte oktettweise lesen (255 und 0 in einem Griff), und das ist der
  Grund, warum `df` auf einer Platte von vier Gigaoktett kein Fall fuer
  Minuten ist. Eine Zaehlerkarte muesste man nibbleweise lesen.
* Zwei neue Superblockwoerter — `SB_RCSTART`, `SB_RCBLOCKS` — nach
  derselben Regel wie alle vorherigen: **eine Null heisst „wie vorher"**,
  also keine Zaehlerkarte, also genau ein Verweis je Block, also das
  heutige Verhalten. Damit bleibt jedes bestehende Abbild lesbar, und
  das ist die Bedingung, unter der dieses Feld ueberhaupt vergeben
  werden darf.
* `block_free` wird zu `block_unref`: Zaehler herunter; nur bei 0 faellt
  das Bit in der Bitkarte.
* Ein Schnappschuss erhoeht dann den Zaehler jedes erreichbaren Blockes
  — und *das* ist der teure Teil, denn er laeuft ueber den ganzen Baum.
  Btrfs macht das nicht so; es zaehlt Verweise auf *Extents* und nicht
  auf Bloecke, und es hat dafuer `extent-tree.c` mit 6938 Zeilen. Diesen
  Unterschied hier zu verschweigen waere unehrlich.

**Warum das in dieser Runde nur ein Entwurf bleibt.** Der Auftrag sagt
es selbst: „Wenn die Zeit nicht reicht: ENTWERFEN und aufschreiben, nicht
halb bauen." Eine Zaehlerkarte, die *da* ist, aber von `block_alloc`
noch nicht gepflegt wird, ist genau das schlechteste Ding, das es gibt —
eine Datenstruktur, die aussieht, als stimme sie. Sie gehoert in die
Runde, die auch den Schnappschuss baut, und in dieselbe.

## 9. Wie nah ist OFS damit an Btrfs — und was fehlt

**Was OFS nach dieser Runde kann, das Btrfs auch kann:**
online wachsen, online verkleinern mit Umzug belegter Bloecke,
ausfallsicher gegen Stromausfall an jeder Stelle, abbrechbar.

**Was fehlt, ehrlich aufgezaehlt:**

| Btrfs | OFS 4 |
|---|---|
| Schnappschuesse, Unterbaende (subvolumes) | nein — Entwurf in Abschnitt 8 |
| Copy-on-Write auf allem | nein — Journal statt CoW (FSROBUST) |
| Pruefsummen ueber *Daten* | nein — nur ueber den Bestaetigungssektor |
| RAID ueber mehrere Geraete | nein — OFS haengt an *einer* Platte (`ofs.fi`: „OFS laesst sich genau einmal einhaengen, als Wurzel") |
| Extents statt Bloecke | nein — 512-Oktett-Bloecke, drei Zeigerstufen |
| B-Baeume fuer Verzeichnisse | nein — lineare Verzeichnisse |
| transparente Verdichtung | nein |
| `balance`, Umverteilung im Betrieb | nein — nur das Verkleinern zieht um |
| Inodezahl waechst mit | nein, und kann es in Weg (b) nicht |
| Senden/Empfangen (`send.c`, 8297 Z.) | nein |

Die Antwort auf „wie nah" ist also: **an genau einer von zehn Stellen so
nah wie versprochen, und an den uebrigen neun gar nicht.** 44 zu 1 an
Zeilen ist kein Zufall.

---

## Was gebaut wurde

*(wird nach Stufe 1 und 2 mit Messwerten gefuellt — siehe
`docs/ROUNDOFS4.md`)*
