# Firn origin

- License: Mozilla Public License 2.0 (since 05.09.2026). Before that: MIT.
- Public repository: https://github.com/Flei-123/Firn
- Pin: `vendor/firn/COMMIT` = `04e18c93` (on `Flei-123/Firn` main).
- All former OrientOS patches are upstream in that pin. `vendor/firn/patches/` no longer exists.
- Pin status, verification and patch history: `vendor/firn/UPSTREAM.md`.
- Pin check: `tools/firnpin/check.sh` (and `tools/firnpin/check.sh origin/main` for a candidate pin).
- Changing the pin: set `vendor/firn/COMMIT`, run `bash vendor/firn/fetch-firnc.sh`, then run the selfhost and k15 gates.
- MPL-2.0 is compatible with this GPL project. Modified Firn files must stay open under MPL-2.0.
- Toolchain: `firn.toolchain` (repo root) = `firn 0.1.4898`, the release built from the pinned commit. `vendor/firn/COMMIT` stays the source of truth; `fetch-firnc.sh` uses an installed toolchain whose COMMIT equals the pin and falls back to the source build (`OSUM_FIRN_TOOLCHAIN=0` forces it).
