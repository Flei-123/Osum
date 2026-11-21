#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys

import numpy as np

EDGE_RANGE = 30.0
MID_LOW = 0.15
MID_HIGH = 0.85
TILE = 32
TILE_MIN_EDGE = 24
TILE_ALIASED_SHARE = 0.12
DENSE_EDGE = 150


def read_ppm(path):
    data = open(path, "rb").read()
    pos = 0
    tokens = []
    while len(tokens) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        tokens.append(data[start:pos])
    pos += 1
    w, h = int(tokens[1]), int(tokens[2])
    return np.frombuffer(data[pos:pos + w * h * 3], dtype=np.uint8).reshape(h, w, 3)


def luminance(img):
    f = img.astype(np.float32)
    return 0.299 * f[..., 0] + 0.587 * f[..., 1] + 0.114 * f[..., 2]


def neighbourhood(lum):
    padded = np.pad(lum, 1, mode="edge")
    stack = [padded[dy:dy + lum.shape[0], dx:dx + lum.shape[1]] for dy in range(3) for dx in range(3)]
    stack = np.stack(stack)
    return stack.min(axis=0), stack.max(axis=0)


def edge_masks(lum):
    lo, hi = neighbourhood(lum)
    span = hi - lo
    edge = span >= EDGE_RANGE
    rel = np.where(span > 0, (lum - lo) / np.maximum(span, 1e-6), 0.0)
    mid = edge & (rel > MID_LOW) & (rel < MID_HIGH)
    return edge, mid


def summarize(edge, mid):
    n = int(edge.sum())
    m = int(mid.sum())
    return n, m, (m / n if n else 0.0)


def aliased_tiles(edge, mid):
    h, w = edge.shape
    out = []
    for ty in range(0, h - TILE + 1, TILE):
        for tx in range(0, w - TILE + 1, TILE):
            n = int(edge[ty:ty + TILE, tx:tx + TILE].sum())
            if n < TILE_MIN_EDGE:
                continue
            share = int(mid[ty:ty + TILE, tx:tx + TILE].sum()) / n
            if share < TILE_ALIASED_SHARE:
                out.append((tx, ty, n, share))
    return out


def tiles_total(edge):
    h, w = edge.shape
    total = 0
    for ty in range(0, h - TILE + 1, TILE):
        for tx in range(0, w - TILE + 1, TILE):
            if int(edge[ty:ty + TILE, tx:tx + TILE].sum()) >= TILE_MIN_EDGE:
                total += 1
    return total


def dense_share(edge, mid):
    h, w = edge.shape
    n = m = tiles = 0
    for ty in range(0, h - TILE + 1, TILE):
        for tx in range(0, w - TILE + 1, TILE):
            e = int(edge[ty:ty + TILE, tx:tx + TILE].sum())
            if e < DENSE_EDGE:
                continue
            tiles += 1
            n += e
            m += int(mid[ty:ty + TILE, tx:tx + TILE].sum())
    return tiles, n, (m / n if n else 0.0)


def binarize(img):
    lum = luminance(img)
    out = img.copy()
    lo, hi = neighbourhood(lum)
    thr = (lo + hi) / 2.0
    pick_hi = lum >= thr
    for c in range(3):
        ch = img[..., c].astype(np.float32)
        chlo = np.pad(ch, 1, mode="edge")
        stack = np.stack([chlo[dy:dy + ch.shape[0], dx:dx + ch.shape[1]] for dy in range(3) for dx in range(3)])
        out[..., c] = np.where(pick_hi, stack.max(axis=0), stack.min(axis=0)).astype(np.uint8)
    return out


def main():
    paths = [a for a in sys.argv[1:] if not a.startswith("--")]
    flag_binarize = "--binarize" in sys.argv
    flag_tiles = "--tiles" in sys.argv
    for path in paths:
        img = read_ppm(path)
        if flag_binarize:
            img = binarize(img)
        edge, mid = edge_masks(luminance(img))
        n, m, share = summarize(edge, mid)
        al = aliased_tiles(edge, mid)
        dt, dn, ds = dense_share(edge, mid)
        print("%s edge=%d aa_share=%.3f dense_tiles=%d dense_edge=%d dense_share=%.3f aliased_tiles=%d/%d" % (path, n, share, dt, dn, ds, len(al), tiles_total(edge)))
        if flag_tiles:
            for tx, ty, cnt, sh in al:
                print("  tile x=%d y=%d edge=%d share=%.3f" % (tx, ty, cnt, sh))


if __name__ == "__main__":
    main()
