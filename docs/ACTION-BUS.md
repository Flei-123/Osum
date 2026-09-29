# The action bus (orient-bus) — concept and prototype

Status: **concept + working prototype** (round ACTION-BUS, branch
`action-bus`), extended in round ACTION-BUS-2 (branch `action-bus-2`) by
AB-003 attested caller identity, AB-005 settings on the bus, AB-008 the
cli/file adapters and AB-016 the bus in the shipped image, and in round
ACTION-BUS-3 (branch `action-bus-3`) by AB-005b the settings window as a
client, AB-006 "what may which app", AB-008b the foreign-window layer
(`keys`/`ui` adapters) and AB-009 "dry run first" for Jarvis, and in round
ACTION-BUS-4 (branch `action-bus-4`) by AB-002 the blocking receive and
AB-005c the remaining settings pages on the bus. Everything
marked *built* runs in `tools/actionbus/run.sh` (test guests) or
`tools/actionbus/image.sh` (the real stick image, booted like the Dell);
everything marked *planned* is a roadmap item (section 12), not a promise
that it exists.

---

## 0. In one paragraph

Every app declares in its package what it can **do** — `notes.add(text)`,
`player.pause()`, `mail.send(to, text)` — with typed arguments, a
description a language model can read without training, and a **level**
(read / write / critical). A broker, `orient-bus`, collects these
declarations and is the **only** door through which anything is invoked:
other apps, scripts, the shell, voice and Jarvis all use the same client
and the same checks. Jarvis is a client like any other and has no side
entrance. Critical actions always need a human "yes", every change is
logged before it happens, and changes can be undone. Programs that were
not built for OrientOS — Linux programs, Windows programs under
Wine/Proton — keep running exactly as before; they become steerable
through wrapper manifests and adapters, never by being forced to change.

## 1. Goals and non-goals

Goals

1. **One catalogue** of what the system can do, machine-readable, typed,
   described — the same for a human, a script and an AI.
2. **One door.** No caller has a private path. A rights check that can
   be bypassed is decoration.
3. **The user stays in charge**: levels, confirmations, grants that end,
   an audit log, undo, a dry run for every action.
4. **Nothing breaks.** Foreign programs run unchanged; the action layer is
   added *around* them.
5. **Cheap for app authors**: a text manifest and three bus calls. Rights,
   confirmation, logging and undo bookkeeping are the broker's job, done
   once for all apps.

Non-goals

* Not a general IPC system. Streams, shared memory and the clipboard stay
  on the kernel bus (`docs/SYSTEMBUS.md`); the action bus sits on top of it.
* Not a replacement for the UI. An action is what an app *offers*; how
  its window looks is unaffected.
* No scripting language of its own. Automations (section 9.3) are
  sequences of the same calls.

## 2. Architecture

```
  shell / script / voice / Jarvis bridge / other apps
                      │   /bin/act  (or the same frames from any program)
                      ▼
            ┌────────────────────┐      /apps/<app>.prog/ACTIONS
            │   orient-bus       │◄──── /etc/actions.d/*.actions (wrappers)
            │   (/bin/orientbus) │      /etc/orientbus/policy
            │  catalogue · rights│───►  /var/log/orientbus.log (audit)
            │  confirm · undo    │
            └─────────┬──────────┘
      kernel service  │  a.<app>   (A_ROOT: only the broker gets through)
                      ▼
      native app (notes)   ·   adapter (cli / file / ui / keys) → foreign program
```

**Why a broker in Ring 3 and not a kernel feature.** The kernel bus
already provides what cannot be done in user space: named services, a
sender pid/uid that the *kernel* stamps into every message, and an access
rule checked before delivery. Everything else — manifests, types, rights
policy, confirmation, undo — is policy, and policy belongs in a process
that can be replaced, updated and restarted. `docs/ASSISTENT.md` § 1
("no kernel code belongs to the assistant") applies literally: nothing in
the kernel exists because of Jarvis.

**Why the checks cannot be skipped.** A provider registers its service
`a.<app>` with `A_ROOT`. The kernel refuses delivery to it from any
process that is not uid 0 — so every call an app receives has passed the
broker. An app does not have to trust its callers or check anything
itself.

**Why not D-Bus.** D-Bus is an IPC system with typed signatures and
XML introspection; authorization lives in a separate daemon (polkit), and
descriptions for humans or models are not part of it. Building an
action catalogue on D-Bus means re-inventing everything in sections 3–5
anyway, on top of a daemon this system does not have. D-Bus *does* matter
as an adapter target for Linux programs (section 7).

## 3. The manifest

*Built* (parser in `kernel/user/orientbus.fi`, second reader for the host
in `tools/actionbus/manifest.py`; both must agree, the test compares
them field by field).

A package ships `ACTIONS` next to `start`; after installation it is
`/apps/<app>.prog/ACTIONS`. One item per line, first word = kind, the
quoted rest = description:

