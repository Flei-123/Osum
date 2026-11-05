# LINUXKPI-PLAN: open Linux DRM drivers on Osum (04.11.2026)

Tier rules and the native-only switch: `DRIVER-TIERS.md`. Compat code lives in `compat/linuxkpi/`.

Status: **plan + measurements + store packaging path. No shim code exists yet** (prototype S0 not built, see section 9).

## 0. Boss rule 04.11. (zwischenruf 2): nothing external in the XoffiOS image
- **linuxkpi and every Linux driver are NOT part of the standard image, NOT linked into the kernel, NOT in the repo main tree.** The standard image runs on own drivers (fb/GOP, virtio, vmsvga).
- Offered only as an **optional, signed download via the driver store** (`kernel/bus/drvstore.fi`, `tools/drvstore/mkpkg.py`): one package dir `/lib/drivers/lkpi-<driver>/` = `driver.inf` + `.sig` (Ed25519, same key as `.omod`) + driver `.omod` + `linuxkpi.omod` + `SOURCES.txt` (driver, Linux version, source URL, tarball+file sha256, license, firmware license) + firmware files (hashes in the signed `fw=` line). Installed only when the user asks (`drvctl install`), removed with `drvctl remove` (package dir gone, module unloaded).
- Linux sources are never checked in: `compat/linuxkpi/sources.tsv` pins version + sha256, `compat/linuxkpi/fetch.sh <driver> <empty-dir-outside-repo>` downloads, verifies and extracts only the needed file (untrusted data, nothing executed). `compat/linuxkpi/pack.sh` builds the store package from the compiled modules.
- Gate `compat/linuxkpi/gate.sh`: repo tracks no Linux source/shim/.ko, no image-side file references linuxkpi, standard image has no linuxkpi/Linux marker (counter-proof: injected marker detected), fetch rejects wrong hash/in-repo output, package passes `mkpkg check` (counter-proof: tampered signature rejected). Install/remove mechanics are proven generically by `tools/drvstore/run.sh`.
- Loader side of module-to-module linking is built (05.11.): every loaded module keeps a table of its global defined symbols (`module.fi`: `build_exports`, `find_export`); an undefined symbol is resolved against kernel exports first, then against loaded modules; the consumer takes a reference on each provider (`take_deps`) and drops it on unload (`release_deps`), so a provider cannot be unloaded under a driver. `driver.inf` `requires=<file>` (L-001, 05.11.) names a provider module in the same package directory: the store loads it before the driver (`drvstore.load_provider`), unloads it after the driver (`drop_provider`), `drvctl install` copies it, the scan rejects the package with code 27 when the file is missing. One provider instance per package; two packages naming the same provider file would load it twice (first export hit wins). Gate: `tools/drvstore/requires.sh` (provider/consumer test modules `module/store/prov*.fi`, `consdemo.fi`).
Boss decision 04.11.: real GPUs the FreeBSD way (linuxkpi + unmodified open Linux drivers), not a rewrite per driver.
Measured = produced by `compat/linuxkpi/measure.py` (nm -u on Debian `6.12.101+deb12-rt` .ko files + the matching upstream 6.12.101 tarball, sha256 verified). Effort S/M/L/XL = judgement.

## 1. What works / what does not
- **Works:** open-source drivers **recompiled from source** against our shim: bochs (S0), later i915/xe (Intel), amdgpu, nouveau (display/KMS first), Mesa userspace (anv/radv) over the normal DRM uapi.
- **Does not work:** binary Linux `.ko` files (vermagic, struct layouts, GPL symbol gating; Debian .ko are only used as a measuring input). **NVIDIA proprietary** driver. Closed firmware is loaded as data only (fw.request), never executed by us. GPU rendering needs Mesa (C++ runtime, threads) on top: separate effort.

## 2. Layer rules (Boss 04.11.)
- `compat/linuxkpi/shim/` = shim only (build-tool area, never in the image tree) (C headers + sources + `osum/` interface). Linux files are fetched at build time by `compat/linuxkpi/fetch.sh` into a directory outside the repo and never checked in. Never mixed with Osum `.fi` code.
- `compat/linuxkpi/sources.tsv`: driver, Linux version, source URL, tarball sha256, file, file sha256, SPDX, shim stage. Gate fails when a file hash differs: **driver code is never patched**, fixes go into the shim.
- Downward interface is narrow and documented: `compat/linuxkpi/shim/osum/osum_if.h` (one header). Allowed callees: own DRM/KMS layer (`kernel/gfx/drm`, r671) and existing kernel APIs: pci (cfg, BAR, MSI), dma/pages, irq, timers, fw.request, serial log. Nothing else. No per-driver special cases: quirks and driver lists live in registries (table of PCI ids, table of exports).
- Not part of the Ring-0 import cycle: shim is C in its own `.omod`; only `kernel/lib/ksym.fi` (existing cycle file) grows. The shim lives outside the image tree (build tool area), no layers entry.
- Every shim part gets a gate + counter-proof (wrong symbol rejected, flipped signature, patched driver hash, skipped modeset = no picture). Build reproducible: pinned gcc major + flags file, sha256 of every `.o` recorded; module signed like `.omod` (`tools/module/mkomod.py`, Ed25519).

