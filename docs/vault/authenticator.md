# Platform authenticator (CTAP2 / WebAuthn) in vaultd

Status: **design only** (31.10.2026, roadmap P3 / r2419–r2421). Nothing here is built. Read `docs/vault/vaultd.md` first (vault, slots, caller classes, prompt).

Goal: OrientOS acts as a WebAuthn **platform authenticator** with **discoverable credentials (passkeys)** stored in our vault. Certus (the browser, Firn-written) implements `navigator.credentials` and calls the authenticator over the kernel bus; other browsers can later use the same interface. External keys (USB-HID, phone) are a client-side matter (P5) and reuse the same CBOR codec.

---

## 1. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | The authenticator speaks **CTAP2 CBOR** (command byte + CBOR map) over the bus, not a custom JSON. | One code path for bus, USB-HID later, and python-fido2 as an independent test client. |
| D2 | Algorithms: **ES256 (−7)** and **EdDSA (−8, Ed25519)**. ES256 is preferred when the RP lists both with ES256 first; the RP's order wins. RS256 is NOT offered. | Primitives exist (`std.crypto.p256`, `std.crypto.ed25519`); ES256 is what every RP accepts. |
| D3 | Attestation: **`none` only** in v1. `fmt = "none"`, `attStmt = {}`, AAGUID = 16 zero octets in authenticator data. Any RP attestation preference (direct, enterprise) is answered with `none`. | Privacy; no attestation key to protect. A product AAGUID can be registered later; it is a constant in brand config, not code. `packed` self attestation is optional later (P3-2 tests whether any RP in the target set needs it). |
| D4 | Every credential is stored in the vault, resident or not. `rk=true` only sets the discoverable flag. | No key-wrapping into credential ids needed; allowList lookup works; simple. |
| D5 | **UV is done by the authenticator itself** (built-in UV, option `uv`), never through `pinUvAuthParam`. Requests with `pinUvAuthParam` (key 8 / 9) are answered `CTAP2_ERR_UNSUPPORTED_OPTION` (0x2B). | Platform authenticator model. PIN stays inside vaultd's prompt; the browser never sees it. |
| D6 | UV methods: PIN verified by `pin.fi` (shared counter with login), account password, TPM unseal of the `tpm` slot (when it exists). UP (presence) = pressing "Allow" / Enter on the physical keyboard in the prompt. Both are shown by the secure prompt owned by vaultd. | `vaultd.md` §4, §6. |
| D7 | Default policy: UV is performed for every makeCredential and every getAssertion, whatever the RP asked (`required` / `preferred` / `discouraged`), and the UV flag reflects what happened. A setting "ask for UV only when the RP requires it" exists but defaults off (Hello-like). | Passkeys are bearer secrets for the account. |
| D8 | `signCount` is always 0 for backup-eligible credentials (BE=1). Flags: UP, UV when verified, AT on creation, BE=1, BS=0 until a sealed export/sync copy exists, then BS=1. | WebAuthn guidance for synced passkeys; see `vaultd.md` §5. |
| D9 | The browser enforces origin and rpId rules (it is the WebAuthn client). vaultd additionally rejects syntactically invalid rp ids and checks suffix relation when the request carries `origin`. The rp id and account name shown in the prompt come from vaultd, not from the caller's strings alone. | `vaultd.md` threat A5. |

---

## 2. Bus envelope

Service `orient.vault`, op `authn`. Request frame (deterministic CBOR map):

| Key | Type | Meaning |
|---|---|---|
| 1 | uint | CTAP command byte: 0x01 makeCredential, 0x02 getAssertion, 0x04 getInfo, 0x0B selection |
| 2 | bstr | the CTAP2 request map, exactly as defined by CTAP2.1 (no leading command byte) |
| 3 | tstr | `origin` of the calling page (browser-supplied; used for the defence-in-depth check and the prompt) |
| 4 | tstr | `topOrigin` (optional, cross-origin iframes: refused unless the RP allows it — v1 refuses with `CTAP2_ERR_NOT_ALLOWED`) |
| 5 | uint | timeout in ms (clamped to 10 000 .. 120 000, default 60 000) |
| 6 | bstr | cancel token (16 octets) so the browser can abort a pending prompt |

