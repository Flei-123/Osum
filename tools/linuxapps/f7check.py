#!/usr/bin/env python3
import os
import re
import sys

BAD_MARKERS = (b"MOZ_CRASH", b"Redirecting call to abort", b"Gtk:ERROR", b"Segmentation fault")
NEEDED = (
    ("load", re.compile(rb"^FXLOAD ")),
    ("typed text", re.compile(rb"^FXINPUT a")),
    ("shifted key", re.compile(rb"^FXKEY D shift=true")),
    ("backspace", re.compile(rb"^FXKEY Backspace")),
    ("cursor edit", re.compile(rb"^FXINPUT abxc")),
    ("right click", re.compile(rb"^FXCTX ")),
    ("key press", re.compile(rb"^FXKEY ")),
    ("wheel", re.compile(rb"^FXWHEEL ")),
    ("scroll", re.compile(rb"^FXSCROLL [1-9]")),
    ("click", re.compile(rb"^FXCLICK ")),
    ("link navigation", re.compile(rb"^FXNAV \?nav")),
    ("url bar navigation", re.compile(rb"^FXURL \?u")),
)
POPUP_NEEDED = (("select popup choice", re.compile(rb"^FXSEL [b-f]\d$")),)
POINTER_NEEDED = (
    ("drag selection", re.compile(rb"^FXDRAG \w+ \w+")),
    ("double click word", re.compile(rb"^FXDBL \w+$")),
)


SIZE = re.compile(rb"^FX(?:SIZE|RESIZE) (\d+)x(\d+)")


def popup_enabled():
    return os.environ.get("FX7_POPUP", "0") != "0"


def pointer_enabled():
    return os.environ.get("FX7_POINTER", "1") != "0"


def grew(lines):
    sizes = [int(m.group(1)) for m in (SIZE.match(l) for l in lines) if m]
    return len(sizes) >= 2 and max(sizes[1:]) > sizes[0]


def resize_note(lines):
    if not pointer_enabled():
        return ""
    return "; window resize " + ("followed" if grew(lines) else "NOT followed")


def verdict(path):
    lines = open(path, "rb").read().splitlines()
    for line in lines:
        for marker in BAD_MARKERS:
            if marker in line:
                return "red", "crash marker: " + marker.decode()
    needed = NEEDED + (POPUP_NEEDED if popup_enabled() else ()) + (POINTER_NEEDED if pointer_enabled() else ())
    missing = [name for name, pat in needed if not any(pat.match(l) for l in lines)]
    if missing:
        return "red", "page never saw: " + ", ".join(missing) + resize_note(lines)
    if pointer_enabled() and not grew(lines):
        return "red", "window resize not followed"
    return "green", "load, typing, shifted key, backspace, cursor edit, key, wheel, scroll, click, right click, link navigation and url bar navigation all reached the page" + resize_note(lines)


if __name__ == "__main__":
    state, why = verdict(sys.argv[1])
    print(state, why)
    sys.exit(0 if state == "green" else 1)
