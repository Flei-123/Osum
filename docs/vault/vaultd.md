# vaultd — one vault for passwords and passkeys

Status: **design only** (31.10.2026, roadmap P1-1 / r2414). Nothing in this file is built. Every statement marked "measured" was read from the tree on that date; everything else is a decision or an open question.

Decisions already taken by the Boss: passkeys live in OUR vault (Certus vault, Argon2id, fully local, no account needed); E2E sync is a concept only (`docs/PASSWORT-SYNC.md`); the product name of the feature is NOT "Hello" (proposal "Xoffi Key", Boss decides, name only in brand config).

Companion documents: `docs/vault/authenticator.md` (CTAP2/WebAuthn), `docs/PASSWORT-SYNC.md` (sync concept), `docs/PIN.md` (login PIN), `docs/ACTION-BUS.md` (caller identity), Certus `docs/TRESOR-FORMAT.md` (format v1).

---

## 1. What exists today (measured)

| Item | Where | Facts | Reusable? |
|---|---|---|---|
| Certus vault container v1 | Certus `origin/main`: `lib/vault/vault.fi` (637 lines), `vault_main.fi` (274), `argon2.fi` (477), `aes256.fi` (237) | Magic `CERTUSTRESOR`, header 84 octets, tag 32. KDF byte 1 = PBKDF2-HMAC-SHA256 (200 000 rounds), 2 = Argon2id (64 MiB, 3 passes, 1 lane; limits 1 GiB / 16 passes / 64 lanes read from file). Keys `EK/AK/CHK` = HMAC(MK, "certus tresor v1 enc/mac/check"). Cipher ChaCha20 (counter 1), random 96-bit nonce per save, HMAC-SHA256 tag over header + ciphertext, checked BEFORE decrypt. `CHK` separates "wrong password" from "damaged". Return codes `F_*`. API: `vault_seal`, `vault_seal_argon2`, `vault_open`, `vault_rewrap`, `vault_check_header`, `vault_key_cached`, `vault_forget_keys`. | **Yes** — the container logic, the labels (on-disk format, must never change), the limits. |
| Certus vault tests | Certus `tools/vault/`: `against.py` (second implementation in Python), `kdf-vectors.json` + `kdf_vectors_test.sh`, `argon2_test.sh`, `argon_vault_test.py`, `aes256_test.sh`, `bw_encrypted_test.py`, `unreadable.sh` | Cross-checked against hashlib / `/usr/bin/argon2` / `cryptography`. | **Yes** — move with the lib. |
| Certus password store | Certus `lib/browser/pwstore.fi` (1198 lines) | Plaintext = tab-separated lines `origin TAB user TAB password`. Sealed with the vault lib. Without a main password the vault password is a random key in `~/.certus/vault.key` (protects copies only, not a same-user program). With main password: Argon2id, no key on disk. | UI/merge/import logic stays in Certus; storage moves behind the lib/vaultd. |
| Argon2id in Firn | `/root/firn/lib/std/crypto/argon2.fi` (+ `blake2b.fi`), commit `31e1696b7`, **inside the OrientOS pin** `031ec5a4` | `argon2id(pwd,pwdn,salt,saltn,secret,secretn,ad,adn,t,m_kib,lanes,out,outlen)`. Header says it was lifted from FirnChat "so that FirnChat and Certus share ONE implementation". Certus still carries its own copy. | **Yes** — Certus `vault/argon2.fi` becomes a duplicate to delete (vectors must stay identical). |
| Other Firn crypto | `std.crypto.{aes (aes256_new, CBC), gcm, chacha (aead_seal/aead_open), hkdf, hmac, sha256, sha512, random, p256 (sign, RFC 6979, DER helpers), ecdsa (verify P-256/P-384), ed25519 (public/sign/verify), x25519, big}` | `p256.fi` says "constant time by construction, not measured (dudect)". `ecdsa.fi` is verify only. | **Yes** — nothing to write for primitives. |
| CBOR | `grep -ri cbor /root/firn/lib` and OrientOS `lib/` | **No CBOR library anywhere.** | **Gap** — new Firn lib `std.cbor`. |
| OrientOS "tresor" CLI | `kernel/user/vault.fi` (509 lines, German, round SYNC) | `vault new/open/close/put/get/list`. Secrets are files `G-<name>` (name ≤ 22, **names in clear on disk**), value ≤ 512, key `K_TRESOR` from `sync.chain`, session file `/system/tresor.sit` (32 random octets, root only) with expiry. `get` writes to fd 1 only. Its own header says it is NOT the handle layer. | **Idea only** (fd-1 output, timeout session). Format and limits are too small and leak names. Becomes a thin client / is removed after migration. |
| Login PIN | `kernel/user/pin.fi` (537 lines), `docs/PIN.md` | 4–12 digits, `HMAC(device key, "osum-pin1:"user":"pin)` → PBKDF2 `$osum1$`, device key `/device/pinkey` (never backed up). Counter persisted BEFORE compare; free tries 1–4, then 60 s … 960 s, 10th wrong try disables the PIN; re-enabled by a password login or a new PIN. Clock-back safe (`seen`). API: `verify(name,pin,wait_out)`, `set`, `change`, `remove_checked`, `status`, `has_pin`, `password_ok`. **Not sealed by a TPM** (stated in the file). | **Yes** as the UV verifier and lockout counter. **No** as a key store: a stolen disk holds `/device/pinkey` and `/etc/pin` together. |
| `tools/vault/` in osum | smbios/hwid/backup round TRESOR | Device identity and backup tests; nothing to do with a secret store. | Unrelated (name clash only). |
| `kernel/user/key.fi` | round TRESOR | Data key wrapped by a passphrase, `key erase`. Header: "no authenticated cipher in this tree" (outdated: `std.crypto.chacha.aead_*` and `gcm.fi` exist now). | Concept (wrap/destroy) — superseded by slots below. |
| `kernel/app/ksiegel.fi` | round KONTO | Token seal with device key `/device/kontoschluessel`; own limits S1–S3 ("root can read the key, no TPM, crypto not audited"). | Pattern for the device-key slot; same honest limits apply. |
| Backup classes | `kernel/user/bsec.fi class_of` | `/device/` = NEVER (device key, machine identity, **TPM handles**), `/secrets/` = SECRET (encrypted backup, "the password vault and everything like it"). | **Yes** — vault files go under `/secrets/`, device keys under `/device/`. |
| Action bus identity | `docs/ACTION-BUS.md` 5.2 (AB-003) | Kernel stamps every task with a sticky ORIGIN label: `app:<name>`, `jarvis`, `compat:<app>`, `automation:<name>`, unlabelled = the signed-in user (uid 0 or the session uid). Labels only narrow; pids are never reused. Reserved bus names: `orient.*` only for an unlabelled root process. Critical actions always ask and are never granted. | **Yes** — the basis for caller identity. |
| TPM | `docs/LAPTOP-HW-FEASIBILITY.md` X7, `BLECH-BEREIT.md`, `grep tpm kernel` | No TIS/CRB driver, no TPM2 commands, no measured boot, Secure Boot off. Only comments. Whether the HP has a usable TPM is **not measured** (r2417 probes it). | Later; design must work without it. |
| Entropy | `lib/entropy/{pool,drbg,health,seedfile}.fi`, `SYS_GETRANDOM` 318 | A DRBG and health checks exist. | vaultd must refuse key generation while the kernel RNG reports "not seeded". |

