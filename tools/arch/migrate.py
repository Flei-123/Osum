#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/arch/migrate.py -- move kernel/user/*.fi into layer folders and keep the flat names as symlinks.

  migrate.py --root R --plan            print the moves (default)
  migrate.py --root R --apply           do them (git mv when R is a git work tree, else rename) + create symlinks
  migrate.py --root R --check           verify: every layered file has its flat symlink, no dangling link, no
                                        flat REAL .fi left that the table assigns to a layer (exit 1 on problems)
  migrate.py --root R --apply --only shell,toolkit    migrate a subset of layers (staged migration)

Why symlinks: firnc resolves `import x` next to the file it compiled (the PATH it was given, symlink not
followed to its target) and then in $FIRNLIB.  Compiling `kernel/user/taskbar.fi` (a link to
`shell/taskbar.fi`) therefore finds `wlib.fi` (a link to `toolkit/wlib.fi`) exactly like before: no source
edit, no change in the ~120 gate scripts that build `kernel/user/$p.fi`.  Measured 21.10.2026
(docs/ARCHITECTURE-DESKTOP.md section 2).
"""
import argparse, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layers  # noqa: E402


def plan(root, only=None):
    usr = os.path.join(root, 'kernel', 'user')
    moves = []
    for f in sorted(os.listdir(usr)):
        p = os.path.join(usr, f)
        if not f.endswith('.fi') or os.path.islink(p) or not os.path.isfile(p):
            continue
        lay = layers.layer_of(f[:-3])
        if lay in ('unassigned', 'lib'):
            continue
        if only and lay not in only:
            continue
        moves.append((f, lay))
    return usr, moves


def in_git(root):
    return subprocess.run(['git', '-C', root, 'rev-parse', '--is-inside-work-tree'],
                          capture_output=True).returncode == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default=os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--plan', action='store_true')
    ap.add_argument('--only')
    a = ap.parse_args()
    only = set(a.only.split(',')) if a.only else None
    usr, moves = plan(a.root, only)
    if a.check:
        bad = 0
        for f in sorted(os.listdir(usr)):
            p = os.path.join(usr, f)
            if f.endswith('.fi') and os.path.islink(p) and not os.path.exists(p):
                print(f'DANGLING {f} -> {os.readlink(p)}'); bad += 1
        for f, lay in moves:
            if not only:
                print(f'NOT-MOVED {f} (belongs in {lay}/)'); bad += 1
        for lay in layers.ALLOWED:
            d = os.path.join(usr, lay)
            if os.path.isdir(d):
                for f in os.listdir(d):
                    if f.endswith('.fi') and not os.path.islink(os.path.join(usr, f)):
                        print(f'NO-FLAT-LINK {lay}/{f}'); bad += 1
        print('ok' if not bad else f'{bad} problem(s)')
        sys.exit(1 if bad else 0)
    if not a.apply:
        for f, lay in moves:
            print(f'{f} -> {lay}/{f}')
        print(f'-- {len(moves)} moves')
        return
    git = in_git(a.root)
    for f, lay in moves:
        os.makedirs(os.path.join(usr, lay), exist_ok=True)
        src, dst = os.path.join(usr, f), os.path.join(usr, lay, f)
        if git:
            subprocess.run(['git', '-C', a.root, 'mv', os.path.relpath(src, a.root), os.path.relpath(dst, a.root)],
                           check=True)
        else:
            os.rename(src, dst)
        os.symlink(os.path.join(lay, f), src)   # relative: survives `cp -a kernel/user <copy>`
        if git:
            subprocess.run(['git', '-C', a.root, 'add', os.path.relpath(src, a.root)], check=True)
    print(f'moved {len(moves)} files')


if __name__ == '__main__':
    main()