```
manifest 1
app notes
title "Notes"

action notes.add write "Add a note at the end of the list"
  arg text string required "The text of the note, one line"
  returns count int "How many notes there are afterwards"
  dryrun
  undo notes.remove

action notes.clear critical "Delete ALL notes"
  returns deleted int "How many notes were deleted"
  dryrun

event notes.changed "Sent after every change of the list"
  field count int "How many notes there are now"
```

Rules

| rule | why |
|---|---|
| names are `<app>.<verb>`; an app may only declare in **its own** namespace | a wrapper called `evil` must not publish `notes.clear` (tested: refused) |
| types: `string`, `int`, `bool` | enough for the prototype; `enum`, `path` (a handle, not a string), `datetime`, lists are planned |
| level: `read`, `write`, `critical` | the input of the rights decision (section 5) |
| `dryrun` | the app can *simulate* the action; otherwise the broker answers a dry run itself |
| `undo <action>` | the **manifest** fixes which action reverses this one, in the same app; the app only supplies its arguments at run time |
| unknown words are skipped with a warning; a broken line rejects the whole file | newer manifests on older brokers; never half an app |

**Line format, not JSON or TOML.** The broker is written in Firn without
an allocator; a line format is 200 lines to parse and impossible to
mis-nest. JSON is what goes *out* (section 4, `describe`).

**Mandatory base.** Every `.opk` must carry a manifest — at minimum
`manifest 1` + `app <name>` (zero actions is valid). *Planned:*
`pkg/opk.py bauen` runs `manifest.py check` and refuses to build
otherwise; the store refuses packages without one. The actions
themselves stay optional.

**Versioning.** `manifest 1` is the format version. Actions are
append-only: a changed meaning gets a new name (`mail.send2`), an old one
may be marked `deprecated` (planned). `describe` reports the bus version.

**Machine-readable for AI.** `act describe` returns the catalogue as JSON:
name, app, level, description, `needs_confirmation`, `dry_run`, `undo`,
`available` (is the provider running), arguments with type/required/
description, returns, events with their fields. That is the same shape as
an MCP tool list, so Jarvis (or any agent) can turn it into tools without
any per-app knowledge.

## 4. The bus API

*Built.* The broker is the kernel service `orient.bus` (anyone may call);
events come from `orient.evt` (published by the broker only).

**Frames.** A kernel bus message carries 64 octets. An action message is
a sequence of frames: magic `0xA7`, kind (request/reply/event), flags
(first/last), payload length, a 32-bit id, 56 octets payload. Reassembly
is keyed by *(kernel-stamped pid, id, kind)*, so one sender cannot
complete or poison another's message.

**Payload** is text, one item per line — the same text the human sees,
the log stores and a model reads:

```
call notes.add          verb + target
@client=jarvis          meta lines start with '@'
@dry=1
text=hello world        arguments, key=value
```

Verbs: `list`, `describe [prefix]`, `call <action>`, `confirm <no|last>`,
`reject <no|last>`, `undo`, `grant <client> <glob> <read|write> [s]`,
`stat`; from providers `hello <app>`.

Replies: `ok` + result lines · `err <code> <detail>` · `confirm <no>
<action>` + level + description. Codes: `unknown_action`, `bad_arg`,
`missing_arg`, `denied`, `app_not_running`, `timeout`,
`audit_unavailable`, `nothing_to_undo`, `too_long`. `act` exits 0 / 1 /
2 (confirmation needed) / 3 (no broker).

**Replies go to `r.<pid>`**, a reply box the client registers; the broker
*derives* the name from the kernel-stamped pid, so nobody can direct
replies to someone else.

**Provider binding.** A provider registers `a.<app>` (A_ROOT) and says
`hello <app>`. The broker pings `a.<app>` — the kernel routes that ping
to the real owner — and binds the pid that answers. From then on replies
and events for that app are accepted only from that pid; a second
process cannot even register `a.notes` (tested).

**Events.** Declared in the manifest; sent by the bound provider; checked
and republished on `orient.evt` with `@app=`. `act watch` subscribes. The
broker itself publishes `bus.confirm_needed` so a dialog can appear.

**Client:** `/bin/act` — `list | describe | call | confirm | reject |
undo | grant | stat | watch | bench`. `act call notes.add "text=hi"
--as jarvis --dry`.

## 5. Rights

*Built*, except where marked.

### 5.1 The decision

| | user (human at the device) | agent / app / script without grant | with grant | deny rule |
|---|---|---|---|---|
| read | allow | allow | allow | **deny** |
| write | allow | **ask** | allow | **deny** |
| critical | **ask** | **ask** | **ask** — critical is never granted | **deny** |
| dry run | allow | allow | allow | **deny** |

A dry run executes nothing and reports the decision that *would* apply
(`decision=ask`), so an agent can plan honestly.

### 5.2 Clients and identity — *built (AB-003)*

