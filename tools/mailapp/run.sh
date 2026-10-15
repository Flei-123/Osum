#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/mailapp/run.sh -- gate entry of the Mail app (see tools/mail/app.sh; stage gui is opt-in).
exec bash "$(dirname "$0")/../mail/app.sh" "$@"
