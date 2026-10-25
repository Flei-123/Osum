#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/screenreader/run.sh -- screen reader gate (P-016), host only, seconds.
#   bash tools/screenreader/run.sh
# 0) kernel-profile compile of fui.speaktext + audio.speech  1) host test tools/screenreader/host.fi
# 2) counter-proofs on a COPY of lib/: silent synthesizer and a leaking name reader must turn the host test red
# 3) /bin/screenreader builds
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
rc=0
FC=vendor/firn/bin/firnc
if FIRNLIB="$PWD/lib" $FC --profile=kernel -c tools/screenreader/kcheck.fi -o "$T/k.o" > "$T/k.build" 2>&1; then
    echo "OK    speaktext + speech compile in profile kernel"
else
    echo "FAIL  kernel-profile compile"; grep -v '^warning' "$T/k.build" | head -20; rc=1
fi
host() {
    FIRNLIB="$1" $FC --profile=app tools/screenreader/host.fi -o "$T/$2" > "$T/$2.build" 2>&1 || { echo "build-failed"; return 2; }
    "$T/$2" > "$T/$2.out"; local r=$?
    echo "$(tail -1 "$T/$2.out")"
    grep '^FAIL' "$T/$2.out" | head -8 | sed 's/^/        /'
    return $r
}
res=$(host "$PWD/lib" real); prc=$?
echo "$res" | head -12
if [ $prc = 0 ]; then echo "OK    host test: $(echo "$res" | head -1)"; else echo "FAIL  host test"; rc=1; fi
mk() { rm -rf "$T/lib.$1"; cp -r lib "$T/lib.$1"; }
mk mute
sed -i 's/let u: u64 = ((v + 65536) as u64) \& 0xFFFF/let u: u64 = 0/' "$T/lib.mute/audio/speech.fi"
cmp -s lib/audio/speech.fi "$T/lib.mute/audio/speech.fi" && { echo "FAIL  counter-proof mute: patch did not apply"; rc=1; }
host "$T/lib.mute" mute > "$T/mute.res" 2>&1; mrc=$?
[ $mrc != 0 ] && echo "OK    counter-proof mute is red ($(head -1 "$T/mute.res"))" || { echo "FAIL  counter-proof mute stayed green"; rc=1; }
mk leak
sed -i '0,/if c == 0 as u8 {/s//if false {/' "$T/lib.leak/fui/speaktext.fi"
cmp -s lib/fui/speaktext.fi "$T/lib.leak/fui/speaktext.fi" && { echo "FAIL  counter-proof leak: patch did not apply"; rc=1; }
host "$T/lib.leak" leak > "$T/leak.res" 2>&1; lrc=$?
[ $lrc != 0 ] && echo "OK    counter-proof leak is red ($(head -1 "$T/leak.res"))" || { echo "FAIL  counter-proof leak stayed green"; rc=1; }
mk flat
sed -i 's/pitch = 125 - decl/pitch = 125/; s/let period: u64 = speechdsp.RATE \/ pitch/let period: u64 = speechdsp.RATE \/ 62/' "$T/lib.flat/audio/speech.fi"
host "$T/lib.flat" flat > "$T/flat.res" 2>&1; frc=$?
[ $frc != 0 ] && echo "OK    counter-proof wrong pitch is red" || { echo "FAIL  counter-proof wrong pitch stayed green"; rc=1; }
if bash tools/sync/build.sh "$T/bin" 0 screenreader > "$T/b.txt" 2>&1 && [ -s "$T/bin/screenreader.elf" ]; then
    echo "OK    /bin/screenreader builds"
else
    echo "FAIL  /bin/screenreader build"; tail -8 "$T/b.txt"; rc=1
fi
[ $rc = 0 ] && echo "SCREENREADER: all green" || echo "SCREENREADER: red"
exit $rc
