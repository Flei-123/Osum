# RUNDE UMLAUT2 -- Zwischenstand

Zweig `umlaut2`, von `mergeline`. `look` und `paint` sind hineingeholt:
beide tragen Bildschirmtext, `look` ausserdem den UTF-8-Teil der
Widget-Bibliothek und `tools/i18n/translit.py`.

    50b1993  Merge branch 'look' into umlaut2
    3cd8a79  Merge branch 'paint' into umlaut2

---

## SCHRITT 1 -- DIE BESTANDSAUFNAHME

### Was der Auftrag als Fundstelle nannte, und was davon noch stimmt

| Meldung | Befund auf `umlaut2` |
|---|---|
| `locale/de/messages` in Ordnung | **stimmt.** 21 Zeilen mit echten Umlauten, Umschrift nur in Zitaten in Kommentaren. |
| `assets/apps/editor.osp/INFO:3` = `Text schreiben und aendern` | **auf `mergeline`/`update` ja, auf `umlaut2` nein.** `look` hat es auf `ändern` gestellt. Alle fuenf `INFO` sind sauber. |
| `locale/de/icons:33` = `Auf die vorige Groesse zuruecksetzen` | **auf `umlaut2` nein.** Steht als `Auf die vorige Größe zurücksetzen` da. |
| Einkompilierte Zeichenketten in `kernel/user/*.fi` | **STIMMT, und das ist der Rest der Arbeit.** `einstellungen.fi` heisst hier `settings.fi` und zieht seinen Text inzwischen aus dem Katalog; `speicher.fi` hat `Name\tGröße\tAnteil` schon. Was BLIEB, steht unten. |

Die genannte Zeile `opk: erprobung bestaetigt fuer ` gibt es auf
`umlaut2` nicht -- sie stammt aus dem Zweig `update` (A/B-Boot), der
hier nicht dazugehoert.

### Das Werkzeug: `tools/i18n/quellen.py`

`translit.py` kannte zwei Quellen -- `locale/de/*` und die Buendel.
Beide waren sauber, waehrend im Starter Umschrift stand. Ein Pruefer,
der nur den Katalog liest, kann den Quelltext nicht sehen.

`quellen.py` liest `kernel/**/*.fi` und `.s`, findet jede Zeichenkette
mit deutscher Umschrift und ordnet sie EINER von drei Klassen zu:

* **SICHTBAR** -- Beschriftung, Ausgabe, Fehlermeldung. Hier gehoeren
  echte Umlaute hin.
* **MITSCHNITT** -- was ein Fensterprogramm oder der Kernel auf die
  serielle Leitung schreibt (`leiste: knopf i=0 id=5`). `docs/I18N.md`
  nimmt diese Zeilen ausdruecklich aus; die Abnahme greppt nach ihnen.
  Erkannt: die Datei macht ein Fenster auf (`import wlib`/`wlibc`) oder
  liegt im Kernel, UND die Kette geht nirgends anders hin als in
  `say`/`kv`/`sag`/`serial.*`.
* **MARKE** -- was mit einer EINGABE verglichen wird: Unterbefehl,
  Schalter, Pfad, Dateiname, Schluessel. Dieselbe Ausnahme wie in
  `docs/I18N.md` ("Befehlsname: nein") und dieselbe wie `keys=`: man
  muss es tippen koennen, auch ohne Umlauttaste.

### Die Zahlen

| Quelle | geprueft | Umschrift |
|---|---|---|
| `locale/de/messages`, `locale/de/icons` | 210 Werte | **0** |
| `assets/apps/*.osp/INFO` (`name=`, `info=`) | in obigen 210 | **0** |
| `kernel/**/*.fi`, `kernel/**/*.s` | 5347 Zeichenketten | **65** |

Die 65 nach Klassen: **SICHTBAR 42**, MITSCHNITT 15, MARKE 8.

Zu korrigieren sind damit **42 Zeichenketten in 16 Dateien**, dazu

* **6 Marken**, die die Umlautform ZUSAETZLICH annehmen muessen
  (`opk zurueck|pruefen`, `vpn schluessel`, `power waerme`,
  `dispctl zurueck|saettigung`),
* **2 Spaltenbreiten**, die in Zeichen gemeint und in Oktett gerechnet
  sind (`power.fi` Beschriftungsspalte, `vpn.fi` Zustandsspalte),
* **2 Laengenpruefungen**, die "vier Zeichen" verlangen und Oktette
  zaehlen (`settings.fi`, `passwd.fi`).

