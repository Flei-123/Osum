# STATUS — Runde MULTIUSER

Zweig `multiuser`, abgezweigt von `mergeline` (4f844b5). **Nicht** nach
`main` mergen.

Alle Zahlen hier sind gemessen. Wo nichts gemessen ist, steht nichts.
Die ausführliche Fassung mit den Begründungen steht in
`docs/ROUNDMULTIUSER.md`.

---

## 0. Der Befund — er widerspricht der Auftragsbeschreibung

Der Auftrag sagt: *„Es gibt kein /etc/passwd, keine Anmeldung, keine
Trennung von Rechten zwischen Nutzern"* und *„nicht auf meine
Beschreibung verlassen, selbst messen."* Selbst gemessen:

    $ git merge-base --is-ancestor k13-user mergeline && echo ja
    ja
    $ bash tools/k13/run.sh            # auf dem frischen Zweig
    K13: 99 passed, 0 failed

**Runde K13 ist längst eingeflossen.** Vor dieser Runde standen auf
`mergeline` bereits:

| Zusage | belegt durch |
|---|---|
| uid/gid je Prozess, echt/wirksam/gesichert | `sched.fi` T_UID=392 … T_UMASK=440 |
| Vererbung über fork/exec | `sched.fi:678–684` |
| setuid/setgid, nur für root, 24 Linux-Nummern | `sys.fi`, `lib/libc/kcall.fi` |
| mode/uid/gid im OFS-Inode | `fs.fi` I_MODE=88, I_UID=96, I_GID=104 |
| Rechteprüfung an EINER Stelle | `perm.fi`, `may_ids` |
| /etc/passwd, /etc/shadow, PBKDF2 | `kernel/user/pw.fi` |
| login, su, passwd, id, chmod, chown | `kernel/user/*.fi` |

Die Beschreibung im Auftrag ist die von `main` **vor** K13. Was fehlte,
steht in `docs/ROUNDK13.md` Abschnitt 7 als ehrliche Grenzenliste — und
genau diese Liste ist der Auftrag dieser Runde geworden.

---

## 1. Was diese Runde gebaut hat

| # | Sache | Datei |
|---|---|---|
| 1 | **Betretungsrecht auf JEDEM Glied eines Pfades** (`perm.walk`), 12 Aufrufstellen + `rename` | `kernel/perm.fi`, `kernel/sys.fi` |
| 2 | **Zusatzgruppen**: `/etc/group`, `getgroups`(115)/`setgroups`(116), `initgroups` in login/su, `id groups=` | `pw.fi`, `sched.fi`, `sys.fi`, `login.fi`, `su.fi`, `id.fi` |
| 3 | **Rechteprüfung über die VFS-Schicht** — `open_vfs` hatte keine; `A_UID`/`A_GID` in der Ops-Tafel | `vfsops.fi`, `ofs.fi`, `fat.fi`, `sys.fi` |
| 4 | **Kostenfaktor aus einer Messung**: PBKDF2 2048 → 8192, Obergrenze 100 000 → 10 000 000, `/etc/login.conf` | `pw.fi` |
| 5 | **Verzögerung nach Fehlversuch**, verdoppelnd, Zähler über die Lebensdauer; `su` wartet auch | `login.fi`, `su.fi` |
| 6 | **`passwd` über eine Zwischendatei**, vier Schritte, Rechte + Eigentümer erhalten | `pw.fi` |
| 7 | **`rename` bekommt Rechte** (hatte keine) und geht ohne die VFS-Schicht (war `-ENOSYS`) | `sys.fi` |
| 8 | **Wächter für die Aufrufnummern**, Kernel + libc + über alle git-Zweige | `tools/kernel/syscalls.py` |
| 9 | **`su -c`**, `chown` löst Gruppennamen aus `/etc/group` auf | `su.fi`, `chown.fi` |
| 10 | Der Abschnitt selbst, unter `-accel kvm` | `tools/multiuser/run.sh`, `test.sh` #29 |

Neue Dateien: `kernel/user/mut.fi` (Selbsttest in Ring 3),
`tools/kernel/syscalls.py`, `tools/multiuser/run.sh`,
`docs/ROUNDMULTIUSER.md`.

---

## 2. Aufrufnummern (Auflage 5 des Auftrags)

Vor der Runde, gemessen:

    syscalls: 141 im Kernel, 141 in der libc, 141 gemeinsam,
    keine Nummer doppelt, kein Name mit zwei Nummern

Der 1320er-Fall von Runde MERGE war bereits behoben (NETVIEW auf 1314
gerückt). Was fehlte, war der Wächter, der es so lässt.

`--zweige` fragt **git** statt des eigenen Baums. Über alle 51 Zweige
frei: `1005…1099 · 1103…1299 · 1302…1309 · 1315…1319 · 1323…1399 ·
1405…1499 · 1505…1599 · 1601…1699 · …`

Genommen: **115** `getgroups`, **116** `setgroups` (die echten
Linux-Nummern — K13 hat 113, 114, 117…120 belegt und diese beiden
ausgelassen) und **1200** `SYS_OSUM_MUSTAT` (erster Wert eines Blocks,
der auf *jedem* Zweig unbenutzt ist).

Nach der Runde: `144 im Kernel, 144 in der libc, keine doppelt`.
Gegenprobe im Abschnitt: die 1320 von damals wird nachgebaut und **muss**
auffallen — sie tut es.

---

## 3. Die Messungen

