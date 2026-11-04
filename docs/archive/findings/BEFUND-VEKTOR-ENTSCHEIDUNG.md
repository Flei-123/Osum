# VEKTOR — Schritt 1: portieren oder neu bauen?

Diese Datei beantwortet die Auflage "die Entscheidung musst du
schriftlich begruenden", und zwar VOR der ersten Zeile Unterbau.

Geprueft wurde `/root/firn-dnspic/lib/paint/{painter,canvas,stroke}.fi`
und `/root/firn-dnspic/lib/font/{ttf,raster}.fi` gegen die
Randbedingungen von `profile kernel` in Osum.

## 1. Was Firn hat

| Datei | Zeilen | Was drin steht |
|---|---:|---|
| `lib/paint/painter.fi` | 1241 | runde Ecken, Raender, zwei Verlaufsarten, Schatten mit Unschaerfe, Beschnitt, Mischmodi |
| `lib/paint/stroke.fi` | 833 | Strichzeichnen: Breite, Enden, Ecken, Gehrung, Boegen |
| `lib/paint/canvas.fi` | 744 | ein gemischter Bildpunkt |
| `lib/font/raster.fi` | 928 | Deckungsrasterer, Zellen, Kantenaufsummierung |

Das ist echte, erprobte Arbeit, und der Auftrag sagt zu Recht:
portieren spart Wochen. Deshalb wurde zuerst gemessen, ob es geht.

## 2. Der harte Befund: Gleitkomma

Gezaehlt mit `grep -c f64`:

| Datei | Treffer `f64` |
|---|---:|
| `lib/paint/painter.fi` | 178 |
| `lib/paint/stroke.fi` | 101 |
| `lib/font/raster.fi` | 83 |

Und die Gegenprobe in Osum, ueber **alle 109** `kernel/*.fi`:

```
$ grep -l 'f64' kernel/*.fi | wc -l
0
```

Keine einzige Kerneldatei benutzt Gleitkomma. Das ist kein Zufall und
keine Gewohnheit, es ist eine niedergeschriebene Regel. `docs/ROUNDK10W.md`,
Abschnitt 4.2, Zeile 274:

> Es gibt keine Gleitkommazahlen in diesem Kernel und es soll keine
> geben: `profile kernel` hat keine SSE-Rettung im Kontextwechsel, und
> eine Rasterung, die je nach Rundungsmodus anders aussieht, ist nicht
> nachpruefbar.

Zwei Gruende, beide bindend:

1. **Kein SSE im Kontextwechsel.** `kernel/arch/x86_64/switch.s` rettet
   die SSE-Register nicht. Ein `f64` im Fensterserver, den eine
   Unterbrechung trifft, verliert seinen Wert oder verdirbt den eines
   anderen Fadens. Das ist kein Leistungsproblem, das ist ein Fehler,
   der sich nur sporadisch zeigt — die schlimmste Sorte.
2. **Nachpruefbarkeit.** Der Selbsttest aus Auflage 3 vergleicht
   gerasterte Formen mit Referenzwerten. Mit Gleitkomma haengt das
   Ergebnis am Rundungsmodus; in Festkomma ist es auf jeder Maschine
   dasselbe Bit.

Dazu kommt die gepruefte Arithmetik: unter `profile kernel` ruft ein
ueberlaufendes `+` `osum_panic` (SPEC 13 L9, `docs/OSUM-K1.md`). Jede
uebernommene Zeile muesste auf Subtraktion-statt-Addition umgeschrieben
werden — auch dort, wo Firn sich auf stillen Ueberlauf verlaesst.

## 3. Was ein "Port" praktisch hiesse

`painter.fi` haengt an `html.mem`, `browser.node`, `css.cascade`,
`layout.box`, `paint.display`, `paint.png` — an einem Anzeigebaum, den
ein Kernel nicht hat. Der Unterbau von `stroke.fi` und `raster.fi` ist
sauberer (`#[no_gc]`, schreibt direkt in den Rasterer, eigener Puffer),
aber jede zweite Zeile rechnet in `f64`.

