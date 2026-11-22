#!/usr/bin/env python3
import argparse
import glob
import math
import os
import re
import shutil
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MATRIX = os.path.join(REPO, "tools", "speedcmp", "matrix.py")
SMP_CASES = (1, 4)
FIREFOX_CASES = ("https", "data")
APP_LINE = re.compile(r"AT (\S+) (\d+) ([\d.]+) ([\d.]+) rc=(\d+)")
FX_LINE = re.compile(r"FX11 run (\d+) (begin|png|rc)\S* .*?t=([\d.]+)")
FX_RC = re.compile(r"FX11 run (\d+) rc=(\d+)")
CPU_LINE = re.compile(r"CPUS proc=(\d+) osum=(?:cpus_online=(\d+))?")
MIN_COLD_RUNS = 1


class CpuMismatch(Exception):
    pass


def read_text(path):
    with open(path, errors="replace") as handle:
        return handle.read().replace("\r", "")


def check_guest_cpus(ser_path, expected, label):
    match = CPU_LINE.search(read_text(ser_path))
    if not match:
        raise CpuMismatch("%s: no CPUS line in %s" % (label, ser_path))
    seen = int(match[2]) if match[2] else int(match[1])
    if seen != expected or int(match[1]) != expected:
        raise CpuMismatch("%s: guest has %s CPUs (proc=%s), expected %d" % (label, seen, match[1], expected))


def check_matrix_cpus(mx_dir, expected):
    files = glob.glob(os.path.join(mx_dir, "*", "*-[0-9]*.cpus"))
    if not files:
        raise CpuMismatch("matrix smp%d: no .cpus files under %s" % (expected, mx_dir))
    bad = [f for f in files if read_text(f).strip() != str(expected)]
    if bad:
        raise CpuMismatch("matrix smp%d: wrong CPU count in %s" % (expected, ", ".join(bad)))
    return len(files)


def app_durations(ser_path):
    durations, codes = {}, {}
    for line in read_text(ser_path).splitlines():
        match = APP_LINE.match(line)
        if match:
            name = match[1]
            durations.setdefault(name, []).append(float(match[4]) - float(match[3]))
            codes.setdefault(name, []).append(match[5])
    return durations, codes


def app_table(work, smp):
    linux, _ = app_durations(os.path.join(work, "ap", "l-%d" % smp, "ser.txt"))
    osum, codes = app_durations(os.path.join(work, "ap", "o-%d" % smp, "ser.txt"))
    lines = ["test                linux_s   osum_s  ratio  rc"]
    for name, values in linux.items():
        if name not in osum:
            lines.append("%-18s %7.2f %8s %6s  missing" % (name, statistics.median(values), "nan", "nan"))
            continue
        lin, osm = statistics.median(values), statistics.median(osum[name])
        lines.append("%-18s %7.2f %8.2f %6.2f  %s" % (name, lin, osm, osm / lin if lin else 0.0, ",".join(codes[name])))
    return "\n".join(lines) + "\n"


def fx_times(ser_path):
    stamps, codes = {}, {}
    text = read_text(ser_path)
    for match in FX_LINE.finditer(text):
        stamps[(int(match[1]), match[2])] = float(match[3])
    for match in FX_RC.finditer(text):
        codes[int(match[1])] = int(match[2])
    walls = {n: stamps[(n, "rc")] - stamps[(n, "begin")] for n in range(1, 8) if (n, "begin") in stamps and (n, "rc") in stamps}
    pngs = {n: stamps[(n, "png")] - stamps[(n, "begin")] for n in range(1, 8) if (n, "begin") in stamps and (n, "png") in stamps}
    return walls, pngs, codes


