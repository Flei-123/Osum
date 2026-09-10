# Runde MESSTAFEL — erst messen, dann bauen

Justin hat das Abbild `14b01f06…d520` gebrannt und getestet. Ergebnis:
**die Eingabe ist weiterhin tot.** Tastatur und Maus arbeiten im
Limine-Menü einwandfrei, im Schreibtisch passiert bei Tastendruck
nichts und der Zeiger bewegt sich nicht. Die Taskleiste meldet Erfolg
(`rc=0`, `w=3440 h=56`) und ist trotzdem unsichtbar.

Damit ist die Erklärung der Runde HIDPUNKTE — der Fensterserver habe
den falschen Regler gewählt — **auf echtem Blech nicht bestätigt**. Die
Reglerbewertung mag richtig sein; Justins Fehler löst sie nicht. Diese
Runde behandelt die Ursache deshalb als **unbekannt** und baut
stattdessen das, was seit vier Runden fehlt: **ein Messgerät.**

---

## 1. Die Messtafel — acht Zeilen, die ein Handyfoto lesbar macht

Nach der Runde FASSUNG stand *eine* Zeile mit zwanzig Zahlen oben am
Schirm. Justin fotografiert aus zwei Metern. Er konnte sie nicht lesen.
Eine Diagnose, die man nicht lesen kann, ist keine.

Jetzt stehen dort **acht kurze Zeilen, jede eine Stufe des Eingabewegs,
jede in einer Farbe**:

```
osum bc23cc78 B73 T4941      weiß    Fassung + Herzschlag
1 USB  BER 10 WAHL 1         Ampel   HID-Berichte des USB-Baums
2 REIHE T3 M4                Ampel   eingereiht (kbd-Ring / ps2m-Pakete)
3 SERV  T4 M5                Ampel   vom Fensterserver abgeholt
4 RING  46  VERL 0           Ampel   in einen Fensterring gelegt
5 APP   12                   Ampel   von einem Ring-3-Programm abgeholt
6 ZEIGER X2219 Y1069         Ampel   wo der Server den Zeiger führt
7 LEISTE id9 y1384 MAL 10 fl2 Ampel  wurde die Taskleiste gemalt?
```

**Grün heißt „hier kam etwas an", rot heißt „hier kam nichts an".** Die
**erste rote Zeile ist die Stelle, an der es abreißt.** Das erkennt man
aus zwei Metern, ohne eine einzige Ziffer zu entziffern.

Zeile 0 beantwortet die Frage davor: *läuft der Rechner überhaupt
noch?* `B` sind die zusammengesetzten Bilder (die Hauptschleife), `T`
die Zeitgebermarken (die Unterbrechung). Stehen beide still, ist die
Maschine hängengeblieben und keine der sieben Stufen darunter bedeutet
etwas. Diese Unterscheidung — **eingefroren gegen läuft-bekommt-aber-nichts**
— war bisher auf keinem Foto zu treffen.

### Gemessen, nicht behauptet

QEMU, 3440×1440, Justins Topologie und **sein echtes `root.img`** aus
dem veröffentlichten Abbild (`mcopy` aus `osum-usb.img`):

| | Leerlauf | nach `sendkey a b c` + `mouse_move` |
|---|---|---|
| 1 USB | **rot** `BER 0` | **grün** `BER 10` |
| 2 REIHE | **rot** `T0 M0` | **grün** `T3 M4` |
| 3 SERV | grün `T1 M1` | grün `T4 M5` |
| 4 RING | grün `39` | grün `46` |
| 5 APP | grün `7` | grün `12` |
| 6 ZEIGER | `X1719 Y719` | `X2219 Y1069` |
| 7 LEISTE | grün `MAL 10` | grün `MAL 10` |

Zurückgelesen wurde das **aus dem Bildschirmfoto**, Zeichen für Zeichen
gegen den echten 8×16-Zeichensatz aus `kernel/font.fi` — nicht aus dem
seriellen Protokoll. Was in der Tabelle steht, stand wirklich auf dem
Schirm.

---

## 2. Der Fehler, der die letzten drei Runden unsichtbar gemacht hat

`wm.compose` steigt in seiner zweiten Zeile aus, wenn nichts schmutzig
ist:

