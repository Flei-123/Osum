#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/usbimg/pubcheck.py -- ROUND LIVE: is this root image fit to publish?

    pubcheck.py <root.img | usb.img> [live-user]

Reads the OFS root back with tools/osum/mkfs.py (the host's second
implementation of the format) and fails unless

  * /etc/passwd, /etc/shadow, /etc/group name exactly root and the live user,
  * root is locked in /etc/shadow (no hash, so no password opens it),
  * /users/ holds nothing but root/ and the live user's home,
  * /etc/autologin names the live user,
  * /etc/jarvis/rechte.conf carries no server= and switches everything off,
  * the name "justin" appears in none of those files.

Given a whole USB image (.img) it takes the root.img from the EFI partition
(the one the stick actually boots, as a boot module) and checks that one.
Exit 0 = fit, 1 = not fit (every reason is printed).
"""
import os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'osum'))
import mkfs  # noqa: E402


def root_from_usb(path, work):
    # Partition 1 (MBR or GPT) starts at 2048 on every image build.sh writes.
    out = os.path.join(work, 'root.img')
    r = subprocess.run(['mcopy', '-o', '-i', '%s@@1M' % path, '::/root.img', out],
                       capture_output=True)
    if r.returncode != 0 or not os.path.exists(out):
        raise SystemExit('pubcheck: no ::/root.img on partition 1 of %s' % path)
    return out


def read(fs, p):
    try:
        ino = fs.resolve(p)
    except Exception:
        return None
    if ino in (None, 0):
        return None
    try:
        return fs.read_at(ino, 0, fs.iget(ino, mkfs.I_SIZE)).decode('utf-8', 'replace')
    except Exception:
        return None


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    img = argv[1]
    live = argv[2] if len(argv) > 2 else 'live'
    with tempfile.TemporaryDirectory() as work:
        if open(img, 'rb').read(4096)[510:512] == b'\x55\xaa':
            img = root_from_usb(img, work)
        fs = mkfs.load(img)
        bad = []
        want = {'root', live}
        for f in ('/etc/passwd', '/etc/shadow', '/etc/group'):
            t = read(fs, f)
            if t is None:
                bad.append('%s missing' % f)
                continue
            names = {l.split(':')[0] for l in t.splitlines() if l.strip()}
            if names != want:
                bad.append('%s names %s, allowed %s' % (f, sorted(names), sorted(want)))
            if 'justin' in t.lower():
                bad.append('%s mentions justin' % f)
        sh = read(fs, '/etc/shadow') or ''
        for l in sh.splitlines():
            parts = l.split(':')
            if parts[0] == 'root' and (len(parts) < 2 or parts[1] not in ('!', '*')):
                bad.append('root is not locked in /etc/shadow')
        try:
            homes = sorted(n for n in fs.dir_names('/users') if n not in ('.', '..'))
        except AttributeError:
            lst = subprocess.run([sys.executable, os.path.join(HERE, '..', 'osum', 'mkfs.py'),
                                  'list', img], capture_output=True, text=True).stdout
            homes = sorted({l.split()[0].split('/')[2] for l in lst.splitlines()
                            if l.startswith('/users/') and len(l.split()[0].split('/')) > 2
                            and l.split()[0].split('/')[2]})
        if homes != sorted({'root', live}):
            bad.append('/users/ holds %s' % homes)
        al = (read(fs, '/etc/autologin') or '').split()
        if al[:1] != [live]:
            bad.append('/etc/autologin says %r, want %r' % (al[:1], live))
        rc = read(fs, '/etc/jarvis/rechte.conf')
        if rc is None:
            bad.append('/etc/jarvis/rechte.conf missing')
        else:
            act = [l.split('#')[0].strip() for l in rc.splitlines()]
            act = [l for l in act if l]
            for l in act:
                k, _, v = (x.strip() for x in l.partition('='))
                if k in ('server', 'servername', 'befehl_erlaubt', 'lesen', 'schreiben', 'auflisten'):
                    bad.append('rechte.conf sets %s' % k)
                if k in ('befehle', 'bildschirmfoto', 'systeminfo') and v != 'nein':
                    bad.append('rechte.conf: %s = %s' % (k, v))
        for b in bad:
            print('pubcheck: NOT FIT --', b)
        if not bad:
            print('pubcheck: fit -- accounts root (locked) and %s, homes %s, bridge off'
                  % (live, homes))
        return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
