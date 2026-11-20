# Catalog schema 2 (unified apps view)

One signed `index.json`, still `"katalog": 1`, plus an additive block for phone and OrientOS clients.

Why `katalog` stays 1: every shipped client (Android app 1.x, `store` tool, `Katalog.lesen`) aborts on any other value. Schema 2 is announced by the new top-level key `schema: 2`. Old clients read only `pakete` (byte-identical to before; measured in `tests/t40_unified.py` and against the live catalog).

## Top level (new keys)

| key | meaning |
|---|---|
| `schema` | `2` |
| `categories` | `{id: {de, en}}`: development, internet, media, productivity, system, tools |
| `apps` | `{app id: app}` |

Written by `Katalog.schreiben` through `unified.apply`, so every publisher (store add, autorelease) emits it.

## App

`id`, `name{de,en}`, `summary{de,en}`, `description{de,en}`, `category`, `developer`, `license`, `listed`, `system`, `platforms[]`, `icons{72,44,64}`, `screenshots[]`, `permissions[]`, `tags[]`, `variants[]`, optional `rating`, `downloads`.

Variant: `package` (key in `pakete`, null for built-in system apps), `art` (`apk|opk|exe|bin|appimage|macos-app|system`), `platforms[]`, `versionName`, `versionCode`, `size`, `sha256`, `file`, `minOs{platform: level}`, `architectures[]`, `androidPermissions[]`, `changes`, `system`, `revision` (system only).

Platform words: `android-arm64|arm|x86|x86_64`, `osum-x86_64`, `osum-any` (every OrientOS machine), `windows-x86_64`, `linux-*`, `macos-*`.

## Rules

- One package id, one build per platform: Certus is `com.fleitec.certus` with an `apk` variant (android-arm64, android-x86_64) and a `system` variant (osum-any).
- System apps (settings, explorer, terminal, task manager, ...) come from the OS `INFO` files (`tools/catalog2/export_system_apps.py` in the Osum repo -> `werkzeug/unified_system/`). They carry `system: true` and a `revision` and are only offered on OrientOS.
- Where a downloadable `opk` exists for a system app, that variant gets `system: true` + `revision` instead of a second variant.
- Icons: derived from the package symbol (72/44/64 px PNG, content addressed under `symbole/`) or from the OS bundle SVG.
- Names, summaries, categories: `werkzeug/unified_meta.json` (de/en); missing text falls back to the package text, then the name.
- Client filter: `unified.apps_for(doc, [platforms], category)`; phone passes `android-*`, OrientOS passes `osum-x86_64` (matches `osum-any`). A catalog without `schema` is converted on the fly (`build_apps`).

## Gate

`python3 tests/t40_unified.py` (37 checks): schema, old-client view identity, platform filter, Certus on both sides, icons, system apps, plus counter-proofs: legacy catalog, missing required field, unknown category, bad sha256, missing icon, bad platform word, tampered catalog, foreign key.
`store verify` runs the schema check automatically; `store apps --platform <word>` shows the filtered view.

## Compatibility levels (per variant)

Every variant carries `compat`: `level` (`works|partial|broken|untested`, default `untested`), `tested_on {build, device}`, `tested_at` (YYYY-MM-DD), `notes {de,en}`, `limitations [{de,en}]`, `gate` (name of the test that backs the level). The publisher sets it (`werkzeug/compat.json` in `/root/orientstore`), never the user.

Rules checked by `unified_check` (and again by the client): `works` needs a `gate` plus `tested_on` and `tested_at`; `partial` needs notes and a limitations list; `broken` needs notes; `untested` carries no gate and no `tested_on`. A client shows a `works` variant without a gate as `untested`.

Platform words added: `osum-linux-x86_64` (Linux program over the Linux ABI) and `osum-windows-x86_64` (Windows program over Wine). A variant without payload yet has `available: false`.

## OrientOS client view (`apps.tsv`)

`stored` has no JSON parser and no heap, so the publisher writes a flat, signed view next to `index.json`: `apps.tsv` + `apps.tsv.sig` (Ed25519 by the catalog key, tab separated: `C` category, `A` app, `V` variant lines; `osview.py`). It is served from `/osum/aktuell/` (symlinks into `/srv/store`). `stored` fetches it on `store.refresh`, verifies it against the pinned catalog key (override: `/etc/store.catalog.pub`), and keeps it as `/var/store/apps`. A failed check removes the file, so nothing unverified is shown. Variants whose platforms are not OrientOS words are dropped.

Actions: `store.apps lang=` (categories, one `app=` line per app) and `store.app name=<id> lang=` (detail with one `variant=` line per platform).

Gate: `STORE_PART=apps bash tools/store/run.sh` (good view, flipped octet, foreign key, Android-only app, works without gate, bad names).
