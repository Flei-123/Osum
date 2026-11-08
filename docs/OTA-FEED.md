# Publishing a new OTA feed stand (osum/aktuell) -- procedure and acceptance

Live feed: `https://store.fleitec.com/osum/aktuell` (directory `/srv/store/osum`).
There are NO `stable/` or `test/` folders and none are created (owner's decision
03.10.2026); images ship `quelle=https://store.fleitec.com/osum/aktuell` without `kanal=`.

Since 19.10.2026 the same directory also holds `system/dev/` (selfupdate kernel feed, see
`docs/SELFUPDATE.md` section 6). It is additive: `aktuell/` and old images never read it, and
`veroeffentlichen.py` does not touch it. Never run `rsync --delete` against `/srv/store/osum/`.

## 1. Prepare the stand LOCALLY (touches nothing live)

    bash tools/loader/build.sh /tmp/laden-new && bash tools/loader/pakete.sh /tmp/laden-new
    cp -a /srv/store/osum /tmp/ota-feed/osum          # same register => next number is letzte+1
    OSUM_SIGN_PASS=$(cat /root/.secrets/osum-ota-pass.txt) \
      python3 tools/ota/veroeffentlichen.py /tmp/ota-feed/osum \
        --stand /tmp/laden-new/stand --bund /root/.secrets/osum-ota-bund.json \
        --notiz "STAND <date>: 14 Programme von main <commit>"

The signing bundle `/root/.secrets/osum-ota-bund.json` (encrypted, main key gen 0,
`9aae8ec4...`) is the one the images already trust (`/system/schluessel.pub` is the
public half of `/srv/store/osum/aktuell/schluessel.pub`). Its passphrase is kept in
`/root/.secrets/osum-ota-pass.txt` (0600).

## 2. Acceptance in the VM BEFORE publishing

    BOOT_KERNEL_COPY=1 OTA_ROOTS=<certs>/ca.pem OTA_CONF=<conf> PARTTAB=mbr \
        bash tools/usbimg/build.sh <image-dir>   # shipped image, local feed address (conf `source=https://10.0.2.2:18555/osum/aktuell`, `name=ota.test`; do not set FS_BLOCKS, 122880 is too small: `mkfs: the disk is full`; certs: tools/ota/mkcerts.py <dir> ota.test 10.0.2.2)
    bash tools/ota/feedtest.sh <image-dir> /tmp/ota-feed [work-dir]

`BOOT_KERNEL_COPY=1` is mandatory at BUILD time: the test boots with QEMU `-kernel/-initrd` (no boot
medium), so the installer needs `/boot/osum.mb` inside the root (without it: `installer: ERROR 2`, `at=52`).
`feedtest.sh` installs the image on a disk, then on that disk: version 0 sees the new
feed, `ota apply` installs the packages, reboot + `ota confirm`, a second
`ota search` says "up to date", rollback (`ota rollback`) and boot again.

## 3. Publish (only with the owner's yes)

    rsync -a /tmp/ota-feed/osum/ /srv/store/osum/       # adds v/<n>/, pakete/, replaces aktuell/
    curl https://store.fleitec.com/osum/aktuell/VERZEICHNIS   # fassung <n>

Old versions stay available (`v/1..n`), nothing is removed. A published number is
never reused (`register.json`), a bad stand is withdrawn with
`veroeffentlichen.py <dir> --zuruecknehmen <n>`.

## Not in the feed (yet)

The feed carries the 14 packages of `tools/loader/apps.tab`. Programs that only ship in
the image (PDF viewer, installer, WLAN window, store window, taskbar, login) are not
packages yet -- an OTA update does not touch them.

## 4. Publishing the selfupdate kernel feed `system/dev` (recipe, 20.10.2026)

`system/dev` is what a device with `kanal=dev` in `/etc/ota.conf` reads (`ota system search|apply`, see
`docs/SELFUPDATE.md` sections 6-7). Re-publish after every kernel/program change that devices should get
(next: after the W-STALL kernel fix). One script does the whole chain and verifies it:

    # 1. full image of the checkout to publish (the overlay programs come from its <prog>.elf files)
    bash vendor/firn/fetch-firnc.sh
    ODB=1 PARTTAB=mbr FS_BLOCKS=122880 IMAGE_ID=x ODB_TOKEN_FILE=/root/abbilder/odb.token \
        /root/jarvis/bin/heavy bash tools/usbimg/build.sh /root/abbilder/x        # ~9 min (+ queue wait)
    # 2. commit everything, then dry run (temp copy of the feed), then the real publish
    git diff --stat 2ebc2717 HEAD -- kernel lib etc        # which /bin programs changed since the stand the devices run?
    bash tools/ota/feed-dev.sh /root/abbilder/x "<notes>" settings settingsd glogin orientbus host fetch --dry
    bash tools/ota/feed-dev.sh /root/abbilder/x "<notes>" settings settingsd glogin orientbus host fetch

