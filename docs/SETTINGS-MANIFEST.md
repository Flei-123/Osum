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
sep                                           eine Trennlinie
row ... endrow                                die Einträge dazwischen stehen nebeneinander in einer Zeile
field <key> <type> [<label-key>] [<default>]  ein Bedienelement
read <action>                                 direkt nach einem `field`: Aktion am Bus, die den Wert liefert (r149)
write <action>                                direkt nach einem `field`: Aktion am Bus, die den Wert setzt (r149)
```

* `<…-key>` ist immer ein **Katalogschlüssel** (`locale/<sprache>/messages`): im Manifest steht kein Satz, nur Schlüssel (I18N-Regel).
* `type`: `bool`, `choice`, `text`, `secret`, `action` (Knopf; `<label-key>` ist die Beschriftung, Pflicht), `status` (eine Textzeile, die die App live füllt), `list`.
* `read`/`write` gehören zum `field` direkt davor (oder zum anderen der beiden `read`/`write`); höchstens je eines je Feld. Sonst (kein Feld davor, doppelt, schlechter Name, andere Wortzahl) wird die **ganze Datei abgelehnt** (Fehler 6/7/5). Bedeutung: `read` ruft die Aktion und nimmt aus der Antwort das Feld mit dem Namen des Feld-Keys (`share_activity=true`); `write` ruft die Aktion mit `<key>=true|false` (bool), `<key>=<Text>` (text/secret) oder ohne Argument (action).
* `#` am Wortanfang beginnt einen Kommentar. Wörter trennen Leerzeichen, Tab, CR.
* Namen (Id, Key, Symbol, Gruppe, Katalogschlüssel): `[a-z0-9._-]`, 1..40 Zeichen (App: 24).
* Grenzen: 8 Seiten, 80 Einträge, 3072 Byte Textspeicher je Manifest.

## 2. Regeln

| Regel | Warum |
|---|---|
| `manifest 1` zuerst, dann `app`, dann Seiten | Version prüfen, bevor etwas gelesen wird |
| Eine **bekannte** Zeile mit falschen Wörtern, ein schlechter Name, eine doppelte Seiten-Id, ein doppelter `field`-Key in einer Seite, ein Eintrag vor der ersten Seite, ein schlechtes `column`, `action` ohne Beschriftung, ein volles Table → die **ganze Datei wird abgelehnt** | nie eine halbe Seite; nach der Ablehnung sind die Tabellen leer, `err_code()`/`err_line()` sagen warum |
| Ein **unbekanntes** Zeilenwort oder ein unbekannter Feldtyp wird übersprungen und gezählt (`warn_count()`) | ein neueres Manifest auf einer älteren App zeigt, was die App versteht |

Fehlercodes: 1 Kopf, 2 App, 3 Seite, 4 doppelte Seite, 5 Eintrag vor Seite, 6 Eintrag falsch, 7 Name, 8 voll, 9 Textspeicher voll, 10 Spalte, 11 doppelter Key, 12 App-Name schon im Katalog, 13 `app` ≠ Paketordner (nur `add_pkg`).

## 3. Wer liest was

* **Parser:** `lib/settingsman/manifest.fi` (kein Profil, kein Heap, kein `str`; wie `lib/apprights/*`). Zweiter, unabhängiger Leser: `tools/settingsman/manifest.py`.
* **Einstellungen-App:** `page_konto()` in `settings.fi` liest die Seite `accounts` und baut daraus dieselben fUi-Elemente wie vorher (gleiche Reihenfolge, gleiche Ids, gleiche Größen).
* **Bindung („Adapter“ der Seite):** die App kennt zu jedem `field`-Key der Konten-Seite das Bedienelement, das die Ereignisschleife seit jeher behandelt (`acct_bind`/`acct_id`/`acct_buf`): `provider`→`K_CKANB`, `target`→`K_EKZIEL`, `certname`→`K_EKNAME`, `login`→`K_EKKEN`, `mfa`→`K_EKCODE`, `add`→`K_BKADD`, `device`→`K_BKDEV`, `book`→`K_BKBOOK`, `accounts`→`K_LKONTEN`, `signout`→`K_BKOUT`, `password`→`K_EKGEH`, `tenant`→`K_EKBER`; `status`/`bookline` sind die Live-Zeilen. **Das Verhalten (Klicks, Anmelden, „Mit Code anmelden und Adressbuch verbinden“) liegt unverändert im Code der App** — nur Aufbau und Beschriftung kommen aus dem Manifest.
* **Wo das Manifest liegt:** `kernel/user/settings.d/accounts.settings`. Es wird beim Bauen mit `__include_str` in `/bin/settings` eingebettet (das Testabbild von `tools/design/audit.sh` braucht dafür keine Datei im `/etc`). Ein Paket legt dasselbe Format als `/apps/<app>.prog/SETTINGS` ab; der Katalog (Abschnitt 4) liest es.
* Ein Manifest, das beim Start nicht lädt (kann bei der eingebetteten Datei nicht passieren — `tools/settingsman/run.sh` prüft sie), zeigt eine leere Seite statt einer halben.