The **kernel** names the client. Every task carries an ORIGIN label in
its task record (`sched.T_ORIGIN`, rules in `kernel/sched/origin.fi`):

* a program started from an app bundle (`/apps/<name>.osp/...` or
  `.prog/...`, the path `execve` resolved; for a `#!` file the script)
  gets `app:<name>` — unless the bundle carries a **root-owned `SYSTEM`
  file**: those are the bundles the image ships (terminal, explorer,
  settings …, written by `tools/k15/bundle.py`); they are the user's own
  tools. `opk` never links a file called `SYSTEM` into `/apps`, so a
  package cannot claim it;
* `jarvisd` marks every command it runs `jarvis` before `execve`;
* adapters run their programs as `compat:<app>` (section 7);
* the label is **sticky**: fork, clone, execve, spawn hand it on, nothing
  clears it, a process may only set its *own* label and only while empty
  (`SYS_OSUM_ORIGIN` 1990: `(0,pid,buf)` read, `(1,label,len)` set). An
  app that runs `/bin/act`, or copies it to /tmp and runs the copy, stays
  the app. Because a label only narrows and pids are never reused, the
  broker's lookup after receiving a message cannot be raced.

**The user** is an unlabelled sender whose uid is 0 *or the uid of the
person who signed in* (round ACTION-BUS-3). On a real device `glogin`
drops the session to the person's own uid (justin, 1000) after entering
it in the kernel (`SYS_SPERRE` op 7, root only, once); until this round
only uid 0 counted, so the one human at the machine could neither
confirm nor grant. Another person's uid (mara, 1001) is still not the
user (tested with `su`, `tools/actionbus/setsess.c`).

The broker resolves the client once per request: a labelled sender *is*
its label (`--as` is ignored and counted, `claims_ignored`); an unlabelled
sender (the user's shell, the desktop, init) is `user`, or may **narrow**
itself with `--as jarvis`/`--as script`. `act whoami` shows what the
broker sees (`client=`, `origin=`, `attested=`). `/proc/<pid>/status`
shows `Origin:`.

**Reserved bus names** (`kernel/bus/bus.fi`, `name_ok`): `a.<app>` only
for a process labelled `app:<app>` or unlabelled; `orient.*` only for an
unlabelled root process; `r.<n>` only for the process whose pid is n.
The broker additionally checks the origin of a provider before binding
it (`foreign_providers`).

*Not covered*, on purpose written down: a user process that runs a file an
app *placed* somewhere (e.g. in an autostart list) is the user's. That is
the sandbox's job (S-010).

### 5.3 Confirmation and grants

A call that needs a "yes" is **parked** with a number and answered
`confirm <no>`; the broker publishes `bus.confirm_needed`. Only the user
can `confirm` or `reject` (an agent asking to confirm its own request is
refused — tested); parked calls expire after 60 s.
*Planned (AB-004):* the confirmation is a dialog owned by the window
server (a trusted path an app cannot draw over or click), not `act
confirm` on a shell.

Grants: `allow <client> <glob> <read|write>` in `/etc/orientbus/policy`
(permanent), or `act grant <client> <glob> write <seconds>` at run time
(timed; expired grants vanish). `act grant` *without* seconds is
permanent and is written into the policy file, so it survives a restart.
"Once" is simply a confirmation. Only the user may grant.

*Built (AB-006):* `act rights` lists every rule with its number, allow/
deny, client, glob, level and `permanent` / `left=<s>` / `session`, the
`dryfirst` clients, and per client the counts reads / changes / asked /
refused / dry runs -- kept since the broker started and seeded from the
audit log at start, so they survive a reboot (tested over a second boot
of the same disk). A client that is not the user sees only its own
lines. `act revoke <n>` (or `<client> <glob>`) takes a rule away -- a
permanent one also out of the policy file, every other line of the file
stays; `act block <client> <glob>` writes a permanent deny rule. Both are
user-only and logged write-ahead. The settings window shows all of it on
the page "App rights" (section 6).

### 5.4 The audit log

`/var/log/orientbus.log`, one line per decision:

```
t=1402 pid=31 uid=0 client=jarvis verb=call action=notes.add decision=ask result=confirm dry=0
```

* **Write-ahead:** a change is logged *before* it is forwarded. If the
  line cannot be written, the change is refused (`audit_unavailable`);
  reads still work. Tested as a counter-check with no `/var/log`.
* Parked, refused, confirmed, rejected, undone, granted: written at once.
* Allowed reads and dry runs are **counted** per (client, action, result)
  and written as one line with `count=` at the next change, after 16
  kinds, or after 0.5 s idle — see section 10 for why.
*Planned:* rotation, a viewer (roadmap S-009), export.

## 6. Settings on the bus — *built (AB-005, AB-005b)*

**The settings window is a client (AB-005b, round ACTION-BUS-3).**
`kernel/user/actcli.fi` is the bus for programs with a window: the same
frames and reply box as `act`, a short wait, no process per call. Two
pages of `/bin/settings` know nothing themselves:

* **System** lists every setting of the schema through `settings.list`
  (key, value, risk, meaning). "Set" is `settings.set`; a critical key
  comes back as a question with a number, the page asks the person in
  front of it and only then sends `confirm <n>`; "Undo last change" is
  the bus undo. Without a broker the page says so and changes nothing.
* **App rights** is AB-006 (section 5.3): rules with their end, the
  dry-run-first clients, the counts per client; "Revoke rule", "Block
  this app", and "Allow Jarvis the display for 1 hour" (a timed grant
  for `settings.display.*`; critical keys stay unreachable).
