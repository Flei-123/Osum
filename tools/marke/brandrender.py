import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brandvalues as brand_values

PLACEHOLDERS = {
    "PRODUCT": "PRODUKT",
    "SLUG": "KURZ",
    "VENDOR": "HERSTELLER",
    "WEB": "WEB",
}

TOKEN = re.compile(rb"\{\{([A-Z][A-Z0-9_]*)\}\}")
STRICT_DIRS = ("locale", "assets", "buendel")
MAX_BYTES = 1 << 20


class UnknownPlaceholder(Exception):
    pass


def table(values):
    return {name: values[field].encode("utf-8")
            for name, field in PLACEHOLDERS.items()}


def render_bytes(data, mapping, source="<data>", strict=True):
    if b"\0" in data or len(data) > MAX_BYTES or b"{{" not in data:
        return data

    def swap(match):
        name = match.group(1).decode("ascii")
        if name in mapping:
            return mapping[name]
        if strict:
            raise UnknownPlaceholder(
                "%s: unknown placeholder {{%s}}" % (source, name))
        return match.group(0)

    return TOKEN.sub(swap, data)


def is_strict_path(path):
    parts = os.path.abspath(path).split(os.sep)
    return any(p in STRICT_DIRS for p in parts)


def repo_conf(start):
    here = os.path.abspath(start)
    while True:
        candidate = os.path.join(here, "marke.conf")
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(here)
        if parent == here:
            brand_values.fail("marke.conf not found above %s" % start)
        here = parent


_cached = {}


def image_mapping():
    if "map" not in _cached:
        conf = repo_conf(os.path.dirname(os.path.abspath(__file__)))
        _cached["map"] = table(brand_values.load(conf))
    return _cached["map"]


def render_for_image(data, host):
    if b"\0" in data or len(data) > MAX_BYTES or b"{{" not in data:
        return data
    try:
        return render_bytes(data, image_mapping(), host, is_strict_path(host))
    except UnknownPlaceholder as err:
        sys.exit("marke: " + str(err))


def render_file(src, dst, mapping):
    with open(src, "rb") as f:
        data = f.read()
    out = render_bytes(data, mapping, src, True)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(out)
    return out != data


def render_tree(src, dst, mapping):
    changed = 0
    for root, dirs, names in os.walk(src):
        dirs.sort()
        rel = os.path.relpath(root, src)
        for name in sorted(names):
            target = os.path.normpath(os.path.join(dst, rel, name))
            if render_file(os.path.join(root, name), target, mapping):
                changed += 1
    return changed


def main(argv):
    if len(argv) != 4:
        sys.exit("usage: render.py <marke.conf> <source file or dir> "
                 "<destination>")
    conf, src, dst = argv[1:]
    mapping = table(brand_values.load(conf))
    try:
        if os.path.isdir(src):
            changed = render_tree(src, dst, mapping)
        else:
            changed = 1 if render_file(src, dst, mapping) else 0
    except UnknownPlaceholder as err:
        sys.exit("marke: " + str(err))
    print("marke: rendered %s -> %s (%d files with placeholders)"
          % (src, dst, changed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
