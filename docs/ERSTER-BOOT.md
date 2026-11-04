<!-- SPDX-License-Identifier: GPL-2.0-only -->
# First boot -- the first 5 minutes on the HP EliteBook x360 1030 G2

Image: `orientos-usb.img` (GPT + EFI partition, boots under UEFI and BIOS).
SHA256: `df4aa8bfeec83eb48a0c3f02dcc3ee16a90ea590607400cee9f8120408db819c`
Status: image built from origin/main `bbbc77c5` (build commit `61fcf87e`, 23.10.2026 20:34 UTC). The same steps apply to the Dell 9020 (F12 instead of F9).

## Boot loader (since 04.11.2026)

- The default loader is **osboot** (own UEFI/BIOS loader). It boots without a menu: logo + spinner, then the default entry.
- **Esc**, **F8** or **Shift** during the logo opens the boot menu (safe mode, RAM root, command line, diagnostics, Advanced).
- **Limine** stays as the fallback: UEFI `/EFI/limine/BOOTX64.EFI` on the EFI partition, `limine.conf` is still the entry list (osboot reads it). Build the old way with `OSBOOT=0 bash tools/usbimg/build.sh <dir>`.
- An existing Limine installation is switched by the OTA system update after the new kernel is confirmed: `ota system loader osboot`. Back with `ota system loader limine`; `ota system loader status` shows which one is active.

## 0. Before (machine with Linux/Windows, 2 minutes)

1. Checksum: `sha256sum orientos-usb.img` (Windows: `certutil -hashfile orientos-usb.img SHA256`) must give the line above.
2. Write (stick >= 1 GB, completely overwritten):
   - Linux: `dd if=orientos-usb.img of=/dev/sdX bs=4M conv=fsync status=progress` (check `sdX` with `lsblk`!)
   - Windows: Rufus, pick the image, **DD mode** (not ISO mode).

## 1. BIOS on the HP (minute 0-1)

1. Laptop off, stick directly in USB-A (no hub). Optional: LAN dongle (USB Ethernet) or phone tethering over USB -- WLAN does not work yet (Intel 8265, no driver).
2. Power on, press **Esc** at once (startup menu), then **F10** = BIOS setup.
3. Set:
   - **Secure Boot: OFF** (Advanced / Boot Options / Secure Boot Configuration)
   - **SATA/storage mode: AHCI** (not RAID/Intel RST) -- otherwise OrientOS does not see the internal disk
   - **USB/UEFI boot: allowed**; legacy boot does not matter
4. Save and restart (F10), press **Esc** again at once, then **F9** (Boot Device Options) and pick the **USB stick (UEFI)**.
5. Note the BIOS version (main page of the BIOS setup) -- it belongs in the feedback.

## 2. What you should see (minute 1-3)

1. The **osboot logo with a spinner** (about 1 s). Press Esc for the menu. The default entry `OrientOS` boots by itself.
2. Boot lines, then the **sign-in screen**. Account `justin`, start password `startkennwort`.
3. **Desktop with the bar at the bottom.** Mouse/touchpad and keyboard should react. Open the start menu, open the terminal.
4. After about 1 min the hardware report exists (see 4). `hwinv` in the terminal shows the same.

Expected on the HP, NOT an error: **WLAN is missing** (`wlan=8086:24fd intel-8265 driver=none`). **Touchpad (I2C) and keyboard special keys** may not work yet -- bring a USB mouse. An internal disk only appears in AHCI mode.

## 3. If something goes wrong (minute 3-5)

1. **Black screen / hang / panic image:** **photograph** the screen with a phone (whole screen, sharp, no swipe). The place of the error is on it.
2. **Restart (hold power 5 s, switch on again):** the next boot goes into **safe mode** by itself (max. 3 restarts, then halt without reset). "SAFE MODE ..." is shown at the top. State in `/proc/safe`.
3. **Safe mode by hand:** press Esc in the logo window and choose the entry **`OrientOS (safe mode)`** -- no network, audio, extra drivers.
4. More entries for graphics/network problems, try in this order:
   - `OrientOS (safe graphics)` -- simple display path
   - `OrientOS (no network)` -- without network drivers
   - `Hardware diagnostics` -- prints the hardware diagnosis only, no desktop
   - `Command line` -- text console
   - `OrientOS (RAM root)` -- runs from RAM, the stick is not mounted as root
