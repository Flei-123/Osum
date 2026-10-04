# Publishing a new OTA feed stand (osum/aktuell) -- procedure and acceptance

Live feed: `https://store.fleitec.com/osum/aktuell` (directory `/srv/store/osum`).
There are NO `stable/` or `test/` folders and none are created (owner's decision
03.10.2026); images ship `quelle=https://store.fleitec.com/osum/aktuell` without `kanal=`.

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

    bash tools/usbimg/build.sh with OTA_ROOTS=<certs>/ca.pem OTA_CONF=<conf>   # shipped image, local feed address
    bash tools/ota/feedtest.sh <image-dir> /tmp/ota-feed [work-dir]

`feedtest.sh` installs the image on a disk, then on that disk: version 0 sees the new
feed, `ota einspielen` installs the packages, reboot + `ota bestaetigen`, a second
`ota suchen` says "alles aktuell", rollback (`ota zurueck`) and boot again.

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
