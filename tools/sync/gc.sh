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
# firnc1 (stage 1) ignores the variable; there --gc-sections finds nothing
# to drop and the result is what it always was.
if [ "${OSUM_NO_GC:-0}" = 1 ]; then
    GCS=""
else
    export FIRN_FUNCTION_SECTIONS=1
    GCS="--gc-sections"
fi
export GCS
