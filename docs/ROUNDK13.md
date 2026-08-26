# Runde K13 — Benutzer, Rechte und `init`

Zweig `k13-user`, Arbeitsbaum `../osum-k13-user`, abgezweigt von `main`
(7a53ac3). Zahlenvorrat dieser Runde: kdata-Seiten `0x41000..0x43000`,
Systemaufrufnummern 1600..1699, Ring-3-Programmnummern `P_*` 16 und 17,
Deskriptorarten `K_*` 10 und 11, `test.sh` Abschnitt 19, Testläufer
`tools/k13/`.

Vor dieser Runde hatte Osum keine Benutzer. Jeder Prozess durfte jede
Datei lesen und überschreiben, es gab kein `chmod`, kein Anmelden, und
der Kern startete unmittelbar `/bin/sh` — es gab keinen ersten Prozess,
also auch keinen Ort, an dem ein `login` hätte laufen können.

---

## 1. Was jetzt da ist

**Kennungen je Prozess.** Sieben Wörter im Aufgabensatz (`sched.fi`,
392..447): echte, wirksame und gesicherte Benutzer- und Gruppenkennung
plus `umask`. Sie liegen im **Aufgabensatz** und nicht in einem eigenen
Bereich von `kdata` — der Satz ist seit Runde K4 512 Oktette groß und war
bis 384 belegt. Vererbt werden sie in `sched.create`, also für **jede**
Art, einen Prozess zu erzeugen: `fork`, `execve`, `SYS_OSUM_SPAWN` und
`proc.create` gehen alle dort durch.

**Systemaufrufe**, mit den Nummern von Linux x86-64:
`getuid` 102, `getgid` 104, `setuid` 105, `setgid` 106, `geteuid` 107,
`getegid` 108, `setreuid` 113, `setregid` 114, `setresuid` 117,
`getresuid` 118, `setresgid` 119, `getresgid` 120, `chmod` 90, `fchmod`
91, `chown` 92, `fchown` 93, `lchown` 94, `umask` 95, `access` 21,
`fchownat` 260, `fchmodat` 268, `faccessat` 269, `reboot` 169. Dazu
**eine** eigene Nummer aus dem zugeteilten Vorrat: `SYS_OSUM_USERINFO`
= 1600, die die Zähler dieser Runde nach Ring 3 gibt. Damit sind es
79 + 24 = **103 deklarierte Systemaufrufe**.

**Rechte und Eigentümer im Inode.** OFS trägt seit dieser Runde `mode`,
`uid` und `gid` (Abschnitt 3 erklärt, woher der Platz kommt).

**Die Prüfung an einer Stelle.** `kernel/perm.fi`, Funktion `may_ids`.
Sie wird aus fünf Toren gerufen — `open`, `mkdir`, `unlink`, `chdir` und
`execve` (über `elf.build`) — und es gibt keine zweite Fassung dieser
Regel im Baum. `access` benutzt dieselbe Funktion mit den **echten**
statt den wirksamen Kennungen, wie POSIX es verlangt; das ist ein
zweiter Eingang, kein zweites Regelwerk.

**Werkzeuge in Ring 3:** `id`, `whoami`, `chmod` (oktal **und**
Buchstabenform), `chown`, `su`, `passwd`, `login`, `init`, `svc` — und
`k13t`, der Selbsttest dieser Runde. Damit sind es **62 Programme** in
Ring 3.

**`/sbin/init` als Prozess 1.** Der Kern startet ihn statt der Shell,
er liest `/etc/inittab`, startet Dienste, startet abgestürzte neu, nimmt
Waisen an und fährt die Maschine über **echtes ACPI** herunter.

---

## 2. Die Zahlen

`bash tools/k13/run.sh` → **99 Zusagen, 0 Fehler** (Abschnitt 19 von
`./test.sh`). Der Gesamtlauf: **19 Abschnitte, 1585 Zusagen, 0 Fehler**
— die 1486 Zusagen von `main` plus die 99 dieser Runde, und keine
einzige verloren.

| Was | Gemessen |
|---|---|
| SHA-256("abc") in Firn | `ba7816bf…f20015ad`, identisch mit FIPS 180-4 und Pythons `hashlib` |
| HMAC-SHA256 in Firn | identisch mit Pythons `hmac` |
| PBKDF2-HMAC-SHA256, 2048 Runden | identisch mit Pythons `hashlib.pbkdf2_hmac` |
| Rechtefragen im Lauf `rechte.sh` | 177, davon 2 abgelehnt |
| setuid-Bit gegriffen im selben Lauf | 6 mal |
| tiefster Kernstapel, `main` | 14224 von 16384 Oktetten |
| tiefster Kernstapel, diese Runde | 14560 von 16384 Oktetten (+336) |
| Dateigröße höchstens, vorher | 2.135.552 Oktette |
| Dateigröße höchstens, jetzt | 2.134.016 Oktette (−1536, −0,07 %) |
| Bereiche in `kdata` | 44, 0 Kollisionen (`tools/kernel/karte.py`) |

