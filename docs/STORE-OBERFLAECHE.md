# STORE-OBERFLÄCHE — Plan (Roadmap r54 / B8)

Stand 02.10.2026. **Nicht gebaut** — dieser Text sagt, warum, und was gebaut werden muss.

## Was es heute gibt

* **Inhalt:** der Live-Store (`store.fleitec.com`) liefert 14 signierte Programme
  (Fassung 4, `osum-x86_64`). **[Quelle]** `docs/DAILY-DRIVER.md` B8, Roadmap r54/r177.
* **Bedienung nur auf der Konsole:** `ota suchen` / `ota einspielen` / `ota zurueck`
  (System-Update) und `opk liste|installieren|entfernen|aktualisieren` (Pakete).
* **System-Updates haben schon eine Oberfläche:** Einstellungen → Reiter *Updates*
  (Stand, Suchen, Installieren, Zurück, Kanal, Automatisch) über die Bus-Aktionen
  `settings.update.*`.
* **Programme sehen:** das Startmenü listet alles unter `/apps/*.osp` (INFO + Symbol).

## Was eine Store-Oberfläche zusätzlich wäre

Ein **Katalog**: die Programme des Stores ansehen (Name, Beschreibung, Version, Größe,
installiert?) und **ein einzelnes** installieren/entfernen/aktualisieren — nicht nur das
Gesamtsystem. Das ist der Teil, der heute fehlt.

## Warum es nicht „nur ein Fenster" ist

Installieren schreibt unter `/store` und `/system` (Wurzel-Rechte, `opk`, Signaturprüfung).
Ein Fenster, das als normaler Benutzer läuft, darf das **nicht selbst**; der Weg dafür ist
der **Aktions-Bus mit Wurzel-Dienst** (so wie `settings.update.install` über `settingsd`
läuft). Das heißt, vor dem Fenster braucht es:

1. **Katalog lesen:** eine Bus-Aktion `store.list` (read) — holt `INDEX` + `INDEX.sig` des
   eingestellten Stores (`/etc/ota.conf quelle=`), prüft die Signatur (wie `opk aktualisieren`)
   und liefert Zeilen `name version größe beschreibung installiert`.
2. **Ändern:** `store.install <name>` / `store.remove <name>` / `store.update <name>` als
   **kritische** Aktionen (fragen immer nach, wie `settings.update.install`), ausgeführt von
   einem Wurzel-Dienst über `opk` — mit Fortschritt in einer Statusdatei.
3. **Rechte:** das Fenster bekommt ein Manifest (`assets/apps/store.osp`), die Bus-Richtlinie
   (`etc/orientbus/policy`) erlaubt `store.*` nur dieser App (AB-007).
4. **Fenster:** fUi-Szenenbaum (`fuiscene`): Tabelle mit Spalten, Knöpfe *Installieren /
   Entfernen / Aktualisieren*, Statuszeile, Suchfeld; Fortschritt über die Statusdatei.

## Prüfung (wenn gebaut)

Wie `tools/ota/run.sh`: lokaler HTTPS-Store mit zwei Paketen, Katalog im Gast gelesen,
Installieren → `/apps/<name>.osp` steht, Entfernen → weg, **Gegenprobe:** Paket mit
gekipptem Oktett wird abgelehnt, Aktion ohne Freigabe wird abgelehnt. Bildabnahme des Fensters.

## Aufwand und Entscheidung

Grob 1 500–2 000 Zeilen (Bus-Dienst ~700, Fenster ~600, Manifest/Richtlinie/Tests ~500) und
**eine Produktentscheidung:** darf ein angemeldeter Benutzer (nicht root) Programme aus dem
signierten Store installieren, oder nur der Administrator? (Empfehlung: ja, mit Bestätigung
über den vertrauenswürdigen Dialog des Fensterservers — der Store ist signiert, die
Bestätigung verhindert Installieren im Hintergrund.)
