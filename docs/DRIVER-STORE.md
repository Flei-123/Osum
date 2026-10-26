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
2. For every PCI/USB/ACPI device without a built-in driver pick the best package, write a device context into `kstate.MODULE_OFF + 0x1800` (bus, ids, subsystem, bdf, bar0), call `module.load` (signature, revocation list, ABI), one error line on failure, boot continues.
3. `/proc/drivers` gets one line per device (id, driver, source `builtin|store|-`, bind result); devices without driver show `drv=none`.
4. `drvctl list|match|install|remove|ban`: `install` verifies the signature before copying to `/lib/drivers`; `ban` is a local deny list `/etc/drivers.deny` (the signed revocation list can only be produced on the host: the private key is not on the target).
5. Word `nostore` (planned bit 1195) switches the whole thing off (counter-proof).

## 3. Test hardware ids (HP EliteBook x360 1030 G2, read under Windows)

`pci 8086:24fd:8086:9010` WLAN 8265 (built-in `iwl` claims it; the store must not touch it), `pci 8086:9d60..9d62` LPSS I2C, `pci 8086:5916` HD 620, `pci 8086:9d71` HDA, `usb 8087:0a2b` Bluetooth, `usb 05c8:0396` / `05c8:080b` webcam, `acpi ALP0016` touchpad, `acpi WCOM481A` touchscreen, `acpi INTC816` ISH. Source: `data/projects_kb/orientos/hwdata/hp-x360-1030g2-ids.md`.

## 4. Security (honest)

- Everything runs in ring 0. A correctly signed but faulty module crashes the kernel (measured in `tools/module/run.sh` section 7). Signature proves origin, not correctness.
- No IOMMU: a loaded driver can DMA anywhere (`DRIVER-ARCHITECTURE.md` D5/D6).
- `rights=` is parsed and will be logged; **not enforced** for `.omod` yet (D4 open).
- Deleting `/lib/omod.sperre` unlocks everything on that list, but not the compiled-in floor (section 8).
- A manifest signature binds only the manifest; the module is bound by its own signature. A validly signed old module paired with a new manifest is possible until the manifest carries the module signature hash (planned: `module-sig=` key).

## 5. Kernel part (built 24.10.2026, gate `tools/drvstore/run.sh`)

- `kernel/bus/drvinf.fi`: manifest parser (same grammar as `mkpkg.py`), record layout, match specificity.
- `kernel/bus/drvstore.fi`: scan `/lib/drivers`, signature check (`module.signatur_gilt`), ABI check, module file check, local deny list `/etc/drivers.deny` (one package name per line), index (16 packages), PCI auto-bind for devices no built-in row claims (`drvreg.claimed`). Boot lines `drvstore: pkgs=N valid=M`, `drvstore: pkg <name> ok|rejected <code>`, `drvstore: bind <name> -> pci ...`.
- Reject codes: 1 syntax, 2 key, 3 duplicate, 4 name, 5 name != dir, 6 number, 7 module, 8 right, 9 fw, 10 slot, 11 missing key, 12 match, 13 no match, 14 too many, 15 too big, 20 signature, 21 ABI, 22 module file missing, 23 file missing.
- Device context for the module at `state + 0xAA800` (`kstate.MODULE_OFF + 0x1800`): +0 version 1, +8 bus (1 pci), +16 vendor, +24 device, +32 subsys (vendor<<16|device), +40 class<<8|sub, +48 prog-if, +56 bdf, +64 BAR0 mapped (only with `rights=mmio`, which also enables memory decode), +72 irq line, +80 pci index, +88 BAR0 physical.
- `/proc/drivers`: old registry table, then `# devices` with one line per PCI/USB/ACPI device: `drv=<name> src=builtin|store|none bind=bound|failed|seen|-`, plus `store=on pkgs= valid= bound= failed=` or `store=off`.
- Word `nostore` (bit 1195) skips scan and bind.
- Demo: `module/store/edudemo.fi` binds QEMU `edu` (1234:11e8), reads the id register and a liveness register through BAR0.

## 6. drvctl and fw.request (built 24.10.2026, gate `tools/drvstore/run.sh` 70/0)

