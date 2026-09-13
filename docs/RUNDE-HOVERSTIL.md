# Runde HOVERSTIL — der Zeiger im Bild, und zwei echte Fehler dabei

Zweig `hoverstil`. Zwei Auftraege: den Hover endlich **fotografieren**
statt ihn im Quelltext nachzuweisen, und belegen, was fUi beim Rand und
bei den Farben wirklich kann.

Die Kurzfassung: der Hover **war kaputt**, und zwar an zwei Stellen.
Beide sind behoben, beide mit Bild und Zahl belegt. Ausserdem waren
**zwei Fehler im Messaufbau** der Grund, warum die Vorrunde nichts
sehen konnte — die sind hier ebenfalls benannt, damit sie niemand
wiederholt.

---

## Teil 1 — warum die Vorrunde nichts sah

### Fund 1: `/etc/uitrace` ist der Stummschalter

`kernel/user/qs.fi::dbg_setup` macht **alle** Meldungen des
Kontrollzentrums von einer Datei abhaengig:

```
let fdt: u64 = io.open("/etc/uitrace", 0)
if !ulib.bad(fdt) { s_dbg = 1 }
```

und `say`/`sayn`/`nl` kehren ohne sie sofort zurueck. Fehlt die Datei,
laeuft das Panel **vollstaendig richtig** — es geht auf, es geht zu,
der Zeiger wirkt — aber es steht **keine einzige `qs:`-Zeile** auf der
Leitung.

Gemessen wurde genau das:

```
hk: super+a          5 x  (die Taste kommt an)
id=10 ... fl=19 -> fl=18   5 x  (das Panel gehorcht: versteckt -> sichtbar)
qs: kachel                 0 x
qs: dbg (eigens eingebaut) 0 x
```

Wer daraus „die Maus kommt nicht an" schliesst, misst diesen Schalter
und nicht das System. `tools/usbimg/build.sh` legt die Datei jetzt mit
`UITRACE=1` ins Abbild; ein Auslieferungsstick bleibt still.

### Fund 2: `usb-tablet` ist absolut, dieser Kern liest nur relativ

`kernel/hidin.fi::mouse_report_boot` liest Oktett 1 und 2 als

```
let dx: u64 = sbits(p + 1, 0, 8)
let dy: u64 = sbits(p + 2, 0, 8)
```

Das ist das **Boot-Protokoll** der USB-Maus: ein Oktett je Achse, mit
Vorzeichen, also ein **Schritt**. Ein Tablet schickt an derselben
Stelle eine **absolute** Lage in 16 Bit. Gemessen:

| Geraet | Pakete | Bewegungen | Zeiger |
|---|---|---|---|
| `usb-tablet` | pk=178 | **bew=0** | springt nur zwischen 0,0 und 1279,799 |
| `usb-mouse` | pk=140 | **bew=140** | landet exakt auf dem Ziel |

Ein Klick braucht nur einen Ort — den setzt auch ein kaputt gelesenes
Tablet gelegentlich richtig. Eine **Ueberfahrung** braucht eine
**Bewegung**, und die gab es mit dem Tablet nie. `pruef/start.sh` hat
dafuer jetzt `$MAUS`.

### Fund 3 (der echte Fehler): niemand malte nach dem Hover neu

`qs.step()` rechnet den Zeigerzustand **richtig** aus. Gemessen, mit
einer eigens eingebauten Diagnosezeile:

```
qs: mv x=185 y=48     ein EV_MOVE kommt im Panel an
qs: hov t=1 f=99      hover_set: Kachel 1 ist jetzt drunter
```

Nur hat danach **niemand neu gemalt**. Die Leiste wirft den
Rueckgabewert weg — `let _qsc: bool = qs.step()`, und zwar an **zwei**
Stellen (`kernel/user/taskbar.fi:5923` und `:6106`) — und `step` selbst
malte nur ueber `click()`. Deshalb war im Bild kein Unterschied
zwischen „Zeiger drueber" und „Zeiger woanders".

Der Fix steht in `qs.fi::step` und nicht in der Leiste: das Fenster
gehoert `qs`, und ein Aufrufer, der sich an zwei Stellen merken muss,
nach `step` zu malen, ist die Naht, an der es wieder auseinanderlaeuft.

```firn
if changed && open_ != 0 {
    let _g: u64 = wlibc.theme_frame_begin()
    paint(false)
    let _s: bool = wlibc.theme_frame_end()
}
```

### Fund 4 (der zweite echte Fehler): im Dunkeln war Hover == Ruhend

`kernel/user/wlibc.fi` gab im dunklen Zweig **derselben Stufe** zwei
Rollen:

```
sem[S_SURFACE_RAISED] = neutral[N_800]
sem[S_SURFACE_HOVER]  = neutral[N_800]     <-- gleich
```

und `C_BUTTON_FACE -> S_SURFACE_RAISED`, `C_BUTTON_HOVER ->
S_SURFACE_HOVER`. Gemessen: `bg=2565930 bthi=2565930`, beide
`#27272A`. Der Zeiger ueber einer ausgeschalteten Kachel oder einem
Fussknopf aenderte **gar nichts** (Abstand 0 von 255), waehrend
derselbe Fall hell 14 Stufen Unterschied hat.

Jetzt: Hover `N_700`, Gedrueckt `N_600`. Gedrueckt musste mitwandern —
sonst waeren ueberfahren und gedrueckt gleich, der Fehler waere nur
verschoben. Vier Stufen statt zwei:

```
Grund 900 (#18181B) - Flaeche 800 (#27272A) - hover 700 (#3F3F46) - gedrueckt 600 (#52525B)
```

