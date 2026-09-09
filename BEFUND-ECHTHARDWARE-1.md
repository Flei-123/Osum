# BEFUND ECHTHARDWARE-1 — Justins Blech-Lauf vom 09.09.2026, 12:37–12:38

Abbild, das er gebootet hat: `orientos-usb-20260909-014f659.img`
(Build 014f6594, MERGE-9 `cad06fb`).
Arbeitsbaum dieser Runde: `/root/osum-merge9`, Zweig `merge9`.

---

## 0. DIE WICHTIGSTE ERKENNTNIS DIESER RUNDE

**Der Pruefstand konnte Justins Fehler gar nicht ausloesen.**

Fast alle Oberflaechenfehler seines Fotos treten **nur bei
Vervielfachung 2** auf (`wlibc.ui_scale() == 2`). Die Zahl kommt aus dem
**EDID seines Monitors**: `vmode.dpi_scale` rechnet Bildpunkte gegen die
physische Groesse und liefert 2, `kgui` setzt sie, und `wlibc.px_ui()`
gibt danach 30 statt 15 Bildpunkte Schrifthoehe zurueck.

**QEMU liefert kein EDID.** Im Emulator stand deshalb immer 1 — und
damit war jeder dieser Fehler unsichtbar, obwohl sie seit Wochen im Baum
lagen.

Neu: **`uiscale=<1..4>` auf der Kernel-Kommandozeile** (`kmain.fi` liest,
`kgui.fi` wendet nach dem EDID an, damit es das EDID schlaegt). Erst
damit ist Justins Schirm nachstellbar und diese Runde ueberhaupt
messbar. Alle Zahlen unten sind mit `uiscale=2` bei 2560x1440 gemessen.

---

## 1. DIE TABELLE

