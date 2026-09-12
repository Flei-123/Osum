# Runde WERKZEUGE — der Aufgabenverwalter und das Kontrollzentrum

Zweig `werkzeug`, abgezweigt von `hidweg` (1493451).

Osum hatte sieben Programme, die etwas über die laufende Maschine
wissen — `ps`, `top`, `kill`, `speicher`, `df`, `netmon`, `powermon` —
und alle sieben schreiben Zeilen in ein Terminal. Was fehlte, ist das
Fenster, das ein Mensch aufmacht, wenn etwas hängt: eine Liste, in der
man eine Zeile **anklickt**, und ein Knopf, der sie beendet.

Diese Runde baut es, und sie baut die drei Kennzahlen dazu, die der
Kernel dafür noch nicht hatte.

---

## 1. Was der Kernel vorher nicht wusste

Ein Aufgabenverwalter zeigt je Zeile einen Speicherwert, einen
Prozessoranteil und den Kern. Von den dreien gab es in diesem Kernel
**keinen**. Die bequeme Lösung wäre gewesen, sie in Ring 3 zu schätzen
(Bildgröße plus Stapel, Schläge geteilt durch Zeit) — und genau die Art
Zahl zeigt dieses Projekt nicht an. Also sind sie eingebaut worden:

| Kennzahl | wo | Anmerkung |
|---|---|---|
| `cpu.C_IDLETICKS` | `kernel/cpu.fi`, gezählt in `sched.on_tick` | Schläge, die die Leerlaufaufgabe eines Kerns bekommen hat. `C_TICKS` (die Gesamtzeit des Kerns) gab es seit Runde K5; ohne die zweite Zahl ist keine Auslastung ausrechenbar. Beide gehen in **derselben Unterbrechung** hoch, also gilt `idle <= ticks` immer — das ist die Gegenprobe, die der Testlauf misst. |
| `proc.space_pages` | `kernel/proc.fi` | Zählt die Rahmen eines Adressraums auf **demselben Weg**, den `free_space` beim Beenden läuft — dieselben Seitentabellen, dieselben Ausnahmen (die 2‑MiB‑Seite des Rahmenpuffers gehört der Grafikkarte und zählt nicht mit). Wer die eine ändert, sieht die andere daneben. |
| `SYS_PSTAT` Feld 8 (`P_CPU`) | `kernel/sys.fi` `do_pstat` | Der Kern, auf dem die Aufgabe zuletzt lief (`sched.cpu_of`). Eine Aufgabe, die noch nie lief, bekommt `MAX_CPUS` — kein Kern, und nicht die Null, die wie Kern 0 aussähe. |
| `SYS_PSTAT` Feld 9 (`P_PAGES`) | ebenda | Die Rahmen ihres Adressraums. |
| `SYS_CPUSTAT` (1840) | `kernel/sys.fi` `do_cpustat` | Eine Zahl je Aufruf, Bauart wie PSTAT/NETMON/PMON: `(kern, feld) -> Wert`, neun Felder. Lesen darf jeder; geschrieben wird nichts. |

**Warum `do_pstat` in `sys.fi` steht und nicht in `uio.fi`:** `proc.fi`
importiert `uio.fi` (Zeile 46 dort), also darf `uio.fi` nicht `proc.fi`
importieren — und der Speicher eines Prozesses steht in seinen
Seitentabellen, die `proc.fi` führt. Die **Nummern** stehen trotzdem in
`uio.fi`, weil sie zu dieser Tafel gehören. Die Alternative wäre gewesen,
den Seitentabellenlauf ein zweites Mal zu schreiben — zwei Stellen, die
dieselbe Speicherkarte kennen müssen, und die eine merkt nicht, wenn die
andere sich ändert.

**Angehängt, nicht eingeschoben:** die Feldnummern 0..7 stehen in
`/bin/ps`, `/bin/top` und in jedem Programm, das seit Runde K6 gegen
diese Tafel gebaut wurde.

---

## 2. `/bin/taskmgr` — der Aufgabenverwalter

`kernel/user/taskmgr.fi`, Ring 3, gebaut mit `wlib`/`wlibc`.

