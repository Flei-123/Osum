# HWPROFILE: hardware scan and driver staging in the installer

## Flow
- `hwprofile scan` reads `/proc/drivers` (PCI, USB, ACPI with `drv= src= bind=`) and `/proc/hwid` (DMI manufacturer, product, board).
- Each device is classified (storage, gpu, wlan, eth, audio, input, usb-ctl, bluetooth, camera, serial-bus, platform, infra) and matched against the signed pool `/lib/driverpool/<name>/` with the store rule (`drvmatch`: pci+subsystem > pci > pciclass > usb/acpi, then rank, then version).
- Status per device: `driver` (built-in or store bound), `staged` (pool package matches), `firmware-missing` (matching package lists `fw=` but the blob is neither in the pool package nor in `/lib/firmware`), `missing` (class needs a driver, no package), `infra` (bridges, hubs), `unknown` (no category).
- `hwprofile stage [--pool DIR] [--prune]` copies matching packages to `/lib/drivers` (`drvpkg.install_dir`, signature checked), copies firmware to `/lib/firmware`, writes `/etc/hwprofile` and `/etc/hwunknown`, prunes the pool when everything was staged.
- The installer calls the same step before the root block copy (next to the account write), so the target disk carries only matching packages plus the profile.

## Files
- `/etc/hwprofile`: `hwprofile 1`, `machine ...`, `storage nvme= ahci= raid= vmd= warn=` (warn=set-sata-to-ahci for RAID/RST/VMD), one `dev` line per device, `summary`.
- `/etc/hwunknown`: same format, only `missing`, `firmware-missing`, `unknown` devices, for deriving new drivers.

## Windows side (concept, nothing changes in Windows)
- BitLocker, hibernation/Fast Startup, dirty volume and free space are already refused with a reason by `lib/ntfsshrink` (`words.fi`) in the shrink flow.
- Secure Boot: the stick needs it OFF (Limine/osboot unsigned); the kernel has no UEFI variable reader, so it stays a printed hint.
- Optional Windows helper (.exe/PowerShell): reads `Confirm-SecureBootUEFI`, `manage-bde -status`, `powercfg /a`, `Get-Disk`, writes a text plan and the stick image. Not built.

## Open
- Pool content: only test packages exist; real iwlwifi/MSHW0084 packages and the AX201 firmware blob (licence, not in git) must be built into the stick pool.
- Online reload from the feed when a network is up is not built; `/etc/hwunknown` is the input for it.
- Firmware blob hash is not checked at staging time (`fw.request` checks it at use).
- Windows plan lines are not yet written into `/etc/hwprofile`; no installer window page, only a log line.
