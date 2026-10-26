import re
import subprocess
import sys

from PIL import Image

path, mode = sys.argv[1], sys.argv[2]
png = path.replace(".ppm", ".png")
img = Image.open(path).convert("L")
img = img.resize((img.width * 2, img.height * 2))
img.save(png)
text = subprocess.run(["tesseract", png, "stdout", "--psm", "6"],
                      capture_output=True, text=True).stdout
rows = [l for l in text.splitlines() if "ROW" in l]
merged = [l for l in rows if len(re.findall(r"ROW", l)) > 1]
tokens = set(re.findall(r"ROW(\d\d)", text))
tail = any(t in tokens for t in ("18", "19", "20", "21", "22", "23", "24"))
print("rows=%d merged=%d tail=%s" % (len(rows), len(merged), tail))
ok = len(rows) >= 8 and not merged and tail
if mode == "expect-fail":
    ok = not ok
print("OK" if ok else "FAIL")
sys.exit(0 if ok else 1)
