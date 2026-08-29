# STATUS-SUPERSEARCH.md -- Zwischenstand der Runde SUPERSEARCH

Zweig `supersearch`, abgezweigt von `mergeline` (adaa9c7). NICHT nach
`main` gemergt.

## 0. Was hereingeholt wurde

* `paint` (5fa39fd) -- Alphamischung, Graustufen-Kantenglaettung,
  Fensterzwischenpuffer fuer echte Schatten.
* `look` (d7cd8ae) -- Form-Token (rrect, rframe, drop_shadow,
  radius_*), die Saetze `classic` und `modern`.

`paint` war von `e0a9fec` abgezweigt, also aus der MITTE von `look`;
beide mussten deshalb einzeln herein. Ein echter Konflikt
(`kernel/user/wlib.fi`, Exportliste: `window_app` gegen
`set_menu_title`, beide Funktionen im Rumpf vorhanden, die Liste ist die
Vereinigung), dreizehn Bildkonflikte, alle mit der Fassung aus `paint`
aufgeloest.

Der Kern baut nach beiden Merges: 2 883 480 Oktette.

## 1. Die Super-Taste allein (fertig)

Vorgefunden (nachgelesen, nicht geglaubt): `kernel/kbd.fi` hatte schon
`KB_SUPER`, `HK_SEQ`, `HK_KEY`, `HK_NS` und den bewusst gewaehlten
RIEGEL statt eines Ereignisses. Die Begruendung steht woertlich im
Quelltext ("A hotkey has no window -- that is what makes it global") und
sie ist richtig; diese Runde baut darauf auf und aendert nichts daran.

Was gefehlt hat: die Taste ALLEIN. Sie war ausschliesslich ein
Modifikator -- gedrueckt, gemerkt, beim Loslassen vergessen.

Neu, drei Stellen:

* `kernel/kstate.fi`: `KB_SUPER_USED = 0xB0` (freier Platz zwischen
  `HK_NS = 0xA8` und dem Kuerzelring `KB_HOT = 0xC0`) und `HK_TAP =
  0x110000` -- eins ueber dem groessten Unicode-Codepunkt, also nie ein
  Zeichen.
* `kernel/kbd.fi`: jeder Druck ausser dem auf Super setzt
  `KB_SUPER_USED`, GANZ OBEN in `on_code` -- weiter unten kehren die
  Modifikatoren einzeln zurueck, und Super+Umschalt waere sonst ein
  Tippen auf Super. Beim Loslassen entscheidet dieses eine Bit.
* `kernel/user/nv.fi`: `HK_TAP` fuer Ring 3, mit dem Vermerk, dass die
  Zahl zweimal steht, und einer Pruefung im Laeufer, die beide
  vergleicht.

Gemeldet wird `hk: super` auf einer EIGENEN Zeile.
`tools/netview/run.sh` zaehlt `grep -ac '^hk: super+a$'`; das Muster ist
an beiden Enden verankert, "hk: super" trifft es nicht.

## 2. Das Pop-up (fertig)

`kernel/user/sucher.fi`, gestartet als `/bin/sucht` von der Leiste. Es
ist ein Fenster OHNE Schmuck (`WS_FLOAT`, im Kern `wm.F_FLOAT`), das
trotzdem durch den Zwischenpuffer aus `paint` geht -- deshalb hat es
runde Ecken und einen echten Schatten, obwohl es keine Titelleiste hat.

Gemessen im Lauf: es steht mittig auf der ARBEITSFLAECHE (x=120, y=102
bei 800x572 abzueglich der Leiste, w=560 h=368), nicht mittig auf dem
Bildschirm -- das ist der Unterschied, den die Leiste ausmacht.

## 3. Die Rangfolge

Programme vor Dateien vor Einstellungsseiten; innerhalb einer Quelle
schlaegt der genaue Name (Rang 0) den Wortanfang (Rang 1) und der den
Treffer in der Mitte (Rang 2). Achtzehn Faelle auf der Standardausgabe,
alle achtzehn stimmen; im laufenden System steht die Liste nach
(Rang, Quelle) sortiert: `10 11 20 20 20 20 21 21`.

UMLAUTE: die Faltung zieht sie auf ihren Grundbuchstaben, ue/oe/ae/ss.
`gro` findet `Größe.txt` UND `GRÖSSE-ALT.txt` -- in beiden Namen kommt
an dieser Stelle gar kein `o` vor. Das ist der Fall, an dem eine
Faltung, die nur Gross auf Klein zieht, durchfaellt.

## 4. Die vier Fehler, die der erste vollstaendige Messlauf gezeigt hat

Der erste Durchlauf stand bei 57 von 62. Keiner der fuenf Fehlschlaege
war eine Nachlaessigkeit der Messung -- vier waren echte Fehler:

1. `kernel/user/launcher.fi` LIEF NEBEN SEIN FELD. `nidx.find` gibt die
   GESAMTZAHL der Treffer zurueck und schreibt hoechstens `DMAX`
   Kennungen; der Starter nahm die Gesamtzahl als Laenge des Feldes.
   Mit den neuen Dateien unter `/etc/shapes` (aus `look`) reichte ein
   getipptes `a`, und das System stand: `panic: index out of bounds in
   '[u64; 16]' at kernel/user/launcher.fi:195`. Danach kam die
   Super-Taste nicht mehr an -- daher die scheinbar unerklaerlichen
   Fehlschlaege in Abschnitt 3.
