#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsbook/run.sh -- CLICK TEST: Settings -> Konten -> "Sign in with code + address book"
# (K_BKBOOK, r125) -> real clicks in the real window server, result read from the serial line.
#
#   /root/jarvis/bin/heavy bash tools/settingsbook/run.sh [<outdir>]
#
# WHAT IT DOES
#   The design-audit machine (tools/design/audit.sh, uitrace=yes) boots with the REAL /bin/settings.
#   /bin/konto is replaced by a STUB (tools/settingsbook/fakekonto.fi) that speaks the same
#   `konto: <key> = <value>` lines but needs no network and no identity provider:
#     1st call -> state device, code, url, continue token, exit 11
#     2nd call (--continue=, --exchange) -> state ok, `exchange = offline`
#   The drehbuch opens Settings, clicks the tab "Konten" (rect `tabi`), clicks the button (rect
#   `kbook`, reported by settings since r126) twice, takes a picture after each step.
#   settings prints `settings: stand reiter=8 ... konto=[<status line>] book=[<book line>]`.
#
# WHAT IT CHECKS (serial log)
#   1. the Konten page reports the button rect `kbook` (and `kdev`);
#   2. before the click the status line is empty;
#   3. after click 1 the status line shows the code ABCD-EFGH (the page reads `code`) and NOT the
#      sign-in message;
#   4. after click 2 the status line is exactly konto.ui.book.offline (en catalogue): the page read
#      `exchange = offline` and chose the message key by the word (book_key);
#   5. the address-book line says "not connected" (no /bin/socfleitec on this disk);
#   6. counter-probe: the status line after click 2 differs from click 1 and from the other
#      messages (.ok/.refused/.noscope/.failed) -- the comparison is not vacuous;
#   7. no crash lines; pictures were taken.
# WHAT IT DOES NOT CHECK: the real konto/IdP/address-book chain (tools/anbfleitec/*.sh does) and the
# other exchange words (structure: tools/account/run.sh section 15).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build" "$OUT-stub"' EXIT; fi
shift || true
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
YRES=800
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
msg() { grep -a "^$1 = " locale/en/messages | head -1 | sed 's/^[^=]*= //'; }

mkdir -p "$OUT-stub"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if "$FIRNC" -c --profile=app -o "$OUT-stub/fk.o" tools/settingsbook/fakekonto.fi > "$OUT-stub/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld -o "$OUT-stub/konto.elf" "$OUT-stub/fk.o" 2>>"$OUT-stub/cc.log"; then
    strip --strip-all "$OUT-stub/konto.elf" 2>/dev/null
    ok "stub konto builds"
else
    bad "stub konto does not build: $(head -5 "$OUT-stub/cc.log")"; echo "SETTINGSBOOK: $pass passed, $fail failed"; exit 1
fi

DREH="$OUT-drehbuch.txt"
{
  echo "warte 12"
  echo "klick 24,$((YRES-20))"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "klickauf tabi"; echo "warte 3"
  echo "foto 1-konten-page"
  echo "klickauf kbook"; echo "warte 4"
  echo "foto 2-after-click-1"
  echo "klickauf kbook"; echo "warte 4"
  echo "foto 3-after-click-2"
} > "$DREH"
AUDIT_MKFS_EXTRA="/bin/konto=$OUT-stub/konto.elf" \
  bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=300 drehbuch="$DREH" "$@" > "$OUT.audit.log" 2>&1
S="$OUT/serial.txt"

grep -aq 'settings: rect name=kbook ' "$S" && ok "the Konten page reports the button rect kbook" || bad "no rect kbook (tab Konten not open?)"
grep -aq 'settings: rect name=kdev ' "$S" && ok "... and kdev" || bad "no rect kdev"
grep -aq 'klickauf kbook -> ' "$OUT/fahren.log" 2>/dev/null && ok "the runner clicked kbook" || bad "the runner found no kbook"

# the lines of the Konten page, in order
grep -a 'settings: stand reiter=8 .* konto=\[' "$S" | sed 's/.* konto=\[//; s/\] book=\[.*//' > "$OUT.konto"
grep -a 'settings: stand reiter=8 .* konto=\[' "$S" | sed 's/.* book=\[//; s/\]$//' | tr -d '\r' > "$OUT.book"
N=$(wc -l < "$OUT.konto")
[ "$N" -ge 1 ] && ok "the page printed its status lines ($N)" || bad "no 'settings: stand reiter=8 ... konto=[' line"
FIRST=$(head -1 "$OUT.konto" | tr -d '\r')
[ -z "$FIRST" ] && ok "before the click the status line is empty" || bad "status line before the click: '$FIRST'"
C1=$(grep -a 'ABCD-EFGH' "$OUT.konto" | head -1 | tr -d '\r')
[ -n "$C1" ] && ok "click 1: the status shows the code ($C1)" || bad "click 1: no ABCD-EFGH in any status line"
OFF=$(msg konto.ui.book.offline)
[ -n "$OFF" ] || bad "catalogue: konto.ui.book.offline missing"
LAST=$(tail -1 "$OUT.konto" | tr -d '\r')
[ "$LAST" = "$OFF" ] && ok "click 2: the status is konto.ui.book.offline" || bad "click 2: status '$LAST', expected '$OFF'"
# counter-probe: the comparison must tell the messages apart
for k in ok refused noscope failed; do
    M=$(msg konto.ui.book.$k)
    [ -n "$M" ] && [ "$LAST" != "$M" ] && ok "counter-probe: the final status is not konto.ui.book.$k" || bad "counter-probe: equals (or missing) konto.ui.book.$k"
done
[ "$LAST" != "$C1" ] && ok "counter-probe: the status changed between click 1 and click 2" || bad "status did not change"
case "$LAST" in *ABCD-EFGH*) bad "the code is still shown after the final answer";; *) ok "the code is gone after the final answer";; esac
BK=$(tail -1 "$OUT.book")
WANT="$(msg konto.ui.book.state)$(msg konto.ui.book.off)"
[ "$BK" = "$WANT" ] && ok "the address-book line says: $BK" || bad "book line '$BK', expected '$WANT'"
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
ls "$OUT"/*.ppm >/dev/null 2>&1 && ok "pictures taken: $(ls "$OUT"/*.ppm | wc -l)" || bad "no pictures"
echo "SETTINGSBOOK: $pass passed, $fail failed"
[ "$fail" = 0 ]
