# Nachtrag zur Runde TUNNEL — alles optional, nichts vorinstalliert

Justins Vorgabe: VPN, Proxy und die Tor-Anbindung sollen **nicht**
standardmäßig installiert sein. Der Benutzer installiert sie, wenn er
sie will, und entfernt sie wieder.

Dieser Nachtrag setzt das um und misst es. Wie im Hauptteil gilt: jede
Zahl hier kommt aus einem Lauf, und was nicht funktioniert, steht mit
Grund da.

---

## 1. Der Schnitt: zwei Pakete, und warum genau dort

**`vpn`** — WireGuard, AmneziaWG, Schlüssel, Profile, Notaus-Bedienung.
**`proxy`** — SOCKS5, HTTP CONNECT, die Tor-Anbindung.
**Keine Abhängigkeit zwischen beiden.**

Das Kriterium für den Schnitt war nicht Geschmack, sondern eine Zahl:

> **Die beiden Pakete teilen sich keine einzige Zeile Code.**

Nachprüfbar in zwei Zeilen. `lib/wg/proto.fi` beginnt mit

```
import crypto.blake2s
import crypto.chacha
import crypto.x25519
```

und `lib/socks/socks5.fi` hat **überhaupt keine `import`-Zeile**. Das
ist kein Zufall, sondern der Unterschied der beiden Sachen: SOCKS5
verschlüsselt nichts. Es ist Rahmenwerk um eine Verbindung, die ein
anderer absichert — ein Protokoll aus Längenfeldern und Adresstypen.
WireGuard ist das Gegenteil: fast nur Kryptographie.

Daraus folgt der Rest von selbst:

* Wer Tor will, will kein WireGuard. Wer sein Büro-VPN will, will kein
  Tor. Die beiden werden **unabhängig voneinander installiert und
  entfernt**, weil sie unabhängige Gründe haben.
* Ein gemeinsames Paket würde jedem Benutzer die Angriffsfläche des
  anderen mitgeben. Wer nur einen Proxy braucht, hätte 203 424 Oktette
  ungeprüfte Kryptographie im System, für nichts.
* Ein `braucht=`-Eintrag zwischen ihnen wäre eine Abhängigkeit, die es
  technisch nicht gibt.

### Und warum AmneziaWG **kein** drittes Paket ist

Das war die Stelle, an der es hätte falsch laufen können. AmneziaWG
klingt nach einem zweiten Protokoll und ist keins: es ist **derselbe
Code** in `lib/wg/proto.fi` mit drei Schaltern (`H1`–`H4`, `S1`/`S2`,
`Jc`/`Jmin`/`Jmax`). Es gibt keine zweite Binärdatei und keine zweite
Zustandsmaschine. Ein eigenes Paket dafür wäre ein Paket für eine
Konfigurationszeile — eine Paketgrenze, die nichts trennt, kostet
Verwaltung und spart nichts.

---

## 2. Was im System bleibt, und was es kostet

Die Aufteilung folgt einer Regel: **im Kern bleibt nur, was in Ring 3
nicht funktionieren würde.**

| | wo | warum dort |
|---|---|---|
| Tunnel-Netzschnittstelle, Cryptokey Routing | **Kern** | sitzt zwischen `stack.net_output` und der Karte |
| **Notaus** | **Kern** | sitzt unter dem **einzigen** Aufruf von `virtio.tx_frame` im ganzen System — deshalb kann nichts daran vorbei. Ein Notaus in Ring 3 wäre keiner |
| WireGuard-Krypto und Protokoll | **Kern** | siehe unten — das ist die unangenehme Stelle |
| Profile, `.conf`-Import, Schlüsselerzeugung, Anzeige | **Paket** | ein Mensch bedient es; nichts davon braucht Ring 0 |
| SOCKS5, HTTP CONNECT | **Paket** | reine Ring-3-Angelegenheit, eine Verbindung wie jede andere |

### Die drei Kosten, einzeln gemessen

Justins Vorgabe lautet, der Kernelteil dürfe „ohne das Paket NICHTS
kosten — weder Speicher noch Rechenzeit". Das zerfällt in drei Kosten,
und sie verhalten sich **verschieden**. Alle drei aus
`tools/tunnel/kosten.sh`:

