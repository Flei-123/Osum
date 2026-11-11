#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

ANSWER_CANCEL = 0
ANSWER_OK = 1
PICKED_NAME = "zzzpick.txt"
PICKED_LEN = 13
PICKED_BODY = "note-body-123"
SAVE_LEN = 13
BIG_LEN = 102400


def verdict(name, cond, note=""):
    print("CHECK %s %s %s" % (name, "ok" if cond else "fail", note))


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin-1")
    picks = [(int(a), n, int(l)) for a, n, l in re.findall(r"(?m)^explorer: pick answer=(\d+) name=(\S*) len=(\d+)", serial)]
    note = str(picks)
    verdict("picker_answers_once_per_ask", len(picks) == 4, note)
    verdict("pick_names_file", len(picks) >= 1 and picks[0] == (ANSWER_OK, PICKED_NAME, PICKED_LEN), note)
    verdict("accept_filter_skips_bin", "zzskip.bin" not in " ".join(n for _, n, _ in picks), note)
    verdict("close_is_cancel", len(picks) >= 2 and picks[1][0] == ANSWER_CANCEL, note)
    ok = re.search(r"(?m)^pickdemo: ok status=ok", serial)
    verdict("service_status_ok", ok is not None)
    rec = re.search(r"(?m)^pickdemo: rec op=\d+ status=ok name=%s len=%d val=%s" % (PICKED_NAME, PICKED_LEN, PICKED_BODY), serial)
    verdict("queue_carries_name_and_content", rec is not None)
    cancel = re.search(r"(?m)^pickdemo: rec op=2 status=canceled", serial)
    verdict("service_status_canceled", cancel is not None)

    saved = re.search(r"(?m)^pickdemo: rec op=1 status=ok name=zsave.txt len=0", serial)
    verdict("save_queue_carries_name", saved is not None)
    verdict("save_pick_answers_ok_with_name", len(picks) >= 3 and picks[2] == (ANSWER_OK, "zsave.txt", 0), note)
    size = re.search(r"(?m)^pickdemo: file size=(\d+)", serial)
    verdict("save_writes_staged_content", size is not None and int(size.group(1)) == SAVE_LEN, str(size and size.group(1)))
    verdict("save_window_title", "explorer: name [Save demo]" in serial)
    verdict("open_window_title", "explorer: name [Demo title]" in serial)
    big = re.search(r"(?m)^pickdemo: rec op=1 status=ok name=zzzbig.big len=(\d+)", serial)
    verdict("big_file_over_64k_picked", big is not None and int(big.group(1)) == BIG_LEN, str(big and big.group(1)))


main()
