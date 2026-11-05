# Dev mode (full remote access for JARVIS)

Dev mode lets JARVIS work on a device through the bridge without the per-path / per-command permission lists. It exists for development devices (HP, test VMs). It is never part of the public image.

## What it does
- Reads, writes and lists any path, runs any program with its full path (up to 7 words), screenshots without the local confirmation (`screenshot = always`), output up to 512 KiB, files up to 4 MiB.
- Every job is written to `/var/log/jarvisd.log` as `ok-dev` / `REJECTED-dev`; switching on and off is logged as `devmode ON` / `devmode OFF`.
- The taskbar shows a red `DEV` field while it is active (the `JARVIS` field has priority).

## What stays locked (deny list, `kernel/app/jarvisd/jddev.fi`)
- Never readable or writable: `/secrets`, `/device`, `/state/session`, `/etc/shadow*`, `/etc/passwd*`, `/etc/machine-id`, `/etc/wlan.conf*`, `/etc/dbgsrv.token`, `/etc/odb.token`, `/etc/social`, `/config/vpn/keys`, `/etc/jarvis/device.key`, `/root/.ssh`.
- Never writable: the audit log, the stop marker `/var/jarvis/dev-off`, the active marker `/var/jarvis/devmode-active`, `/var/jarvis/pairing-ok`.
- Commands: refused if the program name contains `vault` or `jsig`, or the command line names a denied path. The audit log may only be read by read-only programs without `>`.
- Writing `/etc/jarvis/permissions.conf` is allowed, but the daemon re-reads it and restores the previous file when the result has no valid server.
- Limit: with `/bin/sh` on the device the command check is best effort (scripts are not inspected). The real boundary is TLS + pairing + emergency stop + audit log.

## Turn on
- Ship the dev config: `HP_DEV=1 tools/ota/republish-hp.sh "<notes>"` (copies `assets/jarvis/rechte-hp-dev.conf` = HP config + `devmode = yes`, `screenshot = always`, `input = yes`).
- Update the device: `/bin/ota system apply restart`, then `jarvisctl dev` (must say `Dev mode: ACTIVE` after the next job).
- Public images refuse `devmode = yes` / `screenshot = always` (`tools/usbimg/build.sh`).

## Turn off / emergency stop
- At the device or through the bridge: `jarvisctl dev off` (creates `/var/jarvis/dev-off`, the very next job is refused).
- `jarvisctl dev on` releases the stop only at the device; a process started by the bridge is refused.
- Permanently: publish without `HP_DEV` (the HP config has no `devmode`).
- `jarvisctl dev` / `jarvisctl status` show the state.

## Gates
- `tools/hpconf/run.sh` (config rules incl. counter-proofs), `tools/bridge2/devmode.sh` (VM: deny list, counter-proof without devmode, emergency stop, stop marker at boot).
