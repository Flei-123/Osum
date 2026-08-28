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
