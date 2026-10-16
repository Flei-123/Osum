#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Gate entry for W-AX201 M2/M3 prep; the test itself lives in tools/wlan/iwlm2.sh.
exec bash "$(dirname "$0")/../wlan/iwlm2.sh" "$@"
