#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/ui.sh <outdir> -- UI timing numbers of the shipping desktop on the audit machine (QEMU/KVM), as JSON for run.sh --ui.
#   ui.input_to_picture_ms   median input -> picture (tools/latency, kernel clocks, `wm: lat`)
#   ui.drag_frame_mean_ms / ui.drag_frame_max_ms / ui.drag_fps   window drag, phase 5 of tools/design/stationaer.sh (`wm: bild`)
#   ui.menu_frame_max_ms     start menu open/close, phase 4 (largest frame)
# Both runs build their own kernel (~5-10 min each); start through /root/jarvis/bin/heavy. Writes <outdir>/ui.json.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?outdir}; mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
bash tools/latency/run.sh "$OUT/lat" new > "$OUT/lat.txt" 2>&1
bash tools/design/stationaer.sh "$OUT/st" > "$OUT/st.txt" 2>&1
cat "$OUT/lat.txt" "$OUT/st.txt" | grep -aE "median input|phase" | head -20
python3 -I - "$OUT" <<'PY'
import json, re, sys
o = sys.argv[1]
r = {}
lat = open(o + "/lat.txt", errors="replace").read()
m = re.search(r"median input->picture=([\d.]+) ms", lat)
if m:
    r["ui.input_to_picture_ms"] = float(m.group(1))
st = open(o + "/st.txt", errors="replace").read().splitlines()
def phase(n):
    for ln in st:
        if re.match(r"\s+phase %d " % n, ln):
            mm = re.search(r"n=(\d+) mittel=(\d+) max=(\d+)", ln)
            if mm:
                return int(mm.group(1)), int(mm.group(2)), int(mm.group(3))
p5, p4 = phase(5), phase(4)
if p5:
    r["ui.drag_frame_mean_ms"] = round(p5[1] / 1000.0, 3)
    r["ui.drag_frame_max_ms"] = round(p5[2] / 1000.0, 3)
    r["ui.drag_fps"] = round(1e6 / max(p5[1], 1), 1)
if p4:
    r["ui.menu_frame_max_ms"] = round(p4[2] / 1000.0, 3)
json.dump(r, open(o + "/ui.json", "w"))
print(r)
PY
