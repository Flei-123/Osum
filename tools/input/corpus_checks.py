# SPDX-License-Identifier: GPL-2.0-only
import bitreader
import caps2desc
import handhex
import hidcaps
import hidwalk
import refparser
import reportoracle

PAGE_DIGITIZER = 0xD
FINGER_USAGE = 0x22
TOUCHPAD_FINGERS = 5
SYNTH_MARK = "SYNTHESIZED from HidP capabilities"


class Result:
    def __init__(self):
        self.items = []

    def add(self, ok, label, detail=""):
        self.items.append((bool(ok), label, "" if ok else detail))

    @property
    def fails(self):
        return [i for i in self.items if not i[0]]


def signature(element):
    const = element["const"]
    return (element["kind"], element["rid"], None if const else element["page"],
            None if const else element["usage"], element["bitoff"], element["bits"],
            element["lmin"], element["lmax"], const)


def build_runs(elements):
    runs = []
    for element in elements:
        if element["const"]:
            continue
        last = runs[-1] if runs else None
        if last and all(last[k] == element[k] for k in ("kind", "rid", "page", "usage", "bits", "lmin", "lmax", "link")) \
                and element["bitoff"] == last["bitoff"] + last["n"] * last["bits"]:
            last["n"] += 1
        else:
            runs.append(dict(element, n=1))
    return runs


def run_key(item):
    return (item["kind"], item["rid"], item["page"], item["usage"])


def cap_key(cap):
    return (cap.kind, cap.rid, cap.page, cap.usage)


def compare_cap(cap, run, with_link):
    problems = []
    for name, got, want in (("bits", run["bits"], cap.bits), ("count", run["n"], cap.count),
                            ("lmin", run["lmin"], cap.lmin), ("lmax", run["lmax"], cap.lmax)):
        if got != want:
            problems.append("%s %s != %s" % (name, got, want))
    if with_link:
        if run["link"] != cap.link:
            problems.append("link %s != %s" % (run["link"], cap.link))
        if cap.pmin is not None:
            for name, want in (("pmin", cap.pmin), ("pmax", cap.pmax), ("unitexp", cap.unitexp), ("unit", cap.unit)):
                if run[name] != want:
                    problems.append("%s %s != %s" % (name, run[name], want))
    return problems


def match_caps(caps, runs, with_link):
    by_key = {}
    for run in runs:
        by_key.setdefault(run_key(run), []).append(run)
    claimed = set()
    outcomes = []
    ordered = sorted(caps.caps, key=lambda c: (cap_key(c), c.link))
    position = {}
    for cap in ordered:
        key = cap_key(cap)
        pool = by_key.get(key, [])
        index = position.get(key, 0)
        position[key] = index + 1
        if with_link:
            free = [r for r in pool if r["link"] == cap.link and id(r) not in claimed]
            run = free[0] if free else None
        else:
            run = pool[index] if index < len(pool) else None
        if run is None:
            outcomes.append((cap, ["no matching field"]))
            continue
        claimed.add(id(run))
        outcomes.append((cap, compare_cap(cap, run, with_link)))
    unclaimed = [r for r in runs if id(r) not in claimed]
    return outcomes, unclaimed


def describe_run(run):
    return "%s rid=%d page=0x%x usage=0x%x bits=%d n=%d" % (
        run["kind"], run["rid"], run["page"], run["usage"], run["bits"], run["n"])


def parse_meta(text):
    meta = {}
    notes = []
    for line in text.splitlines():
        key, _, value = line.partition(": ")
        if key == "assumption":
            notes.append(value)
        else:
            meta[key] = value
    meta["assumptions"] = notes
    return meta


def check_meta(r, caps, desc, meta_text):
    name = caps.name
    meta = parse_meta(meta_text)
    r.add(SYNTH_MARK in meta.get("note", ""), "%s: meta states the descriptor is synthesized" % name)
    r.add(meta.get("measured") == caps2desc.MEASURED, "%s: meta measurement date" % name, meta.get("measured", ""))
    r.add(meta.get("descriptor_bytes") == str(len(desc)), "%s: meta descriptor size" % name)
    for key, want in (("computed_inlen", caps.inlen), ("computed_outlen", caps.outlen), ("computed_featlen", caps.featlen)):
        r.add(meta.get(key) == str(want), "%s: meta %s" % (name, key), "%s != %s" % (meta.get(key), want))
    r.add(len(meta["assumptions"]) >= 5, "%s: meta lists assumptions" % name)


def check_regeneration(r, caps, desc):
    name = caps.name
    try:
        first, _, _ = caps2desc.synthesize(caps)
        second, _, _ = caps2desc.synthesize(caps)
    except ValueError as error:
        r.add(False, "%s: generator accepts the caps" % name, str(error))
        return
    r.add(first == second, "%s: generator is deterministic" % name)
    r.add(first == desc, "%s: stored descriptor equals generator output" % name)


