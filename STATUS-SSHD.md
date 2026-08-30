# RUNDE SSHD — Abschluss

Zweig `sshd`, abgezweigt von `mergeline` (4f844b5), Arbeitsbaum
`/root/sshd-osum`. **Nicht nach `main` gemergt, keine fremden Zweige
angefasst.** Rundenprotokoll: `docs/ROUNDSSHD.md`.

---

## 1. Die Ausgangslage, gemessen

```
$ git log --oneline mergeline -1
4f844b5 STATUS-MERGE: Zwischenstand nach dem Merge von kvmfix
$ grep -ril ssh --include='*.fi' . | wc -l
0
```

Es gab kein SSH im Baum. **Die Abhängigkeiten wurden geholt, nicht
umgangen:** die Zweige `poll` (der Systemaufruf, ohne den ein Dienst nur
auf eine Sache warten kann) und `update` (SHA-512 und Ed25519, der
wichtigste SSH-Schlüsseltyp) hatten beide schon Ergebnisse und wurden
beide in diesen Zweig gemergt — sauber, ohne Konflikt.

Eine Runde `multiuser` gibt es in diesem Repo nicht; `git branch -a`
kennt keinen solchen Zweig. Was es gibt, ist **K13**, und die ist längst
in `main`. `sshd` bindet daran an und hat **keine** eigene
Benutzertafel und **keine** Übergangslösung: `/etc/passwd`,
`/etc/shadow` mit PBKDF2-HMAC-SHA256, `setgid`+`setuid` vor `execve`,
Rechteprüfung in `kernel/perm.fi`.

---

## 2. Was jetzt da ist

```
osum-wirt$ ssh justin@10.0.2.15 'echo hallo; id'
hallo
uid=1000(justin) gid=1000 euid=1000(justin) egid=1000
```

| Datei | Zeilen | was |
|---|---:|---|
| `lib/crypto/sha256.fi` | 285 | SHA-256 + HMAC, ohne `profile`, ohne `import` |
| `lib/ssh/wire.fi` | 471 | die Datentypen von RFC 4251, Base64, name-list |
| `lib/ssh/pack.fi` | 286 | das binäre Paket, `chacha20-poly1305@openssh.com` |
| `lib/ssh/kex.fi` | 154 | K als mpint, H, die Ableitung von RFC 4253 7.2 |
| `kernel/user/sshd.fi` | 2035 | der Server |
| `tools/sshd/oracle.fi` | 336 | dieselben Dateien, gehostet auf Linux |
| `tools/sshd/vectors.py` | 411 | die Messung gegen Python |
| `tools/sshd/run.sh` | 613 | die Abnahme gegen den echten OpenSSH-Klienten |

`/sbin/sshd` ist **275 832 Oktette** und hat keinen undefinierten Namen.

**Ausgehandelt wird**, vom Klienten bestätigt:
`curve25519-sha256` (RFC 8731) · `ssh-ed25519` (RFC 8709) ·
`chacha20-poly1305@openssh.com` in beide Richtungen ·
`kex-strict-s-v00@openssh.com` (die Gegenmaßnahme gegen Terrapin,
CVE-2023-48795 — nur wenn der Klient sie anbietet).

**Anmeldung:** `publickey` (Ed25519, aus `~/.ssh/authorized_keys` im
Standardformat) **und** `password` (gegen `/etc/shadow`).
**Sitzung:** `shell` und `exec`, wahlweise an einem echten
Pseudoterminal (`SYS_OSUM_PTY`, Runde K9).
**Dienst:** `sshd:respawn:/sbin/sshd` in `/etc/inittab`, sichtbar in
`/run/svc.state`.

---

## 3. Die Zahlen des Abnahmelaufs

### Stufe 1 — die Bausteine gegen ihre RFCs (`tools/sshd/vectors.py`)

Gehostetes Firn-Programm, das **genau dieselben Dateien** bindet wie der
Server, gegen Pythons `hashlib`, `hmac`, `base64` und `cryptography`:

