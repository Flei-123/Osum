import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEGACY_FILE = os.path.join(HERE, "legacy-slugs.txt")


def legacy_slugs():
    with open(LEGACY_FILE, encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


def render(slug, name):
    lines = ["slug=" + slug, "name=" + name]
    for legacy in legacy_slugs():
        if legacy.lower() != slug.lower():
            lines.append("alt=" + legacy)
    return "\n".join(lines) + "\n"


def main(argv):
    if len(argv) != 4:
        sys.exit("usage: bootreg_cfg.py <slug> <name> <out>")
    with open(argv[3], "w", encoding="utf-8", newline="\n") as f:
        f.write(render(argv[1], argv[2]))


if __name__ == "__main__":
    main(sys.argv)
