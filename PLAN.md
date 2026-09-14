# RUNDE WMPLUGIN — Bauplan und Schnittstellen

Zweig `wmplugin`, Arbeitsbaum `/root/os-wmplug`. (Der vorige Inhalt dieser
Datei gehoerte der Runde EXPLORER-2 und steht unveraendert in der
Geschichte: `git show main:PLAN.md`.)

Ziel: ein **Erweiterungssystem fuer den Fensterserver** nach dem Vorbild
von Hyprland-Plugins/hyprpm — **ohne deren Grundfehler**. Hyprland laedt
ein Plugin als `.so` in den Compositor-Prozess und laesst es Funktionen
umhaengen. Unser Fensterserver laeuft IM KERNEL (`kernel/wm.fi`), derselbe
Weg waere Fremdcode in Ring 0, und /root/osum-roadmap/FREMDSOFTWARE.md
Regel 4 sagt: "Kein Fremdcode im Kern."

**Also: Plugins sind gewoehnliche Ring-3-Prozesse.** Der Kern kennt von
ihnen einen Tafelplatz, einen Ereignisring, eine Rechtemaske und eine
Frist. Der Kern **wartet nie** auf ein Plugin. Ein abstuerzendes,
haengendes oder boeswilliges Plugin darf den Schreibtisch nicht
beschaedigen — und genau das wird gemessen, nicht behauptet.

---

## 0. Was schon steht (dieses Grundgeruest, gebaut und GEBOOTET)

Gemessen mit `bash tools/build-kernel.sh /tmp/wmp.img` und einem echten
QEMU-Lauf (`gfx wm wmhold wmplug plugtest ...`, Exitcode 21):

```
wm: selftest 30 / 30  failed=0xc04200        <- Grundlinie UNVERAENDERT
wmplug: reg selbstte platz=0 rechte=0x1f
wmplug: unreg selbstte grund=2 holte=1 verlor=5
wmplug: selftest 10 / 10  failed=0x0
wmplug: abi=1  tafel= offen  frist=50
wm: hold
```

Gegenprobe ohne das Wort `wmplug` auf der Kommandozeile: `tafel= zu`,
Selbsttest 30/30 unveraendert.

* **`kernel/wmplug.fi` (neu, ~800 Zeilen)** — die ganze Buchhaltung:
  8 Plaetze, je ein Ereignisring (64 x 16 Oktette), Rechtemaske,
  Gewaehrungstafel (16 Namen), Flaechentafel (32 Fenster-Ids), Frist,
  Zaehler, 10 Selbsttest-Zusagen. Kein indirekter Sprung, keine
  Rekursion, kein Warten.
* **`kernel/kstate.fi`** — `WMP_OFF=0xF3000`, `WMP_MAX=0x4000`
  (in `tools/kernel/memmap.py` eingetragen: 111 Bereiche, 0 Kollisionen);
  Modusbits `M_WMPLUG=986`, `M_PLUGAUS=987`, `M_PLUGTEST=988`,
  `M_PLUGFRIST=989`.
* **`kernel/sys.fi`** — die zehn Nummern 2117..2126, `WM_MAXNR=2126`,
  die Felder `PL_*` und die Handlungen `PA_*`, alles ausgefuehrt.
* **`kernel/sysgui.fi`** — `plug_call` + `do_plugreg`/`do_pluggrant`/
  `do_pluginfo`/`do_plugact`/`desk_anwenden`, vor der Handle-Suche
  eingehaengt.
* **`kernel/wm.fi`** — fuenf Haken: `init` (Tafel auf/zu), `create`
  (E_WIN_OPEN), `destroy` (E_WIN_CLOSE), `set_focus` (E_FOCUS),
  `compose` (`wmplug.sweep`, acht Vergleiche je Bild).
* **`kernel/kgui.fi`** — `wmplug_stage`: Selbsttest bei `plugtest`,
  kurze Frist bei `plugfrist`, eine Zeile auf die serielle Leitung.
* **`kernel/kmain.fi`** — die vier Kommandozeilenwoerter.
* **`tools/build-kernel.sh`** — `wmplug` in `GFX_DATEIEN` (bei
  `--gui off` faellt die Datei weg wie `tile.fi`).

---

## 1. DIE SCHNITTSTELLE — festgenagelt, hier gilt sie

