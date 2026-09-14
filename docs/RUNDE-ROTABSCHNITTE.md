# Runde ROTABSCHNITTE — die 27 roten Abschnitte der Abnahme

*14.09.2026, Zweig `main`, aufgesetzt auf `a298db7` (der Stand nach dem
Zusammenführen von `baufehler`, `installer`, `anmeldung`, `hotplug` und
`energie`).*

Die Runde BAUFEHLER hat zum ersten Mal seit Wochen für **alle 74
Abschnitte** eine echte Zahl geliefert: 47 grün, 27 rot, 5225 grüne gegen
382 rote Zusagen. Diese Runde arbeitet die 27 roten ab.

---

## Das Ergebnis in einer Tabelle

| Abschnitt | vorher | nachher | Stand |
|---|---|---|---|
| `powermon` | 62 / 54 | **121 / 0** | grün |
| `k17` | 156 / 2 | **158 / 0** | grün |
| `osum` | 129 / 1 | **130 / 0** | grün |
| `userland` | 90 / 1 | **91 / 0** | grün |
| `praesenz` | 34 / 2 | **36 / 0** | grün |
| `server` | 21 / 2 | **23 / 0** | grün |
| `icons` | 24 / 1 | **grün** | grün |
| `hid` | 56 / 1 | **grün** | grün |
| `k15` | 179 / 74 | **216 / 36** | besser |
| `werkzeug` | 18 / 16 | **28 / 6** | besser |
| `umlaut` | 24 / 9 | **39 / 9** | besser |
| `systembus` | 33 / 2 | **34 / 1** | besser |

Acht Abschnitte sind ganz grün, vier deutlich besser. Die übrigen
fünfzehn (`blech`, `customres`, `display`, `glyphe`, `modul`, `netview`,
`paint`, `pci`, `softui`, `stick`, `theme`, `themestore`, `usbimg`,
`vielkern`, `wm`) sind in dieser Runde nicht angefasst worden.

**Nebenbei wurden die Läufe schneller**, weil auf Ereignisse statt auf
die Uhr gewartet wird: `osum` von 921 s auf 121 s, `userland` von 946 s
auf 143 s.

---

## Die fünf Ursachen

Die meisten roten Zusagen kamen **nicht** aus dem Kern. Sie kamen aus
Prüfern, die die falsche Frage stellten, und aus Umbenennungen, die zur
Hälfte durchgezogen wurden. Fünf Ursachen erklären fast alles.

### 1. Ein weggeworfenes Register — 54 rote Zusagen auf einmal

`powermon` meldete 51-mal *„the line `powermon: rate=` is missing
entirely"* und *„one of the two sides did not report at all
(kernel='7700' ring3='')"*. Der Kern meldete, das Programm nicht.

Mit einem behaltenen Mitschnitt war zu sehen, dass `powermon raw` die
**Tabelle** druckt und nicht die Rohzeilen — das Wort `raw` kam nie an.
Am gebauten ELF nachgemessen:

* Runde GRUNDLINIE hat `powermon.fi` von `profile kernel` auf
  `profile app` gezogen. Unter `app` bringt `firnc` **sein eigenes**
  `_start` mit (deshalb darf `crt.o` nicht dazugebunden werden), und das
  endet in `call main` — der Name steht fest in `lib/firnc1/codegen.fi`,
  `--defsym=USER_ENTRY` erreicht ihn nicht.
* `main` aber war die Attrappe mit dem Kommentar *„das `main`, das nie
  läuft"* — und die ruft `u_start(0)`. Die Null ist der Argumentblock.

Der Block liegt an einer festen Adresse: Runde K16 hat den Stapelzeiger
darauf gelegt (`kernel/elf.fi`, `T_USTACK = proc.ARGS_BASE`), und jede
`elf: start`-Zeile druckt sie als `ustack=0x4007f000`.

**Dieselbe Attrappe stand in neunzehn Programmen.** `kernel/user/installer.fi`
hatte den Fehler schon gefunden und ausdrücklich eine eigene Runde dafür
verlangt — das war diese. Die Adresse steht jetzt einmal in `ulib`
(`ARGS_BASE`); achtzehn Kopien wären achtzehn Stellen, die beim nächsten
Verschieben vergessen werden, und in `freunde.fi` hielt der Wächter von
`tools/presence/run.sh` das `0x4007F000` prompt für einen festen
**Farbwert**.

