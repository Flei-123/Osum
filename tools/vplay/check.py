#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib
import os
import re
import sys

import numpy as np

out, yuv_path = sys.argv[1], sys.argv[2]
counter = len(sys.argv) > 3 and sys.argv[3] == "nosync"
WIDTH, HEIGHT, FRAMES, FRAME_MS = 176, 144, 200, 100
MAX_DRIFT_MS = 200
MIN_SHOWN = 190
ok = fail = 0


def say(good, msg):
    global ok, fail
    if good:
        ok += 1
    else:
        fail += 1
    print(("  OK    " if good else "  FAIL  ") + msg)


def trunc_div(a, b):
    return np.where(a >= 0, a // b, -((-a) // b))


def reference_hashes():
    raw = np.fromfile(yuv_path, dtype=np.uint8)
    frame_size = WIDTH * HEIGHT * 3 // 2
    hashes = []
    for i in range(len(raw) // frame_size):
        f = raw[i * frame_size:(i + 1) * frame_size]
        y = f[:WIDTH * HEIGHT].reshape(HEIGHT, WIDTH).astype(np.int64)
        cw, ch = WIDTH // 2, HEIGHT // 2
        u = f[WIDTH * HEIGHT:WIDTH * HEIGHT + cw * ch].reshape(ch, cw).astype(np.int64)
        v = f[WIDTH * HEIGHT + cw * ch:].reshape(ch, cw).astype(np.int64)
        cb = np.repeat(np.repeat(u, 2, 0), 2, 1) - 128
        cr = np.repeat(np.repeat(v, 2, 0), 2, 1) - 128
        r = np.clip(y + trunc_div(91881 * cr, 65536), 0, 255)
        g = np.clip(y - trunc_div(22554 * cb + 46802 * cr, 65536), 0, 255)
        b = np.clip(y + trunc_div(116130 * cb, 65536), 0, 255)
        bgra = np.stack([b, g, r, np.full_like(b, 255)], axis=2).astype(np.uint8)
        hashes.append(hashlib.sha256(bgra.tobytes()).hexdigest())
    return hashes


def load_ppm(path):
    d = open(path, "rb").read()
    fields, at = [], 2
    while len(fields) < 3:
        while d[at:at + 1].isspace():
            at += 1
        start = at
        while not d[at:at + 1].isspace():
            at += 1
        fields.append(int(d[start:at]))
    return fields[0], fields[1], np.frombuffer(d[at + 1:], dtype=np.uint8).reshape(fields[1], fields[0], 3)


raw_serial = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1")
lines = [l.replace("\r", "").replace("\0", "") for l in raw_serial.split("\n")]
lines = [l[l.index("vplay:"):] for l in lines if "vplay:" in l]
ref = reference_hashes()
say(len(ref) == FRAMES, "reference: ffmpeg decoded %d frames" % len(ref))
say(any(re.match(r"vplay: open w=%d h=%d frames=%d " % (WIDTH, HEIGHT, FRAMES), l) for l in lines),
    "the program opened the clip (w=%d h=%d frames=%d)" % (WIDTH, HEIGHT, FRAMES))
say(any(l == "vplay: ready" for l in lines), "the window came up (vplay: ready)")

shows, drifts, paused_leaks, state = [], [], 0, "paused"
for l in lines:
    m = re.match(r"vplay: state (\w+)", l)
    if m:
        state = m.group(1)
    m = re.match(r"vplay: (show|drop) i=(\d+) pts=(\d+) clock=(\d+) drift=(-?\d+) src=(\w+)(?: sha=([0-9a-f]+))?", l)
    if not m:
        continue
    if state == "paused":
        paused_leaks += 1
    drifts.append(int(m.group(5)))
    if m.group(1) == "show":
        shows.append((int(m.group(2)), int(m.group(3)), m.group(7)))

worst = max((abs(d) for d in drifts), default=-1)
if counter:
    say(worst > MAX_DRIFT_MS, "COUNTER-PROOF: without sync (-n) the drift leaves the %d ms bound (worst %d ms)" % (MAX_DRIFT_MS, worst))
    print("RESULT ok=%d fail=%d" % (ok, fail))
    sys.exit(1 if fail else 0)

first_pass = []
seen = set()
for i, pts, sha in shows:
    if i in seen:
        break
    seen.add(i)
    first_pass.append((i, pts, sha))
say(len(first_pass) >= MIN_SHOWN, "first pass showed %d of %d frames (at least %d)" % (len(first_pass), FRAMES, MIN_SHOWN))
bad = [(i, sha) for i, pts, sha in shows if sha != ref[i]]
say(shows and not bad, "all %d shown frames equal the ffmpeg reference by SHA-256%s" % (len(shows), "" if not bad else " (first wrong: i=%d)" % bad[0][0]))
say(all(pts == i * FRAME_MS for i, pts, sha in shows), "frame times are i * %d ms" % FRAME_MS)
say(drifts and worst <= MAX_DRIFT_MS, "audio clock vs frame time: worst drift %d ms (limit %d)" % (worst, MAX_DRIFT_MS))
say(any(s == "audio" for s in re.findall(r"vplay: show .* src=(\w+)", "\n".join(lines))),
    "the audio device is the clock (src=audio)")

walls = [(int(a), int(b)) for a, b in (re.match(r"vplay: wallcheck wall=(\d+) aclock=(\d+)", l).groups() for l in lines if l.startswith("vplay: wallcheck"))]
wdiff = max((abs(a - b) for a, b in walls), default=-1)
say(len(walls) >= 3 and wdiff <= MAX_DRIFT_MS, "audio position follows the wall clock: %d samples, worst %d ms (limit %d)" % (len(walls), wdiff, MAX_DRIFT_MS))

seeks = [re.match(r"vplay: seek ms=(\d+) idx=(\d+)(?: sha=([0-9a-f]+))?", l) for l in lines if l.startswith("vplay: seek")]
seeks = [m for m in seeks if m]
say(len(seeks) >= 5, "seek lines: %d (initial, restart, slider, -1 s, +1 s)" % len(seeks))
bad_idx = [m.group(0) for m in seeks if int(m.group(2)) != min(int(m.group(1)), FRAMES * FRAME_MS - 1) // FRAME_MS]
say(seeks and not bad_idx, "every seek lands on the frame at that time%s" % ("" if not bad_idx else ": " + bad_idx[0]))
bad_sha = [m.group(0) for m in seeks if m.group(3) != ref[int(m.group(2))]]
say(seeks and not bad_sha, "every seek frame (decoded from the keyframe before it) equals the reference%s" % ("" if not bad_sha else ": " + bad_sha[0]))
say(paused_leaks == 0, "pause: no frame shown or dropped while paused (%d)" % paused_leaks)
say(any(l == "vplay: state ended" for l in lines), "playback reached the end")

try:
    photos = {n: load_ppm(os.path.join(out, n + ".ppm")) for n in ("00-open", "01-playing", "02-ended", "03-paused", "04-seek")}
    base = photos["00-open"][2]
    changed = {n: int((p[2] != base).any(axis=2).sum()) for n, p in photos.items()}
    say(changed["01-playing"] > 2000, "01-playing differs from the open window (%d px)" % changed["01-playing"])
    say(int((photos["02-ended"][2] != photos["01-playing"][2]).any(axis=2).sum()) > 2000, "02-ended shows another picture than 01-playing")
    say(int((photos["04-seek"][2] != photos["03-paused"][2]).any(axis=2).sum()) > 2000, "04-seek shows another picture than 03-paused")
    diff = (photos["01-playing"][2] != base).any(axis=2)
    cols = np.where(diff.any(axis=0))[0]
    rows = np.where(diff.any(axis=1))[0]
    pic_w = int(cols.max() - cols.min() + 1) if len(cols) else 0
    pic_h = int(rows.max() - rows.min() + 1) if len(rows) else 0
    say(pic_w >= 2 * WIDTH * photos["01-playing"][0] // 1280 and pic_h >= 2 * HEIGHT * photos["01-playing"][0] // 1280,
        "the picture is upscaled in the window (%dx%d px changed, source %dx%d)" % (pic_w, pic_h, WIDTH, HEIGHT))
    colours = len(set(map(bytes, photos["01-playing"][2].reshape(-1, 3)[::37])))
    say(colours >= 40, "01-playing is a real picture (%d colours sampled)" % colours)
except (OSError, KeyError, ValueError) as e:
    say(False, "pictures missing: %s" % e)
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