---

## 2. Goals and non-goals

Goals
1. One sealed store for logins AND passkeys, used by Certus and by the system (login helper, Settings, `vaultctl`).
2. Works completely offline, with no account. Sync is an optional layer on top (`docs/PASSWORT-SYNC.md`).
3. Secrets never leave vaultd except through a narrow, identity-checked, rate-limited API. Anything an AI agent or script can reach through the action bus never contains a secret.
4. User verification (UV) happens in a prompt that vaultd owns, not in the caller.
5. One format library shared by Certus (all platforms) and OrientOS — no copy.

Non-goals (v1)
- Not a TPM driver (separate roadmap items), not biometrics, not a hardware token, not browser autofill UI (Certus), not sync.
- No protection against root on the running device (same limit as `ksiegel.fi` S1).

---

## 3. Format strategy: one Firn library

**Owner and location.** The Firn repository (`/root/firn`, MPL-2.0, like `std.crypto.*`). New directory `lib/vault/`, plus `lib/std/cbor.fi` and `lib/webauthn/` (see `authenticator.md`). Certus and OrientOS consume it through their Firn pins; OrientOS may mirror files into its `lib/` while the pin lags (the `lib/FROM-FIRN.md` mechanism, with the byte-identity check script).

**Modules**

| Module | Content |
|---|---|
| `std.cbor` | deterministic encoder (CTAP2 canonical form), strict decoder (definite lengths only, depth ≤ 8, total ≤ 64 KiB, no duplicate map keys, unknown types rejected), fuzz target |
| `vault.container` | header, key slots, body AEAD; `open_any` reads v1 (`CERTUSTRESOR`) and v2; `seal`, `rewrap`, `slot_add`, `slot_remove`, `check_header`, limit checks |
| `vault.record` | typed records (§5) on `std.cbor`; unknown fields preserved on rewrite |
| `vault.merge` | last-writer-wins by `(id, modified_ms)` with tombstones; commutative/associative/idempotent (property test as in Certus `tools/account/eigenschaften.py`) |
| `vault.migrate` | v1 plaintext (TRESOR-FORMAT §5 and the `pwstore` line format) → v2 `login` records |

