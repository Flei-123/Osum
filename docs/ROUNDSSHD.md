# Runde SSHD — der Fernzugang

Zweig `sshd`, abgezweigt von `mergeline` (4f844b5), Arbeitsbaum
`/root/sshd-osum`. Testläufer `tools/sshd/`, `./test.sh` Abschnitt 30.
**Nicht nach `main` gemergt.**

> Ohne SSH ist ein Server unbrauchbar. Das war der Auftrag, und er ist
> wörtlich richtig: Osum konnte seit Runde K8 TCP/IP, seit Runde HWNET
> HTTPS *hinaus* — aber es gab keinen Weg *hinein*. Ein Rechner, an den
> man nur mit Tastatur und Bildschirm herankommt, ist kein Server.

---

## 1. Die Ausgangslage, gemessen

```
$ git log --oneline mergeline -1
4f844b5 STATUS-MERGE: Zwischenstand nach dem Merge von kvmfix
$ grep -ril ssh --include='*.fi' . | wc -l
0
```

Kein SSH, nicht ansatzweise. Was es gab und was diese Runde benutzt:

| Baustein | Datei | aus Runde |
|---|---|---|
| X25519 | `lib/crypto/x25519.fi` | TUNNEL |
| Ed25519 (RFC 8032) | `lib/crypto/ed25519.fi` | UPDATE |
| SHA-512 | `lib/crypto/sha512.fi` | UPDATE |
| ChaCha20, Poly1305 | `lib/crypto/chacha.fi` | TUNNEL |
| `poll` (Nummer 7) | `kernel/sys.fi`, `lib/libc/io.fi` | POLL |
| Sockets, Linux-Nummern | `kernel/sys.fi`, `lib/libc/net.fi` | K8 |
| `/etc/passwd`, `/etc/shadow`, uid/gid, `setuid` | `kernel/user/pw.fi`, `kernel/perm.fi` | K13 |
| `init` + `/etc/inittab` + `svc` | `kernel/user/init.fi` | K13 |
| Pseudoterminal (`SYS_OSUM_PTY`) | `kernel/sys.fi`, `kernel/tty.fi` | K9 |

**Die Abhängigkeiten wurden geholt, nicht umgangen.** Die Zweige `poll`
und `update` hatten beide schon Ergebnisse; beide wurden in `sshd`
gemergt (`git merge poll`, `git merge update`, beide sauber). Es musste
nichts gegen eine gedachte Schnittstelle gebaut werden.

**Zur Nutzerverwaltung:** einen Zweig `multiuser` gibt es in diesem Repo
nicht (`git branch -a` kennt keinen). Was es gibt, ist Runde **K13**, und
die ist längst in `main`. `sshd` bindet daran an — es gibt **keine**
eigene Benutzertafel und **keine** Übergangslösung.

---

## 2. Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `lib/crypto/sha256.fi` | 285 | SHA-256 + HMAC, ohne `profile`, ohne `import` |
| `lib/ssh/wire.fi` | 471 | die Datentypen von RFC 4251, Base64 |
| `lib/ssh/pack.fi` | 286 | das binäre Paket, `chacha20-poly1305@openssh.com` |
| `lib/ssh/kex.fi` | 154 | K, H, die Ableitung von RFC 4253 7.2 |
| `kernel/user/sshd.fi` | 2035 | der Server |
| `tools/sshd/oracle.fi` | 336 | dieselben Dateien, auf dem Wirt |
| `tools/sshd/vectors.py` | 411 | die Messung gegen Python |
| `tools/sshd/run.sh` | 613 | die Abnahme gegen den echten Klienten |

### Warum eine dritte SHA-256

Der Baum hatte schon zwei — `kernel/user/pw.fi` (mit
`if len > 256 { return false }`) und `kernel/user/sha.fi` (strömend, aber
mit **einem** Zustand als Modulvariable). Ein SSH-Handschlag rechnet
mehrere Hashes, die einander überlappen: der Austauschhash H läuft über
neun Felder, währenddessen entstehen der Fingerabdruck und die
Schlüsselableitungen. Beide vorhandenen Fassungen sind außerdem
`profile kernel`-Ring-3-Bibliotheken und lassen sich nicht in einen
gehosteten Testläufer binden. Die neue liegt unter `lib/crypto/`, hat
weder `profile` noch `import`, und der Zustand gehört dem Aufrufer —
dieselbe Regel wie `blake2s.fi` und `sha512.fi`.

Die beiden alten bleiben stehen; sie werden von `pw`, `opk`, `backup`,
`bstore` und `hwid` benutzt und sind gegen Pythons `hashlib` gemessen.
Sie zusammenzulegen ist eine eigene Aufgabe und steht in
`STATUS-SSHD.md` als offener Punkt.

### Die drei Stellen, an denen man SSH falsch macht

