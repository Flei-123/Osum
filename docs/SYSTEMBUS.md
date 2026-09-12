# Der Systembus von Osum

Runde SYSTEMBUS, Zweig `systembus`. Dieses Dokument beschreibt die
Systemrufe, das Typmodell und die Grenzen — und zwar so, wie sie
gemessen sind, nicht wie sie gedacht waren.

## Warum es ihn gibt

Die Wegkarte (`/root/osum-roadmap/ROADMAP.md`, A3) nennt den Systembus
den wichtigsten Einzelposten: „Zwischenablage, DnD, Benachrichtigungen,
Energie, Sperrbildschirm haengen daran. Baust du ihn nicht, baust du ihn
siebenmal.“ D1 bis D3 (Zwischenablage, Drag-and-Drop, Verlauf) und A11
(Benachrichtigungen) stehen dort ausdruecklich als „braucht A3“.

Er ist **im Kern** und nicht ein Dienst mit pid 1. Der Grund ist eine
Zahl: ein Ruf ueber einen Vermittlungsprozess kostet zwei
Kontextwechsel, ein Systemruf kostet keinen. Ein D-Bus-Nachbau in Ring 3
haette ausserdem genau dann nicht geantwortet, wenn er gebraucht wird —
beim Absturz, beim Herunterfahren, beim Ausloggen.

## Ein Befund vorweg

Der Auftrag dieser Runde sagte „grosse Daten ueber geteilten Speicher
(`share.fi`)“. **`kernel/share.fi` ist kein geteilter Speicher.** Es ist
die Internetfreigabe der Runde NETMON — Weiterleitung, NAT, DHCP-Server.
Geteilten Speicher gab es in diesem System nicht; er ist in dieser Runde
entstanden (`bus.seg_new` ueber `mem.frame_run`, `proc.map_frame`).

Ebenso vorweg: eine Zwischenablage gab es schon, und sie war zu wenig.
`wig.fi` haelt seit Runde WIG 4096 Oktette bei `CLIP_OFF` mit zwei
Systemrufen (`WIG_CLIPSET`, `WIG_CLIPGET`) — ohne Besitzer, ohne Typ,
ohne Verlauf, ohne Rechtefrage. Sie bleibt unangetastet und ist der
Rueckfallweg, wenn der Bus mit `nobus` abgeschaltet ist.

## Der Systemruf

**Eine** Nummer, **ein** Op-Wort:

    SYS_OSUM_BUS = 1960
    rax = 1960, rdi = op, rsi/rdx/r10/r8 = a1..a4

Warum nicht zweiundzwanzig Nummern: `sys.dispatch` ist eine Funktion mit
ueber hundert Zweigen, und Runde K13 hat gemessen, dass jeder weitere
Zweig Stapel kostet — 112 Oktette waren uebrig. Ein Zweig geht,
zweiundzwanzig nicht.

| op | Name | Argumente | Rueckgabe |
|----|------|-----------|-----------|
| 1 | `REG` | Name, n, Zugriff | Dienstnummer |
| 2 | `FIND` | Name, n | Dienstnummer |
| 3 | `SEND` | Dienst, Puffer, n, Segment | 0 |
| 4 | `RECV` | Puffer, max, Kopf | Oktette |
| 5 | `SUB` | Dienst | 0 |
| 6 | `PUB` | Dienst, Puffer, n | Zahl der Empfaenger |
| 7 | `SEGNEW` | Seiten | Segmentnummer |
| 8 | `SEGMAP` | Segment | Adresse in Ring 3 |
| 9 | `SEGDROP` | Segment | 0 |
| 10 | `CLIPSET` | Typen, Puffer, n, Segment | 0 |
| 11 | `CLIPGET` | zurueck, Puffer, max, Kopf | Oktette |
| 12 | `CLIPINFO` | zurueck, was | Zahl |
| 13 | `OFFER` | Typen | 0 |
| 14 | `FILL` | Puffer, n, Segment | 0 |
| 15 | `DRAGSET` | Typen, Puffer, n, Segment | 0 |
| 16 | `DRAGGET` | Puffer, max, Kopf | Oktette |
| 17 | `DRAGCLEAR` | — | 0 |
| 18 | `DRAGINFO` | was | Zahl |
| 19 | `NOTIPOST` | Dringlichkeit, Puffer, n | 0 |
| 20 | `NOTIGET` | zurueck, Puffer, max | Oktette |
| 21 | `NOTIINFO` | was, zurueck | Zahl |
| 22 | `STAT` | welcher | Zaehler |