The in-process users (Certus on Linux/Windows/Android, host tests) call the lib directly with a password slot. On OrientOS, Certus talks to vaultd instead (§4), and vaultd uses the same lib.

**Migration Certus → lib (P1-2)**
1. Move `vault.fi`, `vault_main.fi` and `tools/vault/*` into Firn unchanged except imports; module path `vault.vault` stays as a shim re-exporting `vault.container` for one release.
2. Delete Certus `vault/argon2.fi`; import `std.crypto.argon2`. Proof: `kdf-vectors.json`, `argon2_test.sh`, `argon_vault_test.py` stay green byte for byte. Same for `aes256.fi` → `std.crypto.aes` (`aes256_new` + CBC decrypt) with `aes256_test.sh`.
3. v1 files stay readable forever. The v1 labels (`certus tresor v1 enc/mac/check`, magic `CERTUSTRESOR`) are on-disk format and are not renamed, brand or no brand.
4. First unlock of a v1 file in vaultd (or in Certus with the new lib) writes a v2 file; the v1 file is kept as `.v1.bak` until the v2 file re-opens successfully. Same pattern as the existing PBKDF2 → Argon2id auto-rewrite.
5. The OrientOS duplicates of Argon2id (`lib/crypto/argon2.fi`, used by `dcrypt`, `cryptopen`, `kernel/crypto/kargon.fi` with an SMP path) are NOT part of this work; replacing them is a separate low-priority roadmap item.

---

## 4. vaultd architecture

```
 Certus (app:certus)      Settings / vaultctl / lock UI (unlabelled user)
        │  kernel bus                 │
        ▼                             ▼
 ┌──────────────────────────────────────────────┐   action bus (thin, no secrets)
 │ vaultd  (bus name orient.vault, root)         │◄── vault.status / vault.lock / vault.unlock
 │  policy · rate limit · unlock state · records │
 │  authn (CTAP2 engine)    prompt broker        │──► vaultprompt (fUi, top layer, input-grabbed)
 └───────┬───────────────────┬──────────────────┘
         │ vault lib          │ pin.fi verify / TPM unseal (later)
         ▼                    ▼
 /secrets/<user>/vault.vlt   /etc/pin, /device/*
```

**Process.** `/bin/vaultd`, one instance for the machine, started by the service supervisor. Runs as root because the reserved bus names `orient.*` are only granted to an unlabelled root process (`bus.fi name_ok`). Files are `root:root 0600`; the user's own processes cannot even copy the sealed file. If a later kernel change allows a dedicated service uid, vaultd moves to it without any format change.

**Per-user vaults.** One vault per uid: `/secrets/<user>/vault.vlt` (dir 0700), plus `vault.vlt.bak` (previous generation) and `state` (see §6). The vault used for a request is the vault of the uid the KERNEL stamped on the sender. Class SECRET in backups (the sealed file is safe to back up); `/device/vault*` is NEVER.

**Transport.** Kernel-bus service `orient.vault`. Frames: 1 octet op, 1 octet flags, then a deterministic CBOR map (the same codec as CTAP). Authenticator requests carry the CTAP2 CBOR request unchanged (§9 of `authenticator.md`). Open question for P1-3: maximum bus payload (the action bus notes 2 KB); the largest normal frame is a passkey record list page — paginate to ≤ 1.5 KB, or add chunking.

