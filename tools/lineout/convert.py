import re
import sys

RULES = [
    (re.compile(rb"(?<![\w.])ulib\.sayn\("), b"lineout.add_num("),
    (re.compile(rb"(?<![\w.])ulib\.sayu\("), b"lineout.add_unum("),
    (re.compile(rb"(?<![\w.])ulib\.say\("), b"lineout.add_text("),
    (re.compile(rb"(?<![\w.])ulib\.nl\(\)"), b"lineout.end_line()"),
]
IMPORT_ULIB = re.compile(rb"^import ulib[ \t]*\r?$", re.M)
IMPORT_LINEOUT = re.compile(rb"^import lineout[ \t]*\r?$", re.M)


def convert(data):
    out = data
    for rule, repl in RULES:
        out = rule.sub(repl, out)
    if out != data and not IMPORT_LINEOUT.search(out):
        m = IMPORT_ULIB.search(out)
        if not m:
            raise SystemExit("no import ulib anchor")
        out = out[: m.end()] + b"\nimport lineout" + out[m.end() :]
    return out


def main(paths):
    for path in paths:
        with open(path, "rb") as fh:
            data = fh.read()
        out = convert(data)
        if out != data:
            with open(path, "wb") as fh:
                fh.write(out)
            print("converted", path)


if __name__ == "__main__":
    main(sys.argv[1:])
