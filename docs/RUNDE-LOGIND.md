# RUNDE LOGIND — P-002 und P-003, nachgesehen und die Reste geschlossen

Zweig `logind`, abgezweigt von `main` (`d133923`). Worktree
`/root/osum-w-logind`. **Nicht** nach `main` gemerged.

Alle Zahlen hier sind gemessen. Wo nichts gemessen ist, steht nichts.

---

## 0. DER BEFUND — BEIDE PUNKTE WAREN SCHON GEBAUT

Der Auftrag nannte `P-002` (grafischer Login/Sperrbildschirm) und
`P-003` (Ausschalten/Neustart aus der Oberfläche) als offene
P1-Punkte und sagte: *„ZUERST NACHSEHEN, WAS SCHON DA IST."* Genau das
war diesmal die halbe Runde.

| Punkt | Zustand auf `main` (d133923) | Beleg |
|---|---|---|
| `P-003` | **erledigt** seit Runde ENERGIE (13.09., Zweig `energie`, gemergt `a298db7`) | `docs/RUNDE-ENERGIE.md`, `belege/energie/` (12 Bilder + Belegzeilen) |
| `P-002` | **erledigt** seit Runde ANMELDUNG (Zweig `anmeldung`, gemergt `996d74e`) | `docs/RUNDE-ANMELDUNG.md`, `belege/anmeldung/` (9 Bilder) |

