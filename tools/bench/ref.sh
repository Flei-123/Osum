#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/ref.sh [--runs 3] [--only alpine,tinycore,debian] [--out refs.json] -- reference distros in QEMU for the OrientOS comparison table.
# Downloads over HTTPS into a private mktemp dir (removed on exit; REF_CACHE=<dir> keeps/reuses the downloads), boots each with
# tools/bench/refboot.py (KVM, 2 vCPU, 1536 MiB) and prints/merges JSON {alpine:{..},tinycore:{..},debian:{..}}.
set -uo pipefail
cd "$(dirname "$0")/../.."
RUNS=3; ONLY=alpine,tinycore,debian; OUTF=""
while [ $# -gt 0 ]; do case $1 in --runs) RUNS=$2; shift 2;; --only) ONLY=$2; shift 2;; --out) OUTF=$2; shift 2;; *) sed -n 2,5p "$0"; exit 2;; esac; done
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
C=${REF_CACHE:-$T/dl}; mkdir -p "$C"
AL=https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64
TCV=https://distro.ibiblio.org/tinycorelinux/16.x/x86_64/release/CorePure64-current.iso
DEB=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2
get() { [ -s "$C/$1" ] || curl -sSfL -m 600 -o "$C/$1" "$2" || { echo "download $2 failed" >&2; return 1; }; }
res="{}"
for k in ${ONLY//,/ }; do
    case $k in
        alpine) f=$(curl -sS -m 30 $AL/latest-releases.yaml | awk '/file: alpine-virt-/{print $2; exit}'); get "$f" "$AL/$f" || continue; art=$C/$f ;;
        tinycore) get tinycore.iso "$TCV" || continue; art=$C/tinycore.iso ;;
        debian) get debian.qcow2 "$DEB" || continue; art=$C/debian.qcow2 ;;
        *) continue ;;
    esac
    mkdir -p "$T/$k"
    echo "== $k ($RUNS runs)" >&2
    j=$(python3 -I tools/bench/refboot.py "$k" "$T/$k" "$art" "$RUNS") && res=$(python3 -I -c "import json,sys; a=json.loads(sys.argv[1]); a.update(json.loads(sys.argv[2])); print(json.dumps(a))" "$res" "$j")
    rm -rf "$T/$k"
done
echo "$res"
[ -n "$OUTF" ] && echo "$res" > "$OUTF"
