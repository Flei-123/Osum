# RUNDE SYNC — der Abgleich, den der Server nicht mitlesen kann

Zwei Geraete, ein Konto, dieselben Daten. Dazwischen ein Server, der
Bloecke ablegt und nichts davon versteht. Dazu der Tresor fuer
Geheimnisse. Das ist die Runde.

Der Satz, an dem alles haengt, steht in der Roadmap unter 6.1e und wird
hier woertlich genommen:

> ein Konto ist eine Bequemlichkeit, es ist nie eine Bedingung.

Wer kein Konto hat, merkt von dieser Runde nichts. Der Stick bleibt das
Mass, der Server ist der Sonderfall.

---

## 1. Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `lib/crypto/scrypt.fi` | 417 | PBKDF2-HMAC-SHA256, Salsa20/8, BlockMix, ROMix, scrypt (RFC 7914) |
| `lib/crypto/hkdf.fi` | 134 | HKDF-SHA256, Extract und Expand (RFC 5869) |
| `lib/sync/kette.fi` | 535 | die Schluesselkette, der versiegelte Block, der Name, der Wiederherstellungscode, die Huelle |
| `kernel/user/kbund.fi` | 595 | der Schluesselbund als Programmteil: Konto anlegen, oeffnen, KOPF schreiben/lesen |
| `kernel/user/sync.fi` | 1947 | `sync` — Speicher, Verzeichnis, Dreiwegabgleich, Konflikte, Einstellungen, Wurzel |
| `kernel/user/tresor.fi` | 509 | `tresor` — Geheimnisse, Sitzung mit Frist, Freigabe ueber Handles |
| `kernel/user/settings.fi` | +253 | die neunte Seite: Abgleich (nur lesend) |
| `locale/{de,en}/messages` | +22 je | 19 neue Schluessel, kein Satz im Programm |
| `tools/sync/oracle.fi` | 355 | das gehostete Orakel — dieselbe Rechnung auf dem Wirt, damit sie messbar ist |
| `tools/sync/vectors.py` | 318 | die Bausteine gegen ihre Normen |
| `tools/sync/schnueffel.py` | 248 | der Server, der mitlesen will |
| `tools/sync/boese.py` | 118 | der Server, der luegt |
| `tools/sync/run.sh` | 1260 | der Testlauf (a)–(j), der volle Datentraeger, der voreingestellte Preis, die Messungen |
| `tools/sync/build.sh`, `lauf.sh`, `strfix.py`, `dbg.sh` | 234 | Handwerkszeug |
| `tools/sync/messdbg.sh` | 90 | die Messstrecke allein, mit stehenbleibendem Arbeitsordner |
| `tools/sync/tresorzeit.sh` | 84 | wie lange das Oeffnen des Tresors dauert, mit der Uhr des Systems |

Kommandozeile:

```
sync neu       <konto> <pass> <anbieter> <ziel> [N] [r]
sync zeigen    <konto>
sync code      <konto> <code>
sync abgleich  <konto> <baum> <pass>
sync konflikte <konto>
sync auf       <konto> <pass>

tresor neu   <konto> <t> <pass>
tresor auf   <konto> <t> <pass> <frist>
tresor zu    <t>
tresor legen <t> <name> <wert>
tresor gib   <t> <name>
tresor liste <t>
```

---

## 2. Die Kette

```
Passphrase --scrypt--> Einpackschluessel --oeffnet--> Huelle --> HAUPTSCHLUESSEL
HAUPTSCHLUESSEL --HKDF--> fuenf Unterschluessel
```

Der Hauptschluessel ist **zufaellig** und wird nicht aus der Passphrase
gerechnet. Er liegt zweimal eingepackt im Kopf des Speichers: einmal
unter dem Einpackschluessel der Passphrase, einmal unter dem
Wiederherstellungscode. Damit gibt es zwei gleichberechtigte Wege zu
denselben Daten, und eine Passphrasenaenderung kostet 48 Oktette statt
einer Neuverschluesselung.

Die fuenf Unterschluessel:

| # | Name | wofuer |
|---|---|---|
| 0 | `K_INHALT` | verschluesselt den Blockinhalt |
| 1 | `K_NAME` | bildet den Namen, den der Server sieht |
| 2 | `K_SIEGEL` | beglaubigt den Wurzelzeiger (Rueckschrittschutz) |
| 3 | `K_TRESOR` | die Geheimnisse, eigene Freigabe |
| 4 | `K_PRUEF` | kein Schluessel — der Erkennungswert im KOPF |

**Der Geraeteschluessel gehoert nicht dazu.** Ed25519 in `system/`
beweist, WELCHES Geraet spricht; die Passphrase oeffnet die DATEN. Wer
beides zusammenlegt, baut entweder ein System, in dem ein gestohlenes
Geraet die Daten aufmacht, oder eines, in dem ein neues Geraet nicht mehr
an die eigenen Daten kommt.

### Warum scrypt und nicht Argon2id

