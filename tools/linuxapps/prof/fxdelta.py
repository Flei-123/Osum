import sys, collections

path = sys.argv[1]
first_run = int(sys.argv[2]) if len(sys.argv) > 2 else 2
start_phase = sys.argv[3] if len(sys.argv) > 3 else "begin"
end_phase = sys.argv[4] if len(sys.argv) > 4 else "png"
only = sys.argv[5:] 

snaps = collections.defaultdict(dict)
for line in open(path, errors="replace"):
    parts = line.split()
    if len(parts) < 5 or parts[0] != "FX19":
        continue
    try:
        run, phase, key, value = int(parts[1]), parts[2], parts[3], int(parts[4])
    except ValueError:
        continue
    snaps[(run, phase)][key] = value

runs = sorted({r for r, p in snaps if p == start_phase and (r, end_phase) in snaps and r >= first_run})
totals = collections.Counter()
for run in runs:
    a, b = snaps[(run, start_phase)], snaps[(run, end_phase)]
    for key in b:
        if key in a:
            totals[key] += b[key] - a[key]

print("runs", runs, "window", start_phase, "->", end_phase, "(mean per run)")
for key in sorted(totals):
    value = totals[key] / max(len(runs), 1)
    if value == 0:
        continue
    if only and not any(key.startswith(o) for o in only):
        continue
    print("%-24s %14.1f" % (key, value))
