# RUNDE HAENGER — die Ausgabe bricht mitten in einer Zeile ab

Justins Foto vom 04.09.2026, 10:35 (Abbild `3d1fb528`, Eintrag
"desktop only (English)"):

    OrientOS K10 WM 0123
    abcdefghijklm ABCDEFGHIJK +-*/
    taskbar: size w=3440 h=56 rc=0
    taskbar: strut edge=0 size=56 rc=0
    qs: symbols n=3
    qs: win id=

Die letzte Zeile hat keinen Wert. Im Lauf davor (`14b01f06`) stand dort
`qs: win id=9`.

## 1. Welche Zeile das ist

`kernel/user/qs.fi`, in `fn init(autohide: u64) -> bool`:

    383    w_id = wlibc.sys3w(wlibc.WM_INFO, h, wlibc.WI_ID, 0)
    384    say((&s_wid[0 as usize]) as u64)      <- "qs: win id="
    385    ulib.sayn(w_id)                       <- die Zahl
    386    ulib.nl()
    387    return true

**Die Zuweisung steht VOR der Ausgabe.** `WM_INFO` ist also bereits
zurueckgekehrt, als der Text gedruckt wurde. Justins erster Kandidat
("der Aufruf, der die Fenster-Kennung besorgt, kehrt nicht zurueck")
scheidet damit an dieser Stelle aus — der Wert lag schon in `w_id`.

Die drei uebrigen Kandidaten, der Reihe nach geprueft:

* **Endlosschleife beim Formatieren.** `ulib.sayn` -> `text.digits`
  (`lib/libc/text.fi:115`). Die Schleife laeuft `value = value / 10`
  bis null: hoechstens 20 Durchlaeufe fuer ein `u64`, Zielpuffer 24
  Oktette. Terminiert immer. **Scheidet aus.**
* **`write_all` dreht.** `lib/libc/io.fi:236` kehrt bei `r == 0`
  zurueck und dreht nicht. **Scheidet aus.**
* **Der Systemaufruf `SYS_WRITE` bleibt im Kern stehen.** Nicht
  ausgeschlossen — und das ist der Punkt, an dem diese Runde ansetzt.

## 2. In QEMU nicht nachstellbar — und das ist selbst ein Befund

Gemessen mit `/tmp/hw3/justin-blech.sh`: das **veroeffentlichte** Abbild
`3d1fb528`, ueber OVMF und Limine (nicht `-kernel`), 3440x1440, ZWEI
xHCI-Regler, der Boot-Stick als `usb-storage` an hc0, Tastatur und Maus
an hc1.

    qs: symbols n=3
    qs: win id=10
    taskbar: STEHT x=0 y=1384 w=3440 h=56

Die Reihenfolge ist bis zum Abbruchpunkt **Zeile fuer Zeile dieselbe wie
auf Justins Foto**; danach laeuft es weiter. Der Unterschied liegt also
nicht in der Aufstellung der Geraete, nicht in der Aufloesung und nicht
im Startweg, sondern im echten Blech: Firmware-Rahmenpuffer,
Zeitverhalten der Regler, echte Unterbrechungen.

## 3. Warum das ALLES erklaeren kann: `nosched`

Jeder Schreibtisch-Eintrag bootet mit `nosched`. In
`kernel/sched.fi:1256` steht:

    if kstate.get(state, kstate.PREEMPT) == 0 {
        atomic.lock_give(state, atomic.L_SCHED)
        return
    }

**Ohne Verdraengung nimmt niemand einem Systemaufruf den Prozessor weg.**
Bleibt ein Aufruf im Kern stehen, bekommt `kgui.wait_wm` — die
Schreibtischschleife — nie wieder den Prozessor. Damit stehen in
derselben Sekunde:

* `wm.poll` — keine Eingabe mehr
* `wm.compose` — kein neues Bild, der Zeiger bleibt, wo er war
* die Taskleiste — sie wird nie fertig gemalt
* `kopf_malen` — **keine Messtafel**

Vier Meldungen, eine Ursache. Der Zeiger steht, weil er VOR der Schleife
gemalt wurde; die Tafel fehlt, weil sie IN ihr gemalt wurde.

## 4. Was gebaut wurde

### 4.1 Die Messtafel haengt jetzt am Zeitgeber

Voriger Stand: `kopf_malen` wurde nur aus `wait_wm` gerufen. Steht die
Schleife, steht die Tafel — genau dann, wenn man sie braucht.

Neuer Weg, an Ring 3 und an der Hauptschleife vorbei:

    kernel/arch/x86_64/trap.fi   VEC_TIMER, vor sched.on_tick
      -> gfx.tafel_tick                (die Naht, gfx-aus.fi = leer)
        -> kgui.tafel_tick             (10 Hz, eigener fb.flush)