Response: `status` octet (0x00 OK, else CTAP2 error code from §6) then the CTAP2 response map. A `BUSY` / `RATE` / `LOCKED` outcome maps to the closest CTAP code (`CTAP2_ERR_NOT_ALLOWED` 0x30 for denied by policy/user, `CTAP2_ERR_OPERATION_DENIED` 0x27 for UV failed or declined, `CTAP2_ERR_KEEPALIVE_CANCEL` 0x2D for cancel, `CTAP2_ERR_USER_ACTION_TIMEOUT` 0x2F for the 60 s timeout).

Caller must be `app:certus` (or a user-listed browser) — vaultd.md §4 table. Anyone else gets `CTAP2_ERR_NOT_ALLOWED` before any prompt.

---

## 3. authenticatorGetInfo (0x04)

Response (CBOR map, keys per CTAP 2.1):

```
1 versions        ["FIDO_2_0", "FIDO_2_1"]
2 extensions      ["credProtect"]                       (hmac-secret, credBlob, largeBlob: later)
3 aaguid          16 x 0x00
4 options         {"rk": true, "up": true, "uv": true, "plat": true, "clientPin": absent,
                   "credMgmt": absent, "authnrCfg": absent}
5 maxMsgSize      1200
10 algorithms     [{"alg": -7, "type": "public-key"}, {"alg": -8, "type": "public-key"}]
9 transports      ["internal"]
```

`uv: true` means built-in UV is configured (a PIN or password verifier exists). If neither exists the field is `false` and makeCredential with `uv` fails with `CTAP2_ERR_UNSUPPORTED_OPTION`.

---

## 4. authenticatorMakeCredential (0x01)

Input keys: 1 clientDataHash (32 octets), 2 rp {id, name?}, 3 user {id ≤ 64, name?, displayName?}, 4 pubKeyCredParams, 5 excludeList?, 6 extensions? (credProtect only), 7 options? {rk, up, uv}, 8/9 not accepted (D5).

Order of checks (the order matters for error codes and for not prompting needlessly):
1. Strict CBOR parse with limits; missing mandatory key → `CTAP2_ERR_MISSING_PARAMETER` (0x14); wrong type → `CTAP2_ERR_CBOR_UNEXPECTED_TYPE` (0x11); malformed → `CTAP2_ERR_INVALID_CBOR` (0x12); `clientDataHash` length ≠ 32 → `CTAP2_ERR_INVALID_LENGTH` (0x03).
2. rp.id syntax (ASCII lowercase host, ≤ 253, no scheme/port/path); user.id ≤ 64.
3. Algorithm: first entry of `pubKeyCredParams` with type `public-key` and alg in {−7, −8}; none → `CTAP2_ERR_UNSUPPORTED_ALGORITHM` (0x26).
4. Vault locked? → open the unlock prompt (it doubles as UV if it succeeds).
5. `excludeList`: any listed credential id that exists for this rp → prompt "already registered" (UP) then `CTAP2_ERR_CREDENTIAL_EXCLUDED` (0x19). Applies to resident and non-resident records alike.
6. Secure prompt: operation "Create a passkey", rp id (bold), account name, UV method; Allow/Deny. Deny → `CTAP2_ERR_OPERATION_DENIED` (0x27).
7. Key generation: ES256 — random 32 octets, rejection-sample until `p256_scalar_valid`, public key via `p256_public`; EdDSA — 32 random octets as seed, `ed25519_public`. `credential_id` = 32 random octets. Entropy health required.
8. Replacement rule: resident with same `(rp.id, user.id)` → old record tombstoned in the same save.
9. **Save the vault (atomic, fsync) before building the response.** Save failure → `CTAP2_ERR_KEY_STORE_FULL` (0x28) (also used for I/O errors); nothing is returned.
10. Response `{1: "none", 2: authData, 3: {}}` with
    `authData = SHA-256(rp.id) ‖ flags ‖ signCount(4, =0) ‖ aaguid(16, =0) ‖ credIdLen(2) ‖ credId ‖ COSE_Key ‖ [extensions CBOR]`,
    flags = UP(0x01) | UV(0x04 when verified) | BE(0x08) | BS(0x10 when applicable) | AT(0x40) | ED(0x80 only if extensions present).
    COSE_Key ES256: `{1: 2, 3: -7, -1: 1, -2: x(32), -3: y(32)}`; EdDSA: `{1: 1, 3: -8, -1: 6, -2: x(32)}`, deterministic encoding.
