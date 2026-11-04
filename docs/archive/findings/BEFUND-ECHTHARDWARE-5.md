# BEFUND ECHTHARDWARE-5

Grundlage: Justins Fotos vom 10.09.2026, 11:31-11:37, vom Abbild
`orientos-usb-20260910-44a5af3.img`. Diagnosetafel im Bild:
`osum 44a5af37 B11905 T8177 sh14`.

Jede Aussage hier hat eine Messung, eine Logzeile oder einen
Commit-Hash hinter sich. Was ich NICHT nachweisen konnte, steht als
solches da.

---

## 0. ZUERST DER PRUEFSTAND -- ohne ihn war nichts davon reproduzierbar

`tools/design/capture.sh`, der Laeufer der letzten vier Runden, baut
eine **andere Maschine als der Stick**. Drei Unterschiede, jeder
einzeln nachgewiesen:

| | capture.sh | der Stick |
|---|---|---|
| Befehlszeile | `wm desk wmhold ... nokbd` | `wm wig desk wmshell wmdauer tafel herz` |
| Programme | 11 | 58 |
| Shell im Terminalfenster | **nie** (kein `wmshell`) | ja |
| Tastatur | **aus** (`nokbd`) | an |
| Diagnosetafel | **nicht gebaut** | ja |

Damit **konnte** Befund B (leeres Terminal) im Nachbau gar nicht
auftreten -- dort stand nie eine Shell im Fenster. Befund A (Tippen)
ebenso wenig, und die Tafelzeilen aus G/H gab es nicht.

**Neu: `tools/design/eh5.sh`** faehrt die Befehlszeile des Sticks.
Erst damit erschienen dieselben Zahlen wie auf Justins Foto
(`sh5`, `PANEL id9`, `SAFETY`, `RING/VERL/KOAL`).

---

## 1. BEHOBEN UND BELEGT

### B -- Terminalfenster war leer

Zwei neue Zaehler im Fensterserver (`wm.term_outs` / `wm.term_puts_n`,
auf der Tafel Zeile 0 als `TO`/`TP`) trennen drei Faelle, die sonst
gleich aussehen: es kommt nichts an / es kommt an und wird nicht
gemalt / es wird gemalt und ueberdeckt.

**Gemessen: `TO 16, TP 16`** -- genau sechzehn Oktette kamen an und
alle sechzehn wurden gemalt. Sechzehn ist die Laenge von
`"sh: ready, osum\n"`. Danach kam **nichts mehr**.

Der Weg Shell → tty → Fenster war also in Ordnung. Die Shell hat
nur nichts mehr geschrieben, und der Grund stand in `sh.fi`:
`prompt()` lief **nach** `get_line()`. Eine Shell, auf die niemand
tippt, haengt in `get_line` fuer immer -- die Eingabeaufforderung
wurde also nie geschrieben. Auf der seriellen Leitung fiel das nie
auf, weil dort ein Skript eingespeist wird und jede Zeile sofort
zurueckkommt.

Jetzt steht sie **vor** dem Lesen, und die gelesene Zeile wird ins
Fenster zurueckgeschrieben (der Kern echot Tasten nicht ins Fenster).

**Nachher: `TO 86, TP 86`.** Tinte im Fenster 0,5 % → 2,21 %
(Aufforderung) → 3,43 % (nach `ls`). Und im Klartext, aus dem
Zellenraster des Fensters selbst:

    wm: termzeile 2 [sh: ready, osum]
    wm: termzeile 3 [osum$ host -c]
    wm: termzeile 4 [nameserver 10.0.2.3]

### D -- Groesse liess sich nur an der rechten Kante ziehen

Drei Ursachen uebereinander:

1. `on_mouse` nahm nur `am_rechts || am_unten` an.
2. Die Titelleistenpruefung `lokal_y < 0` stand **vor** der
   Kantenpruefung und fing die obere Kante immer ab.
3. `resize_win` rechnet die neue Groesse aus der **linken oberen
   Ecke** -- links und oben konnten damit prinzipiell nicht gehen.

