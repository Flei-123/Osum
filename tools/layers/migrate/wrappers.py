import re, sys, os, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import norm as N
from common import (mask, drop_export, exports_of, tracked_files, scan_references, resolve_import,
                    spelling_for, imports_file, remove_import, module_ok, add_imports, file_imports)

APPLY = len(sys.argv) > 1 and sys.argv[1] == 'apply'
ROOT = os.getcwd()
FORWARD = re.compile(r'^\s*(?:return\s+)?([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(([^()]*)\)\s*;?\s*$')
SKIP = ('vendor/', 'tests/', 'lib/libc/', 'tools/')
TARGET_ROOTS = ('lib/', 'kernel/lib/')


def split_params(raw):
    return [p.strip() for p in raw.split(',') if p.strip()]


def signature(hm):
    params = [tuple(x.strip() for x in p.split(':', 1)) for p in split_params(hm.group(3))]
    return [t for _, t in params], re.sub(r'\s+', ' ', (hm.group(4) or '').strip())


def import_path(mt, mod):
    for im in re.finditer(r'^import\s+([\w.]+)\s*$', mt, re.M):
        if im.group(1).split('.')[-1] == mod:
            return im.group(1)
    return None


all_files = tracked_files()
stem_count, ext, ext_sites, ext_value, texts = scan_references(all_files)
stem_files = collections.defaultdict(list)
for f in all_files:
    stem_files[os.path.basename(f)[:-3]].append(f)

target_cache = {}


def target_signature(mod, fname):
    key = (mod, fname)
    if key in target_cache:
        return target_cache[key]
    result = None
    files = stem_files.get(mod, [])
    if len(files) == 1 and files[0] in texts or len(files) == 1:
        path = files[0]
        text = texts.get(path)
        if text is None:
            text = open(path, errors='replace').read()
        for hm, full, body in N.blocks(mask(text)):
            if hm.group(2) == fname:
                result = signature(hm)
                break
    target_cache[key] = result
    return result


def plan_external(f, mt, stem, name, mod, fname, path, callers):
    if (stem, name) in ext_value:
        return None
    target = resolve_import(f, path)
    if target is None or not target.startswith(TARGET_ROOTS):
        return None
    sites = {}
    for g in callers:
        if g.startswith('vendor/') or g == f:
            return None
        gt = texts.get(g)
        if gt is None:
            return None
        gm = mask(gt)
        if not imports_file(g, gm, f):
            return None
        spell = spelling_for(g, gm, target, path)
        if spell is None or not module_ok(gm, mod, spell):
            return None
        sites[g] = spell
    return sites


def apply_external(stem, name, mod, fname, sites, f):
    for g, spell in sites.items():
        gt = texts[g]
        gt = re.sub(r'(?<![\w.])%s\.%s(\s*)\(' % (re.escape(stem), re.escape(name)),
                    lambda m: '%s.%s%s(' % (mod, fname, m.group(1)), gt)
        gt = add_imports(gt, {spell})
        if not re.search(r'(?<![\w.])%s\.' % re.escape(stem), mask(re.sub(r'^import .*$', '', gt, flags=re.M))):
            for p in file_imports(mask(gt)):
                if resolve_import(g, p) == f:
                    gt = remove_import(gt, p)
        texts[g] = gt
        if g not in changed:
            changed.append(g)


external = {}
changed = []
report = collections.Counter()
for f in [x for x in all_files if not x.startswith(SKIP)]:
    t = texts[f]
    mt = mask(t)
    stem = os.path.basename(f)[:-3]
    exported = exports_of(mt)
    mt_body = re.sub(r'export\s*\{[^}]*\}', lambda m: ' ' * len(m.group(0)), mt)
    blocks = list(N.blocks(mt))
    if not blocks:
        continue
    count = collections.Counter(hm.group(2) for hm, _, _ in blocks)
    found = {}
    for hm, full, body in blocks:
        name = hm.group(2)
        if hm.group(1) or count[name] != 1:
            continue
        inner = full[full.index('{', hm.end() - hm.start() - 1) + 1:-1]
        fm = FORWARD.match(inner.strip())
        if not fm:
            continue
        mod, fname, rawargs = fm.group(1), fm.group(2), fm.group(3)
        params = [p.split(':')[0].strip() for p in split_params(hm.group(3))]
        if split_params(rawargs) != params:
            continue
        if re.search(r'(?<![\w.])(?<!fn )%s\b(?!\s*\()' % re.escape(name), mt_body):
            continue
        path = import_path(mt, mod)
        if not path or mod == stem:
            continue
        want = target_signature(mod, fname)
        if want is None or want != signature(hm):
            continue
        callers = ext_sites.get((stem, name), set())
        if name in exported or callers or stem in ext.get(name, ()):
            plan = plan_external(f, mt, stem, name, mod, fname, path, callers)
            if plan is None:
                continue
            external[name] = plan
        found[name] = (hm.start(), hm.start() + len(full), mod, fname, path)
    if not found:
        continue
    out = t
    for name, (s, e, mod, fname, path) in sorted(found.items(), key=lambda x: -x[1][0]):
        b = e
        while b < len(out) and out[b] == '\n':
            b += 1
        out = out[:s] + out[b:]
    for name, (s, e, mod, fname, path) in found.items():
        out = drop_export(out, name)
        out = re.sub(r'(?<![\w.])%s(\s*)\(' % re.escape(name), lambda m: '%s.%s%s(' % (mod, fname, m.group(1)), out)
        report[(mod, fname)] += 1
    texts[f] = out
    if f not in changed:
        changed.append(f)
    for name, sites in external.items():
        mod, fname = found[name][2], found[name][3]
        apply_external(stem, name, mod, fname, sites, f)
    external.clear()

if APPLY:
    for f in changed:
        open(f, 'w').write(texts[f])
print('files', len(changed), 'wrappers', sum(report.values()))
for k, v in report.most_common(25):
    print(k, v)
if os.environ.get('CHANGED_OUT'):
    open(os.environ['CHANGED_OUT'], 'w').write('\n'.join(changed))
