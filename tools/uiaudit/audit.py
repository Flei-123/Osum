import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1])
WORD_KEYS = r"k_(b_uber|settings_back|nav_back|nav_fwd|nav_up)\b"
SOURCES = [ROOT / "kernel/user/settings.fi", ROOT / "kernel/user/navview.fi"]
LOCALES = [ROOT / "locale/de/messages", ROOT / "locale/en/messages"]
DEV_TEXT = re.compile(r"RRGGBB|WCAG|\bhex\b|#[0-9A-Fa-f]{6}\b", re.I)
RAW_CHOICE = re.compile(r"^(modern|classic|osum)$", re.I)

findings = []


def scan_sources():
    for path in SOURCES:
        if not path.exists():
            continue
        for no, line in enumerate(path.read_text().splitlines(), 1):
            if re.search(r"fuiscene\.(button|button_main)\(", line) and re.search(WORD_KEYS, line):
                findings.append((path.name, no, "word button", line.strip()))
            if re.search(r"fuiscene\.(label|label_wrap|label_muted)\(.*\bl_kon\b", line):
                findings.append((path.name, no, "developer value shown (contrast ratios)", line.strip()))
            if re.search(r"fuiscene\.entry\(.*\bK_EA\b", line):
                findings.append((path.name, no, "developer value field (hex accent)", line.strip()))
            if re.search(r"fuiscene\.choice\(.*\bK_CSH\b", line):
                findings.append((path.name, no, "internal shape names in a dropdown", line.strip()))
            if re.search(r"fuiscene\.choice\(.*\bK_CM\b", line) and "fuiscene.segmented(" in path.read_text():
                findings.append((path.name, no, "colour mode shown twice", line.strip()))


def scan_locales():
    shown = set()
    text = (ROOT / "kernel/user/settings.fi").read_text() if (ROOT / "kernel/user/settings.fi").exists() else ""
    for m in re.finditer(r"fuiscene\.(label|label_muted|label_wrap|button|button_main|entry|choice)\([^\n]*msg\.get\(\(&k_(\w+)\[", text):
        shown.add(m.group(2))
    for path in LOCALES:
        if not path.exists():
            continue
        for no, line in enumerate(path.read_text().splitlines(), 1):
            if "=" not in line or not line.startswith("settings."):
                continue
            key, value = [p.strip() for p in line.split("=", 1)]
            ident = "k_" + key.replace(".", "_")
            if ident[2:] in shown and DEV_TEXT.search(value):
                findings.append((path.name, no, "developer text in UI", line))
            if any(RAW_CHOICE.match(v.strip()) for v in value.split("\\n")) and key.endswith("choices"):
                findings.append((path.name, no, "internal name as choice", line))


scan_sources()
scan_locales()
for f, no, kind, line in findings:
    print("FINDING %s:%d %s :: %s" % (f, no, kind, line[:110]))
print("RESULT findings=%d" % len(findings))
sys.exit(1 if findings else 0)
