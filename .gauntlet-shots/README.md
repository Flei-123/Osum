# .gauntlet-shots -- echte Aufnahmen der Oberflaeche

Erzeugt am 09.09.2026 aus dem Stand 220633e ("Ausgangsstand vor Runde 1")
mit `tools/design/aufnahme.sh` (QEMU/TCG, `nostart wigapp=/bin/explorer`),
gesteuert ueber Drehbuecher fuer `tools/design/fahren.py`.
Alle Bilder sind echte QEMU-screendumps (PPM -> PNG), nichts nachgemalt.

| Datei | Aufloesung | Was zu sehen ist |
|---|---|---|
| 01-start.png | 1280x800 | Startzustand /data: Menuezeile, Werkzeugleiste, Baum links, Tabelle rechts, Statuszeile "8 Stueck, 2 Ordner, 354 Oktette" |
| 10-start.png | 1280x800 | derselbe Startzustand aus dem zweiten Lauf (Uhr 14:44) |
| 11-menue-gehezu.png | 1280x800 | Klick auf "Gehe zu": das aufgeklappte Menue zeigt Liste/Symbole/Nach Name und traegt eine eigene Titelleiste "Me - [] X" |
| 12-menue-ansicht.png | 1280x800 | "Ansicht" hervorgehoben, kein Menue offen |
| 14-kontextmenue.png | 1280x800 | Datei-Menue offen: Neuer Ordner / Neue Datei / Oeffnen mit; Popup verdeckt Werkzeugleiste und Baum |
| 15-unterordner.png | 1280x800 | nach Doppelklick auf "bilder": Pfad bleibt /data |
| 16-sortiert-groesse.png | 1280x800 | Klick auf Spaltenkopf "Groesse" |
| 17-sortiert-zeit.png | 1280x800 | Klick auf Spaltenkopf "Zeit"; Zeit-Spalte weiterhin "--" |
| 18-maximiert.png | 1280x800 | Fenster maximiert -- Inhaltsflaeche bleibt vollstaendig leer |
| 20-klein-800x600.png | 800x600 | kleiner Bildschirm: Fenster reicht bis an die Taskleiste |
| 30-dialog-neuer-ordner.png | 1280x800 | Dialog "Neuer Ordner" mit Namensfeld; OK/Abbrechen stossen an den unteren Dialograhmen |
| 31-kontextmenue.png | 1280x800 | Rechtsklick auf die Tabelle bei offenem Dialog -- kein Kontextmenue |
| 32-baum-navigation.png | 1280x800 | Klick auf "bilder" im Baum: Baumzeile ausgewaehlt, Tabelle unveraendert |
| 33-oeffnen-mit.png | 1280x800 | Datei-Menue ueber ausgewaehlter Datei alpha.txt |
| 34-menue-bearbeiten.png | 1280x800 | Zustand mit Inhalt und Auswahl: "bilder" im Baum und "alpha.txt" in der Tabelle markiert |
