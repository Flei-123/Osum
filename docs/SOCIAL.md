# SOCIAL — friends, chat, presence, activity and invites on OrientOS

Round SOCIAL (29.09.2026), round SOCIAL-CHAT (29.09.2026). The concept is
FirnChat's `docs/SOCIAL.md` (Fleitec All-in-One); this file says what of
it stands on OrientOS, how it is wired and **what a provider has to do**.
`docs/ACTION-BUS.md` § 8 is the agreement this builds on: **the local API
v1 of the social layer is a set of actions on orient-bus.**

**The rule (Justin, 29.09.2026): the social layer belongs to no account.**
Fleitec is ONE provider. The service, the actions, the bar and every test
of the core speak only the interface below; an account of any kind
(Fleitec, Xoffi, Matrix, XMPP, the LAN, a second Fleitec account) is one
line in `/etc/social/providers` and one program. `social.fi`,
`freunde.fi` and `pakete/social/ACTIONS` name no provider.

## What exists

| file | what |
|---|---|
| `kernel/user/social.fi` → `/bin/social` | the service: provider on orient-bus (`a.social`), the merged book, messages (`/etc/social/messages`), invites, own presence/activity, privacy, events, the bell |
| `pakete/social/ACTIONS` → `/apps/social.prog/ACTIONS` | 23 actions + 5 events (below) |
| `kernel/app/socfleitec.fi` → `/bin/socfleitec` | provider for a **Fleitec** account: fleikontakte (book, presence, activity, invites) with a device access token; chat **end to end** as a FirnChat device over the relay (`kernel/app/fcrelay.fi`: x25519, HKDF-SHA256, ChaCha20-Poly1305, own-device copies) |
| `kernel/user/soclocal.fi` → `/bin/soclocal` | provider for accounts **without a server**: contacts, messages and invites in files (`-c <base>` = one account) — the second provider that passes the same checks |
| `kernel/user/melder.fi` → `/bin/melder` | the **Melder** on OrientOS (r135): the OrientOS backend of FirnChat's `docs/MELDER-INTERFACE.md` v1 (`melder v1 hello/detect/games/privacy/autostart/report`; no `identity`: there is no token, the service is signed in) plus a small core (`melder serve [ticks] [every]`, `melder once`). A running game of `/etc/social/games.tsv` (same format as FirnChat's `spiele.tsv`, rows with os `l`) becomes `social.activity.set`, its end `social.activity.clear`; the switch is `social.privacy.set` (read back from `social.status` → `share_activity`); the list `never` is `/etc/social/melder.never`. Detection is `SYS_PSTAT` (r146: pid, basename of argv[0] 16 octets, age `P_AGE` in ms, command line `P_CMD0..` = argv joined by blanks, 256 octets at most, lowercased by the Melder): `detect` prints `p <pid> <exe> <age_s> <cmdline>`; a row with command-line text (column 4) matches when the exe is running AND its command line contains the text (case ignored) — `java` + `minecraft`, `wine` + the game's .exe. Autostart = the line `melder:*:respawn:/bin/melder serve` in `/etc/inittab` (server images with `init`; a screen image starts it in `kgui.desk_start`, r140, together with `/bin/social`; r147: the desktop loop restarts either one 5 s after it ended, back-off up to 60 s). Test: `tools/melder/run.sh` (test.sh § 55b) |
| `kernel/user/socperm.fi` | rights per app (`/etc/social/apps`, scopes) and the privacy lists (never show, who may invite) used by `social.fi`; test `tools/social/perms.sh` (test.sh § 55c) |
| `kernel/user/freunde.fi` → `/bin/freunde` | the friends bar like Discord's friends view: tabs **Online** (who plays first, then who is there), **Alle**, **Ausstehend (n)** (requests of every account both ways: Annehmen / Ablehnen / Zurückziehen) and **Hinzufügen** (search at every provider, "Freund hinzufügen"); the presence as the theme's role colours (success / warning / danger / secondary text) on the list's colour tiles plus the dot character; unread counts, the chat window (list, write), "Einladen"/"Beitreten", an incoming invite with "Annehmen"/"Ablehnen" (shown only while there is one), "Unsichtbar" — all through `social.*`. Test stand: `--tab N`, `--annehmen N`, `--suche TEXT [--anfrage N]` |
| `tools/social/run.sh` (test.sh § 55) | a real guest, a real fleikontakte and a real FirnChat relay on the host, anna's FirnChat client. Standard: Gerätetoken fkt1; `SOCIAL_TOKEN_FORMAT=fkz1 bash tools/social/run.sh` = Legacy-Lauf (beide 109/0) |
| `tools/social/chat.sh` | the Fleitec provider on the host against relay + fleikontakte + FirnChat's own client (login, E2E both ways, pin, replay, invites) |