Eine Portierung waere also: jede Zeile anfassen, jede Zahl von
Gleitkomma auf 26.6 umstellen, jede Addition auf Ueberlauf pruefen, die
Fremdbezuege herausschneiden. Das ist keine Uebernahme, das ist eine
Neuschrift mit fremder Vorlage — und sie erbt die Fehler, die man beim
mechanischen Umschreiben macht, ohne die Vorteile der Erprobung: der
erprobte Code ist der mit `f64`, nicht der umgeschriebene.

## 4. Was Osum schon selbst hat

Der Kernel ist an dieser Stelle nicht arm, er ist nur unsortiert. Es
gibt bereits **drei** Verfahren, alle in Festkomma, alle erprobt:

| Ort | Verfahren |
|---|---|
| `kernel/ttf.fi` | Glyphumrisse, quadratische Bezier, **26.6**, Nichtnull-Windung, 4x4-Unterabtastung |
| `kernel/zeiger.fi` | Vieleck, Punkt-in-Vieleck mit 3x3-Ueberabtastung, drei Deckungslagen |
| `kernel/wm.fi:1169` `corner_cov` | Kreisdeckung, 4x4-Unterabtastung |

Das ist genau Justins Klage: drei Verfahren fuer dieselbe Frage
("wie stark deckt diese Form diesen Bildpunkt?"). `corner_cov` kann nur
Kreise, `zeiger.fi` nur Vielecke, `ttf.fi` nur Glyphen.

Die **Rechenart steht damit aber fest und ist erprobt**: 26.6 Festkomma,
Nichtnull-Windung, 4x4-Unterabtastung, Deckung `(cov * 255 + 8) / 16`.
`ttf.fi` rastert damit seit Runden echte Schriften.

## 5. Entscheidung

**NEU BAUEN, in Osums eigener 26.6-Rechenart, mit `stroke.fi` als
fachlicher Vorlage fuer die Strichgeometrie (Enden, Ecken, Gehrung) und
`ttf.fi` als Vorlage fuer Fuellregel und Unterabtastung.**

Nicht portiert wird der Code; uebernommen werden die Verfahren. Konkret
aus Firn uebernommen:

* die Zerlegung von Boegen in Bezier ueber `kappa = 0.5522847` — in 26.6
  als ganzzahlige Konstante `KAPPA_266 = 35` (0.5522847 * 64 = 35.3)
* die Strichlogik aus `stroke.fi`: Normale je Segment, Ecke je nach
  Art, Ende je nach Art
* die Trennung "Deckung erst sammeln, dann mischen" aus `painter.fi` —
  der Grund, warum ein Rand die DIFFERENZ zweier Formen ist und nicht
  zwei uebereinandergemalte Rechtecke

Der Aufwand ist ehrlich hoeher als ein Dateikopieren, aber niedriger als
eine Portierung mit anschliessender Fehlersuche in fremdem
Gleitkommacode, den der Kernel gar nicht ausfuehren darf.

## 6. Was das fuer die Auflagen heisst

* **16 ms**: 26.6 in Ganzzahl ist auf dieser Maschine schneller als
  Gleitkomma waere, und der Zwischenspeicher fuer gerasterte Formen
  kommt von Anfang an mit hinein.
* **Selbsttest**: in Festkomma sind Referenzwerte exakt, nicht
  "ungefaehr gleich".
* **Ein Verfahren statt drei**: `zeiger.fi` und die Widgets kommen auf
  `vektor.fi`; `ttf.fi` behaelt seinen eigenen Weg fuer Glyphen, weil
  er dort schon dieselbe Rechenart benutzt und ein Umbau nur Risiko
  ohne Gewinn waere. Das ist eine bewusste Ausnahme und steht hier,
  damit sie niemand fuer ein Versehen haelt.
