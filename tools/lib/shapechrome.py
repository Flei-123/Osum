#!/usr/bin/env python3
import os
import re

DEFAULT_BAR = 19
DEFAULT_FRAME = 2
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def shape_name(out_dir):
    try:
        lines = open(os.path.join(out_dir, "theme.conf"), "rb").read().decode("latin1").splitlines()
    except OSError:
        return "osum"
    for line in lines:
        if line.startswith("shape="):
            return line[6:].strip()
    return "osum"


def shape_metrics(shape):
    bar, frame = DEFAULT_BAR, DEFAULT_FRAME
    path = os.path.join(REPO_ROOT, "assets", "shapes", shape + ".shape")
    try:
        lines = open(path, "rb").read().decode("latin1").splitlines()
    except OSError:
        return bar, frame
    for line in lines:
        m = re.match(r"\s*(title_bar|frame)\s*=\s*(\d+)", line)
        if not m:
            continue
        if m.group(1) == "title_bar":
            bar = int(m.group(2))
        else:
            frame = int(m.group(2))
    return bar, frame


def client_inset(out_dir):
    bar, frame = shape_metrics(shape_name(out_dir))
    return frame, frame + bar + 1
