import os
import re
import sys

FN_RE = re.compile(r'^\s*(?:export\s+)?fn\s+(\w+)\s*\(([^)]*)\)')
RET_ABS_RE = re.compile(r'^\s*return\s+state\s*\+')
ACCESSORS = ('kstate.get(', 'kstate.set(', 'kstate.add(', 'fget(', 'fset(', 'rget(', 'rset(')
LET_RE = re.compile(r'^\s*(?:let|var)\s+(\w+)\s*(?::\s*\w+)?\s*=\s*(.*)$')


def kernel_files(root):
    for base, _, names in os.walk(os.path.join(root, 'kernel')):
        for name in names:
            if name.endswith('.fi'):
                yield os.path.join(base, name)


def read_lines(path):
    with open(path, encoding='utf-8', errors='replace') as handle:
        return handle.read().split('\n')


def split_functions(lines):
    current = None
    for number, line in enumerate(lines, 1):
        match = FN_RE.match(line)
        if match:
            if current:
                yield current
            current = (match.group(1), number, [])
        if current:
            current[2].append((number, line))
    if current:
        yield current


def absolute_helpers(root):
    helpers = {}
    for path in kernel_files(root):
        for name, number, body in split_functions(read_lines(path)):
            if len(body) > 6:
                continue
            if any(RET_ABS_RE.match(line) for _, line in body):
                helpers.setdefault(name, []).append((path, number))
    return helpers


def call_regex(names):
    return re.compile(r'(?<![\w])(?:\w+\.)?(' + '|'.join(map(re.escape, names)) + r')\s*\(\s*state\b')


def second_argument(tail):
    depth = 0
    parts = []
    current = ''
    for char in tail:
        if char in '([':
            depth += 1
        elif char in ')]':
            if depth == 0:
                break
            depth -= 1
        if char == ',' and depth == 0:
            parts.append(current)
            current = ''
            if len(parts) == 2:
                break
            continue
        current += char
    parts.append(current)
    return parts[1] if len(parts) > 1 else ''


def scan_function(path, name, body, helpers, call_re):
    tainted = {}
    hits = []
    for number, line in body:
        stripped = line.split('//')[0]
        let = LET_RE.match(stripped)
        if let and call_re.search(let.group(2)) and not any(a in let.group(2) for a in ACCESSORS):
            tainted[let.group(1)] = number
        for accessor in ACCESSORS:
            found = re.search(r'(?<![\w])' + re.escape(accessor), stripped)
            if not found:
                continue
            index = found.start()
            tail = stripped[index + len(accessor):]
            if not tail.lstrip().startswith('state'):
                continue
            rest = second_argument(tail)
            if call_re.search(rest):
                hits.append((path, number, 'direct', line.strip()))
                continue
            for var in tainted:
                if re.search(r'(?<![\w.])' + re.escape(var) + r'(?![\w(])', rest):
                    hits.append((path, number, 'via ' + var, line.strip()))
    return hits


def main(root):
    helpers = absolute_helpers(root)
    call_re = call_regex(sorted(helpers))
    total = []
    for path in kernel_files(root):
        for name, number, body in split_functions(read_lines(path)):
            total.extend(scan_function(path, name, body, helpers, call_re))
    for path, number, kind, text in total:
        print('%s:%d: [%s] %s' % (os.path.relpath(path, root), number, kind, text))
    print('helpers=%d hits=%d' % (len(helpers), len(total)))
    return 0 if not total else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
