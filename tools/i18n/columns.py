#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

DEKL = re.compile(
    r'^\s*(static\s+mut\s+|static\s+|var\s+|let\s+|const\s+)'
    r'([A-Za-z_][A-Za-z_0-9]*)'
    r'\s*:\s*\[u8;\s*(\d+)\s*\]\s*=\s*"((?:\\.|[^"\\])*)"')
FN = re.compile(r'^(?:pub\s+)?fn\s+([A-Za-z_0-9]+)')

COLUMNS = [
    ("kernel/user/power.fi",
     [("show_profile", "s_p"), ("show_battery", "s_a"), ("show_battery", "s_net"),
      ("show_battery", "s_mod"), ("show_heat", "s_t")], 9,
     "/bin/power setzt Profil/Akku/Netz/Modell/Wärme untereinander"),
    ("kernel/user/vpn.fi",
     [("show", "s_peer"), ("show", "s_hs"), ("show", "s_port"),
      ("show", "s_kill"), ("show", "s_koct")], 15,
     "/bin/vpn setzt Gegenstellen/Handschläge/Port/Notaus/verworfen "
     "untereinander"),
    ("kernel/user/tiling.fi",
     [("show", "s_bl"), ("show", "s_kn"), ("show", "s_lay"),
      ("show", "s_rec"), ("show", "s_bi")], 11,
     "/bin/tiling setzt Fenster/Knoten/Aufbau/Rechteck/Tasten "
     "untereinander"),
    ("kernel/user/powermon.fi",
     [("machine", n) for n in
      ["l_now", "l_base", "l_att", "l_bat", "l_hp", "l_rt", "l_ac",
       "l_tp", "l_br"]], 15,
     "powermon setzt seine neun Messwerte untereinander"),
    ("kernel/user/netstat.fi",
     [("summary", n) for n in
      ["s_lk", "s_hi", "s_st", "s_sr", "s_ct", "s_cr"]], 20,
     "netstat setzt seine Bilanzzeilen untereinander"),
    ("kernel/fs/procfs/pfproc.fi",
     [("make_status", n) for n in
      ["l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9", "l10"]], 8,
     "/proc/<pid>/status setzt seine zehn Felder untereinander"),
]


def inhalt(roh):
    s = roh.split('\\0')[0]
    return (s.replace('\\n', '\n').replace('\\t', '\t')
             .replace('\\"', '"').replace('\\\\', '\\'))


def oktette(roh):
    n = 0
    i = 0
    while i < len(roh):
        if roh[i] == '\\':
            n += 1
            m = UNI.match(roh, i)
            if m:
                n += len(chr(int(m.group(1), 16)).encode('utf-8')) - 1
                i = m.end()
                continue
            if (i + 3 < len(roh) and roh[i + 1] == 'x'
                    and roh[i + 2] in HEX and roh[i + 3] in HEX):
                i += 4
            else:
                i += 2
        else:
            n += len(roh[i].encode('utf-8'))
            i += 1
    return n


HEX = '0123456789abcdefABCDEF'
UNI = re.compile(r'\\u\{([0-9a-fA-F]+)\}') 


def ketten(path_2):
    aus = {}
    fn = '<datei>'
    for nr, z in enumerate(open(path_2, encoding='utf-8').read().split('\n'),
                           1):
        m = FN.match(z)
        if m:
            fn = m.group(1)
        if z.lstrip().startswith('//'):
            continue
        d = DEKL.match(z.split('//')[0])
        if d:
            aus.setdefault((fn, d.group(2)), (nr, int(d.group(3)),
                                              d.group(4)))
    return aus


def all_ketten(root):
    for dp, dns, fns in os.walk(os.path.join(root, 'kernel')):
        dns[:] = [d for d in dns if not d.startswith('.')]
        for fn in sorted(fns):
            if not fn.endswith('.fi'):
                continue
            path_2 = os.path.join(dp, fn)
            rel = os.path.relpath(path_2, root).replace(os.sep, '/')
            for nr, z in enumerate(
                    open(path_2, encoding='utf-8').read().split('\n'), 1):
                if z.lstrip().startswith('//'):
                    continue
                d = DEKL.match(z.split('//')[0])
                if d:
                    yield rel, nr, d.group(2), int(d.group(3)), d.group(4)


def main(argv):
    root = os.environ.get('OSUM_ROOT', '.')
    schief = []
    geprueft = 0
    for file_2, names, width_2, wozu in COLUMNS:
        path_2 = os.path.join(root, file_2)
        if not os.path.exists(path_2):
            schief.append('%s fehlt' % file_2)
            continue
        k = ketten(path_2)
        for schl in names:
            n = schl[1]
            if schl not in k:
                schief.append('%s: die Kette %s in fn %s gibt es nicht mehr'
                              % (file_2, n, schl[0]))
                continue
            nr, N, roh = k[schl]
            t = inhalt(roh)
            geprueft += 1
            if len(t) != width_2:
                schief.append(
                    '%s:%d  %s = %r -- %d Zeichen, die Spalte ist %d '
                    '(%s)' % (file_2, nr, n, t, len(t), width_2, wozu))
    print('spalten: %d Beschriftungen in %d Spalten, %d schief'
          % (geprueft, len(COLUMNS), len(schief)))
    for z in schief:
        print('    SCHIEF  ' + z)

    eng = []
    nk = 0
    for rel, nr, name, N, roh in all_ketten(root):
        nk += 1
        b = oktette(roh)
        if b != N:
            eng.append('%s:%d  %s: das Literal ist %d Oktette, der Puffer '
                       '%d' % (rel, nr, name, b, N))
    print('buffer:  %d strings, %d do not fit' % (nk, len(eng)))
    for z in eng:
        print('    ZU ENG  ' + z)
    if schief:
        return 1
    if eng:
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