Aenderungen an diesen Nummern **nur ueber diesen Plan**, nicht im
Alleingang: vier Module lesen sie.

### Syscalls (`kernel/sys.fi`, WM_BASE=2100)

| Nr | Name | Argumente | Rueckgabe |
|----|------|-----------|-----------|
| 2117 | `WM_PLUG_REG` | (abi, name*15, maske) | Platz 0..7 / `-E_UNSUPPORTED` (Fassung) / `-E_EXHAUSTED` |
| 2118 | `WM_PLUG_UNREG` | () | 0 |
| 2119 | `WM_PLUG_POLL` | (aus*16) | 1 = geholt, 0 = nichts da. **Nie blockierend** |
| 2120 | `WM_PLUG_SUB` | (maske) | 0 |
| 2121 | `WM_PLUG_INFO` | (platz, feld `PL_*`) | Zahl |
| 2122 | `WM_PLUG_ACT` | (handlung `PA_*`, fenster-id, wert) | 0 / `-E_RIGHTS` / `-E_NOTFOUND` |
| 2123 | `WM_PLUG_KEY` | (taste, mods) | 0 / `-E_RIGHTS` |
| 2124 | `WM_PLUG_BAR` | (text, laenge<=31) | 0 / `-E_RIGHTS` |
| 2125 | `WM_PLUG_BARGET` | (platz, aus, max) | Laenge — **nur die Leiste** (`is_taskbar`) |
| 2126 | `WM_PLUG_GRANT` | (name*15, rechte) | 0 / `-E_RIGHTS` — **nur root** |

Die Felder von `WM_PLUG_INFO` reichen seit Modul A bis `PL_MAXNR = 20`;
neu sind `PL_FRAMES = 18` (Bildnummer) und `PL_LATUS = 19` (mittlere
Bildzeit in us). Beide beantwortet der Kern ohne Anmeldung.

`WM_PLUG_INFO(_, PL_ABI)` beantwortet der Kern **immer**, auch ohne
Plugintafel und ohne Anmeldung: sonst waere die Versionierung ein
Ratespiel. Aktuelle Fassung: **`WMP_ABI = 1`**.

### Ereignis (16 Oktette, so liegt es im Ring)

```
+0x00  u64 typ            E_WIN_OPEN=1 E_WIN_CLOSE=2 E_FOCUS=3
                          E_DESK=4 E_TILE=5 E_KEY=6 E_STOP=7
+0x08  u64 daten          (a & 0xFFFF) << 32 | (b & 0xFFFF) << 16 | (c & 0xFFFF)
```

Abonnement-Maske = `1 << typ`. Belegung von a/b/c:
`E_WIN_OPEN(id, ebene, 0)`, `E_WIN_CLOSE(id,0,0)`, `E_FOCUS(id,0,0)`,
`E_DESK(flaeche,0,0)`, `E_TILE(knoten,blaetter,0)`,
`E_KEY(taste,mods,0)`, `E_STOP(grund,0,0)`.

### Rechte (`wmplug.R_*`, Bitmaske)

```
0x001 R_EV_WIN    0x002 R_EV_FOCUS  0x004 R_EV_DESK
0x008 R_EV_TILE   0x010 R_EV_KEY
0x100 R_ACT_WIN   0x200 R_ACT_FOCUS 0x400 R_ACT_KEY  0x800 R_ACT_BAR
R_DEFAULT = 0x01F (nur zusehen)      R_ALL = 0xF1F
```

Ohne Eintrag in der Gewaehrungstafel bekommt ein Plugin `R_DEFAULT`.
Eingetragen wird ueber `WM_PLUG_GRANT` von **/bin/wmplug als root** aus
`/etc/wmplug.conf`. Der Kern liest keine Datei.

### Gruende einer Abmeldung (`wmplug.G_*`, Feld `PL_GRUND`)

`0 G_OK` (selbst) · `1 G_CRASH` (Prozess weg) · `2 G_FRIST` ·
`3 G_RIGHTS` · `4 G_USER` (`wmplug disable`). Jede Abmeldung schreibt
eine Zeile `wmplug: unreg <name> grund=<n> holte=<n> verlor=<n>`.

### Kommandozeilenwoerter

