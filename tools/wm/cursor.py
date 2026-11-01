#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

W, H = 12, 18

SILHOUETTE = [
    (0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (0, 6), (0, 7),
    (0, 8), (0, 9), (0, 9), (0, 7), (1, 7), (2, 7), (3, 7), (3, 7),
    (3, 7), (3, 7),
]


def empty():
    return [[0] * W for _ in range(H)]


def silhouette():
    s = empty()
    for y, (a, b) in enumerate(SILHOUETTE):
        for x in range(a, b + 1):
            s[y][x] = 1
    return s


def erodiert(sil):
    b = empty()
    for y in range(H):
        for x in range(W):
            if not sil[y][x]:
                continue
            gut = True
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= W or ny >= H or not sil[ny][nx]:
                    gut = False
            b[y][x] = 1 if gut else 0
    return b


def masken(sil, body):
    um, inn = [], []
    for y in range(H):
        u = f = 0
        for x in range(W):
            bit = 1 << (11 - x)
            if body[y][x]:
                f |= bit
            elif sil[y][x]:
                u |= bit
        um.append(u)
        inn.append(f)
    return um, inn


def firn(values):
    aus = ""
    for v in values:
        aus += "\\x%02x\\x%02x" % ((v >> 8) & 0xFF, v & 0xFF)
    return aus + "\\x00"


def read_2(path_2):
    q = open(path_2, encoding="utf-8", errors="replace").read()
    raus = {}
    for name in ("umriss", "innen"):
        m = re.search(r'var %s: \[u8; \d+\] = b"((?:\\x[0-9a-fA-F]{2})+)"'
                      % name, q)
        if not m:
            print("  CASE  %s is not in %s" % (name, path_2))
            return None
        okt = [int(t, 16) for t in re.findall(r'\\x([0-9a-fA-F]{2})',
                                              m.group(1))]
        if len(okt) < H * 2:
            print("  CASE  %s has only %d octets, %d needed"
                  % (name, len(okt), H * 2))
            return None
        raus[name] = [(okt[i * 2] << 8) | okt[i * 2 + 1] for i in range(H)]
    return raus


def gitter(um, inn):
    sil, body = empty(), empty()
    for y in range(H):
        for x in range(W):
            bit = 1 << (11 - x)
            if inn[y] & bit:
                body[y][x] = 1
                sil[y][x] = 1
            elif um[y] & bit:
                sil[y][x] = 1
    return sil, body


def image(sil, body):
    lines = []
    for y in range(H):
        r = ""
        for x in range(W):
            r += "#" if body[y][x] else ("." if sil[y][x] else " ")
        lines.append("  %2d |%s|" % (y, r))
    return lines


def bloecke(reihe):
    n, in_ = 0, False
    for v in reihe:
        if v and not in_:
            n += 1
        in_ = bool(v)
    return n


def check(sil, body):
    error = []
    for y in range(H):
        for x in range(W):
            if body[y][x] and not sil[y][x]:
                error.append("(e) Fuellpunkt %d,%d liegt nicht in der Silhouette" % (x, y))
    start = None
    n = 0
    for y in range(H):
        for x in range(W):
            if body[y][x]:
                n += 1
                if start is None:
                    start = (x, y)
    if n == 0:
        error.append("(a) die Fuellung ist leer")
    else:
        seen = {start}
        stack = [start]
        while stack:
            x, y = stack.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and body[ny][nx] \
                        and (nx, ny) not in seen:
                    seen.add((nx, ny))
                    stack.append((nx, ny))
        if len(seen) != n:
            error.append("(a) die Fuellung zerfaellt: %d von %d Punkten "
                          "haengen zusammen" % (len(seen), n))
    for y in range(H):
        for x in range(W):
            if not body[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= W or ny >= H:
                    error.append("(b) Fuellpunkt %d,%d liegt am Bildrand"
                                  % (x, y))
                elif not sil[ny][nx]:
                    error.append("(b) Fuellpunkt %d,%d hat bei %d,%d den "
                                  "Hintergrund" % (x, y, nx, ny))
    for y in range(H):
        for was, g in (("Fuellung", body), ("Silhouette", sil)):
            b = bloecke(g[y])
            if b > 1:
                error.append("(c) Zeile %d: die %s hat %d getrennte Bloecke"
                              % (y, was, b))
    for y in range(H):
        for x in range(W):
            if not sil[y][x]:
                continue
            nachbarn = 0
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and sil[ny][nx]:
                    nachbarn += 1
            if nachbarn == 0:
                error.append("(d) %d,%d steht allein" % (x, y))
    if not sil[0][0]:
        error.append("(f) auf 0,0 -- dem Griffpunkt -- ist nichts")
    return error


def main():
    if "--bauen" in sys.argv:
        sil = silhouette()
        body = erodiert(sil)
        um, inn = masken(sil, body)
        for z in image(sil, body):
            print(z)
        print('umriss = b"%s"' % firn(um))
        print('innen  = b"%s"' % firn(inn))
        return 0
    path_2 = sys.argv[1] if len(sys.argv) > 1 else "kernel/ui/wm/wmcursor.fi"
    m = read_2(path_2)
    if m is None:
        return 1
    sil, body = gitter(m["umriss"], m["innen"])
    print("  THE POINTER AS IT IS PAINTED (# fill, . edge):")
    for z in image(sil, body):
        print(z)
    error = check(sil, body)
    for f in error:
        print("  FALL  " + f)
    if error:
        print("  ZEIGER: %d Beanstandungen" % len(error))
        return 1
    print("  ZEIGER: 6 Pruefungen, 0 Beanstandungen")
    return 0


sys.exit(main())
