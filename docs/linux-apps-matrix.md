# Linux apps on OrientOS: matrix

Measured 22.11.2026 in QEMU KVM (1 vCPU, wayd, Alpine 3.24 musl root, ArtCraft glibc releases). Gates: `tools/linuxapps/guiapps-gate.sh` (GUI), `tools/linuxapps/artcraft-gate.sh` (ArtCraft), `tools/linuxapps/apps-gate.sh` (CLI tools), `tools/linuxapps/gate.sh` (Firefox).

Columns: starts / window visible (wayd window line) / input (typed keys change the window) / cause / effort.

## GUI apps (guiapps.conf, one boot, apps started one after another)

| app | toolkit | starts | window | input | cause of failure | effort |
|---|---|---|---|---|---|---|
| foot | wayland | yes | yes | yes (foot.sh 12/0) | none | - |
| mousepad | gtk3 | yes | yes | yes | one #GP user fault in a library thread (rip base+0x9cba, window stays); GTK icon-theme pixbuf warning | M |
| galculator | gtk3 | yes | yes | not seen in pixels | icon pixbuf warning | S |
| zathura (+poppler) | gtk3 | yes | yes | not seen in pixels | icon pixbuf warning | S |
| xarchiver | gtk3 | no | no | no | abort rc=134: gdk-pixbuf 2.44 loads through glycin and the guest has no /usr/share/glycin-loaders conf.d ("No image loaders are configured"); tree added to guiapps-trees.txt, re-test after the next prep | S |
| imv (imv-wayland) | wayland | yes | yes | yes | none (wayd survives killed clients, windows of gone clients are closed; gate green) | - |
| mpv --vo=wlshm | wayland | yes | yes | yes | none (testsrc plays) | - |
| lximage-qt | qt6 | yes (starts, exits rc=0 after ~1 s) | no | no | silent clean exit without window, no log; Qt wayland plugin loads (it needs qt6-qtwayland); cause open | M |
| weston-simple-shm | wayland | yes | yes | yes | none | - |
| weston-editor | wayland | yes | no | no | text-input manager v1 now served; client dies rc=139 with a NULL deref (cr2=0x8) right after the binds, cause open | M |

## ArtCraft (storytold, MIT OR Apache-2.0, name/logo trademarked)

| app | version | starts | window | input | note |
|---|---|---|---|---|---|
| gridcraft-cli / wordcraft-cli / deckcraft-cli | 0.19.1 / 0.18.1 / 0.18.1 | yes | - | - | 13/13 steps rc=0 (xlsx, docx, pdf, deckcraft) |
| gridcraft | 0.19.1 | yes | yes | yes (typed text, 1799 px diff) | egui/wgpu GL on Mesa llvmpipe |
| artcraft-launcher | 0.19.2 | yes | yes | not tested | dark UI, check uses distinct colors (`--dark`) |
| wordcraft, deckcraft | 0.18.1 | yes (start screen, earlier run) | yes | not tested | not part of this run |

Blockers for a store package: glibc + ld.so runtime (Debian libs now), Mesa swrast (~150 MB), fonts, file dialog (rfd needs a portal), trademark.

## Other

| app | state | evidence |
|---|---|---|
| Firefox | QEMU green (F3-F8); HP start hangs the device (r4) | gate.sh, reports 22.11. |
| GTK4 hello / glib | 16/3 | tools/gtk/run.sh |
| Wine notepad | red (E2) | r15, wine-gate.sh |
| CLI tools (busybox, bash, python, git, gcc, node, perl, ruby, php, nginx, redis, ffmpeg, vim, htop, ...) | 134 probes, 3 expected red (ip-link, unshare-user, bwrap-run) | apps-gate.sh, apps-expected-red.txt |

## Store packages

Generic packaging toolchain (r431, host part done): registry `tools/linuxapps/store-apps.tsv` (foot, mousepad, galculator, zathura, mpv; category and icon key from `tools/svg/apps.tsv`), builder `tools/linuxapps/lxstore/mkpkgs.py` (apk closure from a prepared Alpine root, shared packages go into the `linuxrt` opk, each app gets a small opk with `braucht=linuxrt`, store.meta, symbol, payload parts + manifest), gate `tools/linuxapps/lxstore/run.sh` 10/0. Measured payload (raw): linuxrt 54 MB, foot 5, mousepad 16, galculator 1, zathura 13, mpv 382 MB. Open: on-device launcher/installer (generic `lxapp`, xfx is still Firefox only), signing + feed publish.


Only Firefox has a store package (`tools/xfx/mkstore.py`, `xfx` is hard wired to firefox). A generic Linux-app package (shared runtime opk + one small opk per app, category and icon from the registry) is roadmap r431.