* The lock time on the page "Users" reads and writes `lock.idle`
  through the bus; only an image *without* a broker still uses the file
  (and says so on the serial line).
* `display.brightness` now lives in the kernel: settingsd reads and
  writes `DG_BRIGHT` (40..200, 100 = unchanged; 50 % = the picture as
  it comes); without a display it stays in /etc/settings.db.
* `settings page=12` opens on that page.
* **AB-005c (round ACTION-BUS-4).** "Übernehmen" on the page Bildschirm
  sends `display.brightness` over the bus (contrast, gamma, saturation,
  rotation and the mode are not in the schema and stay direct); the page
  Sprache sets `locale.language`; switching the page Netz to DHCP is
  `net.dhcp` -- critical, so the page asks, and "Ja, ändern" on that
  page answers. A fixed address stays a direct write (the schema has no
  key for an address). Behind the bus the values now live where they
  take effect: `sound.volume`/`sound.mute` in the sound card
  (SYS_AUDGET/AUDSET, as the taskbar), `locale.language` in the session
  person's own `/users/<name>/config/locale` (the file msg.fi reads
  first; handed to them with chown; without a session the database),
  `net.dhcp` as `modus=` in /etc/network.conf (true also starts
  /bin/dhcp; false is refused where no `ip=` is written). The column
  "Meaning" comes from the catalogue (`settings.key.<key>`).
  Still only in /etc/settings.db: `display.scale` (the kernel's scale is
  an integer factor fixed at boot), `display.night`, `net.wifi.enabled`,
  `net.proxy`, `update.*`, `security.lock`, `privacy.crashreports` --
  no program reads them yet.

Measured in `tools/actionbus/gui.sh` (real window server, clicks through
the QEMU monitor): 14 rows, 30 % reaches the kernel as 60, a critical
change is asked and done only after the yes, the journal names the
window's changes as the user's, the Jarvis button leaves a rule with an
hour to run. Round ACTION-BUS-4 adds: the brightness from the page
Bildschirm reaches the kernel through settingsd, the page Netz asks for
DHCP and after the yes /etc/network.conf says `modus=dhcp`. Not on the
bus: theme, time zone, the fixed network address, contrast/gamma/mode.

### 6.1 The design (AB-005)