---

## 3. Das Dateisystem: woher der Platz kam

**Der Inode war voll.** 128 Oktette, und jedes hatte einen Besitzer:
Art (0), Größe (8), Verweise (16), elf direkte Blockzeiger (24..111),
der einfach indirekte (112), der doppelt indirekte (120). Es gab kein
freies Wort für Rechte, Eigentümer und Gruppe.

Die einzige Reihe mit Luft war die der direkten Zeiger. **Drei davon
sind jetzt `I_MODE` (88), `I_UID` (96) und `I_GID` (104)**, also
`DIRECT` = 8 statt 11. Was das kostet, ist genau ausrechenbar:

    vorher   (11 + 64 + 64*64) * 512 = 2.135.552 Oktette
    jetzt    ( 8 + 64 + 64*64) * 512 = 2.134.016 Oktette

1536 Oktette weniger, 0,07 %. Die Schwelle, ab der eine Datei durch den
indirekten Block geht, sinkt von 5632 auf 4096 Oktette. Das größte
Programm dieses Userlands ist rund 107 KiB groß; es war schon vorher
weit über der Schwelle.

**Die Fassungsnummer, und warum sie sein muss.** Ein Abbild der alten
Fassung, mit den neuen Regeln gelesen, liest den **neunten Blockzeiger
als Rechtebits** und schreibt Rechtebits als Blocknummer. Also trägt der
Superblock seit dieser Runde bei Offset 64 eine Fassungsnummer.

Der Superblock war bis Oktett 63 belegt und dahinter Null — **eine Null
heißt deshalb „Fassung 1"**, und jedes Abbild, das vor dieser Runde
gebaut wurde, sagt damit von selbst das Richtige, ohne dass es jemand
anfassen müsste. Das ist die ganze Rückwärtsverträglichkeit, und sie
kostet ein Wort.

Ein Abbild der Fassung 1 wird weiter eingehängt und ist vollständig
lesbar. Rechte trägt es nicht; `fs.inode_mode` antwortet dort mit
**0o755 für alles** und `uid`/`gid` mit 0. Das ist bewusst so und nicht
0o644: vor dieser Runde hatte dieses Dateisystem **keine** Rechte, jede
Datei war ausführbar, und ein `/bin/sh` mit 0o644 wäre in einem alten
Abbild plötzlich kein Programm mehr — der Kern könnte sein eigenes
Userland nicht mehr starten. `chmod` auf ein solches Abbild gibt
`-EROFS`, und das ist die Wahrheit: dort ist kein Platz dafür.

**Gegenprobe** (`ofsv2raw`): dasselbe Abbild der Fassung 1, mit den
Regeln der Fassung 2 gelesen. Die Programme starten nicht mehr, `id`
gibt nichts aus — die Messung bricht zusammen. Ohne diese Gegenprobe
wäre „die Fassungsnummer wird beachtet" eine Behauptung.

---

## 4. Die Rechteprüfung

Die Regel ist die von Unix und absichtlich nicht klüger:

1. Wirksame Kennung 0 → lesen und schreiben immer. **Ausführen nur, wenn
   irgendein Ausführungsbit gesetzt ist** — root darf keine Textdatei
   starten.
2. Sonst entscheidet **genau eine** der drei Dreiergruppen: Besitzer,
   sonst Gruppe, sonst Rest. Nicht die Vereinigung — eine Datei 0o077
   ist für ihren Besitzer wirklich verschlossen.
3. Gefragt wird mit der **wirksamen** Kennung. Genau das ist der Sinn
   des setuid-Bits.

Beim Anlegen bekommt eine Datei 0o666, ein Verzeichnis 0o777, jeweils
abzüglich der `umask` des Prozesses, und sie gehört seinen wirksamen
Kennungen (`perm.on_create`). Beim Löschen und Anlegen wird das
**Verzeichnis** gefragt, nicht die Datei — deshalb kann man unter Unix
eine schreibgeschützte Datei löschen, wenn einem der Ordner gehört.

**Gemessen wird differentiell**: dasselbe Programm (`k13t`), dieselben
Dateien, in einem einzigen Lauf zweimal — einmal als root, einmal nach
`su justin`:

| | root | justin |
|---|---|---|
| eigene Datei 0o600 öffnen | 1 | 1 |
| dieselbe Datei mit 0o000 öffnen | 1 (Regel 1) | **0** |
| `/etc/shadow` (0o600, root) lesen | 1 | **0** |

**Gegenprobe** (`noperm`): derselbe Kernel, dieselben Dateien, `may`
sagt immer ja. Beide Nullen werden zu Einsen — und der Zähler der
Ablehnungen steht trotzdem über null, weil `noperm` erst **nach** dem
Zählen umbiegt. Gezählt wird, nur nicht gewirkt.

Was `chmod`/`chown` getan haben, liest der Wirt **aus dem Abbild**
zurück (`mkfs.py meta`), nicht aus einem Mitschnitt der seriellen
Leitung:

    /w/root.txt     4755 0 0        (chmod 4755)
    /w/rootneu.txt   640 1000 1000  (chmod 640 + chown justin:justin)
    /w/ju.txt        644 1000 1000  (von justin angelegt)

---

## 5. Das Passwort

`/etc/passwd` und `/etc/shadow` im gewohnten Format. Das `x` in der
zweiten Spalte heißt seit den achtziger Jahren „das Passwort steht
woanders", und genau darum geht es: `/etc/passwd` darf jeder lesen,
`/etc/shadow` niemand außer root.

**PBKDF2-HMAC-SHA256 (RFC 2898)** mit acht Oktetten Salz aus
`getrandom`, 2048 Runden, 32 Oktette Ausgabe:

    $osum1$2048$<16 Hexziffern Salz>$<64 Hexziffern>

SHA-256, HMAC und PBKDF2 sind in Firn geschrieben (`kernel/user/pw.fi`).
Dass es die richtigen sind, wird **nicht behauptet, sondern gemessen**:
der Wirt schickt dieselben Eingaben durch Pythons `hashlib`, `hmac` und
`hashlib.pbkdf2_hmac` und hält die 64 Hexziffern Zeichen für Zeichen
dagegen. Alle drei stimmen.

`passwd` schreibt wirklich: nach dem Lauf liest der Wirt `/etc/shadow`
aus dem Plattenabbild, zerlegt den Eintrag und rechnet ihn mit Python
nach — aus dem **neuen** Passwort kommt derselbe Wert heraus, aus dem
**alten** ein anderer, und das Klartextpasswort steht nirgends in der
Datei.

Der Vergleich läuft in konstanter Zeit (`same_dk`), und ein unbekannter
Benutzername wird trotzdem gegen einen Blindeintrag geprüft — sonst wäre
an der Antwortzeit zu sehen, welche Namen es gibt.

**Was daran zu klein ist, und das ist ehrlich zu sagen:** 2048 Runden
sind für heutige Verhältnisse wenig. glibc nimmt 5000 bei `sha512crypt`,
und die gängige Empfehlung für PBKDF2-HMAC-SHA256 liegt bei
Hunderttausenden. Der Grund ist gemessen: dieses System läuft in einer
Softwareemulation, und eine Anmeldung kostet hier schon bei 2048 Runden
spürbar Zeit. Die **Bauart** ist richtig — Salz, Iteration, die
Rundenzahl steht **im Eintrag** und lässt sich erhöhen, ohne dass ein
bestehendes Passwort ungültig wird. Die **Zahl** ist zu klein.

Nicht gemacht: eine speicherharte Ableitung (scrypt, Argon2). Die
bräuchte einen Allokator, und ein Programm dieses Userlands hat keinen.

---

## 6. Der erste Prozess

`/etc/inittab`, eine Zeile je Dienst:

    name:art:befehl arg arg

`art` ist `once`, `respawn`, `ctrl` oder `off`. `ctrl` gibt es in keinem
echten Unix und der Grund steht hier: dieses System wird **gemessen**,
und ein Lauf, der nie endet, ist ein Lauf ohne Ergebnis. `ctrl` sagt
„wenn dieses Programm fertig ist, ist der Lauf fertig".

Vier Aufgaben, und nur diese vier: Dienste starten, Waisen einsammeln,
abgestürzte Dienste neu starten (höchstens fünfmal je Sekunde) und beim
Herunterfahren aufräumen — SIGTERM an alle, zwei Sekunden warten und
dabei weiter einsammeln, SIGKILL an die Reste, dann ACPI.

**`svc` verständigt sich über zwei Dateien**, nicht über Signale: ein
Signal trägt keine Nutzlast, und dieses System hat weder Sockets im
Dateisystem noch `mkfifo`. `/run/svc.cmd` ist der Auftrag, `/run/svc.state`
der Zustand. Das ist langsamer (init sieht es binnen 50 ms) und dafür
nachvollziehbar: was gewollt war und was daraus wurde, steht beides auf
der Platte.