| Kosten | ohne eingerichteten Tunnel | mit laufendem Tunnel |
|---|---|---|
| **Arbeitsspeicher** | **0 Seiten** | 6 Seiten = 24 576 Oktette |
| **Rechenzeit** | ein Vergleich gegen Null je Rahmen | der Tunnel bei der Arbeit |
| **Abbildgröße** | **203 424 Oktette, immer** | dieselben |

**Speicher und Rechenzeit sind wirklich null**, und zwar konstruktiv,
nicht durch einen Schalter: `rx_hook`, `tx_hook` und `tick` prüfen als
erstes `ready()`, und `ready()` ist `dev(state) != 0`. Ohne `wgpriv=`
wird nie eine Geräteregion angelegt. Die Messung: derselbe Kern zweimal,
einmal mit und einmal ohne Tunnel auf der Kommandozeile, freie
Seitenrahmen **am Ende** des Laufs gezählt (beim Hochlauf gemessen wäre
die Antwort immer null, weil `configure` erst später läuft) — 129 038
gegen 129 032. Die zwölf Skalarworte auf der K2-Seite, 96 Oktette,
stehen in einer Seite, die es ohnehin gibt.

**Die Abbildgröße ist die eine Kosten, die sich zur Laufzeit nicht
wegdrücken lässt.** Osum hat keine nachladbaren Module; ein
Multiboot-Abbild ist ein Stück. Der Code liegt darin, ob ein Tunnel
läuft oder nicht. Dagegen hilft nur, ihn gar nicht erst
hineinzuübersetzen — und genau das gibt es jetzt:

```sh
./tools/build-kernel.sh osum.mb --ohne-tunnel
```

baut mit `kernel/wg-aus.fi` statt `kernel/wg.fi`: eine Datei, in der
jede Funktion „es gibt keinen Tunnel" sagt, in **derselben Form**, in
der `kernel/wg.fi` es sagt, wenn keiner eingerichtet wurde. Deshalb
braucht weder `kernel/inet.fi` noch `kernel/netsvc.fi` eine
Fallunterscheidung. Eine Auslieferung, die das Paket `vpn` nicht
anbietet, liefert einen Kern, in dem der Tunnel **nicht vorhanden** ist
— nicht einen, in dem er abgeschaltet ist. Nur das zweite kostet
wirklich nichts.

Der Notaus fällt dabei mit weg, und das ist richtig: er schützt Verkehr,
der durch einen Tunnel soll, den es dann nicht gibt.

### Eine Falle, die diese Messung einmal verdoppelt hat

Der erste Wert für die Abbildgröße war **96 856 Oktette** und war
falsch. Firn legt an **jeder Stelle, an der es bei Überlauf anhält**,
den Dateipfad als Text ins Abbild. Derselbe Kern, aus einem längeren
Verzeichnis übersetzt, ist deshalb größer — gemessen **2 097 188 gegen
2 248 844 Oktette, 151 656 Oktette Unterschied für nichts als den
Pfad**. Der erste Vergleich hatte den einen Kern direkt und den anderen
aus `/tmp` gebaut. `tools/build-kernel.sh` übersetzt seit diesem
Nachtrag **immer** aus einer Kopie, damit beide Seiten denselben Weg
gehen; `kosten.sh` führt die Gegenprobe bei jedem Lauf mit.

Die allgemeine Form des Fehlers: **eine Differenz zweier Zahlen ist nur
dann die gesuchte Größe, wenn sich wirklich nur eine Sache
unterschieden hat.**

### Die Tür zwischen Ring 3 und Ring 0

Vorher nahm `kernel/wg.fi` seine Einstellung **nur von der
Kommandozeile**. Damit lässt sich ein Testlauf steuern, aber kein
Programm, das ein Benutzer installiert. Dieser Nachtrag fügt zwei
Aufrufe hinzu — `SYS_OSUM_WGGET` (1950) und `SYS_OSUM_WGSET` (1951) —
nach dem Muster der `pwr`-Aufrufe aus Runde K18.

Zwei Entscheidungen darin:

* **Ein Zeiger auf einen Argumentblock** statt sechs Register. `allow`
  will Index, Adresse und Präfix; `awg` will zehn Zahlen. Feldpackerei
  hätte jeden Leser gezwungen, die Packung zu kennen.
* **`wgset` nur für euid 0, und es gibt keinen Getter für den privaten
  Schlüssel.** Er darf hinein und nie wieder heraus. `WG_PUBLIC` gibt
  den öffentlichen — der ist zum Weitergeben da.

---

## 3. Installieren, benutzen, entfernen — und was wirklich bleibt