Argon2id ist heute die bessere Wahl und es gibt sie in diesem Baum
nicht. Argon2 braucht BLAKE2b; vorhanden ist BLAKE2**s**
(`lib/crypto/blake2s.fi`, 32-Bit-Wortbreite). Argon2id dafuer neu zu
schreiben hiesse: BLAKE2b schreiben, den langen Hash `H'` schreiben, die
Kompressionsfunktion `G` schreiben, das indexunabhaengige und das
indexabhaengige Adressieren schreiben — und das alles selbst gebaut, in
einer Runde, die schon vier eigene Kryptobausteine mitbringt. scrypt ist
speicherhart, es ist in RFC 7914 mit Testvektoren normiert, und es steht
auf SHA-256/HMAC, das dieser Baum seit Runde TRESOR gegen Pythons
`hashlib` misst. Der ehrliche Satz dazu: **scrypt ist die zweitbeste
Wahl, gewaehlt weil sie hier die pruefbare ist.**

Parameter: `N = 16384, r = 8, p = 1` — 16 MiB, rund eine Sekunde auf
echtem Blech. Der Testlauf faehrt mit `N = 256`, weil er unter QEMU
laeuft und ein Testlauf den Wirt nicht messen soll.

**Grenze dieses Kernels:** der Arbeitsspeicher fuer scrypt kommt aus der
`mmap`-Arena von Runde K16 (6 MiB). Damit gilt `N * 128 * r <= 6 MiB`,
bei `r = 8` also hoechstens `N = 4096`. Das ist eine Grenze DIESES
Kernels und keine von scrypt; die Voreinstellung 16384 laesst sich erst
setzen, wenn Ring 3 mehr Adressraum bekommt. Das gehoert genannt, nicht
verschwiegen.

---

## 3. Die Falle: Hashes verraten den Inhalt

Ein inhaltsadressierter Speicher nennt einen Block bei seinem Hash. In
dieser einfachen Form ist das ein Leck, und zwar das groesste der Runde:

> Der Server sieht `sha256(P)`. Wer eine Datei VERMUTET, rechnet ihren
> Hash aus und sucht ihn in der Liste. Er braucht kein Passwort, keinen
> Schluessel und keine Rechenzeit.

Das ist der bekannte Angriff gegen konvergente Verschluesselung
(*confirmation of a file*). Deshalb:

```
NAME = HMAC-SHA256(K_NAME, P)      und nicht      sha256(P)
```

Die naive Fassung (`block_name_naiv`) steht absichtlich daneben. Sie wird
von nichts benutzt ausser vom Testlauf — Abschnitt (c) fuehrt mit ihr den
Angriff vor und zeigt, dass er mit `block_name` nicht mehr geht.

**Der Preis, ehrlich:** zwei verschiedene Konten teilen sich keine
Bloecke mehr. Doppelspeicherung gibt es nur noch innerhalb EINES Kontos.
Das ist der Handel: der Server spart weniger Platz und weiss dafuer
nicht, was er speichert.

Der Block selbst:

```
kb    = HMAC-SHA256(K_INHALT, name)
nonce = HMAC-SHA256(K_INHALT, "nonce" || name)[0..24]
C||T  = XChaCha20-Poly1305(kb, nonce, AAD = name, P)
```

Schluessel und Nonce kommen aus dem Namen, obwohl "Nonce = Zufall" die
Regel ist. Der Grund steht im Quelltext und ist eine Bedingung, keine
Bequemlichkeit: der Name ist eine Funktion des Klartextes, also sind zwei
Bloecke mit demselben (Schluessel, Nonce) buchstaeblich dieselben
Oktette. Ein Zufalls-Nonce wuerde nichts hinzufuegen und die
Doppelspeicherung zerstoeren. **Die Bedingung: der Name darf nie von
etwas anderem als dem Klartext abhaengen.** Das AAD ist der Name — damit
ist ein Block an seinen Platz gebunden.

---

## 4. Was der Server trotzdem sieht

Der Server ist blind fuer den Inhalt. Er ist nicht blind.

**Er sieht:**

* **Wieviele Bloecke** es gibt. Bei 4096-Oktett-Bloecken heisst das: die
  Gesamtgroesse der Daten, auf 4 KiB genau.
* **Die Groesse jedes Blocks** — hier immer 4112 Oktette (4096 + 16
  Poly1305). Das Auffuellen ist billig und wird gemacht: jeder Block ist
  gleich gross, also verraet keine Groesse eine Dateilaenge. Was bleibt,
  ist die ANZAHL.
* **Wann** etwas geschrieben wurde. Jeder Abgleich ist ein Zeitstempel.
  Wer taeglich um 7 Uhr synchronisiert, sagt das dem Server.
* **Wieviel sich geaendert hat.** Ein Abgleich mit einem neuen Block ist
  eine kleine Aenderung, einer mit dreihundert ist ein Umzug.
* **Die Generation.** `ROOT` steht im Klartext (`osumwurzel1 <gen>
  <name> <mac>`) — der Zaehler und der Name des Wurzelblocks sind
  sichtbar. Verschluesselt waere er nicht pruefbar, ohne ihn zuerst zu
  entschluesseln; das ist ein bewusster Handel.
