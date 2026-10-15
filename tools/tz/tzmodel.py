# SPDX-License-Identifier: GPL-2.0-only
# tools/tz/tzmodel.py -- python twin of the rules in lib/tz/tz.fi (used by gen.py and by
# the gate as an independent second reading). RULES: 0 none, 1 EU, 2 US, 3 AU, 4 NZ.
import datetime as dt
RULES = [0, 1, 2, 3, 4]

def _days(y, m, d):
    return (dt.date(y, m, d) - dt.date(1970, 1, 1)).days

def _last_sun(y, m, mlen):
    d = _days(y, m, mlen)
    return d - (d + 4) % 7

def _nth_sun(y, m, n):
    d = _days(y, m, 1)
    first = d + (7 - (d + 4) % 7) % 7
    return first + 7 * (n - 1)

def dst(t, base, rule):
    if rule == 0:
        return False
    if rule == 1:
        y = dt.datetime.fromtimestamp(t, dt.timezone.utc).year
        return _last_sun(y, 3, 31) * 86400 + 3600 <= t < _last_sun(y, 10, 31) * 86400 + 3600
    ls = t + base * 60
    y = dt.datetime.fromtimestamp(ls, dt.timezone.utc).year
    if rule == 2:
        return _nth_sun(y, 3, 2) * 86400 + 7200 <= ls < _nth_sun(y, 11, 1) * 86400 + 3600
    if rule == 3:
        return ls >= _nth_sun(y, 10, 1) * 86400 + 7200 or ls < _nth_sun(y, 4, 1) * 86400 + 7200
    if rule == 4:
        return ls >= _last_sun(y, 9, 30) * 86400 + 7200 or ls < _nth_sun(y, 4, 1) * 86400 + 7200
    raise ValueError(rule)

def offset_min(t, base, rule):
    return base + (60 if dst(t, base, rule) else 0)