```
SHA-256:      140 Faelle gegen hashlib und FIPS 180-4
HMAC-SHA-256:  47 Faelle gegen hmac und RFC 4231
mpint:        374 Faelle gegen RFC 4251 Abschnitt 5
Base64:       321 Faelle hin und zurueck
Ableitung:     60 Faelle (RFC 4253 7.2), davon 41 mit Verlaengerung
AEAD:          80 Pakete Oktett fuer Oktett gegen cryptography
              +80 dieselben Pakete wieder aufgemacht
Gegenprobe:    25 Pakete mit EINEM gekippten Bit  -> 0 angenommen
Gegenprobe:    25 Pakete unter falscher Paketnummer -> 0 angenommen
Auffuellung:  600 Faelle, beide Regeln (mit und ohne AEAD)
Klartext:      62 Pakete gebaut und wieder gelesen
name-list:      8 Faelle

1895 Vergleiche, 0 Fehler
```

### Stufe 2 — der echte OpenSSH-Klient (`tools/sshd/run.sh`)

QEMU mit `-accel kvm` und Anschlussweiterleitung; `ssh`, `ssh-keyscan`
und `ssh-keygen` aus **OpenSSH 9.2p1**, unverändert.

```
SSHD: 67 passed, 0 failed
```

Neun Abschnitte, darunter:

* der Dienst lauscht nach **22,8 s** ab Kaltstart (Booten, Erzeugen des
  Wirtsschlüssels, `listen`), unter starker Fremdlast auf dem Wirt
* `ssh-keyscan` holt den Wirtsschlüssel über das Protokoll,
  `ssh-keygen -lf` rechnet **denselben** Fingerabdruck aus wie sshd ihn
  auf die Konsole schreibt **und** wie die `.pub`-Datei auf der Platte
  ergibt — drei unabhängige Wege, ein Wert
* 20 000 Oktette durchgereicht, **SHA-256 auf beiden Seiten gleich**
* Beendigungscode: `exit 7` kommt als 7 an, `true` als 0
* zwei Verbindungen **gleichzeitig**, beide mit ihrer eigenen Ausgabe
* **19 angenommene Verbindungen** in einem Lauf, Zahl der Dienststarts
  in `/run/svc.state`: **1** — der Dienst ist kein einziges Mal gestorben
* **kein einziger Prozessorfehler** im ganzen Lauf
* `svc shutdown` aus der Ferne fährt das System herunter

### Zeiten (unter Fremdlast, load average ~27 auf 12 Kernen)

| was | ms |
|---|---:|
| Versionsaustausch | < 1 |
| Schlüsselaustausch (X25519 ×2 + Ed25519-Signatur + SHA-256) | 222 … 876 |
| Anmeldung (Ed25519-Prüfung **oder** PBKDF2 2048 Runden) | 645 … 3155 |
| eine leere Sitzung (verbinden, `true`, Schluss) | 11 519 |
| 20 000 Oktette Nutzdaten | 9 423 → **≈ 2 100 Oktette/s** |
| poll-Durchläufe der längsten Sitzung | **43** |

Die 43 sind die Zahl, auf die es ankommt: eine Warteschleife hätte
Tausende. Ein Prozess, der wartet, rechnet hier nicht.

**Ehrlich zu den Zeiten:** sie sind langsam, und der Grund ist bekannt.
X25519 und Ed25519 in `lib/crypto/` rechnen mit
Montgomery-Arithmetik auf 32-Bit-Gliedern in reinem Firn, ohne
Assembler und ohne Beschleuniger; PBKDF2 läuft mit 2048 Runden (Runde
K13 hat die Zahl bewusst klein gehalten und das dort begründet). Der
Durchsatz von 2 100 Oktetten/s ist zusätzlich davon begrenzt, dass ein
Rohr dieses Kerns 512 Oktette fasst (`PIPE_CAP` in `kernel/file.fi`) —
mehr passt zwischen Shell und Server nicht auf einmal.

---

## 4. Sicherheitsbewertung — WAS GEPRÜFT IST

