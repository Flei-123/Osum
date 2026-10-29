#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys

SIDEBAR_POINT = "140,300"
LABELS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"


def tab_name(page):
    return "srecttab" + (LABELS[page] if page < 26 else str(page))


def parse_pagemap(path):
    pages = {}
    for line in open(path, encoding="utf-8"):
        words = line.split()
        if len(words) == 3 and words[0] == "page":
            pages[int(words[1])] = words[2]
    return pages


def parent_uri(uri):
    scheme, _, rest = uri.partition("://")
    segments = rest.split("/")
    if len(segments) < 2:
        return None
    return scheme + "://" + segments[0]


def drehbuch(pages, yres):
    by_uri = {uri: page for page, uri in pages.items()}
    lines = ["warte 12", "klick 24,%d" % (yres - 20), "warte 3", "klickauf start_Settings", "warte 12", "foto 00-start"]
    for page in sorted(pages):
        parent = parent_uri(pages[page])
        if parent in by_uri:
            lines += ["klicksuche %s %s" % (tab_name(by_uri[parent]), SIDEBAR_POINT), "warte 2"]
        lines += ["klicksuche %s %s" % (tab_name(page), SIDEBAR_POINT), "warte 2", "foto page-" + LABELS[page]]
    lines += ["taste ctrl-f", "tippe zzzz", "warte 2", "foto search-empty"]
    return "\n".join(lines) + "\n"


def main():
    sys.stdout.write(drehbuch(parse_pagemap(sys.argv[1]), int(sys.argv[2])))


if __name__ == "__main__":
    main()
