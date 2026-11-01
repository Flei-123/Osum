#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
main=$1
dir=${main%.fi}
mods=$(for f in "$dir"/*.fi; do basename "$f" .fi; done | paste -sd'|')
cat "$main" "$dir"/*.fi | LC_ALL=C sed -E "s/(^|[^A-Za-z0-9_.])($mods)\.([A-Za-z_])/\1\3/g" | python3 -c '
import re, sys
text = sys.stdin.buffer.read().decode("latin-1")
text = re.sub(r"^fn (\w+)\([^\n]*\)(?: -> [^\n{]+)? \{\n    (?:return )?\1\([^\n]*\)\n\}\n\n?", "", text, flags=re.M)
text = re.sub(r"^const (\w+): [^=\n]+ = \1\n\n?", "", text, flags=re.M)
sys.stdout.buffer.write(text.encode("latin-1"))
'
