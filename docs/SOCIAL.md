# SOCIAL — friends, presence and activity on OrientOS

Round SOCIAL (29.09.2026). The concept is FirnChat's `docs/SOCIAL.md`
(Fleitec All-in-One); this file says what of it stands on OrientOS and
how it is wired. `docs/ACTION-BUS.md` § 8 is the agreement this builds
on: **the local API v1 of the social layer is a set of actions on
orient-bus.**

## What exists

| file | what |
|---|---|
| `kernel/user/social.fi` → `/bin/social` | the service: provider on orient-bus (`a.social`), the merged book, own presence/activity, privacy, events |
| `pakete/social/ACTIONS` → `/apps/social.prog/ACTIONS` | 14 actions + 3 events (`social.status`, `social.contacts.list/get/search/request/accept/decline/withdraw/remove`, `social.presence.set`, `social.activity.set/clear`, `social.refresh`, `social.privacy.set` critical; events `social.presence`, `social.activity`, `social.contact`) |
| `kernel/app/socfleitec.fi` → `/bin/socfleitec` | provider **fleitec**: fleikontakte (chat.fleitec.com) with a device access token, over HTTPS (`knetz`, `kjson`) |
| `kernel/user/soclocal.fi` → `/bin/soclocal` | provider **local**: contacts kept on this device (`/etc/social/local.book`) |
| `kernel/user/freunde.fi` → `/bin/freunde` | the friends bar reads `social.contacts.list` (who plays first, then who is there, then the rest) and sets "Unsichtbar" with `social.presence.set` |
| `tools/social/run.sh` (test.sh § 54) | a real guest with a real fleikontakte on the host: 63 checks |

## The provider interface (v1)

A provider is a **program**. `/etc/social/providers`:

```
provider fleitec /bin/socfleitec
provider local /bin/soclocal
```

`social` runs `<program> v1 <verb> ...` with the output in a file and a
time limit of 4 s (inside the broker's 5 s), and reads TAB-separated
lines — `kernel/app/socfleitec.fi` documents the verbs (`hello`,
`contacts`, `search`, `relation`, `presence`, `activity`, `alive`), the
contact line and the exit codes (0 ok, 1 error, 2 offline, 3 refused). A
new provider (Matrix, XMPP, the LAN) is a new program and one line; the
service does not change and does not know which providers exist. Several
run at once; an id in the book is `<provider>:<id>`.

## Rights and privacy

Everything the broker does applies unchanged: reads are open, writes by
an agent or an app need the user or a grant (`act grant app:game
social.activity.* write`), `social.privacy.set` always asks, every call
is in `/var/log/orientbus.log`. What the service enforces itself, where
the data leaves the device:

* **invisible** (`social.presence.set state=invisible`): no signs of
  life, the activity is cleared at every provider;
* **share_activity=false** (`social.privacy.set`, kept in
  `/etc/social/privacy`): an activity stays on the device;
* an app clears only the activity **it** set (`@client` from the broker);
  the user clears any.

## Setting a device up (today, by hand)

1. A device access token: signed in at chat.fleitec.com,
   `POST /api/kontakte/zugang {}` → `{"token":"fkz1.<uid>.<64 hex>"}` (a
   new one retires the old; `{"weg":true}` removes it). *Planned:* a
   button in the profile that downloads the finished config.
2. `/etc/social/fleitec.conf`:
   ```
   url=https://<IPv4 of chat.fleitec.com>
   name=chat.fleitec.com
   token=fkz1....
   ```
   An address and not a name: `knetz` does not resolve (see its header);
   *planned:* `libc.dns` in the provider.
3. `orientbus serve &`, `social serve &`, then `freunde` or
   `act call social.contacts.list`. *Planned:* started by init (with
   AB-016).

## Limits (roadmap, project "Fleitec All-in-One")

* chat (`social.messages.*`) and invites/join are not in the interface
  yet; the bar's "Schreiben" window is still the old local one;
* the Melder on OrientOS (detect running games by itself) is not built —
  apps say what they play with `social.activity.set`;
* the same person at two providers is two contacts (no merge by person);
* a provider call blocks the service for up to 4 s (frames wait in the
  kernel meanwhile);
* the bar is `wlib`; the FirnChat friends view (`src/gui/pages.fi`,
  fUi) reads the same v1 words and is the candidate for the OrientOS
  panel once fUi windows host it.