```
fn compose(state: u64) -> u64 {
    ...
    if gs(state, S_DON) == 0 {
        return 0            // <- und der Ausstieg liegt VOR fb.flush
    }
    ...
    fb.dirty(state, y0, y1)
    fb.flush(state)
```

Die Messleiste wird **nach** `compose` gemalt und rief selbst nie
`fb.flush`. **Auf einem Schreibtisch, auf dem sich nichts bewegt, wird
also nie geflusht** — alles, was danach gemalt wird, landet im
Zweitpuffer und kommt dort nicht mehr weg.

In QEMU fiel das nicht auf, weil dort die Shell im Terminalfenster
ständig neu startet und mit jeder Zeile Schmutz erzeugt. Auf Justins
Brett steht der Schreibtisch still.

**Gemessen am Bildschirmfoto vor der Behebung:** die obersten **84**
Bildzeilen der Tafel standen auf dem Schirm, die restlichen **258**
nicht. Nach dem Einbau von `fb.flush` in `kopf_malen`: alle 342 Zeilen,
in drei Fotos in Abständen identisch.

Justin hat nach der Runde FASSUNG gemeldet „kein sichtbarer
Unterschied". **Er hatte zum zweiten Mal recht.**

Ob das auch die tote Eingabe erklärt, ist damit **nicht** gesagt — der
Zeiger geht über `on_mouse` → `damage` → `compose`, und das flusht. Was
es erklärt, ist, warum wir seit drei Runden blind sind.

---

## 3. Die Taskleiste — was ausgeschlossen ist, und was jetzt gemessen wird

**Justins Verdacht `strut edge=0` = obere Kante trifft nicht zu.**
Nachgesehen in `kernel/user/wlibc.fi:210` und `kernel/sys.fi:521`:

```
const WE_BOTTOM: u64 = 0
const WE_TOP:    u64 = 1
```

`edge=0` ist die **untere** Kante. Der Bau schreibt `edge=bottom` nach
`/etc/taskbar.conf`, die Leiste liest es richtig, und
`taskbar: STEHT x=0 y=1384 w=3440 h=56` ist auf einem 1440 hohen Schirm
genau der untere Rand.

Mit **Justins echtem `root.img`** läuft die Leiste in QEMU vollständig
durch — `qs: symbols n=3` (wie bei ihm), dann `STEHT`, `ready`,
Knöpfe, Uhr — und ist auf dem Bildschirmfoto bei y=1384 sichtbar. **Der
Fehler ist hier nicht reproduzierbar.** Also wird er meßbar gemacht:

Zwei neue Zähler je Fenster (`W_PAINTS`, `W_PX`, Lücke 0x130 in
`WIN_BYTES`), hochgezählt in `paint_win` **vor** der Verzweigung nach
`deko`, und eine Fensterliste auf der seriellen Leitung:

```
wm: fen i=2 id=9 x=0 y=1384 w=3440 h=56 lay=2 fl=2 z=4 malen=10 px=1909760
```

Damit ist der Weg lückenlos:

* `7 LEISTE KEIN` (rot) → sie hat sich nie auf der obersten Ebene
  angemeldet.
* `MAL 0` (rot) → `compose` übergeht sie. Dann sagt `fl=` warum
  (verborgen/Reiter) oder `z=` wo sie im Stapel liegt.
* `MAL 47` (grün) **und unten trotzdem blau** → die Bildpunkte sind
  gemalt, der Fehler liegt dahinter (Zweitpuffer, Flush, Zeilenabstand).

---

## 4. Die Namen: OrientOS ist das System, Osum der Kern

`docs/ROADMAP-UPDATE.md:28` sagt es seit langem — auf dem Schirm stand
trotzdem überall Osum. Justins Vergleich trifft: der Kern heißt Linux,
der Startschirm sagt Ubuntu.