`CLIPINFO was`: 0 = Typen, 1 = Laenge, 2 = Besitzer-pid, 3 = Zahl der
Verlaufsplaetze, sonst = Zustandsflags des obersten Eintrags.
`DRAGINFO was`: 0 = laeuft eine Ziehbewegung, 1 = Typen.
`NOTIINFO was`: 0 = wieviele, 1 = wieviele UNGELESEN, 2 = Laenge,
3 = Dringlichkeit.

Fehler kommen als negative Zahlen: `-1` voll, `-2` gibt es nicht,
`-3` **kein Recht**, `-4` ungueltig, `-5` leer, `-6` noch nicht da
(verzoegerte Uebergabe). Ohne Bus (`nobus`) antwortet der Ruf mit
`-ENODEV` (-19) — er tut nicht so, als waere alles in Ordnung.

## Dienste und Rechte

Ein Dienst ist ein Name von hoechstens 16 Oktetten, der einer Aufgabe
gehoert. Beim Anmelden nennt er, wer ihn rufen darf:

| Zugriff | Bedeutung |
|---------|-----------|
| 0 `A_ANY` | jeder |
| 1 `A_SAMEUID` | nur derselbe Benutzer (und root) |
| 2 `A_ROOT` | nur uid 0 |

**pid und uid einer Nachricht traegt der KERN ein**, aus der
Aufgabentafel (`sched.T_PID`, `sched.T_UID`), nicht der Absender. Das
ist der ganze Unterschied zwischen einem Bus mit Rechten und einer
Rohrleitung, und deshalb gibt es keinen Parameter dafuer.

Ein abgelehnter Ruf wird gezaehlt (`S_DENIED`) **und** geschrieben:

    bus: ABGELEHNT dienst=0 pid=5 uid=1000 regel=2

Ein stilles Nein ist ein Nein, das niemand nachweisen kann.

Veroeffentlichen (`PUB`) darf nur, wem der Dienst gehoert — sonst
koennte jeder Prozess im Namen des Energiedienstes „Akku leer“ rufen.
Jeder Abonnent wird beim Zustellen **einzeln** gegen die Rechte
geprueft: wer nicht rufen darf, darf auch nicht mithoeren.

Stirbt eine Aufgabe, raeumt `bus.forget_task` (aus `proc.reap`) ihre
Dienste, Abos, Nachrichten und Segmente ab. Ihr
Zwischenablage-Eintrag bleibt: Text, den man kopiert hat, verschwindet
nicht, weil das Programm zugemacht wurde. Das ist der Unterschied
zwischen X11 (verschwindet) und Windows (bleibt), und Windows hat hier
recht. Ein unerfuelltes **Angebot** verschwindet sehr wohl — das kann
niemand mehr einloesen.

## Das Typmodell: ein Modell, drei Nutzer

Das ist Entscheidung 2 der Wegkarte und der Grund, warum D2 dort sagt
„zusammen mit D1 entwerfen, nicht danach“. Zwischenablage, Ziehplatz und
Benachrichtigung benutzen **dieselben Felder**, dieselben Versaetze und
dieselben zwei Hilfsfunktionen (`put_item`, `item_get`):

    Folgenummer, Besitzer-pid, Besitzer-uid, Typmaske, Laenge,
    Segment (0 = am Ort), Flags, Dringlichkeit, 192 Oktette am Ort

Die Typmaske ist MIME-artig, ein Bit je Art, und mehrere gleichzeitig:

