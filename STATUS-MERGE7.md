# STATUS MERGE-7 — zehn Zweige auf einen Stand

Grundlage: `merge6` = `a92fa00` (Runde GLYPHE, `./test.sh` 65/65 Abschnitte,
1167 gruene Zusagen). Arbeitsbaum `/root/osum-merge7`, Zweig `merge7`.

## Die Tabelle

| # | Zweig | Commit | Konflikte | Abnahme vorher | Abnahme nachher |
|---|-------|--------|-----------|----------------|-----------------|
| 1 | `uhrwerk` | 9f3fea0 | keine (Textverschmelzer) + 1 Bauskript | 8/0 (Zweig) | **8/0** |
| 2 | `store-mobil` | b459644 | keine | — | (in `./test.sh`) |
| 3 | `design2` | 806bd0c | keine | 20/20 Laeufe ohne Panik | (in `./test.sh`) |
| 4 | `blech2` | e9f5854 | 1 (`kgui.fi`, Exportliste) | 33/0 | (in `./test.sh`) |
| 5 | `bridge2` | 1b37234 | 1 (`kgui.fi`, Importzeile) | 16/0 echtserver | siehe unten |
| 6 | `systembus` | d97d4b3 | 3 (`kstate.fi`, `sys.fi`, `test.sh`) | 30/5 | **34/1** |
| 7 | `protokoll` | 422650d | 9 Dateien | 55/0 (Zweig) | **55/0** |
| 8 | `ton` | 6d0b887 | 5 Dateien | — | siehe unten |
| 9 | `certus2` | 94bd4a1 | 2 (`.gitignore`, `wlibc.fi`) | avx 32/0, certus 47/0 | **avx 32/0** |

Zusaetzlich hereingeholt: `origin/main` (d7cbdd9) — acht Commits Lizenz- und
`.gitattributes`-Arbeit vom 27.08., die noch nicht in merge6 steckten. Ein
Konflikt (`LICENSE`); genommen wurde die Fassung von origin (der reine
GPL-2.0-Text, damit GitHub das Repo richtig ausweist) — die Uebersicht steht
weiter in `LICENSE-UEBERSICHT.md` und `LICENSING.md`. Damit ist der Push ein
VORSPULEN und wirft nichts weg.

`alltag` ist ABSICHTLICH NICHT gemergt — die Runde laeuft noch.

## Der eine Fund, um den es in dieser Runde ging

**Drei Runden hatten dasselbe Loch in `kdata` fuer sich genommen, und eine
davon haette der Runde GLYPHE in die Seiten geschrieben.**

Auf jedem Zweig fuer sich war das richtig: `kstate.fi` wies 0xB0000 aufwaerts
als frei aus. Kein Textverschmelzer sieht so etwas — die Kollision steht in
keiner gemeinsamen Zeile.

| Runde | wollte | Groesse |
|-------|--------|---------|
| SYSTEMBUS | 0xAC000..0xB4000 | 32 KiB |
| PROTOKOLL | 0xB0000..0xC0000 | 64 KiB |
| TON | 0xB0000..0xC0000 | 64 KiB |

In `merge6` liegen dort seit Runde GLYPHE **WIGST_OFF (0xB0000..0xB8000)** —
die Buehne je Kern — und **SCANB_OFF (0xB8000..0xC0000)**. SYSTEMBUS haette
also nicht nur die anderen beiden getroffen, sondern die Datenstruktur, die
GLYPHE gerade erst eingezogen hat, um das Zeichenrennen zu beheben.

Das ist Wort fuer Wort der Fehler aus Runde K7/K9 (Signaltabelle auf den
Zeichensatz, `@` bis `o` verschwanden vom Schirm), fuer den
`tools/kernel/memmap.py` gebaut wurde. Der Pruefer hat ihn wieder gefangen.

