# Keyboard layouts, dead keys, compose

The layouts are DATA generated from the xkb data of the build host (`xkeyboard-config` through `libxkbcommon`, rules `evdev`, model `pc105`).
The engine that reads the data is a handful of small kernel modules. Nothing about a layout is written by hand.

## Pipeline

| Stage | Module | What it does |
| --- | --- | --- |
| 1. hardware | `kbd.fi` (`on_code`), `hidin.fi` | PS/2 set 1 bytes or USB HID usages become set 1 scan codes (E0 prefix for the extended keys). Independent of the layout. |
| 2. key position | `kbdlay.fi` `slot_of` | A set 1 scan code becomes a dense key slot (50 slots: the main block, space, the ISO key `<>`, the ABNT2 key 0x73). |
| 3. level | `kbdmap.fi` | Slot + layout + level (`shift`, `altgr`, `caps lock`) becomes an entry: a code point, or `DEAD_FLAG` + dead key id, or 0. |
| 4. state machines | `kbdinput.fi` -> `kbdcompose.fi`, `kbddead.fi` | Compose first, then dead keys; output is up to two code points. |
| 5. output | `kbd.fi` `emit` | UTF-8 octets into the key ring (unchanged below 0x80). |

## The data (`tools/hid/kbdgen.py`)

```
python3 tools/hid/kbdgen.py          write the three files
python3 tools/hid/kbdgen.py --check  exit 1 if a file is stale
```

* `kernel/drv/hid/kbdnames.fi`: the registry. `COUNT`, the names (`us`, `de`, `uk`, `fr`, `es`, `it`, `ru`, `us-intl`, `de-at`, `ch-de`, `pt`, `pt-br`, `pl`, `tr`, `nl`, `ch-fr`, `se`), `id_of(name)`. The id is the index; ids 0..6 are the old numbers and never change, new layouts are appended.
* `kernel/drv/hid/kbdlay.fi`: 8 values per key and layout: plain, shift, altgr, altgr+shift, and the same four with caps lock on. Caps lock is data too (the German `ß` gives `ẞ`, a digit key is unchanged), not a rule in code.
* `kernel/drv/hid/kbdcomb.fi`: the spacing character of every dead key, the dead key combinations (`dead_acute` + `e` = `é`, 821 entries) and the compose sequences (`Multi_key` + two characters, 1152 entries), taken from the xkb compose table of the host.

To add a layout: one line in `LAYOUTS` of `kbdgen.py`, regenerate, add the name to `settings.keyboard.choices` in `locale/*/messages`.

## Dead keys and compose

* A dead key remembers its accent. The next character gives the combined code point (`^` `e` = `ê`, `´` `e` = `é`, `` ` `` `a` = `à`, `~` `n` = `ñ`, `¨` `u` = `ü`).
* Dead key + Space = the accent alone. The same dead key twice = the accent alone. Dead key + a character without combination = accent, then the character. Another dead key = the first accent comes out, the second one waits. Backspace cancels the dead key.
* Compose key: the Menu key (USB usage 0x65), or a tap of the right Ctrl key (press and release without another key in between). Then two characters: `Compose` `'` `e` = `é`, `Compose` `o` `c` = `©`. A sequence that does not exist is dropped silently; a control key (Esc, Enter, Tab) ends compose and is delivered.
* Ctrl, Alt and Super combinations never touch the dead key or compose state.

## Switching

* Ctrl+Alt+L and Win+Space: the next layout (the serial line `kbd: layout=<name>` reports it). A switch drops a pending dead key or compose.
* Settings, page language: the choice list; Apply sets the layout (`SYS_OSUM_KBD` `KB_SET`) and writes it to `/etc/keyboard.conf`.
* Installer: the layout button (cycles, applies at once, so the password fields type with it); the choice is written to `/etc/keyboard.conf` of the system that is copied to the disk.
* Boot: the kernel sets `us` or `de` from `lang=` (round TUERSCHLOSS, `kgui.tastatur_zur_sprache`); then `kbdconf.apply` (called by `glogin`, `login` and `desktop`) reads `/etc/keyboard.conf` and sets the saved layout over it.
* Tray: with `tray_language=1` the language cell shows the layout name in capitals (`DE`, `US-INTL`) while a layout other than `us` is active.

`/etc/keyboard.conf`:

```
keyboard.layout=de
```

## Tests

`bash tools/keymap/run.sh` (host part in seconds, QEMU part with the desktop image):

* `tools/keymap/host.fi` is built from the very kernel modules and dumps every layout x key x level (17 272 entries), every dead key x base character (147 302) and every compose pair (36 481).
* `tools/keymap/oracle.py` compares the dump with libxkbcommon: key states with Shift, AltGr and caps lock, the compose state machine of xkb for the dead keys (both ways: combined and not combined) and for `Multi_key` sequences.
* Counter-probes: a damaged dump and a damaged table must make the oracle fail.
* End to end in QEMU: AltGr+Q = `@` on `de`, `^` `e` = `ê`, `´` `e` = `é`, `` ` `` Space = `` ` ``, AZERTY `a`/`q`, switching by Ctrl+Alt+L, Win+Space, `SYS_OSUM_KBD` and by `/etc/keyboard.conf` at boot.

## Limits

* Compose covers sequences of `Multi_key` + 2 characters (ASCII and Latin-1). Longer sequences and sequences with dead keys inside are not in the table.
* The dead key table covers bases up to U+21FF (Latin, Greek, Cyrillic, extensions).
* Wayland clients (`wl_keytab.fi`, `wayd`) still get the `us` or `de` keymap only; every other layout is sent as `us`.
* `odbd` `input text` types through key codes: a dead key in front of a vowel combines (`^e` types `ê` on `de`).
