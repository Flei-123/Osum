#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

ANSWER_CANCEL = 0
ANSWER_OK = 1
PICKED_NAME = "zzzpick.txt"
PICKED_LEN = 13
PICKED_BODY = "note-body-123"


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin-1")
    picks = [(int(a), n, int(l)) for a, n, l in re.findall(r"(?m)^explorer: pick answer=(\d+) name=(\S*) len=(\d+)", serial)]
    note = str(picks)
    verdict("picker_answers_once_per_ask", len(picks) == 2, note)
    verdict("pick_names_file", len(picks) >= 1 and picks[0] == (ANSWER_OK, PICKED_NAME, PICKED_LEN), note)
    verdict("accept_filter_skips_bin", "zzskip.bin" not in " ".join(n for _, n, _ in picks), note)
    verdict("close_is_cancel", len(picks) >= 2 and picks[1][0] == ANSWER_CANCEL, note)
    ok = re.search(r"(?m)^pickdemo: ok status=ok", serial)
    verdict("service_status_ok", ok is not None)
    rec = re.search(r"(?m)^pickdemo: rec op=\d+ status=ok name=%s len=%d val=%s" % (PICKED_NAME, PICKED_LEN, PICKED_BODY), serial)
    verdict("queue_carries_name_and_content", rec is not None)
    cancel = re.search(r"(?m)^pickdemo: rec op=2 status=canceled", serial)
    verdict("service_status_canceled", cancel is not None)


main()
