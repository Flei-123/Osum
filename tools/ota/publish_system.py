#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ota/publish_system.py -- turn a built image dir into a signed SYSTEM feed stand.

    python3 tools/ota/publish_system.py <imgdir> <feeddir> <channel> --bund <bundle.json>
        [--count N] [--min-from N] [--notes FILE] [--name TEXT] [--bad-hash] [--bad-sig]
    python3 tools/ota/publish_system.py <imgdir> <feeddir> <channel> --key <geheim.key> ...
        [--overlay DIR] [--gz] [--bad-gz] [--bad-ovl-hash]

--key: TEST MODE. Signs with a raw Ed25519 secret key (the one tools/install/pakete.sh makes, which
the test images trust) instead of the production bundle; the VERZEICHNIS then has no key chain
(`schluesselgen 0`, like tools/ota/listing.py). Used by the gate tools/osupdate/run.sh.

<imgdir> holds the kernel `osum.mb` (and `root.img`, listed but not applied on-device
yet). Output: <feeddir>/system/<channel>/{VERZEICHNIS,VERZEICHNIS.sig,kernel-<N>.mb,
CHANGES-<N>.txt,schluessel.pub}. The VERZEICHNIS is the same signed document format
the package feed uses (OTA2: key chain + signature by the existing bundle), plus

    system   <count> <commit7> <min_from> <name>
    sysfile  <role> <sha256> <octets> <file>          role: kernel | notes | root | roots

Old clients ignore both line types. The channel directory is separate from
`aktuell/` (which veroeffentlichen.py rebuilds), so the live package feed is untouched.
--bad-hash / --bad-sig: negative-control stands (kernel hash wrong / signature broken).

SELFUPDATE stage 2 (docs/SELFUPDATE.md):
--overlay DIR   every regular file of DIR becomes a /bin overlay entry
                  sysfile <TAB> file <TAB> sha256 <TAB> octets <TAB> f<count>-<name> <TAB> <name>
                (name = letters, digits . - _ ; empty files are refused). The device fetches each file,
                checks the hash, and swaps them into /bin together with the kernel trial.
                Files in subdirectories are absolute-path entries: DIR/apps/x.osp/start -> /apps/x.osp/start
                (allowed roots: apps etc usr/share lib; at most 60 characters).
--links FILE    one `syslink <TAB> <dest> <TAB> /bin/<name>` line per line "<dest> /bin/<name>" of FILE: after
                the swap <dest> is a second name (hard link) of the new /bin file.
--gz            gzip transport (r1246): also publish <file>.gz of the kernel and of every overlay file
                  sysgz <TAB> <kernel|name> <TAB> sha256(gz) <TAB> octets(gz) <TAB> <file>.gz
                The raw files stay (stage-1 clients and the fallback); `sysfile` hashes are those of the
                UNPACKED files, so the device checks both the gz and the result.
--bad-gz        negative control: one overlay gz (or the kernel gz when there is no overlay) has a flipped
                bit INSIDE the deflate data, its sysgz hash is recomputed (so the transport check passes
                and only the gunzip CRC / format check can catch it).
--bad-ovl-hash  negative control: the first overlay file's sysfile hash is wrong.
--roots FILE    trust-root bundle (PEM): published as `sysfile roots` (+ a sysgz line with --gz). The device
                fetches + hash-checks it and hands it to `rootsctl apply`, which writes /etc/ssl/roots.pem.
