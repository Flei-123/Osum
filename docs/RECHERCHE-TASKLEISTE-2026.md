### Teilaufgabe 1: Recherchiere die Windows-11-Taskleiste im Detail als Bauvorlage für ein eigenes Betriebssystem (OrientOS). Liefere konkrete, umsetzbare Spezifikation, keine Marketingtexte. Punkte: (1) Layout und Maße — Höhe in Pixeln (Standard und 'kleine Taskleiste'), Icon-Größe, Abstände, Verhalten bei HiDPI und sehr breiten Monitoren (3440px ultrawide). (2) Ausrichtung: zentriert vs. linksbündig — wie wachsen die Icons bei zentrierter Anordnung, wie bleibt der Startknopf stabil. (3) Programmknöpfe NUR als Icon ohne Text: wie werden mehrere Fenster derselben App dargestellt (Stapel/Unterstrich), was passiert beim Überlaufen, wie sieht der aktive/hover/gedrückte Zustand aus, wie funktioniert die Vorschau beim Darüberfahren. (4) Angeheftete vs. laufende Programme. (5) Die Einstellung 'Beschriftungen anzeigen' (Windows 10 Stil 'Immer kombinieren / Nie kombinieren'). Gib am Ende eine kompakte Liste von Konfigurationsschlüsseln, die ein eigener Taskleisten-Code haben sollte.
# Windows‑11‑Taskleiste — Bauvorlage für OrientOS

Quellenlage vorab: Microsoft veröffentlicht **keine** offizielle Pixel-Spezifikation der Taskleiste. Die harten Zahlen unten stammen aus (a) der Microsoft-Iconography-Doku (Icon-Größen pro Skalierung), (b) reverse-engineerten Werten aus dem Windhawk-Projekt (`taskbar-icon-size`), das die nativen Layout-Konstanten direkt patcht, und (c) dem Ramen-Software Taskbar-Styling-Guide (XAML-Elementnamen und Visual States). Ich markiere unten jeweils **[verifiziert]**, **[reverse-engineered]** und **[Empfehlung OrientOS]**.

---

## 1) Layout und Maße

### Basiswerte bei 100 % Skalierung (96 DPI)

| Größe | Leistenhöhe | Icon | Buttonbreite | Registry `TaskbarSi` |
|---|---|---|---|---|
| Klein | 40 px | 16 px | ~32 px | 0 |
| **Standard** | **48 px** | **24 px** | **44 px** | 1 |
| Groß | 60 px | 32 px | ~48 px | 2 |

Die Standardzeile (48 / 24 / 44) ist **[reverse-engineered, belastbar]** — der Windhawk-Mod nennt exakt „Windows 11 default: 48 / 24 / 44". Klein und Groß sind **[reverse-engineered, weniger belastbar]**; `TaskbarSi` funktioniert seit 22H2 Moment 2 auf vielen Builds nicht mehr, Microsoft hat den Pfad faktisch aufgegeben und stattdessen „Kleinere Taskleistenschaltflächen anzeigen" mit den Werten *Immer / Wenn Taskleiste voll / Nie* in die Einstellungen genommen.

### Abgeleitete Innenmaße (Standard, 48 px)

```
Leistenhöhe            48
Icon                   24            → 24 px vertikaler Restraum
Icon-Padding vertikal  12 oben / 12 unten (visuell ~11/13, Indikator frisst unten Platz)
Buttonbreite           44            → 10 px Padding links/rechts um das 24er Icon
Button-Gap             0             (Buttons stoßen aneinander, Trennung nur durch Hover-Plate)
Hover-Plate            ~40 × 40, Corner-Radius 4–6 (Win11-Standard-Radius: 4 px für kleine Controls)
Laufindikator          Breite 16 (aktiv) / 6 (inaktiv), Höhe 3, Abstand 4 px vom unteren Rand
Startknopf             gleiche 44 px Zelle wie App-Buttons
Systray-Icons          16 px, Zellenbreite ~24–28 px
Leistenrand links/rechts  ~8 px
```

Der Styling-Guide bestätigt für die Elementstruktur: `Taskbar.TaskListButton#TaskListButton` → `Grid#IconPanel` → `Image#Icon`, `Rectangle#RunningIndicator`, `Rectangle#DefaultIcon` (3×3 px Punkt für Multi-Window), `TextBlock#LabelControl`.

### HiDPI

Windows skaliert die Taskleiste **nicht** stufenlos, sondern rastet auf die Icon-Assetgrößen ein **[verifiziert, MS Iconography-Doku]**:

| Skalierung | 100 % | 125 % | 150 % | 175 % | 200 % | 250 % | 300 % | 400 % |
|---|---|---|---|---|---|---|---|---|
| Icon | 24 | 30 | 36 | 42 | 48 | 60 | 72 | 96 |
| Höhe (48·f) | 48 | 60 | 72 | 84 | 96 | 120 | 144 | 192 |
| Button (44·f) | 44 | 55 | 66 | 77 | 88 | 110 | 132 | 176 |

