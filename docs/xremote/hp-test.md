# Test X-Remote on the HP (Boss guide)

1. **HP:** Update/Apply the feed stand that carries this build and the `xremote` package (Boss only, see "Feed stand").
2. **HP:** Open the Store, install **Remote control**. Then sign out and sign in once (or reboot): sign-in starts the service, no inittab edit needed.
3. **HP:** Settings -> search "remote desktop" -> switch **Allow remote control** on, confirm the system dialog. Wait about 10 s: Status turns "On", **ID** and **Password** appear on the page.
4. **Windows:** start `freeviewer.exe` (0.30.0, `/root/projects/freeviewer/dist-0.30.0/`), "Connect to a computer", enter ID + password.
5. **Check:** picture, mouse, keyboard, wheel, clipboard, both monitors (if two heads), emergency stop `Super+Esc` and the switch off.

## Feed stand (Boss runs this, nothing is published by the worker)
1. Make the unpublished signed stand: `DRY_OUT=/root/xremote-stand bash tools/ota/publish-hp.sh - "xremote test" --dry`
2. Add the package: `bash tools/ota/xrstand.sh /root/xremote-stand` (copies `xremote-0.opk` next to the other packages of the stand)
3. Publish as usual (`tools/ota/publish.sh --stand /root/xremote-stand --apply`).

## How the service starts
`glogin` starts `/bin/xremoted` as root at sign-in (next to `wlanpersist`), only if no `xremoted` process exists. Images that still carry the `xremote:grafik:respawn` inittab line keep working (guard prevents a second copy). The HP inittab (install time) has no such line and the update does not touch it; that no longer matters. Gate: `tools/xremote/autostart.sh`.

## Troubleshooting
- Status "App not installed": package missing in `/apps/xremote.osp`.
- Status stays "Starting"/nothing: `/bin/cat /run/xremote.info` (service=), `/bin/cat /run/xremote.state` (id, status, peer), `/bin/cat /var/log/xremote.log` (host log).
- No ID: no network right. `/bin/apprights get xremote` must list `net`; the package INFO has `perm=net`, granted by the signed install.
- Service never runs: `/bin/ps` must list `xremoted`; if not, sign out and in; serial/klog line `glogin: xremoted pid=`.
- Switch refuses: `act call settings.get key=remote.enabled`.

## HP facts read on 12.11. (read only, nothing changed)
- Build `e9875913` (before this change: no Settings page, no glogin start). `/bin/xremoted` is in the image.
- `/proc/gpu`: one head, kind `fb`, `vram_total_bytes 8294400` = 1920x1080x4 -> plain linear 32-bit framebuffer. `/proc/intelgpu`: `off` (no Intel driver active). `/dev/fb` exists.
- `/etc/inittab` has only `sh`, `hwinv`, `dbgsrv` (no `xremote`, no `vaultd`).

## Capture and input on the HP (open)
Not verified on the real Intel framebuffer (HD 620): the host uses `osum_shot` (grab of `/dev/fb`, per-head rects) and `osum_tipp`. Proven only in QEMU (gate tools/xremote/run.sh). The HP framebuffer is the same plain linear kind QEMU uses, so a working grab is expected; the first real run is this test; report what step 5 shows.
