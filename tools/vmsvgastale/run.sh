#!/usr/bin/env bash
# gate wrapper: 800x600 with a stale BYTES_PER_LINE (see tools/vmsvgaresize/stale.sh)
exec bash "$(dirname "$0")/../vmsvgaresize/stale.sh" "$@"
