#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

VALUE_PATTERN_MOD = 1000003


def pattern_sum(n):
    total = 0
    for i in range(n):
        total = (total * 31 + 97 + (i % 26)) % VALUE_PATTERN_MOD
    return total


def sections(text):
    out = {}
    current = None
    for line in text.splitlines():
        marker = re.search(r"^MARK-([a-z]+)\s*$", line.strip())
        if marker:
            current = marker.group(1)
            out[current] = []
            continue
        if current is not None:
            out[current].append(line.rstrip())
    return out


def proof_lines(lines):
    return [m.group(0) for m in (re.search(r"svcproof: .*", x) for x in lines) if m]


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def check_store(lines):
    rows = proof_lines(lines)
    ls_lines = [x.strip() for x in lines if "svcproof:" not in x and x.strip()]
    expected = [
        ("set_new", "svcproof: set status=ok"),
        ("has_after_set", "svcproof: has has=1"),
        ("get_after_set", "svcproof: get status=ok len=5 val=hello"),
        ("overwrite", "svcproof: set status=ok"),
        ("get_after_overwrite", "svcproof: get status=ok len=6 val=second"),
    ]
    for index, (name, want) in enumerate(expected):
        got = rows[index] if index < len(rows) else ""
        verdict(name, got.strip() == want, got)
    rest = rows[len(expected):]
    first_ls = ls_lines[0].split() if ls_lines else []
    last_ls = ls_lines[-1].split() if len(ls_lines) > 1 else []
    verdict("ls_shows_only_key", first_ls == ["./", "../", "greeting"], " ".join(first_ls))
    verdict("ls_empty_after_remove", last_ls == ["./", "../"], " ".join(last_ls))
    wanted_rest = [
        ("other_app_set", "svcproof: set status=ok"),
        ("other_app_get", "svcproof: get status=ok len=7 val=foreign"),
        ("isolation_first_app_intact", "svcproof: get status=ok len=6 val=second"),
        ("gen_max_value", "svcproof: gen status=ok len=65536"),
        ("sum_max_value", "svcproof: sum status=ok len=65536 sum=%d" % pattern_sum(65536)),
        ("value_over_limit_rejected", "svcproof: gen status=invalid len=65537"),
        ("over_limit_not_stored", "svcproof: has has=0"),
        ("key_with_slash_rejected", "svcproof: set status=invalid"),
        ("app_dotdot_rejected", "svcproof: set status=invalid"),
        ("key_dotdot_stored_as_plain_name_or_rejected", None),
        ("get_missing", "svcproof: get status=not-found"),
        ("remove", "svcproof: rm status=ok"),
        ("has_after_remove", "svcproof: has has=0"),
        ("get_after_remove", "svcproof: get status=not-found"),
        ("remove_missing_is_ok", "svcproof: rm status=ok"),
    ]
    for index, (name, want) in enumerate(wanted_rest):
        got = rest[index].strip() if index < len(rest) else ""
        if want is None:
            verdict(name, got in ("svcproof: set status=invalid", "svcproof: set status=ok"), got)
        else:
            verdict(name, got == want, got)


def check_clip(lines):
    rows = proof_lines(lines)
    text = "\n".join(rows)
    verdict("copy_ok", len(rows) > 0 and rows[0].strip() == "svcproof: copy status=ok", rows[0] if rows else "")
    first = re.search(r"svcproof: paste status=ok pending=1 id=(\d+) op=3 status=ok val=clipboardtext", text)
    verdict("paste_round_trip", first is not None, text[:200].replace("\n", " | "))
    second = re.search(r"svcproof: paste status=ok pending=1 id=(\d+) op=3 status=ok val=second-value", text)
    verdict("paste_follows_latest_copy", second is not None, text[-200:].replace("\n", " | "))


def main():
    data = open(sys.argv[1], errors="replace").read()
    parts = sections(data)
    verdict("markers_present", all(k in parts for k in ("caps", "store", "clip", "end")), " ".join(parts))
    caps_rows = proof_lines(parts.get("caps", []))
    caps = re.search(r"caps=(\d+)", caps_rows[0]) if caps_rows else None
    value = int(caps.group(1)) if caps else -1
    verdict("caps_storage_async", value >= 0 and (value & 96) == 96, str(value))
    verdict("caps_clipboard", value >= 0 and (value & 12) == 12, str(value))
    verdict("caps_no_dialog_without_dialogd", value >= 0 and (value & 16) == 0, str(value))
    check_store(parts.get("store", []))
    check_clip(parts.get("clip", []))


main()