## The actions (API v1)

| action | kind | what |
|---|---|---|
| `social.status`, `social.refresh` | read | providers, counts |
| `social.accounts.list` | read | `account.N=name\|state\|account\|caps` |
| `social.accounts.login provider= [token=]` | critical | pairing code (`state=pending code=…`) or signed in (`state=ok account=…`) |
| `social.contacts.list/get/search` | read | `account:id\|relation\|presence\|name\|handle\|status\|activity\|since_s\|joinable` |
| `social.contacts.request/accept/decline/withdraw/remove` | write | relations |
| `social.presence.set`, `social.activity.set [join=true]`, `social.activity.clear` | write | myself |
| `social.privacy.set` | critical | share the activity or not |
| `social.privacy.get` | read | `share_activity`, `invisible`, `invites_from`, `hidden`, `hide.N` |
| `social.privacy.hide entry= [hide=true\|false]` | critical | never show the activity of a client (`app:game`) or an activity name |
| `social.privacy.invites from=all\|friends\|none` | critical | who may invite me |
| `social.apps.list` | read | `app.N=client\|scope,scope` |
| `social.apps.grant client= scope=` | critical | give an app one of the four scopes |
| `social.apps.revoke client= [scope=]` | critical | take a scope, or every right of the app |
| `social.messages.send id= text=` | write | to a contact, via its account's provider |
| `social.messages.list id= [before=]` | read | `message.N=index\|stamp\|in/out\|read\|text`, newest page |
| `social.messages.unread`, `social.messages.read id=` | read / write | unread per contact, mark read |
| `social.invites.send id= [kind=invite\|join] [name=] [target=]` | write | invite into my activity / ask to join theirs |
| `social.invites.list [filter=open]` | read | `invite.N=account:inv\|account:peer\|in/out\|kind\|state\|age_s\|target\|name` |
| `social.invites.answer id=\|from= accept= [target=]` | write | yes/no; a yes to an invite brings the target, a yes to a join request sends mine |

Events: `social.presence`, `social.activity`, `social.contact`,
`social.message` (id, text), `social.invite` (id, from, kind, name). A new
message or invite also rings the system's bell (`bus.noti_post`, the
taskbar's toast), in the system's language (`social.invite`,
`social.join` in `/usr/share/locale/*/messages`).

## The provider interface (v1)

A provider is a **program**; one line in `/etc/social/providers` is one
**account**:

```
provider fleitec /bin/socfleitec /etc/social/fleitec.conf
provider arbeit  /bin/socfleitec /etc/social/arbeit.conf
provider local   /bin/soclocal
provider lan2    /bin/soclocal /etc/social/lan2
```