`tools/tunnel/pakete.sh`, **18 Prüfungen, 0 fehlgeschlagen**. Der Lauf
baut beide Pakete mit dem Werkzeug des Wirts (`pkg/opk.py` aus dem
OrientOS-Repo, dasselbe Format, das `kernel/user/opk.fi` auf dem Gerät
liest), installiert sie, **benutzt** sie und entfernt sie wieder.

```
  OK    kernel/user/vpn.fi   -> 41448 Oktette Ring 3
  OK    kernel/user/proxy.fi -> 45496 Oktette Ring 3
  OK    vpn-1.0.0.opk gebaut, 41724 Oktette
  OK    proxy-1.0.0.opk gebaut, 45773 Oktette
  OK    zweimal gebaut, Oktett fuer Oktett dasselbe Paket
  --    Baum vor der Installation: 48 Eintraege
  OK    vpn installiert
  OK    proxy installiert
  --    Baum mit beiden Paketen: 69 Eintraege (+21)
  OK    benutzt: /etc/proxy.conf geschrieben
  OK    vpn entfernt (--behalte-daten)
  OK    proxy entfernt (--behalte-daten)
  OK    opk aufraeumen: die Store-Eintraege sind eingesammelt
  OK    SPURLOS: 33 Eintraege verglichen (Pfad, Art, Groesse, SHA-256),
        kein Unterschied
  OK    das Paket 'bleibt' ist Oktett fuer Oktett unberuehrt
  OK    mit --behalte-daten haben Schluessel und Profile das Entfernen ueberlebt
```

**33 Einträge verglichen** — Pfad, Art, Größe und SHA-256 des Inhalts,
über `/apps`, `/store` und `/etc`, also jeden Ort, an dem ein Paket
etwas ablegen könnte. Kein Unterschied.

Drei Dinge, die dieser Lauf absichtlich anders macht als der naive:

1. **Es wird benutzt, nicht nur installiert.** `proxy` schreibt
   `/etc/proxy.conf` — eine Datei *außerhalb* des Pakets, und damit
   genau die Art Rest, die ein Entfernen übersehen könnte.
2. **Ein drittes Paket bleibt die ganze Zeit installiert.** Damit misst
   der Lauf nicht nur „hinterher ist es wie vorher", sondern auch „das
   Entfernen des einen hat das andere nicht angefasst" — der Fall, in
   dem eine Paketverwaltung wirklich Schaden anrichtet.
3. **`/system/generations` wird nicht als Rest gezählt.** Das ist das
   Gedächtnis, aus dem `opk zurück` springt. Zu verlangen, dass es
   verschwindet, hieße zu verlangen, dass das System vergisst, was es
   getan hat.

### Zwei Dinge, die dieser Lauf über `opk` herausgefunden hat

**`/apps` ist abgeleiteter Zustand.** Ein Verzeichnis, das dort von Hand
liegt und zu keinem Paket gehört, ist beim nächsten `opk`-Aufruf weg —
`opk` baut `/apps` bei jedem Aufruf aus dem PLAN der laufenden
Generation neu. Das steht so in PAKETE.md und ist kein Fehler, aber ein
Testbaum, der es nicht weiß, misst es als Rest. (Der erste Lauf hier tat
genau das.)

**`opk aufräumen` ist ein eigener Aufruf.** `entfernen` nimmt das Paket
aus dem Plan; der Store-Eintrag bleibt, solange irgendeine Generation
ihn nennt — sonst wäre `opk zurück` eine Lüge. Spurlos wird es erst,
wenn auch die alten Generationen eingesammelt sind.

---

## 4. Die Schlüssel — hier stimmt die Annahme des Auftrags nicht

Justins Vorgabe lautete:

> „private Schlüssel und Profildateien liegen unter `/users/<name>/config`
> bzw. `state` und werden beim Deinstallieren **nicht automatisch**
> mitgelöscht — frag den Benutzer ausdrücklich [...]"

**Das ist heute nicht so.** `pkg/opk.py` löscht `config/<paket>`,
`state/<paket>` und `cache/<paket>` beim Entfernen **standardmäßig
mit**; `--behalte-daten` ist der Schalter, der sie stehen lässt. Der
Lauf beweist es auf einer Kopie des Baums, damit die Gefahr eine Zahl
hat und keine Vermutung ist:

```
  OK    GEGENPROBE: opk entfernen OHNE --behalte-daten
        loescht die privaten Schluessel mit
```

