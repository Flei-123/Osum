# Surface Laptop 4 live-stick test: WLAN + USB network (LW-9)

Status: preparation only. Nothing here was run on the Surface. All lines below are what the kernel is coded to print.

## Before booting
- Build the stick: `tools/usbimg/build.sh` (BIOS + UEFI, Limine).
- Surface UEFI: Secure Boot = None. Boot from USB: hold Volume-Down while pressing Power.
- Use an external USB keyboard.
- Put the Intel firmware file on the stick root: `/lib/firmware/intel/iwlwifi/iwlwifi-QuZ-a0-hr-b0-77.ucode` (or the Qu-c0 / Qu-b0 name; the kernel tries all candidates and logs each miss).

## Boot words (Limine cmdline)
- default: read-only probe + firmware lookup + parse. No device write.
- `iwlboot`: also copies the image to DMA, powers the chip up, kicks the firmware, waits for ALIVE. First real-silicon step; expect it to fail at first, the log shows where.
- `iwlfwtest`: synthetic AX201 lookup (works without the device, used by the QEMU gate).

## Lines to report back
- `iwl: hw_rev=0x... rf_id=0x... id=8086:a0f0 mac=... rf=... bdf=...` (probe)
- `iwl: fw file=<path> size=<n>` or `iwl: fw missing <path>` / `iwl: fw no file`
- `iwl: fw rc=<n> ver=<n> lmac=<n> umac=<n> paging=<n>`
- `iwl: boot rc=<n>` (only with `iwlboot`; negative = error code, -30 timeout, -31 HW error, -32 SW error)
- USB tethering phone: `usb: rndis <mac>` or `driver=ecm|ncm`, then `usbnet: rndis link up`, `usbnet: rndis keepalive ok`
- Unplug: `usb: unplug port=...` then `usbnet: detached`
- CH336 dongle 1A86:5394: `usb: ch336 info=<8 octets>`, `usb: ch336 <mac>` or `usb: ch336 failed step=N` (framing is a hypothesis)

## How to read the output without a screen log
- ODB serial/agent (`odbc`), or photograph the boot console.