`social` runs `<program> v1 [-c<conf>] <verb> ...` — the configuration
as ONE word, because `exec` takes eight arguments (`proc.MAX_ARGS`) and
`invite` needs the rest (4 s limit, inside the broker's 5 s) and reads TAB-separated lines; the last line is
`ok ...` or `err <code> <text>`. Exit codes: 0 ok, 1 error, 2 offline,
3 refused, 4 pending (a login waits for a code to be typed in).

| verb | answer lines |
|---|---|
| `hello` | `provider <kind> 1`, `caps <words>`, `account <id> [name]` when signed in |
| `contacts`, `search <text>` | `c id relation presence name handle status activity since_s chat joinable` |
| `relation request\|accept\|decline\|withdraw\|remove <id>` | — |
| `presence <online\|away\|dnd\|invisible> [text]`, `activity [-j] [name]`, `alive` | — |
| `games` | writes `/etc/social/games.tsv` (cap `games`); `ok <n>` = rows written |
| `login [token <t>]` | `pair <code> <valid_s>` (exit 4) or `account <id> <name>` |
| `send <id> <text>` | `sent <devices> <stamp>` |
| `inbox` | `m id stamp in\|out text` — each message ONCE (the provider keeps its cursor) |
| `watch` | a long-running process (cap `watch`): the first line `watch 1`, then `m` lines the moment they arrive; it ends with exit 2 when the session breaks |
| `invite <id> <invite\|join> <target\|-> <name>` | `i <invite id>` |
| `invites` | `i inv id in\|out invite\|join open\|accepted\|declined age_s target name` |
| `answer <inv> yes\|no [target]` | the `i` line afterwards |

`caps` names what the provider can: `contacts search relation presence
activity alive login send inbox invite invites answer join games watch`. The service
only asks for what is there — a provider without chat simply has no
`send`/`inbox`, and `social.messages.send` to its contacts answers
`err unsupported send`.

**A new account kind** (Xoffi, Matrix, XMPP, the LAN finder): a program
that speaks these verbs, a line in the file. Nothing else changes.

## Chat, end to end (the Fleitec provider)

`socfleitec` is a FirnChat **device** of its own: `<conf>.key` (x25519,
0600), paired by the eight-digit code (`login` → T_DIR `zugang=1` → the
person types the code at chat.fleitec.com under "Gerät hinzufügen"; asked
again, the address book hands out an access token made FOR this key).
A message is sealed per device of the recipient and once per other
device of the own account (F_SYNC, so the browser shows what OrientOS
wrote). `<conf>.seq` spends sequence numbers BEFORE a frame goes out,
`<conf>.seen` keeps the replay window per sender, `<conf>.pin` pins the
relay's key on first use. Read marks and strangers are dropped.
Construction and wire are FirnChat's (`docs/E2E-GERAETE.md` there):
FirnChat's own client and OrientOS read each other (`tools/social/chat.sh`
§ 3).

## Rights and privacy

Everything the broker does applies unchanged: reads are open, writes by
an agent or an app need the user or a grant (`act grant app:game
social.activity.* write`), `social.privacy.*`, `social.apps.*` and
`social.accounts.login` always ask, every call is in
`/var/log/orientbus.log`. An app that writes in my name
(`social.messages.send --as app:x`) is parked for the user. On top of the
broker the service enforces itself (`kernel/user/socperm.fi`):

* **rights per app**: a client named `app:<x>` may call only what its
  scopes cover; the table is `/etc/social/apps`, one line per client
  (`app:game activity.write`). No line = no right (`err denied scope
  <scope>`); everything not in a scope is for the user (`err denied
  user_only`); `social.status` is open. The user (and agents, whom the
  broker already asks) are not limited by the table.

  | scope | actions |
  |---|---|
  | `contacts.read` | `social.contacts.list/get/search`, `social.refresh` |
  | `activity.write` | `social.activity.set/clear`, `social.presence.set` |
  | `messages.send` | `social.messages.send` |
  | `invites.send` | `social.invites.send` |

* **invisible** (`social.presence.set state=invisible`): no signs of life,
  the activity is cleared everywhere;
* **share_activity=false** (`/etc/social/privacy`): an activity stays on
  the device;
* **never show**: `social.privacy.hide entry=app:game` (a client) or
  `entry=<activity name>`; such an activity stays on the device
  (`shared=false`), the lines `never=<entry>` are in `/etc/social/privacy`;
* **who may invite me**: `social.privacy.invites from=all|friends|none`
  (`invites=<word>` in `/etc/social/privacy`); an incoming invite or join
  request from somebody who may not is dropped before the list, the event
  and the bell;
* an app clears only the activity **it** set; the user clears any.

## Setting a device up

