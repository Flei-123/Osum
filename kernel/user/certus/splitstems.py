#!/usr/bin/env python3
import hashlib
import os
import re
import shutil
import sys

IMPORT = re.compile(r'^(\s*)import ([A-Za-z0-9_.]+)(\s*)$')
PREFIX = 'osa_'
SPLIT_DIR = 'osa'


def load_merge(root):
    path = os.path.join(root, 'kernel/user/certus/merge-stems.txt')
    with open(path) as f:
        return {line.strip() for line in f if line.strip() and not line.startswith('#')}


def digest(path):
    with open(path, 'rb') as f:
        return hashlib.sha1(f.read()).hexdigest()


def read_text(path):
    with open(path, encoding='latin1') as f:
        return f.read()


def module_imports(path):
    found = []
    for line in read_text(path).split('\n'):
        m = IMPORT.match(line)
        if m:
            found.append(m.group(2))
    return found


def module_rel(mod):
    return mod.replace('.', '/') + '.fi'


class Layout:
    def __init__(self, root, bau, shared):
        self.root = root
        self.bau = bau
        self.shared = shared
        self.owned = self.find_owned()

    def find_owned(self):
        owned = set()
        for name in os.listdir(self.bau):
            path = os.path.join(self.bau, name)
            if name.endswith('.fi') and os.path.isfile(path) and not os.path.islink(path):
                if any(os.path.exists(os.path.join(self.root, d, name)) for d in ('kernel/user', 'kernel/user/fuiapp', 'lib')):
                    owned.add(name)
        for sub in ('libc', 'wlib', 'wlibc', 'uitheme'):
            base = os.path.join(self.bau, sub)
            if os.path.isdir(base) and not os.path.islink(base):
                for name in os.listdir(base):
                    if name.endswith('.fi'):
                        owned.add(sub + '/' + name)
        return owned

    def in_bau(self, path):
        return path.startswith(self.bau + os.sep)

    def bau_rel(self, path):
        return os.path.relpath(path, self.bau)

    def resolve_b(self, importer, mod):
        rel = module_rel(mod)
        for base in (os.path.dirname(importer), self.bau):
            cand = os.path.join(base, rel)
            if os.path.isfile(cand):
                return cand
        return None

    def resolve_a(self, importer, mod):
        rel = module_rel(mod)
        if rel in self.owned:
            return os.path.join(self.bau, rel)
        bases = []
        if not self.in_bau(importer):
            bases.append(os.path.dirname(importer))
        bases += [os.path.join(self.root, 'lib'), os.path.join(self.root, 'kernel/user'),
                  os.path.join(self.shared, 'lib')]
        for base in bases:
            cand = os.path.join(base, rel)
            if os.path.isfile(cand):
                return cand
        return None


def walk(roots, resolve, stop):
    seen = {}
    todo = list(roots)
    while todo:
        path = todo.pop()
        if path in seen:
            continue
        seen[path] = None
        for mod in module_imports(path):
            target = resolve(path, mod)
            if target is None or target in stop:
                continue
            todo.append(target)
    return list(seen)


def a_roots(layout):
    roots = []
    for rel in sorted(layout.owned):
        roots.append(os.path.join(layout.bau, rel))
    return roots


def plan(layout, merge):
    owned_paths = set(a_roots(layout))
    b_files = walk([os.path.join(layout.bau, 'certus_main.fi')], layout.resolve_b, owned_paths)
    b_by_rel = {}
    b_stems = set()
    for path in b_files:
        b_by_rel[layout.bau_rel(path)] = digest(path)
        b_stems.add(os.path.basename(path)[:-3])
    a_files = walk(list(owned_paths), layout.resolve_a, set())
    a_rel = {}
    for path in a_files:
        if path in owned_paths:
            continue
        rel = None
        for importer in a_files:
            for mod in module_imports(importer):
                if layout.resolve_a(importer, mod) == path:
                    rel = module_rel(mod)
                    break
            if rel:
                break
        a_rel[path] = rel
    renamed = set()
    for path, rel in a_rel.items():
        stem = os.path.basename(path)[:-3]
        same = b_by_rel.get(rel) == digest(path)
        if stem in merge:
            continue
        if not same and (stem in b_stems or rel in b_by_rel):
            renamed.add(path)
    changed = True
    while changed:
        changed = False
        for path, rel in a_rel.items():
            if path in renamed or b_by_rel.get(rel) != digest(path) or os.path.basename(path)[:-3] in merge:
                continue
            for mod in module_imports(path):
                target = layout.resolve_a(path, mod)
                b_target = layout.resolve_b(os.path.join(layout.bau, rel), mod)
                if target in renamed or target is None or b_target is None \
                        or digest(target) != digest(b_target):
                    renamed.add(path)
                    changed = True
                    break
    for path, rel in a_rel.items():
        if path in renamed or os.path.basename(path)[:-3] in merge:
            continue
        target = os.path.join(layout.bau, rel)
        parent = os.path.realpath(os.path.dirname(target))
        if b_by_rel.get(rel) != digest(path) and not parent.startswith(os.path.realpath(layout.bau) + os.sep):
            renamed.add(path)
    return a_files, a_rel, renamed, owned_paths


def rewrite(layout, path, renamed):
    text = read_text(path)
    lines = text.split('\n')
    stems = []
    for index, line in enumerate(lines):
        m = IMPORT.match(line)
        if not m:
            continue
        target = layout.resolve_a(path, m.group(2))
        if target in renamed:
            stem = os.path.basename(target)[:-3]
            lines[index] = '%simport %s.%s%s%s' % (m.group(1), SPLIT_DIR, PREFIX + stem, '', m.group(3))
            stems.append(stem)
    text = '\n'.join(lines).replace(' as% ', ' as ')
    for stem in stems:
        text = re.sub(r'(?<![A-Za-z0-9_.])%s\.(?=[A-Za-z_])' % re.escape(stem), PREFIX + stem + '.', text)
    return text


def write_clean(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.islink(path):
        os.remove(path)
    with open(path, 'w', encoding='latin1') as f:
        f.write(text)


INCLUDE_ASSET = re.compile(r'__include_str\("([^"]+)"\)')


def copy_assets(source_path, target_path, text):
    for name in INCLUDE_ASSET.findall(text):
        source = os.path.join(os.path.dirname(os.path.realpath(source_path)), name)
        target = os.path.join(os.path.dirname(target_path), name)
        if os.path.isfile(source) and not os.path.exists(target):
            shutil.copyfile(source, target)


def main(argv):
    root, bau, shared = (os.path.abspath(a) for a in argv[1:4])
    layout = Layout(root, bau, shared)
    merge = load_merge(root)
    a_files, a_rel, renamed, owned = plan(layout, merge)
    texts = {}
    for path in a_files:
        if path in owned or path in a_rel:
            texts[path] = rewrite(layout, path, renamed)
    for path in owned:
        write_clean(path, texts[path])
    written = 0
    for path, rel in a_rel.items():
        if os.path.basename(path)[:-3] in merge:
            continue
        if path in renamed:
            stem = os.path.basename(path)[:-3]
            target = os.path.join(bau, SPLIT_DIR, PREFIX + stem + '.fi')
            write_clean(target, texts[path])
            copy_assets(path, target, texts[path])
            written += 1
        elif not os.path.isfile(os.path.join(bau, rel)) or read_text(os.path.join(bau, rel)) != texts[path]:
            target = os.path.join(bau, rel)
            write_clean(target, texts[path])
            copy_assets(path, target, texts[path])
            written += 1
    print('splitstems: %d files in the Osum closure, %d renamed, %d written' % (len(a_rel), len(renamed), written))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