`/bin/settingsd` (provider `settings`, manifest
`etc/actions.d/settings.actions`), the schema `etc/settings.schema`
(14 keys), the shared reader `kernel/user/setschema.fi`. Built as designed
below, plus: `settings.history`, `settings.revert key change` (refused
with `changed_since` if the value was changed again since — nothing is
silently thrown away), a journal `/var/log/settings.journal` written
*before* the value, and the manifest word `keyed` (the argument `key`
names a setting; the broker checks the value against the schema and
decides by `settings.<key>` at the schema's risk). Today one key is wired
to a real consumer: `lock.idle` → `/etc/sperre.conf leerlauf`
(sperrwache). The others live in `/etc/settings.db` until their programs
read them from there, and the settings window does not use the bus yet
(roadmap).

The design:

System settings are served by a provider `settings` like any other app;
the settings window itself is just one client. A **schema** declares each
key:

```
setting display.brightness int 0..100 harmless "Screen brightness in percent"
setting display.scale enum 100,125,150,200 harmless "UI scale"
setting net.wifi.enabled bool critical "Wi-Fi on/off"
setting update.auto bool critical "Install updates automatically"
```

* Actions: `settings.get(key)`, `settings.set(key, value)`,
  `settings.list(area)`, `settings.undo(change)`; the broker maps a key to
  the right `settings.<area>.read|write` so a grant can be *per area*
  ("Jarvis may change display settings for 1 hour").
* Values are validated against type and range **in the broker** (same
  code as action arguments), before the provider sees them.
* Risk `critical` for network, security, accounts, updates, power
  policy: always a confirmation, never grantable.
* Every change is a journal entry (key, old value, new value, client,
  time); undo writes the old value back — the general undo of section 9.1
  with a trivial inverse.
* The existing `/bin/settings` window keeps its UI and moves its reads and
  writes onto these actions; nothing else in the system writes settings
  files directly any more.

## 7. Compatibility: Linux and Windows programs

**Rule: native OrientOS apps first, full actions. Everything else keeps
running unchanged and gets as many actions as an adapter can honestly
provide.** Nothing in the action layer is a precondition for starting a
program.

A **wrapper manifest** (`/etc/actions.d/<program>.actions`, shipped by us
or the community as its own signed package, e.g. `actions-vlc`) declares
actions for a program that has none and binds each to an **adapter**:

| adapter | for | example | reliability |
|---|---|---|---|
| `cli` | programs with a command line / remote control | `playerctl pause`, `code --goto f:12` | good |
| `dbus` | Linux programs with D-Bus interfaces (MPRIS, etc.) via the compat layer | `org.mpris.MediaPlayer2.Player.Pause` | good |
| `file` | settings in known config files | set a key in `~/.config/x.conf` | medium, program may need restart |
| `ui` | accessibility tree: AT-SPI for Linux toolkits; UIA/MSAA as far as Wine exposes it; OrientOS's own a11y tree (S-007) for windows of the compat window server | "press button *Send* in window *Thunderbird*" | medium |
| `keys` | last resort for Wine/Proton and anything else: focus a window, inject keys through the window server | `space` in window matching `VLC` | low, marked as such |

*Built (AB-008b, round ACTION-BUS-3): the foreign-window layer* -- `ui`
and `keys` for a program's WINDOW:

```
for window "Fake Viewer*"            the window: title or app id (glob)
action viewer.search write "Search"
  arg text string required "What"
  adapter keys ctrl+f {text} enter   named keys, ctrl+<letter>, one
                                     character, {arg} = typed text
action viewer.play write "Play"
  adapter ui click 40 30             also: ui close, ui raise
```

The kernel call behind it is `WM_FWIN` (2128, `kernel/sys/sysgui.fi`):
list windows (with the owner's pid), put a key / a click / the close box
into the ring of ONE window, or raise it. Root only -- the broker is the
one caller, after rights, confirmation, dry run and the write-ahead log.
It never touches a terminal, the lock screen (or anything while locked),
a panel, the desktop, the caller's own window, or **any window whose
owner is not a foreign program** (the owner's kernel label must start
with `compat:`): the user's own tools and installed apps are never
steered by synthetic input -- otherwise a wrapper manifest could name
the settings window and an agent could click "Yes, change it" for
itself (tested: refused). `wayd` labels itself `compat:wayland`, and it
now passes input on: every window it made is polled, keys go out as
`wl_keyboard` enter/key (Linux evdev codes, shift/ctrl as their own
presses), clicks as `wl_pointer` enter/motion/button, the close box as
`xdg_toplevel.close`; `set_title`/`set_app_id` are kept and given to the
window. Tested with an unchanged Linux Wayland program
(`tools/actionbus/wlkeys.c`, libwayland-client + xdg-shell, static musl)
whose own log shows every key, the typed text in order, the click at
40,30 and the close. *Not built:* `wl_keyboard.keymap` (needs an fd sent
out of wayd and an XKB keymap) -- programs that insist on a keymap get
none; an accessibility tree for foreign windows (element names like
"button Send") -- Wayland has none, and OrientOS's own (S-007) is for
its own toolkit. **Wine/Proton does not run on OrientOS** (no Win32,
docs FREMDSOFTWARE); if it does one day, its windows come through wayd
(winewayland) and are steerable by exactly this layer.

*Built (AB-008):* `cli` and `file`, in the broker (`run_adapter`), with
the rules below — no shell (a value `a b;rm -rf /` reaches the program as
one argument, tested), the program runs in a child that dropped to the
caller's uid (`adapter_uid`, default 65534, for root callers — never root)
and is labelled `compat:<app>` by the kernel, 5 s timeout then SIGKILL,
`for exe <path>` decides `available`, output `k=v` lines pass through,
the manifest's `undo` works (pause → play). `dbus`, `ui` and `keys` are
parsed and shown with their reliability, and a call is refused with
`err adapter_unsupported <kind>`: OrientOS has no D-Bus, no accessibility
bridge for foreign windows and no key injection for them yet, and a faked
success would be worse than a refusal. Adapters are only accepted in
wrapper manifests (`/etc/actions.d`), never in an app's own manifest.
Tested with an unchanged static Linux (musl) program,
`tools/actionbus/fakeplayer.c`. Wine/Proton programs need the `ui`/`keys`
adapters, i.e. a foreign-window layer in the compat window server — that
part is still planned.

Rules for adapters:

* No shell. `cli` is an argv template (`{arg}` substituted as one
  argument), executed by the broker's adapter host under the **user's**
  uid, never root.
* A wrapper manifest names what it wraps (`for exe vlc version >=3`); an
  action is `available` only if that program is present/running.
* Adapter actions carry `compat` in the catalogue and a reliability; an
  AI can prefer native actions and knows a `keys` action may misfire.
* The same rights, confirmation, audit and dry run apply — a dry run of
  an adapter action reports the command it would run.
* The prototype already *reads* wrapper manifests (the test ships one for
  `player`, with an `adapter` line the prototype skips) and reports
  `app_not_running` cleanly; executing adapters is AB-008.

**"Manifest mandatory" and compat.** A Linux or Windows program packaged
as `.opk` gets a generated minimal manifest (`manifest 1`, `app <name>`,
no actions). That satisfies the rule without touching the program.

## 8. The social layer (Fleitec All-in-One)

*Built* (round SOCIAL, `docs/SOCIAL.md`): `/bin/social` is the provider
`social` with the actions of the table below (messages/invites still
planned), providers as programs behind one interface, the friends bar
reads it; `tools/social/run.sh` (test.sh § 54).

The social layer already has a concept of its own (FirnChat repo,
`docs/SOCIAL.md`, 29.09.2026): a local service `social` that owns the
merged address book, presence, activity, messages and invites, providers
behind one interface, and a local **API v1** (JSON lines over a Unix
socket / localhost + token) that every UI and app speaks.

**Agreed shape on OrientOS: API v1 *is* a set of actions on orient-bus.**
The desktop app on Windows/Linux keeps the socket; on OrientOS the
`social` service is a provider on the bus and the v1 calls keep their
names under the `social.` namespace — one set of words on both sides:

| API v1 call (SOCIAL.md) | action on orient-bus | level |
|---|---|---|
| `contacts.list` | `social.contacts.list` | read |
| `contacts.request / accept / decline / withdraw / block` | `social.contacts.<verb>` | write (agent → ask) |
| `presence.set {state, text, until}` | `social.presence.set` | write |
| `activity.set {kind, name, details, party, join}` / `activity.clear` | `social.activity.set` / `.clear` | write |
| `messages.send {to, text, files}` / `messages.history` | `social.messages.send` / `.history` | write (agent → ask) / read |
| `invites.send {to, activity}` / `invites.answer` | `social.invites.send` / `.answer` | write |
| `subscribe {topics}` | events `social.contact`, `social.presence`, `social.activity`, `social.message`, `social.invite` | — |
| privacy: invisible | `social.privacy.set` | critical |

Consequences:

* SOCIAL.md's per-app rights (`contacts.read`, `activity.write`,
  `messages.send`, `invites.send`, "asked once") become ordinary bus
  grants (`allow <app> social.activity.* write`) — the same page
  "What may which app do" shows them (9.4). The service does not need a
  permission store of its own.
* "Every app that opens the socket is identified by its package id" is
  exactly AB-003 (attested client identity). One mechanism, both uses.
* `setActivity` from an app: the broker passes the calling client, so an
  app can only set *its own* activity; the SDK (C header / Firn module)
  becomes a thin wrapper over `social.activity.set`.
* Providers (fleitec, lan, later matrix/xmpp) stay *behind* `social`;
  the bus never sees them. Privacy switches stay enforced in the service
  ("invisible" is enforced where the data is — PRAESENZ.md).
* The existing `/bin/praesenz` (kernel bus, `docs/PRAESENZ.md`) is the
  starting point of the OrientOS `social` service; its window-focus feed
  ("in <app>") stays a kernel-bus stream, not an action.
* For games under Wine/Proton, "plays X" comes from the same detection the
  Windows Melder uses (process list against the detectable-games list),
  done by `social` itself — no adapter needed.

## 9. Further ideas — assessed

### 9.1 Undo and transactions — **yes to undo, no to transactions**
*Built:* per-client undo stack; the manifest fixes the inverse action,
the provider returns only its arguments (`@undo index=3`), so an app
cannot make the broker call something else as "undo". Undo is a normal
call (rights, log). *Not built on purpose:* multi-app transactions with
rollback. Apps have side effects the broker cannot roll back (a sent mail).
The honest model is **compensation** (sagas): a batch runs step by step,
and on failure the already-done steps are undone in reverse where an
inverse exists; steps without an inverse are marked as such *before* the
batch runs (dry run).

### 9.2 Dry run — **yes, built**
Every action can be dry-run. If the app declares `dryrun`, it simulates
("would delete 2"); otherwise the broker answers with what would be
called and the decision that would apply.

*Built (AB-009): dry run first, enforced by the device.* A policy line
`dryfirst <client>` (the shipped policy has `dryfirst jarvis`) makes the
broker refuse every change of that client (`write`/`critical`; reads
and undo are free) with `err dry_run_first <action>` unless the SAME call
-- action and arguments in order, a FNV-1a print without the `@` meta
lines -- was dry-run by the same client in the last 60 s. One dry run
pays for one call; a dry run of plan-b does not pay for plan-c. The
check comes before a call is parked, so the human is never asked about
something nobody looked at first. `act whoami` says `dry_first=yes`, so
an agent knows. On Justin's personal image `/bin/act` is on the bridge's
command list (`/root/abbilder/justin-permissions.conf`).

### 9.3 Automations ("Baukasten", like Shortcuts) — **yes, as a client**
An automation is a file: trigger (event, time, manual), steps (action
calls, simple conditions on results), and **its own client identity**
`automation:<name>` with its own grants. It is executed by a runner that
is just another client — so an automation can never do more than the user
granted it, and it shows up in the log under its own name. Created by
hand, from the UI, or by Jarvis (as a proposal the user saves).
Dry-running an automation dry-runs every step.

### 9.4 "What may which app" — **yes, built (AB-006, section 5.3)**
A settings page built entirely from bus data: rules, timed grants with
remaining time, deny rules, and per client the counts from the audit log
(e.g. "Jarvis: 41 reads, 3 changes, 1 refused this week"). Revoking is
one click (= removing a rule). AB-006.

### 9.5 Sandbox / capabilities per `.opk` — **yes, but it is the kernel's job**
The action manifest says what an app *offers*; a capability list says
what it *needs* (`needs files ~/Music read`, `needs net`, `needs call
player.*`). The second part — outgoing action calls — the broker can
enforce today with the same rules. Files, network and devices must be
enforced by the kernel (handles instead of ambient authority,
`PACKAGING.md` § 7; roadmap S-010). One manifest file, two enforcers.

### 9.6 Audit log — **yes, built** (section 5.4), rotation/viewer planned.

## 10. Prototype and measurements

| file | what |
|---|---|
| `kernel/user/actwire.fi` | frames, reassembly, text helpers — shared by all three programs |
| `kernel/user/orientbus.fi` | the broker |
| `kernel/user/act.fi` | the client |
| `kernel/user/actcli.fi` | the client for programs with a window (settings) |
| `tools/actionbus/gui.sh` | the screen test: foreign-window layer, settings pages |
| `tools/actionbus/wlkeys.c` | a Linux Wayland program for that test |
| `tools/actionbus/setsess.c` | test aid: the session uid, as glogin sets it |
| `kernel/user/notes.fi` + `pakete/notes/` | example app with manifest and package recipe |
| `tools/actionbus/manifest.py` | host reader (check / JSON) |
| `tools/actionbus/run.sh` | the test: three guests, 10 sections |
| `tools/actionbus/fixlen.py` | development aid: exact lengths of Firn string arrays |

**The test** (`bash tools/actionbus/run.sh`, KVM): see the result line
`ACTIONBUS: n passed, 0 failed` and the numbers below.

**Experiment log — round-trip latency** (client → broker → app → broker
→ client, `act bench`, `notes.count`, KVM, 10 ms tick clock):

| round | hypothesis / change | 200 calls | per call |
|---|---|---|---|
| 1 | first version, audit line appended synchronously per call | 407 ticks | 20.3 ms |
| 1b | same, *without* `/var/log` (counter-check) | 3 ticks / 100 | ~0.3 ms |
| 2 | → the disk write is the cost; buffer allowed reads (3 KB) | 79 ticks | 3.95 ms |
| 3 | → buffer flushes still cost; **count** reads per (client, action) instead of writing each | 2 ticks | ~0.1 ms |
| 3b | same, 2000 calls for resolution (1 core) / 2 × 3000 (4 cores) | 13 / 18 ticks | **65 µs / 60 µs** |

Conclusion: 20.3 ms → 65 µs, a factor of ~300. The bus itself is well
below a millisecond; the design question was the audit log. Changes stay synchronous and write-ahead —
that is the point of the log — and reads are aggregated.

**Jarvis end to end** (section 11 of the test): the JARVIS side of the
test bridge (`tools/bridge/peer.py`, TLS 1.3 + Ed25519 login, the wire
the live server speaks) sends `befehl` jobs; `jarvisd` on the guest may
run exactly one program, `/bin/act`. Jarvis gets the JSON catalogue,
its write is parked for the user, its dry run of `notes.clear` answers,
its real `notes.clear` needs a human yes, `/bin/sh` is refused by the
bridge, and the device's audit log names `client=jarvis`.

**Round ACTION-BUS-2** (sections 12–14 of `run.sh`, and `image.sh`):
an app bundle's program saying `--as user` is `app:evil` for the broker,
its write is parked, it cannot confirm or grant, a copy of `act` is still
the app, it cannot take `a.<other>`, `orient.*` or `r.<pid>`; Jarvis
saying `--as user` over the real bridge is still `jarvis`; settings:
per-area grant, critical asks even the user, bad values refused by the
broker, journal, undo, revert, `/etc/sperre.conf` really changed;
adapters: the Linux program runs as uid 65534 with label `compat:media`,
no shell, timeout, honest refusals. `image.sh`: the shipped image boots
under UEFI from USB, the session starts `orientbus` before the sign-in,
`settingsd` binds, the sign-in screen comes up, no panic.

**AB-016 in the image.** On an image with a screen `init` does not run
(`kmain.wm_owns_shell`); the session is started by the kernel's
`kgui.desk_start`, and that is where the broker and settingsd start —
first, before the sign-in, and only if the image carries
`/bin/orientbus` (older test images start exactly what they did). The
bus blocks since round ACTION-BUS-4 (AB-002 = S-003): `BUS_RECV` takes a
wait in milliseconds (its fifth argument; 0 = the old non-blocking
receive, every older caller passes 0) and sleeps like `poll` does -- the
wake sequence is read before looking, the task sleeps in S_POLL, and a
delivery into its box (`bus.queue_put`) wakes exactly that task.
Broker, settingsd, notes, `act` and the window client wait there (at
most 100 ms, for their timers). Measured (`run.sh` section 17): an idle
broker is scheduled 46 times and settingsd 47 times in 5 s (the old
loop slept 10 ms per turn, up to 500); a round trip is 40-50 us (was 60).
Server images with `init` add `bus:*:respawn:/bin/orientbus serve`.

**Limits** (all on the roadmap): `act confirm` instead of a trusted
dialog (5.3); events visible to every subscriber; payloads above 2 KB
per request refused; manifests are read once at the broker's start (an
app installed later needs a broker restart); an adapter call blocks the
broker for up to 5 s; `dbus` not executable, no keymap for Wayland
programs, no element tree for foreign windows; theme, time zone,
network and language pages of the settings window still write their own
files; a broker that exits keeps its bus names until its parent reaps
it (the kernel frees them in `reap`, not at exit).

