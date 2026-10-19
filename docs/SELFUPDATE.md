# SELFUPDATE -- OrientOS updates itself (design + stage 1), 19.10.2026

Goal (boss): like the FleiLauncher. The OS checks the update server, shows version + changes,
downloads (HTTPS, SHA-256 + Ed25519), installs, restarts. No VM / image swap.

## 1. Inventory (checked in code)
- Exists: `ota.fi` (package update: search/apply/confirm/rollback/service, `kanal=` in /etc/ota.conf),
  `ab.fi` (+ `esp_flip`: trial counter, loader back to slot A), `opk.fi`, Ed25519 chain, feed
  `https://store.fleitec.com/osum/aktuell`, `tools/ota/*`, Settings R_UPDATE page (settingsd).
- Layout facts: installed disk = GPT, partition 0 = ESP (FAT32: `limine.conf`, `osum.mb`, loader),
  partition 1 = OSUM root (OFS v3, **persistent**: /users, /etc, /system, /bin). Boot args `vfs` (no
  `modfs`/`module_path`). The live stick instead loads `root.img` as a RAM module (nothing persists).
- Gaps found: (a) the feed carries only 14 packages -- kernel and /bin system programs are not
  updatable; (b) no ESP write from ring 3 in `ota`; (c) installer writes `limine.conf` without a
  `default_entry` line (esp_flip needs one); (d) the device has gzip/inflate (`flate.fi`) but **no xz
  decoder** and `gunzip` is not streaming (256 KB buffers) -> stage 1 transports files raw with
  `Range` resume; compression = next step; (e) no OS-readable build version existed.

## 2. Design
**Channels** `stable` | `dev` (+ `test`): `kanal=` in /etc/ota.conf (already shared with packages).
**Server layout** (additive; `aktuell/` is rebuilt by veroeffentlichen.py and stays untouched):
`<feed>/system/<channel>/{VERZEICHNIS,VERZEICHNIS.sig,kernel-<N>.mb,CHANGES-<N>.txt,schluessel.pub}`
Device base URL: `sysquelle=` if set, else `quelle` with `/aktuell` -> `/system`.
**Manifest** = the normal signed `VERZEICHNIS` (OTA2: key chain, lock list, signature -- the proven
path) plus two additive line types (old clients ignore them):
`system <TAB> count <TAB> commit7 <TAB> min_from <TAB> name`
`sysfile <TAB> kernel|notes|root <TAB> sha256 <TAB> octets <TAB> file`
`count` = build number (git commit count), only grows. Signature = existing bundle key
(`/root/.secrets/osum-ota-bund.json`). `min_from`: older systems must reinstall.
**Device state**: `/system/SYSVERSION` (8 digits, rollback guard, set at image build and at promote),
`/etc/osversion` (text), `/system/SYSPENDING` (count/commit/sha of the staged kernel),
`/system/sys.stand` (here/there/commit/phase for the UI), `/system/sys.notes` (changelog).
**Slots on the ESP**: A = `osum.mb` (last confirmed), B = `osum-b.mb` (trial). Menu: entry 1 = A,
entry 2 = B. Invariant: default_entry is 1 except during a trial.
**Flow** (`ota system apply [restart]`):
1. dir_get (HTTPS + chain + signature) -> parse `system` lines -> count > SYSVERSION, min_from ok.
2. mount ESP (partition 1 of the boot disk: tries /dev/sda1, /dev/nvme01, /dev/hda1 in that order and takes the first that holds limine.conf -- /dev/hda1 on a box without an IDE disk stalls for minutes) at /sysesp; fetch kernel straight to `osum-b.mb` (length + SHA-256 from the
   signed list, resume with `Range`); wrong hash -> file removed, nothing else touched.
3. write SYSPENDING; arm `/system/ERPROBUNG` (`gen=G vor=G v=00 ok=0`, G = /system/AKTUELL).
4. LAST: new `limine.conf` (default_entry: 2 + entry B, copy of entry 1 cmdline) via limine.nw + rename.
   Only the installer layout is accepted (ONE entry, `path: boot():/osum.mb`), else refused.
