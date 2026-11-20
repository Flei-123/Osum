#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import json
import os
import sys

ICON_SIZES = (72, 44, 64)
UNLISTED = {"installer", "welcome", "launcher", "run", "osk", "widgets"}
CATEGORIES = {
    "certus": "internet", "firefox": "internet",
    "charmap": "tools", "cliphist": "tools", "snip": "tools", "vault": "tools",
    "editor": "productivity", "nedit": "productivity", "pdfview": "productivity",
    "terminal": "development",
    "viewer": "media", "vplay": "media",
}
DEFAULT_CATEGORY = "system"


def read_info(path):
    info = {}
    for line in open(path, encoding="utf-8").read().splitlines():
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            info[key.strip()] = value.strip()
    return info


def render_icons(svg_path, out_dir):
    import cairosvg
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    for size in ICON_SIZES:
        png = cairosvg.svg2png(url=svg_path, output_width=size, output_height=size)
        Image.open(io.BytesIO(png)).convert("RGBA").save(os.path.join(out_dir, "%d.png" % size))


def export(root, out):
    apps = {}
    bundles = os.path.join(root, "assets/apps")
    for entry in sorted(os.listdir(bundles)):
        info_path = os.path.join(bundles, entry, "INFO")
        if not entry.endswith(".osp") or not os.path.isfile(info_path):
            continue
        short = entry[:-4]
        info = read_info(info_path)
        app_id = info.get("id") or "com.fleitec." + short
        apps[app_id] = {
            "short": short,
            "name": info.get("name", short).replace("{{PRODUCT}}", "OrientOS"),
            "summary": info.get("info", ""),
            "developer": info.get("author", "Fleitec"),
            "license": info.get("license", ""),
            "version": info.get("version", "1.0.0"),
            "revision": int(info.get("revision", "1")),
            "category": CATEGORIES.get(short, DEFAULT_CATEGORY),
            "listed": short not in UNLISTED,
        }
        svg = os.path.join(bundles, entry, "symbol.svg")
        if os.path.isfile(svg):
            render_icons(svg, os.path.join(out, "icons", app_id))
    with open(os.path.join(out, "system_apps.json"), "w", encoding="utf-8") as f:
        json.dump({"apps": apps}, f, indent=2, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    return len(apps)


if __name__ == "__main__":
    os.makedirs(sys.argv[2], exist_ok=True)
    print("exported %d system apps" % export(sys.argv[1], sys.argv[2]))