* **Die IP, die Uhrzeit, die Haeufigkeit, die Reihenfolge der Zugriffe.**
  Wer welche Bloecke in welcher Reihenfolge holt, sagt etwas darueber,
  welche Datei geoeffnet wurde. **Verkehrsanalyse bleibt moeglich, und
  diese Runde tut nichts dagegen.**
* **Dass es Sie sind.** Der Anbieter kennt das Konto; die Verschluesselung
  versteckt den Inhalt, nicht den Kunden.

**Er sieht nicht:**

* Einen einzigen Klartext, in keinem Block.
* Einen Dateinamen. Das Verzeichnis ist selbst nur ein Strom von Bloecken
  — auf dem Server gibt es GENAU EINE Art von Ding.
* Ob er eine bestimmte Datei hat, auch wenn er sie kennt (Abschnitt 3).

Der Satz, den diese Runde NICHT sagt, ist "sicher". Sie sagt: der Inhalt
ist weg, die Form ist da.

---

## 5. Der Abgleich

Inhaltsadressiert, nur fehlende Bloecke, wiederaufnehmbar. Drei Dateien
im Speicher: `PACK` (die Bloecke hintereinander), `INDEX` (Name →
Offset, Laenge), `ROOT` (die Wurzel mit Siegel). Der Anbieter braucht
nicht mehr zu koennen als: Block ablegen, Block holen, Liste, loeschen,
Kontingent. **Je duemmer der Server, desto weniger kann er verraten.**

### Wie eine Datei im Verzeichnis steht

Eine Zeile je Datei:

```
f <mode> <groesse> <namehex>,<namehex>,...   <pfad>     bis 10 Bloecke
f <mode> <groesse> K<kopfnamehex>            <pfad>     darueber
```

Bis zu 700 Oktetten Namen (10 Bloecke, 40960 Oktette Datei) stehen die
Namen **in** der Zeile. Darueber wird die Namensliste **selbst** zur
Kette — mit demselben Kopfblockformat, das auch das Verzeichnis benutzt.
Der Server sieht dadurch keine zweite Art von Ding: es sind wieder nur
Bloecke zu 4096. Eine Datei von 200000 Oktetten kostet so 49 Datenbloecke
plus 2 Bloecke fuer ihre Namensliste.

**Die Grenze, ehrlich genannt:** die Namensliste passt in 65536 Oktette,
das sind 1008 Bloecke = knapp 4 MiB je Datei. Darueber bricht der
Abgleich ab und nennt den Pfad. Er ueberspringt die Datei **nicht** —
siehe Abschnitt 8b, Fund (1).

Reihenfolge, und sie ist die ganze Absturzsicherheit: **erst alle
Bloecke, zuletzt die Wurzel.** Ein Block ohne Wurzel ist Muell, den
niemand findet; eine Wurzel ohne Bloecke waere ein kaputter Speicher. Die
Wurzel wird ueber `ROOT.T` geschrieben und dann umbenannt.

### Konflikte

**Dokumente: kein stiller Sieger.** Der Dreiwegvergleich braucht die
letzte Einigkeit (`<konto>/BASIS`). Stimmt die lokale Zeile mit der Basis
ueberein, hat nur die Gegenseite geaendert → holen. Stimmt die ferne
Zeile mit der Basis ueberein, hat nur diese Seite geaendert → hochladen.
Stimmt **keine** von beiden → beide Fassungen bleiben: die eigene unter
ihrem Namen, die fremde als `<pfad>.konflikt`, und der Pfad kommt nach
`<konto>/KONFLIKTE`. Die fremde Fassung bekommt auch im Verzeichnis
ihren eigenen Pfad, damit sie den Weg zum anderen Geraet ueberlebt.

*Warum so:* eine Datei ist ein Dokument, und zwei Fassungen eines
Dokuments sind zwei Fassungen. Ein Verfahren, das eine davon wegwirft,
wirft Arbeit weg — und der Mensch merkt es Wochen spaeter. Zwei Dateien
nebeneinander sind haesslich und ehrlich.

**Einstellungen: letzter Schreiber gewinnt, je Schluessel, mit Verlauf.**
`<baum>/EINST` ist eine Zeile je Schluessel (`<zeit> <schluessel>
<wert>`), gemischt wird pro Schluessel, ueberschriebene Werte gehen nach
`<konto>/VERLAUF`.

*Warum anders:* eine Einstellung ist kein Dokument. Zwei Fassungen von
"Hintergrundbild" sind nicht zwei Fassungen von etwas, das man
zusammenfuehren koennte — es ist eine Frage mit einer Antwort. Wer hier
`.konflikt`-Dateien anlegt, hat ein System, in dem das Aendern einer
Farbe eine Aufraeumarbeit ausloest. Der Verlauf ist der Preis dafuer,
dass "gewinnt" nicht "ist weg" heisst.

**Ein Fehler, den diese Runde selbst gemacht hat und der hier steht,
damit er nicht wiederkommt:** `EINST` ist eine Zeile im Verzeichnis
(sonst reist sie nie zum anderen Geraet) und wurde deshalb zunaechst
AUCH durch den Dreiwegvergleich geschickt. Das musste einen Konflikt
geben — die gemischte Fassung ist ja weder die eigene noch die fremde —
und jeder Abgleich mit einer geaenderten Einstellung hinterliess eine
`EINST.konflikt`. Jetzt gilt: die gemischte Fassung ist das Ergebnis, sie
geht hoch, und der Vergleich ueberspringt sie.

