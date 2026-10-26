# Boot entry after "install beside Windows"

## Where the loader lands

The beside-install reuses the existing EFI System Partition (ESP) and writes:

| ESP path | Content |
|---|---|
| `\EFI\<slug>\BOOTX64.EFI` | Limine (the boot loader of this OS); `<slug>` is the brand slug (`product.slug()`) |
| `\EFI\<slug>\osum.mb` | kernel |
| `\limine.conf` | menu: the product entry, plus `Windows Boot Manager` (chainload of `\EFI\Microsoft\Boot\bootmgfw.efi`) when Windows is present |
| `\EFI\BOOT\BOOTX64.EFI` | Limine, ONLY if the file did not exist yet. An existing fallback loader (for example the one of Windows) is never overwritten. |

After writing, the ESP is unmounted and mounted again; kernel, loader and `limine.conf` are read back and compared byte for byte. A mismatch ends the install with an error code (65 kernel, 66 loader, 67 menu, 68 remount).

Installs made by earlier brands live in a legacy directory, for example `\EFI\orientos\`. The registry of legacy slugs is `tools/marke/legacy-slugs.txt`.

## Why a firmware (NVRAM) entry is needed

Firmware boot menus (HP, Dell, ...) list only UEFI variables `Boot####` in NVRAM. Copying files to the ESP creates none. Osum is started by Limine through multiboot1, so the kernel has no UEFI runtime services and cannot write NVRAM itself.

## Stick registration step

The installer stick carries `\EFI\BOOT\bootreg.efi` and `\EFI\BOOT\bootreg.cfg` (`slug=`, `name=`, and one `alt=` line per legacy slug). Its menu has the entry `Register <product> in firmware boot menu` (not the default).

1. Keep the stick plugged in, restart, choose that entry once.
2. `bootreg.efi` scans all other disks for `\EFI\<slug>\BOOTX64.EFI` (and the `alt=` directories), writes `Boot####`, prepends it to `BootOrder` and reads both back.
3. Remove the stick; the firmware boot menu now lists the product.

## Emergency path on HP firmware

Without registration: F9 (boot menu) -> Boot from EFI File -> choose the ESP disk -> `EFI` -> `<slug>` -> `BOOTX64.EFI`. Installs from the legacy brand: `EFI` -> `orientos` -> `BOOTX64.EFI`.

## Windows Boot Manager entry (manual only)

Documented, never automated. From an elevated Windows prompt, with the ESP mounted as `S:`:

```
mountvol S: /S
bcdedit /copy {bootmgr} /d "<product>"
bcdedit /set {<guid printed by the copy>} path \EFI\<slug>\BOOTX64.EFI
bcdedit /set {bootmgr} displayorder {<guid>} /addlast
mountvol S: /D
```

For a legacy install use `\EFI\orientos\BOOTX64.EFI` as the path.

## Gate

`bash tools/dual/bootentry.sh` runs the installer path against a Windows-like GPT (ESP with `\EFI\Microsoft\Boot\bootmgfw.efi`), once with an existing `\EFI\BOOT\BOOTX64.EFI` (must stay byte-identical) and once without (must be created).
