#!/usr/bin/env python3
import os
import re
import sys

BITS_HELPER = """
#[allow_fp]
fn intr_bits_f64(x: f64) -> u64 {
    var t: f64 = x
    return *(((&t) as usize) as *mut u64)
}
"""

INCLUDE = re.compile(r'__include_str\("([^"]+)"\)')


def escape(text):
    out = []
    for ch in text:
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\t':
            out.append('\\t')
        elif ch == '\r':
            out.append('\\r')
        else:
            out.append(ch)
    return ''.join(out)


def literal_for(base, name):
    with open(os.path.join(base, name), encoding='latin1') as f:
        return '"' + escape(f.read()) + '"'


def lower_file(path):
    with open(path, encoding='latin1') as f:
        text = f.read()
    original = text
    base = os.path.dirname(os.path.realpath(path))
    text = INCLUDE.sub(lambda m: literal_for(base, m.group(1)), text)
    if '__bits(' in text:
        text = text.replace('__bits(', 'intr_bits_f64(') + BITS_HELPER
    if text == original:
        return 0
    if os.path.islink(path):
        os.unlink(path)
    with open(path, 'w', encoding='latin1') as f:
        f.write(text)
    return 1


def main():
    bau = sys.argv[1]
    changed = 0
    for rel in sys.argv[2:]:
        changed += lower_file(os.path.join(bau, rel))
    print('lowerintrinsics: %d files rewritten' % changed)


if __name__ == '__main__':
    main()