def firefox_lines(work):
    lines, failures = [], []
    for kind in FIREFOX_CASES:
        for smp in SMP_CASES:
            for side, prefix in (("linux", "l"), ("osum", "o")):
                case = "%s%d" % (kind, smp)
                walls, pngs, codes = fx_times(os.path.join(work, "fx", "%s-%s" % (prefix, case), "ser.txt"))
                bad = sorted(n for n, rc in codes.items() if rc != 0)
                if bad:
                    failures.append("%s %s: rc != 0 in runs %s (rc %s)" % (case, side, bad, [codes[n] for n in bad]))
                warm = [n for n in walls if n > 1 and n in pngs and n not in bad]
                if not warm or 1 not in walls or 1 not in pngs or 1 in bad:
                    failures.append("%s %s: missing cold or warm runs (walls %s pngs %s)" % (case, side, sorted(walls), sorted(pngs)))
                    continue
                lines.append("%s %s warm n=%d png_med=%.2f wall_med=%.2f | cold png=%.2f wall=%.2f" % (
                    case, side, len(warm), statistics.median(pngs[n] for n in warm), statistics.median(walls[n] for n in warm), pngs[1], walls[1]))
    return lines, failures


def load_range(work):
    values = []
    for path in glob.glob(os.path.join(work, "mx", "*", "*", "load.log")):
        values += [float(line.split()[1]) for line in read_text(path).splitlines() if len(line.split()) >= 2]
    return (int(min(values)), int(math.ceil(max(values)))) if values else (0, 0)


def build_matrix(work, smp, out):
    dirs = sorted(glob.glob(os.path.join(work, "mx", "m%d" % smp, "[ab]")))
    notes = "Setup: QEMU/KVM -cpu host, %d vCPU, 1024 MiB; Osum and Linux boots run concurrently (paired); Osum words: smpfrueh nosched noproc nofs; guest CPU count verified per boot. Commit %s." % (smp, os.environ.get("BENCH_COMMIT", "?"))
    args = [sys.executable, MATRIX, "build", *dirs, "--tsv", os.path.join(out, "matrix-smp%d.tsv" % smp), "--raw", os.path.join(out, "raw%d.tsv" % smp),
            "--md", os.path.join(out, "m%d.md" % smp), "--notes", notes]
    subprocess.run(args, check=True, cwd=REPO)
    return notes


def main():
    parser = argparse.ArgumentParser(description="Assemble a benchmark raw directory from a bench-smp4real work directory")
    parser.add_argument("--work", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--date", required=True)
    parser.add_argument("--boot-from", required=True)
    args = parser.parse_args()
    os.environ["BENCH_COMMIT"] = args.commit
    problems = []
    for smp in SMP_CASES:
        try:
            check_matrix_cpus(os.path.join(args.work, "mx", "m%d" % smp), smp)
        except CpuMismatch as error:
            problems.append(str(error))
        for part in ("ap", "fx"):
            for ser in sorted(glob.glob(os.path.join(args.work, part, "*-*%d" % smp if part == "fx" else "*-%d" % smp, "ser.txt"))):
                try:
                    check_guest_cpus(ser, smp, ser)
                except CpuMismatch as error:
                    problems.append(str(error))
    if problems:
        sys.exit("CPU check failed:\n" + "\n".join(problems))
    os.makedirs(args.out, exist_ok=True)
    notes = ""
    for smp in SMP_CASES:
        notes = build_matrix(args.work, smp, args.out)
        with open(os.path.join(args.out, "apps-smp%d.txt" % smp), "w") as handle:
            handle.write(app_table(args.work, smp))
    fx_lines, failures = firefox_lines(args.work)
    with open(os.path.join(args.out, "firefox-summary.txt"), "w") as handle:
        handle.write("\n".join(fx_lines) + "\n")
    with open(os.path.join(args.out, "failures.txt"), "w") as handle:
        handle.write("\n".join(failures) + "\n")
    with open(os.path.join(args.out, "notes-smp1.txt"), "w") as handle:
        handle.write(notes + "\n")
    low, high = load_range(args.work)
    with open(os.path.join(args.out, "report.md"), "w") as handle:
        handle.write("- Gemessen auf origin/main %s (Kern Stufe 0), Serverlast %d-%d (64 Kerne). Matrix, Apps und Firefox auf %s, alle mit echtem SMP (smpfrueh bei SMP4, CPU-Zahl im Gast geprueft).\n- Datum %s\n" % (args.commit, low, high, args.commit, args.date))
    shutil.copy(os.path.join(args.boot_from, "benchfull.log"), os.path.join(args.out, "benchfull.log"))
    print("assembled %s; firefox failures: %d" % (args.out, len(failures)))


if __name__ == "__main__":
    main()