| Zusage | wie geprüft |
|---|---|
| SHA-256, HMAC | 187 Fälle gegen `hashlib`/`hmac`, FIPS 180-4, RFC 4231 |
| mpint-Kodierung | 374 Fälle gegen eine zweite Umsetzung, RFC 4251 5 |
| Schlüsselableitung | 60 Fälle gegen eine zweite Umsetzung, RFC 4253 7.2 |
| `chacha20-poly1305@openssh.com` | 160 Pakete gegen `cryptography`, Oktett für Oktett |
| Ein gekipptes Bit wird abgelehnt | 25 Fälle, 0 angenommen |
| Eine falsche Paketnummer wird abgelehnt | 25 Fälle, 0 angenommen |
| Der Handschlag ist echtes SSH-2 | OpenSSH 9.2p1 nimmt ihn an |
| Der Wirtsschlüssel ist der, der behauptet wird | `ssh-keyscan` + `ssh-keygen -lf` + die Datei auf der Platte |
| Der Wirtsschlüssel bleibt über einen Neustart | zweiter Start desselben Datenträgers, gleicher Fingerabdruck |
| `authorized_keys` wird wirklich gelesen | derselbe Schlüssel wird auf einem Abbild **ohne** die Datei abgelehnt |
| Ein fremder Schlüssel wird abgelehnt | eigener Testfall, Befehl lief nicht |
| Ein falsches Passwort wird abgelehnt | eigener Testfall, Befehl lief nicht |
| Ein unbekannter Name wird abgelehnt | eigener Testfall, Befehl lief nicht |
| Kein gemeinsames Verfahren → Abbruch | Chiffre und Schlüsselaustausch je einzeln erzwungen |
| Die Sitzung läuft als der ANGEMELDETE Benutzer | `id` aus der Ferne: uid 1000, nicht 0 |
| Ed25519 (RFC 8032) | Runde UPDATE: 1024 offizielle Vektoren + libsodium |
| X25519 | Runde TUNNEL: gegen den WireGuard des Linux-Kernels |

**Zeitkanal bei der Anmeldung:** ein unbekannter Benutzername wird
trotzdem gegen einen Eintrag gerechnet, der nie stimmt (dieselbe
Vorsicht wie `login` in Runde K13) — sonst wäre an der Antwortzeit
abzulesen, welche Namen es gibt. Der Vergleich des abgeleiteten
Schlüssels läuft in konstanter Zeit (`pw.same_dk`), ebenso der Vergleich
des Poly1305-Merkmals (`chacha.tag_equal`).

**Kryptographie ist nicht erfunden worden.** Jedes Verfahren ist ein
benanntes: SHA-256 (FIPS 180-4), HMAC (RFC 2104), ChaCha20 und Poly1305
(RFC 8439), X25519 (RFC 7748), Ed25519 (RFC 8032), das SSH-AEAD
(OpenSSHs `PROTOCOL.chacha20poly1305`), die Ableitung (RFC 4253 7.2).
Ein Punkt kleiner Ordnung im Schlüsselaustausch (Geheimnis = lauter
Nullen) führt zum Abbruch, wie RFC 8731 Abschnitt 3 es verlangt.

---

## 5. Sicherheitsbewertung — WAS UNGEPRÜFT IST

* **Keine Prüfung durch Dritte, kein Audit.** Was hier steht, ist
  gemessen — gegen Testvektoren, gegen zweite Umsetzungen und gegen den
  echten Klienten. Das ist weit mehr als nichts und weit weniger als ein
  Audit.
* **Nicht in jedem Pfad konstantzeitig.** Die Feldarithmetik in
  `lib/crypto/big.fi` benutzt Montgomery-Multiplikation ohne
  ausdrückliche Maskierung jedes Zweigs; ein Seitenkanalangriff mit
  Zeitmessung auf den Wirtsschlüssel ist **nicht** ausgeschlossen worden.
