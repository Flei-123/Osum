import re
import sys

RAM_SUFFIX = " (RAM root)"


def split_entries(text):
    head = []
    entries = []
    for line in text.split("\n"):
        if line.startswith("/"):
            entries.append([line])
        elif entries:
            entries[-1].append(line)
        else:
            head.append(line)
    return head, entries


def partition_root_entry(block):
    out = []
    for line in block:
        if line.strip().startswith("module_path:"):
            continue
        if line.strip().startswith("cmdline:"):
            line = re.sub(r"(cmdline:\s*)modfs\s+", r"\1", line)
            line = re.sub(r"\s+modfs(\s|$)", r"\1", line)
        out.append(line)
    return out


def ram_root_entry(block):
    copy = list(block)
    copy[0] = copy[0].rstrip() + RAM_SUFFIX
    while copy and copy[-1].strip() == "":
        copy.pop()
    return copy


def transform(text):
    head, entries = split_entries(text)
    if not entries:
        return text
    first = entries[0]
    ram = ram_root_entry(first)
    entries[0] = partition_root_entry(first)
    lines = list(head)
    for block in entries:
        lines.extend(block)
    while lines and lines[-1].strip() == "":
        lines.pop()
    lines.append("")
    lines.extend(ram)
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    path = sys.argv[1]
    text = open(path).read()
    open(path, "w").write(transform(text))
