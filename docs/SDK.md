# OrientOS SDK -- app manifest v2, project template, `osdk`

Status: **host tool built and tested** (`bash tools/sdk/run.sh`). Runtime enforcement of
permissions is NOT built (S-010); only `net` is enforced today (via `net=` of netview).

## Tool

    python3 tools/sdk/osdk.py new org.example.hello [--kind app|service] [--perm net,notify]
    python3 tools/sdk/osdk.py check <project>        # lint manifest v2
    python3 tools/sdk/osdk.py build <project> --out DIR
    python3 tools/sdk/osdk.py perms

`new` creates `INFO`, `src/main.fi`, `symbol.txt`, `README.md` from tools/sdk/template
(kind `service` = a bus service on rpc.fi). `build` compiles `src/*.fi` with the SDK modules
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

`net` enforced (netview). `notify clipboard.read clipboard.write fs.home audio.play`: **declared only**
(lint warns). `min_os` declared only (the OS has no version number yet).
