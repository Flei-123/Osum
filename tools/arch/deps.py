#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/arch/deps.py -- import graph of kernel/user (+ lib/), cycles, closures, function map.

Read-only analysis, no build needed.  Firn resolution rules (measured 21.10.2026,
docs/ARCHITECTURE-DESKTOP.md section 2):
  import a.b.c   ->  <dir of importing file>/a/b/c.fi, then $FIRNLIB/a/b/c.fi
  the use-name in code is the LAST component (ulib.say for `import toolkit.ulib`).

usage:
  deps.py                       summary: nodes, programs, edges, cycles, fan-in top 15
  deps.py --edges               every edge "importer -> imported"
  deps.py --cycles              strongly connected components with size > 1 (import cycles)
  deps.py --closure taskbar     transitive imports of one program with line counts
  deps.py --fanin               modules ranked by number of importers
  deps.py --dot > g.dot         Graphviz graph (local modules only)
  deps.py --json                machine readable (used by layers.py)
  deps.py --funcs wlib [--min 3]  function groups (by name prefix) with line ranges of one file
  deps.py --regions wlib [--min 3] contiguous runs of same-prefix functions = responsibility regions
  deps.py --coupling            /etc, /apps ... paths that several files read/write (coupling without an import)
  deps.py --dups                same function NAME in several files (module-scoped, only a hint)
  deps.py --clones              identical function BODIES in several files (real copy/paste)
