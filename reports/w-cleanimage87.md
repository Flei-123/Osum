# w-cleanimage87 -- dev/test parts in the standard image

Profiles: `IMAGE_PROFILE=release` (= `public`, the download/installed system) and `IMAGE_PROFILE=dev` (= `personal`, all acceptance runs and the HP stick). Unset still means dev so the ~40 existing gates keep signing in as `justin`; every product path (tools/usbimg/release.sh public, stable feed) builds release. Single registry of what is dev-only: `tools/usbimg/devparts.conf` (prog / file / entry / word), read by `build.sh`, `limine_release.py` and `pubcheck.py`.

## Inventory

| Item | Where found | Decision |
|---|---|---|
| `widgetdemo` + Widgets app (`/apps/widgets.osp`) | PROGS, assets/apps/widgets.osp (start -> /bin/widgetdemo) | OUT of release (devparts prog) |
| `bench` (in-OS benchmark) | PROGS, PFLICHT | OUT of release |
| `dbgsrv` (debug HTTP service, port 8765) | PROGS; inittab + `/etc/dbgsrv.token` only when DBGSRV=1 (default 1 on dev, 0 on release) | binary OUT of release; service dev only |
| `regdump`, `prphread`, `pcicfg` (register pokers) | PROGS | OUT of release |
| `odbd` ODB agent (COM2 polling), `/etc/odb.conf`, `/etc/odb.token` | only with ODB=1 | already opt-in; release check forbids files and boot word `odb` |
| Developer overlay Ctrl+Shift+F / `debug.mon` | kernel/user/settings/setpages.fi, /etc/debug.mon | stays (runtime switch, off by default, file not shipped); release check forbids `/etc/debug.mon` |
| `uitrace` / `/etc/uitrace`, `/etc/uiblink` | build.sh UITRACE=1 / UIBLINK=1 | already opt-in; release check forbids files |
| jarvisd devmode (`run ok-dev`, `screenshot = always`, `input = yes`) | assets/jarvis/rechte-hp-dev.conf, republish-hp.sh HP_DEV=1 | dev feed only; build.sh already refuses these in public; stays |
| `jarvisctl dev on/off`, one-shot permit `jarvisctl screenshot` | kernel/user/ctldev.fi | stays (inert without `devmode = yes` in permissions.conf; no server in release) |
| JARVIS Mini, `jmlink`, `snip`, `snipt`, `hotkeyd` Ctrl+Alt+J | personal-only already | already out of public; added to release file check |
| OTA channel `dev` | tools/ota/publish_system.py (stable/dev/test) | stays (feed side, signed); release image defaults to stable |
| `shot: pid=` lines | kernel/ui/shot.fi say() | serial (COM1) only, not on screen; stays |
| `crashrestart`, `safeauto`, `wmplug` boot words, install-to-SATA entry | personal menu only | already dev only |
| Measuring boot entries (measuring board `tafel herz`, network interrupt pin / polled, framebuffer uncached / write-back, status lamp, apps on core 0, wrong GS base, Network self-test, Vector unit check) | limine.conf Advanced/ | OUT of release menu; words `tafel herz` stripped from kept entries |
| Boot entries safe mode / safe graphics / no network / Command line / Hardware diagnostics / English / 2560x1440 / 3840x2160 / Diagnostics, then desktop / USB diagnostics / Graphics survey | limine.conf | bleibt (support) |
| Test accounts | build.sh: dev `root`/`osumroot`, `justin`/`startkennwort`; release root locked + `live`/`live` autologin, installer replaces with owner account | no `admin` account exists anywhere; release check allows only root + live |
| Dummy device key | `/root/abbilder/dummy-device.key` only passed to publish-dev | not in image; build.sh refuses JARVIS_DEVICE_KEY / JARVIS_CONF / PW_JUSTIN in release |
| Kernel console mirror | cmdline `console=ttyS0` only in "Command line" entry | bleibt (user shell entry) |
| tools dependencies | build.sh needs /root/stones, /root/bbdyn (dev only), LIMINE_DIR | dev-only inputs are skipped in release (STONES/BBSH only for personal) |

## Done
- Profile aliases dev/release, devparts registry, release filtering of PROGS and boot menu, `pubcheck.py` extended (files, entries, words), gate `tools/cleanimage/run.sh` with counter-proof (dev image is rejected).
- Reset engine `resetsys` (`settings [--ja]`, `system --name N --confirm RESET [--ja] [--reboot]`), factory copies in `/system/factory`, gate `tools/resetsys/run.sh`.

## Open
- Settings page System > Recovery (buttons + RESET field + progress) and bus actions `settings.reset.*` (critical).
- Reset boots into the existing login (the new owner account is created by `resetsys`); a full welcome/OOBE wizard for an empty system is not built.
