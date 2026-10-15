# MAIL -- mail client library (first version, 15.10.2026)

`lib/mail/wire.fi` (no I/O): IMAP4rev1 + SMTP client formats, literal-aware IMAP response end, RFC 5322 header
unfolding, RFC 2047 words (B/Q, utf-8 + Latin-1), base64, quoted-printable, dot-stuffing, `compose`.
`lib/mail/session.fi` (profile app): `Link` over TCP or TLS 1.3 (certificate chain + host name checked against a PEM
trust file, no insecure mode), IMAP (login, LIST, SELECT, FETCH headers/body, STORE \Seen, LOGOUT) and SMTP
(EHLO, AUTH PLAIN, MAIL/RCPT/DATA, QUIT) as step functions returning `E_*` codes.

Gate: `bash tools/mail/run.sh` -- oracle 50 promises, TLS + plain sessions against `tools/mail/stub.py` (30 steps each),
sent mails compared byte-exact, negative controls (wrong name / empty trust store -> E_CERT, wrong password -> E_AUTH,
literal-blind mutation -> oracle red). 123/0.

## Mail app (15.10.2026)

`lib/mail/model.fi` (no window): settings, folders, newest-64 list, reading (text, RFC 2047 headers, QP/base64
body, cut at 4000 octets for the 4096 memo), sending (From = user or user@imap-host, Date UTC, Message-ID).
`kernel/user/mail.fi` (fUi window, profile app): setup form -> folder table + message table + reading pane
-> compose. Package `pakete/mail` (net=real), built by `pakete/bauen.sh`. Settings (no password) in /etc/mail.conf.
Gate: `bash tools/mailapp/run.sh` (= `tools/mail/app.sh`: model vs stub over TLS + plain, mutation control, build +
package); `bash tools/mail/app.sh gui` = QEMU session (opt-in, `tools/mail/gui.sh`, test file /etc/mail.test).

NOT DONE: STARTTLS, multipart/attachments, reply/forward, address book, password storage, IDLE/push,
paging beyond 64 messages, search.
