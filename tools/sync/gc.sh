# SPDX-License-Identifier: GPL-2.0-only
# tools/sync/gc.sh -- sourced by the program builders (sync, alltag, install,
# loader, usbimg, i18n): smaller programs through section garbage collection.
#
# WHY (r278, measured 17.10.2026 with the Firn pin 031ec5a4d): `firnc -c`
# (object mode) never prunes unreachable functions -- the object might be
# linked into a C host that calls any of them by name -- so a program carries
# every function of every module it imports. With the pin bump the same
# sources came out ~50 % larger (explorer 2.47 -> 3.72 MB). With
# FIRN_FUNCTION_SECTIONS=1 every function gets its own `.text.<symbol>`
# section and `ld --gc-sections` drops what nothing references
# (explorer 3.72 -> 2.62 MB, same code, same checks).
#
#   OSUM_NO_GC=1   switch it off (bisecting, size comparisons)
#
# OPTIMISATION LEVEL (r278b): since Firn round 72 the default level is
# `dev-fast` (overflow checks on, little inlining, no dead-code removal at
# the optimiser level); the old pin compiled fully optimised and without
# overflow panics. Programs here are built with an EXPLICIT level, the
# closest match to what Osum always ran: release-fast. Measured with the pin
# 031ec5a4d, explorer: dev-fast+gc 2.62 MB, release-fast+gc 2.21 MB (old pin
# 2.47 MB), release-safe+gc 4.25 MB, dev+gc 9.99 MB.
#   OSUM_OPT=<level>   dev | dev-fast | release-safe | release-fast
#   OSUM_OPT=default   pass no level (Firn default)
#
# firnc1 (stage 1) ignores the variable; there --gc-sections finds nothing
# to drop and the result is what it always was.
if [ "${OSUM_NO_GC:-0}" = 1 ]; then
    GCS=""
else
    export FIRN_FUNCTION_SECTIONS=1
    GCS="--gc-sections"
fi
export GCS
case "${OSUM_OPT:-release-fast}" in
    default) OPTL="" ;;
    *)       OPTL="--opt-level=${OSUM_OPT:-release-fast}" ;;
esac
# r1224: the heuristic inliner nearly doubles scene-tree GUI programs (welcome 1 380 KB -> 901 KB without it, -35 %).
# Programs are built without it; hand-requested #[inline] still works. OSUM_INLINE=1 restores the old build.
[ "${OSUM_INLINE:-0}" = 1 ] || OPTL="$OPTL --no-pass=inline"
OPTL1=${OPTL/--no-pass=inline/}
export OPTL OPTL1
