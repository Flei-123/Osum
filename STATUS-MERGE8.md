# STATUS MERGE-8 — sechs Zweige auf einen Stand

Grundlage: `merge7` = `b73b04d` (45/68 Abschnitte gruen, 4812 Zusagen).
Arbeitsbaum `/root/osum-merge8`, Zweig `merge8`.

## Die Tabelle

| # | Zweig | Konflikte | Pruefstand vorher (Zweig) | nachher (merge8) |
|---|-------|-----------|---------------------------|------------------|
| 1 | `praesenz` (mit `konto`, `sync`) | **keine** (Textverschmelzer) | konto 107/0, praesenz 36/0 | **konto 107/0, praesenz 36/0** |
| 2 | `alltag` | 11 Textstellen in 9 Dateien + 33 PNG + 2 STILLE Nummern | alltag 45/0 | **alltag 45/0** |
| 3 | `ton2` | 2 Dateien + 1 STILLE Widget-Nummer | ton2 25/0 | **ton2 25/0** |
| 4 | `vsync` | 1 (`kgui.fi`) | vsync 14/0 | **vsync 14/0** |
| 5 | `haertung2` | 3 Dateien + 1 STILLE kdata-Kollision | haertung 19/0 | **haertung 19/0** |
| 6 | `wlan2` | 3 Dateien + 3 STILLE Abschnittsnummern | wlan 185/0, wlan2 43/0 | **wlan 185/0, wlan2 43/0** |

Alle sechs Zweige binden denselben Uebersetzer (`vendor/firn/COMMIT`
a751b3d) — kein Uebersetzerdrift zwischen den Zweigen.

## Die Invarianten nach JEDEM Merge

`/root/merge8-pruef.sh` prueft nach jedem Schritt: kdata-Karte,
Syscall-Doppelbelegung Kern und libc, `K_*` (Widget-Arten), `R_*`
(Reiter), `KDATA_SIZE` an beiden Stellen.

| nach | kdata | Syscalls Kern/libc | K_* | R_* | Modusnamen |
|------|-------|--------------------|-----|-----|------------|
| Basis merge7 | 104 Bereiche, **0 Kollisionen** | 156 / 158 / 156 | 15 | 38 | 173 |
| praesenz | 104, **0** | 156 | 15 | 39 | 173 |
| alltag | 104, **0** | 158, Kern 160 / libc 158 | 17 | 39 | 173 |
| ton2 | 104, **0** | 158 | 17 | 39 | 173 |
| vsync | 104, **0** | 158 | 17 | 39 | **181** |
| haertung2 | **105**, **0** | 158 | 17 | 39 | 182 |
| wlan2 | 105, **0** | 158 | 17 | 39 | 182 |

`KDATA_SIZE` steht durchgehend auf `0x100000` in `kstate.fi` UND
`kernel/arch/x86_64/boot.s`. Kein `OSUM_*`-Aufruf steht nur auf einer
der beiden Tafeln (Kern 160, libc 158; die zwei Kern-eigenen sind
`SYS_MARK`/`SYS_LEAVE`, vorbestehend, eigener Nummernraum aus Runde 59).

## Die Konflikte, Datei fuer Datei

### 1. `praesenz` — nichts zu tun

Sechs Commits, der Textverschmelzer kam allein durch. Reiter wie
angekuendigt: `R_KONTO` 8, `R_SYNC` 9, `R_ANZ` 10 (`settings.fi`).

### 2. `alltag` — die vorbereitete Aufloesung, und was sie NICHT kannte

`tools/alltag/probe7-aufloesung.py` (aus Runde ALLTAG) loest die sechs
Dateien, die schon die Probe gegen `merge7` gesehen hat:

| Datei | Stellen | Regel |
|---|---|---|
| `kernel/proc.fi` | 1 | merge7-Seite (Arena 192 MiB deckt ALLTAGs 10 MiB mit ab) |
| `kernel/sys.fi` | 3 | Vereinigung, beide, beide + Klammer |
| `lib/libc/kcall.fi` | 2 | Vereinigung, beide |
| `kernel/user/wlib.fi` | 6 | Vereinigung, beide, KEY_SDEL, 3x beide |
| `tools/loader/apps.tab` | 1 | beide |
| `tools/loader/build.sh` | 1 | GUI/CLI-Listen vereinigt |