5. **Do not choose:** `OrientOS (install to SATA disk)` -- it installs onto an internal disk. The stick otherwise writes NOTHING to other drives (write lock); installing only works with a typed disk name.
6. If osboot itself does not start: boot the same stick built with `OSBOOT=0` (Limine) and report it.
7. **Repair nothing, flash nothing new** -- feedback first (see 5).

## 4. Hardware report (hwinv)

- At boot `hwinv -d /var/jarvis/hwinv.txt` starts: waits 15 s (USB detection), writes the file, once more after 30 s.
- Content: `hwinv: key=value` -- firmware (UEFI/BIOS), storage kind + verdict (`storage_verdict`; `raid-rst-nvme-hidden` = BIOS is on RAID/RST), GPU, WLAN (chip + driver state), Ethernet, audio, I2C controller, pointing device path, xHCI, USB (keyboard/camera/BT) plus a raw copy.
- **Way back A -- bridge:** with network (cable/dongle/tethering) `jarvisd` signs in at the server; JARVIS reads `/var/jarvis/hwinv.txt` itself (`read`, path is released). This stick image holds no personal bridge data: without a bridge configuration only way B works.
- **Way back B -- stick:** laptop off, mount the stick on another machine (partition 1 = EFI, partition 2 = OrientOS root OFS; Linux cannot read OFS without a tool) -- simpler: a **photo** of the terminal with `hwinv`.
- **Logs on the stick:** `/var/jarvis/panic-N.txt` (N=1..32), `/var/jarvis/boot.log` (after 20 s uptime), `/var/jarvis/hwinv.txt`.

## 5. Feedback (chat)

1. Does it start? Yes/No, up to where (osboot logo / boot lines / sign-in / desktop).
2. Photos (panic image, desktop, `hwinv` output), model + BIOS version, which boot entry.
3. Works: keyboard? touchpad? USB mouse? screen resolution? brightness?
4. Files from `/var/jarvis/` if possible.

## 6. Technical (for developers)

- Build: `OSUM_BUILD_JOBS=6 /root/jarvis/bin/heavy bash tools/usbimg/build.sh <dir>` (cache `/root/.osum-bcache`, ~2-5 min). Default loader osboot; `OSBOOT=0` builds the Limine-only image.
- Gates: `STICK_IMG=<img> KERNEL=<osum.mb> heavy bash tools/ovmfboot/run.sh` (UEFI/OVMF, AHCI+NVMe), `bash tools/bootloader/run.sh`, `bash tools/hwinv/run.sh`, `bash tools/hwinv/guest.sh`, `bash tools/install/acceptance.sh`, `bash tools/hwcheck/run.sh`.
- State data in the kernel: `/proc/safe`, `/proc/firmware`, `/proc/pci`, `/proc/usb`.

## Remote test over USB tethering (interim solution until WLAN works)
1. **Prepare the phone:** Android: Settings > Network > Hotspot and tethering > **switch USB tethering on** (the phone needs mobile data or WLAN for it). Alternative: a USB Ethernet dongle (ASIX AX88772, CDC-ECM) with a LAN cable to the router.
2. **Plug in the cable:** phone/dongle into a USB port of the HP. For the phone, before or after boot -- both work (hot plug is built in).
3. **Wait:** up to 1 minute. OrientOS gets an address itself (DHCP) and `jarvisd` signs in at the bridge (type nothing). DHCP retries after a failure at 5/10/20/40/60 s intervals.
4. **Check:** in the terminal `dhcp status` (shows IP) or the file `/var/jarvis/hwinv.txt` on the stick: line `net: up ip=...`. The phone shows "USB tethering active".
5. **Report:** "it stands" in the chat -- JARVIS then tests remotely (bridge/ODB). If it fails: photo of the screen + `/var/jarvis/*` and the lines `usb: port=... driver=...` (if `driver=none`, name the phone model; Android with "File transfer (MTP)" as the first USB configuration cannot be switched by the driver yet -- switch tethering on before plugging in).

