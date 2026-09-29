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
| `kernel/user/freunde.fi` → `/bin/freunde` | the friends bar: the book, unread counts, the chat window (list, write), "Einladen"/"Beitreten", an incoming invite with "Annehmen"/"Ablehnen", "Unsichtbar" — all through `social.*` |
| `tools/social/run.sh` (test.sh § 55) | a real guest, a real fleikontakte and a real FirnChat relay on the host, anna's FirnChat client |
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
| `login [token <t>]` | `pair <code> <valid_s>` (exit 4) or `account <id> <name>` |
| `send <id> <text>` | `sent <devices> <stamp>` |
| `inbox` | `m id stamp in\|out text` — each message ONCE (the provider keeps its cursor) |
| `invite <id> <invite\|join> <target\|-> <name>` | `i <invite id>` |
| `invites` | `i inv id in\|out invite\|join open\|accepted\|declined age_s target name` |
| `answer <inv> yes\|no [target]` | the `i` line afterwards |

`caps` names what the provider can: `contacts search relation presence
activity alive login send inbox invite invites answer join`. The service
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
social.activity.* write`), `social.privacy.set` and
`social.accounts.login` always ask, every call is in
`/var/log/orientbus.log`. An app that writes in my name
(`social.messages.send --as app:x`) is parked for the user. What the
service enforces itself, where the data leaves the device:

* **invisible**: no signs of life, the activity is cleared everywhere;
* **share_activity=false** (`/etc/social/privacy`): an activity stays on
  the device;
* an app clears only the activity **it** set; the user clears any.

## Setting a device up

1. `/etc/social/providers`: `provider fleitec /bin/socfleitec /etc/social/fleitec.conf`
2. `/etc/social/fleitec.conf`:
   ```
   url=https://<IPv4 of chat.fleitec.com>
   name=chat.fleitec.com
   relay=<IPv4 of the relay>:7771
   ```
3. `act call social.accounts.login provider=fleitec` → a code; type it in
   at chat.fleitec.com (profile → MEINE GERÄTE → "Gerät hinzufügen");
   call it again → signed in, chat works. Or a key made by hand in the
   profile (GERÄTE-ZUGANG → "Schlüssel erstellen"):
   `act call social.accounts.login provider=fleitec token=fkz1....`
   (no chat then until the device is paired).

## Limits (roadmap, project "Fleitec All-in-One")

* **Xoffi** has no known API for contacts/presence/chat (only its sign-in
  is known, `kernel/app/anb_xoffi.fi`); a `socxoffi` waits for it;
* the Melder on OrientOS (detect running games by itself) is not built —
  apps say what they play with `social.activity.set`;
* the same person at two providers is two contacts (no merge by person);
* a provider call blocks the service for up to 4 s; chat is polled every
  5 s (a watching provider — the relay's T_WATCH — is the next step);
* join targets travel through the Fleitec server in the clear (like the
  activity); messages do not;
* no pictures, no group chats, no read marks going out yet.