1. `/etc/social/providers`: `provider fleitec /bin/socfleitec /etc/social/fleitec.conf`
2. `/etc/social/fleitec.conf`:
   ```
   url=https://chat.fleitec.com
   # (a number works too: url=https://<IPv4> plus name=chat.fleitec.com;
   #  a NAME in url= is resolved through /etc/resolv.conf, IPv4 only)
   # relay= takes a number or a NAME (r126): chat.fleitec.com:7771 is resolved
   # through /etc/resolv.conf like url= (IPv4/A only; no answer -> `err dns`)
   relay=<IPv4 or name of the relay>:7771
   ```
3. `act call social.accounts.login provider=fleitec` → a code; type it in
   at chat.fleitec.com (profile → MEINE GERÄTE → "Gerät hinzufügen");
   call it again → signed in, chat works. Or a key made by hand in the
   profile (GERÄTE-ZUGANG → "Schlüssel erstellen"):
   `act call social.accounts.login provider=fleitec token=fkz1....`
   (fkt1.... and fkm1.... work the same: socfleitec checks only the
   shape `<tag>.<account>.<64 hex>` with tag fkz1, fkm1 or fkt1; the
   server checks the scopes of the token, r99)
   (no chat then until the device is paired).

## Limits (roadmap, project "Fleitec All-in-One")

* **Xoffi** has no known API for contacts/presence/chat (only its sign-in
  is known, `kernel/app/anb_xoffi.fi`); a `socxoffi` waits for it;
* the Melder on OrientOS (`/bin/melder`, r135) detects games by the program name AND (r146) its
  command line + age from `SYS_PSTAT` (fields `P_AGE` = 12, `P_CMD0`..+31 = 16..47, 8 octets per
  number, 256 octets; `exec` passes 8 arguments at most, so longer lines are cut). The list
  `/etc/social/games.tsv` is filled by the service itself (r140): the provider
  verb `games` of `socfleitec` fetches `GET /api/kontakte/spiele?os=l` (an older
  server that ignores `os` sends all rows) and keeps the rows with os `l`, an executable, a name and
  an optional command-line text (column 4, up to 60 octets); the icon column goes. The service asks
  every provider with the cap `games` 4 s after the start and then
  hourly (10 min after a failure; one fetch blocks the service for up to 15 s,
  so never from a request). The server's Linux list is tiny (8 rows today): only rows the
  list holds can be found. Apps can still say what they play with `social.activity.set`;
* a **screen image** has no `init`: `kgui.desk_start` starts `/bin/social serve`
  and `/bin/melder serve` after the broker, if the image carries them
  (`desk: social pid=`, `desk: melder pid=` on the serial line; test
  `tools/melder/screen.sh`). r147: the desktop loop watches both (`sv2_watch`, like `jarvisd`):
  gone or zombie -> `desk: social ended slot=`, 5 s later `desk: social respawn pid=<n>`, back-off
  doubling to 60 s, a run of two minutes resets it. Test hook: boot word `sokill=<ticks>` kills the
  service that many ticks after each start. The shipped USB image carries social, soclocal, melder
  and socfleitec (r145): `/etc/social/providers` = `local` (soclocal) + `fleitec` (socfleitec,
  `/etc/social/fleitec.conf` with `url=https://chat.fleitec.com`; pair it with
  `act call social.accounts.login provider=fleitec`), `/apps/social.prog/ACTIONS`, an empty
  `/etc/social/games.tsv` (the service fills it);
* the same person at two providers is two contacts (no merge by person);
* a provider call blocks the service for up to 4 s; a provider with the cap
  `watch` (the Fleitec account: `socfleitec watch` holds one relay T_WATCH
  session, heartbeat every 10 s) is read without blocking in the service
  loop (a pipe, every 100 ms) and is not polled; the service restarts it
  5 s after it ended. Providers without `watch` are polled every 5 s
  (`social serve [ticks] [refresh-ticks] [message-poll-ticks]`);
* join targets travel through the Fleitec server in the clear (like the
  activity); messages do not;
* no pictures, no group chats, no read marks going out yet.