5. restart. Trial boot of B: `ab_boot` counts; after 3 unconfirmed boots it rolls back and
   `ab.esp_flip` sets default_entry 1 (slot A).
6. `ota boot` / `ota confirm` after a healthy desktop calls `su_finish`: running commit == pending and
   default_entry still 2 -> hash B, copy B -> A (hash again), patch ONE byte (`2`->`1`), SYSVERSION=count,
   drop SYSPENDING. Running kernel != new, or default already flipped -> update dropped (phase=failed).
   Power cut while copying: default stays 2, pending stays, next confirm retries.
**User data**: untouched. Installed layout: root partition is persistent and not modified by a kernel
update. Live stick / module-root layout: nothing persists by design.
**Stage 2 (below)** adds the /bin overlay and gzip transport. Still open: Settings page block;
early-death kernels (needs the EFI selector, docs/AB-KERNEL.md option 1).

## 3. Use
    bash tools/ota/publish-system.sh <imgdir> <feeddir> <stable|dev> [--count N] [--notes FILE]
    ota system search | apply [restart] | status | confirm
Negative stands: `--bad-hash`, `--bad-sig`. Live publishing: only to `system/dev` first.

## 5. Gate notes (tools/osupdate/run.sh)
- The installed disk is booted on an AHCI controller (`OTA_DRIVE=ahci`, default in the gate; `OTA_DRIVE=ide` keeps the old PIO disk). Measured: copying the 8.66 MB kernel inside the ESP takes ~30 s on AHCI; over emulated IDE (PIO, 512-byte FAT clusters) the promote copy B->A did not finish in 10 minutes.
- The promote copy uses 32 KiB writes (`SU_BIG`).

## 6. Settings block + periodic check (stage 1b)
- Settings > Updates, right column: **System (kernel) update** -- running build (`/etc/osversion`), channel, phase
  (current / available + build + commit / staged / failed), changelog list (`/system/sys.notes`), buttons
  *Check system* and *Install system update and restart*. The install is a critical action: the page asks,
  "Yes, do it" confirms (same path as the package update).
- settingsd actions (manifest `etc/actions.d/settings.actions`): `settings.update.sysstatus` (read: `ver=`, `here=`,
  `there=`, `commit=`, `phase=`, `channel=`, `busy=`, up to 8 `note=` lines), `settings.update.syscheck` (write:
  `ota system search` in the one-child slot), `settings.update.sysinstall` (critical: `ota system apply restart`).
- Service: `ota service` checks the SYSTEM feed at its first round (START seconds after boot) and then every
  `sysabstand=` seconds in /etc/ota.conf (default 21600 = 6 h; 0 = off). Quiet: fetches the changelog, writes
  `sys.stand` phase=available and posts ONE notification per build number (`/system/sys.notified`, toast + bell of
  the bar). Nothing is installed; no check while a trial/pending update exists; an error is retried next round.
  Same on/off switch as the package service (`auto=`). Test entry: `ota service 1 system`.
- Gates: `tools/osupdate/run.sh` section 7 (service check), `tools/actionbus/run.sh` S-UPD + `gui.sh` (page block).


## 6. Live feed `system/dev` (store.fleitec.com), published 19.10.2026
- The store is a plain static directory on the JARVIS server: `/srv/store/osum` is served at
  `https://store.fleitec.com/osum/` (openresty). `aktuell/`, `v/`, `pakete/`, `register.json` are written by
  `veroeffentlichen.py`; `system/` is a sibling that script never touches (it only rewrites `aktuell/`, `v/<n>`).
- Procedure (no extra credentials beyond the bundle on the server: `/root/.secrets/osum-ota-bund.json` +
  `/root/.secrets/osum-ota-pass.txt`, used by `publish-system.sh`):
      bash vendor/firn/fetch-firnc.sh && bash tools/build-kernel.sh <dir>/osum.mb --stufe 0
      bash tools/ota/publish-system.sh <dir> /srv/store/osum dev --notes <notes.txt> --name "OrientOS dev"
  The kernel is copied first, the signed `VERZEICHNIS` last, so a half-written stand is never visible.
  `count` = `git rev-list --count HEAD` (only grows; devices refuse `count <= SYSVERSION`).