**Caller identity.** vaultd never believes names in the request. Per message it takes pid/uid from the kernel stamp and reads the ORIGIN label (`/proc/<pid>/status`, `Origin:`). Because labels are sticky and pids are never reused, the lookup cannot be raced (AB-003 argument).

**Client classes and rights** (file `/etc/vault/clients`, root 0600, edited only through the user class with UV; default content below):

| Caller | Allowed ops (after unlock where marked) |
|---|---|
| unlabelled, uid = signed-in user (Settings, `vaultctl`, desktop) | `status`, `create`, `unlock`/`lock`, `change_password`, `slot_*`, `list_meta`, `export_sealed`, `import`, `delete`, `allow`/`deny` clients. `reveal` (show a secret) and plaintext CSV export need UV in the prompt EVERY time. |
| `app:certus` | `pw.find(origin)` (only entries whose origin matches the page origin the browser passes), `pw.save`, `pw.update`, `pw.list_meta` (title/user only), `authn.*` (makeCredential, getAssertion, getInfo, selection). No `reveal`, no export, no enumeration of secrets. |
| `jarvis`, `automation:*`, `compat:*`, every other `app:*` | `status` only. Secret-bearing ops are hard-denied and **cannot be granted through the action bus** ("critical is never granted"). The user can add an explicit line for a named `app:<x>` in `/etc/vault/clients`; each such line is logged and shown in Settings. |
| uid of another person | nothing (their own vault only). |

**Action-bus exposure (thin).** Only `vault.status` (read), `vault.lock` (write), `vault.unlock` (critical: opens the secure prompt, returns ok/denied, never a secret) are published. There is no `vault.get`. This keeps the AI and script path structurally free of secrets.

**Rate limits.**
- Per caller label: secret-bearing requests token bucket, burst 10, refill 1 per 6 s; over the limit → error `RATE` (no prompt).
- At most ONE prompt open per caller and ONE on screen overall; new requests queue (max 4) or fail `BUSY`. Prompts time out after 60 s (matches WebAuthn timeouts).
- Wrong unlock attempts: see §6.
- Frame size limits and CBOR limits (depth 8, 64 KiB) before any parse.

**Secure prompt.** `vaultprompt` is a separate fUi process spawned by vaultd (label SYSTEM), shown as a top-layer window with input grab, like the lock screen (the `wm.set_layer` / `release+restore_geom` lessons from lockseal A-036 apply). Content it shows is built by vaultd, not by the caller: operation, relying party id / site, account name, UV method. Requirements (each gets a gate check): synthetic input from `keys`/`ui` adapters (`compat:*`, AB-008b) must be rejected while the prompt is up; screenshots of the prompt are not offered to `app:*`; no other window can overlap it. Design in the fUi design system with an HTML mockup first (Boss rule), reports/mockups/.

**Clipboard and display.** `reveal` shows the secret in the prompt window itself with a 15 s auto-hide; copying uses the system clipboard with auto-clear after 30 s (clipboard lives on the kernel bus, `docs/SYSTEMBUS.md`). Output of `vaultctl get` goes to fd 1 only (idea kept from `kernel/user/vault.fi`).

---

## 5. Container v2 and records

All integers big-endian. Brand-neutral magic (the product name is configurable; formats must not carry it).

```
off  len  field
  0    8  magic "VAULT2\0\0"
  8    2  header_len (to the end of the slots)
 10    1  slot_count (1..8)
 11    1  flags (bit0: contains passkeys)
 12    4  body_len
 16   16  vault_id (random, never changes)
 32    8  revision (monotonic, +1 per save)
 40    ·  slots[slot_count]
 ·    16  body_salt (random per save)
 ·  body_len  body = AEAD(subkey, nonce 0, aad = all octets before body_salt .. incl. salt, cbor(records)) + 16 tag
```

Body key per save: `subkey = HKDF-SHA256(salt = body_salt, ikm = VK, info = "vault2 body", 32)`. Because the subkey is unique per save, the AEAD nonce is the fixed zero nonce — no nonce-collision budget to reason about. AEAD = ChaCha20-Poly1305 (`std.crypto.chacha.aead_seal/aead_open`, RFC 8439). The tag covers the header, slots and revision, and is verified before any decryption or parse (Certus decisions 1 and 2, kept).

