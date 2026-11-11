#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob
import os
import statistics
import sys

METRICS = [
    ("syscall_getpid", "getpid syscall", "ns", 1.0),
    ("syscall_lseek", "lseek syscall", "ns", 1.0),
    ("read_64b_devzero", "read 64 B /dev/zero", "ns", 1.0),
    ("write_64b_devnull", "write 64 B /dev/null", "ns", 1.0),
    ("pagefault_anon_page", "page fault anon first touch (per page)", "ns", 1.0),
    ("pagefault_filemap_page", "page fault file mmap sequential (per page)", "ns", 1.0),
    ("file_write_4mib", "file write 4 MiB (64 KiB chunks)", "ms", 1e-6),
    ("file_read_4mib_warm", "file read 4 MiB warm", "ms", 1e-6),
    ("file_read_512kib_warm", "file read 512 KiB warm", "ms", 1e-6),
    ("file_write_4mib_fsync", "file write 4 MiB + fsync", "ms", 1e-6),
    ("fork_exit_wait", "fork + exit + wait", "us", 1e-3),
    ("fork_exec_exit_wait", "fork + exec + exit + wait", "us", 1e-3),
    ("pipe_roundtrip", "pipe round trip (2 processes)", "us", 1e-3),
    ("thread_create_join", "thread create + join", "us", 1e-3),
]


def load(directory, prefix):
    runs = []
    for path in sorted(glob.glob(os.path.join(directory, prefix + "-[0-9]*.txt"))):
        values = {}
        for line in open(path, errors="replace"):
            parts = line.split()
            if len(parts) == 4 and parts[0] == "S":
                try:
                    values[parts[1]] = float(parts[2])
                except ValueError:
                    pass
        if "END" in values:
            runs.append(values)
    return runs


def median_of(runs, key):
    series = [r[key] for r in runs if key in r]
    return (statistics.median(series), len(series), min(series), max(series)) if series else None


def fmt(value):
    return "%.3g" % value if value < 1000 else "%d" % round(value)


def main():
    directory, out_md, out_tsv = sys.argv[1:4]
    notes = sys.argv[4] if len(sys.argv) > 4 else ""
    osum, linux = load(directory, "osum"), load(directory, "linux")
    rows = []
    for key, label, unit, scale in METRICS:
        o, l = median_of(osum, key), median_of(linux, key)
        factor = (o[0] / l[0]) if o and l and l[0] > 0 else None
        rows.append((key, label, unit, scale, o, l, factor))
    tsv = ["metric\tunit\tosum_median\tlinux_median\tfactor\tosum_runs\tlinux_runs\tosum_min\tosum_max\tlinux_min\tlinux_max"]
    md = ["| Metric | Osum | Linux | Factor (Osum/Linux) |", "|---|---|---|---|"]
    for key, label, unit, scale, o, l, factor in rows:
        ov = fmt(o[0] * scale) if o else "n/a"
        lv = fmt(l[0] * scale) if l else "n/a"
        fv = "%.1fx" % factor if factor else "n/a"
        md.append("| %s | %s %s | %s %s | %s |" % (label, ov, unit, lv, unit, fv))
        tsv.append("\t".join([key, unit, ov, lv, "%.2f" % factor if factor else "", str(o[1]) if o else "0", str(l[1]) if l else "0",
                              fmt(o[2] * scale) if o else "", fmt(o[3] * scale) if o else "",
                              fmt(l[2] * scale) if l else "", fmt(l[3] * scale) if l else ""]))
    ranked = sorted((r for r in rows if r[6]), key=lambda r: -r[6])[:3]
    top = ["%s (%.1fx)" % (r[1], r[6]) for r in ranked]
    with open(out_md, "w") as f:
        f.write("\n".join(md) + "\n\nRuns: Osum %d, Linux %d (median).\n" % (len(osum), len(linux)))
        f.write("Largest gaps: " + "; ".join(top) + "\n")
        if notes:
            f.write(notes + "\n")
    with open(out_tsv, "w") as f:
        f.write("\n".join(tsv) + "\n")
    print("\n".join(md))
    print("Largest gaps:", "; ".join(top))


main()
