# App manifest v2 -- one spec for native and web

Status: lint, migration, JSON schema, page output and store index are built and gated (`bash tools/manifest/run.sh`).
Runtime enforcement of permissions is unchanged (docs/SDK.md "Permissions").

One file describes an app for every output: the INFO file (`key=value`, read by the launcher and `osdk`). Its normalized
form is JSON (`osdk.py manifest <project>`, schema `docs/manifest-v2.schema.json`). Sources compared: OrientOS INFO +
`tools/sdk/template`, the OPK recipe (`pakete/*/rezept`, `tools/ota/listing.py` rows), Firn-page contract v1
(`<link rel="application" type="application/wasm">`, projects_kb/certus/FIRN-WEB.md section 2.3 `.firnpage` manifest with
a capability list), Firn services contract v1 (docs/services-contract.md in the Firn tree, main 52c0c4395).

## Keys

| key | rule | launcher | notes |
|---|---|---|---|
| `name` `info` `keys` `revision` | name 1..31, info 1..80, keys = search words, revision = whole number per release | yes (first 1023 octets) | `fassung` is the old spelling of `revision`: accepted, refused by `--strict`, rewritten by `osdk migrate` |
| `exec` `icon` `net` `menu` `hideif` | as before; `menu=show\|hidden` | yes | `exec` = JSON `native.entry` (default `start`); `icon` = file in the bundle (`symbol.svg` for web) |
| `manifest=2` `id` `version` | reverse-DNS id (last part = bundle name), `X.Y.Z` | no | required |
| `author` `license` `min_os` `needs` | free text, SPDX, `N[.N[.N]]`, `os>=N` / `app:<id>>=N` | no | strict needs non-empty author and license |
| `kind` | `gui` window on the scene tree, `app` console/daemon, `service` bus service (needs `service=`) | no | strict: required; without it `service=` implies `service`, else `app` |
| `outputs` | `native`, `web` or both | no | strict: required; default `native`; a `service` has no web output |
| `perm` | catalogue below | no | ceiling of the app |
| `service` `actions` `opens` `sandbox` | bus names (<=16 octets, app namespace), ACTIONS file, extensions, `files` | no | unchanged |
| `web.entry` `web.font` `web.memory` | `<name>.wasm`, `<name>.ttf`, MiB 16..4096 (default 256) | no | only with `outputs` containing `web`; project must hold an SVG icon (`symbol.svg`) |
| `x-...` | custom | no | kept under `custom` in JSON |

Launcher keys stay on top (<1023 octets); v2 keys go behind. Unknown/duplicate keys are errors.

## Permissions mapped to the services contract

`osdk.py perms` prints the table. Level: `enforced` = kernel/rights table, `implicit` = no standing grant, the person acts at
call time (picker/dialog), `declared` = only documentation (warning; `--strict` refuses).

| perm | service call (Firn `services.*`) | OrientOS backend | web backend |
|---|---|---|---|
| `files.open` / `files.save` | `svcfile.open` / `save` (name + content, never a path) | picker window (gap, see services-orientos.md) | `<input type=file>` / download |
| `clipboard.read` / `clipboard.write` | `svcclip.paste_text` / `copy_text` | transfer service (xfer, bus), enforced | clipboard API |
| `dialog` | `svcdialog.message` / `confirm` | `dialog.fi` | alert/confirm |
| `storage` | `svcstore.get/set/remove/has` | `/data/<name>/services/` | localStorage `firn.svc.<app>.<key>` |
| `notify` | (later `svcnotify`) | bus NOTIPOST, enforced | none yet: refused for web |
| `net` | -- | netview, `net=real` | same-origin `certus.fetch*` only |
| `mic fs.home audio.play hotkey window.float` | -- | enforced | no backend: refused for web |

JSON `services` lists the calls a manifest asks for; `web.capabilities` = `services` (any of files/clipboard/dialog/storage)
and `fetch` (net).

## Outputs

- native: `osdk build` as before (ELF + bundle). `native.net` = `net=` or `real` when `perm` has `net`.
- web: `osdk.py manifest <project> --format page` prints the host page of Firn-page contract v1:
  `<link rel="application" type="application/wasm" href=".." data-font="..">` plus
  `<meta name="firn-capabilities" content="services,fetch">`. The meta tag is the Firn proposal "capability `services`,
  contract v1.1", NOT agreed with Certus yet; a page without capabilities has exactly the v1 imports. Building the
  `.wasm` (`firnc --target=wasm32-browser`) is not done by `osdk` yet.

## Tools

    osdk.py check <path> [--strict] [--system]   lint; --strict = full v2 + no unenforced promises; --system = shipped app (folder = bundle name)
    osdk.py manifest <path> [--format json|page]
    osdk.py migrate <INFO...> [--kind gui|app] [--write]   append missing v2 keys, fassung -> revision; idempotent
    osdk.py new <id> [--kind] [--outputs native,web] [--author]
    storeindex.py <dirs|INFO...> [--system] [--opk DIR] [--require-files] [--out F]   store index (orientos.store-index/2)

Store index: sorted packages with the normalized fields (id, name, info, keys, version, revision, kind, outputs, menu,
permissions, services, native, web) and, with `--opk`, `file{name,sha256,size}` for `<bundle>-<version>.opk`. The signed
LISTING/VERZEICHNIS (OTA3/OTA2 rows: name version sha size file platform) is unchanged on purpose; the index is
UNSIGNED and informational until a Boss decision signs it with the listing key (open point).

## Migration state

All 27 shipped INFO files (`assets/apps/*`, `pakete/*`) pass `check --strict --system`; the 22 system bundles got
`manifest id version author license kind outputs` appended (`kind=gui`, `perm` only where `net=real`; their other rights stay in
the kernel table until audited). `pakete/xremote` is `kind=app`; its `info` was over 80 octets (old lint error), now shortened.
