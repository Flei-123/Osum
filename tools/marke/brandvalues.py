import os
import sys

MAX = 32
MAX_URL = 96
FIELDS = {
    "PRODUKT": MAX,
    "KERN": MAX,
    "HERSTELLER": MAX,
    "KURZ": MAX,
    "WEB": MAX_URL,
    "FEED": MAX_URL,
}


def fail(message):
    sys.exit("marke: " + message)


def read_conf(path):
    values = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            text = line.strip()
            if not text or text.startswith("#") or "=" not in text:
                continue
            key, value = text.split("=", 1)
            key = key.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            values[key] = value
    return values


def apply_env(values):
    for key in FIELDS:
        env = os.environ.get("OSUM_MARKE_" + key)
        if env:
            values[key] = env
    return values


def validate(values):
    missing = [k for k in FIELDS if k not in values]
    if missing:
        fail("missing fields: %s" % ", ".join(sorted(missing)))
    for key, limit in FIELDS.items():
        value = values[key]
        if not value:
            fail("%s is empty" % key)
        if len(value) > limit - 1:
            fail("%s is %d characters long, at most %d are allowed "
                 "(kernel/lib/brand.fi)" % (key, len(value), limit - 1))
        if '"' in value or "\\" in value or "\n" in value:
            fail("%s contains a character that is not allowed in a Firn "
                 "literal" % key)
    if values["KURZ"] != values["KURZ"].lower() or " " in values["KURZ"]:
        fail("KURZ must be lowercase without blanks (it is used in file "
             "names)")
    return values


def load(path):
    return validate(apply_env(read_conf(path)))