**pid 1 musste getauscht werden.** Sie gehörte seit Runde 62 der
Bootaufgabe. Beim Start von `/sbin/init` nimmt die Bootaufgabe jetzt die
nächste freie Nummer, der Zähler geht auf 1, und die Aufgabe, die gleich
entsteht, bekommt sie; danach läuft der Zähler dort weiter, wo er war.
**Das geschieht nur, wenn wirklich ein `/sbin/init` auf der Platte
liegt** — jedes Abbild der Runden K1 bis K12 hat keines, und dort ändert
sich keine einzige Zahl.

**Waisen.** Stirbt ein Prozess mit Kindern, hängt `sched.reparent` sie
an den Prozess 1. Gemessen: `k13t waise` spaltet ein Kind ab und endet
sofort; init meldet am Ende `init: orphans=1`, und die Zahl der Leichen
ist 0.

**Die Gegenprobe dazu ist der Kern selbst**, ohne Userland: derselbe
Vorgang als Ring-3-Programm (`k13run zombie`), ohne einen Prozess 1.
Ergebnis `k13: zombies=0 after=1` — die Leiche bleibt stehen. Ohne init
steigt die Zahl nachweislich.

**Die Abschaltung ist wirklich ACPI.** `power.acpi_off` sucht die FADT
über RSDP/XSDT, liest `PM1a_CNT_BLK` und findet `\_S5_` in der DSDT
(Suche nach den vier Oktetten, dann das Paket von Hand gelesen). Der
Beweis steht im **Beendigungscode von QEMU**: eine ACPI-Abschaltung
ergibt 0, der Ausgang des Prüfstands (`isa-debug-exit`) ergibt 21. Mit
`noacpi` derselbe Lauf, derselbe Ablauf — und 21. Ohne diesen
Unterschied wäre „es schaltet über ACPI ab" nicht prüfbar.

**Der Notweg** ist geprüft: `initsh` auf der Kommandozeile startet
`/bin/sh` wie vor dieser Runde, und liegt gar kein `/sbin/init` auf der
Platte, geschieht dasselbe von selbst und es steht eine Zeile darüber
auf der seriellen Leitung.

**Und die Anmeldung läuft wirklich durch die Konsole:** init startet
`/bin/login`, das den Namen und das Passwort Oktett für Oktett von
Deskriptor 0 liest (mit abgeschaltetem Echo, wenn dort ein Terminal
hängt), die Rechte ablegt und zur Shell wird. Gemessen an dem, was
danach `id` sagt: `uid=1000(justin) gid=1000 euid=1000(justin)`. Mit
einem falschen Passwort kommt dreimal „Anmeldung falsch" und niemand
herein.

---

## 7. Was NICHT geht — die Grenzen dieser Runde

1. **Das Betretungsrecht wird nicht auf jedem Glied eines Pfades
   geprüft.** Geprüft werden das Ziel und das **letzte** Verzeichnis.
   `/a/b/c` mit `a` = 0o000 und `b` = 0o755 wird also geöffnet, obwohl
   Unix es verböte. Der Grund ist der Modulgraph: `fs.path` löst den
   Pfad auf und kennt keine Aufgabe, und `fs.fi` darf `perm.fi` nicht
   einbinden, weil `perm.fi` `fs.fi` einbindet. Das ist eine echte
   Lücke, keine Vereinfachung.
2. **Es gibt keine Nebengruppen.** Ein Prozess hat genau eine Gruppe;
   `getgroups`/`setgroups` fehlen, `/etc/group` gibt es nicht. `chown
   name:gruppe` löst die Gruppe über `/etc/passwd` auf.
3. **`passwd` schreibt `/etc/shadow` ohne Zwischendatei.** Dieses
   Dateisystem hat kein `rename`. Fällt der Strom mitten im Schreiben
   aus, ist die Datei halb.
4. **`login` merkt sich Fehlversuche nicht über seine eigene
   Lebensdauer hinaus** und wartet nach einem Fehlversuch nicht. Beides
   gehört zu einer ernsthaften Anmeldung.
5. **`su` kennt kein `-c`.** Die Shell dieses Systems kennt es nicht;
   `su NAME BEFEHL ARG...` nimmt den Befehl unmittelbar.
6. **2048 Runden PBKDF2 sind zu wenig** (Abschnitt 5).
7. **Das Sticky-Bit wird gelesen und geschrieben, aber nicht beachtet.**
   In `/tmp` mit 0o1777 darf hier jeder alles löschen.