`feed-dev.sh` builds the kernel with `build-kernel.sh --stufe 0` into a dir that holds ONLY `osum.mb`, copies the
named `<prog>.elf` into a flat overlay dir, runs `publish-system.sh ... --count $(git rev-list --count HEAD) --gz
--overlay`, verifies the Ed25519 signature of `VERZEICHNIS` against `system/dev/schluessel.pub` plus every
`sysfile`/`sysgz` hash and size, and checks that `aktuell/ v/ pakete/ register.json` are byte-identical before and
after. The working tree must be clean (the stand names the commit). `count` only grows; devices refuse
`count <= SYSVERSION`.

Absolute targets: files in subdirectories of the overlay dir (`DIR/etc/x`, `DIR/usr/share/..`, `DIR/lib/..`, `DIR/apps/<x>.osp/..`) are
swapped to that absolute path (journalled, restored on a lost trial); `--links FILE` (`<dest> /bin/<name>` per line) makes `<dest>`
a hard link of the new /bin file (`/apps/<x>.osp/start`). Gate: `tools/osupdate/run.sh` section 14. For single programs without a feed
use `jarvisctl swap <src> <dst>` / `swap --undo <dst>` (gate `tools/ctlswap/run.sh`).

Limits to know: the Limine config (5 s menu timeout) and root-owned data files (`mouse.conf`, `power.conf`) change only with a new
full image (`tools/vbox/run.sh build` -> `publish` -> laptop `bossswap.ps1`). A program that imports `wlibc` is
functionally changed by r1277 (`platte_ink`), but overlaying every GUI program does not fit a 60 MiB root.

## 5. HP dev feed: publish and device steps (08.11.2026)

Publish (verified by `feed-dev.sh`: signature, every hash and size, package feed byte-identical, VERZEICHNIS below `VZ_MAX`):

    HP_DEV=1 HP_REF=origin/main HP_BASE=/root/abbilder/hp-stick36-base HEAVY_TIMELIMIT=90 \
        setsid nohup /root/jarvis/bin/heavy bash <worktree>/tools/ota/republish-hp.sh "<notes>" [--dry] > log 2>&1 &

Run `--dry` first (prints programs, `verify OK ... N files`, VERZEICHNIS size), then without it; ~3 min plus queue wait.
The stand name is `count` = `git rev-list --count <HP_REF>` at the moment the script fetches, so a main that moves during
the queue wait publishes a later commit: read the `published:` line, not the commit you started from.

Current stand: 5411 (main 6d3d8e658, includes CURRENT/TRIAL files, English wire keys (prov_own, kbund KOPF writer), ab_boot English serial texts, tscdelta, fb-aus gui-off; 141 overlay programs, 359 hashes, VERZEICHNIS 39865 B).
All packages carry the new meta key `version`, so their hashes differ from earlier stands.

Device steps after a power cycle (the HP runs trial 5373; the guard feed `wlanfirst` is NOT applied):

    /bin/cat /proc/wlan
    /bin/ota system status
    /bin/grep last_boot /proc/watchdog
    /bin/ls /var/crash
    /bin/ota confirm
    /bin/ota system apply bg      (then /bin/reboot, /bin/ota confirm)

Steps in order: 1. remove `wlanfirst` from `/etc/wlan.knobs` (unless the guard feed is applied); 2. `/bin/ota system apply bg`;
3. `/bin/reboot`; 4. confirm: `/bin/ota system status` shows stand 5411, `/bin/cat /proc/wlan` shows the link, then `/bin/ota confirm`.

Before any HP reboot remove `wlanfirst` from `/etc/wlan.knobs` unless the feed that contains the wlanfirst guard (main ed6458c91) has been applied.
Feed 5411 contains the guard. The `apply` is the owner's decision; nothing here touches the device.
