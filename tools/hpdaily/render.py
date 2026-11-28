import argparse
import datetime
import json
import sys
from pathlib import Path

from report.common import GREEN, RED, UNKNOWN, YELLOW, Check, parse_kv, worst
from report.firefox import firefox_checks, hang_lines
from report.hardware import hardware_checks, input_checks
from report.network import network_checks
from report.system import system_checks

ICONS = {GREEN: "OK", YELLOW: "WARN", RED: "RED", UNKNOWN: "?"}


def collect_checks(data, expect_build):
    checks = system_checks(data, expect_build)[:3]
    checks += network_checks(data)
    checks += input_checks(data)
    checks += firefox_checks(data)
    checks += hardware_checks(data)
    checks += system_checks(data, expect_build)[3:]
    if data.get("done") != "1":
        checks.append(Check("complete", "Run complete", RED, "stopped in phase %s" % data.get("phase_last", "unknown")))
    return checks


def last_phase(data):
    phases = [(int(value), key[6:-6]) for key, value in data.items() if key.startswith("phase_") and key.endswith("_up_cs") and value.isdigit()]
    return max(phases)[1] if phases else "unknown"


def markdown(meta, checks, data):
    lines = ["# HP daily test %s" % meta["generated"], "", "- Overall: **%s**" % ICONS[meta["overall"]],
             "- Device: %s, expected build: %s" % (meta["device"], meta["expect_build"] or "n/a"), "",
             "| Check | Status | Detail |", "|---|---|---|"]
    for check in checks:
        lines.append("| %s | %s | %s |" % (check.title, ICONS[check.status], check.detail.replace("|", "/")))
    for label in ("example", "youtube"):
        threads = hang_lines(data, label)
        if threads and data.get("ff_%s_state" % label) != "settled":
            lines += ["", "## Firefox %s thread dump (tid state ticks runs syscall name)" % label] + ["- " + value for value in threads[:20]]
    return "\n".join(lines) + "\n"


def build_report(data, expect_build, device):
    data["phase_last"] = last_phase(data)
    checks = collect_checks(data, expect_build)
    meta = {"generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"), "device": device,
            "expect_build": expect_build, "overall": worst([check.status for check in checks])}
    return meta, checks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kv")
    parser.add_argument("--out-dir", default="reports")
    parser.add_argument("--stamp", default=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S"))
    parser.add_argument("--expect-build", type=int)
    parser.add_argument("--device", default="HP-ORIENTOS")
    args = parser.parse_args()
    data = parse_kv(Path(args.kv).read_text() if args.kv != "-" else sys.stdin.read())
    meta, checks = build_report(data, args.expect_build, args.device)
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    payload = {"meta": meta, "checks": [check.__dict__ for check in checks], "kv": data}
    (out / ("hpdaily-%s.json" % args.stamp)).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    (out / ("hpdaily-%s.md" % args.stamp)).write_text(markdown(meta, checks, data))
    print(markdown(meta, checks, data))
    return 0 if meta["overall"] != RED else 1


if __name__ == "__main__":
    sys.exit(main())
