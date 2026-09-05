#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/bridge/weiter.py -- ein Weiterleiter aus dem Netzraum zum Wirt.

    weiter.py <lauschadresse> <lauschport> <zieladresse> <zielport>

WOZU. Der echte JARVIS-Server laeuft auf dem WIRT (127.0.0.1), der Draht
zu Osum endet aber in einem NETZRAUM (`ip netns`) -- und ein Netzraum
sieht das Loopback des Wirtes nicht. Dieses Programm laeuft IM Netzraum,
nimmt dort die Verbindung von Osum an und reicht sie an den Server
weiter.

Es fasst die Oktette NICHT an: TLS bleibt Ende zu Ende zwischen Osum und
dem Server, und dieser Weiterleiter kann darin nichts lesen und nichts
aendern. Er ist ein Kabel, kein Zwischenstueck -- sonst waere die
Messung wertlos.
"""
import socket
import sys
import threading


def rohr(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d:
                break
            b.sendall(d)
    except Exception:
        pass
    finally:
        for s in (a, b):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass


def bedienen(k, ziel):
    try:
        z = socket.create_connection(ziel, timeout=20)
    except Exception as e:
        sys.stderr.write("weiter: %s\n" % e)
        try:
            k.close()
        except Exception:
            pass
        return
    threading.Thread(target=rohr, args=(k, z), daemon=True).start()
    threading.Thread(target=rohr, args=(z, k), daemon=True).start()


def main():
    lh, lp, zh, zp = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((lh, lp))
    s.listen(8)
    sys.stderr.write("weiter: %s:%d -> %s:%d\n" % (lh, lp, zh, zp))
    sys.stderr.flush()
    while True:
        k, _ = s.accept()
        bedienen(k, (zh, zp))


if __name__ == "__main__":
    main()
