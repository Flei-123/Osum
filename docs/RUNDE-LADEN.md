# Runde LADEN — der Laden liefert zum ersten Mal echte Programme aus

Zweig `laden`, abgezweigt von `hidweg`. **Nicht nach `main` gemerged, nicht
nach GitHub gepusht.** Arbeitsbaum `/root/osum-laden`.
Abnahme: `bash tools/laden/run.sh` (QEMU mit `-accel kvm`, offenes Netz).

Vorher lag im Feed **ein** Paket: `hallo-2.opk`, 34 291 Oktette, ein Programm,
das eine Zeile schreibt und sich beendet. Nachher liegen dort **acht**
Programme mit Fenstern, Symbolen und Beschreibungen, zusammen 2 471 438
Oktette — und ein Osum in QEMU holt sie über HTTPS von `store.fleitec.com`,
prüft sie zweimal, installiert sie und startet sie aus dem Starter.

---

## 0. Was den Laden bis hierher blockiert hat, und es war eine Zahl

`kernel/user/opk.fi` las ein Paket **ganz** in einen statischen Puffer:

    const PKT_MAX: u64 = 393216          // 384 KiB
    static mut PKT: [u8; 393216]

Gemessen an diesem Baum:

| Programm | Oktette |
|---|---:|
| `/bin/settings` | 602 800 |
| `/bin/explorer` | 567 440 |
| `/bin/launcher` | 509 672 |
| `/bin/taskbar` | 403 784 |
| `/bin/netmon` | 382 720 |

**Der Laden konnte genau die Programme nicht ausliefern, für die es ihn
gibt.** Was durchging, war `hallo`. Das ist keine Panne im Betrieb — es ist
eine Grenze, die nie an einem echten Paket gemessen wurde, weil es keines
gab.

Neu: **2 MiB**, und die Zahl ist gerechnet und nicht geraten. Das Abbild
eines Ring-3-Programms liegt zwischen `proc.IMAGE_BASE` (0x40100000) und
`proc.IMAGE_END` (0x40400000, seit Runde K16) — drei Megaoktette. `opk`
selbst braucht 147 240 Oktette Text und rund 36 KiB übrige Puffer; das
fertige Abbild endet bei 0x4032BFB8 und lässt über 850 KiB Luft. Die Zusage
darüber bleibt Wort für Wort: **was größer ist, wird abgelehnt und nicht
halb installiert.**

---

## 1. Das Paketformat, aus `opk.fi` und aus den vorhandenen Paketen gelesen

Ein `.opk` ist **Kopf, Metadaten, Nutzlast** — und die Signatur liegt
**daneben**, in `<datei>.opk.sig`, 64 rohe Oktette Ed25519.

### Der Kopf: 64 Oktette, fest

| Versatz | Länge | Inhalt |
|---:|---:|---|
| 0 | 8 | Kennung `OPKG0001` |
| 8 | 8 | Länge der Metadaten, u64 little-endian |
| 16 | 8 | Länge der Nutzlast, u64 little-endian |
| 24 | 32 | SHA-256 über **Metadaten + Nutzlast** |
| 56 | 8 | Füllung, null |

Nachgerechnet an `hallo-2.opk` aus `/root/ota-avx-nach/netzman/`:
`4f504b4730303031` = `OPKG0001`, dann `a1 00…` = 161 Oktette Metadaten,
`1285 00…` = 34 066 Oktette Nutzlast, 64 + 161 + 34 066 = 34 291 = die
Dateigröße. Die drei Zahlen sind die erste Prüfung, die jeder Leser macht.

**Der Streuwert im Kopf ist NICHT der der Datei.** Er geht über Metadaten
und Nutzlast, also über den *Inhalt* — das ist die Zahl, die im PLAN einer
Generation steht und die `opk pruefen` nachrechnet. Der Streuwert über die
**Datei** steht im VERZEICHNIS der Auslieferung und ist die Zahl, die `ota`
prüft, *bevor* es die Oktette anfasst. Zwei Fragen, zwei Zahlen, zwei
Programme.

### Die Metadaten: Text, `schluessel=wert`, eine Zeile je Feld

    name=explorer
    fassung=1.0.0
    titel=Datei-Explorer
    info=Dateien und Ordner ansehen, kopieren und sichern
    keys=datei,dateien,explorer,ordner,verzeichnis,manager,file,files,folder
    handle=fenster

`name` ist der Schlüssel: er ist der Name im INDEX, im PLAN — **und der
Verzeichnisname des installierten Bündels**, `/apps/<name>.osp`
(`kernel/user/opk.fi`, `apps_bauen`). Deshalb ist er englisch und klein.
`braucht=` und `handle=` dürfen mehrfach vorkommen.

