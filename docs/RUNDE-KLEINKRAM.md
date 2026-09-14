# RUNDE KLEINKRAM (14.09.2026, Zweig `kleinkram`)

Sieben kleine offene Punkte aus `/root/osum-roadmap/OFFEN.md`, einzeln
gemessen. Grundlage: `main` `fd33f0f`.

**Die Kurzfassung, und sie ist unbequem: von den sieben Punkten waren
zwei bereits erledigt, drei Messaufbau und nur einer ein echter, noch
offener Sachfehler im Kern — und der ist behoben.** Was am Ende rot
bleibt, bleibt mit Grund und ist unten einzeln benannt.

---

## Die Tabelle

| Punkt | Vorher | Nachher | Zustand |
|---|---|---|---|
| `K-015` `RAND_*`/`MARGIN_*` | 1 Treffer + 7 Tabellenzeilen | 0 | **behoben** |
| `F-006` `vendor/net/BLOBS` | laut Liste 3 rot | 3/3 stimmen | **war schon erledigt, belegt** |
| `B-007` `hwdiag` meldet UEFI falsch | laut Liste `?` | UEFI **und** BIOS richtig | **war schon erledigt, belegt** |
| `A-017` `themetest` | 42/55 (Liste), hier 65/26 | **82/9** | **behoben**, 4 echte Restbefunde |
| `A-018` `customres` | 123/12 | **135/0** | **behoben** |
| `A-019` `powermon` | 24/92 → 62/54 (Liste) | **121/0** | **war schon erledigt, belegt** |
| `A-020` `display` EDID Ring 3 | 142/3 | **145/0** | **behoben** |

Abnahmen am Ende: `tools/build-kernel.sh` baut (5 626 504 Oktette),
`tools/check-ui.sh` **PASSED**, `tools/usbimg/build.sh` erzeugt das
Abbild (136 314 880 Oktette), `python3 tools/kernel/memmap.py` meldet
**0 Kollisionen** (122 Bereiche in 0x140000 Oktetten kdata).

---

## 1. `K-015` — `RAND_*` hiess `MARGIN_*`

**Vorher 1 falscher Bezeichner + 7 Tabellenzeilen, nachher 0.**

Der grosse Teil war schon weg: `kernel/kstate.fi` traegt die
`RAND_*`-Namen wieder (Runde GRUNDLINIE hat das mit `A-014`
miterledigt). Uebrig war **ein** Treffer der Englisch-Etappe 6:
`u_fuzz_margin` in `kernel/uprog.fi:430`. Der Kommentar direkt darueber
sagt, was es ist — *„DER ZUFALL IST EIGENER UND WIEDERHOLBAR. Ein
xorshift mit fester Saat"*. Mit margin/Kante hat das nichts zu tun.
Zurueckbenannt auf `u_fuzz_rand`.

