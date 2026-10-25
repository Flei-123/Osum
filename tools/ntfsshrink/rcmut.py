#!/usr/bin/env python3
import os, shutil, subprocess, sys

D, FIRNC = sys.argv[1], sys.argv[2]
LIB = os.path.abspath("lib")

MUTATIONS = [
    ("balloc", "first-fit needs run > len", "balloc.fi", "if run >= len {", "if run > len {", True),
    ("balloc", "set bit does not reset the run", "balloc.fi", "            } else {\n                run = 0\n            }\n            b = b + 1", "            } else {\n                run = run\n            }\n            b = b + 1", True),
    ("balloc", "full byte does not reset the run", "balloc.fi", "byte == 255 {\n            run = 0", "byte == 255 {\n            run = run", True),
    ("balloc", "run start not recorded on free byte", "balloc.fi", "            if run == 0 {\n                start = n\n            }\n            run = run + 8", "            run = run + 8", True),
    ("balloc", "limit off by one", "balloc.fi", "while b < 8 && n + b < limit {", "while b < 8 && n + b < limit + 1 {", True),
    ("balloc", "sector size wrong", "balloc.fi", "const SECTOR_BITS: u64 = 4096", "const SECTOR_BITS: u64 = 2048", True),
    ("balloc", "clear ignored", "balloc.fi", "if on { cur | m } else { cur & (255 - m) }", "cur | m", True),
    ("balloc", "set never written", "balloc.fi", "        if changed {", "        if false {", True),
    ("balloc", "count ignores byte bits", "balloc.fi", "total = total + popcount8(byte)", "total = total + (byte & 1)", True),
    ("balloc", "range_is ignores want", "balloc.fi", "let want: u64 = if on { len } else { 0 }", "let want: u64 = 0", True),
    ("mpatch", "next delta against old base", "mpatch.fi", "emit_run(d + w, nstart, lb_n, nlcn, new_lcn)", "emit_run(d + w, nstart, lb_n, nlcn, base_k)", True),
    ("mpatch", "gap after shorter encoding not zeroed", "mpatch.fi", "let win: u64 = if new_len > old_len { new_len } else { old_len }", "let win: u64 = new_len", True),
    ("mpatch", "slack check dropped", "mpatch.fi", "if start_k + new_len > re || win > PATCH_MAX {", "if win > PATCH_MAX {", True),
    ("mpatch", "window limit off by one", "mpatch.fi", "win > PATCH_MAX {", "win > PATCH_MAX + 1 {", True),
    ("mpatch", "negative width boundary", "mpatch.fi", "if neg && mag <= lim {", "if neg && mag < lim {", True),
    ("mpatch", "sparse target accepted", "mpatch.fi", "if it.sparse != 0 || new_lcn == 0", "if new_lcn == 0", True),
    ("mpatch", "two's complement off by one", "mpatch.fi", "(18446744073709551615 - (b - a)) + 1", "(18446744073709551615 - (b - a))", True),
    ("mpatch", "sparse runs between k and next dropped", "mpatch.fi", "bytes.copy(d + w, end_k, mid_len)\n    w = w + mid_len", "w = w + 0", True),
    ("rjournal", "crc not checked", "rjournal.fi", "if table.crc32(buf, CRC_AT) != bytes.le32(buf + CRC_AT) {", "if false {", True),
    ("rjournal", "state not validated", "rjournal.fi", "(state != ST_SESSION && state != ST_UNIT) || plen", "plen", True),
    ("rjournal", "patch length not validated", "rjournal.fi", "|| plen > mpatch.PATCH_MAX {", "{", True),
    ("rjournal", "version not checked", "rjournal.fi", "bytes.le32(buf + 8) != VERSION {", "false {", True),
    ("rjournal", "close restores the wrong sector", "rjournal.fi", "var r: u64 = vol.vread(v, 0, 1, buf)", "var r: u64 = vol.vread(v, 1, 1, buf)", True),
    ("rjournal", "patch bytes not stored", "rjournal.fi", "        bytes.copy(buf + DATA_AT, (&(*j).patch.data[0]) as u64, (*j).patch_len)\n", "", True),
    ("rjournal", "jslot not set on write", "rjournal.fi", "    if r == codes.E_OK {\n        (*v).jslot = 1\n    }", "", True),
]

n_ok = 0
for i, (mod, name, fname, old, new, _) in enumerate(MUTATIONS):
    root = os.path.join(D, "mutlib")
    shutil.rmtree(root, ignore_errors=True)
    shutil.copytree(LIB, root)
    path = os.path.join(root, "ntfsshrink", fname)
    src = open(path).read()
    if old not in src:
        print("BAD MUTATION (pattern missing):", name); sys.exit(2)
    open(path, "w").write(src.replace(old, new))
    env = dict(os.environ)
    env["RC_QUICK"] = "1" if os.environ.get("RC_QUICK") else "0"
    env["FIRNLIB"] = root
    r = subprocess.run([sys.executable, "-I", "tools/ntfsshrink/rctest.py", D, FIRNC, "mutexe", root], capture_output=True, env=env, timeout=600)
    out = (r.stdout + r.stderr).decode()
    if r.returncode == 0:
        print("NOT DETECTED: %s: %s" % (mod, name)); sys.exit(1)
    if "FAIL" not in out:
        print("MUTATION DID NOT BUILD OR CRASHED instead of failing a check: %s: %s\n%s" % (mod, name, out[:400])); sys.exit(1)
    n_ok += 1
print("%d source mutations of balloc/mpatch/rjournal, each caught by the unit test" % n_ok)
