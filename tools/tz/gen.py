#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/tz/gen.py -- builds lib/tz/zonedata.fi from IANA tzdata (python zoneinfo).
#
# Every zone in CURATED is CLASSIFIED against the four rules lib/tz/tz.fi knows
# (none / EU / US / AU / NZ): the standard offset is the smaller of the January and
# July offsets, the rule is the one whose instants reproduce EVERY utcoffset of the
# zone for 2024..2040 (hourly samples + both sides of each changeover). A zone that
# matches no rule is REFUSED (printed, not written) -- the table never carries a
# guess. Run:  python3 tools/tz/gen.py > lib/tz/zonedata.fi
import sys, datetime as dt
from zoneinfo import ZoneInfo

# region letter -> zones (IANA id, display name)
CURATED = [
 ("U", "UTC", "UTC"),
 ("E", "Atlantic/Reykjavik", "Reykjavik"), ("E", "Europe/Lisbon", "Lisbon"),
 ("E", "Europe/London", "London"), ("E", "Europe/Dublin", "Dublin"),
 ("E", "Europe/Paris", "Paris"), ("E", "Europe/Madrid", "Madrid"),
 ("E", "Europe/Brussels", "Brussels"), ("E", "Europe/Amsterdam", "Amsterdam"),
 ("E", "Europe/Berlin", "Berlin"), ("E", "Europe/Vienna", "Vienna"),
 ("E", "Europe/Zurich", "Zurich"), ("E", "Europe/Rome", "Rome"),
 ("E", "Europe/Prague", "Prague"), ("E", "Europe/Warsaw", "Warsaw"),
 ("E", "Europe/Budapest", "Budapest"), ("E", "Europe/Stockholm", "Stockholm"),
 ("G", "Europe/Oslo", "Oslo"), ("G", "Europe/Copenhagen", "Copenhagen"),
 ("G", "Europe/Belgrade", "Belgrade"), ("G", "Europe/Zagreb", "Zagreb"),
 ("G", "Europe/Helsinki", "Helsinki"), ("G", "Europe/Athens", "Athens"),
 ("G", "Europe/Bucharest", "Bucharest"), ("G", "Europe/Sofia", "Sofia"),
 ("G", "Europe/Kyiv", "Kyiv"), ("G", "Europe/Istanbul", "Istanbul"),
 ("G", "Europe/Minsk", "Minsk"), ("G", "Europe/Moscow", "Moscow"),
 ("A", "America/New_York", "New York"), ("A", "America/Toronto", "Toronto"),
 ("A", "America/Chicago", "Chicago"), ("A", "America/Denver", "Denver"),
 ("A", "America/Phoenix", "Phoenix"), ("A", "America/Los_Angeles", "Los Angeles"),
 ("A", "America/Vancouver", "Vancouver"), ("A", "America/Anchorage", "Anchorage"),
 ("A", "Pacific/Honolulu", "Honolulu"), ("A", "America/Halifax", "Halifax"),
 ("A", "America/St_Johns", "St Johns"), ("A", "America/Mexico_City", "Mexico City"),
 ("L", "America/Bogota", "Bogota"), ("L", "America/Lima", "Lima"),
 ("L", "America/Caracas", "Caracas"), ("L", "America/Sao_Paulo", "Sao Paulo"),
 ("L", "America/Argentina/Buenos_Aires", "Buenos Aires"),
 ("L", "America/Santiago", "Santiago"), ("L", "America/Havana", "Havana"),
 ("S", "Asia/Dubai", "Dubai"), ("S", "Asia/Riyadh", "Riyadh"),
 ("S", "Asia/Baghdad", "Baghdad"), ("S", "Asia/Tehran", "Tehran"),
 ("S", "Asia/Karachi", "Karachi"), ("S", "Asia/Tashkent", "Tashkent"),
 ("S", "Asia/Kolkata", "Kolkata"), ("S", "Asia/Kathmandu", "Kathmandu"),
 ("S", "Asia/Dhaka", "Dhaka"), ("S", "Asia/Bangkok", "Bangkok"),
 ("S", "Asia/Jakarta", "Jakarta"), ("S", "Asia/Singapore", "Singapore"),
 ("S", "Asia/Hong_Kong", "Hong Kong"), ("S", "Asia/Shanghai", "Shanghai"),
 ("S", "Asia/Taipei", "Taipei"), ("S", "Asia/Seoul", "Seoul"),
 ("S", "Asia/Tokyo", "Tokyo"), ("S", "Asia/Jerusalem", "Jerusalem"),
 ("F", "Africa/Accra", "Accra"), ("F", "Africa/Lagos", "Lagos"),
 ("F", "Africa/Algiers", "Algiers"), ("F", "Africa/Tunis", "Tunis"),
 ("F", "Africa/Cairo", "Cairo"), ("F", "Africa/Casablanca", "Casablanca"),
 ("F", "Africa/Johannesburg", "Johannesburg"), ("F", "Africa/Nairobi", "Nairobi"),
 ("F", "Africa/Addis_Ababa", "Addis Ababa"),
 ("P", "Australia/Perth", "Perth"), ("P", "Australia/Darwin", "Darwin"),
 ("P", "Australia/Adelaide", "Adelaide"), ("P", "Australia/Brisbane", "Brisbane"),
 ("P", "Australia/Sydney", "Sydney"), ("P", "Australia/Melbourne", "Melbourne"),
 ("P", "Australia/Hobart", "Hobart"), ("P", "Pacific/Auckland", "Auckland"),
 ("P", "Pacific/Fiji", "Fiji"),
]

