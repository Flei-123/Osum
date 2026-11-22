import re
import sys

TEXT_LINE = re.compile(
    r"wlib: text win=0 kind=(\d+) x=(\d+) base=(\d+) fg=\d+ bg=\d+ tw=(\d+) ax=(\d+) ay=(\d+) t=(.*)$")
INK_THRESHOLD = 380
ICON_BOX = (28, 8, 14, 2)
SCALE = int(sys.argv[3]) if len(sys.argv) > 3 else 1

failures = 0


def check(ok, message):
    global failures
    print(("ok   " if ok else "FAIL ") + message)
    if not ok:
        failures += 1


def load_ppm(path):
    data = open(path, "rb").read()
    fields = []
    pos = 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    pos += 1
    return int(fields[1]), int(fields[2]), data[pos:]


def is_ink(img, x, y):
    width, height, pix = img
    if x < 0 or y < 0 or x >= width or y >= height:
        return False
    at = (y * width + x) * 3
    return pix[at] + pix[at + 1] + pix[at + 2] < INK_THRESHOLD


def ink_right_edge(img, x0, x1, y0, y1):
    edge = -1
    for x in range(x0, x1):
        for y in range(y0, y1):
            if is_ink(img, x, y):
                edge = x
                break
    return edge


def ink_count(img, x0, x1, y0, y1):
    return sum(1 for x in range(x0, x1) for y in range(y0, y1) if is_ink(img, x, y))


def has_ink(img, x0, x1, y0, y1):
    return ink_right_edge(img, x0, x1, y0, y1) >= 0


def main():
    serial_path, photo_path = sys.argv[1], sys.argv[2]
    lines = []
    for raw in open(serial_path, errors="replace"):
        raw = raw.rstrip("\n")
        m = TEXT_LINE.search(raw)
        if m:
            lines.append((int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)),
                          int(m.group(5)), int(m.group(6)), m.group(7)))
    img = load_ppm(photo_path)
    texts = {t for (_, _, _, _, _, _, t) in lines}

    check("Unten" in texts, "edge dropdown shows the localized word")
    check("bottom" not in texts, "edge dropdown does not show the raw config word")

    konten = {(x, base) for (kind, x, base, _, _, _, t) in lines if kind == 1 and t == "Konten"}
    check(len(konten) == 1, "navigation lists Konten once (rows: %d)" % len(konten))

    head = [(x, base, ax, ay) for (kind, x, base, _, ax, ay, t) in lines
            if kind == 1 and t == "Datenschutz & Sicherheit"]
    check(len(head) > 0, "navigation lists Datenschutz & Sicherheit")
    if head:
        x, base, ax, ay = head[-1]
        left, right, up, down = ICON_BOX
        check(has_ink(img, x + ax - left, x + ax - right, base + ay - up, base + ay + down),
              "Datenschutz & Sicherheit row has an icon")

    toggles = [t for (kind, _, _, _, _, _, t) in lines if kind == 3]
    check(len(toggles) > 0, "taskbar page lists toggle rows")
    row = [(x, base, ax, ay) for (kind, x, base, _, ax, ay, t) in lines if kind == 3 and "verbergen" in t]
    if row:
        x, base, ax, ay = row[-1]
        s = SCALE
        gap = ink_count(img, x + ax, x + ax + 200 * s, base + ay - 6 * s, base + ay - 3 * s)
        lines_above = ink_count(img, x + ax, x + ax + 200 * s, base + ay - 14 * s, base + ay - 9 * s)
        check(lines_above > 0 and gap < 40 * s, "autohide label wraps onto a second line (ink above %d, gap %d)" % (lines_above, gap))

    print("TBSETTINGS checks: %d failed" % failures)
    sys.exit(1 if failures else 0)


main()
