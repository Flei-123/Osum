# SPDX-License-Identifier: GPL-2.0-only
# tools/tz/tzmodel.py -- python twin of the rules in lib/tz/rules.fi + lib/tz/tz.fi (used by gen.py
# and by the gate as an independent second reading). Rule numbers: see NAMES.
import datetime as dt

NAMES = ["none", "eu", "us", "au", "nz", "cl", "cu", "il", "eg"]
RULES = list(range(len(NAMES)))
SUN, THU, FRI = 6, 3, 4
HOUR = 3600
# (start month, window start day, weekday (Mon=0), seconds, ref), (end ...), southern
TABLE = {
    1: ((3, 25, SUN, 1 * HOUR, "utc"), (10, 25, SUN, 1 * HOUR, "utc"), False),
    2: ((3, 8, SUN, 2 * HOUR, "std"), (11, 1, SUN, 1 * HOUR, "std"), False),
    3: ((10, 1, SUN, 2 * HOUR, "std"), (4, 1, SUN, 2 * HOUR, "std"), True),
    4: ((9, 24, SUN, 2 * HOUR, "std"), (4, 1, SUN, 2 * HOUR, "std"), True),
    5: ((9, 2, SUN, 4 * HOUR, "utc"), (4, 2, SUN, 3 * HOUR, "utc"), True),
    6: ((3, 8, SUN, 0, "std"), (11, 1, SUN, 0, "std"), False),
    7: ((3, 23, FRI, 2 * HOUR, "std"), (10, 25, SUN, 1 * HOUR, "std"), False),
    8: ((4, 24, FRI, 0, "std"), (10, 25, THU, 23 * HOUR, "std"), False),
}


def _boundary(y, spec, base):
    month, dom, wd, secs, ref = spec
    d = dt.date(y, month, dom)
    d += dt.timedelta(days=(wd - d.weekday()) % 7)
    t = (d - dt.date(1970, 1, 1)).days * 86400 + secs
    if ref == "std":
        t -= base * 60
    return t


def dst(t, base, rule):
    if rule == 0:
        return False
    start, end, south = TABLE[rule]
    y = dt.datetime.fromtimestamp(t + base * 60, dt.timezone.utc).year
    a = _boundary(y, start, base)
    b = _boundary(y, end, base)
    if south:
        return t >= a or t < b
    return a <= t < b


def offset_min(t, base, rule):
    return base + (60 if dst(t, base, rule) else 0)
