import json
import os
import subprocess

PROJECT = "OrientOS"
KEY_PREFIX = "speed "
UNIT = "x Linux"


def push(rows):
    cmd = os.environ.get("SPEED_METRIC_CMD", "")
    lines = []
    for test, _, _, ratio, budget, status in rows:
        if ratio == "":
            continue
        entry = {"project": PROJECT, "key": KEY_PREFIX + test, "value": float(ratio), "unit": UNIT, "target": "<= 1.0", "note": "budget %s status %s" % (budget, status)}
        lines.append(json.dumps(entry))
        if cmd:
            subprocess.run([cmd, entry["key"], str(entry["value"]), entry["unit"], entry["target"], entry["note"]], check=False)
    return lines