**VK** = 32 random octets generated at creation, never derived from a password. Slots wrap VK:

| Slot kind | Content | Notes |
|---|---|---|
| 1 `pw` | `kdf=2 (Argon2id)`, m_kib u32, t u8, lanes u8, salt16, nonce12, `AEAD(KEK, VK)` 48 octets; `KEK = Argon2id(password, salt, ...)` | Default 64 MiB × 3 × 1 (RFC 9106 second recommendation, ~1 s release build; measured in Certus). Read limits 1 GiB / 16 / 64 before allocating. Min password length 8 (Certus rule). |
| 2 `login` | like `pw`, KEK from the account password (+ device key) | Lets the vault open at sign-in with zero extra typing when the account password was typed; absent after PIN sign-in. Optional, user can disable. |
| 3 `tpm` | TPM2 sealed object holding VK; policy PolicyAuthValue (authValue = PIN-derived) + TPM dictionary-attack lockout | Only with TPM (P2). The only slot that makes a short PIN safe against a stolen disk. |
| 4 `recovery` | `AEAD(HKDF(recovery_key), VK)`; recovery key = 256 random bits shown once as 12 groups of 4 base32 characters | Printed/stored by the user; optional but offered at creation. |
| 5 `device` | VK wrapped by `/device/vaultkey` | **Reserved, not enabled by default**: a key on the same disk gives no offline protection (honest limit as `ksiegel.fi` S1). Allowed only when full-disk encryption is active (`CRYPT-BOOT.md`). |

Changing password/PIN rewrites one slot; the body is untouched. Revoking an unlock method removes the slot AND rotates VK if the old slot content may have leaked (user choice "I think it was exposed").

**Records.** Body = deterministic CBOR array of records; each record is a CBOR map with small integer keys. Unknown keys are preserved on rewrite (forward compatibility, sync between versions).

Common keys: `0` id (16 random octets), `1` type, `2` created_ms, `3` modified_ms, `4` deleted (tombstone flag; payload dropped after 90 days).

| Type | Keys |
|---|---|
| 1 `login` | `10` title, `11` origins [text] (https origins, ≥ 1), `12` username, `13` password, `14` notes, `15` totp_seed (reserved), `16` password_changed_ms |
| 2 `passkey` | `20` rp_id (≤ 253), `21` rp_name, `22` user_handle (≤ 64 octets, opaque), `23` user_name, `24` display_name, `25` credential_id (32 random octets), `26` alg (−7 ES256, −8 EdDSA), `27` private key (ES256: 32-octet scalar; EdDSA: 32-octet seed), `28` public key (cached COSE_Key), `29` sign_count u32, `30` flags: bit0 resident (discoverable), bit1 backup_eligible, bit2 backup_state, `31` uv_policy at creation (0 discouraged, 1 preferred, 2 required), `32` cred_protect (1–3), `33` last_used_ms, `34` creating origin (display only) |
| 3 `note` | `10` title, `14` text |
| 9 `meta` | device id of creator, format revision, last sealed export time (one per vault) |

Uniqueness rules: `credential_id` unique vault-wide; resident passkeys unique per `(rp_id, user_handle)` — a new makeCredential with the same pair replaces the old record (CTAP2 behaviour), the old one is kept as a tombstone with the same id so sync does not resurrect it.

Size budget: a passkey record is ~250 octets, a login ~200 + text. 1000 passkeys + 3000 logins ≈ 1 MB sealed; whole-file rewrite per change is acceptable. Saves are atomic: write `vault.vlt.new` → fsync → rename over `vault.vlt` after copying the old file to `vault.vlt.bak` → fsync directory. A save after every passkey creation is mandatory BEFORE the response goes out (a registered credential must never exist only in the RP).

**Sign counter policy.** Backup-eligible credentials report `signCount = 0` always (WebAuthn recommendation for synced credentials; avoids a write per assertion and rollback conflicts). The stored field is kept for future device-bound (TPM) credentials where a counter is meaningful.

---

## 6. Unlocking

