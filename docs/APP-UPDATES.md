# Single system app updates (sysapp), 20.11.2026

Goal: a new revision of one system app (explorer, settings, taskbar, launcher, task manager ...) reaches a device
without a kernel update, without a reboot and without a new image.

## 1. Analysis (what was there)
- System apps are `/bin/<name>` ELF files in the image (root-owned, kernel gives them the system origin; an `opk`
  package can never claim that, AB-003). Store packages (`/apps/<name>.osp`, `stored` auto-update) are for add-on apps.
- The `system/<channel>` feed already swaps `/bin` files (`sysfile file` overlay, journal `/system/SYSOVL`, backups in
  `/system/old`), but only as part of a stand: one `count`, one kernel line, every overlay file of the stand at once.
  Live apply (no reboot) exists when the kernel is byte-identical to slot A.
- What breaks when only an app is newer: the stable interface is the Linux-style syscall/kcall numbers, `/proc` file
  formats, `/etc` file formats and bus actions (`docs/ACTION-BUS.md`). Apps are statically linked against `ulib`/`wlibc`
  of THEIR build, so an app built against a newer kernel call set can fault on an older kernel. Until now there was no
  number a device could compare.

## 2. Design
- **Kernel ABI number**: `version.app_abi()` (`kernel/lib/version.fi`, now 1), shown as ` abi N` at the end of
  `/proc/version`. A kernel without the field counts as ABI 1. Bump it when a kernel change breaks existing apps
  (syscall removed/changed, bus action semantics) or when apps start to need a new call.
- **Manifest line** (inside the signed list, additive; old clients ignore it):
  `sysapp <TAB> name <TAB> rev <TAB> abi <TAB> sha256 <TAB> octets <TAB> file <TAB> probe(1|-)`
  plus an optional `sysgz <TAB> name ...` gzip transport. Independent of `system <count>`: the kernel line and count
  of the live stand are untouched, so kernel updates and app updates do not block each other.
- **Device** (`ota system apply`, also the periodic `ota service`, key `appauto=` in `/etc/ota.conf`, default on):
  1. `otaapps.plan`: per app: ABI > kernel ABI -> refused with `needs kernel ABI N (this one: M)`; installed `/bin/<name>`
     already has the listed hash -> skipped (delta, revision recorded); revision <= recorded revision
     (`/system/apps.rev`) -> skipped (no downgrade); else selected.
  2. Selected files are fetched (gzip, hash + size checked) into `/system/new`, then swapped in with the existing
     journal (atomic renames, old files to `/system/old`).
  3. Running taskbar/launcher are ended so the supervisor starts the new file; other programs keep running from the old
     ELF and the next start uses the new one: "open windows keep the old version until closed".
  4. Trial: apps with `probe=1` are started with `--appcheck` (must exit 0); the shell programs must be running again
     after 4 s. Any failure restores the old files and keeps the old revision. Success drops the backups.
- **Counter-proofs** (gate `tools/osupdate/run.sh` section 19, `OSU_SECS=19`): ABI too new refused, broken signature
  refused, wrong file hash refused, failing self-check rolled back, byte-identical app skipped, kernel slot A and
  SYSVERSION unchanged, app and revision survive a reboot.

## 3. Publishing (developer fast path)
    bash tools/store/publish-app.sh <app> [--rev N] [--abi N] [--probe] [--dry]
builds `/bin/<app>` (sync cache), adds/replaces its `sysapp` line in the LIVE `system/dev` list (default
`/srv/store/osum`), signs with the OTA bundle, replaces `VERZEICHNIS` last and checks the https feed. `--dry` works on a
copy. Default revision = live revision + 1.
Device: `ota system apply` (on demand) or the service round (schedule `sysabstand=`, default 6 h).

## 4. Limits
- The updater itself (`/bin/ota`) must be new enough: a device with an older `ota` ignores `sysapp` lines until one
  normal system stand (with this `ota`) has been applied once.
- Only programs that opt in (`probe=1`, `--appcheck`) get an automatic crash check; shell programs are checked for
  restart. A GUI app that crashes at its first window is not detected; backups are dropped on success, a bad revision is withdrawn by publishing the previous file as a higher revision.
- App revisions are not shown in Settings yet.