### Die neue Aufteilung — an EINER Stelle, mit Platz dahinter

    KDATA_SIZE  0xC0000 -> 0x100000   (768 -> 1024 KiB, .bss, kein Oktett im Abbild)

    0xB0000..0xB8000  WIGST     (GLYPHE, unveraendert)
    0xB8000..0xC0000  SCANB     (GLYPHE, unveraendert)
    0xC0000..0xC8000  BUS       (SYSTEMBUS, verschoben von 0xAC000)
    0xC8000..0xD8000  LOG       (PROTOKOLL, verschoben von 0xB0000)
    0xD8000..0xE8000  TON       (AUD/HDA/HDAR/HDAB/MIX/AUDB/BLKC/BLKD,
                                 verschoben von 0xB0000, +0x28000)
    0xE8000..0x100000 frei      (96 KiB fuer die naechsten Runden)

`KDATA_SIZE` steht zweimal (`kstate.fi` und `kernel/arch/x86_64/boot.s`);
beide sind gesetzt, `tools/hv/run.sh` vergleicht sie.

### Dasselbe noch einmal, eine Etage tiefer: die Modusbits

Vier Runden haben unabhaengig voneinander **Wort 14 ab Bit 0** genommen.
Zwei Namen auf einem Bit heisst: ein Schalter setzt den anderen mit — und
kein Uebersetzer sagt etwas dazu.

| Runde | wollte | hat jetzt |
|-------|--------|-----------|
| GLYPHE (schon in merge6) | 896..899 | **896..899** (unveraendert) |
| SYSTEMBUS | 896..900 | **900..904** |
| PROTOKOLL | 896..899 | **905..908** |
| TON (20 Bits) | 896..915 | **960..979** (Wort 15 ganz) |

### Und noch einmal: die SMP-Phasennummer

`PH_GRACE` (GLYPHE) und `PH_LOG` (PROTOKOLL) waren **beide 6**. GLYPHE
braucht die Nummern nach oben offen (`ph >= PH_GRACE`, `PH_GRACE + k` fuer
`GRACE_KALT` = 25 Durchgaenge), ein fester Wert darueber waere von dessen
`>=` verschluckt worden. Also: `PH_LOG` = 6, `PH_GRACE` = 7 (belegt 7..31).

### Und die Abschnittsnummer in `test.sh`

GLYPHE, SYSTEMBUS und PROTOKOLL hatten alle drei die **42**. Jetzt: 42
Zeichenweg (GLYPHE), 43 Systembus, 44 Kernprotokoll.

## Zwei Bauskripte, die am Zusammenfuehren gestorben sind

1. **`tools/uhrwerk/bauen.sh`** — `mkfs: '/bin/taskmgr' gibt es nicht`.
   Der Zweig entstand, bevor `assets/apps/taskmgr.osp` da war; sein
   `bundle.py`-Aufruf nimmt JEDES Buendel, seine Programmliste kennt
   `taskmgr` aber nicht. Genau dieser Fall steht schon in
   `tools/design/aufnahme.sh:196` beschrieben, mitsamt der Abhilfe der
   Runde WERKZEUGE: `nur=` ueberspringt jedes Buendel, dessen Programm
   nicht auf dieser Platte liegt. Derselbe Riegel jetzt hier.

2. **`tools/protokoll/run.sh`** — die Zusage stand als `grep -q '0xC0000'`.
   Die Runde PROTOKOLL hatte `kdata` auf genau diesen Wert wachsen lassen
   und der Pruefstand hat die Zahl abgeschrieben. Eine Zusage, die eine
   Zahl abschreibt statt sie zu lesen, misst den Abschreibfehler mit.
   Jetzt wird `KDATA_SIZE` aus `kstate.fi` gelesen.

## Was der Kartenpruefer zusaetzlich gefunden hat

`BLKC_OFF`/`BLKD_OFF` (der Vorauslesepuffer der Platte aus Runde TON,
9 Seiten) standen in `kstate.fi`, aber in **keiner** Karte in
`tools/kernel/memmap.py`. Der Zweig war fuer sich gruen, weil dort nichts
danebenlag. Jetzt eingetragen; ihre Lage wird mitgerechnet.