8. **`init` hat höchstens acht Dienste** und zerlegt einen Befehl in
   höchstens vier Wörter. Beides sind feste Puffer, weil es keinen
   Allokator gibt.
9. **Die `\_S5_`-Suche in der DSDT ist kein AML-Interpreter.** Eine
   Firmware, die das Objekt in einem `If` versteckt oder über eine
   Methode berechnet, wird nicht gefunden; dann meldet `off_reason` 3
   und der Aufrufer nimmt seinen Notweg. Gemessen wurde auf QEMU
   (PIIX4), wo `PM1a_CNT_BLK` = 0x604 und `SLP_TYPa` = 0 ist.
10. **Die Deskriptorarten `K_*` 10 und 11 waren zugeteilt und werden
    nicht gebraucht.** Rechte hängen am Inode, nicht am Deskriptor; es
    gab nichts, wofür eine neue Art die richtige Antwort gewesen wäre.

---

## 8. Drei Dinge, die schiefgingen, und was sie gekostet haben

**Ein Wort, das zu kurz war.** Die Kommandozeile wird nach **Teilworten**
durchsucht (`kmain.find`). Das Wort dieser Runde hieß zuerst `k13` — und
`script=k13t` enthält `k13`. Damit lief bei jedem Lauf des Selbsttests
zusätzlich der Ring-3-Test der Runde mit, den niemand angefordert hatte,
und der Lauf endete mit `lock: stuck id=0 owner=1`. Das sah eine halbe
Stunde lang wie eine Verklemmung im Scheduler aus. Es war keine. Das
Wort heißt jetzt `k13run`.

**5104 Oktette in einer Funktion.** `sys.dispatch` ist **eine** Funktion
mit über hundert Zweigen, und firnc gibt jedem Zwischenwert jedes
Zweiges einen eigenen Platz auf dem Stapel — ihr Rahmen war schon vorher
5104 Oktette groß. Die fünfundzwanzig neuen Aufrufe dieser Runde als
Zweige darin ließen ihn auf 6864 wachsen, und der tiefste Kernstapel
eines Laufs stieg von 14224 auf **16128 von 16384** Oktetten. 112
Oktette Luft.

Gefunden wurde das nicht durch Nachdenken, sondern durch Nachrechnen:
`objdump -d` über beide Abbilder, `sub $N,%rsp` je Funktion, die
Differenz sortiert. Behoben in drei Schritten — die Zweige in eine
eigene Funktion `k13_call` (wie `vm_call` seit K12), der
Ausgabepuffer von `do_userinfo` in `kdata` statt auf den Stapel, und die
Rechteentscheidung von `do_open` in zwei kleine Hilfsfunktionen.
Ergebnis: **14560 von 16384**, also +336 gegenüber `main` statt +1904.

**Ein Suchen-und-Ersetzen, das zu weit griff.** Beim Umbau von
`do_userinfo` (der Ausgabepuffer sollte von `w[i] = …` auf `kdata`
umgestellt werden) lief eine Ersetzung über die **ganze** Datei
`kernel/sys.fi` — und traf damit auch `do_vm_stat`, die Auskunft des
Hypervisors aus Runde K12: ihre fünf Zeilen schrieben danach in **meinen**
`kdata`-Bereich statt in das Feld, das gleich darauf nach Ring 3 kopiert
wurde. Der Kernel-Teil des Hypervisors blieb dabei vollständig grün
(22/22 Zusagen, alle sechs Gäste), nur das Programm in Ring 3 bekam
Nullen: `state=0 exits=0 result=0` statt `3/23/4660`, 11 von 14 Zusagen.

Gefunden hat es **Abschnitt 18 von `./test.sh`**, nicht ich — und genau
deshalb steht in diesem Projekt die Regel, dass am Ende der ganze Lauf
durchgeht und nicht nur der eigene Abschnitt. Eine Runde, die nur ihren
eigenen Testläufer laufen lässt, hätte das nicht bemerkt.

---

## 9. Wie man es nachvollzieht

    bash tools/k13/run.sh            # Abschnitt 19 allein
    ./test.sh                        # alle 19 Abschnitte
    python3 tools/kernel/karte.py kernel -v   # die Speicherkarte

Ein System von Hand starten:

    qemu-system-x86_64 -kernel osum.img -m 128 \
        -append "osum script=justin;geheim12;id" \
        -drive file=disk.img,format=raw,if=ide,index=0

Die Wörter dieser Runde auf der Kommandozeile: `k13run` (Selbsttest in
Ring 3), `zombie` (die Waise dazu), `noperm`, `nosuid`, `noacpi`,
`ofsv2raw`, `initsh`.
