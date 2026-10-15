#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/mail/stub.py -- tiny IMAP4 + SMTP test server (TLS or plain) for tools/mail/run.sh.
#
#   stub.py <outdir> <tls|plain> [cert key]
#
# Writes "<imap_port> <smtp_port>" to <outdir>/ports once both listen. Accepts the one
# account justin / geheim. Mails received by SMTP land in <outdir>/msg-N.eml (after
# undoing dot-stuffing). Not a mail server: just enough protocol for the client gate.
import base64, os, socket, ssl, sys, threading

OUT = sys.argv[1]
MODE = sys.argv[2]
CERT = sys.argv[3] if len(sys.argv) > 4 else None
KEY = sys.argv[4] if len(sys.argv) > 4 else None

MSGS = [
    (b"From: =?utf-8?B?SsO8cmdlbg==?= <juergen@example.org>\r\n"
     b"Subject: Hallo\r\n Welt\r\n"
     b"Date: Wed, 14 Oct 2026 09:00:00 +0200\r\n"
     b"To: justin@example.org\r\n\r\n"
     b"Erste Nachricht.\r\nZeile zwei.\r\n"),
    (b"From: Bank <bank@example.org>\r\n"
     b"Subject: =?iso-8859-1?Q?Gr=FC=DFe?=\r\n"
     b"Date: Wed, 14 Oct 2026 10:00:00 +0200\r\n"
     b"To: justin@example.org\r\n"
     b"Content-Transfer-Encoding: quoted-printable\r\n\r\n"
     b"caf=C3=A9 ist teuer.\r\na005 OK this is body text, not a status line\r\n"),
    (b"From: x@example.org\r\n"
     b"Subject: Drei\r\n"
     b"Date: Thu, 15 Oct 2026 08:00:00 +0200\r\n"
     b"To: justin@example.org\r\n"
     b"Content-Transfer-Encoding: base64\r\n\r\n"
     + base64.encodebytes(b"base64 body\n")),
]


def wrap(conn):
    if MODE != "tls":
        return conn
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(CERT, KEY)
    return ctx.wrap_socket(conn, server_side=True)


def readline(f):
    return f.readline()


def imap(conn):
    try:
        conn = wrap(conn)
    except Exception:
        return
    f = conn.makefile("rwb", buffering=0)
    f.write(b"* OK stub IMAP ready\r\n")
    authed = False
    while True:
        line = f.readline()
        if not line:
            break
        parts = line.strip().split(b" ", 2)
        if len(parts) < 2:
            f.write(b"* BAD empty\r\n")
            continue
        tag, cmd = parts[0], parts[1].upper()
        rest = parts[2] if len(parts) > 2 else b""
        if cmd == b"LOGIN":
            if rest == b'"justin" "geheim"':
                authed = True
                f.write(tag + b" OK LOGIN completed\r\n")
            else:
                f.write(tag + b" NO [AUTHENTICATIONFAILED] bad credentials\r\n")
        elif not authed:
            f.write(tag + b" BAD login first\r\n")
        elif cmd == b"LIST":
            f.write(b'* LIST (\\HasNoChildren) "/" INBOX\r\n'
                    b'* LIST (\\Sent) "/" "Sent Items"\r\n'
                    + tag + b" OK LIST done\r\n")
        elif cmd == b"SELECT":
            if rest.strip(b'"') == b"INBOX":
                f.write(b"* %d EXISTS\r\n* 0 RECENT\r\n" % len(MSGS)
                        + tag + b" OK [READ-WRITE] SELECT done\r\n")
            else:
                f.write(tag + b" NO no such mailbox\r\n")
        elif cmd == b"FETCH":
            seqs = rest.split(b" ", 1)[0]
            if b":" in seqs:
                a, b = seqs.split(b":")
            else:
                a = b = seqs
            out = b""
            for n in range(int(a), int(b) + 1):
                if n < 1 or n > len(MSGS):
                    continue
                m = MSGS[n - 1]
                if b"HEADER.FIELDS" in rest:
                    hdr = m.split(b"\r\n\r\n")[0] + b"\r\n\r\n"
                    out += (b"* %d FETCH (BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {%d}\r\n"
                            % (n, len(hdr))) + hdr + b")\r\n"
                else:
                    out += (b"* %d FETCH (BODY[] {%d}\r\n" % (n, len(m))) + m + b")\r\n"
            f.write(out + tag + b" OK FETCH completed\r\n")
        elif cmd == b"STORE":
            f.write(tag + b" OK STORE done\r\n")
        elif cmd == b"LOGOUT":
            f.write(b"* BYE bye\r\n" + tag + b" OK LOGOUT done\r\n")
            break
        else:
            f.write(tag + b" BAD unknown command\r\n")
    conn.close()


COUNT = [0]


def smtp(conn):
    try:
        conn = wrap(conn)
    except Exception:
        return
    f = conn.makefile("rwb", buffering=0)
    f.write(b"220 stub ESMTP ready\r\n")
    authed = False
    frm = None
    rcpts = []
    while True:
        line = f.readline()
        if not line:
            break
        up = line.strip().upper()
        if up.startswith(b"EHLO"):
            f.write(b"250-stub\r\n250-AUTH PLAIN\r\n250 8BITMIME\r\n")
        elif up.startswith(b"AUTH PLAIN"):
            blob = base64.b64decode(line.split()[2])
            if blob == b"\0justin\0geheim":
                authed = True
                f.write(b"235 2.7.0 ok\r\n")
            else:
                f.write(b"535 5.7.8 bad credentials\r\n")
        elif up.startswith(b"MAIL FROM:"):
            if not authed:
                f.write(b"530 5.7.0 auth first\r\n")
                continue
            frm = line.strip()[10:]
            rcpts = []
            f.write(b"250 ok\r\n")
        elif up.startswith(b"RCPT TO:"):
            rcpts.append(line.strip()[8:])
            f.write(b"250 ok\r\n")
        elif up == b"DATA":
            f.write(b"354 go ahead\r\n")
            body = b""
            while True:
                l = f.readline()
                if not l or l == b".\r\n":
                    break
                if l.startswith(b".."):
                    l = l[1:]
                body += l
            COUNT[0] += 1
            with open(os.path.join(OUT, "msg-%d.eml" % COUNT[0]), "wb") as o:
                o.write(b"X-Stub-From: " + frm + b"\r\nX-Stub-To: " + b",".join(rcpts) + b"\r\n" + body)
            f.write(b"250 queued\r\n")
        elif up == b"QUIT":
            f.write(b"221 bye\r\n")
            break
        else:
            f.write(b"500 what\r\n")
    conn.close()


def serve(handler):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 0))
    s.listen(8)

    def loop():
        while True:
            c, _ = s.accept()
            threading.Thread(target=handler, args=(c,), daemon=True).start()
    threading.Thread(target=loop, daemon=True).start()
    return s.getsockname()[1]


p1 = serve(imap)
p2 = serve(smtp)
with open(os.path.join(OUT, "ports.tmp"), "w") as o:
    o.write("%d %d\n" % (p1, p2))
os.rename(os.path.join(OUT, "ports.tmp"), os.path.join(OUT, "ports"))
threading.Event().wait()
