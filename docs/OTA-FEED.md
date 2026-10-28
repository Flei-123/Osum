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

    BOOT_KERNEL_COPY=1 OTA_ROOTS=<certs>/ca.pem OTA_CONF=<conf> PARTTAB=mbr FS_BLOCKS=122880 \
        bash tools/usbimg/build.sh <image-dir>   # shipped image, local feed address (certs: tools/ota/mkcerts.py <dir> ota.test 10.0.2.2)
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
