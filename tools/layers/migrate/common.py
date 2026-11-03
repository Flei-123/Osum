import re, os, subprocess, collections

CALL = re.compile(r'(?<![\w.])([A-Za-z_][A-Za-z0-9_]*)\s*\(')
KW = {'if', 'while', 'return', 'as', 'fn', 'for', 'match', 'sizeof'}


def mask(t):
    return re.sub(r'//[^\n]*', lambda m: ' ' * len(m.group(0)), t)


def callees(body):
    return {c for c in CALL.findall(body) if c not in KW and not c.startswith('__')}


def module_ok(mt, m, path=None):
    path = path or 'libc.' + m
    plain = re.sub(r'"[^"\n]*"', '""', re.sub(r'^import .*$', '', mt, flags=re.M))
    if re.search(r'(?<![\w.])%s\b(?!\.)' % m, plain):
        return False
    for im in re.finditer(r'^import\s+([\w.]+)\s*$', mt, re.M):
        if im.group(1).split('.')[-1] == m and im.group(1) != path:
            return False
    return True


def drop_export(text, name):
    def fix(m):
        block = m.group(0)
        block = re.sub(r'(?<![\w.])%s\s*,[ \t]*' % re.escape(name), '', block, count=1)
        return re.sub(r',\s*%s\b(?=\s*\})' % re.escape(name), '', block, count=1)
    return re.sub(r'export\s*\{[^}]*\}', fix, text)


def add_imports(out, needed):
    lines = out.split('\n')
    last = -1
    have = set()
    for i, ln in enumerate(lines):
        mm = re.match(r'import\s+([\w.]+)\s*$', ln)
        if mm:
            last = i
            have.add(mm.group(1))
    add = ['import %s' % m for m in sorted(needed) if m not in have]
    if add:
        if last >= 0:
            lines[last + 1:last + 1] = add
        else:
            pos = 0
            while pos < len(lines) and lines[pos].startswith('//'):
                pos += 1
            lines[pos:pos] = add + ['']
    return '\n'.join(lines)


def exports_of(mt):
    out = set()
    for e in re.finditer(r'export\s*\{([^}]*)\}', mt):
        out |= {x.strip() for x in e.group(1).replace('\n', ' ').split(',') if x.strip()}
    return out


def tracked_files():
    return subprocess.check_output(['git', 'ls-files', '*.fi']).decode().split()


def scan_references(all_files, skip_prefix=('lib/libc/',)):
    stem_count = collections.Counter(os.path.basename(f)[:-3] for f in all_files)
    ext = collections.defaultdict(set)
    ext_sites = collections.defaultdict(set)
    ext_value = set()
    texts = {}
    for f in all_files:
        if f.startswith(skip_prefix):
            continue
        t = open(f, errors='replace').read()
        texts[f] = t
        for m in re.finditer(r'\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)\b(\s*\()?', mask(t)):
            key = (m.group(1), m.group(2))
            if m.group(3) is None:
                ext_value.add(key)
            elif f.startswith('vendor/'):
                ext_value.add(key)
            else:
                ext_sites[key].add(f)
            ext[m.group(2)].add(m.group(1))
    return stem_count, ext, ext_sites, ext_value, texts


def resolve_import(importer, path):
    rel = path.replace('.', '/') + '.fi'
    bases = [os.path.dirname(importer), 'lib']
    if importer.startswith('kernel/'):
        bases.append('kernel')
    for base in bases:
        candidate = os.path.normpath(os.path.join(base, rel))
        if os.path.exists(candidate):
            return candidate
    return None


def file_imports(mt):
    return re.findall(r'^import\s+([\w.]+)\s*$', mt, re.M)


def spelling_for(importer, mt, target, preferred):
    for p in file_imports(mt):
        if resolve_import(importer, p) == target:
            return p
    if resolve_import(importer, preferred) == target:
        return preferred
    if target.startswith('lib/'):
        return target[4:-3].replace('/', '.')
    return None


def imports_file(importer, mt, target):
    return any(resolve_import(importer, p) == target for p in file_imports(mt))


def remove_import(text, path):
    return re.sub(r'^import\s+%s\s*\n' % re.escape(path), '', text, count=1, flags=re.M)
