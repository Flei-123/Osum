#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kv=${1:?result.kv path or -}
shift
cd "$here"
exec python3 render.py "$kv" "$@"