def check_lengths(r, caps, head, state):
    name = caps.name
    lengths, rids = refparser.report_bytes(head)
    for kind, want in (("IN", caps.inlen), ("OUT", caps.outlen), ("FEAT", caps.featlen)):
        r.add(lengths[kind] == want, "%s: %s report length from reference parser" % (name, kind),
              "%d != %d" % (lengths[kind], want))
        walked = max([1 + (bits + 7) // 8 for (k, _), bits in state.bits.items() if k == kind and bits], default=0)
        r.add(walked == want, "%s: %s report length from walker" % (name, kind), "%d != %d" % (walked, want))
        r.add(rids[kind] == set(caps.rids(kind)), "%s: %s report ids" % (name, kind),
              "%s != %s" % (sorted(rids[kind]), caps.rids(kind)))


def check_structure(r, caps, head, state):
    name = caps.name
    r.add(head["top"] == (caps.top_page << 16 | caps.top_usage), "%s: top-level usage (reference parser)" % name,
          "0x%x" % head["top"])
    first = state.collections[0] if state.collections else None
    r.add(first is not None and (first["page"], first["usage"]) == (caps.top_page, caps.top_usage),
          "%s: top-level usage (walker)" % name)
    r.add(len(state.collections) == caps.nlink, "%s: link collection count" % name,
          "%d != %d" % (len(state.collections), caps.nlink))
    fingers = [c for c in state.collections if (c["page"], c["usage"]) == (PAGE_DIGITIZER, FINGER_USAGE)]
    wanted_links = len({c.link for c in caps.caps if c.link > 0})
    if (caps.top_page, caps.top_usage) == (PAGE_DIGITIZER, 0x05):
        r.add(len(fingers) == TOUCHPAD_FINGERS, "%s: finger collections == %d" % (name, TOUCHPAD_FINGERS),
              str(len(fingers)))
        r.add(wanted_links == TOUCHPAD_FINGERS, "%s: caps declare %d finger links" % (name, TOUCHPAD_FINGERS),
              str(wanted_links))
    counted = hidcaps.header_counts(caps)
    for key, want in sorted(caps.counts.items()):
        r.add(counted[key] == want, "%s: caps header %s matches caps lines" % (name, key), "%d != %d" % (counted[key], want))


def check_matches(r, caps, ref, state):
    name = caps.name
    ref_elements = [dict(e, link=None) for e in ref]
    for tag, runs, with_link in (("reference table", build_runs(ref_elements), False),
                                 ("walker (link, physical, unit)", build_runs(state.elements), True)):
        outcomes, unclaimed = match_caps(caps, runs, with_link)
        for cap, problems in outcomes:
            r.add(not problems, "%s: %s in %s" % (name, cap.label(), tag), "; ".join(problems))
        r.add(not unclaimed, "%s: every non-const field is claimed by a caps line (%s)" % (name, tag),
              "; ".join(describe_run(u) for u in unclaimed))


def check_device(caps, desc, meta_text=None, regen=True):
    r = Result()
    name = caps.name
    head, fields = refparser.parse(desc)
    r.add(head["ok"] == 1, "%s: reference parser accepts the descriptor" % name,
          "err=%d at %d" % (head["err"], head["errat"]))
    try:
        state = hidwalk.walk(desc)
    except hidwalk.WalkError as error:
        r.add(False, "%s: walker accepts the descriptor" % name, str(error))
        return r
    r.add(True, "%s: walker accepts the descriptor" % name)
    if not head["ok"]:
        return r
    ref = refparser.expand(fields)
    r.add([signature(e) for e in ref] == [signature(e) for e in state.elements],
          "%s: reference parser and walker agree on every field" % name)
    check_structure(r, caps, head, state)
    check_lengths(r, caps, head, state)
    check_matches(r, caps, ref, state)
    if meta_text is not None:
        check_meta(r, caps, desc, meta_text)
    if regen:
        check_regeneration(r, caps, desc)
    return r


def find_element(ref, kind, rid, field):
    pool = [e for e in ref if not e["const"] and (e["kind"], e["rid"], e["page"], e["usage"]) == (kind, rid, field.page, field.usage)]
    return pool[field.occurrence] if field.occurrence < len(pool) else None


def check_report_line(r, line, ref):
    tag = "%s %s" % (line.device, line.name)
    try:
        data = bytes.fromhex(line.hex)
    except ValueError:
        r.add(False, "%s: hex parses" % tag)
        return
    kind = reportoracle.kind_for_name(line.name)
    report = reportoracle.DEVICES.get(line.device, {}).get((kind, data[0] if data else -1))
    r.add(report is not None, "%s: %s report id %s is known" % (tag, kind, data[0] if data else "?"))
    if report is None:
        return
    r.add(len(data) == report.nbytes, "%s: report length" % tag, "%d != %d" % (len(data), report.nbytes))
    if len(data) != report.nbytes:
        return
    names = {f.name for f in report.fields}
    r.add(set(line.values) <= names, "%s: only known field names" % tag, ",".join(sorted(set(line.values) - names)))
    expected = {f.name: line.values.get(f.name, 0) for f in report.fields}
    got = reportoracle.decode(report, data)
    r.add(got == expected, "%s: own bit reader matches the expected values" % tag,
          ", ".join("%s %s != %s" % (k, got[k], expected[k]) for k in expected if got[k] != expected[k]))
    stray = reportoracle.stray_bits(report, data)
    r.add(not stray, "%s: padding bits are zero" % tag, str(stray))
    hand = handhex.HAND_HEX.get((line.device, line.name))
    if hand is not None:
        r.add(hand == line.hex, "%s: bytes equal the hand-computed value" % tag)
    problems = []
    for field in report.fields:
        element = find_element(ref, kind, data[0], field)
        if element is None:
            problems.append("%s: no field in reference table" % field.name)
            continue
        offset = element["bitoff"] + reportoracle.ID_BITS
        if (offset, element["bits"]) != (field.offset, field.width):
            problems.append("%s: table says bit %d width %d, layout says bit %d width %d"
                            % (field.name, offset, element["bits"], field.offset, field.width))
            continue
        value = bitreader.read_bits_shift(data, offset, element["bits"])
        if value != expected[field.name]:
            problems.append("%s: table read %d != %d" % (field.name, value, expected[field.name]))
    r.add(not problems, "%s: reference table reads the same bits" % tag, "; ".join(problems))


def check_reports(lines, refs):
    r = Result()
    for line in lines:
        if line.device not in refs:
            r.add(False, "%s %s: descriptor for device exists" % (line.device, line.name))
            continue
        check_report_line(r, line, refs[line.device])
    return r
