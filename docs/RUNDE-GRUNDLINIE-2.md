# RUNDE O-GRUNDLINIE-2 — der Volllauf, der den Stand wieder aussagekraeftig macht

**18.09.2026** · Zweig `runde-grundlinie2` auf `main` `8e772f44` ·
Arbeitsbaum `/root/osum-w-grund2` · gemessen mit QEMU/TCG auf dem
LXC-Wirt, `OSUM_JOBS=4` fuer den Volllauf, `OSUM_JOBS=1` fuer jedes
Nachmessen.

---

## Das Ergebnis in drei Saetzen

**Der Volllauf gegen den heutigen `main` steht bei 42 gruen / 33 rot.**
Nach den Reparaturen dieser Runde sind es **46 gruen / 28 rot**. Die Zahl
"40 gruen / 34 rot" vom 12.09. ist damit abgeloest.

**Die zwei Punkte, die der Auftrag nennt — `A-018` und `A-017` — waren
bereits erledigt.** Nicht von dieser Runde, sondern am 14.09. Die
Offenliste war nur nicht nachgefuehrt. Das ist unten belegt, nicht
behauptet.

**Der eigentliche Fund dieser Runde ist ein anderer und wiegt schwerer:
dreizehn Gegenproben haben NICHTS gemessen** und das zum Teil, ohne dabei
aufzufallen. Sie sind repariert; sieben Abschnitte sind dadurch gruen
geworden.

---

## 1. Was `A-018` wirklich war

Die Offenliste sagt: *"der Kern NIMMT eine Aufloesung an, die er ablehnen
muesste — gemessen 2560x1440, obwohl 800x600 gefordert war"*, und
vermutet eine fehlende Pruefung in `kernel/gfx/`.

**Diese Lesart ist falsch, und der Baum sagt selbst warum.** Commit
`529b113c` vom 14.09. traegt den Titel *"A-018: die zwoelf
customres-Fehler waren EINE Ursache -- WIN_SLOTS 8 -> 16"*. Der Hergang:
Rahmenpuffer und `apic.map_device` teilen sich die Fensterplaetze;
Commit `a28cc90`/`758c3c6` hat `WIN_SLOTS` von 8 auf 16 gesetzt, weil
Netz, Platte, USB und Ton sonst keinen Platz mehr bekamen. Seither ist
`map_limit` **29 360 128** statt 14 680 064 Oktette — und 2560x1440
braucht 14 745 600, **passt also**. Der Abschnitt `customres` hatte an
mehreren Stellen fest getippt, dass diese Aufloesung NICHT einblendbar
sei. Rot war die **Erwartung**, nicht der Kern.

### Die Pruefung, die es angeblich nicht gibt

Sie steht in `kernel/gfx/vmode.fi` in `check_custom` und wird von
`set_custom` **vor** jedem Wechsel gerufen — fuenf Schranken
nacheinander: Unsinnszahlen (`MIN_W` 320 … `MAX_W` 8192), Farbtiefe
(`bpp != 32`), Bildspeicher der Karte, Kachelgrenze des Kernels
(`map_limit`) und zuletzt die Karte selbst (`karte_nimmt`, zurueckgelesen
ohne den Modus zu setzen).

### Gemessen, nicht gelesen

`bash tools/customres/run.sh` → **135 Zusagen, 0 Fehler.** Aus dem Log,
Abschnitt 4 ("abgelehnt -- aber MIT Schranke und MIT Zahl"):

```
OK  1. Schranke: dieser Kernel kann es nicht einblenden (Grund 3) (3)
OK     und die genannte Zahl ist GENAU das, was das Bild braucht (33177600)
OK     der Fehlerwert nach aussen ist E_LIMIT (8) und nicht E_NOMODE (8)
OK  2. Schranke: die Register der Karte nehmen die Zahl nicht (Grund 1) (1)
OK     und es steht da, was die Karte STATTDESSEN behalten hat (1360)
OK  3. Schranke: diese Farbtiefe zeichnet der Kernel nicht (Grund 4) (4)
OK     und die Zahl ist die verlangte Tiefe (16)
OK  nach drei abgelehnten Anfragen steht die Tafel unveraendert
OK  das Foto ist 800x600 -- der Bildmodus steht noch (800 600)
OK  Feld 1 ist rot -- der Bildschirm ist NICHT schwarz (0 von 10000 Bildpunkten falsch)
```

