# STATUS — RUNDE THEMESTORE

Zweig `themestore` (von `mergeline`, mit `look` und `paint` darin). **Nicht nach `main`.**
Abnahme: `bash tools/themestore/run.sh` — **81 Zusagen, 0 rot** (Lauf `/root/TS-RUN3.log`,
QEMU mit `-accel kvm`). Beweisstücke eines Laufs bleiben mit `TS_OUT=<pfad>` liegen.

## Was der Auftrag verlangte und wo es steht

| Auftrag | Wo | Zustand |
|---|---|---|
| Vorlagen mit einem Klick | `assets/themes/*.preset` (10), `kernel/user/vorlage.fi`, `/bin/theme` | grün |
| Vorschaukachel aus den Token gerendert | `wlib.tile`, Seite „Vorlagen" | grün, 10 Kacheln, 7 verschiedene Flächenfarben |
| Kontrast ist Teil der Vorlage | `theme list`, gegengerechnet mit `tools/theme/model.py` | grün, alle ≥ 4,5:1 |
| Eigene Vorlage: sichern, benennen, ausgeben, einlesen | `theme save/export/import`, `/etc/themes.local/` | grün, lesbarer `key=value`-Text, übersteht Neustart |
| Konto-Verknüpfung | `account_have/account_dir/link_all/restore_all` | grün, **ohne Konto läuft alles** |
| Seite „Darstellung" repariert (132 Bildpunkte) | `kernel/user/settings.fi`, zwei Spalten + achter Reiter | grün, 0 Widgets ragen heraus |
| Screenshots, gemessen statt angeschaut | `docs/shots/themestore/`, `tools/themestore/shotcheck.py` | grün, 12 Bilder, 0 leer / 0 abgeschnitten / 0 überlappend |

## Die sieben Schlüssel einer Vorlage

`name` `scheme` `mode` `shape` `accent` `edge` `align` — und **kein achter**.
`vorlage.parse_key` kennt genau diese sieben und **zählt** jeden anderen als schlecht;
die Gegenprobe schmuggelt `command=/bin/sh` und `password=hunter2` in eine Datei und
bekommt `bad=2` zurück, während die sieben echten trotzdem gelesen werden. Eine Vorlage
kann also keinen Pfad, keinen Befehl und kein Kennwort tragen — sie ändert, wie es aussieht.

## Kontrast (im System gerechnet, auf dem Wirt Ziffer für Ziffer nachgerechnet)

| Vorlage | Schema / Modus / Form | Text auf Grund | schlechtestes Paar |
|---|---|---|---|
| abendrot | paper · dark · modern | 16,74:1 | 5,34:1 |
| kontrast | contrast · light · classic | 21,00:1 | 7,88:1 |
| kontrastnacht | contrast · dark · classic | 21,00:1 | 9,05:1 |
| mitternacht | midnight · dark · modern | 16,97:1 | 5,81:1 |
| papier | paper · light · modern | 16,74:1 | 4,71:1 |
| studio | midnight · dark · modern | 16,97:1 | 5,81:1 |
| tafel | night · light · modern | 17,06:1 | 4,61:1 |
| tageslicht | day · light · modern | 17,06:1 | 4,61:1 |
| terminal | night · dark · classic | 17,06:1 | 5,70:1 |
| werkstatt | day · light · classic | 17,06:1 | 4,61:1 |

Keine Vorlage liegt unter ihrer Latte, keine ist als „geringer Kontrast" gekennzeichnet.
Gegenprobe: eine absichtlich schlechte Vorlage (1,23:1) **wird** so gekennzeichnet — sonst
wäre nie bewiesen, dass die Regel überhaupt läuft.

## Das Konto ist Komfort, nie Bedingung

Drei Ablageorte, in dieser Reihenfolge: `/etc/themes/` (mitgeliefert) →
`/etc/themes.local/` (deine, auf DIESER Maschine) → `/users/<name>/config/themes/`
(das Konto, nur wenn es eines gibt). Ohne Konto: anwenden, sichern, ausgeben, einlesen —
alles grün, gleich viele Vorlagen im Laden, und `theme link` **sagt**, dass es kein Konto
gibt, statt zu scheitern. Was fehlt für echte Synchronisierung: Protokoll, Transport,
Authentifizierung, Konfliktauflösung. Nichts davon wurde erfunden.

## Was diese Runde zusätzlich repariert hat (und warum)

Zweimal ist hier ein Bild mit echtem Fehler durch einen Test gerutscht. Die Ursache war
jedes Mal dieselbe: **der Prüfer hat geraten.**

* `shotcheck.py` nahm für jedes Fenster außer den Einstellungen den Ursprung `0,0` an und
  maß damit Stellen des Schreibtischs. Jetzt sagt **jedes Fenster selbst**, wo es steht und
  wo seine Malfläche anfängt (`wlib: win id= x= y= w= h= cx= cy=`). Der Versatz wird nicht
  nachgerechnet, sondern beim Fensterserver erfragt (`WI_INX`/`WI_INY` → `wm.inx/iny`).
* Die Zeilenhöhe war geraten (16 hinauf, 6 hinunter = 22) — Listenzeilen stehen 20
  auseinander, also schnitt jeder Kasten in den Nachbarn und meldete Überlappungen, die es
  nicht gab. Die Bibliothek sagt die Zahlen jetzt: `wlib: font ui px=15 asc=12 h=18`.
* „Überlappend" hieß „zwei Kästen schneiden sich". Jetzt: **gemeinsame Bildpunkte** — das,
  was im Kopf der Datei seit dem ersten Tag steht.
* **Ein echter Fehler, den das gefunden hat:** die Zeilen des Starters sind breiter als
  ihre Liste und liefen unter dem Rollbalken bis an den Fensterrand. Eine Listenzeile wird
  jetzt an der UTF-8-Grenze gekürzt und mit drei Punkten geschlossen — und **gemeldet wird
  die gekürzte Zeile**, nicht die gewünschte.
* Zweiter echter Fehler: die Beschriftung der Akzentfarbe war breiter als ihre Spalte und
  lief in die rechte Spalte. Text gekürzt (de + en).
* Die Taskleiste sagt jetzt selbst, welcher Formsatz läuft (`taskbar: shape file=`) — vorher
  hatte eine Aufnahme des bloßen Schreibtischs keine Stelle, an der das nachprüfbar stand.

## Drei Fehler im Läufer selbst, benannt statt versteckt

Kein bestehender Test wurde entschärft. Diese drei **maßen etwas anderes als das, was sie
behaupteten**:

1. `grep -c ... || echo 0` gab bei null Treffern **zwei** Zeilen `0` aus, und verglichen
   wurde ein Zweizeiler mit einer Zahl → immer rot. Dieselbe Zusage, jetzt einmal gezählt.
2. Die Zeile des **Fensters** (`name=win`) sieht aus wie ein Widget (`w`+zwei Buchstaben)
   und wurde gegen die **Innen**höhe gehalten — das misst das Fenster gegen sich selbst und
   ist immer rot. `win` ist kein Widget in `win`.
3. Die Rechteck-Prüfung sah nur die sichtbare Seite. Jetzt **beide** Seiten (74 Rechtecke
   statt 24) — strenger, nicht lockerer.

## Nächster Schritt

`docs/ROUNDTHEMESTORE.md` mit der Abnahme Abschnitt für Abschnitt, wie in den Runden davor.
