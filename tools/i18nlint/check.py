#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/i18nlint/check.py -- NO RAW I18N KEY REACHES THE SCREEN (W-D, 17.10.2026).
#
#   python3 -I tools/i18nlint/check.py [<tree-root>]
#
# Boss found 'tray.mute', 'tray.more', 'tray.none' printed raw in the tray popup: the keys
# were used in kernel/user/traypop.fi but never added to locale/*/messages. This lint scans
# every Firn source for NUL-terminated string literals that look like a message key
# ("<prefix>.<name>[.<name>]\0") whose prefix is a prefix of the tables, and requires the key
# in EVERY language table. Also: every language table has the same keys as the others.
import os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
root = os.path.abspath(root)

tables = {}
for lang in sorted(os.listdir(os.path.join(root, "locale"))):
    p = os.path.join(root, "locale", lang, "messages")
    if not os.path.isfile(p):
        continue
    keys = set()
    for ln in open(p, encoding="utf-8", errors="replace"):
        if ln.startswith("#") or "=" not in ln:
            continue
        keys.add(ln.split("=", 1)[0].strip())
    tables[lang] = keys

prefixes = set()
for ks in tables.values():
    for k in ks:
        if "." in k:
            prefixes.add(k.split(".", 1)[0])

allow = set()
for ln in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "allow.txt")):
    if ln.strip() and not ln.startswith("#"):
        allow.add(ln.strip())
# "@<prefix>" lines: prefixes that are ALWAYS checked, even when no table has such a key yet
extra_prefixes = set(a[1:] for a in allow if a.startswith("@"))
allow = set(a for a in allow if not a.startswith("@"))

prefixes |= extra_prefixes
lit = re.compile(r'"([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)\\0')
used = {}
for base in ("kernel", "lib", "module", "pkg"):
    for dp, dn, fn in os.walk(os.path.join(root, base)):
        for f in fn:
            if not f.endswith(".fi"):
                continue
            path = os.path.join(dp, f)
            txt = open(path, encoding="latin1").read()
            for m in lit.finditer(txt):
                key = m.group(1)
                if key.split(".", 1)[0] in prefixes and key not in allow:
                    used.setdefault(key, path[len(root) + 1:])

bad = 0
for key, path in sorted(used.items()):
    miss = [l for l, ks in tables.items() if key not in ks]
    if miss:
        bad += 1
        print("FAIL  %s (%s) missing in: %s" % (key, path, ",".join(miss)))
allk = set().union(*tables.values()) if tables else set()
for l, ks in tables.items():
    for k in sorted(allk - ks):
        bad += 1
        print("FAIL  %s missing in locale/%s (present in another language)" % (k, l))

# r1015: THE CATALOGUE HAS TO FIT INTO kernel/user/msg.fi.  870 keys on 832 places made the last ~38
# keys (every tray.* one) show raw although they were in both tables.  Keys, bytes of the file, key and
# text lengths are held against the constants of msg.fi; 5 % headroom is required so the next round
# does not hit the wall in the field.
msgsrc = open(os.path.join(root, "kernel/user/msg.fi"), encoding="latin1").read()
def const(name):
    m = re.search(r"^const %s: u64 = (\d+)" % name, msgsrc, re.M)
    return int(m.group(1)) if m else 0
SLOTS, FILE_MAX, VALW, KEYW = const("SLOTS"), const("FILE_MAX"), const("VALW"), const("KEYW")
for lang in tables:
    p = os.path.join(root, "locale", lang, "messages")
    n = len(tables[lang]); size = os.path.getsize(p)
    if SLOTS and n * 100 > SLOTS * 95:
        bad += 1; print("FAIL  locale/%s has %d keys, msg.fi SLOTS=%d (need 5 %% headroom)" % (lang, n, SLOTS))
    if FILE_MAX and size * 100 > FILE_MAX * 95:
        bad += 1; print("FAIL  locale/%s is %d bytes, msg.fi FILE_MAX=%d (need 5 %% headroom)" % (lang, size, FILE_MAX))
    for ln in open(p, encoding="utf-8", errors="replace"):
        if ln.startswith("#") or "=" not in ln:
            continue
        k, v = ln.split("=", 1)
        if KEYW and len(k.strip().encode()) >= KEYW:
            bad += 1; print("FAIL  locale/%s key %s too long for KEYW=%d" % (lang, k.strip(), KEYW))
        if VALW and len(v.strip().encode()) >= VALW:
            bad += 1; print("FAIL  locale/%s text of %s too long for VALW=%d" % (lang, k.strip(), VALW))
print("i18nlint capacity: SLOTS=%d FILE_MAX=%d, keys %s" % (SLOTS, FILE_MAX, ",".join("%s=%d" % (l, len(k)) for l, k in tables.items())))
print("i18nlint: %d keys used in source, %d table keys, languages %s, %d problem(s)" % (
    len(used), len(allk), ",".join(tables), bad))
sys.exit(1 if bad else 0)
