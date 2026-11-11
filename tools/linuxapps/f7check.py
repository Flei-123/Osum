#!/usr/bin/env python3
import re
import sys

BAD_MARKERS = (b"MOZ_CRASH", b"Redirecting call to abort", b"Gtk:ERROR", b"Segmentation fault")
NEEDED = (
    ("load", re.compile(rb"^FXLOAD ")),
    ("typed text", re.compile(rb"^FXINPUT a")),
    ("key press", re.compile(rb"^FXKEY ")),
    ("wheel", re.compile(rb"^FXWHEEL ")),
    ("scroll", re.compile(rb"^FXSCROLL [1-9]")),
    ("click", re.compile(rb"^FXCLICK ")),
)


def verdict(path):
    lines = open(path, "rb").read().splitlines()
    for line in lines:
        for marker in BAD_MARKERS:
            if marker in line:
                return "red", "crash marker: " + marker.decode()
    missing = [name for name, pat in NEEDED if not any(pat.match(l) for l in lines)]
    if missing:
        return "red", "page never saw: " + ", ".join(missing)
    return "green", "load, typing, key, wheel, scroll and click all reached the page"


if __name__ == "__main__":
    state, why = verdict(sys.argv[1])
    print(state, why)
    sys.exit(0 if state == "green" else 1)
