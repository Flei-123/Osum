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
**Not in stage 1** (next): `root` role = system programs in /bin (file overlay `sysfile files` with
per-file hash, staged under /system/new + atomic rename, tied to the same trial) -- needed so taskbar,
login, installer update too; gzip transport (streaming inflate); Settings page block; early-death
kernels (needs the EFI selector, docs/AB-KERNEL.md option 1).

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

