import os
import sys
from PIL import Image, ImageDraw

THUMB_WIDTH = 480
GAP = 12
COLUMNS = 3
BACKGROUND = (32, 32, 32)
LABEL_COLOR = (230, 230, 230)
LABEL_HEIGHT = 18


def main():
    folder = sys.argv[1]
    names = sorted(f for f in os.listdir(folder) if f.endswith(".png") and f != "index.png")
    if not names:
        raise SystemExit("sheet: no pictures in %s" % folder)
    thumbs = []
    for name in names:
        image = Image.open(os.path.join(folder, name)).convert("RGB")
        height = image.height * THUMB_WIDTH // image.width
        thumbs.append((name[:-4], image.resize((THUMB_WIDTH, height), Image.LANCZOS)))
    row_height = max(t.height for _, t in thumbs) + LABEL_HEIGHT
    rows = (len(thumbs) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGB", (COLUMNS * (THUMB_WIDTH + GAP) + GAP, rows * (row_height + GAP) + GAP), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    for index, (label, thumb) in enumerate(thumbs):
        x = GAP + (index % COLUMNS) * (THUMB_WIDTH + GAP)
        y = GAP + (index // COLUMNS) * (row_height + GAP)
        draw.text((x, y), label, fill=LABEL_COLOR)
        sheet.paste(thumb, (x, y + LABEL_HEIGHT))
    sheet.save(os.path.join(folder, "index.png"), optimize=True)
    write_gallery(folder, [n for n, _ in thumbs])


def write_gallery(folder, labels):
    cells = "".join('<figure><img src="%s.png" loading="lazy"><figcaption>%s</figcaption></figure>' % (n, n) for n in labels)
    page = ('<!doctype html><meta charset="utf-8"><title>%s</title>'
            '<style>body{background:#202020;color:#e6e6e6;font:13px sans-serif;margin:12px}'
            'main{display:grid;grid-template-columns:repeat(auto-fill,minmax(480px,1fr));gap:12px}'
            'img{width:100%%;display:block}figure{margin:0}</style><main>%s</main>' % (os.path.basename(folder), cells))
    with open(os.path.join(folder, "index.html"), "w", encoding="utf-8") as handle:
        handle.write(page)


main()