Wirt: AMD EPYC 7571, 12 Kerne, 19 GB, QEMU 7.2.22 (Debian), `/dev/kvm`
vorhanden.

### PBKDF2-HMAC-SHA256, eine Prüfung

| Umgebung | Runden/s | 8192 Runden |
|---|---:|---:|
| Osum, `-accel kvm -cpu host`, **ruhige** Maschine | 31 437 | **0,26 s** |
| Osum, TCG, ruhige Maschine | 4 430 | 1,85 s |
| Osum, KVM, **während vier andere Runden liefen** (`load` 17) | 6 150 | 1,33 s |
| derselbe Wirt, OpenSSL hinter Pythons `hashlib` | 1 768 429 | 0,0046 s |

Aus Zeile 1 folgt der Kostenfaktor **8192**: 0,26 s je Anmeldung ist das
Budget, auf das die übliche Empfehlung hinausläuft. Aus Zeile 4 folgt die
unangenehme Zahl: OpenSSL ist **56×** schneller als dieses SHA-256 in
Firn, ein Angreifer schafft also rund **216 Rateversuche je Sekunde und
Kern**. Deshalb baut diese Runde *zusätzlich* die Verzögerung.

Der Abschnitt prüft deshalb **keinen festen Wert**, sondern eine untere
Schranke und das **Verhältnis** 2048 : 8192, das 1 : 4 sein muss (bei
Last gemessen: 3,04 : 1 bis 4,03 : 1).

### QEMU: KVM gegen TCG

| Lauf | KVM | TCG | Faktor |
|---|---:|---:|---:|
| Kernel starten und abschalten (`script=id`) | 788 ms | 2013 ms | 2,6× |
| 8192 PBKDF2-Runden, ruhige Maschine | 0,26 s | 1,85 s | **7,1×** |
| 8192 PBKDF2-Runden, `load` 17 | 1,33 s | 2,68 s | 2,0× |

Der Auftrag nennt 4,6×. Auf reiner Rechenlast und ohne Konkurrenz ist es
mehr, auf einem Lauf, der fast nur startet, weniger — und unter Last
verschwindet der Unterschied fast, weil dann beide auf denselben Kernen
warten.

---

## 4. Abnahme

| Lauf | Ergebnis |
|---|---|
| `tools/k13/run.sh` vor der Runde (Grundlinie) | 93 OK / 0 FAIL (Abschnitte 1–8) |
| `tools/k13/run.sh` nach den Kernelaenderungen | 99 OK / 0 FAIL |
| `tools/k13/run.sh` nach dem Userland | *siehe unten* |
| `tools/multiuser/run.sh`, erster Lauf | 81 OK / 6 FAIL |
| `tools/multiuser/run.sh`, zweiter Lauf | *siehe unten* |

Die sechs Fehler des ersten Laufs waren **alle echte Befunde**, keiner
davon im Kernel:

1. `chown justin:projekt` schlug fehl — `chown` löste Gruppennamen über
   `/etc/passwd` auf statt über `/etc/group`.
2. + 3. Die Wandzeitmessung war 0, weil `rc=$(run_case …)` in einer
   **Unterschale** läuft und `$DAUER` dort nie ankommt. Die Null war
   nicht die Verzögerung, sondern die Unterschale.
3. Die Gegenprobe `nowalk` traf die Lücke nicht: mit `/geheim/inhalt.txt`
   (eine Ebene) hielt schon K13s `dir_allowed`. Umgestellt auf
   `/zu/tief/inhalt.txt` — dort wurde `/zu/tief` gefragt und `/zu` nie.
   **Das war der wichtigste Befund: er hat gezeigt, dass die Lücke
   genauer ist, als sie im Auftrag steht.**
4. Zwei Textfehler im Läufer selbst.

---

## 5. Die Lücken, die bleiben

Kurzfassung; ausgeschrieben in `docs/ROUNDMULTIUSER.md` Abschnitt 9.

1. **Symbolische Verweise** umgehen `perm.walk` teilweise — geprüft
   werden die Glieder des *geschriebenen*, nicht des aufgelösten Pfades.
2. **Zwei Durchgänge** je Pfad (`walk` + `fs.path`). Der Preis dafür,
   `fs.fi` nicht anzufassen. Messbar, nicht gemessen.
3. **`rename` ersetzt nicht** (`-EEXIST`, Entscheidung aus K14). Deshalb
   die vier Schritte in `passwd` und ein Fenster von zwei
   Verzeichnisoperationen.
4. **Sticky-Bit** wird gespeichert, nicht beachtet.
5. **`/dev` ist zu großzügig**: Blockgeräte tragen `0644 root` — lesen
   darf jeder. Diese Runde verhindert das *Schreiben*; die rohe Platte
   lesbar zu lassen bleibt falsch.
6. **Keine Passwortalterung**, `max_versuche` sperrt kein Konto.
7. **Kein `newgrp`, `usermod`, `groupadd`**.
8. **`su -c`** nimmt keine Zeichenkette mit Shell-Syntax.
9. **Argon2id fehlt** — es braucht BLAKE2b und Speicher, den ein
   Programm dieses Userlands nicht allozieren kann. Die Eintragsform
   (`$osum1$`) ist auf ein `$osum2$` daneben vorbereitet.
10. **Zusatzgruppen in einer zweiten Tabelle** — der Aufgabensatz hat
    genau ein freies Wort.
11. **`perm.walk` sperrt nicht**: es schreibt vorübergehend eine Null in
    den Pfadpuffer des Aufrufers, ohne `enter`/`leave` wie `fs.fi`.
