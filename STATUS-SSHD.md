# RUNDE SSHD — Zwischenstand

Zweig `sshd`, abgezweigt von `mergeline` (4f844b5), Arbeitsbaum
`/root/sshd-osum`. Ziel: ein SSH-2-Server auf Osum, an dem sich der
ECHTE OpenSSH-Klient anmeldet.

## Ausgangslage, nachgemessen (nicht behauptet)

    $ git log --oneline mergeline -1
    4f844b5 STATUS-MERGE: Zwischenstand nach dem Merge von kvmfix
    $ grep -ril 'ssh' --include='*.fi' . | wc -l
    0

Es gab kein SSH im Baum. Was es gab und was diese Runde benutzt:

| Baustein | wo | aus welcher Runde |
|---|---|---|
| X25519 | `lib/crypto/x25519.fi` | TUNNEL |
| Ed25519 (RFC 8032) | `lib/crypto/ed25519.fi` | UPDATE |
| SHA-512 | `lib/crypto/sha512.fi` | UPDATE |
| ChaCha20 + Poly1305 | `lib/crypto/chacha.fi` | TUNNEL |
| `poll` (Nummer 7) | `kernel/sys.fi`, `lib/libc/io.fi` | POLL |
| Sockets (Linux-Nummern) | `kernel/sys.fi`, `lib/libc/net.fi` | K8 |
| `/etc/passwd`, `/etc/shadow`, uid/gid | `kernel/user/pw.fi`, `kernel/perm.fi` | K13 |
| `init` + `/etc/inittab` | `kernel/user/init.fi` | K13 |
| Pseudoterminal (`SYS_OSUM_PTY` 1100) | `kernel/sys.fi` | K9 |

## Schritt 0 — die Abhaengigkeiten geholt

`poll` und `update` hatten beide schon Ergebnisse, also wurden BEIDE in
diesen Zweig gemergt (beide sauber, kein Konflikt):

    git merge poll     # fast-forward, 12 Dateien
    git merge update   # 47 Dateien

Damit stehen `poll` UND Ed25519 zur Verfuegung, und es musste nichts
gegen eine gedachte Schnittstelle gebaut werden.

## Zur Nutzerverwaltung (Auftragspunkt 3)

Eine Runde `multiuser` mit einem Zweig `multiuser` gibt es in diesem
Repo NICHT — `git branch -a` kennt keinen. Was es gibt, ist Runde
**K13** (`k13-user`), und die ist laengst in `main`/`mergeline`: echte
uid/gid je Prozess, `/etc/passwd`, `/etc/shadow` mit
PBKDF2-HMAC-SHA256, `setuid`/`setgid`, `kernel/perm.fi`. `sshd` bindet
daran an und braucht KEINE Uebergangsloesung.