Neu: Bitmaske `S_SZEDGE` (links/rechts/oben/unten), Anker
`S_SZAX`/`S_SZAY` auf der **gegenueberliegenden** Kante, Pruefung vor
der Titelleiste, Mindestgroesse **vor** dem Verschieben, Klemmung am
Schirmrand (ohne sie lief `x` ins Negative -- gemessen als
`x=18446744073709551608`, also -8).

**Belegt, alle acht Griffe:** `k=1` links, `k=2` rechts, `k=4` oben,
`k=8` unten, `k=5` Ecke links-oben, `k=10` Ecke rechts-unten.
Beim Ziehen an der Oberkante: Hoehe 380 → 460, waehrend `y` 388 → 308
wandert -- die Unterkante steht still, das Fenster springt nicht.

### F -- Taskmanager und Einstellungen gingen nicht auf

Die serielle Leitung sagte es woertlich: **`qs: settings pid=-22`**.
-22 ist `EINVAL` aus `sys.do_spawn`:

    if prog == 0 || (prog > 16 && prog != P_BUSB_SPAWN) {
        return neg(errno.E_INVAL)
    }

`SYS_SPAWN` (1000) startet ein **eingebautes** Programm und nimmt
dessen **Nummer** (hoechstens 16). `qs.fi` gab ihm einen **Zeiger**
auf `"/bin/taskmgr"` -- und ein Zeiger ist immer groesser als 16.
Derselbe Fehler war in `launcher.fi` schon in Runde BLECHKERN behoben
worden; dieses Panel war uebersehen worden. Jetzt `SYS_EXEC` (1001).

**Zweitens** lag `/bin/taskmgr` gar nicht im Abbild. Nachgewiesen mit
`python3 tools/osum/mkfs.py list` auf der Wurzelpartition des
ausgelieferten Sticks: 177 Inoden, kein `taskmgr`. Jetzt in `PROGS`.

**Belegt:** `qs: druck x=194 y=316` → `qs: settings pid=7`,
Fenster `id=12 752x524`, `taskmgr: graph ... n=59` -- er zeichnet.

### J -- Themenwechsel wirkte nicht auf offene Flaechen

Die Wurzel ist -- wie im Auftrag vermutet -- **eine einzige**:
`qs.fi` hat eine eigene Ereignisschleife und ruft `wlib.step()` nie.
`theme_watch()`, der Wecker, der zehnmal je Sekunde nachsieht und alle
Fenster schmutzig macht, sitzt genau dort. Die Leiste **pollte** das
Thema bereits -- sie behielt es nur fuer sich.

Neu: `qs.thema_neu()`, gerufen aus dem `theme_poll`-Zweig der Leiste.

**Gemessen**, mittlere Helligkeit des Kontrollzentrums im Bild
**unmittelbar** nach dem Klick, ohne Schliessen:
**239,5 → 65,0** und zurueck **239,5**. Kein Zwischenzustand.

### E -- Helligkeit und Lautstaerke

Der Regler liess sich die ganze Zeit ziehen; das Panel meldete bei
jedem Schritt einen neuen Wert. Nur kam jeder Aufruf mit demselben
Fehler zurueck: **`qs: hell auf =150 rc=-19`** (ENODEV).

-19 kommt aus der **ersten Zeile** von `sysgui.do_dispset`:
`if !vmode.ready(state)`. Und `vmode` wird nur bereit, wenn
`vmode_stage` die Karte untersucht -- was es ausdruecklich nur tut,
wenn das Wort **`disp`** auf der Befehlszeile steht. Es stand auf
keinem Menueeintrag des Sticks. Der ganze Bildschirmzweig
(Helligkeit, Kontrast, Gamma, Aufloesung) war abgeschaltet.

**Gegenprobe**, mittlere Bildhelligkeit ueber den ganzen Schirm,
derselbe Zug am selben Regler:

| | Ausgang | runter | hoch |
|---|---|---|---|
| ohne `disp` | 18,78 | 18,77 | 18,76 |
| mit `disp` | 16,83 | **13,44** | **28,18** |

`audio` fehlte aus demselben Grund (`aud: aus (kein Wort)`). Beide
Woerter stehen jetzt in Menue 1 und im englischen Zwilling.

