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
| `tools/laden/apps.tab` | 1 | beide |
| `tools/laden/build.sh` | 1 | GUI/CLI-Listen vereinigt |

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

`kernel/usb.fi` beide Importe, `tools/laden/build.sh` Vereinigung
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
faellt das nicht auf:** `tools/haertung/run.sh` prueft den Kern, nicht
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
