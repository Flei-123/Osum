# Library parts that came from Firn and now live here

Since the Firn pin moved to `c8bf10fe` (round FUI-ALL, 30.09.2026), the
public Firn repository no longer carries these modules. OrientOS still
needs them (`kernel/app/knetz.fi`, `fetch.fi`, `jarvisd.fi`, `fcrelay.fi`,
`ksiegel.fi`), so they are kept in this tree, exactly as they were in the
old pin `7b4c22b1` **with Osum patch 0003 already applied** (the callers
look at the answer of `buf_reserve`):

| path here | was in Firn |
|---|---|
| `lib/tls/` (der, keys, tls, x509 + the two `_main` checks) | `lib/tls/` |
| `lib/std/crypto/{big,chacha,crypto_main,ecdsa,gcm,hkdf,rsa,sha512,x25519}.fi` | `lib/std/crypto/` |

`$FIRNLIB` points at this `lib/`, so `import tls.tls` and
`import std.crypto.chacha` resolve here first; everything else under
`std.*` still comes from the pinned Firn library (`vendor/firn/lib`).

Licence: MPL-2.0 (Firn), author Justin — unchanged, see the SPDX lines.
Patch 0003 was dropped from `vendor/firn/patches/` because its target
files are no longer in Firn; its change is contained in these copies.
