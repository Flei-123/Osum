# STORE-OBERFLÄCHE (Roadmap r54 / P-007 / B8)

Stand 03.10.2026, Zweig `store-gui`. **Gebaut und im Gast gemessen.** Jede Aussage ist gekennzeichnet:
**[gemessen]** (hier ausgeführt), **[Quelle]** (aus dem Code gelesen), **[unbekannt]** (nicht nachgesehen).

## Was es ist

Ein Programmkatalog als fUi-Fenster (`/bin/store`, Szenenbaum `fuiscene`) mit einem **Wurzel-Dienst**
(`/bin/stored`) dahinter. Das Fenster hat **keine Rechte und keinen Netzcode**; es fragt den Dienst über den
Aktions-Bus (`etc/actions.d/store.actions`):

| Aktion | Stufe | Wirkung |
|---|---|---|
| `store.list` | lesen | der Katalog: je Programm `item=name\|version\|größe\|state` (`neu`, `aktuell`, `update`), dazu `can_install`, `can_remove`, Phase, `busy` |
| `store.status` | lesen | Stand des letzten Auftrags: `ruhe`, `laedt`, `fertig`, `fehler`, Verb, Programm, Kurztext |
| `store.refresh` | schreiben | `INDEX` + `INDEX.sig` vom eingestellten Store holen und gegen den vertrauten Schlüssel prüfen; **nichts wird installiert** |
| `store.install` / `store.update` | **kritisch** | ein Paket laden, Paketsignatur **und** Hash gegen den signierten Katalog prüfen, als neue Generation einspielen |
| `store.remove` | **kritisch** | eine neue Generation ohne das Programm |

Alle kritischen Aktionen kennen `--dry` (sagt, was sie täten, ändert nichts). Der Dienst nimmt nur Namen, die der
**geprüfte Katalog** nennt (`not_in_catalog`), und lehnt Namen mit `/`, `..` usw. ab (`bad_name`).

## Wer darf installieren — einstellbar, Standard: nur Administrator

Entschieden wird **im Dienst** (nicht im Fenster) aus `/etc/store.conf` (Wurzel-Datei, nicht schreibbar für andere):

```
installieren=admin     admin | benutzer | aus     (gilt auch für „Neue Fassung")
entfernen=admin        admin | benutzer | aus
admins=1000            weitere Administratoren: uids, mit Komma
```

* **admin** = uid 0, uid 1000 (das Konto, das der Installer anlegt) und die `admins=`.
* **benutzer** = jedes angemeldete Konto — **nie** `nobody` (65534, nicht angemeldet).
* **aus** = niemand; das Fenster zeigt nur an.
* Die Bestätigung des Brokers kommt **zusätzlich** bei jeder kritischen Aktion; die Bestätigung einer Person ersetzt
  das Recht nicht (die Anfrage eines Kontos ohne Recht endet auch nach „Ja" in `not_allowed`). [gemessen]
* Die Knöpfe folgen der Antwort des Dienstes (`can_install`, `can_remove`).

**Die Produktfrage an den Boss ist offen** („dürfen angemeldete Benutzer installieren?"). Der Standard ist die sichere
Seite; ein Wechsel ist eine Zeile in `/etc/store.conf` (`installieren=benutzer`), kein neuer Bau.

## Das Fenster

Tabelle (Name, Version, Größe, Status) und vier Knöpfe: *Aktualisieren* (Katalog neu holen), *Installieren*,
*Neue Fassung*, *Entfernen*. Tasten: Hoch/Runter wählen, Enter installiert (oder aktualisiert), Entf entfernt,
F5/`r` Katalog neu. Vor jeder Änderung fragt das Fenster in einem eigenen Dialog („Programm installieren?" mit dem
Namen, *Installieren* / *Abbrechen*). Beim ersten Start ohne Katalog holt es ihn selbst.

## Wie es geprüft wird — `tools/store/run.sh`

Gegen etwas **Äußeres**: ein HTTPS-Store auf dem Wirt (Pythons `ssl`, echte Zertifikatskette; Pakete von **`opk` des
Wirts** gebaut und signiert, nicht von diesem Code), im Gast ein e1000 hinter QEMUs Benutzernetz.

1. Bau; 2. die Quellen: ein guter Store und **drei schlechte** (gekipptes Oktett mit alter Signatur; gekipptes Oktett
**neu signiert** — Paketsignatur stimmt, Hash im signierten Katalog nicht; Katalog mit **fremdem** Schlüssel);
3. der gute Weg über den Bus: Liste leer vor dem Holen, Holen, Installieren, Neue Fassung, Entfernen, Trockenlauf,
Namen ohne Programm; 4. die Rechte (admin / benutzer / aus / `admins=` und die Anfrage eines fremden Kontos nach
Bestätigung); 5. nach jeder der drei Ablehnungen ist **nichts** installiert; 6. **das Fenster auf dem Bildschirm** mit
den Klicks einer Hand über den QEMU-Monitor (der Katalog holt sich selbst; *Abbrechen* startet nichts; Installieren →
Dialog → Ja → „Arbeitet …" → „Fertig: installiert"; Neue Fassung; Entfernen; am Ende stimmen `opk liste` und
`store.list`). `STORE_WINDOW_ONLY=1` fährt nur Abschnitt 6.

**Gefunden und behoben beim Messen**

* Der Dienst holte die Paketsignatur (`<paket>.sig`) nicht mit; jetzt wird `<datei>.sig` mitgeholt und geprüft.
* **Fenster-Fehler (nur am Bildschirm sichtbar):** der Status „neu" wurde als „Neue Fassung" angezeigt und „update" als
  „aktuell" — die Zeile wurde Buchstabe für Buchstabe ausgewertet, der **letzte** passende Buchstabe gewann. Jetzt
  entscheidet der erste.

## Grenzen (ehrlich)

* **Keine Beschreibung und keine Suche:** das Fenster zeigt Name, Version, Größe, Status; ein Suchfeld gibt es nicht.
* Es gibt **keinen Fortschrittsbalken**, nur „Arbeitet … bitte warten".
* **Gegen den echten Store `store.fleitec.com` ist nichts gelaufen** — nur gegen die Wirts-Quellen oben; das Format
  ist dasselbe (`ota`/`opk`), ob der Live-Katalog alle Fälle abdeckt, ist **[unbekannt]**.
* Ob ein Programm, das gerade läuft, beim Entfernen geschützt wird, ist **[unbekannt]** (nicht geprüft).
