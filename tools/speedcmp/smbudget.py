import subprocess

from smcore import BUDGETS, TARGET, UNSUPPORTED, load_budgets, read_tsv, round_up_budget, write_tsv

MARGIN = 1.25
RED_STATUSES = ("red", "fail", "nodata", "nobudget")


def ratchet(rows, path=BUDGETS):
    old = load_budgets(path)
    out = {}
    for test, _, _, ratio, _, status in rows:
        current = old.get(test)
        if status in ("unsupported", "fail", "nodata") and current in (None, UNSUPPORTED):
            out[test] = UNSUPPORTED
            continue
        if ratio == "":
            out[test] = current if current is not None else UNSUPPORTED
            continue
        proposal = round_up_budget(float(ratio) * MARGIN)
        if current in (None, UNSUPPORTED, ""):
            out[test] = "%g" % proposal
        else:
            out[test] = "%g" % min(float(current), proposal)
    write_tsv(path, ["test", "budget"], [[t, b] for t, b in out.items()])
    return out


def raised(path=BUDGETS, ref="origin/main"):
    rel = "tools/speedcmp/budgets.tsv"
    shown = subprocess.run(["git", "show", "%s:%s" % (ref, rel)], capture_output=True, text=True)
    if shown.returncode != 0:
        return []
    base = {}
    for line in shown.stdout.splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) == 2:
            base[parts[0]] = parts[1]
    now = load_budgets(path)
    bad = []
    for test, budget in now.items():
        before = base.get(test)
        if before is None or before == UNSUPPORTED:
            continue
        if budget == UNSUPPORTED or float(budget) > float(before):
            bad.append("%s %s -> %s" % (test, before, budget))
    return bad


def verdict(rows):
    return [(r[0], r[5], r[3], r[4]) for r in rows if r[5] in RED_STATUSES]


def target_gap(rows):
    return [(r[0], float(r[3])) for r in rows if r[3] != "" and float(r[3]) > TARGET]
