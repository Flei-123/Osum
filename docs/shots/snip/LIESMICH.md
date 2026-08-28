# docs/shots/snip

`vollbild-800x600.png` ist das erste Bildschirmfoto, das Osum sich selbst
gemacht hat: der Schreibtisch, aufgenommen von `/bin/snip` aus Ring 3,
ueber einen Fahrschein, den der Kern ausgestellt hat.

Gemessen:

    800x600, Farbart 2, 65 930 Oktette
    entpackt 1 440 000 Oktette -- Faktor 22
    Zeilenfilter: none=0 sub=39 up=273 avg=0 paeth=288
    479 767 von 480 000 Bildpunkten sind nicht schwarz
    Bildpunkt (0,0) = (2,6,23) -- derselbe Wert wie im `screendump` des Wirtes

DIE FILTERVERTEILUNG IST DIE INTERESSANTESTE ZAHL. Kein einziges `none`:
die adaptive Wahl je Zeile nimmt wirklich den besten der fuenf, und `up`
und `paeth` gewinnen bei einem Verlaufshintergrund genau so, wie es die
Recherche vorhersagt.

ZUR GESCHICHTE DIESER DATEI: die vorige Fassung war ein PNG, das JEDE
Formatpruefung bestand -- richtige Signatur, richtige Pruefsummen,
richtiger zlib-Rahmen, 800x600, 11 400 Oktette -- und vollstaendig
SCHWARZ war. Der Kern konnte in die `mmap`-Zeichenflaeche von `wlibc`
nicht schreiben, und ein Formatpruefer sieht so etwas nicht. Deshalb
steht in dieser Runde nirgends "die Datei existiert" als Zusage, und
deshalb gibt es `tools/snip/pixel.py`. Der Streifen liegt seither im
Programmabbild.
