# RUNDE ANMELDUNG — grafischer Login und Sperrbildschirm

Zweig `anmeldung`, abgezweigt von `main` (ae381a3). **Nicht** nach `main`
gemerged.

Alle Zahlen hier sind gemessen. Wo nichts gemessen ist, steht nichts.

---

## 0. Der Befund — die Offenliste stimmte, der Auftrag nur halb

Der Auftrag sagt: *„Ein grafischer Login und ein Sperrbildschirm für
OrientOS"* und *„fang mit einer Bestandsaufnahme an — die Offenliste ist
vom 12.09. und kann veraltet sein."* Selbst gemessen, am Baum und am
fertigen Abbild:

| Zusage der Offenliste (P-002) | gemessen | Befund |
|---|---|---|
| „`login.fi` (257 Z.) und `lock.fi` (352 Z.) existieren" | `wc -l` = 257 / 371 | **stimmt** |
| „`desktop.fi` ruft keines von beiden" | `grep -c 'login\|lock'` = 0 | **stimmt** |
| „der Schreibtisch ist `root`" | `kgui.fi:3070` startet `/bin/desktop` aus der Startaufgabe (uid 0) | **stimmt** |

**Was die Offenliste NICHT gesagt hat und was diese Runde zuerst
gefunden hat** — das war die eigentliche Lücke:

    $ python3 tools/osum/mkfs.py list root.img | grep -E 'shadow|/bin/login|/bin/lock'
    (nichts)

**Es gab kein `/etc/shadow` im Abbild, und weder `login`, `lock`,
`passwd`, `su` noch `chown` lagen darin.** `/etc/passwd` war da (zwei
Zeilen, `root` und `justin`), aber ohne einen einzigen Kennworteintrag.
Die Programme waren gebaut und gemessen — sie standen nur nicht in der
Programmzeile von `tools/usbimg/build.sh`.

Damit war P-002 **kein Bau-, sondern zu drei Vierteln ein
Verdrahtungsauftrag** — und das letzte Viertel, der grafische
Anmeldeschirm selbst, fehlte ganz.

**Was schon da war und benutzt wurde, statt es neu zu bauen:**

| Sache | wo | Zustand |
|---|---|---|
| PBKDF2-HMAC-SHA256, `$osum1$`-Format, `/etc/shadow` | `kernel/user/pw.fi` (1083 Z.) | vollständig, 8192 Runden |
| uid/gid je Prozess, Vererbung über fork/exec | `kernel/sched.fi` T_UID=392 … | vollständig |
| `login`, `su`, `passwd`, `id`, `chmod`, `chown` | `kernel/user/*.fi` | gebaut, übersetzen sauber |
| Sperre im KERN: wer sperrt, wer aufsperrt, Tastensperre, Neustart des Sperrers | `sys.fi` (op 1870), `wm.fi`, `kgui.fi` | vollständig |
| Super+L | `kernel/kbd.fi:577` | **war schon da** |
| Sperrbildschirm mit fUi über wlib | `kernel/user/lock.fi` | gebaut, nie in einem Abbild |

---

## 1. Was diese Runde gebaut hat

| # | Sache | Datei |
|---|---|---|
| 1 | **Kennwortfelder verdecken ihre Eingabe** — Flag `F_GEHEIM` in der Bibliothek | `wlib.fi` |
| 2 | **Der grafische Anmeldeschirm** — Benutzerliste, Namensfeld, Kennwortfeld, Fehlermeldung, verdoppelnde Verzögerung | `glogin.fi` (neu, 560 Z.) |
| 3 | **Der Schreibtisch läuft unter dem angemeldeten Menschen** — `anmeldung`/`noanmeldung`, `M_ANMELDUNG` | `kgui.fi`, `kmain.fi`, `kstate.fi` |
| 4 | **Ebene 0 darf auch ohne Wurzel** — sonst stirbt der Schreibtisch als uid 1000 | `sysgui.fi` |
| 5 | **Die Sperre gilt der SITZUNG** — `SP_UID`, op 7/8 | `sys.fi`, `kstate.fi`, `lock.fi`, `glogin.fi` |
| 6 | **Der Sperrer wird nicht mehr doppelt gestartet** (Riegel) und **sein Platz stimmt** (`elf.spawn` gibt einen Platz, keine pid) | `kgui.fi` |
| 7 | **Aufgesperrt heißt: das Fenster ist weg** | `lock.fi`, `glogin.fi` |
| 8 | **Konten, Hashes und die Anmeldung im Abbild** | `tools/usbimg/build.sh` |
| 9 | **Die Leerlaufsperre wird wirklich gestartet** — eigenes Programm, weil `lock -d` unerreichbar ist | `sperrwache.fi` (neu), `glogin.fi`, `sys.fi` |
| 10 | Fotos mit Tastendrücken | `tools/anmeldung/shot.sh` (neu) |

