# STATUS — Runde MULTIUSER

Zweig `multiuser`, abgezweigt von `mergeline` (4f844b5). **Nicht** nach
`main` mergen.

Stand: 28.08.2026, laufend. Zahlen in dieser Datei sind gemessen, nicht
geschätzt; wo noch nichts gemessen ist, steht nichts.

---

## 0. Der Befund — und warum er der Auftragsbeschreibung widerspricht

Der Auftrag sagt: *„Es gibt kein /etc/passwd, keine Anmeldung, keine
Trennung von Rechten zwischen Nutzern. In kernel/sched.fi, fs.fi,
uprog.fi tauchen uid-artige Begriffe auf — prüfe zuerst genau, was davon
echt ist und was nur Namensgleichheit."*

**Nachgemessen: das stimmt für diesen Zweig nicht.** Runde K13 (`k13-user`,
Commit 329df51, 26.08.2026) ist über `k-merge2` → `main` → `mergeline`
längst eingeflossen. `git merge-base --is-ancestor k13-user mergeline`
sagt ja. Was auf `mergeline` steht, bevor diese Runde eine Zeile ändert:

| Zusage | Zustand auf `mergeline` | belegt durch |
|---|---|---|
| uid/gid je Prozess | **da**, echt/wirksam/gesichert, 7 Wörter im Aufgabensatz | `kernel/sched.fi` T_UID=392 … T_UMASK=440 |
| Vererbung über fork/exec | **da** | `sched.fi:678–684` (`create` kopiert vom Elternteil) |
| setuid/setgid, nur root | **da**, 24 Linux-Nummern | `kernel/sys.fi`, `lib/libc/kcall.fi` |
| Rechte im Inode (OFS) | **da**, mode/uid/gid, OFS-Fassung 2 | `kernel/fs.fi` I_MODE=88, I_UID=96, I_GID=104 |
| Rechteprüfung an EINER Stelle | **da** | `kernel/perm.fi`, `may_ids` |
| /etc/passwd, /etc/shadow | **da**, klassisches Format | `kernel/user/pw.fi` |
| login, su, passwd, id, chmod, chown | **da** | `kernel/user/*.fi` |
| Passwort nicht im Klartext | **da**, PBKDF2-HMAC-SHA256, 8 Oktett Salz | `kernel/user/pw.fi` |
| Abnahme dafür | **da**, `tools/k13/run.sh` | 93 Zusagen, 0 Fehler (heute nachgefahren) |

Gegenprobe, dass das nicht nur dasteht, sondern läuft: `bash
tools/k13/run.sh` auf dem frischen Zweig, **93 OK / 0 FAIL** (Abschnitt 9
läuft beim Nachfahren noch). Also: die Ausgangslage der
Auftragsbeschreibung ist die von `main` **vor** K13, nicht die von
`mergeline`.

### Was WIRKLICH fehlt

Die ehrliche Grenzenliste steht in `docs/ROUNDK13.md` Abschnitt 7 und im
Gedächtnis-Eintrag zu K13. Nachgeprüft, welche davon noch offen sind:

1. **Kein `/etc/group`, keine Zusatzgruppen.** `grep -r 'etc/group'` im
   ganzen Baum: kein Treffer außer in fremden Testdaten. Ein Prozess hat
   genau eine Gruppe.
2. **Betretungsrecht nur am LETZTEN Verzeichnis eines Pfades.**
   `kernel/fs.fi:resolve` (Zeile 1789) läuft die Bestandteile eines
   Pfades ab und fragt **nie** nach Rechten. `perm.may` wird in
   `kernel/sys.fi` genau neunmal gerufen, immer auf die Zieldatei. Ein
   Verzeichnis `0o700 root:root` schützt also seinen Inhalt **nicht**,
   wenn der Name der Datei darin bekannt ist.
3. **Die Prüfung sieht nur OFS.** `perm.may_ids` ruft
   `fs.inode_mode/uid/gid` unmittelbar — also die OFS-Inode. Über die
   VFS-Schicht (`kernel/vfsops.fi`) gibt es `A_MODE`, aber **kein
   `A_UID`/`A_GID`**. Für FAT32, /proc und /dev gibt es damit keine
   Eigentümerfrage.
