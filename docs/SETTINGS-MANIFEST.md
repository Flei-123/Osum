# SETTINGS-Manifest (r136) — Einstellungen nach „Schnittstelle zuerst“

Die Einstellungen-App (`kernel/user/settings.fi`) war ein Block mit festen Reitern.
Jetzt gilt dasselbe Prinzip wie beim Aktions-Bus (`pakete/<app>/ACTIONS`, `docs/ACTION-BUS.md`):
**eine Seite ist ein Anbieter, die App rendert nur.** Dieses Dokument beschreibt den Stand
der ersten Umsetzung: Format, Parser, die erste Seite aus dem Manifest („Konten“) und was noch fehlt.
Konzept (Melder-Seite, Bus-Anbindung): FirnChat `docs/MELDER-INTERFACE.md`, Abschnitt 4.

## 1. Format

Zeilenformat wie `ACTIONS` (kein JSON: der Leser ist Firn ohne Heap, 400 Zeilen reichen).

```
manifest 1
app <name>
page <id> <title-key> <symbol> <group>        beginnt eine Seite
column left|right                             wohin die folgenden Einträge kommen (Standard: left)
label <label-key>                             eine feste Textzeile
note <label-key> [<zeilen>]                   ein umbrochener Absatz (1..9 Zeilen, Standard 1)
field <key> <type> [<label-key>] [<default>]  ein Bedienelement
```

* `<…-key>` ist immer ein **Katalogschlüssel** (`locale/<sprache>/messages`): im Manifest steht kein Satz, nur Schlüssel (I18N-Regel).
* `type`: `bool`, `choice`, `text`, `secret`, `action` (Knopf; `<label-key>` ist die Beschriftung, Pflicht), `status` (eine Textzeile, die die App live füllt), `list`.
* `#` am Wortanfang beginnt einen Kommentar. Wörter trennen Leerzeichen, Tab, CR.
* Namen (Id, Key, Symbol, Gruppe, Katalogschlüssel): `[a-z0-9._-]`, 1..40 Zeichen (App: 24).
* Grenzen: 8 Seiten, 80 Einträge, 3072 Byte Textspeicher je Manifest.

## 2. Regeln

| Regel | Warum |
|---|---|
| `manifest 1` zuerst, dann `app`, dann Seiten | Version prüfen, bevor etwas gelesen wird |
| Eine **bekannte** Zeile mit falschen Wörtern, ein schlechter Name, eine doppelte Seiten-Id, ein doppelter `field`-Key in einer Seite, ein Eintrag vor der ersten Seite, ein schlechtes `column`, `action` ohne Beschriftung, ein volles Table → die **ganze Datei wird abgelehnt** | nie eine halbe Seite; nach der Ablehnung sind die Tabellen leer, `err_code()`/`err_line()` sagen warum |
| Ein **unbekanntes** Zeilenwort oder ein unbekannter Feldtyp wird übersprungen und gezählt (`warn_count()`) | ein neueres Manifest auf einer älteren App zeigt, was die App versteht |

Fehlercodes: 1 Kopf, 2 App, 3 Seite, 4 doppelte Seite, 5 Eintrag vor Seite, 6 Eintrag falsch, 7 Name, 8 voll, 9 Textspeicher voll, 10 Spalte, 11 doppelter Key.

## 3. Wer liest was

* **Parser:** `lib/settingsman/manifest.fi` (kein Profil, kein Heap, kein `str`; wie `lib/apprights/*`). Zweiter, unabhängiger Leser: `tools/settingsman/manifest.py`.
* **Einstellungen-App:** `page_konto()` in `settings.fi` liest die Seite `accounts` und baut daraus dieselben fUi-Elemente wie vorher (gleiche Reihenfolge, gleiche Ids, gleiche Größen).
* **Bindung („Adapter“ der Seite):** die App kennt zu jedem `field`-Key der Konten-Seite das Bedienelement, das die Ereignisschleife seit jeher behandelt (`acct_bind`/`acct_id`/`acct_buf`): `provider`→`K_CKANB`, `target`→`K_EKZIEL`, `certname`→`K_EKNAME`, `login`→`K_EKKEN`, `mfa`→`K_EKCODE`, `add`→`K_BKADD`, `device`→`K_BKDEV`, `book`→`K_BKBOOK`, `accounts`→`K_LKONTEN`, `signout`→`K_BKOUT`, `password`→`K_EKGEH`, `tenant`→`K_EKBER`; `status`/`bookline` sind die Live-Zeilen. **Das Verhalten (Klicks, Anmelden, „Mit Code anmelden und Adressbuch verbinden“) liegt unverändert im Code der App** — nur Aufbau und Beschriftung kommen aus dem Manifest.
* **Wo das Manifest liegt:** `kernel/user/settings.d/accounts.settings`. Es wird beim Bauen mit `__include_str` in `/bin/settings` eingebettet (das Testabbild von `tools/design/audit.sh` braucht dafür keine Datei im `/etc`). Ein Paket legt dasselbe Format als `/apps/<app>.prog/SETTINGS` ab (siehe unten, noch nicht gelesen).
* Ein Manifest, das beim Start nicht lädt (kann bei der eingebetteten Datei nicht passieren — `tools/settingsman/run.sh` prüft sie), zeigt eine leere Seite statt einer halben.

## 4. Tests

* `bash tools/settingsman/run.sh` (Host, Sekunden, 31 Prüfungen): beide Leser + Golden-Dateien für 30 Fälle (`tools/settingsman/cases/*.txt|.expect`) und die echte Seite; Grenzen (80/8/Textspeicher); Verdrahtung (jeder Key gebunden, jeder Schlüssel in en **und** de, Knopf nicht mehr von Hand gebaut); 19 Mutationen des Parsers, jede muss rot werden.
* Klickprobe der echten App: `tools/settingsbook/run.sh` (17/0), Aufbau-Messung `tools/account/run.sh` Abschnitt 15 (Prüfung „Knopf K_BKBOOK“ liest jetzt Manifest + Bindung statt der Handarbeit-Zeile).

## 5. Noch nicht (nächste Schritte)

1. **Pakete lesen:** beim Start `/apps/*.prog/SETTINGS` einlesen (`manifest.load` kann das schon, der Textspeicher hält aber nur ein Manifest zugleich → Tabellen je Paket oder Seite für Seite rendern) und die Reiterleiste (heute `settings.tabs` + 19 feste Kacheln, `K_TAB0 + page`) daraus erzeugen (`group`/`symbol`/`title-key` stehen schon im Manifest).
2. **Generische Felder:** `bool`/`choice`/`text` ohne Bindungstabelle: Wert lesen/schreiben über die Lese-/Schreib-Aktion am Bus (Rechte, Bestätigung, Audit macht der Broker) — dafür fehlen im Manifest noch `read <aktion>`/`write <aktion>` je Feld. `bool` wird vom Renderer noch **nicht** gezeichnet (nur geparst).
3. **Weitere Seiten auslagern:** Social/Aktivität („Melder“-Seite aus FirnChat `MELDER-INTERFACE.md`), Netz, Benutzer — jeweils eine Datei in `settings.d/` plus Bindung, mit dem vorhandenen Test als Netz.
4. **Befund (nicht angefasst, Verhalten unverändert):** das Kennwort-Feld der Konten-Seite (`password`, `K_EKGEH`) ist ein normales `text`-Feld und zeigt die Eingabe offen; `type secret` im Manifest würde es maskieren (`fuiscene.entry_secret`, der Renderer kann es). Umstellen ist eine Ein-Wort-Änderung im Manifest, aber eine sichtbare Verhaltensänderung → Entscheidung offen.