Options: --root <repo> (default: two levels above this script), --lib (include lib/ nodes).
"""
import argparse, json, os, re, sys
from collections import defaultdict, Counter

IMPORT_RE = re.compile(rb'^\s*import\s+([A-Za-z_][A-Za-z0-9_.]*)')
FN_RE = re.compile(rb'^\s*(?:export\s+|pub\s+)?(?:inline\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)')
PROFILE_RE = re.compile(rb'^profile\s+(\w+)')
USTART_RE = re.compile(rb'\bu_start\b')
STDLIB_ROOTS = {'std', 'fui', 'font', 'paint', 'plat'}   # resolved inside firnc (vendor/firn), no .fi under lib/


def walk_fi(base):
    out = []
    for dp, dn, fn in os.walk(base):
        dn[:] = [d for d in dn if not d.startswith('.')]
        for f in fn:
            fp = os.path.join(dp, f)
            if f.endswith('.fi') and not os.path.islink(fp):   # flat compat symlinks are views, not files
                out.append(fp)
    return sorted(out)


class Graph:
    def __init__(self, root, with_lib=False):
        self.root = root
        self.usr = os.path.join(root, 'kernel', 'user')
        self.lib = os.path.join(root, 'lib')
        self.nodes = {}      # id -> dict(path, lines, kind, profile)
        self.edges = defaultdict(list)   # id -> [ids]
        self.unresolved = defaultdict(list)
        self.stdlib = defaultdict(list)   # imports of the Firn stdlib shipped inside firnc
        files = walk_fi(self.usr)
        if with_lib:
            files += walk_fi(self.lib)
        for p in files:
            self._load(p)
        # flat name -> path, for `import wlib` when the file lives in kernel/user/<layer>/wlib.fi
        self.flat = {}
        for p in files:
            if p.startswith(self.usr + os.sep):
                self.flat.setdefault(os.path.basename(p)[:-3], p)
        for nid, n in list(self.nodes.items()):
            self._resolve(nid, n)

    def ident(self, path):
        rel = os.path.relpath(path, self.root)
        if rel.startswith('kernel/user/'):
            rel = rel[len('kernel/user/'):]
            return rel[:-3]   # flat: 'wlib'; layered: 'toolkit/wlib'
        if rel.startswith('lib/'):
            return 'lib:' + rel[4:-3]
        return rel

    def _load(self, path):
        with open(path, 'rb') as f:
            data = f.read()
        lines = data.split(b'\n')
        imps, fns, prof, ustart = [], [], None, False
        for i, ln in enumerate(lines, 1):
            s = ln.lstrip()
            if s.startswith(b'//'):
                continue
            m = IMPORT_RE.match(ln)
            if m:
                imps.append((m.group(1).decode(), i))
                continue
            m = FN_RE.match(ln)
            if m:
                fns.append((m.group(1).decode(), i))
            m = PROFILE_RE.match(ln)
            if m and prof is None:
                prof = m.group(1).decode()
            if b'u_start' in ln and b'fn u_start' in ln:
                ustart = True
        bodies = []   # (name, start, end, normalized-body hash) for top-level fns
        import hashlib
        for name, st in fns:
            if lines[st - 1][:1] in (b' ', b'\t'):
                continue   # nested / indented, not a top-level function
            en = st
            while en < len(lines) and lines[en - 1].rstrip() != b'}':
                en += 1
            body = [re.sub(rb'\s+', b' ', l.split(b'//')[0]).strip() for l in lines[st:en]]
            body = [l for l in body if l]
            if len(body) >= 4 and name != 'u_start':
                h = hashlib.sha1(b'\n'.join(body)).hexdigest()[:10]
                bodies.append((name, st, en, h, len(body)))
        top = {st for _, st in fns if lines[st - 1][:1] not in (b' ', b'\t')}
        nid = self.ident(path)
        self.nodes[nid] = dict(path=path, lines=len(lines), profile=prof,
                               program=ustart, imports=imps, funcs=fns, bodies=bodies, top=top)

    def _resolve(self, nid, n):
        d = os.path.dirname(n['path'])
        for mod, ln in n['imports']:
            rel = mod.replace('.', '/') + '.fi'
            hit = None
            for base in (d, self.lib):   # importer dir first, then FIRNLIB (= lib/)
                p = os.path.join(base, rel)
                if os.path.isfile(p):
                    hit = p
                    break
            if hit is None and mod in self.flat:
                hit = self.flat[mod]   # layered tree: flat compat symlinks make `import wlib` work from any layer
            if hit is None and os.path.isfile(os.path.join(self.usr, rel)):
                hit = os.path.join(self.usr, rel)
            if hit is None:
                if mod.split('.')[0] in STDLIB_ROOTS:   # embedded in firnc, not a file here
                    self.stdlib[nid].append(mod)
                else:
                    self.unresolved[nid].append((mod, ln))
                continue
            tid = self.ident(hit)
            if tid not in self.nodes:
                # lib module not scanned (no --lib): keep as leaf marker
                self.nodes[tid] = dict(path=hit, lines=sum(1 for _ in open(hit, 'rb')),
                                       profile=None, program=False, imports=[], funcs=[],
                                       leaf=True)
            self.edges[nid].append(tid)

    def sccs(self):
        """Tarjan, iterative."""
        index, low, onstack, stack, out = {}, {}, set(), [], []
        counter = [0]
        for root in self.nodes:
            if root in index:
                continue
            work = [(root, iter(self.edges.get(root, [])))]
            index[root] = low[root] = counter[0]; counter[0] += 1
            stack.append(root); onstack.add(root)
            while work:
                v, it = work[-1]
                adv = False
                for w in it:
                    if w not in index:
                        index[w] = low[w] = counter[0]; counter[0] += 1
                        stack.append(w); onstack.add(w)
                        work.append((w, iter(self.edges.get(w, []))))
                        adv = True
                        break
                    elif w in onstack:
                        low[v] = min(low[v], index[w])
                if adv:
                    continue
                work.pop()
                if work:
                    low[work[-1][0]] = min(low[work[-1][0]], low[v])
                if low[v] == index[v]:
                    comp = []
                    while True:
                        w = stack.pop(); onstack.discard(w); comp.append(w)
                        if w == v:
                            break
                    if len(comp) > 1 or v in self.edges.get(v, []):
                        out.append(sorted(comp))
        return out

    def closure(self, start):
        seen, todo = set(), [start]
        while todo:
            v = todo.pop()
            if v in seen:
                continue
            seen.add(v)
            todo.extend(self.edges.get(v, []))
        return seen

    def fanin(self):
        c = defaultdict(list)
        for a, bs in self.edges.items():
            for b in set(bs):
                c[b].append(a)
        return c


def n_toplevel(n, ln):
    return ln in n.get('top', set())


def func_groups(node, minn):
    groups = defaultdict(list)
    fns = node['funcs']
    for name, ln in fns:
        key = name.split('_')[0] if '_' in name.strip('_') else name
        groups[key].append((name, ln))
    rows = []
    for k, v in groups.items():
        if len(v) >= minn:
            rows.append((min(l for _, l in v), max(l for _, l in v), k, len(v)))
    rows.sort()
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default=os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
    ap.add_argument('--lib', action='store_true')
    ap.add_argument('--edges', action='store_true')
    ap.add_argument('--cycles', action='store_true')
    ap.add_argument('--fanin', action='store_true')
    ap.add_argument('--dot', action='store_true')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--dups', action='store_true')
    ap.add_argument('--clones', action='store_true')
    ap.add_argument('--coupling', action='store_true')
    ap.add_argument('--regions')
    ap.add_argument('--closure')
    ap.add_argument('--funcs')
    ap.add_argument('--min', type=int, default=3)
    a = ap.parse_args()
    g = Graph(a.root, a.lib)
    local = {k: v for k, v in g.nodes.items() if not k.startswith('lib:')}

    if a.json:
        print(json.dumps(dict(
            nodes={k: dict(lines=v['lines'], profile=v['profile'], program=v['program'])
                   for k, v in g.nodes.items()},
            edges={k: sorted(set(v)) for k, v in g.edges.items()},
            unresolved=g.unresolved), indent=1))
        return
    if a.edges:
        for k in sorted(g.edges):
            for t in sorted(set(g.edges[k])):
                print(f'{k} -> {t}')
        return
    if a.dot:
        print('digraph deps {\n rankdir=LR; node [shape=box,fontsize=9];')
        for k, bs in sorted(g.edges.items()):
            for t in sorted(set(bs)):
                if not t.startswith('lib:'):
                    print(f' "{k}" -> "{t}";')
        print('}')
        return
    if a.cycles:
        cs = g.sccs()
        print(f'{len(cs)} import cycle group(s)')
        for c in cs:
            print('  ' + ' <-> '.join(c))
        return
    if a.fanin:
        fi = g.fanin()
        for k, v in sorted(fi.items(), key=lambda kv: -len(set(kv[1]))):
            print(f'{len(set(v)):4d}  {k}  ({g.nodes[k]["lines"]} lines)')
        return
    if a.closure:
        if a.closure not in g.nodes:
            sys.exit(f'unknown module {a.closure}')
        cl = sorted(g.closure(a.closure), key=lambda x: -g.nodes[x]['lines'])
        tot = sum(g.nodes[x]['lines'] for x in cl)
        for x in cl:
            print(f'{g.nodes[x]["lines"]:7d}  {x}')
        print(f'{tot:7d}  TOTAL ({len(cl)} modules)')
        return
    if a.funcs:
        n = g.nodes.get(a.funcs)
        if not n:
            sys.exit(f'unknown module {a.funcs}')
        print(f'{a.funcs}: {n["lines"]} lines, {len(n["funcs"])} functions')
        for lo, hi, k, c in func_groups(n, a.min):
            print(f'  L{lo:6d}-{hi:6d}  {k:<18s} {c:4d} fn')
        return
    if a.coupling:
        # coupling that is NOT an import: files/paths several programs read or write (/etc/*.conf, /apps/*)
        pat = re.compile(rb'"(/(?:etc|apps|var|run|tmp|system)/[A-Za-z0-9_./-]+)')
        users = defaultdict(set)
        for k, v in local.items():
            with open(v['path'], 'rb') as f:
                for m in pat.finditer(f.read()):
                    users[m.group(1).decode().rstrip('/')].add(k)
        rows = sorted(((len(u), p_, sorted(u)) for p_, u in users.items() if len(u) >= 2), reverse=True)
        for n, p_, u in rows[:60]:
            print(f'{n:3d}  {p_:<34s} {" ".join(u[:10])}{" ..." if n > 10 else ""}')
        print(f'-- {len(rows)} paths used by >= 2 files')
        return
    if a.regions:
        n = g.nodes.get(a.regions)
        if not n:
            sys.exit(f'unknown module {a.regions}')
        # contiguous runs of top-level functions sharing a name prefix = regions of one responsibility
        fns = [(nm, ln) for nm, ln in n['funcs'] if n_toplevel(n, ln)]
        runs = []
        for nm, ln in fns:
            key = nm.strip('_').split('_')[0]
            if runs and runs[-1][0] == key:
                runs[-1][2] = ln; runs[-1][3] += 1; runs[-1][4][key] += 1
            else:
                runs.append([key, ln, ln, 1, Counter({key: 1})])
        # merge tiny runs into the neighbour so the list stays readable
        merged = []
        pending = None   # leading tiny runs wait for the first real region
        for r in runs:
            if r[3] < a.min:
                if merged:
                    merged[-1][2] = r[2]; merged[-1][3] += r[3]; merged[-1][4].update(r[4])
                elif pending:
                    pending[2] = r[2]; pending[3] += r[3]; pending[0] = 'misc'; pending[4].update(r[4])
                else:
                    pending = list(r); pending[4] = Counter(r[4])
            else:
                if pending and not merged:
                    merged.append(pending)
                    pending = None
                if merged and merged[-1][0] == r[0]:
                    merged[-1][2] = r[2]; merged[-1][3] += r[3]; merged[-1][4].update(r[4])
                else:
                    merged.append(r)
        if pending and not merged:
            merged.append(pending)
        print(f'{a.regions}: {n["lines"]} lines; regions (run of >= {a.min} fns with one prefix, tiny runs folded into the previous):')
        for key, lo, hi, c, cnt in merged:
            top = ' '.join(f'{k}*{v}' for k, v in cnt.most_common(6))
            print(f'  L{lo:6d}-{hi:6d}  {c:3d} fn  {top}')
        return
    if a.clones:
        byh = defaultdict(list)
        for k, v in local.items():
            for name, st, en, h, n in v.get('bodies', []):
                byh[h].append((k, name, st, n))
        rows = [(n_ * len(set(k for k, *_ in v)), h, v) for h, v in byh.items()
                for n_ in [v[0][3]] if len(set(k for k, *_ in v)) > 1]
        rows.sort(key=lambda r: -r[0])
        tot = 0
        for score, h, v in rows:
            tot += v[0][3] * (len(v) - 1)
            print(f'{v[0][3]:4d} body lines x {len(v)} copies: ' +
                  ', '.join(f'{k}:{name}@{st}' for k, name, st, n in v))
        print(f'-- {len(rows)} cloned function bodies (>=4 normalized lines), ~{tot} redundant lines')
        return
    if a.dups:
        seen = defaultdict(list)
        for k, v in local.items():
            for name, ln in v['funcs']:
                seen[name].append(k)
        n = 0
        for name, ks in sorted(seen.items()):
            ks = sorted(set(ks))
            if len(ks) > 1 and len(name) > 5 and name != 'u_start':
                n += 1
                print(f'{name}: {", ".join(ks)}')
        print(f'-- {n} function names defined in more than one file')
        return

    progs = [k for k, v in local.items() if v['program']]
    cs = g.sccs()
    print(f'files in kernel/user: {len(local)}  programs(u_start): {len(progs)}  '
          f'lines: {sum(v["lines"] for v in local.values())}')
    print(f'edges: {sum(len(set(v)) for v in g.edges.values())}  '
          f'unresolved imports: {sum(len(v) for v in g.unresolved.values())}')
    for k, v in g.unresolved.items():
        for m, ln in v[:3]:
            print(f'  unresolved {k}:{ln} import {m}')
    sl = defaultdict(int)
    for v in g.stdlib.values():
        for m in v:
            sl[m] += 1
    print('firn stdlib imports (inside firnc): ' + ', '.join(f'{m}x{c}' for m, c in sorted(sl.items(), key=lambda kv: -kv[1])))
    print(f'import cycles: {len(cs)}')
    for c in cs:
        print('  ' + ' <-> '.join(c))
    print('top fan-in (local modules):')
    fi = g.fanin()
    for k, v in sorted(fi.items(), key=lambda kv: -len(set(kv[1])))[:15]:
        print(f'  {len(set(v)):4d}  {k}')
    print('biggest files:')
    for k, v in sorted(local.items(), key=lambda kv: -kv[1]['lines'])[:10]:
        print(f'  {v["lines"]:6d}  {k}  ({len(v["funcs"])} fn, {len(set(g.edges.get(k, [])))} imports)')


if __name__ == '__main__':
    main()