### Rueckschritt

Der wichtigste Angriff. Ein Server kann keine Bloecke faelschen, aber er
kann ALTE ausliefern und damit ein Geraet auf einen Stand von gestern
zurueckwerfen. Dagegen:

1. Die Wurzel traegt `HMAC(K_SIEGEL, gen || name)`. Ein Server, der auf
   einen anderen Block zeigt, kann das Siegel nicht mitrechnen.
2. Jedes Geraet merkt sich in `<konto>/ZAEHLER` die hoechste Generation,
   die es je gesehen hat. Eine Wurzel mit kleinerer Generation ist ein
   RUECKSCHRITT und wird abgelehnt — nicht "ignoriert", abgelehnt.

**Ein zweiter Fehler dieser Runde, gefunden von (e):** die Rettung ueber
`ROOT.T` (die vollstaendige Wurzel, falls waehrend des Schreibens der
Strom ausfiel) war eine schlichte Zuweisung. Gibt es kein `ROOT.T`,
liefert das Lesen "keine Wurzel da" — und aus *"die Wurzel ist
gefaelscht"* wurde *"der Speicher ist noch leer"*. Ein Server, der `ROOT`
nur kaputtmacht, haette damit erreicht, dass das Geraet den Speicher fuer
neu haelt. Auf einem leeren Geraet heisst das: alles weg. Jetzt darf
`ROOT.T` nur verbessern, nie verschlechtern.

---

## 6. Der Tresor

Geheimnisse (Passwoerter, Schluessel, Token — auch die aus Runde KONTO)
liegen unter `K_TRESOR`, mit **eigener Freigabe**: der Tresor geht NICHT
mit der Sitzung auf, sondern verlangt die Passphrase, und er schliesst
nach einer Frist wieder (`tresor auf <konto> <t> <pass> <frist>`).
`<tresor>/SITZUNG` haelt die Ablaufzeit und den versiegelten `K_TRESOR`;
`tresor zu` loescht sie.

Ein Programm bekommt ein Geheimnis ueber ein Handle mit Recht, nie als
Klartext im allgemeinen Dateisystem. Der Testlauf zeigt: ohne Sitzung
kein Geheimnis, ohne den Sitzungsschluessel in `/system` kein Geheimnis,
nach der Frist kein Geheimnis, und der Klartext steht in keiner Datei des
Tresors und in keinem Protokoll.

---

## 7. Die drei Anbieter

Ein Format, eine Verschluesselung, ein Verfahren. Je Anbieter nur ein
duenner Transport-Ruecken. Was ein Anbieter koennen muss — mehr nicht:

| Aufruf | was |
|---|---|
| `put(name, bytes)` | Block ablegen (unveraenderlich; derselbe Name = derselbe Inhalt) |
| `get(name) -> bytes` | Block holen |
| `list() -> [name, len]` | die Liste |
| `del(name)` | loeschen (fuer das Aufraeumen) |
| `quota() -> used, max` | Kontingent |

* **`eigen`** — ein Pfad. Stick, NAS, eigener Server. Fertig gebaut und
  im Testlauf gefahren. Ueber HTTPS gegen einen einfachen Blockspeicher
  ist dieselbe Schnittstelle mit einem anderen Ruecken.
* **`jarvis`**, **`xoffi`** — dieselben fuenf Aufrufe. Der KOPF nennt
  `anbieter` und `ziel`; alles darueber ist gleich.

Kein Anbieter erzwingt ein zweites Format. Wuerde einer es tun, waere das
zu melden statt hinzunehmen — es tut keiner.

### Die Uebergabe an Runde KONTO

Schmal, und absichtlich schmal. Die Datenschicht braucht von der
Anmeldung genau drei Dinge:

| was | woher | wie benutzt |
|---|---|---|
| **wer bin ich** | Konto-ID der Anmeldung | landet als `ziel`-Praefix, sonst nichts |
| **wohin gehoeren meine Daten** | Anbieter + Basisadresse | `anbieter` und `ziel` im KOPF |
| **welches Token** | Sitzungstoken | geht in den Transport-Ruecken, nie in die Kette |

Bis zum Zusammenfuehren wird gegen eine Attrappe gearbeitet: `sync neu
… eigen /store …` ist genau dieser Fall — ein Ziel ohne Anmeldung. **Es
wurde keine Anmeldung gebaut.** Das Token ist fuer die Verschluesselung
ohne Bedeutung; wer es hat, darf Bloecke holen und versteht sie trotzdem
nicht.

---

## 8. Was wir selbst gebaut haben und wo das gefaehrlich ist

Selbstgebaute Kryptographie ist ein Risiko. Deshalb steht hier, was aus
einer geprueften Quelle stammt und was nicht.

**NEU in dieser Runde, selbst geschrieben:**