`wmplug` (Tafel auf) · `plugaus` (Gegenprobe: alles gebaut, abgeschaltet)
· `plugtest` (Selbsttest des Moduls) · `plugfrist` (Frist 3 statt 50
Ticks — **ausdrueckliche Abkuerzung fuer den Abnahmelauf**).

---

## 2. DIE MODULE — wer welche Datei besitzt

**Zwei Module fassen nie dieselbe Datei an.** Wer eine fremde Datei
braucht, schreibt es in den Bericht statt sie zu aendern.

### A — `kern` (Kernseite vervollstaendigen)
Dateien: `kernel/wmplug.fi`, `kernel/wm.fi`, `kernel/sysgui.fi`,
`kernel/kgui.fi`, `kernel/kbd.fi` (falls fuer den Kuerzelweg noetig).
**FERTIG UND GEBOOTET.** Was dabei an der Schnittstelle dazukam — die
anderen Module lesen bitte hier, nicht im Quelltext:

* **`PL_FRAMES = 18`, `PL_LATUS = 19`, `PL_MAXNR = 20`** (`kernel/sys.fi`).
  `WM_PLUG_INFO(_, PL_FRAMES)` ist die Bildnummer, `PL_LATUS` die
  mittlere Bildzeit in Mikrosekunden. Beide kommen aus der Bilduhr, die
  `wm.compose` seit der Runde VEKTOR ohnehin fuehrt — ein zweiter
  Zaehler daneben laege immer etwas anders. **Bildrate = PL_FRAMES
  zweimal mit bekannter Pause ablesen** (Modul F).
* **Der Abschied.** Eine Abmeldung legt E_STOP(grund) als letztes
  Ereignis in den Ring, und der Platz geht nicht sofort frei, sondern
  in einen Abschiedszustand: **`WM_PLUG_POLL` beantwortet der Kern noch,
  jeder andere Ruf gibt `-E_NOTFOUND`.** Der Platz verfaellt, sobald der
  Ring leer ist oder die Frist um ist; gewartet wird auf niemanden.
  `PL_USED` ist fuer einen Abschiedsplatz **0** — er zaehlt nicht mehr
  mit. Ausnahme: ein ABGESTUERZTES Plugin bekommt keinen Abschied, sein
  Platz geht sofort frei (es koennte ihn sonst ein spaeterer Prozess auf
  demselben Tafelplatz leerlesen).
* **Der Kehrbesen haengt an der UHR, nicht am Bild** (`wm.poll`, einmal
  je Tick). Gemessener Grund: auf einem ruhigen Schreibtisch wird gar
  nicht zusammengesetzt, und ein Haenger blieb deshalb stehen.
* **Tastenkuerzel.** Beide Wege fragen `key_owner` VOR der Zustellung:
  `on_key` (Zeichentasten, mods aus KB_SHIFT=2/KB_CTRL=4) und `hotkeys`
  (der Alt-Ring, mods wie `kbd.old_key`: Alt=1). Bei einem Treffer gibt
  es nur `notify(E_KEY, taste, mods, 0)`; das Fenster **und** das
  Terminal darin bekommen nichts. Zaehler: `wm.plugkeys`.
* **`E_TILE(knoten, blaetter)`** entsteht in `wm.tile_apply` — dort und
  nur dort, weil jede Baumaenderung die Rechtecke neu verteilt.
* **Selbsttest jetzt 13 Zusagen** (`wmplug: selftest 13 / 13 failed=0x0`).
  Ein Laeufer soll die Zahl aus `fn selftest_max` lesen, nicht festnageln.
* **`wmplug: bilanz plugs= evin= evout= kicks= deny= plugkeys=`** am Ende
  des Haltens — eine Zeile aus dem Kern statt einer Summe, die der
  Laeufer selbst bildet.
* **Zahlen der Kernseite** (5 s Halten, `gfx wm tile wmhold wmplug
  wmshell ...`, je ein Lauf; die belastbare Messung macht Modul F ueber
  PL_FRAMES/PL_LATUS):
  mit angemeldetem Plugin `n=50 mittel=939 us max=13936 ueber16=0`,
  ohne `n=43 mittel=981 us max=13204 ueber16=0`. Die Lasten sind nicht
  dieselben (das Plugin oeffnet ein Fenster), der Unterschied liegt in
  beiden Richtungen im Rauschen — ein Einbruch ist es nicht.

