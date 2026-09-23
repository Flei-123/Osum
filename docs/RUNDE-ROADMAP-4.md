# Runde ROADMAP-4 (24.09.2026)

Auftrag: A-028 (sync-Laeufer patcht Quelltext im Baum), A-031 (Umlaut-
Rest) und A-029 (storage-Abbild). Die zwei Punkte, die Justin
entscheiden muss (Live-Store neu veroeffentlichen, neues Abbild auf den
PC), sind NICHT angefasst.

## Was gemessen wurde

| Laeufer | vorher | nachher | Ursache |
|---|---|---|---|
| `sync` | 88/1 | **90/0** | A-028 (+1 Zusage: Baum unangetastet); `(h)`: `/bin/sleep` fehlte auf dem Geraet |
| `umlaut` | 41/10 | **51/0** | A-031 |
| `storage` | brach beim Bauen ab | **27/0** | A-029 |
| `xtstafel` | 6/0, patchte `lib/` im Baum | **7/0** | gleiche Klasse wie A-028 |
| `clip2` | 32/0, patchte `kernel/` im Baum | **32/0**, Baum unangetastet | gleiche Klasse wie A-028 |
| `ebpf` | 81/0 | 81/0 | erwartet jetzt die Umlautsaetze |
| `ota` | 107/0 | **107/0** | Pflicht, Kern geaendert |

Pflicht-Abnahmen nach den Kernaenderungen: `install/abnahme.sh` 35/0,
`hotplug` 45/0, `clip2` 32/0, `check-ui` PASSED, `anim-ab` anim=4.

## A-028 -- die Gegenproben bauen aus einer Kopie

`tools/sync/build.sh` nimmt `USRC` (Standard `kernel/user`). Die
Gegenproben j3 und j4 kopieren `kernel/user` nach `$TMPD/usrc-j3|j4`,
setzen dort die kaputte `sync.fi` ein und bauen von dort. Der trap, der
die Datei zurueckspielte, ist weg; am Ende vergleicht der Laeufer die
sha256 von `kernel/user/sync.fi` mit dem Stand vom Anfang. Ein
Waechter, der waehrend des ganzen Laufs jede Sekunde die Datei hashte,
sah 527 Proben ohne eine Abweichung. j3 und j4 greifen weiter.

**Dieselbe Klasse an zwei weiteren Stellen gefunden und behoben:**
`tools/xtstafel/run.sh` verbog `lib/crypto/xts.fi` im Baum -- sogar ohne
trap; `tools/clip2/run.sh` stellte `kernel/user/explorer.fi` fuer
mehrere Minuten auf `drop_an(false)`. Das zweite wurde live gesehen:
waehrend clip2 lief, zeigte `git status` den Dateimanager veraendert,
und jeder parallele Bau haette ihn so mitgenommen. Beide arbeiten jetzt
auf Kopien und pruefen am Ende per sha256, dass der Baum unveraendert ist.

## A-031 -- der Umlaut-Rest

Die zehn roten Zusagen hatten vier Ursachen:

1. **33 SICHTBAR-Funde im Quelltext.** Einzeln entschieden, mit der
   Lehre aus A-025: was ein anderes Programm Oktett fuer Oktett liest,
   bleibt ASCII und bekommt `// DRAHT:` -- Kernzeilenwoerter
   (`gastgeraet`, `kryptopruef`, `schlafpruef`, `wachpruef`), Messfelder
   (`dual: menue=`, `gr-gross`, ` flaeche=`, ` gezaehlt=`), der Wert im
   `say_radius`-Mitschnitt, die `hv.s`-Zeile. Echter Bildschirmtext
   bekommt echte Umlaute: Menues und Dialoge von `nedit`, der
   Aenderungsvermerk von `edit`, Meldungen von `ctr`, `ebpfctl`,
   `wmplug`, `stress`, `plugprobe`. Ein Umlaut ist in UTF-8 so lang wie
   seine Umschrift, also stimmen die Puffer; nur die zwei Tabellenzeilen
   von `ebpfctl` brauchten ein Leerzeichen (und ein Oktett) mehr, damit
   die Spalte in ZEICHEN gleich bleibt.
2. **8 Umschriften in `locale/de`** (Knöpfe, größer, Trägheit, Stärke,
   Tönung, Menüs).
3. **Drei getippte Marken nahmen die Umlautform nicht an**, obwohl ihre
   Hilfe sie zeigt: `jsig prüfe`, `papierkorb zurück`/`auslöschen`,
   `ota zurück`. Wer die Hilfe abtippte, bekam "unbekannter Befehl".
4. **Der Starter war auf dem Bild gar nicht zu sehen.** Mit `desk`
   startet der Schreibtisch den Starter seit ECHTHARDWARE-4 versteckt,
   und `wigstart` wirkt in diesem Pfad nicht. Die Aufnahme laeuft jetzt
   im Fensterserver-Pfad (wie der Speicher-Dialog). Und seit FUI-WIN11
   steht die Beschreibung ("Text schreiben und ändern") in einer
   ZWEITEN Zeile in kleinerer Schrift -- die wurde gemalt, aber nie
   gemeldet. `wlib` meldet sie jetzt als `wlib: text2 ... px=12`
   (eigenes Praefix, damit kein bestehender Leser von `wlib: text win=`
   doppelte Zeilen sieht), und `tools/look/umlaut.py` rastert mit der
   gemeldeten Groesse: 691 Tintenpunkte, 0 falsch.
   Dazu `spalten.py` (`vpn.fi`: `zeigen` heisst seit ENGLISCH `show`) und
   das WCAG-Urteil, das seit der Zusammenfuehrung umbricht.

## A-029 -- storage misst wieder

- `inhalt.img` hat 8192 statt 4096 Bloecke (4 MiB). `/bin/speicher`
  (1,26 MB) + Schriften + Messbaum passten nicht auf 2 MiB.
- `wighalt=240` fuer das Foto: die Gegenprobe des Programms ist ein
  echter Durchlauf ueber 4000 Dateien (Abschnitt 1 misst ~60 s) und
  dauerte laenger als `wiglong` (20 s) -- danach war QEMU schon weg.
- `kachelprobe.py` misst auf vier Bildzeilen und nimmt die breiteste:
  der Mauszeiger steht in der Bildmitte und kuerzte die Kachel "chrom"
  auf 54 statt 62. Gegenprobe: eine gemeldete Breite von 80 wird rot.

## Offen, neu

- **A-032** `tools/wmplug/spalten.sh` 15/1 "im Foto ist kein
  Tabellenkopf" -- auch auf `main` (872e3b71) so, also nicht aus dieser
  Runde. Die Farben des Terminals stimmen (nachgemessen).
- **A-033** `themestore/run.sh` und `arch/order.sh` legen Probedateien
  IN `kernel/` bzw. `lib/` an (`.zweimischer-probe.fi`,
  `.order-probe.fi`) -- neue Dateien statt ueberschriebener, aber
  dieselbe Klasse wie A-028.