### Die Nutzlast: ein Archiv, das keines von der Stange ist

Je Eintrag, hintereinander, ohne Ausrichtung:

    1 Oktett    'd' (Verzeichnis) oder 'f' (Datei)
    2 Oktette   Modus, u16 little-endian
    2 Oktette   Länge des Namens, u16
    n Oktette   der Name, UTF-8, mit '/' als Trenner
    8 Oktette   Länge der Daten, u64
    m Oktette   die Daten

Sortiert wird über die **Oktette** des Namens. Kein `tar`: `tar` trägt Zeit,
Eigentümer und Füllung mit sich, und zwei Läufe über denselben Baum ergäben
verschiedene Oktette — dann wäre „gleicher Streuwert = gleicher Inhalt"
nicht mehr wahr, und der ganze Entwurf hängt daran. Aus demselben Grund
kommt der Modus **nicht** vom Wirt: ausführbar ist, was `start` heißt, alles
andere ist 0644.

### Was `opk` daraus auf dem Gerät macht

    /store/<20 Hexziffern>/     der unveränderliche Eintrag, + PAKET
    /system/generations/<n>/PLAN   Text: <name><TAB><sha256>
    /apps/<name>.osp/           harte Verweise auf den Store-Eintrag,
                                alles außer PAKET

`/apps` ist **abgeleiteter** Zustand: `apps_bauen` wirft es weg und baut es
aus dem PLAN neu. Ein Paket, dessen Archiv `start`, `INFO` und `symbol`
enthält, wird damit ohne einen weiteren Handgriff zu einem Bündel im Sinn
von `kernel/user/appdir.fi` — mit Anzeigename, Beschreibung,
Schlüsselwörtern und Symbol. **Genau das hat `hallo` nie getan**: sein
Rezept nennt nur `datei=start`, und ein Bündel ohne INFO hat im Starter
keinen Namen.

---

## 2. Die acht Pakete

`tools/laden/apps.tab` ist die Liste, `tools/laden/pakete.sh` baut daraus je
Paket eine INFO (im Format von `appdir.fi`), ein Symbol (aus einer
Zeichnung, mit `tools/k15/icon.py` — dasselbe Werkzeug wie für die
mitgelieferten Bündel, kein zweites Format) und ein Rezept für
`pkg/opk.py`.

| Paket | Titel | Fassung | Oktette | Art |
|---|---|---|---:|---|
| `explorer` | Datei-Explorer | 1.0.0 | 569 004 | Fenster |
| `settings` | Einstellungen | 1.0.0 | 604 356 | Fenster |
| `netmon` | Netzmonitor | 1.0.0 | 384 242 | Fenster |
| `themetest` | Vorlagen | 1.0.0 | 351 500 | Fenster |
| `widgetdemo` | Widgets | 1.0.0 | 335 286 | Fenster |
| `edit` | Editor | 1.0.0 | 112 528 | Fenster |
| `netview` | Netzsicht | 1.0.0 | 63 468 | Konsole |
| `top` | Prozesse | 1.0.0 | 46 958 | Konsole |

Jedes trägt drei Dateien: `start` (das Programm), `INFO` (219 Oktette bei
`explorer`) und `symbol` (1036 Oktette, 16×16 OSYM). Fünf Zeichnungen sind
neu (`settings`, `netview`, `themetest`, `top`, `netmon`), drei sind die
vorhandenen aus `assets/apps/`.

**Der Dateiname trägt nur die erste Ziffer der Fassung** —
`widgetdemo-1.opk` und nicht `widgetdemo-1.0.0.opk`. Ein
Verzeichniseintrag in OFS ist 32 Oktette, davon 24 für den Namen samt Null
(`kernel/fs.fi`, `NAME_LEN = 24`); `ota` legt neben das Paket dessen
Signatur, und `widgetdemo-1.0.0.opk.sig` sind 24 Zeichen und passen damit
**nicht** mehr hinein. Mit der kurzen Form sind es 20.

---

## 3. Der Feed — mit dem vorhandenen Werkzeug, nicht mit einem zweiten

Es gibt dafür `tools/ota/veroeffentlichen.py`, und es wurde benutzt:

    python3 tools/ota/veroeffentlichen.py /srv/store/osum \
        --stand /tmp/laden/stand --bund /root/.secrets/osum-ota-bund.json \
        --notiz "RUNDE LADEN: acht Programme von Osum"
    -> fassung 3  8 Paket(e)  schluesselgen 0  kette 0  gesperrt -  -> aktuell 3

