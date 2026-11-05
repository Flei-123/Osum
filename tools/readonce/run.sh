#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
FAIL=0
if python3 -I tools/readonce/scan.py > /tmp/readonce.$$ 2>&1; then
    echo "  OK    no unreviewed single reads of large or unbounded files"
else
    FAIL=1
    sed 's/^/  /' /tmp/readonce.$$
    echo "  FAIL  single reads found"
fi
rm -f /tmp/readonce.$$
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/kernel/user" "$D/tools/readonce" "$D/lib"
cp tools/readonce/scan.py "$D/tools/readonce/"
cat > "$D/kernel/user/probe.fi" <<'FI'
fn load(fd: u64, buf: u64) -> u64 {
    let n: u64 = io.read(fd, buf, 8191)
    return n
}
FI
if (cd "$D" && python3 -I tools/readonce/scan.py > /dev/null 2>&1); then
    echo "  FAIL  control: planted single read not detected"; FAIL=1
else
    echo "  OK    control: planted single read detected"
fi
exit "$FAIL"
