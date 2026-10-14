# Local PIN (r253, stage 1)

A Windows-Hello-like PIN next to the password. Requirements: `docs/LAPTOP-HW-FEASIBILITY.md` section 2 (L-011).

## What it is
- 4-12 digits, per user. Trivial PINs are refused when set (all one digit, straight runs like `1234`, `9876`).
- **Never replaces the password.** The sign-in screen (`glogin`) and the lock screen (`lock`) take ONE secret field. Text that looks
  like a PIN (4-12 digits) is tried as the PIN first; a miss, a locked/disabled PIN or no PIN falls through to the password check.
  The password therefore always works. A numeric-only password still works: it is checked as a PIN (counts as one PIN try) and then as password.
- Set / change / remove: Settings, page *Accounts*, block *PIN*; or `pinctl set|remove <user> [pin]`.

## Security model
| Item | Choice |
|---|---|
| Device bound | the hashed secret is `HMAC-SHA256(device key, "osum-pin1:" user ":" pin)`; the device key = 32 random octets in `/device/pinkey` (0600, root, `/device` is never backed up). `/etc/pin` copied to another machine verifies nothing. Without the key file the PIN does not verify (gate checks this). |
| KDF | the HMAC output (64 hex) goes through `pw.make_hash` / `pw.check_hash` = the same PBKDF2 `$osum1$` record as passwords (cost from `/etc/login.conf`). |
| Store | `/etc/pin`, root, 0600: `user:$osum1$..:fails:until:seen`. Replaced atomically (new file with final mode, rename, sync). |
| Counter | **persisted before the compare**: `verify()` writes `fails+1` and the delay for that count, syncs, then compares. Only a correct PIN writes `0`. Power loss mid-check keeps the penalty. |
| Back-off | wrong tries 1-4 free; 5: 60 s, 6: 120 s, 7: 240 s, 8: 480 s, 9: 960 s; the 10th wrong try **disables** the PIN. During a delay even the right PIN is refused. |
| Clock | `until` is a wall-clock second; `seen` = latest second ever seen, `now = max(clock, seen)`, so setting the clock back does not shorten a delay. |
| Re-enable | a successful **password** login (`pin.password_ok`) clears counter and delay; setting a new PIN too. |
| Masking | the field is the existing secret field (masked, eye toggle as for the password). |

## Not in stage 1 (open)
- No PIN-only screen mode (digits pad) and no "PIN" hint in the placeholder; the single field takes both.
- Not sealed by a TPM (L-011 TPM part, X7): root on the running device can read the key (same limit as `ksiegel`).
- The wall clock can be set forward by root; a physical attacker with the disk but without the key cannot verify any PIN guess offline
  at all (the key file is required), a root attacker on the running device is out of scope.
- Settings does not ask for the old PIN/password before changing it (same as the password page today).
- Biometric unlock (L-013) builds on this (releases the PIN-equivalent key).

## Tests
`tools/pin/run.sh` (two boots on one disk): format rules, set, right/wrong, 5 wrong -> delay (right PIN refused), delay survives a reboot,
`pwok` clears it, 10 wrong -> disabled, device binding (key removed), no plaintext in `/etc/pin`.
Existing sign-in gates must stay green: `loginui`, `loginscene`, `lockseal`, `lockscene`, `signinlook`, `lockflicker`.