Das Register führt jetzt `letzte 3`, vorgehalten sind `[1, 2, 3]`, der
Vorrat hat 10 inhaltsadressierte Pakete. Die Fassungen 1 und 2 (`hallo`)
bleiben stehen — `veroeffentlichen.py` nimmt nichts weg.

Für den Katalog des Speichers (`index.json`, den die Android-App liest) gibt
es `werkzeug/store` im Repo `/root/orientstore`, und auch das wurde benutzt:
`store add` je Paket, dann `store publish /srv/store`, dann `store verify`
→ *„Signatur gültig (beide Umsetzungen einig) · 27 Dateien geprüft ·
Ergebnis in Ordnung"*.

Von außen, mit einem **fremden** Werkzeug geholt:

    curl https://store.fleitec.com/osum/aktuell/VERZEICHNIS   200, 875 Oktette
    curl https://store.fleitec.com/osum/aktuell/explorer-1.opk 200, 569 004
    curl https://store.fleitec.com/index.json                  Revision 76, 12 Pakete

### Zwei Befunde am Rand, die keiner gesucht hat

**(a) Der geheime Schlüssel der Auslieferung war weg.** Die Fassungen 1 und
2 wurden in Runde MERGE-5 mit einem Schlüssel signiert, der in `/tmp` lag
und den kein Ort mehr hat. Ein Schlüsselwechsel *mit* Kettensatz
(`schluesselbund.py wechseln`) braucht die alte geheime Hälfte — es ging
also nicht. Fassung 3 trägt deshalb einen **neuen** Hauptschlüssel
(`9aae8ec4…`), und ein Gerät, das noch den alten kennt, würde sie
richtigerweise ablehnen. Es gibt keines. Der neue Bund liegt ab jetzt unter
`/root/.secrets/osum-ota-bund.json` (0600, verschlüsselt, Passphrase in
`OSUM_SIGN_PASS`), damit die nächste Runde weiter unter *demselben*
Schlüssel veröffentlichen kann.

**(b) `store add --name` tat bei einer `.opk` nichts.** Der Katalog zeigte
`explorer` statt `Datei-Explorer`; bei einer `.apk` wurde die Angabe seit
jeher beachtet. Ein Schalter, der bei einer von zwei Dateiarten still nichts
tut, ist schlimmer als keiner. Eine Zeile in `/root/orientstore`
(`werkzeug/store`, `args.name or o.name`), eigener Commit, nicht gepusht.

---

## 4. Was in QEMU wirklich passiert ist

Die Platte für diese Runde baut `tools/laden/abbild.sh`, und sie ist die
erste, die **beides** trägt: die Oberfläche (`tools/look/shot.sh` baut sie
ohne `opk`/`ota`/`fetch`) **und** die Paketverwaltung
(`tools/install/build.sh` baut sie ohne eine Zeile Oberfläche). Ein Laden,
der Programme mit Fenstern ausliefert, braucht beides auf derselben Platte.

### Die Liste — über den NAMEN, mit echter Zertifikatskette

    fetch: aufgeloest 1833282759
    fetch: roots 11
    fetch: verify OK
    fetch: certs 4          fetch: depth 3
    fetch: code 200
    ota: fassung hier 0
    ota: fassung dort 3
    ota: NEUE FASSUNG verfuegbar
    ota: paket edit 1.0.0
    ota: paket explorer 1.0.0
    ota: paket netmon 1.0.0
    ota: paket netview 1.0.0
    ota: paket settings 1.0.0
    ota: paket themetest 1.0.0
    ota: paket top 1.0.0
    ota: paket widgetdemo 1.0.0

Vier Zertifikate, Kettentiefe 3 — das ist Let's Encrypt und nicht eine
Wurzel, die derselbe Lauf zwei Minuten vorher selbst gebaut hat.
`ota suchen` **installiert nichts**; das steht so im Protokoll.

### Die Installation — gemessen, mit Uhrzeit

Ein Osum ohne ein einziges Paket, `ota einspielen` gegen den echten
Server. Anfang und Ende sagt `/bin/date` im Gast:

    2026-09-05 15:37:16   ota einspielen
    2026-09-05 16:13:03   fertig               -> 35 min 47 s

    ota: platz 126317568          ota: noetig 7402026
    ota: streuwert stimmt edit-1.opk … widgetdemo-1.opk      (8 von 8)
    opk: Signatur geprüft /tmp/ota/INDEX.sig
    opk: Signatur geprüft /tmp/ota/<paket>.opk               (8 von 8)
    opk: installiert edit -> 0 … widgetdemo -> 7             (8 von 8)
    ota: BEREIT ZUM NEUSTART -- es wird NICHT
    ota: fassung hier 3           ota: generation 7

