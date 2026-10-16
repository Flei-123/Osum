#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Gate wrapper: VMSVGA on the real desktop (see tools/vmsvga/desktop.sh). Needs a full stick build (~10 min) unless STICK_DIR is set.
exec bash "$(dirname "$0")/../vmsvga/desktop.sh" "$@"