```
taskmgr [takt N] [runden N] [melde] [nohit]
```

**Die Liste.** Sechs Spalten — PID, Name, Zustand, CPU, Speicher, Kern —
sortierbar durch einen Klick in die Kopfzeile, derselbe Klick noch einmal
dreht die Richtung um. Die Pfeilspitze in der Kopfzeile sagt, wonach
sortiert ist; ohne sie wäre die Sortierung nur an der Reihenfolge zu
erraten.

**Die Auswahl merkt sich die Prozessnummer, nicht die Zeilennummer.**
Eine Zeilennummer zeigt nach dem nächsten Sortieren auf einen anderen
Prozess, und der Knopf daneben beendet ihn.

**Der Knopf steht rechts unten** — dieselbe Stelle, an der
`wlib.dlg_new` seit Runde K15 die Antwortknöpfe hinsetzt. Er fragt nach
(`wlib.dlg_ask`), und erst das „Ja" ruft `SYS_KILL` mit dem Code 137 —
**genau den Aufruf aus `/bin/kill`**.

**Der Kopf** trägt CPU gesamt **und je Kern**, Arbeitsspeicher, Platte,
Netzdurchsatz, Betriebszeit und die Zahl der Prozesse. Jede Zahl kommt
aus demselben Systemaufruf wie das Kommandozeilenwerkzeug daneben:

| im Fenster | Quelle | dasselbe wie |
|---|---|---|
| Prozessliste | `SYS_PSTAT` | `/bin/ps`, `/bin/top` |
| Name | `SYS_PMON` Art 2 | `/bin/powermon` |
| Speicher gesamt | `SYS_SYSINFO` `I_FRAMES_*` | `/bin/top` |
| Platte | `SYS_SYSINFO` `I_BLOCKS/I_BFREE/I_BSIZE` | `/bin/df` |
| Netz | `SYS_NETMON` `NM_SYSTX/NM_SYSRX` | `/bin/netmon` |
| Betriebszeit | `SYS_SYSINFO` `I_UPTIME` | `/bin/top` |
| Beenden | `SYS_KILL`, Code 137 | `/bin/kill` |

**Der Anteil bezieht sich auf die ganze Maschine.** Vier Kerne schlagen
viermal hundertmal in der Sekunde; ein Prozess, der einen Kern voll
belegt, bekommt hundert von vierhundert Schlägen und steht mit 25 % da.
So ergibt die Summe der Zeilen die Zahl im Kopf. `top` unter Linux zeigt
die andere Zahl und muss dafür erklären, warum acht Prozesse zusammen
800 % haben.

**Die Leerlaufaufgaben stehen mit in der Liste**, genau wie in `ps`. Sie
zu verstecken wäre die bequeme Anzeige — und die Summe der übrigen
Zeilen ergäbe dann die Zahl im Kopf nicht mehr.

**Kein eigener Adressraum, kein Speicherwert.** Die Bootaufgabe und die
Leerlaufaufgaben laufen im Adressraum des Kernels; dort steht ein Strich
und keine 0 KiB, die wie eine Messung aussähe.

### Der Verlaufsgraph

Sechzig Messpunkte, zwei Kurven, **selbst gezeichnet** mit `wlibc.rrect`,
`wlibc.rect` und `wlibc.hline` im selben Streifenverfahren, das
`wlib.flush_rect` benutzt (Streifen setzen, beschneiden, malen,
hinüberschieben). Farben ausschließlich über die semantischen Rollen
(`S_SURFACE_SUNKEN`, `S_BORDER`, `S_ACCENT`, `S_SUCCESS`).

Zwei Kurven, **drei** Unterschiede: die Prozessorkurve ist zwei
Bildpunkte dick und durchgezogen, die Speicherkurve einen dick und
gestrichelt, und daneben steht in Worten, welche welche ist. Farbe allein
taugt nicht — dieselbe Feststellung wie bei den Kacheln der
Schnelleinstellungen.

