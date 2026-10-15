#!/usr/bin/env python3
# tools/backlum/gen.py -- writes kernel/user/backlum.fi from the template below (the name arrays need exact lengths)
import re, sys
body = open(sys.argv[1]).read()
names = []
def sub(m):
    n = m.group(1)
    if n not in names:
        names.append(n)
    return "(&nm_%d[0 as usize]) as u64" % names.index(n)
body = re.sub(r"@([A-Za-z0-9_-]+)@", sub, body)
decl = "".join('static mut nm_%d: [u8; %d] = "%s\\0"\n' % (i, len(n) + 1, n) for i, n in enumerate(names))
sys.stdout.write(body.replace("//--NAMES--\n", decl))
