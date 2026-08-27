# Naming: the structure is English, only the surface is translated

This is a rule of the owner of the project, and it is not a matter of
taste. It is written down here because it was broken twice already and
because two repositories outside this one (OrientOS, and every round
that adds a configuration file) depend on it.

## The rule

**Paths, directory names, file names, configuration keys, command names
and device names are ALWAYS ENGLISH and are NEVER localized.**

**Only the DISPLAY TEXT of the user interface is translated** — window
titles, button captions, menu entries, messages to the user.

## Why

Windows is the negative example. `C:\Program Files` is shown in a German
Explorer as `Programme`, and there is no such directory: the name on the
screen and the name you have to type are two different things. Every
script, every tutorial and every path a user copies out of a dialog then
lies to somebody. A shell that cannot `cd` into a folder the file
manager just showed you is not a translation, it is a trap.

The structure of a system is an interface for programs. Programs do not
read the display language. The moment a path depends on the locale, the
same system is two incompatible systems.

## What that means in practice

| always English | may be translated |
|---|---|
| `/etc/wallpaper`, `/etc/display.conf` | `Hintergrundbild`, `Bildschirm` on a settings page |
| `/bin/launcher`, `/bin/locate` | the launcher's window title |
| `edge=right` in `/etc/taskbar.conf` | the drop-down row that sets it |
| `/apps/explorer.osp/` | the bundle's `name=` in `INFO` |
| `bg=`, `panel=`, `btn=` in `/etc/theme` | — |
| `/dev/fb`, `/dev/hda` | — |

The `INFO` file of an application bundle is the seam: its `name=`,
`info=` and `keys=` are display text and are translated, the bundle's
directory name and its `start=` path are not.

## The state of the tree

Every path in the running system is English. The four German ones were
renamed in the round `rename-etc`:

| was | is |
|---|---|
| `/etc/hintergrund` | `/etc/wallpaper` |
| `/etc/schirm.conf` | `/etc/display.conf` |
| `/etc/zeit.conf` | `/etc/time.conf` |
| `/etc/netz.conf` | `/etc/network.conf` |

Unchanged because they were already English or are the Unix names:
`/etc/passwd`, `/etc/shadow`, `/etc/inittab`, `/etc/resolv.conf`,
`/etc/hosts`, `/etc/group`, `/etc/schemas`, `/etc/theme`,
`/etc/taskbar.conf`.

Two things are deliberately NOT covered by this rule, and both are
outside the running system:

* **Test fixtures.** The images the acceptance suite builds contain
  `/data/bilder/`, `/data/notizen/`, `apfelstrudel.txt`. They are data a
  test writes and reads again, never anything a user sees or types, and
  renaming them would churn a few hundred assertions for nothing.
* **Identifiers inside the source.** Local variables and comments are
  German in most of this repository. That is the language the code is
  written in; it is not an interface.

There is no backwards compatibility for the old names anywhere. The
system has not shipped, so a rename is a rename — supporting two spellings
of the same file would have made the rule unenforceable on the first day.
