#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Gate wrapper: the kernel panic screen reaches the VMSVGA host (see tools/vmsvga/panic.sh).
exec bash "$(dirname "$0")/../vmsvga/panic.sh" "$@"