--bad-roots-hash negative control: the roots sysfile hash is wrong.
"""
import gzip, hashlib, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import veroeffentlichen as vf  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import marke

PATH_OK = re.compile(r"/(apps|etc|usr/share|lib)/[A-Za-z0-9._/-]+")


def main():
    a = sys.argv[1:]
    if len(a) < 3:
        raise SystemExit(__doc__)
    img, feed, chan = a[0], a[1], a[2]
    opt = {"--bund": None, "--key": None, "--count": None, "--min-from": "0", "--notes": None,
           "--name": "", "--overlay": None, "--roots": None, "--links": None}
    flags = set()
    i = 3
    while i < len(a):
        if a[i] in opt:
            opt[a[i]] = a[i + 1]
            i += 2
        else:
            flags.add(a[i])
            i += 1
    if chan not in ("stable", "dev", "test"):
        raise SystemExit("channel must be stable|dev|test")
    if not opt["--bund"] and not opt["--key"]:
        raise SystemExit("--bund or --key missing")
    kern = os.path.join(img, "osum.mb")
    data = open(kern, "rb").read()
    m = re.search(rb"osum ([0-9a-f]{7})", data)
    if not m:
        raise SystemExit("no `osum <hash>` string in the kernel (built from git?)")
    commit = m.group(1).decode()
    count = int(opt["--count"] or subprocess.check_output(
        ["git", "-C", HERE, "rev-list", "--count", "HEAD"]).decode())
    out = os.path.join(feed, "system", chan)
    os.makedirs(out, exist_ok=True)
    kname = "kernel-%d.mb" % count
    shutil.copyfile(kern, os.path.join(out, kname))
    khash = hashlib.sha256(data).hexdigest()
    if "--bad-hash" in flags:
        khash = ("0" if khash[0] != "0" else "1") + khash[1:]
    want_gz = "--gz" in flags
    bad_gz = "--bad-gz" in flags
    gz_lines = []
    flipped = [False]

    def gz_make(key, srvname, raw, force_bad=False):
        """Write <srvname>.gz next to the raw file and add its sysgz line."""
        # mtime 0 + no name: reproducible bytes
        z = bytearray(gzip.compress(raw, 9, mtime=0))
        if force_bad and not flipped[0]:
            # flip a bit in the middle of the deflate data (header is 10 octets, trailer 8)
            at = 10 + max(1, (len(z) - 18) // 2)
            z[at] ^= 0x10
            flipped[0] = True
        open(os.path.join(out, srvname + ".gz"), "wb").write(bytes(z))
        gz_lines.append("sysgz\t%s\t%s\t%d\t%s.gz" % (key, hashlib.sha256(bytes(z)).hexdigest(),
                                                       len(z), srvname))

    ovl_dir = opt["--overlay"]
    ovl_lines = []
    ovl_files = []
    if ovl_dir:
        entries = []
        for base, dirs, names in os.walk(ovl_dir):
            dirs.sort()
            for n in sorted(names):
                rel = os.path.relpath(os.path.join(base, n), ovl_dir).replace(os.sep, "/")
                entries.append(rel if "/" not in rel else "/" + rel)
        entries.sort(key=lambda e: (e.startswith("/"), e))
        for fn in entries:
            fp = os.path.join(ovl_dir, fn.lstrip("/"))
            if fn.startswith("/"):
                if not PATH_OK.fullmatch(fn) or len(fn) > 60 or ".." in fn or "//" in fn:
                    raise SystemExit("overlay path not allowed: %r" % fn)
            elif not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9._-]{0,59}", fn):
                raise SystemExit("overlay name not allowed: %r" % fn)
            raw = open(fp, "rb").read()
            if not raw:
                raise SystemExit("overlay file is empty: %s" % fn)
            ovl_files.append((fn, raw))
    link_lines = []
    if opt["--links"]:
        for ln in open(opt["--links"]).read().splitlines():
            parts = ln.split()
            if not parts:
                continue
            if len(parts) != 2 or not PATH_OK.fullmatch(parts[0]) or len(parts[0]) > 60 \
                    or not re.fullmatch(r"/bin/[A-Za-z0-9_-][A-Za-z0-9._-]{0,50}", parts[1]):
                raise SystemExit("bad link line: %r" % ln)
            link_lines.append("syslink\t%s\t%s" % (parts[0], parts[1]))
    roots_raw = None
    if opt["--roots"]:
        roots_raw = open(opt["--roots"], "rb").read()
        if b"-----BEGIN CERTIFICATE-----" not in roots_raw:
            raise SystemExit("roots bundle holds no PEM certificate")
    notes = opt["--notes"]
    ntext = open(notes, "rb").read() if notes else (
        ("Build %d (%s)\n" % (count, commit)).encode())
    nname = "CHANGES-%d.txt" % count
    open(os.path.join(out, nname), "wb").write(ntext)
    lines = ["system\t%d\t%s\t%s\t%s" % (count, commit, opt["--min-from"],
                                          opt["--name"] or marke.PRODUKT),
             "sysfile\tkernel\t%s\t%d\t%s" % (khash, len(data), kname),
             "sysfile\tnotes\t%s\t%d\t%s" % (hashlib.sha256(ntext).hexdigest(),
                                             len(ntext), nname)]
    for i, (fn, raw) in enumerate(ovl_files):
        srv = "f%d-%s" % (count, fn.lstrip("/").replace("/", "_"))
        open(os.path.join(out, srv), "wb").write(raw)
        oh = hashlib.sha256(raw).hexdigest()
        if "--bad-ovl-hash" in flags and i == 0:
            oh = ("0" if oh[0] != "0" else "1") + oh[1:]
        lines.append("sysfile\tfile\t%s\t%d\t%s\t%s" % (oh, len(raw), srv, fn))
        if want_gz:
            gz_make(fn, srv, raw, bad_gz)
    lines.extend(link_lines)
    if roots_raw is not None:
        srv = "f%d-roots.pem" % count
        open(os.path.join(out, srv), "wb").write(roots_raw)
        rh = hashlib.sha256(roots_raw).hexdigest()
        if "--bad-roots-hash" in flags:
            rh = ("0" if rh[0] != "0" else "1") + rh[1:]
        lines.append("sysfile\troots\t%s\t%d\t%s" % (rh, len(roots_raw), srv))
        if want_gz:
            gz_make("roots", srv, roots_raw)
    if want_gz:
        gz_make("kernel", kname, data, bad_gz and not ovl_files)
    lines.extend(gz_lines)
    rimg = os.path.join(img, "root.img")
    if os.path.isfile(rimg):
        lines.append("sysfile\troot\t%s\t%d\t%s" % (vf.sha256d(rimg),
                                                    os.path.getsize(rimg), "root.img"))
    vz = os.path.join(out, "VERZEICHNIS")
    if opt["--key"]:
        import listing  # noqa: E402  (test signer, same module the package feed tests use)
        roh = ("OTA2\nfassung\t%d\nschluesselgen\t0\n" % count + "\n".join(lines) + "\n").encode("ascii")
        m = listing.load_opk()
        sk = open(opt["--key"], "rb").read()
        sig = m.ed25519_sign(sk, roh)
        if not m.ed25519_verify(m.ed25519_public(sk), roh, sig):
            raise SystemExit("own signature does not verify")
        open(vz, "wb").write(roh)
        open(vz + ".sig", "wb").write(sig)
        pub = m.ed25519_public(sk)
    else:
        b = vf.bund_lesen(opt["--bund"])
        roh = vf.verzeichnis_text(count, b["haupt"]["gen"], [dict(k) for k in b["kette"]],
                                  [], []).decode()
        roh += "\n".join(lines) + "\n"
        open(vz, "wb").write(roh.encode("ascii"))
        vf.signieren(opt["--bund"], vz, os.path.join(out, "VERZEICHNIS.sig"))
        pub = bytes.fromhex(b["haupt"]["pub"])
    if "--bad-sig" in flags:
        sg = bytearray(open(vz + ".sig", "rb").read())
        sg[0] ^= 1
        open(vz + ".sig", "wb").write(bytes(sg))
    open(os.path.join(out, "schluessel.pub"), "wb").write(pub)
    print("system stand %d (%s) -> %s  [%s]" % (count, commit, out, chan))


main()
