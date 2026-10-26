#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/arch/layers.py -- layer rules for kernel/user (docs/ARCHITECTURE-DESKTOP.md section 3).

REPORT ONLY by default (exit 0).  `--strict` exits 1 on any violation, `--baseline-check` exits 1 only on
violations that are not in tools/arch/layers.baseline.json (new debt), `--baseline-write` refreshes that file.

Layers (a file may import its own layer and the layers listed here; lib/ is layer `lib`):
  lib       lib/**                      imports lib only
  base      runtime + data helpers      -> lib, base          (ulib, msg, pw, sha, images, codecs, bus clients)
  cmd       CLI programs (ls, cp ...)   -> lib, base
  toolkit   window + widget stack       -> lib, base, toolkit (wlibc, wlib, fui*, winopts ...)
  services  headless daemons            -> lib, base, services
  shell     desktop, bar, start menu,   -> lib, base, toolkit, shell
            lock, login, popups
  apps      GUI applications            -> lib, base, toolkit, apps  (NEVER shell; other apps only inside the family)
  test      gate drivers, demos         -> everything
Extra rules:
  P1  a module with `fn u_start` (a program) is not imported by another file (programs are leaves)
  S1  no file above SIZE_WARN lines (report, not a violation)
Layer of a file: the first path component once files live in subfolders (kernel/user/<layer>/...), else
the table below.  Files in neither place are `unassigned` (listed, never a violation).
usage: layers.py [--root R] [--strict] [--baseline-check] [--baseline-write] [--unassigned] [--table] [--json]
"""
import argparse, json, os, sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import deps  # noqa: E402

SIZE_WARN = 4000

ALLOWED = {
    'lib': {'lib'},
    'base': {'lib', 'base'},
    'cmd': {'lib', 'base'},
    'toolkit': {'lib', 'base', 'toolkit'},
    'services': {'lib', 'base', 'services'},
    'shell': {'lib', 'base', 'toolkit', 'shell'},
    'apps': {'lib', 'base', 'toolkit', 'apps'},
    'test': {'lib', 'base', 'cmd', 'toolkit', 'services', 'shell', 'apps', 'test'},
}

def _s(x):
    return set(x.split())

# layer -> file names (without .fi) while the tree is still flat
TABLE = {
    'base': _s("""ulib msg nv pw grp sha tools nidx appdir actwire actcli act image gif jpeg pngenc flate inflate media
        unix kbund bstore jenc jsig key vault pin trash chacha dcrypt bsec aiot setschema wl_data wl_input
        wl_keytab wl_msg wlproto h264 h264tab mp3tab sync serline instaccount diskscan drvpkg drvmatch instkern dualkern
        brand_start hwid dbgio"""),
    'cmd': _s("""cat chmod chown cp cut date df diff dirname du echo env false find grep gunzip gzip head id kill ln
        locate ls mkdir mount mv passwd patch ps rm rmdir sed seq shasum shutdown reboot sleep sort su
        tail tar tee top touch tr true umount uname uniq wc wget which whoami xargs zip host ping netstat
        sh edit sysinfo eject accountcli pinctl jarvisctl fsck log privacy notify apprights backup dualcli
        firun basename lspci pcicfg regdump prphread wlanctl"""),
    'toolkit': _s("""wlibc wlib fuib fuiglyph fuiapp fuiscene fuied winopts winfloat backdrop template"""),
    'services': _s("""orientbus odbd settingsd stored social sshd wayd powerd hotkeyd wmplug dhcp sntp svc rpc rpcc
        rpcd init ota opk presence proxy dnswt fsrv fsrw fsrlim fremdfs stickwr standby power
        melder autorun diskctl drvctl dispctl ebpfctl axd bsect"""),
    'shell': _s("""desktop taskbar launcher glogin login signin lock lockclaim idlelock floatlock welcome barpop traypop
        calpop calev taskview notifc qs runbox wmd freunde tiling backlum cliphist mbg modul elevate"""),
    'apps': _s("""explorer expakt exporte fileop expdlg expmodell massren trashbin settings term termfull nedit calc
        taskmgr store mail pdfview viewer fvviewer mp3 play charmap snip notes netview powermon theme jarvismini
        install installer fas certus disks storage netmon wlan vpn"""),
    'test': _s("""k13t k14 k16 k17 shat h264t i18nt icont themetest hallo1 hallo2 hallo3 hello posix hurt wrace wspam
        wchurn stress crash burn execsmp shmtest ptytest bench compbench compdiff a11ydemo scenedemo widgetdemo
        plugboese plugpaar plugprobe plugregel plugspaet plugtempo pluguhr pollbr pollt sockt soclocal stab fftempo
        cptempo ctr ctrkill presentlog nvcheck noise ofs3 netmeter sysstub mut"""),
}
# a name can only be in one set: first listed layer wins, in this order
ORDER = ['test', 'cmd', 'toolkit', 'services', 'shell', 'apps', 'base']

# apps may import other apps only inside the same family (shared code belongs in toolkit/base)
FAMILY = {}
for fam, names in {
    'explorer': 'explorer expakt exporte fileop expdlg expmodell massren trashbin',
    'edit': 'nedit',
    'mp3': 'mp3 mp3tab play media',
}.items():
    for n in names.split():
        FAMILY[n] = fam


def layer_of(nid):
    if nid.startswith('lib:'):
        return 'lib'
    if '/' in nid:
        top = nid.split('/')[0]
        if top in ALLOWED:
            return top
    name = nid.split('/')[-1]
    for lay in ORDER:
        if name in TABLE[lay]:
            return lay
    return 'unassigned'


def run(root):
    g = deps.Graph(root)
    lay = {k: layer_of(k) for k in g.nodes}
    viol = []   # (rule, importer, imported, text)
    for a, bs in g.edges.items():
        la = lay[a]
        if la in ('unassigned',):
            continue
        for b in sorted(set(bs)):
            lb = lay[b]
            if lb == 'unassigned':
                continue
            if lb not in ALLOWED[la]:
                viol.append(('L1', a, b, f'{la} imports {lb}'))
            elif la == 'apps' and lb == 'apps' and a != b:
                fa, fb = FAMILY.get(a.split('/')[-1], a), FAMILY.get(b.split('/')[-1], b)
                if fa != fb:
                    viol.append(('A1', a, b, f'app {a} imports app {b} (move shared code to toolkit/base)'))
            if g.nodes[b].get('program') and not b.startswith('lib:'):
                viol.append(('P1', a, b, f'{b} is a program (fn u_start), not a module'))
    return g, lay, viol


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default=os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
    ap.add_argument('--strict', action='store_true')
    ap.add_argument('--baseline-check', action='store_true')
    ap.add_argument('--baseline-write', action='store_true')
    ap.add_argument('--unassigned', action='store_true')
    ap.add_argument('--table', action='store_true')
    ap.add_argument('--json', action='store_true')
    a = ap.parse_args()
    g, lay, viol = run(a.root)
    base_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'layers.baseline.json')
    keys = sorted({f'{r} {x} -> {y}' for r, x, y, _ in viol})
    if a.baseline_write:
        with open(base_path, 'w') as f:
            json.dump(keys, f, indent=0)
        print(f'wrote {len(keys)} violations to {base_path}')
        return
    if a.json:
        print(json.dumps(dict(layers=lay, violations=viol), indent=1))
        return
    local = [k for k in g.nodes if not k.startswith('lib:')]
    cnt = defaultdict(lambda: [0, 0])
    for k in local:
        cnt[lay[k]][0] += 1
        cnt[lay[k]][1] += g.nodes[k]['lines']
    if a.table:
        for l in list(ALLOWED) + ['unassigned']:
            names = sorted(k for k in local if lay[k] == l)
            print(f'{l} ({len(names)}): ' + ' '.join(names))
        return
    if a.unassigned:
        for k in sorted(k for k in local if lay[k] == 'unassigned'):
            print(k)
        return
    print('layer        files    lines')
    for l in list(ALLOWED) + ['unassigned']:
        if l in cnt:
            print(f'  {l:<10s} {cnt[l][0]:5d} {cnt[l][1]:8d}')
    by = defaultdict(list)
    for r, x, y, t in viol:
        by[r].append((x, y, t))
    print(f'violations: ' + ', '.join(f'{r}={len(v)}' for r, v in sorted(by.items())) if viol else 'violations: none')
    for r, v in sorted(by.items()):
        print(f'--- {r}')
        for x, y, t in sorted(v):
            print(f'  {x} -> {y}   [{t}]')
    big = sorted(((g.nodes[k]['lines'], k) for k in local if g.nodes[k]['lines'] > SIZE_WARN), reverse=True)
    print(f'--- S1 files above {SIZE_WARN} lines: ' + ', '.join(f'{k}({n})' for n, k in big))
    if a.baseline_check:
        old = set(json.load(open(base_path))) if os.path.exists(base_path) else set()
        new = [k for k in keys if k not in old]
        print(f'baseline: {len(old)} known, {len(new)} NEW')
        for k in new:
            print('  NEW ' + k)
        sys.exit(1 if new else 0)
    if a.strict and viol:
        sys.exit(1)


if __name__ == '__main__':
    main()