---

## 2. Die Abnahme — Bilder, keine Behauptungen

Ein Lauf, ein Abbild, vier Fotos. Kernelzeile:
`gfx fbres=1280x800 wm wig desk wmshell wmdauer herz … anmeldung`

| Schritt | Bild | was der Bericht sagt |
|---|---|---|
| Boot → Anmeldung | `10-login.png` | `desk: anmeldung vor schreibtisch` · `desk: start /bin/glogin pid=2` · `glogin: bereit n=1` |
| falsches Kennwort | `20-falsch.png` | `glogin: abgewiesen, name=justin` · `glogin: gewartet 1257 ms` |
| richtiges Kennwort → Schreibtisch | `50-voll-a-schreibtisch.png` | `glogin: angemeldet als justin` · **`glogin: uid=1000`** · `glogin: desktop pid=7` |
| Super+L → Sperre | `50-voll-b-gesperrt.png` | `sperre: an (Win+L)` · `sperre: Sperrer neu, pid=8` · `sperre: bereit` |
| entsperren → Schreibtisch | `50-voll-c-entsperrt.png` | `sperre: aufgesperrt` |
| Leerlauf (`leerlauf=25`, nichts angefasst) | `99-leerlauf-b-selbst-gesperrt.png` | `sperrwache: an, Leerlauf ab 25 s` · `idle=3018 … 24619` · `Leerlauf abgelaufen, sperre` |

**Die Fotos gegeneinander gerechnet** (Stichproben, 64000 Punkte je
Bild, `pruef/bildpruef.py` und ein Punktvergleich):

    Schreibtisch vs gesperrt : 60596   (die Sperre deckt den Schreibtisch zu)
    gesperrt vs entsperrt    : 60610   (sie geht wieder weg)
    Schreibtisch vs entsperrt:   700   (derselbe Schreibtisch -- der Rest ist die Uhr)

Die 700 sind der Beweis, dass nach dem Entsperren **derselbe**
Schreibtisch dasteht und nicht ein neuer: nur die Taskleisten-Uhr hat
weitergezählt.

**Die Leerlaufsperre**, eigener Lauf mit `leerlauf=25`, nach der
Anmeldung nichts angefasst:

    Schreibtisch (95 Farben) vs von selbst gesperrt (50 Farben):
        63750 von 64000 Stichproben verschieden

Der Wächter zählt den Leerlauf sichtbar hoch (`idle=3018 … 24619`) und
sperrt bei der Grenze — er hängt nicht, und er sperrt nicht zu früh.

**Dass der Schreibtisch nicht mehr root ist**, steht in zwei Zahlen
nebeneinander im selben Bericht:

    glogin: uid=1000            <- nach setuid, vor dem Start des Schreibtischs
    glogin: desktop pid=7       <- das Kind erbt diese Kennung

und im Fensterserver als lebendes Fenster auf Ebene 0:

    wm: fen i=1 id=12 x=0 y=0 w=1280 h=800 lay=0 fl=2 malen=75 px=17201784

**Das Kennwortfeld zeigt Punkte und keine Buchstaben.** Gemessen an der
Mittelzeile des Feldes, bei 13 getippten Zeichen:

    ...##.....####.....####.....####.....####.....####.....####...
    Punkte in der Mittelzeile: 14   Breiten: [2, 4, 4, 4, 4, 4, 4, ...]

Dreizehn gleich breite Punkte (plus die 2 Punkt breite Einfügemarke),
gleichmäßig verteilt. Zum Vergleich dasselbe Maß im Namensfeld, in dem
`justin` im Klartext steht: Breiten `[4, 15, 6, 2, 8]` — ungleich, weil
Buchstaben ungleich breit sind.

**Die Sperre gibt den Schreibtisch nicht preis.** Der Schreibtisch malt
einen Verlauf (183 verschiedene Farben in der Stichprobe), das
Sperrbild hat 50, davon 98 % eine einzige Fläche. Keine der
Verlaufsfarben ist darunter.

---

## 3. Was die Sicherheitsauflagen sagen, gemessen

    'startkennwort' steht NICHT im Klartext im Abbild
    'osumroot'      steht NICHT im Klartext im Abbild
    /etc/shadow traegt $osum1$-Eintraege (PBKDF2, 8192 Runden, 8 Oktette Salz je Konto)
    kein Kennwort in irgendeinem seriellen Mitschnitt

Das Salz kommt je Konto aus `os.urandom` — ein festes Salz wäre in jedem
Abbild dasselbe, und genau dagegen ist ein Salz da.

