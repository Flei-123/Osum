# bootreg

UEFI x86_64 app that registers an NVRAM boot entry (`Boot####` + `BootOrder`) for a bootloader already installed on another disk's ESP. Writes NVRAM only, never disks.

Build: `bash tools/bootreg/build.sh <outdir>` -> `<outdir>/bootreg.efi`. Gate: `bash tools/bootreg/run.sh`.

Config `\EFI\BOOT\bootreg.cfg` on the volume bootreg.efi runs from (text, one `key=value` per line, `#` comments):

    slug=<dir>        required, loader lives at \EFI\<dir>\<file>
    name=<text>       boot menu description (default: slug)
    file=<name>       default BOOTX64.EFI
    alt=<dir>         optional, repeatable, extra legacy slugs checked on every disk
    mode=list         optional, print all Boot#### + BootOrder instead of registering

Load options string `list` does the same as `mode=list`.

Serial/console lines: `bootreg: registered|already registered Boot#### <name> -> <path> verified`, `bootreg: NOT FOUND: no <slug> on any disk`, `bootreg: FAILED: <status>`, `bootreg: list ...`.
