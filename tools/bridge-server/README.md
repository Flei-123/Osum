# Bridge server

`bridge_server.py` (+ `legacy.py`) is the service behind `store.fleitec.com/bridge/*` and the old `/bruecke/*` (systemd unit `bruecke`, installed in `/root/bruecke`, data `/srv/bruecke`). Names and dialects: `docs/BRIDGE.md` part II.

- `python3 tools/bridge-server/test_pairing.py` code pairing (pending, redeem, forget, TTL, cap, limiter)
- `python3 tools/bridge-server/test_why.py` current names, `test_legacy.py` old names (need `cryptography`, ports 18091/18092)
- `why.py [device]` prints why a device is offline
- `vmtest_stage1.py` / `vmtest_stage2.py` drive a VM against the live bridge