Dazu die zwei Klammern in `wlib.fi` von Hand (`on_down` K_LEINWAND,
`on_up` LE_UP) — ohne sie: `'fn' is only allowed at top level`.

**Fuenf Konflikte MEHR als die Probe**, weil `praesenz` jetzt darunter
liegt (die Probe lief gegen reines merge7):

| Datei | Aufloesung |
|---|---|
| `kernel/user/settings.fi` | beide Seiten — KONTO-Schluessel und ALLTAGs Sperr-Leerlauf sind verschiedene Zusaetze an derselben Stelle |
| `locale/de/messages`, `locale/en/messages` | beide Seiten (KONTO/SYNC + ALLTAG) |
| `tools/k15/run.sh` (2 Stellen) | **8192 Bloecke (ALLTAG)** statt 6144 (MERGE-7) — beide Runden haben aus DEMSELBEN Grund vergroessert, die groessere Zahl deckt die kleinere mit ab |
| 33 PNG unter `docs/` | Fassung aus `alltag` (neuer, zeigt die verschmolzene Oberflaeche) |

**Und die zwei STILLEN Nummern**, die kein Textverschmelzer sieht:

1. `SYS_OSUM_SPERRE` 1850 (ALLTAG) lag auf `SYS_OSUM_AUDGET` 1850
   (Runde TON). Der Sperrbildschirm haette den Ton gefragt.
   **1850 -> 1870** an drei Stellen (`sys.fi`, `kcall.fi`, `lock.fi`).
2. `K_BILD` 15 (ALLTAG) lag auf `K_LEINWAND` 15 (CERTUS).
   **K_BILD 16, K_SLIDER 17.**

### 3. `ton2` — zwei Kollisionen, eine davon erst vom Pruefer gefunden

**`kernel/user/taskbar.fi`:** TON-2 bringt `F_SND`, SYSTEMBUS hat
`F_NOTI` — beide haben von 1 an weitergezaehlt, jeder Zweig fuer sich
richtig. Die Statusfelder sind ein zusammenhaengender Bereich `0..F_N`,
den zwei Anordnungsketten ablaufen. Jetzt: NET 0, SND 1, BAT 2, CLK 3,
NOTI 4, `F_N` 5.

**`test.sh`:** TON-2 kam als Abschnitt 42 — die Nummer gehoert seit
MERGE-7 dem Zeichenweg (GLYPHE). Jetzt 46.

**`kernel/user/wlib.fi` — DEN HAT DER PRUEFER GEFUNDEN, nicht git:**
`K_SLIDER = 13` (TON-2) auf `K_CARD = 13` (SOFTUI). Beim Nachsehen war
es mehr als eine Nummer: **TON-2 und ALLTAG haben BEIDE einen
Schieberegler ins Framework gebaut.**

* TON-2: `slider(txt, wert)`, 0..100 Prozent, `K_SLIDER` 13
* ALLTAG: `slider(min, max, wert)`, `K_SLIDER` 17, dazu `paint_slider`,
  `slider_setz`, Klick- und Ziehweg

Firn nimmt die spaetere Bindung, TON-2s 13 war also schon tot — aber
eine tote Nummer, die auf `K_CARD` zeigt. Gemessen statt vermutet:
TON-2s `slider()` hat auf dem ZWEIG SELBST keinen einzigen Aufrufer
(`git grep` ueber alle `.fi` von `ton2`), ALLTAGs hat einen
(`viewer.fi:524`, `wlib.slider(10, 800, 100)` fuer den Zoom). Also EIN
Regler, der von ALLTAG; TON-2s `const`, `slider`, `slider_step`,
`paint_slider`, `slider_set_x` und die zwei toten Zweige in
`on_down`/`on_move` sind heraus.

### 4. `vsync` — ein Konflikt

