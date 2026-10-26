#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "marke"))
import brandvalues
import brandrender

FIELDS = brandvalues.FIELDS
STATICS = {"PRODUKT": "s_product", "KERN": "s_core", "HERSTELLER": "s_vendor", "KURZ": "s_slug", "WEB": "s_web", "FEED": "s_feed"}


def literal(text, length):
    rest = length - len(text)
    if rest < 1:
        sys.exit("internal: '%s' does not fit in %d elements" % (text, length))
    return '"' + text + "\\0" * rest + '"'


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def set_brand(path, values):
    s = read(path)
    for key, expected in FIELDS.items():
        name = STATICS[key]
        pattern = re.compile(
            r'(static mut %s: \[u8; (\d+)\] = )"[^"]*"' % re.escape(name))
        m = pattern.search(s)
        if not m:
            sys.exit("kernel/lib/brand.fi: field %s not found" % name)
        n = int(m.group(2))
        if n != expected:
            sys.exit("kernel/lib/brand.fi: %s has %d elements, expected %d -- "
                     "marke-einsetzen.py and brand.fi disagree"
                     % (name, n, expected))
        s = pattern.sub(lambda mm: mm.group(1) + literal(values[key], n), s, 1)
    for key in FIELDS:
        rest = re.search(r'static mut %s: \[u8; \d+\] = "([^"]*)"'
                         % STATICS[key], s)
        if rest and "?" in rest.group(1):
            sys.exit("kernel/lib/brand.fi: %s is still a placeholder" % key)
    write(path, s)


def set_version(path, slug, commit):
    s = read(path)
    pattern = re.compile(r'(static mut s_fassung: \[u8; (\d+)\] = )"[^"]*"')
    m = pattern.search(s)
    if not m:
        sys.exit("kernel/lib/version.fi: s_fassung not found")
    n = int(m.group(2))
    text = "%s %s" % (slug, commit)
    if len(text) > n - 1:
        sys.exit("kernel/lib/version.fi: '%s' does not fit in %d elements -- "
                 "KURZ is too long" % (text, n))
    write(path, pattern.sub(lambda mm: mm.group(1) + literal(text, n), s, 1))
    return text


def set_image(path, image_id):
    s = read(path)
    pattern = re.compile(r'(static mut s_imageid: \[u8; (\d+)\] = )"[^"]*"')
    m = pattern.search(s)
    if not m:
        sys.exit("kernel/lib/version.fi: s_imageid not found")
    n = int(m.group(2))
    if not re.fullmatch(r"[A-Za-z0-9._+-]{1,%d}" % (n - 1), image_id):
        sys.exit("IMAGE_ID '%s' invalid (A-Z a-z 0-9 . _ + -, max %d chars)"
                 % (image_id, n - 1))
    write(path, pattern.sub(lambda mm: mm.group(1) + literal(image_id, n), s, 1))
    return image_id


def find(tree, name):
    root = os.path.join(tree, "kernel")
    for base, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d not in ("user", "app")]
        if name in names:
            return os.path.join(base, name)
    sys.exit("marke-einsetzen.py: %s is nowhere under %s" % (name, root))


def patch_kernel(argv):
    if len(argv) not in (3, 4):
        sys.exit("usage: marke-einsetzen.py <tree> <marke.conf> <hash> "
                 "[<image id>]")
    tree, conf, commit = argv[0], argv[1], argv[2]
    image_id = argv[3] if len(argv) == 4 else "dev"
    values = brandvalues.load(conf)
    set_brand(find(tree, "brand.fi"), values)
    line = set_version(find(tree, "version.fi"), values["KERN"].lower().replace(" ", ""), commit)
    print("marke: image id '%s'" % set_image(find(tree, "version.fi"), image_id))
    print("marke: PRODUKT=%s KERN=%s HERSTELLER=%s KURZ=%s"
          % (values["PRODUKT"], values["KERN"], values["HERSTELLER"],
             values["KURZ"]))
    print("marke: WEB=%s" % values["WEB"])
    print("marke: FEED=%s" % values["FEED"])
    print("marke: version line '%s'" % line)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--render":
        sys.exit(brandrender.main(["render"] + sys.argv[2:]))
    patch_kernel(sys.argv[1:])


main()
