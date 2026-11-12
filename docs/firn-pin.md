Firn toolchain pin 0.1.5016 (83ecdc9ff169eba5cb3d18643ef11b0d4d552c51), shared by Osum, Certus, fUi and FirnChat; bump all four only with Firn `tools/pin/bump.sh` (policy: Firn `docs/PIN-POLICY.md`).

Scripts source `tools/lib/firnenv.sh`: it reads `firn.toolchain` (override: `FIRN_VERSION`), sets `FIRNC`, `FIRNC1`, `FIRN_STD`, `FIRN_TOOLCHAIN`, `FIRNLIB=$ROOT/lib` (Osum first, toolchain `lib` as fallback). Missing version: `firn install <version>`.
`lib/` files that differ from the toolchain are listed in `tools/firnpin/shadows.txt`; `bash tools/firnpin/check.sh` fails on unlisted shadows, duplicates and stale entries. Refresh `vendor/net/BLOBS` on every pin bump.