## 4. Katalog: mehrere Manifeste (r143)

Die eingebaute Seite und die Pakete stehen in **einem Katalog** (statische Tabellen, kein Heap). Der Leser ist `lib/settingsman/manifest.fi`; der zweite, unabhängige Leser `tools/settingsman/manifest.py` hat dieselbe Schnittstelle (`parse(data, cat, expect)`), `manifest.py --catalog` druckt dieselbe Form wie `tools/settingsman/catalog.fi`.

| Aufruf | Wirkung |
|---|---|
| `load(buf, len)` | wie bisher: **ein** Manifest, der Katalog wird vorher geleert; abgelehnt → Tabellen leer |
| `add(buf, len)` | hängt ein weiteres Manifest an; Rückgabe = Einträge **dieser** Datei oder `ERR` |
| `add_pkg(buf, len, dir)` | wie `add`, aber die `app`-Zeile muss gleich dem Paketordner `dir` (ohne `.prog`, 0-terminiert) sein, sonst Fehler 13 |

Regeln:

* **Abgelehnt = Katalog wie vorher.** Von der Datei bleibt nichts (Einträge, Seiten, App, Textspeicher werden zurückgerollt). `err_code()`/`err_line()` gelten für den letzten Aufruf. `warn_count()` zählt je Datei neu.
* **Ein App-Name einmal** (Fehler 12): kein Paket kann sich `settings` oder ein anderes Paket nehmen. Mit `add_pkg` darf ein Paket außerdem nur für sich selbst sprechen (13); `meld` ≠ `melder`.
* **Seiten-Ids und Feld-Keys gelten je App**: zwei Apps dürfen beide eine Seite `accounts` mit Feld `name` haben. `page_find(id)` liefert die erste App mit dieser Id, `page_find_in(app, id)` die der gewünschten App. Eine Seite weiß ihre App (`page_app`), eine App ihre Seiten (`app_first_page`, `app_page_count`; Seiten einer App liegen hintereinander), `app_find(name)` → Index oder `NONE`.
* **Grenzen**: je Datei weiter 8 Seiten, 80 Einträge, 3072 Byte Text. Katalog gesamt: 8 Apps, 24 Seiten, 240 Einträge, 8192 Byte Text (Fehler 8 bzw. 9).
* **Einträge vor der ersten Seite DIESER Datei** (`field`, `label`, `note`, `column`) sind Fehler 5 — auch wenn eine frühere App schon Seiten hat.

Was der Aufrufer (Settings-App) tun muss: die eingebaute Seite mit `load` lesen, dann je Paket `/apps/<name>.prog/SETTINGS` (höchstens 3072 Byte; größere Dateien gar nicht erst lesen) mit `add_pkg(…, <name>)` anhängen. Ein abgelehntes Paket wird übersprungen — die anderen bleiben. Die App-Seite („das zeichnen“) ist noch **nicht** gebaut, siehe Abschnitt 6.

## 5. Tests

* `bash tools/settingsman/run.sh` (Host, ~2 Min, 66 Prüfungen): beide Leser + Golden-Dateien für 30 Fälle (`tools/settingsman/cases/*.txt|.expect`) und die echte Seite; Grenzen (80/8/Textspeicher); Verdrahtung (jeder Key gebunden, jeder Schlüssel in en **und** de, Knopf nicht mehr von Hand gebaut, Kennwort-Feld ist `secret`); **Katalog (r143)**: 16 Fälle in `tools/settingsman/catalog/` (je `.txt` = Abschnitte `%% add` / `%% pkg <dir>` / `%% load`, dazu `.expect`) und die Katalog-Grenzen (8 Apps, 24 Seiten, 240 Einträge, 8192 Byte, Rollback gibt Textspeicher zurück) mit beiden Lesern; 43 Mutationen des Parsers, jede muss rot werden.
* Klickprobe der echten App: `tools/settingsbook/run.sh` (17/0), Aufbau-Messung `tools/account/run.sh` Abschnitt 15 (Prüfung „Knopf K_BKBOOK“ liest jetzt Manifest + Bindung statt der Handarbeit-Zeile).