Der Kontrast bleibt gut: Text `n50` auf `n700` = **10,01:1**
(WCAG AA verlangt 4,5:1).

---

## Teil 1 — die Messung

`pruef/hoverprobe.py` faehrt den Zeiger in vielen kleinen **relativen**
Schritten auf ein Ziel, **ohne zu klicken**, und fotografiert vorher
und nachher aus **demselben Lauf**.

### Die vier Faelle, hell (Schema `day`, 1280x800)

| Fall | ruhend | mit Zeiger | Abstand |
|---|---|---|---|
| Kachel **aus** | `#FFFFFF` | `#F1F5F9` | 14 |
| Kachel **an** | `#2563EB` | `#8BACF2` | 102 |
| Fussknopf | `#FDFDFE` | `#F0F4F8` | 13 |

### Die vier Faelle, dunkel (Schema `midnight`)

| Fall | ruhend | mit Zeiger | Abstand |
|---|---|---|---|
| Kachel **aus** | `#27272A` | `#3F3F46` | 28 *(vorher 0)* |
| Kachel **an** | `#B799F9` | `#7B6C9F` | 90 |
| Fussknopf | `#28282B` | `#3E3E45` | 26 *(vorher 0)* |

**Vier unterscheidbare Farben in beiden Themen** — der Hover frisst die
Zustandsinformation nicht. Genau das war die Bedingung.

### Der Zeiger ist wirklich im Bild

Gezaehlt wurden die stark geaenderten Bildpunkte in einem 28x28-Fenster
um den Zielort, zwischen dem Bild ohne und dem mit Zeiger:

```
kachel-aus   Zeiger bei (1082,510):  98 Punkte
kachel-ein   Zeiger bei  (957,510): 723 Punkte
fuss-0       Zeiger bei (1210,730): 100 Punkte
```

### Der Schieberegler — ein Befund, kein Fehler

```
regler  rinne 929..1266 ym=656   ohne #FFFFFF  hover #FFFFFF  d=0
```

Der Regler hat in diesem Panel **keinen eigenen Hover-Zustand**. Er hat
einen Wert, und der aendert sich beim **Ziehen** (Runde
ECHTHARDWARE-3). Ein Abstand von 0 ist hier die richtige Antwort und
nicht ein Defekt. Wer ihn will, muss ihn bauen — das waere eine eigene
Runde.

### Wo die Bilder liegen

* `pruef/shots-hoverstil/` — die vier Belegbilder im Repo
  (`hover-viervergleich-hell.png`, `-dunkel.png`,
  `hover-kachel-ein-hell.png`, `hover-kachel-aus-dunkel.png`)
* `pruef/laeufe-hoverstil/HELL.json` und `DUNKEL.json` — die Messwerte
* `/root/hvwork/bilder/` — alle zwoelf Bilder des Laufs, ungekuerzt

Den Lauf selbst wiederholt man mit:

```
cd pruef
MAUS="-device usb-mouse" python3 hoverprobe.py HELL 1280 800
KERN=osum-dunkel.mb WURZEL=root-dunkel.img MAUS="-device usb-mouse" \
    python3 hoverprobe.py DUNKEL 1280 800
```

Die Abbilder dazu:

```
UITRACE=1 bash tools/usbimg/build.sh /pfad/bau
UITRACE=1 THEMA=mitternacht bash tools/usbimg/build.sh /pfad/baud
```

---

## Teil 2 — Rand und Farbe in fUi

Die Arbeit dazu liegt im **Firn-Baum**, Zweig `fui-stilgalerie`
(Commit `5187930f`), nach Justins Regel: was fUi nicht kann, wird in
fUi eingebaut und nicht im Programm nachgebaut.

* `tools/fui/rand_main.fi` — malt jede Fassung und **misst sie nach**
* `docs/FUI-RAND-UND-FARBE.md` — die Anleitung, deutsch
* `tools/fui/run.sh` — ruft die Pruefung als Abschnitt `10c` auf

Elf Pruefungen, alle bestanden. Der wichtigste Befund dreht die Frage
um: **in diesem Thema hat ein Knopf von Haus aus keinen Rand**
(`render.def_border` gibt `color_transparent()`, `def_border_width`
gibt 0 — „tone=0" in `osum.shape`). Die Frage ist nicht, wie man den
Rand wegbekommt, sondern wie man einen hinbekommt.

Was **nicht** geht, ehrlich benannt: Rand pro Seite, gestrichelter
Rand, Randbreite/Radius im Hover aendern, Farbverlauf als Flaeche
(`style_set_gradient` wirkt auf den **Text**), Fokusring getrennt
einstellen. Alle vier sind kleine, aber echte Umbauten an
`Style`/`Override` — Begruendung in `docs/FUI-RAND-UND-FARBE.md`.

---

## Was in dieser Runde geaendert wurde

| Datei | Was |
|---|---|
| `kernel/user/qs.fi` | `step()` malt nach einer Zustandsaenderung selbst neu |
| `kernel/user/wlibc.fi` | dunkles Schema: Hover `N_700`, Gedrueckt `N_600` |
| `tools/usbimg/build.sh` | `UITRACE=1` legt `/etc/uitrace` ins Abbild |
| `pruef/start.sh` | `$MAUS` (relativ statt Tablet), `$KERN`/`$WURZEL` |
| `pruef/hoverprobe.py` | **neu** — der Zeiger faehrt, ohne zu klicken |
| `pruef/laeufe-hoverstil/`, `pruef/shots-hoverstil/` | Messwerte und Belegbilder |
