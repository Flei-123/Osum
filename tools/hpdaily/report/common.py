from dataclasses import dataclass

GREEN = "green"
YELLOW = "yellow"
RED = "red"
UNKNOWN = "unknown"

MIB = 1048576
IDLE_CORE_GREEN = 90
IDLE_CORE_YELLOW = 70


@dataclass
class Check:
    id: str
    title: str
    status: str
    detail: str


def parse_kv(text):
    data = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def num(data, key, default=None):
    raw = data.get(key, "")
    try:
        return float(raw)
    except ValueError:
        return default


def integer(data, key, default=None):
    value = num(data, key)
    return default if value is None else int(value)


def graded(value, green_max, yellow_max):
    if value is None or value < 0:
        return UNKNOWN
    if value <= green_max:
        return GREEN
    if value <= yellow_max:
        return YELLOW
    return RED


def worst(statuses):
    for level in (RED, YELLOW, UNKNOWN, GREEN):
        if level in statuses:
            return level
    return UNKNOWN
