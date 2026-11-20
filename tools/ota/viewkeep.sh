#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

probe() {
    local script=$1 root=$2
    python3 -I - "$script" "$root" <<'PYEOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("publish", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
root = sys.argv[2]
aus = os.path.join(root, "osum")
os.makedirs(os.path.join(aus, "v", "7"), exist_ok=True)
open(os.path.join(aus, "v", "7", "INDEX"), "w").write("x")
reg = {"vergeben": [7]}
mod.current_set(aus, reg, [])
mod.current_set(aus, reg, [])
ak = os.path.join(aus, "aktuell")
good = all(os.path.isfile(os.path.join(ak, n)) and open(os.path.join(ak, n), "rb").read() == open(os.path.join(root, n), "rb").read() for n in ("apps.tsv", "apps.tsv.sig") if os.path.exists(os.path.join(root, n)))
print("KEPT" if good and os.path.isfile(os.path.join(ak, "INDEX")) else "LOST")
PYEOF
}

mkdir -p "$D/a/osum"; printf 'view-v1' > "$D/a/apps.tsv"; printf 'sig-v1' > "$D/a/apps.tsv.sig"
[ "$(probe tools/ota/publish.py "$D/a")" = KEPT ] && ok "apps.tsv + sig survive two republishes of aktuell/" || bad "apps.tsv + sig lost after republish"
printf 'view-v2' > "$D/a/apps.tsv"
[ "$(cat "$D/a/osum/aktuell/apps.tsv")" = view-v2 ] && ok "aktuell/apps.tsv follows the catalog file" || bad "aktuell/apps.tsv is stale"
[ -L "$D/a/osum/aktuell/apps.tsv" ] && ok "view files are relative symlinks" || bad "view file is not a symlink"

mkdir -p "$D/b/osum"
[ "$(probe tools/ota/publish.py "$D/b")" = KEPT ] && [ ! -e "$D/b/osum/aktuell/apps.tsv" ] && ok "no catalog view -> no dangling link" || bad "dangling or wrong state without catalog view"

mkdir -p "$D/t/ota" "$D/t/lib"
cp tools/ota/*.py "$D/t/ota/"; cp tools/lib/*.py "$D/t/lib/" 2>/dev/null
sed -i '/link_catalog_view(aus, ak)$/d' "$D/t/ota/publish.py"
[ "$(probe "$D/t/ota/publish.py" "$D/a")" = LOST ] && ok "counter-check: old publish.py loses the view files" || bad "counter-check did not detect the old behaviour"
echo "VIEWKEEP: $pass passed, $fail failed"
[ "$fail" = 0 ]
