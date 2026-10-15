# Encrypted root: install + boot prompt (K-019)

Install
- GUI: installer window, whole-disk tab: tick "Encrypt the disk", type the passphrase twice (8-100 printable ASCII characters). The install button stays off until both match.
- CLI: `install /dev/hda --ja --crypt <passphrase>`.
- Layout on the root partition: 8 header sectors (OSUMCRYPT, Argon2id t=2 m=32MiB p=4, one key slot) + XTS-AES-256 data. Tweak = sector number relative to the data start.
- "Install beside" (dual boot) does NOT encrypt (box is hidden on that tab).

Boot prompt (kernel/crypto/cryptboot.fi)
- Appears when the root partition carries the OSUMCRYPT header. Five tries, `*` echo; then no mount.
- Test rig only: `kryptopw=<pass>` on the kernel command line skips the prompt.
- KEYBOARD: the prompt polls the PS/2 (i8042) port only. A laptop's built-in keyboard is PS/2 on almost every model (also on USB-less firmware emulation); an external USB keyboard is NOT read before the root mount (xHCI HID starts later). With a USB-only keyboard the prompt cannot be answered -> use the built-in keyboard or enable "legacy USB keyboard" (SMM emulation) in the firmware.
- The prompt uses the kernel keymap (US). Only ASCII passphrases are accepted by the installer for that reason; y/z are swapped on a German layout.

Lost passphrase = lost data (no recovery slot yet).
