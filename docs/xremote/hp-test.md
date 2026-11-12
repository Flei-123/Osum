# Test X-Remote on the HP (Boss guide)

1. **HP:** Update/Apply the next feed stand (Boss only). It must contain the `xremote` package (see "Feed stand" below).
2. **HP:** Open the Store, install **Remote control**. Then add the service line once (the HP inittab is from install time and the update does not touch it): Terminal -> `echo "xremote:grafik:respawn:/bin/xremoted" >> /etc/inittab`, then reboot.
3. **HP:** Settings -> search "remote desktop" -> switch **Allow remote control** on, confirm the system dialog. Wait about 10 s: Status turns "On", **ID** and **Password** appear on the page.
4. **Windows:** start `freeviewer.exe` (0.30.0, `/root/projects/freeviewer/dist-0.30.0/`), "Connect to a computer", enter ID + password.
5. **Check:** picture, mouse, keyboard, wheel, clipboard, both monitors (if two heads), emergency stop `Super+Esc` and the switch off.

## Feed stand (Boss runs this, nothing is published by the worker)
`bash tools/ota/xrstand.sh <stand-dir>` copies `xremote-0.opk` next to the other packages of the stand; then publish as usual.

## Troubleshooting
- Status "App not installed": package missing in `/apps/xremote.osp`.
- Status stays "Starting"/nothing: `/bin/cat /run/xremote.info` (service=), `/bin/cat /run/xremote.state` (id, status, peer), `/bin/cat /var/log/xremote.log` (host log).
- No ID: no network right. `/bin/apprights get xremote` must list `net`; the package INFO has `perm=net`, granted by the signed install.
- Service never runs: `/bin/ls /bin/xremoted` and `/bin/cat /etc/inittab` must show the `xremote` line.
- Switch refuses: `act call settings.get key=remote.enabled`.

## Capture and input on the HP (open)
Not verified on the real Intel framebuffer (HD 620): the host uses `osum_shot` (grab of `/dev/fb`, per-head rects) and `osum_tipp`. Proven only in QEMU (gate tools/xremote/run.sh). First real-hardware run is this test; report what step 5 shows.