* **Kein Fuzzing der Parser.** Der Paketleser und der
  Nachrichtenzerleger sind gegen einen *wohlmeinenden* Klienten
  gemessen, nicht gegen einen bösartigen. Alle Längen werden geprüft
  (`wire.Buf` merkt sich Über- und Unterlauf, `pack_in` prüft
  Auffüllung und Grenzen), aber niemand hat systematisch kaputte Pakete
  hineingeschickt.
* **Der Speicher ist statisch, aber nicht formal begrenzt bewiesen.**
  Die Puffer sind feste Felder (`rxraw` 42 000, `pktbuf` 36 000 …); es
  gibt keinen Allokator und damit keine Verkettung freier Blöcke, die
  man beschädigen könnte. Ein Überlauf innerhalb der Felder ist durch
  die Längenprüfungen ausgeschlossen — geprüft durch Lesen, nicht durch
  einen Beweis.
* **Kein Lasttest.** Zwei gleichzeitige Verbindungen sind gemessen.
  Hundert nicht. Die Aufgabentafel des Kerns hat 32 Plätze; wie sich der
  Lauscher verhält, wenn sie voll ist, ist ungemessen.
* **Der Zufall** kommt aus `getrandom` (Nummer 318, `kernel/rand.fi`).
  Wie gut dieser Zufallszahlengeber beim ersten Start einer frisch
  gebooteten Maschine ist, hat diese Runde **nicht** untersucht. Für den
  Wirtsschlüssel und die flüchtigen Schlüssel ist das die
  sicherheitskritischste offene Frage der Runde.

---

## 6. WOVOR ES NICHT SCHÜTZT

1. **Wer die Platte hat, hat den Wirtsschlüssel.** Er liegt als 32
   Oktette rohe Saat in `/etc/ssh/ssh_host_ed25519_key` (0600, root),
   nicht in OpenSSHs `openssh-key-v1`-Behälter und **ohne** Kennwort.
   Ein Angreifer mit Lesezugriff auf das Abbild kann sich danach als
   dieser Server ausgeben.
2. **Wer `/etc/shadow` hat, hat die Passwörter — mit 2048 Runden
   Vorsprung.** PBKDF2-HMAC-SHA256 mit 2048 Runden ist die richtige
   *Bauart* mit einer für heutige Verhältnisse **zu kleinen Zahl**
   (moderne Empfehlungen: 600 000). Runde K13 hat das so entschieden und
   begründet; die Zahl steht im Datensatz und lässt sich erhöhen, ohne
   dass ein bestehendes Passwort ungültig wird.
3. **Kein Schutz gegen Erraten.** Es gibt **keine** Wartezeit nach einem
   Fehlversuch, **keine** Sperre nach n Versuchen über die Verbindung
   hinaus und **kein** `fail2ban`. Nach sechs Fehlversuchen wird *diese*
   Verbindung getrennt — der Angreifer verbindet sich neu. Wer Passwörter
   zulässt und aus dem offenen Netz erreichbar ist, wird durchprobiert.
4. **Keine Neuaushandlung.** Ein KEXINIT mitten in der Sitzung wird mit
   einem Abbruch beantwortet. Eine Verbindung, die stundenlang steht,
   benutzt denselben Sitzungsschlüssel weiter, bis sie abbricht — statt
   ihn zu erneuern.
5. **Terrapin nur, wenn der Klient mitmacht.** `kex-strict-s-v00` wird
   angeboten und angewandt, sobald der Klient `kex-strict-c-v00`
   anbietet (OpenSSH ab 9.6; der Klient in der Abnahme kann es). Ein
   *älterer* Klient bekommt die Gegenmaßnahme nicht — dann bleibt die
   Verbindung gegen CVE-2023-48795 anfällig, wie bei jedem anderen
   Server auch.
6. **Keine Protokollierung.** Es gibt keine Datei, in der steht, wer
   sich wann angemeldet hat. Die Zeilen gehen auf die Konsole und sind
   nach dem Neustart weg. Wer einen Einbruch nachvollziehen will, hat
   nichts.