| Baustein | gemessen gegen |
|---|---|
| PBKDF2-HMAC-SHA256 | Pythons `hashlib.pbkdf2_hmac`, 9 Faelle |
| Salsa20/8 Core | RFC 7914 Abschnitt 8 (der Vektor im Text) |
| scrypt | RFC 7914 §12, drei der vier Vektoren + `hashlib.scrypt` |
| HKDF-SHA256 | RFC 5869 A.1/A.2/A.3 + Zufallsfaelle gegen eine eigene Python-Umsetzung |
| die Kette (Bund, Name, Siegel) | libsodium ueber PyNaCl |
| der Wiederherstellungscode | hin und zurueck, und ERSCHOEPFEND gegen Tippfehler |

Der vierte scrypt-Vektor aus RFC 7914 (`N = 1048576`) braucht 1 GiB und
wird nicht gefahren. Das ist eine Luecke und sie steht hier.

**NICHT von dieser Runde, aber benutzt:**

* SHA-256 und HMAC — `kernel/user/sha.fi`, Runde TRESOR, gegen `hashlib`.
* XChaCha20-Poly1305 — `lib/crypto/chacha.fi`, RFC 8439, aus der
  Browser-/Tunnel-Runde, dort gegen die Normvektoren gemessen. Hier
  zusaetzlich gegen libsodium.

**Wo das gefaehrlich ist — die Punkte, an denen wir es nicht wissen:**

1. **Seitenkanaele.** ChaCha20 und Poly1305 sind von der Bauart her
   konstantzeitig (kein Tabellenzugriff, kein datenabhaengiger Sprung).
   scrypt ist es NICHT und soll es nicht sein — sein Speicherzugriff
   haengt vom Passwort ab, das ist der Sinn von ROMix. Ob unser
   `bund_gleich` konstantzeitig vergleicht, ist gelesen und **nicht
   gemessen**.
2. **Der Uebersetzer.** `bund_loeschen` ueberschreibt Schluessel mit
   Null. Ob `firnc` dieses Ueberschreiben wegoptimiert, weil danach
   niemand mehr liest, ist **nicht geprueft**. In C waere das die
   bekannte `memset_s`-Falle; hier ist es unbekannt, und unbekannt ist
   schlechter als bekannt-schlecht.
3. **Keine Signatur im Block.** Ein Block ist durch Namen und
   Poly1305-Siegel gebunden; WER ihn geschrieben hat, steht nicht darin.
   Fuer ein Konto mit einem Menschen und mehreren Geraeten reicht das —
   alle Geraete haben denselben Schluessel. Fuer ein GETEILTES Konto
   reicht es nicht. Das ist nicht gebaut.
4. **Die Passphrase steht auf der Befehlszeile.** `ps` sieht sie, die
   Shell merkt sie sich. `pw.fi` hat `read_pass` ohne Echo; die
   Befehlszeile bleibt der Weg fuer Skripte und den Testlauf. Dieselbe
   Grenze wie `bsec.fi` B3.
5. **Der Wiederherstellungscode ist selbst gebaut** (Crockford-Base32
   ohne I, L, O, U, plus zwei Oktett Pruefsumme). Kein Standard, keine
   Kompatibilitaet mit BIP-39. Warum nicht zwoelf Woerter: eine Wortliste
   hat 2048 Eintraege, laege ohne Allokator als festes Feld in jedem
   Programm (~12 KiB) und bringt ein Sprachproblem mit.
6. **Kein Rechenaufwand gegen Verkehrsanalyse.** Siehe Abschnitt 4.

---

## 8b. Vier Funde, die erst die Tests gebracht haben

Keiner der drei ist ein Schoenheitsfehler. Sie stehen hier vollstaendig,
weil ein Bericht, der nur das Gelungene nennt, nichts wert ist.

### (1) Die stille Luecke: Dateien ueber 40960 Oktetten fielen aus dem Abgleich

`datei_zeile` sammelte die Namen der Bloecke einer Datei in einem Feld von
700 Oktetten auf dem Stapel. Ein Name ist 64 Zeichen plus Komma, also
passten **zehn** hinein — 40960 Oktette Datei. Alles darueber liess
`datei_zeile` mit `false` scheitern, und der Aufrufer in `baum_gehen`
machte mit `continue` weiter.

Die Folge: eine Datei von 51200 Oktetten war auf dem zweiten Geraet
**nicht da**, und der Lauf meldete `fertig`. Fuer ein Abgleichprogramm
ist das der schlimmste denkbare Ausgang — schlimmer als ein Absturz, weil
niemand etwas merkt.

Kein Test hat das gesehen, weil die groesste Pruefdatei der Runde 9000
Oktette hatte. Aufgefallen ist es an einer **Messzahl, die nicht stimmen
konnte**: der volle Abgleich ueber 1 MiB in 20 Dateien meldete 201
Bloecke statt 260, und der gerechnete Mehraufwand der Verschluesselung kam
mit **minus 16,9 %** heraus. Ein Verfahren, das beim Verschluesseln Platz
spart, gibt es nicht; die Zusage `der Speicher ist groesser als der
Klartext` fiel, und dahinter lag der Fehler. 201 = 20 x 10 + 1.

