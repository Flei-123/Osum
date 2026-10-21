# OrientOS SDK -- app manifest v2, project template, `osdk`

Status: **host tool built and tested** (`bash tools/sdk/run.sh`). Runtime enforcement of
permissions: see "Permissions" below (AR-2).

## Tool

    python3 tools/sdk/osdk.py new org.example.hello [--kind app|service|gui] [--perm net,notify]
    python3 tools/sdk/osdk.py check <project>        # lint manifest v2
    python3 tools/sdk/osdk.py build <project> --out DIR
    python3 tools/sdk/osdk.py perms

`new` creates `INFO`, `src/main.fi`, `symbol.txt`, `README.md` from tools/sdk/template
(kind `service` = a bus service on rpc.fi; kind `gui` = a window on fUi's scene tree: `profile app`, label + text field +
main button that counts; `build` then copies the import closure of `wlib/fuiapp/fuiscene` and links with `--gc-sections`, ~0.9 MB;
gate `tools/sdk/gui.sh`; see the window without a VM: docs/HOST-PREVIEW.md). `build` compiles `src/*.fi` with the SDK modules
(`ulib`, `actwire`, `rpc` from kernel/user) next to them, writes `DIR/bin/<short>.elf`,
`DIR/apps/<short>.osp/{INFO,symbol,data/}` and `DIR/mkfs.lines` (arguments for tools/osum/mkfs.py).
No SYSTEM marker: a third-party app is labelled by the kernel.

## Manifest v2 = the INFO file (same file the launcher reads)

Launcher keys stay on top (<1023 octets): `name info keys icon exec fassung net`.
v2 keys: `manifest=2` (required) `id` (reverse-DNS, last part = bundle name) `version` (X.Y.Z)
`author license min_os perm service actions opens needs`; custom keys `x-...`.
Lint refuses: unknown/duplicate keys, bad id/version, bundle name equal to a system app,
service outside the app namespace or >16 octets, unknown/duplicate permission,
`net` contradicting `perm`, ACTIONS file refused by tools/actionbus/manifest.py or `app` != bundle name.
`build` derives `net=real` when `perm` has `net`, else `net=none` (enforced by netview).

## Permissions

State of AR-2 (docs/APP-RECHTE-ENERGIE.md). The manifest `perm=` (INFO file) is the CEILING of an app: the kernel never grants more
than the app declared. The kernel table of 16 apps (`lib/apprights/policy.fi`), `/bin/apprights` and `/etc/apprights.conf` hold what
the person actually granted (default deny).

- **Enforced by the kernel:** `net notify clipboard.read clipboard.write audio.play mic window.float hotkey`.
- **Declared only:** `fs.home` (S-010, no sandbox yet).
- **In the rights table, not yet in the manifest vocabulary:** camera, location, contacts, phone (bits `P_CAMERA P_LOCATION P_CONTACTS P_PHONE`).
- **`window.float`** (S2 built): a window above the normal ones, layer `L_FLOAT`, never `L_TOP`; without the right `WS_LAYER` returns `E_RIGHTS`, revoking it drops the window back to `L_NORMAL`.
- **`hotkey`** (S3 built, `docs/HOTKEYS.md`): the helper `hotkeyd` owns the key and calls the app's named bus action (e.g. `jarvismini.toggle`); a line in `/etc/hotkeys.conf` for an app without the right is refused, never bound. Granted by the person like the microphone, NOT in the automatic grant.
- `min_os` is declared only (the OS has no version number yet).