| Bit | Typ | entspricht |
|-----|-----|-----------|
| 1 | `T_TEXT` | text/plain |
| 2 | `T_PATH` | text/uri-list, ein Pfad |
| 4 | `T_HTML` | text/html |
| 8 | `T_IMAGE` | image/* |
| 16 | `T_FILES` | text/uri-list, mehrere |

Derselbe Inhalt kann Text **und** Pfad sein: der Explorer legt einen
Dateinamen ab, der Editor liest ihn als Text, und beide haben recht.
Genau dafuer ist es eine Maske und keine Zahl.

Bis 192 Oktette liegt der Inhalt am Ort. Darueber gehoert er in ein
**Segment**, und die Ablage traegt nur dessen Nummer.

## Verzoegerte Uebergabe

Ein Programm, das ein grosses Bild kopiert, will es nicht kopieren,
solange niemand einfuegt. Also:

1. `OFFER(typen)` meldet nur die Typen an, ohne Daten.
2. Der erste `CLIPGET` bekommt `-6` (E_AGAIN).
3. Der Besitzer liefert mit `FILL(puffer, n, segment)` nach.
4. Der naechste `CLIPGET` liefert.

Das ist ICCCM in drei Funktionen und ohne den Zeitstempel-Tanz.

## Segmente: ein Megabyte ohne ein kopiertes Oktett

`SEGNEW(seiten)` nimmt zusammenhaengende Rahmen aus `mem.frame_run`
(hoechstens 512 Seiten = 2 MiB). `SEGMAP(segment)` haengt sie in den
Adressraum des Aufrufers, in denselben Vorrat, den `big_map` benutzt
(`proc.BIG_FLOOR` .. `T_BIG`) — damit es genau **einen** Zaehler fuer
den grossen Bereich gibt und nicht zwei, die sich ueberholen.

Zwei Prozesse, die dasselbe Segment einblenden, sehen **dieselben
Rahmen**. Was gemessen wird, ist deshalb die Zeit fuer 256
Seitentabelleneintraege und das Lesen, nicht die fuer 1.048.576 kopierte
Oktette: **2683 us** fuer ein Megabyte (Abnahme: unter 5000).

Die Eintraege tragen `PAGE_SHARED` (Bit 9, von der Hardware dem
Betriebssystem ueberlassen). `proc.free_pt` und `proc.page_drop` geben
solche Rahmen **nicht** frei — sie gehoeren dem Bus. Ohne dieses Bit
haette der zweite Prozess nach dem Ende des ersten in laengst neu
vergebenen Speicher geschrieben, und zwar still.

## Der Verlauf

Zwanzig Plaetze, ein Ring. `CLIPGET(zurueck=0)` ist das Neueste, 1 das
davor. Win+V ist genau diese Zahl und sonst nichts. Auf der
Kommandozeile: `clip -l`.

## Die Ein-Kern-Regel

`STATUS-MERGE6.md` haelt zwei Fehler fest, die dieselbe Form hatten: ein
globaler statischer Puffer, den mehrere Kerne gleichzeitig benutzten
(`fs.inode_get`, `wig.glyph_into`). `kernel/bus.fi` hat **keinen**
`static mut`, und `sys.do_bus` kopiert in einen Puffer **auf dem Stapel
des jeweiligen Aufrufs**.

Die Tafel steht unter einer eigenen Sperrzelle in der Busseite selbst —
nicht unter einer der acht Sperren aus `kstate.LOCK_OFF`, deren Zaehler
in `tools/smp` und `tools/multicore` gemessen werden; eine neunte
Nutzerin haette `lock_total_spins` verschoben und damit eine Zusage von
zwei Runden gebrochen, ohne dass es jemand haette sehen muessen.

Die Sperre wird **nicht** ueber `copy_in`/`copy_out` gehalten: die
koennen einen Seitenfehler ausloesen, und ein Seitenfehler mit der
Bussperre in der Hand ist eine haengende Maschine. Erst holen, dann
sperren, dann eintragen.

## Der Speicher

`kdata` 0xAC000..0xB4000, acht Seiten. `KDATA_SIZE` waechst dafuer von
0xB0000 auf 0xB4000 — dieselbe Bewegung wie Merge 2 (512→640 KiB) und
Blech-Echt (640→704). `tools/kernel/memmap.py` fuehrt den Bereich und
meldet 0 Kollisionen.

    0x0000  Skalare      0x1500  128 Nachrichten zu 128
    0x0100  64 Dienste   0x5500  32 Posteingaenge zu 32
    0x1100  128 Abos     0x5900  64 Segmente zu 32
    0x6100  20 Verlaufsplaetze zu 256
    0x7500  Angebot + Ziehplatz
    0x7600  16 Benachrichtigungen zu 64

## Woerter auf der Kernel-Befehlszeile

| Wort | Wirkung |
|------|---------|
| `bus` | der Bus redet auf die serielle Leitung |
| `nobus` | **Gegenprobe**: der Bus wird nicht aufgesetzt, jeder Ruf gibt -ENODEV |
| `busbench` | die drei Messprogramme in Ring 3 laufen |
| `notidemo` | zwei Meldungen fuer die Leiste, vom Kern |
| `clipdemo` | reserviert |

## Von Ring 3 aus

* **Terminalprogramme** (`kernel/user/ulib.fi`): `clip_put`, `clip_take`,
  `clip_hist_take`, `clip_count`, `clip_typ`, `clip_owner`, `drag_take`,
  `drag_an`, `noti_post`, `noti_neu`, `noti_take`, `bus_da`.
* **Oberflaeche** (`kernel/user/wlibc.fi`, durchgereicht von `wlib.fi`):
  dieselben Namen, dazu `clip_put_typ`, `drag_put`, `bus_reg`,
  `bus_find`, `bus_send`, `bus_recv`, `bus_sub`, `bus_pub`.

`wlibc.clip_put`/`clip_take` **faellt auf die alte `wig`-Ablage zurueck**,
wenn der Bus nicht antwortet. Das ist Absicht: `nobus` muss ein System
ergeben, das weiter tut, was es seit Runde WIG tut.

Wer benutzt es heute:

* `kernel/user/sh.fi` — eingebauter Befehl `clip` (zeigen, setzen, `-l`
  fuer den Verlauf).
* `kernel/user/edit.fi` — STRG-K legt die ausgeschnittene Zeile auf den
  Bus, STRG-U fragt **zuerst den Kern** und nimmt von dort, wenn dort
  etwas anderes liegt als im eigenen Puffer. Ohne Dateinamen gestartet
  sieht der Editor auf dem Ziehplatz nach und oeffnet, was dort liegt.
* `kernel/user/explorer.fi` — beim Anfassen einer Zeile legt er den
  vollen Pfad auf den Ziehplatz **und** in die Zwischenablage, mit
  `T_PATH | T_TEXT`.
* `kernel/user/taskbar.fi` — ein viertes Statusfeld (`noti`) mit der
  Zahl der ungelesenen Meldungen. Null Meldungen heisst **kein Feld**
  und nicht die Ziffer 0 — dieselbe Regel, nach der Runde STARTKNOPF
  das Akkufeld eines Tischrechners entfernt hat.

## Was es nicht gibt

* Keine Aktivierung beim ersten Ruf (D-Bus' `--activatable`).
* Keine Introspektion, keine Signaturen, keine Methodenrueckgabe:
  `SEND` legt eine Nachricht in den Eingang, die Antwort ist eine zweite
  Nachricht in die andere Richtung.
* Keine Ziehgrafik unter dem Zeiger. Der Bus traegt den **Inhalt** einer
  Ziehbewegung, nicht das Bild dazu; das Ziel holt ihn.
* Kein Kopieren beim Schreiben und kein Wachsen von Segmenten: ein
  Segment hat seine Groesse, wenn es entsteht.
* Keine Blockierung: `RECV` auf einen leeren Eingang gibt sofort `-5`.
  Wer warten will, ruft `sched_yield` und fragt wieder — die drei
  Messprogramme tun genau das.