1. **Der `mpint`.** Der gemeinsame Schlüssel K geht als vorzeichen­behaftete
   Zahl in den Austauschhash. Ist das oberste Bit gesetzt, muss ein
   `0x00` davor — sonst ist die Zahl negativ, H stimmt nicht, und der
   Klient sagt „incorrect signature". In **jeder zweiten** Verbindung,
   weil das oberste Bit in der Hälfte der Fälle gesetzt ist. Ein Fehler,
   der zur Hälfte funktioniert, ist schlimmer als einer, der nie
   funktioniert. `tools/sshd/vectors.py` misst 374 Fälle gegen eine
   zweite Umsetzung in Python, davon 64 mit gesetztem obersten Bit.

2. **Die Auffüllung, in zwei Fassungen.** Vor NEWKEYS muss die *ganze*
   Länge (4 + 1 + Nutzlast + Auffüllung) durch 8 teilbar sein; mit
   `chacha20-poly1305@openssh.com` ist das Längenfeld getrennt
   verschlüsselt und zählt **nicht** mit, also muss `packet_length`
   selbst durch 8 teilbar sein. Wer nur eine Regel kennt, bekommt vom
   Klienten „padding error" und sonst nichts. 600 Fälle, beide Regeln.

3. **Die Reihenfolge der beiden ChaCha-Schlüssel.** 512 Bit
   Schlüsselmaterial: die **ersten** 256 Bit sind K_2 (Nutzlast und
   Poly1305), die **zweiten** 256 Bit sind K_1 (nur das Längenfeld). Und
   OpenSSH benutzt djbs Aufteilung (64 Bit Zähler, 64 Bit Nonce),
   `lib/crypto/chacha.fi` die von RFC 8439 (32/96). Es ist derselbe
   Zustandsvektor, nur anders benannt — die Umrechnung steht im Kopf von
   `lib/ssh/pack.fi` und ist 80 Pakete lang gegen `cryptography`
   gemessen, Oktett für Oktett.

---

## 3. Die Bauform: ein Prozess je Verbindung, und trotzdem `poll`

Der Lauscher nimmt an und spaltet sich; das Kind führt den ganzen
Handschlag und die Sitzung. Das ist die Bauform von OpenSSH, und sie hat
hier denselben Grund: der Krypto-Zustand einer Verbindung ist dann
einfach der Zustand *dieses* Prozesses.

`poll` (Runde POLL) wird an zwei Stellen gebraucht, und beide sind echt:

1. **Im Lauscher**, damit er zwischen zwei Verbindungen die Leichen
   seiner Kinder einsammeln kann, ohne im `accept` festzuhängen.
2. **In der Sitzung**, und das ist die wichtige. Ein Sitzungskanal muss
   *gleichzeitig* auf Oktette aus dem Netz (der Mensch tippt) und auf
   Oktette aus dem Rohr der Shell (das Programm redet) warten. Ohne
   `poll` hinge ein `ssh host`, bis der Mensch etwas tippt, und die
   Ausgabe eines laufenden Programms käme erst danach. Genau der Fall,
   den `kernel/user/jarvisd.fi` in der Runde POLL vorgemessen hat.

Gemessen: die größte Zahl von `poll`-Durchläufen einer ganzen Sitzung
liegt im zweistelligen Bereich. Eine Warteschleife hätte Tausende.

---

## 4. Drei Fehler, die der Bau gekostet hat

Sie stehen hier, weil ein Rundenprotokoll ohne die Fehler eine Werbung
ist.

**(a) SIGCHLD hat den Lauscher umgebracht.** Der erste Lauf war fast
grün: Anmeldung, Befehl, Ausgabe — und danach stand im Protokoll zweimal
`sshd: listening`. Der Kern bricht *jeden* blockierenden Aufruf mit
`-EINTR` ab, sobald irgendein unmaskiertes Signal ansteht — auch eines,
dessen Standardverhalten „übergehen" ist (`signal.deliverable` in
`kernel/signal.fi` sieht nur die Bits, nicht das Verhalten). SIGCHLD ist
genau so eines, und ein Server mit Kindern bekommt es bei jedem
Sitzungsende. Der Lauscher hielt das für einen Fehler und ging; `init`
startete ihn neu. Zwei Maßnahmen, und beide gehören dazu: SIGCHLD wird
maskiert, **und** `-EINTR` wird als „nichts passiert" behandelt statt
als Fehler.

**(b) Zwei `wait4` hintereinander, und jeder Befehl meldete Erfolg.** Der
erste Entwurf rief erst `wait4` blockierend und dann noch einmal
`wait_for`, um den Status zu holen. Das Kind war da schon eingesammelt,
der zweite Aufruf lief ins Leere, `status` blieb null — und **jeder**
Fernbefehl meldete den Beendigungscode 0. Ein Fehlschlag, der wie ein
Erfolg aussieht, ist der schlimmste; er wäre nie aufgefallen, wenn der
Testläufer nicht ausdrücklich `exit 7` prüfte.