7. **Kein Schutz gegen einen Angreifer, der schon root ist.** Sagt sich
   von selbst, wird hier trotzdem gesagt: `sshd` läuft als root, weil es
   `setuid` machen muss.
8. **Das Kommando einer `exec`-Sitzung steht kurz als Datei auf der
   Platte.** `/bin/sh` dieses Systems kennt kein `-c`; ein Fernbefehl
   wird deshalb nach `/run/sshd-<pid>.sh` geschrieben (0644, root) und
   als Skript gestartet. Für die Dauer der Sitzung kann **jeder** lokale
   Prozess diese Zeile lesen. Die Datei wird am Ende der Sitzung
   gelöscht. Ein `sh -c` in `kernel/user/sh.fi` würde das beseitigen und
   gehört in eine eigene Runde.
9. **Kein `scp`, kein SFTP.** `scp` benutzt seit OpenSSH 9.0 SFTP, und
   das Unterprotokoll gibt es hier nicht (`scp -O` bräuchte ein
   `/bin/scp` auf Osum). Dateien gehen mit `ssh host cat datei` durch —
   so ist es auch gemessen worden, mit SHA-256 auf beiden Seiten.

---

## 7. Was diese Runde gefunden hat und was nicht ihr gehört

**(a) SIGCHLD bricht blockierende Aufrufe ab, obwohl sein
Standardverhalten „übergehen" ist.** `signal.deliverable`
(`kernel/signal.fi`) sieht nur die anstehenden Bits, nicht die
eingestellte Behandlung — POSIX verlangt `EINTR` aber nur für ein
Signal, das *abgefangen* wird. Für diese Runde umgangen (SIGCHLD wird
maskiert, `-EINTR` wird ausgehalten). **Der Befund gehört in eine
Signal-Runde und ist hier nicht behoben worden**, weil er den Kern
betrifft und andere Programme davon abhängen könnten.

**(b) OFS Fassung 2 kürzt zu lange Dateinamen still.** Ein
Verzeichniseintrag hat 24 Oktette für den Namen, also 23 Zeichen.
`ssh_host_ed25519_key.pub` (24 Zeichen) wurde **ohne Fehlermeldung**
auf 23 gekürzt; der Server merkte nichts, weil er beim Lesen denselben
gekürzten Namen erzeugt, aber `mkfs.py cat` auf dem Wirt fand die Datei
nicht mehr. Umgangen durch kürzere Namen. **Ein `-ENAMETOOLONG` statt
einer stillen Kürzung gehört in eine Dateisystem-Runde.**

**(c) Der Baum hat jetzt DREI SHA-256** (`pw.fi`, `sha.fi`,
`lib/crypto/sha256.fi`). Die neue ist die einzige, die überall
hinbindbar ist; die beiden alten stehen noch, weil fünf Programme sie
benutzen. Die Zusammenlegung ist eine eigene, kleine Aufgabe.

---

## 8. Der Weg zurück, für den nächsten

```bash
git worktree add -b sshd /pfad mergeline
git merge poll && git merge update
bash tools/sshd/run.sh          # ~12 Minuten unter Last, 67 Zusagen
```

Was als nächstes fehlt, in der Reihenfolge des Nutzens:

1. **`sh -c`** — dann braucht ein Fernbefehl keine Datei mehr (Punkt 8
   oben), und `scp -O` wäre erreichbar.
2. **Ein SSH-Klient auf Osum** (`/bin/ssh`). Die halbe Arbeit liegt
   schon in `lib/ssh/`; es fehlen die Klientenhälfte des Handschlags und
   `known_hosts`.
3. **`sftp-server`** als Unterprotokoll — dann funktioniert `scp` und
   `sftp` ohne Umweg.
4. **Protokollierung** nach `/var/log/`, sonst ist ein Einbruch nicht
   nachvollziehbar.
5. **Wartezeit nach Fehlversuchen** und eine Sperre je Adresse.
6. **Der Zufallszahlengeber beim Kaltstart** — die offene Frage aus
   Abschnitt 5.
