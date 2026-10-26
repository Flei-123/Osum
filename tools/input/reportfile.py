# SPDX-License-Identifier: GPL-2.0-only
from dataclasses import dataclass

SEPARATOR = " | fields: "
GROUP_ORDER = ("tip", "conf", "id", "x", "y")


@dataclass(frozen=True)
class Line:
    device: str
    name: str
    hex: str
    values: dict


def format_values(values, order):
    parts = []
    seen = set()
    for key in order:
        if key not in values:
            continue
        prefix, _, leaf = key.partition(".")
        if not leaf:
            parts.append("%s=%d" % (key, values[key]))
        elif prefix not in seen:
            seen.add(prefix)
            leaves = sorted((k.partition(".")[2] for k in values if k.partition(".")[0] == prefix and "." in k),
                            key=GROUP_ORDER.index)
            parts.append("%s=%s" % (prefix, ",".join("%s:%d" % (l, values[prefix + "." + l]) for l in leaves)))
    return " ".join(parts)


def parse_values(text):
    values = {}
    for token in text.split():
        key, _, rest = token.partition("=")
        if ":" in rest:
            for item in rest.split(","):
                leaf, _, number = item.partition(":")
                values[key + "." + leaf] = int(number)
        else:
            values[key] = int(rest)
    return values


def format_line(line, order):
    return "%s %s %s%s%s" % (line.device, line.name, line.hex, SEPARATOR, format_values(line.values, order))


def parse_line(text):
    head, sep, tail = text.partition(SEPARATOR)
    if not sep:
        raise ValueError("report line without fields part: %r" % text)
    device, name, hexdata = head.split()
    return Line(device, name, hexdata, parse_values(tail))


def parse_file(text):
    return [parse_line(l) for l in text.splitlines() if l.strip() and not l.startswith("#")]
