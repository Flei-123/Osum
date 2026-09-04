# RUNDE STANDBILD — warum die Messtafel dreimal nicht kam

Justins Foto vom Blech (Abbild `aa191ec2`, Commit `4ca1d9ee`, Eintrag
"Schreibtisch", 3440x1440): blauer Schreibtisch, ein stehender
Mauszeiger, **sonst nichts**. Keine Taskleiste, kein Terminalfenster,
**keine Messtafel** — obwohl sie in der Runde davor ausdruecklich an den
Zeitgeber gehaengt und mit 453 Anstrichen gemessen worden war.

## Das Ergebnis zuerst

**Es war Ursache 1, und es war mein Fehler.** Nicht die
`wmdauer`-Bedingung selbst, sondern eine ZWEITE Sperre eine Zeile
darunter, die ich beim Bauen uebersehen habe.

```
fn tafel_tick(state: u64) {
    if !kstate.mode_on(state, kstate.M_WMDAUER) { return }
    if tafel_hat == 0 { return }        <-- DAS HIER
    ...
}
```

`tafel_hat` wird an **genau einer** Stelle gesetzt: in `tafel_merken`.
`tafel_merken` ruft **nur** `kopf_malen`. `kopf_malen` ruft **nur**
`wait_wm` — die Schreibtischschleife.

**Damit hing der angeblich zeitgeber-getriebene Weg weiterhin daran,
dass die Schleife mindestens eine volle Runde gelaufen war.** Der
Umbau der Vorrunde war wirkungslos fuer genau den Fall, fuer den er
gebaut wurde.

In QEMU lief die Schleife, `tafel_hat` wurde 1, der Zeitgeber malte —
und die Messung "453 Anstriche allein aus dem Zeitgeber" war richtig
gemessen und trotzdem irrefuehrend. Auf Justins Brett laeuft die
Schleife nie eine volle Runde, `tafel_hat` bleibt 0, es kommt nichts.

## Der Beweis (A/B, gemessen)

Justins Fall laesst sich ohne Blech herstellen: **`wmshell` weglassen**.
Dann ruft `kgui` `wait_wm` gar nicht, also nie `kopf_malen`, also bleibt
`tafel_hat` 0 — dieselbe Bedingung wie auf dem Blech.

Beide Laeufe: `modfs osum gfx fbres=3440x1440 wm wig desk wmdauer …
nosched noproc nofs`, **ohne `wmshell`**, gleiche Maschine, gleiches
`root.img`.

| Kern | Tafelzeilen seriell | Balken im Bild |
|---|---|---|
| `4ca1d9ee` (mit `tafel_hat`-Sperre) | **0** | **keiner** (0 von 3440 schwarzen Punkten in y=5) |
| diese Runde (ohne Sperre) | **9** | **volle Breite**, Trennlinie bei y=435 |

Und die Zeile, auf die es ankommt:

```
tafel: 8 TAKT   IRQ 3500 MAL 351 LOOP 0
```

**`LOOP 0`** — die Schleife lief kein einziges Mal, und die Tafel stand
trotzdem 351-mal auf dem Schirm. Das ist der Nachweis, den die
Vorrunde nur scheinbar erbracht hatte.

## Die anderen drei Ursachen — ausgeschlossen, nicht geraten

**2) Kommt der Zeitgeber-IRQ auf Blech an?**
`nosched` und `notimer` sind **zwei verschiedene Schalter**
(`kstate.M_NOSCHED` = 12, `M_NOTIMER`). Nur `notimer` ruft
`hw.timer_off`; `nosched` laesst den Zeitgeber laufen und ueberspringt
lediglich das Aufsetzen des Ablaufplaners (`kmain.fi:1000`), womit
`PREEMPT` auf 0 bleibt. `sched.on_tick` kehrt dann frueh zurueck — **aber
`gfx.tafel_tick` steht in `trap.fi` VOR `sched.on_tick`** und ist davon
nicht betroffen. Gemessen mit exakt Justins Kommandozeile (`nosched`
inbegriffen): `IRQ 5000`. Der Zeitgeber schlaegt. **Ausgeschlossen.**

**3) Schreibt die Tafel in den richtigen Puffer?**
`fb.spot` rechnet den Versatz bei **jedem** Aufruf neu aus
`kstate.get(state, FB_OFF + S_PITCH)` — keine zwischengespeicherte
Zeilenlaenge, keine gemerkte Adresse. `fb.pixel` schreibt nach
`S_DRAW`, also in das aktuelle Ziel. Entscheidender ist die
Gegenprobe auf Justins eigenem Foto: **der blaue Hintergrund und der
Mauszeiger sind da**, und die entstehen durch `fb.fill` und `fb.pixel`
— dieselben zwei Funktionen, die die Tafel benutzt. Traefe die
Malroutine den Schirm nicht, waere auch der Schreibtisch schwarz.
**Ausgeschlossen.**

