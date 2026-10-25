<!-- SPDX-License-Identifier: GPL-2.0-only -->
# RECOVER.md -- restore a backup onto a blank disk (r60, P-013)

    recover TARGET STORE NAME [--ja] [--name DISK] [--into PATH] [-p<pw>] [-m<pw>]

Run from the live stick. TARGET is the disk to wipe (`/dev/hda`), STORE the backup
directory (on a second medium), NAME the snapshot.

Order, and why:

1. `backup verify` the snapshot first. A damaged backup is refused before the disk is touched (exit 2).
2. Without `--ja` it stops here (dry run, nothing written).
3. `install TARGET --ja` writes GPT, ESP, loader and root (exit 3 on failure).
4. Unlock TARGET, mount partition 2 (the OFS root) at `/recover`, `backup restore` into `/recover<PATH>`
   (default PATH is `/`), sync, unmount, relock (exits 4 / 5 / 6).

Refuses the boot ram device. A disk that already has a partition table needs `--name <disk>` like `install`.
Device key, machine identity and session tokens never travel with a backup (docs/BACKUP-SECRETS.md), so the
recovered system keeps the identity the fresh install created. Secrets only come back with `-m`.

Gate: `heavy bash tools/recover/run.sh` (blank disk, recovery, boot from the disk, hash of a restored binary;
counter-proofs: flipped octet in the pack, dry run, ram device -- the target image stays byte-identical).