**Keine Hintertür, kein eingebautes Notfallkennwort.** Die Gegenprobe
dazu ist gemessen: root's Kennwort auf justins gesperrtem Schirm →

    sperre: falsches Kennwort, bleibt zu

**Die Verzögerung ist echt** und wird von der Uhr der Maschine selbst
bestätigt (`CLOCK_MONOTONIC`, nicht von der Uhr des Wirts, die auch die
Prüfzeit enthielte): gefordert 1000 ms, `glogin: gewartet 1257 ms`.

---

## 4. Vier Fehler, die erst beim Messen sichtbar wurden

Sie stehen hier, weil jeder von ihnen eine Abnahme gekostet hat und
keiner im Quelltext zu sehen war.

**4.1 Ebene 0 war der Wurzel vorbehalten.** `sysgui.fi` ließ jede Ebene
außer `L_NORMAL` nur für root zu. Der Schreibtisch als uid 1000 bekam
dort `E_RIGHTS` und beendete sich sofort — leerer Schirm,
wiederverwendete Prozessnummer, **kein Wort im Bericht**, weil
`desktop.fi` diesen Abbruch hinter dem Messschalter meldete.
Die Gefahr einer Ebene ist, **was sie verdeckt**: `L_DESK` liegt hinter
allem und kann nichts überdecken, also auch keinen Kennwortdialog
nachbauen. `L_TOP` und darüber bleibt der Wurzel vorbehalten — daran
hängt die Zusage des Sperrbildschirms.

**4.2 Der Sperrer wurde doppelt gestartet.** `sperre_wache` ruft
`desk_spawn`, das 250 Runden `wm.poll`/`compose` dreht — und die Wache
hängt an **zwei** Schleifen. Während der 250 Runden kam die andere dran,
sah `SP_PID` noch unverändert und startete einen zweiten. Ein zweiter
Sperrer ist nicht harmlos: nur einer steht in `SP_PID`, der andere liegt
mit seinem Fenster darüber, nimmt die Tastatur an und weist **jedes
richtige Kennwort** mit `-EPERM` ab. Abhilfe ist ein Riegel und keine
Wartezeit — eine Wartezeit wäre geraten.

**4.3 `elf.spawn` gibt einen PLATZ zurück, keine Prozessnummer.** Die
Wache behandelte ihn als eine (`find_pid` auf einen Platz). Gemessen mit
einer eigens eingebauten Zeile:

    sperre: Sperrer neu, pid=6  slot=5
    wm: darf i=4 owner=6 slot=5

Das Fenster des Sperrers gehörte Platz 6, eingetragen war Platz 5 — also
stimmte `wm.darf` für sein **eigenes** Fenster nicht, und `compose`
malte während der Sperre **gar nichts**: der Sperrbildschirm blieb
unsichtbar (`malen=0 px=0`), obwohl das Programm lief und `bereit`
meldete. Die beiden Zahlen sind nur gleich, solange nie ein Prozess
geendet hat; nach der Anmeldung laufen sie auseinander.

**4.4 Gesperrt wurde der falsche Mensch.** `/bin/lock` wird vom Kern
gestartet (es muss, sonst könnte ein Absturz es nicht neu starten),
läuft also mit uid 0 und prüfte per `getuid` immer **roots** Eintrag.
Gemessen: nach der Anmeldung als `justin` sperrte Super+L, und
aufgesperrt hat `osumroot`. Damit entsperrt jeder, der das
Verwalterkennwort kennt, **jede fremde Sitzung**, und der angemeldete
Mensch kommt nicht hinein — beides falsch herum. Neu sagt `SP_UID`, wem
die Sitzung gehört; `glogin` trägt es ein, solange es noch root ist.

**4.5 `profile app` bekommt seine Argumente nicht** — und deshalb war
die Leerlaufsperre nicht nur ungestartet, sondern unstartbar. Gemessen
mit einer Zeile in `lock.fi`, im fertigen Abbild:

    lock: argc gesehen 0

**auch** bei dem Sperrer, den der Kern selbst mit `desk_spawn` und
`argc = 1` startet. Ein Programm mit `profile app` wird ohne `crt.o`
gebunden (`tools/usbimg/build.sh`), weil firnc dort sein eigenes
`_start` einsetzt — und dieses `_start` reicht den Argumentblock des
Kerns nicht an `u_start` weiter. `login.fi` und `su.fi` sehen ihre
Argumente (`profile kernel`, und `tools/multiuser/run.sh` misst `login
NAME` mit 91/0); `lock`, `desktop`, `taskbar`, `settings`, `launcher`
und `glogin` sehen sie nicht.

Damit sind `lock -d`, `lock -s`, `lock -an` und `lock -absturz` seit
Runde GRUNDLINIE tot — nicht kaputt, sondern nicht aufrufbar. Das ist
ein Befund über den Baum und kein Schaden dieser Runde.