Die Datei `users/justin/config/vpn/daheim.conf` ist danach weg.

Das ist in `pkg/opk.py` **begründet** und kein Versehen: Nutzerdaten
sind kein Teil einer Generation, weil ein Rücksprung auf gestern die
Dokumente von heute nicht wegnehmen darf. Die Kehrseite steht dort auch:
ein `entfernen` wirft sie wirklich weg, und ein späteres `zurück` bringt
sie **nicht** wieder.

**Für ein Paket, das Schlüssel hält, ist diese Voreinstellung falsch
herum.** Ein gelöschtes Dokument liegt im Zweifel noch woanders; ein
gelöschter privater Schlüssel ist weg, und mit ihm der Zugang. Der
Unterschied ist nicht graduell.

Was dieser Nachtrag deshalb tut:

* Der Läufer benutzt **immer** `--behalte-daten` und prüft beide Wege.
* `vpn vergessen` ist der ausdrückliche Weg, Schlüssel loszuwerden — ein
  eigener Befehl, der fragt, statt ein Nebeneffekt des Entfernens.
* Der Preis steht im Läufer: **8 leere Paket-Töpfe** bleiben stehen
  (`config`/`state`/`cache` ohne Inhalt). Ein leeres Verzeichnis ist der
  Preis dafür, dass ein volles nicht aus Versehen verschwindet.

**Was dieser Nachtrag NICHT getan hat, und wofür er eine Entscheidung
braucht:** die Voreinstellung in `pkg/opk.py` umzudrehen. Das ist eine
bewusste Festlegung einer anderen Runde (INSTALL) in einem anderen
Repository, und sie still zu ändern wäre falsch. **Empfehlung:** entweder
die Voreinstellung global umdrehen (`--auch-daten` löscht, sonst
bleiben sie), oder ein Feld im Paketformat — etwa `daten=kostbar` —,
mit dem ein Paket sagt, dass seine Nutzerdaten nicht beiläufig gelöscht
werden dürfen. Die zweite Fassung ist die genauere: bei einem
Notizprogramm ist die heutige Voreinstellung richtig, bei einem
Schlüsselbund nicht.

---

## 5. Oberfläche ohne Paket: kein toter Knopf

Die Regel, dieselbe wie bei der Lautstärke-Kachel, die es nicht gibt:
**kein Knopf, der nichts tut.**

Es gibt drei Zustände und sie sind **unterscheidbar**, nicht geraten:

| Zustand | woran man ihn erkennt | was die Oberfläche zeigt |
|---|---|---|
| Kern ohne Tunnel | `wgget(WG_READY)` → `-ENODEV` | die Seite erscheint **gar nicht** |
| Kern mit Tunnel, Paket fehlt | `WG_READY` → 0/1, `/apps/vpn.prog` fehlt | „VPN ist nicht installiert" + Knopf **Installieren** |
| Paket da | beides vorhanden | die richtige Seite |

Der erste Zustand ist der wichtige: `-ENODEV` ist genau die Antwort, an
der ein Programm merkt, dass dieses System **ohne** Tunnel gebaut wurde.
Eine Einstellungsseite für etwas, das der Kern nicht kann, wäre nicht
nur ein toter Knopf, sondern eine Lüge über die Maschine.

Auf der Kommandozeile ist das schon so — `vpn` sagt auf einem Kern ohne
Tunnel:

```
vpn: kein Tunnel in diesem Kern (-ENODEV)
```

**Die grafische Seite ist nicht gebaut.** Sie war schon im Hauptteil
nicht gebaut (docs/TUNNEL.md, Abschnitt 9), und dieser Nachtrag hat sie
nicht nachgeholt — die Paketierung, der Syscall und die Messungen haben
die Runde gefüllt. Die Regel oben ist damit heute **eine Vorgabe für
die Runde, die sie baut, und kein Ergebnis.** Dass es keine toten Knöpfe
gibt, stimmt zurzeit nur, weil es keine Knöpfe gibt.

---

## 6. Zur Tor-Empfehlung

Justins Vorgabe stützt sie zusätzlich, und das gehört festgehalten: er
will **die Möglichkeit** solcher Tunnel, ohne dass sie aufgedrängt
werden. Genau das leistet der SOCKS5-Weg und ein eigener Tor-Nachbau
nicht.