Danach:

    osum$ opk liste
    generation 7
      widgetdemo -> 1aeea9192a1f      settings  -> 4949ca447fa0
      top        -> cb7c7badab50      netview   -> 515978a5dc65
      themetest  -> e68ff554b54d      netmon    -> 03cfdf6397a3
      explorer   -> 959bb0557376      edit      -> 646df8d7cca0

Die Zahl neben jedem Namen ist der Streuwert über **Metadaten und
Nutzlast** — dieselbe, die `opk.py bauen` auf dem Wirt ausgegeben hat.
Zwei Programme, zwei Rechnungen, ein Ergebnis.

**Und die Fassungsnummer geht zuletzt hoch**: `ota: fassung hier 3`
steht *nach* `opk: installiert widgetdemo`. Fällt zwischen beidem der
Strom aus, steht die neue Generation und die Fassung ist noch alt — der
nächste Lauf spielt dasselbe noch einmal ein. Andersherum wäre es ein
Gerät, das eine Fassung führt, die es nicht hat.

### Der Starter — und das ist das eigentliche Bild dieser Runde

Derselbe Rechner, neu gestartet, mit Oberfläche. `/bin/launcher` liest
`/apps` und meldet, was er gefunden hat:

    launcher: apps=8
    launcher: treffer i=0 name=[Datei-Explorer] exec=[/apps/explorer.osp/start]
    launcher: treffer i=1 name=[Editor]         exec=[/apps/edit.osp/start]
    launcher: treffer i=2 name=[Einstellungen]  exec=[/apps/settings.osp/start]
    launcher: treffer i=3 name=[Netzmonitor]    exec=[/apps/netmon.osp/start]
    launcher: treffer i=4 name=[Netzsicht]      exec=[/apps/netview.osp/start]
    launcher: treffer i=5 name=[Prozesse]       exec=[/apps/top.osp/start]
    launcher: treffer i=6 name=[Vorlagen]       exec=[/apps/themetest.osp/start]
    launcher: treffer i=7 name=[Widgets]        exec=[/apps/widgetdemo.osp/start]

**Acht Namen, und keiner davon steht im Quelltext dieses Systems.** Sie
kommen aus den INFO-Dateien in den Paketen, die über das Netz kamen. Vor
dieser Runde standen dort fünf Namen, und alle fünf waren beim Bau des
Abbilds eingebacken.

### Und sie laufen

    osum$ /apps/widgetdemo.osp/start
    elf: start 6 … bytes=505036
    wm: fen i=5 id=12 x=60 y=60 w=480 h=400

    osum$ /apps/explorer.osp/start
    elf: start … bytes=563573
    wm: fen i=5 id=12 x=70 y=70 w=660 h=430

Aus den Bildern zurückgelesen (`tesseract`, `docs/shots/laden/`):

* **Widgets**: „K15 Widgets" · „Datei Bearbeiten Hilfe" · „Kopier mich" ·
  „Knopf · Kopieren · Haken" · Liste „alpha beta gamma delta".
* **Datei-Explorer**: „Datei Ansicht" · „Start /data" · Spalten „Name ·
  Größe · Zeit · Rechte" · „8 Stück, 2 Ordner, 354 Oktette".

### Die Gegenprobe: was beschädigt ist, kommt nicht durch

    osum$ opk installieren /boese/verdreht.opk
    opk: SIGNATUR FALSCH -- das Paket wird ABGELEHNT: /boese/verdreht.opk
    osum$ opk installieren /boese/ohnesig.opk
    opk: KEINE SIGNATUR -- abgelehnt, Datei fehlt: /boese/ohnesig.opk.sig
    osum$ opk installieren /boese/hallo-1.opk
    opk: SIGNATUR FALSCH -- das Paket wird ABGELEHNT: /boese/hallo-1.opk
    osum$ opk liste
    (keine Pakete)

Drei Fälle, drei verschiedene Gründe: ein gekipptes Oktett mitten in den
Daten (die Signatur schlägt **vor** der Prüfsumme zu), eine fehlende
Signaturdatei, und ein Paket, dessen Signatur echt ist — nur von einem
Schlüssel, den dieses Gerät nicht kennt. **Und danach ist nichts
installiert**: kein halbes Paket, kein Store-Eintrag, keine Generation. Das
ist die Zeile, die den Abschnitt erst zu einer Messung macht.

---

## 4b. Die Bilder

