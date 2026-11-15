# LICENSES.md -- licence duties of the shipped image

Not legal advice. Facts as of 15 Nov 2026, audit w-licenses42.

## Rule

Nothing foreign enters an image without a line in `licenses/registry.txt`.

* One line per component: `id|name|version|spdx|profiles|paths|texts|source|copyright`.
* `paths` are image paths (glob, `*` also crosses `/`). `-` means the component has no file of its own (own code, compiled-in data).
* `profiles`: `public`, `personal`, `store`, `future`. Only components of the building profile are written into the image.
* `texts` are original licence texts in the repository (`assets/LICENSE-*`, `licenses/texts/`).

`tools/usbimg/build.sh` calls `tools/licenses/notices.py image` before `mkfs`:

* a file whose path matches no entry and looks foreign (`.ttf .otf .so .a .pem .ucode .xkb`, firmware) stops the build;
* a file whose source lies outside the repository and the build directory and has no entry stops the build;
* otherwise the image gets `/usr/share/licenses/<id>/<text>` for every present component and `/usr/share/licenses/THIRD-PARTY-NOTICES`.

Gate: `bash tools/licenses/run.sh` (lint, public image build, 9 counter-checks, HP image listing).
Settings > About shows the licence note and where the texts are.

## Store packages

`pakete/*/INFO` needs `license=<SPDX expression>` (`osdk build --strict` refuses anything else). A package that bundles
foreign files adds `notices=<file>` with their notices and gets a registry line with profile `store`.
Planned: Firefox (MPL-2.0), FreeViewer, linuxkpi drivers (GPL-2.0-only, source offer), Mesa (MIT), Certus data
(public suffix list MPL-2.0, EasyList GPL-3.0/CC-BY-SA, Certus fonts DejaVu/GPL+exception) -- registered as `future`.

## Components in the standard (public) image

| Component | Licence | Duty | Met before | Met now |
|---|---|---|---|---|
| Osum kernel, programs | GPL-2.0-only | licence text, source for recipients | text only in repo | text + notices in image; source at GitHub |
| Ring 3 libs | MIT | notice | repo only | in image |
| Firn runtime modules | MPL-2.0 | licence text, source | repo only | in image |
| Inter (sans, bold) | OFL-1.1 | copyright + licence with every copy | no | yes |
| Liberation Serif | OFL-1.1 | same; reserved name "Liberation" | no | yes (check name table, see open points) |
| Noto Emoji | OFL-1.1 | same | no | yes |
| DejaVu (mono, symbols, console bitmaps) | Bitstream Vera | notice, no "Vera" name for modified | no | yes |
| Lucide icons | ISC | notice | no | yes |
| musl 1.2.6 | MIT | notice with binaries | no | yes |
| Limine 9.6.7 | BSD-2-Clause | notice with binaries | no | yes |
| Mozilla CA bundle | MPL-2.0 | licence, mark changes (filtered) | no | yes |
| xkeyboard-config 2.35.1 keymaps | MIT-style | notices | no | yes |
| Certus | GPL-3.0-or-later + 7(b) | attribution in About box of redistributors | own work | notice shipped |
| minimp3 port, tzdata | CC0, public domain | none | -- | listed |

Personal only (not distributed): iwlwifi firmware (Intel licence: unchanged, licence text with it, no disassembly),
BusyBox and git (GPL-2.0), CPython (PSF), curl, tcc (LGPL-2.1). Duties start when an image with them leaves the house.
