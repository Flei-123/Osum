# Runde ROADMAP-3 (23.09.2026)

Auftrag: die Roadmap weiter abarbeiten, Schwerpunkt `K-` und `A-`.
Angefangen mit den zwei offenen Punkten der Vorrunde (`A-023`, `A-024`),
dann jedem roten Laeufer nachgegangen, bis die Ursache feststand.

## Was gemessen wurde

| Laeufer | vorher | nachher | Ursache |
|---|---|---|---|
| `account` (konto) | **9/4** | **107/0** | A-016-Rest, zwei ENGLISCH-Namen, A-025 (`uebergabe`) |
| `bridge` | 110/3 | **113/0** | A-025 (`platte_bloecke`), A-027, eine Erwartung in Umschrift |
| `posix` | 148/2 | **150/0** | A-025 (`lock bloed`); libc kannte 11 Systemrufe des Kerns nicht |
| `hda` | 135/8 | 141/2 | A-025 (`geraetrate`), A-027; Rest: Aussetzer unter Last |
| `sync` | 83/6 | 88/1 | A-025 (`pruef`, `bloecke`), `kette.fi` -> `chain.fi` |
| `umlaut` | 37/11 | 41/10 | Anker `lines_report`, Gegen-Gegenprobe; Rest: echte Umschrift |
| `module` | baute nicht | **74/0** | A-030 |
| `ota` | brach vor der Messung ab (~80 rot) | **107/0** | A-026, O-010 |
| `alltag` | 41/4, Abschnitt 8 STILL uebersprungen | **45/0** | A-026, P-024, Mitschnitt aus |
| `loader` | baute nicht | 19/12 | Rest: der Live-Store (siehe "braucht Justin") |
| `audio/mischer` | -- | 25/0 | A-025 (`systemklaenge`) |
| `build-kernel.sh --gui off` | rc=1 | rc=0 | A-027 |

Pflicht-Abnahmen nach allen Kernaenderungen: `install/abnahme.sh` 35/0,
`hotplug` 45/0, `clip2` 32/0, `check-ui` PASSED, `anim-ab` anim=4.

## Der eine Fund, der wirklich Schaden anrichtete: A-025

Runde ROTABSCHNITTE 5 (`49bfa4ba`) hat Umschrift in Zeichenketten durch
echte Umlaute ersetzt. Sie hat dabei auch Ketten erwischt, die **kein Satz
sind**, sondern ein Wort eines Formats, das ein anderes Programm Oktett
fuer Oktett erwartet:

- `jarvisd` gruesste mit `osum-brücke 1`; `/root/jarvis/lib/osumbridge.js`
  vergleicht auf `osum-bruecke` -- **die Fernbruecke war tot.**
- `ota` pruefte die Schluesselkette gegen den Text `osum-schlüssel`, das
  Wirtswerkzeug signiert `osum-schluessel` -- **ein Schluesselwechsel
  waere abgelehnt worden.**
- der Papierkorb schrieb `größe=` und las `groesse=` -- jede Groesse 0.
- `konto uebergabe` ging nicht mehr: BEIDE Schreibweisen waren `übergabe`.
- dazu sechs Messfelder, nach denen Laeufer suchen.

Jede dieser Zeilen traegt jetzt `// DRAHT: <wer liest es>`. Der Pruefer
(`tools/i18n/quellen.py`) behandelt DRAHT wie eine Marke, und
`tools/umlaut/run.sh` wird rot, sobald eine DRAHT-Kette einen Umlaut
traegt (mit Gegenprobe).

## Die anderen Funde

- **A-026** -- `opk.py` lag in `/root/orientos-install`, einem
  Arbeitsbaum, der am 21.09. aufgeraeumt wurde. `ota`, `install`,
  `loader`, `module` brachen ab; `alltag` uebersprang Abschnitt 8
  **still**. Neu: `tools/lib/opkpfad.py`.
- **O-010** -- das Wirtswerkzeug auf `main` schreibt eine sechste
  INDEX-Spalte (Architektur). Das Geraete-`opk` las den Dateinamen bis zum
  Zeilenende: **kein Update liess sich einspielen.**
- **A-027** -- `sched/schlaf.fi` (K-018) band `gfx.fb` direkt ein; der
  GUI-lose Serverkern baute nicht. Jetzt ueber die Naht `gfx`.
- **P-024** -- die Loeschfrage des Explorers hiess "Umbenennen"; ein
  mitgegebener Startordner wurde ueberhoert.
- **A-030** -- der Modul-Laeufer kopierte den Kern flach (vor
  O-STRUKTUR), suchte `.prog` statt `.osp`, und seine Gegenprobe
  verdarb toten Code.
- **A-023-Nachtrag** -- parallele Laeufer in einem frischen Baum raeumten
  sich `vendor/firn/lib` weg. Jetzt mit Sperre.
- acht Laeufer suchten Namen aus der Zeit vor Runde ENGLISCH.

## Offen, neu

- **A-028** -- `tools/sync/run.sh` aendert `kernel/user/sync.fi` IM BAUM
  fuer seine Gegenproben und stellt es danach wieder her. Bricht man den
  Lauf ab, oder aendert jemand die Datei waehrenddessen, wird der
  Quelltext mit dem alten Stand ueberschrieben -- in dieser Runde genau
  so passiert. Parallele Laeufer bauen in der Zeit eine kaputte Fassung.
- **A-029** -- `/bin/speicher` ist seit `profile app` 1,26 MB gross und
  passt nicht mehr auf das 2-MB-OFS-Abbild von `tools/storage`.

## Braucht Justin

- der Live-Store (Fassung 3) traegt keine Plattformangabe; jedes aktuelle
  Geraet blendet alle acht Pakete aus.
- nach dem Merge ein neues Abbild auf den PC -- die Bruecke war seit
  ROTABSCHNITTE 5 tot.