* Die Anbindung ist **klein** — `lib/socks/socks5.fi`, 393 Zeilen, ohne
  eine einzige `import`-Zeile.
* Sie ist **optional** — ein Paket, das man installiert und entfernt,
  und ohne das im System nichts von ihr übrig ist.
* Sie ist **ehrlich** — sie verspricht keine Anonymität, sondern leitet
  eine Verbindung an einen Tor weiter, den andere schreiben und andere
  prüfen.

Ein halbfertiger eigener Tor-Nachbau wäre das Gegenteil: groß, nicht
abwählbar (er säße im System), und er würde Anonymität behaupten, die
er nicht halten kann. Ein Fehler darin stürzt nicht ab — er
deanonymisiert still. Die ausführliche Begründung steht in
docs/TUNNEL.md, Abschnitt 6.

Dazu die Grenze, die bleibt: **Osum kann keinen Tor-Dienst betreiben.**
Der Schalter nützt, wenn im Netz ein Tor läuft — auf dem Router, auf
einem anderen Rechner, auf einem Telefon — und sonst nicht. Das gehört
auf die Einstellungsseite und nicht in eine Fußnote.

---

## 7. Ein offener Punkt: `.prog` oder `.osp`

Der Auftrag nennt `/apps/<name>.osp/` und sagt, die Endung sei „gerade"
von `.prog` geändert worden. **Nachgesehen: das ist noch nicht so.** In
`origin/rename-en`, in `origin/install`, in `origin/main` und im
OrientOS-Repo heißt es überall `.prog`; `.osp` kommt in keinem
gepushten Zweig vor.

Dieser Nachtrag baut deshalb gegen den **wirklichen** Stand, `.prog` —
alles andere wäre gegen etwas gebaut, das es nicht gibt, und heute nicht
testbar. Die Endung steht in `kernel/user/appdir.fi` an einer Stelle;
wenn die Runde RENAME sie umdreht, dreht sie sich hier mit, weil weder
`vpn.fi` noch `proxy.fi` noch die Rezepte sie selbst schreiben — sie
steht nur in den Pfaden, die `opk` erzeugt.

---

## 8. Was gemessen ist, und was nicht

**Gemessen:**

* Abbild mit Tunnel 2 166 860, ohne 1 963 436 Oktette — **203 424
  Oktette (9,4 %)**, beide auf demselben Weg gebaut, mit Gegenprobe zur
  Pfadlängen-Falle.
* Arbeitsspeicher: **0 Seiten** ohne eingerichteten Tunnel, 6 Seiten
  (24 576 Oktette) mit.
* Beide Pakete bauen reproduzierbar: zweimal gebaut, **Oktett für
  Oktett dasselbe**.
* Installieren, benutzen, entfernen, aufräumen: **33 Einträge
  verglichen, kein Unterschied**.
* Ein drittes Paket bleibt dabei **Oktett für Oktett unberührt**.
* `opk entfernen` löscht ohne `--behalte-daten` die privaten Schlüssel —
  **auf einer Kopie nachgewiesen**.

**Nicht gemessen, und deshalb nicht behauptet:**

* **Die Pakete sind nie auf Osum selbst installiert worden**, nur mit
  `pkg/opk.py` auf dem Wirt in einen Baum. `kernel/user/opk.fi` (Runde
  INSTALL) liest dasselbe Format, aber dieser Nachtrag hat den Weg auf
  dem Gerät nicht durchlaufen — der Zweig `install` ist nicht gemergt
  und dieser Zweig hat ihn nicht.
* **Die neuen Aufrufe 1950/1951 sind nicht aus Ring 3 aufgerufen
  worden.** Sie übersetzen, sie sind verdrahtet, `kernel/user/vpn.fi`
  bindet dagegen — aber kein Lauf hat `vpn an <profil>` auf einer
  laufenden Maschine ausgeführt. Was der Hauptteil misst, ist der Weg
  über die Kommandozeile.
* **`vpn an <profil>` liest noch keine `.conf`-Datei.** Der Profilleser
  ist begonnen und wieder ausgebaut worden, statt ihn halb drin zu
  lassen; heute kann das Programm Zustand zeigen, den öffentlichen
  Schlüssel nennen, den Tunnel abschalten und den Notaus setzen.
* **Die grafische Oberfläche** — siehe Abschnitt 5.
* Und weiterhin: **die Kryptographie ist nicht auditiert**
  (docs/TUNNEL.md, Abschnitt 8).