`kernel/kgui.fi`: ALLTAGs `sperre_wache` und VSYNCs Bildgrenze haengen
beide in der Halteschleife von `wm_hold`. Beide behalten, **die Wache
zuerst** — sie kehrt ohne stehende Sperre sofort zurueck und darf die
Reihenfolge des Takts nicht verschieben (weiterstellen -> zeichnen ->
EINMAL uebertragen, genau der Punkt der Runde VSYNC).

### 5. `haertung2` — die STILLE kdata-Kollision, Wort fuer Wort wie in MERGE-7

HAERTUNG-2 legt den Pfadpuffer je Kern (`NAMEK_OFF`, acht Seiten) auf
**0xC0000** und laesst `kdata` dafuer auf 0xE0000 wachsen. Auf SEINER
Grundlage (merge6) war 0xC0000 die erste freie Adresse — auf merge7
liegt dort der **BUS** (SYSTEMBUS, 0xC0000..0xC8000). Keine gemeinsame
Zeile, also kein Wort vom Textverschmelzer.

    KDATA_SIZE  0x100000 BEHALTEN (merge7), NICHT die 0xE0000 des Zweigs
                -- die kleinere Zahl haette BUS/LOG/TON abgeschnitten.
    NAMEK_OFF   0xC0000 -> 0xE8000, in die 96 KiB, die MERGE-7 hinter
                dem Ton ausdruecklich frei gelassen hat.

Belegung ab 0xB0000 danach, lueckenlos und ueberschneidungsfrei:

    0xB0000 WIGST | 0xB8000 SCANB | 0xC0000 BUS | 0xC8000 LOG
    0xD8000 AUD/HDA/HDAR/HDAB/MIX/AUDB/BLKC | 0xE0000 BLKD
    0xE8000 NAMEK (neu) | 0xF0000..0x100000 frei (64 KiB)

`kernel/uprog.fi`: beide Seiten — `P_FUZZ` 54 war frei, SYSTEMBUS hat
60..63. `boot.s`: die groessere Zahl.

### 6. `wlan2` — drei Konflikte, dazu drei stille Abschnittsnummern

`kernel/usb.fi` beide Importe, `tools/loader/build.sh` Vereinigung
(+ `wlan`), `test.sh` WLAN kam als 42 (gehoert GLYPHE).

**Was der Textverschmelzer NICHT gesehen hat:** nach dem Zusammenfuehren
trugen VIER Abschnitte die **43** — SYSTEMBUS, VSYNC, HAERTUNG-2 und
WLAN-2s zweiter Lauf; jeder Zweig hatte auf seiner eigenen Grundlage
recht. Endstand: 43 SYSTEMBUS (behaelt), 46 TON-2, 47 WLAN, 48 VSYNC,
49 HAERTUNG-2, 50 WLAN-2.

## Zwei Fehler, die erst diese Runde erzeugt oder sichtbar gemacht hat

### 1. ECHTE REGRESSION, von mir gebaut: die Statusfelder hatten 4 Plaetze

Gefunden mit dem Rezept aus `STATUS-ALLTAG.md` (`glyphe` mit
aufgehobenen Mitschnitten): **32 von 32 Laeufen mit `-smp 4`**

    panic: index out of bounds in '[u64; 4]' at kernel/user/taskbar.fi:2165:18

Das ist meine eigene Aufloesung aus Schritt 3: `F_N` von 4 auf 5
gesetzt, aber die TAFELN dahinter stehen gelassen. Jede wird mit dem
Feldindex angesprochen; Index 4 in einer Tafel mit vier Plaetzen ist
die Panik.

    f_x f_y f_w f_h f_lines prev_h   [u64; 4]  -> [u64; 5]
    f_txt                            [u8; 256] -> [u8; 320]
    f_full                           [u8; 128] -> [u8; 160]

Danach **0 von 40** Laeufen mit `-smp 4` und `-smp 8`.

**Damit ist zugleich die offene Frage aus Runde ALLTAG beantwortet:**
die dortige 1 Panik in 40 `glyphe`-Laeufen, deren Text fehlte, ist
NICHT dieselbe — diese hier trifft 32 von 32 und hat einen anderen
Text. Sie ist in dieser Merge-Runde entstanden.