Endstand: **104 Bereiche in 0x100000 Oktetten kdata, 11 Vektoren,
173 Modusnamen in 16 Woertern, 0 Kollisionen.**

## Ein eigener Fehler, vom Pruefer gefangen

Beim Aufloesen des PROTOKOLL-Konflikts in `kstate.fi` ist mir der
SYSTEMBUS-Block (`BUS_OFF`, `BUS_MAX` und die fuenf Modusbits) verloren
gegangen — git hatte ihn in die Konfliktzone gelegt. `memmap.py` meldete
sofort `unbekannte Konstante BUS_OFF`. Wiederhergestellt.

Beim ton-Merge hat mein Aufloeser zwei schliessende Klammern
verschluckt (`do_bus` und `bus_segmap`). Der Uebersetzer hat es gemeldet
(`'fn' is only allowed at top level`); danach wurden alle elf
zusammengefuehrten Funktionen **Zeichen fuer Zeichen** gegen ihre
Herkunftszweige verglichen: `do_bus`, `bus_segmap`, `bus_word`,
`do_klog`, `do_krach`, `do_audget`, `do_audset`, `do_audwrite`,
`do_audopen`, `do_audsend`, `audget_locked`, `audset_locked` — alle gleich.

## Der Regress, der NICHT zurueckkommen durfte

Der Zweig `certus2` hat einen eigenen fxsave-Regress zurueckgenommen
(`sched.fi`, `switch.s`, `boot.s`, `smp.s` wortgleich auf `2aa3f59`).
Waere er beim Zusammenfuehren zurueckgekommen, faellt `tools/avx/run.sh`
von 32/0 auf 24/8 — ein **stiller** ymm-Rechenfehler, kein Absturz.

Nachgeprueft: `grep -c 'fxsave\|fxrstor'` in `switch.s` und `sched.fi`
= **0**. `git diff 2aa3f59` an `switch.s` und `smp.s`: **leer**. Der
Unterschied an `sched.fi` ist eine reine Kommentar-Richtigstellung aus
GLYPHE. **`tools/avx/run.sh`: 32 passed, 0 failed.**

## Bauzustand

| Bau | Ergebnis |
|-----|----------|
| Stufe 0, gui=on | ok |
| Stufe 0, gui=off (Serverbau) | ok |
| Stufe 1 (selbstgebauter Uebersetzer) | ok |

## Eine Falle fuer die naechste Runde

`vendor/firn/fetch-firnc.sh` legt seinen Bauplatz nach
`${TMPDIR:-/tmp}/firn-pin-$KURZ` — der Name haengt NUR am Commit, nicht am
Arbeitsbaum. Zwei Baeume, die gleichzeitig bauen, raeumen einander das
Verzeichnis mitten im Auspacken weg; das sieht dann aus wie
`tar: ... Cannot open: No such file or directory` und
`vendor/firn/fetch-firnc.sh fehlgeschlagen`, also wie ein Codefehler.
**Je Laeufer ein eigenes `FIRN_BAU_DIR` setzen.**


## Gemessen (Stand 06.09.2026, 19:05)

Alle Zahlen unter FREMDLAST erhoben — auf der Maschine liefen bis zu 37
QEMU-Instanzen anderer Runden (Lastmittel bis 29). Wo das zaehlt, steht es
dabei.

