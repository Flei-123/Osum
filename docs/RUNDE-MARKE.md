# Runde MARKE — der Name an einem Ort

Justins Vorgabe: der Markenname soll nicht vierzigmal im Quelltext
stehen, sondern **einmal**. Als Vorlage gilt sein eigenes Projekt,
`/root/projects/freeviewer/src/brand.rs` — beide Projekte sollen gleich
funktionieren.

---

## 1. Umbenennen ist ein Bauaufruf, kein Codeeingriff

Genau wie `FV_BRAND_*` dort:

```sh
OSUM_MARKE_PRODUKT="Xoffi OS" OSUM_MARKE_HERSTELLER="Xoffi GmbH" \
OSUM_MARKE_KURZ=xoffi OSUM_MARKE_WEB=https://xoffi.example \
OSUM_MARKE_FEED=https://store.xoffi.example/xoffi \
bash tools/usbimg/build.sh /tmp/bau
```

Ohne diese Variablen bleibt alles OrientOS. Die Vorgaben stehen in
`marke.conf` im Wurzelverzeichnis; die Umgebung schlägt die Datei —
dieselbe Reihenfolge wie bei `OSUM_GUI` (`tools/config`).

| Feld | Vorlage | heute |
|---|---|---|
| `PRODUKT` | `NAME` | `OrientOS` |
| `KERN` | *(hat die Vorlage nicht)* | `Osum` |
| `HERSTELLER` | `PUBLISHER` | `fleitec` |
| `KURZ` | `SLUG` | `osum` |
| `WEB` | `WEB` | `https://fleitec.com/orientos` |
| `FEED` | `FEED` | `https://store.fleitec.com/osum` |
| `FASSUNG` | — | aus git, beim Bauen |

`KERN` ist der eine Zusatz: hier gibt es **zwei** Namen, und sie meinen
nicht dasselbe — `Linux` steht im dmesg, `Ubuntu` im Startbildschirm.

**Kein `EXE`, kein `DIR`.** Unter Windows sind Programmname und
Ordner in „Programme" Anzeigetext. Hier sind ihre Entsprechungen —
`osum.mb`, `/users/osum`, `.osp` — genau die Bezeichner, die sich nicht
bewegen dürfen. Das ist der eine bewusste Unterschied zur Vorlage.

**Kein `option_env!`.** Rust liest die Umgebung beim Übersetzen selbst,
Firn kann das nicht. Also tut es der Bau: `tools/marke-einsetzen.py`
ersetzt die Platzhalter in der **/tmp-Kopie** des Kernbaums und bricht
ab, wenn ein Feld fehlt, leer, zu lang oder noch ein Fragezeichen ist.
Der Arbeitsbaum bleibt sauber.

---

## 2. Was sich mit dem Namen ändert — und was niemals

Die Vorlage sagt: *„Protokoll, Relay und IDs sind bei allen Marken
gleich - jeder Build kann mit jedem reden."* Übertragen: **ein
umbenannter Bau muss dieselben Sticks lesen und dieselben Pakete
verstehen.**

**Umgestellt — 34 Stellen:**

| Stellen | wo |
|---|---|
| 10 | Bootmenü-Titel (`limine.conf`) |
| 1 | Kopfzeile von `limine.conf` |
| 1 | Dateiname des Abbilds (`orientos-usb.img`) |
| 1 | OTA-Feed (`quelle=` in `/etc/ota.conf`) |
| 2 | `kernel/kgui.fi` — Zeile im Terminalfenster, Kopf des Prüfbilds |
| 1 | `kernel/hwdiag.fi` — Überschrift der Diagnose |
| 1 | `kernel/procfs.fi` — `/proc/version` |
| 1 | `kernel/fassung.fi` — `<KURZ> <hash>` |
| 16 | bildpunktgenaue Zusagen in `wm`, `gfx`, `customres`, `display` |

Die Zusagen lesen jetzt **dieselbe Datei**. Eine Zusage auf einen fest
getippten Namen wäre nach der ersten Umbenennung eine Zusage auf etwas,
das es nicht mehr gibt — sie ginge auf und prüfte nichts.

**Bewusst stehen geblieben:**

| Zeilen | was | warum |
|---|---|---|
| 51 | `OSUM-OFS`, `OSUMMOD`, `SSH-2.0-OsumSSH`, `osum_panic`, `0x6D75734F`, `osum backup v1 …` | Formatkennung, Protokoll, Symbolname, ABI. **Die KDF-Label sind der härteste Fall: wer die ändert, macht jede bestehende Sicherung unlesbar. Das wäre kein Umbenennen, das wäre Datenverlust.** |
| 17 | `osum: …` auf der seriellen Leitung | `docs/I18N.md`: der Mitschnitt wird nicht übersetzt. Die Vorsilbe benennt das **Modul**, nicht die Marke — wie `taskbar:` und `wm:`. |
| 2 | `OSUM K15 WIDGETS` (`widgetdemo.fi`) | Ring-3-Programm. `marke.fi` ist `import kstate`, und **kein einziges Ring-3-Programm importiert `kstate`** — der Import würde Kernzustand in eine Anwendung ziehen. Das ist eine Verhaltensänderung, und diese Runde darf keine machen. Sauberer Weg: `/etc/marke.conf` ins Abbild, eigene Runde. |
| 90 | Kommentare und Herkunftsangaben (`portiert aus OrientOS' Rust-Kernel`) | Historie. Die meinen das alte Projekt, nicht die Marke. |
| — | `tools/gfx/run.sh`, `$ORIENTOS` | ist der **Pfad zum alten Rust-Repo** für die Zeichensatz-Herkunftsprüfung, nicht die Marke. |

---

## 3. Abnahme: eine Zeile, ein anderes Produkt

Gebaut mit `OSUM_MARKE_PRODUKT="Xoffi OS" …`, gemessen **am fertigen
Abbild**:

* Dateiname: **`xoffios-usb.img`** (Verweis `xoffi-usb.img` daneben)
* `limine.conf` aus dem Abbild: **10 von 10 Einträgen `/Xoffi OS -- …`**,
  **0-mal `OrientOS`** — auch nicht im Kommentar
* `/etc/ota.conf`: `quelle=https://store.xoffi.example/xoffi/aktuell`
  → die zweite Entscheidung der Vorlage hält: *„Ein Xoffi-Build darf
  sich nie zum FreeViewer aktualisieren."*
* Fassungszeile im Abbild: **`xoffi <hash>`, 3 Treffer**
* Bildschirmfoto des Limine-Bootmenüs liegt bei

**Ein Fehler, der dabei aufgefallen ist und behoben wurde:** der erste
Entwurf schrieb `limine.conf` mit einem **unzitierten** Heredoc, damit
die Schale `${MARKE_PRODUKT}` einsetzt. In einem unzitierten Heredoc
führt die Schale aber auch aus, was in **Kommentarzeilen** steht — und
in diesem Text stehen siebzehn Rückwärts-Anführungszeichen
(`` `Linux` ``, `` `dhcp` ``, …). Jedes wäre beim Bauen ein
Befehlsaufruf geworden. Jetzt: zitiertes Heredoc, Platzhalter
`@MARKE_PRODUKT@`, `sed` danach, und ein Abbruch, falls ein Platzhalter
stehen bleibt.

---

## 4. Regression

`tools/wm/run.sh`: **104 erfüllt, 0 gescheitert** — mit den 16 auf
`marke.conf` umgestellten Zusagen. Das Verhalten ist unverändert; das
war die Bedingung dieser Runde.
