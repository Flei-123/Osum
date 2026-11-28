#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
remote_root=/tmp/hpdaily
poll_interval=10
poll_timeout=900
expect_build=""
device=HP-ORIENTOS
out_dir=$repo/reports
config=()

usage() {
    echo "usage: HPD_TRANSPORT=<script> run.sh [--expect-build N] [--device NAME] [--gpu-words] [--require-wlan] [--input-window S] [--poll-timeout S] [--out-dir DIR]" >&2
    echo "transport script commands: put <local> <remote> | exec <command...> | get <remote>" >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --expect-build) expect_build=$2; shift 2 ;;
        --device) device=$2; shift 2 ;;
        --gpu-words) config+=("GPU_WORDS_WANTED=1"); shift ;;
        --require-wlan) config+=("DL_REQUIRE_WLAN=1"); shift ;;
        --input-window) config+=("INPUT_WINDOW_S=$2"); shift 2 ;;
        --poll-timeout) poll_timeout=$2; shift 2 ;;
        --out-dir) out_dir=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "${HPD_TRANSPORT:-}" ] || usage

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
transport() { "$HPD_TRANSPORT" "$@"; }

bash "$here/bundle.sh" "$work/hpdaily.sh"
printf 'export %s\n' "${config[@]:-HPD_NOOP=1}" > "$work/config.sh"
transport exec /bin/busybox mkdir -p "$remote_root"
transport put "$work/hpdaily.sh" "$remote_root/hpdaily.sh"
transport put "$work/config.sh" "$remote_root/config.sh"
transport exec /bin/busybox sh "$remote_root/hpdaily.sh" launch

deadline=$(( $(date +%s) + poll_timeout ))
while :; do
    state=$(transport exec /bin/busybox cat "$remote_root/run/phase" 2>/dev/null || true)
    echo "phase: ${state:-?}" >&2
    [ "${state//[$'\r\n ']/}" = done ] && break
    [ "$(date +%s)" -lt "$deadline" ] || { echo "poll timeout" >&2; break; }
    sleep "$poll_interval"
done

transport get "$remote_root/run/result.kv" > "$work/result.kv"
args=("$work/result.kv" --out-dir "$out_dir" --device "$device")
[ -z "$expect_build" ] || args+=(--expect-build "$expect_build")
PYTHONPATH="$here" python3 "$here/render.py" "${args[@]}"