### B — `verwaltung` (/bin/wmplug)
Dateien: `kernel/user/wmplug.fi` (neu), `etc/wmplug.conf` (neu),
Paketbeschreibungen unter `pakete/wmplug-*/` (opk, Vorlage
`kernel/user/opk.fi`). Vorlage fuer Aufbau und Ton: `kernel/user/tiling.fi`.
`list | enable <name> | disable <name> | info <name>`; enable/disable
setzen die Rechtemaske ueber `WM_PLUG_GRANT` (disable = Maske 0, wirkt
sofort auch auf ein laufendes Plugin), `list` liest `PL_*`.

### C — `regel` (Plugin 1: Fensterregel-Engine)
Dateien: `kernel/user/plugregel.fi` (neu), `etc/wmregeln.conf` (neu).
Abonniert `E_WIN_OPEN`, liest die Regeln ("app=rechner → flaeche 2,
schwebend, zentriert"), setzt sie mit `PA_DESK`/`PA_FLOAT`/`PA_MOVE`.
Fenstername/Buendel ueber die vorhandenen `WM_LIST`-Felder.

### D — `widget` (Plugin 2: Leistenwidget)
Dateien: `kernel/user/pluguhr.fi` (neu), `kernel/user/taskbar.fi`
(**nur dieses Modul aendert die Leiste**). Das Plugin schickt TEXT
(`WM_PLUG_BAR`), die Leiste holt ihn (`WM_PLUG_BARGET`) und malt ihn mit
`wlib`/`fUi` wie jeden anderen Text — **kein neuer Zeichenweg**, damit
`tools/check-ui.sh` PASSED bleibt.

### E — `gegenprobe` (die drei harten Belege + Laeufer)
Dateien: `kernel/user/plugboese.fi` (neu: `segv`, `hang`, `greif` in
einem Programm, per Argument), `tools/wmplug/run.sh` (neu),
`docs/shots/wmplug/` (neu). Vorlage: `tools/tiling/run.sh` und
`tools/wm/run.sh` (`lauf`/`foto`). Druckt am Ende
`N bestanden, M gescheitert`. Muss belegen: (a) SIGSEGV → Schreibtisch
laeuft weiter (Foto + weitere compose-Runden), (b) Endlosschleife →
Frist greift, keine Bildrate verloren, (c) Handlung ohne Recht →
Fehlercode UND `PL_DENY` steigt UND das Fenster steht unveraendert,
(d) an/aus zur Laufzeit → zwei Fotos, mit `tools/gfx/checkshot.py`
maschinell auseinandergehalten.

### F — `bericht` (Messung und Text)
Dateien: `docs/RUNDE-WMPLUGIN.md` (neu), `tools/wmplug/mess.sh` (neu).
Bildrate/Latenz **vor und nach** dem Laden, beide Zahlen im Bericht,
Abweichung benannt. Dazu: Entwurf der Schnittstelle mit Versionierung,
warum Ring 3 statt Hyprlands `.so`-im-Prozess, offene Punkte, und
**jede Abkuerzung ausdruecklich** (bekannt schon jetzt: `plugfrist`,
die 8er-Grenze der Tafel, die Flaechentafel als Ersatz fuer fehlende
Arbeitsflaechen in `wm.fi`).

---

## 3. Regeln fuer jedes Modul

1. Nach jeder Aenderung muss `bash tools/build-kernel.sh /tmp/<eigen>.img`
   fehlerfrei durchlaufen und `python3 tools/kernel/memmap.py kernel`
   0 Kollisionen melden. Ein Stand, der nicht baut, ist kein Stand.
2. **Nichts behaupten ohne Messung.** Jede Zusage braucht eine Zeile aus
   einem wirklich gebooteten Kernel oder ein nachgerechnetes Foto.
3. Eigene QEMU-Socket- und Dateinamen (`/tmp/<modul>-*`): auf dieser
   Maschine laufen andere Laeufe parallel.
4. Kein Zeichnen ausserhalb `fUi`/`wlib`; `tools/check-ui.sh` muss
   PASSED bleiben.
5. Keine Rekursion im Kernel (16 KiB Kernstapel), Schleifen statt dessen.
6. Kommentare deutsch, ohne Umlaute in Bezeichnern, sie erklaeren das
   WARUM mit dem gemessenen Befund.
7. Kleine Commits auf `wmplugin`. **Nicht auf main, nicht mergen.**
