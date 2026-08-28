# Runde MULTIUSER — Mehrbenutzerbetrieb, damit Osum als Serverbetriebssystem taugt

Zweig `multiuser`, abgezweigt von `mergeline` (4f844b5). Nicht nach
`main` gemergt.

---

## 0. Der Befund, und warum er dem Auftrag widerspricht

Der Auftrag sagt: *„Es gibt kein /etc/passwd, keine Anmeldung, keine
Trennung von Rechten zwischen Nutzern."* und *„prüfe zuerst genau, was
davon echt ist und was nur Namensgleichheit."*

Nachgemessen, und das Ergebnis ist ein anderes: **Runde K13 (26.08.2026)
hat Benutzer, Rechte und die Anmeldung gebaut, und sie ist über
`k-merge2` → `main` → `mergeline` längst eingeflossen.**

    $ git merge-base --is-ancestor k13-user mergeline && echo ja
    ja
    $ bash tools/k13/run.sh
    K13: 99 passed, 0 failed

Auf `mergeline` standen vor dieser Runde bereits: `T_UID`…`T_UMASK` im
Aufgabensatz (echt/wirksam/gesichert je Benutzer und Gruppe, vererbt in
`sched.create`), 24 Linux-Aufrufnummern für `setuid`/`setgid`/`setres*`,
`mode`/`uid`/`gid` im OFS-Inode, `kernel/perm.fi` als die eine Stelle für
„darf er?", `/etc/passwd`, `/etc/shadow` mit PBKDF2-HMAC-SHA256, und
`login`, `su`, `passwd`, `id`, `chmod`, `chown`.

**Die Beschreibung im Auftrag ist die von `main` VOR K13.** Was fehlte,
steht in `docs/ROUNDK13.md` Abschnitt 7 als ehrliche Grenzenliste — und
genau diese Liste ist der Auftrag dieser Runde geworden.

---

## 1. Die Lücke, auf die es ankommt: das Betretungsrecht

### Was war

`kernel/sys.fi:dir_allowed` (Runde K13) fragt nach dem **unmittelbaren**
Elternverzeichnis einer Datei. Bei `/geheim/inhalt.txt` wird `/geheim`
gefragt — das hielt also schon. Bei `/zu/tief/inhalt.txt` wird `/zu/tief`
gefragt, und **`/zu` nie**.

Der Kommentar, der seit K13 in `do_open` stand:

> *„WAS HIER NICHT GEPRÜFT WIRD […]: das Betretungsrecht auf JEDEM Glied
> eines langen Pfades. […] Der Grund ist der Modulgraph — `fs.path` löst
> den Pfad auf und kennt keine Aufgabe, und `fs.fi` darf `perm.fi` nicht
> einbinden, weil `perm.fi` `fs.fi` einbindet. Das ist eine echte Lücke
> und keine Vereinfachung."*

Auf einem Serverbetriebssystem ist das kein Schönheitsfehler: ein
Heimverzeichnis mit `0700` schützt sein Inneres nur bis zur ersten
Unterebene.

### Was jetzt ist

`perm.walk(state, t, path)` in `kernel/perm.fi`. **Der Modulgraph war
nicht das Hindernis** — die Prüfung muss nicht *in* `fs.resolve` stehen.
Sie steht in dem Modul, das `fs` ohnehin einbindet und das die Aufgabe
kennt, und läuft den Pfad ein zweites Mal ab, bevor der Aufrufer ihn
auflöst.

Zerlegt wird **ohne Puffer**: die Zeichenkette wird an jedem
Schrägstrich vorübergehend abgeschnitten (eine Null hineingeschrieben),
`fs.path` darauf losgelassen und das Zeichen zurückgeschrieben.
`fs.resolve` kopiert in seinen eigenen Arbeitspuffer, also sieht niemand
die Null außer dieser Schleife.

Gerufen an **zwölf** Stellen in `sys.fi`: `open`, `unlink`, `mkdir`,
`stat`, `lstat`, `symlink`, `readlink`, `utimensat`, `chdir`, `ftype`,
`fopen`, `ino_of_path` (also auch `chmod`, `chown`, `access`) — plus
beide Pfade von `rename`.

