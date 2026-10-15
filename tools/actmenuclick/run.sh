#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/actmenuclick/run.sh -- gate entry of the Explorer "Actions" sub menu click test (tools/actmenu/click.sh).
exec bash "$(dirname "$0")/../actmenu/click.sh" "$@"
