#!/usr/bin/env bash
# tools/english/shared_guard.sh -- the shared Firn guard (tools/english/no_german.py) next to Osum's own ratchet (run.sh).
# Same input everywhere: paths, identifiers, comments, strings; frozen counts in no-german.baseline.json,
# allow list in no-german.json. Osum's own ratchet (section 58) stays as it is, the sharper per-file one.
cd "$(dirname "$0")/../.."
exec bash "${FIRN:-/root/firn}/tools/english/no_german_ci.sh" .
