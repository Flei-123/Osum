# Brand in the Osum kernel and user space

Source of truth: `marke.conf` (PRODUKT, KERN, HERSTELLER, KURZ, WEB, FEED). Environment `OSUM_MARKE_<FIELD>` overrides it at build time. Defaults: product `XoffiOS`, slug `xoffi`, kernel name `Osum`.

`tools/marke-einsetzen.py` writes the values into `kernel/lib/brand.fi` (`s_product`, `s_core`, `s_vendor`, `s_slug`, `s_web`, `s_feed`). The kernel version line is `<KERN lowercase> <hash>` (default `osum <hash>`), so tools that grep `osum <hash>` keep working.

## Accessors
- Kernel (`import lib.brand`): `brand.product()`, `brand.slug()`, `brand.vendor()`, `brand.web()`, `brand.core()`, `brand.feed()` (NUL-terminated pointers, `_n()` variants give the length), `brand.append(dst, at, src, limit)`.
- Ring 3 text file: `/proc/brand` with lines `product=`, `slug=`, `vendor=`, `web=`, `core=`, `feed=`.
- Ring 3 programs with `ulib`: `import product` (`kernel/user/product.fi`): `product.product()`, `product.slug()`, `product.vendor()`, `product.web()`, `product.core_name()`, `product.feed()`, `product.reload()`.
- Ring 3 programs with `std.*` (profile app, `kernel/app`): `import appbrand` (`kernel/app/appbrand.fi`), same function names.
- Boot loader text and ESP paths: `kernel/user/bootcfg.fi` (`efi_dir()` = `/efi/EFI/<slug>`, `efi_kernel()`, `efi_loader()`, `single_text()`, `dual_text(kind)`, `foreign_text()`); used by the installer and `dualcli`.

## Kept on purpose
- `OSUM-OFS`, `OSUMMOD`, `SSH-2.0-OsumSSH`, `osum_panic`, `osum.mb`, `.osp`, `/users/osum`, CPUID hypervisor id, ABI numbers.
- Crypto and derivation labels (`orientos konto v1 siegel`, `orientos konto v1 marke`, `osum backup v1`).
- Provider and protocol ids: `anb_fleitec` client `orientos-device`/audience `orientos`, `anb_xoffi` provider `xoffi`, `melder` backend `orientos`.
- Kernel command line words (`osum`, `wmdauer`, `absturzhalt`, ...).
