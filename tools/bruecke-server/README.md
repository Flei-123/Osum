# Bridge server (copy of /root/bruecke on the JARVIS server)

`bruecke_server.py` is the service behind `store.fleitec.com/bruecke/*` (systemd unit `bruecke`).
It lives outside this repo on the server (`/root/bruecke`); this directory keeps a versioned copy
since 05.10.2026. `test_warum.py` runs a throw-away instance on port 18090 against a fake device
(Ed25519 key, the real wire protocol): 38 checks, `python3 tools/bruecke-server/test_warum.py`
(needs `cryptography`; it starts the server file from `/root/bruecke/`).

See `docs/BRIDGE-OFFLINE.md` for what the 05.10.2026 round added (why-offline record, `/bruecke/warum`,
job expiry, keepalive word `lebt`, `info`, Wake-on-LAN).

`vmtest_stage1.py` / `vmtest_stage2.py` drive a VM (`/root/dellw/vmrun.sh`, image built with the vm-device key and a
permissions file with `watchdog = 30`, `command_timeout = 300`) against the live bridge: keepalive during a 130 s
command, supervisor restart after `kill <worker>`, watchdog after a 30 s network cut (QEMU monitor `set_link n0 off`).
The paths inside are those of the JARVIS server.
