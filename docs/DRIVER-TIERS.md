# DRIVER-TIERS: native vs compat drivers (05.11.2026)

Goal: a product with **own hardware support only** (no Linux code, no shim, no compat loader) is one switch, not a cleanup.

## 1. Tiers
| Tier | What | Where | Delivery |
|---|---|---|---|
| **native** | Own Firn/Osum drivers | `kernel/`, `module/`, signed `.omod` store packages | built in, or signed store package |
| **compat** | LinuxKPI shim + unmodified Linux drivers | `compat/linuxkpi/` only | optional signed store package (`tier=compat`), never in the base image |

## 2. Rules
- **Dependency direction:** compat may depend on the native ABI (`ksym`, `drvstore`, `fw.request`, `mkpkg.py`, `mkomod.py`). **Native never depends on compat**: no import, no path, no symbol, no string.
- **One location:** all compat code, sources manifest, fetch/pack/build scripts and compat gates live under `compat/<name>/`. No `tools/linuxkpi`, no `kernel/linuxkpi`.
- **Vendor-neutral hooks only in native code:** the `tier=` manifest key, the policy knob, and (from the shim worker) `requires=` / module-to-module linking. They never name a compat product.
- **Default is native.** A package without `tier=` is native. A kernel without policy refuses compat packages.
- Linux sources are fetched at build time outside the repo (`compat/linuxkpi/fetch.sh`), never checked in.

## 3. Build / image switch
- `tools/lib/tiers.sh`: `DRIVER_TIERS=native|native+compat` (default `native`, anything else exits 2).
- `tools/usbimg/build.sh` writes `/etc/drvstore.conf` with `tiers=<value>`. With `native+compat` and `COMPAT_PACKAGES=<dir of package dirs>` it also stages those packages into `/lib/drivers/`. With `native` it stages nothing compat, even when `COMPAT_PACKAGES` is set. A caller-supplied `/etc/drvstore.conf` (via `USBIMG_EXTRA`) is respected.
- Own-hardware-only product: build with the default, do not ship `compat/`. The tree gate proves nothing native references it.

## 4. Store and kernel
- `driver.inf`: optional `tier=native|compat` (signed with the manifest; flipping it breaks the signature). `mkpkg.py build --tier compat`; `compat/linuxkpi/pack.sh` always sets it.
- Kernel: `kernel/bus/drvinf.fi` parses `tier` (`E_TIER` 16 for unknown value), record 440 bytes (`rec_tier`).
- Policy: `/etc/drvstore.conf` line `tiers=native+compat` allows compat packages; **absent or anything else = native only**. A refused package is rejected at scan with code **26** (`drvstore: pkg <n> rejected 26`), never loaded, never bound. Allowed policy is announced by `drvstore: tiers=native+compat` and ` tiers=native+compat` on the `/proc/drivers` store line.
- `drvctl list` prints `tier=native|compat` per package (compat under native policy also shows `invalid`, so `valid=` equals the kernel count). `drvctl tiers` prints the active policy. `drvctl install` refuses a compat package under native policy (`drvctl: compat tier refused by policy`).

## 5. Gate
`tools/tiers/run.sh` (78 checks, QEMU edu): tree has no compat reference (grep of native dirs + Firn imports, planted-reference counter-proofs), no second compat location, `DRIVER_TIERS` switch and staging, native-only image holds no compat file/marker (compat image does: scan proven), kernel image marker scan, `mkpkg` tier key (bogus refused, flip breaks signature), kernel policy (absent / `tiers=native` / `tiers=native+compat`: compat refused with 26 and native driver binds although compat ranks higher / compat binds), `drvctl` list/tiers/install, and it runs `compat/linuxkpi/gate.sh` against the same kernel image.

## 6. Open
- No `compat/linuxkpi/build.sh` yet: the shim (stage S0) is not landed; `fetch.sh` + `pack.sh` exist.
- Boot word `nocompat` (force native regardless of the file) not added; the file is the only knob.
- `requires=` (shim worker) shares the manifest parser and `drvpkg.key_known`: merge carefully.