**Gemalt wird er nach JEDEM Durchlauf**, und das ist die Folge davon,
dass er kein Widget ist: `wlib.paint_all` malt den Hintergrund jedes
schmutzigen Rechtecks neu und überstreicht ihn dabei. Die erste Fassung
zog ihn nur nach, wenn `blits_done` sich geändert hatte — im Bild war die
Fläche trotzdem leer, **gemessen**: 83 368 von 83 520 Bildpunkten waren
die reine Fensterfarbe.

---

## 3. Das Kontrollzentrum

`kernel/user/qs.fi`, das Panel der Taskleiste (Runde NETVIEW, dritter
Nachtrag). Es hatte drei Kacheln, weil im August drei Dinge **wirklich**
da waren. Vier davon sind seither dazugekommen:

| dazu | weil |
|---|---|
| **Dunkelmodus** | Runde THEME/THEMESTORE hat die Schnittstelle gebaut, die es im August nicht gab. `wlibc.theme_set_mode` gilt sofort in jedem Fenster (gemeinsame Bank), `vorlage.mode_write` schreibt **eine Zeile** in `/etc/theme.conf`, damit es den Neustart überlebt. |
| **Energieprofil** | Runde K18 hat `osum_pwrget/pwrset`. Der Kern sagt selbst, ob er die Register wirklich lesen konnte (`PG_READY`) — steht dort eine Null, zeigt die Kachel einen Strich und tut nichts. |
| **Kacheln** | Runde TILING, `osum_tileget/tiledo`. |
| **Helligkeit** | Die Begründung von damals ist **nachgeprüft und hinfällig**: `pwr.rescale` skalierte den Rahmenpuffer an Ort und Stelle und verlor bei jedem Schritt Bits. Runde DISPLAY hat das ersetzt — `vmode.set_picture` baut eine Nachschlagetabelle, die beim Ausgeben angewandt wird. Fünfzig Schritte hintereinander kosten nichts. Deshalb steht dort jetzt ein Schieberegler. |

Dazu: der **Akkustand** als Zeile (`PG_BATPRESENT/PERCENT/STATE`; kein
Akku ist ein Wort und keine Null Prozent) und zwei **Verknüpfungen** —
Aufgabenverwaltung und Alle Einstellungen.

**Und Lautstärke steht weiter nicht da.** Nachgemessen in diesem Baum,
nicht angenommen: `grep -ril audio kernel/` findet zwei Treffer, und
beide sind Kommentare. Es gibt keinen Tontreiber, keinen Mischer und
keine Lautstärke, die man setzen könnte. Ein Regler dafür bewegte eine
Zahl, die keinen Lautsprecher erreicht. (Auf dem Zweig `hda` gibt es
einen Anfang; sobald der gemergt ist, ist die Kachel vier Zeilen.)

**Und WLAN steht nicht da**, aus demselben Grund: `kernel/netdev.fi`
sagt über jede gefundene Funkkarte selbst `wifi, needs 802.11 + fw`.
Es gibt Ethernet, und die Netz-Kachel schaltet genau das.

Die drei neuen Kachelzeichnungen (`assets/netview/tile-{dark,power,tile}.txt`)
sind gegen die drei vorhandenen **durchgerechnet**: alle fünfzehn
Paarungen liegen über einem Drittel unterschiedlicher Bildpunkte im
Schattenriss (schlechteste 34 %), die Schwelle von
`tools/netview/icons.py`. Der erste Entwurf (dünne Sichel, Blitz,
Rasterrahmen) fiel mit 17 bis 30 % durch.

---

## 4. Im Startmenü und in der Taskleiste

`assets/apps/taskmgr.osp/` — INFO, `start.txt` (zweiter Name auf
`/bin/taskmgr`, kein zweites Exemplar der Oktette), `symbol.txt` und
`data/`. Der Starter findet es über die Schlüsselwörter: niemand sucht
nach „Aufgabenverwaltung", wenn etwas hängt — gesucht wird nach
`taskmgr`, `monitor`, `top`, `ps`, `prozess`, `cpu`, `beenden`.

Das Fenster meldet sein Bündel mit `wlib.window_app(w, "taskmgr")` — der
**Bündelname** und nicht sein Pfad; die Taskleiste hängt `/apps/` davor
und `.osp/symbol` dahinter.

