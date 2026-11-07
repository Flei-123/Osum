#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys
import wave
import numpy as np

SECONDS = 6


def main():
    path, rate, channels, kind = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    rng = np.random.default_rng(7)
    t = np.arange(rate * SECONDS) / rate
    cols = []
    for c in range(channels):
        if kind == "tone":
            sig = 0.5 * np.sin(2 * np.pi * (440 + 220 * c) * t)
        else:
            sig = 0.3 * np.sin(2 * np.pi * (440 + 220 * c) * t) + 0.2 * np.sin(2 * np.pi * 3000 * t)
            sig += 0.12 * rng.standard_normal(len(t))
            clicks = (np.mod(t, 0.37 + 0.16 * c) < 0.004) * 0.6 * rng.standard_normal(len(t))
            sig += clicks
        cols.append(sig)
    data = np.clip(np.stack(cols, axis=1), -1, 1)
    pcm = (data * 30000).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


main()
