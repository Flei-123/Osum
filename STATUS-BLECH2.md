# RUNDE BLECH2 — was Justins Foto gezeigt hat, und was davon ein Fehler war

Grundlage: Justins Bildschirmfoto vom 05.09.2026, 22:46. Ryzen, Huawei
3440x1440, UEFI, Limine 9.6.7, USB-Tastatur und USB-Maus, Kern
`osum cdf8b69+`, Ring 3 nur Kern 0. Schreibtisch, DHCP und Uhr liefen —
und auf der Messtafel standen drei Zahlen, die der Prüfstand nie gesehen
hatte.

Arbeitsbaum `/root/osum-blech2`, Zweig `blech2` von `merge6` (2aa3f59),
Commit **1730828**. Nicht gepusht, nicht gemergt, nichts nach `/srv/store`.

Kurzfassung: **zwei der drei Zahlen waren echte Fehler, eine war ein
falsches Messgerät.** Abnahme `tools/metal2/run.sh`: **33 bestanden, 0
gescheitert.**

---

## 1. `RING 5226 VERL 1283` — echt, zwei getrennte Ursachen

25 % der Ereignisse fielen aus dem Fensterring. Unter QEMU stand dort
immer 0, und genau das war der Hinweis.

**Ursache A — ein Fenster ohne Abholer.** Das Terminalfenster des Kerns
(`K_TERM` mit gesetztem `W_TTY`) bekommt seine Tasten über den tty-Weg;
einen `ev_pop` auf seinem Ring gibt es nicht — der einzige sitzt in
`sysgui` hinter `WM_EVENT`, und den ruft nur ein Ring-3-Programm. Jede
Mausbewegung über dem Terminal wurde trotzdem eingereiht. Nach 32
Ereignissen war der Ring voll, und von da an zählte **jede weitere
Bewegung einen Verlust**. Justin hat die Maus über sein Terminal bewegt,
der Prüfstand nie — daher 1283 gegen 0.

Behoben in `wm.ev_push`: Ereignisse an ein Fenster, das seine Eingabe
über tty bekommt, werden **gezählt** (`S_EVTERM`) statt eingereiht. Der
Ring läuft nicht mehr voll, weil niemand ihn füllt, der ihn nie leert.

**Ursache B — Koaleszenz fehlte.** Eine echte Maus meldet 125–1000 mal je
Sekunde, die Anzeige läuft mit 99 Hz. Alles zwischen zwei Anstrichen ist
Zwischenposition, die kein Programm je sieht. Jetzt überschreibt eine
neue Bewegung das **jüngste noch nicht abgeholte** `E_MOVE` desselben
Rings (`S_EVKOAL`), statt hinten anzustehen. **Klicks und Tasten
koaleszieren nie** — sie werden immer eingereiht.

**Ursache C — ein Klick konnte zwischen Zeiger und Ring verloren gehen.**
`usb.poll` holte alle Berichte einer Runde, `wm.poll` sah danach nur den
Endzustand; ein Klick, der in derselben Runde kam **und** ging, war weg.
Für PS/2 war das längst gelöst, für USB nicht: `hidin.maus_melden` ruft
`gfx.mouse_now` jetzt **je Bericht**.

Gemessen (QEMU KVM, 3440x1440, `fbpad=16`, xHCI mit USB-Maus):

| Lauf | Strom | Pakete | Klicks | RING | **VERL** | KOAL |
|---|---|---|---|---|---|---|
| A | QMP 814 Hz, 60 s | 7571 | 9 gesendet → 9 an, 9 im Ring | 1486 | **0** | 2507 |
| B | Kernstrom 1000 Hz | 51359 | 206 → K 206 == D 206 | 1540 | **0** | 33082 |
| C | Kernstrom 4000 Hz | 206059 | 824 → K 824 == D 824 | 2884 | **0** | 134740 |

