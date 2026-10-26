# SPDX-License-Identifier: GPL-2.0-only
MAIN, GLOBAL, LOCAL = 0, 1, 2

USAGE_PAGE, LOGICAL_MIN, LOGICAL_MAX, PHYSICAL_MIN, PHYSICAL_MAX = 0, 1, 2, 3, 4
UNIT_EXPONENT, UNIT, REPORT_SIZE, REPORT_ID, REPORT_COUNT = 5, 6, 7, 8, 9

USAGE = 0

INPUT, OUTPUT, COLLECTION, FEATURE, END_COLLECTION = 8, 9, 0xA, 0xB, 0xC
MAIN_TAG = {"IN": INPUT, "OUT": OUTPUT, "FEAT": FEATURE}

SIGNED_GLOBALS = (LOGICAL_MIN, LOGICAL_MAX, PHYSICAL_MIN, PHYSICAL_MAX)
SIZE_CODE = {0: 0, 1: 1, 2: 2, 4: 3}


def signed_bytes(value):
    for size in (1, 2, 4):
        if -(1 << (8 * size - 1)) <= value < (1 << (8 * size - 1)):
            return value.to_bytes(size, "little", signed=True)
    raise ValueError("value out of range: %d" % value)


def unsigned_bytes(value):
    if value < 0:
        raise ValueError("negative unsigned value: %d" % value)
    for size in (1, 2, 4):
        if value < (1 << (8 * size)):
            return value.to_bytes(size, "little")
    raise ValueError("value out of range: %d" % value)


def short_item(item_type, tag, data):
    return bytes([(tag << 4) | (item_type << 2) | SIZE_CODE[len(data)]]) + data


def global_item(tag, value):
    data = signed_bytes(value) if tag in SIGNED_GLOBALS else unsigned_bytes(value)
    return short_item(GLOBAL, tag, data)


def local_item(tag, value):
    return short_item(LOCAL, tag, unsigned_bytes(value))


def main_item(tag, flags):
    return short_item(MAIN, tag, bytes([flags]))


def collection_item(kind):
    return short_item(MAIN, COLLECTION, bytes([kind]))


def end_item():
    return short_item(MAIN, END_COLLECTION, b"")
