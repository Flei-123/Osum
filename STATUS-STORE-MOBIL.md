# Runde STORE-MOBIL (OrientOS-Seite) — `/bin/ota` zeigt nur, was passt

Arbeitsbaum `/root/osum-store`, Zweig `store-mobil` (von `merge6`).
Nichts gemergt, nichts gepusht.

## Welcher Client — und welcher NICHT

* **`kernel/user/ota.fi` (`/bin/ota`)** ist der Store-Client von
  OrientOS: er holt `VERZEICHNIS` von der Quelle, prueft die Signatur
  und listet die Pakete. **Hier wurde gefiltert.**
* `kernel/user/bstore.fi` ist der **Backup**-Store (Bloecke,
  Schnappschuesse, Wiederherstellung) — mit dem App-Store hat er nur den
  Namen gemein.
* `kernel/user/storage.fi` ist das **Plattenplatz**-Werkzeug
  (Gegenstueck zu TreeSize/WizTree).

Eine grafische Store-Oberflaeche gibt es auf OrientOS heute nicht;
deshalb war fuer diese Runde nichts mit `wlib` zu zeichnen. Sobald es
sie gibt, ruft sie dieselbe Regel auf.

## Das VERZEICHNIS

Eine sechste Spalte je Paketzeile: das **Plattformwort**.

```
hallo      2.0.0  <sha256>  <groesse>  hallo-2.opk      osum-x86_64
hallo-arm  2.0.0  <sha256>  <groesse>  hallo-arm-2.opk  osum-aarch64
daten      1.0.0  <sha256>  <groesse>  daten-1.opk      osum-any
```

`osum-any` heisst: kein ELF in der Nutzlast, laeuft auf jeder Maschine.
`tools/ota/veroeffentlichen.py` schreibt die Spalte, `tools/ota/plattform.py`
leitet sie ab (`arch=` im Paketkopf, sonst `e_machine` des ELF),
`tools/ota/listing.py` liest sie.

**Rueckwaerts:** eine Zeile OHNE sechste Spalte wird **ausgeblendet und
gezaehlt**, nicht stillschweigend installiert. Ein Verzeichnis von vor
dieser Runde macht `/bin/ota` also leer, aber nie falsch.

## Was `/bin/ota suchen` jetzt sagt

```
ota: quelle https://10.0.2.2:19126
ota: fassung hier 0
ota: fassung dort 2
ota: NEUE FASSUNG verfuegbar
ota: plattform osum-x86_64
ota: paket daten 1.0.0 osum-any
ota: paket hallo 2.0.0 osum-x86_64
ota: fuer andere Plattformen ausgeblendet: 1
ota: ohne Plattformangabe ausgeblendet: 1
```

Die eigene Plattform wird **genannt**, nicht vorausgesetzt, und das
Ausgeblendete wird **gezaehlt** — sonst haette ein Nutzer, dem ein Paket
fehlt, keine Erklaerung.

## Gemessen

`bash tools/ota/plattformprobe.sh` — **18 gruen, 0 rot**.

Echte Maschine (QEMU, e1000, Benutzernetz), echte Gegenstelle
(`tools/ota/server.py`, TLS 1.3), zwei Durchgaenge:

1. gemischte Quelle: `hallo` (x86-64) und `daten` (any) kommen,
   `hallo-arm` (dasselbe ELF mit `e_machine=183`) kommt **nicht**;
2. dasselbe Verzeichnis, aus dem eine sechste Spalte herausgeschnitten
   und **neu signiert** wurde: die Zeile wird ausgeblendet und gezaehlt.

`bash tools/ota/plattformbild.sh` macht ein Bildschirmfoto derselben
Maschine (QEMU `-vga std` + Monitor + `screendump`, der Weg aus Runde
K15): `/tmp/ota-plattform/ota-plattform.png`. **Ehrliche Einordnung:**
`/bin/ota` schreibt auf die serielle Leitung, der VGA-Schirm zeigt die
Bootkonsole — das Bild belegt die Maschine, der Wortlaut oben belegt die
Ausgabe.

## Dieselbe Regel, zweimal umgesetzt

`tools/ota/plattform.py` (OrientOS) und
`/root/orientstore/werkzeug/plattform.py` (Store) beantworten dieselbe
Frage. Die Android-App (`Katalog.Paket.passt`) ist die dritte Umsetzung.
Drei Umsetzungen sind eine Gefahr; sie werden deshalb **gegeneinander**
gemessen (T12 im Store-Repo, plattformprobe hier).