Behoben mit der **K-Form**: passt die Namensliste nicht in eine
Verzeichniszeile (ab 700 Oktetten Namen, also ab 11 Bloecken), wird sie
selbst zur Kette — mit *demselben* Kopfblockformat, das das Verzeichnis
benutzt. In der Zeile steht dann nur `K<namehex>`. Der Server sieht
dadurch **keine zweite Art von Ding**: es sind wieder nur Bloecke zu 4096.
Die neue Grenze liegt bei 65536 Oktetten Namensliste, also 1008 Bloecken
= knapp 4 MiB je Datei — und sie ist **laut**: darueber bricht der
Abgleich ab und nennt den Pfad. Kein `continue` mehr.

Gegenprobe (j4): die alte Fassung zurueckgebaut, dann faellt `gross.bin`
wieder still heraus und der Lauf meldet trotzdem `fertig`.

### (2) Nach einem Abbruch zeigte der Index auf fremde Oktette

`ix_laden` rechnete `pack_end` — die Stelle, an der der naechste Block in
PACK landet — aus den Eintraegen des INDEX. Das ist genau dann falsch,
wenn ein Lauf abgeschossen wurde: die Reihenfolge ist mit Absicht *erst
die Oktette in PACK, dann die Zeile in INDEX*, also liegen nach einem
SIGKILL Oktette da, auf die niemand zeigt. `pack_end` war damit **kleiner
als die Datei**. Der naechste Lauf schrieb mit `O_APPEND` ans wirkliche
Ende, trug aber die zu kleine Zahl als Offset ein — von da an zeigte jeder
neue Eintrag auf fremde Oktette.

Sichtbar wurde es in (f): der wiederaufgenommene Abgleich meldete
`fertig`, und das dritte Geraet holte sich davon **null von zwoelf**
Dateien. Behoben: `pack_end` ist die wirkliche Groesse von PACK, wenn die
groesser ist. Der verwaiste Schwanz bleibt liegen — verschwendeter Platz,
und sonst nichts.

### (3) Der volle Datentraeger -- und was daran gut ausging

Der Messabschnitt meldete 245 Bloecke statt 302, einen INDEX, der auf dem
Wirt mit 0 Oktetten ankam, und einen Mehraufwand von **minus 16,9 %**.
Die erste Vermutung war ein weiterer Fehler im Programm. Es war das
Abbild: 3 MiB, zwoelf Programme darin, und die 1,25 MB Speicher passten
nicht mehr hinein. Die Messung mass die Groesse des Abbilds.

Das ist ein Messfehler und kein Programmfehler — aber er hat die Frage
aufgeworfen, die niemand gestellt hatte: **was tut der Abgleich, wenn der
eigene Datentraeger voll laeuft?** Gemessen (`tools/sync/messdbg.sh` mit
4400 Bloecken):

```
dateien: 10          von 20
bloecke: 151
generation: 0
sync: fehler 6
sync: bei:  /m3.bin
```

Kein `fertig`, ein Fehler mit **Nummer und Pfad**, und **keine Wurzel**:
Generation bleibt 0. Damit liegen im Speicher Oktette, auf die niemand
zeigt — verschwendeter Platz — und kein einziges Versprechen, das nicht
gedeckt ist. Genau so soll es sein, und genau so verhaelt es sich erst
seit Fund (1): vorher waere die Datei still uebersprungen worden.

Der Fall steht jetzt als eigener Abschnitt im Testlauf (`== 8b. der
eigene Datentraeger laeuft voll ==`), und die Messstrecke bekommt ein
Abbild von 16384 Bloecken.

### (4) `tab_x` zaehlte bis 8, alle anderen bis 12

In `wlib.fi` ging die Berechnung der Reiterlage bis 8, waehrend
`tab_summe`, der Mausklick und die Pfeiltasten bis 12 gehen. Solange es
acht Reiter gab, fiel das nicht auf. Die Seite dieser Runde ist der
neunte — und der neunte war noch der letzte Fall, der zufaellig richtig
herauskam. Beim zehnten haette das Programm die Lage eines Reiters falsch
gemeldet und ein Testlaeufer daneben geklickt, ohne dass irgendetwas rot
geworden waere. Auf 12 gesetzt.

---

## 9. Der Testlauf

`bash tools/sync/run.sh` — **89 erfuellt, 0 gescheitert** (Lauf vom
31.08.2026, 00:24–01:31, KVM).

