# Firn pin and patch upstream status

Updated 02.11.2026.

## Pin
- vendor/firn/COMMIT = 67cf92a2, on Flei-123/Firn main.
- All 12 former OrientOS patches (0001, 0002, 0005-0014) are upstream in that commit; vendor/firn/patches/ is gone.
- Renamed upstream: font_kern_cache_* became font_kerning_cache_* (no OrientOS callers).
- HERKUNFT.md describes the pre-rewrite history and is outdated regarding the hash.

## Verification
- `tools/firnpin/check.sh` (pin) and `tools/firnpin/check.sh origin/main` (pin candidate): build firnc0, build firnc1 from a temp copy with --force.
- Run under /root/jarvis/bin/heavy.
- Firn test run on the patch commit: 1451 pass / 27 fail, identical failing set to origin/main before the patches (27 pre-existing).

## Patches
- None. fetch-firnc.sh patch block is inert while patches/ is missing.
