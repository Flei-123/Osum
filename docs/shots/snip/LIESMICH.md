# docs/shots/snip

`vollbild-800x600-schwarz.png` ist das erste Bildschirmfoto, das Osum sich
selbst gemacht hat: ein gueltiges PNG von 800x600 in 11 400 Oktetten, aus
`/bin/snip` heraus geschrieben, von einem strengen Leser angenommen
(Signatur, jede Chunk-CRC, zlib-Kopf, ADLER-32, nichts hinter IEND).

UND ES IST SCHWARZ, und deshalb heisst es so. Der Grund steht in
STATUS-SNIP.md, Befund 3: der Kern kann in die `mmap`-Zeichenflaeche von
`wlibc` nicht schreiben, also kommen die Bildpunkte des Standbildes dort
nie an -- waehrend derselbe Aufruf mit einem Feld aus dem Programmabbild
einwandfrei liefert.

Das Bild liegt hier, weil es genau das zeigt, worauf diese Runde ihre
Messung stuetzt: EINE DATEI, DIE JEDE FORMATPRUEFUNG BESTEHT, KANN DAS
FALSCHE ZEIGEN. Deshalb steht in dieser Runde nirgends "die Datei
existiert" als Zusage, und deshalb gibt es `tools/snip/pixel.py`.
