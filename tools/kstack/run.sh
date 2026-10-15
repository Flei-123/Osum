#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/kstack/run.sh -- r837 gate: the kernel stack never overflows while the desktop works.
#
#   /root/jarvis/bin/heavy bash tools/kstack/run.sh [outdir]
#
# 1. Audit machine (KVM, modern theme, default drehbuch: Esc, Start, File Explorer, Settings, ...):
#    the serial log must NOT contain `KERNSTAPEL UEBERGELAUFEN` (sched.guard_check, one line per broken guard word).
# 2. Static bound: the deepest call path below sys.dispatch / syscall_entry (tools/kstack/depth.py) must stay under
#    KSTACK_FRAMES * 4096 minus 16 KiB (room for an interrupt on top).
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d /tmp/kstack-XXXXXX); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm > "$OUT.log" 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
S="$OUT/serial.txt"
grep -aq 'launcher: ready' "$S" && ok "launcher up" || bad "launcher up"
grep -aq 'explorer: ready' "$S" && ok "start menu opened and Explorer started" || bad "start menu opened and Explorer started"
n=$(grep -ac 'KERNSTAPEL UEBERGELAUFEN' "$S")
[ "$n" = 0 ] && ok "no KERNSTAPEL UEBERGELAUFEN line" || { bad "KERNSTAPEL UEBERGELAUFEN x$n"; grep -a 'KERNSTAPEL' "$S" | head -3; }
frames=$(grep -oE '^const KSTACK_FRAMES: u64 = [0-9]+' kernel/sched/sched.fi | grep -oE '[0-9]+$')
cap=$((frames * 4096 - 16384))
for root in _F0.sys__dispatch syscall_entry; do
  d=$(python3 -I tools/kstack/depth.py "$DESIGNBUILD/k0.mb.elf" "$root" | grep -oE '[0-9]+ octets' | grep -oE '^[0-9]+')
  echo "  static depth $root = ${d:-?} (cap $cap)"
  [ -n "$d" ] && [ "$d" -le "$cap" ] && ok "static depth below $root within the stack" || bad "static depth below $root"
done
echo "kstack: $pass/$fail OK/FAIL"
[ "$fail" = 0 ]
