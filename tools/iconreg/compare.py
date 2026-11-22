import os
import sys

from PIL import Image

PAIRS = (
    ("rechner", "calc"),
    ("editor", "editor"),
    ("terminal", "terminal"),
    ("lock", "lock"),
    ("zwischenablage", "cliphist"),
    ("datei-explorer", "explorer"),
    ("zeichentabelle", "charmap"),
    ("ausschneiden", "snip"),
)
SIZES = ((72, "symbol.osym"), (64, "symbol64.osym"), (44, "symbol44.osym"))
GROUNDS = ((255, 255, 255), (24, 28, 36))


def load_osym(path):
    data = open(path, "rb").read()
    size = int.from_bytes(data[4:8], "little")
    return Image.frombytes("RGBA", (size, size), data[12:], "raw", "BGRA")


def over(img, ground):
    base = Image.new("RGBA", img.size, ground + (255,))
    base.alpha_composite(img)
    return base.convert("RGB")


def mean_error(a, b):
    pa, pb = a.tobytes(), b.tobytes()
    return sum(abs(x - y) for x, y in zip(pa, pb)) / len(pa)


def bake_dirs(root):
    rows = (line.split("\t") for line in open(os.path.join(root, "tools/svg/apps.tsv")).read().splitlines() if line.strip())
    return {row[0]: os.path.join(root, row[5]) for row in rows}


def main(argv):
    ref_dir, root, limit = argv[0], argv[1], float(argv[2])
    dirs = bake_dirs(root)
    worst = 0.0
    for ref_name, app in PAIRS:
        ref = Image.open(os.path.join(ref_dir, "png", ref_name + ".png")).convert("RGBA")
        for size, file_name in SIZES:
            baked = load_osym(os.path.join(dirs[app], file_name))
            target = ref.resize((size, size), Image.LANCZOS)
            for ground in GROUNDS:
                err = mean_error(over(baked, ground), over(target, ground))
                worst = max(worst, err)
                print("%s %d %s err=%.2f" % (app, size, "light" if ground[0] > 200 else "dark", err))
    print("worst=%.2f limit=%.2f" % (worst, limit))
    return 0 if worst <= limit else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