**Geprueft, ob es ECHTE margin-Bedeutungen gibt — es gibt sie, und sie
sind NICHT angefasst:** `wm.fi:4305` `margin_cursor`, `cursor.fi:428`
`margin_a`, `taskbar.fi:110` `PAD0` („margin between the bar edge and
its contents"), dazu Kommentare in `wlibc.fi` und `icont.fi`. Alle
richtig uebersetzt, alle geblieben.

Dazu die sieben Zeilen `RAND_* → MARGIN_*` aus
`tools/english/const_table.tsv` entfernt. Kein Skript wendet die
Tabelle heute noch an — aber sie war die **Quelle** des Fehlers und
haette ihn beim naechsten Lauf wieder eingebaut.

Nebenbefund der Offenliste bestaetigt: `M_FIXRAND` (`kstate.fi:2779`)
heisst weiter so und passt jetzt wieder zu `RAND_FIXED`.

---

## 2. `F-006` — `vendor/net/BLOBS` beim fUi-Pin-Sprung

**Der Punkt ist bereits erledigt. Belegt, nicht angenommen.**

Die Offenliste nennt drei rote Hashes. Nachgerechnet gegen den Pin, der
wirklich in `vendor/firn/COMMIT` steht
(`c4e3dfcef8c555e5531c85e087649eac18eabd77`):

```
        Soll laut Firn-Repo bei diesem Commit     IST in vendor/net/BLOBS
wire.fi   2632dea5614ea4b1cd6bfa987ca83e855c1d350e   2632dea5…  gleich
tcp.fi    f0b268df9cb0c0b15c63cb6e8c95605a83dc0f1e   f0b268df…  gleich
stack.fi  2f58ae5629f6864df8ae2fece1271e2f5974845e   2f58ae56…  gleich
```

Und derselbe Weg, den `test.sh` Abschnitt 1 wirklich geht (`.roh/`
bevorzugt, sonst die ausgepackte Datei):

```
OK   vendor/firn/lib/net/wire.fi
OK   vendor/firn/lib/net/tcp.fi
OK   vendor/firn/lib/.roh/net/stack.fi
```

Nachgezogen hat das Commit `5091963` („vendor/net/BLOBS nachgezogen,
der Bericht, und ein Foto bei uiscale=2"). Die Datei begruendet es
selbst ausfuehrlich: der ganze Unterschied an `wire.fi` zwischen den
beiden Staenden ist **eine** Zeile, `GPL-2.0-only` → `MPL-2.0` aus dem
Firn-Commit `6ddd9375`. Am Stack selbst hat sich nichts geaendert —
genau das, was diese Datei zusichern soll.

**Nichts zu tun. `F-006` gehoert nach `ERLEDIGT.md`.**

---

## 3. `B-007` — `hwdiag` erkennt UEFI nicht

**Der Punkt ist bereits erledigt. Zwei Laeufe, beide richtig.**

`hwdiag` laeuft nicht von selbst; es braucht das Wort auf der
Kommandozeile. Gemessen wurde deshalb mit dem Stick-Abbild und dem
Menueeintrag „Hardware-Diagnose (bleibt stehen)"
(`cmdline: hwdiag hwdiagstop gfx …`), einmal unter OVMF und einmal
unter SeaBIOS, gleiche Maschine, gleiches Abbild:

```
UEFI (OVMF_CODE_4M.fd + eigene VARS):
  hwdiag: firmware=UEFI  vgarom=nein  smbios=nein  rsdp=nein
  hwdiag: fb 1280x800  bpp=32  pitch=5120  src=multiboot  phys=0xc0000000

BIOS (SeaBIOS, Vorgabe):
  hwdiag: firmware=BIOS  vgarom=0xc0000  smbios=0xf5a00  rsdp=0xf59e0
  hwdiag: fb 1280x800  bpp=32  pitch=5120  src=multiboot  phys=0xfd000000
```

Beide Male **richtig**, und beide Male mit den drei Rohwerten daneben,
aus denen der Befund entsteht (`kernel/hwdiag.fi:198`, `firmware_bios`:
mindestens zwei der drei Spuren VGA-ROM / SMBIOS-Anker / RSDP muessen
da sein). Unter OVMF ohne CSM fehlen alle drei, unter SeaBIOS sind alle
drei da. Auch die Rahmenpufferzeile steht in beiden Laeufen — die
Offenliste sagt, sie fehle.

**Eine Warnung fuer die naechste Messung:** `qemu -kernel` zusammen mit
OVMF funktioniert **nicht** (OVMF ignoriert das Multiboot-Abbild und
faellt auf PXE durch). Wer das so misst, sieht gar keine
`firmware=`-Zeile und haelt das faelschlich fuer den Fehler. Es muss
ueber das Stick-Abbild und Limine gehen.

**Nichts zu tun. `B-007` gehoert nach `ERLEDIGT.md`.**

---

## 4. `A-017` — `themetest` schreibt keine Zahlen

**Vorher 42/55 laut Liste, auf diesem Zweig gemessen 65/26. Nachher 82/9.**

Die Offenliste fragt: *ist der Test kaputt oder die Sache dahinter?*
**Antwort: weder noch — es waren zwei Werkzeugfehler, und keiner sitzt
im Kern.** Die Vermutung der Liste (`nofs`/`noproc` schneiden den
Ausgabeweg ab) trifft nicht zu; der Kern schreibt seine Zahlen.

### (a) Das Abbild war zu klein — 13 rote Zusagen

`tests/theme/image.sh` baute mit **16384 Bloecken = 8 MiB**. Die
`.elf`-Dateien dieses Laeufers wiegen zusammen **15 108 360 Oktette**.
Im Protokoll steht, wenn man das Arbeitsverzeichnis stehen laesst:

```
$ tail -1 /tmp/…/mkfs-day-light.log
mkfs: the disk is full
```

Folge: siebenmal „das Abbild liess sich nicht bauen" und sechsmal
„`<farbe>` steht NICHT im Bild".

`tests/theme/build.sh` hat **genau diese Zeile** in der Runde BAUFEHLER
von 16384 auf 32768 bekommen, mit Begruendung im Kommentar —
`image.sh` wurde dabei uebersehen. Jetzt ebenfalls 32768. Die sieben
Abbilder bauen, die Fotos entstehen.

### (b) Das zweite Modell war nicht nachgezogen — 12 rote Zusagen

`tools/theme/model.py` gab im dunklen Zweig `surface-hover` = `N_800`
und `surface-pressed` = `N_700`. Der Kern gibt `N_700` und `N_600`
(`kernel/user/wlibc.fi:3006`).

**Es ist das Modell, das falsch liegt, nicht der Kern.** Commit
`65d3300` („Der Hover war kaputt — an zwei Stellen, beide behoben und
fotografiert") hat den Kern mit Messung geaendert: dunkel waren
`surface-raised` und `surface-hover` **beide** `N_800`, gemessen
`bg=2565930 bthi=2565930`, beide `#27272A` — der Zeiger ueber einer
Kachel aenderte **gar nichts**, waehrend derselbe Fall hell 14 Stufen
hat. `surface-pressed` musste mitwandern, sonst waeren ueberfahren und
gedrueckt gleich geworden. `git log` zeigt: `model.py` wurde danach nie
angefasst.

Das Modell zieht nach. Der Kern bleibt, wie er ist.

### Was rot bleibt, und warum es bleiben soll

Neun Zusagen, und **keine davon ist von dieser Runde verursacht** — sie
werden erst jetzt sichtbar, weil die Bilder ueberhaupt wieder entstehen:

1. **`rohe Farbwerte im Zeichencode: 17`** (1 Zusage). Vorbestehend.
   `kernel/wm.fi` hat 16 rohe Farbwerte (`0xFF0000`, `0x00FF00`, … in
   `wm.fi:4844-4864`, `5906`, `6447-6537`), `taskbar.fi:3598` einen.
   Das ist echte Arbeit am Fenstermanager und gehoert nicht in eine
   Runde ueber Kleinkram — aber es ist ein echter Befund, kein Messfehler.

2. **`text-secondary auf surface-hover` = 4.03:1** in `day/dark`,
   `paper/dark`, `night/dark`, `midnight/dark` (4 Zusagen). **DAS IST
   EIN ECHTER SACHFEHLER, und er ist neu sichtbar.** WCAG AA verlangt
   4.5:1 fuer normalen Text. Nachgerechnet:

   | Farbe fuer `text-secondary` | Kontrast auf `#334155` |
   |---|---|
   | `N_400` `#94a3b8` (heute) | **4.038** — zu wenig |
   | `N_300` `#cbd5e1` | 6.974 |
   | `N_200` `#e2e8f0` | 8.399 |

   Ursache ist der Hover-Fix selbst: `surface-hover` ist von `N_800`
   nach `N_700` gewandert, also heller geworden, und damit ist der
   Abstand zum ohnehin gedaempften `text-secondary` unter die Schwelle
   gerutscht. **Nicht in dieser Runde behoben**, weil
   `text-secondary` eine Rolle ist, die in jedem Schema und in beiden
   Implementierungen haengt — das ist eine Gestaltungsentscheidung
   (`N_400` → `N_300` in dunkel) und gehoert mit Fotos abgenommen, nicht
   nebenbei geaendert. **Die Zusage wurde ausdruecklich NICHT
   entschaerft.** Empfehlung: eigener Punkt, `N_300` fuer
   `text-secondary` im dunklen Zweig, dann sind alle 17 Paarungen ueber
   der Schwelle.

3. **`surface` fehlt unter den drei haeufigsten Farben** bei `light`,
   `green`, `violet` (`#f8fafc`) und `gold` (`#fafaf9`) (4 Zusagen).
   Vorbestehend, und bei drei der sieben Bilder ist es gruen (`dark`
   `#0f172a` 7.9 %, `contrast` `#ffffff` 97.7 %). Im hellen Schema malt
   der Schreibtisch offenbar ueberwiegend `surface-sunken` (`#f1f5f9`,
   32.4 %) statt `surface` — die Zusage prueft die falsche Rolle, oder
   die Oberflaeche nimmt die falsche. Das ist **nicht entschieden** und
   wird hier auch nicht geraten; es braucht einen Blick auf das Bild,
   nicht auf die Zahl.

---

## 5. `A-018` — `customres`, 12 echte Sachfehler

**Vorher 123/12, nachher 135/0.**

**Alle zwoelf gehen auf EINE Aenderung zurueck, und die war richtig.**
Commit `758c3c6` („e1000-Absturz eingegrenzt: der Rahmenpuffer nahm den
Geraeten die Plaetze") hat `WIN_SLOTS` von 8 auf 16 gesetzt
(`kernel/fb.fi:574`), weil sich Rahmenpuffer und `apic.map_device` die
Fensterplaetze **teilen** und Netz, Platte, USB und Ton sonst keinen
mehr bekamen. Seither ist `maplimit` **29 360 128** statt 14 680 064,
gemessen im Lauf:

```
disp: kacheln alle=16  frei=13  belegt=3  fb=2  laufmax=14
disp: eigen 2560x1440x 32 rc=0 why=0 num=14745600 vram=16777216 maplimit=29360128
```

Der Abschnitt hatte aber an mehreren Stellen fest getippt, dass
2560x1440 (14 745 600 Oktette) **nicht** einblendbar sei. Seit dem
Sprung **passt** es. Der Kern hat also voellig zu Recht angenommen —
**rot war die Erwartung, nicht der Kern.**

**Damit ist die Sorge der Offenliste ausdruecklich widerlegt:** „der
Kern nimmt eine Aufloesung an, die er ablehnen muesste" trifft
**nicht** zu. Er nimmt sie an, weil er sie seit `758c3c6` wirklich
tragen kann.

Nachgezogen:

* `kernel/kgui.fi` (`dispeigenbad`) fragt **3840x2160** statt
  2560x1440; der Laeufer gibt diesem Lauf `vgamem_mb=64`, damit nicht
  die Karte vorher ablehnt — dieselbe Technik, die Abschnitt 9 seit
  jeher benutzt und dort begruendet. Die Schranke wird damit **wieder
  echt** gemessen: Grund 3, `rc=8` (`E_LIMIT`), `num=33177600 >
  29360128`, und `vram` (67 108 864) ist groesser, die Karte war es
  also nicht.
* `tools/customres/run.sh` zieht die Zahlen nach und die Belegung von
  8 auf 16 Plaetze. **Die Zusage selbst bleibt:** der laengste
  zusammenhaengende Bereich muss **kleiner** sein als die Gesamtzahl —
  belegte Plaetze reissen wirklich Loecher, und das wird weiter geprueft
  (`laufmax=14 < 16`).

### Und ein echter Fehler, den erst das sichtbar gemacht hat

`disp: custom selftest` meldete **8/9**, `dispctl: testc` **9/10** —
**eine Zusage zaehlte still nicht mehr mit.** Beide standen hinter
`if gross > map_limit(state)` mit fest getippten 2560x1440: wurde die
Grenze groesser, war die Bedingung falsch, und die Pruefung fiel
**lautlos** aus. Eine Zusage, die bei wachsender Grenze verschwindet,
ist schlimmer als eine, die rot wird.

Beide rechnen die Hoehe jetzt **aus** der Grenze (kleinste Hoehe bei
3840 Breite ueber `map_limit`) — und beide sagen es, wenn die Schranke
auf dieser Karte gar nicht erreichbar ist: `check_custom` fragt den
Bildspeicher **vor** den Fensterplaetzen, und bei einer 16-MiB-Karte
gegen 28 MiB Grenze faengt Grund 2 jede Zahl ab. Dann zaehlt die Zusage
mit **und** der Grund steht im Quelltext. Auf der 64-MiB-Karte greift
sie echt, und Abschnitt 9 misst sie dort unveraendert gruen
(„3840x2160 scheitert jetzt NUR noch an den Fensterplaetzen dieses
Kernels (3)").

---

## 6. `A-019` — `powermon`, noch 54 rote Zusagen

**Der Punkt ist bereits erledigt. Gemessen 121 bestanden, 0 durchgefallen.**

Zweimal gelaufen (`PMON_KEEP=1`), beide Male **121/0**. Die von der
Offenliste genannten Ursachen sind weg: `firnc does not translate
powermon.fi` und `mkfs.py fails` kommen in keinem Lauf mehr vor — das
waren `A-014`/`A-016`, und die sind auf `grundlinie` behoben worden.
Auch die drei „stabilen Restbefunde" (deutsche Zeilen in `pmon.fi` und
`powermon.fi`, doppelte Aufrufnummern) melden sich nicht mehr.

**Ein Hinweis fuer den naechsten Volllauf:** in einem dritten Lauf, der
**parallel** zu zwei anderen QEMU-Laeufen auf derselben Maschine lief,
fiel genau eine Zusage um:

```
FAIL  the two runs do not move the energy the way the floor demands
      (0/1663200 against 77000/1724800)
```

Sie vergleicht zwei Laeufe mit und ohne Grundlast
(`tools/powermon/run.sh:378`, `p1 < p2 && s1 > s2`) und misst dabei
Energie in mW-Ticks unter Last. `p1` ist in **allen** Laeufen 0, auch
in den gruenen — die Bedingung haengt allein an `s1 > s2`, und das sind
Messwerte, die unter Fremdlast wandern. Einzeln gelaufen ist sie
zuverlaessig gruen. **Als lastempfindlich vormerken** (dieselbe Art
Befund wie `K-012` fuer `smp`), nicht als Sachfehler.

---

## 7. `A-020` — `display`, drei EDID-Zusagen

**Vorher 142/3, nachher 145/0.**

**Die drei roten Zusagen waren der Messaufbau, nicht der Kern.** Der
Laeufer setzt ganz oben:

```sh
VGA_STD=${VGA_STD:-"-vga std -global VGA.edid=off"}
```

Die Tafel ist mit **Absicht abgeschaltet** — die uebrigen Abschnitte
messen die eingebaute Vorgabe 800x600 und wollen keine. Abschnitt 10
fragt aber nach dem EDID-Block: „EDID hat auch Ring 3 gesehen",
Hersteller- und Modellname ueber `osum_dispstr`. Ohne Tafel gibt es
keinen Block, `vmode.edid_ok` ist 0, `sysgui.do_dispstr` antwortet mit
`E_NODEV` — und die drei waren rot, **seit es sie gibt**. Genau das
sagt die Offenliste auch („NICHT von dieser Runde verursacht").

Abschnitt 4 macht seit jeher **dieselbe Ausnahme**
(`VGA_STD="-vga std"`) und misst denselben Block in Ring 0 gruen.
Abschnitt 10 bekommt sie jetzt auch — und die Frage der Offenliste
(„kommen EDID-Daten wirklich bis Ring 3 durch?") ist damit **mit Ja
beantwortet und gemessen**:

```
OK    EDID hat auch Ring 3 gesehen (1)
OK    der Herstellername kommt ueber osum_dispstr in Ring 3 an
OK    der Modellname auch
```

**Folge, und sie ist nachgezogen statt weggedrueckt:** mit Tafel nimmt
der Kern die native Aufloesung, QEMU nennt 1280x800. Die zwei Zusagen
„die Tafel 800" / „das Bild 800" galten nur ohne Tafel. Sie vergleichen
jetzt gegen die Zahl, die **der Kern im selben Lauf** meldet, statt
gegen eine fest getippte — das ist die Zusage dieses Abschnitts („zwei
Wege, eine Wahrheit") und haelt auch, wenn die Tafel wechselt.

---

## Was diese Runde ueber die Offenliste sagt

Drei der sieben Punkte (`F-006`, `B-007`, `A-019`) waren **schon
erledigt**, als die Runde begann — die Liste war an diesen Stellen
aelter als der Baum. Drei weitere (`A-017`, `A-020` und der groesste
Teil von `A-018`) waren **Messaufbau**: veraltete Erwartungen, ein zu
kleines Abbild, eine abgeschaltete Tafel.

**Das Muster dahinter ist das eigentliche Ergebnis:** vier der fuenf
untersuchten Ursachen sind *zweite Implementierungen und fest getippte
Zahlen, die einer richtigen Kernaenderung nicht nachgezogen wurden* —
`model.py` gegen `wlibc.fi`, `image.sh` gegen `build.sh`, `2560x1440`
gegen `WIN_SLOTS`, `800` gegen die Tafel. Jedes Mal war der Kern im
Recht und die Messung im Rueckstand.

Zwei Stellen sind deshalb bewusst so gebaut, dass sie **nicht wieder**
veralten koennen: die Kachelschranke rechnet ihre Testaufloesung aus
`map_limit` statt sie zu tippen, und die Tafelbreite in `display`
kommt aus dem Kernmitschnitt desselben Laufs.

**Kein Test wurde entschaerft oder geloescht.** Wo eine Erwartung
geaendert wurde, steht der Grund im Quelltext daneben und oben in
diesem Bericht. Der eine echte, noch offene Sachfehler
(`text-secondary` auf `surface-hover`, 4.03:1 gegen WCAG 4.5:1) ist
**rot gelassen** und benannt, statt die Schwelle zu senken.
