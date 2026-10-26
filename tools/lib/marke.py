# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

FIELDS = ("PRODUKT", "KERN", "HERSTELLER", "KURZ", "WEB", "FEED")
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def load(root=ROOT):
    values = {}
    with open(os.path.join(root, "marke.conf"), encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text or text.startswith("#") or "=" not in text:
                continue
            key, value = text.split("=", 1)
            key = key.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if key in FIELDS:
                values[key] = value
    for key in FIELDS:
        override = os.environ.get("OSUM_MARKE_" + key, "")
        if override:
            values[key] = override
        if not values.get(key):
            sys.exit("marke.py: field %s missing in marke.conf" % key)
    values["DATEI"] = re.sub(r"[^a-z0-9-]", "", values["PRODUKT"].lower())
    if not values["DATEI"]:
        sys.exit("marke.py: no file name derivable from PRODUKT")
    return values


_values = load()
PRODUKT = _values["PRODUKT"]
KERN = _values["KERN"]
HERSTELLER = _values["HERSTELLER"]
KURZ = _values["KURZ"]
WEB = _values["WEB"]
FEED = _values["FEED"]
DATEI = _values["DATEI"]

if __name__ == "__main__":
    for name in sys.argv[1:] or ("PRODUKT",):
        print(_values[name])