**4) Das fehlende Terminalfenster — offen, und das sage ich so.**
Ich kann es **nicht beweisen**. Fakten: das Fenster entsteht in
`kgui.surface()` innerhalb von `if M_WMSHELL`, und beide Eintraege
("Schreibtisch" und "Desktop (English)") tragen `wmshell` — der
Menue-Umbau erklaert es also **nicht**. Hintergrund und Zeiger stammen
aus einem `compose` davor. Daraus folgt nur: der Kern kam bis zum
ersten `compose` und danach nicht mehr bis zum sichtbaren
Fensterbau. **Warum**, sagt kein Foto, das ich habe.

Genau dafuer ist das Standbild dieser Runde gebaut.

## Was gebaut wurde

### 1. Ein Schalter statt einer Annahme: `tafel`

`kstate.M_TAFEL` (840), geparst in `kmain.fi`. Die Bedingung heisst
jetzt `tafel` auf der Kommandozeile und nicht mehr `wmdauer`.

Der alte Grund fuer `wmdauer` war die Annahme, es stehe "auf jedem
Schreibtisch-Eintrag und auf keinem Laeufer". **Das war falsch:**
`tools/hidpunkte/run.sh` setzt `wmdauer` ebenfalls. Ein Schalter, der in
einer Umgebung greift und in der anderen nicht, ist genau die Art
Bedingung, die diese Runde gekostet hat.

* **Blech:** die fuenf Schreibtisch-Eintraege tragen jetzt `tafel`.
* **Laeufer:** kein einziger setzt `tafel` (geprueft). Damit ist die
  Tafel dort aus, und zwar **benannt** statt geraten.

### 2. `tafel_hat`-Sperre weg

Ein Messgeraet darf keinen Messwert brauchen, um anzugehen. Ohne Inhalt
zeigt es Nullen — und das ist die Aussage, auf die es ankommt.

### 3. Zwei unbedingte Standbilder

Direkt aus dem Kern gemalt, eigener `fb.flush`, ohne Zeitgeber, ohne
Schleife, ohne Ring 3:

* **STUFE 1** — in `kgui.surface()` direkt nach `fb.clear` /
  `wm.damage_all`, **vor** dem Terminalfenster. Der frueheste Punkt mit
  Rahmenpuffer und Zeichensatz.
* **STUFE 2** — hinter allen Fenstern, **vor** dem ersten
  Ring-3-Programm.

Zeile 0 traegt die Stufe (`STANDBILD STUFE 1` / `STUFE 2`). Leere Zeilen
werden mit `-- noch keine Messung --` gefuellt, damit eine leere Tafel
nicht mit einer fehlenden verwechselt wird.

**Damit trennt Justins naechstes Foto endlich:**

| Was zu sehen ist | Was es heisst |
|---|---|
| gar keine Tafel | die Malroutine trifft den Schirm nicht |
| `STANDBILD STUFE 1`, sonst nichts | Kern steht zwischen Fensterbau und Ring 3 — **das erklaert das fehlende Terminalfenster** |
| `STUFE 2`, Zahlen stehen still | Kern lebt, Zeitgeber tot |
| `IRQ` laeuft, `LOOP` steht | Zeitgeber lebt, Hauptschleife haengt |
| beides laeuft | alles in Ordnung |

### 4. Serielle Ausgabe unabhaengig von der Schleife

Bisher setzte nur der Puls in `wait_wm` die Marke — lief die Schleife
nicht, kam auch seriell nichts. Jetzt taktet `tafel_tick` die Ausgabe
selbst (alle 5 s, `TAFEL_SERMARKEN`).

**Zur seriellen Schnittstelle:** die Schreibtisch-Eintraege haben
**kein** `console=ttyS0` — das brauchen sie auch nicht. `console=ttyS0`
macht COM1 zum EINGABE-Terminal; die Ausgabe ueber `serial.puts` laeuft
unabhaengig davon und ab dem Kernstart. Wer mitlesen will, braucht nur
den Adapter, nichts an der Kommandozeile.

## Abnahme

* A/B oben: `0` gegen `9` Tafelzeilen bei `LOOP 0`.
* Vollauf mit Justins Kommandozeile: beide Standbilder, `IRQ 5000
  MAL 641 LOOP 139` (**502 Anstriche aus dem Zeitgeber**),
  `taskbar: STEHT`, Terminalfenster gebaut.
* `tools/wm/run.sh`: **104 bestanden, 0 gefallen** — die Tafel ist dort
  aus, weil kein Laeufer `tafel` setzt.
