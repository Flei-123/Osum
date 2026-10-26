# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import descbuild
import hidcaps
import layouts

MEASURED = "2026-10-26"
SYNTH_NOTE = "SYNTHESIZED from HidP capabilities, not the device's raw descriptor"
CORPUS = os.path.join(HERE, "corpus", "holo-laptop-3")
GENERIC_NOTES = [
    "only HidP capabilities were available: no raw descriptor, no item order, no collection types, no flags",
    "Button caps carry no size or range: every Button is 1 bit with logical 0..1 and no physical range",
    "all value fields are Data,Variable,Absolute (0x02); padding items are Constant,Variable (0x03)",
    "the Report ID is declared inside the top-level collection, before the first field of each report",
    "logical and physical numbers use minimal signed 1/2/4 byte encodings; unit exponent and unit are the "
    "raw HidP values (nibble 14 = -2, 12 = -4, 0 = 0; unit 0x11 = cm, 0x1001 = s)",
    "physical/unit globals are only emitted for Value caps and are inherited by Button fields",
    "collection types are assumed: top-level Application, Finger/Device Settings Logical, Stylus Physical",
]


def synthesize(caps):
    nodes, notes = layouts.layout_for(caps)
    builder = descbuild.build(nodes)
    return bytes(builder.out), builder.lengths(), GENERIC_NOTES + notes + builder.notes


def render_meta(source, caps, desc, lengths, notes):
    lines = [
        "source: %s" % source,
        "measured: %s" % MEASURED,
        "note: %s" % SYNTH_NOTE,
        "top_level: 0x%x/0x%x" % (caps.top_page, caps.top_usage),
        "descriptor_bytes: %d" % len(desc),
        "computed_inlen: %d" % lengths["IN"],
        "computed_outlen: %d" % lengths["OUT"],
        "computed_featlen: %d" % lengths["FEAT"],
        "caps_inlen: %d" % caps.inlen,
        "caps_outlen: %d" % caps.outlen,
        "caps_featlen: %d" % caps.featlen,
    ]
    lines += ["assumption: %s" % note for note in notes]
    return "\n".join(lines) + "\n"


def write_pair(caps_path, outdir):
    caps = hidcaps.load(caps_path)
    desc, lengths, notes = synthesize(caps)
    expected = (caps.inlen, caps.outlen, caps.featlen)
    if (lengths["IN"], lengths["OUT"], lengths["FEAT"]) != expected:
        raise SystemExit("%s: computed lengths %s differ from caps %s" % (caps.name, lengths, expected))
    base = os.path.join(outdir, caps.name)
    with open(base + ".desc.hex", "w", encoding="utf-8") as handle:
        handle.write(desc.hex() + "\n")
    with open(base + ".desc.meta", "w", encoding="utf-8") as handle:
        handle.write(render_meta(os.path.basename(caps_path), caps, desc, lengths, notes))
    return caps.name, len(desc)


def main(argv):
    outdir = None
    paths = []
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--outdir":
            outdir = args.pop(0)
        else:
            paths.append(arg)
    if not paths:
        paths = sorted(os.path.join(CORPUS, n) for n in os.listdir(CORPUS) if n.endswith(".caps"))
    for path in paths:
        name, size = write_pair(path, outdir or os.path.dirname(os.path.abspath(path)))
        print("%s: %d bytes" % (name, size))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