### 2. HAERTUNG-2s Flicken 0003: ein `break` ohne Schleife

Der Abbildbau brach ab:

    error: 'break' is outside a loop
      --> vendor/firn/lib/tls/tls.fi:473:13

Flicken 0003 laesst die Aufrufer von `buf_reserve` den Rueckgabewert
pruefen; in `write_record` ist der Fehlerausgang als `break`
geschrieben — die Funktion hat aber keine Schleife. **Auf dem Zweig
faellt das nicht auf:** `tools/hardening/run.sh` prueft den Kern, nicht
die TLS-Bibliothek des Uebersetzers, und der Kernbau bindet `lib/tls`
nicht ein. Erst der Stick-Abbild-Bau (der `fetch-firnc.sh` mit den
Flicken faehrt) zeigt es.

Gemeint war "den Rest dieses Zweigs ueberspringen" — hier ein `if ok`,
denn `buf_free(&out)` am Ende der Funktion muss in JEDEM Fall laufen
(ein `return false` waere ein Leck gewesen). Geaendert wurde die Quelle
UND der Flicken (sonst kommt der Fehler beim naechsten
`fetch-firnc.sh` zurueck); der Flicken ist aus dem echten `diff` gegen
`lib/.roh/` neu gebaut und mit `patch --dry-run` geprueft.

## Nebenbefund aus ALLTAG, eingebaut