**`docs/NAMING.md` steht dem nicht entgegen** und wurde vorher gelesen:
jenes Dokument regelt **Deutsch gegen Englisch** in Pfaden und
Anzeigetexten („die Struktur ist englisch, nur die Oberfläche wird
übersetzt"), nicht den Produktnamen. Es gibt dort keine Regel über
Osum/OrientOS, also gibt es auch keinen Widerspruch aufzulösen.

| trägt jetzt **OrientOS** | bleibt **Osum** |
|---|---|
| die zehn Bootmenü-Einträge | `/osum.mb`, der Kern selbst |
| die erste Zeile im Terminalfenster | das Startprotokoll des Kerns |
| der Dateiname des Abbilds | die Fassungszeile `osum <hash>` |
| | Panikmeldungen, `wm:`/`taskbar:`/`desk:` |

Das Abbild heißt `orientos-usb.img`; **`osum-usb.img` liegt als Verweis
daneben** (Symlink, keine Kopie — zwei Dateien mit demselben Inhalt sind
zwei Dinge, die auseinanderlaufen können).

Die Zeile im Terminalfenster ist Ziel von vier bildpunktgenauen Zusagen
in `tools/wm/run.sh`; die Zeichenkette ist dort **mitgewandert**
(`ORIENTOS K10 WM 0123`). Eine Zusage, die auf einen Text zeigt, den es
nicht mehr gibt, geht immer auf und misst nichts.

---

## 5. Englisch im Bootmenü

Beide Kataloge lagen schon im Abbild (`/usr/share/locale/{de,en}/messages`,
beide in der `PFLICHT`-Liste). Was fehlte, war der Schalter: die Sprache
stand fest in `/users/root/config/locale`, und das
Einstellungsprogramm, das sie umstellen kann, braucht Maus oder
Tastatur — also genau das, was bei Justin klemmt.

`lang=en` auf der Kommandozeile → `kstate.M_LANGEN` → `kgui.locale_setzen`
schreibt die Wahl **vor dem ersten Ring-3-Programm** in die Datei, an
der `msg.fi` ohnehin nachsieht. **Kein zweiter Weg zur Sprache, keine
zweite Wahrheit** — die Datei bleibt der einzige Ort, an dem die
Sprache steht, sie wird nur vorher richtig gestellt. Ohne `lang=`
verhält sich ein Stick Oktett für Oktett wie vorher.

Gemessen:

```
locale: gesetzt en rc=3
taskbar: lang=en src=1 keys=200
taskbar: text net     … t=no network     (vorher: kein Netz)
taskbar: text battery … t=no battery     (vorher: kein Akku)
```

Neuer Eintrag: **`/OrientOS -- desktop only (English)`**.

**Was NICHT auf Englisch ist:** der Starterknopf heißt weiter `Suchen`.
Der Name kommt aus `assets/apps/launcher.osp/INFO` (`name=Suchen`), und
das Bündelformat hat kein Sprachfeld. `docs/NAMING.md` nennt `name=`
ausdrücklich als übersetzbaren Anzeigetext — das Format kann es nur
noch nicht. Das ist eine Formatänderung und gehört in eine eigene
Runde, nicht in einen Schnellschuss am Ende dieser.

---

## 6. Regressionen

| Läufer | Ergebnis |
|---|---|
| `tools/wm/run.sh` | **104 erfüllt, 0 gescheitert** (inkl. der 4 umbenannten Zusagen) |
| `tools/i18n/run.sh` | 37 erfüllt, 0 gescheitert |
| `tools/desktop/run.sh` | 79 erfüllt, **19 gescheitert — Ausgangslage 20** |
| `tools/paint/scalars.py` | 80 Skalare, **0 Überschneidungen** |

Die 19 Fehlschläge im Schreibtisch-Läufer sind **Zeile für Zeile
dieselben** wie in der Ausgangslage der Vorrunde (`comm -23` auf die
sortierten Namen: leer). **Kein einziger neuer Fehlschlag**, einer
weniger als vorher. Der Läufer ist zeitempfindlich; das ist in
`docs/RUNDE-HIDPUNKTE.md` belegt.

---

## 7. Was Justin tun soll

1. Brennen, booten. **Ganz oben muss `osum <hash>` stehen** — steht dort
   etwas anderes, ist es eine andere Fassung.
2. Eintrag **„nur der Schreibtisch (deutsch)"** wählen.
3. **Die Messtafel fotografieren.** Nicht tippen.
4. **Tippen und die Maus bewegen. Noch einmal fotografieren.**

Die beiden Fotos sagen alles: welche Zeile rot ist, und welche Zahlen
sich zwischen den Bildern geändert haben. Danach ist die Ursache keine
Vermutung mehr.

Für Englisch: Eintrag **„desktop only (English)"**.
