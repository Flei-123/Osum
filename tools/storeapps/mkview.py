#!/usr/bin/env python3
import os
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

CATEGORIES = [("tools", "Werkzeuge", "Tools"), ("internet", "Internet", "Internet")]
LIMIT_DE = "Am HP instabil.|Nur ein Fenster."
LIMIT_EN = "Unstable on the HP.|One window only."


def row(*cells):
    return "\t".join(str(c) for c in cells)


def variant(app, art, platforms, level, gate="", build="", device="", at="", notes=("", ""), limits=("", ""),
            version="1.0.0", pkg="", available=1):
    return row("V", app, art, platforms, version, 0, "", pkg, "", 0, 0, available, level, build, device, at, gate,
               notes[0], notes[1], limits[0], limits[1], "")


def app(app_id, name_de, name_en, category="tools", kind="", requires=""):
    cells = ["A", app_id, name_de, name_en, category, "Fleitec", "GPL-2.0-only", "Kurz " + name_de,
             "Short " + name_en, "Lang " + name_de, "Long " + name_en, "netz,disk", "", "a.png,b.png"]
    if kind or requires:
        cells += [kind, requires]
    return row(*cells)


def good_rows():
    tested = dict(build="main test", device="QEMU", at="2026-11-20")
    rows = ["#apps\t2\t7"]
    rows += [row("C", cid, de, en) for cid, de, en in CATEGORIES]
    rows += [app("com.test.native", "Nativ", "Native"),
             variant("com.test.native", "opk", "osum-x86_64", "works", gate="tools/test", pkg="opk:nativ", **tested),
             app("com.test.partial", "Teilweise", "Partial", "internet"),
             variant("com.test.partial", "system", "osum-linux-x86_64", "partial", gate="tools/linux",
                     notes=("Teilweise nutzbar.", "Partly usable."), limits=(LIMIT_DE, LIMIT_EN), **tested),
             app("com.test.wine", "Wein", "Wine"),
             variant("com.test.wine", "exe", "osum-windows-x86_64", "broken", gate="tools/wine", available=0,
                     notes=("Startet nicht.", "Does not start."), **tested),
             app("com.test.phone", "Handy", "Phone"),
             variant("com.test.phone", "apk", "android-arm64", "works", gate="tools/phone", **tested),
             app("com.test.mixed", "Gemischt", "Mixed"),
             variant("com.test.mixed", "apk", "android-arm64", "broken", notes=("x", "x"), **tested),
             variant("com.test.mixed", "opk", "osum-any", "untested", pkg="opk:mixed"),
             app("com.test.nogate", "Ohne Beleg", "No evidence"),
             variant("com.test.nogate", "opk", "osum-x86_64", "works", **tested)]
    return rows


def window_rows():
    tested = dict(build="main test", device="QEMU", at="2026-11-20")
    rows = ["#apps\t2\t8"]
    rows += [row("C", cid, de, en) for cid, de, en in CATEGORIES]
    rows += [app("com.fleitec.hallo", "Hallo", "Hallo"),
             variant("com.fleitec.hallo", "opk", "osum-x86_64", "works", gate="tools/test", pkg="opk:hallo", **tested),
             app("com.fleitec.gruss", "Gruss", "Gruss", "internet"),
             variant("com.fleitec.gruss", "opk", "osum-x86_64", "works", gate="tools/test", pkg="opk:gruss", **tested),
             app("org.test.wine", "Weinprogramm", "Wine program"),
             variant("org.test.wine", "exe", "osum-windows-x86_64", "broken", gate="tools/wine", available=0,
                     notes=("Startet nicht.", "Does not start."), **tested),
             app("org.test.lfox", "Feuerfuchs", "Fire fox", "internet"),
             variant("org.test.lfox", "system", "osum-linux-x86_64", "partial", gate="tools/linux",
                     notes=("Teilweise nutzbar.", "Partly usable."), limits=(LIMIT_DE, LIMIT_EN), **tested)]
    return rows


def tabs_rows():
    tested = dict(build="main test", device="QEMU", at="2026-11-20")

    def entry(app_id, name, **extra):
        return [app(app_id, name, name, **extra),
                variant(app_id, "opk", "osum-x86_64", "works", gate="tools/test", pkg="opk:" + app_id.split(".")[-1], **tested)]

    rows = ["#apps\t2\t8"]
    rows += [row("C", cid, de, en) for cid, de, en in CATEGORIES]
    rows += entry("com.fleitec.hallo", "Hallo")
    rows += entry("com.test.tabnative", "Tabnativ")
    rows += entry("com.test.sysbox", "Sysbox", kind="system")
    rows += entry("org.test.winert", "Weinlauf", kind="runtime")
    rows += entry("org.test.clitool", "Klitool", kind="cli")
    rows += entry("org.test.winapp", "Weinapp", requires="winert>=9.0")
    return rows


def sign(seed_path, data):
    seed = open(seed_path, "rb").read()
    return Ed25519PrivateKey.from_private_bytes(seed).sign(data)


def gen(directory):
    os.makedirs(directory, exist_ok=True)
    key = Ed25519PrivateKey.generate()
    seed = key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    pub = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    open(os.path.join(directory, "catalog.seed"), "wb").write(seed)
    open(os.path.join(directory, "catalog.pub"), "wb").write(pub)


def write(directory, seed_path, flip, rows=None):
    data = ("\n".join(rows or good_rows()) + "\n").encode("utf-8")
    sig = sign(seed_path, data)
    if flip:
        data = data.replace(b"Nativ", b"Natxv", 1)
    open(os.path.join(directory, "apps.tsv"), "wb").write(data)
    open(os.path.join(directory, "apps.tsv.sig"), "wb").write(sig)


def main(argv):
    if argv[1] == "gen":
        gen(argv[2])
    elif argv[1] == "write":
        write(argv[2], argv[3], len(argv) > 4 and argv[4] == "flip")
    elif argv[1] == "tabs":
        write(argv[2], argv[3], False, tabs_rows())
    elif argv[1] == "window":
        write(argv[2], argv[3], False, window_rows())
    else:
        sys.exit(2)


main(sys.argv)