## Stick history (condensed, 23.-24.10.2026; every stick is superseded by the next)

- **Stick 17** (b594cd60): WLAN trace + RX scan + experiments incl. MSI (`fail_exp2=msi`), start menu hover in lists, settings resize without crash, no flicker for scene windows, windows below 120x80 are not built, USB LAN CH336/AX88772. Checklist: `cat /proc/wlan` (all lines), `wlanctl status`, `wlanctl dump`, `lspci`, `cat /proc/drivers`. Unverified on the real 8265. Shut Windows down with `shutdown /s /t 0` first.
- **Stick 16 / GUI fixes** (6e33009f): start menu rows light up under the pointer in "All apps" and search results. Flicker and the settings crash were not reproduced in QEMU.
- **Stick 15** (95cc9d8e): if no ALIVE comes after the timeout the kernel scans the RX buffers raw (`fail_rxs=`, `fail_rx=`, `fail_rxr=` in `/proc/wlan`); `wlanctl status`, `ping`, trace (`fail_trace=`, `fail_series=`, `fail_exp=`), debug tools (`lspci`, `pcicfg`, `regdump`, `prphread`, `wlanctl`), driver store (`drvctl`, `/proc/drivers`) and device classes (`class=` per line).
- **Stick 14** (f69dadbf): secure-boot trace in `/proc/wlan` when the firmware load fails (`fail_trace=`, `fail_series=`, `fail_exp=`); `hdr1=0 hdr2=0` is normal for family 8000; D0/ASPM are not the cause.
- **Stick CH336** (c1f8cf06): CH336 driver aligned to the vendor source; `/proc/drivers` shows `driver=ch336`, `usbnet: ...` and `net: ip= gw=`. Plug the dongle in, cable to the router, boot, then `dhcp`, `ping <router-ip>`. Unverified on the real dongle. Details: `docs/WLAN-CH336.md`.
- **Stick 13** (badf40a6): `lspci [-v] [bb:dd.f]`, `pcicfg <bb:dd.f> [off [len]]`, `regdump <bb:dd.f> <bar> <off> [count]`, `prphread <bb:dd.f> <addr-hex> [count]` (root only), `wlanctl status|reload|dump`. Writes only with `--write` as root. Correction: `drvctl` was missing from stick 10 to 12.
- **Stick 12** (9c417f68): `fail_alive2=` and `fail_pm=` diagnostics, PCI power forced to D0, ASPM off. Shut Windows down fully (`shutdown /s /t 0 /full`).
- **Stick 11** (de07f2da): `ps2maus` module build with ptrcfg/tpcfg, 37 module slots.
- **Stick 10** (71e8521e): driver store in the kernel (`/lib/drivers`, signed packages), `drvctl list|match|install|remove|ban`, `/proc/drivers` with all PCI/USB/ACPI devices (`drv=none` = gaps).
- **Stick 9** (7f8c161e): WLAN 8265 (family 8000) no longer writes APMG registers (0x300C is RELEASE_CPU_RESET there), sets CSR_GIO_REG L0S_DISABLED like Linux. Windows fast start must be off (HiberbootEnabled=1 leaves the card in a residual state): `shutdown /s /t 0`.
- **Stick 8** (a494ab5d): ALIVE wait 2.5 s by tick clock, ALIVE on CSR_INT bit 0, bit 31 or a packet in the RX ring; line `fail_alive=int= fhint= gp1= gp2= cpu1= cpu2= wfp= seen=` in `/proc/wlan`; EC driver + `/proc/hotkeys`, touchpad typing lock, WLAN link watch, PBKDF2 in stages. Check Fn brightness 3x, then `cat /proc/hotkeys` and `cat /proc/backlight`.
- **Stick 7** (6f9bbf42): fixed `fw_load_init err=-45` (bus master set before the firmware load, APMG DMA clock, radio config for family 8000); `fail_hw=`, `fail_fhr=`, `fail_fh=`; wlan.conf as normal user + persistence on the stick EFI partition; Fn brightness keys.
- **Stick 6** (e2bf91e6): `wlan0` network card (task K_WLAN, DHCP from the lease), auto join from `/etc/wlan.conf`, `/proc/wlan` with `net <ssid> ch= sec= rssi=`, `auto=<state> rc= tries= driver=`. Kernel word `noiwl` switches WLAN autostart off.
- **Stick 5** (2380d6c4): 8265 driver with command queue, INIT/RT firmware boot, `/proc/wlan`, settings page **WLAN** writes `/etc/wlan.conf` (0600).
- **Stick 4** (b2937208): touchscreen on devices with several I2C controllers (`/proc/inputdevs`), touchpad gestures + settings page **Touchpad**, corner right-click.
- **Stick 3** (03a803f0): multi-core fix (`/proc/cpus`, boot line `smp: N of M online`), fallback icons, window snap by dragging the title bar, tray chevron flyout, taskbar hover, Windows 11 bar.
- **Stick 2** (30d66381): context menu closes on click-away, USB tethering + bridge auto login, brightness chain (`/proc/backlight`), overlay/fbperf/resize fix, WLAN 8265 driver (sim), touch path.

