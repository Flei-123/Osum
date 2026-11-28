#!/usr/bin/env python3
import datetime
import os
import subprocess
import sys

STATE = os.environ.get("GATES_LASTGREEN") or os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "osum-gates", "lastgreen.tsv")
FIELDS = ("last_green", "first_red", "date")


def load():
    state = {}
    if os.path.exists(STATE):
        for line in open(STATE, encoding="utf-8").read().splitlines():
            parts = line.split("\t")
            if len(parts) == 4:
                state[parts[0]] = dict(zip(FIELDS, parts[1:]))
    return state


def save(state):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as out:
        for gate in sorted(state):
            out.write("\t".join([gate] + [state[gate][f] for f in FIELDS]) + "\n")
    os.replace(tmp, STATE)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def record(results, commit):
    state = load()
    today = datetime.date.today().isoformat()
    for line in open(results, encoding="utf-8").read().splitlines():
        gate, _, status = line.partition("\t")
        entry = state.setdefault(gate, {"last_green": "", "first_red": "", "date": today})
        if status == "green":
            entry.update(last_green=commit, first_red="", date=today)
        elif status == "red" and not entry["first_red"]:
            entry.update(first_red=commit, date=today)
    save(state)


def preexisting(gate, base):
    entry = load().get(gate)
    if not entry or not entry["first_red"]:
        return 1
    if git("merge-base", "--is-ancestor", entry["first_red"], base).returncode != 0:
        return 1
    print(f"   PREEXISTING red: first red {entry['first_red'][:9]}, last green {entry['last_green'][:9] or 'unknown'} (not caused by this change)")
    return 0


def show(gate):
    state = load()
    for name in ([gate] if gate else sorted(state)):
        entry = state.get(name)
        if entry:
            print(f"{name}\tgreen={entry['last_green'][:9]}\tfirst_red={entry['first_red'][:9]}\t{entry['date']}")
    return 0


def field(gate, name):
    entry = load().get(gate)
    print(entry[name] if entry else "")
    return 0


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "record" and len(a) == 3:
        record(a[1], a[2])
        return 0
    if cmd == "preexisting" and len(a) == 3:
        return preexisting(a[1], a[2])
    if cmd == "show":
        return show(a[1] if len(a) > 1 else "")
    if cmd == "field" and len(a) == 3:
        return field(a[1], a[2])
    sys.exit("usage: lastgreen.py record RESULTS COMMIT | preexisting GATE BASE | show [GATE] | field GATE last_green|first_red")


if __name__ == "__main__":
    sys.exit(main())
