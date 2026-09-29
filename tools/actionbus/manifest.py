#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/actionbus/manifest.py -- the action manifest, checked on the HOST.
#
# The second reader of the format of docs/ACTION-BUS.md section 3 (the
# first is kernel/user/orientbus.fi). It exists for the package build --
# a manifest that the broker would refuse must not get into an .opk --
# and for everything off the device that wants the catalogue as JSON
# (the JARVIS server, a store page, documentation).
#
# Two readers of one format on purpose, the same way tools/osum/mkfs.py
# is the second writer of OFS: where they disagree, the test in
# tools/actionbus/run.sh (section 1) shows it.
#
#   manifest.py check <ACTIONS> [...]      exit 1 on the first broken file
#   manifest.py json  <ACTIONS> [...]      the catalogue as JSON on stdout
#   manifest.py check --wrapper <file>     a wrapper manifest (adapters)
#
# AB-005: `keyed` (the argument `key` names a setting of
# /etc/settings.schema; rights by <app>.<key>). AB-008: `for exe <path>`
# and `adapter cli|file|dbus|ui|keys ...`, only in wrapper manifests.
import json
import re
import sys

LEVELS = ("read", "write", "critical")
TYPES = ("string", "int", "bool")
ADAPTERS = ("cli", "file", "dbus", "ui", "keys")
RELIABILITY = {"cli": "good", "dbus": "good", "file": "medium", "ui": "medium",
               "keys": "low"}
NAME = re.compile(r"^[a-z][a-z0-9_]*(\.[a-zA-Z0-9_]+)+$")


class Bad(Exception):
    pass


def quoted(line):
    a = line.find('"')
    b = line.rfind('"')
    if a < 0 or b <= a:
        return ""
    return line[a + 1:b]


def parse(text, path="<manifest>", wrapper=False):
    """Returns (app, actions, events, warnings) or raises Bad."""
    app = None
    title = ""
    title_for = None
    actions, events = [], []
    cur = None
    warnings = []
    head = False
    for no, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        w = line.split()
        where = "%s line %d" % (path, no)
        if not head:
            if w[:2] != ["manifest", "1"]:
                raise Bad("%s: first line must be 'manifest 1'" % where)
            head = True
            continue
        k = w[0]
        if k == "app":
            if app is not None:
                raise Bad("%s: a second 'app'" % where)
            if len(w) < 2 or not 0 < len(w[1]) <= 13 or not re.match(r"^[a-z][a-z0-9_]*$", w[1]):
                raise Bad("%s: app name must be 1..13 of [a-z0-9_]" % where)
            app = w[1]
            continue
        if app is None:
            raise Bad("%s: declaration before 'app'" % where)
        if k == "title":
            title = quoted(line)
        elif k in ("action", "event"):
            if len(w) < 2 or not w[1].startswith(app + ".") or len(w[1]) <= len(app) + 1:
                raise Bad("%s: name outside the app's own namespace" % where)
            if len(w[1]) > 31 or not NAME.match(w[1]):
                raise Bad("%s: bad name '%s'" % (where, w[1]))
            pool = events if k == "event" else actions
            if any(x["name"] == w[1] for x in pool):
                raise Bad("%s: name declared twice" % where)
            if k == "action":
                if len(w) < 3 or w[2] not in LEVELS:
                    raise Bad("%s: level must be read, write or critical" % where)
                cur = {"name": w[1], "app": app, "level": w[2],
                       "description": quoted(line),
                       "needs_confirmation": w[2] == "critical",
                       "dry_run": False, "undo": None, "args": [],
                       "returns": []}
            else:
                cur = {"name": w[1], "app": app,
                       "description": quoted(line), "fields": []}
            pool.append(cur)
        elif k in ("arg", "returns", "field"):
            if cur is None:
                raise Bad("%s: '%s' outside an action" % (where, k))
            if len(w) < 3 or w[2] not in TYPES:
                raise Bad("%s: type must be string, int or bool" % where)
            if len(w[1]) > 23:
                raise Bad("%s: argument name longer than 23" % where)
            item = {"name": w[1], "type": w[2], "description": quoted(line)}
            if k == "arg":
                if "args" not in cur:
                    raise Bad("%s: an event has fields, not args" % where)
                item["required"] = len(w) > 3 and w[3] == "required"
                cur["args"].append(item)
            elif k == "returns":
                cur.setdefault("returns", []).append(item)
            else:
                cur.setdefault("fields", []).append(item)
        elif k == "keyed":
            if cur is not None and "args" in cur:
                cur["keyed"] = "settings.schema"
        elif k == "for":
            # AB-008: `for exe <path>`; AB-008b: `for window "<glob>"`
            if len(w) < 3 or w[1] not in ("exe", "window"):
                raise Bad("%s: 'for exe <path>' or 'for window \"<glob>\"'" % where)
            if w[1] == "window" and not wrapper:
                raise Bad("%s: 'for window' is for wrapper manifests" % where)
            title_for = w[2]
        elif k == "adapter":
            if len(w) < 2 or w[1] not in ADAPTERS:
                raise Bad("%s: adapter kind: cli, file, dbus, ui or keys" % where)
            if not wrapper:
                raise Bad("%s: adapters are for wrapper manifests" % where)
            if cur is not None and "args" in cur:
                cur["adapter"] = w[1]
                cur["reliability"] = RELIABILITY[w[1]]
        elif k == "dryrun":
            if cur is not None and "dry_run" in cur:
                cur["dry_run"] = True
        elif k == "undo":
            if cur is None or len(w) < 2 or not w[1].startswith(app + "."):
                raise Bad("%s: undo must name an action of the same app" % where)
            cur["undo"] = w[1]
        else:
            warnings.append("%s: unknown word '%s' (line skipped)" % (where, k))
    if app is None:
        raise Bad("%s: no 'app'" % path)
    names = {a["name"] for a in actions}
    for a in actions:
        if a["undo"] and a["undo"] not in names:
            raise Bad("%s: undo of %s names %s, which is not declared"
                      % (path, a["name"], a["undo"]))
    return {"app": app, "title": title}, actions, events, warnings


def main(argv):
    if len(argv) < 3 or argv[1] not in ("check", "json"):
        print(__doc__ if False else "usage: manifest.py check|json <ACTIONS> [...]")
        return 2
    cat = {"bus": "orient-bus", "version": 1, "actions": [], "events": []}
    rc = 0
    wrapper = "--wrapper" in argv[2:]
    for p in [a for a in argv[2:] if a != "--wrapper"]:
        try:
            app, acts, evs, warns = parse(open(p, encoding="utf-8").read(), p,
                                          wrapper)
        except (Bad, OSError) as e:
            print("FAIL %s" % e, file=sys.stderr)
            rc = 1
            continue
        for w in warns:
            print("WARN %s" % w, file=sys.stderr)
        if argv[1] == "check":
            print("OK %s app=%s actions=%d events=%d args=%d"
                  % (p, app["app"], len(acts), len(evs),
                     sum(len(a["args"]) + len(a["returns"]) for a in acts)
                     + sum(len(e["fields"]) for e in evs)))
        cat["actions"] += acts
        cat["events"] += evs
    if argv[1] == "json":
        print(json.dumps(cat, indent=1, ensure_ascii=False))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
