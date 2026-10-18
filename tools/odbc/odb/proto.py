# SPDX-License-Identifier: GPL-2.0-only
"""Payload layer on top of the frames. ALL knowledge about request/response
payload encoding lives here, so adapting to docs/ODB.md touches this file only.

Draft "O2-0" (used until W-O1's spec lands; additive to the frame layer):
  REQ  payload: "<op>\\n" then "key=value\\n" lines. Value escapes: \\\\ \\n \\r.
  RESP payload: "key=value\\n" lines (single-shot answer).
  DATA payload: raw bytes; flags bit0 = stderr stream (exec), bit1 = last chunk hint.
  END  payload: "key=value\\n" lines (code=, size=, crc32=, ...).
  ERR  payload: "code=<n>\\nmsg=<text>\\n".
  PING payload: any bytes; the agent echoes a PING with the same id.
"""
from . import frame as F

FLAG_STDERR = 1


def esc(s):
    return str(s).replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")


def unesc(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "r": "\r", "\\": "\\"}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def enc_kv(d):
    return "".join("%s=%s\n" % (k, esc(v)) for k, v in d.items() if v is not None).encode()


def dec_kv(b):
    d = {}
    for line in b.decode("utf-8", "replace").split("\n"):
        if not line:
            continue
        k, _, v = line.partition("=")
        d[k] = unesc(v)
    return d


def enc_req(op, args=None):
    return (op + "\n").encode() + enc_kv(args or {})


def dec_req(b):
    head, _, rest = b.partition(b"\n")
    return head.decode(), dec_kv(rest)


class AgentError(Exception):
    def __init__(self, code, msg):
        super().__init__("agent error %s: %s" % (code, msg))
        self.code = code
        self.msg = msg


def dec_err(b):
    d = dec_kv(b)
    try:
        c = int(d.get("code", "0"))
    except ValueError:
        c = -1
    return AgentError(c, d.get("msg", ""))