- `drvctl list`: one line per `/lib/drivers/<name>`: `version= rank= sig=ok|bad|missing`, plus `invalid` (wrong ABI, missing module, unknown manifest line) and `banned`; ends with `packages=N valid=M` (same count as the kernel scan).
- `drvctl match <pci|pciclass|usb|acpi> <id>`: best package with the kernel rule (specificity, then rank, then version); banned and invalid packages are skipped. `pci` ids: `VVVV:DDDD` or `VVVV:DDDD:SSSS:ssss`; `pciclass`: `CCSS` or `CCSS:PP`.
- `drvctl install <dir>`: verifies `driver.inf.sig` (Ed25519, same key as the kernel) before anything is copied; copies manifest, signature and module to `/lib/drivers/<name>`; takes effect at the next boot.
- `drvctl remove <name>`, `drvctl ban <name>`, `drvctl unload <name>` (section 8) (appends to `/etc/drivers.deny`); names are validated (`[a-z0-9_-]`, no paths).
- `fw.request`: kernel symbol `k_fwreq(name, sha256_32_bytes, dst, cap) -> length (0 = refused)`, in `kernel/bus/drvfw.fi`. Needs the manifest right `fw`, a `fw=` key, name and hash equal to the signed manifest, and the SHA-256 of `/lib/firmware/<name>` must match. Errors are printed as `drvstore: fw <pkg> error N`: 2 no right, 3 no fw key, 4 name, 5 hash differs from module, 6 file missing, 7 too big, 8 read, 9 digest mismatch.
- `ksym` has 14 symbols now (`k_fwreq` appended, ABI unchanged).

## 7. Open

USB/ACPI auto-bind (only PCI binds; USB/ACPI are listed), hot-plug rescan, rights enforcement besides `mmio` and `fw`, PS/2 mouse via store, `drvctl` has no live rescan (active after reboot).

## 8. Trusted keys, revocation floor, reference counts (r16, 25.10.2026, gate `tools/drvpolicy/run.sh` 47/0)

- `tools/module/mkpolicy.py` turns `tools/module/keys.default` (hex public keys, max 4) and `tools/module/banfloor.txt` (hex `.omod` signatures, max 64) into `lib/modpolicy/policydata.fi`. Kernel (`ldr/modpolicy.fi`, `module.signature_valid`) and `drvctl` (`drvpkg.verify_dir`) both read it through `lib/modpolicy/policyhex.fi`; a signature is valid if ANY listed key verifies it.
- Delivery key: private seed `/root/.osum-secrets/osum-delivery.seed` (outside the repo), public key in `keys.default` and `keys.release`. Release procedure: copy `keys.release` over `keys.default`, run `python3 tools/module/mkpolicy.py lib/modpolicy/policydata.fi`; the development seed in the repo then signs nothing the kernel or `drvctl` accepts. The gate fails if the checked-in `policydata.fi` is stale.
- `tools/build-kernel.sh --module-keys FILE --ban-floor FILE` builds a kernel with another policy (copy of `lib/`, build cache key includes it).
- Floor: `check_banlist` tests the compiled-in floor before looking at `/lib/omod.sperre`. A floor module is refused (`gesperrt`) with no list on disk; deleting the list file cannot unlock it.
- Reference counts: `module.ref/unref/refs_of`; the store takes one reference per device bound to a package module. `module.entladen` refuses (returns false, counter `busy_count`) while references exist. Word `drvunload` (bit 1204) makes the boot try to unload every store module, release its references, and unload again (`drvstore: unload <name> refused refs=N` then `ok`).
- Hot unload (r16, 26.10.2026): `drvctl unload <name>` writes `unload <name>` to `/dev/drvctl` (root only, hidden from `ls /dev`) and reads the answer back: `unload <name> ok`, `... idle` (valid package, nothing loaded), `... none` (no valid package of that name), `... busy refs=N` (some holder besides the store's own per-device references; nothing changes). On `ok` the store drops its references, `module.entladen` runs `module_exit` and returns the frames, the binds are marked released (`/proc/drivers` shows the device as `drv=none`, `bound=` falls). Exit code 0 only for `ok`. The kernel logs `drvstore: ctl unload <name> <code>` (0 ok, 1 none, 2 idle, 3 busy). Word `drvhold` (bit 1207) makes the store take one extra reference per bound device, which is the busy case in the gate. No automatic rebind at run time: the package binds again at the next boot.
- Still open: second driver slot class, ref-holding by slot drivers (mouse) that are loaded outside the store, run-time rebind after unload.