State machine per vault: `LOCKED → UNLOCKED(until)`. VK lives only in vaultd memory, zeroed on lock (explicit zero fill; Firn has no mlock — note whether the kernel swaps; OrientOS has no swap file in the measured tree, to be re-checked in P1-3).

**Lock triggers:** lock screen / sign-out / suspend (S3) / idle timeout (default 15 min, setting) / `vault.lock` / vaultd restart. The existing sync-session idea (expiry) from `kernel/user/vault.fi` is reused as the idle timer.

**Unlock paths, strongest first**
1. **PIN + TPM slot** (needs P2). Prompt takes the PIN; vaultd asks the TPM to unseal VK; the TPM counts failures and locks out (DA lockout). Offline disk theft cannot brute force the PIN. After the TPM lockout the prompt says "use the main password".
2. **Login slot.** Sign-in with the account password makes `glogin` hand the password to vaultd once (kernel bus, unlabelled root caller only) → vaultd derives the login KEK and opens. After PIN sign-in this does not happen; the vault stays locked until step 1 or 3.
3. **Main password** (`pw` slot) typed in the prompt. Online attempts: free 3, then 2^n seconds (n=1.. up to 15 min) persisted in `/secrets/<user>/state` BEFORE the derivation (power-loss keeps the penalty); wall-clock set-back safe via a `seen` field (same trick as `pin.fi`). Offline guessing is bounded only by Argon2id cost.
4. **Recovery key** slot.

**PIN without TPM.** Honest answer: no key-protecting PIN. A 4–12 digit PIN with its verifier (`/etc/pin`) and device key (`/device/pinkey`) on the same disk can be brute-forced offline in seconds. Without a TPM (or FDE) the PIN is used ONLY as user verification (UV) for operations on an already unlocked vault, verified by `pin.fi verify` (online counter, back-off, 10-try disable, shared with login). Settings states this in plain words. So on an HP without a usable TPM: unlock = account password (login slot) or main password; UV = PIN.

**UV freshness.** A successful unlock by PIN/password counts as UV for the operation that triggered it. Otherwise each UV-required operation asks again; no "remember for 5 minutes" in v1.

**Lockout interplay.** `pin.fi` is the single counter for PIN UV. The 10th wrong PIN disables the PIN path everywhere (login and vault UV); a password login or setting a new PIN re-enables it (existing `password_ok` rule). vaultd never keeps its own PIN counter.

---

## 7. Backup, export, recovery

| Operation | Behaviour |
|---|---|
| System backup | `/secrets/` is class SECRET: the sealed file is backed up as is. Restoring needs a password/recovery key. `/device/*` (TPM handles, device key) is never backed up, so a restored vault on a new machine has only `pw`/`recovery` slots. |
| Sealed export | Copy of the container re-sealed with a fresh export password (`pw` slot only, no `login`/`tpm`/`device`). UV every time. Includes passkeys; this is the only way private keys leave the machine. Marks `backup_state` on the passkeys that were exported. |
| Import | Sealed vault files (v1/v2), Certus CSV importers (Chrome/Firefox/Bitwarden/1Password/KeePass, already in `pwstore.fi`). Passkeys import only from sealed containers. |
| Plaintext CSV export | Logins only, behind a critical confirmation with a warning; written by vaultd to a user-chosen path with mode 0600, never to stdout of a labelled caller. Passkeys are NEVER exported in plaintext. |
| Interchange with other providers | Possible future: FIDO Alliance credential exchange format (not evaluated here). Not planned for v1. |
| Recovery key | Optional slot 4. Loss of password AND recovery key = vault unrecoverable (no server can help, by design). |
| Crypto erase | Deleting the vault = removing the file; destroying `tpm`/`device` slots = removing those keys. Same flash caveat as `docs/CRYPTO-ERASE.md`. |

---

## 8. Threat model

