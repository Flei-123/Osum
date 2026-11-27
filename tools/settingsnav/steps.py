#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

SIDEBAR_POINT = "140,300"
CONTENT_POINT = os.environ.get("SETTINGSNAV_POINT", "700,400")
LABELS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
SETTINGS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "kernel", "user", "settings.d")


def tab_name(page):
    return "srecttab" + (LABELS[page] if page < 26 else str(page))


def load_pagemap(path):
    pages = {}
    for line in open(path, encoding="utf-8"):
        words = line.split()
        if len(words) == 3 and words[0] == "page":
            pages[words[2]] = int(words[1])
    return pages


def load_routes(path):
    routes = []
    for line in open(path, encoding="utf-8"):
        words = line.split()
        if len(words) >= 2 and words[0] == "route":
            routes.append((words[1], "advanced" in words[2:]))
    return routes


def head_of(uri):
    scheme, _, rest = uri.partition("://")
    return scheme + "://" + rest.split("/")[0]


def landing_page(head, pages, routes):
    if head in pages:
        return pages[head]
    for uri, advanced in routes:
        if uri != head and head_of(uri) == head and uri in pages and not advanced:
            return pages[uri]
    return None


def clicks(page, pages=None, routes=None):
    pages = pages or load_pagemap(os.path.join(SETTINGS_DIR, "settings.pagemap"))
    routes = routes or load_routes(os.path.join(SETTINGS_DIR, "settings.routes"))
    uri = {p: u for u, p in pages.items()}[page]
    landing = landing_page(head_of(uri), pages, routes)
    steps = []
    if landing is not None:
        steps.append(("klicksuche %s %s" % (tab_name(landing), SIDEBAR_POINT)))
    if landing != page:
        steps.append("klicksuche %s %s" % (tab_name(page), CONTENT_POINT))
    return steps


def drehbuch_lines(page, wait=2):
    lines = []
    for step in clicks(page):
        lines += [step, "warte %d" % wait]
    return lines


def main():
    for arg in sys.argv[1:]:
        sys.stdout.write("\n".join(drehbuch_lines(int(arg))) + "\n")


if __name__ == "__main__":
    main()