### Die 42 sichtbaren Fundstellen

    kernel/user/du.fi            310  s_e          pruef       du: probe fertig geprueft=
    kernel/user/fas.fi          1418  t2           groesse     Quellgroesse steht nicht
    kernel/user/fas.fi          1818  t            gross       p2align zu gross
    kernel/user/fas.fi          1998  t            faeng       hier faengt kein Wort a
    kernel/user/fas.fi          2159  t            laesst      fas: Ziel laesst sich nicht 
    kernel/user/fas.fi          2242  t            fuer        fas: kein Speicher mehr fuer den\n
    kernel/user/fas.fi          2407  t            gaeng       fas: die zwei Durchgaenge sind ungleich lang\n
    kernel/user/firun.fi          84  k            Uebersetz   firun: der Uebersetzer lehnt ab, Code 
    kernel/user/firun.fi          90  e2           liess       eine Datei liess sich nicht lesen
    kernel/user/firun.fi         232  t5           liess       firun: das Programm liess sich nicht 
    kernel/user/install.fi        73  S_USE        GERAET      install ZIEL [--quelle GERAET] [--esp SEKTOREN] [--ja]
    kernel/user/install.fi        96  S_KARTE      bloeck      install: zu wenig Kartenbloecke
    kernel/user/opk.fi            70  S_USE6       zurueck     opk zurueck <n>
    kernel/user/opk.fi            71  S_USE7       pruef       opk richten | opk pruefen
    kernel/user/opk.fi           109  E_LAENG      Laenge      opk: Laengen im Kopf passen nicht
    kernel/user/opk.fi           110  E_HASH       Pruef       opk: Pruefsumme falsch
    kernel/user/opk.fi           113  E_STORE      fuer        opk: Store-Eintrag fehlt fuer 
    kernel/user/opk.fi           126  S_ZUR        zurueck     opk: zurueck auf 
    kernel/user/opk.fi           131  E_ARCH       liess       opk: das Archiv liess sich nicht auspacken
    kernel/user/opk.fi           133  E_PLAN       liess       opk: der PLAN liess sich nicht lesen/schreiben
    kernel/user/opk.fi           134  E_AKT        liess       opk: AKTUELL liess sich nicht schreiben
    kernel/user/passwd.fi         44  s_ok         fuer        passwd: gesetzt fuer 
    kernel/user/power.fi         136  c            Hoech       Hoechstleistung
    kernel/user/power.fi         183  s_rf         Rueck         (Rueckfall, die Maschine 
    kernel/user/power.fi         188  s_lim        hoech         GEDROSSELT: hoechstens 
    kernel/user/power.fi         229  s_l          laedt         laedt
    kernel/user/power.fi         230  s_e          laedt         entlaedt
    kernel/user/power.fi         234  s_unb        geraet      kein Netzteilgeraet
    kernel/user/power.fi         235  s_kap        itaet       Kapazitaet
    kernel/user/power.fi         312  s_t          Waerm       Waerme:  
    kernel/user/power.fi         476  s_kein       laeuft      power: die Energieschicht laeuft nicht
    kernel/user/power.fi         477  s_hilfe      waerm       power: sparen | mitte | leistung | akku | waerme | hell N | 
    kernel/user/proxy.fi          89  s_weg        loesch      proxy: geloescht
    kernel/user/su.fi             38  e_noshadow   fuer        su: kein Eintrag in shadow fuer 
    kernel/user/themetest.fi     489  g_ent        fueg        ein Textfeld mit Einfuegemarke
    kernel/user/tiling.fi        134  s_an         laeuft      tiling: der Kachelbetrieb laeuft
    kernel/user/tiling.fi        146  s_io         haelt         Invariante: haelt  
    kernel/user/tiling.fi        334  s_ok         traeg       tiling: Eintraege gelesen
    kernel/user/vpn.fi           162  s_an         laeuft      vpn: laeuft
    kernel/user/vpn.fi           165  s_hs         schlaeg       Handschlaege 
    kernel/user/vpn.fi           210  s_kein       Schluessel  vpn: noch kein Schluessel gesetzt
    kernel/user/vpn.fi           222  s_use1       schluessel  vpn [an <profil>|aus|schluessel]

### Nicht angefasst (und warum)

15 MITSCHNITT-Zeilen (`desktop: keine Flaeche`, `speicher: gross i=`,
`launcher: waehle datei [`, `explorer: zurueck `, `  bloecke=`,
`  saetze=`, `grossdatei`, `menues=`, ...) und 8 MARKEN
(`/tmp/gross`, `zurueck`, `pruefen`, `schluessel`, `saettigung`,
`waerme`, ...). Dazu Kommentare, Bezeichner, Dateinamen, Pfade und die
`keys=`-Zeilen der Buendel.

---

## OFFEN

Schritt 2 (korrigieren), 3 (Puffer und Breiten), 4 (Abnahme),
5 (Bild und Messung).
