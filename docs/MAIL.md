# MAIL -- mail client library (first version, 15.10.2026)

`lib/mail/wire.fi` (no I/O): IMAP4rev1 + SMTP client formats, literal-aware IMAP response end, RFC 5322 header
unfolding, RFC 2047 words (B/Q, utf-8 + Latin-1), base64, quoted-printable, dot-stuffing, `compose`.
`lib/mail/session.fi` (profile app): `Link` over TCP or TLS 1.3 (certificate chain + host name checked against a PEM
trust file, no insecure mode), IMAP (login, LIST, SELECT, FETCH headers/body, STORE \Seen, LOGOUT) and SMTP
(EHLO, AUTH PLAIN, MAIL/RCPT/DATA, QUIT) as step functions returning `E_*` codes.

Gate: `bash tools/mail/run.sh` -- oracle 50 promises, TLS + plain sessions against `tools/mail/stub.py` (30 steps each),
sent mails compared byte-exact, negative controls (wrong name / empty trust store -> E_CERT, wrong password -> E_AUTH,
literal-blind mutation -> oracle red). 123/0.

NOT DONE (next): the fUi window `kernel/user/mail.fi` (account setup, folder list `table_blob`, message list, read pane
`memo` (4096 octet cap), compose), launcher/store registration, STARTTLS, multipart/attachments, config persistence,
password storage. Pattern for the app: `kernel/user/fvviewer.fi` (profile app + TLS + fuiscene), `libc.dns.resolve_a` for
host names, entries via `fuiscene.entry`, tables via blob text (rows `\n`, cells `\t`).
