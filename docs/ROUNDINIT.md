# Runde INIT — der erste Prozess, servertauglich

Zweig `init`, Arbeitsbaum `/root/osum-init`, abgezweigt von `mergeline`
(4f844b5). Testläufer `tools/init/run.sh`, Abschnitt 29 von `./test.sh`.
**Nicht nach `main` gemergt.**

---

## 1. Was vorher wirklich da war

Der Auftrag sagte, es gäbe kein Init-System. Nachgesehen ergibt ein
anderes Bild, und der Unterschied ist wichtig genug, um ihn
aufzuschreiben:

`kernel/user/init.fi` **gab es** — 475 Zeilen aus Runde K13, mit
`/etc/inittab`, den Arten `once`/`respawn`/`ctrl`/`off`, dem Einsammeln
von Waisen und einer Abschaltung über echtes ACPI. `kernel/user/svc.fi`
gab es ebenso.

**Gefehlt hat, was daraus ein System für einen Server macht:**

| | vorher | jetzt |
|---|---|---|
| `/etc/inittab` im gebauten Abbild | **in keinem** — nur `tools/k13/run.sh` legte eine im Temp-Verzeichnis an | im Abbild des Testläufers, und `docs/INIT.md` sagt, wie sie aussieht |
| abstürzender Dienst | für immer neu gestartet, 5×/s | **nach fünf Fehlstarts abgeschaltet** |
| Runlevel/Ziel | keins, jede Zeile lief immer | `konsole` / `grafik` aus `/etc/ziel` |
| Protokoll je Dienst | keins, alles auf die Konsole | `log=/pfad`, anhängend |
| „erst nach Netz" | keins | Option `netz` |
| `/bin/shutdown`, `/bin/reboot` | keins von beiden | beide |
| `reboot(RB_RESTART)` | fiel in `power.shutdown()` — ein **Anhalten** | FADT-RESET_REG → 0xCF9 → 8042, ein **echter Neustart** |
| Pfad des ersten Prozesses | `/sbin/init` | `/bin/init`, `/sbin/init` bleibt als zweiter Weg |
| Zahl der Dienste | 8 | 16 |

---

## 2. Der Rückfall-Zähler, und warum die erste Fassung falsch war

Die Aufgabe: „stirbt ein Dienst fünfmal in kurzer Folge, wird er
abgeschaltet statt endlos neu gestartet."

**Der erste Entwurf** nahm die Lebensdauer: wer keine halbe Sekunde
durchhält, bekommt einen Strich; fünf Striche, dann aus. Im Testlauf
blieb der Zähler bei **null**. Gemessen: `/bin/false` lebte **1,5
Sekunden**. Nicht, weil es etwas tat — sondern weil `fork` + `execve` +
der ELF-Lader für ein 29-KiB-Programm von einer IDE-Platte so lange
brauchen. *Eine Grenze, die unter der Anlaufzeit eines Prozesses liegt,
misst die Platte und nicht den Dienst.*

Bei der Gelegenheit fiel ein zweiter Fehler auf, den dieselbe Messung
sichtbar machte: `/bin/false` und `/bin/sleep 1` kamen auf **exakt
dieselbe Zahl Starts**, obwohl das eine sofort endet und das andere eine
Sekunde läuft. Ursache war das `sleep_ms(200)` mitten in der
Neustartschleife von K13 — es hielt den **ganzen Prozess 1** an, und
zwei Dienste, die gleichzeitig neu starten wollten, warteten
aufeinander. Seit dieser Runde merkt sich jeder Dienst seinen frühesten
nächsten Start (`s_next`), und die Schleife blockiert nicht mehr.

**Die Fassung, die jetzt drin ist**, hat zwei Bedingungen, und beide
müssen erfüllt sein:

> **(a)** der Dienst endet mit einem Code ≠ 0, **und**
> **(b)** er hat es nicht bis `GESUND_MS` (2 s) geschafft.

Sonst fällt der Zähler auf null. Das ist mehr als eine Reparatur, es ist
die richtigere Regel:

* Wer mit **0** endet, hat getan, wozu er da war. Das ist kein Absturz,
  egal wie oft es geschieht. Der Dienst `blink` aus dem Testlauf von K13
  schläft eine Sekunde und endet mit 0 — er kann deshalb **nie**
  abgeschaltet werden, und die 99 Zusagen jener Runde messen weiter, was
  sie gemessen haben.
