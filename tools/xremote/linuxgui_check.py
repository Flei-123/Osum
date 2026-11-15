import re
import subprocess
import sys
import tempfile

from PIL import Image

serial_path, shot_path = sys.argv[1], sys.argv[2]
PANEL = (19, 21, 27)
ACCENT_MIN_BLUE = 200
ACCENT_MAX_RED = 90
GUI_MARKER = "FVGUI start"
MIN_PANEL_SHARE = 0.5
MIN_ACCENT_PIXELS = 2000
TOLERANCE = 6
OCR_SCALE = 2

serial = open(serial_path, errors="replace").read()
checks = []


def check(name, ok, detail=""):
    checks.append(ok)
    print(("OK    " if ok else "FAIL  ") + name + (" (" + detail + ")" if detail else ""))


def near(pixel, color):
    return all(abs(a - b) <= TOLERANCE for a, b in zip(pixel, color))


match = re.search(r"wayd: window c=\d+ x=(\d+) y=(\d+) inx=\d+ iny=\d+ w=(\d+) h=(\d+)", serial)
check("window created", match is not None)
check("no process killed by a signal", "signal: pid=" not in serial.split(GUI_MARKER, 1)[-1])
gui_log = serial.split(GUI_MARKER, 1)[-1]
check("no user fault after the GUI start", "user fault:" not in gui_log)
if match:
    x, y, w, h = (int(v) for v in match.groups())
    image = Image.open(shot_path).convert("RGB")
    pixels = image.load()
    step = 4
    total = panel = accent = 0
    for py in range(y, min(y + h, image.height), step):
        for px in range(x, min(x + w, image.width), step):
            total += 1
            pixel = pixels[px, py]
            panel += near(pixel, PANEL)
            accent += pixel[2] >= ACCENT_MIN_BLUE and pixel[0] <= ACCENT_MAX_RED
    share = panel / max(total, 1)
    check("window shows the dark FreeViewer panel", share >= MIN_PANEL_SHARE, "share %.2f" % share)
    check("window shows the blue accent button", accent * step * step >= MIN_ACCENT_PIXELS, "pixels %d" % (accent * step * step))
if match and len(sys.argv) > 3:
    expected_id = sys.argv[3]
    with tempfile.TemporaryDirectory() as tmp:
        crop = image.crop((x, y, x + w, y + h)).resize((w * OCR_SCALE, h * OCR_SCALE))
        crop_path = tmp + "/crop.png"
        crop.save(crop_path)
        text = subprocess.run(["tesseract", crop_path, "-", "--psm", "6"], capture_output=True, text=True).stdout
    digits = re.sub(r"[^0-9]", "", text)
    check("GUI shows the ID of the running service", expected_id in digits, "ocr digits %s" % digits[:40])
    check("GUI did not start its own host", "host: relay session failed" not in gui_log)
print("XRGUI %d/%d" % (sum(checks), len(checks)))
sys.exit(0 if all(checks) else 1)
