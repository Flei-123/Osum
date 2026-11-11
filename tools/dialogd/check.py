#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import subprocess
import sys
import tempfile

from PIL import Image, ImageOps

ACCENT = (37, 99, 235)
ACCENT_TOLERANCE = 40
ACCENT_MIN_PIXELS = 600
CHANGE_MIN_PIXELS = 300
REGION_TOP = 400
REGION_BOTTOM = 1000
OPEN_ROW_MIN = 5
TASKBAR_LOGICAL_H = 40
BUTTON_MIN_LOGICAL_H = 30
BUTTON_ROW_MIN_PIXELS = 40
BUTTON_GAP_LOGICAL = 11
LABEL_PAD_LOGICAL = 15
OCR_ZOOM = 2


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


def is_accent(pixel):
    return all(abs(pixel[i] - ACCENT[i]) <= ACCENT_TOLERANCE for i in range(3))


def primary_button(img, scale):
    px = img.load()
    limit = img.height - TASKBAR_LOGICAL_H * scale
    rows = []
    for y in range(REGION_TOP, limit):
        if sum(1 for x in range(img.width) if is_accent(px[x, y])) >= BUTTON_ROW_MIN_PIXELS * scale:
            rows.append(y)
    if not rows:
        return None
    run = [rows[-1]]
    for y in reversed(rows[:-1]):
        if y != run[-1] - 1:
            break
        run.append(y)
    top, bottom = run[-1], run[0]
    middle = (top + bottom) // 2
    xs = [x for x in range(img.width) if is_accent(px[x, middle])]
    return {"left": min(xs), "right": max(xs), "top": top, "bottom": bottom, "limit": limit}


def button_complete(button, scale):
    if button is None:
        return False
    tall_enough = button["bottom"] - button["top"] + 1 >= BUTTON_MIN_LOGICAL_H * scale
    return tall_enough and button["bottom"] < button["limit"] - 1


def ocr_label(img, box, invert):
    pad = LABEL_PAD_LOGICAL * (box[3] - box[1]) // BUTTON_MIN_LOGICAL_H // 2
    crop = img.crop((box[0] + pad * 2, box[1] + pad, box[2] - pad * 2, box[3] - pad))
    crop = crop.resize((crop.width * OCR_ZOOM, crop.height * OCR_ZOOM))
    gray = ImageOps.autocontrast(crop.convert("L"))
    if invert:
        gray = ImageOps.invert(gray)
    handle, path = tempfile.mkstemp(suffix=".png")
    os.close(handle)
    try:
        gray.save(path)
        done = subprocess.run(["tesseract", path, "-", "--psm", "7"], capture_output=True, text=True)
        return done.stdout.strip()
    except OSError:
        return ""
    finally:
        os.unlink(path)


def button_labels(img, button, scale, primary_text):
    width = button["right"] - button["left"] + 1
    gap = BUTTON_GAP_LOGICAL * scale
    primary = (button["left"], button["top"], button["right"] + 1, button["bottom"] + 1)
    secondary = (button["right"] + 1 + gap, button["top"], button["right"] + 1 + gap + width, button["bottom"] + 1)
    return ocr_label(img, primary, True) == primary_text and ocr_label(img, secondary, False) == "Cancel"


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
        if name != "open-sel":
            verdict("accent_button_" + name.replace("-", "_"), img is not None and accent_pixels(img) >= minimum)
    for name, text in (("open-start", "Open"), ("save-start", "Save")):
        button = primary_button(shots[name], scale) if shots[name] is not None else None
        label = name.replace("-", "_")
        verdict("button_fully_visible_" + label, button_complete(button, scale), "" if button is None else "bottom=%d limit=%d" % (button["bottom"], button["limit"]))
        verdict("button_labels_" + label, button is not None and button_labels(shots[name], button, scale, text))
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