- The signature uses the same bundle key as `aktuell/` (`system/dev/schluessel.pub` == `aktuell/schluessel.pub`),
  so every installed image already trusts it. Default channel on a device is `stable`; `system/dev` is only read
  by devices with `kanal=dev` in `/etc/ota.conf` (or `sysquelle=`).
- Check after publishing: `curl -s .../system/dev/VERZEICHNIS | ...` + Ed25519 verify with `tools/ota/listing.py`
  (`m.ed25519_verify(pub, doc, sig)`), kernel hash vs the `sysfile kernel` line, and an `aktuell/ v/ pakete/` checksum
  taken before/after (must be identical).
- Rollback of a bad stand: remove `system/dev/VERZEICHNIS` (devices then see "no system line"); installed trial
  kernels roll back by themselves after 3 unconfirmed boots.
- Stand 1: count 3195, commit 676b055 (main 676b0554), kernel sha256 c98bf5c3...2934, 8 649 000 bytes.

## 7. Stage 2: /bin overlay (r1245) + gzip transport (r1246)
Additive: old clients ignore `sysgz` lines and treat `sysfile file` as the old unknown role (just a hint).
**Manifest lines** (inside the signed VERZEICHNIS):
`sysfile <TAB> file <TAB> sha256 <TAB> octets <TAB> <server file> <TAB> <name in /bin>` (hash/octets of the FINAL file)
`sysgz <TAB> <kernel|name> <TAB> sha256(gz) <TAB> octets(gz) <TAB> <server file>.gz` (optional alternate transport)
The device uses the gz when a `sysgz` line exists for the key, else the raw file. VZ buffer is 32 KiB
(~250 octets per overlay file with gz => ~100 files). Names: letters, digits, `. - _`, no leading dot, max 60.
**Apply order** (`ota system apply`): fetch + verify EVERY overlay file into `/system/new/<name>` (gz: download to /tmp/ota,
check gz hash, stream-gunzip, check final length + SHA-256) -> kernel to `osum-b.mb` (same path) -> SYSPENDING -> trial counter ->
**swap**: journal `/system/SYSOVL` (`<1|0><name>` per line, 1 = /bin file existed), then per file old -> `/system/old/<name>`
and new -> `/bin/<name>` (rename never overwrites in this VFS) -> boot menu switch LAST. Any failure after the swap starts restores.
**Commit / rollback** (`su_finish`, i.e. `ota boot`/`ota confirm`): promoted -> `su_ovl_drop` (backups + journal removed);
trial lost, pending note broken, or a journal without a pending note (power cut during apply) -> `su_ovl_restore`
(journal-driven: old files back, new-only files removed). The overlay is live from `apply` on (also under the old kernel);
if a replaced program breaks the desktop, the 3-boot trial rollback + the next `ota confirm` restores them.
**Streaming gunzip** `kernel/user/inflate.fi` (`gunzip_fd(in_fd, out_fd)`): 4 KiB input chunks, 32 KiB ring window, constant ~45 KiB RAM,
CRC-32 + ISIZE trailer checked (E_CRC), puff-style canonical Huffman; flate.fi stays the in-memory codec.
**Publisher**: `publish_system.py ... --overlay DIR [--gz]`; negatives `--bad-gz` (bit flipped inside the deflate data, gz hash
recomputed) and `--bad-ovl-hash`. Empty files are refused.
**Gate** sections 8-11 + overlay checks in 2 (gz trial boot, byte-identical files via shasum) and 5 (lost trial restores /bin).
**Limits**: rename of the running `ota` itself is untested; free space is not pre-checked (a full disk aborts + restores);
staging and backups need ~2x the overlay size on the root partition.
