# HW-WALK -- real-hardware checks without the Boss at the login screen

The paired bridge helper (`jarvisd`) answers before login. Its rights come only from `/etc/jarvis/permissions.conf`: `command_allowed` programs, `read`/`list`/`write` paths, `input = no`, screenshot only with a local permit. There is no password or UI unlock path.

    bash tools/qa/hw_walk/run.sh [--device ID] [--out DIR] [--groups boot,devices,acpi,usb,network,audio,battery,suspend,access] [--passive]
    python3 -E -s tools/qa/hw_walk/selftest.py

Needs `/srv/bruecke/verwalter.key` on the JARVIS server (header `X-Bridge-Admin`). Exit 0 = no FAIL, 1 = FAIL, 3 = no device online (nothing sent).
Output: `protocol.md` and `protocol.json` in `/root/hwwalk-logs/<time>/`.

Groups: boot (uname, version, watchdog, hang reports, klog words), devices (hwinv, drivers, smbios), acpi (tables, AML namespace, SCI storms, battery/lid/EC/AC), usb (xHCI init, errors), network (WLAN firmware, scan, link, interfaces, gateway ping), audio (HDA controller and driver), battery (charge consistency, thermal zones), suspend (dry run: _S3 object, FADT, lid, charge, no OTA in flight; never sends a suspend), access (counter-proofs).

Counter-proofs (`access`): no/wrong admin key -> HTTP 403 on devices, job, fetch; shells, login programs and relative programs refused; `read` of key/shadow/passwd refused; `write` outside `/tmp`+`/var/jarvis` refused; `input` refused; `cat <secret>` through the command channel must be refused (FAIL on a helper older than jdargs).

## Finding fixed here
`command_allowed` programs `cat head tail wc grep ls du find` used to read ANY path (`/bin/cat /etc/jarvis/device.key` returned the device key). `kernel/app/jarvisd/jdargs.fi` + `arg_paths_ok` in `jdcmd.fi` now check every file argument against `read` (cat/head/tail/wc/grep) or `list` (ls/du/find): absolute, clean, listed. Gate: `tools/bridge/run.sh` section 9d with counter-proof (`read = /`).
