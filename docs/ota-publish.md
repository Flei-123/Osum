# One-command feed publish

`bash tools/ota/publish.sh` prepares the HP dev feed (`system/dev`) and changes nothing.

- Default (dry run): checks prerequisites (signing bundle, passphrase, `HP_BASE`, clean tree, live feed key), builds and signs into a temp copy via `publish-dev.sh --dry`, verifies, then prints every file with sha256, size and the target path.
- `--apply`: runs the dry run first, then publishes with `publish-dev.sh`. Never implicit.
- `--stand DIR --pub FILE`: verify and list an existing signed stand only (used by the gate).
- Any bad signature, hash or size, or a missing prerequisite, aborts with a non-zero exit code.
- Env: `FEED_DIR` (`/srv/store/osum`), `HP_BASE`, `HP_REF`, `OSUM_BUND`, `OSUM_SIGN_PASS_FILE`.
- Gate: `tools/otapublish/run.sh` (`OTAPUBLISH: N passed, M failed`).
- After `--apply` the HP steps are printed by `publish-dev.sh`; the HP must be online to apply.

## Baseline images (HP_BASE)

- Never delete `hp-*base*` or `hp-stick*` directories under `/root/abbilder`: they are the baselines `republish-hp.sh` and `publish.sh` compare against.
- `hp-stick36-base` is the build output directory (`*.elf`, `osum.mb`, `buendel`) of `IMAGE_ID=hp-stick36 HP_STICK=1 bash tools/usbimg/build.sh <out>` at commit `89003cb4` (rebuild: detached worktree of that commit, `bash vendor/firn/fetch-firnc.sh` first).

## Device key (WARNING)

- The real HP device key (`hp-device.key`, also `justin-device.key`, `vm-device.key`) is gone from `/root/abbilder`. The only copy left is on the HP itself (`/var/jarvis`, key in `jsig`).
- `hp-stick36-base` was built with a throwaway key (`/root/abbilder/hp36tmp/dummy-device.key`). It is a comparison baseline for overlays only. NEVER flash or boot it on the HP: its device id is not paired.
- Rule for `/root/abbilder`: never delete `*.key`, `hp-*base*`, `hp-stick*`.
- Recover: read the key from the running HP (`jarvisctl` / `/var/jarvis` over an existing bridge session) and store it as `/root/abbilder/hp-device.key`, mode 0600. Do not run an image with that key in parallel in QEMU (same bridge id).
- New pairing instead (needs a new image): build with a fresh key, boot once, read the 6-digit code from `/var/jarvis/pairing`, run `jarvisctl pair <code>` on the device, then the admin calls `POST /bruecke/koppeln {geraet, code}` on the server (see `docs/BRIDGE-PAIRING.md`), and pin the new id in `data/bruecke_devices.json`.
- Nothing in this recipe is applied to the HP by the tooling.