---

## 5. Was diese Runde am Werkzeug repariert hat

* `tools/themestore/click.py`: **zwölf Schritte in die Ecke statt sechs.**
  Sechs mal 120 sind 720 Bildpunkte — auf einem 1280 breiten Schirm
  landet der Zeiger nach dem Zurücksetzen bei x = 451 statt bei 0, und
  der nächste Klick geht um genau diese 451 daneben, ohne dass irgendwo
  ein Fehler steht.
* `tools/themestore/shotcheck.py`: die **Schnittmarke ist ein Argument**
  (`--cut=`). Sie stand als Zeichenkette aus `/bin/settings` fest im
  Code; jedes andere Programm bekam alle je gemalten Texte auf einmal
  vorgelegt, und eine Beschriftung, die sich jede Sekunde ändert, meldete
  damit 23 Überlappungen mit sich selbst.
* `tools/toolbench/fahren.py`: **eine Monitorverbindung für den ganzen
  Ablauf.** Der QEMU-Monitor nahm die zweite Verbindung nicht mehr an;
  ein verlorener Klick sieht im Gast genauso aus wie eine
  Trefferprüfung, die nicht greift.
* `kernel/kgui.fi`: `wigapp=` nimmt **Argumente** (mit Komma getrennt)
  und gilt **auch auf dem Schreibtisch**. Ohne das läuft ein Programm mit
  Fenster nur in seiner Grundeinstellung und ohne Taskleiste — und ohne
  einen zweiten Prozess, den man beenden könnte. Dabei ist ein alter
  Fehler mit aufgefallen: `n0 = wj` vergaß die abschließende Null des
  ersten Arguments.
* `kernel/kgui.fi`: ein abgelehnter Start **sagt jetzt warum**
  (`elf.say_reason`). `pid=0` allein ist keine Auskunft — es gibt
  neunzehn Gründe.
* `kernel/user/qs.fi`: die drei deutschen Oberflächentexte sind in den
  Katalog gewandert. `tools/i18n/scan.py` fällt damit von 38 auf 36.

---

## 6. Was gemessen ist und was noch fehlt

**Wirklich gemessen** (jede Zahl kommt aus einem Systemaufruf):

* CPU gesamt und je Kern, aus `C_TICKS`/`C_IDLETICKS` zweier Messungen
* Anteil je Prozess, aus `T_TICKS` zweier Messungen
* Speicher je Prozess (Rahmen des Adressraums) und gesamt (Rahmen frei /
  gesamt)
* Kern, auf dem ein Prozess zuletzt lief
* Zustand, Art, Vorrang, Elternprozess, Schläge je Prozess
* Programmname je Prozess
* Plattenbelegung, Netzdurchsatz (System), Betriebszeit
* Akkustand, Ladezustand, Energieprofil, Helligkeit

**Fehlt noch, ehrlich benannt:**

* **Lautstärke** — es gibt keinen Ton in diesem Baum.
* **Netzdurchsatz je Prozess** — `netmon` hat `NT_TXPAY/NT_RXPAY` je
  Aufgabe; im Fenster steht bisher nur die Summe.
* **Plattendurchsatz** — der Blockschicht fehlt der Zähler.
* **Fäden je Prozess** — `clone` gibt es, eine Fadenspalte nicht.
* **Ein Fenster stirbt nicht mit seinem Prozess.** Gemessen: nach dem
  Beenden ist der Prozess eine Leiche (Zustand 5, Anteil 0), sein
  Fenster bleibt aber auf dem Schirm stehen, bis der Elternprozess die
  Leiche abholt — und der Boot-Task tut das nie. Das ist eine Lücke des
  Fensterservers, nicht des Aufgabenverwalters, und sie gehört in eine
  eigene Runde (`sched.reap_all` existiert und wird von niemandem
  gerufen).
* **Unter KVM startet der vierte Prozess des Schreibtischs sporadisch
  nicht** (`elf: refused`). Unter TCG nicht reproduzierbar. Der Zweig
  `kvmfix` kennt diese Ecke.