Die Zeilen werden mit `tafel_merken` abgelegt und von `tafel_streichen`
gemalt — von wem auch immer als naechstes drankommt, Schleife oder
Zeitgeber. Eine Wiedereintrittssperre (`tafel_drin`) verhindert, dass
sich beide ins Bild schreiben.

Der Ruf steht **vor** `sched.on_tick`, aus demselben Grund wie
`pmon.tick` darueber: `on_tick` endet in `schedule_locked` und wechselt
den Stapel; was dahinter steht, laeuft nicht beim Schlag.

Nur der Startprozessor malt (`cpu.here(state) == 0`).

### 4.2 Zeile 8: TAKT — die Zeile, die den Fall entscheidet

    8 TAKT   IRQ 4808 MAL 276 LOOP 123

* **IRQ** — Rufe aus dem Zeitgeber
* **MAL** — Anstriche der Tafel
* **LOOP** — Rufe aus der Schreibtischschleife

Ablesen:

| IRQ | LOOP | Bedeutung |
|-----|------|-----------|
| laeuft | laeuft | alles in Ordnung |
| **laeuft** | **steht** | Maschine lebt, **Hauptschleife haengt** (Systemaufruf/Ring 3) |
| steht | steht | Unterbrechungen aus, Rechner haengt |

Diese Unterscheidung war auf keinem Foto zu treffen.

**Gemessen** (3440x1440, Justins Kommandozeile, sein `root.img`):
`MAL 276` bei `LOOP 123`. **153 Anstriche kamen allein aus dem
Zeitgeber** — das ist der Nachweis, dass der Weg ohne die Schleife
funktioniert.

### 4.3 Nur im Dauerbetrieb

`tafel_tick` kehrt ohne `wmdauer` sofort zurueck. Ohne diese Bedingung
malte der Zeitgeber die Tafel auch in `tools/wm/run.sh`, zehnmal je
Sekunde und immer NACH `compose` — zwei Pruefungen fielen sofort ("die
Kopfzeile des Terminalfensters steht im Bild": 950 von 950
Tintenpunkten falsch). `wmdauer` steht auf jedem Schreibtisch-Eintrag
des Sticks und auf keinem Laeufer. Mit der Bedingung: **104 bestanden,
0 gefallen.**

### 4.4 qs sagt jetzt, wo es steht

    qs: state
    qs: info?
    qs: win id=10

* `qs: state` kommt nach den drei `win_state`-Aufrufen.
* `qs: info?` steht **vor** `WM_INFO`.
* `qs: win id=N` geht als **eine Zeile in EINEM Schreibvorgang**
  hinaus, Zeilenende eingebaut.

Damit trennt das naechste Foto sauber:

| Was zu sehen ist | Was es heisst |
|---|---|
| kein `qs: state` | haengt in einem `win_state` |
| `qs: state`, kein `qs: info?` | haengt zwischen den beiden |
| `qs: info?`, keine id-Zeile | **`WM_INFO` kehrt nicht zurueck** |
| id-Zeile wieder mittendrin abgeschnitten | **die KONSOLE schneidet** — anderer Fehler |

Der letzte Fall war bisher nicht von den anderen zu unterscheiden.

## 5. Justins Frage zur Reihenfolge

> `taskbar: strut` kommt VOR `qs: win id=`. Meldet die Taskleiste Erfolg
> fuer etwas, das noch gar nicht existiert?

**Nein, die Reihenfolge stimmt.** In `kernel/user/taskbar.fi:3015` steht
`apply()` (das `WM_SIZE` und `WM_STRUT` fuer das EIGENE Fenster der
Leiste, id=9) **vor** `qs.init(cf_autohide)`. Die Schnelleinstellungen
sind ein ZWEITES Fenster desselben Prozesses (id=10), das danach
angelegt wird. Die Leiste meldet Erfolg fuer ihr eigenes Fenster, nicht
fuer das der Schnelleinstellungen. In QEMU steht dieselbe Reihenfolge,
und dort laeuft alles durch.

## 6. Serielle Schnittstelle

Alle neun Tafelzeilen gehen weiterhin als `tafel: …` auf COM1.
Justin braucht dafuer einen 9-poligen `COM1`-Stiftleisten-Header auf dem
Mainboard, einen USB-TTL-Adapter (CP2102/CH340, **3,3 V**) und an einem
zweiten Rechner `picocom -b 115200 /dev/ttyUSB0`. Ohne Header: eine
PCIe-Serienkarte.

## 7. Was Justin als naechstes liefern muss

Ein Foto der ersten Bildschirmseite. Darauf steht dann:

* **Zeile 8 `TAKT`** — laeuft `IRQ`, waehrend `LOOP` steht, ist es der
  haengende Systemaufruf, und `nosched` ist der Verstaerker.
* **die letzte `qs:`-Marke** — sie nennt die Anweisung, an der es steht.