**(c) Ein Pseudoterminal meldet das Ende des Kindes nicht.** Ein Rohr
tut es von selbst: alle Schreiber weg, `read` gibt 0. Die Steuerseite
eines Pseudoterminals bleibt offen, solange *dieser* Prozess sie hält.
Gemessen: eine Sitzung mit `ssh -tt` lief nach `sh: bye` weiter, bis der
Klient aufgab. Seitdem sieht die Schleife bei jedem Durchlauf ohne Warten
nach, ob das Kind noch lebt (`wait4` mit `WNOHANG`).

**(d) Ein Fund, der nicht dieser Runde gehört:** OFS Fassung 2 hat
32-Oktett-Verzeichniseinträge, davon 24 für den Namen — also **23
Zeichen** plus Null. `ssh_host_ed25519_key.pub` (24) und
`...key.seed` (25) wurden vom Dateisystem **still abgeschnitten**. Der
Server merkte nichts (er schrieb und las denselben abgeschnittenen
Namen), aber `mkfs.py cat` auf dem Wirt fand die Datei nicht mehr. Die
Namen heißen deshalb `ssh_host_ed25519_key` (20) und
`ssh_host_ed25519.pub` (20). Dass ein zu langer Name *stillschweigend*
gekürzt wird statt `-ENAMETOOLONG` zu geben, ist ein eigener Befund und
steht in `STATUS-SSHD.md`.

---

## 5. Was gemessen wurde, und womit

**Nicht** gegen einen selbstgeschriebenen Klienten. Zwei Enden, die
dasselbe Missverständnis teilen, sind sich perfekt einig — das ist die
Versagensart jedes selbstgebauten Protokolls, und `tools/net/run.sh` hat
aus demselben Grund gegen den Linux-Kernel gemessen und nicht gegen sich
selbst.

**Stufe 1 — die Bausteine gegen ihre RFCs** (`tools/sshd/vectors.py`,
auf dem Wirt, gegen `hashlib`, `hmac`, `base64` und `cryptography`).
1895 Vergleiche, 0 Fehler. Darunter 50 Gegenproben, die *fehlschlagen
müssen*: 25 Pakete mit genau einem gekippten Bit und 25 unter der
falschen Paketnummer — keines davon wurde angenommen.

**Stufe 2 — der echte OpenSSH-Klient** (`tools/sshd/run.sh`), QEMU mit
`-accel kvm` und Anschlussweiterleitung, `ssh` / `ssh-keyscan` /
`ssh-keygen` aus OpenSSH 9.2p1. Zu jeder Zusage die Gegenprobe:

| Zusage | Gegenprobe |
|---|---|
| Anmeldung mit Schlüssel | ein *anderer* Schlüssel wird abgelehnt — **und** derselbe Schlüssel auf einem Abbild **ohne** `authorized_keys` |
| Anmeldung mit Passwort | falsches Passwort, unbekannter Name |
| Fernbefehl mit verglichener Ausgabe | — |
| Beendigungscode kommt an | `exit 7` **und** `true` |
| Datei durchgereicht, SHA-256 gleich | Länge und Summe, beide Seiten |
| Pseudoterminal | die Rohr-Sitzung hat **kein** CR, die pty-Sitzung hat eines |
| zwei Verbindungen gleichzeitig | beide bekommen ihre *eigene* Ausgabe |
| als Dienst aus `/etc/inittab` | die Zahl der Starts in `/run/svc.state` ist 1 — er ist nie gestorben |
| Wirtsschlüssel bleibt | zweiter Start desselben Datenträgers, gleicher Fingerabdruck; `ssh-keygen -lf` rechnet ihn aus der `.pub`-Datei **auf der Platte** nach |
| die ausgehandelten Verfahren | ein Klient ohne gemeinsame Chiffre und einer ohne gemeinsamen Schlüsselaustausch werden abgewiesen |

Die Zahlen des Abnahmelaufs stehen in `STATUS-SSHD.md`.

---

## 6. Was NICHT gebaut wurde

* **Keine Neuaushandlung.** Ein KEXINIT mitten in der Sitzung wird
  abgelehnt statt beantwortet.
* **Kein `sftp-server`, kein `scp` auf Osum.** `scp` benutzt seit
  OpenSSH 9.0 SFTP; das Unterprotokoll gibt es hier nicht. Eine Datei
  geht mit `ssh host cat datei` durch, und genau so wird sie gemessen.
* **Kein `aes256-gcm`, keine Kompression, kein Agentenweiterleiten,
  keine Anschlussweiterleitung (`-L`/`-R`), kein X11.**
* **Kein Client.** `ssh` *von* Osum *nach draußen* ist eine eigene Runde.
* **Der private Wirtsschlüssel liegt roh auf der Platte** (32 Oktette
  Saat, 0600, root) und nicht in OpenSSHs `openssh-key-v1`-Behälter.

Die vollständige Liste mit Bewertung steht in `STATUS-SSHD.md`,
Abschnitt „Wovor das NICHT schützt".
