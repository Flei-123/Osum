import hashlib
import re
import sys

PATH_A = "path: boot():/osum.mb"
PATH_B = "path: boot():/osum-b.mb"


def lines_of(text):
    return text.splitlines(keepends=True)


def reference(text):
    lines = lines_of(text)
    starts = [i for i, l in enumerate(lines) if l.startswith("/")]
    if not starts or lines[starts[0]].startswith("//"):
        return 1, None
    first = starts[0]
    end = starts[1] if len(starts) > 1 else len(lines)
    block = lines[first:end]
    idx = [i for i, l in enumerate(block) if l.strip(" \t\r\n") == PATH_A and l.lstrip(" \t").startswith(PATH_A)]
    if not idx:
        return 2, None
    head = lines[:first]
    d = [i for i, l in enumerate(head) if l.startswith("default_entry:")]
    if d:
        val = head[d[0]][len("default_entry:"):].strip()
        if val not in ("1", "2"):
            return 3, None
    b_lines = [i for i, l in enumerate(lines) if l.lstrip(" \t").rstrip("\r\n") == PATH_B]
    has_b = bool(b_lines)
    if has_b:
        e3 = starts[2] if len(starts) > 2 else len(lines)
        if end >= len(lines) or not (end <= b_lines[0] < e3) or lines[end].startswith("//"):
            return 4, None
    out_head = list(head)
    if d:
        eol = re.search(r"[\r\n].*$", head[d[0]], re.S)
        tail = head[d[0]][eol.start():] if eol else ""
        out_head[d[0]] = "default_entry: 2" + tail
    else:
        out_head = ["default_entry: 2\n"] + out_head
    out = out_head + block
    if not has_b:
        a_text = "".join(block)
        if not a_text.endswith("\n"):
            out.append("\n")
        if not (a_text.endswith("\n\n") or a_text.endswith("\n\r\n")):
            out.append("\n")
        b = list(block)
        t = re.match(r"([^\r\n]*)(.*)$", b[0], re.S)
        b[0] = t.group(1) + " (update)" + t.group(2)
        k = idx[0]
        pos = b[k].index(PATH_A)
        b[k] = b[k][:pos] + PATH_B + b[k][pos + len(PATH_A):]
        out += b
    out += lines[end:]
    return 0, "".join(out)


if __name__ == "__main__":
    raw = open(sys.argv[1], "rb").read().decode("latin1")
    st, res = reference(raw)
    if res is not None:
        open(sys.argv[2], "wb").write(res.encode("latin1"))
    print(st)