## 3. Measured symbol surface (Linux 6.12.101, Debian config)
"closed" = undefined symbols of driver + 14 DRM support modules (drm, kms_helper, display_helper, ttm, ttm_helper, gpu-sched, exec, buddy, gpuvm, suballoc, shmem, vram, amdxcp, i2c-algo-bit) minus what that set defines = what linuxkpi must offer when the DRM core is compiled from source too. Compiler artifacts (`__fentry__`, `__x86_*thunk`, `__stack_chk_fail`, ubsan) excluded.

| driver | .ko KB | direct undefined | of those from DRM stack | closed core API | firmware names |
|---|---|---|---|---|---|
| bochs | 71 | 66 | 49 | 515 | 0 |
| nouveau | 6350 | 641 | 325 | 641 | 431 |
| xe | 6340 | 1043 | 511 | 788 | 29 |
| amdgpu | 28565 | 1016 | 398 | 841 | 646 |
| i915 | 8927 | 1213 | 494 | 918 | 44 |

- Union of all five: **1188** names; intersection of the four big drivers: **546**. So ~550 names are the shared base, ~640 are per-driver tails.
- bochs alone: 66 direct names, 49 of them DRM core (atomic helpers, connector/EDID, gem-vram, simple pipe, dev alloc/register); only 17 are base kernel (`_printk`, `__pci_register_driver`, `__request_region`, `__release_region`, `ioremap`...). Exact list: fetched by `compat/linuxkpi/fetch.sh`.
- Largest groups in the closed set (names): lib containers idr/xarray/kref/string/sg/sort 81 (bochs) to 140 (i915); memory 56 to 85; "kernel misc" 52 to 95; dma-buf/fence/sync_file 45 to 57; device model/devres 34 to 56; pci 6 to 51; locks 23 to 32; acpi 6 to 22; irq 2 to 13; i2c 6 to 11; firmware 3 to 4; workqueue/rcu/time smaller.

## 4. Groups, owner, effort
| group | what | where | effort |
|---|---|---|---|
| memory | kmalloc/kfree/vmalloc/kmem_cache/page alloc/shmem/vm_insert_page/dma alloc+map | shim over `mm.mem` + dma | M |
| locks/sched | mutex, spinlock, rwsem, ww_mutex, completion, wait_queue, schedule | shim over our sync + `sched` | M |
| workqueue/time/rcu | queue_work, delayed_work, timers, hrtimer, msleep, ktime, srcu | shim, kernel threads or tick | M |
| lib containers | idr, xarray, radix, kref, list, sort, bitmap, scatterlist, string | **rewrite clean-room in shim** (Linux code GPL) | L |
| device model | struct device, devres, class, kobject, uevent, sysfs/debugfs (stub) | shim, mostly stubs | M |
| pci/io | pci_*, BAR map, ioremap(_wc), config, MSI, AGP/GTT aperture | shim over `bus.pci` | M |
| irq | request_irq, threaded irq, MSI | shim over kernel irq | M |
| dma-buf/fence/sync_file | dma_fence, dma_resv, dma-buf, sync_file | shim (needed by drm core) | L |
| firmware | request_firmware (+nowait) | `drvfw.request` (fw.request) | S |
| i2c | i2c adapter + algo-bit | shim, EDID path | S-M |
| vfs/file | file_operations, anon inode, seq_file, debugfs, mmap | shim + devfs seam | M |
| x86 arch | clflush, wbinvd, set_memory_*, MSR, cpu features, PAT/WC | kernel exports | M |
| acpi/video | backlight, opregion, aperture removal | kernel exports | M |
| DRM core | drm.ko + helpers + ttm + sched + display_helper | **compile real Linux sources** (S1), not rewritten | L |
| per-driver | i915/xe/amdgpu/nouveau compiled unmodified | fetched Linux sources (outside repo) | L-XL each |

## 5. Licenses (SPDX scan, 6.12.101; `compat/linuxkpi/measure.py`)
- **MIT:** i915 (650+154 of 821 files), xe (372 MIT, 14 GPL/dual), amdgpu (all but 3 of 567), amd/display (all 1047), nouveau (all but 55 unknown/dual), scheduler. **Dual `GPL-2.0 OR MIT` / `AND MIT`:** ttm (all 23), parts of drm core.
- **GPL-2.0:** drm core mixed (94 top-level files: ~49 MIT, 16 GPL, 11 dual, 17 unknown), `drivers/dma-buf` core mostly GPL-2.0, `lib/idr.c`, `lib/xarray.c`, `kernel/workqueue.c` GPL: **never copied; shim reimplements** from API behaviour. **bochs.c is GPL-2.0-or-later.**
- Rule: the shim is our own clean-room code (MIT-compatible, no Linux header copied). GPL files (bochs, GPL parts of drm core) are only shipped inside the optional store package (section 0), never in the standard image or base kernel. Legal reading of "GPL module in a non-GPL kernel" is **unverified**: ask before shipping GPL-only drivers; prefer MIT drivers (i915, xe, amdgpu, nouveau) and dual-licensed core files.