## What the Boss should photograph

0. **WLAN:** terminal: `cat /proc/wlan` -- photo (phase/err/err_text/fw/nvm/calib, net lines, auto=). Then Settings > WLAN: enter SSID + password, save, `cat /proc/wlan` again -- photo. On a hang/panic restart with kernel word `noiwl` (photo of the boot line).
   - **WLAN persistence (since main 4b852a81):** the saved SSID/password is mirrored by the service `wlanpersist` to the EFI partition (`wlan.cnf`) and restored at boot (only when the root is RAM). Otherwise Settings shows "Saved only until restart".
0b. **Brightness keys (Fn):** press Fn+brightness up/down (3x each), then in the terminal `cat /proc/hotkeys` -- photo. Every key that does not change brightness appears as `ext 0x.. unknown` / `key 0x.. unknown` / `acpi 0x.. unknown` (the real code); also `cat /proc/backlight` (lines `hotkeys`, `acpi.notifies`, `acpi.lastnt`, `ext.last0..3`). Report: does brightness change, and by EXACTLY one step per press?
1. **Overlay:** `Ctrl+Shift+F` -- photo of the whole screen (line `fb_write_mbs`, FPS, CPU, RAM).
2. **Terminal** (Win key, "terminal"): a photo each of the output of
   - `cat /proc/backlight`
   - `cat /proc/frames`
   - `cat /proc/cpuinfo`
   - `cat /proc/inputdevs` (touchpad/touchscreen/I2C controllers: which devices found, driver)
   - `cat /proc/cpus` (multi-core: `cpus_online`/`cpus_madt`, per core `why`/`esr` if one does not come up) and the boot line `smp: N of M online`
   - `cat /var/jarvis/hwinv.txt`
3. **USB tethering:** phone by cable to the HP, switch "USB tethering" on at the phone. Photo of the terminal after `ip` or the line `net: up ip=` and whether `jarvisd` signs in.
4. **Right click:** touchpad right click, click the menu away, right click again -- must open again. Report yes/no.
5. **Touchscreen:** tap, drag, two-finger scroll, long press (= right click). Report what works. **Photo of `cat /proc/inputdevs`**.
5b. **Touchpad settings:** open Settings > **Touchpad** (tap, gestures, scroll, corner right click) -- photo; change one setting each and report whether it works.
5c. **Corner right click:** tap the touchpad bottom right -- context menu? Yes/no.
6. **WLAN (sim note):** the driver is a sim, nothing may connect -- expected. `wlan verbinden <SSID> <password>` -- photo of the output. **Real connecting is not promised.**
7. **Crash/panic:** photograph the screen, then `/var/jarvis/*` as above.
8. **Window snap:** drag a window by the title bar to the left/right/top edge -- preview + snap? Photo.
9. **Tray:** click the chevron (^) at the right of the taskbar -- flyout with an icon grid; hover and right click inside. Photo.
10. **Taskbar hover:** mouse over program icons in the bar -- hover highlight/preview present? Report briefly.
11. **Fallback icons:** programs without an icon of their own (bar, start menu, Alt+Tab, task manager) -- letter tile instead of empty? Photo.