| Abschnitt | was gemessen wird | Ergebnis |
|---|---|---|
| 1 | bauen: Kern, 12 Programme, das Orakel, zweite Stufe (firnc1) | gruen |
| 2 | die Bausteine gegen ihre Normen (RFC 7914, RFC 5869, libsodium) | gruen |
| 3 (a) | zwei Systeme, ein Konto: **fuenf Dateien Oktett fuer Oktett**, darunter eine von 200000 Oktetten | gruen |
| 4 (b) | der Server sieht nichts: `GEHEIMNIS-4711` in keinem Oktett, keinem Namen, keiner Wurzel | gruen |
| 5 (c) | der Wiedererkennungsangriff, mit und ohne HMAC | gruen |
| 6 (d) | falsche Passphrase, kein Teilklartext; der Wiederherstellungscode holt zurueck | gruen |
| 7 (e) | boesartiger Server: geaendert, alt (**Rueckschritt**), fremd, zu gross, luegende Wurzel, halbe Wurzel | gruen |
| 8 (f) | **30x SIGKILL** mitten im Abgleich, danach wiederaufgenommen; 12 von 12 Dateien heil | gruen |
| 8b | der eigene Datentraeger laeuft voll | gruen |
| 9 (g) | Konflikt: beide Fassungen sind da | gruen |
| 10 (h) | der Tresor: Frist, Recht, kein Klartext in einer Datei | gruen |
| 11 (i) | **ohne Konto** geht alles weiter, der Stick bleibt unveraendert | gruen |
| 12 (j) | vier absichtlich kaputte Fassungen | gruen |
| 12b | der voreingestellte Preis der Schluesselableitung, und die Grenze darueber | gruen |
| 13 | die Messungen | siehe unten |

**Was ausserhalb dieser Runde gruen geblieben ist**, gemessen und nicht
behauptet:

* `tools/server/build.sh` (GUI-loser Serverbau): Rueckgabe 0, Kern
  2443100 Oktette (gui=off), **60** Programme, Platte 10 MiB. Am
  Ausgangspunkt sind es **59** — und der Unterschied ist genau dieses
  Programm. Denn `sync` stand in der Programmliste des Servers schon
  vorher, nur gab es die Datei dazu nicht, und der Bau ist stillschweigend
  darueber hinweggegangen.

  **Der Name ist trotzdem eine Ansage, und sie steht hier:** auf einem
  Unix heisst `sync`, die Puffer auf die Platte zu schreiben. Auf diesem
  System heisst `/bin/sync` ab jetzt *abgleichen*. Das Leeren der Puffer
  gibt es weiter, aber als Systemruf (`SYS_SYNC`) und ohne eigenes
  Programm — es hat hier nie eines gegeben. Wer das anders haben will,
  muss umbenennen, bevor Skripte entstehen; danach ist es teuer.
* `tools/i18n/run.sh` (GUI-Bau, beide Sprachen, dazu `tools/wm/run.sh`
  und `tools/k15/run.sh`): **37 erfuellt, 10 gescheitert**. Zum
  Vergleich derselbe Lauf auf dem Ausgangspunkt dieses Zweiges
  (`mergeline2`, 7d487fb), auf demselben Wirt, in derselben Stunde:
  **36 erfuellt, 11 gescheitert**. Die gescheiterten Zusagen dieses
  Zweiges sind eine **echte Teilmenge** der gescheiterten des
  Ausgangspunktes — es gibt keine einzige, die nur hier faellt. Sie
  haengen an der Last des Wirtes (23 gleichzeitige QEMU-Prozesse
  anderer Testreihen); `tools/k15/run.sh` meldet hier 3 gescheiterte
  gegen 6 am Ausgangspunkt, `tools/wm/run.sh` 0 in beiden.
  **Kein Test wurde abgeschaltet.**

---

## 10. Die Messungen

Alle Zahlen aus dem Lauf vom 31.08.2026, QEMU mit KVM, auf einem Wirt,
der gleichzeitig andere Testreihen fuhr. Sie messen die Emulation mit.

### Durchsatz (1 MiB in 20 Dateien zu je 51200 Oktetten)

| Lauf | neue Bloecke | gesendet | Dauer | Durchsatz |
|---|---|---|---|---|
| erster, voller Abgleich | 302 von 302 | 1241824 Oktette | 228 s | 4,4 KiB/s |
| zweiter, nichts geaendert | **0** | 0 | 40 s | — |
| nach einer kleinen Aenderung | **3** | 12336 Oktette | 42 s | 23,9 KiB/s |

Die 302 Bloecke sind nachrechenbar: 260 Daten (20 Dateien zu je 13
Bloecken), 40 fuer die Namensketten (je Datei ein Block Text und ein
Kopfblock, siehe K-Form) und 2 fuer das Verzeichnis.

### Was die Verschluesselung kostet

| Posten | Wert |
|---|---|
| Klartext | 1028096 Oktette |
| Speicher (`PACK`) | 1254160 Oktette |
| Speicher (`INDEX`) | 23515 Oktette |
| **Mehraufwand** | **+24,3 %** |
| davon Siegel | 0,39 % je Block (16 von 4096) |

Der grosse Posten ist **nicht** die Verschluesselung, sondern das
Auffuellen: 51200 Oktette werden zu 13 Bloecken zu 4096, also 53248 —
und das ist gewollt, denn so sieht der Server die Groessen der Dateien
nicht (Abschnitt 4).

### Die Schluesselableitung (scrypt, r = 8, auf dem Wirt)

| N | Speicher | Zeit |
|---|---|---|
| 256 | 258 KiB | 20,5 ms |
| 1024 | 1026 KiB | 81,0 ms |
| 4096 | 4098 KiB | 310,2 ms |
| 16384 | 16386 KiB | 1239,5 ms |

### Und dieselbe Ableitung IM System