C schiebt 40 Pakete je Schleifenrunde durch einen Ring mit 32 Plätzen —
ohne Koaleszenz fiele dort alles um. Kein Klick ging verloren
(`K == D == gesendet`), keine Taste (`TAS 20 == 20`).

## 2. `LEISTE … TK 643` — ein falsches Messgerät, kein beschnittener Titel

Die Vermutung aus BLECH-EINGABE §4 (Schnittfenster in `wm.fb_glyph` bei
`pitch > breite*4`) hat sich **nicht bestätigt**.

`title_text` zählte hoch, wenn `x < ax0` — wenn das Schnittfenster rechts
vom Titelanfang beginnt. Das ist aber der Normalfall bei **jedem
Teilanstrich**: sobald der Zeiger über der Fensterfläche steht, wird nur
dieser Ausschnitt neu gemalt, und der Titel liegt links davon. Gezählt
wurde also nicht „beschnitten", sondern „teilweise neu gemalt" — bei
Justins Mausbewegung 643 mal.

Der Titel war **nie** beschnitten. Der Beweis ist das Bild, nicht der
Zähler: `checkshot.py tkette` rechnet die Titelzeile bildpunktgenau gegen
den Zeichensatz nach — **„Terminal -- sh", 12 Zeichen, 1477 Tintenpunkte
geprüft, 0 falsch**, bei 3440x1440 mit `fbpad=16` (gemeldete Breite 3424,
Zeilenbreite 13760 — der Fall echter Firmware).

`TK` zählt jetzt, was der Name sagt: Titel, die **im Tafelband**
(`fb.band_lo`) wirklich abgeschnitten sind → **TK 0** in allen drei
Läufen. Die alte Zahl steht als `tka=` in `wm: fen` weiter zur Verfügung
(A: `tka=925`) — sie ist eine Anstrichstatistik, keine Fehlermeldung.

## 3. `ISR … VERL 4 SPAET 1` — der Zeitgeberweg, harmlos

Das sind Marken, die der Zyklenzähler nachtragen musste, und Schläge, die
in einen laufenden Anstrich fielen — **nicht** die Eingabe. Unter KVM
kommt das vom Wirt: steht der vCPU, trägt der Kern LAPIC-Marken nicht
nach. Gemessen A/B/C: `VERL 13 / 5 / 6`, `LM` (Sekunde der letzten
nachgetragenen Marke) 64–67 bei 60 s Last.

Entscheidend: **die Uhr bleibt richtig** — Zeile 19 zeigt `RTC == KRN`.
Auf Justins Blech waren es 4 Marken in einer ganzen Sitzung. Kein
Handlungsbedarf; die Zeile ist jetzt kürzer und trägt `LM`, damit man
sieht, *wann* zuletzt nachgetragen wurde.

## 4. Das Terminal war mit `taskbar:`-Messzeilen zugerollt

Die Schreibtischprogramme erbten `fd1`/`fd2` der Konsole und schrieben
ihre Messzeilen in die Shell des Nutzers. Jetzt bekommen sie beim Start
ein **Protokoll-tty** (`tty.alloc_log`, `SINK_SERIAL`); `file.inherit_std`
tauscht es beim Vererben gegen die Konsole, damit eine `sh` aus dem
Startmenü weiter ins Fenster schreibt.

Ergebnis: Das Terminal startet leer mit Prompt und zeigt nur noch kurze
`sh:`-Zeilen — nachgemessen im Bild (rechts von Spalte 22 blieben 10
Tintenpunkte, das ist der Mauszeiger). Die 896 `taskbar:`-Zeilen stehen
unverändert auf der seriellen Leitung, wo sie hingehören.

## 5. Der abgeschnittene Limine-Eintrag

