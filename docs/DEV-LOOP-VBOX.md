# Dev loop: laptop VirtualBox first, server qemu for series (Boss decision 18.10.2026)

Standard loop: **code -> merge -> image on the server (heavy, `tools/usbimg/build.sh`, ~11 min) -> image to the laptop HOLO-LAPTOP-3
(HTTP, ~8 s) -> VirtualBox VM `OrientOS-Test` boots it (~25 s) -> a worker drives it (screenshots, keys, mouse, idle CPU, serial)
-> result + screenshots -> fix -> next round.** Tools and commands: `tools/vbox/README.md`.

## Who does what
| Task | Where |
|---|---|
| Acceptance of the real desktop: look (taskbar, tray, quick settings, glass, login), live resize, mouse feel, host CPU at idle (target < 30 %) | **Laptop VirtualBox** (the real hypervisor of the boss; VMSVGA/PIIX/e1000 exactly like his VM) |
| Single repros of a bug seen in VirtualBox (resize, EOI/idle, VBox-only video bugs) | **Laptop VirtualBox** |
| Long, parallel or repeated series (30-boot series, fuzz, stress, 4/8-core crash runs, `tools/*/run.sh` gates with many cases) | **Server qemu** (heavy slots, KVM) |
| Gates in CI / `gates.sh` | **Server qemu** (deterministic, no laptop needed) |
| Fallback when the laptop is offline | **Server qemu** (not VirtualBox-faithful: say so in the report) |

## Prerequisites for a laptop round
- Laptop on, unlocked, online, helper running (`list_devices` shows HOLO-LAPTOP-3). The boss VM window may be open or closed.
- NEVER touch the boss VM `OrientOS`, never use the Dell. Only the VM `OrientOS-Test` (max 4 GB RAM, 2-4 CPUs, VMSVGA, VRAM 128, ps2 mouse, one disk converted from the image).
- ONE test VM at a time: `bash tools/vbox/run.sh lock <name>` before, `unlock` after. Clean up after each run (VM, disks, stage, published folder, image dir).
- A heavy-queue wait of 5-30 min before the build is normal when the server is loaded; queue the build first, prepare the laptop meanwhile.

## Rules of thumb
- Build once per round, test many things in the same boot. Prefer `shotstat` / `idle` / `serial wait` (numbers) over reading screenshots; look at screenshots for layout questions.
- A bug found in VirtualBox gets a roadmap point with the screenshot path; the regression gate for it goes to server qemu where possible.
- Measure host CPU only for the test VM process (pid via COM, not by process name; the boss VM runs at the same time).