## 6. Die Einstellungen-App liest den Katalog (r149)

* **Laden:** `pkg_init()` (einmal, in `init_values`) lädt das eingebaute Manifest, ruft `apprights list` und liest je App `/apps/<name>.prog/SETTINGS` (über 3072 Byte: gar nicht gelesen) mit `manifest.add_pkg`. Abgelehnte Pakete werden übersprungen, die anderen bleiben. Höchstens 8 Paket-Seiten (`PKG_MAX`).
* **Reiterleiste:** Paket-Seiten haben die Seitennummer `R_ANZ + n` und die Taste `K_PKGTAB0 + n` (600..607). Der Name kommt aus `page_title` (Katalogschlüssel), die Kategorie aus `page_group`: `system display network accounts personal time update about` (Datei `settings.d/groups.names`) sind die eingebauten Kategorien, alles andere landet in der neunten Kategorie „Apps“. Suche und Pfeiltasten gelten auch für sie. `symbol` ist gelesen, aber noch nicht gezeichnet.
* **Zeichnen (`page_pkg`):** `label`, `note`; `bool` als Schalter; `action` als Knopf; `status` als Zeile „Beschriftung: Wert“; `text`/`secret` als Eingabefeld (Enter schreibt). `choice`/`list` werden noch nicht gezeichnet (das Manifest hat keine Eintragsliste). Tasten der Felder: `K_PKGF0 + Katalog-Eintragsnummer` (620..859).
* **Werte:** beim Öffnen der Seite (`pkg_enter`) und nach jedem Schreiben ruft die App jede `read`-Aktion (`call <aktion>`) und nimmt das Antwortfeld mit dem Feld-Key. Schreiben (`write`) geht über denselben Bus wie alle Seiten: Rechte, Rückfrage, Audit macht der Broker. Eine **kritische** Aktion antwortet mit einer Frage: die Statuszeile sagt es, der nächste Klick auf dasselbe Feld bestätigt (`confirm <Nr>`).
* **Eigener Namensraum:** eine Seite von `<app>` darf nur Aktionen rufen, die mit `<app>.` beginnen (`pkg_prefix_ok`); sonst „Nicht erlaubt“, es wird nichts gesendet. Ein Paket kann so keine fremde Aktion hinter einem Schalter verstecken.
* **Erste Paket-Seite:** `pakete/social/SETTINGS` (Seite „Aktivität“, Gruppe `accounts`): Schalter `share_activity` (`social.status` / `social.privacy.set`), Zeilen `presence` und `activity`, Knopf `social.refresh`. Muss als `/apps/social.prog/SETTINGS` ins Abbild (wie `ACTIONS`).
* **Tests:** `tools/settingsman/run.sh` Abschnitt 4b (Leser gleich, Schlüssel in en+de, Aktionen und Rückgabefelder in `ACTIONS`, Namensraum-Regel, Verdrahtung), 6 neue Fälle + 6 Mutationen für `read`/`write`.

## 7. Noch nicht

1. **Weitere Seiten auslagern:** Netz, Benutzer, Melder-Autostart (Backend-Verb, nicht am Bus) — jeweils eine Datei plus Bindung, mit dem vorhandenen Test als Netz. Eingebaute Seiten bleiben vorerst im Code (`settings.tabs`, 19 Einträge).
2. **`choice` und `list`** generisch: das Manifest braucht eine Eintragsquelle (Aktion oder Liste).
3. **Symbol** der Seite zeichnen (die Reiter haben heute kein Bild).
4. **Mehr als 8 Paket-Seiten / eigene Gruppen-Überschriften** aus `group` (heute nur die 8 eingebauten Kategorien + „Apps“).
5. **Ende-zu-Ende-Probe** in der VM: Paket-Seite öffnen und den Schalter klicken (braucht `social` in `/proc/apps` und das Abbild mit `SETTINGS`); heute prüfen nur die Host-Tests und der Bau.
6. Erledigt (r143): Kennwort-Feld maskiert.

## Seiten im Manifest (r1590/Folgearbeit)

Neben „accounts“ kommen jetzt „network“, „display“ und „display2“ aus `settings.d/accounts.settings`. `page_man` in `settings.fi` rendert alle vier; je Seitengruppe bindet eine Namensdatei (`accounts.bind`, `network.bind`, `display.bind`) den Feldschlüssel an Steuer-ID, Puffer, Sichtbarkeit (`man_shown`), Breite (`man_wd`) und Knopfart (`man_bk`).