## 6. How C reaches Ring 0
- Host `gcc` (pin major, e.g. 12), flags in `compat/linuxkpi/cflags`: `-O2 -ffreestanding -fno-pic -mcmodel=small -mno-red-zone -mgeneral-regs-only -fno-stack-protector -fno-asynchronous-unwind-tables -fno-common -fcf-protection=none`. Object per file, `ld -r` into one `ET_REL`, `mkomod.py` wraps + signs (Ed25519), kernel `kernel/ldr/module.fi` loads it.
- Loader today (read from `module.fi`): relocs 64/PC32/PLT32/32/32S, `MAX_FILE` 512 KiB, `MAX_MOD` 4, `MAX_SEC` 64, 14 kernel exports (`ksym.fi`, name via function-value cell trick), entry `modul_init(state)`/`modul_exit`. **Gaps for linuxkpi:** (1) module-to-module symbol export so `drm.omod` + `i915.omod` link at load, (2) file limit to tens of MB (i915 9 MB, amdgpu 29 MB, compressed `.omod.gz`), (3) GOT relocs if PIC needed, (4) data-driven export table (registry) instead of the if-chain in `ksym.fi`, (5) BSS/percpu/init-section handling, (6) `__ksymtab`/`__param`/`.modinfo` sections read by shim.

## 7. Mapping onto our DRM/KMS layer
- Seam: shim `drm_dev_register()` registers a **backend** with `kernel/gfx/drm` (registry, same as native vgpu/vmsvga backends) that forwards `/dev/dri/cardN` ioctl/mmap/poll to the Linux DRM core in the module. The Linux DRM uapi is stable, so Mesa/libdrm see standard ioctls.
- Osum layer keeps: device naming, display ownership/arbitration (compositor `wmd` is a normal KMS client), vblank/flip events, boot-framebuffer handover. fbdev emulation (`drm_fbdev_ttm_setup`) is replaced by an Osum boot client.
- Open: who owns GEM/TTM memory (Linux core keeps it; Osum maps pages via dma/pages interface).

## 8. Firmware
- `request_firmware(name)` -> `drvfw.request` (fw.request, signed store `/lib/firmware`). Counts above: amdgpu 646 names (few per ASIC needed), nouveau 431, i915 44, xe 29. Licences of blobs are separate (`linux-firmware`, redistributable, no source): manifest column `firmware_license`.

## 9. Stages and gates
| stage | content | gate (+ counter-proof) |
|---|---|---|
| S0 | shim core (pci, io, mem, printk, mutex/spin, workqueue stub, DRM subset ~60 API items) + `bochs.c` unmodified; module loads in QEMU, modeset 1024x768 + test picture | `compat/linuxkpi/run.sh`: serial ID lines, screendump pixels; mutants: unknown symbol rejected, flipped signature, patched bochs hash, skipped modeset = no picture |
| S1 | data-driven export table, module-to-module linking, big-file loader, real Linux DRM core + ttm + helpers compiled over shim | symbol closure = 0 undefined (nm gate), `drm_info`-like ioctl probe |
| M | lib containers + dma-fence/resv + device model + irq/workqueue real; virtio-gpu / vmwgfx / qxl (small open drivers) | per-driver QEMU gates |
| L1 | i915 (Gen7.5 Haswell Dell 9020 first, then Gen12 Iris Xe) display + GEM + execbuf; Mesa anv/hasvk | HP/Dell real-hardware test (Boss) |
| L2 | xe / amdgpu / nouveau (display first, no reclock for NVIDIA) | per-driver |

**Prototype status (honest):** shim and `bochs.c` build not started; only the loader prerequisite (module export tables + dependency references) is in `kernel/ldr/module.fi`, regression-checked with `tools/drvstore/run.sh` (184 OK; 4 red, identical on main 1ab665f7a: `--ohne-ps2m` kernel does not compile). Prepared: bochs.c pinned (6.12.101, sha256 `5877fe15d83a825666e474e5bd6580ea16bc72e5dbb2ffe43802a66b0cb8368a`, fetched not vendored), sources.tsv, measuring tool, exact API list. bochs.c needs (from the source): linux/module+pci+io, DRM drv/dev/atomic helpers/simple pipe/connector+EDID/gem-vram/aperture/fbdev-ttm entry points (66 direct names above).

## 10. Risks
- Version drift (6.12 -> 6.18 renamed fbdev helpers): pin one LTS per driver in the manifest, update per LTS.
- Real GPU bring-up cannot be tested on the build server (no GPU, LXC): only Boss hardware; QEMU covers bochs/virtio/vmsvga/qxl.
- Locking/preemption model differences (Linux RT vs our scheduler) show up as hangs, not crashes: add lockdep-lite gate in M.