4. **2048 PBKDF2-Runden.** Die Zahl steht als „zu wenig" schon in
   `kernel/user/pw.fi`. Dazu kommt eine harte Obergrenze:
   `check_hash` weist jeden Eintrag mit `iters > 100000` ab.
5. **`login` wartet nach einem Fehlversuch nicht** und zählt Fehlversuche
   nicht über seine Lebensdauer. Steht als Grenze im Kopf von
   `kernel/user/login.fi`.
6. **`passwd` schreibt `/etc/shadow` ohne Zwischendatei.** Ein Absturz
   mitten im Schreiben lässt die Datei halb da.
7. **`su` kennt kein `-c`.**
8. **Sticky-Bit wird gespeichert, nicht beachtet.**
9. **FAT32 kann keine Rechte** — das ist richtig so und gehört
   dokumentiert, nicht gefälscht.

Diese Runde arbeitet an 1–7 und dokumentiert 9. Punkt 8 bleibt und steht
am Ende in der Lückenliste.

---

## 1. Aufrufnummern (Auflage 5 des Auftrags)

`tools/kernel/syscalls.py` ist neu: es liest `kernel/sys.fi` **und**
`lib/libc/kcall.fi`, und es meldet
(a) jede doppelt vergebene Nummer, (b) jeden Namen mit zwei Nummern,
(c) jeden Namen, den die libc kennt und der Kernel nicht.

Gemessener Stand von `mergeline` **vor** dieser Runde:

    syscalls: 141 im Kernel, 141 in der libc, 141 gemeinsam,
    keine Nummer doppelt, kein Name mit zwei Nummern

Der 1320er-Fall aus Runde MERGE ist also bereits behoben (NETVIEW wurde
auf 1314 gerückt, siehe `kernel/sys.fi` bei `SYS_OSUM_HOTKEY`); was
fehlte, war der Wächter, der es so lässt.

`--zweige` fragt **git** statt des eigenen Baums, weil eine Nummer, die
hier frei ist und auf einem Nachbarzweig vergeben, beim Verschmelzen
genau der Fehler von damals wäre. Über **alle 51 Zweige** dieses Repos
gerechnet ist frei:

    1005..1099  1103..1299  1302..1309  1315..1319  1323..1399
    1405..1499  1505..1599  1601..1699  1704..1749  ...

Diese Runde nimmt:

| Nummer | Name | warum diese |
|---:|---|---|
| 115 | `SYS_GETGROUPS` | die **echte** Linux-x86-64-Nummer, in beiden Tabellen frei |
| 116 | `SYS_SETGROUPS` | dito |
| 1200 | `SYS_OSUM_MUSTAT` | erster Wert des Blocks 1200..1299, der auf **jedem** Zweig frei ist |

---

## 2. Fortschritt

- [erledigt] Ausgangslage gemessen (oben), Grundlinie `tools/k13/run.sh`
  93 OK / 0 FAIL
- [erledigt] `tools/kernel/syscalls.py`, Nummernblock nachgewiesen frei
- [offen] /etc/group + Zusatzgruppen
- [offen] Passwortableitung mit Kostenfaktor, Zeit gemessen
- [offen] Betretungsrecht über den ganzen Pfad
- [offen] Eigentümer über die VFS-Schicht, FAT dokumentiert
- [offen] login/su/passwd
- [offen] Abschnitt `tools/multiuser/run.sh` unter `-accel kvm`

## 3. Zahlen

| was | Wert | wie gemessen |
|---|---|---|
| QEMU | 7.2.22 (Debian) | `qemu-system-x86_64 --version` |
| Kernel bauen, Stufe 0 | 4 s | `tools/build-kernel.sh` |
| ein Kernellauf, TCG | 2013 ms | `script=id`, `-no-reboot` |
| ein Kernellauf, KVM (`-accel kvm -cpu host`) | 788 ms | derselbe Lauf |
| Verhältnis | **2,6×** auf diesem trivialen Lauf | — |

(Der Auftrag nennt 4,6×; auf einem Lauf, der fast nur startet und
abschaltet, ist der Anteil, den KVM beschleunigen kann, kleiner. Der
rechenlastige Teil dieser Runde — PBKDF2 — wird getrennt gemessen.)
