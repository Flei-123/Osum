import re, sys
txt = open(sys.argv[1], 'rb').read().decode('latin-1')
snap = {}
for line in txt.splitlines():
    m = re.match(r'^([BPR])(\d+) (\S+)\s*[:=]?\s*(\d+)', line.strip())
    if m:
        snap.setdefault((m.group(1), int(m.group(2))), {})[m.group(3)] = int(m.group(4))
times = {}
for m in re.finditer(r'FX11 run (\d+) (begin|png|rc=\d+)[^\n]*?t=([\d.]+)', txt):
    times.setdefault(int(m.group(1)), {})[m.group(2)[:3]] = float(m.group(3))
keys = ['blk.ahci_cmds','blk.ahci_wait_cy','blk.ahci_write_cmds','blk.ahci_write_cy','blk.ahci_flush_cmds','blk.ahci_flush_cy','fslock.cycles','fslock.long']
for run in sorted(times):
    t = times[run]
    out = [f"run{run} start={t.get('png',0)-t.get('beg',0):.2f}s exit={t.get('rc=',0)-t.get('png',0):.2f}s"]
    for a, b, tag in (('B', 'P', 'load'), ('P', 'R', 'exit')):
        sa, sb = snap.get((a, run)), snap.get((b, run))
        if not sa or not sb:
            continue
        parts = []
        for k in keys:
            if k in sa and k in sb:
                d = sb[k] - sa[k]
                parts.append(f"{k.split('.',1)[1]}={d/1e6:.0f}M" if d > 10**7 else f"{k.split('.',1)[1]}={d}")
        out.append(f" {tag}: " + ' '.join(parts))
    print(' |'.join(out))
