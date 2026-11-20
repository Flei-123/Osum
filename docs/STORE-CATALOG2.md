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
