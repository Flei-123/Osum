#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SITE="${OSUM_SITE_REPO:-/root/projects/osum-site}"
python3 "$HERE/bench_export.py" --out "$SITE/src/data" "$@"
bash "$SITE/tools/deploy.sh"