Eine unzulaessige Aufloesung wird also **abgelehnt, mit Grund und mit
Zahl**, und der Bildschirm steht danach bildpunktgenau unveraendert da —
das ist die Gegenprobe. Eine zulaessige geht weiter durch: derselbe Lauf
stellt 1400x1050 ein, das in **keiner** Kandidatenliste steht, und das
Foto ist danach 1400x1050 gross.

**`A-017` ebenso:** die Offenliste fuehrt "customres 123/12, powermon
62/54, theme 42/55". Gemessen am 18.09.: **customres 135/0**,
**powermon 121/0**, **theme 97/1**. Zwei der drei sind gruen.

---

## 2. Der eigentliche Fund: dreizehn Gegenproben, die nichts messen

Der Kernel liegt seit dem Trennschnitt in Unterordnern —
`kernel/lib/kstate.fi`, `kernel/gfx/fb.fi`, `kernel/drv/blk/nvme.fi`.
Die Pruefskripte kopierten ihn aber weiter **flach** mit
`cp kernel/*.fi`. Das schlaegt in zwei Stufen durch, und die zweite ist
die gefaehrlichere.

### Stufe 1 — der Pruefer stirbt, und die Zusage zeigt auf den Falschen

`memmap.py` bekam eine Kopie ohne `kstate.fi` und endete mit
`KeyError: 'kstate.fi'`. Die Zusage meldete daraufhin *"der
Kollisionspruefer findet den Fehler dieser Runde NICHT"* — also einen
Fehler im **Prueflingsstand**, obwohl der Pruefer nie angelaufen war. Wer
dem Text glaubt, sucht an der voellig falschen Stelle.

Betroffen: `gfx`, `wm` (**zweimal** — Kollisions- und Vektorpruefer),
`k13`, `k14`, `k15`, `k16`, `k17`, `codec`, `fremdfs`, `krypto`,
`tiling`, `vault`.

### Stufe 2 — der Pruefer schweigt, und alles sieht gruen aus

Bei `vault` und `k17` zielte der `sed` auf Adressen, die es seit Langem
nicht mehr gibt: `HWID_OFF` stand auf `0x5A000`, liegt heute aber auf
`0x72000`; das `EVT_OFF`-Ziel `0x4C000` liegt **ausserhalb** des
K17-Vorrats (`0x50000..0x58000`) und ist damit gar keine Kollision. Der
`sed` griff ins Leere, die Kopie blieb unveraendert und war —
voellig richtig — kollisionsfrei. **Diese Gegenproben meldeten gruen,
ohne irgendetwas geprueft zu haben.** Ein Pruefer, der nie anschlaegt,
ist von einem, der nichts prueft, nicht zu unterscheiden.

### Dieselbe Bauart, ausserhalb der Kernkopien

* **`tools/protocol/run.sh`** las `kernel/$f.fi` fuer `nvme`, `xhci`,
  `usb`, `ahci`, `e1000`, `fs`. **Keine** dieser sechs Dateien liegt noch
  dort. `grep` gab 0 zurueck, und die Zusage meldete *"Treiber, die ueber
  die Log-Schnittstelle sprechen: 0, erwartet 6"*. Gemessen mit den
  echten Pfaden: **6 von 6** (3, 3, 1, 1, 2, 3 Aufrufe).
* **`tools/multiuser/run.sh`** kopierte `sys.fi` flach nach
  `kol/kernel/` und sedete danach `kol/kernel/sys/sys.fi` — einen Pfad,
  den die Kopie nie hatte. Der Waechter fand folgerichtig keine
  Doppelvergabe, und die Runde nannte ihn *"wertlos"*. Er ist es nicht:
  mit richtigem Pfad meldet er sofort
  `KOLLISION: die Nummer 1320 ist 2 mal vergeben`.
* **`tools/k17/run.sh`** zaehlte Modus-Masken nur in `kernel/*.fi`, also
  in der obersten Ebene statt im Baum.

### Was geaendert wurde

Die Kopien spiegeln den **Baum**
(`find . -name '*.fi' -exec cp --parents {} …`), die `sed`-Ziele tragen
den echten Unterordner, tote Adressen sind auf die heutigen Nachbarn
gezogen — und wo eine Gegenprobe etwas verschieben MUSS, prueft jetzt ein
`grep`, dass sie es auch wirklich getan hat. Sonst faellt die Zusage.
Das ist der Teil, der verhindert, dass derselbe Fehler beim naechsten
Verschieben stumm zurueckkommt.

Commits `9508c568` und `523ec846`.

### Belegt an der Sache

