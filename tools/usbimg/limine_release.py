#!/usr/bin/env python3
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(kind):
    out = []
    with open(os.path.join(HERE, 'devparts.conf')) as handle:
        for line in handle:
            key, _, value = line.rstrip('\n').partition(' ')
            if key == kind and value:
                out.append(value)
    return out


def split_entries(lines):
    head, entries = [], []
    for line in lines:
        if line.startswith('/'):
            entries.append([line])
        elif entries:
            entries[-1].append(line)
        else:
            head.append(line)
    return head, entries


def strip_words(line, words):
    if not line.strip().startswith('cmdline:'):
        return line
    kept = [w for w in line.split(' ') if w not in words]
    return ' '.join(kept)


def filter_conf(text):
    patterns = load('entry')
    words = set(load('word'))
    head, entries = split_entries(text.split('\n'))
    kept = [e for e in entries if not any(p in e[0] for p in patterns)]
    out = list(head)
    for entry in kept:
        out.append(entry[0])
        out.extend(strip_words(l, words) for l in entry[1:])
    return '\n'.join(out)


def main(argv):
    path = argv[1]
    with open(path) as handle:
        text = handle.read()
    with open(path, 'w') as handle:
        handle.write(filter_conf(text))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