**4.6 Eine Sitzung, die gerade anfängt, hat keinen Leerlauf.**
`SP_LAST` hängt an `wm.input_seen` (Maus und Taste am Fensterserver).
Während des Anmeldeschirms zählte der Leerlauf also seit dem Start der
Maschine weiter — mit `leerlauf=25` sperrte der Schirm **sofort** nach
der Anmeldung, ohne eine einzige eigene Meldung des Wächters. `op 7`
setzt die Uhr jetzt zurück: wer sich gerade angemeldet hat, war
offensichtlich da.

---

## 5. Was NICHT gebaut wurde, und warum

**5.1 Die Taskleiste läuft weiter als root.** Der Kern startet sie
selbst, unmittelbar nach dem Anmeldeschirm. Sie umzuziehen ist mehr als
eine Zeile: sie schreibt `/etc/taskbar.conf` (gehört root, 0755), sie
liest `/proc`, und sie startet über `SYS_EXEC` weitere Programme, die
dann ebenfalls die Kennung wechseln würden. Das gehört gemessen und
nicht nebenbei umgestellt. **Der Schreibtisch ist der Prozess, an dem
der Mensch arbeitet — er ist der, der zuerst herunter musste.**

**5.2 Kein Wechsel des Benutzers zur Laufzeit, kein Abmelden.** Der
Anmeldeschirm läuft einmal beim Start. „Abmelden" hieße: den
Schreibtisch und alles darunter beenden und `glogin` neu starten — das
braucht einen Sitzungsbegriff (wer gehört zu dieser Anmeldung?), den
dieses System nicht hat. `SP_UID` ist der erste Baustein dafür.

**5.3 `lock -d`, `-s`, `-an`, `-absturz` bleiben unerreichbar.** Siehe
4.5: `profile app` reicht die Argumente nicht durch. Diese Runde hat den
Wächter deshalb als eigenes Programm gebaut, statt die ABI anzufassen —
das wäre ein Eingriff in Übersetzer oder Binder und ein eigener
Auftrag. Wer ihn nimmt, findet die Messung in `sperrwache.fi`.

**5.4 Die Heimatverzeichnisse fehlen.** `/etc/passwd` verspricht
`justin` das Verzeichnis `/users/justin`; im Abbild gibt es nur
`/users/root`. Der Schreibtisch braucht es heute nicht (er schreibt
nichts), die Einstellungen und `explorer` werden es brauchen.

**5.5 Nur `firnc0`.** `tools/desktop/run.sh` baut auch mit `firnc1`, und
dort scheitern `desktop`, `taskbar`, `settings` und `launcher` am
Assembler (`symbol '_F1.rt__ld8' is already defined`). Das ist **kein
Befund dieser Runde**: derselbe Fehler tritt auf unverändertem `main`
mit einer Datei auf, die diese Runde nie angefasst hat (gegengeprüft mit
`launcher.fi`).

---

## 6. Die Programme im Abbild

Neu in der Programmzeile von `tools/usbimg/build.sh`:
`glogin`, `lock`, `login`, `passwd`, `su`, `chown`.

Neu in `/etc/`: `shadow` (0600), `group`, `login.conf`, `sperre.conf`.

Anfangskennwörter, auf der Bauausgabe genannt und mit `passwd` zu
ändern: `justin` = `startkennwort`, `root` = `osumroot`. Ein Abbild ohne
bekanntes Anfangskennwort wäre eines, an dem sich niemand anmelden kann.

---

## 7. Bestehende Zusagen

    MULTIUSER: 91 passed, 0 failed     (tools/multiuser/run.sh)
    K13:       99 passed, 0 failed     (tools/k13/run.sh)
    CHECK-UI PASSED                    (tools/check-ui.sh)
      166 Dateien geprueft
      0 Programme malen sich ein Bedienelement selbst
      0 Programme greifen an der Bibliothek vorbei auf fUi zu
      0 Funktionen in wlib.fi malen an fUi vorbei

**Und der alte Weg ist unveraendert.** Gemessen am selben Abbild, ohne
das Wort `anmeldung`:

    desk: OHNE anmeldung -- uid bleibt
    desk: start /bin/desktop  pid=2

und mit `anmeldung noanmeldung` (die Gegenprobe ueberstimmt, wie
angekuendigt) genau dasselbe. Kein Pruefstand, der `desk` schreibt,
sieht von dieser Runde etwas.

Der Anmeldeschirm malt kein einziges Bedienelement selbst — er benutzt
`wlib.label`, `wlib.list`, `wlib.entry`, `wlib.button`, und die
Verdeckung sitzt in der Bibliothek, damit **jedes** Kennwortfeld dieses
Systems sie bekommt und nicht nur dieses eine.