| # | Kritikpunkt | Ursache | Fix | Beleg |
|---|---|---|---|---|
| A1 | Startmenue: Klick startet nichts | **`panic: integer overflow` in `wlib.fi:2878`** — `bw - 2*bo` und `rb - bo` laufen in `u64` unter null, sobald ein Knopf schmaler als zwei Randbreiten ist. Der Zweig laeuft **nur bei `radius_button != 0`**, also nur unter `shape=osum` — den lieferte der Stick nie mit. Der Starter starb beim Malen seines eigenen Knopfes. | Untergrenzen geprueft, `bo=0` bzw. `ri=0` statt Unterlauf | `serial: 0 panics`; `launcher: start /apps/explorer.osp/start pid=19`, Fenster id=12 erscheint |
| A1b | Tippen kommt nicht an | `wm.on_mouse` gibt den Fokus **nur an `L_NORMAL`**. Der Starter muss auf `L_TOP` liegen (sonst verschwindet er hinter Fenstern) und war damit von jedem Fokus ausgeschlossen; `on_key` gibt die Taste nur an den Fokus. Tasten kamen bis in den Server und fielen dort auf den Boden. | Neues Fensterflag **`F_KEYS`/`WS_KEYS`**: ein Fenster sagt selbst, dass es die Tastatur will. Vorgabe nein — die Taskleiste bleibt, was sie war. | `launcher: suche [edi] treffer=4 apps=2 dateien=2`, Fenster `fl=18` (NODECO+KEYS) |
| A1c | (Folgefehler) | `panic: index out of bounds '[u64;16]'` in `launcher.fi:199` — die Meldeschleife zaehlte bis `ntreffer` (= `napp+ndatei`, bis 32) ueber `treffer[16]`, das nur Programme traegt. Fiel nie auf, weil die Dateisuche ein nichtleeres Suchfeld braucht — und tippen ging ja nicht. | Schleife auf `napp` und `< 16` begrenzt | 0 panics nach dem Fix, `edi` liefert Programme **und** Dateien |
| A2 | Kacheln: Titel ueber Zustand, abgeschnitten | `qs.fi` rechnete mit **festen** Bildpunkten (`TW 180`, `TH 74`, `SL_X 114`), geeicht an Schrifthoehe 15. Bei 30 passen zwei Textzeilen + Symbol nicht in 74. | Jedes Mass ist eine **Funktion ueber `ui_scale()`**; `TH()` wird aus dem Inhalt gerechnet, beide Grundlinien aus demselben Raster | Titel `y=93`, Zustand `y=136` → **43 px Abstand**; Texte voll: `Dunkelmodus`, `Aufgabenverwaltung`, `Alle Einstellungen` |
| A2b | Schieber: Linie quer durch die Schrift | Beschriftung bei `PAD`, Rinne ab **fester** Spalte `PAD+104`. Bei 30er Schrift ist „Lautstaerke" breiter als 104 → Rinne beginnt mitten im Wort. | Beschriftung in **eigener Zeile**, Rinne darunter ueber die volle Breite | Text endet `y<=515`, Rinne ab `y=540` — kein Schnittpunkt |
| A2c | Titel hart abgeschnitten | `qs.fit()` zaehlte **Oktette** herunter (zerteilt Umlaute) und schrieb kein Kuerzungszeichen | `wlibc.fit` (UTF-8-**Zeichengrenze**) + `...` | „Netz vortae" → `Netz-Sim`; `Akku: keiner` |
| A3 | Fenster ohne Text | **Kein Fehler** — Schrift und Rendering sind bei uiscale 2 in Ordnung | — | `suchtext.py`: „Ausfuehren" **100 %**, „Einstellungen" **100 %** bei 30 px |
| A4 | Netz nur 169.254.10.1 | `/bin/dhcp` meldet seinen Fortschritt **nur auf die serielle Leitung** — die sein Brett nicht hat (LSR FF). Aus der Tafel war nicht zu entscheiden, ob nichts hinausging, niemand antwortete oder ein NAK kam. | `inet.dhcp_set/get` + Syscall 1302; Tafelzeile 22 zeigt **einen Buchstaben** `D<x>` | Zeile bleibt exakt 48 Zeichen (Kopf auf `22 NETZ ` gekuerzt) |
| A5 | Uhr: RTC 12:38, KRN 14:38, Leiste 12:37 | `time.init` legte den RTC-Wert **unbesehen als UTC** ab, `now_local` addierte `tz=120` **noch einmal**. Die RTC steht auf **Ortszeit** (Windows daneben). Die Leiste las die RTC bei jedem Aufruf **roh** — drei Zeiten, drei Rechenwege. | `rtc_roh` merkt den Rohwert, **`tz_anwenden` rechnet EINMAL** nach UTC (`rtcutc` kehrt es um); `uio.sysinfo` beantwortet `I_YEAR..I_SEC` aus `time.now_local` | Systemzeit **UTC 11:43** → Leiste **13:43** (genau +2 h, einmal gezaehlt) |
| A6 | Tafel rot: `LG 2 Z21 51` | **Keine Sicherheitsfrage.** Zeile 21 listete bis zu 6 USB-Funde a 7 Zeichen: 9 + 42 = **51 > 48 Spalten**. `tafel_merken` setzt dann `zu_lang`, und Zeile 23 wird rot, sobald `zu_lang != 0`. | Hoechstens **5 Funde** (44 Zeichen) + `+N` fuer den Rest | Rechnung im Quelltext dokumentiert |
| B1 | „Alles komplett eckig" | Das Abbild lieferte **kein** `/etc/theme.conf`, keine `/etc/schemas/`, `/etc/shapes/`, `/etc/themes/`. Ohne `shape=` bleibt `wlibc.met` auf `classic` (`radius_window=0`); die Taskleiste ruft `form_push()` treu und schickt **lauter Nullen** an `wm.FM_RADIUS`. **Kein fehlender Zeichenweg — eine fehlende Datei.** | `build.sh` liefert Schemata, Formen und Voreinstellungen mit; Vorgabe `THEMA=tageslicht` | `taskbar: shape file=osum name=OrientOS keys=26`, `form n=8`, Fensterecke als **sauberer Viertelkreis** |
| B2 | „Farben passen nicht zusammen" | `/etc/theme` aus `tools/k15/tree.py` — **zwoelf dunkle Flaechenfarben ohne Schriftfarbe** — wird von `wlibc.reload_inner` **ZULETZT** gelesen und ueberschrieb das helle Tagschema wieder | `/etc/theme` wird **nicht mehr** mitgeliefert | Panelgrund `bg=16777215` (weiss) statt `3820126`; Palette `#f1f5f9` / `#ffffff` / Akzent `#2563eb` = Demo |

---

## 2. WAS NUR AUF ECHTER HARDWARE ZU PRUEFEN BLEIBT

### NETZ (A4) — bleibt offen, und zwar ehrlich

Im Emulator laeuft DHCP gegen QEMUs Benutzernetz und ist deshalb **kein
Beweis** fuer Justins Router. Was gebaut wurde, ist die **Diagnose**, nicht
die Loesung. Auf Tafelzeile 22 steht jetzt hinter der IP ein `D` und ein
Buchstabe:

| Zeichen | Bedeutung | Was es heisst |
|---|---|---|
| `.` | nicht gelaufen | `/bin/dhcp` wurde gar nicht gestartet |
| `d` | DISCOVER hinaus | laeuft, wartet auf Angebot |
| **`x`** | **DISCOVER ging NICHT hinaus** | der Stapel liess nichts los (Rundruf haengt an ARP) |
| `o` | OFFER da | Server hat geantwortet |
| `r` | REQUEST hinaus | fast fertig |
| `A` | **ACK — Adresse steht** | fertig, echte IP |
| `t` | Zeitablauf | gesendet, keine Antwort |
| `n` | NAK | Server hat abgelehnt |