Gegenprobe: `nowalk` auf der Kommandozeile. Gezählt wird weiter, gewirkt
nicht — also genau der Zustand vor dieser Runde, und der Testläufer hält
beide Läufe gegeneinander.

---

## 2. Zusatzgruppen

`/etc/group` im klassischen Format (`name:x:gid:mitglied,mitglied`) gab
es nicht. Ein Benutzer hatte genau **eine** Gruppe, und „gemeinsam an
einer Datei arbeiten" hieß damit entweder `0666` oder gar nicht.

* `getgroups` = **115**, `setgroups` = **116** — die echten
  Linux-x86-64-Nummern. K13 hat 113, 114 und 117…120 belegt und diese
  beiden ausgelassen.
* `setgroups` ist **root vorbehalten**. Wer sich selbst eine Gruppe geben
  darf, hat keine Gruppen.
* `perm.may_attr` fragt Haupt- **und** Nebengruppen, in der Reihenfolge
  von POSIX (Besitzer, dann Gruppe, dann Rest — immer nur *eine* der drei
  Dreiergruppen, nicht ihre Vereinigung).
* `login` und `su` rufen `pw.initgroups` **vor** `setgid`/`setuid`.
  Danach ist der Prozess kein root mehr und dürfte es nicht.
* `id` schreibt `groups=2000(projekt)` — aber nur, wenn es welche gibt;
  eine leere Liste hinzuschreiben wäre eine Zeile, die aussieht wie eine
  Antwort und keine ist. Damit bleibt die Ausgabe für jeden Prozess ohne
  Zusatzgruppen Oktett für Oktett die von K13.

### Wo die Liste liegt, und warum nicht im Aufgabensatz

K13 hat zwölf Zeilen darauf verwendet zu begründen, dass ein
Prozessattribut in den Satz des Prozesses gehört. Die Begründung stimmt
weiter — der Platz nicht:

    TASK_BYTES = 512
    K13   392..440   (T_UID .. T_UMASK)
    K16   448        (T_BIG)
    NETVIEW 448..503 (T_NETV, T_NETOK mit sechs Wörtern)
    frei: GENAU EIN WORT, 504.

Sechzehn Zusatzgruppen brauchen sechzehn. Also steht im Satz die
**Anzahl** (`T_NGROUPS` bei 504, null nach `sched.create` — ein Prozess
von vor dieser Runde verhält sich exakt wie vorher), und die Kennungen
stehen in `kstate.MU_OFF + MU_GRP` (`MAX_TASKS × 16 × 8 = 4096` Oktette,
genau eine Seite). Die Gefahr, die K13 beschreibt — eine zweite Tabelle,
die jemand zu leeren vergisst — ist damit nicht weg, sondern benannt: es
gibt genau eine Stelle, die füllt (`sched.groups_inherit`, neben den
sieben Zeilen von K13), und genau eine, die leert
(`sched.groups_clear`).

Gegenprobe: `nogroups`. Die Liste wird gesetzt, aber nicht beachtet — die
Datei, die nur über eine Nebengruppe zu haben war, bleibt zu.

---

## 3. Rechte über die VFS-Schicht

`sys.open_vfs` hatte **keine einzige Zeile Rechteprüfung**. `do_open`
fragt seit K13 `perm.may`, bevor es eine Datei der Wurzel herausgibt;
der Weg jeder eingehängten Platte, jedes `/proc`-Eintrags und jedes
Geräts in `/dev` fragte nicht. Eine OFS-Partition hinter einem
Einhängepunkt war damit für jeden offen, obwohl in jedem ihrer Inodes
Rechte und ein Eigentümer standen.

Dafür braucht die Ops-Tafel zwei Attribute mehr:

    kernel/vfsops.fi   A_UID = 9, A_GID = 10
    kernel/ofs.fi      -> fs.inode_uid / fs.inode_gid
    kernel/fat.fi      -> 0 / 0, und im Quelltext steht, warum

Die Regel bleibt **eine**: `perm.may_attr(state, t, mode, owner, group,
want, id, gid)`. `may_ids` holt die drei Zahlen aus der OFS-Inode,
`sys.vfs_may` aus `vfs.v_attr`. Zwei Eingänge, ein Regelwerk.

### FAT32 — dokumentiert statt gefälscht

