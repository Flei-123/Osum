<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Die grossen ungemergten Zweige — gesichtet, entschieden, begründet

**Erhebung vom 21.09.2026.** Baum `/root/fb-osum`, `main` bei `c0cda62c`
("Merge branch 'runde-blur'").

`docs/ALTZWEIGE-AUGUST.md` hat im selben Monat die **sechs** Augustzweige
abgearbeitet (`certus`, `demux`, `feedback`, `a11y`, `inventory`,
`haertung`). Dabei kam heraus, dass deutlich mehr herumliegt: **neun
weitere Zweige**, grösser, neuer, teils mit eigener Abnahme. Dieses Blatt
beantwortet für jeden dieser neun dieselben drei Fragen — **was er
wollte, ob es noch gilt, ob er noch aufsetzt** — mit gemessenen Belegen.

**Kein Zweig wird gelöscht.** Alle neun bleiben stehen; jede Zahl aus
diesen Runden bleibt nachlesbar. Was sich ändert, ist nur, dass es
jetzt aufgeschrieben ist.

---

## 0. Die kurze Antwort

| Zweig | Commits | was er wollte | gilt noch? | gemergt? |
|---|---:|---|---|---|
| `wmplugin` | 51 | Plugin-System für den Fensterserver | **nein** — die Runde **ist auf `main`** | nein |
| `viewer` | 15 | Bildbetrachter (P-014) | **nein** — von Runde ALLTAG/BILD ersetzt | nein |
| `supersearch` | 12 | Suche im Startmenü | **nein** — `tools/look`, `tools/paint` auf `main` | nein |
| `media1` | 10 | Ton: AC97, Abspieler, Mischer | **nein** — von Runde HDA/TON-2 ersetzt | nein |
| `nvmeq` | 7 | NVMe-Warteschlange, io_uring-Weg | **teilweise** — Idee gilt, Code nicht | nein, **Neubau nötig** |
| `snip` | 6 | Bildschirmfoto/Ausschnitt | **nein** — `/bin/snip` + `shot.fi` auf `main` | nein |
| `struktur` | 5 | Treiber in Verzeichnisse | **nein** — von `struktur2`/O-STRUKTUR ersetzt | nein |
| `speicherdruck` | 5 | Speicherdruck/OOM (K-002) | **JA — als einziger ganz** | nein, **Neubau nötig** |
| `netprofil` | 5 | Netz-Profil und -Statistik | **grösstenteils nein** | nein |

**Gemergt wurde: keiner.** Die Begründung ist bei allen neun im Kern
dieselbe und steht in Abschnitt 1.

---

## 1. Der gemeinsame Grund: O-STRUKTUR liegt dazwischen

Sieben der neun Zweige zweigten zwischen dem **28.08.** und **02.09.**
ab, zwei am **14.09.** Seither ist `main` weitergelaufen:

| Zweig | Abzweig | Commits auf `main` seither |
|---|---|---:|
| `viewer` | 28.08. | **1088** |
| `media1` | 28.08. | **1088** |
| `supersearch` | 28.08. | **1057** |
| `snip` | 28.08. | **1052** |
| `nvmeq` | 29.08. | **1010** |
| `netprofil` | 30.08. | **927** |
| `struktur` | 02.09. | **855** |
| `speicherdruck` | 14.09. | **262** |
| `wmplugin` | 14.09. | **185** |

Dazwischen liegt die Runde **O-STRUKTUR** (17.09., `docs/STRUKTUR.md`,
Commits `3b78ecc9`…`567b2771`), die den Kernbaum in Schichten geordnet
hat — **120 Dateien umgezogen**, alle als echte Umbenennung:

```
kernel/sys.fi     -> kernel/sys/sys.fi        kernel/mem.fi    -> kernel/mm/mem.fi
kernel/kstate.fi  -> kernel/lib/kstate.fi     kernel/proc.fi   -> kernel/sched/proc.fi
kernel/wm.fi      -> kernel/ui/wm.fi          kernel/nvme.fi   -> kernel/drv/blk/nvme.fi
kernel/ac97.fi    -> kernel/drv/snd/ac97.fi   kernel/e1000.fi  -> kernel/drv/net/e1000.fi
```

Die Zweige kennen diese Ordnung nicht. Ein `git merge` meldet die
Umzüge als **`modify/delete`** und legt die **alte** Datei am **alten**
Pfad wieder an — neben die neue.

### Gemessen: kein einziger Zweig setzt sauber auf