```
codec    FINDET Kollision | WMPLUG 0x108000..0x10C000 ueberschneidet CODEC
fremdfs  FINDET Kollision | VGPU   0xF2000..0xF3000   ueberschneidet EXT4
k13      FINDET Kollision | HV (hv.fi:HV_OFF) 0x40000..0x41000 ueberschneidet K13
k14      FINDET Kollision | FB     0x3C000..0x3D000   ueberschneidet K14
k15      FINDET Kollision | WM     0x1E000..0x20000   ueberschneidet WIG
k16      FINDET Kollision | TTF    0x3F000..0x40000   ueberschneidet K16
krypto   FINDET Kollision | WMPLUG 0x108000..0x10C000 ueberschneidet CRYPT
tiling   FINDET Kollision | K18    0x58000..0x59000   ueberschneidet TILE
vault    FINDET Kollision | SHARE  0x6F000..0x72000   ueberschneidet HWID
wm       FINDET Kollision | Vektor 44 haben zwei Namen: VEC_MOUSE, VEC_NVME
```

---

## 3. Was die Reparatur gebracht hat

| Abschnitt | vorher | nachher | was es war |
|---|---|---|---|
| `gfx` | 75/1 | **76/0** | Prueferabsturz |
| `tiling` | 67/2 | **68/0** | Prueferabsturz + toter `sed` |
| `k13` | 93/1 | **99/0** | Prueferabsturz |
| `k18` | 169/1 | **170/0** | `launcher.fi` als fuenfter Leser von `SYS_PWRGET` |
| `multiuser` | 90/1 | **91/0** | toter Pfad in der Gegenprobe |
| `protokoll` | 54/1 | **55/0** | sechs Treiberpfade zeigten ins Leere |
| `k14` | 114/4 | 151/1 | Prueferabsturz |
| `k16` | 67/2 | 67/2 | Gegenprobe repariert, zwei echte Fehler bleiben |
| `wm` | 97/7 | 99/5 | beide Pruefer repariert, fuenf echte bleiben |
| `k17` | 158/0 | **158/0** | war gruen — aber erst jetzt zu Recht |
| `tresor` | 220/0 | **220/0** | dito |

`k18` war kein Messfehler, sondern eine echte kleine Luecke:
`kernel/user/launcher.fi:1478` liest `SYS_PWRGET`/`PG_BTN`, um sein
Ausschaltmenue zu oeffnen — ein **fuenfter Leser** derselben Nummer, keine
zweite Vergabe. Er steht jetzt mit Begruendung in der Ausnahmeliste; eine
zweite VERGABE faende die Suche weiterhin, weil sie auf
`const SYS_… = 17xx` zielt und nicht auf die Benutzung.

---

## 4. Die vollstaendige Abschnittstafel

`vorher` ist der Volllauf vom 18.09. gegen `8e772f44`, `nachher` der
Stand nach dieser Runde. Ein `←` markiert, wo sich etwas bewegt hat.