**Ehrlich dazu:** die Helligkeit ist eine **LUT im Rahmenpuffer**,
keine Hintergrundbeleuchtung. Sie wirkt auf das Bild, nicht auf die
Lampe. Eine echte Backlight-Steuerung braucht ACPI und ist eine
eigene Runde. Der Regler ist damit kein Regler, der nichts tut --
aber er ist auch nicht das, was ein Notebook-Nutzer erwartet.

Der Lautstaerkeregler graut sich bei fehlender Karte selbst aus
(`T_DIM`) und nimmt keinen Zug an -- das war schon richtig.

### H -- die zwei roten Zeilen

**Zeile 23** (`SAFETY AWA 0 KS 55880 R3W 0 R3K 6 LG 6 Z8 19`):
Rot heisst hier **nicht**, dass etwas unsicher ist. `WA 0` und
`R3W 0` sind genau die zwei Zahlen, die null sein muessen, und sie
sind null. Rot wurde sie durch ihre dritte Bedingung: `zu_lang` --
"es gibt Tafelzeilen, die abgeschnitten wurden". `LG 6` sagt sechs
Stueck, `Z8 19...` nennt die schlimmste: **Zeile 8 mit 190 Zeichen**
auf einer Tafel, die 48 breit ist.

**Zeile 8 war die Ursache**, und die Ursache dort ist eine Zeile Code:

    var t8: [u8; 8] = "8 TICK  "

Acht Zeichen in einem Feld von acht Oktetten -- **kein
Nullabschluss**. `puls_text` kopiert bis zur Null und lief ueber das
Feldende hinaus in die Nachbarfelder:

    tafel: 8 TICK  8 TICK  8 TICK  ...   (vierundzwanzigmal)

Das ist ein Lesen ueber eine Feldgrenze, kein Schoenheitsfehler.

**Derselbe Fehler lag noch zwanzigmal in derselben Datei** --
darunter `t19 = "19 CLOCK"` und `t23 = "23 SAFETY  "`. Daher kamen
Justins kaputte Zeilen `19 CLOCKZZZZ RK RTC ...` und
`23 SAFETY .WA 0 ...`: das `ZZZZ` und der fuehrende Punkt waren das
jeweils naechste Feld im Speicher. Alle 21 haben jetzt ihren
Abschluss; fuenf weitere derselben Sorte ausserhalb der Tafel
(`procfs`, `edit`, `kcore`) ebenso.

Zeile 19 blieb danach als letzte mit 49 Zeichen bei 48 Plaetzen
uebrig -- Ueberschrift `19 CLOCK` → `19 UHR`, macht 48.

**Vorher / nachher:**

    vorher  tafel: 8 TICK  8 TICK  8 TICK ... (190 Zeichen)
            tafel: 19 CLOCKZZZZ RK RTC 11:32:06 K 13:32:05 Z 120
            tafel: 23 SAFETY  .WA 0 ... LG 3 Z8 190
    nachher tafel: 8 TICK  IRQ 3709 MAL 682 LOOP 301 PRE 1 HZ 100
            tafel: 19 UHR RTC 12:01:33 K 14:01:33 Z 120 D 10.09 U 0
            tafel: 23 SAFETY  WA 0 KS 46904 R3W 0 R3K 1 LG 0

**`LG 0`** -- keine abgeschnittene Zeile mehr, Zeile 23 ist gruen.

**Zeile 7** (`PANEL id9 y2080 MAL 2028 fl2 ZU 3 TK 396`): rot wegen
`TK 396` -- 396 Titelzeilen im Band der Tafel wurden beschnitten.
`ZU 3` heisst "der Prozess der Leiste schlaeft" und ist der
Normalfall. Das ist eine Beschriftungssache, kein Betriebsfehler --
**bleibt offen** und ist hier als solches benannt.

### G -- Ringpuffer

Unter Last gemessen (Drehbuch mit Ziehen, Groessenaendern, Tippen und
zwei Programmstarts): **`tafel: 4 RING 98 VERL 0 KOAL 0`**, und keine
einzige `wm: RINGVERLUST`-Zeile.

Justins `ISR ... VERL 43` gehoert **nicht** dazu: das sind
**Zeitgeberschlaege**, die ausfielen, weil die Unterbrechungen
gesperrt waren (`trap.ticks_lost`) -- eine voellig andere Groesse, die
nur dieselbe Abkuerzung trug. Sie heisst jetzt **`TVERL`**.

