# DRIVERS — runtime-loaded kernel drivers (Boss decision 26.10.2026)

Target: drivers are loaded into the kernel at runtime like on Windows: ring 0, own kernel loader, package file + manifest with PCI ids, signature, fixed kernel API, DriverEntry-like entry point, unload and reload without a new kernel.

## 1. Current state (measured against the tree, main ccaec9b8 + this branch)

| Piece | State | Where |
|---|---|---|
| Kernel loader (ring 0) | REAL. `module.load` maps an ELF `.omod`, relocates it, resolves symbols against the kernel table, checks the Ed25519 signature and the revocation list, then calls `module_init(state)`. `module.entladen` calls `module_exit(state)` and frees the image. | `kernel/ldr/module.fi`, `kernel/lib/ksym.fi` |
| Package format | REAL. `/lib/drivers/<name>/driver.inf` + `driver.inf.sig` + `<module>.omod`; `/apps/*.osp/lib` packages too. | `kernel/bus/drvinf.fi`, `tools/drvstore/mkpkg.py` |
| Auto-bind | REAL for PCI. A store package binds only if no built-in driver claims the device (`drvreg.claimed`). USB/ACPI records are indexed, not bound live. | `kernel/bus/drvstore.fi` |
| Unload / load / reload | REAL. `drvctl unload|load|reload <pkg>`; reload refuses while references are held (busy). | `kernel/bus/drvctlnode.fi`, `kernel/user/drvctl.fi` |
| Kernel API | 14 symbols, ABI 1: `k_puts k_putc k_dec k_hex k_nl k_text k_get k_set k_get8 k_set8 k_bind k_abi kdata k_fwreq`. Device context at `state + 0xAA800`. | `kernel/lib/ksym.fi` |
| Entry point | `module_init(state)` / `module_exit(state)`. | `module/store/edudemo.fi` |
| Observability | `/proc/drivers` (per-device driver, source, bind result, store summary); boot lines `drvstore: ...` | `kernel/bus/drvdev.fi` |
| Test mode | NEW. See section 3. | `kernel/bus/drvstore.fi`, `kernel/ldr/module.fi`, `kernel/user/testmark.fi` |

So a store package is really loaded by the kernel loader and runs in ring 0 (proof: `tools/drvstore/run.sh`, the edudemo module reads the device id register through BAR0). It is not only an assignment table.

## 2. What is missing for the Intel 8265 WLAN as a package

WLAN is a built-in driver today (`kernel/drv/net/iwl*.fi`, `lib/wlan/iwl_*.fi`). A package needs ABI 2 first:

- memory and DMA allocation, PCI config and MSI/PM access, IRQ registration, timers, VFS read for firmware and config, netdev/netclass registration, procfs registration (`/proc/wlan`), sha256.
- `rights=` is enforced only for `mmio` and `fw`.
- The built-in driver wins over any store package, so the built-in row must be removed when the package exists.

Order of work: ABI 2 symbols, then a thin shim (register/DMA/IRQ access), then policy, PHY-DB and calibration (`lib/wlan/iwl_phydb.fi`, `iwl_boot.fi`, `iwl_mvm*.fi`) as the package. Not done in this round because W-WLAN71 changes the same files.

## 3. Test mode (unsigned packages)

- Switch: `/etc/drvstore.conf` with a line `testmode=1`. Read at store scan (boot). Without the file or with `testmode=0` every unsigned or tampered package is rejected with code 20, and the loader refuses an unsigned module (`R_SIG`).
- With the switch: a package with a wrong or missing `driver.inf.sig` is accepted and marked `unsigned` (`drvstore: pkg <n> ok unsigned`); the loader accepts an unsigned `.omod` (`module: unsigned accepted (testmode)`); the store prints `drvstore: testmode=on` and `/proc/drivers` carries ` testmode=on` on the store line.
- Revocation list and the compiled-in floor still apply to modules; ABI, manifest syntax and the file checks stay enforced.
- Warning display: `kernel/user/testmark.fi` (hosted by the taskbar) shows a small window `Test mode: unsigned drivers on` at the top right while the file says `testmode=1`.
- Only developers set this: there is no Bridge right for it (`rechte-hp.conf` allows no `install`, `ban`, `remove`, and the file is not in the write list).
- Gates: `tools/drvtest/run.sh` (rejected without switch, accepted with switch, counter-proofs `off` and `testmode=0`), `tools/testmark/run.sh` (watermark with and without the switch).

## 4. Bridge rights HP (`assets/jarvis/rechte-hp.conf`)

`/bin/drvctl`: only `list match slots load unload reload`. `/bin/wlanctl`: only `status dump reload`. No `install`, `remove`, `ban`, `aux`. Checked by `tools/hpconf/run.sh`.

## 5. Open

- ABI 2 and the WLAN package (section 2).
- Settings page "Developer": reload driver, install package from file or feed, live log (`/proc/wlan`), test-mode toggle. Needs a manifest page, a root action in `settingsd`, locale keys de+en, route and rights class. Until then the switch is the config file and the Bridge gives `wlanctl status|dump|reload`, `drvctl reload`.
- `drvctl install` (userland check in `drvpkg`) still demands a valid signature even in test mode; unsigned test packages are copied into `/lib/drivers` by file tools.
- Runtime toggle without reboot (store rescan).
