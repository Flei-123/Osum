# JARVIS bridge inside the laptop VirtualBox VM (16.10.2026)

Measured state: the VM `OrientOS` on HOLO-LAPTOP-3 (NAT, Intel PRO/1000 `82540EM`, MAC 08:00:27:0b:9e:67) boots the
personal image, `jarvisd` signs in at `store.fleitec.com/bruecke/` and runs jobs (`/bin/ls /etc/jarvis`, `/bin/cat
/proc/version` via `remote_shell`). No pairing code is needed: the device key is already paired.

## Two identities, never the same key twice
| image | key (JARVIS_DEVICE_KEY) | bridge id | name in list_devices |
|---|---|---|---|
| real Dell stick | /root/abbilder/justin-device.key | osum-a4206b26eb96 | Dell |
| laptop VM / QEMU test images | /root/abbilder/vm-device.key | osum-3807242d1d62 | OrientOS-VM |

Until now the laptop VM ran the Dell-key image, so it showed up as "Dell" and would collide with the real Dell.
**Build every image that goes to the laptop VM with `JARVIS_DEVICE_KEY=/root/abbilder/vm-device.key`**
(plus `JARVIS_CONF=/root/abbilder/justin-permissions.conf`). Names are pinned in `/root/jarvis/data/bruecke_devices.json`
(read by `lib/osumBridgeDevices.js` at server start).

## Checks
* VM NIC: `VBoxManage showvminfo OrientOS --machinereadable | grep -E 'nic1|nictype1'` -> `nat` / `82540EM`.
* Online: `GET /bruecke/geraete` (verwalter key) -> `verbunden: true`, MAC `08:00:27:…`.
* Gate for a fresh image: `tools/svclog/bootserie.sh` (jarvisd started + server reached).
