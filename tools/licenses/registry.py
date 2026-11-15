# SPDX-License-Identifier: GPL-2.0-only
import fnmatch
import os
import re
from dataclasses import dataclass

FIELDS = ["id", "name", "version", "spdx", "profiles", "paths", "texts", "source", "copyright"]
PROFILES = {"public", "personal", "store", "future"}
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SPDX_RE = re.compile(r"^(LicenseRef-[A-Za-z0-9.-]+|[A-Za-z0-9.+-]+)( (AND|OR|WITH) [A-Za-z0-9.+-]+)*$")
SOURCE_REQUIRED = ("GPL", "LGPL", "MPL", "OFL", "CC-BY")
FOREIGN_SUFFIXES = (".ttf", ".otf", ".woff", ".woff2", ".ucode", ".pem", ".crt", ".a", ".ko", ".xkb")
FOREIGN_MARKERS = (".so", "/firmware/")
REGISTRY_PATH = "licenses/registry.txt"
NO_TEXT = "-"
TEXT_MARKERS = {
    "OFL-1.1": "SIL OPEN FONT LICENSE",
    "GPL-2.0": "GNU GENERAL PUBLIC LICENSE",
    "GPL-3.0": "GNU GENERAL PUBLIC LICENSE",
    "LGPL-2.1": "GNU LESSER GENERAL PUBLIC LICENSE",
    "MPL-2.0": "Mozilla Public License",
    "MIT": "Permission is hereby granted",
    "ISC": "Permission to use, copy, modify",
    "BSD-2-Clause": "Redistribution and use",
}


@dataclass
class Component:
    id: str
    name: str
    version: str
    spdx: str
    profiles: set
    paths: list
    texts: list
    source: str
    copyright: str


def split_list(value):
    return [] if value == NO_TEXT else [item for item in value.split(",") if item]


def parse_line(line, number):
    parts = [part.strip() for part in line.split("|")]
    if len(parts) != len(FIELDS):
        raise ValueError("registry line %d has %d fields, want %d" % (number, len(parts), len(FIELDS)))
    row = dict(zip(FIELDS, parts))
    return Component(row["id"], row["name"], row["version"], row["spdx"], set(split_list(row["profiles"])),
                     split_list(row["paths"]), split_list(row["texts"]), row["source"], row["copyright"])


def load(root, path=REGISTRY_PATH):
    components = []
    with open(os.path.join(root, path), encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if line.strip():
                components.append(parse_line(line.rstrip("\n"), number))
    return components


def read_texts(root, comp):
    chunks = []
    for text in comp.texts:
        path = os.path.join(root, text)
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as handle:
                chunks.append(handle.read())
    return "\n".join(chunks)


def missing_markers(root, comp):
    body = read_texts(root, comp)
    tokens = re.split(r"[ ()]+|-only|-or-later", comp.spdx)
    wanted = {TEXT_MARKERS[t] for t in tokens if t in TEXT_MARKERS}
    return [marker for marker in sorted(wanted) if marker.lower() not in body.lower()]


def lint(root, components):
    problems = []
    seen = set()
    for comp in components:
        if not ID_RE.match(comp.id) or comp.id in seen:
            problems.append("bad or duplicate id: %s" % comp.id)
        seen.add(comp.id)
        if not SPDX_RE.match(comp.spdx):
            problems.append("%s: bad SPDX expression %r" % (comp.id, comp.spdx))
        if not comp.profiles or not comp.profiles <= PROFILES:
            problems.append("%s: bad profiles" % comp.id)
        if any(key in comp.spdx for key in SOURCE_REQUIRED) and not comp.source.startswith("http"):
            problems.append("%s: licence needs a source or origin URL" % comp.id)
        if not comp.texts and "Public-Domain" not in comp.spdx and "CC0" not in comp.spdx:
            problems.append("%s: no licence text" % comp.id)
        for text in comp.texts:
            if not os.path.isfile(os.path.join(root, text)):
                problems.append("%s: missing licence text %s" % (comp.id, text))
        for marker in missing_markers(root, comp):
            problems.append("%s: licence texts do not contain the %r licence body" % (comp.id, marker))
    return problems


def matches(comp, dest):
    return any(fnmatch.fnmatchcase(dest, pattern) for pattern in comp.paths)


def looks_foreign(dest):
    return dest.endswith(FOREIGN_SUFFIXES) or any(marker in dest for marker in FOREIGN_MARKERS)