2. DER FALSCHE SYSTEMRUF. `sucher` (und `launcher`) startete Programme
   mit `spawn` (1000). Der nimmt eine PROGRAMMNUMMER aus `uprog.fi`
   zwischen 1 und 16 und gibt auf einen Pfad `-22` (E_INVAL) zurueck.
   In der Mitschrift stand `sucher: start [...] pid=-22`, und es ging
   kein Fenster auf. Ein Pfad wird mit `exec` (1001) gestartet; jetzt
   steht dort `pid=7` und das Programm meldet sich selbst.
3. DIE ECKENPROBE KANNTE KEINEN RAHMEN. Sie nannte eine Ecke "eckig",
   wenn sie die FUELLFARBE des Fensters trug. Der Satz `classic` hat
   `radius_window=0` UND einen Rahmen -- seine kerzengeraden Ecken
   trugen (226,232,240) statt (255,255,255) und galten als "rund". Die
   Gegenprobe scheiterte an der Messung, nicht am Bild. Jetzt gilt eine
   Ecke als eckig, wenn sie traegt, was auch die Kantenmitte traegt.
4. EIN `grep`-MUSTER, DAS NIE BESTEHEN KONNTE. Im Laeufer stand ein
   `grep -F` mit einem Zeilenumbruch IM MUSTER. `grep -F` liest das als
   zwei Muster -- "hk: super" und das LEERE --, und das leere passt auf
   jede Datei. Ersetzt durch `grep -ac '^hk: super$'` und einen
   Zahlenvergleich.

Der fuenfte Fehlschlag war wirklich die Messuhr: der Lauf, der ein
Programm STARTET, braucht 8 s Vorlauf, 6 s fuer die Tasten und dann die
Zeit, bis das neue Fenster von der Platte geladen und gemalt ist --
zusammen mehr als die 20 s, die `wiglong` stillhaelt. Der Kern war
fertig, bevor das Foto genommen war. Neu: `wigxl` (M_WIGXL, Bit 578)
haelt eine Minute still.

## 5. Die Zahlen (QEMU, Emulation, 800x572)

| was | gemessen |
|---|---|
| Tastendruck bis STEHENDES Fenster | 53 ms |
| Tastendruck bis GEMALTES Fenster | 152 ms |
| davon Zeichnen | 99 ms (fuellen 16, Rahmen 2, Zeilen 29, uebergeben 20) |
| ein Suchlauf im Index | 0,7 ms |
| Aufbau des Index, EINMAL beim Start | 61 ms fuer 98 Namen |
| ein Baumdurchlauf, waere der Preis JEDES Tastendrucks | 397 ms |

DIE ENTSCHEIDUNG FUER DEN INDEX steht in der letzten Zeile: 397 ms
gegen 0,3 ms je Suchlauf, Faktor 1313. Der Aufbau kostet 61 ms und hat
sich nach EINEM Tastendruck bezahlt. Ohne Index waere jeder Buchstabe
eine Drittelsekunde -- Tippen mit sofortiger Suche waere unmoeglich.

KVM GEGEN EMULATION, gemessen und nicht angenommen: fuer DIESEN Kern
ist `-accel kvm` LANGSAMER. Hochfahren 98 s statt 14 s, Indexaufbau
984 ms statt 57 ms. Der Grund ist die serielle Leitung: jede Zeile und
jeder Torzugriff ist unter KVM ein VM-Austritt, unter TCG nicht. Die
Annahme "KVM ist 4,6x schneller" gilt fuer diesen Kern nicht; die
Messungen oben laufen deshalb ohne KVM. `SSKVM=1` schaltet es an.

## 6. Der Testabschnitt

`tools/supersearch/run.sh`: 64 Pruefungen, 64 bestanden, 0
fehlgeschlagen. Dazu `tools/supersearch/shot.sh` (ein Lauf, ein Bild),
`messen.py` (Tinte, Ecken, Schatten, Zeilen) und `pad.py`.

Bilder nach `docs/shots/supersearch/`, und sie werden GEMESSEN, nicht
angesehen:

* `popup-leer.png` -- Hinweistext im Feld (4137 Tintenpunkte von
  19008), 5 zuletzt benutzte Programme, alle 4 Ecken rund.
* `popup-treffer.png` -- 8 Zeilen, jede mit Text im Bild.
* `treffer-umlaut.png` -- `gro` findet `Größe.txt` und
  `GRÖSSE-ALT.txt`; die gleichnamige Datei unter `/aussen` NICHT.
* `programm-gestartet.png` -- 411 756 Tintenpunkte, und das gestartete
  Programm meldet sich mit `widgetdemo: ready` selbst.

Jede Zeilenbeschriftung wird an der Stelle geprueft, die das Programm
SELBST auf der seriellen Leitung genannt hat. Das ist die Lehre aus dem
Fehler, bei dem jeder Fenstertitel leer war: 0 von 4137 faellt auf,
"sieht gut aus" nicht.