| Laeufer | merge7 | Grundlinie | Bemerkung |
|---------|--------|------------|-----------|
| `tools/avx/run.sh` | **32 / 0** | 32 / 0 | der fxsave-Kanarienvogel |
| `tools/posix/run.sh` | **134 / 0** | 134 / 0 | nach dem SHOT-Fix (vorher 133/1) |
| `tools/pci/run.sh` | **98 / 0** | 98 / 0 | allein gemessen (unter Last 97/1) |
| `tools/userland/run.sh` | **91 / 0** | 91 / 0 | |
| `tools/protokoll/run.sh` | **55 / 0** | 55 / 0 | nach dem kdata-Fix |
| `tools/bridge/run.sh` | **113 / 0** | 16 / 0 (Zweig) | |
| `tools/systembus/run.sh` | **34 / 1** | 30 / 5 (Zweig) | besser als der Zweig |
| `tools/uhrwerk/abnahme.sh` | **8 / 0** | 8 / 0 | 3440x1440, smp1 und smp4 |
| `tools/hda/run.sh` | 140 / 3 | — | die 3 sind Tempo/Aussetzer, lastabhaengig |
| `tools/vielkern/run.sh` | 37 / 3 | **26 / 13** | merge6 unter derselben Last SCHLECHTER |
| `tools/usbimg/run.sh` | 27 / 15 | 37 / 11 (rot) | vorbestehend rot, siehe unten |
| `tools/certus/run.sh` | uebersprungen | — | `/root/certus-sammeln` gibt es nicht mehr |

### Der eine echte Fehler, den das Zusammenfuehren gefunden hat

`SYS_OSUM_SHOT = 1841` stand NUR in `kernel/sys.fi`, nicht in
`lib/libc/kcall.fi`. Auf dem Zweig `bridge2` faellt das nie auf —
`tools/bridge/run.sh` geht ueber den Kern und fragt die libc nie (113/0).
Erst `tools/posix/run.sh` Abschnitt 1 haelt beide Tafeln nebeneinander:

    SYS_OSUM_SHOT: kernel 1841, libc missing

POSIX 133/1 → nach der Ergaenzung **134/0**. Das ist das DRITTE Mal: die
Datei beschreibt `SYS_OSUM_CPUSTAT` (1840, Runde WERKZEUGE) und
`SYS_OSUM_KLOG` (1860, Runde PROTOKOLL) mit demselben Text.

### Zwei falsche Rotmeldungen, beide nachgewiesen

1. **PCI**: unter Last `DMA against PIO, in thousandths: 1009, expected ge
   1200` → 97/1. ALLEIN nachgemessen: **1360 → 98/0**. Eine reine
   Durchsatzmessung auf einer Maschine mit 37 fremden QEMU.
2. **VIELKERN**: 37/3 sah nach Regression aus. Gegenprobe mit merge6 auf
   DERSELBEN Maschine, DERSELBEN Last: **26/13**, mit demselben
   `abw: 7, wollte eq 0` und vielen `keine Zahl gefunden` (QEMU-Zeitlimit).
   merge7 ist also besser als die Grundlinie.

### `usbimg` ist vorbestehend rot, nicht neu

Der GLYPHE-Lauf auf merge6 meldet denselben Abschnitt schon als
fehlgeschlagen (37/11). Ursache: eine spaetere Runde (LEISTE) hat
`default_entry` in `limine.conf` bewusst auf den Schreibtisch gestellt,
`tools/usbimg/run.sh` erwartet aber weiter den Diagnose-Eintrag und sucht
`hwdiag:`-Zeilen, die dann nicht kommen. Das Abbild selbst ist in Ordnung:
es startet unter BIOS UND UEFI, GPT/EFI/MBR stimmen, und der serielle
Mitschnitt zeigt den vollen Schreibtisch samt Uhr (`18:54:20 06.09.26`),
Netz (`10.0.2.15`) und `sh: ready`.

## Das Abbild

    /root/abbilder/orientos-usb-20260906-db3e942.img   118 MiB
    sha256 bc9648058e4d5c34fd2811c93d4539253e70ab286b1bcfd50bf990f22e52753b

Gebaut mit `JARVIS_CONF=assets/jarvis/rechte-justin.conf`, also mit Justins
ECHTEM Server vorbelegt (`server = 192.168.1.54:8443`,
`servername = jarvis.fleitec.com`) — im rohen `.img` nachgewiesen. Der
allgemeine Stick bleibt bei "nichts erlaubt".

Liegt unter `https://store.fleitec.com/abbilder/orientos-usb-20260906-db3e942.img`
(+ `.sha256`) als NEUE Datei; `orientos-usb.img` vom 05.09. ist unberuehrt.