`KOAL` ist ausserdem **kein Fehler**, sondern eine Absicht: der Ring
fasst Mausbewegungen zusammen, statt sie zu verlieren. Justins
`KOAL 10283` heisst "zehntausend Bewegungen zusammengefasst", nicht
"zehntausend Kollisionen".

Neu ausserdem: `wm: RINGVERLUST i= id= typ= kind= an=` nennt bei einem
echten Verlust den Schuldigen. Ein Verlust heisst immer: der Ring
**eines** Fensters ist voll **und** es steht keine Bewegung darin, die
man opfern koennte -- also ein Fenster, das nicht abholt.

### I -- Netz (nur pruefen, nicht bauen)

Der Pruefstand hat jetzt `netz=ja` (QEMU-Benutzernetz, e1000) und baut
`fetch` mit (`kernel/app`, `--profile=app`) samt `/etc/ssl/roots.pem`.

| | Ergebnis |
|---|---|
| DHCP | `ack ip=10.0.2.15 lease=86400`, Tafel Zeile 22 `IP 10.0.2.15 DA`, `/etc/resolv.conf` geschrieben |
| DNS | `host -v example.com` → **172.66.147.243**, server 10.0.2.3, tries 1, **ms 11**, ttl 273 |
| HTTPS | `fetch https://example.com/` → roots 11, **verify OK**, suite **4865** (TLS 1.3), certs 4, depth 4, **HTTP/1.1 200 OK**, code 200, body 559 Oktette |

**Beides geht.** Browser und Jarvis-Bruecke haben ihre Grundlage.
Gebaut wurde nichts -- das war der Auftrag.

---

## 2. URSACHE BENANNT, WIRKUNG NICHT NACHWEISBAR

### C -- Zeichenartefakte beim Verschieben

**Im Nachbau nicht reproduzierbar.** Nach einem Zug ueber den halben
Schirm stehen in der freigewordenen Flaeche **0,06 %** helle Punkte --
genauso viele wie **innerhalb** des Fensters (0,08 %). Kein Rest.

Das ist kein Freispruch, sondern der Hinweis, wo es liegt: der
Unterschied zwischen QEMU und Justins Brett ist der
**Zwischenspeicher**. Seine Tafel Zeile 9 sagt `FB WC` --
write-combining.

Der Streifenbetrieb schiebt den Rahmenpuffer in 2-MiB-Scheiben durch
**ein** Fenster und haengt den Platz dabei um (`fb.slot_remap`:
Seitentafeleintrag schreiben, `cr3` neu laden). Stand in dem
Augenblick noch etwas im WC-Puffer der CPU, geht dieser Rest an
dieselbe **virtuelle** Adresse -- die jetzt auf einen **anderen**
Block des Bildspeichers zeigt. Bildpunkte einer Bildschirmzeile landen
in einer voellig anderen: genau das Kammmuster, und genau deshalb
ueber die halbe Breite. In QEMU gibt es keine WC-Semantik, deshalb hat
es dort nie jemand gesehen.

**Behoben:** `arch.barrier_write()` (`sfence`) **vor** jedem
Umhaengen, in `slot_remap` und in `unmap_slot`. Auf dem geraden Weg
kostet es nichts -- der Puffer ist dann ohnehin leer.

**Ob es reicht, sagt erst Justins naechster Lauf.** Die Ursache ist
benannt, die Stelle ist die einzige, an der die Reihenfolge ueberhaupt
zu retten ist -- aber ich habe es nicht auf seinem Blech gemessen.

### A -- Suchfenster im Dunkelmodus weiss und tot

**Im Nachbau nicht aufgetreten**, in keiner Reihenfolge, die ich
probiert habe: hell wie dunkel, beim Umschalten mit **offenem** Menue,
beim Neuaufmachen danach, und mit dem Stand des Sticks
(`mode=light` in `/etc/theme.conf`).

Gemessen: mittlere Helligkeit der Flaeche **45,0** (dunkel), Farben
`09090b`/`18181b`, und getippt wird jedes Mal --
`launcher: suche [t] → [te] → [ter] → [term] treffer=3`, Pfeiltaste
waehlt, Enter startet (`launcher: start /apps/terminal.osp/start
pid=7`), Escape schliesst.

