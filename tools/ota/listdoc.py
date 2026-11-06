import os

STYLES = {
    "legacy": {
        "marker": "OTA2",
        "revision": "fassung",
        "keygen": "schluesselgen",
        "chain": "kette",
        "blocked": "gesperrt",
        "package": "paket",
        "files": ("VERZEICHNIS", "VERZEICHNIS.sig"),
    },
    "english": {
        "marker": "OTA3",
        "revision": "revision",
        "keygen": "keygen",
        "chain": "chain",
        "blocked": "blocked",
        "package": "package",
        "files": ("LISTING", "LISTING.sig"),
    },
}
ENV_STYLES = "OTA_LISTING_STYLES"
DEFAULT_STYLES = "legacy,english"


def active_styles():
    names = [n for n in os.environ.get(ENV_STYLES, DEFAULT_STYLES).split(",") if n]
    for name in names:
        if name not in STYLES:
            raise SystemExit("unknown listing style: " + name)
    return names


def render(style, revision, keygen, chain=(), blocked=(), packages=(), extra_lines=()):
    k = STYLES[style]
    rows = [k["marker"], "%s\t%d" % (k["revision"], revision), "%s\t%d" % (k["keygen"], keygen)]
    for link in chain:
        rows.append("%s\t%d\t%s\t%s" % (k["chain"], link["gen"], link["pub"], link["sig"]))
    for gen in blocked:
        rows.append("%s\t%d" % (k["blocked"], gen))
    for name, version, digest, size, file_name, platform in packages:
        rows.append("%s\t%s\t%s\t%s\t%d\t%s\t%s" % (k["package"], name, version, digest, size, file_name, platform))
    rows.extend(extra_lines)
    return ("\n".join(rows) + "\n").encode("ascii")


def write_signed(out_dir, sign, revision, keygen, **doc):
    written = {}
    for style in active_styles():
        text_name, sig_name = STYLES[style]["files"]
        text = render(style, revision, keygen, **doc)
        text_path = os.path.join(out_dir, text_name)
        with open(text_path, "wb") as f:
            f.write(text)
        sign(text_path, os.path.join(out_dir, sig_name))
        written[style] = text_path
    return written
