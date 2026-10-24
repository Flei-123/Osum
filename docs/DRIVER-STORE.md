# DRIVER-STORE — signed driver packages (K-014, D1+D3+D4), 24.10.2026

Status: **format + host tool done and gated; kernel index/auto-bind/drvctl NOT built yet** (see "Open"). Nothing here changes a built-in driver.

## 1. Package format (done: `tools/drvstore/mkpkg.py`, gate `tools/drvstore/host.sh` 8/0)

Directory `/lib/drivers/<name>/`:

| File | Content |
|---|---|
| `driver.inf` | text manifest, at most 1536 bytes, `key=value` lines, `#` comments |
| `driver.inf.sig` | 64 bytes Ed25519 over the exact bytes of `driver.inf`, **same key** as `.omod` and `/lib/omod.sperre` (`tools/module/pruef.seed`, public key compiled into the kernel) |
| `<module>.omod` | signed module (`tools/module/mkomod.py`, format unchanged) |

Manifest keys:

| Key | Rule |
|---|---|
| `name` | `[a-z0-9][a-z0-9_-]{0,22}`, must equal the directory name |
| `version`, `abi`, `rank` | decimal; `abi` must equal `ksym.ABI`; `rank` 0..255 |
| `module` | file name in the same directory, `[A-Za-z0-9][A-Za-z0-9._-]{0,30}` |
| `rights` | optional list: `pci-cfg,mmio,irq,dma,fw,usb,acpi,mouse-slot` |
| `fw` | optional `file:sha256hex` (for `fw.request`, D3) |
| `slot` | optional, only `mouse` (binds into `modidx.SLOT_MOUSE`) |
| `match` | 1..8 lines: `pci VVVV:DDDD[:SSSS:ssss]`, `pciclass CCSS[:PP]`, `usb VVVV:PPPP`, `acpi HID` |

Selection rule (planned for the kernel): specificity (`pci` with subsystem > `pci` > `pciclass` with prog-if > `pciclass` > `usb`/`acpi` exact) first, then `rank`, then `version`; a built-in driver that already claims the device (`drvreg.claimed`) always wins.

Any unknown key, duplicate key, bad id, missing `name/version/abi/module`, or no `match` line makes the package invalid. An invalid package never loads.

Host tool: `mkpkg.py build <outdir> --name N --module M.omod --match "pci 1234:11e8" ...` and `mkpkg.py check <pkgdir>`. Broken variants for gates are built by the tool itself (`--bad-sig`, `--tamper`, `--garbage`, `--no-module`), not patched afterwards.

## 2. Planned kernel flow (not built)

1. After the root is mounted: scan `/lib/drivers`, verify each `driver.inf.sig`, parse, build an index (hardware id -> package) without loading any `.omod`.
2. For every PCI/USB/ACPI device without a built-in driver pick the best package, write a device context into `kstate.MODUL_OFF + 0x1800` (bus, ids, subsystem, bdf, bar0), call `module.load` (signature, revocation list, ABI), one error line on failure, boot continues.
3. `/proc/drivers` gets one line per device (id, driver, source `builtin|store|-`, bind result); devices without driver show `drv=none`.
4. `drvctl list|match|install|remove|ban`: `install` verifies the signature before copying to `/lib/drivers`; `ban` is a local deny list `/etc/drivers.deny` (the signed revocation list can only be produced on the host: the private key is not on the target).
5. Word `nostore` (planned bit 1195) switches the whole thing off (counter-proof).

## 3. Test hardware ids (HP EliteBook x360 1030 G2, read under Windows)

`pci 8086:24fd:8086:9010` WLAN 8265 (built-in `iwl` claims it; the store must not touch it), `pci 8086:9d60..9d62` LPSS I2C, `pci 8086:5916` HD 620, `pci 8086:9d71` HDA, `usb 8087:0a2b` Bluetooth, `usb 05c8:0396` / `05c8:080b` webcam, `acpi ALP0016` touchpad, `acpi WCOM481A` touchscreen, `acpi INTC816` ISH. Source: `data/projects_kb/orientos/hwdata/hp-x360-1030g2-ids.md`.

## 4. Security (honest)

- Everything runs in ring 0. A correctly signed but faulty module crashes the kernel (measured in `tools/module/run.sh` section 7). Signature proves origin, not correctness.
- No IOMMU: a loaded driver can DMA anywhere (`DRIVER-ARCHITECTURE.md` D5/D6).
- `rights=` is parsed and will be logged; **not enforced** for `.omod` yet (D4 open).
- Deleting `/lib/omod.sperre` unlocks every banned module (K-014 open point: needs a minimum list in the kernel or in the OTA image).
- A manifest signature binds only the manifest; the module is bound by its own signature. A validly signed old module paired with a new manifest is possible until the manifest carries the module signature hash (planned: `module-sig=` key).

## 5. Open

Index and auto-bind in the kernel, `/proc/drivers` device lines (all PCI/USB/ACPI), `drvctl`, `fw.request`, demo drivers (QEMU `edu` 1234:11e8 probe module, PS/2 mouse via store), QEMU gate `tools/drvstore/run.sh`, `nostore` word.
