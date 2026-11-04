import re

TOKEN = re.compile(r"([A-Za-z0-9_.\-]+)=(\S*)")


def tokens(line):
    return {k: v for k, v in TOKEN.findall(line)}


def merge_tokens(text):
    out = {}
    for line in text.splitlines():
        out.update(tokens(line))
    return out


def colon_pairs(text):
    out = {}
    for line in text.splitlines():
        if ": " in line:
            key, value = line.split(": ", 1)
            out[key.strip()] = value.strip()
    return out


def space_pairs(text):
    out = {}
    for line in text.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and not line.startswith("#"):
            out[parts[0]] = parts[1].strip()
    return out


def as_int(value, default=0):
    try:
        return int(str(value), 0)
    except (TypeError, ValueError):
        return default


def lines_with(text, prefix):
    return [line for line in text.splitlines() if line.startswith(prefix)]