| # | Attacker | Outcome / defence | Residual |
|---|---|---|---|
| A1 | Thief with the powered-off device or a disk image | Needs the password (Argon2id, slot limits checked) or recovery key. PIN does not open the vault unless a TPM slot exists. Backup copies have the same property. | Weak main password. TPM lockout state not measured. |
| A2 | Malware running as the signed-in user | Cannot read `/secrets` (root 0600). Must use the bus: `app:*` other than the allow-listed browser is denied; an unlabelled user-class program may list metadata but every `reveal`, export and every passkey signature needs a prompt on a grabbed top-layer window; rate limit and one-prompt rule stop prompt flooding. | A user-class program can wait for the user to approve a prompt that shows the operation; the user is the last line. Sandbox S-010 is the real fix. |
| A3 | Jarvis / scripts / adapters | `status` only; no grant path through the action bus; adapters cannot inject input into the prompt (gate). | A user who writes an allow line for an app takes the risk knowingly. |
| A4 | Root on the running device | Out of scope: can read vaultd memory and `/device`. Same limit as `ksiegel.fi` S1. | — |
| A5 | Malicious web page | Browser (Certus) enforces origin and rpId rules; vaultd shows the rp id in the prompt and rejects syntactically invalid rp ids; request carries the origin so vaultd re-checks suffix relation as defence in depth. | Public-suffix list handling is the browser's job. |
| A6 | Phishing look-alike domain | rp id is bound to each passkey; a wrong domain finds no credential. Passwords: `pw.find` matches origin exactly (scheme+host+port) unless the user adds an alias. | Users approving look-alikes for passwords. |
| A7 | File rollback / swap | `revision` is covered by the tag; `/secrets/<user>/state` remembers the highest seen revision and `vault_id`; a lower revision triggers a warning prompt (not silent accept). | An attacker who also rewrites `state` as root (A4). |
| A8 | Crash or power loss during save | Atomic rename with `.bak` generation; passkey response only after the fsync of the new file. | Flash translation layer lies about fsync (same caveat as CRYPTO-ERASE). |
| A9 | Memory disclosure after lock | VK and decrypted records zeroed on lock; no swap measured. | Compiler/optimizer dead-store removal — gate: read back the buffer after lock in a test guest. |
| A10 | Timing side channel | `p256.fi` is a Montgomery ladder with complete formulas and masks, "written to be constant time, not proven" (its own P2 note). Ed25519 shares the field code. | Not measured with dudect; documented limit. |
| A11 | Weak randomness | vaultd refuses to create keys until `lib/entropy` health says seeded; credential ids and keys come from `random_bytes`; P-256 nonces are RFC 6979 deterministic (hedged with fresh random). | Early-boot entropy on real hardware (HP) not measured. |
| A12 | Server / sync operator | Sees only the sealed container and metadata (`docs/PASSWORT-SYNC.md`). | Availability (overwrite/delete). |

---

## 9. Build orders (small, ordered)

Existing roadmap points keep their numbers; new ones are added (see the report). Order and dependencies:

```
 P0-1 std.cbor ─────────────┬───────────────► P3-0 lib webauthn ─┐
 P1-2a lib vault.container ─┤                                     │
 P2-1 TPM probe (r2417) ... independent                           │
                            ▼                                     ▼
 P1-2b Certus on the lib   P1-2c vault.record/merge/migrate ─► P1-3a vaultd core (+QEMU gate)
                                                                  │
                         P1-3b vaultprompt + mockup ◄─────────────┤
                         P1-3c clients policy + action-bus stubs ◄┤
                                                                  ▼
                         P2-2a UV by pin.fi        P3-1 authenticator in vaultd ─► P3-2 gate (python-fido2)
                         P2-2b TPM slot (needs P2-1)                              ─► P3-3 Certus WebAuthn (Certus job)
                         P6-1 name (Boss) ─► P6-2 Settings UI
                         P1-4 retire kernel/user/vault.fi (import G-* once)
                         P5-1 USB-HID client, P4 biometrics, P5-2 hybrid: later, independent
```

Gates (each build order names its own; all heavy runs through `/root/jarvis/bin/heavy`):
- `std.cbor`: RFC 8949 Appendix A vectors, round-trip, fuzz with mutation, differential test against `fido2.cbor` / Python `cbor2` when installed.
- `vault.container`: Certus `against.py` second implementation extended to v2; wrong password vs damaged file; header tamper (iterations/params) rejected by tag; slot add/remove/rewrap; limits; v1 files from Certus fixtures open.
- vaultd QEMU gate (`tools/vaultd/run.sh`): create/unlock/lock/list/get/put; origin matrix (certus yes, jarvis/script/other app no); rate limit; prompt singleton; lockout counter survives reboot; rollback warning; crash-in-save (kill between `.new` and rename).
- Authenticator gate: `authenticator.md` section 8.