Alle in `docs/shots/laden/`, 1280x1024, aus QEMU über den Monitor
(`screendump`), auf derselben Maschine, in dieser Reihenfolge:

| Bild | Was darauf steht |
|---|---|
| `1-liste-im-terminal.png` | `ota suchen` im Terminalfenster: `fassung hier 0` · `fassung dort 3` · `NEUE FASSUNG verfuegbar` · die Paketzeilen |
| `2-starter-acht-programme.png` | der Starter mit den acht Programmen aus dem Laden, mit Symbol und Beschreibung |
| `3-installation-im-terminal.png` | `opk installieren /tmp/ota/top-1.opk` im Terminalfenster |
| `4-widgets-laeuft.png` | `/apps/widgetdemo.osp/start` — das Fenster steht, mit Menü, Knöpfen und Liste |
| `5-explorer-laeuft.png` | `/apps/explorer.osp/start` — der Dateimanager zeigt `/data` |

Getippt wird über die **PS/2-Tastatur** (`tools/laden/tippen.py` →
`tools/wm/monitor.py` → QEMU `sendkey`), nicht über `script=` auf der
seriellen Leitung: was durch die serielle Tür geht, steht nie auf dem
Bildschirm, und ein Bild davon gäbe es nicht.

**Bild 3 ist das schwächste, und das steht hier, weil es stimmt.** Das
Terminalfenster hängt an der Konsole; der Schreibtisch schreibt im
Fünf-Sekunden-Takt zwei Dutzend Zeilen Messwerte dorthin. Zwischen
`opk: installiert top -> 8` und der Aufnahme lag ein solcher Takt, und
die Antwort war hinausgerollt. Was die Installation belegt, ist der
Mitschnitt — Bild 3 zeigt den Befehl und das Fenster, in dem er lief.

## 5. Was diese Runde NICHT eingelöst hat

* **Es gibt keinen Laden mit Oberfläche.** Der Katalog wird mit `/bin/ota`
  gelesen und mit `/bin/opk` installiert — auf der Konsole, im
  Terminalfenster des Fensterservers. Ein Fenster mit Kacheln, Symbolen und
  einem Knopf „installieren" wäre die nächste Runde; das Symbol liegt seit
  dieser Runde **im Paket**, also hätte sie etwas anzuzeigen.
* **`opk` ist langsam.** Gemessen auf diesem Wirt, `explorer` (569 004
  Oktette) von der Platte, ohne Netz: **130 Sekunden** von `opk
  aktualisieren` bis `installiert explorer`. Für `hallo` (34 KiB) fiel das
  nie auf. Wo die Zeit hingeht, ist nicht gemessen — Verdacht in dieser
  Reihenfolge: SHA-512 über das ganze Paket für die Ed25519-Prüfung,
  SHA-256 für die Inhaltsprüfung, und das Schreiben von 570 KiB durch OFS
  mit Journal. Eine Runde, die das misst, hätte drei Zahlen statt einer
  Vermutung.
* **Der Puffer ist immer noch statisch.** 2 MiB sind für die heutigen
  Programme reichlich und für ein Paket mit einem Bild oder einer Schrift
  darin knapp. Der richtige Bau liest in Stücken und prüft dabei — dann
  gäbe es die Grenze gar nicht. Das ist keine kleine Änderung: die Zusage
  „geprüft, **bevor** etwas auf die Platte kommt" hängt daran, dass alles
  im Speicher liegt.
* **`fbhold` meldet sich in diesem Zweig nicht.** `gfx nocursor fbhold`
  zeichnet den Bildschirm und spiegelt die Konsole, aber `fb: hold`
  erscheint nicht in der seriellen Leitung, obwohl `fb.parse` das Wort
  kennt und `M_GFX` aus demselben Wort greift. Damit ist der Weg „Shell auf
  dem Bildschirm fotografieren" hier nicht benutzbar; die Bilder dieser
  Runde entstehen deshalb über den **Fensterserver** (`wmshell wmdauer`).
  Das ist ein Befund über `hidweg`, nicht über diese Runde, und er ist
  nicht behoben — er ist gemessen und aufgeschrieben.
* **Das Terminalfenster hängt an der Konsole.** Alles, was Kern,
  Schreibtisch und Taskleiste auf die serielle Leitung schreiben, steht
  auch im Fenster. Ein Bild vom Terminal zeigt deshalb neben der Antwort
  des Befehls auch Zeilen, die niemand angefordert hat. Für ein
  Bildschirmfoto ist das lästig; für einen Laden mit eigener Oberfläche
  wäre es keine Frage mehr.
