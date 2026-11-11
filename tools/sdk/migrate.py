# SPDX-License-Identifier: GPL-2.0-only
import re

from manifest import Report, parse_info

DEFAULT_VERSION = "1.0.0"
DEFAULT_AUTHOR = "Fleitec"
DEFAULT_LICENSE = "GPL-2.0-only"
DEFAULT_ID_PREFIX = "com.fleitec."


def missing_lines(fields, folder, kind):
    short = folder.removesuffix(".osp")
    wanted = [
        ("manifest", "2"),
        ("id", DEFAULT_ID_PREFIX + short),
        ("version", DEFAULT_VERSION),
        ("author", DEFAULT_AUTHOR),
        ("license", DEFAULT_LICENSE),
        ("kind", kind),
        ("outputs", "native"),
    ]
    lines = ["%s=%s" % (k, v) for k, v in wanted if k not in fields]
    net = fields.get("net", ("none", 0))[0]
    if net == "real" and "perm" not in fields:
        lines.append("perm=net")
    return lines


def migrate_text(text, folder, kind="gui"):
    fields = parse_info(text, Report())
    if "fassung" in fields and "revision" not in fields:
        text = re.sub(r"^fassung=", "revision=", text, count=1, flags=re.M)
    lines = missing_lines(fields, folder, kind)
    if not lines:
        return text
    return text.rstrip("\n") + "\n" + "\n".join(lines) + "\n"