`git merge --no-commit --no-ff`, Konfliktdateien gezählt, danach
`git merge --abort`:

```
speicherdruck    5 Konflikte
media1           9
nvmeq           11
netprofil       15   (davon kernel/netdev.fi modify/delete)
wmplugin        12   (davon 10 PNG)
viewer          18   (davon kernel/kstate.fi modify/delete)
snip            21
supersearch     24
struktur       101   (davon rename/rename: zwei konkurrierende Ordnungen)
```

**Neun von neun rot.** Bei `struktur` steht wörtlich:

```
CONFLICT (rename/rename): kernel/ahci.fi renamed to kernel/drv/blk/ahci.fi
  in HEAD and to kernel/drivers/blk/ahci.fi in struktur.
```

Zwei Ordnungen desselben Baums, die sich gegenseitig ausschliessen.

### Der gefährlichere Teil: was git *nicht* meldet

| Datei | auf `main` | auf dem Zweig |
|---|---:|---:|
| `kernel/ui/wm.fi` | **11230** Z., `anim` **43×** | `wmplugin` 9449 Z., `anim` 29× |
| `kernel/ui/wm.fi` | **11230** Z., `anim` **43×** | `supersearch`/`snip` `anim` **0×** |
| `kernel/user/wlib.fi` | **10475** Z., `anim` 20×, `zug_*` **4×** | `supersearch` 3649 Z., beides **0×** |
| `kernel/user/wlibc.fi` | **6252** Z. | `supersearch` 3654 Z. |
| `kernel/kmain.fi` | **7832** Z. | `nvmeq` 6785 Z. |

In `wlib.fi` sitzen die **Animationen** und Justins **Zieh-Aufhebung**,
in `ui/wm.fi` die Bewegungen der Runde BLUR. Eine Zusammenführung, die
an einer dieser Stellen die alte Fassung gewinnen lässt, **löscht sie
still aus — ohne einen einzigen Konflikt zu melden.** Das ist genau der
Vorgang, der auf `certus` fast fünf Errungenschaften gekostet hat.

---

## 2. `wmplugin` — die Runde ist längst auf `main`

Der Zweig sah nach dem dicksten Brocken aus: 51 Commits, eigene Abnahme,
`219 bestanden, 0 gescheitert`. **Er ist trotzdem kein Merge-Kandidat,
und zwar aus dem denkbar besten Grund.**

**Die Runde wurde am 14.09. gemergt.** Beleg:

```
1286cf69  2026-09-14 19:41:51  Merge branch 'wmplugin'
          Eltern: 0355a819  f09af289
78ad622d  2026-09-14 19:54:47  Merge-Nachtrag: wmplugin auf main,
                               WMP_OFF nach 0x108000
```

`git merge-base --is-ancestor 1286cf69 main` → **ja**. Auf `main` liegen
`docs/RUNDE-WMPLUGIN.md` (40 593 Oktette), `kernel/ui/wmplug.fi`
(1313 Z.), `kernel/user/wmplug.fi` (993 Z.), `tools/wmplug/` mit fünf
Läufern und `BEFUND-WMPLUG-NAMENSPUFFER.md`. Der Bericht auf `main`
nennt die Zahlen des gemergten Standes:

```
REGEL:   38 bestanden, 0 gescheitert
WIDGET:  30 bestanden, 0 gescheitert
WMPLUG: 139 bestanden, 0 gescheitert     zusammen 207
```

**Was sind dann die 51 Commits?** Der Nachlauf *nach* dem gemergten
Stand `f09af289` — Bericht, Bilder, Feinschliff — der die Abnahme von
207 auf **219** gehoben hat (Delta **12 Zusagen**). Er entstand auf dem
Vor-O-STRUKTUR-Baum und wurde nie nachgezogen. `git cherry main wmplugin`
meldet alle 51 als fehlend, weil der Merge die Hashes nicht übernimmt —
die *Inhalte* der Runde sind da.

**Was ein Merge des Tips anrichten würde**, gemessen:

```
git diff main wmplugin --stat
  424 Dateien, 4700 Zeilen dazu, 88018 Zeilen WEG
```

Verschwinden würden unter anderem `tools/wayland/` (sechs Dateien),
`tools/wlan/` (`oracle.fi`, `vollweg.py`, `gegenstelle.py`) und
`tools/xtstafel/` — alles Arbeit, die nach dem 14.09. auf `main` kam.
Dazu käme `kernel/wm.fi` (9449 Z., `anim` 29×) **neben**
`kernel/ui/wm.fi` (11230 Z., `anim` 43×) zu liegen.