**Was trotzdem eine echte Luecke ist und jetzt zu ist:** das Fenster
wird von der **Leiste** mit `WA_TOGGLE` sichtbar gemacht, ohne dass
der Starter davon erfaehrt -- er merkt es erst am Fokus. Bis zum
naechsten Anstrich steht der alte Inhalt mit den **alten Farben** auf
dem Schirm. Wer in der Zwischenzeit das Thema wechselt, hat genau ein
weisses Fenster im dunklen Schreibtisch. Ausserdem hatte das Suchfeld
beim Aufgehen nicht zwingend den Eingabefokus -- dann geht jede Taste
an das Bedienelement, das zuletzt dran war, und man tippt ins Leere.
Das ist Justins zweite Haelfte, und sie ist damit beantwortet, egal
woher der Zustand kam.

Beim Aufgehen also: `theme_now()` (sofort nachfragen statt auf den
250-ms-Takt zu warten), `set_focus` auf das Suchfeld, `dirty_all` +
`draw_all`. Gegenprobe: dieselben Zahlen wie vorher, kein Unterschied
im Bild, keine Regression.

---

## 3. WAS OFFEN BLEIBT

| ID | Punkt |
|---|---|
| C | ob das `sfence` die Streifen auf ECHTEM Blech wirklich beseitigt -- nur dort messbar |
| A | ob das weisse Suchfenster damit weg ist -- im Nachbau war es nie da |
| H | Zeile 7 `TK 396`: die Titelzeilen im Tafelband werden beschnitten (Beschriftung, kein Betriebsfehler) |
| E | echte Backlight-Steuerung (ACPI) statt LUT im Rahmenpuffer |
| WM | zwei Zeigerpruefungen in `tools/wm/run.sh` sind rot (`zeiger.fi`, Runde ECHTHARDWARE-4) -- gehoert zur VEKTOR-Runde, nicht angefasst |

---

## 4. WERKZEUGE DIESER RUNDE

* **`tools/design/eh5.sh`** -- die Maschine des Sticks: dessen
  Befehlszeile, dessen Programmliste, Tafel an, Tastatur an, Shell im
  Terminalfenster. `netz=ja` haengt eine e1000 mit Ausgang ins
  Internet dran und baut `fetch` samt Wurzelzertifikaten mit.
* **`wm.term_dump`** -- schreibt das **Zellenraster** des
  Terminalfensters auf die serielle Leitung. Ich habe zweimal
  versucht, aus Bildpunkten Buchstaben zu raten, und beide Male stand
  am Ende ein Muster, das man so oder so lesen kann. Jetzt sagt das
  Fenster selbst, was in ihm steht.
* **`drive.py ziehkante <id> <kante> <dx>,<dy>`** -- greift die Kante
  aus der **gemeldeten** Geometrie statt aus getippten Zahlen. Eine
  Greifzone ist acht Bildpunkte breit und wandert nach jedem Zug; mit
  festen Zahlen trifft der zweite Zug daneben. Hat mich zwei Laeufe
  gekostet, bevor es das gab.
* **`drive.py klicknah` / `ziehspurnah`** -- klicken und ziehen ohne
  den Umweg ueber die Bildschirmecke. `fahre` faehrt immer erst nach
  0,0; das Kontrollzentrum schliesst sich dabei voellig zu Recht
  (`qs: closed by outside`), und es sah aus, als taeten die Regler
  nichts.
* **`qs: zeile tm y= h=` / `qs: zeile set y= h=`** -- das
  Kontrollzentrum meldet seine zwei Knopfzeilen selbst.
  `qs: text ... y=` ist die **Grundlinie der Schrift** und nicht das
  Feld; ein Klick darauf geht daneben. Mir in dieser Runde zweimal
  passiert.
* **`drive.py`** kennt jetzt `:` und die uebrigen URL-Zeichen
  (US-Belegung). Ohne sie fiel aus `https://example.com/` still
  `https//example.com/`, was `fetch` zu Recht ablehnte und wie ein
  Netzfehler aussah.