## 11. Comparison

| | declared where | typed args | descriptions for AI | who decides rights | audit/undo | foreign programs |
|---|---|---|---|---|---|---|
| **Android Intents** | manifest intent filters | loose (extras) | no | app permissions at install/run time | no / no | n/a |
| **Android AppFunctions** (2025) | code annotations | yes | yes | system + agent permission | no / no | no |
| **Apple App Intents + Shortcuts** | Swift code, compiled metadata | yes | yes | system; `requestConfirmation` by the app | no / no | no |
| **Windows** App Actions (2025) / COM / UIA | JSON action definitions / type libraries / none | partly | partly | app / none | no / no | UIA as fallback |
| **D-Bus + polkit** | XML introspection | yes | no | polkit rules | no / no | Linux only |
| **MCP** | server tool list | JSON Schema | yes | the host application | host-specific | via wrappers |
| **orient-bus** | text manifest in the package | yes | yes | **one broker, for every caller alike** | **yes / yes** | wrapper manifests + adapters |

What we take: App Intents' idea that actions are *declared* and typed;
Android's rule that the package states it up front; MCP's JSON shape for
the catalogue; polkit's separation of policy from the service; Shortcuts
as the automation model. What we do not take: per-app confirmation code
(the app decides whether to ask — here the broker does), a second path
for the system assistant, and rights that exist only at install time.

