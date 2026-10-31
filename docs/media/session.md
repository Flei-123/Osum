# Media sessions on the action bus (service `media`, provider `/bin/mediad`)

Status: provider, manifest, client module, quick settings card (kernel/user/qsmedia.fi) and /bin/play session (kernel/user/playsess.fi) wired into the image; gate tools/qsmedia/run.sh (card, buttons, poll, counter-proof without mediad), tools/qsmedia/ssim.sh (mockup match).

## Model
- One session per owner, at most 4. Owner key = the broker-stamped client: `app:<name>`, `compat:<name>`, `jarvis`, or for an unlabelled person's program `user:<app>` (the `app=` argument names it).
- Only the owner can change or end its session (`media.publish`, `media.end`, `media.poll` all resolve the owner from `@client`, never from an argument, except the display name for `user:`).
- `media.publish` is `write noask`: any app may announce its own session without a prompt; a deny rule still wins.
- `media.control` is `write`: the person (quick settings card) acts without a prompt, an app/agent without grant is asked. An `app:X` client can only control its own session (`err not_owner`).
- Commands wait in one slot per session; the owner fetches them with `media.poll` (read, answers at once, `cmd=` empty when nothing waits).
- Cover: absolute path, no `..`, file at most 65536 octets (`err bad_cover`); title < 96, artist < 64 octets.

## Actions
`media.publish title= state=playing|paused|stopped [artist= cover= app= can_prev= can_next=]`, `media.end`, `media.current`, `media.poll`, `media.control cmd=play|pause|toggle|next|prev|stop [owner=]`, `media.stat`.

## Players
- Osum: only the CLI `/bin/play` exists (no GUI player, no pause). Hook: publish at start, poll between audio blocks.
- Certus (Web Media Session API): not in this repo. Certus maps `navigator.mediaSession.metadata` + `playbackState` to `media.publish`, and `setActionHandler` for play/pause/previoustrack/nexttrack to `media.poll` (about every 250 ms while a session exists). Uses the same frames as `kernel/user/actcli.fi`.

## Client module
`kernel/user/mediacli.fi`: `fetch()` (true when the shown session changed), `present()`, `playing()`, `title()`, `artist()`, `app()`, `control(cmd)`.

## Open
- Wire `mediad` into PROGS (tools/usbimg/build.sh), kernel/ui/kgui.fi spawn next to `stored`, `/etc/actions.d/media.actions` in the image lists.
- Quick settings card (qs.fi: sub-card at the top, cover/title/artist, prev/play-pause/next; replaces the placeholder tile `K_MEDIA`).
- Cover decoding in the card (JPEG via `jpeg.jpeg_read` into a capped buffer).
- Gate with an app-labelled bundle (see tools/actionbus/run.sh section 12), pixel check of the card.