11. credProtect: levels 1–3 recorded; level 3 (`userVerificationRequired`) makes getAssertion without allowList and without UV return no credentials; level 2 hides credentials from a getAssertion without allowList unless UV. With D7 (UV always) level 1–3 behave the same in v1; the stored level is honoured as soon as the setting in D7 is turned off.

## 5. authenticatorGetAssertion (0x02)

Input keys: 1 rpId, 2 clientDataHash, 3 allowList?, 4 extensions?, 5 options? {up, uv}, 6/7 not accepted (D5).

1. Parse and validate as above.
2. Candidate set: with `allowList` — records whose `credential_id` matches an entry and whose rp matches; without — resident passkeys for the rp. Empty → `CTAP2_ERR_NO_CREDENTIALS` (0x2E) **without any prompt** (no user-visible side channel for "do you have an account here"; the browser decides what to show).
3. Vault locked → unlock prompt.
4. Prompt: operation "Sign in", rp id, and when several candidates exist an account chooser (user name, display name). `numberOfCredentials` is therefore omitted from the response; `getNextAssertion` (0x08) is not implemented (`CTAP1_ERR_INVALID_COMMAND` 0x01).
5. Signature: `sig = Sign(sk, authData ‖ clientDataHash)`. ES256: `p256_sign` over SHA-256 of that concatenation, hedged RFC 6979 nonce, DER via `p256_sig_der`; EdDSA: `ed25519_sign` over the raw concatenation (64 octets). `authData = SHA-256(rpId) ‖ flags(UP, UV, BE, BS) ‖ signCount(=0)` (no AT).
6. Response `{1: {"id": credId, "type": "public-key"}, 2: authData, 3: sig, 4: {"id": user.id [, "name", "displayName" when multiple candidates]}}`.
7. `last_used_ms` is updated and saved after the response is built; a failed save does not block the sign-in (counter is 0, nothing the RP depends on).

## 6. Other commands and error map

- `authenticatorSelection` (0x0B): prompt "Touch to select" → OK or 0x27/0x2F.
- `authenticatorReset` (0x07) and credential management (0x0A): NOT exposed on the bus. Deleting or listing passkeys is a vault operation done in Settings by the unlabelled user class with UV.
- Any other command byte: `CTAP1_ERR_INVALID_COMMAND` (0x01).
- Error codes used (CTAP2.1): 0x01, 0x03, 0x11, 0x12, 0x14, 0x19, 0x26, 0x27, 0x28, 0x2B, 0x2D, 0x2E, 0x2F, 0x30, plus 0x7F `CTAP1_ERR_OTHER`.

## 7. User verification details

| Case | Behaviour |
|---|---|
| PIN set (`pin.has_pin`) | Prompt asks for the PIN, `pin.verify(user, pin, wait)`. Wrong PIN consumes one try of the shared counter (persisted before compare); `R_LOCKED` shows the remaining delay; `R_DISABLED` → "use your password". |
| No PIN | Account password via the normal check, or the vault main password; both counted by their own back-off. |
| TPM slot present | PIN is passed to the TPM unseal; the TPM's own lockout applies; also unlocks the vault in the same step. |
| No verifier configured | `uv: false` in getInfo; Settings asks to create a PIN; UP-only credentials are not created (passkeys without UV are refused in v1). |
| Prompt cancelled by the browser (cancel token) | Prompt closes, `0x2D`. |

## 8. Test plan

Principle: an independent implementation on the other side of every interface (the Certus rule "a crypto block checked only against itself proves it gets the same thing wrong twice").

**Environment.** Python package `fido2` (python-fido2): `pip download fido2` was verified to work on the JARVIS server on 31.10.2026; it is NOT installed yet and the exact version is recorded when the gate is created. `cryptography` 38.0.4 is installed (P-256, Ed25519 verify). `cbor2` is not installed (python-fido2 has its own `fido2.cbor`). Everything runs in a venv under the gate directory.

