#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Gate entry point: keyboard layouts UK/FR/ES/IT/RU (host check). See tools/hid/kbdlay.sh.
exec bash "$(dirname "$0")/../hid/kbdlay.sh" "$@"