## 12. Roadmap

Kept in the JARVIS project roadmap (group *Aktions-Bus*), not in a file:
AB-001 prototype (this round) · AB-002 blocking receive (= S-003) ·
AB-003 attested client identity + reserved `a.<app>` names · AB-004
trusted confirmation dialog · AB-005 settings on the bus · AB-006 "what
may which app" page · AB-007 manifest mandatory in `opk.py`/store ·
AB-008 adapters (cli → file → ui → keys) · AB-009 Jarvis as client
(bridge identity, dry run first, catalogue → tools) · AB-010 social on
the bus · AB-011 automations · AB-012 audit rotation/viewer · AB-013
large payloads via segments · AB-014 action versioning · AB-015 event
permissions · AB-016 orientbus in the image and started by init.
Done in round ACTION-BUS-2: AB-003, AB-005, AB-008 (cli/file), AB-016.
Done in round ACTION-BUS-3: AB-005b (settings window + lock time +
brightness), AB-006, AB-008b (foreign-window layer, keys/ui), AB-009
(dry run first; the bridge may run `/bin/act`).
Done in round ACTION-BUS-4: AB-002 (blocking receive), AB-005c (pages
Bildschirm/Sprache/Netz, sound and language where they take effect,
the meaning column from the catalogue), AB-018 (`act reload`: the
catalogue is read again without a restart -- provider bindings, call
counts and undo records are carried over by name, a reload during a
call in flight is refused as `busy`, only the user may reload; opk
reloads after it rebuilt /apps).
Done in round ROADMAP-7: AB-012 (the audit log rotates at 256 KiB --
`auditmax <octets>` in the policy -- into ONE older generation,
/var/log/orientbus.log.1, the new log starts with a line that says so,
the counts per client are seeded from both files -- a line older than
the kept generation is gone, and so is its count; `act audit [n]` gives
the user the last n lines, nobody else), S-009 (the settings page
"Protokoll": the last 40 lines of the audit log over the bus, newest
first -- time, who, verb, target, decision, result -- with a refresh
button).
