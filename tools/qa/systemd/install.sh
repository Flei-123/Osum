#!/usr/bin/env bash
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
install -m 0644 "$SRC/osum-nightly-gates.service" "$SRC/osum-nightly-gates.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now osum-nightly-gates.timer
systemctl list-timers osum-nightly-gates.timer --no-pager