`test.sh` las bei `OSUM_NUR` ein altes `.netto.$i` aus einem frueheren
Lauf (darum stand bei `update` "davon 1442,242 s Warten auf die
Netzsperre", obwohl die Maschine frei war). `rm -f "$WORK/.netto.$i"`
am Anfang von `abschnitt_ausfuehren`.

## Das Abbild

    /root/abbilder/orientos-usb-20260908-<hash>.img   118 MiB
    (+ .sha256)

Gebaut mit `JARVIS_CONF=assets/jarvis/rechte-justin.conf`, also mit
Justins ECHTEM Server vorbelegt (`server = 192.168.1.54:8443`,
`servername = jarvis.fleitec.com`) — im rohen `.img` nachgewiesen.

**Der Uhrentest (UHRWERK), ohne jede Eingabe:** Abbild in QEMU
gestartet, Schreibtisch nach 30 s, Bild bei 0 s und nach 90 s.

    UHR RTC 12:20:00 KRN 14:19:59 TZ 120 D 08.09
    UHR RTC 12:21:38 KRN 14:21:38 TZ 120 D 08.09

Die Uhr in der Leiste ist auf beiden Bildern lesbar und steht auf
12:20 bzw. 12:21 (Ortszeit, TZ 120 = CEST), das Datum unveraendert
08.09. Dazu `taskbar: round=3201 ... px=5222400 soll=5222400 null=0`
und **0 Paniken** im seriellen Mitschnitt.

## Volllauf 1 + Fixes (08.09.2026)

test.sh, OSUM_JOBS=4: **50 von 74 Abschnitten gruen, 5066 Zusagen**.
Gegen merge7 verglichen: alles gleich oder besser -- vier echte
Regressionen, alle behoben und einzeln nachgemessen:

| Abschnitt  | Volllauf | merge7 | Ursache | Fix | solo danach |
|------------|----------|--------|---------|-----|-------------|
| tiling     | 55/12 | 68/0  | `find()` sucht Teilzeichenketten: `tilefuzz` enthaelt `fuzz` -> Aufruf-Fuzzer (HAERTUNG-2) mit 100000 Runden -> QEMU rc=124 | `find_wort()` in kernel/kmain.fi, fuer `fuzz` benutzt | **68/0** |
| netview    | 121/29 | 182/13 | Zustandsabbilder fest 8192 Bloecke, Programme gewachsen -> mkfs failed | 16384 Bloecke | **182/13** |
| themestore | 78/3  | 81/0  | (a) Klick 680,51 traf bei zehn Reitern "Abgleich" statt "Vorlagen" (b) Konten-Seite: 17 Elemente links, Ende 632 > 542 | (a) click=548,41 (b) Geheimnis/Bereich nach rechts | **81/0** |
| userland   | 90/1  | 91/0  | Lastartefakt (QEMU exit 0 statt 21) | keiner noetig | **91/0** |

Besser als merge7: ota 107/0 (104/4), k15 232/20 (228/24), display 142/3,
k18 170/0, gfx 76/0, init 78/0, usbimg 37/11, vielkern 36/4.
Neu und gruen: praesenz 36/0, vsync 14/0.
umlaut bleibt 5 rot -- in merge7 identisch, keine Regression.

Bestaetigungslauf: systemd-Unit `m8-test2`, Log /tmp/m8-test2sh.log.

## Volllauf 2 (Bestaetigung) + Endtafel gegen MERGE-7

`test.sh`, OSUM_JOBS=4, Unit `m8-test2`, Log /tmp/m8-test2sh.log:

**56 von 74 Abschnitten gruen, 18 rot, 5138 Zusagen.**
(Volllauf 1 davor: 50/74. Die vier Fixes aus Volllauf 1 -- tiling,
netview, themestore, userland -- sind alle gruen geblieben.)

Der Lauf stand unter Fremdlast: Lastmittel 8-10, bis zu 7 fremde QEMUs
anderer Runden. Deshalb ist jeder rote Abschnitt EINZELN gegen
STATUS-MERGE7.md gestellt und im Zweifel solo nachgefahren.

### Die Endtafel: alle 18 roten Abschnitte

| Abschnitt | merge7 | merge8 (Volllauf) | Urteil |
|-----------|--------|-------------------|--------|
| `k15`       | 228/24 | **232/20** | besser als merge7 |
| `display`   | 141/4  | **142/3**  | besser als merge7 |
| `theme`     | 90/1   | 90/1   | vorbestehend, identisch |
| `icons`     | 25/0   | 23/2   | **REGRESSION -> gefixt, jetzt 25/0** |
| `paint`     | 32/1   | 32/1   | vorbestehend, identisch |
| `netview`   | 182/13 | 182/13 | vorbestehend, identisch |
| `powermon`  | 119/2  | 119/2  | vorbestehend, identisch |
| `server`    | 21/2   | 21/2   | vorbestehend, identisch |
| `usbimg`    | 36/12  | **37/11** | besser als merge7 |
| `umlaut`    | 43/5   | 43/5   | vorbestehend, identisch |
| `softui`    | 21/3   | 21/3   | vorbestehend, FAIL-Menge bitgleich |
| `hid`       | 56/1   | 56/1   | vorbestehend, identisch |
| `modul`     | 72/2   | 72/2   | vorbestehend, identisch |
| `stick`     | 20/22  | 20/22  | vorbestehend, identisch |
| `vielkern`  | 35/5   | **38/2**  | besser als merge7 |
| `werkzeug`  | 30/4   | 23/11  | Lastflake -> solo **31/3**, Teilmenge von merge7 |
| `glyphe`    | 27/2   | 28/1   | besser; solo 27/2 = merge7-Menge |
| `systembus` | 34/1   | 34/1   | vorbestehend, identisch |

**Kein einziger Abschnitt ist schlechter als merge7 -- ausser `icons`,
und der ist behoben.** Sechs sind besser.

### Die Einzelnachfahrten (ruhige Maschine, Mitschnitte aufgehoben)

* **`glyphe` solo: 27/2**, rc=1 -- FAIL-Menge **identisch** mit merge7
  (`diff` leer). Beide FAILs sind GEGENPROBEN, die absichtlich einen
  Fehler provozieren sollen und ihn nicht sehen (Abschnitt 5
  `glyphtafelfrei`, Abschnitt 8 `glyphblind`) -- Schwaechen des
  Testaufbaus, keine Kernfehler.
  **Der ALLTAG-Panikfall ist weg**: Abschnitt 7 meldet
  `-smp 4: 20 Laeufe, 0 mit Panic` UND `-smp 8: 20 Laeufe, 0 mit Panic`.
  In Runde ALLTAG war das 1 von 40 mit `-smp 8` (apic.fi:452).
  Mitschnitt: `.test-work/glyphe-solo.log`.
* **`systembus` solo: 34/1**, rc=1 -- derselbe einzelne FAIL wie merge7,
  wortgleich ("der Editor ist nie gestartet -- die Tasten kamen nicht
  an"). Auch ohne Fremdlast reproduzierbar, also **kein** Lastflake,
  aber auch keine Regression. Mitschnitt: `.test-work/systembus-solo.log`.
* **`werkzeug` solo: 31/3** (Volllauf 23/11) -- die acht Maus- und
  Panel-Fehler waren reiner Lastflake. Die drei verbliebenen sind eine
  **echte Teilmenge** von merge7s vier FAILs; merge7s
  "gemessene Beschriftungen im Bild: 2" ist in merge8 sogar gruen (4).
  Mitschnitt: `.test-work/werkzeug-solo.log`.
* **`icons` solo: 24/1** (Volllauf 23/2) -- der Font-FAIL war Lastflake,
  der Tooltip-FAIL blieb reproduzierbar. Siehe Regression unten.
  Mitschnitte: `.test-work/icons-solo.log`, `.test-work/icons-solo2.log`.

### Die einzige echte Regression: `icons` (behoben)

    icons=49 tips=45 missing=4 extra=0
    no tooltip: icon.volume.high / .low / .muted / .zero

Runde TON-2 hat vier Lautstaerkesymbole nach `assets/icons/icons.map`
gelegt (E010..E013), aber keine Sprechnamen in die Kataloge. `merge7`
kennt die vier Symbole gar nicht, deshalb war der Abschnitt dort gruen.
`tools/icons/run.sh` Abschnitt 3 haelt jedes Symbol gegen
`locale/en/icons` und verlangt zusaetzlich, dass der deutsche Katalog
GENAUSO viele traegt (`de == tips`) -- also mussten BEIDE ergaenzt
werden, sonst kippt die dritte Zusage.

FIX: vier `.tip`-Zeilen in `locale/en/icons` und `locale/de/icons`.
Danach `icons=49 tips=49 missing=0 extra=0 de=49`, Abschnitt
**25/0, rc=0** -- wieder auf merge7-Stand.

### Die beiden geforderten Nachweise

* **Zeitgeber-Wachhund (MERGE-7, `sched.fi:timer_tot`) ist in merge8
  wirklich drin.** `kernel/cpu.fi` traegt `C_TOTMARKE`/`C_TOTZEIT`/
  `C_TOTZAHL` auf 176/184/192, `timer_tot()` arbeitet ueber
  `cpu.here`/`cpu.get`/`cpu.set` je Kern statt ueber `static mut`, und
  die Haertung `t > zeit` vor der Subtraktion steht ebenfalls. Belegt
  durch 0 Panics in 20 Laeufen `-smp 8` (siehe oben).
* **SYSTEMBUS' kdata-Bereich stimmt nach der ALLTAG/PRAESENZ-
  Neuaufteilung noch.** `tools/kernel/memmap.py`: *105 Bereiche in
  0x100000 Oktetten kdata, 11 Vektoren, 182 Modusnamen in 16 Woertern,
  **0 Kollisionen***. `BUS_OFF` steht weiterhin auf 0xC0000 (MERGE-7
  hatte es von 0xAC000 wegverschoben), kollidiert also nicht mit
  `WIGST_OFF` 0xB0000..0xB8000 oder `SCANB_OFF` 0xB8000..0xC0000.

### Werkzeug-Nachruestung

`tools/glyph/run.sh`, `tools/systembus/run.sh` und `tools/icons/run.sh`
verstehen jetzt -- wie `tools/toolbench/run.sh` mit `WZ_OUT` und
`tools/tiling/run.sh` mit `TILING_KEEP` -- die Umgebungsvariablen
`<RUNDE>_KEEP=1` und `<RUNDE>_TMPD=<dir>`, damit das Arbeitsverzeichnis
nach einem roten Lauf zum Nachsehen stehen bleibt.