FAT32 kennt ein Attributoktett mit fünf Bits (nur-lesen, versteckt,
System, Datenträger, Verzeichnis) und **kein Feld für eine Kennung**.
Das Format kommt aus einer Welt, in der ein Rechner einem Menschen
gehörte.

Was hier **nicht** gemacht wird: die Kennung des Einhängenden eintragen
(Linux tut das mit `-o uid=`, und es ist dort eine *Einhängeoption* und
kein Dateiattribut). Eine erfundene Zahl wäre schlimmer als eine
ehrliche Null — sie sähe aus wie eine Rechteverwaltung, und die Datei
kann trotzdem jeder lesen, der das Dateisystem eingehängt bekommt.

Es gilt also: auf FAT32 gehört alles root, Verzeichnisse sind `0755`,
Dateien `0644` (nur-lesen: `0444`). **Jeder darf lesen, nur root darf
schreiben.** Wer Rechte braucht, nimmt OFS. Das steht so in
`kernel/fat.fi` bei `f_attr`.

---

## 4. Der Kostenfaktor — gemessen, nicht abgeschrieben

K13 nahm PBKDF2-HMAC-SHA256 mit **2048** Runden und schrieb selbst
hinein, dass das zu wenig ist. Diese Runde ersetzt die Zahl nicht durch
eine schönere, sondern durch eine gemessene.

### Die Messung

`kernel/user/mut.fi`, Unterbefehl `mut kdf <runden>`: es misst genau
das, was eine Anmeldung tut — `pbkdf2` über ein Passwort —, dreimal, und
nennt die **kleinste** Zeit. Nicht den Mittelwert: ein Ausreißer nach
oben ist der Zeitgeber oder ein anderer Prozess, ein Ausreißer nach
unten kann es nicht geben.

Wirt: AMD EPYC 7571, 12 Kerne, QEMU 7.2.22 (Debian).

| Umgebung | Runden/s | 8192 Runden |
|---|---:|---:|
| Osum, `-accel kvm -cpu host`, ruhige Maschine | **31.437** | **0,26 s** |
| Osum, TCG (Softwareemulation) | **4.430** | **1,85 s** |
| derselbe Wirt, OpenSSL hinter Pythons `hashlib` | **1.768.429** | 0,0046 s |

(Die Zahlen im Abnahmelauf liegen niedriger, weil auf derselben Maschine
gleichzeitig weitere Runden liefen — `load average` 17. Der Läufer prüft
deshalb nicht auf einen festen Wert, sondern auf eine *untere Schranke*
und auf das **Verhältnis** 2048 : 8192, das 1 : 4 sein muss.)

### Was daraus folgt

