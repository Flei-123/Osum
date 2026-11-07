#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys
import numpy as np

SNR_MIN_DB = 60.0
MAX_ABS_ERR = 4


def load(path, channels):
    raw = np.fromfile(path, dtype="<i2")
    return raw[: len(raw) // channels * channels].reshape(-1, channels).astype(np.int64)


def main():
    out_path, ref_path, channels, label = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    mode = sys.argv[5] if len(sys.argv) > 5 else ""
    out = load(out_path, channels)
    ref = load(ref_path, channels)
    n = min(len(out), len(ref))
    out, ref = out[:n], ref[:n]
    err = out - ref
    sig = float(np.sum(ref.astype(np.float64) ** 2))
    noise = float(np.sum(err.astype(np.float64) ** 2))
    snr = 200.0 if noise == 0 else 10.0 * np.log10(max(sig, 1.0) / noise)
    worst = int(np.max(np.abs(err))) if n else 0
    ok_len = abs(len(out) - len(ref)) <= 1024
    expect_fail = mode == "expect-fail"
    good = snr >= SNR_MIN_DB and worst <= MAX_ABS_ERR and ok_len
    if expect_fail:
        good = not good
    print("  %s    %s: snr %.1f dB, max abs err %d, frames %d/%d" % ("OK  " if good else "FAIL", label, snr, worst, len(out), len(ref)))
    return 0 if good else 1


sys.exit(main())