Der voreingestellte Preis ist **N = 4096, r = 8**, also 4 MiB. Gemessen
mit der Uhr des Systems (`date -u`), einmal im Testlauf (Abschnitt 12b)
und einmal ausfuehrlicher mit `tools/sync/tresorzeit.sh`:

| Schritt | im Testlauf | mit tresorzeit.sh |
|---|---|---|
| `sync neu` (Konto anlegen) | 470 ms | 510 ms |
| `tresor neu` | 440 ms | 480 ms |
| **`tresor auf` (den Tresor oeffnen)** | **440 ms** | **470 / 520 ms** |
| `tresor legen` | — | 100 ms |
| `tresor gib` | — | 110 ms |
| `tresor zu` | — | 40 ms |

**Die Antwort auf die Frage des Auftrags:** den Tresor zu oeffnen kostet
rund **eine halbe Sekunde**, und fast alles davon ist scrypt.

**Und die Grenze, ehrlich:** N = 16384 (16 MiB) geht auf diesem System
**nicht**. Der Arbeitsspeicher fuer scrypt kommt aus der grossen Arena
(Runde K16, 6 MiB); bei r = 8 ist bei N = 4096 Schluss. Gemessen: mit
N = 16384 endet `sync neu` mit `sync: fehler`, und danach geht der
Tresor nie auf. Im Kopf von `kbund.fi` stand N = 16384 als
Voreinstellung — das war falsch und ist berichtigt. **4 MiB sind
weniger, als man heute fuer eine Passphrase empfehlen wuerde** (ueblich
sind 16 MiB und mehr). Das ist eine Grenze dieses Kernels und keine
Entscheidung fuer Bequemlichkeit; wer sie heben will, muss dem Ring 3
mehr Adressraum geben, und das ist eine Speicherrunde und keine
Abgleichrunde.

### Der Blockindex bei 10 000 Dateien

| wo | Groesse |
|---|---|
| auf der Platte (`INDEX`, eine Zeile je Block) | 800000 Oktette = 781,2 KiB |
| im Arbeitsspeicher (32 Oktette Name + zwei Zahlen) | 468 KiB |

Gerechnet aus dem Format, dessen Zeilen oben gemessen wurden. Der Index
liegt heute **vollstaendig** im Speicher (`MAXBLK = 3000`); fuer 10 000
Dateien muesste er auf die Platte, und das ist noch nicht gebaut.

---

## 11. Kann man jetzt wirklich zwei Geraete abgleichen, ohne dass der Server mitliest?

**Ja — mit drei Einschraenkungen, und die stehen hier, nicht im
Kleingedruckten.**

Was wirklich nachgewiesen ist: zwei Systeme, ein Konto, und die Dateien
kommen Oktett fuer Oktett an (a). Der ganze Blockspeicher enthaelt den
bekannten Klartext nirgends — nicht im Inhalt, nicht in einem Namen,
nicht in der Wurzel (b). Der Wiedererkennungsangriff, an dem konvergente
Verschluesselung stirbt, geht mit dem blanken SHA-256 auf und mit dem
HMAC nicht mehr; beide Ergebnisse sind gemessen, nicht behauptet (c).
Ein boesartiger Server kommt mit geaenderten, alten, fremden und zu
grossen Bloecken nicht durch, und der Rueckschritt — der gefaehrlichste
Fall — wird erkannt (e). 30 Abbrueche mit SIGKILL hinterlassen keinen
halben Zustand, und der wiederaufgenommene Abgleich liefert alle zwoelf
Dateien heil (f). Ein Konflikt verliert nichts still (g). Und **ohne
Konto laeuft alles weiter** (i).

Die drei Einschraenkungen:

1. **Verkehrsanalyse bleibt.** Der Server sieht Anzahl, Zeitpunkte,
   Muster und IP. Was er sieht, steht vollstaendig in Abschnitt 4.
2. **Die Schluesselableitung ist schwaecher als ueblich**: 4 MiB statt
   16 MiB, weil dieser Kernel nicht mehr hergibt. Wer eine kurze
   Passphrase waehlt, ist damit schlechter geschuetzt, als die Zahl
   `scrypt` vermuten laesst.
3. **Selbstgebaute Kryptographie.** scrypt, PBKDF2, HKDF und der Bund
   sind in dieser Runde geschrieben worden. Sie stimmen gegen die
   Normvektoren — das schliesst Rechenfehler aus, nicht Seitenkanaele
   (Abschnitt 8).

Und ein Satz, der nicht aus dem Testlauf kommt, sondern aus dem Bauen:
**die Tests haben vier Dinge ans Licht gebracht, nach denen niemand
gesucht hat** (Abschnitt 8b),
und der schlimmste davon — Dateien ueber 40960 Oktetten fielen aus dem
Abgleich, waehrend der Lauf `fertig` meldete — war ueber die ganze Runde
hinweg unsichtbar, weil keine Pruefdatei gross genug war. Ein
Abgleichprogramm, das still etwas weglaesst, ist schlimmer als eines,
das abstuerzt. Dass es gefunden wurde, verdankt sich einer Messzahl, die
nicht stimmen konnte — nicht einem Test, der danach gesucht haette.