`OFFEN.md` ist in diesem Punkt **veraltet**. Bei `P-003` sagt die Datei
es selbst schon („ERLEDIGT RUNDE ENERGIE"); bei `P-002` steht dort noch
der Stand vom 12.09. (*„`desktop.fi` ruft keines von beiden"*), und der
ist seit dem Merge des Zweigs `anmeldung` überholt.

**Nachgemessen, nicht gelesen:**

```
$ git log main --oneline | grep -iE 'anmeldung|energie'
996d74e Merge branch 'anmeldung'
a298db7 Merge branch 'energie'
$ git log main..anmeldung --oneline | wc -l      # 0 -- vollstaendig gemergt
$ git log main..energie   --oneline | wc -l      # 0 -- vollstaendig gemergt
$ wc -l kernel/user/glogin.fi kernel/user/lock.fi kernel/user/sperrwache.fi
  683 glogin.fi   431 lock.fi   146 sperrwache.fi
$ sed -n '187p' tools/usbimg/build.sh
glogin lock login passwd su chown sperrwache init svc"}
```

### Was schon da war und benutzt wurde, statt es neu zu bauen

Der Auftrag verlangte ausdrücklich: *„Baue KEINE eigene Kennwort-Ablage
und KEINE eigene Hashfunktion, wenn es schon eine gibt."* Es gibt eine,
und diese Runde hat **keine Zeile** Krypto geschrieben.

| Sache | wo | Zustand |
|---|---|---|
| PBKDF2-HMAC-SHA256, Format `$osum1$`, `/etc/shadow` | `kernel/user/pw.fi` (1094 Z.) | vollständig, 8192 Runden, Salz je Konto aus `os.urandom` |
| Der grafische Anmeldeschirm | `kernel/user/glogin.fi` (683 Z.) | Benutzerliste, Namensfeld, verdecktes Kennwortfeld, verdoppelnde Verzögerung |
| Der Sperrbildschirm | `kernel/user/lock.fi` (431 Z.) | sperrt die **Sitzung** (`SP_UID`), nicht den Sperrer |
| Leerlaufsperre | `kernel/user/sperrwache.fi` (146 Z.) | eigenes Programm, weil `lock -d` unerreichbar ist |
| Sperre im Kern (wer sperrt, wer aufsperrt, Ausfallzustand) | `sys.fi` op 1870, `kgui.sperre_wache` | vollständig |
| uid/gid je Prozess, Vererbung über fork/exec | `kernel/sched.fi` `T_UID`=392 | vollständig |
| Ausschalten/Neustart/ACPI S5 | `kernel/power.fi`, `init.fi::shutdown` | vollständig |
| Energiemenü im Startmenü | `kernel/user/launcher.fi` | Knopf, Klappmenü, Sicherheitsabfrage |

**Also war diese Runde kein Bau-, sondern ein Rest-Auftrag.** Die zwei
Reste standen in den Berichten der Vorrunden als ausdrücklich offen
benannt — und genau das ist gebaut worden.

---

## 1. DIE ZWEI ECHTEN LÜCKEN

### 1.1 „Abmelden" meldete nicht ab

`docs/RUNDE-ANMELDUNG.md` §5.2 und `docs/RUNDE-ENERGIE.md` §3.4 sagen es
beide selbst. Der Menüpunkt tat dies:

```
fn pw_abmelden() -> bool {
    let pid: u64 = ulib.sys(ulib.SYS_EXEC, "/bin/desktop", 0, 0)
    return !ulib.bad(pid)
}
```

Er startete den Schreibtisch neu — **unter derselben Kennung**. Die
Sitzung blieb offen.

Solange es keine Anmeldung gab, war das die ehrlichste mögliche Antwort,
und der Kommentar darüber nannte es auch so. **Mit** einer Anmeldung im
System ist dieselbe Zeile falsch: wer abmeldet und weggeht, lässt seine
Sitzung offen stehen, und der Nächste sitzt darin. Ein Knopf, der
„Abmelden" heißt und nicht abmeldet, ist schlimmer als kein Knopf — man
verlässt den Rechner im Vertrauen darauf.

### 1.2 `/users/justin` fehlte

`docs/RUNDE-ANMELDUNG.md` §5.4. `/etc/passwd` verspricht es:

```
justin:x:1000:1000:Justin:/users/justin:/bin/sh
```

Im Abbild gab es nur `/users/root/`. `glogin` legt die Rechte ab und
startet den Schreibtisch als uid 1000; jedes Programm, das danach etwas
Eigenes ablegen will (die Einstellungen schreiben
`/users/<name>/config/locale`), schreibt in ein Verzeichnis, das nicht
existiert.

---

## 2. WAS GEBAUT WURDE

### 2.1 Abmelden: der Wunsch, den nur der Kern erfüllen kann

**Warum es nicht ohne den Kern geht** — und warum die Vorrunde hier
aufgehört hat: der Starter läuft als uid 1000. `glogin` **muss** als
root laufen, denn es liest `/etc/shadow` (0600, root) und legt danach mit
`setgroups`/`setgid`/`setuid` die Rechte ab. Wer abgegeben hat, bekommt
nicht zurück — das ist der Sinn von `setuid`. Der Starter kann `glogin`
also nicht selbst starten, und `setuid(0)` darf er auch nicht.

Der Weg ist deshalb derselbe wie bei der Sperre daneben: **was Rechte
braucht, gehört in den Kern.**

| Stück | Datei | was |
|---|---|---|
| `SP_LOGOUT` (0x148), `SP_LOGOUTS` (0x150) | `kernel/kstate.fi` | der Wunsch und ein Zähler, in der K11-Region (4096 Oktette ab 0x3D000, reichlich Platz) — **und in der `export`-Liste** |
| `do_sperre` op 9 / op 10 | `kernel/sys.fi` | „bitte abmelden" / „wie oft abgemeldet" |
| `abmelde_wache` | `kernel/kgui.fi` | die Arbeit, an **beiden** Schleifen des Fensterservers, mit Riegel |
| `pw_abmelden` | `kernel/user/launcher.fi` | statt `exec /bin/desktop` jetzt Syscall 1870 op 9 |

**Wer op 9 rufen darf: jeder.** Das ist bewusst so. Mehr als die
**eigene** Sitzung beenden kann damit niemand — es gibt genau eine, und
wer an der Tastatur sitzt, darf sie beenden. Ein Kennwort dafür zu
verlangen wäre die falsche Frage: abmelden ist der Weg **von** den
Rechten weg, nicht zu ihnen hin. Der Weg zurück führt über `glogin` und
`/etc/shadow`, und der ist mit Kennwort geschützt.

**Was `abmelde_wache` tut, in dieser Reihenfolge:**

1. **`blk.flush`** — die Puffer. Ein Abmelden beendet Programme, und ein
   Programm, dessen Datei noch im Speicher steht, verliert sie sonst.
   (`blk.flush` und nicht `do_sync` aus `sys.fi`: das wäre ein
   Rückimport, denn `sys.fi` importiert `kgui`. Es ist derselbe Aufruf,
   den `do_sync` als letztes macht.)
2. **SIGKILL an jede Aufgabe mit `T_UID == SP_UID`** — der Schreibtisch
   **und** alles, was der Mensch von dort gestartet hat. Ein Abmelden,
   das die Programme des Vorgängers weiterlaufen lässt, ist keines.
   SIGKILL und nicht SIGTERM: hier wartet niemand auf eine Frist, und
   ein Programm, das den Abschied verweigert, hielte sonst die Sitzung
   offen.
3. **Die Sperre räumen.** Stand sie (abgemeldet vom Sperrbildschirm
   aus), wäre der Anmeldeschirm sonst unter einem Sperrbildschirm
   begraben, dessen Sperrer gerade gestorben ist — und `sperre_wache`
   würde ihn brav neu starten.
4. **`SP_UID` auf 0.** Es gibt keine Sitzung mehr.
5. **`glogin` neu, als root**, über denselben `desk_spawn`, den
   `desk_start` beim Systemstart nimmt. Kein zweiter Weg daneben.

**`uid 0` wird nicht gejagt.** Lief das System ohne Anmeldung hoch
(`SP_UID == 0`), wäre „alles mit uid 0" der ganze Rechner —
einschließlich der Leiste, des Fensterservers und der Aufgabe, in der die
Zeile gerade läuft. Ohne Sitzung gibt es nichts abzumelden.

**Der Riegel** (`lo_startet`) steht aus demselben Grund da wie in
`sperre_wache`: die Funktion hängt an **zwei** Schleifen, und
`desk_spawn` dreht 250 Runden `wm.poll`. Ohne Riegel käme die andere
Schleife dazwischen, sähe den Wunsch noch stehen und startete einen
**zweiten** Anmeldeschirm.

**Die Taskleiste bleibt stehen.** Sie läuft als root (die ehrliche
Grenze der Runde ANMELDUNG) und gehört damit nicht zur Sitzung —
Schritt 2 fasst sie nicht an. Das ist hier sogar richtig: der
Anmeldeschirm liegt auf `L_TOP` und deckt sie zu.

### 2.2 Das Heimatverzeichnis

`tools/usbimg/build.sh`:

```
"/users/justin/@0700:1000:1000"
"/users/justin/config/@0700:1000:1000"
```

**Rechte und Eigentum sind der Punkt**, nicht die bloße Existenz. Ohne
`@0700:1000:1000` gehörte das Verzeichnis root mit 0755 (die Vorgabe von
`mkfs.py`) — dann könnte justin in seinem eigenen Zuhause nichts
anlegen, und jeder andere könnte hineinsehen. 0700 heißt: nur er.

Beide Pfade stehen in der **Pflichtliste** (65 → 67 Pfade, nachgezählt), also fällt
der Bau, wenn sie einmal nicht mehr ankommen.

---

## 3. GEMESSEN

### 3.0 `tools/logind/run.sh` — **48 bestanden, 0 gescheitert**

Der Volllauf der Runde, `RC=0`, alle sieben Abschnitte grün (die
Abschnitte 1/2/3/4/6/7 unten in 3.3, Abschnitt 5 in 3.1).

### 3.1 `pruef/abmelden.py` — **13 bestanden, 0 gescheitert**

Echte Mausklicks, `usb-mouse` + `usb-kbd`, Lage der Bedienelemente aus
dem Bericht der Programme selbst.

```
  OK    der Anmeldeschirm ist bereit (nach 4s)
  OK    angemeldet als justin, der Schreibtisch laeuft unter uid=1000
  OK    das Startmenue ist offen (Fenster 11, fl=18)
  OK    die Lage des Energieknopfs steht im Bericht: 12,376 88x32
  OK    das Energiemenue ist aufgeklappt ('launcher: energie auf')
  OK    der Starter hat die Wahl aus dem Energiemenue gemeldet
  OK    der Kern hat den Abmeldewunsch bekommen ('abmelden: Sitzung')
  OK    die Sitzung wurde beendet -- 2 SIGKILL im Mitschnitt (pids 15, 16)
        der Kern zaehlt selbst n=2
  OK    der Anmeldeschirm wurde neu gestartet (pid=18)
  OK    der Anmeldeschirm hat seine Bedienelemente WIEDER aufgebaut
        ('glogin: rect id=6' 2x, 'bereit' 2x)
  OK    GEGENPROBE: nach dem Abmelden ist niemand angemeldet (1x 'angemeldet')
  OK    BILD: der Schirm ist ein ANDERER (62892 Stichproben verschieden)
        Farben Schreibtisch 70, nach dem Abmelden 53
  OK    BILD: es ist WIEDER DER ANMELDESCHIRM -- nur 23 von 64000
        Stichproben anders (0.04 %, das ist die Uhr)
```

**Fünfmal gefahren** (11/1, 12/0, 13/0, 12/1, 13/0). Die roten Zusagen
der Läufe 1 und 4 waren **beide** die Verschränkung auf der seriellen
Leitung (Abschnitt 4.5) und **kein** Sachfehler: in Lauf 4 stand
`abmelden: Anmelduwlib: font ui px=15` im Mitschnitt — die Zeile wurde
geschrieben, `wlib` des gerade startenden Anmeldeschirms hat mitten
hinein gemeldet. Die Sachaussagen waren in **allen fünf** Läufen grün.

**Eine Zahl schwankt, und das ist richtig so:** die Menge der
getroffenen Aufgaben ist **1 oder 2**. Getroffen wird, was zur Sitzung
gehört und **noch lebt** — der Schreibtisch immer, die Leerlaufwache
nur, wenn sie nicht schon von selbst geendet hat. `abmelde_wache`
überspringt `S_ZOMBIE` und `S_FREE` ausdrücklich. Eine Abnahme, die hier
auf genau 2 bestünde, würde die Lebensdauer der Wache messen und nicht
das Abmelden; verlangt wird deshalb **mindestens eine**.

**Die ganze Kette in einem echten Mitschnitt.**
`belege/logind/abmelden-mitschnitt.txt`, gefiltert auf die Zeilen von
`glogin`, `launcher`, `signal` und Kern — **sonst unverändert,
einschließlich der verschränkten Stellen** (ein geglätteter Mitschnitt
wäre kein Beleg):

```
desk: anmeldung vor schreibtisch          <- der Kern nimmt den Anmeldeweg
desk: start /bin/glogin  piwlib: font ui px=15 asc=12 h=18
glogin: bereit n=1
glogin: rect id=0 … id=6                  <- sieben Bedienelemente, erster Aufbau
desk: start /bin/taskbar  pid=4
desk: start /bin/launcher  pid=5
glogin: angemeldet als justin
glogin: uid=1000                          <- P-002: NICHT root
glogin: desktop pid=16
glogin: waechconf -- 17                   ("waechter pid=17", verschraenkt)
launcher: energie auf                     <- Klick auf den Energieknopf
launcher: energie wahl=2                  <- "Abmelden" gewaehlt
abmelden: Sitzung uliadu=n1c0h0e0r        ("Sitzung uid=1000", verschraenkt)
signal: pid=17 SIGKIL -- killed           <- der Schreibtisch, von signal.fi gemeldet
desk: start /bin/glogin  pid=9
abmelden: Anmeldung neu pid=18
glogin: bereit n=1
glogin: rect id=0 … id=6                  <- ZWEITER Aufbau, der Schirm ist zurueck
```

Zwei Zeilen dieses Laufs sind zeichenweise verschränkt (`waechconf --
17` statt `waechter pid=17`, `uliadu=n1c0h0e0r` statt `uid=1000`) —
siehe Abschnitt 4.5. **Genau deshalb hängt keine Zusage an ihnen.**

**Zwei unabhängige Quellen sagen dasselbe.** Der Kern zählt selbst
(`abmelden: beendet n=`), und `kernel/signal.fi` meldet für jeden
getroffenen Prozess `SIGKIL -- killed` — mit genau der Prozessnummer,
die `glogin` vorher als sein Kind gemeldet hat. Die zweite Quelle ist
die bessere: sie kommt aus dem Signalweg und nicht aus der Funktion,
die geprüft wird. **Und die Gegenprobe**: in den Läufen ohne Abmelden
steht **0×** `SIGKIL` (`belege/logind/anmelden.txt`,
`belege/logind/ohne.txt`).

Dass `/bin/glogin` **zweimal** gestartet wurde, steht ein drittes Mal
unabhängig da: `desk: start /bin/glogin` kommt in diesem Mitschnitt
zweimal vor, mit verschiedenen Prozessnummern (3 und 9).

### 3.2 Das Bild — der Anmeldeschirm ist wirklich zurück

Drei Bilder desselben Laufs, Stichproben über 64000 Punkte:

```
Anmeldeschirm (Start)  vs  nach dem Abmelden :     23 von 64000  (0,04 %)
Anmeldeschirm (Start)  vs  Schreibtisch      :  62870 von 64000  (98,2 %)
```

**Die 23 sind der Beweis.** Nach dem Abmelden steht derselbe
Anmeldeschirm da wie beim Start — nicht ein anderer Schirm, nicht ein
leerer, nicht der Schreibtisch. Die 23 abweichenden Stichproben sind die
Uhr in der Taskleiste, die weitergezählt hat. Ein „Abmelden", das nur
den Schreibtisch neu malt, käme auf 98 % Unterschied zum Anmeldeschirm.

Farben: Anmeldeschirm 53, Schreibtisch 71 (der malt einen Verlauf).

Belege: `belege/logind/k-10-anmeldeschirm.png`,
`k-20-schreibtisch.png`, `k-30-startmenue.png`,
`k-40-energiemenue.png`, `k-50-wieder-anmeldung.png` — alle fünf mit
0 % schwarzer Fläche, also wirklich gemalt.

### 3.3 Die übrigen Abschnitte des Volllaufs

```
== 1. das Abbild traegt, was die Anmeldung braucht
  OK    im Abbild: /bin/glogin /bin/lock /bin/login /bin/passwd /bin/su
        /bin/sperrwache /etc/shadow /etc/passwd /etc/group
        /etc/login.conf /etc/sperre.conf          (11 Zusagen)
  OK    /etc/shadow traegt $osum1$-Eintraege (PBKDF2), 2 Zeilen, Runden 8192
  OK    GEGENPROBE: 'startkennwort' steht NICHT im Klartext im Abbild
  OK    GEGENPROBE: 'osumroot' steht NICHT im Klartext im Abbild

== 2. das Heimatverzeichnis von justin
  OK    /etc/passwd nennt als Heimat: /users/justin
  OK    im Abbild: /users/justin/ und /users/justin/config/
  OK    es gehoert justin und nur ihm: /users/justin 700 1000 1000
  OK    auch config/: /users/justin/config 700 1000 1000
  OK    GEGENPROBE: /users/root gehoert weiter root (/users/root 755 0 0)

== 3. die Anmeldung kommt VOR dem Schreibtisch (P-002)
  OK    der Kern startet die Anmeldung vor dem Schreibtisch
  OK    der Anmeldeschirm ist bereit
  OK    angemeldet als justin
  OK    der Schreibtisch laeuft unter uid=1000 und NICHT als root
  OK    und er hat den Schreibtisch gestartet
  OK    BILD: der Schreibtisch steht (99 % Tinte)

== 4. ein falsches Kennwort wird abgewiesen -- und verzoegert
  OK    das falsche Kennwort wurde abgewiesen
  OK    und danach mindestens 1000 ms gewartet (gemessen: 1276 ms)
  OK    GEGENPROBE: kein 'angemeldet' -- kein Weg an der Anmeldung vorbei
  OK    GEGENPROBE: kein Kennwort im seriellen Mitschnitt

== 6. GEGENPROBE: ohne 'anmeldung' ist der alte Weg unveraendert
  OK    ohne das Wort meldet der Kern den alten Weg
  OK    und startet den Schreibtisch direkt
  OK    GEGENPROBE: glogin wurde nicht gestartet
  OK    GEGENPROBE: keine Abmeldung ohne Sitzung

== 7. die Oberflaeche haelt die Regel
  OK    check-ui.sh PASSED   188 Dateien geprueft
```

Die Verzögerung von **1276 ms** wird von der Uhr der **Maschine** selbst
gemessen (`glogin: gewartet …`, `CLOCK_MONOTONIC`), nicht von der des
Wirts — die enthielte auch die Prüfzeit.

Abschnitt 6 ist die Zusage, dass **fremde Prüfstände nichts sehen**:
jeder Läufer dieses Baums, der `desk` schreibt, fährt ohne das Wort
`anmeldung`, und dort ändert sich keine Zeile.

### 3.4 Die bekannten Sollwerte

**Seriell gemessen**, jeder für sich:

| Läufer | Soll | gemessen |
|---|---|---|
| `bash tools/check-ui.sh` | PASSED | **CHECK-UI PASSED** (188 Dateien, 0 Befunde) |
| `tools/krypto/run.sh` | 61/0 | **61 bestanden, 0 gescheitert** |
| `tools/aesni/run.sh` | 31/0 | **31 bestanden, 0 gescheitert** |
| `tools/xtstafel/run.sh` | 6/0 | **6 bestanden, 0 gescheitert** |
| `tools/geraetekey/run.sh` | 12/0 | **12 bestanden, 0 gescheitert** |
| `tools/argon/run.sh` | 35/0 | **34 bestanden, 1 gescheitert** — siehe 5.2 |
| `tools/build-kernel.sh` | baut | **6 077 432 Oktette, Stufe 0** |
| `tools/usbimg/build.sh` | baut | **RC=0**, 67 Pflichtpfade, Abbild 130 MiB |

`tools/install/abnahme.sh` (35/0) ist **nicht** nachgemessen — siehe
Abschnitt 5.1. `krypto` **61/0** und `aesni` **31/0** wurden dabei
**zweimal unabhängig** bestätigt: einmal einzeln und einmal aus dem
Nachbarabschnitt von `tools/argon/run.sh`, der sie selbst mitfährt.

---

## 4. FÜNF FEHLER, DIE ERST BEIM MESSEN SICHTBAR WURDEN

Sie stehen hier, weil jeder von ihnen eine Abnahme gekostet hat und
keiner im Quelltext zu sehen war. **Vier von fünf steckten im
Messaufbau, nicht im System** — und das ist die Lehre der Runde.

### 4.1 Parallel gemessene Läufer zerstören die Messung

Der erste Versuch lief `krypto`, `aesni`, `argon` und `xtstafel`
**gleichzeitig** (vier Kerne, sieht vernünftig aus). Ergebnis:

```
KRYPTO:    7 bestanden, 1 gescheitert      "der Kern laesst sich nicht bauen"
XTSTAFEL:  0 bestanden, 1 gescheitert      "vendor/firn/bin/firnc: No such file"
ARGON:     9 bestanden, 20 gescheitert
AESNI:     8 bestanden, 10 gescheitert
```

Ursache: alle vier rufen `vendor/firn/fetch-firnc.sh`, und das baut in
ein **gemeinsames** `/tmp/firn-pin-<commit>`. Sie löschten sich
gegenseitig den Übersetzer unter den Füßen weg
(`rm: cannot remove '/tmp/firn-pin-c4e3dfce/…': Directory not empty`).

**Seriell nachgefahren: 61/0, 31/0, 6/0.** Kein einziger echter Fehler.
Wer diese Zahlen parallel erhebt, misst den Prüfstand und nennt es
Kernel. **Diese Läufer laufen seriell, immer.**

### 4.2 Die Eingabetaste heißt `ret`, nicht `kp_enter`

Im ersten Lauf der Abnahme standen die Buchstaben im Bericht
(`key: s`, `key: t`, …), aber die Zeile `key: [enter]` fehlte — das
Kennwort wurde getippt und nie abgeschickt. Die Abnahme meldete völlig
zu Recht „`glogin: angemeldet` fehlt": es hatte sich niemand angemeldet.

Die übrigen Läufer dieses Baums nehmen überall `ret`
(`pruef/abnahme2.py`, `pruef/ausschalten.py`).

### 4.3 `/etc/uitrace` — ohne diese leere Datei ist die Oberfläche stumm

Der Klick auf den Energieknopf ging ins Leere, weil
`launcher: rect id=4` (die Lage des Knopfs) nirgends stand und der
Läufer auf eine geratene Vorgabe zurückfiel: `12,376 76x32` statt der
echten `12,376 88x32`.

`dbg_setup` in `launcher.fi` (und in `qs.fi`, `taskbar.fi`) macht
**alle** Meldungen von dieser Datei abhängig; `say`/`sayn`/`nl` kehren
ohne sie sofort zurück. Das Programm arbeitet vollständig richtig — es
sagt nur nichts. Das Abbild muss mit `UITRACE=1` gebaut werden.

Der Kopf von `build.sh:792` beschreibt genau diese Falle und sagt, dass
sie die Runde WERKZEUGE schon einmal zwei Anläufe gekostet hat. **Sie
hat sie diese Runde noch einmal gekostet** — der Kommentar war da, ich
hatte ihn nur nicht gelesen, bevor ich klickte.

### 4.4 Tabulatorzahlen im Startmenü sind kein Vertrag

Der erste Anlauf erreichte den Energieknopf mit vier Tabulatoren. Im
Mitschnitt stand daraufhin der **Texteditor**:

```
key: ^I  ^I  ^I  ^I
key: [enter]
[?25l[1;1H[7m  edit   New file  …
```

`launcher.fi` setzt den Fokus am Ende ausdrücklich auf das **Suchfeld**
(`wlib.set_focus(fe)`), und die Reihenfolge ist Beschriftung, Suchfeld,
Liste, „Ausführen", Energieknopf. Vom Suchfeld sind es **drei**
Tabulatoren — mit vier ist der Fokus wieder im Suchfeld, und die
Eingabetaste startet den ersten Treffer der Liste.

Eine Abnahme, die diese Reihenfolge mitzählt, misst die nächste
Umstellung des Startmenüs und nicht das Abmelden. Deshalb klickt
`pruef/abmelden.py` auf die **gemeldeten Koordinaten** — derselbe Weg
wie `pruef/oneshot.py` in der Runde ENERGIE.

### 4.5 Zwei Prozesse auf einer seriellen Leitung, zeichenweise verschränkt

Vier Zusagen waren rot, obwohl das Abmelden funktionierte. Der Grund
steht wörtlich im Mitschnitt:

```
6launcher: energie wahl= gemalt=216
taskbar: text button x=80 base=25 fg=abmelden: Sitzung uid988970 bg=16777215 t=
abmelden: Sitzung luaiudn=c1h0e0r0:
```

In der letzten Zeile stecken `abmelden: Sitzung uid=1000` und
`launcher:` **Buchstabe für Buchstabe** ineinander. Die Leitung hat kein
Schloss je Zeile, und mit `uitrace` schreibt die Taskleiste in diesem
Lauf 472 Zeilen dazwischen.

Dieselbe Falle hat die Runde ECHTHARDWARE-2 beschrieben (A1: *„wer das
vom Foto abliest, liest wlib und eine Zahl daneben"*). Die Abnahme
prüft jetzt auf den Teil **vor** der Stelle, an der sich zwei Zeilen
treffen können — und nimmt für die harte Zusage eine **andere Quelle**
(`signal: pid=… SIGKIL` aus `kernel/signal.fi`) als die Funktion, die
geprüft wird.

### 4.6 Und einer im eigenen Werkzeug: `cd "$(dirname "$0")/../.."`

Aus einem anderen Verzeichnis gerufen, stand `pwd` auf `/`, und jeder
Aufruf von `tools/osum/mkfs.py` schlug fehl — **ohne dass eine Zusage
es gesagt hätte**: fünf Prüfungen meldeten „Rechte falsch: ''" und
sahen wie ein Sachfehler aus. Jetzt `BASH_SOURCE` plus eine Prüfung,
dass `tools/osum/mkfs.py` wirklich da ist.

---

## 5. WAS OFFEN BLIEB

**5.1 `tools/install/abnahme.sh` (35/0) ist nicht nachgemessen.** Der
Läufer braucht QEMU-Läufe mit echten Platten und kopiert die Wurzel
rund **acht Minuten** (`docs/RUNDE-INSTALLER2.md` sagt das selbst,
Abschnitt „Was diese Runde NICHT behauptet"). Auf dieser Maschine
liefen drei weitere Runden parallel, und die Platte stand mehrfach bei
1,5 GB frei.

Die Runde hat `kernel/user/install.fi` **nicht angefasst**. Die
Änderung an `build.sh` betrifft zwei Verzeichniseinträge, und dass sie
ankommen, prüft die Pflichtliste bei **jedem** Bau (`RC=0`, 67 Pfade).
`tools/geraetekey/run.sh` — der Läufer, der in derselben Abnahme den
Gerätschlüssel prüft — ist **nachgemessen und grün (12/0)**. Das ist
ein starkes Argument, aber keine Messung von `abnahme.sh` selbst:
**wer merged, sollte sie fahren.**

**5.2 `argon` 35/0 nicht bestätigt.** Der serielle Nachlauf hat in
Abschnitt 7 eine Zusage rot gemeldet:

```
Argon2 (t=2, m=32 MiB, p=4): seriell 2047265154 Takte,
                             parallel 1450968816 Takte auf 4 Kernen
Faktor 1,41
FAIL  der Gewinn ist zu klein: Faktor 1,41
```

Das ist eine **Tempomessung**: sie vergleicht Argon2 seriell gegen
parallel auf vier Kernen und verlangt einen Mindestgewinn. Auf dieser
Maschine rechnen drei weitere Runden — genau die Sorte Zahl, die unter
Last fällt, und die einzige lastabhängige Zusage im ganzen Läufer.

**Die übrigen 34 Zusagen sind grün**, darunter die
Nachbarabschnitte, die `krypto` (**61/0**) und `aesni` (**31/0**) selbst
mitfahren. Die Runde hat an Argon2, `lib/crypto/` oder `pw.fi` **keine
Zeile** geändert — die Kennwortprüfung benutzt PBKDF2 aus `pw.fi`, nicht
Argon2.

**Ich sage es lieber so, als eine 35/0 zu behaupten, die ich nicht
gesehen habe.** Wer merged und die Maschine für sich hat, sollte den
Abschnitt einzeln nachfahren; fällt er dort auch, ist es ein echter
Punkt und keiner dieser Runde.

**5.3 Die Taskleiste läuft weiter als root.** Unverändert die Grenze aus
`docs/RUNDE-ANMELDUNG.md` §5.1. Der Kern startet sie selbst, und sie
schreibt `/etc/taskbar.conf`, liest `/proc` und startet über `SYS_EXEC`
weitere Programme. Nach dem Abmelden bleibt sie deshalb stehen — hier
ist das richtig (der Anmeldeschirm deckt sie zu), aber ein
Benutzerwechsel mit zwei Menschen bräuchte sie je Sitzung.

**5.4 Kein Wechsel des Benutzers, nur Abmelden.** Es gibt genau eine
Sitzung (`SP_UID` ist ein Wort, keine Liste). „Benutzer wechseln" —
zwei angemeldete Menschen gleichzeitig, umschaltbar — ist damit nicht
gebaut. `SP_UID` ist der erste Baustein.

**5.5 Der Sperrbildschirm ist in dieser Runde nicht neu gemessen.** Er
ist aus der Runde ANMELDUNG mit Bildern belegt
(`belege/anmeldung/A-abnahme-4-gesperrt.png`, Super+L, Entsperren,
`60596`/`60610`/`700` Stichproben) und diese Runde hat `lock.fi` nicht
angefasst. `abmelde_wache` räumt die Sperre mit — **dass Abmelden vom
gesperrten Schirm aus funktioniert, ist gebaut und begründet, aber
nicht gemessen.** Dafür bräuchte es einen Lauf, der erst sperrt und
dann abmeldet, und dort ist der Energieknopf nicht erreichbar (die
Sperre nimmt die Tastatur) — es bräuchte einen Weg vom Sperrschirm zum
Abmelden, und den gibt es nicht.

**5.6 `lock -d`, `-s`, `-an`, `-absturz` bleiben unerreichbar.**
Unverändert `docs/RUNDE-ANMELDUNG.md` §4.5/§5.3: `profile app` reicht
die Argumente nicht durch (firnc setzt dort sein eigenes `_start` ein).
Das ist ein Befund über den Baum, kein Schaden dieser Runde.

**5.7 Die Einschalttaste am Rechner.** Unverändert
`docs/RUNDE-ENERGIE.md` §7.1: `hw.fi::gpe_block_off` schaltet alle GPEs
beim Start ab, es gibt keinen SCI-Handler. Eigene Runde im Kern.

**5.8 Nur `firnc0`, nur QEMU, nur `uiscale=1`.** Gemessen wurde mit
`-accel kvm`, 1280×800, einer IDE-Platte. Echtes Blech, `firnc1` und
`uiscale=2` sind nicht Teil dieser Runde.

---

## 6. DIE REGEL FÜR DIE OBERFLÄCHE

Justins Vorgabe steht im Kopf von `tools/check-ui.sh`. Diese Runde hat
im Starter **nur den Weg hinter dem Menüpunkt getauscht** — eine
Funktion, die einen Systemaufruf macht statt einen `exec`. Kein
Bedienelement wurde angefasst, keine Zeichenfunktion angelegt, und der
Anmeldeschirm malt wie vorher mit `wlib.label`, `wlib.list`,
`wlib.entry`, `wlib.button`.

```
CHECK-UI PASSED.
  188 Dateien geprueft
  0 Programme malen sich ein Bedienelement selbst
  0 Programme greifen an der Bibliothek vorbei auf fUi zu
  0 Funktionen in wlib.fi malen an fUi vorbei
  0 Zeichenfunktionen im Kern malen an fUi vorbei
```

---

## 7. SPEICHER

**Zwei Wörter in der K11-Region, kein neuer Bereich, kein Modusbit.**
`SP_LOGOUT` auf `0x148` und `SP_LOGOUTS` auf `0x150`; `SP_UID` lag
bisher als letztes auf `0x140`, und `K11_MAX` ist **4096** Oktette ab
`K11_OFF = 0x3D000`. Die nächste Region beginnt bei `0x3F000`
(`TTF_OFF`) — es liegt also nichts in der Nähe.

`MODE_WORDS` bleibt unberührt: diese Runde hat **kein** neues Wort für
die Kernel-Kommandozeile gebraucht, sie benutzt das vorhandene
`anmeldung`.

---

## 8. DATEIEN

| Datei | was |
|---|---|
| `kernel/kstate.fi` | `SP_LOGOUT`, `SP_LOGOUTS` + `export` |
| `kernel/sys.fi` | `do_sperre` op 9 (Wunsch) und op 10 (Zähler) |
| `kernel/kgui.fi` | `abmelde_wache` + zwei Aufrufe, `import signal` |
| `kernel/user/launcher.fi` | `pw_abmelden` geht über den Kern |
| `tools/usbimg/build.sh` | `/users/justin/` + `config/` mit 0700:1000:1000, 2 neue Pflichtpfade |
| `tools/logind/run.sh` | die Abnahme der Runde (neu) |
| `pruef/abmelden.py` | Abmelden mit echten Mausklicks (neu) |
| `belege/logind/` | Bilder, Mitschnitte, Befunde |

---

## 9. ZUSTAND

`P-003` war schon erledigt und ist es weiter. `P-002` war zu drei
Vierteln erledigt; der Rest, der in `OFFEN.md` fehlte und in
`RUNDE-ANMELDUNG.md` als offen benannt stand, ist jetzt gebaut und
gemessen: **Abmelden beendet die Sitzung wirklich, und der
Anmeldeschirm kommt zurück** — bewiesen mit zwei unabhängigen Quellen
im Mitschnitt und mit drei Bildern, von denen zwei sich um 0,04 %
unterscheiden.

**Für `OFFEN.md`** wäre nach einem Merge zu ändern: `P-002` von
*„teilweise / P1"* auf **erledigt**, mit dem Hinweis, dass der
Benutzerwechsel (5.4) und die Taskleiste als root (5.3) als eigene,
kleinere Punkte weiterleben.
