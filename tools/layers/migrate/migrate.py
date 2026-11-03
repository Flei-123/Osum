import re, sys, os, subprocess, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import norm as N

def nn(hm, full):
    return N.norm(hm, full[:hm.start(2) - hm.start()] + 'F' + full[hm.end(2) - hm.start():])


MODS = sys.argv[1].split(',')
APPLY = len(sys.argv) > 2 and sys.argv[2] == 'apply'
ROOT = os.getcwd()
CALL = re.compile(r'(?<![\w.])([A-Za-z_][A-Za-z0-9_]*)\s*\(')
KW = {'if', 'while', 'return', 'as', 'fn', 'for', 'match', 'sizeof'}


def mask(t):
    return re.sub(r'//[^\n]*', lambda m: ' ' * len(m.group(0)), t)


def callees(body):
    return {c for c in CALL.findall(body) if c not in KW and not c.startswith('__')}


files = subprocess.check_output(['git', 'ls-files', '*.fi']).decode().split()
files = [f for f in files if not f.startswith(('vendor/', 'tests/', 'lib/libc/', 'tools/'))]

if os.environ.get('ONLY'):
    files = [f for f in files if f in os.environ['ONLY'].split(',')]

libfns = {}
for m in MODS:
    path = 'lib/libc/%s.fi' % m
    t = mask(open(path).read())
    exp = set()
    for e in re.finditer(r'export\s*\{([^}]*)\}', t):
        exp |= {x.strip() for x in e.group(1).replace('\n', ' ').split(',') if x.strip()}
    for hm, full, body in N.blocks(t):
        name = hm.group(2)
        if name in exp:
            form = nn(hm, full)
            libfns.setdefault(form, []).append((m, name, callees(body)))

at = mask(open(os.path.join(HERE, 'aliases.fi')).read())
for hm, full, body in N.blocks(at):
    mod, lname = hm.group(2).split('__')
    libfns.setdefault(nn(hm, full), []).append((mod, lname, callees(body)))

ext = collections.defaultdict(set)
texts = {}
for f in files:
    t = open(f, errors='replace').read()
    texts[f] = t
    for m in re.finditer(r'\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(', mask(t)):
        ext[m.group(2)].add(m.group(1))

changed = []
report = collections.Counter()
for f in files:
    t = texts[f]
    mt = mask(t)
    stem = os.path.basename(f)[:-3]
    exported = set()
    for e in re.finditer(r'export\s*\{([^}]*)\}', mt):
        exported |= {x.strip() for x in e.group(1).replace('\n', ' ').split(',') if x.strip()}
    blocks = list(N.blocks(mt))
    if not blocks:
        continue
    local = {}
    for hm, full, body in blocks:
        local.setdefault(hm.group(2), []).append((hm, full, body))
    resolved = {}
    removal = []
    progress = True
    while progress:
        progress = False
        for hm, full, body in blocks:
            name = hm.group(2)
            if name in resolved or hm.group(1) or len(local[name]) != 1:
                continue
            if name in exported or stem in ext.get(name, ()):
                continue
            if re.search(r'(?<![\w.])(?<!fn )%s\b(?!\s*\()' % re.escape(name), mt):
                continue
            form = nn(hm, full)
            cand = libfns.get(form)
            if not cand:
                continue
            mod, lname, lcallees = cand[0]
            mycallees = callees(body)
            if mycallees != lcallees:
                continue
            if any(resolved.get(c, (None, None))[1] != c for c in mycallees if c in local):
                continue
            if any(c not in local and c not in {x[1] for x in resolved.values()} for c in mycallees):
                continue
            resolved[name] = (mod, lname)
            removal.append((hm.start(), hm.start() + len(full), name))
            progress = True
    if not resolved:
        continue
    mods_needed = {m for m, _ in resolved.values()}
    ok_mods = set()
    for m in mods_needed:
        bad = False
        if re.search(r'(?<![\w.])%s\b(?!\.)' % m, re.sub(r'^import .*$', '', mt, flags=re.M)):
            bad = True
        for im in re.finditer(r'^import\s+([\w.]+)\s*$', mt, re.M):
            if im.group(1).split('.')[-1] == m and im.group(1) != 'libc.' + m:
                bad = True
        if not bad:
            ok_mods.add(m)
    resolved = {k: v for k, v in resolved.items() if v[0] in ok_mods}
    if not resolved:
        continue
    removal = [r for r in removal if r[2] in resolved]
    out = t
    for s, e, name in sorted(removal, reverse=True):
        b = e
        while b < len(out) and out[b] == '\n':
            b += 1
        out = out[:s] + out[b:]
    for name, (mod, lname) in resolved.items():
        out = re.sub(r'(?<![\w.])%s(\s*)\(' % re.escape(name), lambda m: '%s.%s%s(' % (mod, lname, m.group(1)), out)
    needed = sorted({m for m, _ in resolved.values()})
    lines = out.split('\n')
    last = -1
    have = set()
    for i, ln in enumerate(lines):
        mm = re.match(r'import\s+([\w.]+)\s*$', ln)
        if mm:
            last = i
            have.add(mm.group(1))
    add = ['import libc.%s' % m for m in needed if 'libc.%s' % m not in have]
    if add:
        if last >= 0:
            lines[last + 1:last + 1] = add
        else:
            pos = 0
            while pos < len(lines) and lines[pos].startswith('//'):
                pos += 1
            lines[pos:pos] = add + ['']
    out = '\n'.join(lines)
    for name, (mod, lname) in resolved.items():
        report[(mod, lname)] += 1
    changed.append(f)
    if APPLY:
        open(f, 'w').write(out)

print('files', len(changed))
for k, v in sorted(report.items(), key=lambda x: -x[1]):
    print(k, v)
if os.environ.get('CHANGED_OUT'):
    open(os.environ['CHANGED_OUT'], 'w').write('\n'.join(changed))
