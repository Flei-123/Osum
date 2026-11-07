#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys
import numpy as np

out, ref_path = sys.argv[1], sys.argv[2]
counter = len(sys.argv) > 3 and sys.argv[3] == "mute"
RATE = 44100
TONE_HZ = 440
TONE_TOLERANCE_HZ = 9
PEAK_TOLERANCE = 2
SUM_TOLERANCE = 0.002
ok = fail = 0


def say(good, msg):
    global ok, fail
    ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(("  OK    " if good else "  FAIL  ") + msg)


ref = np.fromfile(ref_path, dtype="<i2").reshape(-1, 2)[:, 0].astype(np.int64)
raw = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1").replace("\r", "").replace("\0", "")
stat = re.search(r"vplay: audiostat n=(\d+) cross=(\d+) peak=(\d+) bad=(\d+) sum=(\d+)", raw)
sources = re.findall(r"vplay: show .* src=(\w+)", raw)
if counter:
    say(stat is None, "COUNTER-PROOF: with -q no AAC frame is decoded")
    say(bool(sources) and all(s == "wall" for s in sources), "COUNTER-PROOF: with -q the wall clock drives playback (%d shown, src=wall)" % len(sources))
else:
    say(stat is not None, "the player decoded the AAC track")
    if stat:
        n, cross, peak, bad, total = (int(x) for x in stat.groups())
        say(abs(n - len(ref)) <= 1024, "decoded %d sample frames (ffmpeg %d)" % (n, len(ref)))
        hz = cross * RATE / 2 / n
        say(abs(hz - TONE_HZ) <= TONE_TOLERANCE_HZ, "decoded tone is %.1f Hz (expected %d +- %d)" % (hz, TONE_HZ, TONE_TOLERANCE_HZ))
        say(abs(peak - int(np.abs(ref).max())) <= PEAK_TOLERANCE, "peak %d (ffmpeg %d)" % (peak, int(np.abs(ref).max())))
        ref_sum = int(np.abs(ref).sum())
        say(abs(total - ref_sum) <= ref_sum * SUM_TOLERANCE, "sum of |samples| %d (ffmpeg %d)" % (total, ref_sum))
        say(bad == 0, "undecodable frames: %d" % bad)
    say("audio" in sources, "the AAC track is the clock (src=audio)")
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
