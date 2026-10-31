# FreeViewer / X-Remote protocol (host side view)

Source: /root/projects/freeviewer (v0.30.0, read only): relay/relay.js, src/net.rs, src/crypto.rs, src/proto.rs, src/viewer.rs, src/hostside.rs, src/testhost.rs, src/input.rs, src/app_frame.rs, src/app_session.rs. Complements the viewer-side notes in the FreeViewer repo (docs/ORIENTOS-VIEWER.md). Goal of this file: everything an OrientOS HOST (the controlled machine) has to implement.

## 1. Relay (WebSocket, JSON text frames = relay control, binary frames = opaque, forwarded 1:1)
- URL `wss://freeviewer.fleitec.com/fv/ws` (path `/fv/ws`). Plain `ws://` only for a local relay (client needs `FV_ALLOW_INSECURE_RELAY=1`). Relay max frame 16 MiB, pings every 25 s (answer with pong).
- Host registers: `{"t":"host_register","secret":"<32..128 hex chars>","name":"<name>"}`. Relay answers `{"t":"registered","id":"<9 digits>"}`. The ID is derived by the relay from `sha256(lowercase secret)`; same secret = same ID forever. Name: letters, digits, space, `._-`, max 40. A second registration with the same ID sends `{"t":"replaced"}` to the old connection and closes it (code 4001).
- Viewer connects: `{"t":"connect","id":"<digits>"}`. Relay sends host `{"t":"incoming","sid":..,"from":..,"client_ip":..}` and viewer `{"t":"paired","sid","id"}`. Errors: `{"t":"error","msg":"offline"|"busy"|"bad_secret"|"bad_json"|"unknown_type"}`.
- End of a session: `{"t":"peer_gone","reason":..}` to the remaining side; the host STAYS registered and waits for the next `incoming`. Either side may send `{"t":"bye"}`, `{"t":"ping","ts":n}` -> `{"t":"pong","ts":n}`.

## 2. Handshake (binary frames through the relay)
1. V->H `0x01 || client_pub(32) [|| caps(1)]` (X25519 ephemeral; caps bit0 = CAP_HOST_PROOF).
2. H->V `0x02 || host_pub(32) || salt(16)` (host: fresh X25519 pair, 16 random bytes).
3. Both: `key = HKDF-SHA256(ikm = X25519 shared, salt, info = "freeviewer-v1 session")`, 32 bytes. Session code (shown on both sides in ask mode) = `SHA256("freeviewer-v1 code" || key)[0..4]` as u32 BE mod 10000, 4 digits.
4. Password mode: V->H `0x03 || proof(32)`; `proof = HMAC-SHA256(pw_key, "fv-auth" || client_pub || host_pub || salt)`; `pw_key = Argon2id(password UTF-8, salt)`, m=19456 KiB, t=2, p=1, v=0x13, 32 B out (constant-time compare on the host).
5. Ask mode: V->H `0x06 || device_name`; host user must allow; no password.
6. H->V `0x04` ok, or `0x04 || host_proof(32)` when the hello had caps bit0 (`host_proof = HMAC-SHA256(pw_key, "fv-host" || client_pub || host_pub || salt || key)`); `0x05` = refused (wrong password / declined). A bare `0x04` is accepted by the 0.30.0 viewer (REQUIRE_HOST_PROOF=false).
7. Data frames both ways: `0x10 || nonce(12) || AES-256-GCM(plain) || tag(16)`, no AAD. Nonce = `dir(1) || 0 0 0 || counter u64 BE`, dir host=1 viewer=2, counter starts at 1 per direction, receiver rejects counter <= last. Frame overhead 29 bytes.

## 3. Session messages (inside data frames; 1 type byte, little-endian fields, blob = u32 len + bytes)
Host -> viewer:
- `0x20 ScreenInfo` w u32, h u32.
- `0x21 Frame` w u32, h u32, len u32, JPEG. Full keyframe; viewer sets its canvas to w x h from it.
- `0x22 Tiles` w u32, h u32, n u32, n x (x,y,w,h,len u32 + JPEG). Ignored by the viewer until a `Frame` of the same w x h arrived.
- `0x23 Cursor` x i32, y i32 (0..10000), visible u8. `0x24 Monitors` active u8, n u32, n x (name len u32 + bytes, w, h u32, primary u8). `0x3B Resolutions` list of (w,h). `0x37 Clipboard` len u32 + utf8 (max 256 KiB). `0x41 Pong` ts. Never send `0x25 Video` unless the viewer sent `Caps{h264:true}`; JPEG-only is enough.
Viewer -> host:
- `0x26 Caps` h264 u8. `0x30 MouseMove` x i32, y i32 normalized 0..10000. `0x31 MouseButton` button u8 (0 L, 1 R, 2 M, 3/4 extra), down u8. `0x32 Wheel` lines i32. `0x33 Key` code u32, named u8, down u8: named = KEY_* (1 Backspace, 2 Enter, 3 Tab, 4 Escape, 5-8 arrows L R U D, 9 Delete, 10 Home, 11 End, 12 PgUp, 13 PgDn, 14 Insert, 15 Space, 20 Shift, 21 Ctrl, 22 Alt, 23 Meta, 30..41 F1..F12), else a unicode scalar (letters are sent LOWERCASE, digits and punctuation as the plain character; modifiers arrive as separate named down/up events). `0x35 KeyVk` vk u16, ext u8, down u8 (Windows virtual key). `0x36 Special` code u8 (1 CtrlAltDel, 2 TaskMgr, 3 Win, 4 AltTab, 5 Lock, 6 ReleaseAll). `0x37 Clipboard`. `0x39 SetMonitor` index u8. `0x40 Ping` ts u64. `0x62 NeedKeyframe`. Mouse delta (`T_DELTA`), file transfer 0x50-0x53, audio 0x70, P2P offers: ignorable.
- Limits: MAX_TILES 4096 per message, MAX_VIDEO 8 MiB, MAX_CLIP 256 KiB.

