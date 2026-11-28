# hpdaily

Repeatable daily test for the HP (OrientOS device). Output: `hpdaily-<stamp>.md` and `.json` in `reports/`.

## Run
1. `tools/hpdaily/publish.sh` (bundles `hp/*.sh` + `hp/awk/*.awk` into one busybox sh script at the store)
2. On the HP: `/bin/fetch -o /tmp/hpdaily/hpdaily.sh https://store.fleitec.com/osum/hpdaily/hpdaily.sh`
3. On the HP: `/bin/busybox sh /tmp/hpdaily/hpdaily.sh launch` (returns at once, runs about 7 min in the background)
4. Poll `/tmp/hpdaily/run/phase` until `done`
5. Copy `/tmp/hpdaily/run/result.kv` to the server and run `tools/hpdaily/report.sh result.kv --expect-build N --out-dir reports`

Tunables are env or `/tmp/hpdaily/config.sh` on the HP: `DL_URL`, `DL_EXPECT_BYTES`, `URL_EXAMPLE`, `URL_YOUTUBE`, `FX_DEADLINE_*_S`, `IDLE_WINDOW_S`, `INPUT_WINDOW_S`, `EXPECT_KERNEL_COMMIT`.

Needs a logged-in desktop session (xfx refuses otherwise) and `blob64m.bin` + `blob64m.sha256` at the store.