* Wer **fünf Minuten gearbeitet** hat und dann abstürzt, gehört neu
  gestartet und nicht abgeschaltet. Er hat bewiesen, dass er laufen
  kann.

`svc start NAME` setzt den Zähler auf null — wer von Hand startet, hat
nachgesehen.

---

## 2b. Der Kernfehler, den diese Runde gefunden hat

Das wichtigste Ergebnis dieser Runde steht nicht in `init.fi`, sondern in
`kernel/sys.fi`. Es kam beim Messen heraus und nicht beim Lesen.

**Der Befund.** Ein Dienst mit `respawn`, der schnell endet, blieb nach
seinem **zweiten** Start für immer stehen. `svc status` zeigte ihn weiter
als `running`, `ps` zeigte an derselben Stelle einen **Zombie mit
Elternteil 1**, und die Zahl der Starts bewegte sich nicht mehr. Mit
genügend Diensten lief die Aufgabentafel (32 Plätze) voll, und dann
startete nichts mehr — `elf:`-Zeilen ohne ein `elf: start` dahinter.

**Die Ursache.** `do_wait4` fragte:

```
let child: u64 = find_child(state, me, want)
```

und `find_child` gibt den **ersten** Prozess der Aufgabentafel zurück,
dessen Elternteil der Rufer ist — **ohne nach seinem Zustand zu fragen**.
Lebt der noch, so antwortete `wait4` mit `WNOHANG` an dieser Stelle eine
`0` („nichts Neues"), und der **Zombie dahinter** wurde nie abgeholt.

**Warum es 25 Runden lang niemand gemerkt hat.** Eine Shell wartet auf
**ein** Kind und hat meist kein zweites; für sie ist der erste Treffer
immer der richtige. Der Prozess 1 hat **immer** mehrere Kinder, und das
langlebigste (die Konsole) steht in der Tafel meist **vor** den
kurzlebigen Diensten. Runde K13 hatte im Testlauf genau zwei Zeilen in
`/etc/inittab` und ist knapp daran vorbeigelaufen.

**Die Behebung** ist, wonach man fragt: zuerst nach einem **Zombie**
(`find_zombie_child`), und erst wenn es keinen gibt, danach, ob es
überhaupt ein Kind gibt — das unterscheidet „warte" von `-ECHILD`. Bei
genau einem Kind ist das Verhalten Zeile für Zeile das alte.

**Die Gegenprobe** heißt `waitfirst` und stellt den alten Weg wieder her.
Gemessen, derselbe Lauf, dasselbe Abbild:

| | `sauber` (`/bin/true`, `respawn`) | Aufgabentafel |
|---|---|---|
| behoben | `stopped 0 20 0` — 20 Starts, `reaped=21`, `zombies=0` | kein Zombie |
| `waitfirst` | `running 11 2` — steht bei **2** Starts, für immer | `11 1 zombie user` bleibt stehen |

---

## 2c. Die zweite Bremse: init darf die Maschine nicht selbst auffressen

Der Rückfall-Zähler trifft nur, wer mit einem Fehler endet. Ein Dienst,
der **sofort und mit 0** endet (`/bin/true` als `respawn`), ist nach
dieser Regel keine Fehlfunktion — und frisst die Maschine trotzdem auf:
fünf Prozessstarts je Sekunde, jeder mit `fork`, `execve` und einem
ELF-Lader, der 28 KiB von der Platte holt. **Gemessen:** mit einem
solchen Dienst brauchte ein `sleep 15` in einer anderen Shell länger als
drei Minuten; ohne ihn lief derselbe Lauf durch.

Dazu kam `init` selbst: es las `/run/svc.cmd` in **jedem** Durchgang, also
vierzig Dateiöffnungen je Sekunde, dauerhaft, auf einer IDE-Platte.

Zwei Änderungen, beide aus der Messung:

1. **Eine Startbremse für JEDEN Dienst**, ohne nach dem Grund zu fragen:
   mehr als **10 Starts binnen 5 Sekunden**, und der nächste Start wartet
   **5 Sekunden** statt 200 ms. Ein gesunder Dienst kommt dort nie hin —
   `blink` (`sleep 1`) schafft in fünf Sekunden vier Starts.
2. **`/run/svc.cmd` nur noch alle 200 ms.** `svc` wartet eine Sekunde auf
   Antwort; 200 ms reichen, und es ist ein Achtel der Last.

---

## 3. Das Format von `/etc/inittab`

Zwei Schreibweisen, und **beide werden gelesen**:

    name:art:befehl                       (Runde K13, unverändert)
    name:ziele:art:befehl:optionen        (diese Runde)

Welche es ist, entscheidet das **zweite Feld**: steht dort eines der
Wörter `once`, `respawn`, `ctrl`, `off`, ist es die kurze Form. Sonst
ist es die Zielliste. Das ist eindeutig, weil ein Ziel `konsole`,
`grafik`, beides mit Komma oder `*` heißt.

* **art** — `once` (einmal), `respawn` (immer wieder), `ctrl` (wie
  `once`, aber sein Ende beendet das System), `off` (steht da, läuft
  nicht).
* **ziele** — Komma-Liste oder `*`. Eine Angabe, die niemand versteht,
  heißt **nirgends** und nicht „überall": ein Tippfehler soll auf einem
  Server nichts Unerwartetes starten.
* **optionen** — Komma-Liste aus `netz` und `log=/pfad`.

Beispiel:

    # name:ziele:art:befehl:optionen
    sshd:*:respawn:/bin/sshd:netz,log=/var/log/sshd.log
    leiste:grafik:respawn:/bin/leiste
    login:konsole:respawn:/bin/login

`/etc/ziel` enthält **ein Wort**. Fehlt die Datei, ist das Ziel
`konsole` — ein Server ohne Bildschirm startet damit von selbst nichts
Grafisches, und das ist die richtige Voreinstellung: wer eine Oberfläche
will, sagt es.

---

## 4. Die Wurzel, und was `init` daran wirklich tut

Der Auftrag verlangt, `init` solle „die Wurzel mounten". Ehrlich ist:
**der Kern muss das tun**, bevor es diesen Prozess überhaupt gibt — er
könnte `/bin/init` sonst nicht laden. Was `init` tut und was hier steht,
damit es niemand für mehr hält, als es ist:

1. Es **prüft die Wurzel nach** (`SYS_MOUNT` mit op 0) und hängt sie
   ein, wenn sie fehlt (op 1). Der Fall ist nicht theoretisch: ein
   System, dessen Wurzel aus einem Boot-Modul kommt und dessen Platte
   erst danach auftaucht, hat sonst keine Stelle dafür. Gemeldet als
   `init: wurzel=1`.
2. Es hängt **alles andere** aus `/etc/fstab` ein (`quelle ziel art
   [ro]`, `SYS_VMOUNT`, Linux' Aufruf 165) und beim Herunterfahren in
   umgekehrter Reihenfolge wieder aus. Gemeldet als `init: mounts=N`
   und `init: umounts=N`.

---

## 5. Herunterfahren und Neustart

Die Reihenfolge beim Herunterfahren ist der ganze Unterschied zwischen
„heruntergefahren" und „ausgesteckt":

1. `SIGTERM` an jeden Dienst
2. zwei Sekunden warten — und dabei weiter einsammeln, was fällt
3. `SIGKILL` an die Reste
4. `sync`
5. die Dateisysteme aus `/etc/fstab` aushängen, dann die Wurzel
6. `reboot(RB_POWEROFF)` bzw. `reboot(RB_RESTART)`

**Der Neustart ist neu und war vorher keiner.** `kernel/sys.fi` schickte
`RB_RESTART` in `power.shutdown()`, also in den Ausgang des Prüfstands:
die Maschine blieb stehen. Jetzt geht `power.acpi_reset` drei Wege, in
dieser Reihenfolge:

1. **Das RESET-Register aus der FADT** (ACPI 2.0, 4.7.3.6): generische
   Adresse ab Oktett 116, Wert bei 128, Bit 10 der Flags bei 112 sagt,
   dass es das gibt. Die FADT muss dafür mindestens 129 Oktette lang
   sein — eine FADT der Fassung 1 hört bei 116 auf, und was dahinter
   steht, gehört einer anderen Tabelle.
2. **Anschluss 0xCF9** (Reset Control): `0x02`, dann `0x06`.
3. **Der 8042**: `0xFE` an 0x64.

**Gemessen auf diesem Wirt:** QEMUs i440fx liefert eine FADT ohne
RESET_REG, also greift Weg 2 — im Mitschnitt steht `power: reset 0xCF9`,
und QEMU beendet sich mit 0. Der ehrlichere Beweis steht daneben:
derselbe Lauf **ohne** `-no-reboot` lässt den Kernel ein **zweites Mal**
hochkommen (`osum: pid1 init` steht zweimal im Mitschnitt). Ein `halt`,
das sich als Neustart ausgibt, kommt kein zweites Mal.

---

## 6. `svc`

    svc                 die Tafel: wer läuft, seit wann, wie oft neu
    svc list            dasselbe
    svc status          eine Zeile je Dienst, roh, wie init sie schreibt
    svc start NAME      (hebt eine Abschaltung auf)
    svc stop NAME
    svc restart NAME
    svc ziel            welches Ziel gerade gilt
    svc shutdown
    svc reboot

`svc status` bleibt **roh**, und das ist keine Bequemlichkeit:
`tools/k13/run.sh` liest die Spalten dieser Ausgabe mit
`grep -aoE '^blink running [0-9]+ [0-9]+'`. Diese Runde legt drei
Spalten **hinten** an — `fehler`, `seit`, `ziele` —, die vier vorderen
stehen unverändert da, und jene Zusagen messen weiter, was sie gemessen
haben. Die Tafel mit Überschrift und Spaltenbreiten bekommt ein eigenes
Wort.

---

## 7. Was für einen Dauerbetrieb noch fehlt

Ehrlich und ohne Beschönigung — das hier ist ein Init-System, das einen
Server über Wochen trägt, aber es ist kein systemd:

1. **Keine Protokollrotation.** `log=/var/log/x.log` wächst, bis die
   Platte voll ist. Ein Server, der ein Jahr läuft, braucht entweder
   eine Größengrenze in `init` oder ein `logrotate` als `once`-Dienst.
   Das ist die wichtigste offene Lücke.
2. **Keine Abhängigkeiten zwischen Diensten.** Es gibt genau eine:
   `netz`. „B startet erst, wenn A läuft" gibt es nicht.
3. **Kein `poll`.** Die Schleife von `init` fragt alle 25 ms nach; das
   ist eine Abfrage und kein Warten. Auf einem Rechner mit Akku ist das
   messbar (Runde POWERMON), auf einem Server ist es Rundungsfehler.
   `docs/ROADMAP-UPDATE.md` B2 hat `SYS_POLL` schon als eigene Runde
   vorgemerkt.
4. **`/run/svc.cmd` ist eine Datei und kein Socket.** Zwei `svc`-Aufrufe
   gleichzeitig können einander überschreiben. Auf einem System mit
   einem Menschen davor ist das nie passiert; auf einem, das aus einem
   Skript gesteuert wird, kann es.
5. **Keine Zeitsteuerung.** Kein `cron`, kein Timer.
6. **Kein Zustand über einen Neustart hinweg.** Ein von Hand
   abgeschalteter Dienst läuft nach dem Neustart wieder — `init` kennt
   nur `/etc/inittab`, nicht „was zuletzt gewollt war".
7. **Keine Grenzen je Dienst.** Kein Speicherlimit, keine
   Prozesszahl-Grenze, kein `nice`. Ein Dienst, der Speicher frisst,
   frisst den der Maschine.
8. **`MAX_SVC = 16`** ist eine Konstante und keine Liste; die 17. Zeile
   in `/etc/inittab` wird stillschweigend ignoriert.
9. **Kein Dienst läuft unter einer anderen Kennung.** Alles ist root.
   Die Kennungsschicht aus K13 ist da (`setuid` in Ring 3 möglich), aber
   `init` benutzt sie nicht — ein `user=`-Feld in der inittab wäre eine
   kleine, lohnende Ergänzung.
10. **Der Neustart ist nur auf QEMU gemessen**, Weg 2 von dreien. Das
    RESET-Register der FADT und der 8042 stehen im Code und sind auf
    diesem Wirt nicht gelaufen.
11. **Die Startbremse ist grob.** Zehn Starts in fünf Sekunden, dann
    fünf Sekunden Pause — es gibt keinen ansteigenden Rückfall
    (200, 400, 800 …), wie ihn systemd fährt. Für einen kaputten Dienst
    reicht es; für einen, der alle sechs Sekunden stirbt, greift sie
    nie.
12. **`nanosleep` schläft Marke für Marke.** `sleep 15` sind 1500
    Durchgänge durch den Scheduler. Solange der Prozess 1 wenig tut,
    fällt das nicht auf — unter Last wird ein langer Schlaf messbar
    länger als er sollte. Das ist kein Fehler dieser Runde, aber es ist
    der Grund, warum die Testskripte hier mit `sleep 5` arbeiten und
    nicht mit `sleep 30`.