1. **8192 Runden = 0,26 s** auf echter Hardware. Das ist das
   Zeitbudget, das man einer Anmeldung zumuten kann, und es ist das,
   worauf die übliche Empfehlung („wähle den Kostenfaktor so, dass eine
   Prüfung eine viertel Sekunde dauert") hinausläuft.
2. Gegenüber 2048 ist das **Faktor 4**.
3. **Ein Angreifer rechnet nicht mit diesem Code.** OpenSSL ist auf
   demselben Rechner **56× schneller** als dieses SHA-256 in Firn (keine
   SIMD-Befehle, 32-Bit-Wörter in `u64` mit Maske). Bei 8192 Runden
   schafft ein Kern rund **216 Rateversuche je Sekunde**, 32 Kerne rund
   6.900. Das ist der ehrliche Wert dieser Zahl — und der Grund, warum
   diese Runde **zusätzlich** die Verzögerung baut: gegen ein gestohlenes
   `/etc/shadow` hilft der Kostenfaktor, gegen Durchprobieren an der
   Anmeldung kaum.

### Warum nicht 600.000

Die Empfehlung von 600.000 Runden für PBKDF2-HMAC-SHA256 ist für eine
Umsetzung geschrieben, die eine halbe Million Runden in einer drittel
Sekunde schafft. Hier wären es **19 Sekunden je Anmeldung**. Eine Zahl
abzuschreiben, ohne die Maschine darunter zu messen, wäre
Sicherheitstheater.

Stattdessen ist die Zahl **verstellbar**: `/etc/login.conf` mit
`kdf_runden = N`. Ein Wert, den man nur durch Neuübersetzen ändern kann,
wird nie geändert. Die Obergrenze in `check_hash` lag bei 100.000 —
*unter* dem, was heute empfohlen wird — und liegt jetzt bei 10.000.000;
sie ist eine Notbremse gegen einen verdorbenen Eintrag, nicht eine
Vorgabe.

### Warum nicht Argon2id

Der Auftrag zieht Argon2id vor. Es ist **nicht** gebaut, und der Grund
steht hier und nicht zwischen den Zeilen:

* Argon2id ist **speicherhart** — das ist sein ganzer Sinn und genau
  das, was die 56× gegenüber einer optimierten Umsetzung
  zusammenschrumpfen ließe.
* Es braucht dafür einen **Speicherblock** (üblich: 64 MiB), und ein
  Programm dieses Userlands hat **keinen Allokator** — weder `malloc`
  noch `brk` in `ulib`. Ein festes Feld wäre machbar.
* Darunter braucht es **BLAKE2b**. Das ist eine zweite Hashfunktion, die
  geschrieben *und* gegen die Vektoren aus RFC 7693 und RFC 9106
  gemessen werden müsste — eine Hashfunktion, die „ungefähr stimmt",
  ist schlimmer als keine.

Das ist Arbeit für eine eigene Runde und keine Zeile, die man
nebenherschreibt. **Die Form des Eintrags ist darauf vorbereitet:**
`$osum1$` ist eine Kennung des *Verfahrens*, und ein `$osum2$` daneben
ändert an keinem bestehenden Eintrag etwas — `check_hash` liest
Verfahren, Rundenzahl und Salz aus dem Eintrag selbst.

---

## 5. Die Anmeldung

### Die Verzögerung, und sie verdoppelt sich

K13 schrieb: *„es zählt Fehlversuche nicht über seine eigene Lebensdauer
hinaus und wartet nach einem Fehlversuch nicht."*

Jetzt: nach dem ersten Fehlversuch 1 s, nach dem zweiten 2 s, nach dem
dritten 4 s, gedeckelt bei einer Minute. Der Deckel ist kein
Zugeständnis — ohne ihn wartete der zwanzigste Fehlversuch acht Tage,
und eine Anmeldung, die nie wiederkommt, ist ein kaputtes Terminal und
keine Sicherheitsmaßnahme.

Der Zähler steht **vor** der Schleife: wer nach zwei Fehlversuchen einen
anderen Namen eintippt, fängt nicht von vorn an.

**Die Verzögerung kommt vor der Meldung.** Stünde die Meldung davor,
wüsste ein Angreifer sofort, dass es nicht gestimmt hat, und könnte die
Verbindung abbrechen, statt zu warten — die Verzögerung kostete ihn dann
nichts.

`su` wartet ebenso (feste Zeit, denn `su` lebt genau einen Versuch
lang). Eine Verzögerung, die nur in `login` steht, wäre eine Tür mit
Schloss neben einem offenen Fenster: wer schon eine Shell hat, nimmt den
bequemeren Weg.

### Der Scheineintrag

Ein unbekannter Name wird trotzdem gegen einen Eintrag geprüft, der nie
stimmt — sonst wäre an der Antwortzeit zu sehen, welche Namen es gibt.
Die Rundenzahl darin ist jetzt dieselbe wie der Kostenfaktor; stünde
dort weiter 2048, wäre ein unbekannter Name viermal schneller abgewiesen
als ein bekannter, und die ganze Vorsichtsmaßnahme wäre ihr eigenes
Leck.

### `/etc/login.conf`

    # Zeilen mit # sind Kommentar
    kdf_runden      = 8192
    verzoegerung_ms = 1000
    max_versuche    = 3

Gibt es die Datei nicht, gelten die Vorgaben — ein System ohne sie muss
sich anmelden lassen.

---

## 6. `passwd` schreibt nicht mehr in die offene Datei

Alte Fassung: `write_all` mit `O_TRUNC`. Zwischen dem Abschneiden und
dem letzten geschriebenen Oktett ist `/etc/shadow` **leer oder halb** —
wer in genau diesem Augenblick den Strom verliert, hat ein System, an
dem sich niemand mehr anmelden kann. Der Kommentar dazu sagte, das gehe
nicht anders, weil das Dateisystem kein `rename` habe. Seit Runde OFS3
hat es eines.

**Gemessen und nicht angenommen:** `rename` dieses Kernels
**überschreibt nicht**. Runde K14 hat das ausdrücklich so entschieden
(`fs.rename_path`: *„dieser Kernel überschreibt nicht still"*, `-EEXIST`)
und `tools/k14/run.sh` misst es. Der erste Versuch dieser Runde — „schreib
`.neu`, rename über `shadow`" — kam mit `-17` zurück. Also vier Schritte:

    1. /etc/shadow.neu schreiben, mit 0o600 und dem alten Eigentümer
       VOR dem ersten Oktett
    2. /etc/shadow      -> /etc/shadow.alt
    3. /etc/shadow.neu  -> /etc/shadow
    4. /etc/shadow.alt löschen

Zu **keinem** Zeitpunkt sind die alten Oktette weg. Was bleibt: zwischen
2 und 3 gibt es kurz kein `/etc/shadow` — zwei Verzeichnisoperationen
lang, ohne Ein-/Ausgabe dazwischen. Nicht null, und deshalb steht es
unten in der Lückenliste.

**Rechte und Eigentümer werden von der alten Datei übernommen.** Der
erste Lauf dieser Runde produzierte sonst `/etc/shadow 600 0 1000`, also
`root:justin`: das setuid-Bit setzt die wirksame **Benutzer**kennung auf
0, die wirksame **Gruppe** bleibt die des Menschen davor, und
`perm.on_create` nimmt beide. Mit `0600` ist das nicht ausnutzbar — beim
nächsten `chmod 0640` wäre es eine offene Tür.

---

## 7. `rename` hatte keine Rechteprüfung

Nebenbefund, beim Bauen von 6 gefunden: `sys.do_rename` fragte **nichts**
— weder nach dem Weg noch nach den beiden Verzeichnissen. Ein
gewöhnlicher Benutzer konnte eine Datei aus einem fremden Verzeichnis
herausbenennen, solange er ihren Namen kannte. Jetzt: Betretungsrecht
auf beiden Pfaden, Schreib- und Betretungsrecht in beiden
Elternverzeichnissen (an der Datei selbst nichts — ihr Inhalt wird nicht
angefasst; so steht es in POSIX).

Und: ohne die VFS-Schicht antwortete `rename` mit `-ENOSYS`. Jetzt geht
es auch dort über `fs.rename_path`, denselben Aufruf, den
`vfs.v_rename` auf der Wurzel ohnehin erreicht.

---

## 8. Die Aufrufnummern (Auflage 5 des Auftrags)

`tools/kernel/syscalls.py` ist neu. Es liest `kernel/sys.fi` **und**
`lib/libc/kcall.fi` und meldet: jede doppelt vergebene Nummer, jeden
Namen mit zwei Nummern, jeden Namen, den nur die libc kennt.

Stand vor der Runde: `141 im Kernel, 141 in der libc, keine Nummer
doppelt`. Der 1320er-Fall aus Runde MERGE war bereits behoben (NETVIEW
auf 1314 gerückt); was fehlte, war der Wächter, der es so lässt.

`--zweige` fragt **git** statt des eigenen Baums — eine Nummer, die hier
frei ist und auf einem Nachbarzweig vergeben, wäre beim Verschmelzen
genau der Fehler von damals. Über alle 51 Zweige gerechnet frei:
`1005…1099 · 1103…1299 · 1302…1309 · 1315…1319 · 1323…1399 · 1405…1499 ·
1505…1599 · 1601…1699 · …`

Genommen: **115** (`getgroups`), **116** (`setgroups`) — die echten
Linux-Nummern, in beiden Tabellen frei — und **1200**
(`SYS_OSUM_MUSTAT`), der erste Wert eines Blocks, der auf *jedem* Zweig
unbenutzt ist.

Die Gegenprobe im Testabschnitt baut den Fehler von damals nach (zweimal
1320) und **muss** fallen.

---

## 9. Die Lücken, die bleiben

Ehrlich und einzeln, so wie K13 es vorgemacht hat:

1. **Symbolische Verweise umgehen die Pfadprüfung teilweise.**
   `perm.walk` prüft die Glieder des *geschriebenen* Pfades.
   `fs.resolve` baut den Pfad beim Verfolgen eines Verweises neu, und
   diese Schleife sieht das Ergebnis nicht. Ein Verweis, der aus einem
   erlaubten in ein verbotenes Verzeichnis zeigt, wird also am Ziel
   geprüft (die Datei selbst) und nicht an den Verzeichnissen des
   aufgelösten Weges. Richtig wäre die Prüfung *in* der Auflösung.
2. **Zwei Durchgänge statt einem.** `perm.walk` läuft den Pfad ab und
   `fs.path` gleich danach noch einmal. Bei einem Pfad mit vier Gliedern
   sind das vier zusätzliche Auflösungen. Messbar, nicht gemessen — der
   Preis dafür, `fs.fi` nicht anzufassen.
3. **`rename` ersetzt nicht.** POSIX sagt, `rename` über eine
   bestehende Datei ersetzt sie atomar. Dieser Kernel sagt `-EEXIST`
   (Entscheidung aus K14, gemessen in `tools/k14/run.sh`). Deshalb die
   vier Schritte in `passwd` und deshalb das kleine Fenster zwischen
   Schritt 2 und 3.
4. **Sticky-Bit** (`S_ISVTX`) wird gespeichert und nicht beachtet. Ein
   `/tmp`, in dem jeder schreiben darf, ist damit eines, in dem jeder
   alles löschen darf. Steht schon seit K13 so da.
5. **`/dev` ist zu großzügig.** Die Blockgeräte (`/dev/hda`, `/dev/ram0`,
   `/dev/nvme0`) tragen `0644 root` — **lesen darf jeder.** Diese Runde
   hat die Prüfung eingebaut, die das Schreiben verhindert; die
   Rohplatte lesbar zu lassen ist trotzdem falsch (`0600` wäre richtig).
   Nicht geändert, weil bestehende Abschnitte darauf stehen könnten und
   „keinen bestehenden Test entschärfen" auch heißt, ihn nicht blind
   umzubauen.
6. **Keine Passwortalterung.** Die Felder in `/etc/shadow` (letzte
   Änderung, Mindest-/Höchstalter, Warnung) werden geschrieben und nie
   gelesen. `max_versuche` sperrt kein Konto, es beendet nur `login`.
7. **Kein `newgrp`, kein Gruppenpasswort**, kein `usermod`/`groupadd`.
   Benutzer und Gruppen entstehen im Abbild (`mkfs.py`) oder mit einem
   Editor.
8. **`su -c` nimmt keine Zeichenkette mit Shell-Syntax.** `su justin -c
   /bin/id` läuft, `su justin -c "a | b"` nicht — die Shell dieses
   Systems kennt kein `-c`, an das man sie weiterreichen könnte.
9. **Argon2id fehlt**, siehe Abschnitt 4. Der Kostenfaktor ist die
   richtige Bauart mit einer Zahl, die zu dieser Maschine passt, und
   nicht die beste Bauart.
10. **Die Zusatzgruppen liegen in einer zweiten Tabelle.** Der
    Aufgabensatz ist voll (ein Wort frei). Zwei Stellen fassen sie an,
    beide in `sched.fi` — aber es *sind* zwei Stellen, und K13 hat
    aufgeschrieben, warum das eine Gefahr ist.
11. **`perm.walk` benutzt keinen eigenen Puffer**, sondern schreibt
    vorübergehend eine Null in den Pfadpuffer des Aufrufers. Das ist der
    Puffer in `kdata`, der je Systemaufruf gilt; auf mehreren
    Prozessoren gleichzeitig wäre das dieselbe Frage, die `fs.fi` mit
    `enter`/`leave` beantwortet, und `walk` stellt sie nicht.

---

## 10. Die Zahlen

| was | Wert |
|---|---|
| Abschnitt `tools/multiuser/run.sh` | siehe `STATUS-MULTIUSER.md` |
| Bestehender Abschnitt `tools/k13/run.sh` | 99 Zusagen, 0 Fehler (unverändert grün) |
| Aufrufnummern | 144 im Kernel, 144 in der libc, keine doppelt |
| kdata | 65 Bereiche, 0 Kollisionen |
| Modusvektor | 90 Namen in 16 Wörtern |
| neue Aufrufnummern | 115, 116, 1200 |
| neue Dateien | `kernel/user/mut.fi`, `tools/kernel/syscalls.py`, `tools/multiuser/run.sh` |