**Justin: bitte Zeile 22 fotografieren.** `x` und `t` sind zwei ganz
verschiedene Fehler — `x` liegt bei uns, `t` am Netz.

### UHR (A5) — der Rest ist eine Annahme

Die Vorgabe ist jetzt **„RTC steht auf Ortszeit"** (wie Windows), weil
Justins Brett so gebootet ist. Das ist eine **Annahme ueber sein BIOS**,
die nur er pruefen kann.

- Zeigt die Leiste die **richtige** Uhrzeit → passt.
- Zeigt sie **zwei Stunden zu wenig** → seine RTC steht doch auf UTC,
  dann gehoert `rtcutc` in die Kommandozeile.

Tafelzeile 19 zeigt dazu `U 0` (Ortszeit) bzw. `U 1` (UTC).

### WAS JUSTIN TESTEN SOLL

1. **Startmenue**: Knopf klicken → Eintrag anklicken → Fenster erscheint.
   Ins Suchfeld tippen → Liste wird kuerzer.
2. **Knopf „Ausfuehren"** unten rechts: ganzes Wort lesbar?
3. **Kontrollzentrum** (Super+A): Titel **ueber** dem Zustand, nichts
   uebereinander; Schieber-Linie **unter** der Beschriftung.
4. **Ecken**: Fensterrahmen und Startmenue **rund** statt eckig?
5. **Tafel Zeile 19** (`U`-Ziffer) und **Zeile 22** (`D`-Buchstabe)
   fotografieren.
6. **Tafel Zeile 23**: steht dort noch `LG` ungleich 0?

---

## 3. PRUEFSTAENDE

| Stand | Ergebnis |
|---|---|
| WM | **104 bestanden, 0 gescheitert** |
| USERLAND | **91 bestanden, 0 gescheitert** |
| K16 | **64 bestanden, 0 gescheitert** |
| USBIMG | **46 bestanden, 2 gescheitert** |
| Abbildbau | 55 Pflichtpfade geprueft, 181 Umlautfolgen |
| Durchklick 2560x1440 uiscale=2 | 0 panics, Starten und Tippen belegt |

Die **zwei** bei USBIMG sind dieselben wie in der Vorrunde und liegen
beide im **UEFI-Lauf** (`erkannte Firmware: ?`, `kein Rahmenpuffer im
Bericht`) — sie haengen an OVMF und nicht an dieser Runde. Der
BIOS-Lauf, der AHCI-Lauf und der e1000-Lauf sind gruen.

Nebenbefund aus demselben Lauf, der diese Runde bestaetigt: der Stand
prueft selbst, dass **„Ausfuehren" mit Umlaut** im Bild steht und die
ASCII-Ersatzschreibung *nicht* — `'Programm suchen:' 100 %`.

### Eine Messfalle, die hier festgehalten gehoert

Nach vielen Oeffnen/Schliessen-Zyklen in **einer** langen QEMU-Sitzung
reagiert die Liste des Starters nicht mehr auf Klicks: die Ereignisse
kommen an (`RING` und `APP` steigen), der Starter meldet nichts. Nach
einem **frischen Boot** geht es sofort wieder.

Deshalb gilt ab hier: **Durchklick-Punkte immer auf frischem Boot
messen.** Wer das nicht tut, misst Sitzungsdrift und haelt sie fuer
einen Fehler des Systems — genau das ist mir in dieser Runde einmal
passiert, bevor der Gegenlauf es zeigte.

## 4. ABBILD

`orientos-usb-20260909-1bdd599.img`
`de4ce0a960d7b62eb5e92b7c9a6b1a1467052fd7f5037fe688b2d2304933e312`

- `/root/abbilder/` und `/srv/store/abbilder/`
- **NICHT als aktuell markiert** — der Verweis zeigt unveraendert auf das alte Abbild.

### Gegenprobe am FERTIGEN Abbild (frischer Boot, 2560x1440, uiscale=2)

| Punkt | Ergebnis |
|---|---|
| Abstuerze | **0 panics** |
| Form | `taskbar: shape file=osum name=OrientOS keys=26`, `form n=8` |
| Uhr | Systemzeit **UTC 12:00** → Leiste **14:00:38** (genau +2 h) |
| Klick auf Eintrag | `launcher: start /apps/explorer.osp/start pid=19` |
| Tippen | `[e]` 18 Treffer → `[ed]` 6 → `[edi]` 4 — die Liste wird mit jedem Zeichen kuerzer |

## 5. BELEGE

- `/srv/store/belege/orientos-vergleich/20260909/` — `vergleich-*.png`
  (Demo links, jetzt rechts), dazu die Einzelbilder.
- `/srv/store/belege/echthardware-1/` — Panel, Startmenue, Knopf-Lupe.