**Regeln für OrientOS:**
- Alle Maße in DIPs definieren, erst beim Rendern mit `scale` multiplizieren, dann `round()` auf ganze Pixel. Nicht floor — sonst kollabieren 3‑px‑Indikatoren bei 125 % auf 3 statt 4.
- Icon-Assets in **16 / 24 / 32 / 48 / 256** vorhalten. Nie hochskalieren, immer die nächstgrößere Stufe herunterskalieren (Windows' 24 px sind heruntergerechnete 32er und deshalb sichtbar weich — dieser Fehler ist in OrientOS vermeidbar, wenn ihr ein 24er-Asset erzwingt).
- Pro Monitor eigener Skalierungsfaktor (Per-Monitor-DPI-Aware V2). Die Leiste auf Monitor B wird neu gelayoutet, nicht gestreckt.

### Ultrawide (3440 px)

Windows tut hier faktisch **nichts Besonderes** — und genau das ist das Problem, das ihr lösen solltet:
- Bei zentrierter Ausrichtung liegt die Icon-Gruppe in der optischen Mitte, die Systray-Uhr ganz rechts am Rand. Auf 3440 px sind das ~1500 px Mausweg zwischen Startknopf und Uhr.
- **[Empfehlung OrientOS]** Einen `max_content_width` einführen (z. B. 1920 DIPs) und einen Modus `ultrawide_anchor`: Bei Monitorbreite > Schwellwert wird der komplette Leisteninhalt (Start + Apps + Tray) in ein zentriertes Band dieser Breite gepackt, statt Tray an den physischen Rand zu nageln. Alternativ `tray_follows_content: true`.
- Zweiter nützlicher Modus: `segmented` — Leiste rendert nur über einem Teilbereich (z. B. mittlere 2560 px), der Rest bleibt Desktop. Windows kann das nicht, Ultrawide-Nutzer bauen es mit Drittsoftware nach.
- Überlaufberechnung immer gegen den **verfügbaren** Bereich, nicht gegen die Monitorbreite.

---

## 2) Ausrichtung: zentriert vs. linksbündig

Registry `TaskbarAl`: **0 = links, 1 = zentriert** (Standard 1). Rechtsbündig wird von einigen Tools über denselben Schlüssel angeboten, ist aber kein natives Windows-Feature.

### Wachstumsverhalten bei zentrierter Anordnung

Der entscheidende Punkt, den Windows 11 gelöst hat: **Der Startknopf ist Teil der zentrierten Gruppe, nicht fixiert.** Es gibt genau ein Layout-Cluster:

```
[Start][Suche][TaskView][App1][App2][App3] … 
     ^ dieser gesamte Block wird als Einheit zentriert
```

Beim Öffnen einer neuen App wächst der Block um genau eine Buttonbreite (44 px), und **beide Enden verschieben sich um 22 px nach außen**. Der Startknopf wandert also nach links, alle bestehenden Buttons wandern nach rechts. Neue Buttons werden immer **rechts angehängt**.

Konsequenzen und Gegenmaßnahmen:

| Problem | Windows-11-Verhalten | **[Empfehlung OrientOS]** |
|---|---|---|
| Startknopf bewegt sich → Muskelgedächtnis kaputt | akzeptiert, Hauptkritikpunkt an Win11 | Modus `start_pinned_left: true` — Startknopf bleibt bei x=8 verankert, nur die App-Gruppe zentriert sich im Restbereich |
| Alle Buttons springen beim App-Start | Animation ~150 ms Ease-Out | gleiche Animation, aber `reflow_animation_ms` konfigurierbar, 0 = sofort |
| Klick geht ins Leere weil Icon wegrutscht | tritt real auf | **Reflow-Freeze**: solange der Mauszeiger über der Leiste steht, Layoutänderungen zurückhalten und erst 300 ms nach Verlassen anwenden. Löst das Problem vollständig |
| Ungerade Buttonanzahl | Rundung, ½‑Pixel-Versatz | Zentrum immer auf ganze Pixel runden, Rundungsrichtung konstant halten (sonst 1‑px-Jitter) |

Bei **linksbündig** entfällt das alles: Anker bei x = `edge_padding`, Wachstum nur nach rechts, Startknopf ist absolut stabil. Für OrientOS ist links der sichere Default für Poweruser, zentriert der ästhetische Default.

---

## 3) Programmknöpfe nur als Icon (kombinierter Modus)

### Mehrere Fenster derselben App

Windows 11 zeigt beides gleichzeitig — Indikator **und** Stapel:

1. **Laufindikator (`RunningIndicator`)**, Linie unter dem Icon:
   - kein Fenster (nur angeheftet): kein Indikator
   - 1 Fenster, nicht fokussiert: kurzer Strich, ~6 px, gedämpfte Farbe
   - 1 Fenster, fokussiert: langer Strich, ~16 px, Akzentfarbe
   - Aufmerksamkeit gefordert (Flash): roter Strich + rötliche Backplate
2. **Stapel-Effekt**: bei ≥ 2 Fenstern wird hinter dem Icon eine leicht versetzte Kopie der Button-Backplate gerendert (~2–3 px nach rechts/oben), sodass der Button wie ein Kartenstapel wirkt. Zusätzlich existiert `Rectangle#DefaultIcon` als 3×3‑px‑Punkt-Indikator.

**[Empfehlung OrientOS]** Nicht beides mischen. Sauberer: Indikator kodiert **Fokus**, Stapelkante kodiert **Anzahl**. Bei ≥ 3 Fenstern nicht mehr Kanten stapeln (wird Matsch), sondern eine kleine Zahl im Badge.

### Zustände

| Zustand | Backplate | Icon | Indikator |
|---|---|---|---|
| Idle, angeheftet | transparent | 100 % | keiner |
| Idle, laufend | transparent | 100 % | kurz, gedämpft |
| **Hover** | Subtle-Fill ~8 % Weiß, Radius 4, Fade-In 100 ms | 100 %, optional 1,05× Scale | Indikator wächst leicht |
| **Pressed** | Fill ~4 % (dunkler als Hover) | **Icon auf 0,92 skaliert**, 80 ms | unverändert |
| **Aktiv/fokussiert** | Fill ~12 %, dauerhaft | 100 % | lang, Akzentfarbe |
| Aktiv + Hover | Fill ~16 % | 100 % | lang |
| Attention/Flash | rötliche Backplate, Pulsieren 1 s | 100 % | rot |
| Tastaturfokus | zusätzlich 2‑px‑Fokusring, 2 px Offset | — | — |

Die Zustandsnamen aus der echten Implementierung, die ihr 1:1 übernehmen könnt: `NoRunningIndicator`, `ActiveRunningIndicator`, `InactivePointerOver`, `Pressed`, `MultiWindow`, `RequestingAttentionMulti`.

### Überlauf

Windows 11 (ab 22H2): Reicht der Platz nicht, wandern Buttons in ein **Overflow-Flyout**, erreichbar über ein Chevron/„⋯" am rechten Ende der App-Gruppe. Icons im Flyout bleiben voll funktional (Klick, Rechtsklick, Kontextmenü), Badges und Attention-Flash funktionieren dort weiter.

Priorisierung beim Verdrängen (so verhält sich Windows, so solltet ihr es auch machen):
1. zuerst laufende, nicht angeheftete Apps, am längsten nicht benutzt zuerst
2. dann angeheftete ohne laufendes Fenster
3. **nie** die fokussierte App, nie Start/Suche/TaskView

Alternativstrategie, die Windows 10 hatte und die ihr als Option anbieten solltet: **Shrink-before-overflow** — Buttonbreite von 44 auf bis zu 32 px reduzieren, bevor überhaupt ausgelagert wird. Das ist die alte Einstellung „Kleinere Schaltflächen, wenn Taskleiste voll".

### Vorschau beim Darüberfahren

- Auslöseverzögerung: standardmäßig die System-Hover-Zeit (`SPI_GETMOUSEHOVERTIME`, 400 ms). Überschreibbar per `ExtendedUIHoverTime` (DWORD, Millisekunden) unter `HKCU\...\Explorer\Advanced`. 1 = sofort, bis 5000 sinnvoll, 30000 = praktisch deaktiviert. **[verifiziert]**
- Beim Wandern zwischen benachbarten Buttons entfällt die Verzögerung (Flyout bleibt offen, Inhalt wechselt). Schließen mit ~150–300 ms Verzögerung, damit die Maus diagonal ins Flyout fahren kann („Safe Triangle" wie bei Menüs).
- Inhalt: pro Fenster ein DWM-Thumbnail (Live, nicht Standbild), Titelzeile, App-Icon 16 px, Schließen-X oben rechts.
- Thumbnailgröße dynamisch: bei 1 Fenster größer, bei vielen kleiner; ab einer Grenze (Windows: grob ~10–12 Fenster) fällt die Darstellung auf eine **Textliste ohne Thumbnails** zurück.
- Hover über ein Thumbnail → **Aero Peek**: alle anderen Fenster werden zu Glasrahmen, das gemeinte Fenster kurzzeitig eingeblendet, ohne Fokuswechsel.
- Positionierung: horizontal am Button zentriert, geklemmt an Arbeitsbereichsränder, vertikal `taskbar_top - gap` (Gap ~8 px).

---

## 4) Angeheftet vs. laufend

Ein Button repräsentiert im kombinierten Modus **eine Identität**, nicht ein Fenster. Identität = AppUserModelID (AUMID), Fallback: Executable-Pfad + Shell-Link-Zielprüfung.

| | Angeheftet, nicht laufend | Angeheftet, laufend | Laufend, nicht angeheftet |
|---|---|---|---|
| Position | fest, in Pin-Reihenfolge, ganz links der App-Gruppe | **dieselbe** feste Position | rechts nach allen Pins, in Startreihenfolge |
| Indikator | keiner | ja | ja |
| Klick | startet App | fokussiert / minimiert (Toggle) bzw. Vorschau bei mehreren Fenstern | wie links |
| App schließen | — | Button bleibt, Indikator verschwindet | **Button verschwindet**, Rest rückt nach |
| Drag | verschiebbar → ändert Pin-Reihenfolge | verschiebbar | Windows 11: nicht sortierbar |
| Kontextmenü | Jump List (statisch), „Lösen" | Jump List + „Alle Fenster schließen", „Lösen" | Jump List + „An Taskleiste anheften" |

**Wichtige Invariante:** Anheften einer laufenden App darf den Button **nicht springen lassen** — Windows tut das aber (er wandert an die Pin-Position). **[Empfehlung OrientOS]** Beim Anheften die Pin-Position auf den aktuellen Index setzen, dann bleibt der Button stehen.

Persistenz: Windows speichert Pins in `%AppData%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar` (Verknüpfungen) plus Binärblob in `HKCU\...\Taskband\Favorites`. Für OrientOS: **eine** deklarative Datei (TOML/JSON) mit Liste von `{app_id, exec, args, icon_override, index}` — kein Binärblob, das war schon in Windows der Grund für kaputte Pins nach Updates.

---

## 5) „Beschriftungen anzeigen" / Kombinationsmodus

Registry: `TaskbarGlomLevel` (Hauptmonitor) und `MMTaskbarGlomLevel` (Nebenmonitore), DWORD unter `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced`. **[verifiziert]**

| Wert | Windows-Bezeichnung | Verhalten |
|---|---|---|
| **0** | Immer kombinieren, Beschriftungen ausblenden | 1 Button pro App, nur Icon, 44 px. Windows-11-Default. |
| **1** | Kombinieren, wenn Taskleiste voll | 1 Button **pro Fenster** mit Text; bei Platzmangel Fallback auf 0 |
| **2** | Nie kombinieren | 1 Button **pro Fenster** mit Text, permanent; bei Platzmangel Überlauf statt Kombinieren |

In Windows 11 fehlte das von 21H2 bis 22H2 komplett und kam erst mit **23H2** zurück (UI: Einstellungen → Personalisierung → Taskleiste → Verhalten → „Taskleistenschaltflächen kombinieren und Beschriftungen ausblenden", separat für Haupt- und Nebenmonitor).

### Maße im Beschriftungsmodus

```
Buttonbreite   min 88, max 168 DIPs (Windows: dynamisch je nach Platz)
Innenaufbau    [8 px][Icon 16-24][8 px][Label, ellipsized][8 px]
Textstil       12 px, Regular, TextTrimming = CharacterEllipsis, kein Umbruch
Höhe           unverändert 48 px (Leiste wird nicht höher)
Indikator      bei Modus 1/2 kodiert er nur Fokus, nicht Fensteranzahl
```

Schrumpfregel: Beim Füllen der Leiste werden alle Buttons gleichmäßig von 168 → 88 verkleinert. Erst wenn 88 unterschritten würde, greift Modus 1 (kombinieren) bzw. Modus 2 (Überlauf).

**Gruppierung im Modus 2:** Fenster derselben App bleiben trotz „nie kombinieren" **benachbart** gruppiert (kein separater Rahmen, aber die Sortierung hält sie zusammen). Wichtig, sonst wird die Leiste bei mehreren Browsern unbrauchbar.

---

## 6) Konfigurationsschlüssel für OrientOS

```toml
[taskbar.geometry]
size_preset            = "medium"    # small | medium | large | custom
height                 = 48          # DIPs, wirksam bei custom
icon_size              = 24          # 16 | 24 | 32
button_width           = 44
button_gap             = 0
edge_padding           = 8
corner_radius          = 4
indicator_height       = 3
indicator_width_active   = 16
indicator_width_inactive = 6
indicator_bottom_offset  = 4

[taskbar.placement]
edge                   = "bottom"    # bottom | top | left | right
alignment              = "center"    # left | center | right
start_pinned_left      = false       # Startknopf aus der Zentrierung herausnehmen
autohide               = false
autohide_reveal_px     = 2
always_on_top          = true
reserve_workarea       = true        # Fenster maximieren nicht darunter

[taskbar.ultrawide]
enabled                = true
trigger_width          = 2560        # ab dieser Monitorbreite aktiv
max_content_width      = 1920
tray_follows_content   = true
mode                   = "banded"    # off | banded | segmented

[taskbar.grouping]
combine_mode           = "always"    # always | when_full | never   (≙ TaskbarGlomLevel 0/1/2)
show_labels            = false       # implizit true bei when_full/never
label_width_min        = 88
label_width_max        = 168
label_font_size        = 12
keep_same_app_adjacent = true
multi_window_style     = "stack"     # none | stack | badge_count | both
stack_offset           = 2
stack_max_layers       = 2

[taskbar.overflow]
strategy               = "shrink_then_flyout"  # flyout | shrink | shrink_then_flyout
shrink_min_width       = 32
flyout_columns         = 5
evict_order            = ["running_unpinned_lru", "pinned_idle"]
never_evict            = ["focused", "system_buttons"]

[taskbar.preview]
enabled                = true
hover_delay_ms         = 400         # 0 = sofort; ≙ ExtendedUIHoverTime
close_delay_ms         = 250
live_thumbnails        = true
thumbnail_width        = 200
thumbnail_max_count    = 10          # darüber: Textliste
peek_enabled           = true
peek_delay_ms          = 150
list_fallback          = true
safe_triangle          = true

[taskbar.interaction]
click_action           = "toggle"    # focus | toggle | cycle
middle_click           = "new_instance"
shift_click            = "new_instance"
ctrl_click             = "cycle_windows"
drag_reorder_pinned    = true
drag_reorder_running   = true        # Windows kann das nicht — Vorteil für OrientOS
reflow_freeze_on_hover = true
reflow_freeze_ms       = 300
reflow_animation_ms    = 150
reflow_easing          = "ease_out_cubic"

[taskbar.pinning]
store_path             = "~/.config/orientos/taskbar/pins.toml"
identity_key           = "app_id"    # app_id | exec_path
pin_keeps_position     = true
jumplist_max_items     = 10

[taskbar.hidpi]
per_monitor_dpi        = true
snap_icon_sizes        = [16, 24, 32, 48, 64, 96, 256]
rounding               = "round"     # round | floor | ceil
min_effective_height   = 32

[taskbar.multimonitor]
mode                   = "all"       # primary_only | all | all_with_own_windows
secondary_combine_mode = "always"    # ≙ MMTaskbarGlomLevel
secondary_show_tray    = false

[taskbar.appearance]
material               = "acrylic"   # opaque | acrylic | mica | transparent
opacity                = 0.85
accent_from_wallpaper  = true
hover_fill_opacity     = 0.08
pressed_fill_opacity   = 0.04
active_fill_opacity    = 0.12
pressed_icon_scale     = 0.92
attention_flash_count  = 3
```

---

## Zusammenfassung

- **Harte Zahlen:** 48 px Höhe / 24 px Icon / 44 px Button bei 100 % ist der Standard; 40/16/32 klein, 60/32/48 groß. Skalierung rastet auf 24‑30‑36‑48‑60‑72‑96 ein.
- **Zentrierung:** ein einziges Layout-Cluster inklusive Startknopf, wächst symmetrisch nach beiden Seiten, neue Buttons rechts. Der bewegliche Startknopf ist die größte UX-Schwäche — `start_pinned_left` und `reflow_freeze_on_hover` sind die zwei Fixes, die OrientOS besser machen können.
- **Zustände:** sechs Visual States mit den bewährten Namen aus der Windows-Implementierung; Indikator kodiert Fokus, Stapel kodiert Anzahl.
- **Überlauf:** Windows 11 kann nur Flyout, Windows 10 konnte nur Schrumpfen — `shrink_then_flyout` kombiniert beides.
- **Ultrawide:** Windows löst es gar nicht. `max_content_width` + `tray_follows_content` sind auf 3440 px der spürbarste Gewinn gegenüber der Vorlage.
- **Kombinationsmodus:** dreiwertig (always / when_full / never), separat pro Monitor, in Windows als `TaskbarGlomLevel` / `MMTaskbarGlomLevel`.

Sources:
- [Construct your Windows App's Icon — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction)
- [Windhawk — Taskbar height and icon size](https://windhawk.net/mods/taskbar-icon-size)
- [ramensoftware/windows-11-taskbar-styling-guide — Pills theme](https://github.com/ramensoftware/windows-11-taskbar-styling-guide/blob/main/Themes/Pills/README.md)
- [How to enable Taskbar labels and never combine on Windows 11 — Pureinfotech](https://pureinfotech.com/show-taskbar-labels-never-combine-windows-11/)
- [Hands on with Windows 11's 'never combine' taskbar feature — BleepingComputer](https://www.bleepingcomputer.com/news/microsoft/hands-on-with-windows-11s-never-combine-taskbar-feature/)
- [How to enable new taskbar overflow in Windows 11 22H2 — Neowin](https://www.neowin.net/guides/how-to-enable-new-taskbar-overflow-in-windows-11-22h2-beta/)
- [Change Hover Time to Show Taskbar Thumbnail Previews — ElevenForum](https://www.elevenforum.com/t/change-hover-time-to-show-taskbar-thumbnail-previews-in-windows-11.6366/)
- [How to Change the Speed of Windows' Taskbar Thumbnail Previews — How-To Geek](https://www.howtogeek.com/20052/increase-the-speed-of-the-aero-taskbar-thumbnails-in-windows-7/)
- [How to Align Taskbar to the left on Windows 11 — Prajwal Desai](https://www.prajwaldesai.com/align-taskbar-to-the-left-on-windows-11/)
- [How to Change the Taskbar Size in Windows 11 — Tom's Hardware](https://www.tomshardware.com/how-to/change-taskbar-icon-size-windows-11)
- [How to Change Taskbar Height, Icon Size and Width in Windows 11 — iTechGuides](https://www.itechguides.com/how-to-change-the-taskbar-height-icon-size-and-icon-width-in-windows-11/)

---

### Teilaufgabe 2: Recherchiere den Windows-11-Infobereich (System Tray) rechts in der Taskleiste als Bauvorlage. Konkret: (1) Welche Symbole gibt es standardmäßig (Netz, Lautstärke, Akku, Eingabesprache, Uhr, Benachrichtigungen, überlaufender Chevron-Pfeil) und in welcher Reihenfolge. (2) WICHTIGSTE FRAGE: Wann wird ein Symbol GAR NICHT angezeigt — z. B. Akku-Symbol auf einem Desktop-PC ohne Batterie, WLAN-Symbol auf einem Gerät ohne WLAN-Adapter. Wie entscheidet Windows das, und was zeigt es stattdessen (LAN-Symbol statt WLAN etc.)? (3) Wie ist die Uhr konfigurierbar: nur Uhrzeit, Uhrzeit+Datum, mit/ohne Sekunden, mit/ohne Wochentag — welche Registry-/Einstellungsschlüssel gibt es dafür, und wie verhält sich die Breite der Uhr bei verschiedenen Formaten. (4) Der Überlaufbereich (versteckte Symbole hinter dem Pfeil) — wie kommt ein Symbol dorthin. Ergebnis als konkrete Regel-Liste, die man 1:1 in Code gießen kann.
# Windows-11-Infobereich (System Tray) — Bauvorlage

Stand: Win11 22H2–25H2. Alle Angaben als Code-Regeln formuliert. Unsicherheiten sind explizit markiert.

---

## 1. Aufbau & Reihenfolge (links → rechts)

Der Tray ist in Win11 **kein frei sortierbares Ganzes**, sondern besteht aus festen Zonen. Reihenfolge in der Taskleisten-Ecke:

| # | Zone | Element | Verschiebbar? |
|---|------|---------|---------------|
| 1 | Overflow | **Chevron ^** („Ausgeblendete Symbole") | nein, feste Position ganz links |
| 2 | App-Icons | Promotete App-Tray-Icons (OneDrive, Defender, Teams, Druckertreiber …) | ja, per Drag&Drop untereinander und in/aus Overflow |
| 3 | Corner Icons | Stifteingabe (Pen), Touch-Tastatur, Virtuelles Touchpad | nein (nur an/aus) |
| 4 | Input | **Eingabeanzeige** (`DEU`, `ENG`, IME) | nein |
| 5 | System | **Netzwerk + Lautstärke + Akku** — als *ein* zusammengefasster „Quick Settings"-Button (Win+A) | nein, Reihenfolge innerhalb fix: Netz, Lautstärke, Akku |
| 6 | Clock | **Uhrzeit + Datum** (= zugleich Notification-Center-Button, Win+N) | nein |
| 7 | Badge | **Benachrichtigungs-Badge / Glocke** (bzw. Mond bei „Nicht stören") | überlagert Zone 6 |
| 8 | Ende | **„Desktop anzeigen"**-Streifen (schmaler Balken ganz rechts) | nein, optional abschaltbar |

**Wichtiger Unterschied zu Win10:** Netz/Lautstärke/Akku sind in Win11 **keine drei einzeln anklickbaren Icons** mehr, sondern ein einziger Hit-Target-Block, der Quick Settings öffnet. Für einen Nachbau heißt das: die drei Glyphen rendern, aber als *eine* Schaltfläche behandeln.

**Benachrichtigungen:** In Win11 gibt es keinen eigenen „Action-Center"-Button mehr wie in Win10. Die Zahl ungelesener Benachrichtigungen erscheint als **Badge über der Uhr**. Ab 24H2 gilt zusätzlich: bei aktivem „Nicht stören" wird **kein Glocken-Icon mehr** angezeigt.

---

## 2. ⭐ Wann ein Symbol GAR NICHT erscheint (Kernfrage)

Grundprinzip: **Windows rendert Systemsymbole hardware- und zustandsgesteuert, nicht statisch.** Es gibt kein „Akku-Icon ausgegraut" — es existiert schlicht nicht, und die Nachbarelemente rücken auf. Die Settings-Schalter für diese Icons sind auf betroffenen Geräten gar nicht erst vorhanden (nicht nur deaktiviert).

### Regel-Liste (Pseudocode)

```
// ---------- AKKU ----------
if (GetSystemPowerStatus().BatteryFlag & 128)   // 128 = "No system battery"
    render_battery = FALSE          // Desktop-PC: Icon existiert nicht, Platz entfällt
else
    render_battery = TRUE
    state = charging | discharging | full | saver | low | critical
// Zusatz: Windows zeigt auch bei angeschlossenen Bluetooth-/Peripherie-Akkus
// KEIN Tray-Akku - nur bei System-Batterie (ACPI Battery device).

// ---------- NETZWERK ----------
adapters = alle aktiven, nicht-deaktivierten, nicht-versteckten NICs
if (adapters.empty())              render_network = FALSE   // sehr selten (VM ohne NIC)
else if (kein Adapter connected)   glyph = GLOBE_disconnected  // "Nicht verbunden"
else {
    primary = Adapter der Default-Route (niedrigste Metrik)
    if (primary.type == WLAN)      glyph = WIFI_bars(0..4)
    else if (primary.type == ETH)  glyph = ETHERNET
    else if (primary.type == WWAN) glyph = CELLULAR_bars
    // NCSI-Overlay unabhängig vom Typ:
    if (!NCSI.internetReachable)   glyph += WARNING_overlay  // bzw. Globus in 22H2+
    if (VPN aktiv)                 glyph += VPN_shield
    if (Flugmodus)                 glyph = AIRPLANE          // ersetzt alles
}
```

**Kernaussage zu WLAN vs. LAN:** Es gibt **kein separates WLAN- und LAN-Icon nebeneinander**. Es ist *ein* Netzwerk-Slot, dessen Glyph durch den **aktiven Primäradapter** bestimmt wird. Ein Desktop ohne WLAN-Karte zeigt deshalb einfach das Ethernet-Symbol — kein durchgestrichenes WLAN. Ist LAN *und* WLAN verbunden, gewinnt der Adapter mit der besseren Routenmetrik (typisch: Ethernet). Ab Win11 22H2 wird bei „keine Verbindung / kein Internet" häufig ein **Globus** statt des typspezifischen Symbols gezeigt — das ist beabsichtigtes Verhalten, kein Bug.

```
// ---------- LAUTSTÄRKE ----------
if (kein aktives Render-Endpoint / kein Audio-Gerät)  render_volume = FALSE
else glyph = muted | vol_0 | vol_low | vol_mid | vol_high

// ---------- EINGABEANZEIGE (Sprache) ----------
if (count(installierte Tastaturlayouts / IMEs) >= 2)  render_input = TRUE
else                                                  render_input = FALSE
// Bei genau 1 Layout ist der Indikator NICHT sichtbar und auch nicht erzwingbar
// (außer über die klassische, angedockte Sprachleiste).

// ---------- CORNER ICONS ----------
render_pen        = Digitizer/Stift-Hardware vorhanden AND Setting an
render_touchkbd   = Setting (immer / nie / nur ohne Tastatur)
render_touchpad   = Touchscreen vorhanden AND Setting an

// ---------- CHEVRON ----------
render_chevron = SystemTrayChevronVisibility == 1
// Hinweis: Chevron bleibt sichtbar, auch wenn Overflow leer ist,
// solange der Schalter an ist.
```

### Policy-Ebene (überschreibt alles)
`HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer` (bzw. HKLM):

| Wert | =1 bewirkt |
|---|---|
| `HideSCAPower` | Akku-Symbol entfernt |
| `HideSCANetwork` | Netzwerk-Symbol entfernt |
| `HideSCAVolume` | Lautstärke-Symbol entfernt |
| `HideSCAHealth` | Wartungscenter entfernt |
| `HideClock` | Uhr entfernt |
| `NoTrayItemsDisplay` | kompletter Infobereich entfernt |

Wenn eine dieser Policies gesetzt ist, sind die zugehörigen Schalter in den Settings **ausgegraut** — im Unterschied zum Hardware-Fall, wo sie ganz fehlen. Das ist ein gutes Unterscheidungsmerkmal für den Nachbau.

**Zusammengefasste Anzeigelogik:**
```
sichtbar = HardwareVorhanden AND !PolicyHidden AND UserSettingAn
```
Fehlt die Hardware → Slot verschwindet komplett, Layout kollabiert (kein Platzhalter).

---

## 3. Uhr — Konfiguration & Breite

### Schalter und Registry

| Funktion | UI-Pfad | Registry |
|---|---|---|
| Sekunden anzeigen | Personalisierung → Taskleiste → Verhalten → „Sekunden in der Systray-Uhr anzeigen" | `HKCU\...\Explorer\Advanced` → `ShowSecondsInSystemClock` (DWORD 0/1) |
| Uhr/Datum ganz aus | Zeit & Sprache → Datum & Uhrzeit → „Uhrzeit und Datum in der Taskleiste ausblenden" (23H2) bzw. „…anzeigen" (24H2) | `HKCU\...\Explorer\Advanced` → `HideSystrayDateTime` (DWORD 1) ⚠️ Wertname variiert je Build, in Quellen auch als `ShowSystemTrayDateTime` genannt — **vor Verwendung am Zielsystem verifizieren** |
| Verkürzte Anzeige | Taskleisten-Einstellungen → „Verkürzte Zeit und Datum anzeigen" | `HKCU\...\Explorer\Advanced` → `ShowShortenedDateTimeFormat` (DWORD 0/1) |
| Uhr per Policy weg | GPO | `HKCU\Software\Policies\Microsoft\Windows\Explorer` → `HideClock` = 1 |
| Format Uhrzeit | Zeit & Sprache → Sprache & Region → Administrative Spracheinstellungen → Formate → Weitere Einstellungen → Uhrzeit → **Kurze Zeit** | `HKCU\Control Panel\International` → `sShortTime` |
| Format Datum | dito → Datum → **Kurzes Datum** | `HKCU\Control Panel\International` → `sShortDate` |

⚠️ **`ShowSecondsInSystemClock` gibt es erst ab Build 22621.1928.** Auf 21H2/frühem 22H2 existiert weder Schalter noch Wirkung.

### Kernpunkt: Es gibt KEINEN Schalter „nur Uhrzeit ohne Datum"
Win11 kennt nur: *Uhrzeit+Datum* oder *gar nichts*. Alles dazwischen wird über die **Regional-Format-Strings** erzwungen:

| Wunsch | Vorgehen |
|---|---|
| Wochentag anzeigen | `sShortDate` = `ddd dd.MM.yyyy` (kurz) oder `dddd, dd.MM.yyyy` (lang) |
| Datum verstecken, Uhr behalten | `sShortDate` = ein Leerzeichen oder ein einzelnes Literal |
| Uhr verstecken, Datum behalten | `sShortTime` = `s` (Legacy-Trick) |
| Sekunden ohne Settings-Schalter | `sShortTime` = `HH:mm:ss` — wirkt in älteren Builds **nicht** auf die Tray-Uhr |

Nebenwirkung: `sShortDate`/`sShortTime` gelten **systemweit** — auch Explorer-Spalten, Office, Datei-Dialoge übernehmen das Format. Das ist der bekannteste Kritikpunkt an dieser Methode.

### Breitenverhalten (für Layout-Code entscheidend)

1. Die Uhr ist ein **auto-size Block** — die Breite ergibt sich aus der gerenderten Textbreite plus feste Innenabstände. Es gibt keine fixe Spaltenbreite.
2. **Zwei Zeilen**, gestapelt: Zeile 1 Uhrzeit, Zeile 2 Datum. Die Blockbreite = `max(width(Zeile1), width(Zeile2))`. Meist dominiert das Datum.
3. **Sekunden an** verbreitert Zeile 1 um ca. 3 Zeichen (`:ss`) → typisch +18–25 px bei Standard-DPI. Ist das Datum breiter, ändert sich die Gesamtbreite **gar nicht**.
4. **Wochentag** (`ddd`/`dddd`) verbreitert Zeile 2 stark und ist damit fast immer der breitenbestimmende Faktor. `dddd` kann den Block auf das Doppelte bringen.
5. **24H2:** Das **Jahr wird nicht mehr angezeigt** — Standard ist nur Tag+Monat, wodurch der Block deutlich kompakter (fast quadratisch) wird. Wichtig: Ein 23H2-Layout ist nicht 1:1 auf 24H2 übertragbar.
6. **12h-Format** (`h:mm tt`) ist durch „AM/PM" breiter als 24h — genau das kürzt `ShowShortenedDateTimeFormat` weg (entfernt Jahr und Meridiem).
7. **Nichtproportionale Ziffern:** Windows rendert mit Tabular Figures, d. h. `11:11` und `08:38` sind gleich breit → die Uhr „zappelt" nicht im Sekundentakt. **Für einen Nachbau unbedingt `font-variant-numeric: tabular-nums` bzw. eine Monospace-Ziffernvariante setzen**, sonst flackert das Layout jede Sekunde.
8. Änderung der Breite → alle Elemente links davon verschieben sich; die Uhr bleibt rechtsbündig am Ende der Taskleiste verankert.
9. Uhr aus (`HideSystrayDateTime`) → Block-Breite 0, aber der **Klickbereich für das Notification Center bleibt bestehen** (schmaler unsichtbarer Streifen).

---

## 4. Der Überlaufbereich (Chevron)

### Wie ein Icon dorthin kommt

```
HKCU\Control Panel\NotifyIconSettings\<Hash-ID pro App>
    IsPromoted (DWORD)
        1 → Icon steht direkt im Tray
        0 (oder Wert fehlt) → Icon liegt im Overflow hinter dem Chevron
```

**Regeln:**

1. **Default für neue Apps: `IsPromoted = 0`** → jedes neu registrierte Tray-Icon landet zunächst im Overflow. Es gibt in Win11 **kein „Alle Symbole immer anzeigen"** mehr wie in Win10 — jede App muss einzeln promotet werden.
2. Der Nutzer promotet per **Drag&Drop** (aus dem Chevron-Flyout in den Tray) oder per Toggle unter *Einstellungen → Personalisierung → Taskleiste → Weitere Symbole in der Taskleistenecke*.
3. Der Schlüssel wird **pro App-Identität** angelegt (abgeleitet aus Executable-Pfad + GUID/UID des NOTIFYICONDATA). → **Ändert sich der Pfad (z. B. Versionsordner nach Update), gilt die App als neu und fällt zurück in den Overflow.** Das ist die Ursache des bekannten „Icons springen nach Updates zurück"-Verhaltens.
4. Es existieren dadurch häufig **Karteileichen** in der Liste (alte Versionspfade), die in den Settings als Duplikate erscheinen.
5. **Systemsymbole (Netz/Lautstärke/Akku/Uhr/Eingabeanzeige) können NIEMALS in den Overflow.** Der Overflow enthält ausschließlich App-Icons.
6. Chevron-Sichtbarkeit selbst:
   `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\TrayNotify` → `SystemTrayChevronVisibility` (1 = anzeigen, 0 = ausblenden).
   Bei `0` sind die dort liegenden Icons **komplett unzugänglich** — nicht nur eingeklappt.
7. **Kein automatischer Overflow bei Platzmangel.** Anders als Win10 verschiebt Windows 11 Icons *nicht* dynamisch bei voller Taskleiste — die Zuordnung ist rein durch `IsPromoted` bestimmt. Der Tray-Bereich wächst stattdessen nach links.
8. Alle Änderungen erfordern einen **Explorer-Neustart** (oder `WM_SETTINGCHANGE`-Broadcast), um sichtbar zu werden.

---

## Kompakte Implementierungs-Checkliste

```
render_tray():
  if PolicyNoTrayItemsDisplay: return

  if SystemTrayChevronVisibility: emit(CHEVRON)

  for icon in appIcons where IsPromoted == 1: emit(icon)     // sortierbar

  if hasPen        and setting: emit(PEN)
  if hasTouch      and setting: emit(TOUCH_KEYBOARD)
  if hasTouch      and setting: emit(VIRTUAL_TOUCHPAD)

  if layoutCount >= 2:          emit(INPUT_INDICATOR)

  emit_group(QUICK_SETTINGS):                                // ein Button
     if hasNIC     and !HideSCANetwork: emit(networkGlyph())  // WIFI|ETH|WWAN|GLOBE|AIRPLANE
     if hasAudio   and !HideSCAVolume:  emit(volumeGlyph())
     if hasBattery and !HideSCAPower:   emit(batteryGlyph())  // sonst KEIN Platzhalter

  if !HideClock and !HideSystrayDateTime:
     emit(CLOCK, lines=[fmt(sShortTime, seconds), fmt(sShortDate)])
     width = max(textWidth(line1), textWidth(line2)) + padding
     // tabular-nums verwenden!
  if unreadNotifications > 0 and !doNotDisturb: emit(BADGE over CLOCK)

  emit(SHOW_DESKTOP_STRIP)
```

**Die drei wichtigsten Nachbau-Fallen:**
1. Fehlende Hardware → Slot **entfällt ersatzlos**, kein ausgegrautes Icon, kein reservierter Platz.
2. Netz/Lautstärke/Akku sind **ein** Button, nicht drei.
3. Uhr-Breite ist dynamisch und wird meist vom **Datum**, nicht von der Uhrzeit bestimmt — Sekunden verbreitern oft gar nichts.

**Zu verifizieren:** Der exakte Wertname für „Uhrzeit und Datum ausblenden" (`HideSystrayDateTime` vs. `ShowSystemTrayDateTime`) unterscheidet sich zwischen Builds und sollte am konkreten Zielsystem geprüft werden, bevor er in Code fest verdrahtet wird.

**Sources:**
- [Customize the Taskbar in Windows – Microsoft Support](https://support.microsoft.com/en-us/windows/customize-the-taskbar-in-windows-0657a50f-0cc7-dbfd-ae6b-05020b195b07)
- [Hide or Show Notification Icons on Taskbar System Tray in Windows 11 – ElevenForum](https://www.elevenforum.com/t/hide-or-show-notification-icons-on-taskbar-system-tray-in-windows-11.415/)
- [Turn On or Off Hidden Icon Menu on Taskbar System Tray – ElevenForum](https://www.elevenforum.com/t/turn-on-or-off-hidden-icon-menu-on-taskbar-system-tray-in-windows-11.5132/)
- [Turn Off Show Seconds in System Tray Clock – NinjaOne](https://www.ninjaone.com/blog/turn-off-show-seconds-in-system-tray-clock/)
- [How to Set the Abbreviated Time and Date on the Taskbar – NinjaOne](https://www.ninjaone.com/blog/set-the-abbreviated-time-and-date-on-the-taskbar/)
- [How to hide clock and date from Taskbar on Windows 11 – Pureinfotech](https://pureinfotech.com/hide-clock-taskbar-windows-11/)
- [Show or Hide Time and Date on Taskbar System Tray – ElevenForum](https://www.elevenforum.com/t/show-or-hide-time-and-date-on-taskbar-system-tray-in-windows-11.14295/)
- [ADMX_Taskbar Policy CSP – Microsoft Learn](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-taskbar)
- [Globe icon instead of ethernet or wifi icon in system tray – ElevenForum](https://www.elevenforum.com/t/globe-icon-instead-of-ethernet-or-wifi-icon-in-system-tray-issue.23317/)
- [Add or Remove Language Bar in Windows 11 – ElevenForum](https://www.elevenforum.com/t/add-or-remove-language-bar-in-windows-11.10107/)
- [Windows 11 Battery Icon / Power Icon in System Tray – Microsoft Community Hub](https://techcommunity.microsoft.com/discussions/windows11/power-icon-in-the-windows-11-system-tray%E2%80%94percentage-of-remaining-battery-life-no/4544973)
- [How to add day of the week to the Taskbar Clock in Windows 11 – TheWindowsClub](https://www.thewindowsclub.com/add-day-of-week-to-taskbar-windows)
- [Show or Hide Touch Keyboard icon on Taskbar System Tray – ElevenForum](https://www.elevenforum.com/t/show-or-hide-touch-keyboard-icon-on-taskbar-system-tray-in-windows-11.2866/)

---

### Teilaufgabe 3: Recherchiere das Windows-11 'Schnelleinstellungen'-Panel (Quick Settings, Tastenkürzel Win+A) als Bauvorlage für ein eigenes Betriebssystem. Konkret: (1) Genauer Aufbau von oben nach unten: Medien-Steuerung des laufenden Players, Raster der Umschaltkacheln, Helligkeitsregler, Lautstärkeregler, Akkuanzeige, Zahnrad. (2) Die Kachel-Typen: einfacher Umschalter vs. Umschalter mit Pfeil (öffnet Unterseite, z. B. WLAN-Netzliste, Bluetooth-Geräte). Wie sieht die Unterseiten-Navigation aus (Zurück-Pfeil)? (3) Standardkacheln und welche davon auf einem Gerät ohne die jeweilige Hardware verschwinden. (4) Bearbeiten-Modus: Kacheln hinzufügen/entfernen/verschieben. (5) Verankerung und Größe des Panels: wo genau erscheint es, wie schließt es (Escape, Klick daneben, erneut Win+A), Animation. (6) Verhältnis zum getrennten Benachrichtigungs-Panel (Win+N). Gib eine kompakte Bauanleitung mit Maßen und Zustandsübergängen.
# Windows 11 Quick Settings (Win+A) — Rekonstruktion als Bauvorlage

**Wichtige Vorbemerkung zur Quellenlage:** Microsoft veröffentlicht *keine* Spezifikation dieses Panels (es ist Shell-intern, `ShellExperienceHost.exe` / `ShellHost.exe`, nicht Teil der WinUI-Doku). Alle Pixelmaße unten sind **abgeleitete Rekonstruktionswerte** aus WinUI-3-Standardmetriken + Screenshot-Vermessung bei 100 % Skalierung, nicht offizielle Zahlen. Die *Struktur*, *Zustandslogik* und *Kachelliste* sind belegt. Zusätzlich: **das Panel wurde in 24H2 umgebaut** — das ist für dich relevant, weil es zwei verschiedene Bauvorlagen gibt.

---

## 1. Aufbau von oben nach unten

Zwei Container in *einem* Popup-Fenster, vertikal gestapelt, mit Abstand dazwischen:

```
┌─────────────────────────────┐  ← Medien-Karte (nur wenn Session aktiv)
│ [Cover] Titel               │     eigener Container, eigener Backdrop
│         Interpret     ⏮ ⏸ ⏭ │
└─────────────────────────────┘
        ↕ 8 px Lücke
┌─────────────────────────────┐  ← Quick-Settings-Karte
│  [Kachel] [Kachel] [Kachel] │
│  [Kachel] [Kachel] [Kachel] │
│         ● ○   (Pips)        │
│  ☀ ──────●──────────        │  Helligkeit
│  🔊 ─────────●───────  🔈▾  │  Lautstärke (+ Ausgabegerät-Chevron)
│  🔋 87 %              ✏  ⚙  │  Fußzeile
└─────────────────────────────┘
```

**Reihenfolge und Regeln:**

| # | Element | Sichtbarkeitsbedingung |
|---|---|---|
| 1 | **Medien-Transportsteuerung** (SMTC) | Nur wenn mindestens eine App eine System-Media-Transport-Control-Session registriert hat (Spotify, Edge, Groove). Verschwindet komplett inkl. Layoutplatz, wenn nichts läuft. Bei mehreren Sessions: horizontal wischbar/Pips, aktive Session zuerst. |
| 2 | **Kachelraster** | Immer |
| 3 | **Seiten-Pips** | Nur wenn > 1 Seite (23H2) bzw. ersetzt durch Scrollbar (24H2) |
| 4 | **Helligkeitsregler** | Nur bei Displays mit steuerbarer Helligkeit (interne Panels, DDC/CI-fähige externe). Bei reinem Desktop mit dummem Monitor: **fehlt**. |
| 5 | **Lautstärkeregler** | Nur bei vorhandenem Audio-Endpunkt. Rechts ein Chevron → Ausgabegeräte-Unterseite. |
| 6 | **Akku-Zeile** (Symbol + Prozent, klickbar → Energie-Einstellungen) | Nur bei Akku vorhanden. Auf Desktop: **fehlt**. |
| 7 | **Stift-Symbol (Bearbeiten)** | Nur ≤ 23H2 (siehe §4) |
| 8 | **Zahnrad „Alle Einstellungen"** | Immer, rechts unten |

Fußzeile ist **eine Zeile**: links Akku, rechts Stift + Zahnrad.

---

## 2. Kacheltypen

Es gibt genau **drei** Typen — das ist die zentrale Designentscheidung:

**Typ A — Einfacher Umschalter (ToggleButton).**
Ganze Kachel ist eine Klickfläche. Klick = Zustand kippen. Visuell: aktiv = Akzentfarbe als Füllung + kontrastierendes Icon; inaktiv = neutrale, leicht abgehobene Fläche. Beispiele: Flugzeugmodus, Nachtlicht, Energiesparmodus, Standortdienste.

**Typ B — Geteilter Umschalter (Split-Button mit Chevron).**
Die Kachel ist in zwei Hit-Zonen geteilt: **links das Icon + Beschriftung = An/Aus**, **rechts ein schmaler Streifen mit `›`-Chevron = Unterseite öffnen**. Es gibt eine sichtbare 1-px-Trennlinie zwischen den Zonen, und beide Zonen haben *eigenen* Hover-Effekt — das ist wichtig für die Erlernbarkeit. Beispiele: WLAN, Bluetooth, Zugriffstasten/Bedienungshilfen, VPN, Mobilfunk.

**Typ C — Reiner Navigator.**
Kein Zustand, Klick auf die ganze Kachel öffnet direkt eine Unterseite oder einen Dialog. Beispiel: „Projizieren", „Übertragen" (Cast).

### Unterseiten-Navigation

Die Unterseite ist **kein neues Fenster** und kein Overlay — sie ersetzt den *gesamten Inhalt* der Quick-Settings-Karte, während die Karte selbst am Platz bleibt und ihre Höhe animiert auf die neue Inhaltshöhe fährt.

```
┌─────────────────────────────┐
│ ‹  WLAN                  ⟳  │  ← Kopfzeile: Zurück-Chevron, Titel, ggf. Aktion
├─────────────────────────────┤
│ 📶 FRITZ!Box 7590           │  ← Liste, scrollbar, max ~5 Einträge sichtbar
│    Verbunden, gesichert     │
│ 📶 Nachbar-WLAN             │
│ 📶 Gast                     │
├─────────────────────────────┤
│ Weitere WLAN-Einstellungen  │  ← Fußzeile: Deep-Link in die Settings-App
└─────────────────────────────┘
```

Regeln:
- **Nur eine Ebene tief.** Es gibt keine Unter-Unterseite. Alles Tiefere ist ein Deep-Link in die Einstellungen-App, der das Panel schließt.
- Zurück-Chevron `‹` immer **links oben**, gleiche Position auf jeder Unterseite.
- **Escape auf einer Unterseite = zurück zur Hauptseite**, nicht schließen. Erst der zweite Escape schließt. (Wichtig: Backstack hat Vorrang vor Dismiss.)
- Medien-Karte bleibt oben stehen, wird von der Navigation nicht berührt.
- Ein Klick auf einen Listeneintrag (z. B. WLAN) expandiert diesen inline zu einer Detailzeile mit „Automatisch verbinden"-Checkbox und „Verbinden"-Button — das ist Inline-Expansion, keine Navigation.

---

## 3. Standardkacheln und Hardware-Abhängigkeit

**Standard (erste Seite, 6 Kacheln, 3×2):** WLAN, Bluetooth, Flugzeugmodus, Energiesparmodus/Akkusparen, Bedienungshilfen, Nachtlicht — mit gerätespezifischen Abweichungen.

| Kachel | Verschwindet ohne … |
|---|---|
| WLAN | WLAN-Adapter |
| Bluetooth | Bluetooth-Radio |
| Flugzeugmodus | **jedes** Funkgerät (WLAN/BT/Mobilfunk) |
| Mobilfunk / Mobiler Hotspot | WWAN-Modem bzw. teilbare Verbindung |
| Akkusparen / Energiesparmodus | Akku |
| Rotationssperre | Beschleunigungssensor; zusätzlich **ausgegraut**, wenn das Gerät im Laptop-Modus ist |
| Nachtlicht | steuerbares Display |
| Übertragen (Cast) | Miracast-fähigen Grafiktreiber/Adapter |
| Projizieren | zweiten Anzeigeausgang |
| Nahegelegene Freigabe | Bluetooth LE |
| Standortdienste, Fokus-Assistent, Live-Untertitel, Bedienungshilfen, Farbprofil, Studioeffekte (nur mit NPU + kompatibler Kamera), OEM-Kacheln | jeweils Feature-/Treiber-abhängig |

**Bauregel:** Kachelverfügbarkeit ist ein *Fähigkeits-Query* zur Panel-Öffnungszeit, kein statisches Layout. Eine nicht verfügbare Kachel wird **entfernt und die Nachfolger rutschen nach**, sie wird nicht als Lücke oder ausgegraut gezeigt. Ausnahme: temporär nicht *nutzbar* (Rotationssperre im Laptop-Modus) → ausgegraut, bleibt sichtbar. Diese Unterscheidung „dauerhaft nicht vorhanden = weg" vs. „gerade nicht anwendbar = ausgegraut" solltest du übernehmen.

---

## 4. Bearbeiten-Modus — und der 24H2-Bruch

**Bis Windows 11 23H2 (das reichere Modell, für dich die bessere Vorlage):**

1. Klick auf Stift → Panel geht in Edit-State. Alle Kacheln bekommen ein **Löschsymbol (Pin-durchgestrichen / ✕) an der oberen rechten Ecke**, wackeln nicht (kein iOS-Jiggle), sind aber funktional deaktiviert (Klick schaltet nicht mehr um).
2. Unten erscheinen zwei Buttons: **„Hinzufügen" (mit +)** und **„Fertig"**.
3. „Hinzufügen" öffnet ein **Flyout-Menü** mit allen verfügbaren, aktuell nicht angehefteten Kacheln. Ist die Liste leer, ist der Button ausgegraut.
4. **Verschieben per Drag & Drop**: gezogene Kachel wird angehoben (Schatten + leichte Skalierung ~1,05), die anderen Kacheln machen animiert Platz (Reflow), Drop rastet ins Raster ein.
5. „Fertig" oder Escape verlässt den Edit-State. **Persistenz sofort**, nicht erst bei „Fertig".
6. Sonderfall: Bedienungshilfen und Zahnrad sind nicht entfernbar.

**Ab 24H2:** Der Stift ist **entfernt**. Das Raster ist stattdessen **scrollbar** statt seitenbasiert, und man kann nur noch **umsortieren** (Drag & Drop direkt, ohne Modus). Hinzufügen/Entfernen entfällt; „Verstecken" geht nur noch faktisch, indem man ungeliebte Kacheln nach unten schiebt. Das ist von Nutzern breit als Rückschritt kritisiert worden.

**Empfehlung für dein OS:** Nimm das 23H2-Modell (expliziter Edit-Modus mit Hinzufügen/Entfernen) und kombiniere es mit der 24H2-Scrollliste statt der Pip-Seiten. Die Seiten-Pips sind die schwächste Stelle des Originals — sie verstecken Kacheln hinter einer nicht entdeckbaren horizontalen Geste.

---

## 5. Verankerung, Maße, Öffnen/Schließen

**Position:** Rechtsbündig verankert an der **unteren rechten Ecke des Arbeitsbereichs**, über der Taskleiste. Nicht am Mauszeiger, nicht am geklickten Icon zentriert — immer dieselbe Ecke, egal ob per Win+A oder per Klick auf das Netzwerk/Lautstärke/Akku-Cluster geöffnet.

- Abstand zum rechten Bildschirmrand: **12 px**
- Abstand zur Taskleistenoberkante: **12 px**
- Bei linksbündiger Taskleiste: bleibt trotzdem rechts.
- Bei Taskleiste oben (nicht offiziell): würde nach oben klappen.
- Auf Multi-Monitor: erscheint auf dem Monitor mit der **fokussierten Taskleiste**.

**Maße (Rekonstruktionswerte, 100 % Skalierung):**

| Element | Wert |
|---|---|
| Panelbreite | **360 px**, fix (skaliert mit DPI, nicht mit Inhalt) |
| Höhe | inhaltsabhängig, ~300–460 px |
| Eckenradius | 8 px (Fenster), 4 px (Kacheln) |
| Innenabstand der Karte | 16 px rundum |
| Kachelraster | 3 Spalten × N Zeilen, Gap 8 px |
| Kachelgröße | ~104 × 68 px (Typ A/C), Typ B intern 76 px Toggle + 28 px Chevronzone |
| Icongröße in Kachel | 16 px, oben mittig-links, Text 12 px darunter, 1 Zeile, Ellipsis |
| Reglerzeile | 40 px Höhe, Icon 16 px links, Thumb 12 px |
| Fußzeile | 40 px Höhe |
| Medien-Karte | 360 × ~104 px, Cover 72 × 72 px links |
| Hintergrund | **Acryl** (Desktop-Acrylic, in-app blur ~30 px, Tint nach Hell/Dunkel-Theme), 1 px Rahmen mit Theme-Kontrast, Schlagschatten |

**Zustandsübergänge:**

```
GESCHLOSSEN
  ── Win+A ──────────────────────► OFFEN (Hauptseite)
  ── Klick Tray-Cluster ─────────►
OFFEN
  ── Win+A erneut ───────────────► GESCHLOSSEN   (Toggle)
  ── Escape ─────────────────────► GESCHLOSSEN
  ── Klick außerhalb (Light-Dismiss) ► GESCHLOSSEN
  ── Fokusverlust des Fensters ──► GESCHLOSSEN
  ── Win+N ──────────────────────► GESCHLOSSEN, dann Benachrichtigungen OFFEN
  ── Klick auf Chevron (Typ B/C) ► UNTERSEITE
  ── Klick auf Stift ────────────► EDIT
  ── Klick auf Zahnrad ──────────► GESCHLOSSEN + Settings-App startet
UNTERSEITE
  ── Zurück-Chevron / Escape ────► OFFEN (Hauptseite)
  ── Klick außerhalb ────────────► GESCHLOSSEN (Backstack wird verworfen)
EDIT
  ── Fertig / Escape ────────────► OFFEN (Hauptseite)
```

Wichtig: **Klick auf eine Kachel schließt das Panel nicht.** Nur Deep-Links und das Zahnrad schließen. Das Panel bleibt für Mehrfachbedienung offen — das ist ein bewusster Unterschied zu einem Menü.

**Animation:**
- Öffnen: 250 ms, `FluentEaseOut` / kubisch (0.1, 0.9, 0.2, 1.0). Kombination aus Fade (0→1 über 150 ms) und **vertikalem Slide von unten**, ~40 px Versatz. Zusätzlich leichte Skalierung 0,95 → 1,0 mit Transform-Origin unten rechts.
- Schließen: 150 ms, schneller als Öffnen, reines Fade + 20 px Slide nach unten.
- Höhenänderung bei Seitenwechsel/Unterseite: 300 ms Höhen-Animation, Inhalt kreuzblendet.
- Unterseiten-Wechsel: horizontaler Slide (neuer Inhalt von rechts herein, alter nach links heraus, ~200 ms) — analog zur Navigations-Semantik.

---

## 6. Verhältnis zum Benachrichtigungs-Panel (Win+N)

Windows 11 hat das Windows-10-**Info-Center bewusst in zwei getrennte Flyouts gespalten**:

| | Quick Settings (Win+A) | Benachrichtigungscenter (Win+N) |
|---|---|---|
| Trigger im Tray | Netzwerk/Lautstärke/Akku-Cluster | Datum/Uhrzeit |
| Inhalt | Systemsteuerung, Medien | Toasts (gruppiert nach App) + **Kalender-Monatsansicht** darunter |
| Verankerung | unten rechts, 12 px Rand | unten rechts, 12 px Rand — **dieselbe Ecke** |
| Breite | 360 px | ~360 px |

Beide sind **gegenseitig exklusiv**: Öffnen des einen schließt das andere sofort (kein Übergang, harter Wechsel, kein gemeinsamer Container). Sie teilen sich Position, Breite, Backdrop, Eckenradius und Öffnungsanimation — visuell wirken sie wie zwei Ansichten derselben Fläche, sind technisch aber getrennte Fenster.

**Bewertung für deinen Nachbau:** Diese Trennung ist der umstrittenste Teil des Designs. Der Vorteil ist, dass beide Panels flach und kurz bleiben. Der Nachteil: zwei Kürzel, zwei Trefferzonen in derselben Taskleistenecke, und Nutzer treffen regelmäßig das falsche. Wenn du sie trennst, mach die Trefferzonen im Tray **visuell klar separiert** (eigener Hover-Hintergrund pro Cluster) — genau das macht Windows 11, und es ist der einzige Grund, warum es einigermaßen funktioniert. Alternative: ein Panel mit zwei Tabs, was den Kürzelkonflikt auflöst.

---

## Kompakte Bauanleitung (Checkliste)

1. **Ein Popup-Fenster**, 360 px breit, Acryl-Backdrop, R8, verankert unten rechts mit 12 px Rand, Light-Dismiss aktiv.
2. **Vertikaler Stack**: [Medienkarte, bedingt] → 8 px → [QS-Karte].
3. **QS-Karte** = `NavigationFrame` mit Backstack der Tiefe 1. Root-Seite: Raster → Regler → Fußzeile.
4. **Raster**: 3 Spalten, 8 px Gap, scrollbar (nicht paginiert). Kacheln aus Fähigkeits-Query, nicht statisch.
5. **Kachel-Komponente** mit Property `hasDetailPage` → rendert Split-Button mit Chevron-Zone rechts, eigenem Hover, 1 px Trennlinie.
6. **Regler** nur rendern, wenn Fähigkeit vorhanden; Lautstärke bekommt Geräte-Chevron.
7. **Fußzeile**: Akku (bedingt) links, Edit-Stift + Zahnrad rechts.
8. **Edit-State** als Modus-Flag der Root-Seite: Kacheln → deaktiviert + ✕-Badge, Drag&Drop mit Reflow, Buttons „Hinzufügen"/„Fertig", Persistenz sofort.
9. **Escape-Kette**: Edit → Root → Unterseite → Root → geschlossen. Backstack schlägt Dismiss.
10. **Exklusivität** zum Benachrichtigungspanel per gemeinsamem Shell-Flyout-Manager erzwingen.

**Sources:**
- [Quick Settings (24H2) — Thurrott, Windows 11 Field Guide](https://www.thurrott.com/books/windows-11-field-guide/311804/quick-settings-24h2)
- [Quick Settings — Thurrott, Windows 11 Field Guide](https://www.thurrott.com/books/windows-11-field-guide/274144/quick-settings)
- [Customize the Quick Settings Panel in Windows 11 24H2 — allthings.how](https://allthings.how/customize-the-quick-settings-panel-in-windows-11-24h/)
- [How to Add, Remove, Rearrange Quick Settings in Windows 11 — WindowsLoop](https://windowsloop.com/how-to-open-add-or-remove-quick-settings-in-windows-11/)
- [How to add or remove Quick Settings icons on Windows 11 — Windows Central](https://www.windowscentral.com/how-add-or-remove-quick-settings-icons-windows-11)
- [How to Disable Media Controls Overlay in Windows 11 Quick Settings — Nerdschalk](https://nerdschalk.com/how-to-disable-media-controls-overlay-in-windows-11-quick-settings/)
- [How to use Quick Actions in Windows 11 — XDA](https://www.xda-developers.com/use-quick-actions-windows-11/)
- [System backdrops (Mica/Acrylic) — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/develop/ui/system-backdrops)

---

### Teilaufgabe 4: Recherchiere, wie Linux-Desktops (GNOME Shell, KDE Plasma 6, Cinnamon, XFCE, Waybar/wlroots) ihre Taskleiste, ihren Infobereich und ihr Schnelleinstellungs-Panel technisch aufbauen — als Vergleich für ein eigenes Betriebssystem, das alles selbst schreibt. Konkret: (1) Wie kommen die Statusinformationen zustande — welche Datenquellen für Akku (upower / sysfs /sys/class/power_supply), Netz (NetworkManager D-Bus), Lautstärke (PulseAudio/PipeWire), Helligkeit (backlight sysfs)? Nenne die konkreten Pfade/Schnittstellen. (2) Wie erkennt ein Panel, dass es KEINEN Akku gibt und blendet das Symbol aus? Zeige die tatsächliche Logik (z. B. leeres /sys/class/power_supply, oder Typ != Battery). (3) Wie wird die Fensterliste geliefert (EWMH _NET_CLIENT_LIST unter X11, foreign-toplevel-management unter Wayland)? (4) GNOME Quick Settings (seit 43) als Referenz für das Panel. Ziel: eine Liste der Datenquellen und Erkennungsregeln, die ein eigener Kernel selbst implementieren müsste.
# Linux-Desktop-Panels: Datenquellen & Erkennungsregeln

**Recherche-Hinweis:** UPower-, Kernel-ABI-, wlroots- und Waybar-Quellen konnte ich direkt verifizieren. GNOME-Shell-JS-Quellcode (`power.js`) war über Web nicht abrufbar (GitLab/GitHub-Raw liefern 404 gegen den Fetcher) — die dortigen Angaben stammen aus API-Doku + Fachkenntnis und sind unten als **[unverifiziert]** markiert.

---

## 1. Datenquellen im Detail

### 1.1 Akku / Stromversorgung

**Ebene A — Kernel (sysfs), die Ground Truth:**

```
/sys/class/power_supply/<name>/
    type              → "Battery" | "Mains" | "USB" | "UPS"   ← Schlüssel-Attribut
    scope             → "System" | "Device"   ← "Device" = Maus/Tastatur-Akku, NICHT System
    present           → 0|1  (hot-removable Akkus)
    status            → "Charging"|"Discharging"|"Full"|"Not charging"|"Unknown"
    capacity          → 0..100 (%)  [read-only, nicht immer vorhanden]
    capacity_level    → "Critical"|"Low"|"Normal"|"High"|"Full"
    energy_now/_full/_full_design   (µWh)   ← Variante A
    charge_now/_full/_full_design   (µAh)   ← Variante B (nie beide!)
    voltage_now       (µV)
    current_now / power_now
    online            → 0|1  (nur bei type=Mains/USB: Netzteil eingesteckt?)
    uevent            → alle Werte als KEY=VALUE-Block in einem Read
```

Typische Namen: `BAT0`, `BAT1`, `CMB0`, `AC`, `ADP1`, `ACAD`, `macsmc-battery`.

**Wichtig für einen eigenen Kernel:** `capacity` ist optional. Der robuste Weg ist `energy_now/energy_full` bzw. `charge_now/charge_full`. Waybar prüft explizit auf `capacity` **oder** `charge_now`.

**Ebene B — UPower (D-Bus System Bus), was Desktops tatsächlich nutzen:**

```
Bus:    System Bus
Name:   org.freedesktop.UPower
Pfad:   /org/freedesktop/UPower
Iface:  org.freedesktop.UPower
  Methode: EnumerateDevices() → ao
  Signale: DeviceAdded(o), DeviceRemoved(o)
  Property: OnBattery (b), LidIsClosed, LidIsPresent

Gerät:  /org/freedesktop/UPower/devices/battery_BAT0
Iface:  org.freedesktop.UPower.Device
  Type         u   0=Unknown 1=LinePower 2=Battery 3=Ups 4=Monitor
                   5=Mouse 6=Keyboard 7=Pda 8=Phone ... (bis 28)
  State        u   0=Unknown 1=Charging 2=Discharging 3=Empty
                   4=FullyCharged 5=PendingCharge 6=PendingDischarge
  IsPresent    b   ← Akku physisch im Schacht
  PowerSupply  b   ← TRUE nur wenn das Gerät DAS SYSTEM versorgt
                     (Laptop-Akku, USV) — FALSE bei Funkmaus/Headset
  Percentage   d   0..100
  TimeToEmpty  x   Sekunden, 0 = unbekannt
  TimeToFull   x
  WarningLevel u   0=Unknown 1=None 2=Discharging 3=Low 4=Critical 5=Action
  IconName     s   ← UPower liefert den Themen-Icon-Namen fertig mit
  Energy/EnergyFull/EnergyRate, Voltage, Temperature
  BatteryLevel u   (grob: für Geräte ohne Prozentwert)
  Signal: PropertiesChanged (via org.freedesktop.DBus.Properties)
```

**Der Aggregat-Trick — `DisplayDevice`:**
```
/org/freedesktop/UPower/devices/DisplayDevice
```
Garantierter, immer existierender Pfad. UPower fasst hier **alle** System-Energiequellen zu einem einzigen virtuellen Gerät zusammen (Laptop mit zwei Akkus → ein Prozentwert). Genau dieses Objekt rendert GNOME Shell im Panel. `Type` dieses Objekts ist dynamisch: `2 (Battery)`, `3 (Ups)` oder `0 (Unknown)` wenn nichts da ist.

**Wer benutzt was:**
| Desktop | Backend |
|---|---|
| GNOME Shell | UPower `DisplayDevice` via `gnome-settings-daemon` |
| KDE Plasma 6 | PowerDevil → Solid `Solid::Battery` → UPower-Backend |
| Cinnamon | UPower direkt (csd-power) |
| XFCE | `xfce4-power-manager-plugin` → UPower |
| Waybar | **direkt sysfs** + inotify + udev (kein UPower) |

---

### 1.2 Netzwerk

```
Bus:    System Bus
Name:   org.freedesktop.NetworkManager
Pfad:   /org/freedesktop/NetworkManager
Iface:  org.freedesktop.NetworkManager
  State (u):   NM_STATE_UNKNOWN=0, ASLEEP=10, DISCONNECTED=20,
               DISCONNECTING=30, CONNECTING=40,
               CONNECTED_LOCAL=50, CONNECTED_SITE=60,
               CONNECTED_GLOBAL=70    ← "echtes" Internet
  Connectivity (u): UNKNOWN=0 NONE=1 PORTAL=2 LIMITED=3 FULL=4
  PrimaryConnection (o) ← DIE Verbindung mit der Default-Route
                          Das ist die Quelle für das Panel-Icon.
  PrimaryConnectionType (s) → "802-11-wireless"|"802-3-ethernet"|"vpn"|"wwan"
  ActiveConnections (ao), Devices (ao)
  Signale: StateChanged(u), PropertiesChanged

Pfad:   /org/freedesktop/NetworkManager/Devices/N
Iface:  org.freedesktop.NetworkManager.Device
  DeviceType (u): 1=Ethernet 2=Wifi 5=Bluetooth 8=Modem 13=Bridge
                  14=TUN 16=Veth 29=Wireguard ...
  State (u): 100 = ACTIVATED
  Managed, Interface, Ip4Config

Iface:  org.freedesktop.NetworkManager.Device.Wireless
  ActiveAccessPoint (o), AccessPoints (ao)
Pfad:   /org/freedesktop/NetworkManager/AccessPoint/N
Iface:  org.freedesktop.NetworkManager.AccessPoint
  Strength (y)  0..100   ← Balken-Anzahl
  Ssid (ay), Flags, WpaFlags, RsnFlags  ← Schloss-Symbol
  Frequency (u)
```

Icon-Ableitung im Panel: `PrimaryConnectionType` → Symbolfamilie, dann bei WLAN `Strength` in 4–5 Stufen quantisieren (typisch: 0–20 / 21–40 / 41–60 / 61–80 / 81–100).

Fallback ohne NetworkManager (Waybar `network`-Modul, i3status): `AF_NETLINK`/`RTNETLINK` (`RTM_NEWLINK`, `RTM_NEWADDR`), `/sys/class/net/<if>/operstate` (`up`/`down`), `/proc/net/wireless` bzw. `nl80211` für Signalstärke.

---

### 1.3 Lautstärke

**PulseAudio-Protokoll (auch PipeWire spricht es via `pipewire-pulse`):**
```
Socket: /run/user/<uid>/pulse/native
API:    libpulse / pa_context
  pa_context_get_sink_info_by_name("@DEFAULT_SINK@", ...)
  → pa_cvolume  (PA_VOLUME_NORM = 65536 = 100%; darüber = Overamplification)
  → int mute
  Subscribe: PA_SUBSCRIPTION_MASK_SINK | SOURCE | SERVER
```
GNOME/KDE/Cinnamon/XFCE nutzen alle **libgvc** bzw. `KMix`/`plasma-pa` → also den PulseAudio-Client-Layer, nicht ALSA direkt.

**PipeWire nativ:**
```
Socket: /run/user/<uid>/pipewire-0
API:    libpipewire, Registry-Objekte
  Node   (media.class = "Audio/Sink")
  Props: SPA_PROP_channelVolumes (float[], kubisch skaliert!), SPA_PROP_mute
  Metadata-Objekt "default" → default.audio.sink
```
Achtung: PipeWire-Volumes sind **kubisch** (`linear = cubic³`), PulseAudio-Werte sind es nicht — ein häufiger Anzeige-Bug.

**Roh-Ebene:** ALSA `/dev/snd/controlC0` via `ioctl(SNDRV_CTL_IOCTL_ELEM_READ)`, Element „Master Playback Volume". Nur das würde ein eigener Kernel selbst bereitstellen müssen.

**Tasten:** Multimedia-Keys kommen als evdev-Events aus `/dev/input/event*`: `KEY_VOLUMEUP (115)`, `KEY_VOLUMEDOWN (114)`, `KEY_MUTE (113)`, `KEY_BRIGHTNESSUP (225)`, `KEY_BRIGHTNESSDOWN (224)`.

---

### 1.4 Helligkeit

```
/sys/class/backlight/<name>/
    brightness         rw   0..max_brightness   ← Schreiben braucht Rechte
    actual_brightness  ro   was die HW wirklich macht (lesen für Anzeige!)
    max_brightness     ro
    bl_power           rw   0 = an, 4 = FB_BLANK_POWERDOWN
    type               ro   "firmware" | "platform" | "raw"
    scale              ro   "unknown" | "linear" | "non-linear"
```
Namen: `intel_backlight`, `amdgpu_bl0`, `acpi_video0`, `nvidia_wmi_ec_backlight`, `apple-panel-bl`.

**Priorisierungsregel bei mehreren Devices** (so macht es gnome-settings-daemon / systemd-backlight):
`type == "firmware"` > `"platform"` > `"raw"`. Ein Laptop hat oft gleichzeitig `acpi_video0` (firmware) und `intel_backlight` (raw) — nur eines darf bedient werden.

**`scale`-Semantik** (verifiziert in Kernel-ABI): `linear` → UI muss **logarithmisch** mappen; `non-linear` → UI mappt **linear**. Das ist kontraintuitiv und wird häufig falsch implementiert.

**Tastatur-Backlight:** `/sys/class/leds/<name>::kbd_backlight/{brightness,max_brightness}`.

**Zugriffsweg der Desktops** (sysfs ist root-only!):
- GNOME: `org.gnome.SettingsDaemon.Power` / `/org/gnome/SettingsDaemon/Power`, Iface `org.gnome.SettingsDaemon.Power.Screen`, Property `Brightness (i)` **[unverifiziert]**
- KDE: PowerDevil D-Bus `org.kde.Solid.PowerManagement`, intern via `logind`
- Universell: `org.freedesktop.login1.Session.SetBrightness(s subsystem, s name, u value)` — polkit-geschützt
- Externe Monitore: **DDC/CI** über I²C (`/dev/i2c-N`, Slave 0x37, VCP-Code `0x10`) via `libddcutil`. KDE Plasma 6 nutzt das produktiv.

---

## 2. Die Akku-Erkennungslogik (Kernfrage)

### Regel A — GNOME Shell (`js/ui/status/power.js`) **[unverifiziert, aus Doku rekonstruiert]**

Proxy auf `/org/freedesktop/UPower/devices/DisplayDevice`, dann sinngemäß:

```js
_sync() {
    // Do we have batteries or a UPS?
    this._indicator.visible = this._proxy.IsPresent;
    if (!this._proxy.IsPresent)
        return;
    this._percentageLabel.text = '%d\u2009%%'.format(this._proxy.Percentage);
    this._indicator.icon_name = this._proxy.IconName;   // UPower liefert Icon
}
```

Das Entscheidende: **eine einzige boolesche Property `IsPresent` auf dem aggregierten `DisplayDevice`**. UPower hat die ganze Komplexität (mehrere Akkus, Typ-Filterung, `PowerSupply`-Prüfung) bereits erledigt. Desktop-Rechner → `IsPresent = false` → Icon weg.

### Regel B — Waybar (`src/modules/battery.cpp`) — **verifiziert**

```cpp
for (auto& node : fs::directory_iterator("/sys/class/power_supply")) {
    if (!fs::is_directory(node))                        continue;
    // muss Kapazität liefern können
    bool has_cap = fs::exists(node/"capacity") || fs::exists(node/"charge_now");
    bool has_st  = fs::exists(node/"uevent") &&
                   (fs::exists(node/"status") || compat_mode);
    if (!(has_cap && has_st))                           continue;

    std::string type = read(node/"type");
    if (type != "Battery")                              continue;   // ← Mains/USB raus

    // "Ignore non-system power supplies unless explicitly requested"
    if (!explicitly_configured && read(node/"scope") == "Device")
        continue;                                                   // ← Funkmaus raus

    batteries_.push_back(node);
    inotify_add_watch(fd, (node/"uevent").c_str(), IN_ACCESS);
}
if (batteries_.empty()) { spdlog::warn("No batteries."); /* Modul bleibt versteckt */ }
```
Zusätzlich: `udev_monitor` mit Subsystem-Filter `"power_supply"` für Hotplug. Kein Akku → kein Exception, Modul rendert einfach nichts.

### Regel C — Das Anti-Pattern

`ls /sys/class/power_supply` auf Leerheit prüfen ist **falsch**. Ein Desktop-PC ohne Akku hat dort trotzdem oft Einträge:
- `AC` / `ADP1` mit `type=Mains`
- USV via `usbhid` mit `type=UPS`
- Bluetooth-Maus/Headset mit `type=Battery`, aber `scope=Device` ← der klassische Fehlalarm
- Bei `hid_apple`, Logitech Unifying etc. genauso

### Empfohlene Regel für einen eigenen Kernel

Zeige das Akku-Symbol **genau dann**, wenn mindestens ein Gerät alle folgenden Bedingungen erfüllt:

1. `type ∈ {"Battery", "UPS"}`
2. `scope ∉ {"Device"}` (fehlendes `scope` ⇒ als `"System"` werten)
3. `present == 1` (fehlend ⇒ als `1` werten)
4. Kapazität ableitbar: `capacity` **oder** (`energy_now` ∧ `energy_full`) **oder** (`charge_now` ∧ `charge_full`)

Das entspricht exakt UPowers `IsPresent && PowerSupply && Type∈{Battery,Ups}`.

Ergänzend: bei mehreren gültigen Akkus **aggregieren** (Summe der `energy_now` / Summe der `energy_full`), nicht den ersten nehmen. Zustand: `Charging` gewinnt über `Discharging` gewinnt über `Full`.

---

## 3. Fensterliste

### X11 / EWMH
```
Root-Window Properties:
  _NET_CLIENT_LIST           WINDOW[]  ← Mapping-Reihenfolge (Taskleiste)
  _NET_CLIENT_LIST_STACKING  WINDOW[]  ← Stapelreihenfolge (Pager/Alt-Tab)
  _NET_ACTIVE_WINDOW         WINDOW
  _NET_CURRENT_DESKTOP       CARDINAL
  _NET_NUMBER_OF_DESKTOPS    CARDINAL
  _NET_DESKTOP_NAMES         UTF8_STRING[]

Pro Fenster:
  _NET_WM_NAME               UTF8_STRING  (Fallback: WM_NAME)
  _NET_WM_ICON               CARDINAL[]   (ARGB, w,h,pixels… mehrere Größen)
  _NET_WM_ICON_NAME, _NET_WM_DESKTOP (0xFFFFFFFF = alle)
  _NET_WM_WINDOW_TYPE        _NET_WM_WINDOW_TYPE_NORMAL|DOCK|DIALOG|UTILITY|
                             SPLASH|TOOLBAR|MENU|DESKTOP
  _NET_WM_STATE              _NET_WM_STATE_SKIP_TASKBAR   ← ausblenden!
                             _NET_WM_STATE_SKIP_PAGER
                             _NET_WM_STATE_HIDDEN (= minimiert)
                             _NET_WM_STATE_MAXIMIZED_{VERT,HORZ}, FULLSCREEN,
                             DEMANDS_ATTENTION, ABOVE, BELOW, MODAL
  _NET_WM_PID                CARDINAL
  WM_CLASS                   STRING[2] (instance, class) → .desktop-Matching
  WM_TRANSIENT_FOR           WINDOW    ← Dialoge unterdrücken

Aktionen (ClientMessage an Root, mask SubstructureNotify|Redirect):
  _NET_ACTIVE_WINDOW, _NET_CLOSE_WINDOW, _NET_WM_STATE,
  _NET_MOVERESIZE_WINDOW, _NET_WM_DESKTOP
Updates: XSelectInput(root, PropertyChangeMask) → PropertyNotify
```
Taskleisten-Filter in der Praxis: Typ `NORMAL` (oder kein Typ), kein `SKIP_TASKBAR`, kein `WM_TRANSIENT_FOR`, `override_redirect == False`.

### Wayland — `zwlr_foreign_toplevel_management_unstable_v1` (verifiziert)

```
zwlr_foreign_toplevel_manager_v1
  event  toplevel(new_id zwlr_foreign_toplevel_handle_v1)
  event  finished
  request stop

zwlr_foreign_toplevel_handle_v1
  events:  title(string)
           app_id(string)              ← Match auf .desktop-Datei
           output_enter(output) / output_leave(output)
           state(array<uint>)          ← maximized=0 minimized=1
                                          activated=2 fullscreen=3
           done                        ← atomarer Commit aller Änderungen
           closed
           parent(handle|null)         [v3]
  requests: set_maximized / unset_maximized
            set_minimized / unset_minimized
            set_fullscreen / unset_fullscreen
            activate(seat)
            close
            set_rectangle(surface,x,y,w,h)  ← Minimier-Animationsziel
            destroy
```
Nutzer: Waybar, sway/wlroots-Compositors, KDE (zusätzlich `kde-plasma-window-management`). **GNOME/Mutter implementiert dieses Protokoll bewusst nicht** — GNOME Shell ist selbst der Compositor und liest `Meta.Display.get_tab_list()` intern.

Neuere Alternative: `ext-foreign-toplevel-list-v1` (staging, nur Auflistung, keine Kontrolle) — von Mutter perspektivisch eher akzeptiert.

**Kein Icon im Protokoll!** Es gibt nur `app_id`. Panels müssen selbst über `$XDG_DATA_DIRS/applications/<app_id>.desktop` → `Icon=` → Icon-Theme-Lookup auflösen (heuristisches Fuzzy-Matching, häufige Fehlerquelle).

---

## 4. GNOME Quick Settings (seit 43) als Panel-Referenz

**Architektur** (verifiziert über gjs.guide):

```
Main.panel.statusArea.quickSettings          (QuickSettingsMenu)
  ├─ Indicator-Leiste oben rechts  (die kleinen Icons)
  └─ Popup-Grid, 2 Spalten
       ├─ QuickToggle        Pille: iconName + title + subtitle, toggleMode
       ├─ QuickMenuToggle    wie oben + rechter Pfeil → eigenes PopupMenu
       ├─ QuickSlider        Slider mit Icon (Helligkeit, Lautstärke) — colSpan 2
       └─ QuickSettingsItem  Basisklasse (z.B. Systemaktions-Buttons)

SystemIndicator  = Klammer-Objekt:
    .quickSettingsItems : []   Widgets fürs Grid
    ._indicator                Icon in der Panelleiste (kann entfallen)
Registrierung: Main.panel.statusArea.quickSettings
                   .addExternalIndicator(indicator, colSpan = 1)
```

**Die architektonische Kernidee, die übertragbar ist:**
Ein `SystemIndicator` bündelt **beides** — die kompakte Panel-Repräsentation *und* die aufgeklappte Bedien-Repräsentation — in einer Klasse mit **einem gemeinsamen `_sync()`**. Sichtbarkeit im Panel und Sichtbarkeit im Popup werden aus derselben Datenquelle abgeleitet. Genau deshalb kann GNOME das Akku-Icon mit einer Zeile (`visible = IsPresent`) an- und abschalten, ohne dass Panel und Panel-Inhalt auseinanderlaufen.

Aktuelle Standard-Kacheln: Netzwerk (MenuToggle), Bluetooth, Power Mode, Night Light, Dark Style, Airplane Mode, Rotation Lock, Screen Sharing/Recording, Helligkeits-Slider, Lautstärke-Slider (+ Mikrofon-Slider nur wenn aktiv), Nutzer/Ausschalten/Einstellungen/Sperren.

---

## 5. Konsolidierte Liste für einen eigenen Kernel

| # | Was | Kernel muss liefern | Erkennungsregel fürs Panel |
|---|---|---|---|
| 1 | Akku | Enumeration Energiequellen: `type`, `scope`, `present`, `status`, `energy_now/full` oder `charge_now/full`, `capacity` | Icon nur wenn `type∈{Battery,UPS} ∧ scope≠Device ∧ present=1 ∧ Kapazität ableitbar`; mehrere aggregieren |
| 2 | Netzteil | `type∈{Mains,USB}` + `online` 0/1 | Blitz-Overlay wenn `online=1 ∧ status=Charging` |
| 3 | Akku-Events | Push-Benachrichtigung bei Wertänderung (Analogon zu `uevent`+inotify+udev) | Kein Polling erzwingen |
| 4 | Netz | Interface-Liste, `operstate`, Typ (eth/wifi/wwan), Default-Route-Owner, WLAN-SSID + Signal 0..100, Security-Flags | Icon aus Typ des Default-Route-Interfaces; Balken aus Signal; Schloss aus Security |
| 5 | Konnektivität | Portal-/Captive-Erkennung (Analogon `NM_CONNECTIVITY_PORTAL`) | Warn-Overlay statt „verbunden" |
| 6 | Audio | Default-Sink/Source, Volume (Skala explizit dokumentieren!), Mute, Subscribe auf Änderung | Mikrofon-Indikator nur wenn ein Stream aktiv aufnimmt |
| 7 | Helligkeit | Backlight-Devices mit `brightness`/`actual_brightness`/`max_brightness`/`type`/`scale` | Slider nur wenn ≥1 Device; Priorität `firmware>platform>raw`; `scale`-Semantik beachten |
| 8 | Externe Monitore | I²C-Zugriff für DDC/CI (VCP `0x10`) | Optionaler zweiter Slider |
| 9 | Rechte-Broker | Privilegierter Dienst für `brightness`-Schreibzugriff (Analogon logind/polkit) | Unprivilegierte Panels dürfen nicht direkt in sysfs schreiben |
| 10 | Fensterliste | ID, Titel, App-ID, Zustände (min/max/fullscreen/aktiv), Output, Parent, Icon-Handle, atomares `done` | Filter: normale Toplevels, kein SkipTaskbar, kein Transient-For |
| 11 | Fenster-Aktionen | activate/close/minimize/maximize/fullscreen + `set_rectangle` | — |
| 12 | Icon-Auflösung | App-ID → Icon-Pfad **im System**, nicht im Panel | Vermeidet das Wayland-`app_id`-Fuzzy-Matching-Problem — echter Vorteil eines Eigenbaus |
| 13 | Eingabe | evdev-Keycodes 113/114/115 (Audio), 224/225 (Helligkeit) | Direkt an die jeweiligen Regler routen |
| 14 | Zeit/Datum | Monotonic + Realtime + Zeitzone + NTP-Sync-Status | — |
| 15 | Sensoren | Lid-State, Tablet-Mode, Rotation, Umgebungslicht (`/sys/bus/iio/`) | Rotation-Lock-Kachel nur wenn Accelerometer existiert |

**Die drei übertragbaren Meta-Prinzipien:**

1. **Aggregations-Layer wie `DisplayDevice`.** Nicht jedes Panel soll Akkus zusammenrechnen. Der Kernel/Systemdienst liefert *einen* vorverdichteten Zustand plus *ein* `IsPresent`-Flag. Das ist der Grund, warum GNOMEs Logik trivial ist und Waybars Logik 40 Zeilen Filterei braucht.

2. **Sichtbarkeit ist eine Eigenschaft der Datenquelle, nicht der UI.** Kein Hardware-Sonderfall gehört ins Panel-Rendering. `visible = quelle.vorhanden` — mehr nicht.

3. **Push statt Poll, mit atomarem Commit.** Sowohl `uevent`/udev als auch das `done`-Event von wlr-foreign-toplevel lösen dasselbe Problem: Konsumenten dürfen nie Zwischenzustände sehen. Ein eigener Kernel sollte das von Anfang an als Grundvertrag jeder Statusquelle festlegen.

---

**Sources:**
- [org.freedesktop.UPower.Device Reference](https://upower.freedesktop.org/docs/Device.html)
- [org.freedesktop.UPower Reference](https://upower.freedesktop.org/docs/UPower.html)
- [Kernel ABI: sysfs-class-power](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-class-power)
- [Linux power supply class](https://docs.kernel.org/power/power_supply_class.html)
- [Kernel ABI: sysfs-class-backlight](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-class-backlight)
- [wlr-foreign-toplevel-management-unstable-v1.xml](https://github.com/swaywm/wlr-protocols/blob/master/unstable/wlr-foreign-toplevel-management-unstable-v1.xml)
- [Waybar src/modules/battery.cpp](https://github.com/Alexays/Waybar/blob/master/src/modules/battery.cpp)
- [waybar-battery(5)](https://man.archlinux.org/man/extra/waybar/waybar-battery.5.en)
- [GJS Guide: Quick Settings](https://gjs.guide/extensions/topics/quick-settings.html)
- [gnome-shell js/ui/status](https://gitlab.gnome.org/GNOME/gnome-shell/-/tree/main/js/ui/status)
- [NetworkManager D-Bus API Types](https://networkmanager.dev/docs/api/1.32.10/nm-dbus-types.html)
- [org.freedesktop.NetworkManager](https://networkmanager.dev/docs/api/latest/gdbus-org.freedesktop.NetworkManager.html)
- [org.freedesktop.NetworkManager.Device](https://www.networkmanager.dev/docs/api/latest/gdbus-org.freedesktop.NetworkManager.Device.html)
- [PowerDevil in Plasma 6.0 and beyond](https://blogs.kde.org/2024/04/23/powerdevil-in-plasma-6.0-and-beyond/)
- [KDE/powerdevil README](https://github.com/KDE/powerdevil/blob/master/README.md)