| Abschnitt | vorher | nachher | Stand | Ursache bei rot |
|---|---|---|---|---|
| `ahci` | 62/0 | 62/0 | **gruen** | — |
| `aml` | 54/0 | 54/0 | **gruen** | — |
| `arm` | 48/0 | 48/0 | **gruen** | — |
| `async` | 108/0 | 108/0 | **gruen** | — |
| `avx` | 31/1 | 31/1 | rot | Vektoranweisungen ausserhalb der Probe, in 10 Funktionen. |
| `blech` | 65/1 | 65/1 | rot | Der ALTE Kern haengt nichts ein (Rueckwaertsfall der Blech-Runde). |
| `boot` | 20/0 | 20/0 | **gruen** | — |
| `bridge` | 110/3 | 110/3 | rot | Der GUI-lose Serverbau ist kaputt; `system` nennt die Platte nicht. |
| `caps` | 67/0 | 67/0 | **gruen** | — |
| `core` | 46/0 | 46/0 | **gruen** | — |
| `customres` | 135/0 | 135/0 | **gruen** | — |
| `display` | 145/0 | 145/0 | **gruen** | — |
| `freestanding` | 41/0 | 41/0 | **gruen** | — |
| `fsrobust` | 30/0 | 30/0 | **gruen** | — |
| `gfx` | 75/1 | 76/0 ← | **gruen** | — |
| `glyphe` | 26/3 | 26/3 | rot | `ttf.glyph` haelt die Unterbrechungen nicht an; ohne Tafelsperre misst die Gegenprobe nichts. |
| `guard` | 58/0 | 58/0 | **gruen** | — |
| `haertung` | 19/0 | 19/0 | **gruen** | — |
| `handle` | 80/0 | 80/0 | **gruen** | — |
| `hid` | 56/1 | 56/1 | rot | Eine Zusage der Latenzmessung faellt. |
| `hv` | 162/0 | 162/0 | **gruen** | — |
| `hwnet` | 56/0 | 56/0 | **gruen** | — |
| `hwnettls` | 24/0 | 24/0 | **gruen** | — |
| `icons` | 33/0 | 33/0 | **gruen** | — |
| `init` | 78/0 | 78/0 | **gruen** | — |
| `k11` | 85/0 | 85/0 | **gruen** | — |
| `k13` | 99/0 | 99/0 | **gruen** | — |
| `k14` | 114/4 | 151/1 ← | rot | Rest nach der Reparatur: eine Zusage der Gegenprobe `nopart`. |
| `k15` | 218/34 | 219/33 ← | rot | Echte Pixel- und Dialogfehler (Menuetexte, Rahmenlage, Dialogtext leer). Der Prueferabsturz ist weg. |
| `k16` | 67/2 | 67/2 | rot | `fas` kennt `rdtsc` und `movdqu` nicht -> 153 statt 157 gebundene Programme. |
| `k17` | 158/0 | 158/0 | **gruen** | — |
| `k18` | 169/1 | 170/0 ← | **gruen** | — |
| `kernel` | 176/0 | 176/0 | **gruen** | — |
| `kvm` | 31/0 | 31/0 | **gruen** | — |
| `modul` | 25/47 | 25/47 | rot | Der Modulbau scheitert; `k_abi` wird nicht mehr verlangt. |
| `multiuser` | 90/1 | 91/0 ← | **gruen** | — |
| `net` | 75/0 | 75/0 | **gruen** | — |
| `netmon` | 73/3 | 73/3 | rot | Der Lauf bewegt keine Oktette (`wget: octets 65536` fehlt), nichts geht in die Geschichte. |
| `netview` | 124/45 | 124/45 | rot | Symbole brechen eine Regel des Nachtrags; Kontrast gegen die Leiste 10 statt 8 Rollen. |
| `osum` | 129/1 | 129/1 | rot | ET_DYN statt ET_EXEC: der Kern antwortet Grund 13, erwartet 8. |
| `ota` | 106/1 | 106/1 | rot | Ein unbekannter Schluessel wird nicht abgelehnt. |
| `paint` | 30/3 | 30/3 | rot | Kein Bild und kein gemeldetes Fenster; die Taskleiste zeigt kein Programmsymbol. |
| `pci` | 96/2 | 96/2 | rot | Keine Abschluss-Unterbrechung ueber Pin und I/O-APIC; DMA gegen PIO 1070 statt >=1200 Promille. |
| `poll` | 67/0 | 67/0 | **gruen** | — |
| `posix` | 148/2 | 148/2 | rot | 11 Aufrufnummern, bei denen Kernel und libc auseinanderlaufen. |
| `powermon` | 121/0 | 121/0 | **gruen** | — |
| `praesenz` | 36/0 | 36/0 | **gruen** | — |
| `protokoll` | 54/1 | 55/0 ← | **gruen** | — |
| `rtl` | 67/0 | 67/0 | **gruen** | — |
| `server` | 4/13 | 4/13 | rot | `gui=off` laesst sich nicht bauen; 16 Module greifen noch auf die Grafik zu. |
| `smp` | 59/0 | 59/0 | **gruen** | — |
| `softui` | 12/12 | 12/12 | rot | `modern`/`classic` booten im Foto-Pfad nicht -> keine Marken aus der Formdatei. |
| `sshd` | 67/0 | 67/0 | **gruen** | — |
| `stick` | 20/22 | 20/22 | rot | `jarvisd` verbindet sich nicht (keine TLS-Sitzung, keine Anmeldung). |
| `systembus` | 34/1 | 34/1 | rot | Der Editor startet nie -- die Tasten kommen nicht an. |
| `theme` | 97/1 | 97/1 | rot | Die Gegenprobe gegen den Stand VOR der Runde liefert 0 Treffer. |
| `themestore` | 78/3 | 78/3 | rot | Ein Schluessel ausserhalb der sieben; nicht jede Vorlage hat alle sieben. |
| `tiling` | 67/2 | 68/0 ← | **gruen** | — |
| `ton2` | 24/1 | 24/1 | rot | Der Systemklang ging nicht wirklich durch den Mischer. |
| `tresor` | 220/0 | 220/0 | **gruen** | — |
| `tunnel` | 16/0 | 16/0 | **gruen** | — |
| `tunnelkosten` | 3/0 | 3/0 | **gruen** | — |
| `tunnelpakete` | 18/0 | 18/0 | **gruen** | — |
| `umlaut` | 40/8 | 40/8 | rot | 23 SICHTBARE Umschriften in kernel/**, erwartet 0. |
| `unix` | 107/0 | 107/0 | **gruen** | — |
| `update` | 49/0 | 49/0 | **gruen** | — |
| `usbimg` | 41/7 | 41/7 | rot | Die deutschen Texte stehen nicht im Bild (Starter/Taskleiste). |
| `userland` | 91/0 | 91/0 | **gruen** | — |
| `vielkern` | 30/10 | 30/10 | rot | `darf_ring3` fragt die GS-Basis nicht ab; R3W liefert keine Zahl. |
| `vsync` | 14/0 | 14/0 | **gruen** | — |
| `werkzeug` | 28/6 | 28/6 | rot | Der Knopf fragt nicht nach, sondern toetet sofort; falsche pid beendet. |
| `wlan` | 210/0 | 210/0 | **gruen** | — |
| `wlan2` | 43/0 | 43/0 | **gruen** | — |
| `wm` | 97/7 | 99/5 ← | rot | Zeigerspitze und drei Fenstertitel stehen nicht bildpunktgenau. Beide Pruefer sind repariert. |

**46 gruen / 28 rot** von 74 Abschnitten.

---

## 5. Zwei Dinge, die jede kuenftige Runde wissen muss

**Ein Abschnitt, der nicht baut, ist rot — nicht "0 Fehler".** Die Tafel
oben unterscheidet drei Faelle sauber: gebaut und bestanden (`ahci` 62/0),
gebaut und gefallen (`wm` 99/5), Bau gescheitert (`server` 4/13,
`modul` 25/47 — die niedrige Zahl links ist hier das Warnzeichen, nicht
die Entwarnung).

**Die Platte verfaelscht Messungen, und zwar sichtbar.** Der Wirt lief
waehrend dieser Runde zweimal auf **0 Byte** voll, weil mehrere Runden
gleichzeitig arbeiten. Unter diesem Druck meldete `wm` **95/9** und `k13`
**93/1**; seriell nachgefahren sind es **99/5** und **99/0**. Die Regel
aus `A-008` gilt unveraendert und ist hier erneut belegt: **jeder rote
Abschnitt wird seriell nachgefahren, bevor man ihm glaubt.**
Aufgeraeumt wurden ausschliesslich Reste des **eigenen** Laufs
(`/tmp/update-run`, `/tmp/ota-run`, `/tmp/softui-run`, `/tmp/wlan2-run`
und die Abbilder von `usbimg`/`stick`) — an fremden Baeumen wurde nichts
angefasst.

`KDATA_SIZE` wurde **nicht** angefasst. Beide Stellen stimmen ueberein
(`boot.s` = `kstate.fi` = `0x160000`), geprueft vor und nach der Runde.

---

## 6. Was als Naechstes den meisten Nutzen bringt

1. **`modul` (25/47) und `server` (4/13) / `bridge` (110/3) / `stick`
   (20/22).** Die groessten roten Bloecke, und sie haengen zusammen: der
   **GUI-lose Serverbau** ist kaputt (`gui=off laesst sich nicht bauen`,
   16 Module greifen noch auf die Grafik zu). Ein Fix an dieser einen
   Naht raeumt vermutlich in allen vier Abschnitten auf — dieselbe Lage
   wie bei `A-016` damals.
2. **`netview` (124/45) und `k15` (219/33).** Beides echte
   Oberflaechenfehler, jetzt ohne Messrauschen sichtbar: Symbolregeln und
   Kontrast gegen die Leiste beim einen, Menuetexte und Rahmenlage beim
   anderen.
3. **`posix` (148/2).** Elf Aufrufnummern, bei denen Kernel und libc
   auseinanderlaufen — klein an Zahl, aber das ist die Sorte Fehler, die
   sich spaeter an voellig anderer Stelle zeigt.
4. **`umlaut` (40/8).** 23 sichtbare Umschriften in `kernel/**`, erwartet
   0. Reine Fleissarbeit, kein Denkproblem.

---

*Gemessen, nicht geraten. Wo Osum verliert, steht die Zahl.*
