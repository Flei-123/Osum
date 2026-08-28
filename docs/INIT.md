# `init`, `svc`, `shutdown`, `reboot` — die Bedienungsanleitung

Das ist die Kurzfassung für jemanden, der einen Osum-Server einrichtet.
Warum es so gebaut ist und was dabei gemessen wurde, steht in
`docs/ROUNDINIT.md`.

---

## Die drei Dateien

| Datei | Muss sie da sein? | Inhalt |
|---|---|---|
| `/etc/inittab` | **ja** — ohne sie sagt `init` „`/etc/inittab` fehlt" und gibt 1 zurück | eine Zeile je Dienst |
| `/etc/ziel` | nein — fehlt sie, gilt `konsole` | **ein** Wort: `konsole` oder `grafik` |
| `/etc/fstab` | nein | `quelle ziel art [ro]`, eine Zeile je Einhängung |

Dazu zwei, die `init` selbst schreibt:

| Datei | Wer schreibt | Inhalt |
|---|---|---|
| `/run/svc.state` | `init` | `name zustand pid starts fehler seit ziele` |
| `/run/svc.cmd` | `svc`, `shutdown`, `reboot` | ein Auftrag, den `init` liest und löscht |

---

## `/etc/inittab`

Zwei Schreibweisen, beide gültig:

    name:art:befehl                       kurz (Runde K13)
    name:ziele:art:befehl:optionen        lang (Runde INIT)

Welche es ist, entscheidet das **zweite Feld**: steht dort `once`,
`respawn`, `ctrl` oder `off`, ist es die kurze Form. Eine Zeile in der
kurzen Form gilt für **jedes** Ziel.

**art**

| | |
|---|---|
| `once` | einmal starten, danach `done` |
| `respawn` | nach jedem Ende wieder starten |
| `ctrl` | wie `once`, aber sein Ende **fährt das System herunter** |
| `off` | steht da, läuft nicht |

**ziele** — `konsole`, `grafik`, beides mit Komma, oder `*` für alle.
Ein Wort, das niemand versteht, heißt **nirgends** und nicht „überall".

**optionen** — durch Komma getrennt:

| | |
|---|---|
| `netz` | erst starten, wenn der Stapel läuft **und** eine Adresse hat. Vorher steht der Dienst auf `waiting` |
| `log=/pfad` | Ausgabe und Fehler des Dienstes gehen **anhängend** in diese Datei statt auf die Konsole |

Kommentare beginnen mit `#`. Höchstens **16** Dienste; die 17. Zeile wird
ignoriert. Ein Befehl darf höchstens **vier** Wörter haben.

### Beispiel: ein Server ohne Bildschirm

```
# /etc/ziel enthaelt: konsole
# name:ziele:art:befehl:optionen
login:konsole:respawn:/bin/login
dhcp:*:once:/bin/dhcp
netview:*:once:/bin/netview boot
sshd:*:respawn:/bin/sshd:netz,log=/var/log/sshd.log
web:*:respawn:/bin/httpd 80:netz,log=/var/log/web.log
leiste:grafik:respawn:/bin/leiste
```

Auf diesem Rechner startet `leiste` **nicht** — `/etc/ziel` sagt
`konsole`. Es genügt, dieses eine Wort zu ändern, um dieselbe Platte mit
Oberfläche zu starten.

---

## Die zwei Grenzen, die einen Server am Leben halten

**Der Rückfall-Zähler.** Ein Dienst mit `respawn`, der **fünfmal
hintereinander** mit einem Code ≠ 0 endet, **ohne dabei je zwei Sekunden
zu leben**, wird abgeschaltet: Zustand `failed`, keine weiteren Versuche.
`svc start NAME` hebt das auf und setzt den Zähler auf null.

Wer mit **0** endet, bekommt **nie** einen Strich — er hat getan, wozu er
da war. Wer **länger als zwei Sekunden** gelaufen ist, auch nicht — er
hat bewiesen, dass er laufen kann.

**Die Startbremse.** Sie fragt nicht nach dem Grund: mehr als **zehn
Starts binnen fünf Sekunden**, und der nächste wartet **fünf Sekunden**
statt 200 ms. Das fängt den Fall ab, den der Rückfall-Zähler nicht sieht
— einen Dienst, der sofort und *erfolgreich* endet und sich damit selbst
in einer Schleife startet.

---

## `svc`

```
svc                 die Tafel: wer läuft, seit wann, wie oft neu gestartet
svc list            dasselbe
svc status          eine Zeile je Dienst, roh (für Skripte)
svc start NAME      startet — und hebt eine Abschaltung auf
svc stop NAME
svc restart NAME
svc ziel            welches Ziel gerade gilt
svc shutdown        herunterfahren
svc reboot          neu starten
```

Die Tafel sieht so aus:

```
DIENST           ZUSTAND   PID  STARTS  FEHLER  LAUFZEIT  ZIEL
blink            running    23     4       0    0.6s   konsole,grafik
kaputt           failed      0     5       5    -      konsole,grafik
fenster          stopped     0     0       0    -      grafik
3 / 9 Dienste laufen
```

**Zustände:** `running` · `stopped` (soll laufen, läuft gerade nicht) ·
`done` (`once` fertig, oder von Hand gestoppt) · `waiting` (wartet auf
das Netz) · `failed` (abgeschaltet, siehe oben).

`svc` darf nur `root` — nicht weil das Programm es entscheidet, sondern
weil `/run/svc.cmd` root gehört und 0o600 trägt.

---

## Herunterfahren und Neustart

```
shutdown        herunterfahren und ausschalten
shutdown -r     herunterfahren und neu starten
reboot          dasselbe wie shutdown -r
shutdown -f     ohne init: nur sync und Aufruf (Notweg)
reboot -f       dito
```

Beide gehen über `init`, und der macht der Reihe nach: `SIGTERM` an jeden
Dienst → zwei Sekunden warten → `SIGKILL` an die Reste → `sync` → die
Einhängungen aus `/etc/fstab` aushängen → `sync` → ACPI aus bzw. RESET.

Antwortet `init` binnen drei Sekunden nicht (weil keiner läuft — der
Notweg `initsh` auf der Kernel-Kommandozeile startet die Shell
unmittelbar), machen beide Programme es selbst: `sync` und der Aufruf.
Das ist ehrlich weniger — kein Dienst bekommt ein Signal.

---

## Wenn etwas nicht geht

| Meldung | Bedeutung |
|---|---|
| `init: /etc/inittab fehlt` | die Datei ist nicht da oder leer — der Kern startet danach nichts weiter |
| `init: ich bin nicht der Prozess 1` | `/bin/init` wurde von Hand aufgerufen |
| `init: kann nicht: /bin/x` | `execve` auf den Befehl der Zeile ist gescheitert (Pfad? Rechte?) |
| `init: abgeschaltet NAME nach 5 Fehlstarts, 5 Starts` | der Rückfall-Zähler hat gegriffen |
| `svc: /run/svc.cmd nicht schreibbar` | nicht als `root` |
| `svc: init antwortet nicht` | kein `init` als Prozess 1 (`initsh`?) |
| `init: ACPI hat nicht aus` | `reboot(RB_POWEROFF)` kam zurück — die Firmware nennt kein `_S5_` |