## 4. What an OrientOS host needs (design, nothing of it built yet)
- Transport + TLS + WebSocket client: reuse `lib/fv/client.fi` (`cl_connect`, `ws_send`, `next_binary`, `release`; export them), `lib/net/ws.fi`, `lib/fv/crypto.fi` (`Cipher` already supports `is_host = true`; `keypair`, `session_key`, `session_code`, `password_key`, `auth_proof`, `proof_matches`, `seal`, `open`). Missing: host half of `lib/fv/session.fi` (answer hello with 0x02, check 0x03 proof, send 0x04/0x05, optional `host_proof` HMAC) and host-side encoders/decoders in `lib/fv/proto.fi` (enc ScreenInfo/Frame/Tiles/Cursor/Monitors/Resolutions/Pong, dec MouseMove/Button/Wheel/Key/KeyVk/Special/Ping/NeedKeyframe).
- Picture: `SYS_OSUM_SHOT` (1841; SH_ARM as root, SH_GRAB bands of RGB bytes, `SI_FRAMES` = compositor frame counter to skip idle polls) as used by `kernel/user/odbd.fi`; JPEG via `kernel/user/jenc.fi` (`jenc.encode(pix 0xAARRGGBB, w, h, quality, out, cap, ..)`, whole tile in memory). First message after the handshake must be a full-size `Frame`: a flat-grey JPEG of size w x h can be synthesized from an 8x8 jenc header (patch SOF dimensions, scan data = repeated 14-bit MCU `00 1010 00 00 00 00`) to avoid holding the whole screen, then send dirty tiles (cell hash per 64 x 32 strip cell) as `Tiles`.
- Input: `SYS_OSUM_TIPP` (1843): `TI_ARM` (root), `TI_MOVE` (pixel x,y), `TI_BUTTON` (mask 1 L 2 R 4 M; a2=1 down / 0 all up), `TI_SCAN` (PS/2 set-1 scancodes, `0xE0` prefix as own call, `|0x80` release), layout aware character -> scancode via `TI_INFO` / `TQ_KEYFOR` (see `layout_code` in odbd.fi). There is no wheel call yet: needs a new `TI_WHEEL` that calls `ps2m.usb_packet(state, mask, 0, 0, wheel, true)`. Permit allows ~200 strokes, re-arm with `TI_ARM` before it runs dry (`inp_budget` in odbd.fi). Emergency stop (Win+Esc) and the remote-input sign stay in force.
- Service: `/bin/xremoted` (init `respawn`), config `/etc/xremote.conf` (`enabled=0` default, `relay=`, `secret=` random hex generated on first enable, `password=`, `name=`), state file with the registered ID for Settings. Default OFF = no network traffic at all.
- Ask mode (0x06) needs a visible confirm dialog + the 4-digit code; v1 can answer `0x05` and support password mode only.

## 5. Test setup (gate idea, tools/xremote/run.sh)
- Local relay: `node /root/projects/freeviewer/relay/relay.js` (PORT env, plain ws://), the real Rust viewer headless: `freeviewer --connect <id> <password> [frames]` (needs `FV_ALLOW_INSECURE_RELAY=1`; Linux build with `CARGO_TARGET_DIR=$(mktemp -d /dev/shm/..)` via `/root/jarvis/bin/heavy cargo build`, not in the shared repo target). From QEMU user networking the server is `10.0.2.2`. `tools/orientos-testhost.sh` in the FreeViewer repo shows how relay + binary are started.
- Checks: Frame/Tiles pixels == QEMU screendump, click opens the start menu, typed text arrives in the terminal, wrong password -> 0x05, default off -> host never registers at the relay.
