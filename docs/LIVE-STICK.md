# Round LIVE — the public stick is a live system (25.09.2026)

## What was wrong

There was ONE stick build (`tools/usbimg/build.sh`) and it was copied by hand
to `store.fleitec.com/abbilder/orientos-usb-neuestes.img.xz`, the public
download. Read back from that file (`orientos-usb-20260925-821de79-mbr`):

    /etc/passwd   root:x:0:0:root:/:/bin/sh
                  justin:x:1000:1000:Justin:/users/justin:/bin/sh
    /etc/shadow   root   -> PBKDF2 of "osumroot"
                  justin -> PBKDF2 of "startkennwort"
    /users/       root/ justin/ justin/config/

The passwords were the build defaults, not Justin's real one, and the bridge
file was the factory one (everything off). But a download for everybody
carried a personal account with a password printed in the build log, and the
next `JARVIS_CONF=...` for Justin's own machine would have gone public too.

## The two targets

| | `IMAGE_PROFILE=personal` (default) | `IMAGE_PROFILE=public` |
|---|---|---|
| for | Justin's test stick, every acceptance run | the download |
| accounts | root / osumroot, justin / startkennwort | root **locked**, live / live |
| sign-in | the normal screen | `live` signed in automatically, once per boot |
| bridge | `JARVIS_CONF` if given | factory file; `JARVIS_CONF` refuses the build |
| screen lock | after 300 s | off (`leerlauf=0`) |
| menu | unchanged | 1 `OrientOS Live (try without installing)`, 2 `Install OrientOS` |
| taskbar | unchanged | `pins=installer,explorer,terminal,settings` |
| published by | `tools/usbimg/release.sh personal` → `/root/abbilder` (not served) | `tools/usbimg/release.sh public` → `/srv/store/abbilder` |

The default stays `personal` because some forty acceptance runs in this tree
build through `build.sh` and sign in as `justin`. The public image is
protected by the one way it is published: `release.sh public` builds with
the public profile from a clean tree, runs `tools/usbimg/pubcheck.py` on the
FINISHED image (the root.img the stick boots and the copy on partition 2),
runs `tools/usbimg/live.sh`, and only then copies it. `build.sh` itself runs
`pubcheck.py` on every public build and stops if it fails.

## Why it is "live"

The root file system is a boot module (`module_path: boot():/root.img`,
`modfs`): Limine loads it into RAM through the firmware and the kernel works
on that copy. Nothing the session writes reaches the stick or a disk, and it
is gone after a restart. That was already so; `live.sh` now measures it.

`glogin` reads `/etc/autologin` (only on the public image), checks that the
name is a real account with uid >= 1000 and a shadow entry, leaves
`/run/autologin.done` (in RAM) and starts the desktop as that user. Signing
out brings the normal sign-in screen (live / live), not a loop.

## What `tools/usbimg/live.sh` measures

1. `pubcheck.py`: only root (locked) and live, only their homes, bridge off;
   the menu entries, the pin, no screen lock.
2. Entry 1 under UEFI with an empty 256 MiB disk: `glogin: autologin live`,
   `uid=1000`, `desktop: ready`, no sign-in screen, a photo — and afterwards
   the stick AND the disk are bit for bit unchanged (sha256).
3. "Command line" twice on the same stick copy: a file written and read back
   in boot 1 is gone in boot 2; the stick is unchanged.
4. Entry 2: the installer opens on the live desktop, sees `/dev/hda`, and
   writes nothing without the two confirmations.

The installation itself is `tools/install/abnahme.sh` with `BAU=` a public
build (`SCHNELL=1`): install onto an empty disk, boot it through OVMF without
the stick, a file survives a restart.

## Known limits (roadmap)

* The installed system boots without `anmeldung` (the installer writes its
  own limine.conf, `kernel/user/installer.fi` `lim_text`) and without `usb`,
  `hidgen`, `nic`: no sign-in, and on real hardware no USB keyboard. The
  installer also asks for no account — the installed disk inherits `live`.
* Two programs loaded at the same moment collide in the kernel
  (`elf: refused, reason 13  segment past the end`). The live sign-in waits
  3 s and retries; the kernel bug itself is open.

## The watchman

`release.sh` is the one way into `/srv/store/abbilder`, but a folder cannot
refuse a `cp`. Half an hour after the first public live image went up, a
personal test stick of another round was copied there by hand.
`tools/usbimg/guard.sh` runs on every change of the folder (systemd
`osum-abbilder-guard.path`) and every ten minutes (`.timer`): every stick
image is unpacked and checked with `pubcheck.py`; one that is not fit is
MOVED to `/root/abbilder` (not served), and `orientos-usb-neuestes` is
pointed back at the newest fit `*-live` image. Log:
`/var/log/osum-abbilder-guard.log`. Personal test sticks are handed to
Justin directly (chat download), never through the store.