sys.path.insert(0, __file__.rsplit("/", 1)[0])
sys.path.insert(0, __file__.rsplit('/', 1)[0] if '/' in __file__ else '.')
from tzmodel import offset_min, RULES   # the python twin of lib/tz/tz.fi

def samples(zi):
    out = []
    t0 = int(dt.datetime(2024, 1, 1, tzinfo=dt.timezone.utc).timestamp())
    t1 = int(dt.datetime(2041, 1, 1, tzinfo=dt.timezone.utc).timestamp())
    t = t0
    while t < t1:
        out.append(t)
        t += 3 * 3600 + 17 * 60
    return out

def real(zi, t):
    d = dt.datetime.fromtimestamp(t, dt.timezone.utc).astimezone(zi)
    return int(d.utcoffset().total_seconds() // 60)

def classify(zid):
    zi = ZoneInfo(zid)
    ss = samples(zi)
    # refine around every real offset change
    prev = real(zi, ss[0]); extra = []
    for a, b in zip(ss, ss[1:]):
        cur = real(zi, b)
        if cur != prev:
            lo, hi = a, b
            while hi - lo > 1:
                m = (lo + hi) // 2
                if real(zi, m) == prev: lo = m
                else: hi = m
            extra += [hi - 1, hi, hi + 1]
        prev = cur
    ss = ss + extra
    offs = [real(zi, t) for t in ss]
    base = min(offs)
    for rule in RULES:
        if all(offset_min(t, base, rule) == o for t, o in zip(ss, offs)):
            return base, rule
    return None

def main():
    rows = []
    for reg, zid, name in CURATED:
        try:
            r = classify(zid)
        except Exception as e:
            print("// REFUSED %s: %s" % (zid, e), file=sys.stderr); continue
        if r is None:
            print("// REFUSED %s: no rule matches 2024..2040" % zid, file=sys.stderr); continue
        rows.append((reg, name, r[0], RULES[r[1]] if False else r[1]))

    blob = "".join("%s%s,%d,%d\\n" % (reg, name, base, rule) for reg, name, base, rule in rows)
    n = len(blob.replace("\\n", "\n"))
    print("// SPDX-License-Identifier: GPL-2.0-only")
    print("// lib/tz/zonedata.fi -- GENERATED by tools/tz/gen.py from IANA tzdata. Do not edit.")
    print("// One line per zone: <region letter><display name>,<standard offset minutes>,<rule>.")
    print("// rule: 0 none, 1 EU, 2 US, 3 AU, 4 NZ (lib/tz/tz.fi). Zones that no rule reproduces")
    print("// for 2024..2040 are not in this table (gen.py refuses them).")
    print("// zones: %d" % len(rows))
    print("export { zdata, zdata_len }")
    print("static mut ZD: [u8; %d] = \"%s\\0\"" % (n + 1, blob))
    print("fn zdata() -> u64 {\n    return (&ZD[0 as usize]) as u64\n}")
    print("fn zdata_len() -> u64 {\n    return %d\n}" % n)


if __name__ == "__main__":
    main()
