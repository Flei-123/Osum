#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/fvviewer/wstest.py -- lib/net/ws.fi against an independent peer
# (Python `websockets`). Starts the Firn host driver as a subprocess.
#
#   python3 tools/fvviewer/wstest.py <wstest-binary> [slow]
#
# The server sends text/binary of several lengths (7/16/64-bit headers), a
# fragmented message, a ping; the client must report every event with the
# exact length and octet sum, answer the ping, and its own masked frames
# (incl. a 70000-octet one and a fragmented one) must arrive intact.
import asyncio, sys
from websockets.asyncio.server import serve

def pat(n):
    return bytes((i * 7 + 3) & 255 for i in range(n))

def ev(kind, data):
    return "EV %d %d %d" % (kind, len(data), sum(data))

async def run(binary, slow):
    got = {}
    expect_server_view = [
        "hello-client",
        pat(200),
        pat(70000),
        "abcdefghi",
    ]

    async def handler(ws):
        try:
            await ws.send("hello-server")
            await ws.send(pat(300))
            await ws.send(pat(70000))
            await ws.send(pat(0))                     # empty binary
            await ws.send([b"a" * 10, b"b" * 20, b"c" * 30])   # 3 fragments
            await ws.send("é" * 5)                    # text, multi-byte
            await ws.ping(b"srvping")
            seen = []
            for _ in expect_server_view:
                seen.append(await asyncio.wait_for(ws.recv(), 10))
            got["seen"] = seen
            await ws.close(1000, "bye")
        except Exception as e:  # noqa
            got["err"] = repr(e)

    async with serve(handler, "127.0.0.1", 0, max_size=2**22) as server:
        port = server.sockets[0].getsockname()[1]
        args = [binary, str(port)] + (["slow"] if slow else [])
        p = await asyncio.create_subprocess_exec(
            *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
        out, _ = await asyncio.wait_for(p.communicate(), 60)
        lines = out.decode().splitlines()
    want = [
        "UPGRADED",
        ev(1, b"hello-server"),
        ev(2, pat(300)),
        ev(2, pat(70000)),
        ev(2, b""),
        ev(2, b"a" * 10 + b"b" * 20 + b"c" * 30),
        ev(1, "é".encode() * 5),
        ev(9, b"srvping"),
        ev(8, b"\x03\xe8bye"),
        "DONE",
    ]
    ok = True
    if lines != want:
        ok = False
        print("CLIENT LINES DIFFER")
        for i in range(max(len(lines), len(want))):
            a = lines[i] if i < len(lines) else "<none>"
            b = want[i] if i < len(want) else "<none>"
            print("  %s %r vs %r" % ("ok " if a == b else "BAD", a, b))
    if got.get("seen") != expect_server_view:
        ok = False
        print("SERVER VIEW DIFFERS", got.get("err"), [type(x).__name__ + str(len(x)) for x in got.get("seen", [])])
    print("WSTEST", "PASS" if ok else "FAIL", "(slow)" if slow else "")
    return 0 if ok else 1

sys.exit(asyncio.run(run(sys.argv[1], len(sys.argv) > 2)))