**Layers**
1. **CBOR (`std.cbor`)** — RFC 8949 Appendix A vectors (encode/decode round trip), deterministic-encoding checks (CTAP2 canonical ordering), rejected inputs (indefinite length, duplicate keys, depth 9, truncated, trailing bytes), mutation fuzz (1e5 inputs, no crash, no allocation above the limit), differential run against `fido2.cbor`.
2. **Primitives** — RFC 6979 A.2.5 (P-256/SHA-256) nonce and signature vectors, RFC 8032 Ed25519 vectors (already in Firn tests; re-run in the gate), `p256_public` vs `cryptography`, every produced signature verified by `cryptography`.
3. **Authenticator logic on the host** — a Firn program `authn_main.fi` (stdin/stdout frames like Certus `vault_main.fi`) with an in-memory vault and a scripted "prompt" (answers set by a test flag: allow, deny, wrong PIN, timeout). A Python driver implements a `fido2` `CtapDevice` subclass whose `call(cmd, data)` pipes to `authn_main`; then python-fido2's `Ctap2` and `Fido2Server` do the real work:
   - `Fido2Server.register_begin` → client data → our makeCredential → `register_complete` verifies attestation `none`, rpIdHash, flags, AT data, COSE key, credential id length.
   - `authenticate_begin/complete` verifies the signature with the registered public key, rp hash, flags (UV/UP/BE/BS), `signCount` handling (0 accepted).
   - Discoverable flow without allowList; two accounts for one rp (chooser); replacement by `(rp, user.id)`; ES256-only and EdDSA-only `pubKeyCredParams`; mixed order.
   - Negative matrix: excluded credential (0x19), unknown rp (0x2E, no prompt asserted), unsupported alg only (0x26), `pinUvAuthParam` present (0x2B), `clientDataHash` 31 octets (0x03), missing rp (0x14), wrong types (0x11), garbage (0x12), user denies (0x27), timeout (0x2F), cancel (0x2D), save failure injected (0x28 and credential NOT registered), vault locked → unlock path.
4. **Cross-checks with fixed vectors** — use the python-fido2 repository's recorded makeCredential/getAssertion examples (parse with ours as a verifier of authData layout) and the CTAP 2.1 specification example CBOR messages; for COSE keys the RFC 9052/9053 examples. Where a vector cannot be found offline it is generated by python-fido2 and committed as a fixture with the generator.
5. **QEMU gate** (`tools/vaultd/authn.sh`, after P3-1) — real vaultd + bus: a test client labelled `app:certus` registers and signs in; a client labelled `jarvis`, `automation:x`, `compat:y` and a second `app:z` get 0x30 and NO prompt window appears (pixel check of the screen); one prompt at a time; synthetic keystrokes from a `keys` adapter do not answer the prompt (gate with the AB-008b adapter); wrong PIN ×5 survives a reboot (counter persisted); credential survives reboot and is signed again; `kill -9` of vaultd between key generation and save leaves no ghost credential and no half-written file; rollback warning when an older vault file is put back.
6. **Browser end-to-end** (Certus work, P3-3) — against a local RP built with python-fido2's `Fido2Server` served over https with a test certificate, and against the public WebAuthn test pages as a manual check (the Boss tests on the HP; project_needs when ready).

**Pass criteria.** All layers green, plus the negative matrix; the gate counts OK/FAIL like the other gates and goes into `tools/qa/gates.tsv` (tier: full; the QEMU part nightly).

## 9. Out of scope in v1 (written down on purpose)

hmac-secret / PRF, largeBlob, credBlob, enterprise attestation, `packed` attestation, cross-origin iframes, getNextAssertion, credential management over CTAP, CTAP1/U2F, caBLE/hybrid transport (P5-2), USB-HID server mode (OrientOS as a USB key), biometrics (P4), device-bound TPM credentials with real counters.

## 10. Naming

The user-visible name of the feature (prompt title, Settings page, Certus "use <name>") is read from brand config only: new key `KEYNAME` in `marke.conf` with a `{{KEYNAME}}` placeholder and an accessor `brand.keyname()` / `/proc/brand keyname=` (mechanism: `docs/BRAND-KERNEL.md`). Proposal "Xoffi Key"; not "Hello". The Boss decides (project_needs); until then the key defaults to the product name plus "Key". The word never appears in formats, labels or AAGUID.
