#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

from PIL import Image

ACCENT = (37, 99, 235)
ACCENT_TOLERANCE = 40
ACCENT_MIN_PIXELS = 600
CHANGE_MIN_PIXELS = 300
REGION_TOP = 400
REGION_BOTTOM = 1000
OPEN_ROW_MIN = 5


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def find(serial, pattern):
    return re.search(pattern, serial)


def accent_pixels(img):
    px = img.load()
    count = 0
    for y in range(REGION_TOP, min(REGION_BOTTOM, img.height)):
        for x in range(0, img.width):
            r, g, b = px[x, y][:3]
            if (abs(r - ACCENT[0]) <= ACCENT_TOLERANCE and abs(g - ACCENT[1]) <= ACCENT_TOLERANCE
                    and abs(b - ACCENT[2]) <= ACCENT_TOLERANCE):
                count += 1
    return count


def changed_pixels(a, b):
    pa, pb = a.load(), b.load()
    count = 0
    for y in range(REGION_TOP, min(REGION_BOTTOM, a.height)):
        for x in range(0, a.width):
            if pa[x, y] != pb[x, y]:
                count += 1
    return count


def load(out, name):
    try:
        return Image.open("%s/%s.ppm" % (out, name)).convert("RGB")
    except OSError:
        return None


def check_serial(serial, scale):
    verdict("caps_dialog_bits", bool(find(serial, r"dialogdemo: caps=127(?![0-9])")))
    verdict("message_ok", bool(find(serial, r"dialogdemo: msg status=ok ans=1")))
    verdict("confirm_enter_yes", bool(find(serial, r"dialogdemo: confirm-yes status=ok ans=1")))
    verdict("confirm_esc_no", bool(find(serial, r"dialogdemo: confirm-no status=ok ans=0")))
    listed = find(serial, r"dialogd: list n=([0-9]+) dir=/data")
    verdict("picker_lists_data", bool(listed) and int(listed.group(1)) >= OPEN_ROW_MIN)
    verdict("picker_geometry", bool(find(serial, r"dialogd: geom w=560 h=360 s=%d" % scale)))
    verdict("save_geometry", bool(find(serial, r"dialogd: geom w=560 h=410 s=%d" % scale)))
    verdict("open_ok", bool(find(serial, r"dialogdemo: open status=ok")))
    verdict("open_plain_name_and_content", bool(find(
        serial, r"dialogdemo: rec op=\d+ status=ok name=zznote\.txt len=13 val=note-body-123")))
    verdict("open_cancel", bool(find(serial, r"(?s)dialogdemo: open-cancel status=ok.{0,400}?dialogdemo: rec op=\d+ status=canceled")))
    verdict("save_ok", bool(find(serial, r"dialogdemo: save status=ok")))
    verdict("save_name_reported", bool(find(serial, r"dialogdemo: rec op=\d+ status=ok name=ddout\.txt")))
    verdict("save_file_content", bool(find(serial, r"dialogdemo: file len=16 val=saved-payload-77")))
    verdict("save_cancel", bool(find(serial, r"(?s)dialogdemo: save-cancel status=ok.{0,400}?dialogdemo: rec op=\d+ status=canceled")))
    verdict("save_cancel_writes_nothing", bool(find(serial, r"dialogdemo: file len=0(?![0-9])")))
    verdict("demo_done", bool(find(serial, r"dialogdemo: done")))


def check_photos(out, scale):
    minimum = ACCENT_MIN_PIXELS * scale * scale
    shots = {}
    for name in ("msg", "confirm", "open-start", "open-sel", "save-start"):
        shots[name] = load(out, name)
        img = shots[name]
        if name != "open-sel" and (scale == 1 or name in ("msg", "confirm")):
            verdict("accent_button_" + name.replace("-", "_"), img is not None and accent_pixels(img) >= minimum)
    if shots["open-start"] is not None and shots["open-sel"] is not None:
        verdict("end_key_moves_selection", changed_pixels(shots["open-start"], shots["open-sel"]) >= CHANGE_MIN_PIXELS)
    else:
        verdict("end_key_moves_selection", False, "missing photo")
    if shots["open-start"] is not None and shots["save-start"] is not None:
        verdict("save_differs_from_open", changed_pixels(shots["open-start"], shots["save-start"]) >= CHANGE_MIN_PIXELS)
    else:
        verdict("save_differs_from_open", False, "missing photo")


def main():
    out, serial_path = sys.argv[1], sys.argv[2]
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    serial = open(serial_path, "rb").read().decode("latin-1")
    check_serial(serial, scale)
    check_photos(out, scale)


main()
