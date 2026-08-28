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

Every path and every program name in the running system is English.

**The four German configuration paths**, renamed by `b5c796e`
(the round `rename-etc` wrote the rule down; its branch was never
merged, see the note at the end):

| was | is |
|---|---|
| `/etc/hintergrund` | `/etc/wallpaper` |
| `/etc/schirm.conf` | `/etc/display.conf` |
| `/etc/zeit.conf` | `/etc/time.conf` |
| `/etc/netz.conf` | `/etc/network.conf` |

**The three German program names**, renamed by round LOOK's addendum.
Round `rename-en` (`d89f512`) had renamed `suchen`, `starter` and
`wigdemo` and left these three alone, because four rounds were editing
them at the same time and a rename that collides with four merges is a
rename nobody thanks you for. The file name, the `/bin` path, the
argv[0] the kernel passes and the prefix the program writes on the
serial line are ONE name and all four moved together:

| was | is |
|---|---|
| `kernel/user/leiste.fi`, `/bin/leiste`, `leiste: …` | `kernel/user/taskbar.fi`, `/bin/taskbar`, `taskbar: …` |
| `kernel/user/schreibtisch.fi`, `/bin/schreibtisch`, `schreibtisch: …` | `kernel/user/desktop.fi`, `/bin/desktop`, `desktop: …` |
| `kernel/user/einstellungen.fi`, `/bin/einstellungen`, `einstellungen: …` | `kernel/user/settings.fi`, `/bin/settings`, `settings: …` |

A module name in Firn is also a SYMBOL PREFIX, so `leiste__paint`
became `taskbar__paint`. `tools/desktop/run.sh` proves the taskbar is a
ring-3 program by looking for exactly those symbols in the kernel image
and failing if it finds them; a counter-test that looks for a symbol
which no longer exists always passes and tests nothing, so it moved
with the name.

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

There is ONE piece of backwards compatibility in the whole tree, and it
is named rather than hidden: `wlibc.timezone_read()` reads
`/etc/time.conf` and, if that is not there, `/etc/zeit.conf`. A machine
that silently loses its timezone on an upgrade is not an upgrade. It is
a READ, never a write — nothing in the system creates the old name — and
it is the only such fallback. Everything else is a rename and nothing
else: the system has not shipped, and supporting two spellings of the
same file would have made this rule unenforceable on the first day.

## The branch `rename-etc` must NOT be merged

It was cut before `rename-en` and before the seventeen branches that
became `mergeline`. `git diff --name-status -M mergeline..rename-etc`
is a list of BACKWARDS renames — `assets/apps/launcher.osp` →
`suchen.prog`, `REMOVE-FROM-FIRN.md` → `ENTFERNEN-AUS-FIRN.md` — and it
deletes `LICENSE.MIT`, `THIRD_PARTY.md`, `assets/icons/LICENSE.lucide`
and the whole of `assets/netview/`. Merging it would undo this document.

Its one piece of real content, commit `283b378`, is the four `/etc`
paths above, and that content is already in the tree: `b5c796e` applied
it mechanically to the finished files instead of replaying a diff that
would have conflicted in every one of them. The branch can be deleted.
