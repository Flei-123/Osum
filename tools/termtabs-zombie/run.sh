#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# gate wrapper (gates.tsv wants tools/<gate>/run.sh): see tools/termtabs/zombie.sh
exec bash "$(dirname "$0")/../termtabs/zombie.sh" "$@"
