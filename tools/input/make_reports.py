# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import reportfile
import reportoracle

CORPUS = os.path.join(HERE, "corpus", "holo-laptop-3")
TP = "touchpad-045e-09af"
TS = "touchscreen-045e-0c32"
PEN = "pen-045e-0c32"
MODE = "inputmode-045e-09af"
HEADER = [
    "# Example reports per device, raw bytes including the Report ID byte (hex, byte 0 = Report ID).",
    "# Format: <device> <name> <hex> | fields: <decoded values>. Names starting with feat- are Feature reports.",
    "# Values are computed from the bit layout in tools/input/reportoracle.py; fields not listed decode to 0.",
    "# Bit layout of the synthesized descriptors (SYNTHESIZED from HidP capabilities, see *.desc.meta).",
]


def contact(k, conf, tip, ident, x, y):
    p = "contact%d." % k
    return {p + "conf": conf, p + "tip": tip, p + "id": ident, p + "x": x, p + "y": y}


def touchpad(scan, count, btn, *contacts):
    out = {"scan": scan, "count": count, "btn": btn}
    for item in contacts:
        out.update(contact(*item))
    return out


def pen(**kw):
    base = {"barrel": 0, "invert": 0, "eraser": 0, "tip": 0, "inrange": 1, "x": 4800, "y": 3600,
            "pressure": 0, "xtilt": 9000, "ytilt": 9000, "scan": 5000, "vendor": 0}
    base.update(kw)
    return base


VECTORS = [
    (TP, "1finger-down", 4, touchpad(1234, 1, 0, (0, 1, 1, 2, 1000, 700))),
    (TP, "2finger-down", 4, touchpad(1250, 2, 0, (0, 1, 1, 2, 1000, 700), (1, 1, 1, 3, 1500, 900))),
    (TP, "2finger-moved", 4, touchpad(1266, 2, 0, (0, 1, 1, 2, 1100, 650), (1, 1, 1, 3, 1480, 940))),
    (TP, "1finger-up", 4, touchpad(1282, 1, 0, (0, 1, 0, 2, 1100, 650))),
    (TP, "palm-no-confidence", 4, touchpad(1300, 1, 0, (0, 0, 1, 4, 2200, 1400))),
    (TP, "click-edge-max", 4, touchpad(65535, 1, 1, (0, 1, 1, 5, 2227, 1459))),
    (TP, "5finger-down", 4, touchpad(2000, 5, 0, (0, 1, 1, 0, 100, 100), (1, 1, 1, 1, 600, 150),
                                      (2, 1, 1, 2, 1100, 200), (3, 1, 1, 3, 1600, 250), (4, 1, 1, 4, 2100, 300))),
    (TP, "feat-contact-max", 4, {"count_max": 5, "pad_type": 0}),
    (TP, "feat-latency", 6, {"latency": 1}),
    (TS, "tip-down-center", 64, {"tip": 1, "x": 16384, "y": 8192}),
    (TS, "tip-up-center", 64, {"tip": 0, "x": 16384, "y": 8192}),
    (TS, "tip-down-min", 64, {"tip": 1, "x": 0, "y": 0}),
    (TS, "tip-down-max", 64, {"tip": 1, "x": 32767, "y": 32767}),
    (PEN, "hover", 1, pen()),
    (PEN, "tip-pressure-2048", 1, pen(tip=1, pressure=2048, scan=5010)),
    (PEN, "barrel-hover", 1, pen(barrel=1, scan=5020)),
    (PEN, "eraser-contact", 1, pen(invert=1, eraser=1, tip=1, pressure=1024, vendor=7, scan=5030)),
    (PEN, "tilt-extremes", 1, pen(tip=1, pressure=4096, xtilt=0, ytilt=18000, x=9600, y=7200, scan=5040)),
    (MODE, "feat-mode-ptp", 7, {"mode": 3}),
    (MODE, "feat-switches-on", 8, {"surface": 1, "button": 1}),
]


def build_lines():
    lines = []
    for device, name, rid, values in VECTORS:
        report = reportoracle.lookup(device, name, rid)
        data = reportoracle.encode(report, rid, values)
        lines.append(reportfile.Line(device, name, data.hex(), values))
    return lines


def render():
    rows = []
    for (device, name, rid, _), line in zip(VECTORS, build_lines()):
        order = [f.name for f in reportoracle.lookup(device, name, rid).fields]
        rows.append(reportfile.format_line(line, order))
    return "\n".join(HEADER + rows) + "\n"


def main():
    with open(os.path.join(CORPUS, "reports.txt"), "w", encoding="utf-8") as handle:
        handle.write(render())
    print("reports.txt: %d lines" % len(VECTORS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