`OrientOS -- Schreibtisch (Zwischenspeicher nach jedem Bild lee` hörte
mitten im Wort auf. Alle Einträge sind gekürzt, und `tools/usbimg/build.sh`
**prüft es beim Bauen** — nach dem Einsetzen des Produktnamens aus
`marke.conf`, denn ein längerer Name nimmt dem Rest den Platz. Bricht der
Bau ab, wenn ein Eintrag über 60 Zeichen geht. Aktuell: 17 Einträge,
längster **58** Zeichen.

---

## Eine Beobachtung, die kein Fehler ist

Die Knöpfe der Fensterleiste tragen **keine Beschriftung** — im Bild nur
Symbole, auf der Leitung `taskbar: btn … t=` mit leerem Text. Das sieht
nach abgeschnittenem Titel aus und ist keiner: `cf_labels` steht auf
`LB_NEVER` (Voreinstellung), und bei 60 Pixel Knopfbreite liegt man
ohnehin unter `TASK_MIN` (48 + Symbol). Der Code setzt die Beschriftung
dann **absichtlich leer, statt „Termina" abzuschneiden**, und meldet den
leeren Text ehrlich. Gegengeprüft am unveränderten Kern (Lauf `e1`):
dort steht dieselbe Zeile. Nichts an dieser Runde hat das verursacht.

## Was gemessen wurde, und womit

`tools/metal2/run.sh` stellt die Bedingungen des Fotos her — 3440x1440
mit `fbpad=16`, xHCI mit USB-Tastatur und -Maus — und prüft 33 Zusagen.
`tools/metal2/maus.py` schickt den Bewegungsstrom über QMP
(`input-send-event`), das Bootwort `mausflut=<hz>` erzeugt ihn im Kern.

Eine **Korrektur am Messgerät selbst** gehört in diesen Bericht: die
Prüfung „keine Messzeilen im Terminal" zählte anfangs 73920 Tintenpunkte,
wo im Bild gar kein Text stand. Das Terminal malt seine Zeilen
abwechselnd auf zwei Untergründe; „ungleich *einer* Hintergrundfarbe"
zählt jede zweite Zeile vollständig mit. Die Messung prüft jetzt gegen
**beide** Streifenfarben. Erst das Bild hat den Fehler gezeigt — der
Zähler allein hätte eine saubere Anzeige als Fehler gemeldet.

    bash tools/metal2/run.sh --aus /tmp/abn
    → BLECH2: 33 bestanden, 0 gescheitert

## Das Abbild für den Stick

    /root/blech2-usb/orientos-usb-2026-09-05-1730828.img          (118 MiB)
    /root/blech2-usb/orientos-usb-2026-09-05-1730828.img.sha256

    sha256 45bba1d8e9d56e63fb3fdf321cfc5bae12746c106d8088dde722b00c2082433b

    sudo dd if=orientos-usb-2026-09-05-1730828.img of=/dev/sdX bs=4M conv=fsync status=progress

### Was Justin auf der Tafel fotografieren soll

Booten, **die Maus 30 Sekunden lang über das Terminalfenster bewegen**
(genau das hat den Fehler ausgelöst) und ein paar mal klicken. Dann:

* **Zeile 4** — `RING … VERL 0 KOAL …`. `VERL` muss **0** sein und wird
  grün gezeigt; `KOAL` darf beliebig groß werden, das sind die
  zusammengefassten Bewegungen. Steht dort wieder eine Zahl > 0, ist die
  Zeile rot.
* **Zeile 7** — `LEISTE … TK 0`. Ab dem ersten beschnittenen Titel rot.
* **Zeile 2** — `K` und `D` müssen **gleich** sein (Klicks beim Zeiger
  gegen Klicks im Ring). Das ist der Klickverlust-Test auf echtem Blech.
* **Das Terminal** — startet leer mit Prompt, keine `taskbar:`-Zeilen.
* **Das Limine-Menü** — kein Eintrag hört mitten im Wort auf.

Zeile 16 (`ISR … VERL`) darf kleine Zahlen zeigen; solange Zeile 19
`RTC` und `KRN` gleich stehen, ist die Uhr richtig.
