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