**Entscheidung: nicht mergen, die Runde ist drin.** Offen bleibt einzig
das Delta von zwölf Zusagen (207 → 219) und `kernel/user/zeile.fi` (ein
Schreibruf je Zeile, gegen zerrissene Meldungen auf der seriellen
Leitung). Beides gehört, wenn es jemand will, **neu gegen den heutigen
Baum** gebaut — der Zweig ist die Vorlage, `219/0` der Sollwert.

---

## 3. `viewer` — P-014 ist erledigt, nur anders

**Was er wollte.** Ein Bildbetrachter mit eigenem Bildstack:
`img.fi` (713 Z.), `imgpng.fi` (971), `imgjpeg.fi` (1419),
`imggif.fi` (546), `viewer.fi` (1476).

**Gilt es noch? Nein.** Die Runden **ALLTAG** (`df0fdb63`, „Bilder — PNG,
BMP und ein JPEG-Decoder") und **BILD** (`f0c36727`, „GIF lesen, als
JPEG sichern") haben den Betrachter unabhängig davon gebaut, und er ist
auf `main`:

```
kernel/user/viewer.fi  1048 Z.   das Fenster, -i Messausgabe, -s Sichern
kernel/user/image.fi    798 Z.   PNG (alle fünf Farbarten) und BMP, lesen und schreiben
kernel/user/jpeg.fi     640 Z.   JPEG lesen
kernel/user/jenc.fi     688 Z.   JPEG schreiben
kernel/user/gif.fi      648 Z.   GIF lesen (LZW, Farbtafeln, verschachtelt)
```

Damit kann `main` **PNG, BMP, JPEG und GIF** lesen sowie PNG und JPEG
schreiben — mehr, als der Zweig konnte. Dazu `assets/apps/viewer.osp`,
Vergrössern, Drehen, Blättern, Miniaturen.

**Punkt `P-014` der Offenliste („Bildbetrachter: Zweig ungemergt,
Ausbaustand unklar") ist damit sachlich erledigt** — nicht durch den
Zweig, sondern an ihm vorbei. Der Eintrag gehört geschlossen.

**Setzt er auf?** 18 Konflikte, `kernel/kstate.fi` als `modify/delete`,
`kernel/user/viewer.fi` als `add/add` gegen die heutige Fassung.

**Entscheidung: begraben.**

---

## 4. `supersearch` — der Werkzeugteil ist da, der Rest ist gefährlich

**Was er wollte.** Eine Suche (`sucher.fi`, `sucht.fi`) und dazu eine
ganze Messwerkstatt: `tools/look/`, `tools/paint/`, `tools/i18n/translit.py`.

**Gilt es noch? Grösstenteils nein.** Der wertvolle Teil — die
Messwerkstatt — ist längst auf `main`, aus der Runde **LOOK**:

```
tools/look/    compare.py corner.py hue.py inkbox.py inventory.sh run.sh shot.sh umlaut.py
tools/paint/   aacheck.py blendcheck.py native.c run.sh scalars.py shadow.py
docs/ROUNDLOOK.md   1139 Z.      docs/ROUNDPAINT.md   677 Z.
```

`pruef/anim-ab.sh` selbst ruft heute `tools/look/shot.sh` auf — die
Abnahme dieses Projekts hängt an Werkzeugen, die es schon hat.

**Setzt er auf? Nein, und ein Merge wäre teuer.** 24 Konflikte. Seine
`kernel/wm.fi` hat **`anim` 0×**, seine `wlib.fi` **3649 Z. mit
`zug_*` 0×** gegen 10475 Z. mit 4× auf `main`. Genau die Datei, in der
Justins Zieh-Aufhebung sitzt.

**Entscheidung: begraben.** Wenn eine Startmenü-Suche gewünscht ist,
ist sie ein Neubau — `kernel/user/find.fi` (Runde K11) und
`launcher.fi` sind der heutige Ausgangspunkt.

---

## 5. `media1` — vom Ton der späteren Runden überholt

**Was er wollte.** AC97-Treiber, Tonschicht, Abspieler, Lautstärke,
Containerformat: `ac97.fi` (841 Z.), `audio.fi` (789), `play.fi` (746),
`vol.fi` (266), `omc.fi` (324).

**Gilt es noch? Nein, und zwar belegt durch `main` selbst.**
`docs/AUDIO.md` auf `main` sagt im Kopf wörtlich:

> Diese Datei löst die gleichnamige aus Runde MEDIA1 ab. Was dort stand,
> gilt weiter; was diese Runde daran geändert hat, steht in Abschnitt 1.

Und weiter, als Probe auf die Rechnung von MEDIA1:

> „der HDA-Treiber der späteren Runde bedient GENAU diese Schnittstelle
> und KEINE Zeile darüber ändert sich." — **Die Behauptung stimmt zu
> zwölf Zwölfteln.**

Gemessen:

| | `media1` | `main` (`kernel/drv/snd/`) |
|---|---:|---:|
| `audio.fi` | 789 | **2075** |
| `ac97.fi` | 841 | **1024** |
| `hda.fi` | — | **2570** |
| `mix.fi` | — | **869** |

Die Grenze, die MEDIA1 entworfen hat, **hat gehalten** — sie wurde von
den Runden HDA und TON-2 ausgefüllt. Das ist der Erfolg des Zweigs, und
genau deshalb braucht ihn niemand mehr.

**Setzt er auf?** 9 Konflikte, `kstate.fi` und `einstellungen.fi` als
`modify/delete`, `play.fi` und `docs/AUDIO.md` als `add/add`.

**Entscheidung: begraben.** Offen bleibt allein der **Behälter**
(`omc.fi`, MP4/MKV) — derselbe Punkt, den schon `demux` offen liess
(siehe `docs/ALTZWEIGE-AUGUST.md`).

---

## 6. `snip` — ersetzt, und zweimal

**Was er wollte.** Bildschirmfoto und Ausschnitt: `snap.fi`,
`kernel/user/snip.fi`, ein eigener PNG-Schreiber (`png.fi`).

**Gilt es noch? Nein.** Auf `main` liegen **zwei** spätere Fassungen:

* `kernel/user/snip.fi` (759 Z., Runde **ALLTAG**) — das
  Ausschnittwerkzeug mit `snip -o`, `-v <sek>`, `-a fenster`; es
  versteckt sich vor der Aufnahme (`wlib.win_hide`).
* `kernel/ui/shot.fi` (418 Z., Runde **FEEDBACK**) — das Bildschirmfoto
  von innen, für Nutzer ohne QEMU-Monitor.

Der PNG-Schreiber steckt heute in `kernel/user/image.fi`
(`png_write`, `png_read`, Farbart 6 RGBA).

**Setzt er auf?** 21 Konflikte. `kernel/wm.fi` mit **`anim` 0×**.

**Entscheidung: begraben.** (`docs/ALTZWEIGE-AUGUST.md` hat `feedback`
aus demselben Grund begraben.)

---

## 7. `struktur` — von der eigenen Nachfolgerunde überholt

**Was er wollte.** Justins Kritik aufnehmen, dass die Treiber schlecht
abgelegt sind: 83 flache Dateien in `kernel/` nach `bus/`, `net/`,
`blk/`, `usb/` sortieren. Die Kritik war berechtigt.

**Gilt es noch? Nein — sie ist umgesetzt, nur von einem anderen Zweig.**
Am 17.09. hat **`struktur2`** dieselbe Aufgabe noch einmal gefahren,
gegen den damaligen `main`, und **ist gemergt**: `docs/STRUKTUR.md`
(42 325 Oktette) liegt auf `main`, dazu `tools/struktur/` mit elf
Werkzeugen. Der heutige Baum hat die Ordnung, die dieser Zweig wollte —
nur mit `kernel/drv/` statt `kernel/drivers/`.

**Setzt er auf? Am wenigsten von allen: 101 Konflikte**, darunter
`rename/rename` für jede Treiberdatei. Zwei Ordnungen desselben Baums.

**Entscheidung: begraben.** Der Zweig hat gewonnen, ohne gemergt zu
werden.

---

## 8. `netprofil` — der Gedanke lebt, der Code nicht

**Was er wollte.** Netz-Profil und -Statistik im Kern (`netprof.fi`
454 Z.) mit Oberfläche (`nprof.fi` 1200 Z., `npt.fi` 376 Z.).

**Gilt es noch? Grösstenteils nein.** `main` hat `kernel/net/` mit
`netmon.fi` (991 Z.), `netview.fi` (1034 Z.), `netmark.fi` (263 Z.),
dazu die eBPF-Kette und die Runde **O-NETZUI** (`1862d737`, „der
Live-Netzzustand in den Einstellungen"). Die Netzsicht ist da.

**Setzt er auf?** 15 Konflikte, `kernel/netdev.fi` als `modify/delete`
(auf `main` liegt es unter `kernel/net/netdev.fi`), dazu `settings.fi`,
`wlib.fi`, beide Sprachkataloge.

**Entscheidung: begraben.** Fehlt später eine bestimmte Zahl aus
`docs/ROUNDNETPROFIL.md` (493 Z.), steht sie dort weiter nachlesbar.

---

## 9. `nvmeq` — echte Arbeit, falscher Baum

**Was er wollte.** Das Ergebnis von `ring` weitertreiben. `RING-STATUS.md`
endet ehrlich mit: *„Der synchrone Weg wird auf einem Kern weiterhin
nicht geschlagen"* — weil die Arbeitsfäden intern **synchron** auf die
Platte gehen. Diese Runde nimmt ihnen das ab: der Auftrag geht in die
**Submission-Warteschlange des NVMe-Controllers**, das Gerät meldet sich
per Interrupt. `nvmeq.fi` (1209 Z.), `ring.fi` (1055 Z.),
`ringt.fi` (289 Z.), zwei Berichte über 1200 Zeilen.

Der Zweig hat sauber gemessen — und **seine Messgrenzen selbst benannt**:
alle drei Wege in *einem* Boot, weil auf der Maschine andere Runden
liefen (Lastmittel 11–13 auf 12 Kernen). Das ist gute Arbeit.

**Gilt es noch? Der Gedanke ja, der Code nein.** Er zweigte von `ring`
ab, nicht von `main`, und ist **1010 Commits** zurück. Auf `main` liegen
heute `kernel/drv/blk/nvme.fi` (979 Z.), `kernel/block/blk.fi` (1217 Z.),
`kernel/ipc/async.fi` (924 Z.) — alle seither weiterentwickelt.

**Setzt er auf?** 11 Konflikte, quer durch den Kern: `boot.s`, `trap.fi`,
`blk.fi`, `hw.fi`, `nvme.fi`, `kmain.fi` (6785 gegen 7832 Z.),
`proc.fi`, `sys.fi`, `uprog.fi` (+2551 Zeilen Differenz).

**Entscheidung: nicht mergen, aber nicht vergessen.** Das ist der
Kandidat für `B-005`/Blech (NVMe wurde bei der Installation nie
gemessen). Wer ihn aufnimmt, baut **neu gegen `kernel/drv/blk/nvme.fi`**
und nimmt die Zahlen aus `docs/NVMEQ-STATUS.md` als Sollwert.

---

## 10. `speicherdruck` — der einzige, der ganz gilt

**Was er wollte.** Punkt **`K-002`** der Offenliste, wörtlich:
*„Speicherdruck/OOM — keine Auswahl, keine Reserve. Bei vollem RAM
friert das System ein."*

**Gilt es noch? Ja — und der Zweig korrigiert dabei die Offenliste.**
Sein Bericht misst *zuerst*, wie es sich wirklich verhält, bevor eine
Zeile geändert wurde, und kommt zu einem anderen Ergebnis als der
Eintrag behauptet:

> **Der `mmap`-Weg friert NICHT ein.** Er gibt eine ehrliche Absage.
> Die Aussage der Offenliste ist in dieser Form also nicht mehr [richtig].

Die erste eigene Messung war zudem falsch — `brk` meldete `fail=448`,
was wie „kein Speicher" aussah und in Wahrheit das Ende des Adressraums
zwischen `BRK_BASE` und `MMAP_TOP` war (`0x70000` = 448 KiB). Dass der
Bericht diesen Irrtum offenlegt statt ihn zu verstecken, macht ihn
brauchbar.

Auf `main` gibt es **weiterhin keine OOM-Auswahl und keine Reserve**:
`kernel/mm/mem.fi` kennt `reserve`/`reserve_frame` nur für den
Startaufbau, `kernel/sched/sched.fi` spricht an einer Stelle von einem
„Opfer", ein Auswahlverfahren steht nirgends.

**Setzt er auf? Am besten von allen — 5 Konflikte:** `.gitignore`,
`kmain.fi`, `lib/kstate.fi`, `sched/proc.fi`, `sched/sched.fi`. Klein,
aber genau in den Dateien, in denen es weh tut: alle fünf sind
kdata-Belegung und Planer.

**Entscheidung: nicht mergen, neu bauen.** Die Sollwerte stehen im
Zweig und sind der Auftrag für die Runde:

```
tools/oom/run.sh       37 bestanden, 0 gescheitert
tools/mem/run.sh       50 bestanden, 0 gescheitert
tools/kernel/run.sh   176 bestanden, 0 gescheitert
tools/check-ui.sh     bleibt gruen
```

Mitzunehmen sind `P_HOG`/`P_HOGWRITE` (der Fresser, der bei jedem
Schritt sagt, wie weit er ist — ohne diese Ausgabe sieht ein gestorbener
Fresser aus wie ein hängender) und die Gegenproben
`nooom`/`noreserve`/`oomsay`/`koom`.

---

## 11. Der Stand von `main` nach dieser Sichtung

`main` ist **unverändert** — es wurde nichts gemergt, nichts gelöscht,
kein Zweig angefasst. Gemessen am Ende der Erhebung:

```
main                         c0cda62c
tools/check-ui.sh            PASSED — 196 Dateien, 0 Verstoesse,
                             Ausnahmen 3 Dateien / 14 Funktionen, alle begruendet
tools/build-kernel.sh        RC=0, 6 671 008 Oktette, 7421 Symbole
pruef/anim-ab.sh             anim=4  frames=0   <- Sollwert gehalten
```

Die Zeile aus dem Lauf, vollständig:

```
wm: vsync=0 comp=166 pres=0 pxsum=0 pend=0 anim=4 frames=0 ticks=2001
    sig=0 frame=166 motion=0 lift=0 tilt=0 swing=0 ziehpx=0 swings=0
```

Die übrigen Sollwerte (`abnahme.sh` 35/0, `hotplug` 45/0, `clip2` 32/0,
`logind` 49/0) wurden in dieser Erhebung **nicht** gefahren: es wurde
nichts verändert, was sie berühren könnte, und auf der Maschine liefen
durchgehend vier bis acht fremde QEMU-Prozesse bei 4,1 GB freiem Platz.
Eine Abnahme unter solcher Last misst die Last, nicht den Baum — das ist
derselbe Effekt, den `nvmeq` für `tools/ring/run.sh` (119/1 gegen 120/0)
und die Blur-Runde für `logind` (35/1 gegen 49/0) belegt haben.

---

## 12. Was offen bleibt

| # | Sache | woher |
|---|---|---|
| 1 | **OOM/Speicherdruck** neu bauen (`K-002`) | `speicherdruck`, Sollwerte Abschnitt 10 |
| 2 | **NVMe-Warteschlange** neu bauen (`B-005`) | `nvmeq`, `docs/NVMEQ-STATUS.md` |
| 3 | wmplugin: zwölf Zusagen **207 → 219** nachziehen, `zeile.fi` | `wmplugin` nach `f09af289` |
| 4 | Behälter MP4/MKV (`omc.fi`) | `media1`, vorher schon `demux` |
| 5 | `P-014` in der Offenliste **schliessen** | erledigt, siehe Abschnitt 3 |
| 6 | `K-002` umformulieren — „friert ein" stimmt nicht | siehe Abschnitt 10 |

---

## 13. Die Lehre, zum zweiten Mal

Zwei Sichtungen, fünfzehn Zweige, **null Merges**. Das Muster ist beide
Male dasselbe, und es ist kein Zufall:

**Ein Zweig, der einen Monat liegt, ist in diesem Projekt kein Zweig
mehr, sondern ein Bericht.** Nicht weil die Arbeit schlecht war — sie
war es bei keinem der neun —, sondern weil `main` schneller läuft, als
ein Zweig altern darf. In acht von neun Fällen war die Sache längst
erledigt, dreimal sogar *besser* als der Zweig es vorhatte
(`viewer`, `media1`, `struktur`). Bei `wmplugin` war sie sogar
buchstäblich schon gemergt und nur niemandem mehr präsent.

Der praktische Schluss, für das nächste Mal:

* **Was in einer Woche nicht nach `main` kommt, kommt gar nicht mehr.**
  Lieber früh und unfertig mergen als spät und perfekt.
* **Ein Zweig, der `sys.fi`, `kstate.fi`, `wm.fi`, `wlib.fi` oder
  `kmain.fi` anfasst, hat eine Halbwertszeit von Tagen** — das sind die
  Dateien, in denen jede Runde arbeitet.
* **Vor jedem Merge zählen, nicht schauen:** `grep -c anim`,
  `grep -c zug_` auf beiden Seiten. Git meldet den stillen Verlust nicht.
* **Der Wert eines alten Zweigs steckt im Bericht, nicht im Code.**
  Deshalb bleiben alle neun stehen.