Beweis an einem zweiten, unabhängigen Abschnitt: `praesenz` meldete
*„die Leiste zeigt die vier Demo-Freunde: 0, erwartet 4"*. Die Liste
füllt der Schalter `--demo`. Danach: **4**, und der Abschnitt ist ganz
grün.

### 2. `/etc/uitrace` fehlte im Abbild

`taskbar.fi`, `qs.fi`, `launcher.fi` und `explorer.fi` melden ihre
Rechtecke und Zustände **nur**, wenn diese Datei auf der Platte liegt.
`qs.fi` sagt es im Kommentar selbst: *„die Prüfstände legen sie ohnehin
an"* — und drei von ihnen taten es nicht.

Ohne die Datei schweigen die Programme vollständig. Im Mitschnitt von
`systembus` stand keine einzige `taskbar:`-Zeile, nicht einmal das
`taskbar: ready ascent` des Starts. Damit konnte weder `Meldg` im
Mitschnitt stehen noch `klickauf tbbtn0` ein Rechteck finden.

Betroffen: `systembus`, `werkzeug`, `k15` (dort allein 26 Lesestellen).

### 3. Der Anzeigename ging nie durch den Katalog

Jede Bündel-INFO sagt dasselbe in ihrem Kopf:

> Der Anzeigename steht hier und nicht im Quelltext. Übersetzt wird er
> über den Katalog (`locale/*/messages`, Schlüssel `taskmgr.title`).

Übersetzt wurde er nirgends. In einem Lauf mit `lang=de` und 416
geladenen Schlüsseln meldete der Starter `name=[Task Manager]`, während
`locale/de/messages` seit langem `taskmgr.title = Aufgabenverwaltung`
sagt. `appdir.fi` kannte `msg` schlicht nicht.

`name_of` und `info_of` bauen den Schlüssel jetzt aus dem Bündelnamen
(`taskmgr.osp` → `taskmgr.title`) und fragen `msg.get`. Das ist
rückfallsicher ohne Sonderfall: `msg.get` gibt den **Schlüssel** zurück,
wenn es ihn nicht gibt — daran ist zu erkennen, dass nichts übersetzt
wurde, und dann bleibt der Text aus der INFO stehen. Ohne Katalog ändert
sich kein Oktett.

Die dreizehn neuen Katalogzeilen je Sprache sind nicht erfunden: die
deutschen Sätze stammen aus der Geschichte der INFO-Dateien
(`git log -p --follow`), aus den Zeilen, die `c101990` ersetzt hat.

### 4. Ein Commit, der die Läufer nicht mitgezogen hat

`c101990` (ECHTHARDWARE-2) hat die INFO-Dateien auf Englisch gestellt —
`name=Datei-Explorer` wurde `name=File Explorer` — und die Läufer nicht
angepasst. Das erklärt mehrere rote Zusagen in `k15` und die Gegenprobe
in `umlaut`, die auf die INFO statt auf den Katalog zielte.

Dabei fiel eine Erwartung auf, die nie eine war: `k15` verlangte
`launcher: treffer i=0 name=[Datei-Explorer]`. Die **Null** war keine
Zusage, sondern eine Folge des Alphabets — „Datei-Explorer" stand vor
„Editor", „File Explorer" steht dahinter. Geprüft wird jetzt, was die
Zusage sagt: dass das Bündel den Dateimanager mit Name **und** Befehl
führt.

### 5. Prüfer, die die falsche Frage stellten

* **`grep -c '^key: '`** verlor je Shell-Prompt eine Tastenmeldung. Die
  Shell schreibt `osum$ ` ohne Zeilenumbruch, die erste Meldung landet
  deshalb als `osum$ key: l` mitten in der Zeile. `k17` bestätigt es
  exakt: 31 getippte Zeichen, 3 Prompts, `^key: ` sah 28. Das war nie
  eine Lastfrage — keine noch so lange Wartezeit hätte es geheilt.
