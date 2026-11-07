#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

out = sys.argv[1]
counter = len(sys.argv) > 2 and sys.argv[2] == "mute"
RATE = 44100
TONE_HZ = 440
TONE_TOLERANCE_HZ = 9
PEAK_MIN, PEAK_MAX = 3600, 4700
MAX_BAD_FRAMES = 2
ok = fail = 0


def say(good, msg):
    global ok, fail
    if good:
        ok += 1
    else:
        fail += 1
    print(("  OK    " if good else "  FAIL  ") + msg)


raw = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1")
lines = [l.replace("\r", "").replace("\0", "") for l in raw.split("\n")]
lines = [l[l.index("vplay:"):] for l in lines if "vplay:" in l]
stat = next((re.match(r"vplay: audiostat n=(\d+) cross=(\d+) peak=(\d+) bad=(\d+)", l) for l in lines if l.startswith("vplay: audiostat")), None)
sources = re.findall(r"vplay: show .* src=(\w+)", "\n".join(lines))
if counter:
    say(stat is None, "COUNTER-PROOF: with -q no MP3 frame is decoded")
    say(sources and all(s == "wall" for s in sources), "COUNTER-PROOF: with -q the wall clock drives playback (%d shown, src=wall)" % len(sources))
else:
    say(stat is not None, "the player decoded the MP3 track")
    if stat:
        n, cross, peak, bad = (int(x) for x in stat.groups())
        hz = cross * RATE / 2 / n if n else 0
        say(n >= 15 * RATE, "decoded %d sample frames (at least 15 s)" % n)
        say(abs(hz - TONE_HZ) <= TONE_TOLERANCE_HZ, "decoded tone is %.1f Hz (expected %d +- %d)" % (hz, TONE_HZ, TONE_TOLERANCE_HZ))
        say(PEAK_MIN <= peak <= PEAK_MAX, "peak amplitude %d (expected %d..%d)" % (peak, PEAK_MIN, PEAK_MAX))
        say(bad <= MAX_BAD_FRAMES, "undecodable frames: %d (limit %d)" % (bad, MAX_BAD_FRAMES))
    say("audio" in sources, "the MP3 track is the clock (src=audio)")
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