* **`tools/server/moved.py`** meldete 87 Abweichungen. 74 davon waren
  Funktionen, die es beim Umzug **noch gar nicht gab** (`panikbild` aus
  Runde PROTOKOLL, die `grace_*` aus ECHTHARDWARE-6). Code, den es beim
  Umzug nicht gab, kann der Umzug nicht verändert haben.
* **`systembus`** benutzte eine US-Tastenkarte, obwohl der Mitschnitt
  `kbd: layout de` sagt. `sendkey slash` ist auf einer deutschen
  Tastatur das **Minus**; getippt wurde `edit -etc-taskbar.conf`.

---

## Was gemessen und dann verworfen wurde

**`wmdauer` für `systembus`.** Nachdem `wmshell` die Shell im
Terminalfenster gestartet hatte, endete sie sofort wieder (die Konsole
ist leer, getippt wird über den Monitor). `wmdauer` startet sie neu —
und daraus wurde eine Endlosschleife: `elf: start 2295`, 2410-mal
`sh: ready` in einem Lauf, 830 KB Mitschnitt, `wm: hold` kam nie. Die
beiden Wörter schließen sich aus; `hidpunkte`, `hidweg` und `loader`
setzen `wmdauer` deshalb **ohne** `wmhold`.

Die Zusage d) von `systembus` bleibt damit rot, aber die Ursache ist
jetzt benannt statt vermutet: `wait_wm` läuft vollständig durch, **bevor**
`wm: hold` gedruckt wird — getippt wird aber erst danach.

---

## Was offen bleibt

* **`k15`, 36 rote Zusagen:** fast alle sind bildpunktgenaue
  Glyphenvergleiche (*„6 Zeichen, 300 Tintenpunkte geprüft, 164
  falsch"*). Vorher gab es diese Bilder gar nicht (*„No such file"*) —
  jetzt entstehen sie und werden verglichen. Das ist eine eigene Runde.
* **`werkzeug`, 6 rote Zusagen:** drei Läufe mit demselben Stand ergaben
  28/6, 27/7 und 27/7 — und die abweichende Zusage war **jedesmal eine
  andere**. Klick- und Bildprüfungen flattern auf einem geteilten Wirt.
  Fest sind 27.
* **`pci`:** *„DMA gegen PIO, in Tausendsteln: 919, erwartet ≥ 1200"* ist
  ein **Leistungsverhältnis**. Auf einem Wirt, den sich mehrere
  QEMU-Prozesse teilen, misst das den Wirt. Gehört auf eine ruhige
  Maschine.
* Fünfzehn Abschnitte sind gar nicht angefasst.

---

## Eine Regel, zweimal teuer gelernt

Eine **laufende** `run.sh` darf nicht bearbeitet werden. Bash liest das
Skript während der Ausführung weiter; eine Änderung mitten im Lauf ergibt
`unexpected EOF` oder `syntax error near unexpected token`, obwohl
`bash -n` die Datei für gültig hält. Passiert bei `tools/k15/run.sh` und
`tools/umlaut/run.sh` — beide Male ging ein Lauf von zwanzig Minuten
verloren.

---

## Jede Reparatur hat eine Gegenprobe

Ein Prüfer, den man nicht widerlegen kann, ist nichts wert. Deshalb wurde
zu jeder Lockerung nachgewiesen, dass sie nichts zudeckt:

* Die neue Tastenzählung `(^|[^a-z])key: ` zählt `monkey:`, `donkey:`,
  `keyboard:` und `apic: keyboard gsi 1` **nicht** mit, und eine fehlende
  Taste ergibt weiterhin rot.
* `moved.py`: eine absichtliche Zeile in `disp_wait` — einer der 26 noch
  zeichengleichen umgezogenen Funktionen — wird sofort als „weicht ab"
  gemeldet, Beendigungscode 1.
* `tools/hid/worte.py`: ein eingebautes `nofliptest` wird sofort als zwei
  neue Überschneidungen gemeldet.
* Die 125 aufgelösten Umschriften sind **oktettneutral** (`ae`→`ä` sind
  zwei Oktette wie vorher). Nachgewiesen am Ergebnis: die 94 berührten
  `[u8; N]`-Deklarationen sind vorher und nachher zeichengleich.
